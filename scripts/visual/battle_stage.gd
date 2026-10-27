class_name BattleStage
extends Control
## The battle scene: dungeon backdrop, hero vs enemy, HP bars, and all combat animation.
## play(event) animates one GameLog event and returns when it is done (use with await).

const FLOOR := 0.70      # floor line, as a share of height
const FEET := 0.88       # where characters stand
const HERO_X := 0.26
const FOE_X := 0.72

var sfx: Sfx
var hero := Creature.new()         # this machine's hero
var heroes: Array[Creature] = []   # the whole party in slot order (just [hero] in solo)
var _actor: Creature               # hero the event being played is about
var _party: Array[PlayerData] = []
var _my_slot := 0
var _ready_slots: Array = []       # co-op: heroes who already picked this round's action
var _plate_hp := {}                # co-op nameplates: slot -> [hp, max_hp]
var foe := Creature.new()
var world := Node2D.new()   # everything that shakes
var shake := 0.0
var _t := 0.0
var _boxes := {}            # "player"/"enemy" -> {panel, name, bar, text}
var _max_hp := {"player": 1, "enemy": 1}
var _banner: Label
var _intent: Label
var _intent_icon: GameIcon
var _turn: Label
var _flash_rect := ColorRect.new()
var _in_hitstop := false
var _dust: CPUParticles2D
var _embers: Array[CPUParticles2D] = []
var _enemy: EnemyData
var _player: PlayerData
var _state: GameState  # for the reward preview (optional)
var floor_theme := 1  # floor number, picks the backdrop

## Backdrop per floor: wall gradient, floor, torch flame + glow, and an extra effect drawn on top.
## The map screen reuses these colors.
const THEMES := [
	{"top": "#1b1826", "bottom": "#2d2738", "floor": "#272030", "flame": "#ff9a30", "glow": Color(1, 0.6, 0.2), "fx": ""},
	{"top": "#0f1a1c", "bottom": "#1d2f30", "floor": "#16232a", "flame": "#7dffd0", "glow": Color(0.4, 1, 0.8), "fx": "mist"},
	{"top": "#0d1828", "bottom": "#26425c", "floor": "#2a3e52", "flame": "#9fe8ff", "glow": Color(0.6, 0.9, 1), "fx": "snow"},
	{"top": "#24100c", "bottom": "#47190f", "floor": "#2a120e", "flame": "#ff6a20", "glow": Color(1, 0.35, 0.1), "fx": "lava"},
	{"top": "#07050d", "bottom": "#1e1030", "floor": "#120a1c", "flame": "#c77dff", "glow": Color(0.7, 0.4, 1), "fx": "void"},
]


static func theme_for(floor_num: int) -> Dictionary:
	return THEMES[clampi(floor_num, 1, THEMES.size()) - 1]


func _ready() -> void:
	clip_contents = true
	add_child(world)
	_dust = _ambient(40, 8.0, Color(1, 0.95, 0.8, 0.25), Vector2(0, -6), 1.0, 2.5)
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.spread = 180.0
	for i in 3:
		var e := _ambient(10, 1.4, Color(1, 0.6, 0.2, 0.8), Vector2(0, -60), 1.5, 3.0)
		e.initial_velocity_min = 10.0
		e.initial_velocity_max = 40.0
		e.spread = 25.0
		e.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		e.emission_sphere_radius = 6.0
		_embers.append(e)
	world.add_child(hero)
	world.add_child(foe)
	heroes = [hero]
	_actor = hero
	_boxes["player"] = _make_box()
	_boxes["enemy"] = _make_box()
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 52)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.visible = false
	add_child(_banner)
	_intent = Label.new()
	_intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent.size = Vector2(260, 30)
	_intent.add_theme_font_size_override("font_size", 18)
	_intent.add_theme_constant_override("outline_size", 7)
	_intent.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_intent)
	_intent_icon = GameIcon.make("attack", 26)
	add_child(_intent_icon)
	_turn = UiKit.heading("", 20, GameLog.GREEN)
	_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_turn)
	_banner.add_theme_font_override("font", UiKit.serif())
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash_rect)
	resized.connect(_layout)


