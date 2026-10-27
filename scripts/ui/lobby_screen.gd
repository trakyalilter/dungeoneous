class_name LobbyScreen
extends Control
## LAN co-op lobby. Page "setup": pick a name and class, then host a party or join one found on the network
## (or by typing the host's IP). Page "room": the party roster; the host picks a difficulty and starts.

signal host_requested(player_name: String, cls: String)
signal join_requested(ip: String, player_name: String, cls: String)
signal start_requested(difficulty: String)
signal leave_requested

var _pages := {}
var _name: LineEdit
var _class_pick: OptionButton
var _classes: Array = []
var _hosts_list: VBoxContainer
var _ip: LineEdit
var _status: Label
var _roster_list: VBoxContainer
var _room_title: Label
var _room_hint: Label
var _host_box: VBoxContainer
var _difficulty := "Normal"
var _start: Button


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(560, 0)
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	var title := UiKit.heading("Play with friends", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UiKit.label("Co-op over your local network (same Wi-Fi or LAN). Up to %d heroes." % Net.MAX_PLAYERS, 14, GameLog.GRAY)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	_pages["setup"] = _build_setup()
	_pages["room"] = _build_room()
	for page in _pages.values():
		col.add_child(page)
	_status = UiKit.label("", 14, GameLog.RED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	_show("setup")


func _build_setup() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 12)
	form.add_theme_constant_override("v_separation", 8)
	v.add_child(form)
	form.add_child(UiKit.label("Name", 16))
	_name = LineEdit.new()
	_name.max_length = 16
	_name.placeholder_text = "Hero"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_name)
	form.add_child(UiKit.label("Class", 16))
	_class_pick = OptionButton.new()
	_class_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_class_pick)

	var host := UiKit.button("Host a party", func() -> void: host_requested.emit(_player_name(), _picked_class()))
	host.custom_minimum_size = Vector2(0, 48)
	host.add_theme_font_size_override("font_size", 18)
	v.add_child(host)
	v.add_child(HSeparator.new())
	v.add_child(UiKit.label("Parties on your network", 15, GameLog.CYAN))
	_hosts_list = VBoxContainer.new()
	_hosts_list.add_theme_constant_override("separation", 6)
	v.add_child(_hosts_list)
	set_hosts([])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_ip = LineEdit.new()
	_ip.placeholder_text = "or type the host's IP, e.g. 192.168.1.20"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ip)
	row.add_child(UiKit.button("Join", func() -> void:
		if _ip.text.strip_edges() != "":
			join_requested.emit(_ip.text.strip_edges(), _player_name(), _picked_class())))
	v.add_child(row)
	v.add_child(UiKit.button("Back", func() -> void: leave_requested.emit()))
	return v


func _build_room() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_room_title = UiKit.heading("", 26, GameLog.CYAN)
	v.add_child(_room_title)
	_roster_list = VBoxContainer.new()
	_roster_list.add_theme_constant_override("separation", 6)
	v.add_child(_roster_list)
	_room_hint = UiKit.label("", 14, GameLog.GRAY)
	_room_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_room_hint)
	_host_box = VBoxContainer.new()
	_host_box.add_theme_constant_override("separation", 8)
	v.add_child(_host_box)
	var diffs := HBoxContainer.new()
	diffs.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for d in Config.DIFFICULTIES:
		var b := UiKit.button(d, func() -> void: _difficulty = d)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = d == _difficulty
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		diffs.add_child(b)
	_host_box.add_child(diffs)
	_start = UiKit.button("Set off!", func() -> void: start_requested.emit(_difficulty))
	_start.custom_minimum_size = Vector2(0, 48)
	_start.add_theme_font_size_override("font_size", 18)
	_host_box.add_child(_start)
	v.add_child(UiKit.button("Leave", func() -> void: leave_requested.emit()))
	return v


func _show(page: String) -> void:
	for k in _pages:
		_pages[k].visible = k == page


func _player_name() -> String:
	var n := _name.text.strip_edges()
	return n if n != "" else "Hero"


func _picked_class() -> String:
	return _classes[_class_pick.selected] if _class_pick.selected >= 0 else "Warrior"


## Fresh setup page. Classes locked in the Soul Shrine are left out.
func open(meta: MetaProgress, default_name: String, default_class: String) -> void:
	_show("setup")
	set_status("")
	_name.text = default_name
	_class_pick.clear()
	_classes.clear()
	for c in Config.CLASSES:
		if meta.class_unlocked(c):
			_classes.append(c)
			_class_pick.add_item(c)
	_class_pick.selected = maxi(0, _classes.find(default_class))


func set_status(text: String, hex: String = GameLog.RED) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(hex))


## Games heard on the LAN: [{"ip", "name", "players", "max", "open"}].
func set_hosts(hosts: Array) -> void:
	for c in _hosts_list.get_children():
		c.queue_free()
	if hosts.is_empty():
		_hosts_list.add_child(UiKit.label("Searching...  (ask a friend to press \"Host a party\")", 14, "#888888"))
		return
	for h in hosts:
		var full: bool = int(h.get("players", 0)) >= int(h.get("max", Net.MAX_PLAYERS)) or not h.get("open", true)
		var b := UiKit.button("%s's party  -  %d/%d players  -  %s%s" % [h.get("name", "?"), int(h.get("players", 0)),
				int(h.get("max", Net.MAX_PLAYERS)), h["ip"], "  (started)" if not h.get("open", true) else ""],
				func() -> void: join_requested.emit(String(h["ip"]), _player_name(), _picked_class()))
		b.disabled = full
		_hosts_list.add_child(b)


## Show the party room with the current roster.
func show_room(roster: Array, is_host: bool, my_slot: int) -> void:
	_show("room")
	set_status("")
	_room_title.text = "%s's party" % (roster[0]["name"] if not roster.is_empty() else "?")
	for c in _roster_list.get_children():
		c.queue_free()
	for i in roster.size():
		var entry: Dictionary = roster[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var view := CreatureView.new()
		view.custom_minimum_size = Vector2(56, 56)
		row.add_child(view)
		view.show_kind.call_deferred(entry["class"])
		var text := "%s  -  %s%s%s" % [entry["name"], entry["class"], "  (host)" if i == 0 else "", "  (you)" if i == my_slot else ""]
		var l := UiKit.label(text, 17, GameLog.YELLOW if i == my_slot else "#dddddd")
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		_roster_list.add_child(row)
	for i in range(roster.size(), Net.MAX_PLAYERS):
		_roster_list.add_child(UiKit.label("   empty seat", 14, "#666666"))
	_host_box.visible = is_host
	if is_host:
		_room_hint.text = "Friends on the same network will see your party in their list. If they can't, they can type one of your IPs: %s" \
				% ", ".join(local_ips())
	else:
		_room_hint.text = "Waiting for the host to set off..."


## This PC's LAN addresses (IPv4, no loopback), for friends who join by IP.
static func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return out
