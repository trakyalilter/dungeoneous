class_name BattleScreen
extends Control
## Battle stage, action buttons (with damage previews and tooltips), consumables and relics.

signal action(key: String)

const ACTIONS := ["a", "s", "f", "d", "h", "r"]

var stage := BattleStage.new()
var _buttons := {}
var _item_row: HBoxContainer
var _relic_row: HFlowContainer
var _state: GameState
var _enemy: EnemyData


func _ready() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(stage)

	var bar := UiKit.panel(UiKit.PANEL, 10)
	v.add_child(bar)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	bar.add_child(bottom)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	for key in ACTIONS:
		var b := UiKit.button("", func() -> void: action.emit(key))
		b.custom_minimum_size = Vector2(124, 58)
		b.add_theme_font_size_override("font_size", 14)
		b.mouse_entered.connect(_hover.bind(key))
		b.mouse_exited.connect(_hover.bind(""))
		grid.add_child(b)
		_buttons[key] = b
	bottom.add_child(grid)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 4)
	bottom.add_child(side)
	side.add_child(UiKit.label("Items (free action)  -  keys 1 2 3", 12, GameLog.GRAY))
	_item_row = HBoxContainer.new()
	_item_row.add_theme_constant_override("separation", 6)
	side.add_child(_item_row)
	_relic_row = HFlowContainer.new()
	_relic_row.add_theme_constant_override("h_separation", 4)
	side.add_child(_relic_row)


## Hovering an action shows the HP it would take off the enemy.
func _hover(key: String) -> void:
	if _state == null or key == "" or _buttons[key].disabled:
		stage.preview_damage([])
		return
	var p := _state.player
	if key.begins_with("i"):
		var idx := int(key.substr(1))
		stage.preview_damage([8 + 2 * p.level, 8 + 2 * p.level] if idx < p.items.size() and p.items[idx] == "bomb" else [])
	else:
		stage.preview_damage(Combat.preview(p, _enemy, key))


func refresh(state: GameState, enemy: EnemyData, busy: bool) -> void:
	_state = state
	_enemy = enemy
	stage.set_turn(not busy)
	if busy:
		stage.preview_damage([])
	var p := state.player
	_set_button("a", "Attack", _range_text(p, enemy, "a"), "A",
			"Basic attack: ATK %d, +/-1 damage. %d%% crit chance, 10%% miss chance." % [p.atk, roundi(p.crit_chance * 100)], busy)
	_set_skill("s", p.skill_name, p.skill_cooldown, true, p, enemy, busy)
	_set_skill("f", p.ult_name, p.ult_cooldown, p.ult_unlocked, p, enemy, busy)
	_set_button("d", "Defend", "half damage" if not p.has_relic("anchor") else "quarter damage", "D",
			"Take %s damage from the next enemy turn. Best against heavy hits." % ("75% less" if p.has_relic("anchor") else "half"), busy)
	_set_button("h", "Potion x%d" % p.potions, "+%d HP" % mini(p.heal_amount, p.max_hp - p.hp) if p.hp < p.max_hp else "full HP", "H",
			"Drink a potion: heal %d HP and cure poison." % p.heal_amount, busy or p.potions == 0)
	if state.party:
		_set_button("r", "Run", "not with a party", "R", "Your party fights together: no running away.", true)
	else:
		_set_button("r", "Run", "%d%% chance" % roundi(p.run_chance * 100), "R",
				"Try to flee. Can't flee bosses. Failing still gives the enemy a turn.", busy or enemy.boss)
	# glow on Defend when a big hit is coming
	_buttons["d"].modulate = Color(1.35, 1.35, 0.6) if enemy.intent in ["heavy", "special"] and not busy else Color.WHITE

	for c in _item_row.get_children():
		c.queue_free()
	for i in Config.MAX_ITEMS:
		var b := UiKit.button("", func() -> void: action.emit("i%d" % i))
		b.custom_minimum_size = Vector2(48, 44)
		b.mouse_entered.connect(_hover.bind("i%d" % i))
		b.mouse_exited.connect(_hover.bind(""))
		if i < p.items.size():
			var info: Dictionary = Config.CONSUMABLES[p.items[i]]
			b.tooltip_text = "%d. %s: %s" % [i + 1, info["name"], info["desc"]]
			var icon := GameIcon.make(p.items[i], 30)
			icon.size = Vector2(30, 30)
			icon.position = Vector2(9, 7)
			b.add_child(icon)
			b.disabled = busy
		else:
			b.text = "-"
			b.disabled = true
			b.tooltip_text = "Empty slot"
		_item_row.add_child(b)

	for c in _relic_row.get_children():
		c.queue_free()
	if not p.relics.is_empty():
		_relic_row.add_child(UiKit.label("Relics:", 12, GameLog.GRAY))
	for id in p.relics:
		var info := Progression.relic_info(id)
		_relic_row.add_child(GameIcon.make(id, 26, "%s: %s" % [info["name"], info["desc"]]))


func _range_text(p: PlayerData, enemy: EnemyData, key: String) -> String:
	var r := Combat.preview(p, enemy, key)
	if r.is_empty():
		return ""
	return "%d dmg" % r[0] if r[0] == r[1] else "%d-%d dmg" % r


func _set_skill(key: String, skill: String, cd: int, unlocked: bool, p: PlayerData, enemy: EnemyData, busy: bool) -> void:
	var sub := ""
	if not unlocked:
		sub = "unlocks Lv%d" % Config.ULT_LEVEL
	elif cd > 0:
		sub = "ready in %d" % cd
	else:
		sub = _range_text(p, enemy, key)
		if sub == "":
			sub = "ready"
	_set_button(key, skill, sub, key.to_upper(), Config.SKILL_DESC[skill], busy or not unlocked or cd > 0)


func _set_button(key: String, title: String, sub: String, hotkey: String, tip: String, disabled: bool) -> void:
	var b: Button = _buttons[key]
	b.text = "%s [%s]\n%s" % [title, hotkey, sub]
	b.tooltip_text = tip
	b.disabled = disabled