func _process(delta: float) -> void:
	_t += delta
	world.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	# animations only move the offset, so resizing never fights a running tween
	for i in heroes.size():
		heroes[i].position = _hero_home(i) + heroes[i].offset * unit()
	foe.position = home("enemy") + foe.offset * unit()
	_intent.size = Vector2(maxf(260, size.x * 0.4), 30)
	_intent.position = foe.position + Vector2(-_intent.size.x / 2, foe.head_y() * foe.scale.y - 44 + sin(_t * 3.0) * 3)
	var text_w := _intent.get_theme_font("font").get_string_size(_intent.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_intent_icon.position = _intent.position + Vector2(_intent.size.x / 2 - text_w * _intent.scale.x / 2 - 32, 2)
	_intent_icon.visible = _intent.text != ""
	queue_redraw()


## Show what the enemy will do on its next turn.
func update_intent() -> void:
	if _enemy == null or _enemy.hp <= 0:
		_intent.text = ""
		return
	if _party.size() > 1:  # co-op: say who the enemy is going after
		var target := _party[clampi(_enemy.target_slot, 0, _party.size() - 1)]
		_intent.text = "%s  >  %s" % [_enemy.intent_text(target.armor), "YOU" if target.slot == _my_slot else target.name]
	else:
		_intent.text = _enemy.intent_text(_player.armor)
	var colors := {"attack": "#ffffff", "charge": GameLog.YELLOW, "heavy": GameLog.RED, "guard": GameLog.BLUE, "special": GameLog.MAGENTA}
	_intent.add_theme_color_override("font_color", Color(colors.get(_enemy.intent, "#ffffff")))
	_intent_icon.set_id({"guard": "shield"}.get(_enemy.intent, _enemy.intent))
	refresh_hud()
	_intent.pivot_offset = _intent.size / 2
	_intent.scale = Vector2(1.3, 1.3)
	create_tween().tween_property(_intent, "scale", Vector2.ONE, 0.2)


# ------------------------------------------------------------------ setup / layout

## In co-op pass the party state: every hero in it takes the stage, player is this machine's hero.
func setup(player: PlayerData, enemy: EnemyData, state: GameState = null) -> void:
	_player = player
	_state = state
	_enemy = enemy
	_intent.text = ""
	_ready_slots = []
	var cast: Array[PlayerData] = [player]
	if state and state.party:
		cast = state.players
	_set_heroes(cast, player.slot if state and state.party else 0)
	foe.setup(enemy.base_name, enemy.boss, enemy.elite)
	_max_hp = {"player": player.max_hp, "enemy": enemy.max_hp}
	_boxes["player"].name.text = "%s  Lv%d" % [player.name, player.level]
	_boxes["enemy"].name.text = "%s  Lv%d" % [enemy.name, enemy.level]
	_boxes["enemy"].name.add_theme_color_override("font_color",
			Color(GameLog.YELLOW if enemy.boss else (GameLog.RED if enemy.elite else "#ffffff")))
	_layout()
	set_hp("player", player.hp, true)
	set_hp("enemy", enemy.hp, true)
	_boxes["enemy"].xp.visible = false
	set_xp(player.xp, Config.exp_needed(player.level), true)
	refresh_hud()
	foe.offset = Vector2(1500, 0)  # off screen; slides in on the "appear" event


func unit() -> float:
	return maxf(size.y, 200.0) / 420.0


func home(who: String) -> Vector2:
	return _hero_home(_my_slot) if who == "player" else Vector2(size.x * FOE_X, size.y * FEET)


## Spot for hero i: alone in the middle of the left side, or a staggered line for a party.
func _hero_home(i: int) -> Vector2:
	var n := heroes.size()
	if n <= 1:
		return Vector2(size.x * HERO_X, size.y * FEET)
	var right := 0.34 if n == 2 else 0.4
	return Vector2(size.x * lerpf(0.1, right, float(i) / (n - 1)), size.y * (FEET + (0.05 if i % 2 == 1 else -0.01)))


## Make one Creature per party member and point `hero` at this machine's one.
func _set_heroes(players: Array[PlayerData], my_slot: int) -> void:
	_party = players
	_my_slot = my_slot
	while heroes.size() < players.size():
		var c := Creature.new()
		world.add_child(c)
		heroes.append(c)
	while heroes.size() > players.size():  # heroes[0] is the node made in _ready and is never freed
		heroes.pop_back().queue_free()
	_plate_hp.clear()
	for i in players.size():
		heroes[i].setup(players[i].char_class)
		world.move_child(heroes[i], -1 if i % 2 == 1 else 0)  # front row (odd slots) draws over the back row
		_plate_hp[i] = [players[i].hp, players[i].max_hp]
	hero = heroes[my_slot]
	_actor = hero


## Co-op: which heroes have locked in their action (shown as checks over their heads).
func set_ready(slots: Array) -> void:
	_ready_slots = slots


func _plate(slot: int, hp: int, max_hp: int = -1) -> void:
	if _plate_hp.has(slot):
		_plate_hp[slot] = [maxi(hp, 0), max_hp if max_hp > 0 else _plate_hp[slot][1]]


## Looping background particles (dust motes, torch embers).
func _ambient(amount: int, lifetime: float, col: Color, gravity: Vector2, min_size: float, max_size: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.local_coords = true
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.direction = Vector2(0, -1)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 14.0
	p.gravity = gravity
	p.scale_amount_min = min_size
	p.scale_amount_max = max_size
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col, 0.0))
	ramp.add_point(0.3, col)
	ramp.set_color(1, Color(col, 0.0))
	p.color_ramp = ramp
	world.add_child(p)
	return p


func _layout() -> void:
	var crowd: float = [1.0, 1.0, 0.9, 0.8, 0.75][mini(heroes.size(), 4)]
	for h in heroes:
		h.scale = Vector2.ONE * unit() * h.size_mult() * crowd
	foe.scale = Vector2.ONE * unit() * foe.size_mult()
	_dust.position = size / 2
	_dust.emission_rect_extents = size / 2
	var torch_col: Color = theme_for(floor_theme)["glow"]
	for i in _embers.size():
		_embers[i].position = Vector2(size.x * [0.06, 0.5, 0.94][i], size.y * FLOOR * 0.42 - 20)
		# gradient stops: 0 = birth (transparent), 1 = 30% (visible), 2 = death (transparent)
		_embers[i].color_ramp.set_color(1, Color(torch_col.lightened(0.3), 0.85))
		_embers[i].color_ramp.set_color(2, Color(torch_col, 0.0))
	var w := minf(300.0, size.x * 0.4)
	_boxes["player"].panel.position = Vector2(16, 14)
	_boxes["enemy"].panel.position = Vector2(size.x - w - 96, 14)  # leave the corner for settings/sound
	_turn.size = Vector2(340, 30)
	_turn.position = Vector2((size.x - 340) / 2, 18)
	for b in _boxes.values():
		b.panel.size = Vector2(w, 0)
	_banner.size = Vector2(size.x, 80)
	_banner.position = Vector2(0, size.y * 0.3)
	_banner.pivot_offset = _banner.size / 2


