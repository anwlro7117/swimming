# -*- coding: utf-8 -*-
"""
VR실 고속 터치 트래커 (YTS 대신 사용). 카메라 5대를 60~120fps 로 읽어 TUIO 로 보낸다.
  실행: python tracker.py            (11_tracker_start.bat)
  시험: python tracker.py --synth    (카메라 없이 가짜 영상)
  점검: python tracker.py --probe    (카메라별 실제 fps 측정)
YTS 설정 파일은 읽지도 쓰지도 않는다. 설정은 tracker.json 에만 저장.
미리보기 창 키:
  1~5 / Tab  카메라 선택        l f r  선택 카메라 = 좌/정면/우 벽   a d  바닥 왼쪽/오른쪽     n  선택 카메라 끄기(바닥 등)   u  지정 해제
  k  선택 카메라에서 지금 빨간 곳 = 무시 구역 등록 (아무도 안 만질 때)   o  무시 구역 지우기
  c  선택 카메라 터치 보정(벽에 점 표시)     b  배경 다시 찍기(손 떼고)
  t / g  감도 문턱 +/-     ] / [  최소 크기 +/-     m  흑백/검출 화면 전환
  x / y  선택 카메라 좌우/상하 뒤집기     s  저장     q / Esc  종료
"""
import argparse, json, math, os, socket, struct, sys, threading, time, urllib.request

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CFG_PATH = os.path.join(HERE, 'tracker.json')
KIT_PATH = os.path.join(HERE, 'config.json')

DEFAULT = {
    "cap_width": 640, "cap_height": 480,   # 카메라에서 받는 크기 (이 카메라는 640x480 MJPG 가 ~100fps)
    "width": 320, "height": 240,           # 검출용으로 줄인 크기
    "fps": 120, "fourcc": "MJPG",
    "exposure": None,        # None = 카메라 그대로. 숫자(-6, -7)를 넣으면 고정. -6 이면 최대 60fps
    "threshold": 30,         # 배경과 밝기 차이 문턱 (YTS Threshold 와 다른 값)
    "blur": 5,               # 잡티 제거 (홀수)
    "highpass": 0,           # 0=끔. 넓게 번진 빛 제거하려면 15~31
    "amplify": 1.0,
    "min_area": 10, "max_area": 2500,   # 픽셀 면적
    "bg_frames": 30,
    "bg_learn": 0.002,       # 터치 없는 곳 배경 천천히 갱신 (0=끔)
    "track_dist": 45,        # 같은 손가락으로 볼 최대 이동(픽셀/프레임)
    "hold_ms": 60,           # 1프레임만 찍힌 공도 이 시간만큼 유지
    "stable_ms": 0,          # >0 이면 이 시간 이상 보인 점만 보냄 (가짜 깜빡임 거르기)
    "tuio_host": "127.0.0.1", "tuio_port": 3333,
    "grid_u": [0.08, 0.36, 0.64, 0.92],
    "grid_v": [0.08, 0.38, 0.68],
    "cams": [{"index": i, "display": None, "flip_x": False, "flip_y": False} for i in range(5)],
}


def load_cfg():
    cfg = json.loads(json.dumps(DEFAULT))
    if os.path.exists(CFG_PATH):
        with open(CFG_PATH, encoding='utf-8') as f:
            cfg.update(json.load(f))
    return cfg


def save_cfg(cfg):
    tmp = CFG_PATH + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    os.replace(tmp, CFG_PATH)
    print('저장함:', CFG_PATH)


