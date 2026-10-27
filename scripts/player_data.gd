class_name PlayerData
extends RefCounted
## The player character. Stats like atk and max_hp are computed from
## level, class, perks, shop upgrades, meta upgrades and gear, so they never drift out of sync.

var name: String
var char_class: String
var slot := 0       # position in a co-op party (0 in single player)
var level := 1
var xp := 0
var hp := 0
var potions := 3
var gold := 0
var kills := 0
var bonus_atk := 0  # from the shop / training
var bonus_hp := 0   # from the shop
var meta_hp := 0    # from meta upgrades
var xp_mult := 1.0  # from meta upgrades
var perks := {}     # perk id -> stacks
var pending_perks := 0  # level ups waiting for a perk choice
var relics: Array[String] = []  # relic ids (passive, whole run)
var items: Array[String] = []   # consumable ids (max Config.MAX_ITEMS)
var weapon: Item = null
var armor_piece: Item = null
var poison := 0         # turns of poison left
var poison_damage := 1  # damage per poison tick (burns hit harder)
# per-battle state, not saved
var defending := false
var shield_wall := false
var dodge_next := false   # smoke bomb
var strength := 0         # tonic ATK bonus (or Soul Drain penalty) for this fight
var corroded := 0         # armor melted by Acid Spit this fight
var attacks_made := 0     # for the War Drum
var skill_cooldown := 0
var ult_cooldown := 0
var second_wind_used := false

var cls: Dictionary:
	get:
		return Config.CLASSES[char_class]

var max_hp: int:
	get:
		var gear: int = armor_piece.hp if armor_piece else 0
		return (Config.player_hp(level) + int(cls.get("bonus_hp", 0)) + bonus_hp + meta_hp + gear
				+ 4 * perk("tough") + (10 if has_relic("iron_heart") else 0) + (8 if has_relic("crown") else 0))

var atk: int:
	get:
		var gear: int = weapon.atk if weapon else 0
		var relic := (2 if has_relic("whetstone") else 0) + (2 if has_relic("crown") else 0)
		if has_relic("mask") and hp < max_hp / 2:
			relic += 3
		return maxi(1, Config.player_atk(level) + bonus_atk + gear + perk("strong") + relic + strength)

var armor: int:
	get:
		var gear := 0
		for item in [weapon, armor_piece]:
			if item:
				gear += item.armor
		return maxi(0, int(cls.get("armor", 0)) + gear + perk("armor") + (1 if has_relic("crown") else 0) - corroded)

var crit_chance: float:
	get:
		return cls.get("crit_chance", Config.CRIT_CHANCE) + 0.08 * perk("keen") + (0.1 if has_relic("clover") else 0.0)

var run_chance: float:
	get:
		return cls.get("run_chance", Config.RUN_CHANCE)

var heal_amount: int:
	get:
		return int(cls.get("heal_amount", Config.HEAL_AMOUNT)) + level + 4 * perk("alchemist")

var skill_name: String:
	get:
		return cls["skill"]

var skill_max_cooldown: int:
	get:
		return maxi(1, int(cls["cooldown"]) - perk("swift") - (1 if has_relic("orb") else 0))

var ult_max_cooldown: int:
	get:
		return maxi(1, int(cls["ult_cooldown"]) - (1 if has_relic("hourglass") else 0))

var ult_name: String:
	get:
		return cls["ult"]

var ult_unlocked: bool:
	get:
		return level >= Config.ULT_LEVEL


func _init(p_name: String = "Hero", p_class: String = "Warrior") -> void:
	name = p_name
	char_class = p_class
	potions = int(cls.get("potions", 3))
	hp = max_hp


func perk(id: String) -> int:
	return int(perks.get(id, 0))


func has_relic(id: String) -> bool:
	return id in relics


func add_relic(id: String) -> void:
	var old_max := max_hp
	relics.append(id)
	hp += maxi(0, max_hp - old_max)


## Add a consumable if there is room. Returns false when the bag is full.
func add_item(id: String) -> bool:
	if items.size() >= Config.MAX_ITEMS:
		return false
	items.append(id)
	return true


## Gold multiplier from perks and relics.
func gold_mult() -> float:
	return 1.0 + 0.25 * perk("greedy") + (0.4 if has_relic("idol") else 0.0)


## Starting bonuses bought with souls.
func apply_meta(meta: MetaProgress) -> void:
	meta_hp = 3 * meta.level("vitality")
	potions += meta.level("satchel")
	gold += 15 * meta.level("purse")
	xp_mult = 1.0 + 0.15 * meta.level("wisdom")
	hp = max_hp


## Upgrades get pricier each time you buy them.
func shop_price(key: String) -> int:
	var item: Dictionary = Config.SHOP[key]
	var bought := 0
	match key:
		"atk":
			bought = bonus_atk
		"hp":
			bought = bonus_hp / 3
	return int(item["base"]) + int(item["step"]) * bought


func equipped(slot: String) -> Item:
	return weapon if slot == "weapon" else armor_piece


func equip(item: Item) -> void:
	var old_max := max_hp
	if item.slot == "weapon":
		weapon = item
	else:
		armor_piece = item
	hp = clampi(hp + maxi(0, max_hp - old_max), 1, max_hp)


func heal(amount: int) -> int:
	var healed := mini(amount, max_hp - hp)
	hp += healed
	return healed


func add_perk(id: String) -> void:
	var old_max := max_hp
	perks[id] = perk(id) + 1
	hp += maxi(0, max_hp - old_max)


