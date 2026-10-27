class_name RunEvents
extends RefCounted
## "Unknown" map nodes: a short story with choices.
## options(id, state) lists the choices; resolve(id, choice, state) applies one and returns the result.

const EVENTS := {
	"fountain": {"title": "Healing Fountain", "text": "Clear water bubbles up from a cracked stone basin. It glows faintly."},
	"shrine": {"title": "Blood Shrine", "text": "A stone altar, stained dark. Carved words promise strength for a price in blood."},
	"gambler": {"title": "The Gambler", "text": "A grinning skeleton shakes a cup of dice. \"Double or nothing, friend?\""},
	"chest": {"title": "Suspicious Chest", "text": "An iron-bound chest sits in the middle of the corridor. Too convenient?"},
	"trainer": {"title": "Old Swordmaster", "text": "A scarred veteran sits by a fire. \"I can teach you a trick or two. For a fee.\""},
	"adventurer": {"title": "Wounded Adventurer", "text": "A wounded adventurer leans against the wall, clutching a coin purse."},
	"idol": {"title": "Cursed Idol", "text": "A small idol rests on a pedestal of bones. It hums with power... and malice."},
	"caravan": {"title": "Lost Caravan", "text": "A merchant's cart, its owner long gone. One crate is still sealed, with a price tag nailed to it."},
	"library": {"title": "Ancient Library", "text": "Dusty shelves stretch into the dark. Most books have rotted, but not all."},
	"mushrooms": {"title": "Glowing Mushrooms", "text": "Pale blue mushrooms pulse with light. They smell... surprisingly good."},
	"well": {"title": "Wishing Well", "text": "An old well. Coins glint far below. A faint voice whispers: \"Make a wish.\""},
	"statue": {"title": "Weeping Statue", "text": "A stone angel weeps tears of light. A collection bowl sits at its feet."},
}


static func random_id() -> String:
	return EVENTS.keys().pick_random()


## Choices as [{label, disabled}].
static func options(id: String, state: GameState) -> Array:
	var p := state.player
	var f := state.floor_num
	match id:
		"fountain":
			return [{"label": "Drink deeply (heal 50%)"}, {"label": "Fill a bottle (+1 potion)"}]
		"shrine":
			return [{"label": "Offer blood (lose 25% HP, +1 ATK)", "disabled": p.hp <= 4}, {"label": "Walk away"}]
		"gambler":
			return [{"label": "Bet 20 gold (50%: win 45)", "disabled": p.gold < 20}, {"label": "Decline"}]
		"chest":
			return [{"label": "Open it (70% loot, 30% trap)"}, {"label": "Leave it"}]
		"trainer":
			return [{"label": "Pay 35 gold (choose a perk)", "disabled": p.gold < 35}, {"label": "Move on"}]
		"adventurer":
			return [{"label": "Help them (+%d EXP)" % (15 * f)}, {"label": "Rob them (+%d gold)" % (20 * f)}]
		"idol":
			return [{"label": "Take it (gain a relic, lose 30% HP)", "disabled": p.hp <= 5}, {"label": "Leave it alone"}]
		"caravan":
			return [{"label": "Buy the crate for 30 gold (2 consumables)", "disabled": p.gold < 30 or p.items.size() >= Config.MAX_ITEMS},
					{"label": "Search the cart (find %d gold)" % (8 * f)}]
		"library":
			return [{"label": "Study the old tomes (+%d EXP)" % (25 * f)}, {"label": "Search for anything valuable (40%: relic)"}]
		"mushrooms":
			return [{"label": "Eat one (50%: +5 max HP forever, 50%: poisoned)"}, {"label": "Better not"}]
		"well":
			return [{"label": "Toss in 15 gold", "disabled": p.gold < 15}, {"label": "Walk on"}]
		"statue":
			return [{"label": "Pray (heal to full, costs 25% of your gold)"}, {"label": "Pry out its gem eyes (+%d gold, take damage)" % (25 * f)}]
	return [{"label": "Continue"}]


