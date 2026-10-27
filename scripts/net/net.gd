class_name Net
extends Node
## LAN co-op over ENet. One player hosts: their game holds the real run state and resolves every fight.
## Everyone (the host too) sends requests to the host with rpc_id(1, ...); the host answers everybody with rpc(...).
## Shops, campfires, events, treasure and loot choices are personal: each player plays them on their own screen
## and sends their updated hero back with personal_done().
## main.gd listens to the signals below and drives the screens. Must be added as a child named "Net".

signal roster_changed(roster: Array)
signal connection_lost(reason: String)
signal notice(text: String)
signal run_started(state_dict: Dictionary)
signal map_shown(state_dict: Dictionary, announce: bool)
signal votes_changed(votes: Dictionary, seconds_left: int)
signal room_entered(row: int, idx: int, type: String, state_dict: Dictionary)
signal battle_started(row: int, idx: int, state_dict: Dictionary, enemy_dict: Dictionary, events: Array)
signal battle_updated(events: Array, snap: Dictionary)
signal ready_changed(slots: Array)
signal battle_won(events: Array, snap: Dictionary, state_dict: Dictionary, rewards: Dictionary)
signal waiting_changed(names: Array)
signal floor_cleared(state_dict: Dictionary, text: String)
signal run_over(events: Array, state_dict: Dictionary)

const PORT := 8910
const MAX_PLAYERS := 4
const VOTE_SECONDS := 15.0

var active := false   # in a lobby or co-op run
var is_host := false
var my_slot := 0
var roster: Array = []  # [{"id", "name", "class", "meta"}], index = party slot
var discovery := LanDiscovery.new()
var announce := true  # broadcast hosted games on the LAN (tests turn it off)

# host only
var _state: GameState
var _enemy: EnemyData
var _phase := ""        # lobby, map, battle, personal
var _votes := {}        # slot -> [row, idx]
var _vote_left := -1.0  # seconds until the vote closes (-1 = no vote running)
var _actions := {}      # slot -> action key for this round
var _pending := {}      # slot -> true while that player is busy with a personal room
var _after := "map"     # what follows the personal phase: "map" or "boss"
var _left := {}         # slot -> true for players who disconnected mid-run


func _ready() -> void:
	add_child(discovery)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _drop("Could not connect to that game."))
	multiplayer.server_disconnected.connect(func() -> void: _drop("The host left the game."))


# ================================================================== lobby

## Start hosting. Returns "" on success or an error message.
func host_game(player_name: String, cls: String, meta: Dictionary) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		return "Could not open port %d. Is another game already hosting on this PC?" % PORT
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	_phase = "lobby"
	roster = [{"id": 1, "name": player_name, "class": cls, "meta": meta}]
	if announce:
		discovery.start_broadcast(func() -> Dictionary:
			return {"name": roster[0]["name"], "players": roster.size(), "max": MAX_PLAYERS, "open": _phase == "lobby"})
	_set_roster.rpc(roster)
	return ""


## Join a host by IP. The result arrives as roster_changed (joined) or connection_lost (failed).
func join_game(ip: String, player_name: String, cls: String, meta: Dictionary) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		return "Could not reach %s." % ip
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	roster = [{"id": 0, "name": player_name, "class": cls, "meta": meta}]  # sent once connected
	return ""


func leave() -> void:
	discovery.stop()
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	is_host = false
	roster = []
	_state = null
	_enemy = null
	_phase = ""
	_votes.clear()
	_actions.clear()
	_pending.clear()
	_left.clear()
	_vote_left = -1.0


func _drop(reason: String) -> void:
	var was_active := active
	leave()
	if was_active:
		connection_lost.emit(reason)


func _on_connected() -> void:
	var me: Dictionary = roster[0]
	_register.rpc_id(1, me["name"], me["class"], me["meta"])


func _on_peer_connected(_id: int) -> void:
	pass  # the new player introduces themselves with _register


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	var slot := _slot_of(id)
	if slot < 0:
		return
	var who: String = roster[slot]["name"]
	if _phase == "lobby":
		roster.remove_at(slot)
		_set_roster.rpc(roster)
		return
	_left[slot] = true
	_votes.erase(slot)
	_actions.erase(slot)
	_pending.erase(slot)
	_notice.rpc("%s left the party. Their hero fights on by instinct." % who)
	_check_progress()


@rpc("any_peer", "reliable")
func _register(player_name: String, cls: String, meta: Dictionary) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if _phase != "lobby":
		_kicked.rpc_id(id, "That party has already set off.")
		return
	if roster.size() >= MAX_PLAYERS:
		_kicked.rpc_id(id, "That party is full.")
		return
	roster.append({"id": id, "name": player_name, "class": cls if Config.CLASSES.has(cls) else "Warrior", "meta": meta})
	_set_roster.rpc(roster)


@rpc("authority", "reliable")
func _kicked(reason: String) -> void:
	_drop(reason)


