extends Control
## 지폐 세기 놀이터 — VR실 정면 벽용

const FONT := preload("res://Jua.ttf")
const CFG_PATH := "user://money_settings.cfg"
const WALLS := ["front", "left", "right"]
const WALL_KO := {"front": "정면", "left": "좌측", "right": "우측"}

var players := 1
var level := 0
var mode := "count"
var boards: Array = []
var layer: Control          # 메뉴·게임 화면이 올라가는 곳
var fx: Fx
var sfx: Sfx
var tuio: Tuio
var cfg := ConfigFile.new()
var screen_idx := -1
var voice := ""
var info_lbl: Label
var info_t := 0.0
var deco: Array = []
var t := 0.0
var auto_test := ""

func _ready() -> void:
	cfg.load(CFG_PATH)
	screen_idx = cfg.get_value("win", "screen", -1)
	sfx = Sfx.new()
	add_child(sfx)
	tuio = Tuio.new()
	tuio.wall = cfg.get_value("win", "wall", "front")
	add_child(tuio)
	tuio.touch.connect(tap)
	layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = Vector2(1920, 1080)
	add_child(layer)
	fx = Fx.new()
	add_child(fx)
	info_lbl = Data.label("", 34, Color("#3b2e2a"), 8, Color.WHITE)
	info_lbl.position = Vector2(60, 990)
	info_lbl.z_index = 300
	add_child(info_lbl)
	var vs := DisplayServer.tts_get_voices_for_language("ko")
	if vs.size() > 0:
		voice = vs[0]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			auto_test = a.substr(7)
	if auto_test == "":
		place_window()
	show_players()
	if auto_test != "":
		run_test.call_deferred()

# ---------------- 창 위치 ----------------
func place_window() -> void:
	var n := DisplayServer.get_screen_count()
	if screen_idx < 0 or screen_idx >= n:
		screen_idx = DisplayServer.get_primary_screen()
		for i in n:   # config.json 기본값: 정면 벽 = x 1920
			if DisplayServer.screen_get_position(i) == Vector2i(1920, 0):
				screen_idx = i
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(screen_idx)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func save_cfg() -> void:
	cfg.set_value("win", "screen", screen_idx)
	cfg.set_value("win", "wall", tuio.wall)
	cfg.save(CFG_PATH)

func info(s: String) -> void:
	info_lbl.text = s
	info_t = 4.0

# ---------------- 입력 ----------------
func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		tap(e.position)
	elif e is InputEventScreenTouch and e.pressed:
		tap(e.position)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:
				show_players()
			KEY_S:
				var n := DisplayServer.get_screen_count()
				screen_idx = (screen_idx + 1) % max(1, n)
				place_window()
				save_cfg()
				info("화면 %d / %d 번" % [screen_idx + 1, n])
			KEY_T:
				tuio.wall = WALLS[(WALLS.find(tuio.wall) + 1) % WALLS.size()]
				tuio.active.clear()
				save_cfg()
				info("터치 받는 벽: " + WALL_KO[tuio.wall])
			KEY_M:
				sfx.toggle_mute()
				info("소리 끔" if sfx.muted else "소리 켬")
			KEY_F:
				var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
			KEY_N:
				for b in boards:
					if is_instance_valid(b):
						b.skip()

func tap(p: Vector2) -> void:
	fx.ripple(p)
	var best: TapButton = null
	for n in get_tree().get_nodes_in_group("tap"):
		var b := n as TapButton
		if b and b.is_visible_in_tree() and not b.is_queued_for_deletion() and b.get_global_rect().has_point(p):
			best = b
	if best and best.press():
		if best.bill == 0:
			sfx.play("tap")

func say(text: String) -> void:
	if voice == "" or players != 1 or sfx.muted:
		return
	DisplayServer.tts_speak(text, voice, 70, 1.05, 1.0, 0, true)

# ---------------- 화면 바꾸기 ----------------
func clear_layer() -> void:
	if voice != "":
		DisplayServer.tts_stop()
	for c in layer.get_children():
		c.queue_free()
	boards.clear()

func _btn(r: Rect2, txt: String, col: String, fs := 64, sub := "") -> TapButton:
	var b := TapButton.new().setup(r, txt, Color(col), fs, sub)
	layer.add_child(b)
	return b

func _title(txt: String, sub := "") -> void:
	var l := Data.label(txt, 104, Color("#ff7a59"), 22, Color.WHITE)
	l.position = Vector2(0, 92)
	l.size = Vector2(1920, 130)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(l)
	if sub != "":
		var s := Data.label(sub, 46, Color("#5a3e2b"), 10, Color.WHITE)
		s.position = Vector2(0, 222)
		s.size = Vector2(1920, 70)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layer.add_child(s)

