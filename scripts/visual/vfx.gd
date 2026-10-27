class_name Vfx
extends Node2D
## One-shot visual effect drawn in code. Frees itself after `life` seconds.
##   Vfx.spawn(world, "slash", target_pos, Color.WHITE, 70.0)
## Kinds: slash, ring, star, explosion, pillar, beam, smoke, bolt, heal, whoosh, hex.

var kind := ""
var col := Color.WHITE
var radius := 60.0
var life := 0.4
var dir := 1.0           # facing for directional effects (slash, whoosh)
var target := Vector2.ZERO  # bolt destination, relative to position
var _age := 0.0
var _seed := randf() * 100.0


static func spawn(parent: Node, p_kind: String, pos: Vector2, p_col: Color = Color.WHITE, p_radius: float = 60.0,
		p_life: float = 0.4, p_dir: float = 1.0) -> Vfx:
	var v := Vfx.new()
	v.kind = p_kind
	v.position = pos
	v.col = p_col
	v.radius = p_radius
	v.life = p_life
	v.dir = p_dir
	parent.add_child(v)
	return v


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := clampf(_age / life, 0.0, 1.0)
	var fade := 1.0 - k
	match kind:
		"slash":  # crescent sweeping across the target
			draw_set_transform(Vector2.ZERO, -0.7 * dir, Vector2(dir, 1))
			var sweep := 2.4 * minf(1.0, k * 4.0)
			for j in 3:
				draw_arc(Vector2.ZERO, radius - j * 5, -2.0, -2.0 + sweep, 24,
						Color(col, fade * (0.95 - j * 0.3)), (9 - j * 3) * fade + 1, true)
		"ring":
			draw_arc(Vector2.ZERO, radius * (0.25 + k), 0, TAU, 48, Color(col, fade), 8 * fade + 1, true)
		"star":  # impact spikes
			for j in 10:
				var a := j * TAU / 10 + _seed
				var inner := radius * (0.15 + k * 0.5)
				var outer := radius * (0.5 + k * 0.7) * (1.0 if j % 2 == 0 else 0.65)
				draw_line(Vector2(cos(a), sin(a)) * inner, Vector2(cos(a), sin(a)) * outer, Color(col, fade), 4 * fade + 1, true)
		"explosion":
			draw_circle(Vector2.ZERO, radius * (0.4 + k * 0.8), Color(1, 0.55, 0.1, 0.55 * fade))
			draw_circle(Vector2.ZERO, radius * (0.25 + k * 0.5), Color(1, 0.85, 0.3, 0.8 * fade))
			draw_circle(Vector2.ZERO, radius * 0.2 * fade, Color(1, 1, 0.9, fade))
			draw_arc(Vector2.ZERO, radius * (0.5 + k * 1.1), 0, TAU, 48, Color(1, 0.7, 0.3, fade), 6 * fade + 1, true)
		"pillar":  # column of light rising from the feet
			var w := radius * (1.0 - k * 0.4)
			for j in 4:
				var ww := w * (1.0 - j * 0.22)
				draw_rect(Rect2(-ww / 2, -700, ww, 700), Color(col, 0.12 * fade * (1 + j)))
			draw_rect(Rect2(-w * 0.08, -700, w * 0.16, 700), Color(1, 1, 1, 0.6 * fade))
		"beam":  # strikes down from above
			var w := radius * (0.5 + 0.5 * sin(minf(k * 6.0, PI)))
			draw_rect(Rect2(-w / 2, -900, w, 900), Color(col, 0.35 * fade))
			draw_rect(Rect2(-w / 6, -900, w / 3, 900), Color(1, 1, 1, 0.75 * fade))
			draw_circle(Vector2.ZERO, w * 0.9, Color(col, 0.4 * fade))
		"smoke":
			for j in 9:
				var a := j * 2.4 + _seed
				var p := Vector2(cos(a), sin(a) * 0.6) * radius * (0.2 + k * 0.7) + Vector2(0, -k * 20)
				draw_circle(p, radius * (0.25 + 0.3 * k) * (0.8 + 0.4 * sin(a * 3.0)), Color(col, 0.5 * fade))
		"bolt":  # orb flying to `target` with a trail
			var e := ease(k, 0.6)
			for j in 6:
				var t := clampf(e - j * 0.04, 0.0, 1.0)
				var p := target * t + Vector2(0, -sin(t * PI) * 40)
				draw_circle(p, radius * 0.25 * (1.0 - j * 0.14), Color(col, (1.0 - j * 0.15) * (1.0 if k < 0.9 else fade * 10)))
			var head := target * e + Vector2(0, -sin(e * PI) * 40)
			draw_circle(head, radius * 0.12, Color(1, 1, 1, 0.9))
		"heal":  # little crosses floating up
			for j in 7:
				var x := sin(j * 1.9 + _seed) * radius * 0.6
				var y := -k * radius * (1.0 + (j % 3) * 0.4) - j * 6
				var s := 6.0 + (j % 3) * 2
				var c := Color(col, fade)
				draw_line(Vector2(x - s, y), Vector2(x + s, y), c, 3.0)
				draw_line(Vector2(x, y - s), Vector2(x, y + s), c, 3.0)
		"whoosh":  # near miss swoosh
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(dir, 1))
			for j in 3:
				var y := -j * 12.0
				draw_line(Vector2(-radius * (1.0 - k), y), Vector2(-radius * (1.0 - k) + radius * 0.8, y + 4),
						Color(col, fade * (0.8 - j * 0.2)), 3.0, true)
		"hex":  # shield barrier pop
			var r := radius * (0.7 + k * 0.4)
			for j in 6:
				var a0 := j * TAU / 6
				draw_line(Vector2(cos(a0), sin(a0)) * r, Vector2(cos(a0 + TAU / 6), sin(a0 + TAU / 6)) * r, Color(col, fade), 5.0 * fade + 1, true)
			draw_circle(Vector2.ZERO, r, Color(col, 0.15 * fade))