@rpc("authority", "call_local", "reliable")
func _set_roster(new_roster: Array) -> void:
	roster = new_roster
	my_slot = maxi(0, _slot_of(multiplayer.get_unique_id()))
	roster_changed.emit(roster)


@rpc("authority", "call_local", "reliable")
func _notice(text: String) -> void:
	notice.emit(text)


func _slot_of(id: int) -> int:
	for i in roster.size():
		if int(roster[i]["id"]) == id:
			return i
	return -1


func _sender_slot() -> int:
	return _slot_of(multiplayer.get_remote_sender_id())


## Host: everyone in the lobby sets off together.
func start_run(difficulty: String) -> void:
	if not is_host or _phase != "lobby":
		return
	var heroes: Array[PlayerData] = []
	for entry in roster:
		var p := PlayerData.new(entry["name"], entry["class"])
		p.apply_meta(MetaProgress.from_dict(entry["meta"]))
		heroes.append(p)
	_state = GameState.new_party(heroes, difficulty)
	_phase = "map"
	_run_started.rpc(_state.to_dict())


@rpc("authority", "call_local", "reliable")
func _run_started(state_dict: Dictionary) -> void:
	run_started.emit(state_dict)


# ================================================================== map vote

func vote(row: int, idx: int) -> void:
	_vote.rpc_id(1, row, idx)


@rpc("any_peer", "call_local", "reliable")
func _vote(row: int, idx: int) -> void:
	var slot := _sender_slot()
	if not is_host or _phase != "map" or slot < 0:
		return
	var ok := false
	for pair in _state.map.reachable():
		ok = ok or (pair[0] == row and pair[1] == idx)
	if not ok:
		return
	_votes[slot] = [row, idx]
	if _vote_left < 0.0:
		_vote_left = VOTE_SECONDS
	_show_votes.rpc(_votes, ceili(_vote_left))
	_check_progress()


@rpc("authority", "call_local", "reliable")
func _show_votes(votes: Dictionary, seconds_left: int) -> void:
	votes_changed.emit(votes, seconds_left)


func _process(delta: float) -> void:
	if not is_host or _vote_left < 0.0:
		return
	var before := ceili(_vote_left)
	_vote_left -= delta
	if _vote_left <= 0.0:
		_resolve_vote()
	elif ceili(_vote_left) != before:
		_show_votes.rpc(_votes, ceili(_vote_left))


## Majority wins; a tie goes to the host's pick if it is among the tied rooms, otherwise to a random one.
func _resolve_vote() -> void:
	_vote_left = -1.0
	if _votes.is_empty():
		return
	var counts := {}
	for slot in _votes:
		var key := "%d,%d" % _votes[slot]
		counts[key] = int(counts.get(key, 0)) + 1
	var best := 0
	for key in counts:
		best = maxi(best, counts[key])
	var tied := []
	for key in counts:
		if counts[key] == best:
			tied.append(key)
	var pick: String = tied.pick_random()
	if _votes.has(0) and "%d,%d" % _votes[0] in tied:
		pick = "%d,%d" % _votes[0]
	_votes.clear()
	_show_votes.rpc({}, 0)
	var parts := pick.split(",")
	_enter(int(parts[0]), int(parts[1]))


func _enter(row: int, idx: int) -> void:
	var node := _state.map.move_to(row, idx)
	var type: String = node.type
	if type in ["fight", "elite", "boss"]:
		_enemy = PartyCombat.make_enemy(_state, type)
		GameLog.clear()
		PartyCombat.start(_state, _enemy)
		_phase = "battle"
		_actions.clear()
		_battle_started.rpc(row, idx, _state.to_dict(), _enemy.to_dict(), GameLog.take_events())
	else:
		_begin_personal("map")
		_room_entered.rpc(row, idx, type, _state.to_dict())


@rpc("authority", "call_local", "reliable")
func _room_entered(row: int, idx: int, type: String, state_dict: Dictionary) -> void:
	room_entered.emit(row, idx, type, state_dict)


@rpc("authority", "call_local", "reliable")
func _battle_started(row: int, idx: int, state_dict: Dictionary, enemy_dict: Dictionary, events: Array) -> void:
	battle_started.emit(row, idx, state_dict, enemy_dict, events)


@rpc("authority", "call_local", "reliable")
func _show_map(state_dict: Dictionary, announce: bool) -> void:
	map_shown.emit(state_dict, announce)


# ================================================================== battle

## Lock in this round's action ("a", "s", "f", "d", "h").
func act(action: String) -> void:
	_act.rpc_id(1, action)


## Use a consumable right away (free action, like in solo).
func use_item(idx: int) -> void:
	_use_item.rpc_id(1, idx)


@rpc("any_peer", "call_local", "reliable")
func _act(action: String) -> void:
	var slot := _sender_slot()
	if not is_host or _phase != "battle" or slot < 0 or _state.players[slot].hp <= 0:
		return
	_actions[slot] = action
	_ready_slots.rpc(_actions.keys())
	_check_progress()


