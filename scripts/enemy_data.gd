class_name EnemyData
extends RefCounted
## One enemy. Create with EnemyData.make() or EnemyData.for_node().
## Each turn the enemy has an intent (attack / charge / heavy / guard) the player can see.

var base_name: String
var level: int
var max_hp: int
var atk: int
var boss: bool
var elite: bool
var title := ""   # boss display name, e.g. "Troll King"
var hp: int
var intent := "attack"
var guarding := false  # takes half damage until it acts again
var poison := 0        # turns of poison/burn left
var poison_damage := 0
var rage := 0          # ATK bonus from War Cry
var fortify := 0       # armor bonus from Harden
var split_done := false  # slimes split only once
var revived := false     # undying enemies rise only once
var target_slot := 0     # co-op: which hero its next attack goes for

var name: String:
	get:
		if title != "":
			return title
		return "Elite " + base_name if elite else base_name

var enemy_trait: String:
	get:
		return Config.ENEMY_TRAITS.get(base_name, "")

var armor: int:
	get:
		return {"armored": 1, "stone": 2}.get(enemy_trait, 0) + fortify

var current_atk: int:
	get:
		if enemy_trait == "berserk" and hp <= max_hp / 2:
			return atk + rage + 2
		return atk + rage

var special: Dictionary:
	get:
		return Config.SPECIALS.get(base_name, {"name": "Strike", "desc": "a strong hit"})


func _init(p_base_name: String, p_level: int, p_max_hp: int, p_atk: int, p_boss: bool = false, p_elite: bool = false) -> void:
	base_name = p_base_name
	level = p_level
	max_hp = p_max_hp
	atk = p_atk
	boss = p_boss
	elite = p_elite
	hp = max_hp


static func make(p_base_name: String, p_level: int, p_boss: bool = false, difficulty: String = "Normal",
		p_elite: bool = false) -> EnemyData:
	var diff: Dictionary = Config.DIFFICULTIES[difficulty]
	var mult := 2.0 if p_boss else (Config.ELITE_HP_MULT if p_elite else 1.0)
	var hp_base := Config.enemy_hp(p_level) * mult
	var atk_base := Config.enemy_atk(p_level) + (1 if p_boss else 0)
	var e := EnemyData.new(p_base_name, p_level,
			maxi(1, roundi(hp_base * diff["enemy_hp"])),
			maxi(1, roundi(atk_base * diff["enemy_atk"])),
			p_boss, p_elite)
	e.choose_intent()
	return e


## The enemy for a map node ("fight", "elite" or "boss") on a floor.
static func for_node(floor_num: int, row: int, kind: String, difficulty: String) -> EnemyData:
	var info: Dictionary = Config.FLOOR_INFO[floor_num - 1]
	var lvl := Config.node_level(floor_num, row, kind)
	if kind == "boss":
		var b := make(info["boss"], lvl, true, difficulty)
		b.title = info["boss_title"]
		b.max_hp = roundi(b.max_hp / 2.0 * float(info["boss_hp"]))  # per-floor boss toughness
		b.hp = b.max_hp
		return b
	return make(info["pool"].pick_random(), lvl, false, difficulty, kind == "elite")


## Decide what to do next turn. A charge is always followed by a heavy hit.
func choose_intent() -> void:
	if intent == "charge":
		intent = "heavy"
		return
	var weights: Dictionary = Config.BOSS_INTENTS if boss else Config.INTENTS
	var total := 0
	for k in weights:
		total += weights[k]
	var pick := randi_range(1, total)
	for k in weights:
		pick -= weights[k]
		if pick <= 0:
			intent = k
			break
	if intent == "charge" and level < 2:
		intent = "attack"
	# pointless specials become attacks (healing at full HP, stealing from nobody, raging twice)
	if intent == "special" and ((base_name == "Troll" and hp >= max_hp * 0.8) or (base_name == "Orc" and rage > 0)
			or (base_name == "Golem" and fortify >= 2)):
		intent = "attack"


