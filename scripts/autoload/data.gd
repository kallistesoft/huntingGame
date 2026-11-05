extends Node
## Static game data and balance values. Tune numbers here; the rest of the
## code reads from this file instead of hard-coding them.

# --- Player and survival -----------------------------------------------------
# Distances are in metres (1 unit = 1 m), speeds in metres per second.

const PLAYER_SPEED := 5.0 # metres per second
const BASE_CARRY := 20.0 # kg
const START_ENERGY := 100.0
const MAX_HEALTH := 100.0
const HEALTH_REGEN := 0.5 # per second while food and water are above LOW_NEED
const REVIVE_HEALTH := 0.5 # share of max health after the "get back up" ad
const REVIVE_GRACE := 2.0 # seconds the hunter can't be hit after getting back up
const STARVE_DAMAGE := 1.0 # health lost per second for each of food/water at 0
## Starvation never hurts inside the camp or near an outpost campfire: the
## hunter can always make it home and cook something.
const CAMP := Rect2(5.5, 11, 16, 10.5) # the home camp clearing, zone 1
const CAMPFIRE_SAFE_RADIUS := 6.0 # metres around an outpost's spot
const WAKE_NEEDS := 50.0 # food and water after giving up and waking at home
const HUNGER_PER_SEC := 100.0 / 480.0 # full to empty in 8 minutes
const THIRST_PER_SEC := 100.0 / 300.0 # full to empty in 5 minutes
const SLEEP_NEED_RATE := 0.5 # hunger/thirst drain multiplier while asleep
const LOW_NEED := 25.0 # below this, hunger/thirst slow the hunter
const LOW_NEED_SPEED := 0.75
const EMPTY_NEED_SPEED := 0.5
const EXHAUSTED_SPEED := 0.6 # speed multiplier at 0 energy
const DRINK_AMOUNT := 100.0
const ATTACK_ENERGY := 2.0
const NO_HOUSE_SLEEP_TIME := 60.0 # seconds, sleeping on the ground

# --- Monetization ------------------------------------------------------------

const AD_ENERGY_REWARD := 10.0
const ADS_PER_DAY := 10

# --- Progression -------------------------------------------------------------

## Total XP needed to reach level (index + 1). Level 1 starts at 0 XP.
## The curve follows the quest lines (tools/xp_budget.gd prints where each
## level lands): a zone's level gate is reached around its boss fight, so a
## new zone opens when the previous line is nearly done, not halfway through.
const LEVEL_XP := [0, 60, 200, 450, 900, 1250, 1600, 2000, 2600, 3300, 3800, 4400, 4900, 5800, 6800, 7400, 8000, 8700, 9500, 10500]

# --- Zones -------------------------------------------------------------------

## The map, zone by zone, laid out left to right. Everything that differs
## between zones lives here, so a new zone is a new entry (plus its items,
## animals, boss, recipes and quests). Rects are on the ground plane.
##   unlock:    level needed, and the boss (id in BOSSES) to defeat first ("" for none)
##   entry:     how the zone is closed until unlocked: {"kind": "fence"} draws a
##              fence along its west edge; {"kind": "pass", "name", "position",
##              "facing"} is a gate to walk through (an interactable landmark)
##   resources: node kind -> how many to scatter; animals: kind -> how many
##   ponds:     water spots; boss: id in BOSSES or ""; outpost: chest + campfire spot or null
const ZONES := [
	{
		"id": "meadow", "name": "the meadow", "label": "",
		"rect": Rect2(0, 0, 45, 32.5),
		"ground": Color(0.36, 0.52, 0.26), "grass": Color(0.42, 0.62, 0.3), "grass_count": 1400, "flowers": 160,
		"unlock": {"level": 1, "boss": ""}, "entry": {},
		"resources": {"tree": 30, "rock": 14, "bush": 12, "grass": 14},
		"animals": {"rabbit": 6, "squirrel": 5},
		"ponds": [Vector2(34, 7.5)], "boss": "", "outpost": null,
	},
	{
		"id": "east_forest", "name": "the east forest", "label": "EAST FOREST",
		"rect": Rect2(45, 0, 40, 32.5),
		"ground": Color(0.24, 0.4, 0.22), "grass": Color(0.3, 0.5, 0.26), "grass_count": 1300, "flowers": 0,
		"unlock": {"level": 3, "boss": ""}, "entry": {"kind": "fence"},
		"resources": {"tree": 40, "rock": 20, "bush": 10, "grass": 8},
		"animals": {"rabbit": 4, "squirrel": 3, "deer": 4},
		"ponds": [Vector2(67, 24)], "boss": "boar", "outpost": Vector2(49.5, 17),
	},
	{
		"id": "mountains", "name": "the mountains", "label": "MOUNTAINS",
		"rect": Rect2(85, 0, 40, 32.5),
		"ground": Color(0.44, 0.47, 0.4), "grass": Color(0.52, 0.56, 0.42), "grass_count": 700, "flowers": 0,
		"unlock": {"level": 8, "boss": "boar"},
		"entry": {"kind": "pass", "name": "Mountain pass", "position": Vector2(83.5, 25), "facing": -90},
		"resources": {"tree": 14, "rock": 16, "iron_rock": 12, "herb": 8, "grass": 4},
		"animals": {"snow_hare": 5, "goat": 4, "wolf": 3},
		"ponds": [Vector2(104, 7)], "boss": "bear", "outpost": Vector2(89.5, 17),
	},
	{
		"id": "far_north", "name": "the far north", "label": "FAR NORTH",
		"rect": Rect2(125, 0, 40, 32.5),
		"ground": Color(0.76, 0.79, 0.83), "grass": Color(0.66, 0.72, 0.8), "grass_count": 400, "flowers": 0,
		"unlock": {"level": 13, "boss": "bear"},
		"entry": {"kind": "pass", "name": "Northern pass", "position": Vector2(123.5, 25), "facing": -90},
		"resources": {"tree": 10, "rock": 8, "silver_rock": 10, "herb": 5, "grass": 3},
		"animals": {"arctic_fox": 5, "elk": 4, "ice_wolf": 3},
		"ponds": [Vector2(144, 8)], "boss": "mammoth", "outpost": Vector2(129.5, 17),
	},
]

