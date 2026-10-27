class_name Progression
extends RefCounted
## Rewards, loot, perks, resting, the shop.


static func _weighted_rarity() -> Array:
	var total := 0
	for r in Config.RARITIES:
		total += r[2]
	var pick := randi_range(1, total)
	for r in Config.RARITIES:
		pick -= r[2]
		if pick <= 0:
			return r
	return Config.RARITIES[0]


static func roll_loot(level: int, min_rarity: int = 0) -> Item:
	var tier := mini((level - 1) / 2, Config.WEAPON_NAMES.size() - 1)
	var rarity: Array = _weighted_rarity()
	if Config.RARITIES.find(rarity) < min_rarity:
		rarity = Config.RARITIES[min_rarity]
	var rarity_name: String = rarity[0]
	var mult: float = rarity[1]
	var prefix := "" if rarity_name == "Common" else rarity_name + " "

	if randf() < 0.5:
		return Item.new(prefix + Config.WEAPON_NAMES[tier], "weapon", roundi((1 + tier) * mult), 0, 0, rarity_name)
	return Item.new(prefix + Config.ARMOR_NAMES[tier], "armor", 0,
			roundi((tier / 2) * mult) + (1 if rarity_name == "Epic" else 0),
			roundi((2 + 2 * tier) * mult), rarity_name)


static func _gold_mult(state: GameState, who: PlayerData = null) -> float:
	return float(Config.DIFFICULTIES[state.difficulty]["gold"]) * (who if who else state.player).gold_mult()


## A random relic the player doesn't own yet ("" if they own them all).
static func random_relic(player: PlayerData) -> String:
	var open := []
	for id in Config.RELICS:
		if not player.has_relic(id):
			open.append(id)
	return open.pick_random() if not open.is_empty() else ""


## Up to three boss relics to choose from (falls back to normal relics once all are owned).
static func boss_relic_choices(player: PlayerData) -> Array:
	var open := []
	for id in Config.BOSS_RELICS:
		if not player.has_relic(id):
			open.append(id)
	while open.size() < 3:
		var r := random_relic(player)
		if r == "" or r in open:
			break
		open.append(r)
	open.shuffle()
	return open.slice(0, 3)


static func relic_info(id: String) -> Dictionary:
	return Config.RELICS[id] if Config.RELICS.has(id) else Config.BOSS_RELICS[id]


## Give a relic and say so.
static func grant_relic(player: PlayerData, id: String) -> void:
	player.add_relic(id)
	GameLog.say("Relic gained: %s - %s" % [relic_info(id)["name"], relic_info(id)["desc"]], GameLog.MAGENTA)


## Give a random consumable. Returns its id, or "" if the bag is full.
static func grant_consumable(player: PlayerData) -> String:
	var id: String = Config.CONSUMABLES.keys().pick_random()
	if not player.add_item(id):
		GameLog.say("Your bag is full; you leave a %s behind." % Config.CONSUMABLES[id]["name"], GameLog.GRAY)
		return ""
	GameLog.say("Found a %s!" % Config.CONSUMABLES[id]["name"], GameLog.CYAN)
	return id


static func _reward_mult(boss: bool, elite: bool, boss_mult: float, elite_mult: float) -> float:
	return boss_mult if boss else (elite_mult if elite else 1.0)


## Base EXP for beating an enemy (before the player's EXP bonuses).
static func base_exp(level: int, boss: bool, elite: bool) -> int:
	return roundi(10 * level * _reward_mult(boss, elite, 2.5, 1.5))


## EXP the player would actually receive, with Wisdom and the Old Tome applied.
static func exp_preview(player: PlayerData, level: int, boss: bool, elite: bool) -> int:
	return player.exp_with_bonus(base_exp(level, boss, elite))


## Gold range [lo, hi] for beating an enemy.
static func gold_range(state: GameState, level: int, boss: bool, elite: bool) -> Array:
	var k := level * _reward_mult(boss, elite, 4.0, 2.0) * _gold_mult(state)
	return [roundi(3 * k), roundi(6 * k)]


## One line like "+40 EXP, 9-18 gold (enough to level up!)" for map and battle tooltips.
static func reward_text(state: GameState, level: int, boss: bool, elite: bool) -> String:
	var p := state.player
	var xp := exp_preview(p, level, boss, elite)
	var gold := gold_range(state, level, boss, elite)
	var text := "+%d EXP, %d-%d gold" % [xp, gold[0], gold[1]]
	if p.xp + xp >= Config.exp_needed(p.level):
		text += " (enough to level up!)"
	return text


