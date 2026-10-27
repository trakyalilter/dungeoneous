class_name TitleScreen
extends Control
## Title menu with four pages: new run (class cards, difficulty), Soul Shrine, achievements, how to play.

signal new_run(player_name: String, cls: String, difficulty: String)
signal continue_run
signal open_settings
signal open_multiplayer(player_name: String, cls: String)

const HELP := """[b]Goal[/b]  Descend through 5 floors (Stone Halls, Sunken Crypt, Frozen Caverns, Burning Depths, Void Throne) and destroy the Lich Emperor at the bottom of the dungeon.

[b]The map[/b]  Click a glowing room to move there. Hover any room to light up every route onward from it; fight rooms also show the EXP and gold they pay. Fights give gold, EXP and loot. [color=#ff6b6b]Elites[/color] (ringed in flame) are tougher but always drop an item and a relic. Unknown rooms hold events, campfires let you rest or train, shops sell gear, items and relics.

[b]Deeper foes[/b]  Slimes split once when hurt, Wraiths let some blows pass through them, Golems harden their stone skin, the Frost Titan chills your cooldowns, and the Lich Emperor rises again once.

[b]Combat[/b]  The text above the enemy shows what it will do next turn. Use it:
 - [color=#ffd84d]Charging[/color] means a HEAVY hit is coming next: Defend (or Shield Wall) halves it.
 - [color=#7d9dff]Guarding[/color] enemies take half damage: a good turn to drink a potion or buff up.
 - [color=#e07bff]Special[/color] moves are unique per enemy type. Hover the enemy's chips to see its trait.
Hover an action to see how much of the enemy's HP bar it would take (red = it could kill). Hover anything for details.

[b]Items[/b]  Consumables (bombs, tonics, smoke, elixirs) are free actions: the enemy does not get a turn. You can carry 3.
[b]Relics[/b]  Passive bonuses for the whole run. Bosses offer a choice of powerful boss relics.
[b]Levels[/b]  Each level up lets you pick a perk. At level 3 your class ultimate unlocks (F key).

[b]Co-op[/b]  "Play with friends" lets up to 4 players on the same network adventure together. Vote on rooms, everyone picks an action each round, the enemy strikes one hero (shown above it). Shops, campfires, events and loot are personal. Downed heroes get back up after the fight; the run ends only if the whole party falls.

[b]Between runs[/b]  You earn souls even when you die. Spend them in the Soul Shrine on permanent upgrades and the Necromancer class.

[b]Keys[/b]  A attack, S skill, F ultimate, D defend, H potion, R run, 1-3 items, M mute, Esc pause."""

const DIFFICULTY_HINTS := {"Easy": "weaker enemies, more gold", "Normal": "the intended challenge", "Hard": "tougher enemies, +50% souls"}
const UPGRADE_ICONS := {"vitality": "heart", "satchel": "potion", "purse": "gold", "wisdom": "tome", "necromancer": "skull"}

var meta: MetaProgress
var _t := 0.0
var _title: Label
var _pages := {}
var _best: Label
var _continue: Button
var _name: LineEdit
var _class := "Warrior"
var _class_cards := {}  # class -> Button
var _class_desc: Label
var _difficulty := "Normal"
var _shrine_list: VBoxContainer
var _souls_label: Label
var _ach_list: VBoxContainer
var _shrine_button: Button
var _ach_button: Button


func _ready() -> void:
	var embers := CPUParticles2D.new()
	embers.local_coords = true
	embers.amount = 60
	embers.lifetime = 6.0
	embers.preprocess = 6.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(700, 10)
	embers.direction = Vector2(0, -1)
	embers.spread = 25.0
	embers.initial_velocity_min = 20.0
	embers.initial_velocity_max = 60.0
	embers.gravity = Vector2(0, -5)
	embers.scale_amount_min = 1.5
	embers.scale_amount_max = 3.5
	embers.color = Color(1.0, 0.55, 0.2, 0.7)
	add_child(embers)
	resized.connect(func() -> void: embers.position = Vector2(size.x / 2, size.y + 10))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(540, 0)
	col.add_theme_constant_override("separation", 8)
	center.add_child(col)

	_title = UiKit.heading("ENDLESS DUNGEON", 52)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_best = UiKit.label("", 14, GameLog.GRAY)
	_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_best)

	_pages["main"] = _build_main()
	_pages["shrine"] = _build_shrine()
	_pages["achievements"] = _build_achievements()
	_pages["help"] = _build_help()
	for page in _pages.values():
		col.add_child(page)
	_show_page("main")


