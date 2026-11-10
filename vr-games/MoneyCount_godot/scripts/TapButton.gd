class_name TapButton
extends Control
## 여러 명이 동시에 눌러도 되는 버튼 (터치 다운에 바로 반응)

signal tapped

const FONT := preload("res://Jua.ttf")

var text := ""
var sub := ""
var color := Color("#ffffff")
var text_color := Color("#3b2e2a")
var bill := 0
var font_size := 52
var enabled := true:
	set(e):
		enabled = e
		queue_redraw()
var mark := ""      # "ok" 초록 테두리, "no" 빨강
var _last := 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(r: Rect2, t: String, c: Color, fs := 52, s := "") -> TapButton:
	position = r.position
	size = r.size
	text = t
	color = c
	font_size = fs
	sub = s
	pivot_offset = size / 2
	add_to_group("tap")
	return self

func set_mark(m: String) -> void:
	mark = m
	queue_redraw()

func press() -> bool:
	var now := Time.get_ticks_msec()
	if not enabled or now - _last < 380:
		return false
	_last = now
	pivot_offset = size / 2
	var tw := create_tween()
	scale = Vector2.ONE
	tw.tween_property(self, "scale", Vector2(0.9, 0.9), 0.06)
	tw.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tapped.emit()
	return true

func _box(col: Color, rad: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	return sb

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rad: float = min(size.y * 0.28, 44.0)
	if mark != "":
		var mc := Color("#38c172") if mark == "ok" else Color("#ef5350")
		draw_style_box(_box(mc, rad + 10), r.grow(10))
	if bill > 0:
		var bh: float = min(size.y * 0.86, size.x * 0.86 / BillArt.ASPECT)
		var br := Rect2(size / 2 - Vector2(bh * BillArt.ASPECT, bh) / 2, Vector2(bh * BillArt.ASPECT, bh))
		draw_style_box(_box(Color(1, 1, 1, 0.55), rad), r)
		BillArt.draw_bill(self, br, bill)
		# + 표시
		var pc := Vector2(size.x - size.y * 0.16, size.y * 0.17)
		draw_circle(pc, size.y * 0.13, Color("#ff7a59"))
		var t := size.y * 0.035
		var l := size.y * 0.075
		draw_rect(Rect2(pc - Vector2(l, t), Vector2(l * 2, t * 2)), Color.WHITE)
		draw_rect(Rect2(pc - Vector2(t, l), Vector2(t * 2, l * 2)), Color.WHITE)
		if not enabled:
			draw_style_box(_box(Color(1, 1, 1, 0.55), rad), r)
		return
	var col := color if enabled else color.lerp(Color("#bdbdbd"), 0.7)
	draw_style_box(_box(col.darkened(0.28), rad), Rect2(Vector2(0, 9), size))
	draw_style_box(_box(col, rad), r)
	draw_style_box(_box(Color(1, 1, 1, 0.28), rad * 0.8), Rect2(Vector2(size.x * 0.06, size.y * 0.07), Vector2(size.x * 0.88, size.y * 0.32)))
	var tc := text_color if enabled else Color("#8a8a8a")
	if sub == "":
		var y := size.y / 2 + (FONT.get_ascent(font_size) - FONT.get_descent(font_size)) / 2
		draw_string(FONT, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, tc)
	else:
		var fs2 := int(font_size * 0.5)
		var y1 := size.y * 0.47
		draw_string(FONT, Vector2(0, y1), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, tc)
		draw_string(FONT, Vector2(0, y1 + fs2 * 1.6), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs2, Color(tc, 0.75))