## The zone after the last one: not built yet. Its gate stands at the end of
## the last zone; crossing it ends the demo. When the zone is added to ZONES,
## move this gate into its "entry" and point NEXT_ZONE at the one after.
const NEXT_ZONE := {
	"id": "frozen_sea", "name": "the frozen sea",
	"unlock": {"level": 18, "boss": "mammoth"},
	"entry": {"kind": "pass", "name": "Sea pass", "position": Vector2(163.5, 25), "facing": -90},
}


## Zone i's data; NEXT_ZONE for the one after the last; {} beyond that.
static func zone(i: int) -> Dictionary:
	if i < ZONES.size():
		return ZONES[i]
	return NEXT_ZONE if i == ZONES.size() else {}

# --- Items -------------------------------------------------------------------

## Headings that group items, tools and recipes in the windows, in display order.
const CATEGORIES := {
	"weapons": "Weapons",
	"tools": "Tools",
	"clothing": "Clothing",
	"gear": "Gear",
	"food": "Food",
	"materials": "Materials",
	"animal": "Animal parts",
}

const ITEMS := {
	"wood": {"name": "Wood", "weight": 1.0, "category": "materials"},
	"stone": {"name": "Stone", "weight": 1.5, "category": "materials"},
	"fibre": {"name": "Fibre", "weight": 0.2, "category": "materials"},
	"rope": {"name": "Rope", "weight": 0.3, "category": "materials"},
	"leather": {"name": "Leather", "weight": 0.5, "category": "materials"},
	"thick_leather": {"name": "Thick leather", "weight": 0.7, "category": "materials"},
	"iron_ore": {"name": "Iron ore", "weight": 2.0, "category": "materials"},
	"iron_bar": {"name": "Iron bar", "weight": 1.5, "category": "materials"},
	"silver_ore": {"name": "Silver ore", "weight": 2.0, "category": "materials"},
	"silver_bar": {"name": "Silver bar", "weight": 1.5, "category": "materials"},
	"thick_fur": {"name": "Thick fur", "weight": 0.5, "category": "materials"},
	"berries": {"name": "Berries", "weight": 0.2, "food": 8.0, "category": "food"},
	"raw_meat": {"name": "Raw meat", "weight": 0.5, "food": 12.0, "category": "food"},
	"cooked_meat": {"name": "Cooked meat", "weight": 0.4, "food": 35.0, "category": "food"},
	"herbs": {"name": "Mountain herbs", "weight": 0.1, "food": 6.0, "heal": 30.0, "category": "food"},
	"hide": {"name": "Hide", "weight": 0.6, "category": "animal"},
	"fur": {"name": "Fur", "weight": 0.3, "category": "animal"},
	"antler": {"name": "Antler", "weight": 0.8, "category": "animal"},
	"tusk": {"name": "Boar tusk", "weight": 1.0, "category": "animal"},
	"bone": {"name": "Bone", "weight": 0.4, "category": "animal"},
	"horn": {"name": "Goat horn", "weight": 0.7, "category": "animal"},
	"wolf_pelt": {"name": "Wolf pelt", "weight": 0.6, "category": "animal"},
	"bear_pelt": {"name": "Bear pelt", "weight": 1.2, "category": "animal"},
	"claw": {"name": "Bear claw", "weight": 0.3, "category": "animal"},
	"ice_pelt": {"name": "Ice-wolf pelt", "weight": 0.7, "category": "animal"},
	"mammoth_pelt": {"name": "Mammoth pelt", "weight": 1.5, "category": "animal"},
	"mammoth_tusk": {"name": "Mammoth tusk", "weight": 2.0, "category": "animal"},
}

## Food eaten by the quick "Eat" button, best first.
const FOOD_ORDER := ["cooked_meat", "raw_meat", "berries"]