class Kit:
    """config.json(브리지 설정) 의 화면 구역을 2초마다 다시 읽는다."""
    def __init__(self):
        self.displays, self.t, self.port = {}, 0, 3333
        self.load()

    def load(self):
        self.t = time.time()
        try:
            with open(KIT_PATH, encoding='utf-8-sig') as f:
                c = json.load(f)
            self.displays = {d['id']: d for d in c.get('displays', [])}
            self.port = c.get('tuioPort', 3333); self.http = c.get('httpPort', 8080)
        except Exception as e:
            print('config.json 읽기 실패:', e)

    FLOORS = {
        'floorL': {'name': '바닥 왼쪽', 'monitor': 1, 'screen': {'x': 5760, 'y': 0, 'w': 1920, 'h': 1080}},
        'floorR': {'name': '바닥 오른쪽', 'monitor': 2, 'screen': {'x': 7680, 'y': 0, 'w': 1920, 'h': 1080}},
    }

    def ensure(self, did):
        """바닥 화면이 config.json 에 없으면 추가 (브리지 켜져 있으면 브리지 통해 저장)."""
        if did not in self.FLOORS: return
        self.load()
        if did in self.displays: return
        url = f'http://127.0.0.1:{getattr(self, "http", 8080)}/config'
        try:
            with urllib.request.urlopen(url, timeout=2) as r: c = json.loads(r.read().decode('utf-8'))
            via = 'bridge'
        except Exception:
            with open(KIT_PATH, encoding='utf-8-sig') as f: c = json.load(f)
            via = 'file'
        ds = c.setdefault('displays', [])
        x0 = max([0.6] + [d['tuio']['x1'] for d in ds if 'tuio' in d])
        d = {'id': did, **json.loads(json.dumps(self.FLOORS[did])), 'tuio': {'x0': round(x0, 4), 'y0': 0, 'x1': round(x0 + 0.2, 4), 'y1': 1}}
        ds.append(d)
        body = json.dumps(c, ensure_ascii=False, indent=2)
        if via == 'bridge':
            urllib.request.urlopen(urllib.request.Request(url, body.encode('utf-8'), {'Content-Type': 'application/json'}), timeout=2).read()
        else:
            with open(KIT_PATH, 'w', encoding='utf-8') as f: f.write(body)
        print(f'config.json 에 {d["name"]} 추가함 (화면 x={d["screen"]["x"]}). 위치 다르면 config.json "screen" 고칠 것')
        self.load()

    def get(self, did):
        if time.time() - self.t > 2: self.load()
        return self.displays.get(did)


# ---------------- 보정: 카메라 좌표 -> 벽 0~1 좌표 ----------------
class Mapper:
    def __init__(self, src, dst):
        self.src = np.array(src, np.float64); self.dst = np.array(dst, np.float64)
        H, _ = cv2.findHomography(self.src, self.dst, 0)
        if H is None: raise ValueError('보정 계산 실패')
        self.H = H
        self.base = self._h(self.src)
        self.res = self.dst - self.base          # 렌즈 휨 등 남은 오차
        self.err = float(np.mean(np.linalg.norm(self.res, axis=1)))

    def _h(self, p):
        p = np.asarray(p, np.float64).reshape(-1, 1, 2)
        return cv2.perspectiveTransform(p, self.H).reshape(-1, 2)

    def __call__(self, x, y):
        q = self._h([[x, y]])[0]
        d2 = np.sum((self.base - q) ** 2, axis=1)
        w = np.exp(-d2 / (0.3 ** 2))
        q = q + (w[:, None] * self.res).sum(0) / (w.sum() + 0.15)
        return float(q[0]), float(q[1])


# ---------------- 카메라 ----------------
_id_lock = threading.Lock(); _next_id = [1]
def new_id():
    with _id_lock:
        _next_id[0] += 1
        return _next_id[0]


class Synth:
    """가짜 카메라: 천천히 움직이는 손가락 1개 + 가끔 1프레임만 찍히는 빠른 공."""
    def __init__(self, slot, w, h, fps):
        self.slot, self.w, self.h, self.dt = slot, w, h, 1.0 / fps
        self.t0 = time.time(); self.n = 0
        self.rng = np.random.default_rng(slot)

    def read(self):
        nxt = self.t0 + self.n * self.dt
        d = nxt - time.time()
        if d > 0: time.sleep(d)
        self.n += 1
        t = self.n * self.dt
        img = (self.rng.normal(20, 3, (self.h, self.w))).clip(0, 255).astype(np.uint8)
        if t > 1.0:   # 처음 1초는 배경
            cx = self.w * (0.5 + 0.3 * math.cos(t + self.slot)); cy = self.h * (0.4 + 0.2 * math.sin(t))
            cv2.circle(img, (int(cx), int(cy)), 6, 200, -1)
            if self.n % 45 == 0:   # 공: 딱 1프레임
                cv2.circle(img, (int(self.w * 0.2), int(self.h * 0.3)), 7, 230, -1)
        return True, cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)

    def release(self): pass


