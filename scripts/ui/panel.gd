extends "res://scripts/ui/panel_shell.gd"
## The window's views: camp stations (build/upgrade, crafting, storage,
## house, quest board), the bag, the shop and the menu. The shell and the
## building blocks are in panel_shell.gd.

## Icon and colour of a recipe's or an item's tile. Equipment takes its icon
## from Data.TOOLS; the colour follows the tier (stone, bone…).
const ITEM_LOOKS := {
	"cooked_meat": ["food", Color("f08a4b")],
	"rope": ["rope", Color("d8b36a")],
	"leather": ["leather", Color("a0703f")],
	"thick_leather": ["leather", Color("7a4e28")],
	"iron_bar": ["ingot", Color("9fb4c7")],
	"silver_bar": ["ingot", Color("dfe6ee")],
	"thick_fur": ["leather", Color("eef0f4")],
}
const TIER_COLORS := [Color("c9ccd2"), Color("c8a17a"), Color("efe6cf"), Color("9fb4c7")]


## [icon, colour] for a recipe id or a tool id.
static func look_of(id: String) -> Array:
	if ITEM_LOOKS.has(id):
		return ITEM_LOOKS[id]
	if Data.TOOLS.has(id):
		var t: Dictionary = Data.TOOLS[id]
		return [t["icon"], TIER_COLORS[clampi(t.get("tier", 1), 1, TIER_COLORS.size()) - 1]]
	return ["build", Style.TEXT]
## Order of recipe states in a category: what you can craft now comes first.
const RECIPE_STATE_ORDER := ["ready", "busy", "missing", "locked", "owned"]

var _station_kind := ""
var _confirm_reset := false


func _on_open() -> void:
	_confirm_reset = false


func _on_close() -> void:
	if _station_kind in Data.recipe_stations():
		Game.mark_recipes_seen(_station_kind)
	_station_kind = ""


# --- Camp stations -----------------------------------------------------------

func open_station(kind: String) -> void:
	_station_kind = kind
	var title: String = "Quest board" if kind == "board" else Data.STRUCTURES[kind]["name"]
	open(title, _build_station.bind(kind))


func _build_station(kind: String) -> void:
	if kind == "board":
		_build_board()
		return
	var tier := Game.structure_tier(kind)
	if kind in Data.recipe_stations() and tier > 0:
		# Recipes are what you come here for; the upgrade goes below them.
		_build_crafting(kind)
		_separator()
		_heading("Upgrade the %s" % Data.STRUCTURES[kind]["name"].to_lower())
		_build_upgrade(kind)
		return
	_build_upgrade(kind)
	if tier == 0:
		return
	_separator()
	match kind:
		"storage": _build_storage()
		"house": _build_house()


## The build/upgrade block of a station: what the next tier gives, what it
## costs, and a progress card with a speed-up while it is being built.
func _build_upgrade(kind: String) -> void:
	var tiers: Array = Data.STRUCTURES[kind]["tiers"]
	var tier := Game.structure_tier(kind)
	_label("Tier %d of %d" % [tier, tiers.size()] if tier > 0 else "Not built yet", Style.MUTED, 18)

	if Game.structure_busy(kind):
		var next_tier: int = Game.structures[kind]["next_tier"]
		var total: float = tiers[next_tier - 1]["time"]
		_timer_card("build", Style.ACCENT, "Building tier %d" % next_tier,
			func() -> float: return Game.structures[kind]["busy_until"] - Game.now(), total, kind)
		return
	if tier >= tiers.size():
		_label("Fully upgraded. " + _tier_benefit(kind, tier))
		return

	var next: Dictionary = tiers[tier]
	var blocker := Game.build_blocker(kind)
	var verb := "Build" if tier == 0 else "Upgrade"
	var parts := _card()
	var row: HBoxContainer = parts[1]
	var tile := _icon_tile("build", Style.ACCENT)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tile)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	col.add_child(_make_label("%s to tier %d" % [verb, tier + 1], Style.TEXT, 22, true))
	col.add_child(_make_label(_tier_benefit(kind, tier), Style.MUTED, 17))
	var chips := _cost_chips(next["cost"], next["time"])
	chips.add_child(_chip("Level %d" % next["level"], Style.GOOD if Game.level >= next["level"] else Style.BAD))
	if next.get("house_tier", 0) > 0:
		chips.add_child(_chip("House tier %d" % next["house_tier"], Style.GOOD if Game.structure_tier("house") >= next["house_tier"] else Style.BAD))
	col.add_child(chips)
	if blocker != "":
		var missing := missing_text(next["cost"])
		col.add_child(_make_label(missing if blocker == "Missing materials" and missing != "" else blocker, Style.BAD, 17))
	row.add_child(_button(verb, blocker == "", Game.start_build.bind(kind), true))
	_place(parts[0])
	_label("Materials are taken from storage first, then from your bag.", Style.MUTED, 17)