## Equipment: owned once, not carried as weight. Each piece fills a slot; the
## highest tier owned in a slot is the one in use (Game.equipped). Tier = the
## zone whose materials make it. "upgrades_from" is the piece the recipe
## consumes. Stats: damage/range (weapons), yield (items per hit), max_health,
## drain_mult (hunger/thirst), armor (share of damage blocked), speed_mult,
## carry_bonus (kg). "icon" is the vector icon in icons.gd.
const TOOLS := {
	"spear": {"name": "Wooden spear", "slot": "weapon", "tier": 1, "icon": "spear", "range": 1.8, "damage": 1, "category": "weapons"},
	"bone_spear": {"name": "Bone spear", "slot": "weapon", "tier": 2, "icon": "spear", "range": 2.0, "damage": 2, "upgrades_from": "spear", "category": "weapons"},
	"bow": {"name": "Hunting bow", "slot": "weapon", "tier": 2, "icon": "bow", "range": 5.5, "damage": 3, "category": "weapons"},
	"stone_axe": {"name": "Stone axe", "slot": "axe", "tier": 1, "icon": "axe", "yield": 2, "category": "tools"},
	"bone_axe": {"name": "Bone axe", "slot": "axe", "tier": 2, "icon": "axe", "yield": 3, "upgrades_from": "stone_axe", "category": "tools"},
	"stone_pick": {"name": "Stone pickaxe", "slot": "pick", "tier": 1, "icon": "pick", "yield": 2, "category": "tools"},
	"bone_pick": {"name": "Bone pickaxe", "slot": "pick", "tier": 2, "icon": "pick", "yield": 3, "upgrades_from": "stone_pick", "category": "tools"},
	"fur_hood": {"name": "Fur hood", "slot": "head", "tier": 1, "icon": "hood", "max_health": 25.0, "category": "clothing"},
	"tusk_helm": {"name": "Boar-tusk helm", "slot": "head", "tier": 2, "icon": "hood", "max_health": 50.0, "upgrades_from": "fur_hood", "category": "clothing"},
	"fur_tunic": {"name": "Fur tunic", "slot": "body", "tier": 1, "icon": "tunic", "drain_mult": 0.67, "category": "clothing"},
	"leather_armor": {"name": "Leather armor", "slot": "body", "tier": 2, "icon": "tunic", "drain_mult": 0.67, "armor": 0.5, "upgrades_from": "fur_tunic", "category": "clothing"},
	"fibre_wraps": {"name": "Fibre wraps", "slot": "feet", "tier": 1, "icon": "boots", "speed_mult": 1.15, "category": "clothing"},
	"leather_boots": {"name": "Leather boots", "slot": "feet", "tier": 2, "icon": "boots", "speed_mult": 1.3, "upgrades_from": "fibre_wraps", "category": "clothing"},
	"fibre_pouch": {"name": "Fibre pouch", "slot": "bag", "tier": 1, "icon": "bag", "carry_bonus": 10.0, "category": "gear"},
	"leather_bag": {"name": "Leather bag", "slot": "bag", "tier": 2, "icon": "bag", "carry_bonus": 20.0, "upgrades_from": "fibre_pouch", "category": "gear"},
	# Tier 3: iron and wolf pelts from the mountains.
	"iron_spear": {"name": "Iron spear", "slot": "weapon", "tier": 3, "icon": "spear", "range": 2.2, "damage": 4, "upgrades_from": "bone_spear", "category": "weapons"},
	"iron_bow": {"name": "Iron-tipped bow", "slot": "weapon", "tier": 3, "icon": "bow", "range": 6.0, "damage": 5, "upgrades_from": "bow", "category": "weapons"},
	"iron_axe": {"name": "Iron axe", "slot": "axe", "tier": 3, "icon": "axe", "yield": 4, "upgrades_from": "bone_axe", "category": "tools"},
	"iron_pick": {"name": "Iron pickaxe", "slot": "pick", "tier": 3, "icon": "pick", "yield": 4, "upgrades_from": "bone_pick", "category": "tools"},
	"iron_helm": {"name": "Iron helm", "slot": "head", "tier": 3, "icon": "hood", "max_health": 80.0, "upgrades_from": "tusk_helm", "category": "clothing"},
	"wolf_armor": {"name": "Wolf-pelt armor", "slot": "body", "tier": 3, "icon": "tunic", "drain_mult": 0.67, "armor": 0.7, "upgrades_from": "leather_armor", "category": "clothing"},
	"wolf_boots": {"name": "Wolf boots", "slot": "feet", "tier": 3, "icon": "boots", "speed_mult": 1.45, "upgrades_from": "leather_boots", "category": "clothing"},
	"hunters_pack": {"name": "Hunter's pack", "slot": "bag", "tier": 3, "icon": "bag", "carry_bonus": 35.0, "upgrades_from": "leather_bag", "category": "gear"},
	# Tier 4: silver and thick fur from the far north.
	"silver_spear": {"name": "Silver spear", "slot": "weapon", "tier": 4, "icon": "spear", "range": 2.4, "damage": 6, "upgrades_from": "iron_spear", "category": "weapons"},
	"silver_bow": {"name": "Silver bow", "slot": "weapon", "tier": 4, "icon": "bow", "range": 6.5, "damage": 8, "upgrades_from": "iron_bow", "category": "weapons"},
	"silver_axe": {"name": "Silver axe", "slot": "axe", "tier": 4, "icon": "axe", "yield": 5, "upgrades_from": "iron_axe", "category": "tools"},
	"silver_pick": {"name": "Silver pickaxe", "slot": "pick", "tier": 4, "icon": "pick", "yield": 5, "upgrades_from": "iron_pick", "category": "tools"},
	"silver_helm": {"name": "Silver helm", "slot": "head", "tier": 4, "icon": "hood", "max_health": 120.0, "upgrades_from": "iron_helm", "category": "clothing"},
	"mammoth_armor": {"name": "Mammoth-pelt armor", "slot": "body", "tier": 4, "icon": "tunic", "drain_mult": 0.6, "armor": 0.8, "upgrades_from": "wolf_armor", "category": "clothing"},
	"icewolf_boots": {"name": "Ice-wolf boots", "slot": "feet", "tier": 4, "icon": "boots", "speed_mult": 1.6, "upgrades_from": "wolf_boots", "category": "clothing"},
	"great_pack": {"name": "Great pack", "slot": "bag", "tier": 4, "icon": "bag", "carry_bonus": 50.0, "upgrades_from": "hunters_pack", "category": "gear"},
}

## Equipment slots in display order, with their labels.
const SLOTS := {"weapon": "Weapon", "axe": "Axe", "pick": "Pickaxe", "head": "Head", "body": "Body", "feet": "Feet", "bag": "Bag"}

# --- Gathering ---------------------------------------------------------------

## Each hit gives 1 item, or the "yield" of the tool equipped in "slot".
const RESOURCES := {
	"tree": {"name": "Tree", "item": "wood", "amount": 6, "slot": "axe", "energy": 2.0, "xp": 2, "respawn": 60.0},
	"rock": {"name": "Rock", "item": "stone", "amount": 5, "slot": "pick", "energy": 3.0, "xp": 2, "respawn": 75.0},
	"bush": {"name": "Berry bush", "item": "berries", "amount": 4, "slot": "", "energy": 1.0, "xp": 1, "respawn": 45.0},
	"grass": {"name": "Tall grass", "item": "fibre", "amount": 4, "slot": "", "energy": 1.0, "xp": 1, "respawn": 40.0},
	"iron_rock": {"name": "Iron rock", "item": "iron_ore", "amount": 4, "slot": "pick", "needs_tier": 2, "energy": 4.0, "xp": 3, "respawn": 90.0},
	"herb": {"name": "Mountain herb", "item": "herbs", "amount": 3, "slot": "", "energy": 1.0, "xp": 1, "respawn": 60.0},
	"silver_rock": {"name": "Silver rock", "item": "silver_ore", "amount": 4, "slot": "pick", "needs_tier": 3, "energy": 5.0, "xp": 4, "respawn": 100.0},
}

# --- Animals -----------------------------------------------------------------

## Every kill gives a little XP, food (raw meat) and fur. Hide and antler come
## only from deer in the east forest.

