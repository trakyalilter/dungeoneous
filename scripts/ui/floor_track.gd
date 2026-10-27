class_name FloorTrack
extends Control
## Row of floor markers under the map title: cleared floors, the current one (pulsing), and what lies below.
## Hover a marker for the floor's name and boss.

const STEP := 54.0

var floor_num := 1
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(STEP * (Config.FLOORS - 1) + 40, 34)
	tooltip_text = " "  # enables _get_tooltip


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _center(f: int) -> Vector2:
	var x0 := (size.x - STEP * (Config.FLOORS - 1)) / 2
	return Vector2(x0 + (f - 1) * STEP, size.y / 2)


func _get_tooltip(at_position: Vector2) -> String:
	for f in range(1, Config.FLOORS + 1):
		if at_position.distance_to(_center(f)) < 16:
			var info: Dictionary = Config.FLOOR_INFO[f - 1]
			var state := "cleared" if f < floor_num else ("you are here" if f == floor_num else "ahead")
			return "Floor %d: %s (%s)\nBoss: %s" % [f, info["name"], state, info["boss_title"] if f <= floor_num else "???"]
	return ""


func _draw() -> void:
	draw_line(_center(1), _center(Config.FLOORS), Color(1, 1, 1, 0.15), 3.0)
	if floor_num > 1:
		draw_line(_center(1), _center(floor_num), Color(GameLog.YELLOW), 3.0)
	for f in range(1, Config.FLOORS + 1):
		var c := _center(f)
		var glow: Color = BattleStage.theme_for(f)["glow"]
		if f == floor_num:
			var pulse := 0.5 + 0.5 * sin(_t * 3.0)
			draw_circle(c, 15 + pulse * 3, Color(glow, 0.25))
			draw_circle(c, 11, MapView.OUT)
			draw_circle(c, 9, glow)
		elif f < floor_num:
			draw_circle(c, 9, MapView.OUT)
			draw_circle(c, 7, Color(GameLog.YELLOW))
			draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-1, 3), c + Vector2(4, -3)]), MapView.OUT, 2.0, true)
		else:
			draw_circle(c, 8, MapView.OUT)
			draw_arc(c, 7, 0, TAU, 20, Color(glow, 0.55), 2.0, true)
		if f == Config.FLOORS:  # the final floor gets a little crown
			draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -12), c + Vector2(-6, -18), c + Vector2(-3, -15),
					c + Vector2(0, -20), c + Vector2(3, -15), c + Vector2(6, -18), c + Vector2(6, -12)]), Color(GameLog.YELLOW))