## What the next tier of a station gives, as "now → next" where possible.
func _tier_benefit(kind: String, tier: int) -> String:
	var tiers: Array = Data.STRUCTURES[kind]["tiers"]
	var next: Dictionary = tiers[tier] if tier < tiers.size() else {}
	match kind:
		"storage":
			if next.is_empty():
				return "Holds %d kg." % Game.storage_capacity()
			return "Holds %d kg → %d kg" % [Game.storage_capacity(), next["capacity"]] if tier > 0 \
				else "Empty your bag here. Holds %d kg." % next["capacity"]
		"house":
			if next.is_empty():
				return "Sleep %d s, max energy %d." % [Game.sleep_duration(), Game.max_energy()]
			if tier == 0:
				return "Sleep %d s instead of %d s outside · max energy %d" % [next["sleep_time"], Data.NO_HOUSE_SLEEP_TIME, next["max_energy"]]
			return "Sleep %d s → %d s · max energy %d → %d" % [Game.sleep_duration(), next["sleep_time"], Game.max_energy(), next["max_energy"]]
		_:
			if next.is_empty():
				return "All recipes unlocked."
			var parts := []
			var unlocks := []
			for id in Data.RECIPES:
				if Data.RECIPES[id]["station"] == kind and Data.RECIPES[id]["tier"] == tier + 1:
					unlocks.append(Data.recipe_name(id))
			if not unlocks.is_empty():
				parts.append("Unlocks: %s" % ", ".join(unlocks))
			if next.has("speed") and next["speed"] < Game.station_speed(kind):
				parts.append("Crafts here take %d%% less time" % roundi((1.0 - next["speed"] / Game.station_speed(kind)) * 100))
			return " · ".join(parts) if not parts.is_empty() else "Better tiers unlock better recipes."


## A progress card: icon, title, bar, time left and a speed-up (ad) button.
## target is what Game.speed_up acts on (a structure id or "craft").
func _timer_card(icon: String, color: Color, title: String, left_fn: Callable, total: float, target: String) -> void:
	var parts := _card()
	var row: HBoxContainer = parts[1]
	row.add_child(_icon_tile(icon, color, 34))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	col.add_child(_make_label(title, Style.TEXT, 22, true))
	col.add_child(_progress_bar(func() -> float: return 1.0 - clampf(left_fn.call() / total, 0.0, 1.0)))
	var text_fn := func() -> String: return "%s left" % fmt_time(maxf(0.0, left_fn.call()))
	var left := _make_label(text_fn.call(), Style.ACCENT, 20, true)
	left.autowrap_mode = TextServer.AUTOWRAP_OFF
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	_live.append([left, text_fn])
	var ads := Game.ads_left_today()
	var speed := _button("½ time · ad (%d)" % ads, ads > 0, Game.speed_up.bind(target), true)
	speed.custom_minimum_size.x = 190
	row.add_child(speed)
	_content.add_child(parts[0])


