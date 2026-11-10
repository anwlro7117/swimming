class_name BillArt
extends RefCounted
## 놀이돈 지폐 그리기 (실제 지폐 도안은 쓰지 않음)

const FONT := preload("res://Jua.ttf")
const ASPECT := 2.15

static func _box(col: Color, rad: float, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	return sb

static var _tex := {}
static var _loaded := false

## 실제 지폐 사진: exe 옆 bills 폴더(1000.png 등) → 없으면 게임 안 res://bills → 없으면 놀이돈 그림
static func tex(v: int) -> Texture2D:
	if not _loaded:
		_loaded = true
		var dirs := [OS.get_executable_path().get_base_dir() + "/bills/", ProjectSettings.globalize_path("res://bills/")]
		for k in [1000, 5000, 10000, 50000]:
			for d in dirs:
				if _tex.has(k):
					break
				for ext in ["png", "jpg", "jpeg", "webp"]:
					var f: String = d + str(k) + "." + ext
					if FileAccess.file_exists(f):
						var img := Image.load_from_file(f)
						if img and not img.is_empty():
							img.generate_mipmaps()
							_tex[k] = ImageTexture.create_from_image(img)
							break
			if not _tex.has(k) and ResourceLoader.exists("res://bills/%d.png" % k):
				_tex[k] = load("res://bills/%d.png" % k)
	return _tex.get(v)

static func draw_bill(ci: CanvasItem, r: Rect2, v: int, shadow := true, glow := 0.0) -> void:
	var t := tex(v)
	if t:
		_draw_photo(ci, r, t, shadow, glow)
		return
	var c: Array = Data.BILL_COLORS.get(v, Data.BILL_COLORS[1000])
	var h := r.size.y
	if shadow:
		ci.draw_style_box(_box(Color(0, 0, 0, 0.22), h * 0.08), Rect2(r.position + Vector2(h * 0.035, h * 0.06), r.size))
	if glow > 0.0:
		ci.draw_style_box(_box(Color(1, 1, 0.6, glow), h * 0.14), r.grow(h * 0.08))
	ci.draw_style_box(_box(c[0], h * 0.08), r)
	var inner := r.grow(-h * 0.07)
	ci.draw_style_box(_box(c[1], h * 0.05, c[0].lerp(c[1], 0.45), max(1, int(h * 0.016))), inner)
	# 물결 무늬
	for k in 3:
		var pts := PackedVector2Array()
		var yb := inner.position.y + inner.size.y * (0.86 + k * 0.045)
		for i in 31:
			var x := inner.position.x + inner.size.x * 0.04 + inner.size.x * 0.92 * i / 30.0
			pts.append(Vector2(x, yb + sin(i * 0.7 + k * 1.3) * h * 0.018))
		ci.draw_polyline(pts, Color(c[0], 0.35), max(1.0, h * 0.011), true)
	# 왼쪽 동그라미 문양
	var ec := Vector2(inner.position.x + inner.size.x * 0.2, inner.get_center().y - h * 0.03)
	var er := h * 0.27
	ci.draw_circle(ec, er, c[0].lerp(Color.WHITE, 0.2))
	ci.draw_arc(ec, er * 0.84, 0, TAU, 48, c[1], max(1.0, h * 0.016), true)
	var star := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		var rr := er * (0.6 if i % 2 == 0 else 0.27)
		star.append(ec + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(star, c[1])
	# 숫자
	var right := inner.size.x - h * 0.1
	var fs := int(h * (0.36 if v < 10000 else 0.32))
	ci.draw_string(FONT, Vector2(inner.position.x, inner.position.y + inner.size.y * 0.56), str(v),
		HORIZONTAL_ALIGNMENT_RIGHT, right, fs, c[2])
	ci.draw_string(FONT, Vector2(inner.position.x, inner.position.y + inner.size.y * 0.8), Data.KOR_BILL.get(v, ""),
		HORIZONTAL_ALIGNMENT_RIGHT, right, int(h * 0.15), c[2])
	ci.draw_string(FONT, Vector2(inner.position.x + h * 0.07, inner.position.y + h * 0.15), "놀이돈",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.1), Color(c[2], 0.75))

static func _draw_photo(ci: CanvasItem, r: Rect2, t: Texture2D, shadow: bool, glow: float) -> void:
	# 사진 비율 그대로, 높이를 맞추고 가운데 정렬
	var h := r.size.y
	var w: float = min(r.size.x * 1.06, h * t.get_width() / float(t.get_height()))
	var pr := Rect2(r.get_center() - Vector2(w, h) / 2, Vector2(w, h))
	if shadow:
		ci.draw_style_box(_box(Color(0, 0, 0, 0.25), h * 0.04), Rect2(pr.position + Vector2(h * 0.035, h * 0.06), pr.size))
	if glow > 0.0:
		ci.draw_style_box(_box(Color(1, 1, 0.5, glow), h * 0.1), pr.grow(h * 0.08))
	ci.draw_texture_rect(t, pr, false)
