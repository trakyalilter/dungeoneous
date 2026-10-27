class_name GameIcon
extends Control
## Small vector icon drawn in code (relics, consumables, statuses, intents, stats).
## GameIcon.make("bomb", 28) returns a ready-to-add control.

const OUT := Color("#0e0c12")

var id := ""
var tint := Color.WHITE  # multiplies the icon's own colors


static func make(icon_id: String, px: int = 24, tip: String = "") -> GameIcon:
	var icon := GameIcon.new()
	icon.id = icon_id
	icon.custom_minimum_size = Vector2(px, px)
	icon.tooltip_text = tip
	icon.mouse_filter = Control.MOUSE_FILTER_PASS if tip != "" else Control.MOUSE_FILTER_IGNORE
	return icon


func set_id(icon_id: String) -> void:
	id = icon_id
	queue_redraw()


# coordinates below are in a -1..1 box, converted to pixels by _p()
func _p(x: float, y: float) -> Vector2:
	var s := minf(size.x, size.y) / 2.0
	return size / 2.0 + Vector2(x, y) * s * 0.9


func _r(r: float) -> float:
	return r * minf(size.x, size.y) / 2.0 * 0.9


func _c(hex: String) -> Color:
	return Color(hex) * tint


func _circle(x: float, y: float, r: float, hex: String, outline: bool = true) -> void:
	if outline:
		draw_circle(_p(x, y), _r(r) + 1.5, OUT)
	draw_circle(_p(x, y), _r(r), _c(hex))


func _poly(flat: Array, hex: String, outline: bool = true) -> void:
	var pts := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		pts.append(_p(flat[i], flat[i + 1]))
	draw_colored_polygon(pts, _c(hex))
	if outline:
		pts.append(pts[0])
		draw_polyline(pts, OUT, 1.5, true)


func _line(x0: float, y0: float, x1: float, y1: float, hex: String, w: float = 0.18) -> void:
	draw_line(_p(x0, y0), _p(x1, y1), OUT, _r(w) + 2.5)
	draw_line(_p(x0, y0), _p(x1, y1), _c(hex), _r(w))


func _rect(x: float, y: float, w: float, h: float, hex: String) -> void:
	_poly([x, y, x + w, y, x + w, y + h, x, y + h], hex)