## EXP after Wisdom (meta upgrade) and the Old Tome relic.
func exp_with_bonus(amount: int) -> int:
	return roundi(amount * xp_mult * (1.25 if has_relic("tome") else 1.0))


func gain_exp(amount: int) -> void:
	amount = exp_with_bonus(amount)
	xp += amount
	GameLog.say("+%d EXP (%d/%d)" % [amount, xp, Config.exp_needed(level)], GameLog.CYAN)
	GameLog.event({"type": "exp", "amount": amount, "xp": mini(xp, Config.exp_needed(level)), "need": Config.exp_needed(level)})
	var start_level := level
	# carry leftover exp over, may level up more than once
	while xp >= Config.exp_needed(level):
		xp -= Config.exp_needed(level)
		level += 1
		pending_perks += 1
		hp = max_hp
		poison = 0
		GameLog.say("LEVEL UP! You are now Level %d. HP fully restored (%d)." % [level, max_hp], GameLog.YELLOW)
		if level == Config.ULT_LEVEL:
			GameLog.say("Ultimate unlocked: %s!" % ult_name, GameLog.YELLOW)
		GameLog.event({"type": "level_up", "level": level, "hp": hp, "max_hp": max_hp})
	if level > start_level:  # leftover exp toward the next level
		GameLog.event({"type": "exp", "amount": 0, "xp": xp, "need": Config.exp_needed(level)})


## Reset per-battle state.
func start_battle() -> void:
	defending = false
	shield_wall = false
	dodge_next = false
	strength = 0
	corroded = 0
	attacks_made = 0
	skill_cooldown = 0
	ult_cooldown = 0
	second_wind_used = false


## Per-battle state, for sending co-op fights over the network.
func battle_dict() -> Dictionary:
	return {"defending": defending, "shield_wall": shield_wall, "dodge_next": dodge_next, "strength": strength,
			"corroded": corroded, "attacks_made": attacks_made, "skill_cooldown": skill_cooldown,
			"ult_cooldown": ult_cooldown, "second_wind_used": second_wind_used}


func apply_battle_dict(d: Dictionary) -> void:
	for key in ["defending", "shield_wall", "dodge_next", "second_wind_used"]:
		set(key, bool(d.get(key, false)))
	for key in ["strength", "corroded", "attacks_made", "skill_cooldown", "ult_cooldown"]:
		set(key, int(d.get(key, 0)))


## Status chips for the HUD: [{icon, text, tip}].
func statuses() -> Array:
	var out := []
	if poison > 0:
		out.append({"icon": "poison", "text": str(poison),
				"tip": "Poisoned: %d damage per turn, %d turns left. Potions cure it." % [poison_damage, poison]})
	if strength > 0:
		out.append({"icon": "strength", "text": "+%d" % strength, "tip": "Strength Tonic: +%d ATK this fight" % strength})
	elif strength < 0:
		out.append({"icon": "strength", "text": str(strength), "tip": "Soul Drain: %d ATK this fight" % strength})
	if corroded > 0:
		out.append({"icon": "armor", "text": "-%d" % corroded, "tip": "Acid: -%d armor this fight" % corroded})
	if dodge_next:
		out.append({"icon": "dodge", "text": "", "tip": "Smoke: dodges the next enemy attack"})
	if shield_wall:
		out.append({"icon": "shield", "text": "", "tip": "Shield Wall: blocks the next enemy hit"})
	if defending:
		out.append({"icon": "shield", "text": "", "tip": "Defending: takes half damage this turn"})
	return out


func to_dict() -> Dictionary:
	return {
		"name": name, "char_class": char_class, "slot": slot, "level": level, "xp": xp, "hp": hp,
		"potions": potions, "gold": gold, "kills": kills, "bonus_atk": bonus_atk, "bonus_hp": bonus_hp,
		"meta_hp": meta_hp, "xp_mult": xp_mult, "perks": perks, "pending_perks": pending_perks, "poison": poison,
		"poison_damage": poison_damage, "relics": relics, "items": items,
		"weapon": weapon.to_dict() if weapon else null,
		"armor_piece": armor_piece.to_dict() if armor_piece else null,
	}


static func from_dict(d: Dictionary) -> PlayerData:
	var p := PlayerData.new(d["name"], d["char_class"])
	p.load_dict(d)
	return p


## Overwrite this hero with saved/sent data (keeps the same object, so the UI can hold on to it).
func load_dict(d: Dictionary) -> void:
	name = d["name"]
	char_class = d["char_class"]
	for key in ["slot", "level", "xp", "potions", "gold", "kills", "bonus_atk", "bonus_hp", "meta_hp", "pending_perks", "poison"]:
		set(key, int(d.get(key, 0)))
	xp_mult = float(d.get("xp_mult", 1.0))
	poison_damage = int(d.get("poison_damage", 1))
	relics.clear()
	for id in d.get("relics", []):
		relics.append(String(id))
	items.clear()
	for id in d.get("items", []):
		items.append(String(id))
	perks = {}
	for id in d.get("perks", {}):
		perks[id] = int(d["perks"][id])
	weapon = Item.from_dict(d["weapon"]) if d["weapon"] else null
	armor_piece = Item.from_dict(d["armor_piece"]) if d["armor_piece"] else null
	hp = int(d["hp"])
	if d.has("battle"):
		apply_battle_dict(d["battle"])
