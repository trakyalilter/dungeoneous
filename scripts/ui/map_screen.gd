class_name MapScreen
extends Control
## Floor map on the left, character sheet on the right. In co-op the sheet also lists the party
## and the map takes votes.

signal node_chosen(row: int, idx: int)
signal quit_run

var view := MapView.new()
var _track := FloorTrack.new()
var _floor_label: Label
var _hint: Label
var _sheet: RichTextLabel
var _banner: Label
var _relics: HFlowContainer
var _items: HBoxContainer
var _hp_bar: ProgressBar
var _hp_text: Label
var _xp_bar: ProgressBar
var _xp_text: Label
var _party_box: RichTextLabel
var _quit: Button
var _state: GameState


func _ready() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	var left := UiKit.panel(Color("#1b1924"), 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	_floor_label = UiKit.heading("", 26)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(_floor_label)
	_track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lv.add_child(_track)
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.node_chosen.connect(func(r: int, i: int) -> void: node_chosen.emit(r, i))
	view.hovered.connect(func(text: String) -> void: _hint.text = text if text != "" else _default_hint())
	lv.add_child(view)
	_hint = UiKit.label("", 14, "#bbbbbb")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(_hint)
	lv.add_child(MapLegend.new())

	var right := UiKit.panel(UiKit.PANEL, 14)
	right.custom_minimum_size = Vector2(330, 0)
	row.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	var corner_gap := Control.new()  # keeps the settings/sound buttons from covering the sheet
	corner_gap.custom_minimum_size = Vector2(0, 26)
	rv.add_child(corner_gap)
	_hp_bar = UiKit.bar(20)
	var hp_text := UiKit.label("", 13)
	hp_text.add_theme_constant_override("outline_size", 4)
	hp_text.add_theme_color_override("font_outline_color", Color.BLACK)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_bar.add_child(hp_text)
	_hp_text = hp_text
	rv.add_child(_hp_bar)
	_xp_bar = UiKit.bar(16)
	_xp_text = UiKit.label("", 12)
	_xp_text.add_theme_constant_override("outline_size", 4)
	_xp_text.add_theme_color_override("font_outline_color", Color.BLACK)
	_xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_xp_bar.add_child(_xp_text)
	rv.add_child(_xp_bar)
	_party_box = UiKit.rich(14)
	_party_box.visible = false
	rv.add_child(_party_box)
	_sheet = UiKit.rich(14)
	_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheet.fit_content = false
	_sheet.scroll_active = true
	rv.add_child(_sheet)
	rv.add_child(UiKit.label("Relics (hover for details)", 13, GameLog.GRAY))
	_relics = HFlowContainer.new()
	_relics.add_theme_constant_override("h_separation", 6)
	rv.add_child(_relics)
	rv.add_child(UiKit.label("Items", 13, GameLog.GRAY))
	_items = HBoxContainer.new()
	_items.add_theme_constant_override("separation", 6)
	rv.add_child(_items)
	_quit = UiKit.button("Save & quit to title", func() -> void: quit_run.emit())
	rv.add_child(_quit)

	_banner = UiKit.heading("", 50)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.visible = false
	add_child(_banner)


func _default_hint() -> String:
	if _state and _state.party:
		return "Vote for the next room by clicking it. Majority wins; the host breaks ties."
	return "Choose your path. Glowing rooms are reachable."


func refresh(state: GameState) -> void:
	_state = state
	view.state = state
	view.vote_mode = state.party
	view.votes = {}
	var kinds := [state.player.char_class]
	for p in state.players:
		if p != state.player:
			kinds.append(p.char_class)
	view.party_kinds = kinds
	_quit.text = "Leave the party" if state.party else "Save & quit to title"
	_party_box.visible = state.party
	if state.party:
		var lines := PackedStringArray(["[color=%s]Party[/color]" % GameLog.GRAY])
		for p in state.players:
			var dot: String = MapView.VOTE_COLORS[p.slot % MapView.VOTE_COLORS.size()].to_html(false)
			lines.append("[color=#%s][b]%s[/b][/color]%s  Lv%d %s  [color=%s]HP %d/%d[/color]" % [dot, GameLog.esc(p.name),
					" (you)" if p == state.player else "", p.level, p.char_class,
					GameLog.GREEN if p.hp > p.max_hp / 2 else GameLog.RED, p.hp, p.max_hp])
		_party_box.text = "\n".join(lines)
	view.floor_num = state.floor_num
	view.map = state.map
	view.hero_kind = state.player.char_class
	_track.floor_num = state.floor_num
	_floor_label.text = "Floor %d of %d - %s" % [state.floor_num, Config.FLOORS, state.floor_name()]
	_hint.text = _default_hint()
	UiKit.set_bar(_hp_bar, state.player.hp, state.player.max_hp)
	_hp_text.text = "HP %d / %d" % [state.player.hp, state.player.max_hp]
	var need := Config.exp_needed(state.player.level)
	UiKit.set_bar(_xp_bar, state.player.xp, need, "#4fc3f7")
	_xp_text.text = "Level %d  -  EXP %d / %d" % [state.player.level, state.player.xp, need]
	_sheet.text = UiKit.character_sheet(state) + "\n\n[color=%s]%s difficulty[/color]" % [GameLog.GRAY, state.difficulty]
	for c in _relics.get_children() + _items.get_children():
		c.queue_free()
	for id in state.player.relics:
		var info := Progression.relic_info(id)
		_relics.add_child(GameIcon.make(id, 30, "%s: %s" % [info["name"], info["desc"]]))
	if state.player.relics.is_empty():
		_relics.add_child(UiKit.label("none yet", 13))
	for id in state.player.items:
		var info: Dictionary = Config.CONSUMABLES[id]
		_items.add_child(GameIcon.make(id, 30, "%s: %s" % [info["name"], info["desc"]]))
	if state.player.items.is_empty():
		_items.add_child(UiKit.label("empty", 13))


## Co-op: show everyone's votes and the countdown.
func show_votes(votes: Dictionary, seconds_left: int) -> void:
	view.votes = votes
	if _state == null or votes.is_empty():
		_hint.text = _default_hint()
		return
	var names := PackedStringArray()
	for slot in votes:
		if int(slot) < _state.players.size():
			names.append(_state.players[int(slot)].name)
	_hint.text = "Voted: %s  -  %d/%d  -  deciding in %ds" % [", ".join(names), votes.size(), _state.players.size(), seconds_left]


## Big "Floor 2: The Sunken Crypt" title that fades away.
func announce(state: GameState) -> void:
	_banner.text = "Floor %d\n%s" % [state.floor_num, state.floor_name()]
	_banner.visible = true
	_banner.size = Vector2(size.x, 140)
	_banner.position = Vector2(0, size.y * 0.35)
	_banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.2)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void: _banner.visible = false)