func _build_crafting(station: String) -> void:
	_craft_status(station)
	var order: Array = Data.RECIPES.keys()
	var ids := order.filter(func(id: String) -> bool: return Data.RECIPES[id]["station"] == station)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ra := RECIPE_STATE_ORDER.find(_recipe_state(a))
		var rb := RECIPE_STATE_ORDER.find(_recipe_state(b))
		return ra < rb if ra != rb else order.find(a) < order.find(b))
	for group in Data.by_category(ids, Data.recipe_category):
		_section(group[0])
		for id in group[1]:
			_recipe_card(id)
	_label("Equipment is worn when done; other crafts go to storage. Tap a cost to see where to find it; pin a recipe to follow it on screen.", Style.MUTED, 17)


## The card at the top: what is being crafted and how long is left.
func _craft_status(station: String) -> void:
	var job := Game.craft_job_at(station)
	if job.is_empty():
		var parts := _card()
		var row: HBoxContainer = parts[1]
		row.add_child(_icon_tile("build", Style.MUTED, 34))
		var idle := _make_label("Nothing crafting. Pick a recipe below.", Style.MUTED, 20)
		idle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		idle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(idle)
		_content.add_child(parts[0])
		return
	var id: String = job["recipe"]
	var count: int = job.get("count", 1)
	var look := look_of(id)
	var title := "Crafting %s" % Data.recipe_name(id) + (" ×%d" % count if count > 1 else "")
	_timer_card(look[0], look[1], title, Game.craft_left.bind(station), job["total"], "craft:" + station)
	# Waiting jobs, each with a cancel that refunds its materials.
	var q := Game.craft_queue(station)
	for i in range(1, q.size()):
		var waiting: Dictionary = q[i]
		var wait_fn := func() -> String: return "starts in %s" % fmt_time(maxf(0.0, q[i - 1]["done_at"] - Game.now()))
		_row("Next: %s%s\n%s" % [Data.recipe_name(waiting["recipe"]), " ×%d" % waiting["count"] if waiting["count"] > 1 else "", wait_fn.call()],
			[["Cancel", true, Game.cancel_craft.bind(station, i)]])
		_live.append([_content.get_child(_content.get_child_count() - 1).get_child(0).get_child(0).get_child(1), wait_fn])
	_label("Queue: %d / %d. Jobs run one after the other, even while the app is closed." % [q.size(), Game.queue_slots()], Style.MUTED, 17)


## "ready", "busy" (another craft is running), "missing" (materials),
## "locked" (crafting place tier too low) or "owned" (tool already made).
func _recipe_state(id: String) -> String:
	var r: Dictionary = Data.RECIPES[id]
	if r.has("tool") and Game.has_tool(r["tool"]):
		return "owned"
	if Game.structure_tier(r["station"]) < r["tier"]:
		return "locked"
	if not Game.can_afford(r["cost"]):
		return "missing"
	if Game.craft_queue(r["station"]).size() >= Game.queue_slots():
		return "busy"
	return "ready"


## One line on what the crafted thing does; upgrades show "old → new".
func _recipe_effect(id: String) -> String:
	var r: Dictionary = Data.RECIPES[id]
	if r.has("item"):
		var item: Dictionary = Data.ITEMS[r["item"]]
		if item.has("food"):
			return "Eat for +%d food" % item["food"]
		var uses := []
		for other in Data.RECIPES:
			if Data.RECIPES[other]["cost"].has(r["item"]):
				uses.append(Data.recipe_name(other))
		return "For: %s" % ", ".join(uses.slice(0, 3)) if not uses.is_empty() else ""
	var tool: Dictionary = Data.TOOLS[r["tool"]]
	var text := Data.tool_effect(r["tool"])
	if tool.has("upgrades_from") and Game.has_tool(tool["upgrades_from"]):
		text = "%s → %s" % [Data.tool_effect(tool["upgrades_from"]), text]
	return text


