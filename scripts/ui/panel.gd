extends Control
## Modal window for camp stations, the bag, the shop and the menu. Its content
## is rebuilt whenever the game state changes; timer lines tick every frame.

const Style := preload("res://scripts/ui/style.gd")
const IconButton := preload("res://scripts/ui/icon_button.gd")
const SHEET_WIDTH := 860.0
const SHEET_HEIGHT := 600.0

var _dim: ColorRect
var _sheet: PanelContainer
var _title: Label
var _content: VBoxContainer
var _builder := Callable()
var _live: Array = [] # [Label, Callable returning String]
var _rebuild_queued := false
var _confirm_reset := false


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

	# Bottom sheet that slides up.
	_sheet = PanelContainer.new()
	_sheet.anchor_left = 0.5
	_sheet.anchor_right = 0.5
	_sheet.anchor_top = 1.0
	_sheet.anchor_bottom = 1.0
	_sheet.offset_left = -SHEET_WIDTH / 2.0
	_sheet.offset_right = SHEET_WIDTH / 2.0
	_sheet.offset_top = -SHEET_HEIGHT
	_sheet.offset_bottom = 30 # rounded bottom corners hidden off screen
	add_child(_sheet)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_sheet.add_child(vbox)

	var handle := ColorRect.new()
	handle.color = Color(Style.TEXT, 0.25)
	handle.custom_minimum_size = Vector2(60, 5)
	handle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(handle)

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

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(bottom_pad)

	Game.changed.connect(_queue_rebuild)


func _process(_delta: float) -> void:
	for pair in _live:
		pair[0].text = pair[1].call()


func open(title: String, builder: Callable) -> void:
	_title.text = title
	_builder = builder
	_confirm_reset = false
	var was_open := visible
	visible = true
	_rebuild()
	if not was_open:
		_sheet.position.y += SHEET_HEIGHT
		_dim.modulate.a = 0.0
		var t := create_tween().set_parallel()
		t.tween_property(_sheet, "position:y", _sheet.position.y - SHEET_HEIGHT, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(_dim, "modulate:a", 1.0, 0.25)


func close() -> void:
	if not visible:
		return
	_builder = Callable()
	var t := create_tween().set_parallel()
	t.tween_property(_sheet, "position:y", _sheet.position.y + SHEET_HEIGHT, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(_dim, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(func() -> void:
		visible = false
		_sheet.position.y -= SHEET_HEIGHT)


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
	_builder.call()


# --- Building blocks ---------------------------------------------------------

func _label(text: String, color := Style.TEXT, font_size := 20) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	_content.add_child(l)
	return l


func _live_label(text_fn: Callable, color := Style.ACCENT) -> void:
	_live.append([_label(text_fn.call(), color), text_fn])


## A card: a title line, optional detail lines, and buttons on the right.
## Each button is [text, enabled, callable]; the first one is the primary action.
func _row(text: String, buttons: Array) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
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
		var button := Button.new()
		button.text = b[0]
		button.disabled = not b[1]
		button.custom_minimum_size = Vector2(130, 58)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if i == 0:
			button.theme_type_variation = "PrimaryButton"
		button.pressed.connect(b[2])
		Style.add_press_juice(button)
		row.add_child(button)
	_content.add_child(card)


func _separator() -> void:
	_content.add_child(HSeparator.new())


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
	_label("Materials are taken from storage first, then from your bag.", Style.MUTED, 16)

	if tier == 0:
		return
	_separator()
	match kind:
		"crafting": _build_crafting()
		"storage": _build_storage()
		"house": _build_house()


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
			return "Better tiers unlock better recipes."


func _build_crafting() -> void:
	if not Game.craft_job.is_empty():
		var name := Data.recipe_name(Game.craft_job["recipe"])
		_live_label(func() -> String: return "Crafting %s… %s left" % [name, fmt_time(Game.craft_left())])
	for id in Data.RECIPES:
		var r: Dictionary = Data.RECIPES[id]
		var blocker := Game.craft_blocker(id)
		if blocker == "Owned":
			_row("%s — owned" % Data.recipe_name(id), [])
			continue
		var text := "%s\n%s · %s" % [Data.recipe_name(id), _cost_have(r["cost"]), fmt_time(r["time"])]
		if blocker != "" and blocker != "Busy":
			text += "\n" + blocker
		_row(text, [["Craft", blocker == "", Game.start_craft.bind(id)]])
	_label("Tools are equipped when done. Other crafts go to storage.", Style.MUTED, 16)


func _build_storage() -> void:
	_label("Stored: %.1f / %d kg" % [Game.bag_weight(Game.storage), Game.storage_capacity()])
	_row("Your bag: %.1f / %d kg" % [Game.carry_weight(), Game.carry_limit()],
		[["Deposit all", not Game.inventory.is_empty(), Game.deposit_all]])
	_separator()
	if Game.storage.is_empty():
		_label("Storage is empty.", Style.MUTED)
	for id in Game.storage:
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
	_label("Quests complete on their own as you play.", Style.MUTED, 16)


# --- Bag, shop, menu ---------------------------------------------------------

func open_bag() -> void:
	open("Bag", _build_bag)


func _build_bag() -> void:
	_label("Weight: %.1f / %d kg" % [Game.carry_weight(), Game.carry_limit()])
	if Game.inventory.is_empty():
		_label("Your bag is empty.", Style.MUTED)
	for id in Game.inventory:
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
