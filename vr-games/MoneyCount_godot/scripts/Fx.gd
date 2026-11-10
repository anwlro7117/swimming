class_name Fx
extends Node2D
## 색종이, 터치 물결, 글자 튀어나오기

const FONT := preload("res://Jua.ttf")
const COLS := [Color("#ff6b6b"), Color("#ffd93d"), Color("#6bcB77"), Color("#4d96ff"), Color("#c77dff"), Color("#ff9f43")]
var parts: Array = []

func _ready() -> void:
	z_index = 200

func ripple(p: Vector2) -> void:
	parts.append({"k": 0, "p": p, "life": 0.0, "max": 0.45})

func confetti(p: Vector2, n := 40) -> void:
	for i in n:
		var a := randf() * TAU
		var sp := randf_range(320, 900)
		parts.append({"k": 1 if i % 3 else 2, "p": p, "v": Vector2(cos(a), sin(a) - 0.6) * sp,
			"life": 0.0, "max": randf_range(0.9, 1.5), "c": COLS.pick_random(),
			"s": randf_range(10, 20), "r": randf() * TAU, "w": randf_range(-8, 8)})

func pop(p: Vector2, text: String, size := 80) -> void:
	parts.append({"k": 3, "p": p, "life": 0.0, "max": 1.1, "t": text, "s": size})

func _process(dt: float) -> void:
	if parts.is_empty():
		return
	for e in parts:
		e.life += dt
		if e.has("v"):
			e.v.y += 1300 * dt
			e.v *= 0.985
			e.p += e.v * dt
			e.r += e.w * dt
	parts = parts.filter(func(e): return e.life < e.max)
	queue_redraw()

func _draw() -> void:
	for e in parts:
		var k: float = e.life / e.max
		match e.k:
			0:
				draw_arc(e.p, 30 + 70 * k, 0, TAU, 40, Color(1, 1, 1, 0.9 * (1 - k)), 8 * (1 - k) + 2, true)
				draw_arc(e.p, 18 + 40 * k, 0, TAU, 32, Color(1, 0.8, 0.3, 0.8 * (1 - k)), 5, true)
			1:
				var c: Color = e.c
				c.a = 1 - k * k
				draw_set_transform(e.p, e.r)
				draw_rect(Rect2(-e.s / 2, -e.s / 4, e.s, e.s / 2), c)
				draw_set_transform(Vector2.ZERO)
			2:
				var c2: Color = e.c
				c2.a = 1 - k * k
				var pts := PackedVector2Array()
				for i in 10:
					var a: float = e.r + i * PI / 5
					pts.append(e.p + Vector2(cos(a), sin(a)) * (e.s if i % 2 == 0 else e.s * 0.45))
				draw_colored_polygon(pts, c2)
			3:
				var y: float = -90 * k
				var a2: float = 1.0 if k < 0.7 else (1 - k) / 0.3
				var sz: int = e.s
				var w := 900.0
				draw_string_outline(FONT, e.p + Vector2(-w / 2, y), e.t, HORIZONTAL_ALIGNMENT_CENTER, w, sz, 16, Color(1, 1, 1, a2))
				draw_string(FONT, e.p + Vector2(-w / 2, y), e.t, HORIZONTAL_ALIGNMENT_CENTER, w, sz, Color(1, 0.45, 0.2, a2))
