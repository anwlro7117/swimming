// 세 벽에 걸친 창 하나로 도는 게임용: TUIO 터치를 진짜 터치(PointerEvent)처럼 페이지에 넣어 준다.
// 게임 코드는 그대로 두고 <script src="/tuio-pointer.js"></script> 한 줄만 넣으면 된다.
// 벽 화면 위치는 config.json 의 displays[].screen {x,y,w,h} (윈도우 화면 픽셀) 를 쓴다.
(function () {
  let config = null, dwell = 0;
  const active = new Map();   // tuio id -> {pid, t0, x0, y0, moved, target, cx, cy}
  const ignored = new Set();
  let nextPid = 1000;

  function origin() {
    const bx = Math.max(0, (outerWidth - innerWidth) / 2);
    return { x: screenX + bx, y: screenY + Math.max(0, outerHeight - innerHeight - bx) };
  }
  // TUIO 좌표 -> 페이지 좌표 (벽 구역 밖이면 null)
  function toClient(x, y) {
    for (const d of config.displays) {
      const r = d.tuio, s = d.screen;
      if (!s || s.w == null) continue;
      const nx = (x - r.x0) / (r.x1 - r.x0), ny = (y - r.y0) / (r.y1 - r.y0);
      if (nx < 0 || nx > 1 || ny < 0 || ny > 1) continue;
      const o = origin();
      return { cx: s.x + nx * s.w - o.x, cy: s.y + ny * s.h - o.y };
    }
    return null;
  }
  function fire(type, st, cx, cy) {
    const target = type === 'pointerdown' ? (document.elementFromPoint(cx, cy) || document.body) : st.target;
    if (type === 'pointerdown') st.target = target;
    const ev = new PointerEvent(type, {
      bubbles: true, cancelable: true, composed: true,
      pointerId: st.pid, pointerType: 'touch', isPrimary: false,
      clientX: cx, clientY: cy, screenX: cx, screenY: cy,
      buttons: type === 'pointerup' ? 0 : 1, button: 0, pressure: type === 'pointerup' ? 0 : 0.5, width: 20, height: 20,
    });
    target.dispatchEvent(ev);
  }
  function frame(list) {
    const now = performance.now(), seen = new Set();
    for (const c of list) {
      const p = toClient(c.x, c.y);
      if (!p) continue;
      seen.add(c.id);
      if (ignored.has(c.id)) continue;
      let st = active.get(c.id);
      if (!st) {
        st = { pid: nextPid++, t0: now, x0: p.cx, y0: p.cy, cx: p.cx, cy: p.cy };
        active.set(c.id, st);
        fire('pointerdown', st, p.cx, p.cy);
        continue;
      }
      if (Math.hypot(p.cx - st.x0, p.cy - st.y0) > 40) st.moved = true;
      if (dwell && !st.moved && now - st.t0 > dwell) {   // 가만히 기대고 있는 손·몸은 버림
        fire('pointercancel', st, st.cx, st.cy); active.delete(c.id); ignored.add(c.id); continue;
      }
      st.cx = p.cx; st.cy = p.cy;
      fire('pointermove', st, p.cx, p.cy);
    }
    for (const [id, st] of active) if (!seen.has(id)) {
      fire('pointerup', st, st.cx, st.cy);
      // 버튼은 짧게 톡 누르면 클릭으로 처리
      if (!st.moved && now - st.t0 < 1200) {
        const el = document.elementFromPoint(st.cx, st.cy);
        const btn = el && el.closest && el.closest('button,a,[onclick],.opt,label,select');
        if (btn) btn.click();
      }
      active.delete(id);
    }
    for (const id of [...ignored]) if (!seen.has(id)) ignored.delete(id);
  }
  function connect() {
    const es = new EventSource('/events');
    es.onmessage = (e) => frame(JSON.parse(e.data).c);
    es.onerror = () => { es.close(); setTimeout(connect, 1000); };
  }
  fetch('/config').then((r) => r.json()).then((c) => {
    config = c; dwell = window.TUIO_DWELL_MS != null ? window.TUIO_DWELL_MS : (c.dwellIgnoreMs || 0);
    if (!c.displays.some((d) => d.screen && d.screen.w)) console.warn('config.json screen.w/h 없음 → TUIO 입력 못 씀');
    connect();
  }).catch(() => console.warn('브리지 없음 — 마우스/터치만 사용'));
})();