const ANIMALS := {
	"rabbit": {
		"name": "Rabbit", "hp": 1, "size": 0.25, "color": Color(0.86, 0.82, 0.72), "long_ears": true,
		"wander_speed": 1.0, "flee_speed": 3.75, "flee_radius": 3.75,
		"xp": 5, "drops": {"raw_meat": 1, "fur": 1}, "respawn": 40.0,
	},
	"squirrel": {
		"name": "Squirrel", "hp": 1, "size": 0.18, "color": Color(0.75, 0.42, 0.18),
		"wander_speed": 1.25, "flee_speed": 4.1, "flee_radius": 3.25,
		"xp": 4, "drops": {"raw_meat": 1, "fur": 1}, "respawn": 40.0,
	},
	"deer": {
		"name": "Deer", "hp": 3, "size": 0.45, "color": Color(0.6, 0.4, 0.22), "legs": true, "antlers": true,
		"wander_speed": 0.9, "flee_speed": 4.4, "flee_radius": 5.0,
		"xp": 25, "drops": {"raw_meat": 3, "fur": 2, "hide": 1, "antler": 1, "bone": 1}, "respawn": 60.0,
	},
	# Mountains. A wolf is "aggressive": it hunts the hunter inside flee_radius
	# (its aggro range), runs at flee_speed and bites every bite_every seconds.
	"snow_hare": {
		"name": "Snow hare", "hp": 1, "size": 0.26, "color": Color(0.95, 0.95, 0.97), "long_ears": true,
		"wander_speed": 1.0, "flee_speed": 3.9, "flee_radius": 3.75,
		"xp": 10, "drops": {"raw_meat": 1, "fur": 2}, "respawn": 40.0,
	},
	"goat": {
		"name": "Mountain goat", "hp": 3, "size": 0.42, "color": Color(0.85, 0.8, 0.7), "legs": true, "horns": true,
		"wander_speed": 0.9, "flee_speed": 4.3, "flee_radius": 4.5,
		"xp": 30, "drops": {"raw_meat": 2, "hide": 1, "horn": 1, "bone": 1}, "respawn": 60.0,
	},
	"wolf": {
		"name": "Wolf", "hp": 4, "size": 0.4, "color": Color(0.45, 0.45, 0.5), "legs": true, "pointed_ears": true,
		"wander_speed": 1.1, "flee_speed": 4.6, "flee_radius": 6.0,
		"aggressive": true, "bite": 12.0, "bite_every": 1.6, "bite_text": "The wolf bites you!",
		"xp": 40, "drops": {"raw_meat": 2, "wolf_pelt": 1, "bone": 1}, "respawn": 75.0,
	},
	# Far north.
	"arctic_fox": {
		"name": "Arctic fox", "hp": 2, "size": 0.3, "color": Color(0.96, 0.96, 0.98), "legs": true, "pointed_ears": true,
		"wander_speed": 1.2, "flee_speed": 4.5, "flee_radius": 4.0,
		"xp": 15, "drops": {"raw_meat": 1, "fur": 3}, "respawn": 45.0,
	},
	"elk": {
		"name": "Elk", "hp": 5, "size": 0.55, "color": Color(0.45, 0.33, 0.22), "legs": true, "antlers": true,
		"wander_speed": 0.9, "flee_speed": 4.2, "flee_radius": 5.0,
		"xp": 45, "drops": {"raw_meat": 4, "hide": 2, "antler": 2, "bone": 2}, "respawn": 70.0,
	},
	"ice_wolf": {
		"name": "Ice wolf", "hp": 6, "size": 0.45, "color": Color(0.8, 0.85, 0.92), "legs": true, "pointed_ears": true,
		"wander_speed": 1.1, "flee_speed": 4.8, "flee_radius": 6.5,
		"aggressive": true, "bite": 18.0, "bite_every": 1.5, "bite_text": "The ice wolf bites you!",
		"xp": 60, "drops": {"raw_meat": 2, "ice_pelt": 1, "bone": 2}, "respawn": 80.0,
	},
}

## Bosses, one per zone (ZONES[i].boss names the id). A boss lives in its
## lair, charges instead of fleeing; a charge that hits hurts the hunter and
## knocks them back. After a charge it is dizzy for a moment.
const BOSSES := {
	"boar": {
		"name": "Great Boar", "look": "boar", "hit_text": "The boar rams you!",
		"hp": 24, "size": 0.9, "color": Color(0.32, 0.22, 0.16),
		"lair": Vector2(76, 9), "lair_radius": 6.0,
		"walk_speed": 1.6, "charge_speed": 9.0, "aggro_radius": 8.0,
		"windup": 0.9, "charge_time": 0.8, "dizzy": 2.2, "dizzy_damage_mult": 2,
		"hit_damage": 30.0, "knockback": 4.0, "regen_per_sec": 0.5,
		"xp": 150, "drops": {"raw_meat": 6, "hide": 3, "tusk": 2, "bone": 3},
	},
	"bear": {
		"name": "Great Bear", "look": "bear", "hit_text": "The bear swipes you!",
		"hp": 45, "size": 1.1, "color": Color(0.3, 0.2, 0.14),
		"lair": Vector2(116, 9), "lair_radius": 6.5,
		"walk_speed": 1.5, "charge_speed": 7.5, "aggro_radius": 8.5,
		"windup": 1.0, "charge_time": 0.9, "dizzy": 2.0, "dizzy_damage_mult": 2,
		"hit_damage": 40.0, "knockback": 4.5, "regen_per_sec": 0.6,
		"xp": 300, "drops": {"raw_meat": 8, "bear_pelt": 2, "claw": 2, "bone": 4},
	},
	"mammoth": {
		"name": "Great Mammoth", "look": "mammoth", "hit_text": "The mammoth tramples you!",
		"hp": 80, "size": 1.4, "color": Color(0.42, 0.3, 0.2),
		"lair": Vector2(156, 9), "lair_radius": 7.0,
		"walk_speed": 1.3, "charge_speed": 7.0, "aggro_radius": 9.0,
		"windup": 1.2, "charge_time": 1.0, "dizzy": 2.2, "dizzy_damage_mult": 2,
		"hit_damage": 50.0, "knockback": 5.0, "regen_per_sec": 0.8,
		"xp": 600, "drops": {"raw_meat": 12, "mammoth_pelt": 2, "mammoth_tusk": 2, "bone": 6},
	},
}

## Animals run for this long, then stop to catch their breath.
const FLEE_STAMINA := 3.0
const FLEE_REST := 1.2

# --- Crafting ----------------------------------------------------------------

