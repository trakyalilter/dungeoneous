extends SceneTree
## Headless logic checks + bot balance simulation over full map runs. Run from the project folder:
##   godot --headless --path . --script res://tests/smoke_test.gd
## Exit code 0 = all checks passed.

const RUNS := 120

var failures := 0
var death_spots := {}  # where bots die, for tuning


func _init() -> void:
	GameLog.quiet = true
	Storage.use_test_paths()
	seed(1)
	_unit_checks()
	_map_checks()
	_save_roundtrip()
	_balance()
	Storage.delete_test_files()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		print("ok    ", what)
	else:
		failures += 1
		print("FAIL  ", what)


func _unit_checks() -> void:
	var p := PlayerData.new("T")
	p.gain_exp(Config.exp_needed(1) + Config.exp_needed(2) + 5)
	check(p.level == 3 and p.xp == 5 and p.hp == p.max_hp and p.pending_perks == 2, "exp carries over, perks pending")
	check(p.ult_unlocked and not PlayerData.new("X").ult_unlocked, "ultimate unlocks at level 3")

	check(PlayerData.new("W", "Warrior").max_hp == PlayerData.new("R", "Rogue").max_hp + 4, "warrior bonus HP")
	check(PlayerData.new("C", "Cleric").potions == 5, "cleric potions")

	var perked := PlayerData.new("P", "Rogue")
	var base_atk := perked.atk
	perked.add_perk("strong")
	perked.add_perk("tough")
	check(perked.atk == base_atk + 1 and perked.hp == perked.max_hp, "perks add stats")
	check(Progression.perk_choices(perked).size() == 3, "three perk choices")

	var meta := MetaProgress.new()
	meta.souls = 500
	check(meta.buy("vitality") and meta.buy("satchel") and meta.level("vitality") == 1, "buy meta upgrades")
	check(not meta.class_unlocked("Necromancer") and meta.buy("necromancer") and meta.class_unlocked("Necromancer"),
			"necromancer unlock")
	var mp := PlayerData.new("M")
	mp.apply_meta(meta)
	check(mp.max_hp == PlayerData.new("N").max_hp + 3 and mp.potions == 4, "meta bonuses apply")

	var skel := EnemyData.make("Skeleton", 1)
	check(Combat.hit_enemy(skel, 4) == 3, "armored enemy takes 1 less")
	var guard := EnemyData.make("Orc", 3)
	guard.guarding = true
	check(Combat.hit_enemy(guard, 8) == 4, "guarding enemy takes half")

	var charger := EnemyData.make("Orc", 3)
	charger.intent = "charge"
	charger.choose_intent()
	check(charger.intent == "heavy", "charge is followed by a heavy hit")

	var tank := PlayerData.new("T")
	tank.bonus_hp = 999
	tank.hp = tank.max_hp
	var boss := EnemyData.for_node(1, 7, "boss", "Normal")
	check(boss.boss and boss.title == "Troll King", "floor 1 boss is the Troll King")
	Combat.start_battle(tank, boss)
	check(Combat.take_turn(tank, boss, "r") == "invalid", "cannot run from boss")
	check(Combat.take_turn(tank, boss, "f") == "invalid", "ultimate locked at level 1")
	Combat.take_turn(tank, boss, "s")
	check(Combat.take_turn(tank, boss, "s") == "invalid", "skill has cooldown")

	var warrior := PlayerData.new("W", "Warrior")
	warrior.level = 3
	var hitter := EnemyData.make("Orc", 5)
	hitter.intent = "heavy"
	Combat.start_battle(warrior, hitter)
	var before := warrior.hp
	Combat.take_turn(warrior, hitter, "f")
	check(warrior.hp == before, "shield wall blocks a heavy hit")

	var necro := PlayerData.new("N", "Necromancer")
	necro.level = 3
	var victim := EnemyData.make("Giant", 4)
	Combat.start_battle(necro, victim)
	Combat.take_turn(necro, victim, "f")
	check(victim.poison > 0, "plague poisons the enemy")

	GameLog.quiet = false
	GameLog.clear()
	Combat.take_turn(PlayerData.new("E"), EnemyData.make("Orc", 1), "a")
	var types := GameLog.take_events().map(func(ev: Dictionary) -> String: return ev.type)
	check("log" in types and "attack" in types and "intent" in types, "combat emits log + animation events")
	GameLog.quiet = true

	var all_loot_ok := true
	for i in 200:
		var item := Progression.roll_loot(randi_range(1, 20))
		all_loot_ok = all_loot_ok and item.score() > 0 and item.name != ""
	check(all_loot_ok, "loot always has a name and stats")

	var rp := PlayerData.new("R")
	var atk0 := rp.atk
	var hp0 := rp.max_hp
	rp.add_relic("whetstone")
	rp.add_relic("iron_heart")
	check(rp.atk == atk0 + 2 and rp.max_hp == hp0 + 10 and rp.hp == rp.max_hp, "relics add stats")
	check(rp.add_item("bomb") and rp.add_item("bomb") and rp.add_item("bomb") and not rp.add_item("bomb"), "bag holds 3 items")
	var bomb_target := EnemyData.make("Giant", 5)
	var bomb_hp := bomb_target.hp
	check(Combat.take_turn(rp, bomb_target, "i0") == "ok" and bomb_target.hp == bomb_hp - (8 + 2 * rp.level) \
			and rp.items.size() == 2, "bomb is a free action that ignores armor")

	var phoenix := PlayerData.new("P")
	phoenix.add_relic("phoenix")
	phoenix.hp = 1
	var killer := EnemyData.make("Orc", 6)
	killer.intent = "heavy"
	var survived := false
	for i in 20:
		Combat.enemy_attack(phoenix, killer, 2.0)
		if phoenix.hp > 0 and not phoenix.has_relic("phoenix"):
			survived = true
			break
	check(survived, "phoenix feather saves you once")

	var specials_ok := true
	for kind in Config.SPECIALS:
		var sp := PlayerData.new("S")
		sp.bonus_hp = 500
		sp.hp = sp.max_hp
		var foe := EnemyData.make(kind, 5)
		foe.hp = foe.max_hp / 2
		foe.intent = "special"
		Combat.enemy_turn(sp, foe)
		specials_ok = specials_ok and foe.intent_text(sp.armor) != ""
	check(specials_ok, "every enemy special resolves")
	var orc := EnemyData.make("Orc", 3)
	orc.intent = "special"
	var orc_atk := orc.current_atk
	Combat.enemy_turn(PlayerData.new("T"), orc)
	check(orc.current_atk == orc_atk + 2, "orc war cry raises ATK")

	var slime := EnemyData.make("Slime", 3)
	Combat.start_battle(PlayerData.new("T"), slime)
	slime.hp = slime.max_hp / 2 - 1
	check(not Combat._enemy_dead(slime) and slime.split_done and slime.hp > slime.max_hp / 2 - 1, "slime splits once below half")
	var lich := EnemyData.for_node(5, 6, "boss", "Normal")
	check(lich.title == "Lich Emperor", "floor 5 boss is the Lich Emperor")
	lich.hp = 0
	check(not Combat._enemy_dead(lich) and lich.hp > 0, "lich rises once")
	lich.hp = 0
	check(Combat._enemy_dead(lich), "lich stays dead the second time")
	var golem := EnemyData.make("Golem", 5)
	check(golem.armor == 2, "golem has stone skin")
	var yeti := EnemyData.make("Yeti", 9)
	var chilled := PlayerData.new("C")
	chilled.bonus_hp = 500
	chilled.hp = chilled.max_hp
	yeti.intent = "special"
	Combat.enemy_turn(chilled, yeti)
	check(chilled.skill_cooldown >= 1 or chilled.hp == chilled.max_hp, "avalanche chills on hit")
	var corroded := PlayerData.new("A", "Warrior")
	corroded.corroded = 5
	check(corroded.armor == 0, "armor never goes negative")
	check(Config.FLOOR_INFO.size() == Config.FLOORS, "every floor has info")
	var drawn_ok := true
	for f in Config.FLOOR_INFO:
		for kind in f["pool"] + [f["boss"]]:
			drawn_ok = drawn_ok and Config.ENEMY_TRAITS.has(kind) and Config.SPECIALS.has(kind) and Creature.HEIGHT.has(kind)
	check(drawn_ok, "every enemy has a trait, a special and a drawing")

	var state := GameState.new(PlayerData.new("E"), "Normal")
	var events_ok := true
	for id in RunEvents.EVENTS:
		for c in RunEvents.options(id, state).size():
			var res := RunEvents.resolve(id, c, state)
			events_ok = events_ok and res.text != "" and state.player.hp > 0
	check(events_ok, "every event choice resolves")


