class_name Config
extends RefCounted
## Game balance and content tables. Tweak numbers here,
## then run tests/smoke_test.gd to see how win rates moved.

const CRIT_CHANCE := 0.15
const MISS_CHANCE := 0.10
const RUN_CHANCE := 0.5
const POTION_DROP_CHANCE := 0.3
const HEAL_AMOUNT := 5          # potions heal this + player level
const QUICK_CHANCE := 0.25
const POISON_CHANCE := 0.4
const POISON_TURNS := 3
const LOOT_DROP_CHANCE := 0.25  # elites and bosses always drop
const ULT_LEVEL := 3            # ultimate skill unlocks at this level
const REST_HEAL := 0.35         # share of max HP a rest node restores
const FLOOR_HEAL := 0.3         # share of max HP restored when descending

const SAVE_PATH := "user://savegame.json"
const HIGHSCORE_PATH := "user://highscore.json"
const META_PATH := "user://meta.json"

const ENEMY_NAMES := ["Goblin", "Orc", "Troll", "Skeleton", "Zombie", "Vampire", "Werewolf", "Demon", "Giant", "Dragon",
		"Slime", "Wraith", "Golem", "Yeti", "Lich"]

# ------------------------------------------------------------------ run structure

const FLOORS := 5
const MAP_ROWS := 6  # rows of nodes before the boss row
# base = enemy level on the first row; enemies gain up to +3 levels toward the boss row
const FLOOR_INFO := [
	{"name": "The Stone Halls", "base": 1, "boss_hp": 1.0, "pool": ["Goblin", "Orc", "Skeleton", "Slime"],
		"boss": "Troll", "boss_title": "Troll King"},
	{"name": "The Sunken Crypt", "base": 6, "boss_hp": 2.2, "pool": ["Zombie", "Skeleton", "Wraith", "Werewolf"],
		"boss": "Vampire", "boss_title": "Vampire Lord"},
	{"name": "The Frozen Caverns", "base": 11, "boss_hp": 2.8, "pool": ["Werewolf", "Golem", "Wraith", "Slime"],
		"boss": "Yeti", "boss_title": "Frost Titan"},
	{"name": "The Burning Depths", "base": 16, "boss_hp": 3.3, "pool": ["Demon", "Giant", "Golem", "Vampire"],
		"boss": "Dragon", "boss_title": "Ancient Dragon"},
	{"name": "The Void Throne", "base": 21, "boss_hp": 3.8, "pool": ["Demon", "Wraith", "Giant", "Werewolf"],
		"boss": "Lich", "boss_title": "Lich Emperor"},
]
# map node weights (row 0 is always fights, the last row is always rest)
const NODE_WEIGHTS := {"fight": 46, "event": 20, "elite": 10, "shop": 9, "rest": 10, "treasure": 5}
const NODE_NAMES := {"fight": "Fight", "elite": "Elite", "event": "Unknown", "shop": "Shop", "rest": "Campfire",
		"treasure": "Treasure", "boss": "Boss"}

const ELITE_HP_MULT := 1.4


static func node_level(floor_num: int, row: int, kind: String) -> int:
	var base: int = FLOOR_INFO[floor_num - 1]["base"]
	if kind == "boss":
		return base + 3
	return base + int(row * 4 / (MAP_ROWS + 1)) + (1 if kind == "elite" else 0)


# ------------------------------------------------------------------ difficulty / classes

const DIFFICULTIES := {
	"Easy": {"enemy_hp": 0.8, "enemy_atk": 0.8, "gold": 1.3, "souls": 0.75},
	"Normal": {"enemy_hp": 1.0, "enemy_atk": 1.0, "gold": 1.0, "souls": 1.0},
	"Hard": {"enemy_hp": 1.2, "enemy_atk": 1.15, "gold": 0.85, "souls": 1.5},
}

