class_name Board
extends Control
## 한 사람(또는 한 팀)의 놀이판. 1인은 화면 전체, 2인은 반쪽씩.

signal finished(board)

const FONT := preload("res://Jua.ttf")
const ASPECT := BillArt.ASPECT
const P_COLORS := [Color("#ffb347"), Color("#ff6b6b"), Color("#4d96ff")]
const P_NAMES := ["", "빨강", "파랑"]

var main
var pid := 0
var level := 0
var mode := "count"
var total_q := 8
var qi := 0
var stars := 0
var busy := false
var done := false
var sc := 1.0
var base_pos := Vector2.ZERO
var P := Rect2()      # 버튼 칸
var S := Rect2()      # 보여주는 칸
var q := {}
var cur_mode := ""
var tries := 0
var token := 0
var nodes: Array = []
var tray: Array = []           # 내가 낸 지폐 BillNode
var tray_rect := Rect2()
var trays: Array = []          # 그릴 계산대 [{r, title}]
var bill_btn := {}             # 금액 -> TapButton
var answer_btns: Array = []
var lbl_top: Label
var lbl_total: Label
var lbl_hint: Label
var item_rect: TextureRect
var last_modes: Array = []

func setup(m, p: int, lv: int, md: String, r: Rect2) -> void:
	main = m
	pid = p
	level = lv
	mode = md
	position = r.position
	base_pos = r.position
	size = r.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc = 1.0 if pid == 0 else 0.8
	var pw := 540.0 if pid == 0 else 360.0
	var mg := 40.0 * sc
	var top := 150.0
	var bottom := 820.0   # 벽 아래 1/4은 터치가 잘 안 잡힘
	if pid == 1:
		P = Rect2(mg, top, pw, bottom - top)
		S = Rect2(mg * 2 + pw, 120, size.x - pw - mg * 3.5, size.y - 150)
	else:
		P = Rect2(size.x - pw - mg, top, pw, bottom - top)
		S = Rect2(mg * (1.5 if pid == 2 else 1.0), 120, size.x - pw - mg * (3.5 if pid == 2 else 3.0), size.y - 150)
	lbl_top = Data.label("", int(44 * sc), Color("#5a3e2b"), 10, Color.WHITE)
	lbl_top.position = Vector2(S.position.x, 66)
	lbl_top.size = Vector2(S.size.x, 60)
	lbl_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl_top)
	next_question()

func L() -> Dictionary:
	return Data.LEVELS[level]

func kinds() -> Array:
	return L().bills

# ---------------- 문제 만들기 ----------------
const LIMITS := [
	[[1000, 2, 6]],
	[[5000, 0, 3], [1000, 0, 5]],
	[[10000, 0, 3], [5000, 0, 2], [1000, 0, 5]],
	[[50000, 0, 2], [10000, 0, 4], [5000, 0, 1], [1000, 0, 4]],
]

func gen_bundle(minn := 2, maxn := 10) -> Array:
	for _a in 80:
		var out := []
		for lim in LIMITS[level]:
			for _i in randi_range(lim[1], lim[2]):
				out.append(lim[0])
		if out.size() >= minn and out.size() <= maxn and Data.sum(out) <= L().max:
			return out
	return [1000, 1000]

func break_one(a: Array) -> Array:
	var b := a.duplicate()
	var big := -1
	for i in b.size():
		if b[i] > 1000 and (big < 0 or randf() < 0.5):
			big = i
	if big < 0:
		return []
	var v: int = b[big]
	b.remove_at(big)
	var parts := []
	match v:
		50000: parts = [10000, 10000, 10000, 10000, 10000] if randf() < 0.5 else [10000, 10000, 10000, 10000, 5000, 5000]
		10000: parts = [5000, 5000] if randf() < 0.6 else [5000, 1000, 1000, 1000, 1000, 1000]
		5000: parts = [1000, 1000, 1000, 1000, 1000]
	b.append_array(parts)
	if b.size() > 11:
		return []
	return b