## "station" is the structure that makes it and "tier" the station tier needed.
## A recipe gives either a tool (equipment) or items. A cost entry can be a
## piece of equipment: the upgrade consumes it.
const RECIPES := {
	"spear": {"tool": "spear", "tier": 1, "station": "crafting", "time": 10.0, "cost": {"wood": 3, "stone": 1}},
	"stone_axe": {"tool": "stone_axe", "tier": 1, "station": "crafting", "time": 15.0, "cost": {"wood": 2, "stone": 2}},
	"stone_pick": {"tool": "stone_pick", "tier": 1, "station": "crafting", "time": 15.0, "cost": {"wood": 2, "stone": 3}},
	"cooked_meat": {"item": "cooked_meat", "count": 1, "tier": 1, "station": "crafting", "time": 5.0, "cost": {"raw_meat": 1, "wood": 1}},
	"rope": {"item": "rope", "count": 1, "tier": 1, "station": "crafting", "time": 8.0, "cost": {"fibre": 3}},
	"fur_hood": {"tool": "fur_hood", "tier": 1, "station": "tailor", "time": 15.0, "cost": {"fur": 4}},
	"fur_tunic": {"tool": "fur_tunic", "tier": 1, "station": "tailor", "time": 25.0, "cost": {"fur": 6, "rope": 1}},
	"fibre_wraps": {"tool": "fibre_wraps", "tier": 1, "station": "tailor", "time": 12.0, "cost": {"fibre": 6}},
	"fibre_pouch": {"tool": "fibre_pouch", "tier": 1, "station": "tailor", "time": 20.0, "cost": {"fibre": 8, "rope": 1}},
	"leather": {"item": "leather", "count": 1, "tier": 1, "station": "tanning", "time": 20.0, "cost": {"hide": 1, "fibre": 1}},
	"bone_spear": {"tool": "bone_spear", "tier": 2, "station": "crafting", "time": 60.0, "cost": {"spear": 1, "bone": 2, "rope": 1}},
	"bow": {"tool": "bow", "tier": 2, "station": "crafting", "time": 90.0, "cost": {"wood": 6, "leather": 2, "rope": 2}},
	"bone_axe": {"tool": "bone_axe", "tier": 2, "station": "crafting", "time": 60.0, "cost": {"stone_axe": 1, "bone": 3, "rope": 1}},
	"bone_pick": {"tool": "bone_pick", "tier": 2, "station": "crafting", "time": 60.0, "cost": {"stone_pick": 1, "bone": 3, "rope": 1}},
	"tusk_helm": {"tool": "tusk_helm", "tier": 2, "station": "tailor", "time": 90.0, "cost": {"fur_hood": 1, "tusk": 1, "leather": 2}},
	"leather_armor": {"tool": "leather_armor", "tier": 2, "station": "tailor", "time": 120.0, "cost": {"fur_tunic": 1, "leather": 4, "rope": 2}},
	"leather_boots": {"tool": "leather_boots", "tier": 2, "station": "tailor", "time": 90.0, "cost": {"fibre_wraps": 1, "leather": 3}},
	"leather_bag": {"tool": "leather_bag", "tier": 2, "station": "tailor", "time": 90.0, "cost": {"fibre_pouch": 1, "leather": 4}},
	# Tier 3 (mountains): iron bars from the forge, thick leather from wolf pelts.
	"iron_bar": {"item": "iron_bar", "count": 1, "tier": 1, "station": "forge", "time": 30.0, "cost": {"iron_ore": 2, "wood": 2}},
	"thick_leather": {"item": "thick_leather", "count": 1, "tier": 3, "station": "tanning", "time": 40.0, "cost": {"wolf_pelt": 1, "leather": 1}},
	"iron_spear": {"tool": "iron_spear", "tier": 3, "station": "crafting", "time": 150.0, "cost": {"bone_spear": 1, "iron_bar": 2, "rope": 1}},
	"iron_bow": {"tool": "iron_bow", "tier": 3, "station": "crafting", "time": 180.0, "cost": {"bow": 1, "iron_bar": 1, "thick_leather": 1}},
	"iron_axe": {"tool": "iron_axe", "tier": 3, "station": "crafting", "time": 150.0, "cost": {"bone_axe": 1, "iron_bar": 2}},
	"iron_pick": {"tool": "iron_pick", "tier": 3, "station": "crafting", "time": 150.0, "cost": {"bone_pick": 1, "iron_bar": 2}},
	"iron_helm": {"tool": "iron_helm", "tier": 3, "station": "tailor", "time": 180.0, "cost": {"tusk_helm": 1, "iron_bar": 2, "thick_leather": 1}},
	"wolf_armor": {"tool": "wolf_armor", "tier": 3, "station": "tailor", "time": 240.0, "cost": {"leather_armor": 1, "thick_leather": 4, "rope": 2}},
	"wolf_boots": {"tool": "wolf_boots", "tier": 3, "station": "tailor", "time": 180.0, "cost": {"leather_boots": 1, "thick_leather": 2}},
	"hunters_pack": {"tool": "hunters_pack", "tier": 3, "station": "tailor", "time": 180.0, "cost": {"leather_bag": 1, "thick_leather": 3, "rope": 2}},
	# Tier 4 (far north): silver bars from the forge tier 2, thick fur from the rack tier 4.
	"silver_bar": {"item": "silver_bar", "count": 1, "tier": 2, "station": "forge", "time": 45.0, "cost": {"silver_ore": 2, "wood": 2}},
	"thick_fur": {"item": "thick_fur", "count": 1, "tier": 4, "station": "tanning", "time": 50.0, "cost": {"fur": 4, "ice_pelt": 1}},
	"silver_spear": {"tool": "silver_spear", "tier": 4, "station": "crafting", "time": 240.0, "cost": {"iron_spear": 1, "silver_bar": 2, "rope": 1}},
	"silver_bow": {"tool": "silver_bow", "tier": 4, "station": "crafting", "time": 300.0, "cost": {"iron_bow": 1, "silver_bar": 2, "thick_fur": 1}},
	"silver_axe": {"tool": "silver_axe", "tier": 4, "station": "crafting", "time": 240.0, "cost": {"iron_axe": 1, "silver_bar": 3}},
	"silver_pick": {"tool": "silver_pick", "tier": 4, "station": "crafting", "time": 240.0, "cost": {"iron_pick": 1, "silver_bar": 3}},
	"silver_helm": {"tool": "silver_helm", "tier": 4, "station": "tailor", "time": 300.0, "cost": {"iron_helm": 1, "silver_bar": 2, "thick_fur": 1}},
	"mammoth_armor": {"tool": "mammoth_armor", "tier": 4, "station": "tailor", "time": 420.0, "cost": {"wolf_armor": 1, "mammoth_pelt": 2, "thick_fur": 3}},
	"icewolf_boots": {"tool": "icewolf_boots", "tier": 4, "station": "tailor", "time": 300.0, "cost": {"wolf_boots": 1, "ice_pelt": 2, "thick_fur": 2}},
	"great_pack": {"tool": "great_pack", "tier": 4, "station": "tailor", "time": 300.0, "cost": {"hunters_pack": 1, "thick_fur": 3, "rope": 3}},
}