## Apply a choice. Returns {"text": String, "item": Item or null, "relic": id or ""}.
static func resolve(id: String, choice: int, state: GameState) -> Dictionary:
	var p := state.player
	var f := state.floor_num
	var out := {"text": "You move on.", "item": null, "relic": ""}
	match [id, choice]:
		["fountain", 0]:
			out.text = "The water is cool and sweet. You heal %d HP." % p.heal(roundi(p.max_hp * 0.5))
			p.poison = 0
		["fountain", 1]:
			p.potions += 1
			out.text = "You fill an empty bottle. +1 potion."
		["shrine", 0]:
			var cost := maxi(1, p.hp / 4)
			p.hp -= cost
			p.bonus_atk += 1
			out.text = "The altar drinks %d HP. Power surges through your arms. +1 ATK." % cost
		["gambler", 0]:
			if randf() < 0.5:
				p.gold += 25
				out.text = "The dice roll your way! You walk off with 45 gold."
			else:
				p.gold -= 20
				out.text = "Snake eyes. The skeleton cackles and pockets your 20 gold."
		["chest", 0]:
			if randf() < 0.7:
				out.item = Progression.roll_loot(Config.node_level(f, state.map.pos_row, "fight") + 1)
				out.text = "The lock clicks open. Something useful inside!"
			else:
				var dmg := maxi(1, roundi(p.max_hp * 0.2))
				p.hp = maxi(1, p.hp - dmg)
				out.text = "A needle trap! You take %d damage." % dmg
		["trainer", 0]:
			p.gold -= 35
			p.pending_perks += 1
			out.text = "\"Watch closely.\" He shows you a technique."
		["adventurer", 0]:
			p.gain_exp(15 * f)
			out.text = "You bandage their wounds. They share what they know of the dungeon."
		["adventurer", 1]:
			p.gold += 20 * f
			out.text = "You take the purse. They curse you as you leave."
		["idol", 0]:
			var dmg := maxi(1, roundi(p.hp * 0.3))
			p.hp = maxi(1, p.hp - dmg)
			out.relic = Progression.random_relic(p)
			out.text = "Dark energy lashes out as you lift it (-%d HP). But the idol is yours." % dmg
		["caravan", 0]:
			p.gold -= 30
			var found := []
			for i in 2:
				var c := Progression.grant_consumable(p)
				if c != "":
					found.append(Config.CONSUMABLES[c]["name"])
			out.text = "You pry the crate open: %s." % (" and ".join(found) if not found.is_empty() else "nothing you can carry")
		["caravan", 1]:
			p.gold += 8 * f
			out.text = "Under a loose plank: %d gold." % (8 * f)
		["library", 0]:
			p.gain_exp(25 * f)
			out.text = "Hours pass. You learn old fighting forms from faded diagrams."
		["library", 1]:
			if randf() < 0.4:
				out.relic = Progression.random_relic(p)
				out.text = "Behind a loose brick, wrapped in oilcloth: a relic!"
			else:
				out.text = "Only dust and mouse droppings."
		["mushrooms", 0]:
			if randf() < 0.5:
				p.bonus_hp += 5
				p.hp += 5
				out.text = "Warmth spreads through your body. +5 max HP!"
			else:
				p.poison = 3
				p.poison_damage = 2
				out.text = "Your stomach lurches. You are poisoned (2 damage for 3 turns)."
		["well", 0]:
			p.gold -= 15
			var roll := randf()
			if roll < 0.55:
				var c := Progression.grant_consumable(p)
				out.text = "Something floats up: a %s!" % Config.CONSUMABLES[c]["name"] if c != "" \
						else "Something floats up, but your bag is full."
			elif roll < 0.8:
				p.potions += 1
				p.gold += 15
				out.text = "Your coin comes back, along with a potion. Lucky!"
			else:
				out.text = "Splash. Nothing happens."
		["statue", 0]:
			var cost := p.gold / 4
			p.gold -= cost
			var healed := p.heal(p.max_hp)
			p.poison = 0
			out.text = "Light washes over you. +%d HP (the bowl takes %d gold)." % [healed, cost]
		["statue", 1]:
			var dmg := maxi(1, roundi(p.max_hp * 0.15))
			p.hp = maxi(1, p.hp - dmg)
			p.gold += 25 * f
			out.text = "The statue screams as you pry the gems free (-%d HP, +%d gold)." % [dmg, 25 * f]
	return out