func make_question(md: String) -> Dictionary:
	var d := {"mode": md}
	match md:
		"count":
			var b := gen_bundle(2, 10)
			var t := Data.sum(b)
			var deltas := []
			for k in kinds():
				deltas.append_array([k, -k])
			deltas.append_array([2000, -2000, 1000, -1000])
			deltas.shuffle()
			var opts := [t]
			for dl in deltas:
				var v: int = t + dl
				if v > 0 and not opts.has(v):
					opts.append(v)
				if opts.size() >= 3:
					break
			opts.shuffle()
			d.bills = b
			d.target = t
			d.opts = opts
			d.answer = opts.find(t)
			d.text = "모두 얼마일까요?"
			d.say = "모두 얼마일까요? 하나씩 세어 봐요." if level == 0 else "모두 얼마일까요?"
		"pay":
			var price := 1000
			match level:
				0: price = randi_range(1, 6) * 1000
				1: price = randi_range(2, 20) * 1000
				2: price = randi_range(3, 50) * 1000
				_: price = randi_range(8, 100) * 1000
			var it := Data.item_for(price)
			d.item = it
			d.target = price
			d.text = "%s %s이에요." % [Data.josa(it.name, "은", "는"), Data.won(price)]
			d.say = d.text + " 돈을 내 볼까요?"
		"change":
			var price := 1000
			var unit := 5000
			match level:
				0, 1:
					unit = 5000
					price = randi_range(1, 4) * 1000
				2:
					unit = 10000
					price = randi_range(1, 19) * 1000
					if price % 10000 == 0:
						price -= 1000
				_:
					unit = 50000 if randf() < 0.55 else 10000
					price = randi_range(6, 95) * 1000
					if price % unit == 0:
						price -= 1000
			var paid: int = int(ceil(price / float(unit))) * unit
			var it := Data.item_for(price)
			d.item = it
			d.price = price
			d.paid = paid
			d.paid_bills = Data.greedy(paid, [unit])
			d.target = paid - price
			d.text = "%s짜리 %s 사고\n%s 냈어요. 거스름돈은?" % [Data.won(price), Data.josa(it.name, "을", "를"), Data.josa(Data.won(paid), "을", "를")]
			d.say = "%s짜리 %s 사고 %s 냈어요. 거스름돈을 주세요." % [Data.won(price), Data.josa(it.name, "을", "를"), Data.josa(Data.won(paid), "을", "를")]
		"compare":
			var a := []
			var b := []
			var eq: bool = L().equal and randf() < 0.25
			for _t in 60:
				if level == 0:
					var na := randi_range(1, 6)
					var nb := randi_range(1, 6)
					if na == nb:
						continue
					a = []
					b = []
					for _i in na: a.append(1000)
					for _i in nb: b.append(1000)
					break
				if eq:
					a = gen_bundle(1, 6)
					b = break_one(a)
					if b.is_empty():
						continue
					break
				a = gen_bundle(1, 7)
				if randf() < 0.4:
					# 장수는 많은데 돈은 적은 함정
					b = []
					var small_kinds := kinds().filter(func(k): return k < a.max())
					if small_kinds.is_empty():
						continue
					while b.size() <= a.size() + 1 and b.size() < 9:
						b.append(small_kinds.pick_random())
				else:
					b = gen_bundle(1, 8)
				if Data.sum(a) != Data.sum(b) and b.size() > 0:
					break
			if randf() < 0.5:
				var tmp := a
				a = b
				b = tmp
			d.a = a
			d.b = b
			var sa := Data.sum(a)
			var sb := Data.sum(b)
			d.answer = 2 if sa == sb else (0 if sa > sb else 1)
			d.text = "어느 쪽 돈이 더 많을까요?"
			d.say = d.text
	return d

# ---------------- 화면 만들기 ----------------
func clear_q() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	tray.clear()
	trays.clear()
	bill_btn.clear()
	answer_btns.clear()
	lbl_total = null
	item_rect = null

func _add(n: Node) -> Node:
	add_child(n)
	nodes.append(n)
	return n

