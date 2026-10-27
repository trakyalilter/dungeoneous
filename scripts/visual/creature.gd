class_name Creature
extends Node2D
## A vector-drawn character: one of the enemy types or a hero class.
## Origin is at the feet. Enemies face left, heroes face right.
## Shapes are cel-shaded (light from the top left), eyes blink, and the body bobs, breathes and
## reacts to hits (squash) and attacks (lean). Status flags draw auras (charging, guarding, poisoned).

const OUT := Color("#14121a")
const W := 3.0  # outline width
const STEEL := Color("#cfd6dd")
const WOOD := Color("#6b4a2a")
const IVORY := Color("#f0e6c8")
const LIGHT := Vector2(-0.55, -0.83)  # direction the light comes from

## Approximate drawn height (px at scale 1), used to place text above heads.
const HEIGHT := {
	"Goblin": 100, "Orc": 115, "Troll": 150, "Skeleton": 155, "Zombie": 145, "Vampire": 150,
	"Werewolf": 170, "Demon": 170, "Giant": 255, "Dragon": 170,
	"Slime": 85, "Wraith": 170, "Golem": 172, "Yeti": 205, "Lich": 195,
	"Warrior": 140, "Rogue": 135, "Cleric": 165, "Necromancer": 160,
}
## Per-kind size so a Giant does not tower out of the stage.
const SIZE := {"Goblin": 1.0, "Giant": 0.72, "Dragon": 0.95, "Troll": 0.95, "Slime": 1.1, "Golem": 0.95, "Yeti": 0.85,
	"Lich": 0.9}

var kind := "Warrior"
var boss := false
var elite := false
var shielded := false
var offset := Vector2.ZERO  # animation offset from the spot the owner places it at
var squash := 0.0           # >0 squashes wide (hit), <0 stretches tall (jump)
var lean := 0.0             # radians, for wind-ups and lunges
var charging := false       # winding up a heavy hit: hot aura
var guarding := false       # blue barrier in front
var poisoned := false       # green bubbles
var _t := randf() * 10.0
var _blink_in := randf_range(1.0, 4.0)
var _blink := 0.0


func setup(p_kind: String, p_boss: bool = false, p_elite: bool = false) -> void:
	kind = p_kind
	boss = p_boss
	elite = p_elite
	shielded = false
	charging = false
	guarding = false
	poisoned = false
	offset = Vector2.ZERO
	squash = 0.0
	lean = 0.0
	modulate = Color.WHITE
	rotation = 0.0


## Scale multiplier for this kind (bosses are bigger).
func size_mult() -> float:
	return SIZE.get(kind, 1.0) * (1.25 if boss else (1.12 if elite else 1.0))


func head_y() -> float:
	return -float(HEIGHT.get(kind, 150))


func _process(delta: float) -> void:
	_t += delta
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink = 0.13
		_blink_in = randf_range(2.0, 5.0)
	_blink = maxf(0.0, _blink - delta)
	queue_redraw()


func _draw() -> void:
	var mid := Vector2(0, head_y() * 0.5)
	if boss or elite:  # menacing aura on the ground
		var glow := Color(1, 0.75, 0.2) if boss else Color(1, 0.25, 0.25)
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		_flat_ellipse(Vector2(0, 2), 70 + pulse * 6, 14 + pulse, Color(glow, 0.18 + 0.1 * pulse))
	_soft_shadow()
	if charging:  # heat haze hugging the body
		var p := 0.5 + 0.5 * sin(_t * 9.0)
		for k in 3:
			_flat_ellipse(mid, -head_y() * (0.32 + k * 0.06) + p * 4, -head_y() * (0.45 + k * 0.06) + p * 4,
					Color(1, 0.5 - k * 0.1, 0.1, 0.09))
	var bob := sin(_t * 2.2) * 2.5
	var breathe := sin(_t * 2.2) * 0.015
	draw_set_transform(Vector2(0, bob), lean, Vector2(1.0 + squash, 1.0 - squash + breathe))
	match kind:
		"Goblin": _goblin()
		"Orc": _orc()
		"Troll": _troll()
		"Skeleton": _skeleton()
		"Zombie": _zombie()
		"Vampire": _vampire()
		"Werewolf": _werewolf()
		"Demon": _demon()
		"Giant": _giant()
		"Dragon": _dragon()
		"Slime": _slime()
		"Wraith": _wraith()
		"Golem": _golem()
		"Yeti": _yeti()
		"Lich": _lich()
		"Warrior": _warrior()
		"Rogue": _rogue()
		"Cleric": _cleric()
		"Necromancer": _necromancer()
	draw_set_transform(Vector2.ZERO)
	if poisoned:  # bubbles drifting up
		for k in 6:
			var ph := fmod(_t * 0.7 + k / 6.0, 1.0)
			var x := sin(k * 2.3 + _t * 2.0) * 26
			draw_circle(Vector2(x, lerpf(-10, head_y(), ph)), 3.0 + 3.0 * (1.0 - ph), Color(0.45, 0.95, 0.35, 0.55 * (1.0 - ph)))
	if guarding:  # shimmering barrier on the side facing the opponent
		var face := -1.0 if kind in Config.ENEMY_TRAITS else 1.0
		var facing := PI if face < 0 else 0.0  # angle pointing toward the opponent
		var shimmer := 0.6 + 0.4 * sin(_t * 6.0)
		var r := -head_y() * 0.5
		for k in 3:
			draw_arc(mid - Vector2(face * 10, 0), r + k * 6, facing - 0.85, facing + 0.85, 20,
					Color(0.5, 0.8, 1.0, (0.8 - k * 0.25) * shimmer), 5.0 - k, true)
	if shielded:
		var r := -head_y() * 0.62
		draw_circle(mid, r, Color(0.5, 0.8, 1.0, 0.1))
		for k in 6:  # hexagon facets turning slowly
			var a0 := _t * 0.6 + k * TAU / 6
			draw_line(mid + Vector2(cos(a0), sin(a0)) * r, mid + Vector2(cos(a0 + TAU / 6), sin(a0 + TAU / 6)) * r,
					Color(0.6, 0.85, 1.0, 0.85), 3.0, true)


# ------------------------------------------------------------------ helpers

func _v(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, points.size(), 2):
		out.append(Vector2(points[i], points[i + 1]))
	return out


## Base color tinted by how much a point faces the light: lit edges brighter, far edges darker.
func _lit(col: Color, normal: Vector2) -> Color:
	var k := normal.dot(LIGHT)
	return col.lightened(0.22 * k) if k > 0.0 else col.darkened(-0.32 * k)


func _soft_shadow() -> void:
	for k in 3:
		_flat_ellipse(Vector2(0, 2), 56 - k * 10, 10 - k * 2, Color(0, 0, 0, 0.14))


func _flat_ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


## Shaded ellipse with outline and a small specular highlight. outline = false gives a flat patch (bellies, shadows).
func _ellipse(c: Vector2, rx: float, ry: float, col: Color, outline: bool = true) -> void:
	if not outline or col.a < 1.0:
		_flat_ellipse(c, rx, ry, col)
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 32:
		var a := TAU * i / 32.0
		var n := Vector2(cos(a), sin(a))
		pts.append(c + Vector2(n.x * rx, n.y * ry))
		cols.append(_lit(col, n))
	draw_polygon(pts, cols)
	if rx > 9.0 and ry > 9.0:
		_flat_ellipse(c + Vector2(-rx * 0.35, -ry * 0.42), rx * 0.28, ry * 0.16, Color(1, 1, 1, 0.22))
	pts.append(pts[0])
	draw_polyline(pts, OUT, W, true)


## Filled polygon from a flat [x0, y0, x1, y1, ...] list, shaded from its center, with outline.
func _poly(flat: Array, col: Color, outline: bool = true) -> void:
	var pts := _v(flat)

	if not outline or col.a < 1.0:
		draw_colored_polygon(pts, col)
		return
	var center := Vector2.ZERO
	for p in pts:
		center += p
	center /= pts.size()
	var cols := PackedColorArray()
	for p in pts:
		cols.append(_lit(col, (p - center).normalized()))
	draw_polygon(pts, cols)
	pts.append(pts[0])
	draw_polyline(pts, OUT, W, true)



func _eye(c: Vector2, r: float, iris: Color, look: Vector2 = Vector2(-1, 0)) -> void:
	if _blink > 0.0:
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), OUT, 3.0)
		return
	_flat_ellipse(c, r + 1.5, r + 1.5, OUT)
	_flat_ellipse(c, r, r, Color.WHITE)
	draw_circle(c + look * r * 0.3, r * 0.55, iris)
	draw_circle(c + look * r * 0.4, r * 0.25, OUT)
	draw_circle(c + look * r * 0.15 + Vector2(-r * 0.2, -r * 0.25), r * 0.18, Color(1, 1, 1, 0.9))


func _glow_eye(c: Vector2, r: float, col: Color) -> void:
	var p := 0.85 + 0.15 * sin(_t * 4.0 + c.x)
	draw_circle(c, r * 2.6 * p, Color(col, 0.18))
	draw_circle(c, r * 1.6, Color(col, 0.3))
	draw_circle(c, r * (0.3 if _blink > 0.0 else 1.0), col)
	draw_circle(c, r * 0.4, Color(1, 1, 1, 0.8))

# ------------------------------------------------------------------ smooth-shape toolkit