## Crafting a tool or a piece of gear is worth XP; materials and food give
## one point apiece, so queueing "Max" rope is not a way to level up.
const CRAFT_XP_TOOL := 10
const CRAFT_XP_ITEM := 1
## Jobs a station can hold at once: one running and the rest waiting.
const QUEUE_SLOTS := 2

# --- Camp structures ---------------------------------------------------------

## tiers[0] is tier 1. "level" is the hunter level needed to build that tier;
## "house_tier" the house tier needed (the house is the master building).
## "speed" scales craft times at that station (0.5 = twice as fast).
const STRUCTURES := {
	"crafting": {"name": "Crafting place", "tiers": [
		{"cost": {"wood": 5}, "time": 10.0, "level": 1, "house_tier": 0},
		{"cost": {"wood": 10, "stone": 6, "rope": 2}, "time": 120.0, "level": 2, "house_tier": 1},
		{"cost": {"wood": 20, "stone": 15, "leather": 2, "antler": 2}, "time": 300.0, "level": 4, "house_tier": 2},
		{"cost": {"wood": 30, "stone": 25, "iron_bar": 4, "thick_leather": 2}, "time": 480.0, "level": 13, "house_tier": 3},
	]},
	"tailor": {"name": "Tailor's tent", "tiers": [ # clothing and bags; same gates as the crafting place, cheaper
		{"cost": {"wood": 6, "fibre": 3}, "time": 10.0, "level": 1, "house_tier": 0},
		{"cost": {"wood": 8, "rope": 2, "leather": 2}, "time": 100.0, "level": 2, "house_tier": 1},
		{"cost": {"wood": 15, "stone": 8, "leather": 4, "thick_leather": 1}, "time": 240.0, "level": 4, "house_tier": 2},
		{"cost": {"wood": 20, "stone": 12, "thick_leather": 3, "silver_bar": 1}, "time": 400.0, "level": 13, "house_tier": 3},
	]},
	"storage": {"name": "Storage", "tiers": [
		{"cost": {"wood": 8}, "time": 15.0, "level": 1, "house_tier": 0, "capacity": 50.0},
		{"cost": {"wood": 15, "stone": 8, "rope": 2}, "time": 120.0, "level": 2, "house_tier": 1, "capacity": 150.0},
		{"cost": {"wood": 25, "stone": 20, "hide": 4}, "time": 300.0, "level": 4, "house_tier": 2, "capacity": 400.0},
	]},
	"house": {"name": "House", "tiers": [
		{"cost": {"wood": 12, "stone": 4}, "time": 20.0, "level": 1, "house_tier": 0, "sleep_time": 40.0, "max_energy": 100.0},
		{"cost": {"wood": 20, "stone": 12, "leather": 3}, "time": 180.0, "level": 3, "house_tier": 0, "sleep_time": 30.0, "max_energy": 120.0},
		{"cost": {"wood": 30, "stone": 25, "leather": 6}, "time": 360.0, "level": 5, "house_tier": 0, "sleep_time": 20.0, "max_energy": 150.0},
	]},
	"tanning": {"name": "Tanning rack", "tiers": [
		{"cost": {"wood": 6, "fibre": 6}, "time": 20.0, "level": 2, "house_tier": 0, "speed": 1.0},
		{"cost": {"wood": 10, "rope": 2, "hide": 2}, "time": 120.0, "level": 4, "house_tier": 1, "speed": 0.5},
		{"cost": {"wood": 14, "rope": 4, "leather": 4}, "time": 300.0, "level": 8, "house_tier": 2, "speed": 0.4},
		{"cost": {"wood": 20, "rope": 6, "thick_leather": 2}, "time": 420.0, "level": 13, "house_tier": 3, "speed": 0.3},
	]},
	"forge": {"name": "Forge", "tiers": [
		{"cost": {"stone": 20, "wood": 10, "rope": 4}, "time": 300.0, "level": 8, "house_tier": 2},
		{"cost": {"stone": 30, "iron_bar": 4, "rope": 4}, "time": 420.0, "level": 13, "house_tier": 3},
	]},
}

const BUILD_XP_PER_TIER := 15

# --- Quests ------------------------------------------------------------------