func _recipe_card(id: String) -> void:
	var r: Dictionary = Data.RECIPES[id]
	var state := _recipe_state(id)
	var parts := _card()
	var card: PanelContainer = parts[0]
	var row: HBoxContainer = parts[1]
	var look := look_of(id)
	var tile := _icon_tile(look[0], look[1])
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tile)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 8)
	col.add_child(title)
	var name_label := _make_label(Data.recipe_name(id), Style.TEXT, 22, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name_label)
	if id in Game.unseen_recipes():
		var tag := _chip("NEW", Style.ACCENT, "", Callable(), true)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.add_child(tag)
	if state != "owned":
		var pinned := Game.pinned_recipe == id
		var pin := _small_icon_button("pin", Style.ACCENT if pinned else Color(Style.TEXT, 0.45), Game.toggle_pin.bind(id))
		pin.custom_minimum_size = Vector2(44, 44)
		pin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.add_child(pin)
	var effect := _recipe_effect(id)
	if effect != "":
		col.add_child(_make_label(effect, Style.MUTED, 17))

	if state != "owned":
		col.add_child(_cost_chips(r["cost"], r["time"]))
	match state:
		"missing":
			col.add_child(_make_label(missing_text(r["cost"]), Style.BAD, 17))
		"locked":
			col.add_child(_make_label("Unlocks at %s tier %d" % [Data.STRUCTURES[r["station"]]["name"].to_lower(), r["tier"]], Style.MUTED, 17))
			card.modulate.a = 0.55
		"busy":
			col.add_child(_make_label("Queue full: wait for a craft to finish", Style.MUTED, 17))

	if state == "owned":
		card.modulate.a = 0.7
		var up := Data.upgrade_of(r["tool"])
		if up != "" and not Game.has_tool(Data.RECIPES[up]["tool"]):
			col.add_child(_make_label("Upgrade: %s" % Data.recipe_name(up), Style.ACCENT, 17))
		var badge := HBoxContainer.new()
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var check := IconRect.new()
		check.icon = "check"
		check.color = Style.GOOD
		check.custom_minimum_size = Vector2(26, 26)
		check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.add_child(check)
		var owned := _make_label("Owned", Style.GOOD, 20, true)
		owned.autowrap_mode = TextServer.AUTOWRAP_OFF
		badge.add_child(owned)
		row.add_child(badge)
		_place(card)
		return

	# Craft (×1 / ×5 / Max for items you can make several of). "Queue" when
	# the station is already working.
	var verb := "Queue" if not Game.craft_queue(r["station"]).is_empty() else "Craft"
	var max_count := Game.max_craft_count(id)
	if r.has("item") and max_count > 1:
		var stack := VBoxContainer.new()
		stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stack.add_theme_constant_override("separation", 6)
		row.add_child(stack)
		stack.add_child(_button(verb, state == "ready", Game.start_craft.bind(id, 1), true, 48))
		if max_count >= 5:
			stack.add_child(_button("×5", state == "ready", Game.start_craft.bind(id, 5), false, 44))
		stack.add_child(_button("Max ×%d" % max_count, state == "ready", Game.start_craft.bind(id, max_count), false, 44))
	else:
		row.add_child(_button(verb, state == "ready", Game.start_craft.bind(id, 1), true))
	_place(card)


func _build_storage() -> void:
	_label("Stored: %.1f / %d kg" % [Game.bag_weight(Game.storage), Game.storage_capacity()])
	_row("Your bag: %.1f / %d kg" % [Game.carry_weight(), Game.carry_limit()],
		[["Deposit all", not Game.inventory.is_empty(), Game.deposit_all]])
	_separator()
	if Game.storage.is_empty():
		_label("Storage is empty.", Style.MUTED)
	for group in Data.by_category(Game.storage.keys(), Data.item_category):
		_section(group[0])
		for id in group[1]:
			var n: int = Game.storage[id]
			_row("%s ×%d" % [Data.item_name(id), n],
				[["Take 1", true, Game.take_from_storage.bind(id, 1)], ["Take all", true, Game.take_from_storage.bind(id, n)]])


## The outpost chest: the camp storage, reachable from another zone.
func open_outpost() -> void:
	_station_kind = "outpost"
	open("Outpost chest", _build_outpost)


