extends Node
## Static game data and balance values. Tune numbers here; the rest of the
## code reads from this file instead of hard-coding them.

# --- Player and survival -----------------------------------------------------
# Distances are in metres (1 unit = 1 m), speeds in metres per second.

const PLAYER_SPEED := 5.0 # metres per second
const BASE_CARRY := 20.0 # kg
const START_ENERGY := 100.0
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
const LEVEL_XP := [0, 50, 170, 390, 700, 1100, 1600, 2200, 2900, 3700]
const ZONE2_LEVEL := 3

# --- Items -------------------------------------------------------------------

const ITEMS := {
	"wood": {"name": "Wood", "weight": 1.0},
	"stone": {"name": "Stone", "weight": 1.5},
	"berries": {"name": "Berries", "weight": 0.2, "food": 8.0},
	"raw_meat": {"name": "Raw meat", "weight": 0.5, "food": 12.0},
	"cooked_meat": {"name": "Cooked meat", "weight": 0.4, "food": 35.0},
	"hide": {"name": "Hide", "weight": 0.6},
	"fur": {"name": "Fur", "weight": 0.3},
	"antler": {"name": "Antler", "weight": 0.8},
	"tusk": {"name": "Boar tusk", "weight": 1.0},
}

## Food eaten by the quick "Eat" button, best first.
const FOOD_ORDER := ["cooked_meat", "raw_meat", "berries"]

## Tools are owned once, not carried as weight.
const TOOLS := {
	"spear": {"name": "Wooden spear", "range": 1.8, "damage": 1},
	"bow": {"name": "Hunting bow", "range": 5.5, "damage": 2},
	"stone_axe": {"name": "Stone axe"},
	"stone_pick": {"name": "Stone pickaxe"},
	"leather_bag": {"name": "Leather bag", "carry_bonus": 15.0},
}

# --- Gathering ---------------------------------------------------------------

## Each hit gives 1 item, or 2 with the matching tool.
const RESOURCES := {
	"tree": {"name": "Tree", "item": "wood", "amount": 6, "tool": "stone_axe", "energy": 2.0, "xp": 2, "respawn": 60.0},
	"rock": {"name": "Rock", "item": "stone", "amount": 5, "tool": "stone_pick", "energy": 3.0, "xp": 2, "respawn": 75.0},
	"bush": {"name": "Berry bush", "item": "berries", "amount": 4, "tool": "", "energy": 1.0, "xp": 1, "respawn": 45.0},
}

# --- Animals -----------------------------------------------------------------

## Every kill gives a little XP, food (raw meat) and fur. Hide and antler come
## only from deer in the east forest.

const ANIMALS := {
	"rabbit": {
		"name": "Rabbit", "hp": 1, "size": 0.25, "color": Color(0.86, 0.82, 0.72),
		"wander_speed": 1.0, "flee_speed": 3.75, "flee_radius": 3.75,
		"xp": 5, "drops": {"raw_meat": 1, "fur": 1}, "respawn": 40.0,
	},
	"squirrel": {
		"name": "Squirrel", "hp": 1, "size": 0.18, "color": Color(0.75, 0.42, 0.18),
		"wander_speed": 1.25, "flee_speed": 4.1, "flee_radius": 3.25,
		"xp": 4, "drops": {"raw_meat": 1, "fur": 1}, "respawn": 40.0,
	},
	"deer": {
		"name": "Deer", "hp": 3, "size": 0.45, "color": Color(0.6, 0.4, 0.22),
		"wander_speed": 0.9, "flee_speed": 4.4, "flee_radius": 5.0,
		"xp": 12, "drops": {"raw_meat": 3, "fur": 2, "hide": 1, "antler": 1}, "respawn": 60.0,
	},
}

## The boss of the demo: the Great Boar in its lair at the far end of the east
## forest. It charges instead of fleeing; a charge that hits costs the hunter
## energy and knocks them back. After a charge it is dizzy for a moment.
const BOSS := {
	"name": "Great Boar", "hp": 12, "size": 0.9, "color": Color(0.32, 0.22, 0.16),
	"lair": Vector2(76, 9), "lair_radius": 6.0,
	"walk_speed": 1.6, "charge_speed": 9.0, "aggro_radius": 8.0,
	"windup": 0.9, "charge_time": 0.8, "dizzy": 2.2, "dizzy_damage_mult": 2,
	"hit_energy": 15.0, "knockback": 4.0, "regen_per_sec": 0.5,
	"xp": 150, "drops": {"raw_meat": 6, "hide": 3, "tusk": 2},
}

## The mountain pass at the end of the east forest. Crossing it ends the demo.
const NEXT_AREA := {"name": "Mountain pass", "level": 5, "position": Vector2(83.5, 25)}

## Animals run for this long, then stop to catch their breath.
const FLEE_STAMINA := 3.0
const FLEE_REST := 1.2

