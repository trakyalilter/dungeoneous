class_name Combat
extends RefCounted
## Attacks, skills, items, enemy turns. No UI here: the caller passes in the action
## ("a" attack, "s" skill, "f" ultimate, "d" defend, "h" potion, "r" run, "i0".."i2" use item)
## and reads the result. Everything that happens is also emitted as GameLog events for the stage to animate.


## Returns {damage, crit, miss} with a little randomness.
static func roll_damage(atk: int, crit_chance: float = -1.0) -> Dictionary:
	if crit_chance < 0.0:
		crit_chance = Config.CRIT_CHANCE
	if randf() < Config.MISS_CHANCE:
		return {"damage": 0, "crit": false, "miss": true}
	var damage := maxi(1, atk + randi_range(-1, 1))
	if randf() < crit_chance:
		return {"damage": damage * 2, "crit": true, "miss": false}
	return {"damage": damage, "crit": false, "miss": false}


## Apply enemy armor and guard, subtract HP, return damage actually dealt.
static func hit_enemy(enemy: EnemyData, raw_damage: int) -> int:
	var damage := maxi(1, raw_damage - enemy.armor)
	if enemy.guarding:
		damage = maxi(1, damage / 2)
	enemy.hp -= damage
	return damage


## Expected damage range of an action, for the button labels. Returns [lo, hi] or [] if it deals none.
static func preview(player: PlayerData, enemy: EnemyData, action: String) -> Array:
	var mult := 0.0
	match action:
		"a":
			mult = 2.0 if player.has_relic("drum") and player.attacks_made == 0 else 1.0
		"s":
			mult = {"Power Strike": 2.0, "Backstab": 2.5, "Smite": 1.0, "Drain Life": 1.5}[player.skill_name]
		"f":
			if player.ult_name == "Poison Blade":
				mult = 1.0
	if mult == 0.0:
		return []
	var bonus := 2 if player.skill_name == "Smite" and action == "s" else 0
	var out := []
	for a in [player.atk - (1 if action == "a" else 0), player.atk + (1 if action == "a" else 0)]:
		var d := maxi(1, roundi(a * mult) + bonus - enemy.armor)
		out.append(maxi(1, d / 2) if enemy.guarding else d)
	return out


static func _damage_event(target: String, amount: int, hp: int, crit: bool = false, kind: String = "") -> void:
	GameLog.event({"type": "damage", "target": target, "amount": amount, "hp": hp, "crit": crit, "kind": kind})


static func _heal_event(target: String, amount: int, hp: int) -> void:
	if amount > 0:
		GameLog.event({"type": "heal", "target": target, "amount": amount, "hp": hp})


static func _status(target: String, text: String, hex: String) -> void:
	GameLog.event({"type": "status", "target": target, "text": text, "color": hex})


## Player landed a hit: vampiric perk heals, venom relic poisons.
static func _on_player_hit(player: PlayerData, enemy: EnemyData) -> void:
	player.attacks_made += 1
	if player.perk("vampiric") > 0:
		_heal_event("player", player.heal(player.perk("vampiric")), player.hp)
	if player.has_relic("venom") and enemy.hp > 0 and enemy.poison == 0:
		_poison_enemy(enemy, 2, 2)


static func player_attack(player: PlayerData, enemy: EnemyData) -> void:
	GameLog.event({"type": "attack", "by": "player"})
	var roll := roll_damage(player.atk, player.crit_chance)
	if not roll.miss and enemy.enemy_trait == "ethereal" and randf() < 0.2:
		roll.miss = true
		GameLog.say("Your blow passes right through the %s!" % enemy.name, GameLog.GRAY)
		_status("enemy", "PHASED", GameLog.CYAN)
	if roll.miss:
		GameLog.say("You swing at the %s and miss!" % enemy.name, GameLog.GRAY)
		GameLog.event({"type": "miss", "target": "enemy"})
		player.attacks_made += 1
		return
	var raw: int = roll.damage
	var drum := player.has_relic("drum") and player.attacks_made == 0
	if drum:
		raw *= 2
	var damage := hit_enemy(enemy, raw)
	GameLog.say("You attack the %s for %d damage!%s%s" % [enemy.name, damage, " CRITICAL HIT!" if roll.crit else "",
			" (War Drum)" if drum else ""], GameLog.YELLOW if roll.crit or drum else GameLog.GREEN)
	_damage_event("enemy", damage, enemy.hp, roll.crit or drum)
	_on_player_hit(player, enemy)


