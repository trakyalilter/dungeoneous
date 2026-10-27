class_name MapView
extends Control
## Draws a RunMap on a backdrop themed after the floor: nodes bottom (start) to top (boss), curved paths between them.
## Reachable nodes pulse. Hovering a node lights up every route onward from it.
## Clicking a reachable node walks the hero token there, then emits node_chosen.
## In co-op (vote_mode) a click is a vote: node_chosen fires right away and the walk happens once the party decides.

signal node_chosen(row: int, idx: int)
signal hovered(text: String)

const COLORS := {
	"fight": Color("#7a8597"), "elite": Color("#b03a3a"), "event": Color("#6a5acd"), "shop": Color("#c9a227"),
	"rest": Color("#e07b28"), "treasure": Color("#b8862b"), "boss": Color("#8b1010"),
}
const OUT := Color("#0e0c12")
const MARGIN_X := 60.0
const MARGIN_TOP := 64.0
const MARGIN_BOTTOM := 76.0
const TOKEN_SCALE := 0.3

var map: RunMap:
	set(value):
		map = value
		_hover = [-1, -1]
		_route = {}
		_walk = -1.0
var state: GameState  # for reward previews
var vote_mode := false
var votes := {}           # co-op: slot -> [row, idx]
var party_kinds: Array = []  # co-op: class of every hero, for the extra tokens
const VOTE_COLORS := [Color("#ffd84d"), Color("#5fd7ff"), Color("#e07bff"), Color("#6ee36e")]
var floor_num := 1:
	set(value):
		floor_num = value
		_decor = _make_decor()
var hero_kind := "Warrior":
	set(value):
		hero_kind = value
		_token.setup(value)
var _t := 0.0
var _hover := [-1, -1]
var _route := {}         # "r,i" -> true for nodes reachable from the hovered node
var _decor: Array = []   # [kind, normalized position, size, variant]
var _token := Creature.new()
var _mates: Array[Creature] = []  # co-op: the other heroes standing next to yours
var _boss := Creature.new()
var _walk := -1.0        # 0..1 while the token walks to _walk_to; -1 when standing
var _walk_from := Vector2.ZERO
var _walk_to := [-1, -1]


func _ready() -> void:
	tooltip_text = " "  # enables _get_tooltip
	clip_contents = true
	add_child(_token)
	add_child(_boss)
	_token.setup(hero_kind)
	_decor = _make_decor()


## Tooltip right next to the cursor when hovering a room.
func _get_tooltip(at_position: Vector2) -> String:
	if map == null:
		return ""
	var h := _node_at(at_position)
	if h[0] < 0:
		return ""
	return _describe(h[0], h[1]) + ("\nClick to enter" if _is_reachable(h[0], h[1]) else "")


func _process(delta: float) -> void:
	_t += delta
	if map != null and size.x > 0:
		_place_creatures()
	queue_redraw()


# ------------------------------------------------------------------ layout

func _pos(r: int, i: int) -> Vector2:
	var rows := map.rows.size()
	var x: float = map.rows[r][i].x
	return Vector2(MARGIN_X + x * (size.x - 2 * MARGIN_X),
			size.y - MARGIN_BOTTOM - r * (size.y - MARGIN_TOP - MARGIN_BOTTOM) / (rows - 1))


func _start_pos() -> Vector2:
	return Vector2(size.x / 2, size.y - 8)


func _radius(r: int) -> float:
	return 34.0 if map.rows[r][0].type == "boss" else 19.0


## Where the hero token stands now.
func _token_home() -> Vector2:
	if map.pos_row < 0:
		return _start_pos()
	return _pos(map.pos_row, map.pos_idx) + Vector2(0, 8)