func _make_box() -> Dictionary:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.11, 0.8)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 18)
	box.add_child(name_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 22)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#30303c")
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	box.add_child(bar)
	var preview := ColorRect.new()  # ghost segment: HP an action would remove
	preview.color = Color(1, 1, 1, 0.45)
	preview.visible = false
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(preview)
	var text := Label.new()  # "HP 12 / 20" drawn on the bar
	text.add_theme_font_size_override("font_size", 13)
	text.add_theme_constant_override("outline_size", 4)
	text.add_theme_color_override("font_outline_color", Color.BLACK)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(text)
	var xp_bar := UiKit.bar(8)  # player only: progress to the next level
	xp_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(xp_bar)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.custom_minimum_size = Vector2(0, 22)
	box.add_child(chips)
	add_child(panel)
	return {"panel": panel, "name": name_label, "bar": bar, "text": text, "chips": chips, "preview": preview, "xp": xp_bar}


## Show the slice of the enemy HP bar that an action would remove ([lo, hi] damage), or hide it ([]).
func preview_damage(dmg: Array) -> void:
	var b: Dictionary = _boxes["enemy"]
	var rect: ColorRect = b.preview
	if dmg.is_empty() or _enemy == null:
		rect.visible = false
		return
	var bar: ProgressBar = b.bar
	var hp := maxi(_enemy.hp, 0)
	var lo := clampi(hp - int(dmg[1]), 0, hp)
	rect.visible = true
	rect.position = Vector2(bar.size.x * lo / _enemy.max_hp, 0)
	rect.size = Vector2(bar.size.x * (hp - lo) / _enemy.max_hp, bar.size.y)
	rect.color = Color(1, 0.3, 0.3, 0.7) if dmg[1] >= hp else Color(1, 1, 1, 0.45)  # red = could kill


## "YOUR TURN" when the player can act; hidden while your action plays out.
## "ENEMY TURN" appears when the enemy starts acting (the "pause" event).
func set_turn(player_turn: bool) -> void:
	if _enemy == null or _enemy.hp <= 0 or _player.hp <= 0 or not player_turn:
		_turn.text = ""
		return
	_turn.text = "YOUR TURN"
	_turn.add_theme_color_override("font_color", Color(GameLog.GREEN))


## Co-op: big status line while you wait ("WAITING FOR PARTY", "YOU ARE DOWN").
func show_status(text: String, hex: String = GameLog.YELLOW) -> void:
	_turn.text = text
	_turn.add_theme_color_override("font_color", Color(hex))


## Redraw the stat line and status chips (poison, guard, buffs...) for both fighters.
func refresh_hud() -> void:
	if _player == null or _enemy == null:
		return
	foe.charging = _enemy.intent == "heavy" and _enemy.hp > 0
	foe.guarding = _enemy.guarding and _enemy.hp > 0
	foe.poisoned = _enemy.poison > 0 and _enemy.hp > 0
	for i in mini(heroes.size(), _party.size()):
		heroes[i].poisoned = _party[i].poison > 0 and _party[i].hp > 0
	for who in ["player", "enemy"]:
		var b: Dictionary = _boxes[who]
		var chips: HBoxContainer = b.chips
		for c in chips.get_children():
			c.queue_free()
		var list: Array = _player.statuses() if who == "player" else _enemy.statuses()
		var atk := _player.atk if who == "player" else _enemy.current_atk
		var arm := _player.armor if who == "player" else _enemy.armor
		_chip(chips, "atk", str(atk), "Attack: %d" % atk)
		_chip(chips, "armor", str(arm), "Armor: reduces each hit by %d" % arm)
		for s in list:
			_chip(chips, s.icon, s.text, s.tip)
		if who == "enemy" and _enemy.hp > 0:
			var xp := Progression.exp_preview(_player, _enemy.level, _enemy.boss, _enemy.elite)
			var tip := Progression.reward_text(_state, _enemy.level, _enemy.boss, _enemy.elite) if _state \
					else "+%d EXP" % xp
			_chip(chips, "exp", "+%d" % xp, "Reward for winning: " + tip)


func _chip(row: HBoxContainer, icon: String, text: String, tip: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(GameIcon.make(icon, 18))
	if text != "":
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", 13)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(l)
	row.add_child(h)


## Fill the player's EXP bar (tweened unless instant).
func set_xp(xp: int, need: int, instant: bool = false) -> Tween:
	var bar: ProgressBar = _boxes["player"].xp
	bar.tooltip_text = "EXP %d / %d to level %d" % [xp, need, _player.level + 1 if _player else 2]
	UiKit.set_bar(bar, int(bar.value), need, "#4fc3f7")
	if instant:
		bar.value = xp
		return null
	var tw := create_tween()
	tw.tween_property(bar, "value", float(xp), 0.45).set_ease(Tween.EASE_OUT)
	return tw


## Tween an HP bar to a new value (or snap it).
func set_hp(who: String, hp: int, instant: bool = false, max_hp: int = -1) -> void:
	if max_hp > 0:
		_max_hp[who] = max_hp
	var b: Dictionary = _boxes[who]
	var bar: ProgressBar = b.bar
	var mx: int = _max_hp[who]
	hp = maxi(hp, 0)
	bar.max_value = mx
	if instant:
		bar.value = hp
	else:
		create_tween().tween_property(bar, "value", float(hp), 0.3).set_ease(Tween.EASE_OUT)
	b.text.text = "HP %d / %d" % [hp, mx]
	var ratio := float(hp) / mx
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#4caf50") if ratio > 0.5 else (Color("#e0b030") if ratio > 0.25 else Color("#e04040"))
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)


