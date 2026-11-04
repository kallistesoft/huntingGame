extends Control
## Full-screen window for camp stations, the bag, the shop and the menu. Its
## content is rebuilt whenever the game state changes; timer lines tick every
## frame. Item lists are grouped under category headings in a two-column grid.

const Style := preload("res://scripts/ui/style.gd")
const IconButton := preload("res://scripts/ui/icon_button.gd")
const IconRect := preload("res://scripts/ui/icon_rect.gd")
const GRID_COLUMNS := 2
const SCROLL_DEADZONE := 14

## Icon and colour of each recipe's tile in the crafting window.
const RECIPE_LOOKS := {
	"spear": ["spear", Color("c9ccd2")],
	"bow": ["bow", Color("e0b47a")],
	"stone_axe": ["axe", Color("b9bcc2")],
	"stone_pick": ["pick", Color("b9bcc2")],
	"leather_bag": ["bag", Color("c8a17a")],
	"cooked_meat": ["food", Color("f08a4b")],
}
## Order of recipe states in a category: what you can craft now comes first.
const RECIPE_STATE_ORDER := ["ready", "busy", "missing", "locked", "owned"]

var _dim: ColorRect
var _sheet: PanelContainer
var _title: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _grid: GridContainer # current category grid that rows go into, or null
var _builder := Callable()
var _live: Array = [] # [Label, Callable returning String]
var _live_bars: Array = [] # [ProgressBar, Callable returning 0..1]
var _rebuild_queued := false
var _confirm_reset := false
var _ignore_tap := false # the current touch scrolled the list or opened the window


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0, 0, 0, 0.5)
	_dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(_dim)

	# Full-screen sheet that slides up.
	_sheet = PanelContainer.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sheet_box := Style.box(Style.BG, 0, 20)
	sheet_box.content_margin_left = 48 # clear of the camera cutout and rounded screen corners
	sheet_box.content_margin_right = 48
	_sheet.add_theme_stylebox_override("panel", sheet_box)
	add_child(_sheet)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_sheet.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	_title = Label.new()
	_title.add_theme_font_override("font", Style.font_bold())
	_title.add_theme_font_size_override("font_size", 30)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_button := IconButton.new()
	close_button.icon_name = "close"
	close_button.custom_minimum_size = Vector2(60, 60)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = SCROLL_DEADZONE
	_scroll.scroll_started.connect(func() -> void: _ignore_tap = true)
	vbox.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_theme_constant_override("separation", 10)
	_scroll.add_child(_content)

	Game.changed.connect(_queue_rebuild)


func _input(event: InputEvent) -> void:
	# Touch only: the mouse press emulated from a touch arrives after it and
	# must not clear the flag that open() set.
	if visible and event is InputEventScreenTouch and event.pressed:
		_ignore_tap = false


func _process(_delta: float) -> void:
	for pair in _live:
		pair[0].text = pair[1].call()
	for pair in _live_bars:
		pair[0].value = pair[1].call()


