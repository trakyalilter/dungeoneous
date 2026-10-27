extends Control
## Game flow: title -> map -> (fight | shop | rest | event | treasure) -> map ... -> boss -> next floor ... -> end.
## Each screen is its own script under scripts/ui; this file wires them together.
## Game logic queues events (GameLog); the battle stage animates them one by one.
## Co-op: the Net node (scripts/net) talks to the other players; the "co-op" section below reacts to it.
## Fights are resolved by the host; personal rooms (shop, campfire, events, loot) run here and report back.

const KEY_ACTIONS := {KEY_A: "a", KEY_S: "s", KEY_F: "f", KEY_D: "d", KEY_H: "h", KEY_R: "r", KEY_1: "i0", KEY_2: "i1", KEY_3: "i2"}

var meta: MetaProgress
var state: GameState
var enemy: EnemyData
var busy := false  # true while animations or dialogs run in battle
var sfx := Sfx.new()
var net := Net.new()

var title := TitleScreen.new()
var lobby := LobbyScreen.new()
var map_screen := MapScreen.new()
var battle := BattleScreen.new()
var shop := ShopScreen.new()
var rest := RestScreen.new()
var end_screen := EndScreen.new()
var overlay := ChoiceOverlay.new()
var settings := SettingsPanel.new()
var _screens: Array[Control] = []
var _current: Control
var _fade := ColorRect.new()
var _toast: Label
var _waiting: Label  # co-op: "Waiting for: ..." while friends finish their rooms
var _sound_button: Button
var _corner: HBoxContainer
var _fight_from := [-1, -1]  # map position before entering the current room
var _fight_node := [-1, -1]
var _animating := false      # co-op: a batch of host events is playing
var _ready_slots: Array = [] # co-op: heroes that locked in their action this round
var _in_lobby := false       # co-op: on the lobby screen (it may still be fading in)

const PERK_ICONS := {"tough": "heart", "strong": "atk", "keen": "clover", "armor": "armor", "alchemist": "potion",
		"thorns": "cactus", "vampiric": "skull", "greedy": "gold", "swift": "hourglass", "second_wind": "phoenix"}


func _ready() -> void:
	randomize()
	theme = UiKit.make_theme()
	meta = Storage.load_meta()
	add_child(sfx)
	UiKit.sfx = sfx
	net.name = "Net"  # same path on every machine, so RPCs find it
	add_child(net)

	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	for screen in [title, lobby, map_screen, battle, shop, rest, end_screen]:
		screen.visible = false
		margin.add_child(screen)
		_screens.append(screen)
	battle.stage.sfx = sfx
	shop.sfx = sfx

	title.new_run.connect(_on_new_run)
	title.continue_run.connect(_on_continue)
	title.open_settings.connect(settings.open)
	title.open_multiplayer.connect(_open_lobby)
	map_screen.node_chosen.connect(_on_node_chosen)
	map_screen.quit_run.connect(func() -> void:
		if state.party:
			_leave_party()
			return
		Storage.save_game(state)
		show_title())
	battle.action.connect(_on_action)
	shop.changed.connect(func() -> void:
		if not state.party:
			Storage.save_game(state)
		_check_achievements())
	shop.leave.connect(_room_done)
	rest.chosen.connect(_on_rest)
	end_screen.done.connect(show_title)
	_wire_coop()

	# top-right corner: settings + sound (the battle HUD leaves this spot free)
	var corner := HBoxContainer.new()
	corner.add_theme_constant_override("separation", 6)
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.position = Vector2(-84, 4)
	_sound_button = UiKit.icon_button("sound", "Mute / unmute (M)", _toggle_sound, 34)
	corner.add_child(UiKit.icon_button("gear", "Settings", settings.open, 34))
	corner.add_child(_sound_button)
	add_child(corner)
	_corner = corner

	add_child(overlay)
	settings.sfx = sfx
	add_child(settings)
	_toast = UiKit.label("", 18, GameLog.YELLOW)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.modulate.a = 0.0
	add_child(_toast)
	_waiting = UiKit.label("", 17, GameLog.CYAN)
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting.add_theme_constant_override("outline_size", 8)
	_waiting.add_theme_color_override("font_outline_color", Color.BLACK)
	_waiting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_waiting)
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	show_title()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo:
		return
	if key.keycode == KEY_M:
		_toggle_sound()
	elif key.keycode == KEY_ESCAPE and _current in [map_screen, battle, shop, rest] and not busy and not settings.visible:
		_pause_menu()
	elif battle.visible and KEY_ACTIONS.has(key.keycode):
		_on_action(KEY_ACTIONS[key.keycode])