## Quest lines, one per zone, played in order (the flat list is quests()).
## Types: "gather" (item from nodes), "hunt" (animal kills), "collect" (an
## animal's drop, target "animal:item"), "craft" (recipe), "build" (structure,
## optional "tier"; also counts one built earlier), "level" (reach a level),
## "boss" (defeat a boss id), "travel" (set foot in a zone id).
## XP is tuned so a zone's line, its boss and the gathering they force land
## the hunter on the next zone's level gate around the boss fight.
const QUEST_LINES := {
	"meadow": [
		{"text": "Gather 5 wood", "type": "gather", "target": "wood", "count": 5, "xp": 15},
		{"text": "Build the crafting place", "type": "build", "target": "crafting", "count": 1, "xp": 20},
		{"text": "Craft a wooden spear", "type": "craft", "target": "spear", "count": 1, "xp": 20},
		{"text": "Harvest 2 rabbit fur", "type": "collect", "target": "rabbit:fur", "count": 2, "xp": 30},
		{"text": "Build the storage", "type": "build", "target": "storage", "count": 1, "xp": 25},
		{"text": "Gather 6 fibre from tall grass", "type": "gather", "target": "fibre", "count": 6, "xp": 15},
		{"text": "Build the tailor's tent", "type": "build", "target": "tailor", "count": 1, "xp": 20},
		{"text": "Craft fibre wraps", "type": "craft", "target": "fibre_wraps", "count": 1, "xp": 25},
		{"text": "Build the tanning rack", "type": "build", "target": "tanning", "count": 1, "xp": 25},
		{"text": "Tan 1 leather", "type": "craft", "target": "leather", "count": 1, "xp": 25},
		{"text": "Harvest 1 squirrel fur", "type": "collect", "target": "squirrel:fur", "count": 1, "xp": 20},
		{"text": "Harvest 10 rabbit fur", "type": "collect", "target": "rabbit:fur", "count": 10, "xp": 40},
		{"text": "Cook 2 meat", "type": "craft", "target": "cooked_meat", "count": 2, "xp": 20},
		{"text": "Craft a fur tunic", "type": "craft", "target": "fur_tunic", "count": 1, "xp": 40},
	],
	"east_forest": [
		{"text": "Enter the east forest", "type": "travel", "target": "east_forest", "count": 1, "xp": 30},
		{"text": "Build the house", "type": "build", "target": "house", "count": 1, "xp": 60},
		{"text": "Hunt 3 deer", "type": "hunt", "target": "deer", "count": 3, "xp": 90},
		{"text": "Harvest 1 deer antler", "type": "collect", "target": "deer:antler", "count": 1, "xp": 60},
		{"text": "Upgrade the crafting place to tier 2", "type": "build", "target": "crafting", "tier": 2, "count": 1, "xp": 100},
		{"text": "Craft a bone pickaxe", "type": "craft", "target": "bone_pick", "count": 1, "xp": 120},
		{"text": "Upgrade the tailor's tent to tier 2", "type": "build", "target": "tailor", "tier": 2, "count": 1, "xp": 100},
		{"text": "Craft leather boots", "type": "craft", "target": "leather_boots", "count": 1, "xp": 120},
		{"text": "Craft leather armor", "type": "craft", "target": "leather_armor", "count": 1, "xp": 150},
		{"text": "Reach level 7", "type": "level", "target": "", "count": 7, "xp": 0},
		{"text": "Defeat the Great Boar", "type": "boss", "target": "boar", "count": 1, "xp": 300},
		{"text": "Upgrade the house to tier 2", "type": "build", "target": "house", "tier": 2, "count": 1, "xp": 150},
	],
	"mountains": [
		{"text": "Cross the mountain pass", "type": "travel", "target": "mountains", "count": 1, "xp": 80},
		{"text": "Mine 4 iron ore (bone pickaxe)", "type": "gather", "target": "iron_ore", "count": 4, "xp": 80},
		{"text": "Hunt 3 wolves", "type": "hunt", "target": "wolf", "count": 3, "xp": 150},
		{"text": "Build the forge", "type": "build", "target": "forge", "count": 1, "xp": 150},
		{"text": "Smelt 4 iron bars", "type": "craft", "target": "iron_bar", "count": 4, "xp": 120},
		{"text": "Upgrade the crafting place to tier 3", "type": "build", "target": "crafting", "tier": 3, "count": 1, "xp": 200},
		{"text": "Tan 2 thick leather", "type": "craft", "target": "thick_leather", "count": 2, "xp": 120},
		{"text": "Upgrade the tailor's tent to tier 3", "type": "build", "target": "tailor", "tier": 3, "count": 1, "xp": 150},
		{"text": "Craft wolf boots or wolf-pelt armor", "type": "craft", "target": "wolf_gear", "count": 1, "xp": 150},
		{"text": "Craft an iron axe or pickaxe", "type": "craft", "target": "iron_tool", "count": 1, "xp": 200},
		{"text": "Reach level 12", "type": "level", "target": "", "count": 12, "xp": 0},
		{"text": "Defeat the Great Bear", "type": "boss", "target": "bear", "count": 1, "xp": 500},
		{"text": "Take the northern pass", "type": "travel", "target": "far_north", "count": 1, "xp": 100},
	],
	"far_north": [
		{"text": "Hunt 3 arctic foxes", "type": "hunt", "target": "arctic_fox", "count": 3, "xp": 150},
		{"text": "Mine 4 silver ore (iron pickaxe)", "type": "gather", "target": "silver_ore", "count": 4, "xp": 150},
		{"text": "Upgrade the forge to tier 2", "type": "build", "target": "forge", "tier": 2, "count": 1, "xp": 250},
		{"text": "Smelt 4 silver bars", "type": "craft", "target": "silver_bar", "count": 4, "xp": 200},
		{"text": "Hunt 2 ice wolves", "type": "hunt", "target": "ice_wolf", "count": 2, "xp": 250},
		{"text": "Upgrade the crafting place to tier 4", "type": "build", "target": "crafting", "tier": 4, "count": 1, "xp": 300},
		{"text": "Craft a silver axe or pickaxe", "type": "craft", "target": "silver_tool", "count": 1, "xp": 300},
		{"text": "Upgrade the tailor's tent to tier 4", "type": "build", "target": "tailor", "tier": 4, "count": 1, "xp": 250},
		{"text": "Reach level 16", "type": "level", "target": "", "count": 16, "xp": 0},
		{"text": "Defeat the Great Mammoth", "type": "boss", "target": "mammoth", "count": 1, "xp": 900},
		{"text": "Take the sea pass", "type": "travel", "target": "frozen_sea", "count": 1, "xp": 0},
	],
}

## Quest targets that stand for several ids ("craft an iron axe or pickaxe").
const QUEST_GROUPS := {"iron_tool": ["iron_axe", "iron_pick"], "silver_tool": ["silver_axe", "silver_pick"],
	"wolf_gear": ["wolf_boots", "wolf_armor"]}

static var _quests_flat: Array = []


## Every quest in zone order, as one list; Game.quest_index indexes it.
static func quests() -> Array:
	if _quests_flat.is_empty():
		for z in ZONES:
			for q in QUEST_LINES.get(z["id"], []):
				var copy: Dictionary = q.duplicate()
				copy["zone"] = z["id"]
				_quests_flat.append(copy)
	return _quests_flat

