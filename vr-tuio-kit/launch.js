// 크롬(없으면 엣지)을 모니터마다 키오스크로 띄운다.
//   node launch.js           → config.json 대로 화면 5개 + 조작 모니터에 관제 화면
//   node launch.js identify  → 모든 모니터에 번호 크게 표시 (config "monitor" 번호 찾기용)
//   node launch.js list      → 모니터 목록 출력
//   node launch.js game.html → 화면 5개 모두에 game.html?d=화면id 띄우기 (public 폴더 안 파일)
const { execFileSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const config = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
const BASE = `http://localhost:${config.httpPort}`;

function monitors() {
  const ps = `
Add-Type @"
using System; using System.Runtime.InteropServices;
public class D { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
"@
[D]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
  "{0}|{1}|{2}|{3}|{4}|{5}" -f $_.DeviceName,$_.Bounds.X,$_.Bounds.Y,$_.Bounds.Width,$_.Bounds.Height,$_.Primary }`;
  const out = execFileSync('powershell', ['-NoProfile', '-Command', ps], { encoding: 'utf8' });
  return out.trim().split(/\r?\n/).map((l) => {
    const [dev, x, y, w, h, pri] = l.trim().split('|');
    const n = parseInt((dev.match(/DISPLAY(\d+)/i) || [])[1], 10);
    return { n, dev, x: +x, y: +y, w: +w, h: +h, primary: pri === 'True' };
  }).sort((a, b) => a.n - b.n);
}

function browser() {
  const L = process.env.LOCALAPPDATA || '', P = process.env.ProgramFiles || 'C:\\Program Files', P86 = process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)';
  const c = [
    path.join(P, 'Google\\Chrome\\Application\\chrome.exe'),
    path.join(P86, 'Google\\Chrome\\Application\\chrome.exe'),
    path.join(L, 'Google\\Chrome\\Application\\chrome.exe'),
    path.join(P86, 'Microsoft\\Edge\\Application\\msedge.exe'),
    path.join(P, 'Microsoft\\Edge\\Application\\msedge.exe'),
  ];
  const f = c.find((p) => fs.existsSync(p));
  if (!f) throw new Error('크롬/엣지 못 찾음');
  return f;
}

function open(url, mon, tag, kiosk = true) {
  const dir = path.join(os.tmpdir(), 'vrtuio_' + tag);
  const args = [
    `--user-data-dir=${dir}`, '--no-first-run', '--no-default-browser-check', '--disable-session-crashed-bubble',
    '--disable-features=TranslateUI', '--overscroll-history-navigation=0', '--disable-pinch',
    '--autoplay-policy=no-user-gesture-required',
    `--window-position=${mon.x + 50},${mon.y + 50}`, `--window-size=${Math.min(800, mon.w - 100)},${Math.min(600, mon.h - 100)}`,
  ];
  if (kiosk) args.push('--kiosk');
  args.push(kiosk ? `--app=${url}` : url);
  spawn(browser(), args, { detached: true, stdio: 'ignore' }).unref();
  console.log(`DISPLAY${mon.n} (${mon.x},${mon.y} ${mon.w}x${mon.h}) ← ${url}`);
}

const cmd = process.argv[2];
const mons = monitors();
const byN = (n) => mons.find((m) => m.n === n);

if (cmd === 'list') {
  mons.forEach((m) => console.log(`${m.n}: ${m.dev}  위치 ${m.x},${m.y}  크기 ${m.w}x${m.h}${m.primary ? '  (주 모니터)' : ''}`));
} else if (cmd === 'identify') {
  mons.forEach((m) => open(`${BASE}/identify.html?n=${m.n}&info=${encodeURIComponent(`${m.w}x${m.h} @ ${m.x},${m.y}`)}`, m, 'id' + m.n));
  console.log('각 모니터에 번호 표시함. 아무 키 누르면 닫힘 (안 닫히면 Alt+F4)');
} else {
  const page = cmd || 'display.html';
  for (const d of config.displays) {
    const m = byN(d.monitor);
    if (!m) { console.log(`!! ${d.name}: 모니터 ${d.monitor} 없음`); continue; }
    open(`${BASE}/${page}?d=${d.id}`, m, d.id);
  }
  const op = byN(config.operatorMonitor);
  if (!cmd && op) open(`${BASE}/`, op, 'operator', false);
}
