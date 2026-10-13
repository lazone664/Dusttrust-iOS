import UIKit
import WebKit

class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    let baseDir: URL

    init(baseDir: URL) {
        self.baseDir = baseDir
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "SchemeHandler", code: 400, userInfo: nil))
            return
        }

        var path = url.path
        if path.isEmpty || path == "/" {
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

        if let data = try? Data(contentsOf: fileURL) {
            let mime = mimeType(for: fileURL.pathExtension)
            let headers: [String: String] = [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                "Access-Control-Allow-Headers": "*"
            ]
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // No asynchronous tasks to cancel
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
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!

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

        let schemeHandler = LocalSchemeHandler(baseDir: baseDir)
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "dusttrust")

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        view.addSubview(webView)

        if let gameURL = URL(string: "dusttrust://localhost/index.html") {
            webView.load(URLRequest(url: gameURL))
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.frame = view.bounds
    }
}
