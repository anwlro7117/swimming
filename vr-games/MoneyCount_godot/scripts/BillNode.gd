class_name BillNode
extends Node2D
## 움직이는 지폐 한 장

var value := 1000
var bsize := Vector2(300, 140)
var glow := 0.0:
	set(g):
		glow = g
		queue_redraw()

func setup(v: int, h: float) -> BillNode:
	value = v
	bsize = Vector2(h * BillArt.ASPECT, h)
	return self

func set_height(h: float) -> void:
	bsize = Vector2(h * BillArt.ASPECT, h)
	queue_redraw()

func _draw() -> void:
	BillArt.draw_bill(self, Rect2(-bsize / 2, bsize), value, true, glow)