## Closed Catmull-Rom curve through the control points (flat [x0, y0, x1, y1, ...]).
func _smooth(flat: Array, seg: int = 6) -> PackedVector2Array:
	var p := _v(flat)
	var n := p.size()
	var out := PackedVector2Array()
	for i in n:
		var p0 := p[(i - 1 + n) % n]
		var p1 := p[i]
		var p2 := p[(i + 1) % n]
		var p3 := p[(i + 2) % n]
		for s in seg:
			var t := float(s) / seg
			var t2 := t * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t2 * t))
	return out


## Fill a closed outline lit by its surface normals, add a rim light on lit edges, then the ink outline.
func _fill(pts: PackedVector2Array, col: Color, outline: bool = true) -> void:
	var n := pts.size()
	var area := 0.0
	for i in n:
		area += pts[i].cross(pts[(i + 1) % n])
	var s := 1.0 if area > 0.0 else -1.0
	var cols := PackedColorArray()
	var normals := PackedVector2Array()
	for i in n:
		var e := pts[(i + 1) % n] - pts[(i - 1 + n) % n]
		var nrm := Vector2(e.y, -e.x).normalized() * s
		normals.append(nrm)
		cols.append(_lit(col, nrm))

	draw_polygon(pts, cols)
	if not outline:
		return
	var rim := Color(col.lightened(0.45), 0.55)
	for i in n:
		if normals[i].dot(LIGHT) > 0.55 and normals[(i + 1) % n].dot(LIGHT) > 0.55:
			draw_line(pts[i] - normals[i] * 2.5, pts[(i + 1) % n] - normals[(i + 1) % n] * 2.5, rim, 2.0, true)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, OUT, W, true)


## Smooth shaded shape from control points.
func _shape(flat: Array, col: Color, outline: bool = true) -> void:
	_fill(_smooth(flat), col, outline)


## Tapered capsule from a (width wa) to b (width wb). pass_no 0 = ink outline, 1 = color.
func _taper(a: Vector2, b: Vector2, wa: float, wb: float, col: Color, pass_no: int) -> void:
	var d := b - a
	if d.length() < 0.5:
		return
	var nrm := d.orthogonal().normalized()
	var grow := W if pass_no == 0 else 0.0
	var c := OUT if pass_no == 0 else col.darkened(0.1)
	draw_colored_polygon(PackedVector2Array([a + nrm * (wa / 2 + grow), b + nrm * (wb / 2 + grow),
			b - nrm * (wb / 2 + grow), a - nrm * (wa / 2 + grow)]), c)
	draw_circle(a, wa / 2 + grow, c)
	draw_circle(b, wb / 2 + grow, c)
	if pass_no == 1 and minf(wa, wb) >= 5.0:
		var side := nrm if nrm.dot(LIGHT) > 0.0 else -nrm
		draw_line(a + side * wa * 0.2, b + side * wb * 0.2, col.lightened(0.14), minf(wa, wb) * 0.4)


## Limb with a joint: a -> knee/elbow k -> b, tapering from w0 to w1.
func _limb3(a: Vector2, k: Vector2, b: Vector2, w0: float, w1: float, col: Color) -> void:
	var wk := (w0 + w1) / 2.0
	for pass_no in 2:
		_taper(a, k, w0, wk, col, pass_no)
		_taper(k, b, wk, w1, col, pass_no)


