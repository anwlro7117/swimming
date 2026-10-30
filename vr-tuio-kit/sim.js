// 가짜 TUIO 송신기 — 센서 없이 브리지·게임 테스트용. 실행: node sim.js
// 손가락 2개가 원을 그리며 움직이고, 1개는 가만히 서 있음(머무름 무시 테스트), 1개는 3초마다 톡 찍음.
const dgram = require('dgram');
const config = require('./config.json');
const sock = dgram.createSocket('udp4');

const pad = (b) => Buffer.concat([b, Buffer.alloc(4 - (b.length % 4))]);
const str = (s) => pad(Buffer.from(s, 'ascii'));
function msg(addr, args) {
  const tags = ',' + args.map((a) => (typeof a === 'string' ? 's' : a.f !== undefined ? 'f' : 'i')).join('');
  const parts = [str(addr), str(tags)];
  for (const a of args) {
    if (typeof a === 'string') parts.push(str(a));
    else if (a.f !== undefined) { const b = Buffer.alloc(4); b.writeFloatBE(a.f); parts.push(b); }
    else { const b = Buffer.alloc(4); b.writeInt32BE(a); parts.push(b); }
  }
  return Buffer.concat(parts);
}
function bundle(msgs) {
  const parts = [str('#bundle'), Buffer.from([0, 0, 0, 0, 0, 0, 0, 1])];
  for (const m of msgs) { const n = Buffer.alloc(4); n.writeInt32BE(m.length); parts.push(n, m); }
  return Buffer.concat(parts);
}
const F = (f) => ({ f });

let fseq = 0, t = 0, tapId = 100;
setInterval(() => {
  t += 1 / 30;
  const cur = [
    { id: 1, x: 0.3 + 0.08 * Math.cos(t), y: 0.5 + 0.3 * Math.sin(t) },
    { id: 2, x: 0.7 + 0.08 * Math.cos(-t * 1.3), y: 0.5 + 0.3 * Math.sin(-t * 1.3) },
    { id: 3, x: 0.9, y: 0.8 },
  ];
  const phase = t % 3;
  if (phase < 0.2) cur.push({ id: tapId, x: 0.1, y: 0.3 });
  else if (phase < 0.25) tapId++;
  const msgs = [msg('/tuio/2Dcur', ['alive', ...cur.map((c) => c.id)])];
  for (const c of cur) msgs.push(msg('/tuio/2Dcur', ['set', c.id, F(c.x), F(c.y), F(0), F(0), F(0)]));
  msgs.push(msg('/tuio/2Dcur', ['fseq', ++fseq]));
  sock.send(bundle(msgs), config.tuioPort, '127.0.0.1');
}, 1000 / 30);
console.log(`가짜 TUIO 송신 중 → 127.0.0.1:${config.tuioPort}  (Ctrl+C 종료)`);
