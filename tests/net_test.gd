extends SceneTree
## Headless co-op check: a host and two clients in one process (each with its own multiplayer branch)
## play a whole party run over localhost ENet with simple bot choices. Run from the project folder:
##   godot --headless --path . --script res://tests/net_test.gd
## Exit code 0 = the run finished (won or wiped) without getting stuck.

const PLAYERS := 3
const TIMEOUT := 120.0

var nets: Array[Net] = []
var started := false
var finished := 0
var won := false
var floor_reached := 0
var battles := 0
var rooms := 0
var clock := 0.0


func _initialize() -> void:
	Storage.use_test_paths()
	seed(3)
	for i in PLAYERS:
		var holder := Node.new()
		holder.name = "P%d" % i
		root.add_child(holder)
		set_multiplayer(SceneMultiplayer.new(), NodePath("/root/P%d" % i))
		var net := Net.new()
		net.name = "Net"
		net.announce = false
		holder.add_child(net)
		nets.append(net)
		_wire(net)


## Called on the first frame, once the nodes are inside the tree and have their multiplayer branches.
func _connect_all() -> void:
	var err := nets[0].host_game("Host", "Warrior", {})
	if err != "":
		print("FAIL host: ", err)
		_end(1)
		return
	for i in range(1, PLAYERS):
		nets[i].join_game("127.0.0.1", "Friend%d" % i, ["Rogue", "Cleric", "Warrior"][i % 3], {})


func _wire(net: Net) -> void:
	net.roster_changed.connect(func(r: Array) -> void:
		if net.is_host and r.size() == PLAYERS and not started:
			started = true
			print("ok    %d players in the lobby" % r.size())
			net.start_run("Easy"))
	net.connection_lost.connect(func(reason: String) -> void: print("FAIL connection lost: ", reason))
	net.run_started.connect(func(d: Dictionary) -> void: _vote(net, d))
	net.map_shown.connect(func(d: Dictionary, _a: bool) -> void: _vote(net, d))
	net.floor_cleared.connect(func(d: Dictionary, _t: String) -> void: _vote(net, d))
	net.room_entered.connect(func(_r: int, _i: int, _t: String, d: Dictionary) -> void:
		if net.is_host:
			rooms += 1
		net.personal_done(GameState.from_dict(d, net.my_slot).player.to_dict()))
	net.battle_started.connect(func(_r: int, _i: int, d: Dictionary, _e: Dictionary, _ev: Array) -> void:
		if net.is_host:
			battles += 1
		_act(net, GameState.from_dict(d, net.my_slot).player.hp))
	net.battle_updated.connect(func(_ev: Array, snap: Dictionary) -> void:
		_act(net, int(snap["players"][net.my_slot]["hp"])))
	net.battle_won.connect(func(_ev: Array, _s: Dictionary, d: Dictionary, rewards: Dictionary) -> void:
		var state := GameState.from_dict(d, net.my_slot)
		if rewards["item"]:
			state.player.equip(Item.from_dict(rewards["item"]))
		if rewards["relic"] != "":
			state.player.add_relic(rewards["relic"])
		if not rewards["boss_relics"].is_empty():
			state.player.add_relic(rewards["boss_relics"][0])
		while state.player.pending_perks > 0:
			state.player.pending_perks -= 1
			var perks := Progression.perk_choices(state.player)
			if not perks.is_empty():
				state.player.add_perk(perks[0])
		net.personal_done(state.player.to_dict()))
	net.run_over.connect(func(_ev: Array, d: Dictionary) -> void:
		var state := GameState.from_dict(d, net.my_slot)
		finished += 1
		won = state.won
		floor_reached = state.floor_num)


func _vote(net: Net, d: Dictionary) -> void:
	var state := GameState.from_dict(d, net.my_slot)
	var options := state.map.reachable()
	if not options.is_empty():
		var pick: Array = options[randi() % options.size()]
		net.vote(pick[0], pick[1])


func _act(net: Net, hp: int) -> void:
	if hp > 0:
		net.act(["a", "a", "s", "d", "f"].pick_random())


func _process(delta: float) -> bool:
	if clock == 0.0:
		_connect_all()
	clock += delta
	if finished >= PLAYERS:
		print("ok    run over for every player: %s on floor %d after %d battles, %d other rooms" % [
				"won" if won else "wiped", floor_reached, battles, rooms])
		_end(0)
		return true
	if clock > TIMEOUT:
		print("FAIL  stuck: %d battles, %d rooms, %d/%d players saw the end" % [battles, rooms, finished, PLAYERS])
		_end(1)
		return true
	return false


func _end(code: int) -> void:
	for net in nets:
		net.leave()
	Storage.delete_test_files()
	quit(code)
