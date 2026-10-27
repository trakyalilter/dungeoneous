class_name RestScreen
extends Control
## Campfire node: rest (heal) or train (+1 ATK).

signal chosen(train: bool)

var _view := CreatureView.new()
var _rest: Button
var _info: Label


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	center.add_child(row)
	_view.campfire = true
	_view.custom_minimum_size = Vector2(400, 280)
	row.add_child(_view)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(380, 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	row.add_child(v)
	v.add_child(UiKit.heading("Campfire", 34))
	_info = UiKit.label("", 16)
	v.add_child(_info)
	_rest = UiKit.button("", func() -> void: chosen.emit(false))
	_rest.custom_minimum_size = Vector2(0, 50)
	v.add_child(_rest)
	var train := UiKit.button("Train - +1 ATK permanently", func() -> void: chosen.emit(true))
	train.custom_minimum_size = Vector2(0, 50)
	v.add_child(train)


func open(state: GameState) -> void:
	var p := state.player
	_view.show_kind(p.char_class)
	_info.text = "HP %d/%d. The fire crackles warmly." % [p.hp, p.max_hp]
	var heal := mini(roundi(p.max_hp * Config.REST_HEAL), p.max_hp - p.hp)
	_rest.text = "Rest - heal %d HP" % heal if heal > 0 else "Rest - already at full HP"
	_rest.disabled = heal == 0