func _place_creatures() -> void:
	var s := TOKEN_SCALE * size.y / 560.0
	_token.scale = Vector2(s, s) * _token.size_mult()
	if _walk >= 0.0:
		var to := _pos(_walk_to[0], _walk_to[1]) + Vector2(0, 8)
		_token.position = _walk_from.lerp(to, _walk) + Vector2(0, -sin(_walk * PI) * 26)
		_token.scale.x *= -1.0 if to.x < _walk_from.x - 4 else 1.0
	else:
		_token.position = _token_home()
	_sync_mates(s)


func _sync_mates(s: float) -> void:
	var others := party_kinds.size() - 1 if vote_mode else 0
	while _mates.size() < maxi(others, 0):
		var c := Creature.new()
		add_child(c)
		move_child(c, 0)  # behind your own token
		_mates.append(c)
	while _mates.size() > maxi(others, 0):
		_mates.pop_back().queue_free()
	for k in _mates.size():
		var kind: String = party_kinds[k + 1] if k + 1 < party_kinds.size() else "Warrior"
		if _mates[k].kind != kind:
			_mates[k].setup(kind)
		_mates[k].scale = Vector2(s, s) * 0.8 * _mates[k].size_mult()
		_mates[k].position = _token.position + Vector2((k + 1) * 14 * (1 if k % 2 == 0 else -1), -4)
		_mates[k].modulate = Color(1, 1, 1, 0.85)
	var top := map.rows.size() - 1
	var b := _pos(top, 0)
	_boss.position = b + Vector2(_radius(top) + 52, _radius(top) - 2)
	_boss.scale = Vector2(s, s) * _boss.size_mult() * 1.1
	var info: Dictionary = Config.FLOOR_INFO[clampi(floor_num, 1, Config.FLOORS) - 1]
	if _boss.kind != info["boss"]:
		_boss.setup(info["boss"])


# ------------------------------------------------------------------ input

func _is_reachable(r: int, i: int) -> bool:
	for pair in map.reachable():
		if pair[0] == r and pair[1] == i:
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if map == null or _walk >= 0.0:
		return
	if event is InputEventMouseMotion:
		var h := _node_at(event.position)
		if h != _hover:
			_hover = h
			_route = _routes_from(h[0], h[1]) if h[0] >= 0 else {}
			hovered.emit(_describe(h[0], h[1]) if h[0] >= 0 else "")
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h[0] >= 0 and _is_reachable(h[0], h[1]) \
					else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var h := _node_at(event.position)
		if h[0] >= 0 and _is_reachable(h[0], h[1]):
			if vote_mode:
				node_chosen.emit(h[0], h[1])
			else:
				await walk_to(h[0], h[1])
				node_chosen.emit(h[0], h[1])