func _build_outpost() -> void:
	if Game.structure_tier("storage") == 0:
		_label("The chest is linked to your camp storage. Build the storage at camp first.", Style.MUTED)
		return
	_label("Linked to the camp storage.", Style.MUTED, 17)
	_build_storage()


func _build_house() -> void:
	if Game.is_sleeping():
		_live_label(func() -> String: return "Sleeping… %s left" % fmt_time(Game.sleep_left()))
		return
	_row("Sleep for %s and wake with %d energy" % [fmt_time(Game.sleep_duration()), Game.max_energy()],
		[["Sleep", Game.energy < Game.max_energy(), func() -> void:
			Game.start_sleep()
			close()]])


## The quest board: the current zone's line with done, current and upcoming
## quests, then the lines of the zones already finished, folded to one row.
func _build_board() -> void:
	var all := Data.quests()
	var q := Game.current_quest()
	_label("Quests done: %d / %d" % [Game.quest_index, all.size()])
	if q.is_empty():
		_label("All quests done! More come with the next zones.")
		return
	var line_zone: String = q["zone"]
	for z in Data.ZONES:
		var ids := []
		for i in all.size():
			if all[i]["zone"] == z["id"]:
				ids.append(i)
		if ids.is_empty():
			continue
		var done := ids.filter(func(i: int) -> bool: return i < Game.quest_index).size()
		_separator()
		_heading("%s · %d / %d" % [z["name"].capitalize(), done, ids.size()])
		if z["id"] != line_zone:
			_label("All done." if done == ids.size() else "Later.", Style.MUTED, 17)
			continue
		for i in ids:
			var quest: Dictionary = all[i]
			if i < Game.quest_index:
				_label("✓  " + quest["text"], Style.MUTED, 18)
			elif i == Game.quest_index:
				var parts := _card()
				var row: HBoxContainer = parts[1]
				row.add_child(_icon_tile("quest", Style.ACCENT, 34))
				var col := VBoxContainer.new()
				col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				col.add_theme_constant_override("separation", 6)
				row.add_child(col)
				col.add_child(_make_label(quest["text"], Style.TEXT, 24, true))
				col.add_child(_progress_bar(func() -> float: return float(Game.quest_progress_count()) / maxi(1, quest["count"])))
				col.add_child(_make_label("%d / %d · reward %d XP" % [Game.quest_progress_count(), quest["count"], quest["xp"]], Style.ACCENT, 17))
				_content.add_child(parts[0])
			else:
				_label("·  " + quest["text"], Color(Style.TEXT, 0.55), 18)
	_label("Quests complete on their own as you play.", Style.MUTED, 17)


# --- Hunter (equipment) ------------------------------------------------------

func open_hunter() -> void:
	open("Hunter", _build_hunter)


func _build_hunter() -> void:
	var totals := []
	totals.append("Max health %d" % Game.max_health())
	totals.append("Carry %d kg" % Game.carry_limit())
	var speed := roundi((Game.gear_stat("feet", "speed_mult", 1.0) - 1.0) * 100)
	if speed > 0:
		totals.append("Speed +%d%%" % speed)
	var armor := roundi(Game.gear_stat("body", "armor", 0.0) * 100)
	if armor > 0:
		totals.append("Blocks %d%% of damage" % armor)
	var drain := roundi((1.0 - Game.gear_stat("body", "drain_mult", 1.0)) * 100)
	if drain > 0:
		totals.append("Hunger and thirst %d%% slower" % drain)
	_label("Level %d · %s" % [Game.level, " · ".join(totals)])
	_heading("Equipment")
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(_grid)
	for slot in Data.SLOTS:
		_slot_card(slot)
	_grid = null
	_label("Craft equipment at the crafting place. A better piece replaces the one you wear; upgrades use the old piece.", Style.MUTED, 17)