func _map_checks() -> void:
	var ok := true
	for i in 50:
		var m := RunMap.generate()
		ok = ok and m.rows.size() == Config.MAP_ROWS + 1 and m.rows[-1][0].type == "boss"
		for r in Config.MAP_ROWS:
			var reached := {}
			for node in m.rows[r]:
				ok = ok and node.links.size() > 0
				for l in node.links:
					reached[l] = true
			ok = ok and reached.size() == m.rows[r + 1].size()  # every node above has a way in
	check(ok, "maps are fully connected and end in a boss")


func _save_roundtrip() -> void:
	check(Storage.save_path != Config.SAVE_PATH and Storage.meta_path != Config.META_PATH, "tests use their own save files")
	var p := PlayerData.new("T", "Rogue")
	p.level = 4
	p.gold = 33
	p.add_perk("keen")
	p.equip(Item.new("Longsword", "weapon", 3, 0, 0, "Rare"))
	var state := GameState.new(p, "Hard")
	state.floor_num = 2
	state.map.move_to(0, 0)
	Storage.save_game(state)
	var loaded := Storage.load_game()
	check(loaded != null and JSON.stringify(loaded.to_dict()) == JSON.stringify(state.to_dict()), "save/load roundtrip")

	var meta := MetaProgress.new()
	meta.souls = 42
	meta.unlock("first_blood")
	Storage.save_meta(meta)
	check(JSON.stringify(Storage.load_meta().to_dict()) == JSON.stringify(meta.to_dict()), "meta save/load roundtrip")
	Storage.delete_test_files()
	check(not FileAccess.file_exists(Storage.save_path), "delete save")