# ---------------------------------------------------------------- screen plumbing

## Fade to black, swap screens, fade back in.
func go(screen: Control) -> void:
	if screen == _current:
		return
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	if _current:
		var out := create_tween()
		out.tween_property(_fade, "color:a", 1.0, 0.18)
		await out.finished
	for s in _screens:
		s.visible = s == screen
	_current = screen
	Engine.time_scale = settings.battle_speed if screen == battle else 1.0
	var fade_in := create_tween()
	fade_in.tween_property(_fade, "color:a", 0.0, 0.25)
	await fade_in.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _toggle_sound() -> void:
	sfx.set_muted(not sfx.muted)
	(_sound_button.get_child(0) as GameIcon).set_id("mute" if sfx.muted else "sound")


func toast(text: String) -> void:
	_toast.text = text
	_toast.size = Vector2(size.x, 40)
	_toast.position = Vector2(0, -40)
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(_toast, "position:y", 24.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


## Esc during a run: resume, settings, or save & quit (leave the party in co-op).
func _pause_menu() -> void:
	if overlay.visible:
		return
	var in_battle := _current == battle
	var quit_label := "Leave the party" if state.party else "Save & quit to title" + (" (this fight restarts)" if in_battle else "")
	var pick := await overlay.ask("Paused", "[center]%s - Floor %d[/center]" % [state.floor_name(), state.floor_num], [
		{"label": "Resume", "cancel": true},
		{"label": "Settings"},
		{"label": quit_label},
	])
	match pick:
		1:
			settings.open()
		2:
			if state.party:
				_leave_party()
				return
			if in_battle:
				state.map.pos_row = _fight_from[0]
				state.map.pos_idx = _fight_from[1]
				state.map.rows[_fight_node[0]][_fight_node[1]].done = false
			Storage.save_game(state)
			show_title()


func _check_achievements() -> Array:
	var fresh := meta.check(state)
	for id in fresh:
		toast("Achievement unlocked: %s" % Config.ACHIEVEMENTS[id]["name"])
		sfx.play("levelup")
	if not fresh.is_empty():
		Storage.save_meta(meta)
	return fresh


## Animate queued events on the battle stage. Log lines are not shown (the stage shows everything visually).
func _play_events() -> void:
	await _play_list(GameLog.take_events())


func _play_list(events: Array) -> void:
	for ev in events:
		if ev.type != "log" and battle.visible:
			await battle.stage.play(ev)
			battle.stage.refresh_hud()


## Outside battle: nothing to animate.
func _flush_events() -> void:
	GameLog.take_events()


# ---------------------------------------------------------------- title / map

func show_title() -> void:
	_in_lobby = false
	if net.active:
		net.leave()
	_set_waiting([])
	title.refresh(meta, Storage.load_highscore(), Storage.load_game())
	sfx.play_music("explore")
	go(title)


func _on_new_run(player_name: String, cls: String, difficulty: String) -> void:
	state = GameState.new(PlayerData.new(player_name, cls), difficulty)
	state.player.apply_meta(meta)
	Storage.delete_save()
	GameLog.clear()
	show_map(true)


func _on_continue() -> void:
	state = Storage.load_game()
	if state == null:
		show_title()
		return
	GameLog.clear()
	show_map()


func show_map(announce: bool = false) -> void:
	_flush_events()
	if not state.party:
		Storage.save_game(state)
	map_screen.refresh(state)
	sfx.play_music("explore")
	await go(map_screen)
	if announce:
		map_screen.announce(state)


func _on_node_chosen(r: int, i: int) -> void:
	if _current != map_screen or overlay.visible:
		return
	sfx.play("click")
	if state.party:  # co-op: a click is a vote; the host decides where the party goes
		net.vote(r, i)
		return
	_fight_from = [state.map.pos_row, state.map.pos_idx]
	_fight_node = [r, i]
	var node := state.map.move_to(r, i)
	match node.type:
		"fight", "elite", "boss":
			start_fight(node.type)
		_:
			_open_room(node.type)


## Shop, campfire, treasure or event. In co-op this is your personal part of the room.
func _open_room(type: String) -> void:
	match type:
		"rest":
			rest.open(state)
			go(rest)
		"shop":
			shop.open(state, Progression.shop_stock(state))
			go(shop)
		"treasure":
			await _treasure()
			_room_done()
		"event":
			await _event()
			_room_done()


## A room is finished: back to the map in solo; in co-op report back and wait for the others.
func _room_done() -> void:
	if state == null:
		return
	if not state.party:
		show_map()
		return
	if not net.active:
		return  # the connection dropped while a dialog was open
	net.personal_done(state.player.to_dict())
	map_screen.refresh(state)
	go(map_screen)


# ---------------------------------------------------------------- non-combat nodes

func _on_rest(train: bool) -> void:
	if train:
		Progression.train(state.player)
		toast("+1 ATK")
		sfx.play("skill")
	else:
		toast("+%d HP" % Progression.rest(state.player))
		sfx.play("heal")
	_room_done()


func _treasure() -> void:
	var chest := Progression.open_treasure(state)
	sfx.play("coin")
	await overlay.ask("Treasure!", "You pry open an old chest and find [color=%s]%d gold[/color]." % [
			GameLog.YELLOW, chest.gold], [{"label": "Look inside"}])
	await _offer_loot(chest.item)
	await _offer_relic(chest.relic, "Hidden beneath the gear lies a relic.")
	_check_achievements()


## Announce and grant a relic found somewhere ("" = nothing).
func _offer_relic(id: String, story: String) -> void:
	if id == "":
		return
	var info := Progression.relic_info(id)
	Progression.grant_relic(state.player, id)
	sfx.play("levelup")
	await overlay.ask("Relic found!", "%s\n\n[font_size=20][color=%s]%s[/color][/font_size]\n%s" % [
			story, GameLog.MAGENTA, info["name"], info["desc"]], [{"label": "Take it", "icon": id}])


## Boss reward: choose one of up to three relics.
func _choose_boss_relic(choices: Array) -> void:
	if choices.is_empty():
		return
	var options := []
	for id in choices:
		var info := Progression.relic_info(id)
		options.append({"label": info["name"], "desc": info["desc"], "icon": id})
	var pick := await overlay.ask("Boss Relic", "The boss guarded a hoard. Choose one treasure to keep.", options, true)
	Progression.grant_relic(state.player, choices[pick])
	sfx.play("levelup")


func _event() -> void:
	var id := RunEvents.random_id()
	var ev: Dictionary = RunEvents.EVENTS[id]
	var choice := await overlay.ask(ev["title"], ev["text"], RunEvents.options(id, state))
	var result := RunEvents.resolve(id, choice, state)
	await overlay.ask(ev["title"], result.text, [{"label": "Continue"}])
	if result.item:
		await _offer_loot(result.item)
	await _offer_relic(result.relic, "It is yours now.")
	await _choose_perks()
	_check_achievements()


func _offer_loot(item: Item) -> void:
	if item == null:
		return
	var current := state.player.equipped(item.slot)
	var pick := await overlay.ask("Loot!", UiKit.compare_item(item, current), [{"label": "Equip"}, {"label": "Keep current"}])
	if pick == 0:
		state.player.equip(item)
		sfx.play("defend")


func _choose_perks() -> void:
	var p := state.player
	while p.pending_perks > 0:
		p.pending_perks -= 1
		var choices := Progression.perk_choices(p)
		if choices.is_empty():
			return
		var options := []
		for id in choices:
			var perk: Dictionary = Config.PERKS[id]
			options.append({"label": perk["name"], "desc": perk["desc"] + ("\n(you have %d)" % p.perk(id) if p.perk(id) > 0 else ""),
					"icon": PERK_ICONS.get(id, "trait")})
		var pick := await overlay.ask("Level %d!" % p.level, "[center]Choose a perk.[/center]", options, true)
		p.add_perk(choices[pick])
		sfx.play("levelup")


# ---------------------------------------------------------------- combat

func start_fight(kind: String) -> void:
	enemy = EnemyData.for_node(state.floor_num, state.map.pos_row, kind, state.difficulty)
	busy = true
	sfx.play_music("boss" if kind == "boss" else "battle")
	battle.stage.floor_theme = state.floor_num
	await go(battle)
	battle.stage.setup(state.player, enemy, state)
	battle.refresh(state, enemy, busy)
	Combat.start_battle(state.player, enemy)
	await _play_events()
	busy = false
	battle.refresh(state, enemy, busy)


func _on_action(action: String) -> void:
	if busy or overlay.visible or _current != battle:
		return
	if state.party:
		_coop_action(action)
		return
	busy = true
	if not action.begins_with("i"):
		battle.stage.hero.shielded = state.player.shield_wall
	battle.refresh(state, enemy, busy)
	var result := Combat.take_turn(state.player, enemy, action)
	await _play_events()
	match result:
		"win":
			var rewards := Progression.give_rewards(state, enemy)
			await _play_events()
			await get_tree().create_timer(0.3).timeout
			Engine.time_scale = 1.0
			if rewards.item:
				await _offer_loot(rewards.item)
			await _offer_relic(rewards.relic, "The elite was carrying something special.")
			await _choose_boss_relic(rewards.boss_relics)
			await _choose_perks()
			_check_achievements()
			busy = false
			if enemy.boss:
				_boss_cleared()
			else:
				show_map()
			return
		"lose":
			await get_tree().create_timer(0.6).timeout
			busy = false
			end_run()
			return
		"fled":
			busy = false
			show_map()
			return
	busy = false
	battle.stage.hero.shielded = state.player.defending or state.player.shield_wall
	battle.refresh(state, enemy, busy)


func _boss_cleared() -> void:
	if not state.next_floor():
		end_run()
		return
	var healed := state.player.heal(roundi(state.player.max_hp * Config.FLOOR_HEAL))
	await overlay.ask("Floor cleared!", "The %s falls.\nYou descend into [color=%s]%s[/color] and catch your breath (+%d HP)." % [
			Config.FLOOR_INFO[state.floor_num - 2]["boss_title"], GameLog.YELLOW, state.floor_name(), healed],
			[{"label": "Descend"}])
	show_map(true)


func end_run() -> void:
	var fresh := meta.check(state)  # before banking, so kills are not counted twice
	var souls := meta.finish_run(state)
	var new_best := Storage.save_highscore(state)
	if not state.party:  # a co-op run never touches the solo save slot
		Storage.delete_save()
	Storage.save_meta(meta)
	end_screen.show_result(state, souls, new_best, fresh)
	sfx.play_music("explore")
	sfx.play("levelup" if state.won else "death")
	go(end_screen)


# ---------------------------------------------------------------- co-op

func _wire_coop() -> void:
	lobby.host_requested.connect(func(player_name: String, cls: String) -> void:
		var err := net.host_game(player_name, cls, meta.to_dict())
		if err != "":
			lobby.set_status(err))
	lobby.join_requested.connect(func(ip: String, player_name: String, cls: String) -> void:
		var err := net.join_game(ip, player_name, cls, meta.to_dict())
		lobby.set_status(err if err != "" else "Connecting to %s..." % ip, GameLog.RED if err != "" else GameLog.CYAN))
	lobby.start_requested.connect(func(difficulty: String) -> void: net.start_run(difficulty))
	lobby.leave_requested.connect(func() -> void:
		net.leave()
		show_title())
	net.discovery.hosts_changed.connect(lobby.set_hosts)
	net.roster_changed.connect(func(roster: Array) -> void:
		if _in_lobby:
			lobby.show_room(roster, net.is_host, net.my_slot))
	net.connection_lost.connect(_on_connection_lost)
	net.notice.connect(toast)
	net.run_started.connect(func(d: Dictionary) -> void:
		_in_lobby = false
		state = GameState.from_dict(d, net.my_slot)
		GameLog.clear()
		show_map(true))
	net.map_shown.connect(func(d: Dictionary, announce: bool) -> void:
		state = GameState.from_dict(d, net.my_slot)
		_set_waiting([])
		show_map(announce))
	net.votes_changed.connect(func(votes: Dictionary, seconds_left: int) -> void:
		if _current == map_screen:
			map_screen.show_votes(votes, seconds_left))
	net.room_entered.connect(_coop_room)
	net.battle_started.connect(_coop_battle_start)
	net.battle_updated.connect(_coop_battle_update)
	net.ready_changed.connect(func(slots: Array) -> void:
		_ready_slots = slots
		battle.stage.set_ready(slots))
	net.battle_won.connect(_coop_battle_won)
	net.waiting_changed.connect(_set_waiting)
	net.floor_cleared.connect(_coop_floor_cleared)
	net.run_over.connect(_coop_run_over)


func _open_lobby(player_name: String, cls: String) -> void:
	_in_lobby = true
	lobby.open(meta, player_name, cls)
	if not net.discovery.start_listening():
		lobby.set_status("Can't scan the network (is another copy of the game open?). You can still join by IP.", GameLog.GRAY)
	go(lobby)


func _leave_party() -> void:
	net.leave()
	state = null
	show_title()
	toast("You left the party.")


func _on_connection_lost(reason: String) -> void:
	if _current in [title, end_screen]:  # the run is already over; the host just closed the party
		return
	if _in_lobby:
		lobby.open(meta, title._name.text.strip_edges(), title._class)
		lobby.set_status(reason)
		net.discovery.start_listening()
		lobby.set_hosts([])
		return
	overlay.visible = false
	busy = false
	_animating = false
	state = null
	show_title()
	toast(reason)


## "Waiting for: Ana, Bo" once you have finished your own part of a room.
func _set_waiting(names: Array) -> void:
	var me := state.player.name if state and state.player else ""
	var others := names.filter(func(n: String) -> bool: return n != me)
	_waiting.text = "" if others.is_empty() or names.has(me) else "Waiting for: %s" % ", ".join(others)
	_waiting.size = Vector2(size.x, 30)
	_waiting.position = Vector2(0, size.y - 110)


## Host batches can arrive while an earlier one is still animating: play them strictly in order.
func _coop_lock() -> void:
	while _animating:
		await get_tree().process_frame
	_animating = true


func _coop_room(r: int, i: int, type: String, d: Dictionary) -> void:
	state = GameState.from_dict(d, net.my_slot)
	if _current == map_screen:
		await map_screen.view.walk_to(r, i)
	_open_room(type)


func _coop_battle_start(r: int, i: int, d: Dictionary, enemy_dict: Dictionary, events: Array) -> void:
	await _coop_lock()
	state = GameState.from_dict(d, net.my_slot)
	enemy = EnemyData.from_dict(enemy_dict)
	_ready_slots = []
	if _current == map_screen:
		await map_screen.view.walk_to(r, i)
	busy = true
	sfx.play_music("boss" if enemy.boss else "battle")
	battle.stage.floor_theme = state.floor_num
	await go(battle)
	battle.stage.setup(state.player, enemy, state)
	battle.refresh(state, enemy, busy)
	await _play_list(events)
	_animating = false
	_coop_turn_ready()


## After the host's results have played: unlock the buttons unless you are down or already locked in.
func _coop_turn_ready() -> void:
	if state == null or enemy == null or _current != battle:
		return
	var down := state.player.hp <= 0
	var locked := state.player.slot in _ready_slots
	busy = down or locked
	battle.stage.hero.shielded = state.player.defending or state.player.shield_wall
	battle.refresh(state, enemy, busy)
	if down:
		battle.stage.show_status("YOU ARE DOWN", GameLog.RED)
	elif locked:
		battle.stage.show_status("WAITING FOR PARTY")


func _coop_action(action: String) -> void:
	var p := state.player
	if p.hp <= 0 or action == "r":
		return
	if action.begins_with("i"):
		if int(action.substr(1)) < p.items.size():
			busy = true
			battle.refresh(state, enemy, busy)
			net.use_item(int(action.substr(1)))
		return
	if (action == "s" and p.skill_cooldown > 0) or (action == "f" and (not p.ult_unlocked or p.ult_cooldown > 0)) \
			or (action == "h" and p.potions == 0):
		return
	busy = true
	battle.refresh(state, enemy, busy)
	battle.stage.show_status("WAITING FOR PARTY")
	net.act(action)


func _coop_battle_update(events: Array, snap: Dictionary) -> void:
	await _coop_lock()
	if state == null or _current != battle:
		_animating = false
		return
	busy = true
	battle.refresh(state, enemy, busy)
	await _play_list(events)
	PartyCombat.apply_snapshot(state, enemy, snap)
	_animating = false
	_coop_turn_ready()


## Victory: play the finishing blow, then your own loot, relics and perks, then report back.
func _coop_battle_won(events: Array, _snap: Dictionary, d: Dictionary, rewards: Dictionary) -> void:
	await _coop_lock()
	busy = true
	if _current == battle:
		battle.refresh(state, enemy, busy)
		await _play_list(events)
	state = GameState.from_dict(d, net.my_slot)
	await get_tree().create_timer(0.3).timeout
	Engine.time_scale = 1.0
	if rewards["item"]:
		await _offer_loot(Item.from_dict(rewards["item"]))
	await _offer_relic(rewards["relic"], "The elite was carrying something special.")
	await _choose_boss_relic(rewards["boss_relics"])
	await _choose_perks()
	_check_achievements()
	_animating = false
	busy = false
	_room_done()


func _coop_floor_cleared(d: Dictionary, text: String) -> void:
	await _coop_lock()
	_animating = false
	_set_waiting([])
	state = GameState.from_dict(d, net.my_slot)
	await overlay.ask("Floor cleared!", text, [{"label": "Descend"}])
	if state and net.active:
		show_map(true)


func _coop_run_over(events: Array, d: Dictionary) -> void:
	await _coop_lock()
	if _current == battle:
		await _play_list(events)
		await get_tree().create_timer(0.6).timeout
	_animating = false
	busy = false
	_set_waiting([])
	state = GameState.from_dict(d, net.my_slot)
	end_run()