## Hop the hero token along the path to (r, i). Await it to wait for the hop.
func walk_to(r: int, i: int) -> void:
	_walk_from = _token.position
	_walk_to = [r, i]
	_walk = 0.0
	var tw := create_tween()
	tw.tween_property(self, "_walk", 1.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_walk = -1.0


func _node_at(p: Vector2) -> Array:
	for r in map.rows.size():
		for i in map.rows[r].size():
			if p.distance_to(_pos(r, i)) <= _radius(r) + 6:
				return [r, i]
	return [-1, -1]


## Every node you could still reach after entering (r, i), including itself.
func _routes_from(r: int, i: int) -> Dictionary:
	var out := {"%d,%d" % [r, i]: true}
	var frontier := [[r, i]]
	while not frontier.is_empty():
		var n: Array = frontier.pop_back()
		if n[0] >= map.rows.size() - 1:
			continue
		for l in map.rows[n[0]][n[1]].links:
			var key := "%d,%d" % [n[0] + 1, l]
			if not out.has(key):
				out[key] = true
				frontier.append([n[0] + 1, l])
	return out


func _describe(r: int, i: int) -> String:
	var t: String = map.rows[r][i].type
	var text: String = Config.NODE_NAMES[t]
	match t:
		"fight", "elite", "boss":
			var lvl := Config.node_level(floor_num, r, t)
			text += " - enemy level %d" % lvl
			if state:
				text += " - " + Progression.reward_text(state, lvl, t == "boss", t == "elite")
	var hints := {"elite": "tougher, guaranteed loot", "event": "something unexpected", "shop": "spend your gold",
			"rest": "heal or train", "treasure": "gold and an item",
			"boss": Config.FLOOR_INFO[floor_num - 1]["boss_title"]}
	if hints.has(t):
		text += " (%s)" % hints[t]
	return text


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if map == null:
		return
	var th := BattleStage.theme_for(floor_num)
	_draw_backdrop(th)
	_draw_paths()
	for r in map.rows.size():
		for i in map.rows[r].size():
			_draw_node(r, i)
	var top := map.rows.size() - 1
	var b := _pos(top, 0)
	var title: String = Config.FLOOR_INFO[floor_num - 1]["boss_title"]
	var font := UiKit.serif()
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string_outline(font, b + Vector2(-_radius(top) - 16 - w, 6), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, OUT)
	draw_string(font, b + Vector2(-_radius(top) - 16 - w, 6), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(GameLog.RED))
	if map.pos_row < 0 and _walk < 0.0:  # "start here" marker under the token
		var c := _start_pos()
		draw_arc(c + Vector2(0, -2), 16 + sin(_t * 3.0) * 2, 0, TAU, 24, Color(1, 0.85, 0.3, 0.6), 2.0, true)


func _draw_backdrop(th: Dictionary) -> void:
	var w := size.x
	var h := size.y
	for i in 16:  # floor-colored gradient, darkest at the boss end
		var k := i / 16.0
		draw_rect(Rect2(0, h * k, w, h / 16.0 + 1), Color(th["top"]).darkened(0.25).lerp(Color(th["bottom"]), k))
	var glow: Color = th["glow"]
	draw_circle(_pos(map.rows.size() - 1, 0), 120, Color(glow, 0.06))
	draw_circle(_pos(map.rows.size() - 1, 0), 70, Color(glow, 0.06))
	for d in _decor:
		_draw_decor(d[0], Vector2(d[1].x * w, d[1].y * h), d[2], d[3])
	_draw_ambient(th["fx"], glow)
	for i in 5:  # soft vignette
		draw_rect(Rect2(i * 6, i * 6, w - i * 12, h - i * 12), Color(0, 0, 0, 0.1), false, 6.0)


## Scatter props that suit the floor, keeping clear of the rooms.
func _make_decor() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_num * 7919
	var kinds: Array = [["rubble", "pillar"], ["tomb", "bones"], ["crystal", "drift"], ["pool", "crack"], ["rune", "star"]][
			clampi(floor_num, 1, 5) - 1]
	var out := []
	for i in 34:
		out.append([kinds[rng.randi() % kinds.size()], Vector2(rng.randf_range(0.03, 0.97), rng.randf_range(0.05, 0.97)),
				rng.randf_range(0.7, 1.3), rng.randi() % 3])
	return out


func _draw_decor(kind: String, p: Vector2, s: float, v: int) -> void:
	for r in map.rows.size():  # skip props that would sit under a room
		for i in map.rows[r].size():
			if p.distance_to(_pos(r, i)) < _radius(r) + 26:
				return
	var ink := Color(0, 0, 0, 0.35)
	match kind:
		"rubble":
			for k in 3:
				var q := p + Vector2((k - 1) * 9 * s, (k % 2) * 4)
				draw_rect(Rect2(q - Vector2(5, 4) * s, Vector2(10, 8) * s), Color(0.45, 0.42, 0.5, 0.35))
				draw_rect(Rect2(q - Vector2(5, 4) * s, Vector2(10, 8) * s), ink, false, 1.5)
		"pillar":
			draw_rect(Rect2(p + Vector2(-7, -30) * s, Vector2(14, 30) * s), Color(0.4, 0.38, 0.46, 0.35))
			draw_rect(Rect2(p + Vector2(-10, -34) * s, Vector2(20, 5) * s), Color(0.5, 0.48, 0.56, 0.4))
			draw_rect(Rect2(p + Vector2(-10, -2) * s, Vector2(20, 5) * s), Color(0.5, 0.48, 0.56, 0.4))
		"tomb":
			var c := Color(0.42, 0.5, 0.5, 0.4)
			draw_rect(Rect2(p + Vector2(-8, -16) * s, Vector2(16, 16) * s), c)
			draw_circle(p + Vector2(0, -16) * s, 8 * s, c)
			draw_line(p + Vector2(0, -20) * s, p + Vector2(0, -8) * s, ink, 2.0)
			draw_line(p + Vector2(-4, -15) * s, p + Vector2(4, -15) * s, ink, 2.0)
		"bones":
			var c := Color(0.85, 0.82, 0.72, 0.3)
			draw_line(p + Vector2(-8, -3) * s, p + Vector2(8, 3) * s, c, 3.0)
			draw_line(p + Vector2(-8, 3) * s, p + Vector2(8, -3) * s, c, 3.0)
			draw_circle(p + Vector2(0, -9) * s, 5 * s, c)
		"crystal":
			for k in 2 + v:
				var q := p + Vector2((k - 1) * 7 * s, 0)
				var hgt := (14 + k * 6 + v * 3) * s
				draw_colored_polygon(PackedVector2Array([q + Vector2(-4, 0) * s, q + Vector2(0, -hgt), q + Vector2(4, 0) * s]),
						Color(0.7, 0.9, 1, 0.35))
		"drift":
			draw_set_transform(p, 0.0, Vector2(1.0, 0.3))
			draw_circle(Vector2.ZERO, 16 * s, Color(0.9, 0.95, 1, 0.14))
			draw_circle(Vector2(14, 6) * s, 11 * s, Color(0.9, 0.95, 1, 0.14))
			draw_set_transform(Vector2.ZERO)
		"pool":
			var glow := 0.5 + 0.5 * sin(_t * 2.0 + v)
			draw_set_transform(p, 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 18 * s, Color(1, 0.35, 0.05, 0.18 + 0.1 * glow))
			draw_circle(Vector2.ZERO, 10 * s, Color(1, 0.6, 0.15, 0.25 + 0.15 * glow))
			draw_set_transform(Vector2.ZERO)
		"crack":
			draw_polyline(PackedVector2Array([p + Vector2(-14, 6) * s, p + Vector2(-4, -2) * s, p + Vector2(4, 4) * s,
					p + Vector2(14, -6) * s]), Color(1, 0.4, 0.1, 0.3 + 0.2 * sin(_t * 2.0 + v)), 2.0, true)
		"rune":
			var a := _t * 0.4 + v
			draw_arc(p, 12 * s, a, a + TAU * 0.8, 20, Color(0.7, 0.4, 1, 0.2), 2.0, true)
			draw_arc(p, 6 * s, -a, -a + PI, 12, Color(0.7, 0.4, 1, 0.2), 1.5, true)
		"star":
			draw_circle(p, (1.5 + v * 0.5) * s, Color(0.9, 0.8, 1, 0.3 + 0.3 * sin(_t * 2.5 + p.x)))


## Drifting particles: dust, mist, snow, embers or void motes.
func _draw_ambient(fx: String, glow: Color) -> void:
	var w := size.x
	var h := size.y
	for i in 28:
		var speed := 10.0 + (i % 5) * 4.0
		var x := fmod(i * 97.3 + sin(_t * 0.5 + i) * 14.0 + 1000.0, w)
		match fx:
			"snow":
				draw_circle(Vector2(x, fmod(i * 53.1 + _t * speed, h)), 1.2 + (i % 3) * 0.6, Color(1, 1, 1, 0.45))
			"lava":
				var y := h - fmod(i * 53.1 + _t * speed * 1.4, h)
				draw_circle(Vector2(x, y), 1.5, Color(1, 0.55, 0.2, 0.6 * y / h))
			"mist":
				if i < 6:
					draw_circle(Vector2(fmod(i * 210.0 + _t * 12.0, w + 240) - 120, h * (0.2 + i * 0.14)), 90,
							Color(0.6, 1, 0.9, 0.025))
			_:
				var y := h - fmod(i * 53.1 + _t * speed * 0.5, h)
				draw_circle(Vector2(x, y), 1.2, Color(glow.lightened(0.4), 0.25))


func _draw_paths() -> void:
	var walking_to := "%d,%d" % _walk_to if _walk >= 0.0 else ""
	if map.pos_row < 0 or walking_to != "":
		var from := _start_pos() if map.pos_row < 0 else _pos(map.pos_row, map.pos_idx)
		if walking_to != "":  # the step being taken right now
			_dots(from, _pos(_walk_to[0], _walk_to[1]), 0, Color(GameLog.YELLOW), 3.0)
	for r in map.rows.size() - 1:
		for i in map.rows[r].size():
			var node: Dictionary = map.rows[r][i]
			for l in node.links:
				var a := _pos(r, i)
				var b := _pos(r + 1, l)
				var bend: float = ((r * 7 + i * 3 + int(l) * 5) % 3 - 1) * 12.0
				if node.done and map.rows[r + 1][l].done:
					_curve_line(a, b, bend, Color(GameLog.YELLOW), 3.5)
				elif _route.has("%d,%d" % [r, i]) and _route.has("%d,%d" % [r + 1, l]):
					_dots(a, b, bend, Color(1, 0.95, 0.75, 0.85), 2.6)
				else:
					_dots(a, b, bend, Color(1, 1, 1, 0.2), 1.8)


func _bezier(a: Vector2, b: Vector2, bend: float, t: float) -> Vector2:
	var mid := (a + b) / 2 + (b - a).orthogonal().normalized() * bend
	return a.lerp(mid, t).lerp(mid.lerp(b, t), t)


func _curve_line(a: Vector2, b: Vector2, bend: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for k in 13:
		pts.append(_bezier(a, b, bend, k / 12.0))
	draw_polyline(pts, OUT, width + 3.0, true)
	draw_polyline(pts, col, width, true)


func _dots(a: Vector2, b: Vector2, bend: float, col: Color, r: float) -> void:
	var n := maxi(2, int(a.distance_to(b) / 11.0))
	for k in range(1, n):
		draw_circle(_bezier(a, b, bend, float(k) / n), r, col)


func _draw_node(r: int, i: int) -> void:
	var node: Dictionary = map.rows[r][i]
	var c := _pos(r, i)
	var rad := _radius(r)
	var reach := _is_reachable(r, i) and _walk < 0.0
	var current := r == map.pos_row and i == map.pos_idx
	var on_route := _route.has("%d,%d" % [r, i])
	if [r, i] == _hover and reach:
		rad *= 1.15
	var col: Color = COLORS[node.type]
	if node.done and not current:
		col = col.darkened(0.55)
	elif not reach and not current and not on_route:
		col = col.darkened(0.25)
	if reach:
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		draw_circle(c, rad + 8 + pulse * 4, Color(1, 0.85, 0.3, 0.18 + 0.2 * pulse))
	elif on_route and not node.done:
		draw_arc(c, rad + 5, 0, TAU, 32, Color(1, 0.95, 0.75, 0.6), 2.0, true)
	if node.type == "elite" and not node.done:  # flickering flames around elites
		for k in 8:
			var a := k * TAU / 8 + _t * 0.8
			var f := 0.7 + 0.3 * sin(_t * 9.0 + k * 1.7)
			draw_colored_polygon(PackedVector2Array([c + Vector2(cos(a - 0.2), sin(a - 0.2)) * (rad + 2),
					c + Vector2(cos(a), sin(a)) * (rad + 8 + 5 * f), c + Vector2(cos(a + 0.2), sin(a + 0.2)) * (rad + 2)]),
					Color(1, 0.4, 0.2, 0.55))
	paint_node(self, node.type, c, rad, col, node.done and not current)
	if node.done and not current:  # visited: small check mark
		draw_polyline(PackedVector2Array([c + Vector2(rad * 0.45, rad * 0.55), c + Vector2(rad * 0.7, rad * 0.8),
				c + Vector2(rad * 1.1, rad * 0.3)]), Color(GameLog.YELLOW), 3.0, true)
	if current:
		draw_arc(c, rad + 7, 0, TAU, 40, Color.WHITE, 3.0, true)
	var k := 0
	for slot in votes:  # co-op votes: one colored pip per hero around the room
		var v: Array = votes[slot]
		if v[0] == r and v[1] == i:
			var a := -PI / 2 + k * 0.7
			var p := c + Vector2(cos(a), sin(a)) * (rad + 12)
			draw_circle(p, 7, OUT)
			draw_circle(p, 5.5, VOTE_COLORS[int(slot) % VOTE_COLORS.size()])
			k += 1


## Draw one room circle with its icon on any CanvasItem (also used by the map legend).
static func paint_node(ci: CanvasItem, type: String, c: Vector2, r: float, col: Color, dim: bool) -> void:
	ci.draw_circle(c + Vector2(0, 3), r + 3, Color(0, 0, 0, 0.35))
	ci.draw_circle(c, r + 3, OUT)
	ci.draw_circle(c, r, col)
	ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.55, Color(1, 1, 1, 0.08))
	ci.draw_arc(c, r - 2, PI * 1.05, PI * 1.6, 10, Color(1, 1, 1, 0.25), 2.0, true)
	var ink := Color(1, 1, 1, 0.45 if dim else 0.95)
	var font := ThemeDB.fallback_font
	match type:
		"fight", "elite":
			var s := r * 0.55
			ci.draw_line(c + Vector2(-s, -s), c + Vector2(s, s), ink, 3.0)
			ci.draw_line(c + Vector2(s, -s), c + Vector2(-s, s), ink, 3.0)
			if type == "elite":
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.7, -r * 0.6), c + Vector2(-r * 0.95, -r * 1.25),
						c + Vector2(-r * 0.35, -r * 0.85)]), ink)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.7, -r * 0.6), c + Vector2(r * 0.95, -r * 1.25),
						c + Vector2(r * 0.35, -r * 0.85)]), ink)
		"event", "shop":
			var glyph := "?" if type == "event" else "$"
			var fs := int(r * 1.3)
			var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			ci.draw_string(font, c + Vector2(-w / 2, fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		"rest":
			var k := r / 19.0
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 8) * k, c + Vector2(0, -12) * k, c + Vector2(8, 8) * k]),
					Color(1, 0.85, 0.3, ink.a))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 8) * k, c + Vector2(0, -2) * k, c + Vector2(4, 8) * k]),
					Color(1, 1, 0.8, ink.a))
		"treasure":
			var k := r / 19.0
			ci.draw_rect(Rect2(c + Vector2(-10, -5) * k, Vector2(20, 13) * k), Color(0.45, 0.28, 0.1, ink.a))
			ci.draw_rect(Rect2(c + Vector2(-10, -9) * k, Vector2(20, 6) * k), Color(0.6, 0.38, 0.15, ink.a))
			ci.draw_rect(Rect2(c + Vector2(-2, -4) * k, Vector2(4, 5) * k), Color(1, 0.85, 0.3, ink.a))
		"boss":
			ci.draw_circle(c + Vector2(0, -r * 0.09), r * 0.55, ink)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.3, r * 0.25), Vector2(r * 0.6, r * 0.3)), ink)
			ci.draw_circle(c + Vector2(-r * 0.22, -r * 0.1), r * 0.15, OUT)
			ci.draw_circle(c + Vector2(r * 0.22, -r * 0.1), r * 0.15, OUT)
			for k in 3:
				var x := -r * 0.15 + k * r * 0.15
				ci.draw_line(c + Vector2(x, r * 0.25), c + Vector2(x, r * 0.55), OUT, 2.0)