@rpc("authority", "call_local", "reliable")
func _ready_slots(slots: Array) -> void:
	ready_changed.emit(slots)


@rpc("any_peer", "call_local", "reliable")
func _use_item(idx: int) -> void:
	var slot := _sender_slot()
	if not is_host or _phase != "battle" or slot < 0:
		return
	GameLog.clear()
	var result := PartyCombat.use_item(_state, _enemy, slot, idx)
	if result == "invalid":
		return
	var events := GameLog.take_events()
	if result == "win":
		_win(events)
	else:
		_battle_update.rpc(events, PartyCombat.snapshot(_state, _enemy))


func _resolve_round() -> void:
	GameLog.clear()
	var result := PartyCombat.play_round(_state, _enemy, _actions)
	_actions.clear()
	var events := GameLog.take_events()
	match result:
		"win":
			_win(events)
		"lose":
			_phase = ""
			_run_over.rpc(events, _state.to_dict())
		_:
			_battle_update.rpc(events, PartyCombat.snapshot(_state, _enemy))
			_ready_slots.rpc([])


@rpc("authority", "call_local", "reliable")
func _battle_update(events: Array, snap: Dictionary) -> void:
	battle_updated.emit(events, snap)


func _win(events: Array) -> void:
	var rewards := PartyCombat.finish_win(_state, _enemy)
	events.append_array(GameLog.take_events())
	_begin_personal("boss" if _enemy.boss else "map")
	var snap := PartyCombat.snapshot(_state, _enemy)
	var state_dict := _state.to_dict()
	for slot in roster.size():
		if _left.has(slot):
			continue
		var id := int(roster[slot]["id"])
		if id == multiplayer.get_unique_id():
			_battle_won(events, snap, state_dict, rewards[slot])
		else:
			_battle_won.rpc_id(id, events, snap, state_dict, rewards[slot])


@rpc("authority", "reliable")
func _battle_won(events: Array, snap: Dictionary, state_dict: Dictionary, rewards: Dictionary) -> void:
	battle_won.emit(events, snap, state_dict, rewards)


@rpc("authority", "call_local", "reliable")
func _run_over(events: Array, state_dict: Dictionary) -> void:
	run_over.emit(events, state_dict)


# ================================================================== personal rooms

func _begin_personal(after: String) -> void:
	_phase = "personal"
	_after = after
	_pending.clear()
	for slot in roster.size():
		if not _left.has(slot):
			_pending[slot] = true


## This player finished their own room (shop, campfire, loot...). hero_dict is their updated hero.
func personal_done(hero_dict: Dictionary) -> void:
	_personal_done.rpc_id(1, hero_dict)


@rpc("any_peer", "call_local", "reliable")
func _personal_done(hero_dict: Dictionary) -> void:
	var slot := _sender_slot()
	if not is_host or _phase != "personal" or slot < 0 or not _pending.has(slot):
		return
	_state.players[slot].load_dict(hero_dict)
	_state.players[slot].slot = slot
	_pending.erase(slot)
	_check_progress()


@rpc("authority", "call_local", "reliable")
func _waiting(names: Array) -> void:
	waiting_changed.emit(names)


@rpc("authority", "call_local", "reliable")
func _floor_cleared(state_dict: Dictionary, text: String) -> void:
	floor_cleared.emit(state_dict, text)


## Host: move on once everyone we are waiting for is done (votes, actions or personal rooms).
func _check_progress() -> void:
	if not is_host:
		return
	var present := []
	for slot in roster.size():
		if not _left.has(slot):
			present.append(slot)
	match _phase:
		"map":
			if not _votes.is_empty() and _votes.size() >= present.size():
				_resolve_vote()
		"battle":
			for slot in present:
				if _state.players[slot].hp > 0 and not _actions.has(slot):
					return
			if not _state.alive().is_empty():
				_resolve_round()
		"personal":
			_waiting.rpc(_pending.keys().map(func(s: int) -> String: return roster[s]["name"]))
			if _pending.is_empty():
				_end_personal()


func _end_personal() -> void:
	_phase = "map"
	if _after != "boss":
		_show_map.rpc(_state.to_dict(), false)
		return
	var boss_title: String = Config.FLOOR_INFO[_state.floor_num - 1]["boss_title"]
	if not _state.next_floor():
		_phase = ""
		_run_over.rpc([], _state.to_dict())
		return
	for p in _state.players:
		p.hp = maxi(p.hp, 1)
		p.heal(roundi(p.max_hp * Config.FLOOR_HEAL))
	_floor_cleared.rpc(_state.to_dict(), "The %s falls.\nThe party descends into [color=%s]%s[/color] and catches its breath." % [
			boss_title, GameLog.YELLOW, _state.floor_name()])