static func _poison_enemy(enemy: EnemyData, turns: int, damage: int) -> void:
	enemy.poison = maxi(enemy.poison, turns)
	enemy.poison_damage = maxi(enemy.poison_damage, damage)
	GameLog.say("The %s is poisoned (%d damage for %d turns)!" % [enemy.name, damage, turns], GameLog.GREEN)
	_status("enemy", "POISONED", GameLog.GREEN)


static func _poison_player(player: PlayerData, turns: int, damage: int, label: String = "POISONED") -> void:
	player.poison = maxi(player.poison, turns)
	player.poison_damage = maxi(player.poison_damage, damage)
	GameLog.say("You are %s (%d damage for %d turns)!" % [label.to_lower(), damage, turns], GameLog.GREEN)
	_status("player", label, GameLog.GREEN)


static func use_skill(player: PlayerData, enemy: EnemyData) -> void:
	GameLog.event({"type": "skill", "name": player.skill_name})
	GameLog.event({"type": "attack", "by": "player"})
	var damage := 0
	match player.skill_name:
		"Power Strike":
			damage = hit_enemy(enemy, player.atk * 2)
			GameLog.say("POWER STRIKE! You smash the %s for %d damage!" % [enemy.name, damage], GameLog.GREEN)
			_damage_event("enemy", damage, enemy.hp, true)
		"Backstab":
			damage = hit_enemy(enemy, roundi(player.atk * 2.5))
			GameLog.say("BACKSTAB! You slip behind the %s for %d damage!" % [enemy.name, damage], GameLog.GREEN)
			_damage_event("enemy", damage, enemy.hp, true)
		"Smite":
			damage = hit_enemy(enemy, player.atk + 2)
			var healed := player.heal(4 + player.level)
			player.poison = 0
			GameLog.say("SMITE! Holy light hits the %s for %d damage%s!" % [enemy.name, damage,
					" and heals you for %d" % healed if healed > 0 else ""], GameLog.YELLOW)
			_damage_event("enemy", damage, enemy.hp, false, "holy")
			_heal_event("player", healed, player.hp)
		"Drain Life":
			damage = hit_enemy(enemy, roundi(player.atk * 1.5))
			var healed := player.heal(maxi(1, roundi(damage * 0.7)))
			GameLog.say("DRAIN LIFE! You leech %d damage from the %s and heal %d!" % [damage, enemy.name, healed],
					GameLog.MAGENTA)
			_damage_event("enemy", damage, enemy.hp, false, "holy")
			_heal_event("player", healed, player.hp)
	_on_player_hit(player, enemy)


static func use_ult(player: PlayerData, enemy: EnemyData) -> void:
	GameLog.event({"type": "skill", "name": player.ult_name, "ult": true})
	match player.ult_name:
		"Shield Wall":
			player.shield_wall = true
			GameLog.say("SHIELD WALL! The next enemy hit is blocked.", GameLog.BLUE)
			GameLog.event({"type": "defend"})
		"Poison Blade":
			GameLog.event({"type": "attack", "by": "player"})
			var damage := hit_enemy(enemy, player.atk)
			GameLog.say("POISON BLADE! You cut the %s for %d damage." % [enemy.name, damage], GameLog.GREEN)
			_damage_event("enemy", damage, enemy.hp)
			_poison_enemy(enemy, 4, 2 + player.level / 3)
		"Divine Light":
			var healed := player.heal(roundi(player.max_hp * 0.4))
			player.poison = 0
			GameLog.say("DIVINE LIGHT! You are healed for %d HP and cleansed." % healed, GameLog.YELLOW)
			_heal_event("player", healed, player.hp)
		"Plague":
			_poison_enemy(enemy, 4, 3 + player.level / 3)