func _back(to: Callable) -> void:
	var b := _btn(Rect2(40, 100, 230, 100), "← 뒤로", "#e9ecef", 44)
	b.tapped.connect(to)

## 메뉴 버튼은 벽 가운데(터치가 약함)를 피해 왼쪽·오른쪽에 둔다
func _side_rects(n: int, top := 320.0, bottom := 800.0) -> Array:
	var left := int(ceil(n / 2.0))
	var right := n - left
	var out := []
	for col in 2:
		var cnt := left if col == 0 else right
		if cnt == 0:
			continue
		var g := 30.0
		var h: float = min(210.0, (bottom - top - g * (cnt - 1)) / cnt)
		var y0 := top + (bottom - top - (h * cnt + g * (cnt - 1))) / 2
		var x := 150.0 if col == 0 else 1920 - 150.0 - 620.0
		for i in cnt:
			out.append(Rect2(x, y0 + i * (h + g), 620, h))
	return out

func show_players() -> void:
	clear_layer()
	_title("지폐 세기 놀이터", "돈을 세고, 내고, 비교해 봐요!")
	var rs := _side_rects(2, 360, 780)
	var b1 := _btn(rs[0], "혼자 하기", "#ffd166", 80, "1명")
	b1.tapped.connect(func(): players = 1; show_levels())
	var b2 := _btn(rs[1], "둘이 대결", "#ff9aa2", 80, "2명 · 화면 반씩")
	b2.tapped.connect(func(): players = 2; show_levels())
	_spawn_deco()

func show_levels() -> void:
	clear_layer()
	_title("몇 단계로 할까요?", "혼자 하기" if players == 1 else "둘이 대결")
	_back(show_players)
	var rs := _side_rects(4)
	var cols := ["#b9f6ca", "#ffe08a", "#a0d8ff", "#d0bfff"]
	for i in 4:
		var lv: Dictionary = Data.LEVELS[i]
		var b := _btn(rs[i], lv.name, cols[i], 66, lv.sub)
		b.tapped.connect(func(): level = i; show_modes())
	_spawn_deco()

func show_modes() -> void:
	clear_layer()
	_title("무슨 놀이를 할까요?", Data.LEVELS[level].name)
	_back(show_levels)
	var ms: Array = Data.LEVELS[level].modes.duplicate()
	ms.append("mix")
	var rs := _side_rects(ms.size(), 300, 810)
	for i in ms.size():
		var m: Dictionary = Data.MODES[ms[i]]
		var md: String = ms[i]
		var b := _btn(rs[i], m.name, m.color, 62, m.sub)
		b.tapped.connect(func(): mode = md; start_game())
	_spawn_deco()

func start_game() -> void:
	clear_layer()
	sfx.play("start")
	var home := _btn(Rect2(1920 - 150, 20, 120, 84), "⌂", "#ffffff", 54)
	home.tapped.connect(show_players)
	if players == 1:
		var b := Board.new()
		layer.add_child(b)
		b.finished.connect(_on_finished)
		boards.append(b)
		b.setup(self, 0, level, mode, Rect2(0, 0, 1920, 1080))
	else:
		for p in [1, 2]:
			var b := Board.new()
			layer.add_child(b)
			b.finished.connect(_on_finished)
			boards.append(b)
			b.setup(self, p, level, mode, Rect2(0 if p == 1 else 960, 0, 960, 1080))
	layer.move_child(home, -1)

func _on_finished(_b) -> void:
	for b in boards:
		if not b.done:
			return
	get_tree().create_timer(1.6).timeout.connect(show_result)

func show_result() -> void:
	if boards.is_empty():
		return
	var st := boards.map(func(b): return b.stars)
	var total: int = boards[0].total_q
	clear_layer()
	sfx.play("win")
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.93)
	sb.set_corner_radius_all(48)
	sb.border_color = Color("#ffb347")
	sb.set_border_width_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.position = Vector2(560, 150)
	card.size = Vector2(800, 400)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(card)
	var txt := ""
	var big := ""
	if st.size() == 1:
		var s: int = st[0]
		big = "★ %d / %d" % [s, total]
		txt = "최고예요!" if s >= total - 1 else ("참 잘했어요!" if s >= total / 2 else "다음엔 더 잘할 수 있어요!")
		say(txt)
	else:
		big = "빨강 ★%d  :  ★%d 파랑" % [st[0], st[1]]
		txt = "빨강 승리!" if st[0] > st[1] else ("파랑 승리!" if st[1] > st[0] else "비겼어요! 둘 다 최고!")
	var l1 := Data.label(big, 92, Color("#ff7a59"), 14, Color.WHITE)
	l1.position = Vector2(560, 200)
	l1.size = Vector2(800, 140)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(l1)
	var l2 := Data.label(txt, 70, Color("#5a3e2b"))
	l2.position = Vector2(560, 360)
	l2.size = Vector2(800, 120)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(l2)
	fx.confetti(Vector2(960, 300), 90)
	var rs := _side_rects(2, 600, 800)
	_btn(rs[0], "다시 하기", "#8be0a4", 70).tapped.connect(start_game)
	_btn(rs[1], "처음으로", "#ffd166", 70).tapped.connect(show_players)

