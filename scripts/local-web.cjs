// Built Flutter SPA, loopback only. Unknown routes return index for OAuth redirects.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../build/web');
if (!fs.existsSync(path.join(root, 'index.html'))) throw new Error('Build web first: flutter build web --debug');
const types = {'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.css':'text/css','.wasm':'application/wasm','.png':'image/png','.svg':'image/svg+xml','.woff2':'font/woff2','.ico':'image/x-icon'};
http.createServer((req,res) => {
  if (!['GET','HEAD'].includes(req.method)) { res.writeHead(405);res.end();return; }
  let filename;
  try {filename = path.resolve(root, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname));}
  catch {res.writeHead(400);res.end();return;}
  if (filename !== root && !filename.startsWith(root+path.sep)) {res.writeHead(403);res.end();return;}
  if (!fs.existsSync(filename) || !fs.statSync(filename).isFile()) filename = path.join(root,'index.html');
  res.writeHead(200,{'content-type':types[path.extname(filename)]||'application/octet-stream','cache-control':'no-store','x-content-type-options':'nosniff'});
  if(req.method === 'HEAD')res.end();else fs.createReadStream(filename).pipe(res);
}).listen(8080,'127.0.0.1',()=>console.log('LunchSync local web: http://localhost:8080'));