# skill = always available, ult = unlocks at ULT_LEVEL
const CLASSES := {
	"Warrior": {"desc": "+4 max HP, 1 armor.\nSkill: Power Strike (2x damage).\nUltimate: Shield Wall (block the next hit).",
		"bonus_hp": 4, "armor": 1, "skill": "Power Strike", "cooldown": 4, "ult": "Shield Wall", "ult_cooldown": 5},
	"Rogue": {"desc": "30% crit, 85% run chance.\nSkill: Backstab (2.5x damage).\nUltimate: Poison Blade (heavy poison).",
		"crit_chance": 0.3, "run_chance": 0.85, "skill": "Backstab", "cooldown": 4, "ult": "Poison Blade", "ult_cooldown": 4},
	"Cleric": {"desc": "+3 max HP, 5 stronger potions.\nSkill: Smite (hit + heal).\nUltimate: Divine Light (heal 40%).",
		"bonus_hp": 3, "potions": 5, "heal_amount": 9, "skill": "Smite", "cooldown": 2, "ult": "Divine Light", "ult_cooldown": 5},
	"Necromancer": {"desc": "+3 max HP, +50% souls.\nSkill: Drain Life (hit, heal most of it).\nUltimate: Plague (deadly poison).",
		"bonus_hp": 3, "souls_mult": 1.5, "skill": "Drain Life", "cooldown": 3, "ult": "Plague", "ult_cooldown": 4,
		"locked": true},
}

const SKILL_DESC := {
	"Power Strike": "Hit for 2x ATK. Never misses.",
	"Backstab": "Hit for 2.5x ATK. Never misses.",
	"Smite": "Hit for ATK + 2 and heal 4 + level HP. Cures poison.",
	"Drain Life": "Hit for 1.5x ATK and heal 70% of the damage dealt.",
	"Shield Wall": "Completely block the next enemy hit.",
	"Poison Blade": "Hit for ATK and poison the enemy: 2 + level/3 damage for 4 turns.",
	"Divine Light": "Heal 40% of your max HP and cure poison.",
	"Plague": "Poison the enemy: 3 + level/3 damage for 4 turns.",
}

# ------------------------------------------------------------------ enemies

const TRAIT_DESC := {
	"quick": "may attack twice",
	"berserk": "hits harder below half HP",
	"regen": "regenerates HP each turn",
	"armored": "takes 1 less damage per hit",
	"poison": "attacks can poison you",
	"lifesteal": "heals from damage it deals",
	"split": "splits once below half HP, healing 25%",
	"ethereal": "your basic attacks pass through it 20% of the time",
	"stone": "takes 2 less damage per hit",
	"frost": "hits can chill you (+1 turn on your cooldowns)",
	"undying": "rises again once with 40% HP",
}
const ENEMY_TRAITS := {
	"Goblin": "quick", "Orc": "berserk", "Troll": "regen", "Skeleton": "armored",
	"Zombie": "poison", "Vampire": "lifesteal", "Werewolf": "berserk", "Demon": "poison",
	"Giant": "armored", "Dragon": "quick",
	"Slime": "split", "Wraith": "ethereal", "Golem": "stone", "Yeti": "frost", "Lich": "undying",
}
const CHILL_CHANCE := 0.3
# intent weights: what an enemy plans for its next turn
const INTENTS := {"attack": 58, "charge": 14, "guard": 12, "special": 16}
const BOSS_INTENTS := {"attack": 45, "charge": 22, "guard": 10, "special": 23}