## Everything a won fight gives: gold, exp, maybe a potion, consumable, relic, item.
## Returns {"item": Item or null, "relic": id or "", "boss_relics": [ids to choose from]}.
## In co-op, call it once per hero with who = that hero; only the first call counts the shared fight stats.
static func give_rewards(state: GameState, enemy: EnemyData, who: PlayerData = null) -> Dictionary:
	var player := who if who else state.player
	player.kills += 1
	if who == null or who == state.players[0]:
		state.fights_won += 1
		if enemy.boss:
			state.bosses_killed += 1
	GameLog.say("You defeated the %s!" % enemy.name, GameLog.YELLOW)
	var after_heal := (4 if player.has_relic("bandages") else 0) + (roundi(player.max_hp * 0.15) if player.has_relic("skull") else 0)
	if after_heal > 0:
		var healed := player.heal(after_heal)
		if healed > 0:
			GameLog.event({"type": "heal", "target": "player", "amount": healed, "hp": player.hp})
	var mult := 4.0 if enemy.boss else (2.0 if enemy.elite else 1.0)
	var gold := roundi(randi_range(3, 6) * enemy.level * mult * _gold_mult(state, player))
	player.gold += gold
	GameLog.say("+%d gold" % gold, GameLog.YELLOW)
	GameLog.event({"type": "loot_text", "text": "+%d gold" % gold, "color": GameLog.YELLOW, "sound": "coin"})
	player.gain_exp(base_exp(enemy.level, enemy.boss, enemy.elite))
	if enemy.boss or randf() < Config.POTION_DROP_CHANCE:
		player.potions += 1
		GameLog.say("The %s dropped a potion! (Potions: %d)" % [enemy.name, player.potions], GameLog.GREEN)
		GameLog.event({"type": "loot_text", "text": "+1 potion", "color": GameLog.GREEN, "sound": "heal"})
	if enemy.elite or randf() < Config.ITEM_DROP_CHANCE:
		var c := grant_consumable(player)
		if c != "":
			GameLog.event({"type": "loot_text", "text": "+%s" % Config.CONSUMABLES[c]["name"], "color": GameLog.CYAN, "sound": "coin"})
	var drop_chance := Config.LOOT_DROP_CHANCE * (2.0 if player.has_relic("magnet") else 1.0)
	var rewards := {"item": null, "relic": "", "boss_relics": []}
	if enemy.boss or enemy.elite or randf() < drop_chance:
		rewards["item"] = roll_loot(enemy.level, 1 if enemy.boss else 0)
	if enemy.elite:
		rewards["relic"] = random_relic(player)
	if enemy.boss:
		rewards["boss_relics"] = boss_relic_choices(player)
	return rewards


## Treasure node: gold, a guaranteed item, and a relic.
## Returns {"gold": int, "item": Item, "relic": id or ""}.
static func open_treasure(state: GameState) -> Dictionary:
	var lvl := Config.node_level(state.floor_num, state.map.pos_row, "fight") + 1
	var gold := roundi(randi_range(15, 25) * state.floor_num * _gold_mult(state))
	state.player.gold += gold
	GameLog.say("The chest holds %d gold!" % gold, GameLog.YELLOW)
	return {"gold": gold, "item": roll_loot(lvl), "relic": random_relic(state.player)}


## Up to three perks the player could take, at random.
static func perk_choices(player: PlayerData) -> Array:
	var open := []
	for id in Config.PERKS:
		if player.perk(id) < int(Config.PERKS[id]["max"]):
			open.append(id)
	open.shuffle()
	return open.slice(0, 3)


static func rest(player: PlayerData) -> int:
	var healed := player.heal(roundi(player.max_hp * Config.REST_HEAL))
	player.poison = 0
	GameLog.say("You rest by the fire and recover %d HP." % healed, GameLog.GREEN)
	return healed


static func train(player: PlayerData) -> void:
	player.bonus_atk += 1
	GameLog.say("You train through the night. +1 ATK.", GameLog.YELLOW)


## Try to buy a shop upgrade. Returns true if bought.
static func buy(player: PlayerData, key: String) -> bool:
	var price := player.shop_price(key)
	if player.gold < price:
		GameLog.say("Not enough gold!", GameLog.RED)
		return false
	player.gold -= price
	match key:
		"potion":
			player.potions += 1
		"atk":
			player.bonus_atk += 1
		"hp":
			player.bonus_hp += 3
			player.hp += 3
	GameLog.say("Bought %s!" % Config.SHOP[key]["name"], GameLog.GREEN)
	return true


## Items for sale at a shop node: {"gear": [Item, Item], "consumables": [id, id], "relic": id or ""}.
static func shop_stock(state: GameState) -> Dictionary:
	var lvl := Config.node_level(state.floor_num, state.map.pos_row, "fight") + 1
	var keys: Array = Config.CONSUMABLES.keys()
	keys.shuffle()
	return {"gear": [roll_loot(lvl, 1), roll_loot(lvl)], "consumables": keys.slice(0, 2), "relic": random_relic(state.player)}


static func item_price(item: Item) -> int:
	return roundi(item.score() * 6 + {"Common": 5, "Rare": 15, "Epic": 30}[item.rarity])


static func relic_price(state: GameState) -> int:
	return 60 + 25 * state.floor_num
