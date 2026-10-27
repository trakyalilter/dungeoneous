class_name ChoiceOverlay
extends Control
## Modal dialog used for events, loot, perks, relics, pause menu and floor transitions.
##   var index := await overlay.ask("Title", "[b]bbcode[/b] body", [{"label": "A"}, {"label": "B", "disabled": true}])
## Options may have "icon" (GameIcon id), "tip" (tooltip) and, for cards, "desc".
## cards = true lays options out side by side as big cards (perks, boss relics).
## Number keys 1-9 pick an option; Esc picks the option marked "cancel": true, if any.

signal chosen(index: int)

var _box: PanelContainer
var _title: Label
var _body: RichTextLabel
var _list: VBoxContainer
var _cards: HBoxContainer
var _enabled: Array[bool] = []
var _cancel := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = UiKit.panel(Color("#242433"), 22)
	_box.custom_minimum_size = Vector2(480, 0)
	var sb: StyleBoxFlat = _box.get_theme_stylebox("panel")
	sb.border_color = Color("#5a5070")
	sb.set_border_width_all(2)
	center.add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_box.add_child(v)
	_title = UiKit.heading("", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_body = UiKit.rich(16)
	v.add_child(_body)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	v.add_child(_list)
	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override("separation", 14)
	v.add_child(_cards)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key and key.pressed and not key.echo:
		var n := key.keycode - KEY_1
		if n >= 0 and n < _enabled.size() and _enabled[n]:
			UiKit.click()
			chosen.emit(n)
		elif key.keycode == KEY_ESCAPE and _cancel >= 0:
			chosen.emit(_cancel)
		get_viewport().set_input_as_handled()  # nothing behind the dialog reacts to keys


## Show the dialog and wait for a choice.
func ask(title: String, body: String, options: Array, cards: bool = false) -> int:
	_title.text = title
	_body.text = body
	_body.visible = body != ""
	for c in _list.get_children() + _cards.get_children():
		c.queue_free()
	_enabled.clear()
	_cancel = -1
	_list.visible = not cards
	_cards.visible = cards
	for i in options.size():
		var opt: Dictionary = options[i]
		var b := _card(opt, i) if cards else _row(opt, i)
		b.disabled = opt.get("disabled", false)
		b.tooltip_text = opt.get("tip", "")
		(_cards if cards else _list).add_child(b)
		_enabled.append(not b.disabled)
		if opt.get("cancel", false):
			_cancel = i
	visible = true
	_box.pivot_offset = _box.size / 2
	_box.scale = Vector2(0.85, 0.85)
	_box.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_box, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_box, "modulate:a", 1.0, 0.12)
	var index: int = await chosen
	visible = false
	return index


func _row(opt: Dictionary, i: int) -> Button:
	var has_icon: bool = opt.get("icon", "") != ""
	var b := UiKit.button(("         %d. %s" if has_icon else "%d. %s") % [i + 1, opt["label"]], func() -> void: chosen.emit(i))
	b.custom_minimum_size = Vector2(0, 48 if has_icon else 44)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if has_icon:
		var icon := GameIcon.make(opt["icon"], 34)
		icon.size = Vector2(34, 34)
		icon.position = Vector2(10, 7)
		b.add_child(icon)
	return b


## A tall card: big icon, name, description, key hint.
func _card(opt: Dictionary, i: int) -> Button:
	var b := UiKit.button("", func() -> void: chosen.emit(i))
	b.custom_minimum_size = Vector2(190, 230)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var icon_row := CenterContainer.new()
	icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_row.add_child(GameIcon.make(opt.get("icon", "trait"), 64))
	v.add_child(icon_row)
	for part in [[opt["label"], 18, GameLog.YELLOW], [opt.get("desc", ""), 14, "#d0d0dc"], ["[%d]" % (i + 1), 12, GameLog.GRAY]]:
		var l := UiKit.label(part[0], part[1], part[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	return b
