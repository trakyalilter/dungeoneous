class_name GameState
extends RefCounted
## Everything needed to save and resume a run.
## In co-op, players holds the whole party (index = slot) and player is this machine's hero.

var player: PlayerData
var players: Array[PlayerData] = []
var party := false
var difficulty: String
var floor_num := 1
var map: RunMap
var fights_won := 0
var bosses_killed := 0
var won := false


func _init(p_player: PlayerData = null, p_difficulty: String = "Normal") -> void:
	player = p_player
	if p_player:
		players = [p_player]
	difficulty = p_difficulty
	map = RunMap.generate()


## A co-op run for the given heroes (slots are set from their order).
static func new_party(heroes: Array[PlayerData], p_difficulty: String) -> GameState:
	var state := GameState.new(heroes[0], p_difficulty)
	state.players = heroes
	state.party = true
	for i in heroes.size():
		heroes[i].slot = i
	return state


func floor_name() -> String:
	return Config.FLOOR_INFO[floor_num - 1]["name"]


## Heroes still standing.
func alive() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p in players:
		if p.hp > 0:
			out.append(p)
	return out


## Move down to the next floor. Returns false if that was the last one (run won).
func next_floor() -> bool:
	if floor_num >= Config.FLOORS:
		won = true
		return false
	floor_num += 1
	map = RunMap.generate()
	for p in players:
		if p.has_relic("orb"):
			p.potions += 1
	return true


## Souls earned by this run so far (paid out when it ends).
func souls() -> int:
	var s := player.kills + 10 * bosses_killed + (40 if won else 0)
	return roundi(s * float(Config.DIFFICULTIES[difficulty]["souls"]) * float(player.cls.get("souls_mult", 1.0)))


func to_dict() -> Dictionary:
	var d := {"player": player.to_dict(), "difficulty": difficulty, "floor_num": floor_num, "map": map.to_dict(),
			"fights_won": fights_won, "bosses_killed": bosses_killed}
	if party:
		d["players"] = players.map(func(p: PlayerData) -> Dictionary: return p.to_dict())
		d["won"] = won
	return d


## my_slot picks which party member is this machine's hero (ignored for solo saves).
static func from_dict(d: Dictionary, my_slot: int = 0) -> GameState:
	var state := GameState.new(PlayerData.from_dict(d["player"]), d["difficulty"])
	if d.has("players"):
		var heroes: Array[PlayerData] = []
		for pd in d["players"]:
			heroes.append(PlayerData.from_dict(pd))
		state.players = heroes
		state.party = true
		state.player = heroes[clampi(my_slot, 0, heroes.size() - 1)]
		state.won = bool(d.get("won", false))
	state.floor_num = int(d["floor_num"])
	state.map = RunMap.from_dict(d["map"])
	state.fights_won = int(d.get("fights_won", 0))
	state.bosses_killed = int(d.get("bosses_killed", 0))
	return state
