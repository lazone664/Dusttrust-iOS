const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PORT = 8080;
const WWW_DIR = path.resolve(__dirname, 'www');

const mimeTypes = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.wav': 'audio/wav',
  '.mp3': 'audio/mpeg',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf'
};

const server = http.createServer((req, res) => {
  let reqPath = decodeURI(req.url.split('?')[0]);
  if (reqPath === '/' || reqPath === '') reqPath = '/index.html';

  const filePath = path.join(WWW_DIR, reqPath);

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('404 Not Found');
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = mimeTypes[ext] || 'application/octet-stream';

    res.writeHead(200, {
      'Content-Type': contentType,
      'Content-Length': stats.size,
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache'
    });

    const stream = fs.createReadStream(filePath);
    stream.pipe(res);
  });
});

function getLocalIp() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return 'localhost';
}

server.listen(PORT, '0.0.0.0', () => {
  const localIp = getLocalIp();
  console.log('====================================================');
  console.log('✦ SERVEUR DUSTTRUST POUR IPHONE X DÉMARRÉ ! ✦');
  console.log('====================================================');
  console.log('');
  console.log('Sur votre iPhone X (connecté au même Wi-Fi) :');
  console.log(`1. Ouvrez Safari et allez sur : http://${localIp}:${PORT}`);
  console.log('2. Tapez sur le bouton Partager (icône carré avec flèche vers le haut)');
  console.log('3. Sélectionnez "Sur l\'écran d\'accueil"');
  console.log('4. Lancez le jeu : il sera en plein écran avec contrôles tactiles et 500 PV !');
  console.log('');
  console.log('Appuyez sur Ctrl+C pour arrêter le serveur.');
});
