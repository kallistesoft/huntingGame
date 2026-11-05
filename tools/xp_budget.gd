extends SceneTree
## Prints the XP a hunter earns by following the quest lines in order: the
## quest rewards plus the "ambient" XP of what each quest makes them do
## (gathering the materials, hunting the animals, crafting, building). Run:
##   godot --headless --path . -s tools/xp_budget.gd
## Use it to see where the level gates land compared to the quest lines.

const D := preload("res://scripts/autoload/data.gd")

var _unit := {} # item id -> XP earned while obtaining one unit (memo)


func _init() -> void:
	var total := 0.0
	var level := 1
	var gates := {} # level -> zone name unlocked at that level
	for z in D.ZONES:
		gates[z["unlock"]["level"]] = z["name"]
	gates[D.NEXT_ZONE["unlock"]["level"]] = D.NEXT_ZONE["name"]
	print("%-12s %-44s %6s %8s %7s %5s" % ["zone", "quest", "quest", "ambient", "total", "lvl"])
	for q in D.quests():
		var ambient := _ambient(q)
		total += q["xp"] + ambient
		var new_level := _level_at(total)
		var note := ""
		for l in range(level + 1, new_level + 1):
			if gates.has(l):
				note += "  <- level %d opens %s" % [l, gates[l]]
		level = new_level
		print("%-12s %-44s %6d %8.0f %7.0f %5d%s" % [q["zone"], q["text"].left(44), q["xp"], ambient, total, level, note])
	quit()


func _level_at(xp: float) -> int:
	var level := 1
	while level < D.LEVEL_XP.size() and xp >= D.LEVEL_XP[level]:
		level += 1
	return level


## XP earned on the side while doing one quest.
func _ambient(q: Dictionary) -> float:
	match q["type"]:
		"gather":
			return q["count"] * _unit_xp(q["target"])
		"collect":
			var parts: PackedStringArray = q["target"].split(":")
			var a: Dictionary = D.ANIMALS[parts[0]]
			return ceili(float(q["count"]) / a["drops"][parts[1]]) * a["xp"]
		"hunt":
			return q["count"] * D.ANIMALS[q["target"]]["xp"]
		"craft":
			var ids: Array = D.QUEST_GROUPS.get(q["target"], [q["target"]])
			return q["count"] * _recipe_xp(ids[0])
		"build":
			var tier: int = q.get("tier", 1)
			var t: Dictionary = D.STRUCTURES[q["target"]]["tiers"][tier - 1]
			return D.BUILD_XP_PER_TIER * tier + _cost_xp(t["cost"])
		"boss":
			return D.BOSSES[q["target"]]["xp"]
	return 0.0


func _cost_xp(cost: Dictionary) -> float:
	var sum := 0.0
	for item in cost:
		sum += cost[item] * _unit_xp(item)
	return sum


## XP of crafting one job of the recipe: the craft itself plus its inputs.
func _recipe_xp(id: String) -> float:
	var r: Dictionary = D.RECIPES[id]
	return _craft_xp(r) + _cost_xp(r["cost"])


## XP earned while obtaining one unit of an item, by the cheapest route.
func _unit_xp(item: String) -> float:
	if _unit.has(item):
		return _unit[item]
	_unit[item] = 0.0 # guards against cycles
	var best := INF
	for res in D.RESOURCES.values():
		if res["item"] == item:
			best = minf(best, float(res["xp"]) / res["amount"])
	for r in D.RECIPES.values():
		if r.get("item", "") == item:
			best = minf(best, _recipe_xp(r.get("id", _recipe_id(r))) / r["count"])
	for a in D.ANIMALS.values():
		if a["drops"].has(item):
			best = minf(best, float(a["xp"]) / a["drops"][item])
	_unit[item] = 0.0 if best == INF else best # boss drops count with the boss
	return _unit[item]


func _recipe_id(r: Dictionary) -> String:
	for id in D.RECIPES:
		if D.RECIPES[id] == r:
			return id
	return ""


func _craft_xp(r: Dictionary) -> float:
	return float(D.craft_xp(r))