func update_top() -> void:
	var s := "%d / %d 문제   ★ %d" % [min(qi, total_q), total_q, stars]
	if pid > 0:
		s = P_NAMES[pid] + "   " + s
	lbl_top.text = s

func next_question() -> void:
	token += 1
	busy = false
	qi += 1
	if qi > total_q:
		finish()
		return
	clear_q()
	tries = 0
	var md := mode
	if md == "mix":
		var opts: Array = L().modes.duplicate()
		if last_modes.size() > 0 and opts.size() > 1:
			opts.erase(last_modes[-1])
		md = opts.pick_random()
		last_modes.append(md)
	cur_mode = md
	q = make_question(md)
	update_top()
	var ql := Data.label(q.text, int(50 * sc), Color("#3b2e2a"), 12, Color.WHITE)
	ql.position = Vector2(S.position.x, S.position.y + 10)
	ql.size = Vector2(S.size.x, 130 * sc)
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ql.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ql.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add(ql)
	var area := Rect2(S.position.x, S.position.y + 150 * sc, S.size.x, S.size.y - 150 * sc)
	lbl_hint = Data.label("", int(42 * sc), Color("#d9480f"), 10, Color.WHITE)
	lbl_hint.position = Vector2(S.position.x, S.end.y - 66 * sc)
	lbl_hint.size = Vector2(S.size.x, 60 * sc)
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add(lbl_hint)
	area.size.y -= 70 * sc
	match md:
		"count": build_count(area)
		"pay": build_pay(area, false)
		"change": build_pay(area, true)
		"compare": build_compare(area)
	queue_redraw()
	if pid == 0:
		main.say(q.say)

func build_count(area: Rect2) -> void:
	tray_rect = area.grow(-6)
	trays.append({"r": tray_rect, "title": "지갑"})
	show_bills(q.bills, tray_rect.grow(-28 * sc), 150 * sc, true)
	var n: int = q.opts.size()
	var g := 26.0 * sc
	var h: float = min(180.0 * sc, (P.size.y - g * (n - 1)) / n)
	var y0 := P.position.y + (P.size.y - (h * n + g * (n - 1))) / 2
	for i in n:
		var b := TapButton.new().setup(Rect2(P.position.x, y0 + i * (h + g), P.size.x, h), Data.won(q.opts[i]), Color("#fff3c4"), int(68 * sc))
		b.tapped.connect(answer.bind(i))
		_add(b)
		answer_btns.append(b)

func build_compare(area: Rect2) -> void:
	var side := area.size.x > 900
	var g := 24.0 * sc
	var ra: Rect2
	var rb: Rect2
	if side:
		var w := (area.size.x - g) / 2
		ra = Rect2(area.position, Vector2(w, area.size.y))
		rb = Rect2(area.position + Vector2(w + g, 0), Vector2(w, area.size.y))
	else:
		var h := (area.size.y - g) / 2
		ra = Rect2(area.position, Vector2(area.size.x, h))
		rb = Rect2(area.position + Vector2(0, h + g), Vector2(area.size.x, h))
	trays.append({"r": ra, "title": "가"})
	trays.append({"r": rb, "title": "나"})
	q.ra = ra
	q.rb = rb
	var pad := Vector2(70, 30) * sc
	show_bills(q.a, Rect2(ra.position + Vector2(pad.x, pad.y), ra.size - pad * 2), 120 * sc, true)
	show_bills(q.b, Rect2(rb.position + Vector2(pad.x, pad.y), rb.size - pad * 2), 120 * sc, true)
	var labels := ["가", "나"]
	if L().equal:
		labels.append("똑같아요")
	var n := labels.size()
	var gg := 26.0 * sc
	var h: float = min(190.0 * sc, (P.size.y - gg * (n - 1)) / n)
	var y0 := P.position.y + (P.size.y - (h * n + gg * (n - 1))) / 2
	var cols := [Color("#ffd6a5"), Color("#bde0fe"), Color("#e2d4ff")]
	for i in n:
		var b := TapButton.new().setup(Rect2(P.position.x, y0 + i * (h + gg), P.size.x, h), labels[i], cols[i], int((90 if i < 2 else 64) * sc))
		b.tapped.connect(answer.bind(i))
		_add(b)
		answer_btns.append(b)