## Use consumable number idx. Free action: the enemy does not get a turn.
static func use_item(player: PlayerData, enemy: EnemyData, idx: int) -> bool:
	if idx >= player.items.size():
		return false
	var id: String = player.items[idx]
	player.items.remove_at(idx)
	var item: Dictionary = Config.CONSUMABLES[id]
	GameLog.event({"type": "item", "id": id, "name": item["name"]})
	match id:
		"bomb":
			var damage := 8 + 2 * player.level
			enemy.hp -= damage
			GameLog.say("You throw a bomb at the %s for %d damage!" % [enemy.name, damage], GameLog.YELLOW)
			_damage_event("enemy", damage, enemy.hp, true, "bomb")
		"fire":
			_poison_enemy(enemy, 3, 4 + player.level / 2)
		"tonic":
			player.strength += 3
			GameLog.say("You down a Strength Tonic. +3 ATK this fight!", GameLog.YELLOW)
			_status("player", "+3 ATK", GameLog.YELLOW)
		"smoke":
			player.dodge_next = true
			GameLog.say("Smoke billows around you. The next attack will miss.", GameLog.CYAN)
			_status("player", "HIDDEN", GameLog.CYAN)
		"elixir":
			var healed := player.heal(roundi(player.max_hp * 0.5))
			player.poison = 0
			GameLog.say("The Elixir restores %d HP." % healed, GameLog.GREEN)
			_heal_event("player", healed, player.hp)
	return true


## One enemy hit. mult scales damage; ignore_armor / ignore_defend for specials; drain heals the enemy.
static func enemy_attack(player: PlayerData, enemy: EnemyData, mult: float = 1.0, ignore_armor: bool = false,
		ignore_defend: bool = false, drain: bool = false) -> int:
	GameLog.event({"type": "attack", "by": "enemy", "heavy": mult >= 1.5})
	if player.shield_wall:
		player.shield_wall = false
		GameLog.say("Your Shield Wall blocks the %s's attack!" % enemy.name, GameLog.BLUE)
		_status("player", "BLOCKED", GameLog.BLUE)
		return 0
	var dodge := player.dodge_next or (player.has_relic("cloak") and randf() < 0.15)
	var roll := roll_damage(enemy.current_atk)
	if roll.miss or dodge:
		player.dodge_next = false
		GameLog.say("You dodge the %s's attack!" % enemy.name if dodge else "The %s attacks and misses!" % enemy.name,
				GameLog.CYAN if dodge else GameLog.GRAY)
		GameLog.event({"type": "miss", "target": "player"})
		return 0
	var damage := maxi(1, roundi(roll.damage * mult) - (0 if ignore_armor else player.armor))
	if player.defending and not ignore_defend:
		damage = maxi(1, damage / 4 if player.has_relic("anchor") else damage / 2)
	player.hp -= damage

	if player.hp <= 0 and player.has_relic("phoenix"):
		player.relics.erase("phoenix")
		player.hp = roundi(player.max_hp * 0.3)
		GameLog.say("The Phoenix Feather bursts into flame! You rise again with %d HP." % player.hp, GameLog.YELLOW)
		_damage_event("player", damage, 0, true)
		_heal_event("player", player.hp, player.hp)
		return damage
	GameLog.say("The %s %s you for %d damage%s!%s" % [enemy.name, "SLAMS" if mult >= 1.5 else "hits", damage,
			" (blocked)" if player.defending and not ignore_defend else "", " CRITICAL HIT!" if roll.crit else ""], GameLog.RED)
	_damage_event("player", damage, player.hp, roll.crit or mult >= 1.5)

	var thorns := 2 * player.perk("thorns") + (3 if player.has_relic("cactus") else 0)
	if thorns > 0 and enemy.hp > 0:
		enemy.hp -= thorns
		GameLog.say("Thorns hit the %s for %d." % [enemy.name, thorns], GameLog.GREEN)
		_damage_event("enemy", thorns, enemy.hp, false, "thorns")

	if drain or enemy.enemy_trait == "lifesteal":
		var healed := mini(damage if drain else damage / 2 + 1, enemy.max_hp - enemy.hp)
		if healed > 0:
			enemy.hp += healed
			GameLog.say("The %s drains %d HP!" % [enemy.name, healed], GameLog.MAGENTA)
			_heal_event("enemy", healed, enemy.hp)
	elif enemy.enemy_trait == "poison" and randf() < Config.POISON_CHANCE:
		_poison_player(player, Config.POISON_TURNS, 1)
	elif enemy.enemy_trait == "frost" and randf() < Config.CHILL_CHANCE:
		_chill(player)
	return damage