## Straight limb, same look as _limb3.
func _limb(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	for pass_no in 2:
		_taper(a, b, width, width, col, pass_no)


## Hand with three stubby fingers (and optional claws) pointing along dir.
func _hand(c: Vector2, r: float, col: Color, dir: Vector2 = Vector2(-1, 0), claw: Color = Color(0, 0, 0, 0)) -> void:
	dir = dir.normalized()
	var side := dir.orthogonal()
	for k in [-1, 0, 1]:
		var tip: Vector2 = c + dir * r * 1.5 + side * k * r * 0.6
		_limb(c + side * k * r * 0.4, tip, r * 0.55, col)
		if claw.a > 0.0:
			draw_colored_polygon(PackedVector2Array([tip + side * r * 0.25, tip + dir * r * 0.7, tip - side * r * 0.25]), claw)
	_ellipse(c, r, r * 0.9, col)


func _brow(a: Vector2, b: Vector2, w: float = 4.0) -> void:
	draw_line(a, b, OUT, w, true)


## Row of n triangular teeth between a and b, pointing down (or up).
func _teeth(a: Vector2, b: Vector2, n: int, size: float, up: bool = false, col: Color = IVORY) -> void:
	for i in n:
		var p0 := a.lerp(b, float(i) / n)
		var p1 := a.lerp(b, float(i + 1) / n)
		var tip := (p0 + p1) / 2 + Vector2(0, -size if up else size)
		draw_colored_polygon(PackedVector2Array([p0, p1, tip]), col)
		draw_polyline(PackedVector2Array([p0, tip, p1]), OUT, 1.5, true)


## Short fur / texture strokes scattered in an ellipse.
func _strokes(c: Vector2, rx: float, ry: float, count: int, col: Color, length: float = 7.0, angle: float = 1.9) -> void:
	for i in count:
		var a := i * 2.399 + 0.5
		var r := sqrt((i + 0.5) / count)
		var p := c + Vector2(cos(a) * rx * r, sin(a) * ry * r)
		draw_line(p, p + Vector2(cos(angle), sin(angle)) * length, col, 2.0, true)


func _rivet(c: Vector2, r: float = 2.2) -> void:
	draw_circle(c, r + 1.0, OUT)
	draw_circle(c, r, Color("#e8e8ee"))


# ------------------------------------------------------------------ enemies (face left)

func _goblin() -> void:
	var skin := Color("#7bc043")
	var dark := Color("#4e8a2a")
	var cloth := Color("#8a5a32")
	_limb3(Vector2(14, -46), Vector2(24, -36), Vector2(18, -26), 7, 6, dark)
	_hand(Vector2(17, -24), 4.5, dark, Vector2(-0.3, 1))
	_limb3(Vector2(8, -24), Vector2(15, -13), Vector2(12, -4), 9, 7, dark)
	_shape([2, -5, 16, -7, 21, -1, 4, 0], dark)
	_limb3(Vector2(-8, -24), Vector2(-13, -13), Vector2(-15, -4), 9, 7, skin)
	_shape([-27, -4, -10, -7, -7, -1, -28, 0], skin)
	_shape([-20, -48, -2, -56, 16, -50, 22, -34, 14, -18, -4, -14, -20, -20, -26, -34], skin)
	_flat_ellipse(Vector2(-6, -32), 11, 10, Color(skin.lightened(0.15), 0.7))
	_shape([-22, -26, 18, -26, 15, -12, 6, -17, -2, -8, -12, -15, -21, -10], cloth)
	_strokes(Vector2(-2, -18), 14, 4, 6, cloth.darkened(0.3), 5.0, 1.4)
	_limb(Vector2(-22, -26), Vector2(18, -26), 4, Color("#5a3a1a"))
	var twitch := sin(_t * 30.0) * 5.0 if fmod(_t, 4.0) < 0.25 else 0.0
	_poly([16, -84, 54, -104 - twitch, 58, -96, 24, -71], skin)
	_poly([22, -83, 47, -99 - twitch, 26, -76], Color("#d98a8a"), false)
	_shape([-30, -74, -24, -92, -6, -100, 14, -96, 24, -82, 22, -64, 8, -54, -12, -52, -26, -60], skin)
	_poly([-22, -84, -68, -103 + twitch, -72, -94, -28, -70], skin)
	_poly([-28, -82, -62, -99 + twitch, -32, -75], Color("#d98a8a"), false)
	_shape([-24, -78, -42, -71, -37, -62, -24, -65], skin.darkened(0.06))
	_eye(Vector2(-14, -82), 7.5, Color("#ffd23f"))
	_eye(Vector2(5, -84), 6.5, Color("#ffd23f"))
	_brow(Vector2(-23, -92), Vector2(-8, -88))
	_brow(Vector2(-1, -90), Vector2(12, -94))
	_fill(PackedVector2Array([Vector2(-24, -63), Vector2(0, -60), Vector2(14, -65), Vector2(8, -56), Vector2(-16, -54)]), Color("#3a1a1a"))
	_teeth(Vector2(-20, -62), Vector2(10, -61), 5, 4.0)
	for w in [Vector2(10, -72), Vector2(15, -78), Vector2(-26, -86)]:
		draw_circle(w, 2.2, dark)
	_limb3(Vector2(-14, -46), Vector2(-24, -40), Vector2(-33, -36), 7, 6, skin)
	_limb(Vector2(-30, -36), Vector2(-42, -38), 4, WOOD)
	_poly([-41, -42, -76, -48, -42, -33], STEEL)
	draw_line(Vector2(-44, -38), Vector2(-70, -46), Color(1, 1, 1, 0.6), 1.5)
	_hand(Vector2(-33, -36), 4.5, skin, Vector2(0.2, 1))


func _orc() -> void:
	var skin := Color("#5c8f3a")
	var dark := Color("#3e6626")
	var leather := Color("#6b4a2e")
	var metal := Color("#9aa3ad")
	_limb3(Vector2(30, -84), Vector2(46, -60), Vector2(40, -38), 17, 13, dark)
	_hand(Vector2(40, -34), 8, dark, Vector2(-0.3, 1))
	_limb3(Vector2(14, -34), Vector2(22, -18), Vector2(18, -6), 18, 15, dark)
	_shape([8, -10, 30, -10, 32, 0, 6, 0], leather.darkened(0.2))
	_limb3(Vector2(-14, -34), Vector2(-20, -18), Vector2(-22, -6), 18, 15, skin)
	_shape([-36, -10, -12, -10, -10, 0, -38, 0], leather.darkened(0.2))
	_shape([-40, -80, -12, -96, 24, -94, 42, -74, 40, -46, 24, -30, -20, -28, -40, -44], skin)
	draw_arc(Vector2(-6, -64), 18, 0.3, 2.6, 12, dark, 2.5, true)
	draw_line(Vector2(-4, -86), Vector2(-4, -56), dark, 2.0)
	draw_line(Vector2(12, -80), Vector2(22, -70), Color("#c88a7a"), 2.5)
	_shape([-40, -42, 38, -44, 40, -30, -38, -27], leather)
	_ellipse(Vector2(-4, -36), 6, 6, Color("#c9a227"))
	_shape([-30, -30, -6, -30, -10, -12, -26, -12], leather.lightened(0.1))
	_shape([2, -30, 26, -32, 24, -14, 6, -12], leather.lightened(0.1))
	_shape([-30, -98, -20, -118, 2, -124, 20, -114, 22, -94, 6, -82, -18, -82], skin)
	_shape([-30, -94, 8, -92, 6, -80, -24, -80], skin.darkened(0.08))
	_fill(_smooth([-26, -88, -6, -86, 2, -89, -4, -84, -22, -83]), Color("#2a1a1a"))
	_poly([-26, -89, -18, -89, -25, -110], IVORY)
	_poly([-2, -89, 6, -89, 3, -108], IVORY)
	_shape([-20, -100, -10, -103, -8, -94, -18, -93], skin.lightened(0.06))
	draw_circle(Vector2(-16, -95), 1.6, OUT)
	draw_circle(Vector2(-11, -96), 1.6, OUT)
	_glow_eye(Vector2(-22, -106), 3.2, Color("#ff4030"))
	_glow_eye(Vector2(-4, -107), 3.2, Color("#ff4030"))
	_fill(_smooth([-32, -112, -14, -116, 8, -116, 10, -111, -12, -110, -30, -108]), dark)
	_shape([-56, -86, -36, -94, -24, -82, -36, -68, -58, -72], metal)
	for r in [Vector2(-48, -82), Vector2(-36, -86), Vector2(-44, -74)]:
		_rivet(r)
	_limb(Vector2(-58, -50), Vector2(-68, -134), 7, WOOD)
	_shape([-66, -128, -100, -142, -108, -116, -98, -100, -66, -108], metal)
	draw_line(Vector2(-100, -138), Vector2(-104, -106), Color(1, 1, 1, 0.5), 2.0)
	_limb3(Vector2(-30, -84), Vector2(-46, -64), Vector2(-58, -52), 17, 13, skin)
	_hand(Vector2(-58, -50), 8, skin, Vector2(-0.2, -1))


func _troll() -> void:
	var skin := Color("#7f95ad")
	var dark := Color("#5a6c82")
	var hair := Color("#4a6b3a")
	_limb3(Vector2(30, -110), Vector2(48, -66), Vector2(50, -24), 16, 12, dark)
	_hand(Vector2(50, -20), 8, dark, Vector2(0, 1), IVORY)
	_limb3(Vector2(16, -44), Vector2(24, -22), Vector2(20, -6), 20, 16, dark)
	_shape([10, -8, 34, -9, 36, 0, 8, 0], dark)
	_limb3(Vector2(-14, -44), Vector2(-20, -22), Vector2(-22, -6), 20, 16, skin)
	_shape([-38, -9, -12, -8, -10, 0, -40, 0], skin)
	_shape([-34, -112, -10, -128, 22, -124, 38, -96, 36, -60, 24, -38, -18, -36, -38, -58, -42, -88], skin)
	_flat_ellipse(Vector2(-4, -66), 22, 24, Color(skin.lightened(0.15), 0.6))
	_shape([-36, -46, 30, -48, 26, -26, 10, -32, -4, -22, -18, -30, -34, -24], Color("#7a5a3a"))
	for w in [Vector2(20, -100), Vector2(28, -82), Vector2(-26, -92), Vector2(10, -116)]:
		draw_circle(w, 3.0, dark)
	_shape([-24, -122, -8, -142, 16, -140, 26, -122, 20, -108, -16, -108], skin)
	for k in 5:
		var x := -16 + k * 8
		var d := absf(k - 2)
		_poly([x - 5, -136 + d * 2, x + 5, -136 + d * 2, x + 2, -156 + d * 4], hair)
	_eye(Vector2(-12, -128), 5, Color("#ffd23f"))
	_eye(Vector2(6, -129), 5, Color("#ffd23f"))
	_brow(Vector2(-18, -136), Vector2(-6, -133), 5)
	_brow(Vector2(0, -134), Vector2(12, -137), 5)
	_shape([-6, -124, -24, -116, -22, -104, -8, -108], skin.lightened(0.05))
	_fill(_smooth([-22, -100, 0, -96, 18, -102, 14, -90, -18, -90]), Color("#2a1a1a"))
	_teeth(Vector2(-16, -91), Vector2(12, -91), 3, 7.0, true)
	_limb3(Vector2(-30, -110), Vector2(-50, -68), Vector2(-56, -26), 17, 12, skin)
	_hand(Vector2(-57, -22), 8, skin, Vector2(-0.2, 1), IVORY)


func _skeleton() -> void:
	var bone := Color("#ece6d4")
	var shade := Color("#b8b09a")
	_shape([18, -110, 42, -112, 46, -84, 36, -66, 16, -70, 12, -92], Color("#7a5a3a"))
	_ellipse(Vector2(30, -88), 7, 7, Color("#9aa3ad"))
	_limb3(Vector2(22, -104), Vector2(30, -82), Vector2(30, -62), 6, 5, shade)
	_limb3(Vector2(10, -46), Vector2(14, -24), Vector2(14, -6), 7, 6, shade)
	_shape([6, -8, 26, -8, 26, -1, 4, -1], shade)
	_limb3(Vector2(-8, -46), Vector2(-12, -24), Vector2(-14, -6), 7, 6, bone)
	for p in [Vector2(-12, -24), Vector2(14, -24)]:
		draw_circle(p, 5.5, OUT)
		draw_circle(p, 4.0, bone)
	_shape([-26, -8, -8, -8, -6, -1, -28, -1], bone)
	_shape([-18, -54, 18, -54, 14, -40, 0, -46, -14, -40], bone)
	_limb(Vector2(0, -56), Vector2(0, -106), 6, bone)
	for i in 4:
		var y := -100.0 + i * 11
		var w := 24.0 - i * 3
		draw_arc(Vector2(0, y - 6), w, 0.2, PI - 0.2, 14, OUT, 9.0, true)
		draw_arc(Vector2(0, y - 6), w, 0.2, PI - 0.2, 14, bone, 5.0, true)
	_shape([-4, -106, 4, -106, 3, -80, -3, -80], bone)
	_shape([-26, -110, -4, -114, -6, -104, -26, -102], bone)
	_shape([4, -114, 26, -110, 26, -102, 6, -104], bone)
	var jaw := absf(sin(_t * 7.0)) * 3.0 if fmod(_t, 3.0) < 0.8 else 0.0
	_shape([-14, -122 + jaw, 12, -122 + jaw, 10, -112 + jaw, -12, -112 + jaw], bone)
	for x in [-9, -4, 1, 6]:
		draw_line(Vector2(x, -122 + jaw), Vector2(x, -116 + jaw), OUT, 1.5)
	_shape([-24, -136, -18, -154, 0, -160, 20, -152, 24, -134, 14, -122, -16, -122], bone)
	draw_line(Vector2(-20, -128), Vector2(-10, -126), shade, 2.0)
	draw_line(Vector2(20, -128), Vector2(10, -126), shade, 2.0)
	_fill(_smooth([-18, -142, -6, -144, -4, -134, -16, -132]), OUT, false)
	_fill(_smooth([4, -144, 16, -142, 14, -132, 2, -134]), OUT, false)
	_glow_eye(Vector2(-11, -138), 2.5, Color("#ff5040"))
	_glow_eye(Vector2(9, -138), 2.5, Color("#ff5040"))
	draw_colored_polygon(PackedVector2Array([Vector2(-3, -126), Vector2(3, -126), Vector2(0, -132)]), OUT)
	draw_line(Vector2(6, -156), Vector2(12, -146), shade, 1.5)
	_limb3(Vector2(-22, -106), Vector2(-40, -84), Vector2(-56, -94), 6, 5, bone)
	_poly([-60, -96, -64, -166, -58, -178, -52, -166, -54, -96], Color("#b8bcc4"))
	draw_line(Vector2(-58, -100), Vector2(-58, -166), Color("#7a6a5a"), 1.5)
	_limb(Vector2(-70, -98), Vector2(-46, -94), 5, Color("#8a6a3a"))
	_hand(Vector2(-56, -95), 4, bone, Vector2(0, -1))


func _zombie() -> void:
	var skin := Color("#93ab7a")
	var dark := Color("#6e8a58")
	var cloth := Color("#5a4a6a")
	var pants := Color("#3e4a5a")
	var back_y := -82 + sin(_t * 1.6 + 1.0) * 5.0
	_limb3(Vector2(18, -92), Vector2(-14, -86), Vector2(-46, back_y), 11, 9, dark)
	_hand(Vector2(-48, back_y), 5.5, dark)
	_limb3(Vector2(10, -38), Vector2(16, -20), Vector2(12, -6), 12, 10, pants.darkened(0.2))
	_shape([2, -8, 20, -8, 22, 0, 0, 0], Color("#3a2a1a"))
	_limb3(Vector2(-10, -38), Vector2(-16, -20), Vector2(-20, -6), 12, 10, pants)
	_shape([-30, -6, -14, -6, -12, 0, -32, 0], dark)
	_shape([-28, -100, 26, -104, 32, -64, 30, -34, 16, -26, 6, -34, -6, -24, -18, -34, -32, -30, -34, -64], cloth)
	_flat_ellipse(Vector2(6, -66), 10, 14, Color(skin, 0.9))
	for i in 3:
		draw_line(Vector2(-2, -74 + i * 7), Vector2(14, -74 + i * 7), dark, 2.0)
	for i in 4:
		draw_line(Vector2(-22 + i * 4, -84), Vector2(-20 + i * 4, -78), OUT, 1.5)
	draw_line(Vector2(-24, -81), Vector2(-8, -81), OUT, 1.5)
	_shape([-24, -136, -12, -152, 10, -150, 22, -132, 16, -110, -4, -104, -20, -112], skin)
	draw_line(Vector2(-18, -146), Vector2(12, -140), OUT, 2.0)
	for x in [-14, -6, 2, 10]:
		draw_line(Vector2(x, -148), Vector2(x + 2, -138), OUT, 1.5)
	_eye(Vector2(-12, -128), 8, Color("#c84040"), Vector2(-1, 0.3))
	draw_line(Vector2(2, -134), Vector2(14, -122), OUT, 3.0)
	draw_line(Vector2(2, -122), Vector2(14, -134), OUT, 3.0)
	_fill(_smooth([-18, -116, -2, -112, 8, -116, 4, -108, -14, -106]), Color("#3a2020"))
	_teeth(Vector2(-14, -114), Vector2(4, -113), 3, 3.0)
	var front_y := -94 + sin(_t * 1.6) * 6.0
	_limb3(Vector2(-24, -92), Vector2(-48, -94), Vector2(-74, front_y), 11, 9, skin)
	_hand(Vector2(-76, front_y), 5.5, skin)


func _vampire() -> void:
	var cape := Color("#1c0a14")
	var inner := Color("#8b1a2e")
	var skin := Color("#e9ddd8")
	var suit := Color("#2a2a3a")
	var sway := sin(_t * 1.8) * 6.0
	_shape([-30, -120, 30, -120, 58 + sway * 0.6, -40, 66 + sway, 0, 20, -6, 0, 2, -20, -6, -66 + sway, 0, -56 + sway, -40], cape)
	_shape([-22, -112, 22, -112, 44 + sway * 0.6, -30, 46 + sway, -4, 0, -10, -44 + sway, -4, -42 + sway, -30], inner, false)
	_limb3(Vector2(-8, -50), Vector2(-10, -26), Vector2(-12, -4), 10, 9, suit)
	_limb3(Vector2(8, -50), Vector2(10, -26), Vector2(12, -4), 10, 9, suit.darkened(0.2))
	_shape([-22, -2, -6, -6, -4, 0, -24, 1], Color("#111111"))
	_shape([6, -6, 22, -2, 24, 1, 4, 0], Color("#111111"))
	_shape([-20, -108, 20, -108, 18, -50, 0, -44, -18, -50], suit)
	_shape([-9, -106, 9, -106, 0, -72], Color("#f0f0f0"))
	_ellipse(Vector2(0, -98), 4, 4, inner)
	_shape([-24, -110, -46, -150, -30, -150, -10, -116], inner)
	_shape([24, -110, 46, -150, 30, -150, 10, -116], inner)
	_shape([-18, -124, -20, -142, -6, -152, 10, -150, 20, -138, 16, -118, 0, -110, -14, -114], skin)
	_poly([-18, -136, -26, -148, -16, -142], skin)
	_fill(PackedVector2Array([Vector2(-22, -136), Vector2(-20, -152), Vector2(-4, -160), Vector2(12, -158), Vector2(22, -146),
			Vector2(20, -136), Vector2(10, -146), Vector2(0, -138), Vector2(-10, -146)]), Color("#111018"))
	_glow_eye(Vector2(-8, -130), 3.2, Color("#ff2a2a"))
	_glow_eye(Vector2(8, -130), 3.2, Color("#ff2a2a"))
	_brow(Vector2(-14, -136), Vector2(-3, -133), 3)
	_brow(Vector2(14, -136), Vector2(3, -133), 3)
	draw_line(Vector2(-7, -118), Vector2(7, -118), Color("#6a2030"), 2.0)
	_teeth(Vector2(-6, -118), Vector2(-2, -118), 1, 5.0, false, Color.WHITE)
	_teeth(Vector2(2, -118), Vector2(6, -118), 1, 5.0, false, Color.WHITE)
	_limb3(Vector2(-18, -102), Vector2(-34, -84), Vector2(-46, -92), 9, 8, suit)
	_hand(Vector2(-48, -93), 4.5, skin, Vector2(-1, -0.4), Color("#2a1a2a"))


func _werewolf() -> void:
	var fur := Color("#7a5a3c")
	var dark := Color("#4e3826")
	var light := Color("#b08a64")
	var wag := sin(_t * 3.0) * 8.0
	_shape([24, -54, 52, -74 + wag, 64, -66 + wag, 40, -44], dark)
	_limb3(Vector2(30, -104), Vector2(46, -76), Vector2(44, -50), 15, 12, dark)
	_hand(Vector2(44, -46), 7, dark, Vector2(0, 1), IVORY)
	_limb3(Vector2(12, -44), Vector2(26, -24), Vector2(16, -6), 17, 10, dark)
	_shape([4, -8, 26, -8, 30, 0, 2, 0], dark)
	_limb3(Vector2(-12, -44), Vector2(-4, -24), Vector2(-18, -6), 17, 10, fur)
	_shape([-34, -8, -12, -8, -8, 0, -36, 0], fur)
	_teeth(Vector2(-36, -1), Vector2(-26, -1), 2, 4.0, false, IVORY)
	_shape([-30, -100, -6, -116, 26, -110, 40, -84, 34, -52, 14, -38, -16, -40, -34, -60], fur)
	_shape([-20, -96, 2, -104, 12, -84, 6, -54, -12, -48, -24, -70], light, false)
	_strokes(Vector2(4, -80), 26, 30, 22, dark, 6.0, 1.8)
	_poly([-14, -150, -22, -180, -2, -158], fur)
	_poly([8, -152, 18, -182, 24, -150], fur)
	_poly([-14, -154, -18, -172, -6, -158], Color("#c88a7a"), false)
	_shape([-24, -136, -14, -156, 10, -158, 26, -142, 22, -122, 4, -114, -16, -118], fur)
	_shape([-20, -136, -46, -132, -52, -122, -40, -114, -18, -118], light)
	_ellipse(Vector2(-50, -128), 5, 4, OUT)
	_fill(_smooth([-46, -118, -22, -114, -20, -108, -42, -110]), Color("#3a1a1a"))
	_teeth(Vector2(-44, -118), Vector2(-24, -116), 4, 4.0)
	_glow_eye(Vector2(-14, -138), 3.5, Color("#ffd23f"))
	_glow_eye(Vector2(2, -140), 3.5, Color("#ffd23f"))
	_brow(Vector2(-20, -146), Vector2(-8, -142), 4)
	_strokes(Vector2(4, -142), 12, 10, 8, dark, 5.0, 2.2)
	_limb3(Vector2(-26, -100), Vector2(-48, -82), Vector2(-62, -64), 15, 12, fur)
	_hand(Vector2(-64, -62), 7, fur, Vector2(-0.6, 0.8), IVORY)


func _demon() -> void:
	var skin := Color("#c43a2b")
	var dark := Color("#7a1f17")
	var wing := Color("#5a1410")
	var flap := sin(_t * 2.4) * 10.0
	_shape([14, -100, 70, -158 + flap, 96, -150 + flap, 84, -126 + flap * 0.5, 100, -104 + flap * 0.3, 70, -98, 30, -76], wing)
	for tip in [Vector2(70, -158 + flap), Vector2(84, -126 + flap * 0.5), Vector2(100, -104 + flap * 0.3)]:
		draw_line(Vector2(24, -96), tip, OUT, 2.0)
	var swish := sin(_t * 2.6) * 12.0
	_limb3(Vector2(26, -40), Vector2(66, -48), Vector2(82 + swish, -86), 8, 5, dark)
	_poly([82 + swish, -88, 72 + swish, -102, 96 + swish, -106], dark)
	_limb3(Vector2(12, -44), Vector2(22, -24), Vector2(16, -8), 14, 10, dark)
	_shape([6, -10, 24, -10, 22, 0, 8, 0], OUT)
	_limb3(Vector2(-12, -44), Vector2(-18, -24), Vector2(-14, -8), 14, 10, skin)
	_shape([-24, -10, -6, -10, -8, 0, -22, 0], OUT)
	_shape([-30, -96, -8, -110, 22, -106, 34, -80, 26, -50, 10, -36, -14, -36, -30, -56], skin)
	draw_arc(Vector2(-4, -82), 14, 0.4, 2.7, 10, dark, 2.5, true)
	draw_line(Vector2(-2, -96), Vector2(-2, -50), dark, 2.0)
	for y in [-62, -52]:
		draw_line(Vector2(-14, y), Vector2(10, y), dark, 2.0)
	_shape([-28, -40, 26, -40, 22, -26, -24, -26], Color("#2a1010"))
	_poly([-20, -132, -34, -150, -42, -178, -27, -153, -8, -138], IVORY)
	_poly([6, -138, 16, -132, 32, -150, 36, -180, 22, -154], IVORY)
	_shape([-22, -126, -16, -144, 4, -148, 20, -136, 18, -116, 2, -108, -16, -112], skin)
	_poly([-18, -128, -6, -124, -16, -120], Color("#ffe04a"), false)
	_poly([14, -128, 2, -124, 12, -120], Color("#ffe04a"), false)
	draw_circle(Vector2(-12, -124), 6, Color(1, 0.9, 0.3, 0.25))
	draw_circle(Vector2(8, -124), 6, Color(1, 0.9, 0.3, 0.25))
	_fill(_smooth([-14, -116, 0, -112, 12, -116, 6, -110, -10, -110]), Color("#2a0a0a"))
	_teeth(Vector2(-12, -115), Vector2(10, -115), 4, 3.0)
	_poly([-4, -110, 4, -110, 0, -100], dark)
	_limb3(Vector2(-26, -94), Vector2(-46, -80), Vector2(-56, -66), 12, 10, skin)
	_hand(Vector2(-58, -64), 6, skin, Vector2(-0.6, -0.8), OUT)
	var f := 1.0 + sin(_t * 12.0) * 0.12
	draw_circle(Vector2(-66, -74), 20 * f, Color(1, 0.4, 0.05, 0.25))
	draw_circle(Vector2(-66, -74), 12 * f, Color(1, 0.65, 0.1, 0.8))
	draw_circle(Vector2(-66, -76), 6 * f, Color(1, 0.95, 0.6))


func _giant() -> void:
	var skin := Color("#d1a77d")
	var tunic := Color("#6b5a3a")
	var beard := Color("#6a4424")
	var sway := sin(_t * 1.4) * 0.06
	var bob := sin(_t * 2.2) * 2.5
	_limb3(Vector2(46, -176), Vector2(66, -130), Vector2(62, -90), 22, 17, skin.darkened(0.12))
	_hand(Vector2(62, -84), 10, skin.darkened(0.12), Vector2(0, 1))
	_limb3(Vector2(22, -66), Vector2(28, -36), Vector2(26, -10), 26, 22, skin.darkened(0.12))
	_shape([10, -16, 42, -16, 46, 0, 8, 0], Color("#4a3a26"))
	_limb3(Vector2(-22, -66), Vector2(-28, -36), Vector2(-26, -10), 26, 22, skin)
	_shape([-46, -16, -12, -16, -8, 0, -48, 0], Color("#4a3a26"))
	_shape([-50, -192, -10, -204, 40, -196, 58, -150, 60, -96, 48, -62, -48, -62, -60, -100, -58, -150], tunic)
	_shape([-30, -150, 30, -150, 40, -100, 0, -88, -40, -100], skin, false)
	_shape([-58, -100, 58, -100, 58, -84, -58, -84], Color("#3a2a1a"))
	_shape([-8, -100, 8, -100, 8, -84, -8, -84], Color("#c9a227"))
	_shape([-34, -136, -14, -136, -14, -116, -34, -116], tunic.lightened(0.15))
	for p in [Vector2(-32, -134), Vector2(-16, -134), Vector2(-32, -118), Vector2(-16, -118)]:
		draw_circle(p, 1.5, OUT)
	_shape([-28, -236, -18, -256, 6, -262, 26, -252, 30, -226, 18, -206, -20, -206], skin)
	_ellipse(Vector2(-27, -226), 6, 9, skin)
	_shape([-30, -218, -26, -194, -10, -172, 6, -170, 22, -190, 28, -216, 12, -206, -16, -206], beard)
	_strokes(Vector2(-2, -196), 18, 16, 12, beard.darkened(0.3), 8.0, 1.6)
	_shape([-18, -224, -4, -228, -6, -214, -18, -214], skin.darkened(0.06))
	_eye(Vector2(-12, -236), 5.5, Color("#3a6ab0"))
	_eye(Vector2(10, -237), 5.5, Color("#3a6ab0"))
	_brow(Vector2(-22, -246), Vector2(-4, -242), 6)
	_brow(Vector2(20, -247), Vector2(4, -243), 6)
	draw_set_transform(Vector2(0, bob), sway + lean, Vector2(1.0 + squash, 1.0 - squash))
	_limb(Vector2(-76, -118), Vector2(-90, -228), 12, WOOD)
	_shape([-74, -230, -82, -262, -100, -264, -108, -232, -96, -214], WOOD.darkened(0.1))
	for s in [Vector2(-104, -250), Vector2(-78, -248), Vector2(-92, -264)]:
		_poly([s.x - 3, s.y, s.x + 3, s.y, s.x, s.y - 9], STEEL)
	draw_set_transform(Vector2(0, bob), lean, Vector2(1.0 + squash, 1.0 - squash + sin(_t * 2.2) * 0.015))
	_limb3(Vector2(-44, -186), Vector2(-66, -150), Vector2(-76, -120), 22, 17, skin)
	_hand(Vector2(-78, -116), 10, skin, Vector2(0, -1))


func _dragon() -> void:
	var red := Color("#b83a2e")
	var dark := Color("#7a2018")
	var belly := Color("#e8b04a")
	var wing := Color("#8a2a20")
	var flap := sin(_t * 3.2) * 22.0
	_shape([10, -80, 58, -150 + flap, 76, -176 + flap, 84, -132 + flap * 0.6, 112, -142 + flap * 0.8, 108, -108 + flap * 0.4,
			124, -96, 70, -70], wing)
	for tip in [Vector2(76, -176 + flap), Vector2(112, -142 + flap * 0.8), Vector2(124, -96)]:
		_limb(Vector2(22, -84), tip, 3, dark)
	_limb3(Vector2(40, -36), Vector2(86, -18), Vector2(116, -44), 18, 8, red)
	for k in 4:
		var p := Vector2(52 + k * 18, -34 + absf(k - 1.5) * 4)
		_poly([p.x - 5, p.y, p.x + 5, p.y, p.x, p.y - 10], dark)
	_poly([112, -46, 132, -64, 124, -36], dark)
	_limb3(Vector2(34, -40), Vector2(44, -22), Vector2(36, -6), 18, 13, dark)
	_hand(Vector2(36, -4), 6, dark, Vector2(-1, 0.2), IVORY)
	_shape([-46, -70, -10, -92, 40, -90, 64, -66, 54, -34, 10, -26, -40, -34, -54, -50], red)
	_shape([-44, -52, -20, -66, 20, -64, 34, -44, 0, -32, -36, -36], belly, false)
	for k in 4:
		draw_arc(Vector2(-6 + k * 12, -48), 14, 0.6, 2.5, 8, Color(belly.darkened(0.25), 0.7), 2.0)
	for k in 5:
		for m in 2:
			draw_arc(Vector2(-10 + k * 14, -80 + m * 10), 6, PI + 0.3, TAU - 0.3, 6, dark, 2.0)
	_limb3(Vector2(-26, -40), Vector2(-20, -22), Vector2(-30, -6), 18, 13, red)
	_hand(Vector2(-32, -4), 6, red, Vector2(-1, 0.2), IVORY)
	var neck := sin(_t * 1.5) * 4.0
	_limb3(Vector2(-30, -74), Vector2(-46, -104), Vector2(-60, -122 + neck), 30, 22, red)
	for k in 3:
		var p := Vector2(-28 - k * 12, -98 - k * 12)
		_poly([p.x - 4, p.y, p.x + 6, p.y - 2, p.x + 4, p.y - 12], dark)
	_poly([-52, -138 + neck, -28, -168 + neck, -36, -134 + neck], IVORY)
	_poly([-64, -140 + neck, -52, -170 + neck, -56, -136 + neck], IVORY)
	_shape([-48, -138 + neck, -66, -142 + neck, -96, -132 + neck, -108, -120 + neck, -100, -112 + neck, -64, -108 + neck,
			-46, -116 + neck], red)
	_shape([-60, -112 + neck, -96, -112 + neck, -92, -102 + neck, -64, -102 + neck], dark)
	_teeth(Vector2(-96, -112 + neck), Vector2(-66, -112 + neck), 5, 4.0)
	_poly([-70, -132 + neck, -56, -134 + neck, -60, -124 + neck], Color("#ffd24a"), false)
	draw_line(Vector2(-63, -133 + neck), Vector2(-63, -125 + neck), OUT, 2.0)
	_brow(Vector2(-74, -136 + neck), Vector2(-54, -140 + neck), 4)
	draw_circle(Vector2(-102, -122 + neck), 2.5, OUT)
	var puff := fmod(_t, 1.6) / 1.6
	draw_circle(Vector2(-112 - puff * 20, -128 - puff * 18 + neck), 4 + puff * 6, Color(0.6, 0.6, 0.6, 0.5 * (1.0 - puff)))


func _slime() -> void:
	var goo := Color("#5fd35a")
	var deep := Color("#2f8a3a")
	var w := sin(_t * 3.0)
	var w2 := sin(_t * 3.0 + 1.2)
	_flat_ellipse(Vector2(-2, -2), 52 + w * 3, 7, Color(deep, 0.85))
	_shape([-46 - w * 3, -2, -52 - w * 2, -28, -38, -62 + w2 * 3, -10, -80 + w * 4, 20, -76 + w2 * 3, 42, -52, 50 + w * 3, -22,
			40, -2, 0, 1], goo)
	_flat_ellipse(Vector2(10, -30), 26, 18, Color(deep, 0.35))
	# things it swallowed: a bone and a coin
	draw_line(Vector2(6, -30), Vector2(28, -20), Color(IVORY, 0.55), 5.0, true)
	for e in [Vector2(6, -30), Vector2(28, -20)]:
		draw_circle(e + Vector2(0, -3), 3.5, Color(IVORY, 0.55))
		draw_circle(e + Vector2(0, 3), 3.5, Color(IVORY, 0.55))
	draw_circle(Vector2(-20, -16), 5.5, Color(1, 0.85, 0.3, 0.6))
	for k in 4:  # bubbles rising inside
		var ph := fmod(_t * 0.45 + k * 0.25, 1.0)
		var p := Vector2(-22 + k * 16 + sin(_t + k) * 3, lerpf(-8, -66, ph))
		draw_arc(p, 2.5 + (k % 2) * 2, 0, TAU, 12, Color(1, 1, 1, 0.45 * (1.0 - ph)), 1.5, true)
	_flat_ellipse(Vector2(-24, -60 + w2 * 3), 11, 6, Color(1, 1, 1, 0.45))
	draw_circle(Vector2(-8, -70 + w * 3), 3, Color(1, 1, 1, 0.6))
	_eye(Vector2(-24, -48 + w2 * 2), 9, Color("#1a3a1a"))
	_eye(Vector2(0, -52 + w * 2), 7.5, Color("#1a3a1a"))
	_fill(_smooth([-34, -32, -16, -28, -2, -32, -8, -22, -26, -22]), Color("#1e4a22"))
	var drip := fmod(_t * 0.6, 1.0)  # slime drooling from the mouth
	draw_line(Vector2(-28, -26), Vector2(-28, -26 + drip * 18), Color(goo, 1.0 - drip), 4.0, true)
	draw_circle(Vector2(-28, -24 + drip * 20), 3.5 * (1.0 - drip * 0.5), Color(goo.lightened(0.1), 1.0 - drip))


func _wraith() -> void:
	var robe := Color("#3c4a68")
	var dark := Color("#232b3e")
	var ghost := Color("#9fd8ff")
	var bone := Color("#c8d4e0")
	var s := sin(_t * 2.5)
	# floats above the ground (the shadow stays put)
	draw_set_transform(Vector2(0, sin(_t * 2.2) * 2.5 - 14 + sin(_t * 1.7) * 6), lean,
			Vector2(1.0 + squash, 1.0 - squash + sin(_t * 2.2) * 0.015))
	for k in 5:  # wisps trailing off the hem
		var ph := fmod(_t * 0.6 + k / 5.0, 1.0)
		draw_circle(Vector2(-30 + k * 15 + sin(_t * 2.0 + k) * 4, 4 + ph * 16), 7.0 * (1.0 - ph), Color(ghost, 0.25 * (1.0 - ph)))
	_limb3(Vector2(16, -106), Vector2(34, -86), Vector2(40, -70), 12, 9, dark)
	_hand(Vector2(40, -68), 4.5, bone, Vector2(0.2, 1), bone)
	draw_line(Vector2(42, -64), Vector2(44, -48), Color("#8a8f98"), 2.0)  # chain to a ghost lantern
	_poly([36, -48, 52, -48, 50, -30, 38, -30], Color("#5d626b"))
	var f := 0.85 + 0.15 * sin(_t * 7.0)
	draw_circle(Vector2(44, -39), 14 * f, Color(ghost, 0.2))
	draw_circle(Vector2(44, -39), 5 * f, Color(ghost, 0.9))
	_shape([-24, -112, 22, -114, 34, -70, 40 + s * 4, -24, 30, -4 + s * 3, 18, -16, 8, 0 - s * 3, -4, -14, -16, -2 + s * 3,
			-28, -16, -38 + s * 4, -6, -34, -64], robe)
	_shape([-12, -104, 10, -104, 14, -40, 4, -20, -8, -34, -16, -60], dark, false)
	for k in 3:
		draw_line(Vector2(-22 + k * 4, -96 + k * 18), Vector2(20 - k * 2, -94 + k * 18), Color(robe.darkened(0.3), 0.8), 2.0)
	_shape([-28, -128, -20, -150, 0, -156, 18, -146, 26, -124, 18, -104, -22, -104], robe)
	_shape([-26, -128, -16, -144, 2, -144, 10, -130, 6, -112, -20, -110], Color("#07070c"), false)
	_glow_eye(Vector2(-15, -130), 3.2, ghost)
	_glow_eye(Vector2(-1, -131), 3.2, ghost)
	var wail := 0.5 + 0.5 * sin(_t * 1.3)
	_flat_ellipse(Vector2(-9, -118), 4, 2 + wail * 3, Color(ghost, 0.35))
	var reach := sin(_t * 1.6) * 5.0
	_limb3(Vector2(-22, -106), Vector2(-44, -96), Vector2(-64, -104 + reach), 12, 9, robe)
	_hand(Vector2(-67, -104 + reach), 4.5, bone, Vector2(-1, -0.2), bone)


func _golem() -> void:
	var stone := Color("#8a8f98")
	var dark := Color("#5d626b")
	var rune := Color("#6fd8ff")
	var glow := 0.6 + 0.4 * sin(_t * 2.0)
	_shape([36, -132, 58, -124, 62, -88, 42, -92], dark)
	_shape([44, -94, 64, -90, 62, -56, 42, -58], dark)
	_shape([36, -62, 66, -62, 68, -36, 52, -28, 36, -36], dark)
	_shape([4, -52, 34, -54, 38, -4, 2, -2], dark)
	_shape([-38, -52, -6, -52, -4, -2, -42, -4], stone)
	_shape([-50, -128, -18, -150, 30, -146, 52, -118, 46, -70, 30, -46, -34, -44, -54, -74], stone)
	for seam in [[Vector2(-50, -96), Vector2(-24, -92), Vector2(-14, -70)], [Vector2(18, -146), Vector2(14, -120), Vector2(44, -104)],
			[Vector2(-10, -60), Vector2(10, -66), Vector2(28, -50)]]:
		draw_polyline(PackedVector2Array(seam), Color(0, 0, 0, 0.35), 2.5, true)
	var crack := PackedVector2Array([Vector2(-20, -134), Vector2(-8, -116), Vector2(-16, -98), Vector2(-2, -80), Vector2(-8, -62)])
	draw_polyline(crack, Color(rune, 0.25 * glow), 9.0, true)
	draw_polyline(crack, Color(rune, glow), 3.0, true)
	draw_circle(Vector2(12, -100), 14, Color(rune, 0.15 * glow))
	draw_arc(Vector2(12, -100), 10, 0, TAU, 20, Color(rune, glow), 2.5, true)
	draw_line(Vector2(12, -108), Vector2(12, -92), Color(rune, glow), 2.0)
	draw_line(Vector2(5, -100), Vector2(19, -100), Color(rune, glow), 2.0)
	for c in [[-40, -128, -30, -150, -24, -128], [24, -142, 30, -164, 38, -140], [32, -138, 44, -152, 46, -130]]:
		_poly(c, Color("#bfe6f5"))  # ice crystals growing on the shoulders
	_shape([-32, -142, -26, -168, 0, -178, 22, -168, 26, -144, 10, -132, -22, -132], stone.lightened(0.08))
	_shape([-34, -160, 6, -168, 8, -158, -32, -152], dark)  # heavy brow
	_glow_eye(Vector2(-20, -150), 3.4, rune)
	_glow_eye(Vector2(-3, -152), 3.4, rune)
	draw_line(Vector2(-22, -140), Vector2(0, -141), Color(0, 0, 0, 0.45), 2.5)
	var punch := sin(_t * 1.4) * 3.0
	var arm := stone.lightened(0.1)
	_shape([-66, -134, -40, -132, -52, -94, -78, -100], arm)
	_shape([-84, -100, -56, -94, -62, -60, -90, -64], arm.darkened(0.04))
	draw_line(Vector2(-70, -122), Vector2(-60, -108), Color(0, 0, 0, 0.35), 2.0)
	draw_polyline(PackedVector2Array([Vector2(-80, -88), Vector2(-72, -80), Vector2(-74, -70)]), Color(rune, glow), 2.5, true)
	_shape([-100, -66 + punch, -60, -66 + punch, -58, -38 + punch, -74, -28 + punch, -96, -36 + punch], arm)
	for k in 3:
		draw_line(Vector2(-92 + k * 10, -62 + punch), Vector2(-90 + k * 10, -48 + punch), Color(0, 0, 0, 0.35), 2.0)


func _yeti() -> void:
	var fur := Color("#e8f0f8")
	var shade := Color("#b8c8dc")
	var skin := Color("#5f7fa8")
	var horn := Color("#d8d0b8")
	var ice := Color("#bfe6f5")
	var heave := sin(_t * 2.0) * 3.0
	_limb3(Vector2(30, -132), Vector2(56, -94), Vector2(54, -52), 26, 20, shade)
	_strokes(Vector2(46, -96), 8, 26, 6, shade.darkened(0.2), 6.0, 1.7)
	_hand(Vector2(54, -46), 10, skin.darkened(0.15), Vector2(0, 1), IVORY)
	_limb3(Vector2(16, -50), Vector2(26, -28), Vector2(20, -8), 26, 20, shade)
	_shape([6, -12, 36, -12, 40, 0, 4, 0], skin.darkened(0.25))
	_limb3(Vector2(-16, -50), Vector2(-22, -28), Vector2(-24, -8), 26, 20, fur)
	_shape([-46, -12, -14, -12, -10, 0, -48, 0], skin.darkened(0.1))
	_shape([-44, -132 + heave, -10, -156 + heave, 30, -150 + heave, 50, -118, 48, -74, 40, -52, 30, -46, 18, -54, 6, -44, -8, -54,
			-22, -44, -34, -54, -46, -80], fur)
	_shape([-30, -116, 8, -122, 22, -90, 10, -64, -22, -62, -34, -86], skin.lightened(0.25), false)
	_strokes(Vector2(10, -100), 34, 40, 26, shade, 7.0, 1.8)
	for p in [Vector2(-40, -78), Vector2(30, -50), Vector2(-20, -50)]:
		_poly([p.x - 4, p.y, p.x + 4, p.y, p.x, p.y + 12], ice)
	_limb3(Vector2(-14, -176 + heave), Vector2(6, -196 + heave), Vector2(-4, -212 + heave), 10, 4, horn)
	_limb3(Vector2(-36, -176 + heave), Vector2(-50, -198 + heave), Vector2(-38, -212 + heave), 10, 4, horn)
	_shape([-52, -150 + heave, -46, -176 + heave, -20, -188 + heave, 8, -180 + heave, 16, -158 + heave, 6, -136 + heave,
			-38, -132 + heave], fur)
	_shape([-54, -154 + heave, -44, -170 + heave, -22, -170 + heave, -14, -152 + heave, -22, -136 + heave, -46, -136 + heave], skin)
	_glow_eye(Vector2(-42, -160 + heave), 3.5, Color("#9fe8ff"))
	_glow_eye(Vector2(-26, -161 + heave), 3.5, Color("#9fe8ff"))
	_brow(Vector2(-50, -168 + heave), Vector2(-36, -164 + heave), 5)
	_brow(Vector2(-32, -165 + heave), Vector2(-18, -169 + heave), 5)
	_fill(_smooth([-52, -148 + heave, -36, -146 + heave, -22, -150 + heave, -28, -138 + heave, -46, -138 + heave]),
			Color("#2a1a2a"))
	_teeth(Vector2(-48, -148 + heave), Vector2(-26, -149 + heave), 4, 3.5)
	_teeth(Vector2(-46, -139 + heave), Vector2(-30, -139 + heave), 2, 6.0, true)
	var puff := fmod(_t, 1.8) / 1.8  # frosty breath
	for k in 2:
		var q := fmod(puff + k * 0.5, 1.0)
		draw_circle(Vector2(-60 - q * 30, -144 - q * 10 + heave), 5 + q * 9, Color(0.8, 0.95, 1.0, 0.45 * (1.0 - q)))
	_limb3(Vector2(-30, -128 + heave), Vector2(-60, -100), Vector2(-72, -62), 26, 20, fur)
	_strokes(Vector2(-56, -96), 8, 22, 6, shade, 6.0, 1.4)
	_poly([-66, -76, -58, -76, -62, -62], ice)
	_hand(Vector2(-74, -56), 10, skin, Vector2(-0.2, 1), IVORY)


func _lich() -> void:
	var robe := Color("#3a1f5a")
	var cape := Color("#22102e")
	var trim := Color("#c9a227")
	var bone := Color("#e6dfc8")
	var magic := Color("#b06bff")
	var green := Color("#7dff9a")
	var sway := sin(_t * 1.6) * 6.0
	_shape([-26, -132, 26, -134, 50, -60, 58 + sway, -2, 30, -10, 14, 0, -6, -10, -24, 0, -40, -8, -48 + sway, -2, -42, -60], cape)
	_limb(Vector2(40, -4), Vector2(40, -186), 6, WOOD.darkened(0.35))
	for k in [-1, 1]:  # claws holding the orb
		_limb3(Vector2(40, -184), Vector2(40 + k * 12, -196), Vector2(40 + k * 6, -210), 4, 2, trim)
	var pulse := 0.8 + 0.2 * sin(_t * 3.0)
	draw_circle(Vector2(40, -200), 24 * pulse, Color(magic, 0.15))
	draw_circle(Vector2(40, -200), 12 * pulse, Color(magic, 0.5))
	draw_circle(Vector2(40, -200), 6, Color(1, 0.9, 1, 0.95))
	_limb3(Vector2(18, -122), Vector2(34, -108), Vector2(40, -100), 12, 10, robe.darkened(0.2))
	_hand(Vector2(40, -100), 5, bone, Vector2(-1, 0))
	_shape([-24, -128, 22, -130, 34, -60, 38, -2, -38, -2, -34, -60], robe)
	_shape([-7, -118, 7, -118, 9, -2, -9, -2], trim)
	for y in [-92, -60, -28]:  # runes stitched into the trim
		draw_arc(Vector2(0, y), 4, 0, TAU, 10, Color(magic, 0.9), 1.5, true)
	for i in 3:
		var y := -116.0 + i * 8
		draw_arc(Vector2(0, y - 4), 14 - i * 2, 0.3, PI - 0.3, 10, OUT, 6.0, true)
		draw_arc(Vector2(0, y - 4), 14 - i * 2, 0.3, PI - 0.3, 10, bone, 3.0, true)
	_shape([-28, -84, 26, -84, 26, -76, -28, -76], trim)
	_ellipse(Vector2(-2, -80), 5, 5, green)
	for side in [-1, 1]:  # spiked bone pauldrons
		var c := Vector2(23 * side, -126)
		_poly([c.x - 8, c.y - 4, c.x + 2 * side, c.y - 22, c.x + 8, c.y - 4], bone)
		_ellipse(c, 14, 9, robe.lightened(0.15))
	_shape([-22, -152, -16, -170, 2, -176, 18, -168, 20, -150, 12, -138, -16, -138], bone)
	_fill(_smooth([-18, -160, -8, -162, -6, -152, -16, -150]), OUT, false)
	_fill(_smooth([0, -162, 10, -160, 8, -150, -2, -152]), OUT, false)
	_glow_eye(Vector2(-12, -156), 3.0, green)
	_glow_eye(Vector2(4, -156), 3.0, green)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, -146), Vector2(0, -146), Vector2(-3, -152)]), OUT)
	var jaw := absf(sin(_t * 5.0)) * 2.5 if fmod(_t, 4.0) < 1.0 else 0.0
	_shape([-14, -140 + jaw, 10, -140 + jaw, 8, -132 + jaw, -12, -132 + jaw], bone)
	for x in [-8, -3, 2]:
		draw_line(Vector2(x, -140 + jaw), Vector2(x, -135 + jaw), OUT, 1.5)
	_poly([-22, -164, -24, -186, -14, -174, -6, -192, 2, -176, 10, -190, 14, -172, 22, -182, 20, -162], trim)
	_ellipse(Vector2(-6, -172), 3, 3, Color("#ff3a5a"))
	var cast := sin(_t * 2.2) * 4.0
	_limb3(Vector2(-20, -122), Vector2(-42, -104), Vector2(-56, -114 + cast), 13, 11, robe)
	_hand(Vector2(-60, -116 + cast), 5, bone, Vector2(-0.4, -1), bone)
	var orb := Vector2(-70, -136 + cast)
	draw_circle(orb, 16 * pulse, Color(green, 0.18))
	draw_circle(orb, 8, Color(green, 0.7))
	draw_circle(orb, 3.5, Color(1, 1, 1, 0.9))
	for k in 3:  # runes circling the spell
		var a := _t * 2.0 + k * TAU / 3
		var p := orb + Vector2(cos(a) * 20, sin(a) * 8)
		draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(green, 0.8))


