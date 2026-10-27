class_name PartyCombat
extends RefCounted
## Co-op fights: the whole party against one enemy. Only the host runs this.
## A round: every standing hero acts in slot order, then the enemy strikes the hero it was eyeing,
## then poison and regen tick. Actions use the solo keys ("a", "s", "f", "d", "h"); items go through use_item().
## Heroes knocked to 0 HP are down for the rest of the fight and get back up afterwards.

const HP_PER_EXTRA_HERO := 0.7  # enemy max HP grows by this share per extra hero
const REVIVE_HP := 0.25         # downed heroes stand up with this share of max HP after a win


## The enemy for a map node, toughened for the party size.
static func make_enemy(state: GameState, kind: String) -> EnemyData:
	var e := EnemyData.for_node(state.floor_num, state.map.pos_row, kind, state.difficulty)
	e.max_hp = roundi(e.max_hp * (1.0 + HP_PER_EXTRA_HERO * (state.players.size() - 1)))
	e.hp = e.max_hp
	return e


static func start(state: GameState, enemy: EnemyData) -> void:
	for p in state.players:
		if p.has_relic("dragon_eye"):  # one Evil Eye is enough, they don't stack
			enemy.max_hp = maxi(1, roundi(enemy.max_hp * 0.8))
			enemy.hp = enemy.max_hp
			break
	GameLog.slot = 0
	GameLog.event({"type": "appear", "boss": enemy.boss, "elite": enemy.elite})
	for p in state.players:
		p.start_battle()
	pick_target(state, enemy)
	GameLog.event({"type": "intent"})


## The enemy picks which standing hero its next move is aimed at.
static func pick_target(state: GameState, enemy: EnemyData) -> void:
	var standing := state.alive()
	if not standing.is_empty():
		enemy.target_slot = standing.pick_random().slot


## A hero uses a consumable (free action). Returns "ok", "win" or "invalid".
static func use_item(state: GameState, enemy: EnemyData, slot: int, idx: int) -> String:
	var p := state.players[slot]
	if p.hp <= 0:
		return "invalid"
	GameLog.slot = slot
	if not Combat.use_item(p, enemy, idx):
		return "invalid"
	return "win" if Combat._enemy_dead(enemy) else "ok"


## One full round. actions maps slot -> action key (missing = attack). Returns "ok", "win" or "lose".
static func play_round(state: GameState, enemy: EnemyData, actions: Dictionary) -> String:
	for p in state.alive():
		GameLog.slot = p.slot
		p.defending = false
		var act: String = actions.get(p.slot, "a")
		if act == "r" or act.begins_with("i"):  # no running away from a party fight; items are separate
			act = "d"
		if Combat.player_turn(p, enemy, act) == "invalid":
			Combat.player_turn(p, enemy, "a")
		if Combat._enemy_dead(enemy):
			return "win"
		p.skill_cooldown = maxi(0, p.skill_cooldown - 1)
		p.ult_cooldown = maxi(0, p.ult_cooldown - 1)

	var target := state.players[enemy.target_slot]
	if target.hp <= 0:
		pick_target(state, enemy)
		target = state.players[enemy.target_slot]
	GameLog.slot = target.slot
	GameLog.event({"type": "pause", "time": 0.25})
	var standing := state.alive()
	Combat.enemy_act(target, enemy)
	if Combat._enemy_dead(enemy):  # thorns
		return "win"
	Combat.end_of_round(state.players, enemy)
	for p in standing:
		if p.hp <= 0:
			GameLog.slot = p.slot
			GameLog.say("%s is down!" % p.name, GameLog.RED)
			GameLog.event({"type": "death", "target": "player"})
	if Combat._enemy_dead(enemy):  # poison
		return "win"
	if state.alive().is_empty():
		return "lose"
	enemy.choose_intent()
	pick_target(state, enemy)
	GameLog.slot = enemy.target_slot
	GameLog.event({"type": "intent"})
	return "ok"


## After a win: downed heroes get up, then everyone collects their own rewards.
## Returns slot -> {"item": item dict or null, "relic": id, "boss_relics": [ids]}.
static func finish_win(state: GameState, enemy: EnemyData) -> Dictionary:
	var out := {}
	for p in state.players:
		GameLog.slot = p.slot
		if p.hp <= 0:
			p.hp = maxi(1, roundi(p.max_hp * REVIVE_HP))
			p.poison = 0
			GameLog.event({"type": "heal", "target": "player", "amount": p.hp, "hp": p.hp, "revive": true})
		var r := Progression.give_rewards(state, enemy, p)
		out[p.slot] = {"item": r.item.to_dict() if r.item else null, "relic": r.relic, "boss_relics": r.boss_relics}
	GameLog.slot = 0
	return out


## Whole party state for the clients: persistent data plus per-battle state, and the enemy.
static func snapshot(state: GameState, enemy: EnemyData) -> Dictionary:
	var heroes := []
	for p in state.players:
		var d := p.to_dict()
		d["battle"] = p.battle_dict()
		heroes.append(d)
	return {"players": heroes, "enemy": enemy.to_dict() if enemy else {}}


## Apply a snapshot in place, so the battle screen keeps its references.
static func apply_snapshot(state: GameState, enemy: EnemyData, snap: Dictionary) -> void:
	var heroes: Array = snap["players"]
	for i in mini(heroes.size(), state.players.size()):
		state.players[i].load_dict(heroes[i])
	if enemy and not snap["enemy"].is_empty():
		enemy.load_dict(snap["enemy"])