## Damage range [lo, hi] of a hit with multiplier mult, after armor (unless it ignores armor).
func hit_range(player_armor: int, mult: float = 1.0, ignore_armor: bool = false) -> Array:
	var a := 0 if ignore_armor else player_armor
	return [maxi(1, roundi((current_atk - 1) * mult) - a), maxi(1, roundi((current_atk + 1) * mult) - a)]


## Short text for the intent badge, with the damage range after the player's armor.
func intent_text(player_armor: int) -> String:
	var r := hit_range(player_armor)
	match intent:
		"attack":
			return "Attack %d-%d%s" % [r[0], r[1], " (may strike twice)" if enemy_trait == "quick" else ""]
		"charge":
			return "Charging a heavy hit!"
		"heavy":
			var h := hit_range(player_armor, 2.0)
			return "HEAVY HIT %d-%d" % [h[0], h[1]]
		"guard":
			return "Guarding (takes half damage)"
		"special":
			return "%s: %s" % [special["name"], special_preview(player_armor)]
	return ""


func special_preview(player_armor: int) -> String:
	match base_name:
		"Goblin":
			var r := hit_range(player_armor, 0.5)
			return "%d-%d, steals gold" % r
		"Skeleton":
			var r := hit_range(player_armor, 1.0, true)
			return "%d-%d, ignores armor" % r
		"Werewolf":
			var r := hit_range(player_armor, 0.6)
			return "3 x %d-%d" % r
		"Giant":
			var r := hit_range(player_armor, 1.5)
			return "%d-%d, ignores Defend" % r
		"Dragon":
			var r := hit_range(player_armor, 1.8, true)
			return "%d-%d, ignores armor" % r
		"Zombie", "Vampire", "Demon":
			var r := hit_range(player_armor)
			return "%d-%d, %s" % [r[0], r[1], special["desc"].split(" ", true, 1)[1] if base_name != "Zombie" else "poisons"]
		"Slime":
			var r := hit_range(player_armor)
			return "%d-%d, melts 1 armor" % r
		"Wraith":
			var r := hit_range(player_armor)
			return "%d-%d, saps 1 ATK" % r
		"Golem":
			return "guard, +1 armor"
		"Yeti":
			var r := hit_range(player_armor, 1.6)
			return "%d-%d, chills" % r
		"Lich":
			var r := hit_range(player_armor, 1.4, true)
			return "%d-%d, curses" % r
	return special["desc"]


const _SAVED := ["base_name", "level", "max_hp", "atk", "boss", "elite", "title", "hp", "intent", "guarding", "poison",
		"poison_damage", "rage", "fortify", "split_done", "revived", "target_slot"]


## Full state, for sending co-op fights over the network.
func to_dict() -> Dictionary:
	var d := {}
	for key in _SAVED:
		d[key] = get(key)
	return d


static func from_dict(d: Dictionary) -> EnemyData:
	var e := EnemyData.new(d["base_name"], int(d["level"]), int(d["max_hp"]), int(d["atk"]), bool(d["boss"]), bool(d["elite"]))
	e.load_dict(d)
	return e


## Overwrite with sent data, keeping the same object.
func load_dict(d: Dictionary) -> void:
	for key in _SAVED:
		var v: Variant = d[key]
		set(key, int(v) if v is float else v)  # JSON-style numbers arrive as floats


## Status chips for the HUD: [{icon, text, tip}].
func statuses() -> Array:
	var out := []
	if enemy_trait != "":
		out.append({"icon": "trait", "text": enemy_trait,
				"tip": "Trait - %s: %s" % [enemy_trait, Config.TRAIT_DESC[enemy_trait]]})
	if guarding:
		out.append({"icon": "shield", "text": "", "tip": "Guarding: takes half damage until it acts"})
	if poison > 0:
		out.append({"icon": "poison", "text": str(poison), "tip": "Poisoned: %d damage per turn, %d turns left" % [poison_damage, poison]})
	if rage > 0:
		out.append({"icon": "strength", "text": "+%d" % rage, "tip": "War Cry: +%d ATK" % rage})
	if fortify > 0:
		out.append({"icon": "armor", "text": "+%d" % fortify, "tip": "Harden: +%d armor" % fortify})
	return out