# ------------------------------------------------------------------ heroes (face right)

func _warrior() -> void:
	var steel := Color("#a7b1bd")
	var dark := Color("#5d6873")
	var skin := Color("#f0c8a0")
	var cape := Color("#8b1a2e")
	var cape_sway := sin(_t * 1.8) * 4.0
	_shape([-18, -100, 14, -100, 18, -60, 10 + cape_sway, -14, -26 + cape_sway, -16, -30, -60], cape)
	_poly([-30, -46, -36, -138, -30, -152, -24, -138], Color("#dfe4ea"))
	draw_line(Vector2(-30, -50), Vector2(-30, -136), Color(1, 1, 1, 0.6), 1.5)
	_limb(Vector2(-42, -50), Vector2(-18, -44), 6, Color("#c9a227"))
	_limb3(Vector2(-14, -92), Vector2(-26, -70), Vector2(-30, -50), 11, 9, steel.darkened(0.15))
	_hand(Vector2(-30, -48), 5, Color("#6b4a2a"), Vector2(0, -1))
	_limb3(Vector2(-8, -40), Vector2(-12, -22), Vector2(-12, -6), 12, 10, dark)
	_limb3(Vector2(10, -40), Vector2(14, -22), Vector2(14, -6), 12, 10, dark)
	_shape([-20, -8, -2, -8, 0, 0, -22, 0], Color("#4a3a2a"))
	_shape([6, -8, 24, -8, 26, 0, 4, 0], Color("#4a3a2a"))
	_shape([-20, -44, 20, -44, 24, -26, 0, -22, -24, -26], Color("#8a93a0"))
	for k in 4:
		draw_arc(Vector2(-12 + k * 8, -34), 4, 0, PI, 6, OUT, 1.2)
	_shape([-22, -96, 22, -96, 26, -66, 20, -44, -20, -44, -26, -66], steel)
	draw_line(Vector2(0, -92), Vector2(0, -50), dark, 2.0)
	_shape([-24, -50, 24, -50, 24, -42, -24, -42], Color("#6b4a2a"))
	_ellipse(Vector2(0, -46), 5, 5, Color("#c9a227"))
	_shape([-30, -100, -8, -104, -6, -88, -24, -82, -34, -88], steel.lightened(0.05))
	_shape([10, -104, 30, -100, 34, -88, 24, -82, 8, -88], steel.lightened(0.05))
	for r in [Vector2(-22, -94), Vector2(22, -94)]:
		_rivet(r)
	_ellipse(Vector2(4, -112), 14, 14, skin)
	_eye(Vector2(12, -113), 2.6, Color("#3a6ab0"), Vector2(1, 0))
	draw_line(Vector2(17, -110), Vector2(19, -106), OUT, 2.0)
	draw_line(Vector2(8, -103), Vector2(14, -103), OUT, 1.5)
	_shape([-14, -102, -18, -122, -6, -136, 12, -134, 20, -124, 20, -119, 4, -120, -2, -106], steel)
	_limb(Vector2(4, -121), Vector2(20, -121), 3, steel.darkened(0.2))
	_rivet(Vector2(-8, -122))
	var flutter := sin(_t * 5.0) * 4.0
	_shape([0, -136, -14, -150 + flutter, -34, -146 + flutter, -26, -132, -10, -128], Color("#c0392b"))
	_shape([10, -96, 40, -92, 44, -64, 28, -36, 12, -60], Color("#2f5d9a"))
	_poly([24, -84, 32, -76, 24, -58, 16, -76], Color("#ffd24a"))
	_rivet(Vector2(26, -90))
	_limb3(Vector2(16, -88), Vector2(26, -72), Vector2(22, -60), 10, 8, steel)