# each enemy type's signature move (the "special" intent)
const SPECIALS := {
	"Goblin": {"name": "Pilfer", "desc": "weak hit that steals gold"},
	"Orc": {"name": "War Cry", "desc": "gains +2 ATK"},
	"Troll": {"name": "Regrow", "desc": "heals 20% HP"},
	"Skeleton": {"name": "Bone Spear", "desc": "hit that ignores armor and Defend"},
	"Zombie": {"name": "Infect", "desc": "hit that always poisons (2 dmg, 3 turns)"},
	"Vampire": {"name": "Blood Feast", "desc": "hit that heals it for all damage dealt"},
	"Werewolf": {"name": "Frenzy", "desc": "three quick slashes"},
	"Demon": {"name": "Hellfire", "desc": "hit that burns you (3 dmg, 3 turns)"},
	"Giant": {"name": "Ground Slam", "desc": "1.5x hit that ignores Defend"},
	"Dragon": {"name": "Fire Breath", "desc": "1.8x hit that ignores armor"},
	"Slime": {"name": "Acid Spit", "desc": "hit that melts 1 armor for this fight"},
	"Wraith": {"name": "Soul Drain", "desc": "hit that saps 1 ATK for this fight"},
	"Golem": {"name": "Harden", "desc": "guards and gains +1 armor"},
	"Yeti": {"name": "Avalanche", "desc": "1.6x hit that chills you"},
	"Lich": {"name": "Soul Storm", "desc": "1.4x hit that ignores armor and curses you (3 dmg, 3 turns)"},
}

# ------------------------------------------------------------------ shop / loot

# key -> name, base price, extra price per purchase of that upgrade
const SHOP := {
	"potion": {"name": "Potion", "base": 10, "step": 0},
	"atk": {"name": "Sharpen weapon (+1 ATK)", "base": 25, "step": 15},
	"hp": {"name": "Toughen armor (+3 max HP)", "base": 20, "step": 12},
}
const WEAPON_NAMES := ["Rusty Dagger", "Short Sword", "Longsword", "War Axe", "Runeblade", "Frostbrand", "Dragonfang",
		"Voidreaver"]
const ARMOR_NAMES := ["Leather Vest", "Chainmail", "Scale Armor", "Plate Armor", "Runic Plate", "Frostguard Mail",
		"Dragonscale", "Void Aegis"]
const RARITIES := [  # name, stat multiplier, weight
	["Common", 1.0, 65],
	["Rare", 1.5, 28],
	["Epic", 2.0, 7],
]
const RARITY_COLORS := {"Common": "#dddddd", "Rare": "#5fa8ff", "Epic": "#c77dff"}

# ------------------------------------------------------------------ perks (one pick per level up)

const PERKS := {
	"tough": {"name": "Toughness", "desc": "+4 max HP", "max": 5},
	"strong": {"name": "Strength", "desc": "+1 ATK", "max": 5},
	"keen": {"name": "Keen Eye", "desc": "+8% crit chance", "max": 3},
	"armor": {"name": "Thick Skin", "desc": "+1 armor", "max": 2},
	"alchemist": {"name": "Alchemist", "desc": "Potions heal +4", "max": 3},
	"thorns": {"name": "Thorns", "desc": "Attackers take 2 damage", "max": 2},
	"vampiric": {"name": "Vampiric", "desc": "Heal 1 HP each time you hit", "max": 3},
	"greedy": {"name": "Greed", "desc": "+25% gold", "max": 2},
	"swift": {"name": "Swiftness", "desc": "Skill cooldown -1", "max": 1},
	"second_wind": {"name": "Second Wind", "desc": "Once per fight, heal 30% when below 30% HP", "max": 1},
}

# ------------------------------------------------------------------ relics (passive items, keep for the whole run)