# ---------------- 배경 ----------------
func _spawn_deco() -> void:
	for d in deco:
		if is_instance_valid(d):
			d.queue_free()
	deco.clear()
	var ks := [1000, 5000, 10000, 50000]
	for i in 7:
		var bn := BillNode.new().setup(ks[i % 4], randf_range(70, 110))
		bn.position = Vector2(randf_range(0, 1920), randf_range(300, 1000))
		bn.rotation = randf_range(-0.6, 0.6)
		bn.modulate.a = 0.35
		bn.set_meta("v", Vector2(randf_range(-30, 30), randf_range(-40, -15)))
		bn.set_meta("w", randf_range(-0.3, 0.3))
		layer.add_child(bn)
		layer.move_child(bn, 0)
		deco.append(bn)

func _process(dt: float) -> void:
	t += dt
	if info_t > 0:
		info_t -= dt
		if info_t <= 0:
			info_lbl.text = ""
	for d in deco:
		if is_instance_valid(d):
			d.position += d.get_meta("v") * dt
			d.rotation += d.get_meta("w") * dt
			if d.position.y < 220:
				d.position = Vector2(randf_range(0, 1920), 1100)
	queue_redraw()

func _draw() -> void:
	# 하늘색 → 크림색
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1920, 0), Vector2(1920, 1080), Vector2(0, 1080)]),
		PackedColorArray([Color("#bfe6ff"), Color("#bfe6ff"), Color("#fff4dc"), Color("#fff4dc")]))
	# 가게 차양
	var sw := 120.0
	for i in 17:
		var c := Color("#ff8a80") if i % 2 == 0 else Color("#fffdf7")
		draw_rect(Rect2(i * sw, 0, sw, 44), c)
		draw_circle(Vector2(i * sw + sw / 2, 44), sw / 2, c)
	# 바닥 계산대 띠
	draw_rect(Rect2(0, 1040, 1920, 40), Color("#e7c9a0"))
	if players == 2 and boards.size() == 2:
		for y in range(130, 1040, 36):
			draw_rect(Rect2(957, y, 6, 18), Color(1, 1, 1, 0.9))
	# 센서 상태 점
	var okc := Color("#2fbf71") if tuio.ok() else Color("#e5484d")
	draw_circle(Vector2(26, 1056), 11, okc)
	draw_string(FONT, Vector2(44, 1067), "%s · %s" % [tuio.how, WALL_KO.get(tuio.wall, "")], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0, 0, 0, 0.45))

# ---------------- 자동 점검 (개발용) ----------------
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % name)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func run_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://shots"))
	await _wait(0.5)
	await _shot("00_menu")
	if auto_test == "tuio":
		await _wait(9.0)
		await _shot("tuio")
		get_tree().quit()
		return
	var parts := auto_test.split(",")
	players = int(parts[0])
	level = int(parts[1])
	mode = parts[2]
	show_levels()
	await _wait(0.3)
	await _shot("01_levels")
	show_modes()
	await _wait(0.3)
	await _shot("02_modes")
	start_game()
	for k in 5:
		await _wait(1.2)
		await _shot("q%d_a" % k)
		for b in boards:
			_auto_play(b, k)
		await _wait(0.6)
		await _shot("q%d_b" % k)
		await _wait(3.4)
	for b in boards:
		while not b.done:
			b.skip()
	await _wait(2.2)
	await _shot("99_result")
	get_tree().quit()

## 정답·오답을 섞어 실제 터치처럼 눌러 본다
func _auto_play(b: Board, k: int) -> void:
	var wrong_first := k % 2 == 1
	match b.cur_mode:
		"count", "compare":
			var i: int = b.q.answer
			if wrong_first:
				i = (i + 1) % b.answer_btns.size()
			var btn: TapButton = b.answer_btns[i]
			tap(btn.get_global_rect().get_center())
		"pay", "change":
			var vals := Data.greedy(b.q.target, b.kinds())
			if wrong_first:
				vals.append(b.kinds()[0])
			for v in vals:
				var btn: TapButton = b.bill_btn[v]
				btn._last = 0
				tap(btn.get_global_rect().get_center())
			await _wait(0.4)
			for n in b.nodes:
				if n is TapButton and (n.text.begins_with("다 ")):
					tap(n.get_global_rect().get_center())