func _process(delta: float) -> void:
	_t += delta
	_title.modulate = Color(1, 1, 1).lerp(Color(1.3, 1.1, 0.8), 0.5 + 0.5 * sin(_t * 1.5))


func _build_main() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_continue = UiKit.button("Continue", func() -> void: continue_run.emit())
	_continue.custom_minimum_size = Vector2(0, 44)
	v.add_child(_continue)

	v.add_child(UiKit.label("Choose your hero", 15, GameLog.GRAY))
	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 8)
	v.add_child(cards)
	var group := ButtonGroup.new()
	for c in Config.CLASSES:
		var card := UiKit.button("", _select_class.bind(c))
		card.toggle_mode = true
		card.button_group = group
		card.custom_minimum_size = Vector2(128, 168)
		var view := CreatureView.new()
		view.size = Vector2(128, 128)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(view)
		view.show_kind(c)
		var name_label := UiKit.label(c, 15)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.position = Vector2(0, 134)
		name_label.size = Vector2(128, 24)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_label)
		var lock := GameIcon.make("lock", 34)
		lock.size = Vector2(34, 34)
		lock.position = Vector2(47, 50)
		lock.name = "Lock"
		card.add_child(lock)
		cards.add_child(card)
		_class_cards[c] = card
	_class_desc = UiKit.label("", 14, "#cccccc")
	_class_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_desc.custom_minimum_size = Vector2(0, 62)
	v.add_child(_class_desc)

	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 12)
	form.add_theme_constant_override("v_separation", 8)
	v.add_child(form)
	form.add_child(UiKit.label("Name", 16))
	_name = LineEdit.new()
	_name.placeholder_text = "Hero"
	_name.max_length = 20
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_name)
	form.add_child(UiKit.label("Difficulty", 16))
	var diffs := HBoxContainer.new()
	diffs.add_theme_constant_override("separation", 6)
	var dgroup := ButtonGroup.new()
	for d in Config.DIFFICULTIES:
		var b := UiKit.button(d, func() -> void: _difficulty = d)
		b.toggle_mode = true
		b.button_group = dgroup
		b.button_pressed = d == _difficulty
		b.tooltip_text = DIFFICULTY_HINTS[d]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		diffs.add_child(b)
	form.add_child(diffs)

	var start := UiKit.button("Start new run", _on_start)
	start.custom_minimum_size = Vector2(0, 48)
	start.add_theme_font_size_override("font_size", 18)
	v.add_child(start)
	var coop := UiKit.button("Play with friends (LAN co-op)", func() -> void:
		var n := _name.text.strip_edges()
		open_multiplayer.emit(n if n != "" else "Hero", _class))
	coop.custom_minimum_size = Vector2(0, 42)
	v.add_child(coop)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_shrine_button = UiKit.button("", func() -> void: _show_page("shrine"))
	_ach_button = UiKit.button("", func() -> void: _show_page("achievements"))
	for b in [_shrine_button, _ach_button, UiKit.button("How to play", func() -> void: _show_page("help"))]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)
	return v


func _build_help() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(UiKit.heading("How to play", 28))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var text := UiKit.rich(14)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = HELP
	scroll.add_child(text)
	v.add_child(UiKit.button("Back", func() -> void: _show_page("main")))
	return v


func _build_shrine() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(UiKit.heading("Soul Shrine", 28, GameLog.MAGENTA))
	_souls_label = UiKit.label("", 16)
	v.add_child(_souls_label)
	v.add_child(UiKit.label("Souls are earned at the end of every run, win or lose.", 13, GameLog.GRAY))
	_shrine_list = VBoxContainer.new()
	_shrine_list.add_theme_constant_override("separation", 6)
	v.add_child(_shrine_list)
	v.add_child(UiKit.button("Back", func() -> void: _show_page("main")))
	return v