func _rogue() -> void:
	var cloak := Color("#2f4f3a")
	var dark := Color("#1d3326")
	var leather := Color("#6b4a2a")
	var tail := sin(_t * 2.0) * 5.0
	_shape([-20, -96, 16, -98, 24, -40, 14 + tail, -10, -10 + tail, -20, -30 + tail, -6, -26, -50], cloak.darkened(0.15))
	_limb3(Vector2(-12, -84), Vector2(-26, -66), Vector2(-34, -52), 9, 8, dark)
	_hand(Vector2(-35, -50), 4.5, Color("#3a2a20"), Vector2(-1, 0.4))
	_poly([-36, -54, -58, -38, -36, -46], STEEL)
	_limb3(Vector2(-8, -42), Vector2(-14, -22), Vector2(-12, -6), 11, 9, dark)
	_limb3(Vector2(8, -42), Vector2(16, -22), Vector2(14, -6), 11, 9, dark.lightened(0.1))
	_shape([-22, -8, -4, -8, -2, 0, -24, 0], leather.darkened(0.3))
	_shape([6, -8, 24, -8, 26, 0, 4, 0], leather.darkened(0.3))
	_shape([-18, -92, 18, -92, 22, -60, 16, -40, -16, -40, -22, -60], leather)
	_limb(Vector2(-16, -88), Vector2(14, -48), 5, Color("#3a2a1a"))
	_shape([-20, -52, 20, -52, 20, -44, -20, -44], Color("#3a2a1a"))
	for x in [-12, 10]:
		_shape([x - 5, -48, x + 5, -48, x + 5, -38, x - 5, -38], leather.darkened(0.15))
	_shape([-24, -100, -10, -132, 8, -138, 24, -120, 26, -96, 12, -86, -12, -86], cloak)
	_fill(_smooth([-8, -108, 4, -120, 18, -114, 18, -98, 4, -94, -6, -98]), Color("#0e1a12"), false)
	_glow_eye(Vector2(6, -110), 2.4, Color("#9effa0"))
	_glow_eye(Vector2(14, -110), 2.4, Color("#9effa0"))
	_shape([-4, -101, 20, -102, 19, -96, -3, -95], Color("#3a2424"))
	_limb3(Vector2(12, -84), Vector2(28, -74), Vector2(38, -64), 9, 8, cloak)
	_hand(Vector2(40, -63), 4.5, Color("#3a2a20"), Vector2(1, 0))
	_poly([42, -67, 68, -74, 44, -59], STEEL)
	draw_line(Vector2(44, -66), Vector2(64, -72), Color(1, 1, 1, 0.6), 1.5)


