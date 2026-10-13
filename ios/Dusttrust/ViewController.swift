import UIKit
import WebKit
import Network

class LocalWebServer {
    private var listener: NWListener?
    let baseDir: URL
    let port: UInt16 = 8080

    init(baseDir: URL) {
        self.baseDir = baseDir
    }

    var onReady: (() -> Void)?

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("Local web server ready on http://127.0.0.1:\(self?.port ?? 8080)")
                    DispatchQueue.main.async {
                        self?.onReady?()
                    }
                default:
                    break
                }
            }
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: .global(qos: .userInitiated))
        } catch {
            print("Failed to start server: \(error)")
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }
            let reqStr = String(decoding: data, as: UTF8.self)
            self.respond(to: reqStr, connection: connection)
        }
    }

    private func respond(to request: String, connection: NWConnection) {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            connection.cancel()
            return
        }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }

        var path = parts[1]
        if let queryIdx = path.firstIndex(of: "?") {
            path = String(path[..<queryIdx])
        }
        if path == "/" || path.isEmpty {
            path = "/index.html"
        }
        while path.hasPrefix("/") {
            path.removeFirst()
        }

        var fileURL = baseDir.appendingPathComponent(path)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let altURL = Bundle.main.bundleURL.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: altURL.path) {
                fileURL = altURL
            }
        }

        guard let fileData = try? Data(contentsOf: fileURL) else {
            let res = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
            connection.send(content: res.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
            return
        }

        let mime = mimeType(for: fileURL.pathExtension)
        let totalLen = fileData.count

        // Support HTTP Range requests for streaming and decoding audio
        var rangeStart = 0
        var rangeEnd = totalLen - 1
        var isRange = false

        for line in request.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("range:") {
                let rangeVal = line.components(separatedBy: "=").last ?? ""
                let rangeParts = rangeVal.components(separatedBy: "-")
                if let s = Int(rangeParts[0].trimmingCharacters(in: .whitespaces)) {
                    rangeStart = s
                    isRange = true
                }
                if rangeParts.count > 1, let e = Int(rangeParts[1].trimmingCharacters(in: .whitespaces)) {
                    rangeEnd = min(e, totalLen - 1)
                    isRange = true
                }
                break
            }
        }

        if isRange && rangeStart < totalLen {
            let length = (rangeEnd - rangeStart) + 1
            let subData = fileData.subdata(in: rangeStart..<(rangeStart + length))
            let headers = [
                "HTTP/1.1 206 Partial Content",
                "Content-Type: \(mime)",
                "Content-Length: \(subData.count)",
                "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(totalLen)",
                "Accept-Ranges: bytes",
                "Access-Control-Allow-Origin: *",
                "Connection: close"
            ].joined(separator: "\r\n") + "\r\n\r\n"

            var responseData = headers.data(using: .utf8)!
            responseData.append(subData)
            connection.send(content: responseData, completion: .contentProcessed({ _ in connection.cancel() }))
        } else {
            let headers = [
                "HTTP/1.1 200 OK",
                "Content-Type: \(mime)",
                "Content-Length: \(totalLen)",
                "Accept-Ranges: bytes",
                "Access-Control-Allow-Origin: *",
                "Connection: close"
            ].joined(separator: "\r\n") + "\r\n\r\n"

            var responseData = headers.data(using: .utf8)!
            responseData.append(fileData)
            connection.send(content: responseData, completion: .contentProcessed({ _ in connection.cancel() }))
        }
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "ogg": return "audio/ogg"
        case "otf": return "font/otf"
        case "ttf": return "font/ttf"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!
    var server: LocalWebServer?

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        var baseDir = Bundle.main.bundleURL.appendingPathComponent("www")
        if !FileManager.default.fileExists(atPath: baseDir.appendingPathComponent("index.html").path) {
            baseDir = Bundle.main.bundleURL
        }

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        view.addSubview(webView)

        var hasLoaded = false
        let loadApp = { [weak self] in
            guard let self = self, !hasLoaded else { return }
            hasLoaded = true
            if let url = URL(string: "http://127.0.0.1:8080/index.html") {
                print("Loading http://127.0.0.1:8080/index.html...")
                self.webView.load(URLRequest(url: url))
            }
        }

        // Start embedded HTTP server
        server = LocalWebServer(baseDir: baseDir)
        server?.onReady = {
            DispatchQueue.main.async {
                loadApp()
            }
        }
        server?.start()

        // Fallback in case onReady fired before listener or was delayed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            loadApp()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("Provisional navigation failed: \(error.localizedDescription). Retrying in 0.5s...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let url = URL(string: "http://127.0.0.1:8080/index.html") {
                self?.webView.load(URLRequest(url: url))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebView finished loading successfully.")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("WebContent process terminated! Reloading webView...")
        webView.reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.frame = view.bounds
    }
}