class Cam(threading.Thread):
    def __init__(self, slot, cc, cfg, synth=False):
        super().__init__(daemon=True)
        self.slot, self.cc, self.cfg, self.synth = slot, cc, cfg, synth
        self.W, self.H = cfg['width'], cfg['height']
        self.cap = None; self.ok = False; self.err = ''
        self.frame = None; self.mask = None
        self.ign = None; self.ign_key = None   # 무시 구역 마스크
        self.bg = None; self.bg_acc = None; self.bg_n = 0
        self.raw = []                 # 이번 프레임 검출 [(x,y,area)]
        self.tracks = {}              # id -> dict
        self.lock = threading.RLock()
        self.fps = 0.0; self._fc = 0; self._ft = time.time()
        self.version = 0
        self.mapper = None
        self.set_calib(cc.get('calib'))
        self.running = True

    def set_calib(self, cal):
        self.mapper = None
        if cal and len(cal.get('src', [])) >= 4:
            try: self.mapper = Mapper(cal['src'], cal['dst'])
            except Exception as e: print(f'카메라 {self.slot+1} 보정값 오류:', e)

    def open(self):
        cfg = self.cfg
        if self.synth:
            self.cap = Synth(self.slot, self.W, self.H, cfg['fps']); self.ok = True; return
        idx = self.cc['index']
        cap = cv2.VideoCapture(idx, cv2.CAP_DSHOW) if os.name == 'nt' else cv2.VideoCapture(idx)
        if not cap.isOpened():
            self.err = '열기 실패 (YTS 켜져 있나?)'; print(f'카메라 {self.slot+1} (번호 {idx}) {self.err}'); return
        fcc = cv2.VideoWriter_fourcc(*cfg['fourcc'])
        cap.set(cv2.CAP_PROP_FOURCC, fcc)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, cfg.get('cap_width', self.W)); cap.set(cv2.CAP_PROP_FRAME_HEIGHT, cfg.get('cap_height', self.H))
        cap.set(cv2.CAP_PROP_FPS, cfg['fps'])
        cap.set(cv2.CAP_PROP_FOURCC, fcc)
        try: cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        except Exception: pass
        if cfg.get('exposure') is not None:
            cap.set(cv2.CAP_PROP_EXPOSURE, cfg['exposure'])
        self.cap = cap; self.ok = True
        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)); h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        print(f'카메라 {self.slot+1} (번호 {idx}) 열림 {w}x{h} 요청 {cfg["fps"]}fps')

    def ignore_mask(self):
        spots = self.cc.get('ignore') or []
        key = json.dumps(spots)
        if key != self.ign_key:
            self.ign_key = key
            if not spots: self.ign = None
            else:
                mk = np.full((self.H, self.W), 255, np.uint8)
                for u, v, r in spots:
                    cv2.circle(mk, (int(u * self.W), int(v * self.H)), max(2, int(r * self.W)), 0, -1)
                self.ign = mk
        return self.ign

    def add_ignore(self):
        """지금 검출된(빨간) 곳을 무시 구역으로 등록."""
        m = self.mask
        if m is None: return 0
        m = cv2.dilate(m, None, iterations=4)
        cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        spots = self.cc.setdefault('ignore', [])
        n = 0
        for ct in cnts:
            x, y, w, h = cv2.boundingRect(ct)
            # 긴 띠는 작은 원 여러 개로 덮는다
            step = max(4, min(w, h))
            r = max(w, h) / 2 if max(w, h) <= 2 * step else step * 0.75
            for cx in np.arange(x + step / 2, x + w + 1, step) if w >= h else [x + w / 2]:
                for cy in np.arange(y + step / 2, y + h + 1, step) if h > w else [y + h / 2]:
                    rr = (min(w, h) / 2 + 3) if max(w, h) > 2 * step else r + 3
                    spots.append([round(float(cx) / self.W, 4), round(float(cy) / self.H, 4), round((max(rr, step * 0.75) + 2) / self.W, 4)])
                    n += 1
        return n

    def reset_bg(self):
        with self.lock: self.bg = None; self.bg_acc = None; self.bg_n = 0

    def run(self):
        self.open()
        while self.running and self.ok:
            ok, img = self.cap.read()
            if not ok or img is None:
                self.err = '영상 끊김'; time.sleep(0.05); continue
            now = time.time()
            g = img if img.ndim == 2 else cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            if g.shape[1] != self.W or g.shape[0] != self.H: g = cv2.resize(g, (self.W, self.H), interpolation=cv2.INTER_AREA)
            if self.cc.get('flip_x') and self.cc.get('flip_y'): g = cv2.flip(g, -1)
            elif self.cc.get('flip_x'): g = cv2.flip(g, 1)
            elif self.cc.get('flip_y'): g = cv2.flip(g, 0)
            self.detect(g, now)
            self._fc += 1
            if now - self._ft >= 1:
                self.fps = self._fc / (now - self._ft); self._fc = 0; self._ft = now
        if self.cap: self.cap.release()

    def detect(self, g, now):
        c = self.cfg
        with self.lock:
            if self.bg is None:
                f = g.astype(np.float32)
                self.bg_acc = f if self.bg_acc is None else self.bg_acc + f
                self.bg_n += 1
                if self.bg_n >= c['bg_frames']:
                    self.bg = self.bg_acc / self.bg_n
                self.frame = g; self.raw = []; self._update_tracks([], now)
                return
            bg8 = cv2.convertScaleAbs(self.bg)
        d = cv2.subtract(g, bg8)
        k = int(c['blur']) | 1
        if k > 1: d = cv2.GaussianBlur(d, (k, k), 0)
        hp = int(c['highpass'])
        if hp > 1: d = cv2.subtract(d, cv2.blur(d, (hp, hp)))
        if c['amplify'] != 1: d = cv2.convertScaleAbs(d, alpha=c['amplify'])
        _, m = cv2.threshold(d, c['threshold'], 255, cv2.THRESH_BINARY)
        ig = self.ignore_mask()
        if ig is not None: m = cv2.bitwise_and(m, ig)
        n, lab, st, cen = cv2.connectedComponentsWithStats(m, connectivity=8)
        raw = []
        for i in range(1, n):
            a = st[i, cv2.CC_STAT_AREA]
            if c['min_area'] <= a <= c['max_area']:
                raw.append((float(cen[i][0]), float(cen[i][1]), int(a)))
        lr = c.get('bg_learn', 0)
        if lr > 0:
            with self.lock:
                if self.bg is not None:
                    cv2.accumulateWeighted(g, self.bg, lr, mask=cv2.bitwise_not(cv2.dilate(m, None, iterations=3)))
        self.frame = g; self.mask = m; self.raw = raw
        self._update_tracks(raw, now)

    def _update_tracks(self, raw, now):
        c = self.cfg; maxd = c['track_dist']; hold = c['hold_ms'] / 1000
        with self.lock:
            free = dict(self.tracks); used = set()
            pairs = []
            for j, (x, y, a) in enumerate(raw):
                for tid, t in free.items():
                    dd = math.hypot(x - t['x'], y - t['y'])
                    if dd <= maxd: pairs.append((dd, j, tid))
            pairs.sort()
            got = set()
            for dd, j, tid in pairs:
                if j in got or tid in used: continue
                got.add(j); used.add(tid)
                t = self.tracks[tid]; t['x'], t['y'] = raw[j][0], raw[j][1]; t['seen'] = now
            for j, (x, y, a) in enumerate(raw):
                if j not in got:
                    self.tracks[new_id()] = {'x': x, 'y': y, 'seen': now, 't0': now}
            for tid in [k for k, t in self.tracks.items() if now - t['seen'] > hold]:
                del self.tracks[tid]
            self.version += 1

    def points(self, kit):
        """보낼 점들: [(id, X, Y)] TUIO 전체 좌표."""
        c = self.cfg; did = self.cc.get('display'); n = len(c['cams'])
        if did == 'off': return []
        out = []; now = time.time(); stable = c.get('stable_ms', 0) / 1000
        with self.lock: tr = [(k, dict(t)) for k, t in self.tracks.items()]
        rect = None
        if self.mapper and did:
            d = kit.get(did)
            if d: rect = d['tuio']
        for tid, t in tr:
            if stable and t['seen'] - t['t0'] < stable: continue
            u, v = t['x'] / self.W, t['y'] / self.H
            if rect:
                u, v = self.mapper(u, v)
                if not (-0.03 <= u <= 1.03 and -0.03 <= v <= 1.03): continue   # 벽 밖(바닥 반사 등)
                X = rect['x0'] + u * (rect['x1'] - rect['x0']); Y = rect['y0'] + v * (rect['y1'] - rect['y0'])
            else:
                X = (self.slot + u) / n; Y = v       # 보정 전: 카메라 순서대로 5칸
            out.append((tid, X, Y))
        return out