## Frost: push the player's cooldowns back a turn.
static func _chill(player: PlayerData) -> void:
	player.skill_cooldown += 1
	if player.ult_unlocked:
		player.ult_cooldown += 1
	GameLog.say("The cold bites deep. Your abilities slow down!", GameLog.CYAN)
	_status("player", "CHILLED", GameLog.CYAN)


## The enemy's signature move.
static func enemy_special(player: PlayerData, enemy: EnemyData) -> void:
	var move: String = enemy.special["name"]
	GameLog.event({"type": "status", "target": "enemy", "text": move.to_upper() + "!", "color": GameLog.MAGENTA})
	GameLog.say("The %s uses %s!" % [enemy.name, move], GameLog.MAGENTA)
	match enemy.base_name:
		"Goblin":
			if enemy_attack(player, enemy, 0.5) > 0:
				var stolen := mini(player.gold, 5 + enemy.level * 2)
				player.gold -= stolen
				if stolen > 0:
					GameLog.say("The Goblin snatches %d gold!" % stolen, GameLog.YELLOW)
					_status("player", "-%d gold" % stolen, GameLog.YELLOW)
		"Orc":
			enemy.rage += 2
			GameLog.say("The %s roars. +2 ATK!" % enemy.name, GameLog.RED)
		"Troll":
			var healed := mini(roundi(enemy.max_hp * 0.2), enemy.max_hp - enemy.hp)
			enemy.hp += healed
			GameLog.say("The %s's wounds close. +%d HP." % [enemy.name, healed], GameLog.MAGENTA)
			_heal_event("enemy", healed, enemy.hp)
		"Skeleton":
			enemy_attack(player, enemy, 1.0, true, true)
		"Zombie":
			if enemy_attack(player, enemy) > 0:
				_poison_player(player, 3, 2)
		"Vampire":
			enemy_attack(player, enemy, 1.0, false, false, true)
		"Werewolf":
			for i in 3:
				if player.hp > 0:
					enemy_attack(player, enemy, 0.6)
		"Demon":
			if enemy_attack(player, enemy) > 0:
				_poison_player(player, 3, 3, "BURNING")
		"Giant":
			enemy_attack(player, enemy, 1.5, false, true)
		"Dragon":
			enemy_attack(player, enemy, 1.8, true)
		"Slime":
			if enemy_attack(player, enemy) > 0 and player.armor > 0:
				player.corroded += 1
				GameLog.say("Acid eats into your armor! -1 armor this fight.", GameLog.GREEN)
				_status("player", "-1 ARMOR", GameLog.GREEN)
		"Wraith":
			if enemy_attack(player, enemy) > 0 and player.strength > -3:
				player.strength -= 1
				GameLog.say("The Wraith drains your strength! -1 ATK this fight.", GameLog.MAGENTA)
				_status("player", "-1 ATK", GameLog.MAGENTA)
		"Golem":
			enemy.guarding = true
			enemy.fortify += 1
			GameLog.say("The %s's stone skin thickens. +1 armor!" % enemy.name, GameLog.BLUE)
			_status("enemy", "+1 ARMOR", GameLog.BLUE)
		"Yeti":
			if enemy_attack(player, enemy, 1.6) > 0 and player.hp > 0:
				_chill(player)
		"Lich":
			if enemy_attack(player, enemy, 1.4, true) > 0 and player.hp > 0:
				_poison_player(player, 3, 3, "CURSED")
		_:
			enemy_attack(player, enemy, 1.3)


