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
const LEVEL_XP := [0, 50, 170, 390, 700, 1100, 1600, 2200, 2900, 3700]

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
]

## The zone after the last one: not built yet. Its gate stands at the end of
## the last zone; crossing it ends the demo. When the zone is added to ZONES,
## move this gate into its "entry" and point NEXT_ZONE at the one after.
const NEXT_ZONE := {
	"id": "mountains", "name": "the mountains",
	"unlock": {"level": 5, "boss": "boar"},
	"entry": {"kind": "pass", "name": "Mountain pass", "position": Vector2(83.5, 25), "facing": -90},
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
	"berries": {"name": "Berries", "weight": 0.2, "food": 8.0, "category": "food"},
	"raw_meat": {"name": "Raw meat", "weight": 0.5, "food": 12.0, "category": "food"},
	"cooked_meat": {"name": "Cooked meat", "weight": 0.4, "food": 35.0, "category": "food"},
	"hide": {"name": "Hide", "weight": 0.6, "category": "animal"},
	"fur": {"name": "Fur", "weight": 0.3, "category": "animal"},
	"antler": {"name": "Antler", "weight": 0.8, "category": "animal"},
	"tusk": {"name": "Boar tusk", "weight": 1.0, "category": "animal"},
	"bone": {"name": "Bone", "weight": 0.4, "category": "animal"},
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
		"xp": 12, "drops": {"raw_meat": 3, "fur": 2, "hide": 1, "antler": 1, "bone": 1}, "respawn": 60.0,
	},
}

## Bosses, one per zone (ZONES[i].boss names the id). A boss lives in its
## lair, charges instead of fleeing; a charge that hits hurts the hunter and
## knocks them back. After a charge it is dizzy for a moment.
const BOSSES := {
	"boar": {
		"name": "Great Boar", "hit_text": "The boar rams you!",
		"hp": 24, "size": 0.9, "color": Color(0.32, 0.22, 0.16),
		"lair": Vector2(76, 9), "lair_radius": 6.0,
		"walk_speed": 1.6, "charge_speed": 9.0, "aggro_radius": 8.0,
		"windup": 0.9, "charge_time": 0.8, "dizzy": 2.2, "dizzy_damage_mult": 2,
		"hit_damage": 30.0, "knockback": 4.0, "regen_per_sec": 0.5,
		"xp": 150, "drops": {"raw_meat": 6, "hide": 3, "tusk": 2, "bone": 3},
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
	"fur_hood": {"tool": "fur_hood", "tier": 1, "station": "crafting", "time": 15.0, "cost": {"fur": 4}},
	"fur_tunic": {"tool": "fur_tunic", "tier": 1, "station": "crafting", "time": 25.0, "cost": {"fur": 6, "rope": 1}},
	"fibre_wraps": {"tool": "fibre_wraps", "tier": 1, "station": "crafting", "time": 12.0, "cost": {"fibre": 6}},
	"fibre_pouch": {"tool": "fibre_pouch", "tier": 1, "station": "crafting", "time": 20.0, "cost": {"fibre": 8, "rope": 1}},
	"leather": {"item": "leather", "count": 1, "tier": 1, "station": "tanning", "time": 20.0, "cost": {"hide": 1, "fibre": 1}},
	"bone_spear": {"tool": "bone_spear", "tier": 2, "station": "crafting", "time": 30.0, "cost": {"spear": 1, "bone": 2, "rope": 1}},
	"bow": {"tool": "bow", "tier": 2, "station": "crafting", "time": 40.0, "cost": {"wood": 6, "leather": 2, "rope": 2}},
	"bone_axe": {"tool": "bone_axe", "tier": 2, "station": "crafting", "time": 30.0, "cost": {"stone_axe": 1, "bone": 3, "rope": 1}},
	"bone_pick": {"tool": "bone_pick", "tier": 2, "station": "crafting", "time": 30.0, "cost": {"stone_pick": 1, "bone": 3, "rope": 1}},
	"tusk_helm": {"tool": "tusk_helm", "tier": 2, "station": "crafting", "time": 40.0, "cost": {"fur_hood": 1, "tusk": 1, "leather": 2}},
	"leather_armor": {"tool": "leather_armor", "tier": 2, "station": "crafting", "time": 60.0, "cost": {"fur_tunic": 1, "leather": 4, "rope": 2}},
	"leather_boots": {"tool": "leather_boots", "tier": 2, "station": "crafting", "time": 40.0, "cost": {"fibre_wraps": 1, "leather": 3}},
	"leather_bag": {"tool": "leather_bag", "tier": 2, "station": "crafting", "time": 45.0, "cost": {"fibre_pouch": 1, "leather": 4}},
}

const CRAFT_XP := 5

# --- Camp structures ---------------------------------------------------------

## tiers[0] is tier 1. "level" is the hunter level needed to build that tier;
## "house_tier" the house tier needed (the house is the master building).
## "speed" scales craft times at that station (0.5 = twice as fast).
const STRUCTURES := {
	"crafting": {"name": "Crafting place", "tiers": [
		{"cost": {"wood": 5}, "time": 10.0, "level": 1, "house_tier": 0},
		{"cost": {"wood": 10, "stone": 6, "rope": 2}, "time": 30.0, "level": 2, "house_tier": 1},
		{"cost": {"wood": 20, "stone": 15, "leather": 2, "antler": 2}, "time": 60.0, "level": 4, "house_tier": 2},
	]},
	"storage": {"name": "Storage", "tiers": [
		{"cost": {"wood": 8}, "time": 15.0, "level": 1, "house_tier": 0, "capacity": 50.0},
		{"cost": {"wood": 15, "stone": 8, "rope": 2}, "time": 30.0, "level": 2, "house_tier": 1, "capacity": 150.0},
		{"cost": {"wood": 25, "stone": 20, "hide": 4}, "time": 60.0, "level": 4, "house_tier": 2, "capacity": 400.0},
	]},
	"house": {"name": "House", "tiers": [
		{"cost": {"wood": 12, "stone": 4}, "time": 20.0, "level": 1, "house_tier": 0, "sleep_time": 40.0, "max_energy": 100.0},
		{"cost": {"wood": 20, "stone": 12, "leather": 3}, "time": 45.0, "level": 3, "house_tier": 0, "sleep_time": 30.0, "max_energy": 120.0},
		{"cost": {"wood": 30, "stone": 25, "leather": 6}, "time": 90.0, "level": 5, "house_tier": 0, "sleep_time": 20.0, "max_energy": 150.0},
	]},
	"tanning": {"name": "Tanning rack", "tiers": [
		{"cost": {"wood": 6, "fibre": 6}, "time": 20.0, "level": 2, "house_tier": 0, "speed": 1.0},
		{"cost": {"wood": 10, "rope": 2, "hide": 2}, "time": 40.0, "level": 4, "house_tier": 1, "speed": 0.5},
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
	{"text": "Gather 6 fibre from tall grass", "type": "gather", "target": "fibre", "count": 6, "xp": 15},
	{"text": "Craft fibre wraps", "type": "craft", "target": "fibre_wraps", "count": 1, "xp": 25},
	{"text": "Build the tanning rack", "type": "build", "target": "tanning", "count": 1, "xp": 25},
	{"text": "Tan 1 leather", "type": "craft", "target": "leather", "count": 1, "xp": 25},
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