# ------------------------------------------------------------------ backdrop

func _draw() -> void:
	var w := size.x
	var h := size.y
	var floor_y := h * FLOOR
	var th := theme_for(floor_theme)
	var torch_glow: Color = th["glow"]
	var fx: String = th["fx"]
	draw_set_transform(world.position)
	for i in 12:
		var k := i / 12.0
		draw_rect(Rect2(-20, floor_y * k - 1, w + 40, floor_y / 12.0 + 2), Color(th["top"]).lerp(Color(th["bottom"]), k))
	if fx == "void":  # stars glinting through the walls and a swirling rift behind the fight
		for i in 40:
			var p := Vector2(fmod(i * 137.5, w), fmod(i * 71.3, floor_y))
			draw_circle(p, 1.0 + (i % 3) * 0.6, Color(0.85, 0.7, 1, 0.25 + 0.25 * sin(_t * 2.0 + i)))
		var rc := Vector2(w * 0.5, floor_y * 0.2)
		for k in 6:
			var a := _t * (0.4 + k * 0.1) + k
			draw_set_transform(world.position + rc, a, Vector2(1.0, 0.45))
			draw_arc(Vector2.ZERO, 30.0 + k * 14, 0, PI * 1.3, 24, Color(0.7, 0.4, 1, 0.22 - k * 0.03), 6.0 - k * 0.6, true)
		draw_set_transform(world.position)
		draw_circle(rc, 20, Color(0.05, 0, 0.1, 0.9))
		draw_circle(rc, 32, Color(0.7, 0.4, 1, 0.12))
	var bw := 64.0
	var bh := 30.0
	for row in int(floor_y / bh) + 1:
		var y := row * bh
		draw_line(Vector2(-20, y), Vector2(w + 20, y), Color(0, 0, 0, 0.28), 2.0)
		var off := (row % 2) * bw / 2
		for x in range(-1, int(w / bw) + 2):
			draw_line(Vector2(x * bw + off, y), Vector2(x * bw + off, minf(y + bh, floor_y)), Color(0, 0, 0, 0.28), 2.0)
	for tx in [w * 0.06, w * 0.5, w * 0.94]:
		var ty := floor_y * 0.42
		var flicker := 0.88 + 0.12 * sin(_t * 9.0 + tx) * sin(_t * 13.7 + tx * 0.3)
		draw_circle(Vector2(tx, ty), 110 * flicker, Color(torch_glow, 0.05))
		draw_circle(Vector2(tx, ty), 55 * flicker, Color(torch_glow, 0.08))
		draw_rect(Rect2(tx - 4, ty, 8, 28), Color("#3a3030"))
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 9, ty), Vector2(tx, ty - 26 * flicker), Vector2(tx + 9, ty)]),
				Color(th["flame"]))
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 4, ty), Vector2(tx, ty - 14 * flicker), Vector2(tx + 4, ty)]),
				Color(th["flame"]).lightened(0.6))
	draw_rect(Rect2(-20, floor_y, w + 40, h - floor_y + 20), Color(th["floor"]))
	for i in 4:
		var y := floor_y + (h - floor_y) * (0.15 + i * 0.25)
		draw_line(Vector2(-20, y), Vector2(w + 20, y), Color(1, 1, 1, 0.03), 2.0)
	if fx == "snow":  # icicles along the ceiling, sheen on the ice, falling snow
		for i in int(w / 38.0) + 1:
			var x := i * 38.0 + 10
			var drop := 18.0 + fmod(i * 23.7, 30.0)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 7, -2), Vector2(x + 7, -2), Vector2(x, drop)]), Color(0.75, 0.9, 1, 0.55))
		for i in 6:
			var x0 := w * (0.04 + i * 0.17)
			draw_line(Vector2(x0, floor_y + 14 + i % 2 * 30), Vector2(x0 + 70, floor_y + 4 + i % 2 * 30), Color(1, 1, 1, 0.12), 3.0)
		for i in 50:
			var x := fmod(i * 97.3 + sin(_t * 0.6 + i) * 18.0 + 4000.0, w)
			var y := fmod(i * 53.1 + _t * (22.0 + (i % 5) * 7.0), h)
			draw_circle(Vector2(x, y), 1.2 + (i % 3) * 0.7, Color(1, 1, 1, 0.55))
	elif fx == "void":  # rune circle on the floor
		var c := Vector2(w * 0.5, floor_y + (h - floor_y) * 0.5)
		draw_set_transform(world.position + c, 0.0, Vector2(1.0, 0.22))
		var glow := 0.5 + 0.5 * sin(_t * 1.5)
		draw_arc(Vector2.ZERO, w * 0.36, 0, TAU, 64, Color(0.7, 0.4, 1, 0.12 + 0.1 * glow), 6.0, true)
		draw_arc(Vector2.ZERO, w * 0.3, 0, TAU, 64, Color(0.7, 0.4, 1, 0.08 + 0.08 * glow), 3.0, true)
		for k in 8:
			var a := k * TAU / 8 + _t * 0.2
			draw_line(Vector2(cos(a), sin(a)) * w * 0.3, Vector2(cos(a), sin(a)) * w * 0.36, Color(0.7, 0.4, 1, 0.2), 3.0)
		draw_set_transform(world.position)
	elif fx == "lava":  # glowing lava cracks in the floor
		for i in 7:
			var x0 := w * (0.05 + i * 0.15)
			var glow := 0.5 + 0.5 * sin(_t * 2.0 + i)
			var crack := PackedVector2Array([Vector2(x0, h - 6), Vector2(x0 + 20, floor_y + (h - floor_y) * 0.6),
					Vector2(x0 + 8, floor_y + (h - floor_y) * 0.35), Vector2(x0 + 30, floor_y + 6)])
			draw_polyline(crack, Color(1, 0.4, 0.1, 0.35 + 0.35 * glow), 3.0, true)
	elif fx == "mist":  # creeping mist
		for i in 5:
			var mx := fmod(i * w * 0.27 + _t * 18.0, w + 300) - 150
			draw_circle(Vector2(mx, h - 8), 110, Color(0.6, 1, 0.9, 0.035))
	draw_line(Vector2(-20, floor_y), Vector2(w + 20, floor_y), Color("#0e0c12"), 3.0)

	if heroes.size() > 1:
		_draw_plates()

	# low HP warning: pulsing red vignette
	if _player and _player.hp > 0 and _player.hp < _player.max_hp * 0.3:
		draw_set_transform(Vector2.ZERO)
		var a := 0.12 + 0.1 * sin(_t * 5.0)
		for i in 6:
			var inset := i * 10.0
			draw_rect(Rect2(inset, inset, w - 2 * inset, h - 2 * inset), Color(0.9, 0.1, 0.1, a * (1.0 - i / 6.0)), false, 10.0)