# --- Shop packs (placeholder purchases) ---------------------------------------

## Pack items are delivered to the camp storage.
const PACKS := {
	"starter": {
		"name": "Starter pack", "price": "€1.99",
		"items": {"wood": 20, "stone": 10}, "energy": 50.0, "xp_boost_minutes": 30,
	},
	"hunter": {
		"name": "Hunter pack", "price": "€4.99",
		"items": {"raw_meat": 10, "fur": 10}, "tools": ["spear"], "xp_boost_minutes": 120,
	},
}

const XP_BOOST_MULT := 2.0


func item_name(id: String) -> String:
	if ITEMS.has(id):
		return ITEMS[id]["name"]
	if TOOLS.has(id):
		return TOOLS[id]["name"]
	return id


func item_weight(id: String) -> float:
	return ITEMS[id]["weight"] if ITEMS.has(id) else 0.0


func item_category(id: String) -> String:
	if ITEMS.has(id):
		return ITEMS[id]["category"]
	return TOOLS[id]["category"]


func recipe_category(id: String) -> String:
	var r: Dictionary = RECIPES[id]
	return item_category(r["tool"] if r.has("tool") else r["item"])


## Groups ids by category: [[category, [ids...]], ...] in CATEGORIES order,
## skipping empty categories. category_of maps an id to its category.
func by_category(ids: Array, category_of: Callable) -> Array:
	var groups := []
	for category in CATEGORIES:
		var members := ids.filter(func(id: String) -> bool: return category_of.call(id) == category)
		if not members.is_empty():
			groups.append([category, members])
	return groups


func recipe_name(id: String) -> String:
	var r: Dictionary = RECIPES[id]
	return item_name(r["tool"] if r.has("tool") else r["item"])


## Name of the tier-N piece for a slot, e.g. ("pick", 2) -> "Bone pickaxe".
static func tool_of_tier(slot: String, tier: int) -> String:
	for id in TOOLS:
		if TOOLS[id].get("slot", "") == slot and TOOLS[id].get("tier", 0) == tier:
			return TOOLS[id]["name"]
	return ""


## Icon name for a piece of equipment ("" for none).
static func tool_icon(id: String) -> String:
	return TOOLS[id]["icon"] if TOOLS.has(id) else ""


## Structures that have recipes.
static func recipe_stations() -> Array:
	var out := []
	for id in RECIPES:
		if not out.has(RECIPES[id]["station"]):
			out.append(RECIPES[id]["station"])
	return out


## The recipe that upgrades a piece of equipment, or "".
static func upgrade_of(tool_id: String) -> String:
	for id in RECIPES:
		var r: Dictionary = RECIPES[id]
		if r.has("tool") and TOOLS[r["tool"]].get("upgrades_from", "") == tool_id:
			return id
	return ""


## One line on what a piece of equipment does.
static func tool_effect(id: String) -> String:
	var t: Dictionary = TOOLS[id]
	var parts := []
	if t.has("damage"):
		parts.append("Damage %d · reach %.1f m" % [t["damage"], t["range"]])
	if t.has("yield"):
		parts.append("%d %s per hit" % [t["yield"], "wood" if t["slot"] == "axe" else "stone"])
	if t.has("max_health"):
		parts.append("+%d max health" % t["max_health"])
	if t.has("drain_mult"):
		parts.append("Hunger and thirst %d%% slower" % roundi((1.0 - t["drain_mult"]) * 100))
	if t.has("armor"):
		parts.append("Blocks %d%% of damage" % roundi(t["armor"] * 100))
	if t.has("speed_mult"):
		parts.append("+%d%% speed" % roundi((t["speed_mult"] - 1.0) * 100))
	if t.has("carry_bonus"):
		parts.append("+%d kg carry" % t["carry_bonus"])
	return " · ".join(parts)


## Name of the first zone an animal lives in, e.g. "the east forest".
static func animal_zone(kind: String) -> String:
	for z in ZONES:
		if z["animals"].has(kind):
			return z["name"]
	return ""


## Lower-case plural of a creature or resource name: "rabbits", "deer", "berry bushes".
static func plural(name: String) -> String:
	var n := name.to_lower()
	if n.ends_with("deer") or n.ends_with("sheep"):
		return n
	if n.ends_with("y") and not n.ends_with("ey"):
		return n.left(-1) + "ies"
	if n.ends_with("s") or n.ends_with("sh") or n.ends_with("ch") or n.ends_with("x"):
		return n + "es"
	return n + "s"


## Where an item comes from, for the "where to find" toast:
## "Fur: rabbits, squirrels (zone 1), deer (east forest)".
func sources(item: String) -> String:
	var parts := []
	for id in RESOURCES:
		var r: Dictionary = RESOURCES[id]
		if r["item"] == item:
			parts.append("%s%s" % [plural(r["name"]), " (more per hit with a%s)" % ("n axe" if r["slot"] == "axe" else " pickaxe") if r["slot"] != "" else ""])
	var by_zone := {}
	for id in ANIMALS:
		var a: Dictionary = ANIMALS[id]
		if a["drops"].has(item):
			var where := animal_zone(id)
			if not by_zone.has(where):
				by_zone[where] = []
			by_zone[where].append(plural(a["name"]))
	for where in by_zone:
		parts.append(", ".join(by_zone[where]) + (" (%s)" % where if where != "" else ""))
	for id in BOSSES:
		if BOSSES[id]["drops"].has(item):
			parts.append("the %s" % BOSSES[id]["name"])
	for id in RECIPES:
		var r: Dictionary = RECIPES[id]
		if r.get("item", "") == item or r.get("tool", "") == item:
			parts.append("made at the %s" % STRUCTURES[r["station"]]["name"].to_lower())
	if parts.is_empty():
		return "%s: no known source yet." % item_name(item)
	return "%s: %s." % [item_name(item), ", ".join(parts)]


func cost_text(cost: Dictionary) -> String:
	var parts := []
	for id in cost:
		parts.append("%s ×%d" % [item_name(id), cost[id]])
	return ", ".join(parts)


## XP for one craft job of the recipe (multiply by the count for items).
static func craft_xp(recipe: Dictionary) -> int:
	return CRAFT_XP_TOOL if recipe.has("tool") else CRAFT_XP_ITEM