func _cleric() -> void:
	var robe := Color("#ece8f4")
	var trim := Color("#d4a82a")
	var orb := Color("#8fd8ff")
	_limb(Vector2(-28, -4), Vector2(-28, -140), 6, WOOD)
	_shape([-36, -140, -28, -152, -20, -140, -28, -146], trim)
	var pulse := 1.0 + sin(_t * 3.0) * 0.12
	draw_circle(Vector2(-28, -156), 20 * pulse, Color(orb, 0.25))
	_ellipse(Vector2(-28, -156), 9, 9, orb)
	_shape([-30, 0, -22, -60, -16, -92, 16, -92, 22, -60, 30, 0, 10, -4, -10, -4], robe)
	for x in [-14, 12]:
		draw_line(Vector2(x * 0.7, -80), Vector2(x, -6), robe.darkened(0.2), 2.0)
	_shape([-8, -92, 8, -92, 10, -4, -10, -4], trim)
	_ellipse(Vector2(0, -66), 7, 7, Color("#fff4c0"))
	for k in 8:
		var a := k * TAU / 8
		draw_line(Vector2(0, -66) + Vector2(cos(a), sin(a)) * 8, Vector2(0, -66) + Vector2(cos(a), sin(a)) * 11, trim, 2.0)
	_shape([-30, -4, 30, -4, 30, 0, -30, 0], trim)
	_shape([14, -50, 26, -50, 26, -36, 14, -36], Color("#6b3a2a"))
	_limb3(Vector2(-12, -86), Vector2(-22, -70), Vector2(-28, -64), 10, 9, robe)
	_hand(Vector2(-28, -62), 4.5, Color("#f0c8a0"), Vector2(0, -1))
	_shape([-20, -100, -18, -124, 0, -130, 18, -124, 20, -100, 14, -92, -14, -92], robe.darkened(0.05))
	_ellipse(Vector2(2, -106), 14, 15, Color("#f0c8a0"))
	_shape([-12, -110, -8, -122, 6, -124, 16, -116, 12, -112, 0, -116], Color("#8a5a2a"))
	for ex in [7, 13]:
		if _blink > 0.0:
			draw_line(Vector2(ex - 2, -106), Vector2(ex + 2, -106), OUT, 1.5)
		else:
			draw_circle(Vector2(ex, -106), 2.0, OUT)
			draw_circle(Vector2(ex + 0.6, -106.7), 0.7, Color.WHITE)
	draw_arc(Vector2(9, -98), 4, 0.3, PI - 0.3, 8, OUT, 2.0, true)
	draw_circle(Vector2(0, -100), 3, Color(1, 0.6, 0.6, 0.35))
	draw_arc(Vector2(2, -136), 16, 0, TAU, 32, Color(trim, 0.4), 6.0, true)
	draw_arc(Vector2(2, -136), 16, 0, TAU, 32, trim, 3.0, true)