func build_pay(area: Rect2, is_change: bool) -> void:
	var it: Dictionary = q.item
	var ih := (230.0 if not is_change else 170.0) * sc
	var tex: Texture2D = load("res://items/%s.svg" % it.id)
	item_rect = TextureRect.new()
	item_rect.texture = tex
	item_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_rect.size = Vector2(ih, ih)
	item_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := Data.label(Data.won(q.price if is_change else q.target), int(62 * sc), Color("#5a3e2b"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#ffe066")
	sb.set_corner_radius_all(int(24 * sc))
	sb.border_color = Color("#e0a800")
	sb.set_border_width_all(int(5 * sc))
	sb.content_margin_left = 26 * sc
	sb.content_margin_right = 26 * sc
	sb.content_margin_top = 6 * sc
	sb.content_margin_bottom = 6 * sc
	tag.add_theme_stylebox_override("normal", sb)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tag_w: float = FONT.get_string_size(tag.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(62 * sc)).x + 52 * sc
	var block_w := ih + 24 * sc + tag_w
	var bx := area.position.x + (area.size.x - block_w) / 2
	item_rect.position = Vector2(bx, area.position.y)
	tag.position = Vector2(bx + ih + 24 * sc, area.position.y + ih / 2 - 50 * sc)
	tag.size = Vector2(tag_w, 100 * sc)
	_add(item_rect)
	_add(tag)
	item_rect.pivot_offset = Vector2(ih / 2, ih)
	var y := area.position.y + ih + 16 * sc
	if is_change:
		var row_h := 96.0 * sc
		var pl := Data.label("낸 돈", int(40 * sc), Color("#5a3e2b"), 8, Color.WHITE)
		var paid_w: float = min(area.size.x - 150 * sc, 560 * sc)
		var px := area.position.x + (area.size.x - paid_w - 130 * sc) / 2
		pl.position = Vector2(px, y + row_h / 2 - 28 * sc)
		_add(pl)
		show_bills(q.paid_bills, Rect2(px + 130 * sc, y, paid_w, row_h), 80 * sc, false)
		y += row_h + 14 * sc
	tray_rect = Rect2(area.position.x, y, area.size.x, area.end.y - y)
	trays.append({"r": tray_rect, "title": "거스름돈" if is_change else "계산대"})
	lbl_total = Data.label("", int(42 * sc), Color("#2b5f8a"), 8, Color.WHITE)
	lbl_total.position = Vector2(tray_rect.position.x, tray_rect.end.y - 58 * sc)
	lbl_total.size = Vector2(tray_rect.size.x - 24 * sc, 54 * sc)
	lbl_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_add(lbl_total)
	update_total()
	# 버튼 칸: 지폐 + 빼기 + 다 냈어요
	var ks: Array = kinds()
	var g := 22.0 * sc
	var act_h := 112.0 * sc
	var bill_area := Rect2(P.position, Vector2(P.size.x, P.size.y - act_h * 2 - g * 2))
	var cols := 1 if ks.size() == 1 or pid > 0 else 2
	var rows := int(ceil(ks.size() / float(cols)))
	var cw := (bill_area.size.x - g * (cols - 1)) / cols
	var ch: float = min((bill_area.size.y - g * (rows - 1)) / rows, cw / 1.75)
	var gy := bill_area.position.y + (bill_area.size.y - (ch * rows + g * (rows - 1))) / 2
	for i in ks.size():
		var cx := bill_area.position.x + (i % cols) * (cw + g)
		var cy := gy + (i / cols) * (ch + g)
		var b := TapButton.new().setup(Rect2(cx, cy, cw, ch), "", Color.WHITE)
		b.bill = ks[i]
		b.tapped.connect(add_bill.bind(ks[i]))
		_add(b)
		bill_btn[ks[i]] = b
	var ay := P.end.y - act_h * 2 - g
	var ub := TapButton.new().setup(Rect2(P.position.x, ay, P.size.x, act_h), "↩ 하나 빼기", Color("#d7e3fc"), int(46 * sc))
	ub.tapped.connect(undo)
	_add(ub)
	var okb := TapButton.new().setup(Rect2(P.position.x, ay + act_h + g, P.size.x, act_h), "다 줬어요!" if is_change else "다 냈어요!", Color("#8be0a4"), int(54 * sc))
	okb.tapped.connect(submit)
	_add(okb)

## 지폐 묶음 보여주기 (금액별로 줄을 나눠 세기 쉽게)
func show_bills(vals: Array, r: Rect2, max_h: float, drop: bool) -> Array:
	var bl := []
	for v in vals:
		var bn := BillNode.new().setup(v, max_h)
		bl.append(bn)
		_add(bn)
	var res := layout_bills(vals, r, max_h)
	for i in bl.size():
		var bn: BillNode = bl[i]
		bn.set_height(res.h)
		bn.z_index = res.z[i]
		bn.rotation = randf_range(-0.04, 0.04)
		if drop:
			bn.position = res.pos[i] + Vector2(0, -60)
			bn.modulate.a = 0.0
			var tw := bn.create_tween()
			tw.tween_interval(0.05 * i)
			tw.tween_property(bn, "position", res.pos[i], 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(bn, "modulate:a", 1.0, 0.2)
		else:
			bn.position = res.pos[i]
	return bl

func layout_bills(vals: Array, r: Rect2, max_h: float) -> Dictionary:
	var ks := []
	for v in vals:
		if not ks.has(v):
			ks.append(v)
	ks.sort()
	ks.reverse()
	var rows := []
	for k in ks:
		var idx := []
		for i in vals.size():
			if vals[i] == k:
				idx.append(i)
		while idx.size() > 0:
			rows.append(idx.slice(0, 5))
			idx = idx.slice(5)
	var nr: int = max(1, rows.size())
	var g := 14.0 * sc
	var h: float = min(max_h, (r.size.y - (nr - 1) * g) / nr)
	var maxn := 1
	for row in rows:
		maxn = max(maxn, row.size())
	var bw := h * ASPECT
	if maxn > 1 and (r.size.x - bw) / (maxn - 1) < bw * 0.56:
		bw = r.size.x / (1.0 + 0.56 * (maxn - 1))
		h = bw / ASPECT
	elif bw > r.size.x:
		bw = r.size.x
		h = bw / ASPECT
	bw = h * ASPECT
	var pos := []
	var z := []
	pos.resize(vals.size())
	z.resize(vals.size())
	var total_h := nr * h + (nr - 1) * g
	var y0 := r.position.y + (r.size.y - total_h) / 2 + h / 2
	for ri in rows.size():
		var row: Array = rows[ri]
		var n := row.size()
		var step: float = 0.0 if n == 1 else min(bw + g, (r.size.x - bw) / (n - 1))
		var row_w := bw + (n - 1) * step
		var x0 := r.position.x + (r.size.x - row_w) / 2 + bw / 2
		for j in n:
			pos[row[j]] = Vector2(x0 + j * step, y0 + ri * (h + g))
			z[row[j]] = 50 - j
	return {"pos": pos, "h": h, "z": z}

func relayout_tray(anim := true) -> void:
	var vals := tray.map(func(b): return b.value)
	var res := layout_bills(vals, tray_rect.grow(-30 * sc).grow_side(SIDE_BOTTOM, -40 * sc), 125 * sc)
	for i in tray.size():
		var bn: BillNode = tray[i]
		bn.set_height(res.h)
		bn.z_index = res.z[i]
		if anim:
			var tw := bn.create_tween()
			tw.tween_property(bn, "position", res.pos[i], 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			bn.position = res.pos[i]

func update_total(force_show := false) -> void:
	if lbl_total == null:
		return
	var s := Data.sum(tray.map(func(b): return b.value))
	if L().show_total or force_show:
		lbl_total.text = "모두 " + Data.won(s)
	else:
		lbl_total.text = "%d장" % tray.size() if tray.size() > 0 else ""

# ---------------- 누르기 ----------------
func add_bill(v: int) -> void:
	if busy or done:
		return
	if tray.size() >= 18:
		hint("너무 많아요! 빼 보세요")
		return
	var btn: TapButton = bill_btn[v]
	var bn := BillNode.new().setup(v, 110 * sc)
	bn.position = btn.position + btn.size / 2
	bn.rotation = randf_range(-0.05, 0.05)
	_add(bn)
	tray.append(bn)
	relayout_tray()
	main.sfx.play("bill")
	lbl_hint.text = ""
	update_total()

func undo() -> void:
	if busy or done or tray.is_empty():
		return
	var bn: BillNode = tray.pop_back()
	nodes.erase(bn)
	var btn: TapButton = bill_btn.get(bn.value)
	var tw := bn.create_tween()
	if btn:
		tw.tween_property(bn, "position", btn.position + btn.size / 2, 0.22)
	tw.parallel().tween_property(bn, "modulate:a", 0.0, 0.22)
	tw.tween_callback(bn.queue_free)
	relayout_tray()
	main.sfx.play("back")
	update_total()

func submit() -> void:
	if busy or done:
		return
	if tray.is_empty():
		hint("지폐를 눌러서 돈을 내요")
		return
	var s := Data.sum(tray.map(func(b): return b.value))
	var t: int = q.target
	if s == t:
		update_total(true)
		correct(tray_rect.get_center())
		return
	tries += 1
	var easy: bool = L().easy_hint
	var msg := ""
	if s < t:
		msg = ("%s 더 필요해요" % Data.won(t - s)) if easy else "돈이 모자라요"
	else:
		msg = ("%s 많아요. 빼 보세요" % Data.won(s - t)) if easy else "너무 많아요. 빼 보세요"
	wrong(msg)
	if tries >= 3:
		reveal_pay()

func answer(i: int) -> void:
	if busy or done:
		return
	var b: TapButton = answer_btns[i]
	if i == q.answer:
		b.set_mark("ok")
		var c := tray_rect.get_center() if cur_mode == "count" else S.get_center()
		if cur_mode == "compare":
			show_compare_totals()
		correct(c)
		return
	tries += 1
	b.set_mark("no")
	b.enabled = false
	var limit := 2 if cur_mode == "count" and q.opts.size() > 2 else 1
	if cur_mode == "compare" and answer_btns.size() > 2:
		limit = 2
	if tries >= limit:
		wrong("")
		busy = true
		answer_btns[q.answer].set_mark("ok")
		if cur_mode == "compare":
			show_compare_totals()
			hint("정답은 '%s'!" % ["가", "나", "똑같아요"][q.answer])
		else:
			hint("정답은 %s!" % Data.won(q.target))
		_later(2.8)
	else:
		wrong("다시 세어 볼까요?" if cur_mode == "count" else "다시 골라 볼까요?")

func show_compare_totals() -> void:
	for pair in [[q.ra, Data.sum(q.a)], [q.rb, Data.sum(q.b)]]:
		var r: Rect2 = pair[0]
		var l := Data.label(Data.won(pair[1]), int(54 * sc), Color("#2b5f8a"), 12, Color.WHITE)
		l.position = Vector2(r.position.x, r.end.y - 64 * sc)
		l.size = Vector2(r.size.x - 20 * sc, 60 * sc)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.z_index = 80
		_add(l)

# ---------------- 결과 ----------------
func _later(t: float) -> void:
	var my := token
	get_tree().create_timer(t).timeout.connect(func():
		if is_instance_valid(self) and token == my and not done:
			next_question())

func hint(t: String) -> void:
	lbl_hint.text = t

func correct(at: Vector2) -> void:
	busy = true
	stars += 1
	update_top()
	main.sfx.play("correct")
	main.fx.confetti(global_position + at, 46 if pid == 0 else 30)
	main.fx.pop(global_position + at + Vector2(0, -40), "딩동댕! ★", int(84 * sc))
	hint(["잘했어요!", "맞았어요!", "최고예요!", "정확해요!"].pick_random())
	lbl_hint.label_settings.font_color = Color("#2f9e44")
	if pid == 0:
		main.say(["딩동댕! 잘했어요.", "맞았어요!", "정확해요!"].pick_random())
	for bn in tray:
		var tw: Tween = bn.create_tween()
		tw.tween_property(bn, "glow", 0.85, 0.2)
		tw.tween_property(bn, "glow", 0.0, 0.6)
	if item_rect:
		var p0 := item_rect.position
		var tw2 := item_rect.create_tween()
		for _k in 2:
			tw2.tween_property(item_rect, "position", p0 + Vector2(0, -36 * sc), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw2.tween_property(item_rect, "position", p0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_later(2.0)

func wrong(msg: String) -> void:
	main.sfx.play("wrong")
	if msg != "":
		hint(msg)
		if pid == 0:
			main.say(msg)
	var tw := create_tween()
	for k in [14, -14, 9, -9, 0]:
		tw.tween_property(self, "position", base_pos + Vector2(k, 0), 0.05)

func reveal_pay() -> void:
	busy = true
	for bn in tray:
		nodes.erase(bn)
		var tw: Tween = bn.create_tween()
		tw.tween_property(bn, "modulate:a", 0.0, 0.25)
		tw.tween_callback(bn.queue_free)
	tray.clear()
	var my := token
	get_tree().create_timer(0.35).timeout.connect(func():
		if not is_instance_valid(self) or token != my:
			return
		for v in Data.greedy(q.target, kinds()):
			var bn := BillNode.new().setup(v, 110 * sc)
			bn.position = tray_rect.get_center()
			_add(bn)
			tray.append(bn)
			bn.glow = 0.6
		relayout_tray()
		update_total(true)
		hint("이렇게 내면 돼요!")
		if pid == 0:
			main.say("이렇게 내면 돼요.")
		_later(3.2))

func finish() -> void:
	done = true
	busy = true
	clear_q()
	qi = total_q
	update_top()
	var l := Data.label("다 했어요!\n★ %d" % stars, int(110 * sc), Color("#ff7a59"), 18, Color.WHITE)
	l.position = Vector2(0, 260)
	l.size = Vector2(size.x, 420)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_add(l)
	queue_redraw()
	finished.emit(self)

func skip() -> void:
	if not done:
		next_question()

# ---------------- 그리기 ----------------
func _box(col: Color, rad: float, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	return sb

func _draw() -> void:
	if pid > 0:
		draw_style_box(_box(Color(P_COLORS[pid], 0.9), 22), Rect2(S.position.x + S.size.x / 2 - 120 * sc, 62, 240 * sc, 8))
	if done:
		return
	draw_style_box(_box(Color(1, 1, 1, 0.45), 36), P.grow(18 * sc))
	for t in trays:
		var r: Rect2 = t.r
		draw_style_box(_box(Color("#c98b55"), 30), Rect2(r.position + Vector2(0, 10), r.size))
		draw_style_box(_box(Color("#f6e3c3"), 30, Color("#d9a46c"), int(6 * sc)), r)
		var title: String = t.title
		if title == "가" or title == "나":
			var c := r.position + Vector2(46, 46) * sc
			draw_circle(c, 38 * sc, Color("#ff9f43") if title == "가" else Color("#4d96ff"))
			draw_string(FONT, c + Vector2(-38 * sc, 17 * sc), title, HORIZONTAL_ALIGNMENT_CENTER, 76 * sc, int(50 * sc), Color.WHITE)
		else:
			var tw: float = FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(32 * sc)).x + 36 * sc
			draw_style_box(_box(Color("#d9a46c"), 16), Rect2(r.position + Vector2(24 * sc, -22 * sc), Vector2(tw, 46 * sc)))
			draw_string(FONT, r.position + Vector2(24 * sc, 12 * sc), title, HORIZONTAL_ALIGNMENT_CENTER, tw, int(32 * sc), Color.WHITE)