func open(title: String, builder: Callable) -> void:
	_title.text = title
	_builder = builder
	_confirm_reset = false
	var was_open := visible
	visible = true
	# The touch that opened the window (the action button) must not press the
	# button that now sits under the finger.
	_ignore_tap = true
	_scroll.scroll_vertical = 0
	_rebuild()
	if not was_open:
		_sheet.position.y = size.y
		_dim.modulate.a = 0.0
		var t := create_tween().set_parallel()
		t.tween_property(_sheet, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(_dim, "modulate:a", 1.0, 0.25)


func close() -> void:
	if not visible:
		return
	_builder = Callable()
	var t := create_tween().set_parallel()
	t.tween_property(_sheet, "position:y", size.y, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(_dim, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(func() -> void:
		visible = false
		_sheet.position.y = 0.0)


func _queue_rebuild() -> void:
	# Deferred so a button can safely trigger a rebuild that removes it.
	if visible and not _rebuild_queued:
		_rebuild_queued = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if not visible or not _builder.is_valid():
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_live.clear()
	_live_bars.clear()
	_grid = null
	var keep := _scroll.scroll_vertical
	_builder.call()
	# The new content is sized next frame; restore the scroll then so a tap
	# on a row does not jump the list back to the top.
	await get_tree().process_frame
	_scroll.scroll_vertical = keep


# --- Building blocks ---------------------------------------------------------

func _label(text: String, color := Style.TEXT, font_size := 20) -> Label:
	_grid = null
	var l := _make_label(text, color, font_size)
	_content.add_child(l)
	return l


func _make_label(text: String, color := Style.TEXT, font_size := 20, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	if bold:
		l.add_theme_font_override("font", Style.font_bold())
	return l


func _live_label(text_fn: Callable, color := Style.ACCENT) -> void:
	_live.append([_label(text_fn.call(), color), text_fn])


## A card: a title line, optional detail lines, and buttons on the right.
## Each button is [text, enabled, callable]; the first one is the primary action.
func _row(text: String, buttons: Array) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_PASS # let drags reach the scroll
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var lines := text.split("\n")
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	for i in lines.size():
		var l := Label.new()
		l.text = lines[i]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if i == 0:
			l.add_theme_font_override("font", Style.font_bold())
		else:
			l.add_theme_font_size_override("font_size", 17)
			l.add_theme_color_override("font_color", Style.MUTED)
		col.add_child(l)
	for i in buttons.size():
		var b: Array = buttons[i]
		row.add_child(_button(b[0], b[1], b[2], i == 0))
	_place(card)


func _button(text: String, enabled: bool, action: Callable, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(130, 58)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if primary:
		button.theme_type_variation = "PrimaryButton"
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.pressed.connect(func() -> void:
		if not _ignore_tap:
			action.call())
	Style.add_press_juice(button)
	return button


## Adds a card to the current category grid, or to the page.
func _place(card: Control) -> void:
	if _grid != null:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(card)
	else:
		_content.add_child(card)


## An empty card with a row inside; returns [card, row].
func _card() -> Array:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	return [card, row]


## A rounded square with an icon, tinted with the icon's colour.
func _icon_tile(icon: String, color: Color, icon_size := 46.0) -> Control:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", Style.box(Color(color, 0.16), 16, 10))
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ic := IconRect.new()
	ic.icon = icon
	ic.color = color
	ic.custom_minimum_size = Vector2(icon_size, icon_size)
	tile.add_child(ic)
	return tile


func _separator() -> void:
	_grid = null
	_content.add_child(HSeparator.new())


func _heading(text: String) -> void:
	_label(text, Style.ACCENT, 24).add_theme_font_override("font", Style.font_bold())


## A category heading; the rows after it go into a grid under it.
func _section(category: String) -> void:
	_heading(Data.CATEGORIES[category])
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(_grid)


static func fmt_time(seconds: float) -> String:
	var s := ceili(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func _cost_have(cost: Dictionary) -> String:
	var parts := []
	for id in cost:
		parts.append("%s %d/%d" % [Data.item_name(id), Game.count_available(id), cost[id]])
	return ", ".join(parts)


func _noop() -> void:
	pass


# --- Camp stations -----------------------------------------------------------

func open_station(kind: String) -> void:
	var title: String = "Quest board" if kind == "board" else Data.STRUCTURES[kind]["name"]
	open(title, _build_station.bind(kind))


func _build_station(kind: String) -> void:
	if kind == "board":
		_build_board()
		return
	var tier := Game.structure_tier(kind)
	if kind == "crafting" and tier > 0:
		# Recipes are what you come here for; the upgrade goes below them.
		_build_crafting()
		_separator()
		_heading("Upgrade the crafting place")
		_build_upgrade(kind)
		return
	_build_upgrade(kind)
	if tier == 0:
		return
	_separator()
	match kind:
		"storage": _build_storage()
		"house": _build_house()


func _build_upgrade(kind: String) -> void:
	var tiers: Array = Data.STRUCTURES[kind]["tiers"]
	var tier := Game.structure_tier(kind)
	_label("Tier %d of %d" % [tier, tiers.size()] if tier > 0 else "Not built yet")
	_label(_station_effects(kind, tier), Style.MUTED, 18)

	if Game.structure_busy(kind):
		var next_tier: int = Game.structures[kind]["next_tier"]
		_live_label(func() -> String:
			return "Building tier %d… %s left" % [next_tier, fmt_time(Game.structures[kind]["busy_until"] - Game.now())])
	elif tier < tiers.size():
		var next: Dictionary = tiers[tier]
		var blocker := Game.build_blocker(kind)
		var verb := "Build" if tier == 0 else "Upgrade"
		_row("%s to tier %d\nCost: %s\nTime %s · needs level %d" % [verb, tier + 1, _cost_have(next["cost"]), fmt_time(next["time"]), next["level"]],
			[[verb, blocker == "", Game.start_build.bind(kind)]])
		if blocker != "":
			_label(blocker, Style.BAD, 18)
	else:
		_label("Fully upgraded.")
	_label("Materials are taken from storage first, then from your bag.", Style.MUTED, 17)


func _station_effects(kind: String, tier: int) -> String:
	var tiers: Array = Data.STRUCTURES[kind]["tiers"]
	var next: Dictionary = tiers[tier] if tier < tiers.size() else {}
	match kind:
		"storage":
			var text := "Holds %d kg." % Game.storage_capacity() if tier > 0 else "Empty your bag here."
			return text + (" Next tier: %d kg." % next["capacity"] if not next.is_empty() else "")
		"house":
			var text := "Sleep %ds, max energy %d." % [Game.sleep_duration(), Game.max_energy()] if tier > 0 \
				else "Sleeping outside takes %ds. A house is faster." % Data.NO_HOUSE_SLEEP_TIME
			return text + (" Next tier: sleep %ds, max energy %d." % [next["sleep_time"], next["max_energy"]] if not next.is_empty() else "")
		_:
			if next.is_empty():
				return "All recipes unlocked."
			var unlocks := []
			for id in Data.RECIPES:
				if Data.RECIPES[id]["tier"] == tier + 1:
					unlocks.append(Data.recipe_name(id))
			return "Tier %d unlocks: %s." % [tier + 1, ", ".join(unlocks)] if not unlocks.is_empty() \
				else "Better tiers unlock better recipes."


func _build_crafting() -> void:
	_craft_status()
	var order: Array = Data.RECIPES.keys()
	var ids := order.duplicate()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ra := RECIPE_STATE_ORDER.find(_recipe_state(a))
		var rb := RECIPE_STATE_ORDER.find(_recipe_state(b))
		return ra < rb if ra != rb else order.find(a) < order.find(b))
	for group in Data.by_category(ids, Data.recipe_category):
		_section(group[0])
		for id in group[1]:
			_recipe_card(id)
	_label("Tools are equipped when done. Other crafts go to storage.", Style.MUTED, 17)


## The card at the top: what is being crafted and how long is left.
func _craft_status() -> void:
	var parts := _card()
	var row: HBoxContainer = parts[1]
	if Game.craft_job.is_empty():
		row.add_child(_icon_tile("build", Style.MUTED, 34))
		var idle := _make_label("Nothing crafting. Pick a recipe below.", Style.MUTED, 20)
		idle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		idle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(idle)
	else:
		var id: String = Game.craft_job["recipe"]
		var look: Array = RECIPE_LOOKS.get(id, ["build", Style.TEXT])
		var total: float = Data.RECIPES[id]["time"]
		row.add_child(_icon_tile(look[0], look[1], 34))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 8)
		row.add_child(col)
		col.add_child(_make_label("Crafting %s" % Data.recipe_name(id), Style.TEXT, 22, true))
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.step = 0.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		bar.add_theme_stylebox_override("fill", Style.box(Style.ACCENT, 6, 0))
		col.add_child(bar)
		var progress := func() -> float: return 1.0 - Game.craft_left() / total
		bar.value = progress.call()
		_live_bars.append([bar, progress])
		var left_fn := func() -> String: return "%s left" % fmt_time(Game.craft_left())
		var left := _make_label(left_fn.call(), Style.ACCENT, 20, true)
		left.autowrap_mode = TextServer.AUTOWRAP_OFF
		left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(left)
		_live.append([left, left_fn])
	_content.add_child(parts[0])


## "ready", "busy" (another craft is running), "missing" (materials),
## "locked" (crafting place tier too low) or "owned" (tool already made).
func _recipe_state(id: String) -> String:
	var r: Dictionary = Data.RECIPES[id]
	if r.has("tool") and Game.has_tool(r["tool"]):
		return "owned"
	if Game.structure_tier("crafting") < r["tier"]:
		return "locked"
	if not Game.can_afford(r["cost"]):
		return "missing"
	if not Game.craft_job.is_empty():
		return "busy"
	return "ready"


## One line on what the crafted thing does.
func _recipe_effect(id: String) -> String:
	var r: Dictionary = Data.RECIPES[id]
	if r.has("item"):
		var item: Dictionary = Data.ITEMS[r["item"]]
		return "Eat for +%d food" % item["food"] if item.has("food") else ""
	var tool: Dictionary = Data.TOOLS[r["tool"]]
	if tool.has("damage"):
		return "Damage %d · reach %.1f m" % [tool["damage"], tool["range"]]
	if tool.has("carry_bonus"):
		return "+%d kg carry limit" % tool["carry_bonus"]
	for res in Data.RESOURCES.values():
		if res["tool"] == r["tool"]:
			return "2 %s per hit on a %s" % [Data.item_name(res["item"]).to_lower(), res["name"].to_lower()]
	return ""


func _recipe_card(id: String) -> void:
	var r: Dictionary = Data.RECIPES[id]
	var state := _recipe_state(id)
	var parts := _card()
	var card: PanelContainer = parts[0]
	var row: HBoxContainer = parts[1]
	var look: Array = RECIPE_LOOKS.get(id, ["build", Style.TEXT])
	var tile := _icon_tile(look[0], look[1])
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tile)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	col.add_child(_make_label(Data.recipe_name(id), Style.TEXT, 22, true))
	var effect := _recipe_effect(id)
	if effect != "":
		col.add_child(_make_label(effect, Style.MUTED, 17))

	if state != "owned":
		var chips := HFlowContainer.new()
		chips.mouse_filter = Control.MOUSE_FILTER_PASS
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 6)
		for item in r["cost"]:
			chips.add_child(_cost_chip(item, r["cost"][item]))
		chips.add_child(_chip(fmt_time(r["time"]), Style.MUTED))
		col.add_child(chips)

	match state:
		"missing":
			var need := []
			for item in r["cost"]:
				var short: int = r["cost"][item] - Game.count_available(item)
				if short > 0:
					need.append("%d more %s" % [short, Data.item_name(item).to_lower()])
			col.add_child(_make_label("Need " + ", ".join(need), Style.BAD, 17))
		"locked":
			col.add_child(_make_label("Unlocks at crafting place tier %d" % r["tier"], Style.MUTED, 17))
			card.modulate.a = 0.55
		"busy":
			col.add_child(_make_label("Wait for the current craft", Style.MUTED, 17))

	if state == "owned":
		card.modulate.a = 0.7
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
	else:
		row.add_child(_button("Craft", state == "ready", Game.start_craft.bind(id), true))
	_place(card)


## Small rounded tag for a cost or a duration, with an optional muted note.
func _chip(text: String, color: Color, note := "") -> PanelContainer:
	var chip := PanelContainer.new()
	var box := Style.box(Color(0, 0, 0, 0.22), 12, 4)
	box.content_margin_left = 10
	box.content_margin_right = 10
	chip.add_theme_stylebox_override("panel", box)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)
	var l := _make_label(text, color, 17, true)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	if note != "":
		var n := _make_label(note, Style.MUTED, 17)
		n.autowrap_mode = TextServer.AUTOWRAP_OFF
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(n)
	return chip


## "2 Wood" in green when you have enough, red when you don't, with how many you have.
func _cost_chip(item: String, need: int) -> PanelContainer:
	var have := Game.count_available(item)
	return _chip("%d %s" % [need, Data.item_name(item)], Style.GOOD if have >= need else Style.BAD, "have %d" % have)


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


func _build_house() -> void:
	if Game.is_sleeping():
		_live_label(func() -> String: return "Sleeping… %s left" % fmt_time(Game.sleep_left()))
		return
	_row("Sleep for %s and wake with %d energy" % [fmt_time(Game.sleep_duration()), Game.max_energy()],
		[["Sleep", Game.energy < Game.max_energy(), func() -> void:
			Game.start_sleep()
			close()]])


func _build_board() -> void:
	var q := Game.current_quest()
	_label("Quests done: %d / %d" % [Game.quest_index, Data.QUESTS.size()])
	if q.is_empty():
		_label("All quests done! More come with the next zones.")
		return
	_separator()
	_label(q["text"], Style.ACCENT, 26)
	_label("Progress: %d / %d" % [Game.quest_progress_count(), q["count"]])
	_label("Reward: %d XP" % q["xp"])
	_label("Quests complete on their own as you play.", Style.MUTED, 17)


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
	var owned := []
	for id in Game.tools:
		owned.append(Data.item_name(id))
	_label("Tools: " + (", ".join(owned) if not owned.is_empty() else "none"))


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
	_row("Progress is saved every few seconds.", [["Save now", true, func() -> void:
		Game.save_game()
		Game.notify("Saved.")]])
	_row("Start over from level 1. This deletes the save.",
		[["Tap again" if _confirm_reset else "Reset", true, func() -> void:
			if _confirm_reset:
				Game.reset_progress()
			else:
				_confirm_reset = true
				_rebuild()]])
