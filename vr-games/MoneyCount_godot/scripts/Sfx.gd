class_name Sfx
extends Node
## 효과음·배경음악

var players := {}
var bgm: AudioStreamPlayer
var muted := false

func _ready() -> void:
	for n in ["tap", "bill", "back", "correct", "wrong", "win", "start"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://sounds/%s.wav" % n)
		p.max_polyphony = 4
		add_child(p)
		players[n] = p
	bgm = AudioStreamPlayer.new()
	bgm.stream = load("res://sounds/bgm.wav")
	bgm.volume_db = -15
	add_child(bgm)
	bgm.finished.connect(func(): if not muted: bgm.play())
	bgm.play()

func play(n: String) -> void:
	if muted or not players.has(n):
		return
	players[n].play()

func toggle_mute() -> void:
	muted = not muted
	if muted:
		bgm.stop()
	else:
		bgm.play()
