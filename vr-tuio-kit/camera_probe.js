// 센서 카메라가 60프레임을 지원하는지 확인한다. (YTS 를 끄고 실행)
// 필요: 이 폴더에 ffmpeg.exe (https://www.gyan.dev/ffmpeg/builds/ → ffmpeg-release-essentials.zip → bin\ffmpeg.exe)
// 결과: camera_info.txt
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ff = fs.existsSync(path.join(__dirname, 'ffmpeg.exe')) ? path.join(__dirname, 'ffmpeg.exe') : 'ffmpeg';
const run = (args) => { const r = spawnSync(ff, args, { encoding: 'utf8' }); if (r.error) { console.log('ffmpeg.exe 없음 — 이 폴더에 넣고 다시 실행'); process.exit(1); } return (r.stderr || '') + (r.stdout || ''); };

const list = run(['-hide_banner', '-list_devices', 'true', '-f', 'dshow', '-i', 'dummy']);
const names = [];
for (const line of list.split(/\r?\n/)) {
  const m = /"([^"]+)"\s*\(video\)/.exec(line) || (/DirectShow video devices/.test(line) ? null : null);
  if (m) names.push(m[1]);
}
// 옛 ffmpeg 형식 (video 표시 없이 목록만)
if (!names.length) { let inVideo = false; for (const line of list.split(/\r?\n/)) { if (/video devices/i.test(line)) inVideo = true; else if (/audio devices/i.test(line)) inVideo = false; else if (inVideo) { const m = /"([^"]+)"/.exec(line); if (m && !/Alternative name/.test(line)) names.push(m[1]); } } }

let out = `카메라 ${names.length}대\n\n`;
const seen = new Map();
for (const n of names) seen.set(n, (seen.get(n) || 0) + 1);
for (const [n, cnt] of seen) {
  out += `=== ${n}  (${cnt}대)\n`;
  const opt = run(['-hide_banner', '-f', 'dshow', '-list_options', 'true', '-i', `video=${n}`]);
  const modes = new Set();
  for (const line of opt.split(/\r?\n/)) { const m = /s=(\d+x\d+)\s+fps=([\d.]+)(?:\s+max\s+s=(\d+x\d+)\s+fps=([\d.]+))?/.exec(line); if (m) modes.add(`${m[1]} 최대 ${m[4] || m[2]}fps`); }
  out += modes.size ? [...modes].join('\n') + '\n' : opt.split(/\r?\n/).slice(-15).join('\n') + '\n';
  out += '\n';
}
out += '320x240 또는 640x480 에서 60 이상이 있으면 60프레임 가능. 30 까지만 있으면 카메라 한계.\n';
fs.writeFileSync(path.join(__dirname, 'camera_info.txt'), '﻿' + out);
console.log(out);