# ---------------- TUIO 송신 ----------------
def _s(s):
    b = s.encode('ascii') + b'\0'
    return b + b'\0' * ((4 - len(b) % 4) % 4)

def osc(addr, args):
    tags = ',' + ''.join('s' if isinstance(a, str) else 'f' if isinstance(a, float) else 'i' for a in args)
    out = [_s(addr), _s(tags)]
    for a in args:
        if isinstance(a, str): out.append(_s(a))
        elif isinstance(a, float): out.append(struct.pack('>f', a))
        else: out.append(struct.pack('>i', a))
    return b''.join(out)

def bundle(msgs):
    return _s('#bundle') + struct.pack('>II', 0, 1) + b''.join(struct.pack('>i', len(m)) + m for m in msgs)


class Sender(threading.Thread):
    def __init__(self, cams, cfg, kit):
        super().__init__(daemon=True)
        self.cams, self.cfg, self.kit = cams, cfg, kit
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.fseq = 0; self.running = True; self.paused = False
        self.count = 0; self.sent_ids = set()

    def run(self):
        last_v, last_t = None, 0
        while self.running:
            time.sleep(0.002)
            v = tuple(c.version for c in self.cams)
            now = time.time()
            if v == last_v and now - last_t < 0.1: continue
            last_v, last_t = v, now
            pts = [] if self.paused else [p for c in self.cams for p in c.points(self.kit)]
            self.send(pts)

    def send(self, pts):
        self.fseq += 1
        msgs = [osc('/tuio/2Dcur', ['source', 'vrtracker'])]
        msgs.append(osc('/tuio/2Dcur', ['alive'] + [int(p[0]) for p in pts]))
        for tid, x, y in pts:
            msgs.append(osc('/tuio/2Dcur', ['set', int(tid), float(x), float(y), 0.0, 0.0, 0.0]))
        msgs.append(osc('/tuio/2Dcur', ['fseq', self.fseq]))
        try: self.sock.sendto(bundle(msgs), (self.cfg['tuio_host'], self.cfg.get('tuio_port') or self.kit.port))
        except OSError: pass
        for p in pts:
            if p[0] not in self.sent_ids: self.count += 1
        self.sent_ids = {p[0] for p in pts}


