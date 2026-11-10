class_name Tuio
extends Node
## VR실 센서 입력. 1순위: vr-tuio-kit 브리지(http://localhost:8080/events)
## 브리지가 없으면 UDP 3333 TUIO 를 직접 받는다.

signal touch(pos: Vector2)

const HOST := "127.0.0.1"
const PORT := 8080
const DEFAULT_DISPLAYS := [
	{"id": "left", "tuio": {"x0": 0.0, "y0": 0.0, "x1": 0.2, "y1": 1.0}},
	{"id": "front", "tuio": {"x0": 0.2, "y0": 0.0, "x1": 0.4, "y1": 1.0}},
	{"id": "right", "tuio": {"x0": 0.4, "y0": 0.0, "x1": 0.6, "y1": 1.0}},
]

var wall := "front"
var displays: Array = DEFAULT_DISPLAYS.duplicate(true)
var how := "없음"          # 지금 연결 방식
var last_frame := 0         # 마지막 신호 받은 시각(ms)

var http := HTTPClient.new()
var phase := 0              # 0 접속 시도, 1 config 요청, 2 config 읽기, 3 events 요청, 4 events 읽기, 9 쉬기
var phase_t := 0.0
var body := PackedByteArray()
var buf := ""
var active := {}            # id -> true
var udp: PacketPeerUDP
var udp_cur := {}           # session id -> Vector2
var udp_last := 0

func _ready() -> void:
	_start_connect()

func ok() -> bool:
	return Time.get_ticks_msec() - last_frame < 20000 and how != "없음"

func _start_connect() -> void:
	http.close()
	http = HTTPClient.new()
	var err := http.connect_to_host(HOST, PORT)
	phase = 0 if err == OK else 9
	phase_t = 0.0

func _fail() -> void:
	http.close()
	phase = 9
	phase_t = 0.0
	if udp == null:
		udp = PacketPeerUDP.new()
		if udp.bind(3333) == OK:
			how = "UDP 3333"
		else:
			udp = null
			how = "없음"

func _process(dt: float) -> void:
	phase_t += dt
	_poll_http()
	_poll_udp()

func _poll_http() -> void:
	if phase == 9:
		# 브리지 없음 → 5초 뒤 다시 (UDP 로 신호가 오고 있으면 그대로 둠)
		if phase_t > 5.0 and (udp == null or Time.get_ticks_msec() - udp_last > 5000):
			if udp:
				udp.close()
				udp = null
			_start_connect()
		return
	http.poll()
	var st := http.get_status()
	match phase:
		0:
			if st == HTTPClient.STATUS_CONNECTED:
				http.request(HTTPClient.METHOD_GET, "/config", [])
				phase = 2
				body = PackedByteArray()
			elif st in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_DISCONNECTED] or phase_t > 2.5:
				_fail()
		2:
			if st == HTTPClient.STATUS_BODY:
				body.append_array(http.read_response_body_chunk())
			elif st == HTTPClient.STATUS_CONNECTED and http.has_response():
				var j = JSON.parse_string(body.get_string_from_utf8())
				if j is Dictionary and j.has("displays"):
					displays = j.displays
				http.request(HTTPClient.METHOD_GET, "/events", ["Accept: text/event-stream"])
				phase = 4
				buf = ""
			elif st in [HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_DISCONNECTED]:
				_fail()
		4:
			if st == HTTPClient.STATUS_BODY:
				for _k in 30:
					var chunk := http.read_response_body_chunk()
					if chunk.size() == 0:
						break
					how = "브리지"
					last_frame = Time.get_ticks_msec()
					buf += chunk.get_string_from_utf8()
					http.poll()
					if http.get_status() != HTTPClient.STATUS_BODY:
						break
				_eat_sse()
			elif st != HTTPClient.STATUS_REQUESTING:
				_fail()

func _eat_sse() -> void:
	buf = buf.replace("\r\n", "\n")
	while true:
		var i := buf.find("\n\n")
		if i < 0:
			break
		var block := buf.substr(0, i)
		buf = buf.substr(i + 2)
		for line in block.split("\n"):
			if line.begins_with("data:"):
				var j = JSON.parse_string(line.substr(5).strip_edges())
				if j is Dictionary and j.has("c"):
					_frame(j.c)

func _rect() -> Dictionary:
	for d in displays:
		if d.get("id", "") == wall and d.has("tuio"):
			return d.tuio
	for d in DEFAULT_DISPLAYS:
		if d.id == wall:
			return d.tuio
	return DEFAULT_DISPLAYS[1].tuio

## 점 목록 [{id,x,y,ign?}] → 새로 닿은 점마다 touch 신호
func _frame(list: Array) -> void:
	last_frame = Time.get_ticks_msec()
	var r := _rect()
	var seen := {}
	for c in list:
		if c.has("ign"):
			continue
		var id = c.id
		seen[id] = true
		if active.has(id):
			continue
		active[id] = true
		var nx: float = (float(c.x) - r.x0) / (float(r.x1) - r.x0)
		var ny: float = (float(c.y) - r.y0) / (float(r.y1) - r.y0)
		if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1:
			touch.emit(Vector2(nx * 1920.0, ny * 1080.0))
	for id in active.keys():
		if not seen.has(id):
			active.erase(id)

# ---------- UDP TUIO (브리지 없을 때) ----------
func _poll_udp() -> void:
	if udp == null:
		return
	var got := false
	while udp.get_available_packet_count() > 0:
		var pk := udp.get_packet()
		var msgs := []
		_osc(pk, msgs)
		for m in msgs:
			if m.addr != "/tuio/2Dcur" or m.args.is_empty():
				continue
			var cmd = m.args[0]
			if cmd == "alive":
				var keep := {}
				for k in m.args.slice(1):
					keep[k] = true
				for k in udp_cur.keys():
					if not keep.has(k):
						udp_cur.erase(k)
				got = true
			elif cmd == "set" and m.args.size() >= 4:
				udp_cur[m.args[1]] = Vector2(m.args[2], m.args[3])
				got = true
	if got:
		udp_last = Time.get_ticks_msec()
		how = "UDP 3333"
		var list := []
		for k in udp_cur:
			list.append({"id": k, "x": udp_cur[k].x, "y": udp_cur[k].y})
		_frame(list)

func _osc_str(b: PackedByteArray, i: int) -> Array:
	var e := i
	while e < b.size() and b[e] != 0:
		e += 1
	var s := b.slice(i, e).get_string_from_utf8()
	e += 1
	while e % 4 != 0:
		e += 1
	return [s, e]

func _osc(b: PackedByteArray, out: Array) -> void:
	if b.size() < 8:
		return
	var sp := StreamPeerBuffer.new()
	sp.data_array = b
	sp.big_endian = true
	if b.slice(0, 7).get_string_from_ascii() == "#bundle":
		var i := 16
		while i + 4 <= b.size():
			sp.seek(i)
			var n := sp.get_32()
			i += 4
			if n <= 0 or i + n > b.size():
				break
			_osc(b.slice(i, i + n), out)
			i += n
		return
	var a := _osc_str(b, 0)
	var t := _osc_str(b, a[1])
	var tags: String = t[0]
	var i: int = t[1]
	var args := []
	for ch in tags.substr(1):
		match ch:
			"i":
				sp.seek(i)
				args.append(sp.get_32())
				i += 4
			"f":
				sp.seek(i)
				args.append(sp.get_float())
				i += 4
			"s":
				var r := _osc_str(b, i)
				args.append(r[0])
				i = r[1]
			_:
				pass
	out.append({"addr": a[0], "args": args})
