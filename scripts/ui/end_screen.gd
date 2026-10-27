class_name EndScreen
extends Control
## Victory or defeat summary, souls earned, achievements unlocked this run.

signal done

var _title: Label
var _view := CreatureView.new()
var _body: RichTextLabel


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(520, 0)
	v.add_theme_constant_override("separation", 12)
	center.add_child(v)
	_title = UiKit.heading("", 60)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 10)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	v.add_child(_title)
	_view.custom_minimum_size = Vector2(0, 170)
	v.add_child(_view)
	_body = UiKit.rich(17)
	v.add_child(_body)
	v.add_child(UiKit.button("Return to title", func() -> void: done.emit()))


func show_result(state: GameState, souls: int, new_best: bool, fresh: Array) -> void:
	var p := state.player
	_title.text = "VICTORY!" if state.won else "YOU DIED"
	_title.add_theme_color_override("font_color", Color(GameLog.YELLOW if state.won else GameLog.RED))
	_view.show_kind(p.char_class)
	_view.creature.rotation = 0.0 if state.won else -1.4
	_view.creature.modulate = Color.WHITE if state.won else Color(0.6, 0.6, 0.7)
	var lines := PackedStringArray()
	lines.append("[center]%s the %s" % [GameLog.esc(p.name), p.char_class])
	if state.won:
		lines.append("destroyed the %s on %s!" % [Config.FLOOR_INFO[-1]["boss_title"], state.difficulty])
	else:
		lines.append("fell on floor %d, %s (%s)" % [state.floor_num, state.floor_name(), state.difficulty])
	lines.append("")
	lines.append("Level %d   -   %d enemies defeated   -   %d bosses" % [p.level, p.kills, state.bosses_killed])
	lines.append("[color=%s]+%d souls[/color]" % [GameLog.MAGENTA, souls])
	if new_best:
		lines.append("[color=%s]NEW BEST RUN![/color]" % GameLog.YELLOW)
	for id in fresh:
		lines.append("[color=%s]Achievement: %s[/color]" % [GameLog.YELLOW, Config.ACHIEVEMENTS[id]["name"]])
	lines.append("[/center]")
	_body.text = "\n".join(lines)