func _slot_card(slot: String) -> void:
	var id := Game.equipped(slot)
	var parts := _card()
	var card: PanelContainer = parts[0]
	var row: HBoxContainer = parts[1]
	var look := look_of(id) if id != "" else ["hunter", Style.MUTED]
	var tile := _icon_tile(look[0], look[1])
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tile)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	col.add_child(_make_label(Data.SLOTS[slot], Style.MUTED, 16, true))
	if id == "":
		col.add_child(_make_label("Nothing", Style.TEXT, 22, true))
		card.modulate.a = 0.7
		# The first piece for this slot and where it is made.
		for rid in Data.RECIPES:
			var r: Dictionary = Data.RECIPES[rid]
			if r.has("tool") and Data.TOOLS[r["tool"]]["slot"] == slot and Data.TOOLS[r["tool"]].get("tier", 1) == 1:
				col.add_child(_make_label("Craft: %s (%s)" % [Data.recipe_name(rid), Data.STRUCTURES[r["station"]]["name"].to_lower()], Style.ACCENT, 17))
				break
		_place(card)
		return
	var t: Dictionary = Data.TOOLS[id]
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 8)
	col.add_child(title)
	var name_label := _make_label(t["name"], Style.TEXT, 22, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name_label)
	var stars := _make_label("★".repeat(t.get("tier", 1)), Style.ACCENT, 20, true)
	stars.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_child(stars)
	col.add_child(_make_label(Data.tool_effect(id), Style.MUTED, 17))
	var up := Data.upgrade_of(id)
	if up != "":
		var r: Dictionary = Data.RECIPES[up]
		col.add_child(_make_label("Next: %s (%s tier %d)" % [Data.recipe_name(up), Data.STRUCTURES[r["station"]]["name"].to_lower(), r["tier"]], Style.ACCENT, 17))
	_place(card)


# --- Bag, shop, menu ---------------------------------------------------------

func open_bag() -> void:
	open("Bag", _build_bag)


func _build_bag() -> void:
	_label("Weight: %.1f / %d kg" % [Game.carry_weight(), Game.carry_limit()])
	if Game.inventory.is_empty():
		_label("Your bag is empty.", Style.MUTED)
	for group in Data.by_category(Game.inventory.keys(), Data.item_category):
		_section(group[0])
		for id in group[1]:
			var buttons := []
			if Data.ITEMS[id].has("food"):
				buttons.append(["Eat", true, Game.eat.bind(id)])
			_row("%s ×%d (%.1f kg)" % [Data.item_name(id), Game.inventory[id], Data.item_weight(id) * Game.inventory[id]], buttons)
	_separator()
	var worn := []
	for slot in Data.SLOTS:
		if Game.equipped(slot) != "":
			worn.append(Data.item_name(Game.equipped(slot)))
	_label("Equipment: " + (", ".join(worn) if not worn.is_empty() else "none") + " (see Hunter)")


func open_shop() -> void:
	open("Shop", _build_shop)


func _build_shop() -> void:
	_label("PLACEHOLDER: no real ads and no real payments yet.", Style.ACCENT, 18)
	_row("Watch an ad: +%d energy (%d left today)" % [Data.AD_ENERGY_REWARD, Game.ads_left_today()],
		[["Watch", Game.ads_left_today() > 0, Game.watch_ad_for_energy]])
	_separator()
	for id in Data.PACKS:
		var p: Dictionary = Data.PACKS[id]
		var parts := []
		for item in p.get("items", {}):
			parts.append("%s ×%d" % [Data.item_name(item), p["items"][item]])
		for tool in p.get("tools", []):
			parts.append(Data.item_name(tool))
		if p.has("energy"):
			parts.append("+%d energy" % p["energy"])
		if p.has("xp_boost_minutes"):
			parts.append("×%d XP for %d min" % [Data.XP_BOOST_MULT, p["xp_boost_minutes"]])
		_row("%s\n%s" % [p["name"], ", ".join(parts)], [[p["price"], true, Game.buy_pack.bind(id)]])


func open_menu() -> void:
	open("Menu", _build_menu)