## Enemy carries out its intent, then end-of-round effects (regen, poison) tick.
static func enemy_turn(player: PlayerData, enemy: EnemyData) -> void:
	enemy_act(player, enemy)
	end_of_round([player], enemy)
	enemy.choose_intent()
	GameLog.event({"type": "intent"})


## The enemy's intent, aimed at one hero.
static func enemy_act(player: PlayerData, enemy: EnemyData) -> void:
	enemy.guarding = false
	match enemy.intent:
		"attack":
			enemy_attack(player, enemy)
			if enemy.enemy_trait == "quick" and player.hp > 0 and enemy.hp > 0 and randf() < Config.QUICK_CHANCE:
				GameLog.say("The %s is quick and attacks again!" % enemy.name, GameLog.RED)
				_status("enemy", "QUICK!", GameLog.RED)
				enemy_attack(player, enemy)
		"heavy":
			enemy_attack(player, enemy, 2.0)
		"charge":
			GameLog.say("The %s gathers its strength..." % enemy.name, GameLog.YELLOW)
			_status("enemy", "CHARGING", GameLog.YELLOW)
		"guard":
			enemy.guarding = true
			GameLog.say("The %s raises its guard." % enemy.name, GameLog.BLUE)
			_status("enemy", "GUARD", GameLog.BLUE)
		"special":
			enemy_special(player, enemy)


## Regen and poison tick for the enemy and every standing hero.
static func end_of_round(players: Array, enemy: EnemyData) -> void:
	if enemy.enemy_trait == "regen" and enemy.hp < enemy.max_hp and enemy.hp > 0:
		var healed := mini(1 + enemy.level / 3, enemy.max_hp - enemy.hp)
		enemy.hp += healed
		GameLog.say("The %s regenerates %d HP." % [enemy.name, healed], GameLog.MAGENTA)
		_heal_event("enemy", healed, enemy.hp)

	if enemy.poison > 0 and enemy.hp > 0:
		enemy.hp -= enemy.poison_damage
		enemy.poison -= 1
		GameLog.say("Poison deals %d damage to the %s." % [enemy.poison_damage, enemy.name], GameLog.GREEN)
		_damage_event("enemy", enemy.poison_damage, enemy.hp, false, "poison")

	for player: PlayerData in players:
		GameLog.slot = player.slot
		if player.poison > 0 and player.hp > 0:
			player.hp -= player.poison_damage
			player.poison -= 1
			GameLog.say("Poison deals %d damage." % player.poison_damage, GameLog.GREEN)
			_damage_event("player", player.poison_damage, player.hp, false, "poison")
			if player.poison == 0:
				player.poison_damage = 1

		if player.hp > 0 and player.hp < player.max_hp * 0.3 and player.perk("second_wind") > 0 and not player.second_wind_used:
			player.second_wind_used = true
			var healed := player.heal(roundi(player.max_hp * 0.3))
			GameLog.say("Second Wind! You recover %d HP." % healed, GameLog.YELLOW)
			_heal_event("player", healed, player.hp)


## Do one player action. Returns "ok", "free" (no enemy turn), "fled" or "invalid" (no turn used).
static func player_turn(player: PlayerData, enemy: EnemyData, action: String) -> String:
	if action.begins_with("i"):
		return "free" if use_item(player, enemy, int(action.substr(1))) else "invalid"
	match action:
		"a":
			player_attack(player, enemy)
		"s":
			if player.skill_cooldown > 0:
				GameLog.say("%s is recharging (%d turns left)." % [player.skill_name, player.skill_cooldown], GameLog.RED)
				return "invalid"
			use_skill(player, enemy)
			player.skill_cooldown = player.skill_max_cooldown + 1  # +1 because it ticks down this turn
		"f":
			if not player.ult_unlocked:
				GameLog.say("%s unlocks at level %d." % [player.ult_name, Config.ULT_LEVEL], GameLog.RED)
				return "invalid"
			if player.ult_cooldown > 0:
				GameLog.say("%s is recharging (%d turns left)." % [player.ult_name, player.ult_cooldown], GameLog.RED)
				return "invalid"
			use_ult(player, enemy)
			player.ult_cooldown = player.ult_max_cooldown + 1
		"d":
			player.defending = true
			GameLog.say("You raise your guard.", GameLog.BLUE)
			GameLog.event({"type": "defend"})
		"h":
			if player.potions == 0:
				GameLog.say("You have no potions left!", GameLog.RED)
				return "invalid"
			if player.hp == player.max_hp and player.poison == 0:
				GameLog.say("You are already at full HP!")
				return "invalid"
			var healed := player.heal(player.heal_amount)
			player.potions -= 1
			player.poison = 0  # potions also cure poison
			GameLog.say("You used a potion and healed for %d HP!" % healed, GameLog.GREEN)
			_heal_event("player", healed, player.hp)
		"r":
			if enemy.boss:
				GameLog.say("There is no escape from a boss!", GameLog.RED)
				return "invalid"
			if randf() < player.run_chance:
				GameLog.say("You ran away from the battle!", GameLog.CYAN)
				GameLog.event({"type": "fled"})
				return "fled"
			GameLog.say("You failed to escape!", GameLog.RED)
			_status("player", "CAN'T ESCAPE", GameLog.RED)
		_:
			return "invalid"
	return "ok"


