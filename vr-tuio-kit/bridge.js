// YTS(TUIO/UDP) -> 브라우저(SSE) 브리지. 외부 패키지 없음. 실행: node bridge.js
const dgram = require('dgram');
const http = require('http');
const fs = require('fs');
const path = require('path');

const CONFIG_PATH = path.join(__dirname, 'config.json');
const PUBLIC = path.join(__dirname, 'public');
let config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));

// ---------- OSC 파서 ----------
function readStr(buf, o) {
  let e = o; while (e < buf.length && buf[e] !== 0) e++;
  const s = buf.toString('ascii', o, e);
  return [s, (e + 4) & ~3];
}
function parseMessage(buf) {
  let [addr, o] = readStr(buf, 0);
  let [tags, o2] = readStr(buf, o); o = o2;
  const args = [];
  for (const t of tags.slice(1)) {
    if (t === 'i') { args.push(buf.readInt32BE(o)); o += 4; }
    else if (t === 'f') { args.push(buf.readFloatBE(o)); o += 4; }
    else if (t === 's') { const [s, n] = readStr(buf, o); args.push(s); o = n; }
    else if (t === 'd') { args.push(buf.readDoubleBE(o)); o += 8; }
    else if (t === 'h') { o += 8; args.push(0); }
  }
  return { addr, args };
}
function parsePacket(buf, out = []) {
  if (buf.toString('ascii', 0, 7) === '#bundle') {
    let o = 16;
    while (o + 4 <= buf.length) {
      const n = buf.readInt32BE(o); o += 4;
      parsePacket(buf.subarray(o, o + n), out); o += n;
    }
  } else out.push(parseMessage(buf));
  return out;
}

// ---------- TUIO 2Dcur 상태 ----------
const cursors = new Map(); // id -> {id,x,y}
let alive = new Set();
const clients = new Set();
let lastPacket = 0, packetCount = 0;

// ---------- 가짜 터치 거르기 ----------
// 고장 난 바닥 센서 등에서 계속 찍히는 점을 게임에 안 보낸다. (관제 화면에는 회색으로 보임)
//  dead : 관제 화면에서 "무시 점"으로 등록한 자리 (config.deadSpots)
//  stuck: 한자리에 config.stuckMs 넘게 그대로 있는 점 (사라질 때까지 무시)
//  out  : 벽 화면 구역 밖 (config.dropOutside 가 true 일 때)
const track = new Map(); // id -> {t0,x0,y0,stuck}
function inRect(c, r) { return c.x >= Math.min(r.x0, r.x1) && c.x <= Math.max(r.x0, r.x1) && c.y >= Math.min(r.y0, r.y1) && c.y <= Math.max(r.y0, r.y1); }
function classify(c, now) {
  let t = track.get(c.id);
  if (!t) { t = { t0: now, x0: c.x, y0: c.y }; track.set(c.id, t); }
  if (Math.hypot(c.x - t.x0, c.y - t.y0) > 0.012 && !t.stuck) { t.t0 = now; t.x0 = c.x; t.y0 = c.y; }
  const stuckMs = config.stuckMs ?? 8000;
  if (stuckMs > 0 && now - t.t0 > stuckMs) t.stuck = true;
  if ((config.deadSpots || []).some((d) => Math.hypot(c.x - d.x, c.y - d.y) < (d.r || 0.02))) return 'dead';
  if (t.stuck) return 'stuck';
  if (config.dropOutside !== false && !(config.displays || []).some((d) => inRect(c, d.tuio))) return 'out';
  return null;
}
function frameJSON() {
  const now = Date.now();
  for (const id of [...track.keys()]) if (!cursors.has(id)) track.delete(id);
  const list = [...cursors.values()].map((c) => { const ign = classify(c, now); return ign ? { ...c, ign } : c; });
  return JSON.stringify({ t: now, c: list });
}
function broadcast() {
  const frame = frameJSON();
  for (const res of clients) res.write(`data: ${frame}\n\n`);
}

function handle(msgs) {
  let changed = false;
  for (const { addr, args } of msgs) {
    if (addr !== '/tuio/2Dcur') continue;
    const cmd = args[0];
    if (cmd === 'alive') {
      alive = new Set(args.slice(1));
      for (const id of [...cursors.keys()]) if (!alive.has(id)) cursors.delete(id);
      changed = true;
    } else if (cmd === 'set') {
      const [, id, x, y] = args;
      cursors.set(id, { id, x: +x.toFixed(4), y: +y.toFixed(4) });
      changed = true;
    }
  }
  if (changed) broadcast();
}

const udp = dgram.createSocket({ type: 'udp4' });
udp.on('message', (buf) => {
  lastPacket = Date.now(); packetCount++;
  try { handle(parsePacket(buf)); } catch (e) { /* 깨진 패킷 무시 */ }
});
function already(what) {
  console.error('\n[멈춤] ' + what + ' 이미 사용 중이다.');
  console.error('  → 브리지가 이미 켜져 있다. 작업표시줄의 다른 "VR TUIO bridge" 창(옛 폴더 것)을 모두 닫고 이 파일을 다시 실행한다.');
  console.error('  → 씽킹플레이 콘텐츠가 켜져 있어도 이렇게 된다. 끄고 다시 실행한다.\n');
  process.exit(1);
}
udp.on('error', (e) => { if (e.code === 'EADDRINUSE') already(`UDP ${config.tuioPort} 포트가`); console.error('UDP 오류:', e.message); });
udp.bind(config.tuioPort, () => console.log(`TUIO 수신: UDP ${config.tuioPort}`));

// ---------- HTTP ----------
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.svg': 'image/svg+xml' };

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/events') {
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive', 'Access-Control-Allow-Origin': '*' });
    res.write(`data: ${frameJSON()}\n\n`);
    clients.add(res);
    req.on('close', () => clients.delete(res));
    return;
  }
  if (url.pathname === '/config' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    return res.end(JSON.stringify(config));
  }
  if (url.pathname === '/config' && req.method === 'POST') {
    let body = '';
    req.on('data', (d) => (body += d));
    req.on('end', () => {
      try {
        config = JSON.parse(body);
        fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
        res.writeHead(200); res.end('ok');
        console.log('config.json 저장됨');
      } catch (e) { res.writeHead(400); res.end(e.message); }
    });
    return;
  }
  if (url.pathname === '/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ lastPacket, packetCount, clients: clients.size }));
  }
  let p = url.pathname === '/' ? '/operator.html' : decodeURIComponent(url.pathname);
  const file = path.join(PUBLIC, path.normalize(p).replace(/^(\.\.[\/\\])+/, ''));
  if (!file.startsWith(PUBLIC)) { res.writeHead(403); return res.end(); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end('not found'); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream' });
    res.end(data);
  });
}).on('error', (e) => { if (e.code === 'EADDRINUSE') already(`웹 ${config.httpPort} 포트가`); throw e; }).listen(config.httpPort, () => console.log(`웹: http://localhost:${config.httpPort}/  (조작 화면)`));

// 고정 점 판정이 바뀌도록 1초마다 다시 보냄
setInterval(() => { if (cursors.size) broadcast(); }, 1000);
// SSE 연결 유지
setInterval(() => { for (const res of clients) res.write(': ping\n\n'); }, 15000);