# --- Crafting ----------------------------------------------------------------

## "tier" is the crafting place tier needed. A recipe gives either a tool or items.
const RECIPES := {
	"spear": {"tool": "spear", "tier": 1, "time": 10.0, "cost": {"wood": 3, "stone": 1}},
	"stone_axe": {"tool": "stone_axe", "tier": 1, "time": 15.0, "cost": {"wood": 2, "stone": 2}},
	"stone_pick": {"tool": "stone_pick", "tier": 1, "time": 15.0, "cost": {"wood": 2, "stone": 3}},
	"cooked_meat": {"item": "cooked_meat", "count": 1, "tier": 1, "time": 5.0, "cost": {"raw_meat": 1, "wood": 1}},
	"leather_bag": {"tool": "leather_bag", "tier": 2, "time": 30.0, "cost": {"fur": 5}},
	"bow": {"tool": "bow", "tier": 2, "time": 40.0, "cost": {"wood": 6, "fur": 4}},
}

const CRAFT_XP := 5

# --- Camp structures ---------------------------------------------------------

## tiers[0] is tier 1. "level" is the hunter level needed to build that tier.
const STRUCTURES := {
	"crafting": {"name": "Crafting place", "tiers": [
		{"cost": {"wood": 5}, "time": 10.0, "level": 1},
		{"cost": {"wood": 10, "stone": 6, "fur": 2}, "time": 30.0, "level": 2},
		{"cost": {"wood": 20, "stone": 15, "antler": 2}, "time": 60.0, "level": 4},
	]},
	"storage": {"name": "Storage", "tiers": [
		{"cost": {"wood": 8}, "time": 15.0, "level": 1, "capacity": 50.0},
		{"cost": {"wood": 15, "stone": 8}, "time": 30.0, "level": 2, "capacity": 150.0},
		{"cost": {"wood": 25, "stone": 20, "hide": 4}, "time": 60.0, "level": 4, "capacity": 400.0},
	]},
	"house": {"name": "House", "tiers": [
		{"cost": {"wood": 12, "stone": 4}, "time": 20.0, "level": 1, "sleep_time": 40.0, "max_energy": 100.0},
		{"cost": {"wood": 20, "stone": 12, "fur": 4}, "time": 45.0, "level": 3, "sleep_time": 30.0, "max_energy": 120.0},
		{"cost": {"wood": 30, "stone": 25, "fur": 6}, "time": 90.0, "level": 5, "sleep_time": 20.0, "max_energy": 150.0},
	]},
}

const BUILD_XP_PER_TIER := 15

# --- Quests ------------------------------------------------------------------

## Done in order. Types: "gather" (item from trees/rocks/bushes), "hunt" (animal
## kills), "collect" (an animal's drop, target "animal:item"), "craft" (recipe),
## "build" (structure; also counts one built earlier), "level" (reach a level),
## "boss" (defeat the Great Boar), "travel" (cross the mountain pass).
const QUESTS := [
	{"text": "Gather 5 wood", "type": "gather", "target": "wood", "count": 5, "xp": 15},
	{"text": "Build the crafting place", "type": "build", "target": "crafting", "count": 1, "xp": 20},
	{"text": "Craft a wooden spear", "type": "craft", "target": "spear", "count": 1, "xp": 20},
	{"text": "Harvest 2 rabbit fur", "type": "collect", "target": "rabbit:fur", "count": 2, "xp": 30},
	{"text": "Build the storage", "type": "build", "target": "storage", "count": 1, "xp": 25},
	{"text": "Harvest 1 squirrel fur", "type": "collect", "target": "squirrel:fur", "count": 1, "xp": 20},
	{"text": "Harvest 10 rabbit fur", "type": "collect", "target": "rabbit:fur", "count": 10, "xp": 40},
	{"text": "Cook 2 meat", "type": "craft", "target": "cooked_meat", "count": 2, "xp": 20},
	{"text": "Build the house", "type": "build", "target": "house", "count": 1, "xp": 40},
	{"text": "Harvest 1 deer antler in the east forest", "type": "collect", "target": "deer:antler", "count": 1, "xp": 60},
	{"text": "Reach level 5", "type": "level", "target": "", "count": 5, "xp": 0},
	{"text": "Defeat the Great Boar", "type": "boss", "target": "boar", "count": 1, "xp": 100},
	{"text": "Take the mountain pass", "type": "travel", "target": "mountains", "count": 1, "xp": 0},
]

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


func recipe_name(id: String) -> String:
	var r: Dictionary = RECIPES[id]
	return item_name(r["tool"] if r.has("tool") else r["item"])


func cost_text(cost: Dictionary) -> String:
	var parts := []
	for id in cost:
		parts.append("%s ×%d" % [item_name(id), cost[id]])
	return ", ".join(parts)