# ------------------------------------------------------------- bot simulation

func bot_action(p: PlayerData, e: EnemyData) -> String:
	for i in p.items.size():
		var id: String = p.items[i]
		if (id == "elixir" and p.hp < p.max_hp * 0.35) or (id == "smoke" and e.intent in ["heavy", "special"]) \
				or (id in ["tonic", "bomb", "fire"] and (e.boss or e.elite) and (id != "tonic" or p.strength == 0)):
			return "i%d" % i
	if e.intent == "heavy":
		if p.ult_unlocked and p.ult_cooldown == 0 and p.ult_name == "Shield Wall":
			return "f"
		return "d"
	if p.potions > 0 and (p.hp <= p.max_hp * 0.35 or (p.poison > 0 and p.hp < p.max_hp * 0.6)):
		return "h"
	if p.ult_unlocked and p.ult_cooldown == 0 and p.ult_name != "Shield Wall":
		if p.ult_name != "Divine Light" or p.hp < p.max_hp * 0.5:
			return "f"
	if p.skill_cooldown == 0:
		return "s"
	return "a"


func bot_shop(state: GameState) -> void:
	var p := state.player
	var stock := Progression.shop_stock(state)
	if stock.relic != "" and p.gold >= Progression.relic_price(state) + 20:
		p.gold -= Progression.relic_price(state)
		p.add_relic(stock.relic)
	for item in stock.gear:
		var current := p.equipped(item.slot)
		if p.gold >= Progression.item_price(item) and (current == null or item.score() > current.score() + 1):
			p.gold -= Progression.item_price(item)
			p.equip(item)
	while true:
		if p.potions < 3 and p.gold >= p.shop_price("potion"):
			Progression.buy(p, "potion")
			continue
		var upgrade := "atk" if p.bonus_atk <= p.bonus_hp / 3 else "hp"
		if p.gold >= p.shop_price(upgrade):
			Progression.buy(p, upgrade)
			continue
		return