func _draw() -> void:
	match id:
		"atk", "attack", "whetstone":
			_line(-0.7, 0.7, 0.6, -0.6, "#d8dde2", 0.2)
			_line(-0.55, 0.25, -0.25, 0.55, "#c9a227", 0.16)
			_line(-0.8, 0.8, -0.6, 0.6, "#6b4a2a", 0.18)
			if id == "whetstone":
				_rect(0.1, 0.35, 0.8, 0.45, "#7a8597")
		"armor", "shield", "guard":
			_poly([-0.75, -0.7, 0.75, -0.7, 0.7, 0.1, 0.0, 0.85, -0.7, 0.1], "#5d8fd6")
			_poly([-0.1, -0.55, 0.1, -0.55, 0.1, 0.55, -0.1, 0.55], "#c9d8ee", false)
		"heart", "iron_heart":
			_circle(-0.38, -0.25, 0.42, "#c0392b" if id == "heart" else "#8a93a0")
			_circle(0.38, -0.25, 0.42, "#c0392b" if id == "heart" else "#8a93a0")
			_poly([-0.8, -0.1, 0.8, -0.1, 0.0, 0.85], "#c0392b" if id == "heart" else "#8a93a0", false)
		"gold", "idol":
			if id == "idol":
				_poly([-0.4, 0.8, 0.4, 0.8, 0.3, 0.2, 0.45, -0.3, 0.0, -0.85, -0.45, -0.3, -0.3, 0.2], "#e0b030")
				_circle(-0.15, -0.35, 0.08, "#0e0c12", false)
				_circle(0.15, -0.35, 0.08, "#0e0c12", false)
			else:
				_circle(0.0, 0.0, 0.75, "#e0b030")
				_circle(0.0, 0.0, 0.48, "#f5d060", false)
		"potion", "elixir":
			_rect(-0.18, -0.85, 0.36, 0.35, "#8a6a3a")
			_circle(0.0, 0.25, 0.6, "#e04060" if id == "potion" else "#8fd8ff")
			_circle(-0.2, 0.05, 0.12, "#ffffff", false)
		"poison", "venom":
			_circle(0.0, -0.15, 0.6, "#7dd35f")
			_rect(-0.3, 0.3, 0.6, 0.35, "#7dd35f")
			_circle(-0.25, -0.2, 0.15, "#0e0c12", false)
			_circle(0.25, -0.2, 0.15, "#0e0c12", false)
		"burn", "fire", "phoenix":
			_poly([-0.6, 0.8, -0.7, 0.0, -0.3, -0.4, 0.0, -0.9, 0.3, -0.4, 0.7, 0.0, 0.6, 0.8], "#ff7a20")
			_poly([-0.3, 0.8, -0.35, 0.25, 0.0, -0.25, 0.35, 0.25, 0.3, 0.8], "#ffe070", false)
			if id == "fire":
				_rect(-0.6, 0.55, 1.2, 0.3, "#8fd8ff")
		"strength", "tonic":
			_poly([-0.75, 0.75, -0.75, -0.1, -0.3, -0.75, 0.1, -0.75, 0.1, -0.35, -0.25, -0.2, 0.75, -0.2, 0.75, 0.75], "#f0c8a0")
		"dodge", "smoke", "cloak":
			_circle(-0.35, 0.15, 0.45, "#9aa5b1")
			_circle(0.3, -0.15, 0.5, "#b5bec8")
			_circle(0.35, 0.4, 0.35, "#9aa5b1")
		"trait", "special":
			_poly([0.0, -0.9, 0.22, -0.22, 0.9, 0.0, 0.22, 0.22, 0.0, 0.9, -0.22, 0.22, -0.9, 0.0, -0.22, -0.22], "#e07bff")
		"exp":  # five-point star
			var pts := []
			for k in 10:
				var a := -PI / 2 + k * PI / 5
				var rr := 0.9 if k % 2 == 0 else 0.4
				pts.append_array([cos(a) * rr, sin(a) * rr])
			_poly(pts, "#4fc3f7")
			_circle(-0.12, -0.15, 0.12, "#e0f6ff", false)
		"charge":
			_poly([0.2, -0.9, -0.55, 0.15, -0.05, 0.15, -0.25, 0.9, 0.55, -0.2, 0.05, -0.2], "#ffd84d")
		"heavy":
			_poly([0.0, -0.9, 0.25, -0.35, 0.85, -0.5, 0.45, 0.0, 0.85, 0.5, 0.25, 0.35, 0.0, 0.9, -0.25, 0.35,
					-0.85, 0.5, -0.45, 0.0, -0.85, -0.5, -0.25, -0.35], "#ff5a3a")
		"clover":
			for a in [[0.0, -0.4], [0.4, 0.0], [0.0, 0.4], [-0.4, 0.0]]:
				_circle(a[0], a[1], 0.36, "#4caf50")
			_line(0.1, 0.3, 0.45, 0.85, "#3a7a3a", 0.12)
		"cactus":
			_poly([-0.6, 0.8, 0.6, 0.8, 0.5, -0.2, 0.0, -0.6, -0.5, -0.2], "#8a93a0")
			for x in [-0.4, 0.0, 0.4]:
				_poly([x - 0.12, -0.3 + absf(x) * 0.4, x + 0.12, -0.3 + absf(x) * 0.4, x, -0.85 + absf(x) * 0.4], "#e8e4d8")
		"bandages":
			_poly([-0.85, -0.25, 0.85, -0.25, 0.85, 0.25, -0.85, 0.25], "#f0e6c8")
			_rect(-0.2, -0.25, 0.4, 0.5, "#e0b0a0")
			_circle(-0.55, 0.0, 0.07, "#8a6a3a", false)
			_circle(0.55, 0.0, 0.07, "#8a6a3a", false)
		"drum":
			_poly([-0.7, -0.35, 0.7, -0.35, 0.6, 0.65, -0.6, 0.65], "#b03a3a")
			draw_line(_p(-0.7, -0.35), _p(0.7, -0.35), _c("#f0e6c8"), _r(0.2))
			_line(-0.3, -0.5, 0.1, -0.95, "#8a6a3a", 0.1)
			_line(0.3, -0.5, 0.7, -0.9, "#8a6a3a", 0.1)
		"hourglass":
			_poly([-0.6, -0.85, 0.6, -0.85, 0.0, 0.0], "#f0d8a0")
			_poly([-0.6, 0.85, 0.6, 0.85, 0.0, 0.0], "#f0d8a0")
			_poly([-0.3, 0.85, 0.3, 0.85, 0.0, 0.4], "#e0b030", false)
		"anchor":
			_line(0.0, -0.75, 0.0, 0.7, "#8a93a0", 0.16)
			_line(-0.35, -0.45, 0.35, -0.45, "#8a93a0", 0.14)
			draw_arc(_p(0, 0.15), _r(0.6), 0.2, PI - 0.2, 16, _c("#8a93a0"), _r(0.16))
			_circle(0.0, -0.8, 0.15, "#8a93a0")
		"magnet":
			draw_arc(_p(0, -0.1), _r(0.55), PI, TAU, 20, OUT, _r(0.42) + 2.5)
			draw_arc(_p(0, -0.1), _r(0.55), PI, TAU, 20, _c("#c0392b"), _r(0.42))
			_rect(-0.76, -0.1, 0.42, 0.8, "#c0392b")
			_rect(0.34, -0.1, 0.42, 0.8, "#c0392b")
			_rect(-0.76, 0.45, 0.42, 0.25, "#e8e4d8")
			_rect(0.34, 0.45, 0.42, 0.25, "#e8e4d8")
		"tome":
			_rect(-0.7, -0.8, 1.4, 1.6, "#6b3a2a")
			_rect(-0.5, -0.65, 1.1, 1.3, "#f0e6c8")
			_rect(-0.7, -0.8, 0.25, 1.6, "#4a2a1a")
		"mask":
			_poly([-0.8, -0.6, 0.8, -0.6, 0.65, 0.4, 0.0, 0.85, -0.65, 0.4], "#c0392b")
			_poly([-0.55, -0.6, -0.8, -1.0, -0.3, -0.6], "#f0e6c8")
			_poly([0.55, -0.6, 0.8, -1.0, 0.3, -0.6], "#f0e6c8")
			_poly([-0.5, -0.2, -0.15, -0.1, -0.45, 0.05], "#ffe04a", false)
			_poly([0.5, -0.2, 0.15, -0.1, 0.45, 0.05], "#ffe04a", false)
		"crown":
			_poly([-0.85, 0.6, -0.85, -0.5, -0.4, 0.0, 0.0, -0.75, 0.4, 0.0, 0.85, -0.5, 0.85, 0.6], "#e0b030")
			_circle(0.0, 0.25, 0.14, "#c0392b")
		"orb":
			_circle(0.0, -0.15, 0.65, "#7d6bff")
			_circle(-0.2, -0.35, 0.18, "#d8d0ff", false)
			_rect(-0.5, 0.45, 1.0, 0.35, "#6b4a2a")
		"skull":
			_circle(0.0, -0.15, 0.68, "#e8e4d8")
			_rect(-0.35, 0.35, 0.7, 0.45, "#e8e4d8")
			_circle(-0.27, -0.15, 0.18, "#0e0c12", false)
			_circle(0.27, -0.15, 0.18, "#0e0c12", false)
		"dragon_eye":
			_poly([-0.9, 0.0, 0.0, -0.6, 0.9, 0.0, 0.0, 0.6], "#f0e6c8")
			_circle(0.0, 0.0, 0.42, "#e0b030", false)
			_poly([-0.08, -0.4, 0.08, -0.4, 0.08, 0.4, -0.08, 0.4], "#0e0c12", false)
		"bomb":
			_circle(-0.1, 0.15, 0.65, "#2a2a36")
			_circle(-0.3, -0.05, 0.14, "#8a8a9a", false)
			_line(0.3, -0.35, 0.6, -0.7, "#8a6a3a", 0.1)
			_circle(0.68, -0.8, 0.14, "#ffb040", false)
		"gear":
			for k in 8:
				var a := k * TAU / 8
				_line(cos(a) * 0.45, sin(a) * 0.45, cos(a) * 0.85, sin(a) * 0.85, "#c8cdd6", 0.28)
			_circle(0.0, 0.0, 0.55, "#c8cdd6")
			_circle(0.0, 0.0, 0.22, "#2e2e3e", false)
		"sound", "mute":
			_poly([-0.8, -0.3, -0.4, -0.3, 0.1, -0.75, 0.1, 0.75, -0.4, 0.3, -0.8, 0.3], "#c8cdd6")
			if id == "sound":
				draw_arc(_p(0.15, 0), _r(0.4), -0.9, 0.9, 12, _c("#c8cdd6"), _r(0.12))
				draw_arc(_p(0.15, 0), _r(0.72), -0.9, 0.9, 12, _c("#c8cdd6"), _r(0.12))
			else:
				_line(0.35, -0.35, 0.85, 0.35, "#ff6b6b", 0.14)
				_line(0.35, 0.35, 0.85, -0.35, "#ff6b6b", 0.14)
		"lock":
			draw_arc(_p(0, -0.2), _r(0.38), PI, TAU, 14, OUT, _r(0.16) + 2.5)
			draw_arc(_p(0, -0.2), _r(0.38), PI, TAU, 14, _c("#c8cdd6"), _r(0.16))
			_rect(-0.6, -0.2, 1.2, 1.0, "#c9a227")
			_circle(0.0, 0.25, 0.12, "#0e0c12", false)
		_:
			_circle(0.0, 0.0, 0.6, "#7a8597")