const RELICS := {
	"whetstone": {"name": "Whetstone", "desc": "+2 ATK"},
	"iron_heart": {"name": "Iron Heart", "desc": "+10 max HP"},
	"clover": {"name": "Four-Leaf Clover", "desc": "+10% crit chance"},
	"cactus": {"name": "Spiked Pauldron", "desc": "Attackers take 3 damage"},
	"bandages": {"name": "Field Bandages", "desc": "Heal 4 HP after every won fight"},
	"idol": {"name": "Golden Idol", "desc": "+40% gold"},
	"drum": {"name": "War Drum", "desc": "Your first attack each fight deals double damage"},
	"cloak": {"name": "Shadow Cloak", "desc": "15% chance to dodge enemy attacks"},
	"hourglass": {"name": "Hourglass", "desc": "Ultimate cooldown -1"},
	"phoenix": {"name": "Phoenix Feather", "desc": "Once: survive a killing blow with 30% HP"},
	"venom": {"name": "Venom Gland", "desc": "Your hits poison (2 dmg, 2 turns)"},
	"anchor": {"name": "Anchor Shield", "desc": "Defend blocks 75% instead of 50%"},
	"magnet": {"name": "Lodestone", "desc": "Enemies drop items twice as often"},
	"tome": {"name": "Old Tome", "desc": "+25% EXP"},
	"mask": {"name": "Berserker Mask", "desc": "+3 ATK while below half HP"},
}
const BOSS_RELICS := {
	"crown": {"name": "Crown of Kings", "desc": "+2 ATK, +1 armor, +8 max HP"},
	"orb": {"name": "Seer's Orb", "desc": "Skill cooldown -1 and +1 potion per floor"},
	"skull": {"name": "Lich Skull", "desc": "Heal 15% of max HP after every won fight"},
	"dragon_eye": {"name": "Evil Eye", "desc": "Enemies start each fight with 20% less HP"},
}

# ------------------------------------------------------------------ consumables (single use, free action in battle)

const MAX_ITEMS := 3
const CONSUMABLES := {
	"bomb": {"name": "Bomb", "desc": "Deal 8 + 2x level damage, ignores armor", "price": 18},
	"fire": {"name": "Fire Flask", "desc": "Burn the enemy: 4 + level/2 damage for 3 turns", "price": 16},
	"tonic": {"name": "Strength Tonic", "desc": "+3 ATK for this fight", "price": 14},
	"smoke": {"name": "Smoke Bomb", "desc": "Dodge the next enemy attack", "price": 12},
	"elixir": {"name": "Elixir", "desc": "Heal 50% of max HP and cure poison", "price": 22},
}
const ITEM_DROP_CHANCE := 0.18  # elites always drop one

# ------------------------------------------------------------------ meta progression

const META_UPGRADES := {
	"vitality": {"name": "Vitality", "desc": "+3 starting max HP", "costs": [20, 40, 70]},
	"satchel": {"name": "Satchel", "desc": "+1 starting potion", "costs": [25, 55]},
	"purse": {"name": "Purse", "desc": "+15 starting gold", "costs": [15, 30, 50]},
	"wisdom": {"name": "Wisdom", "desc": "+15% EXP", "costs": [30, 70]},
	"necromancer": {"name": "Necromancer", "desc": "Unlock the Necromancer class", "costs": [100]},
}

const ACHIEVEMENTS := {
	"first_blood": {"name": "First Blood", "desc": "Win a fight"},
	"boss_slayer": {"name": "Boss Slayer", "desc": "Defeat a floor boss"},
	"dragon_slayer": {"name": "Dragon Slayer", "desc": "Defeat the Ancient Dragon"},
	"conqueror": {"name": "Conqueror", "desc": "Win a run: topple the Lich Emperor"},
	"frostbitten": {"name": "Frostbitten", "desc": "Reach the Frozen Caverns"},
	"void_walker": {"name": "Void Walker", "desc": "Reach the Void Throne"},
	"hard_win": {"name": "Unbreakable", "desc": "Win a run on Hard"},
	"epic_loot": {"name": "Shiny!", "desc": "Find an Epic item"},
	"level_10": {"name": "Veteran", "desc": "Reach level 10"},
	"hoarder": {"name": "Hoarder", "desc": "Hold 200 gold at once"},
	"centurion": {"name": "Centurion", "desc": "Defeat 100 enemies in total"},
	"all_classes": {"name": "Jack of All Trades", "desc": "Win with every class"},
}


# ------------------------------------------------------------------ formulas

static func enemy_hp(level: int) -> float:
	return 10 + (level - 1) * 4


static func player_hp(level: int) -> int:
	return 14 + (level - 1) * 4


static func enemy_atk(level: int) -> float:
	return 2 + (level - 1) * 1.3


static func player_atk(level: int) -> int:
	return 3 + (level - 1)


static func exp_needed(level: int) -> int:
	return 20 + (level - 1) * 12
