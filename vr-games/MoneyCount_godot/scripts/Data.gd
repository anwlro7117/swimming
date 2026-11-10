class_name Data
extends RefCounted
## 단계·모드·물건 데이터와 공용 도우미

const FONT := preload("res://Jua.ttf")

# [바탕, 밝은 안쪽, 진한 글자]
const BILL_COLORS := {
	1000: [Color("#5b8fd0"), Color("#dbe9f8"), Color("#234f86")],
	5000: [Color("#e57f4f"), Color("#fde3d2"), Color("#9c3f17")],
	10000: [Color("#56a861"), Color("#dcf0da"), Color("#24632d")],
	50000: [Color("#d9a51f"), Color("#fcf0c6"), Color("#87600a")],
}

const LEVELS := [
	{"name": "1단계 새싹", "sub": "유치부 · 천 원만", "bills": [1000], "max": 6000,
	 "show_total": true, "easy_hint": true, "equal": false,
	 "modes": ["count", "pay", "compare"]},
	{"name": "2단계 열매", "sub": "유치부~1학년 · 오천 원까지", "bills": [1000, 5000], "max": 20000,
	 "show_total": true, "easy_hint": true, "equal": false,
	 "modes": ["count", "pay", "compare", "change"]},
	{"name": "3단계 나무", "sub": "1~3학년 · 만 원까지", "bills": [1000, 5000, 10000], "max": 50000,
	 "show_total": false, "easy_hint": false, "equal": true,
	 "modes": ["count", "pay", "compare", "change"]},
	{"name": "4단계 숲", "sub": "3학년 이상 · 오만 원까지", "bills": [1000, 5000, 10000, 50000], "max": 150000,
	 "show_total": false, "easy_hint": false, "equal": true,
	 "modes": ["count", "pay", "compare", "change"]},
]

const MODES := {
	"count": {"name": "얼마일까?", "sub": "지폐 세기", "color": "#ffd166"},
	"pay": {"name": "값 치르기", "sub": "가격만큼 돈 내기", "color": "#7fd1ae"},
	"compare": {"name": "누가 더 많을까?", "sub": "금액 비교하기", "color": "#9ec5ff"},
	"change": {"name": "거스름돈 주기", "sub": "남은 돈 계산", "color": "#f4a6c8"},
	"mix": {"name": "골고루 섞어서", "sub": "모든 놀이", "color": "#c9b6ff"},
}

const ITEMS := [
	{"id": "apple", "name": "사과", "min": 1000, "max": 4000},
	{"id": "banana", "name": "바나나", "min": 2000, "max": 6000},
	{"id": "milk", "name": "우유", "min": 1000, "max": 4000},
	{"id": "pencil", "name": "연필", "min": 1000, "max": 3000},
	{"id": "icecream", "name": "아이스크림", "min": 1000, "max": 5000},
	{"id": "bread", "name": "빵", "min": 2000, "max": 9000},
	{"id": "ball", "name": "공", "min": 5000, "max": 20000},
	{"id": "umbrella", "name": "우산", "min": 6000, "max": 22000},
	{"id": "book", "name": "동화책", "min": 8000, "max": 28000},
	{"id": "car", "name": "장난감 자동차", "min": 10000, "max": 45000},
	{"id": "cake", "name": "케이크", "min": 15000, "max": 45000},
	{"id": "bear", "name": "곰인형", "min": 15000, "max": 70000},
	{"id": "shoes", "name": "운동화", "min": 30000, "max": 99000},
	{"id": "bike", "name": "자전거", "min": 60000, "max": 150000},
]

const KOR_BILL := {1000: "천 원", 5000: "오천 원", 10000: "만 원", 50000: "오만 원"}

static func won(v: int) -> String:
	var s := str(v)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out + "원"

static func has_batchim(word: String) -> bool:
	if word.is_empty():
		return false
	var code := word.unicode_at(word.length() - 1)
	if code < 0xAC00 or code > 0xD7A3:
		return false
	return (code - 0xAC00) % 28 != 0

static func josa(word: String, a: String, b: String) -> String:
	return word + (a if has_batchim(word) else b)

static func sum(bills: Array) -> int:
	var s := 0
	for b in bills:
		s += int(b)
	return s

## 가장 적은 장수로 나누기
static func greedy(v: int, kinds: Array) -> Array:
	var ks := kinds.duplicate()
	ks.sort()
	ks.reverse()
	var out := []
	for k in ks:
		while v >= k:
			out.append(k)
			v -= k
	return out

static func item_for(price: int) -> Dictionary:
	var fit := []
	for it in ITEMS:
		if price >= it.min and price <= it.max:
			fit.append(it)
	if fit.is_empty():
		var best = ITEMS[0]
		for it in ITEMS:
			if abs(price - (it.min + it.max) / 2) < abs(price - (best.min + best.max) / 2):
				best = it
		return best
	return fit.pick_random()

static func label(text: String, size: int, color: Color, outline := 0, outline_color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = outline_color
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
