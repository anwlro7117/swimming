// 게임용 TUIO 클라이언트. 사용법:
//   <script src="/tuio-client.js"></script>
//   const t = new TuioTouch({ display: 'front' });   // 화면 id (config.json). 생략하면 URL ?d= 값
//   t.on('down', p => ...);  t.on('move', p => ...);  t.on('up', p => ...);
//   p = { id, x, y (화면 픽셀), nx, ny (0~1), display, age(ms) }
// 오래 머무는 점(서 있는 발 등)은 dwellIgnoreMs 이후 자동 'up' 처리하고 무시한다.
// 마우스 클릭/터치도 같은 이벤트로 들어온다 → 센서 없이 개발 가능.
(function () {
  class TuioTouch {
    constructor(opts = {}) {
      const q = new URLSearchParams(location.search);
      this.displayId = opts.display || q.get('d');
      this.server = opts.server || '';
      this.handlers = { down: [], move: [], up: [], frame: [] };
      this.active = new Map();   // id -> state
      this.ignored = new Set();
      this.config = null;
      this.ready = fetch(this.server + '/config').then(r => r.json()).then(c => {
        this.config = c;
        this.display = c.displays.find(d => d.id === this.displayId) || null;
        this.dwell = opts.dwellIgnoreMs ?? c.dwellIgnoreMs ?? 0;
        this._connect();
        return c;
      });
      if (opts.mouse !== false) this._mouse();
    }
    on(ev, fn) { this.handlers[ev].push(fn); return this; }
    _emit(ev, p) { for (const f of this.handlers[ev]) f(p); }

    // TUIO 전체 좌표 -> 이 화면 0~1 좌표 (화면 밖이면 null)
    map(x, y) {
      if (!this.display) return { nx: x, ny: y };
      const r = this.display.tuio;
      const nx = (x - r.x0) / (r.x1 - r.x0), ny = (y - r.y0) / (r.y1 - r.y0);
      if (nx < 0 || nx > 1 || ny < 0 || ny > 1) return null;
      return { nx, ny };
    }
    _pt(id, nx, ny, st) {
      return { id, nx, ny, x: nx * innerWidth, y: ny * innerHeight, display: this.displayId, age: performance.now() - st.t0 };
    }
    _connect() {
      const es = new EventSource(this.server + '/events');
      es.onmessage = (e) => this._frame(JSON.parse(e.data).c);
      es.onerror = () => { es.close(); setTimeout(() => this._connect(), 1000); };
    }
    _frame(list) {
      const now = performance.now(), seen = new Set();
      for (const c of list) {
        const m = this.map(c.x, c.y);
        if (!m) continue;
        const id = 't' + c.id;
        seen.add(id);
        if (this.ignored.has(id)) continue;
        let st = this.active.get(id);
        if (!st) { st = { t0: now, x: m.nx, y: m.ny }; this.active.set(id, st); this._emit('down', this._pt(id, m.nx, m.ny, st)); continue; }
        // 머무름 판정: 시작점에서 거의 안 움직였는데 오래 있음
        const moved = Math.hypot(m.nx - st.x, m.ny - st.y) > 0.03;
        if (moved) st.moved = true;
        if (this.dwell && !st.moved && now - st.t0 > this.dwell) {
          this.ignored.add(id); this.active.delete(id);
          this._emit('up', { ...this._pt(id, m.nx, m.ny, st), dwell: true }); continue;
        }
        this._emit('move', this._pt(id, m.nx, m.ny, st));
        st.lx = m.nx; st.ly = m.ny;
      }
      for (const [id, st] of this.active) if (id[0] === 't' && !seen.has(id)) {
        this.active.delete(id); this._emit('up', this._pt(id, st.lx ?? st.x, st.ly ?? st.y, st));
      }
      for (const id of [...this.ignored]) if (!seen.has(id)) this.ignored.delete(id);
      this._emit('frame', [...this.active.keys()]);
    }
    _mouse() {
      const st = {};
      const P = (e) => [e.clientX / innerWidth, e.clientY / innerHeight];
      addEventListener('pointerdown', (e) => { const [x, y] = P(e); st[e.pointerId] = { t0: performance.now() }; this._emit('down', this._pt('m' + e.pointerId, x, y, st[e.pointerId])); });
      addEventListener('pointermove', (e) => { if (!st[e.pointerId]) return; const [x, y] = P(e); this._emit('move', this._pt('m' + e.pointerId, x, y, st[e.pointerId])); });
      const up = (e) => { if (!st[e.pointerId]) return; const [x, y] = P(e); this._emit('up', this._pt('m' + e.pointerId, x, y, st[e.pointerId])); delete st[e.pointerId]; };
      addEventListener('pointerup', up); addEventListener('pointercancel', up);
    }
  }
  window.TuioTouch = TuioTouch;
})();
