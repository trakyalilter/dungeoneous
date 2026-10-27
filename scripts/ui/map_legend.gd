class_name MapLegend
extends Control
## One row explaining the map's room icons.

const TYPES := ["fight", "elite", "event", "shop", "rest", "treasure", "boss"]


func _ready() -> void:
	custom_minimum_size = Vector2(0, 30)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var step := size.x / TYPES.size()
	for i in TYPES.size():
		var t: String = TYPES[i]
		var c := Vector2(step * i + 18, size.y / 2)
		MapView.paint_node(self, t, c, 11.0, MapView.COLORS[t], false)
		draw_string(font, c + Vector2(17, 5), Config.NODE_NAMES[t], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#bbbbbb"))