## Co-op: name, mini HP bar and a "ready" check over every hero's head.
func _draw_plates() -> void:
	var font := ThemeDB.fallback_font
	for i in mini(heroes.size(), _party.size()):
		var h := heroes[i]
		var top := h.position + Vector2(0, h.head_y() * h.scale.y - 26)
		var hp_max: Array = _plate_hp.get(i, [1, 1])
		var down: bool = hp_max[0] <= 0
		var label: String = "DOWN" if down else _party[i].name
		var col := Color(GameLog.YELLOW) if i == _my_slot else Color.WHITE
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline(font, top + Vector2(-tw / 2, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
		draw_string(font, top + Vector2(-tw / 2, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(GameLog.GRAY) if down else col)
		var bar := Rect2(top + Vector2(-32, 5), Vector2(64, 7))
		draw_rect(bar.grow(1.5), Color(0, 0, 0, 0.8))
		var ratio := clampf(float(hp_max[0]) / maxi(int(hp_max[1]), 1), 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)),
				Color("#4caf50") if ratio > 0.5 else (Color("#e0b030") if ratio > 0.25 else Color("#e04040")))
		if i in _ready_slots and not down:
			var c := top + Vector2(tw / 2 + 12, -5)
			draw_circle(c, 8, Color(0.1, 0.5, 0.2))
			draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-1, 3), c + Vector2(4, -3)]), Color.WHITE, 2.0, true)


# ------------------------------------------------------------------ animation