static func start_battle(player: PlayerData, enemy: EnemyData) -> void:
	if player.has_relic("dragon_eye"):
		enemy.max_hp = maxi(1, roundi(enemy.max_hp * 0.8))
		enemy.hp = enemy.max_hp
	GameLog.event({"type": "appear", "boss": enemy.boss, "elite": enemy.elite})
	if enemy.boss:
		GameLog.say("!!! The %s (Level %d) blocks your path! You cannot run. !!!" % [enemy.name, enemy.level], GameLog.RED)
	else:
		GameLog.say("A%s %s (Level %d) appears!" % ["n" if enemy.elite else "", enemy.name, enemy.level], GameLog.MAGENTA)
	player.start_battle()
	GameLog.event({"type": "intent"})


## One full round. Returns "win", "lose", "fled", "ok" (fight goes on) or "invalid".
static func take_turn(player: PlayerData, enemy: EnemyData, action: String) -> String:
	if not action.begins_with("i"):
		player.defending = false
	var result := player_turn(player, enemy, action)
	if result == "free":
		return "win" if _enemy_dead(enemy) else "ok"
	if result != "ok":
		return result
	if _enemy_dead(enemy):
		return "win"

	player.skill_cooldown = maxi(0, player.skill_cooldown - 1)
	player.ult_cooldown = maxi(0, player.ult_cooldown - 1)

	# enemy gets a turn after every valid action, including heal/defend/failed run
	GameLog.event({"type": "pause", "time": 0.25})
	enemy_turn(player, enemy)
	if player.hp <= 0:
		GameLog.event({"type": "death", "target": "player"})
		return "lose"
	if _enemy_dead(enemy):  # poison or thorns finished it
		return "win"
	return "ok"


## Death check after damage. Slimes split below half HP; undying enemies rise once.
static func _enemy_dead(enemy: EnemyData) -> bool:
	if enemy.hp > 0:
		if enemy.enemy_trait == "split" and not enemy.split_done and enemy.hp <= enemy.max_hp / 2:
			enemy.split_done = true
			var healed := mini(roundi(enemy.max_hp * 0.25), enemy.max_hp - enemy.hp)
			enemy.hp += healed
			GameLog.say("The %s splits and pulls itself back together! +%d HP." % [enemy.name, healed], GameLog.GREEN)
			_status("enemy", "SPLIT!", GameLog.GREEN)
			_heal_event("enemy", healed, enemy.hp)
		return false
	if enemy.enemy_trait == "undying" and not enemy.revived:
		enemy.revived = true
		enemy.poison = 0
		enemy.hp = roundi(enemy.max_hp * 0.4)
		GameLog.say("The %s refuses to die and rises again!" % enemy.name, GameLog.MAGENTA)
		_status("enemy", "RISES AGAIN!", GameLog.MAGENTA)
		_heal_event("enemy", enemy.hp, enemy.hp)
		return false
	GameLog.event({"type": "death", "target": "enemy"})
	return true