# ---------------- 보정 화면 ----------------
def calibrate(cam, kit, cfg, sender):
    did = cam.cc.get('display')
    d = kit.get(did) if did and did != 'off' else None
    if not d:
        print('먼저 이 카메라가 어느 벽인지 l/f/r 로 지정하세요'); return False
    sc = d['screen']; W, H = sc['w'], sc['h']
    targets = [(u, v) for v in cfg['grid_v'] for u in cfg['grid_u']]
    win = 'VRTRACKER_CALIB'
    cv2.namedWindow(win, cv2.WINDOW_NORMAL)
    cv2.moveWindow(win, sc['x'], sc['y']); cv2.resizeWindow(win, W, H)
    cv2.setWindowProperty(win, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
    sender.paused = True
    src, dst = [], []
    i = 0; state = 'wait'; samples = []; t_on = 0; t_off = time.time()
    print(f'보정 시작: {d.get("name", did)} — 노란 원 가운데를 손가락으로 1초 누르고 떼기. Esc 취소')
    ok = False
    # 시작 전 0.7초: 아무도 안 만질 때 계속 보이는 점(반사광 등) 위치를 기억해 보정에서 뺀다
    static = []; t_s = time.time()
    while time.time() - t_s < 0.7:
        static += [(x, y) for x, y, a in cam.raw]; time.sleep(0.02)
    def real(raw):
        return [r for r in raw if all(math.hypot(r[0] - x, r[1] - y) > 12 for x, y in static)]
    while True:
        img = np.zeros((H, W, 3), np.uint8)
        for j, (u, v) in enumerate(targets):
            p = (int(u * W), int(v * H))
            if j < i: cv2.circle(img, p, 14, (60, 160, 60), -1)
            elif j > i: cv2.circle(img, p, 10, (70, 70, 70), 2)
        if i < len(targets):
            u, v = targets[i]; p = (int(u * W), int(v * H))
            col = (0, 220, 255) if state != 'hold' else (0, 255, 0)
            r = 60 if state != 'hold' else int(60 - 40 * min(1, (time.time() - t_on) / 0.8))
            cv2.circle(img, p, r, col, 6); cv2.circle(img, p, 8, col, -1)
            cv2.line(img, (p[0] - 90, p[1]), (p[0] + 90, p[1]), col, 2); cv2.line(img, (p[0], p[1] - 90), (p[0], p[1] + 90), col, 2)
        seen = len(real(list(cam.raw)))
        cv2.putText(img, f'camera {cam.slot+1} sees: {seen}', (40, 60), cv2.FONT_HERSHEY_SIMPLEX, 1.4, (0, 255, 0) if seen else (90, 90, 255), 3)
        cv2.putText(img, f'{min(i+1, len(targets))} / {len(targets)}   (Esc = cancel)', (40, H - 40), cv2.FONT_HERSHEY_SIMPLEX, 1.4, (200, 200, 200), 3)
        cv2.imshow(win, img)
        k = cv2.waitKey(10) & 0xFF
        if k == 27: break
        if i >= len(targets):
            try:
                cal = {'display': did, 'src': src, 'dst': dst}
                mp = Mapper(src, dst)
                cam.cc['calib'] = cal; cam.set_calib(cal)
                print(f'보정 완료. 평균 오차 {mp.err*100:.1f}% (2% 이하 좋음)')
                ok = True
            except Exception as e:
                print('보정 실패:', e)
            break
        now = time.time()
        raw = real(list(cam.raw))
        if state == 'wait':
            if raw and now - t_off > 0.3:
                state = 'hold'; t_on = now; samples = []
        if state == 'hold':
            if raw:
                b = max(raw, key=lambda r: r[2]); samples.append((b[0] / cam.W, b[1] / cam.H))
                if now - t_on >= 0.8 and len(samples) >= 5:
                    s = np.array(samples[len(samples) // 3:])
                    src.append([float(np.median(s[:, 0])), float(np.median(s[:, 1]))]); dst.append(list(targets[i]))
                    i += 1; state = 'release'
            else:
                state = 'wait'; t_off = now
        elif state == 'release':
            if not raw: state = 'wait'; t_off = now
    cv2.destroyWindow(win)
    sender.paused = False
    return ok


# ---------------- 미리보기 ----------------
def preview_img(cams, sel, show_mask, cfg):
    tiles = []
    for c in cams:
        if c.frame is None:
            t = np.zeros((c.H, c.W, 3), np.uint8)
        else:
            base = c.mask if (show_mask and c.mask is not None) else c.frame
            t = cv2.cvtColor(base, cv2.COLOR_GRAY2BGR)
            if not show_mask and c.mask is not None:
                t[c.mask > 0] = (0, 0, 255)
        with c.lock: tr = list(c.tracks.items())
        for tid, tk in tr:
            cv2.circle(t, (int(tk['x']), int(tk['y'])), 9, (0, 255, 0), 2)
            cv2.putText(t, str(tid % 1000), (int(tk['x']) + 8, int(tk['y']) - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 0), 1)
        did = c.cc.get('display') or '-'
        cal = 'CAL' if c.mapper else 'no-cal'
        st = 'BG...' if c.bg is None and c.ok else (c.err or '')
        cv2.putText(t, f'{c.slot+1} cam#{c.cc["index"]} {did} {cal}', (4, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (255, 255, 0), 1)
        cv2.putText(t, f'{c.fps:.0f}fps {st}', (4, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (255, 255, 0), 1)
        if c.slot == sel: cv2.rectangle(t, (0, 0), (t.shape[1] - 1, t.shape[0] - 1), (0, 255, 255), 3)
        tiles.append(cv2.resize(t, (320, 240)))
    row = np.hstack(tiles)
    bar = np.zeros((44, row.shape[1], 3), np.uint8)
    cv2.putText(bar, f'thr {cfg["threshold"]} (t/g)  min {cfg["min_area"]} ([/])  sel {sel+1} (1-5)  wall l/f/r floor a/d  off n  ignore k/o  calib c  bg b  mask m  flip x/y  save s  quit q',
                (6, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (220, 220, 220), 1)
    return np.vstack([row, bar])


def probe():
    print('카메라별 실제 fps 측정 (YTS 끄고 실행)')
    for idx in range(8):
        cap = cv2.VideoCapture(idx, cv2.CAP_DSHOW) if os.name == 'nt' else cv2.VideoCapture(idx)
        if not cap.isOpened(): continue
        for fcc in ('MJPG', 'YUY2'):
            for (w, h, fps) in ((640, 480, 120), (640, 480, 60), (320, 240, 120)):
                cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*fcc))
                cap.set(cv2.CAP_PROP_FRAME_WIDTH, w); cap.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
                cap.set(cv2.CAP_PROP_FPS, fps); cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*fcc))
                for _ in range(5): cap.read()
                t = time.time(); n = 0
                while time.time() - t < 1.5:
                    if cap.read()[0]: n += 1
                rw = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)); rh = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                print(f'  번호 {idx}  {fcc} {w}x{h}@{fps} 요청 → 실제 {rw}x{rh} {n/1.5:.0f}fps')
        cap.release()
    print('끝')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--synth', action='store_true', help='카메라 없이 가짜 영상으로 시험')
    ap.add_argument('--probe', action='store_true', help='카메라 fps 측정만')
    ap.add_argument('--nogui', action='store_true', help='미리보기 창 없이')
    ap.add_argument('--seconds', type=float, default=0, help='시험용: N초 후 종료')
    a = ap.parse_args()
    if a.probe: probe(); return
    cfg = load_cfg(); kit = Kit()
    cams = [Cam(i, cc, cfg, a.synth) for i, cc in enumerate(cfg['cams'])]
    for c in cams: c.start()
    snd = Sender(cams, cfg, kit); snd.start()
    print(f'TUIO 송신 → {cfg["tuio_host"]}:{cfg["tuio_port"]}   손 떼고 1초 기다리면 배경 찍힘')
    sel, show_mask = 0, False
    t_end = time.time() + a.seconds if a.seconds else None
    t_log = time.time()
    try:
        while True:
            if t_end and time.time() > t_end: break
            if a.nogui:
                time.sleep(0.2)
                if time.time() - t_log > 2:
                    t_log = time.time()
                    print('fps', ' '.join(f'{c.fps:.0f}' for c in cams), '| 지금 점', sum(len(c.tracks) for c in cams), '| 누적 터치', snd.count, flush=True)
                continue
            cv2.imshow('VR Tracker', preview_img(cams, sel, show_mask, cfg))
            k = cv2.waitKey(30) & 0xFF
            if k == 255: continue
            ch = chr(k) if k < 128 else ''
            cur = cams[sel]
            if k in (27,) or ch == 'q': break
            elif k == 9: sel = (sel + 1) % len(cams)
            elif ch.isdigit() and 1 <= int(ch) <= len(cams): sel = int(ch) - 1
            elif ch in 'lfrad':
                did = {'l': 'left', 'f': 'front', 'r': 'right', 'a': 'floorL', 'd': 'floorR'}[ch]
                try: kit.ensure(did)
                except Exception as e: print('바닥 화면 추가 실패:', e)
                if cur.cc.get('display') != did: cur.cc.pop('calib', None); cur.set_calib(None)
                cur.cc['display'] = did; print(f'카메라 {sel+1} = {did} (보정 필요: c)')
            elif ch == 'n': cur.cc['display'] = 'off'; print(f'카메라 {sel+1} 끔')
            elif ch == 'u': cur.cc['display'] = None; cur.cc.pop('calib', None); cur.set_calib(None)
            elif ch == 'c': calibrate(cur, kit, cfg, snd)
            elif ch == 'k':
                print(f'카메라 {sel+1}: 무시 구역 {cur.add_ignore()}개 추가 (s 로 저장)')
            elif ch == 'o':
                cur.cc['ignore'] = []; print(f'카메라 {sel+1}: 무시 구역 지움')
            elif ch == 'b':
                for c in cams: c.reset_bg()
                print('배경 다시 찍는 중 — 손 떼기')
            elif ch == 't': cfg['threshold'] = min(250, cfg['threshold'] + 2)
            elif ch == 'g': cfg['threshold'] = max(2, cfg['threshold'] - 2)
            elif ch == ']': cfg['min_area'] += 2
            elif ch == '[': cfg['min_area'] = max(1, cfg['min_area'] - 2)
            elif ch == 'm': show_mask = not show_mask
            elif ch == 'x': cur.cc['flip_x'] = not cur.cc.get('flip_x'); cur.reset_bg()
            elif ch == 'y': cur.cc['flip_y'] = not cur.cc.get('flip_y'); cur.reset_bg()
            elif ch == 's': save_cfg(cfg)
    except KeyboardInterrupt:
        pass
    snd.running = False; snd.send([])
    for c in cams: c.running = False
    cv2.destroyAllWindows()


if __name__ == '__main__':
    main()
