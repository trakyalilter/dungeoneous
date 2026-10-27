class_name SettingsPanel
extends Control
## Settings dialog: music / effects volume, battle speed, fullscreen. Saved to user://settings.cfg.

signal closed

const SPEEDS := {"Normal": 1.0, "Fast": 1.6, "Very fast": 2.5}

var sfx: Sfx
var battle_speed := 1.0
var _music: HSlider
var _effects: HSlider
var _speed: OptionButton
var _fullscreen: CheckButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := UiKit.panel(Color("#242433"), 20)
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	v.add_child(UiKit.heading("Settings", 28))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	grid.add_child(UiKit.label("Music volume", 16))
	_music = _slider()
	grid.add_child(_music)
	grid.add_child(UiKit.label("Effects volume", 16))
	_effects = _slider()
	grid.add_child(_effects)
	grid.add_child(UiKit.label("Battle speed", 16))
	_speed = OptionButton.new()
	for s in SPEEDS:
		_speed.add_item(s)
	_speed.item_selected.connect(func(_i: int) -> void: _apply())
	grid.add_child(_speed)
	grid.add_child(UiKit.label("Fullscreen", 16))
	_fullscreen = CheckButton.new()
	_fullscreen.toggled.connect(func(_on: bool) -> void: _apply())
	grid.add_child(_fullscreen)
	v.add_child(UiKit.button("Close", func() -> void:
		_save()
		visible = false
		closed.emit()))
	_load()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		get_viewport().set_input_as_handled()


func _slider() -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(200, 24)
	s.value_changed.connect(func(_v: float) -> void: _apply())
	return s


func open() -> void:
	visible = true


func _apply() -> void:
	if sfx:
		sfx.set_volumes(_music.value, _effects.value)
	battle_speed = SPEEDS[_speed.get_item_text(_speed.selected)]
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen.button_pressed else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode and not DisplayServer.get_name() == "headless":
		DisplayServer.window_set_mode(mode)


func _load() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Storage.settings_path)
	_music.set_value_no_signal(cfg.get_value("audio", "music", 0.7))
	_effects.set_value_no_signal(cfg.get_value("audio", "effects", 0.8))
	var speed_name: String = cfg.get_value("game", "speed", "Normal")
	for i in _speed.item_count:
		if _speed.get_item_text(i) == speed_name:
			_speed.select(i)
	_fullscreen.set_pressed_no_signal(cfg.get_value("video", "fullscreen", false))
	_apply()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", _music.value)
	cfg.set_value("audio", "effects", _effects.value)
	cfg.set_value("game", "speed", _speed.get_item_text(_speed.selected))
	cfg.set_value("video", "fullscreen", _fullscreen.button_pressed)
	cfg.save(Storage.settings_path)