func _build_achievements() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(UiKit.heading("Achievements", 28))
	_ach_list = VBoxContainer.new()
	_ach_list.add_theme_constant_override("separation", 4)
	v.add_child(_ach_list)
	v.add_child(UiKit.button("Back", func() -> void: _show_page("main")))
	return v


func _show_page(page: String) -> void:
	for k in _pages:
		_pages[k].visible = k == page


## Fill in everything from saved data. saved may be null.
func refresh(p_meta: MetaProgress, best: Dictionary, saved: GameState) -> void:
	meta = p_meta
	if best.is_empty():
		_best.text = "No runs yet. The dungeon awaits."
	else:
		_best.text = "Best: %s the %s - %s, Level %d (%s)" % [best["name"], best["class"],
				"VICTORY" if int(best.get("won", 0)) else "Floor %d" % int(best.get("floor", 1)), int(best["level"]), best["difficulty"]]
	_continue.visible = saved != null
	if saved:
		_continue.text = "Continue: %s the %s  -  Floor %d, Level %d, %s" % [saved.player.name, saved.player.char_class,
				saved.floor_num, saved.player.level, saved.difficulty]

	for c in _class_cards:
		var card: Button = _class_cards[c]
		var unlocked := meta.class_unlocked(c)
		card.disabled = not unlocked
		card.get_node("Lock").visible = not unlocked
		card.tooltip_text = "" if unlocked else "Unlock in the Soul Shrine (%d souls)" % Config.META_UPGRADES[c.to_lower()]["costs"][0]
		card.get_child(0).modulate = Color.WHITE if unlocked else Color(0.25, 0.25, 0.3)
	if not meta.class_unlocked(_class):
		_class = "Warrior"
	_select_class(_class)

	_shrine_button.text = "Soul Shrine (%d)" % meta.souls
	_ach_button.text = "Achievements %d/%d" % [meta.achievements.size(), Config.ACHIEVEMENTS.size()]
	_souls_label.text = "You have %d souls." % meta.souls
	for c in _shrine_list.get_children():
		c.queue_free()
	for id in Config.META_UPGRADES:
		var up: Dictionary = Config.META_UPGRADES[id]
		var cost := meta.next_cost(id)
		var maxed := cost < 0
		var b := UiKit.button("         %s  [%d/%d]  -  %s   %s" % [up["name"], meta.level(id), up["costs"].size(), up["desc"],
				"MAXED" if maxed else "(%d souls)" % cost], _on_buy.bind(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 42)
		b.disabled = maxed or meta.souls < cost
		var icon := GameIcon.make(UPGRADE_ICONS.get(id, "trait"), 28)
		icon.size = Vector2(28, 28)
		icon.position = Vector2(10, 7)
		b.add_child(icon)
		_shrine_list.add_child(b)
	for c in _ach_list.get_children():
		c.queue_free()
	for id in Config.ACHIEVEMENTS:
		var a: Dictionary = Config.ACHIEVEMENTS[id]
		var got: bool = id in meta.achievements
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(GameIcon.make("crown" if got else "lock", 24))
		row.add_child(UiKit.label(a["name"], 15, GameLog.YELLOW if got else "#777777"))
		row.add_child(UiKit.label(a["desc"], 14, "#bbbbbb" if got else "#555555"))
		_ach_list.add_child(row)


func _select_class(cls: String) -> void:
	_class = cls
	for c in _class_cards:  # set_pressed_no_signal skips the button group, so clear the others by hand
		_class_cards[c].set_pressed_no_signal(c == cls)
	_class_desc.text = Config.CLASSES[cls]["desc"]


func _on_buy(id: String) -> void:
	if meta.buy(id):
		Storage.save_meta(meta)
		refresh(meta, Storage.load_highscore(), Storage.load_game())
		_show_page("shrine")


func _on_start() -> void:
	var player_name := _name.text.strip_edges()
	new_run.emit(player_name if player_name != "" else "Hero", _class, _difficulty)