func bot_take(p: PlayerData, item: Item) -> void:
	if item == null:
		return
	var current := p.equipped(item.slot)
	if current == null or item.score() > current.score():
		p.equip(item)


func bot_pick_node(state: GameState) -> Array:
	var p := state.player
	var low := p.hp < p.max_hp * 0.5
	var prefs := ["rest", "shop", "event", "treasure", "fight", "elite"] if low \
			else ["treasure", "fight", "event", "elite", "shop", "rest"]
	var options := state.map.reachable()
	options.sort_custom(func(a: Array, b: Array) -> bool:
		return prefs.find(state.map.node(a[0], a[1]).type) < prefs.find(state.map.node(b[0], b[1]).type))
	return options[0]


func bot_fight(state: GameState, kind: String) -> String:
	var p := state.player
	var e := EnemyData.for_node(state.floor_num, state.map.pos_row, kind, state.difficulty)
	Combat.start_battle(p, e)
	var result := "ok"
	while result == "ok" or result == "invalid":
		result = Combat.take_turn(p, e, bot_action(p, e))
	if result == "win":
		var rewards := Progression.give_rewards(state, e)
		bot_take(p, rewards.item)
		if rewards.relic != "":
			p.add_relic(rewards.relic)
		if not rewards.boss_relics.is_empty():
			p.add_relic(rewards.boss_relics[0])
	return result


## Plays one full run. Returns the floor reached (Config.FLOORS + 1 = won).
func bot_run(cls: String, difficulty: String) -> int:
	var state := GameState.new(PlayerData.new("Bot", cls), difficulty)
	var p := state.player
	while true:
		var pick := bot_pick_node(state)
		var node := state.map.move_to(pick[0], pick[1])
		match node.type:
			"fight", "elite", "boss":
				if bot_fight(state, node.type) == "lose":
					var spot := "F%d %s" % [state.floor_num, node.type if node.type != "fight" else "fight row %d" % state.map.pos_row]
					death_spots[spot] = int(death_spots.get(spot, 0)) + 1
					return state.floor_num
				if node.type == "boss":
					if not state.next_floor():
						return Config.FLOORS + 1
					p.heal(roundi(p.max_hp * Config.FLOOR_HEAL))
			"rest":
				if p.hp < p.max_hp * 0.7:
					Progression.rest(p)
				else:
					Progression.train(p)
			"shop":
				bot_shop(state)
			"treasure":
				var chest := Progression.open_treasure(state)
				bot_take(p, chest.item)
				if chest.relic != "":
					p.add_relic(chest.relic)
			"event":
				var id := RunEvents.random_id()
				var opts := RunEvents.options(id, state)
				var c := 0 if not opts[0].get("disabled", false) else 1
				var res := RunEvents.resolve(id, c, state)
				bot_take(p, res.item)
				if res.relic != "":
					p.add_relic(res.relic)
		while p.pending_perks > 0:
			p.pending_perks -= 1
			var perks := Progression.perk_choices(p)
			if not perks.is_empty():  # long runs can max out every perk
				p.add_perk(perks[0])
	return 0


func _balance() -> void:
	print("\n%d bot runs per combo. Win rate and where runs end." % RUNS)
	print("class        difficulty   win%   died F1  F2  F3  F4  F5")
	for difficulty in Config.DIFFICULTIES:
		for cls in Config.CLASSES:
			var reached := []
			reached.resize(Config.FLOORS + 2)
			reached.fill(0)
			for i in RUNS:
				reached[bot_run(cls, difficulty)] += 1
			var died := ""
			for f in range(1, Config.FLOORS + 1):
				died += "%4d" % reached[f]
			print("%-13s%-11s%5d%%   %s" % [cls, difficulty, 100 * reached[Config.FLOORS + 1] / RUNS, died])
	var spots := death_spots.keys()
	spots.sort_custom(func(a: String, b: String) -> bool: return death_spots[a] > death_spots[b])
	print("Most deaths: ", ", ".join(spots.slice(0, 6).map(func(s: String) -> String: return "%s (%d)" % [s, death_spots[s]])))
