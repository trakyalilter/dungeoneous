class_name MetaProgress
extends RefCounted
## Progress that survives between runs: souls, permanent upgrades, achievements, lifetime stats.

var souls := 0
var upgrades := {}       # upgrade id -> level bought
var achievements := []   # unlocked achievement ids
var total_kills := 0
var wins_by_class := {}  # class -> wins


func level(id: String) -> int:
	return int(upgrades.get(id, 0))


## Price of the next level, or -1 if maxed.
func next_cost(id: String) -> int:
	var costs: Array = Config.META_UPGRADES[id]["costs"]
	return costs[level(id)] if level(id) < costs.size() else -1


func buy(id: String) -> bool:
	var cost := next_cost(id)
	if cost < 0 or souls < cost:
		return false
	souls -= cost
	upgrades[id] = level(id) + 1
	return true


func class_unlocked(cls: String) -> bool:
	if not Config.CLASSES[cls].get("locked", false):
		return true
	return level(cls.to_lower()) > 0


## Unlock an achievement. Returns true if it is new.
func unlock(id: String) -> bool:
	if id in achievements:
		return false
	achievements.append(id)
	return true


## Check achievements against the current run. Returns the ids unlocked just now.
func check(state: GameState) -> Array:
	var p := state.player
	var fresh := []
	var checks := {
		"first_blood": state.fights_won > 0,
		"boss_slayer": state.bosses_killed > 0,
		"dragon_slayer": state.bosses_killed >= 4,  # the dragon guards floor 4
		"conqueror": state.won,
		"frostbitten": state.floor_num >= 3,
		"void_walker": state.floor_num >= 5,
		"hard_win": state.won and state.difficulty == "Hard",
		"epic_loot": (p.weapon and p.weapon.rarity == "Epic") or (p.armor_piece and p.armor_piece.rarity == "Epic"),
		"level_10": p.level >= 10,
		"hoarder": p.gold >= 200,
		"centurion": total_kills + p.kills >= 100,
		"all_classes": _won_all(state),
	}
	for id in checks:
		if checks[id] and unlock(id):
			fresh.append(id)
	return fresh


func _won_all(state: GameState) -> bool:
	for cls in Config.CLASSES:
		if int(wins_by_class.get(cls, 0)) == 0 and not (state.won and state.player.char_class == cls):
			return false
	return true


## Bank the results of a finished run.
func finish_run(state: GameState) -> int:
	var earned := state.souls()
	souls += earned
	total_kills += state.player.kills
	if state.won:
		wins_by_class[state.player.char_class] = int(wins_by_class.get(state.player.char_class, 0)) + 1
	return earned


func to_dict() -> Dictionary:
	return {"souls": souls, "upgrades": upgrades, "achievements": achievements,
			"total_kills": total_kills, "wins_by_class": wins_by_class}


static func from_dict(d: Dictionary) -> MetaProgress:
	var m := MetaProgress.new()
	m.souls = int(d.get("souls", 0))
	for k in d.get("upgrades", {}):
		m.upgrades[k] = int(d["upgrades"][k])
	for a in d.get("achievements", []):
		m.achievements.append(String(a))
	m.total_kills = int(d.get("total_kills", 0))
	for k in d.get("wins_by_class", {}):
		m.wins_by_class[k] = int(d["wins_by_class"][k])
	return m