func _necromancer() -> void:
	var robe := Color("#2b1d3a")
	var trim := Color("#5a3d7a")
	var bone := Color("#e8e4d8")
	var soul := Color("#7dffb0")
	_limb(Vector2(-28, -4), Vector2(-28, -136), 6, Color("#3a3030"))
	_shape([-40, -148, -28, -158, -16, -148, -20, -136, -36, -136], bone)
	draw_circle(Vector2(-32, -146), 3, OUT)
	draw_circle(Vector2(-24, -146), 3, OUT)
	var glow := 1.0 + sin(_t * 2.5) * 0.15
	draw_circle(Vector2(-28, -148), 24 * glow, Color(soul, 0.16))
	_shape([-30, 2, -22, -50, -18, -92, 18, -92, 22, -50, 32, 2, 22, -4, 14, 2, 4, -6, -6, 2, -16, -4], robe)
	_shape([-6, -92, 6, -92, 8, -4, -8, -4], trim, false)
	for k in 3:
		_ellipse(Vector2(-12 + k * 12, -50), 4, 4, bone)
	_shape([-20, -54, 20, -54, 20, -46, -20, -46], Color("#3a2a3a"))
	_limb3(Vector2(-12, -84), Vector2(-24, -70), Vector2(-28, -64), 10, 9, robe.lightened(0.08))
	_hand(Vector2(-28, -62), 4.5, bone, Vector2(0, -1))
	_shape([-22, -100, -14, -132, 6, -140, 22, -122, 24, -96, 10, -88, -12, -88], robe.lightened(0.05))
	_fill(_smooth([-6, -104, 6, -118, 18, -110, 18, -96, 4, -92]), Color("#0c0812"), false)
	_shape([2, -112, 16, -112, 16, -98, 8, -94, 2, -100], bone)
	_glow_eye(Vector2(7, -106), 2.2, soul)
	_glow_eye(Vector2(13, -106), 2.2, soul)
	_limb3(Vector2(12, -84), Vector2(26, -74), Vector2(32, -68), 10, 9, robe.lightened(0.08))
	_hand(Vector2(34, -67), 4.5, bone, Vector2(1, 0))
	for k in 3:
		var a := _t * 2.0 + k * TAU / 3
		var c := Vector2(40, -80) + Vector2(cos(a), sin(a) * 0.5) * 16
		draw_circle(c, 6, Color(soul, 0.25))
		draw_circle(c, 3.5, Color(soul, 0.9))