func _build_menu() -> void:
	_label("Hunting Game — proof of concept v%s" % ProjectSettings.get_setting("application/config/version"))
	_label("Move with the left side of the screen (or WASD). Tap the round button (or Space) to chop, mine, pick, drink, hunt or open a camp station. Hold it to repeat.", Style.MUTED, 18)
	_separator()
	_row("Sounds: %s" % ("on" if Game.sounds_on else "off"), [["Turn off" if Game.sounds_on else "Turn on", true, Game.toggle_sounds]])
	_row("Progress is saved every few seconds.", [["Save now", true, func() -> void:
		Game.save_game()
		Game.notify("Saved.")]])
	_row("Phone notification when a build, a craft or a sleep ends while the app is closed.",
		[["On" if Game.notifications_on else "Off", true, Game.toggle_notifications]])
	_row("Start over from level 1. This deletes the save.",
		[["Tap again" if _confirm_reset else "Reset", true, func() -> void:
			if _confirm_reset:
				Game.reset_progress()
			else:
				_confirm_reset = true
				_rebuild()]])
	if OS.is_debug_build():
		_build_dev_menu()


## Test helpers, debug builds only: skip the grind when checking a feature.
func _build_dev_menu() -> void:
	_separator()
	_heading("Dev (debug build)")
	_row("Materials: +20 of every item into storage and 5 into the bag.", [["Give", true, Game.dev_give_materials]])
	for kind in Data.STRUCTURES:
		var buttons := []
		for t in range(0, Data.STRUCTURES[kind]["tiers"].size() + 1):
			buttons.append(["T%d" % t, Game.structure_tier(kind) != t, Game.dev_set_tier.bind(kind, t)])
		_row("%s: tier %d" % [Data.STRUCTURES[kind]["name"], Game.structure_tier(kind)], buttons)
	var levels := []
	for l in [1, 3, 5, 8, 13, 18, Data.LEVEL_XP.size()]:
		levels.append(["Lv %d" % l, Game.level != l, Game.dev_set_level.bind(l)])
	_row("Level %d" % Game.level, levels)
	var gear := [["None", true, Game.dev_set_gear.bind(0)]]
	for t in range(1, 5):
		gear.append(["Tier %d" % t, Game.gear_tier("body") != t, Game.dev_set_gear.bind(t)])
	_row("Equipment: every piece of one tier (replaces what you own).", gear)
	_row("Finish every running timer now.", [["Finish", true, Game.dev_finish_timers]])
	_row("Day/night: move the clock forward.", [["+3 min", true, Game.dev_advance_time.bind(180.0)]])
	_row("Forget which recipes you have seen (NEW badges come back).", [["Reset", true, Game.dev_reset_seen]])
	_row("Notification in 10 s (then put the app in the background). Plugin: %s." % ("present" if NotifyService.available() else "absent"),
		[["Test", true, NotifyService.test_in.bind(10)]])
	for id in Data.BOSSES:
		_row("%s: %s" % [Data.BOSSES[id]["name"], "defeated" if Game.bosses_defeated.has(id) else "alive"],
			[["Defeat", not Game.bosses_defeated.has(id), Game.dev_defeat_boss.bind(id)]])
	var world: Node3D = get_parent().player.get_parent() if get_parent().get("player") != null else null
	if world != null:
		var spots := [["Camp", true, func() -> void: _teleport(world, world.CAMP.get_center())]]
		for i in range(1, Data.ZONES.size()):
			var z: Dictionary = Data.ZONES[i]
			spots.append([z["name"].capitalize(), true, func() -> void: _teleport(world, z["rect"].get_center())])
		for id in Data.BOSSES:
			var lair: Vector2 = Data.BOSSES[id]["lair"]
			spots.append([Data.BOSSES[id]["name"], true, func() -> void: _teleport(world, lair + Vector2(-6, 0))])
		_row("Teleport (locked zones stay locked)", spots)


func _teleport(world: Node3D, to: Vector2) -> void:
	world.player.position = Vector3(to.x, 0, to.y)
	world.camera.position = world.player.position + world.CAMERA_OFFSET
	close()