func _node(who: String) -> Creature:
	return _actor if who == "player" else foe


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func play(ev: Dictionary) -> void:
	var slot := int(ev.get("slot", 0))
	_actor = heroes[slot] if slot < heroes.size() else hero
	var mine := slot == _my_slot  # events about this machine's hero (always true in solo)
	match ev.type:
		"appear":
			foe.offset = Vector2(500, 0)
			var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(foe, "offset", Vector2.ZERO, 0.55)
			if ev.boss:
				sfx.play("boss")
				_shake(10.0, 0.8)
				_screen_flash(Color(0.6, 0.0, 0.0), 0.5)
				_fx("ring", foe, Color(1, 0.3, 0.2), 160, 0.8, 0.5, 0.0)
				_show_banner("BOSS FIGHT!", GameLog.RED)
			else:
				sfx.play("appear")
			await tw.finished
			_fx("smoke", foe, Color(0.5, 0.5, 0.55), 70, 0.6, 0.0, 0.0)
			_squash(foe, -0.12)
		"attack":
			var who := _node(ev.by)
			var dir := 1.0 if ev.by == "player" else -1.0
			var heavy: bool = ev.get("heavy", false)
			var tw := create_tween()
			if heavy:  # wind up, then slam
				tw.parallel().tween_property(who, "lean", -0.25 * dir, 0.2)
				tw.tween_property(who, "offset", Vector2(-30 * dir, -20), 0.2).set_ease(Tween.EASE_OUT)
			tw.tween_property(who, "lean", 0.18 * dir, 0.1)
			tw.parallel().tween_property(who, "offset", Vector2((110 if heavy else 70) * dir, -6), 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(who, "lean", 0.0, 0.2)
			tw.parallel().tween_property(who, "offset", Vector2.ZERO, 0.2).set_ease(Tween.EASE_IN_OUT)
			await _wait(0.32 if heavy else 0.12)
		"intent":
			update_intent()
		"damage":
			var target := _node(ev.target)
			var dir := -1.0 if ev.target == "player" else 1.0
			_set_hp_for(ev, ev.hp)
			var kind: String = ev.kind
			var col: String = GameLog.GREEN if kind == "poison" else (GameLog.YELLOW if ev.crit else "#ffffff")
			_float_text(target, ("%d!" if ev.crit else "%d") % ev.amount, col, 44 if ev.crit else 30, Vector2.INF, ev.crit)
			_flash(target, Color(0.6, 1.0, 0.6) if kind == "poison" else Color(1.0, 0.35, 0.35))
			match kind:
				"poison":
					_fx("smoke", target, Color(0.4, 0.9, 0.3), 45, 0.5)
				"bomb":
					_fx("explosion", target, Color.WHITE, 110, 0.55)
					_screen_flash(Color(1, 0.7, 0.3), 0.35)
				"holy":
					_fx("beam", target, Color(1, 0.9, 0.5), 70, 0.5)
				"thorns":
					_fx("star", target, Color(0.6, 1, 0.5), 40, 0.3)
				_:
					_fx("slash", target, Color.WHITE, 75 if not ev.crit else 95, 0.3, 0.5, dir * -1.0)
			if ev.crit:
				_fx("star", target, Color(1, 0.9, 0.4), 90, 0.35)
				_fx("ring", target, Color(1, 0.9, 0.4), 120, 0.4)
				_screen_flash(Color.WHITE, 0.25)
				_hitstop(0.07)
			_burst(target, Color(col), 24 if ev.crit else 12)
			_squash(target, 0.2 if ev.crit else 0.12)
			_knockback(ev.target)
			if kind == "poison":
				sfx.play("hurt", 0.2)
			else:
				sfx.play("crit" if ev.crit else ("hurt" if ev.target == "player" else "hit"))
			if ev.crit or ev.target == "player":
				_shake(10.0 if ev.crit else 5.0, 0.25)
			await _wait(0.3)
		"miss":
			var target := _node(ev.target)
			_float_text(target, "MISS", GameLog.GRAY, 26)
			var dir := -1.0 if ev.target == "player" else 1.0
			_fx("whoosh", target, Color(0.85, 0.85, 0.9), 80, 0.3, 0.5, -dir)
			var tw := create_tween()
			tw.tween_property(target, "offset", Vector2(30 * dir, 0), 0.1)
			tw.parallel().tween_property(target, "lean", 0.15 * dir, 0.1)
			tw.tween_property(target, "offset", Vector2.ZERO, 0.15)
			tw.parallel().tween_property(target, "lean", 0.0, 0.15)
			sfx.play("miss")
			await _wait(0.28)
		"heal":
			var target := _node(ev.target)
			_set_hp_for(ev, ev.hp)
			if ev.get("revive", false):  # co-op: a downed hero gets back up after the fight
				create_tween().tween_property(target, "rotation", 0.0, 0.4)
				create_tween().tween_property(target, "modulate:a", 1.0, 0.4)
			_float_text(target, "+%d" % ev.amount, GameLog.GREEN, 30)
			_fx("heal", target, Color(0.5, 1, 0.5), 60, 0.9)
			_fx("ring", target, Color(0.5, 1, 0.5), 70, 0.45, 0.0)
			_burst(target, Color(GameLog.GREEN), 14, true)
			sfx.play("heal")
			await _wait(0.3)
		"skill":
			var ult: bool = ev.get("ult", false)
			_show_banner(String(ev.name).to_upper() + "!", GameLog.MAGENTA if ult else GameLog.YELLOW)
			sfx.play("skill", 0.0 if ult else 0.06)
			_skill_fx(ev.name)
			if ult:
				_shake(6.0, 0.3)
				_screen_flash(Color(0.8, 0.4, 1.0), 0.3)
				for i in 2:
					_burst(_actor, Color(GameLog.MAGENTA), 20, true)
			await _wait(0.45 if ult else 0.35)
		"item":
			_show_banner(String(ev.name).to_upper(), GameLog.CYAN)
			sfx.play("flee" if ev.id == "smoke" else ("crit" if ev.id == "bomb" else "skill"))
			match ev.id:
				"smoke":
					_fx("smoke", _actor, Color(0.6, 0.62, 0.68), 90, 0.8)
				"tonic":
					_fx("ring", _actor, Color(1, 0.4, 0.3), 90, 0.5)
					_fx("star", _actor, Color(1, 0.6, 0.3), 70, 0.4)
				"fire":
					_fx("bolt_to_foe", _actor, Color(1, 0.5, 0.1), 50, 0.4)
					_fx("explosion", foe, Color.WHITE, 70, 0.5, 0.5, 1.0, 0.35)
				"bomb":
					_fx("bolt_to_foe", _actor, Color(0.3, 0.3, 0.35), 50, 0.35)
				_:
					_burst(_actor, Color(GameLog.CYAN), 14, true)
			await _wait(0.35)
		"defend":
			_actor.shielded = true
			_fx("hex", _actor, Color(0.6, 0.85, 1.0), 80, 0.4)
			sfx.play("defend")
			await _wait(0.25)
		"status":
			_float_text(_node(ev.target), ev.text, ev.color, 22)
			match ev.text:
				"CHARGING":
					_fx("ring", foe, Color(1, 0.6, 0.2), 90, 0.5, 0.5, 1.0)
				"CHILLED":
					_fx("star", _actor, Color(0.7, 0.95, 1), 80, 0.45)
					_fx("ring", _actor, Color(0.7, 0.95, 1), 90, 0.4)
					_burst(_actor, Color(0.8, 0.95, 1), 18)
					sfx.play("defend")
				"RISES AGAIN!":
					_fx("pillar", foe, Color(0.5, 1, 0.6), 120, 1.0, 0.0)
					_fx("ring", foe, Color(0.7, 0.4, 1), 150, 0.7, 0.0)
					_screen_flash(Color(0.4, 1, 0.5), 0.35)
					_shake(8.0, 0.5)
					sfx.play("boss")
					foe.modulate.a = 1.0
				"SPLIT!":
					_fx("smoke", foe, Color(0.4, 0.85, 0.35), 80, 0.6)
					_squash(foe, 0.3)
				"PHASED":
					_fx("smoke", foe, Color(0.6, 0.85, 1.0), 60, 0.5)
					_flash(foe, Color(1, 1, 1, 0.35))
				"+1 ARMOR":
					_fx("hex", foe, Color(0.6, 0.85, 1.0), 90, 0.5)
				"-1 ARMOR":
					_fx("smoke", _actor, Color(0.5, 0.9, 0.3), 60, 0.5)
				"-1 ATK":
					_fx("bolt_to_foe", _actor, Color(0.6, 0.85, 1.0), 40, 0.45)
			await _wait(0.3)
		"fled":
			sfx.play("flee")
			_fx("smoke", _actor, Color(0.6, 0.6, 0.65), 60, 0.5, 0.0)
			var tw := create_tween()
			tw.tween_property(_actor, "offset", Vector2(-500, 0), 0.4).set_ease(Tween.EASE_IN)
			await tw.finished
		"death":
			var target := _node(ev.target)
			if ev.target == "enemy":
				_intent.text = ""
				target.charging = false
				target.guarding = false
			sfx.play("death")
			_hitstop(0.12)
			_screen_flash(Color.WHITE, 0.3)
			var dir := -1.0 if ev.target == "player" else 1.0
			var tw := create_tween().set_parallel()
			tw.tween_property(target, "rotation", 1.3 * dir, 0.6).set_ease(Tween.EASE_IN)
			tw.tween_property(target, "modulate:a", 0.0, 0.8)
			await _wait(0.35)
			_dissolve(target)
			_fx("smoke", target, Color(0.3, 0.28, 0.35), 90, 0.9, 0.0)
			await tw.finished
		"exp":
			if mine:  # other heroes' EXP only shows on their own screens
				if ev.amount > 0:
					_float_text(_actor, "+%d EXP" % ev.amount, GameLog.CYAN, 22)
				var tw := set_xp(ev.xp, ev.need)
				await tw.finished
		"level_up":
			_set_hp_for(ev, ev.hp, ev.max_hp)
			if mine:
				_boxes["player"].xp.value = 0
				_boxes["player"].name.text = "%s  Lv%d" % [_player.name, ev.level]
			_show_banner("LEVEL UP!" if mine else "%s LEVEL UP!" % _party[slot].name.to_upper(), GameLog.YELLOW)
			sfx.play("levelup")
			_fx("pillar", _actor, Color(1, 0.85, 0.35), 110, 1.2, 0.0)
			_fx("ring", _actor, Color(1, 0.85, 0.35), 140, 0.6, 0.0)
			for i in 3:
				_burst(_actor, Color(GameLog.YELLOW), 16, true)
				await _wait(0.15)
			await _wait(0.4)
		"loot_text":
			if mine:
				_float_text(foe, ev.text, ev.color, 24, home("enemy"))
				sfx.play(ev.sound)
				await _wait(0.3)
		"pause":
			if _enemy.hp > 0:
				_turn.text = "ENEMY TURN"
				_turn.add_theme_color_override("font_color", Color(GameLog.RED))
			await _wait(ev.time)


## HP change from an event: the enemy box, this machine's hero box, and the co-op nameplates.
func _set_hp_for(ev: Dictionary, hp: int, max_hp: int = -1) -> void:
	if ev.get("target", "player") == "enemy":
		set_hp("enemy", hp)
		return
	var slot := int(ev.get("slot", 0))
	_plate(slot, hp, max_hp)
	if slot == _my_slot:
		set_hp("player", hp, false, max_hp)


# ------------------------------------------------------------------ effect helpers

## Spawn an effect on a creature. height = where on the body (0 = feet, 1 = head top).
func _fx(kind: String, target: Creature, col: Color, radius: float, life: float, height: float = 0.5,
		dir: float = 1.0, delay: float = 0.0) -> void:
	if delay > 0.0:
		await _wait(delay)
	var pos := target.position + Vector2(0, target.head_y() * target.scale.y * height)
	if kind == "bolt_to_foe":  # projectile from the _actor to the enemy
		var v := Vfx.spawn(world, "bolt", pos, col, radius, life)
		v.target = foe.position + Vector2(0, foe.head_y() * foe.scale.y * 0.5) - pos
		return
	if kind == "bolt_to_hero":
		var v := Vfx.spawn(world, "bolt", pos, col, radius, life)
		v.target = _actor.position + Vector2(0, _actor.head_y() * _actor.scale.y * 0.5) - pos
		return
	Vfx.spawn(world, kind, pos, col, radius * unit(), life, dir)


## Signature effect for each skill and ultimate.
func _skill_fx(skill: String) -> void:
	match skill:
		"Power Strike":
			_fx("ring", _actor, Color(1, 0.8, 0.4), 80, 0.35)
		"Backstab":
			_fx("smoke", _actor, Color(0.3, 0.35, 0.3), 60, 0.4)
		"Smite":
			pass  # the holy damage event draws the beam
		"Drain Life":
			_fx("bolt_to_hero", foe, Color(0.75, 0.3, 1.0), 60, 0.55, 0.5, 1.0)
		"Shield Wall":
			_fx("hex", _actor, Color(0.6, 0.85, 1.0), 110, 0.6)
		"Poison Blade", "Plague":
			_fx("smoke", foe, Color(0.4, 0.9, 0.3), 90, 0.8, 0.5, 1.0, 0.2)
		"Divine Light":
			_fx("pillar", _actor, Color(1, 0.95, 0.6), 120, 1.0, 0.0)


## Death: the body breaks into particles of its own colors.
func _dissolve(target: Creature) -> void:
	var colors := {"Goblin": "#6cbf4a", "Orc": "#5d8a3e", "Troll": "#7a8fa6", "Skeleton": "#e8e4d8", "Zombie": "#8fa878",
			"Vampire": "#8b1a2e", "Werewolf": "#7a5a3c", "Demon": "#c0392b", "Giant": "#c9a27a", "Dragon": "#b83a2e",
			"Slime": "#5fd35a", "Wraith": "#9fd8ff", "Golem": "#8a8f98", "Yeti": "#e8f0f8", "Lich": "#b06bff"}
	var col := Color(colors.get(target.kind, "#9aa5b1"))
	for k in 2:
		var p := CPUParticles2D.new()
		p.local_coords = true
		p.position = target.position + Vector2(0, target.head_y() * target.scale.y * (0.3 + k * 0.4))
		p.one_shot = true
		p.amount = 40
		p.lifetime = 1.1
		p.explosiveness = 0.8
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 40.0 * unit()
		p.direction = Vector2(0, -1)
		p.spread = 50.0
		p.initial_velocity_min = 30.0
		p.initial_velocity_max = 110.0
		p.gravity = Vector2(0, -60)
		p.scale_amount_min = 3.0
		p.scale_amount_max = 7.0
		var ramp := Gradient.new()
		ramp.set_color(0, col.lightened(0.2))
		ramp.set_color(1, Color(col.darkened(0.4), 0.0))
		p.color_ramp = ramp
		world.add_child(p)
		p.emitting = true
		get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _squash(target: Creature, amount: float) -> void:
	target.squash = amount
	create_tween().tween_property(target, "squash", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Brief freeze on big hits so they land with weight.
func _hitstop(seconds: float) -> void:
	if _in_hitstop:
		return
	_in_hitstop = true
	var prev := Engine.time_scale
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = prev
	_in_hitstop = false


func _screen_flash(col: Color, strength: float) -> void:
	_flash_rect.color = Color(col, strength)
	create_tween().tween_property(_flash_rect, "color:a", 0.0, 0.25)


func _float_text(target: Creature, text: String, hex: String, font_size: int, at: Vector2 = Vector2.INF,
		big: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(hex))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	if big:
		label.add_theme_font_override("font", UiKit.serif())
	label.size = Vector2(240, 60)
	var base := at if at != Vector2.INF else target.position + Vector2(0, target.head_y() * target.scale.y)
	label.position = base + Vector2(-120 + randf_range(-18, 18), -40)
	label.pivot_offset = label.size / 2
	label.scale = Vector2(0.4, 0.4)
	if big:
		label.rotation = randf_range(-0.15, 0.15)
	add_child(label)
	var tw := create_tween().set_parallel()
	tw.tween_property(label, "scale", Vector2.ONE * (1.25 if big else 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "position:y", label.position.y - 60, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.chain().tween_callback(label.queue_free)


func _flash(target: Creature, tint: Color) -> void:
	target.modulate = tint
	create_tween().tween_property(target, "modulate", Color.WHITE, 0.3)


func _knockback(who: String) -> void:
	var target := _node(who)
	var dir := -1.0 if who == "player" else 1.0
	var tw := create_tween()
	tw.tween_property(target, "offset", Vector2(18 * dir, 0), 0.06)
	tw.tween_property(target, "offset", Vector2.ZERO, 0.18)


func _shake(amount: float, duration: float) -> void:
	shake = amount
	create_tween().tween_property(self, "shake", 0.0, duration)


func _burst(target: Creature, col: Color, amount: int, upward: bool = false) -> void:
	var p := CPUParticles2D.new()
	p.local_coords = true  # global coords would emit from a stale transform on the first frame
	p.position = target.position + Vector2(0, target.head_y() * target.scale.y * 0.5)
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector2(0, -1)
	p.spread = 60.0 if upward else 180.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 240.0
	p.gravity = Vector2(0, -80 if upward else 420)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	var ramp := Gradient.new()  # sparks cool and fade as they fly
	ramp.set_color(0, col.lightened(0.4))
	ramp.set_color(1, Color(col, 0.0))
	p.color_ramp = ramp
	world.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _show_banner(text: String, hex: String) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", Color(hex))
	_banner.visible = true
	_banner.modulate.a = 1.0
	_banner.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.3)
