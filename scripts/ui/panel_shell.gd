extends Control
## Full-screen window shell and the building blocks the views are made of:
## labels, cards, chips, icon tiles, category grids, live timer labels and
## bars. The views themselves (stations, bag, shop, menu) are in panel.gd,
## which extends this script. Content is rebuilt whenever the game state
## changes; live labels and bars tick every frame.

const Style := preload("res://scripts/ui/style.gd")
const IconButton := preload("res://scripts/ui/icon_button.gd")
const IconRect := preload("res://scripts/ui/icon_rect.gd")
const GRID_COLUMNS := 2
const SCROLL_DEADZONE := 14

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
	Style.glass(_sheet, 0.0, 20.0, Style.GLASS_SHEET, 4.0) # frosted over the world
	var sheet_box: StyleBox = _sheet.get_theme_stylebox("panel")
	sheet_box.content_margin_left = 48 # clear of the camera cutout and rounded screen corners
	sheet_box.content_margin_right = 48
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
	_on_open()
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
	_on_close()
	_builder = Callable()
	var t := create_tween().set_parallel()
	t.tween_property(_sheet, "position:y", size.y, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(_dim, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(func() -> void:
		visible = false
		_sheet.position.y = 0.0)


## Hooks for the views (reset per-window state, mark things as seen).
func _on_open() -> void:
	pass


func _on_close() -> void:
	pass


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
	var parts := _card()
	var row: HBoxContainer = parts[1]
	var lines := text.split("\n")
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	for i in lines.size():
		var l := _make_label(lines[i], Style.TEXT if i == 0 else Style.MUTED, 22 if i == 0 else 17, i == 0)
		l.custom_minimum_size.x = 200 # wrap rather than widen the card past the screen
		col.add_child(l)
	# Up to three buttons sit on the text's line; more (the Dev menu's tier,
	# level and teleport rows) wrap onto lines of their own.
	var holder: Container = row
	if buttons.size() > 3:
		holder = HFlowContainer.new()
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_theme_constant_override("h_separation", 10)
		holder.add_theme_constant_override("v_separation", 8)
		col.add_child(holder)
	for i in buttons.size():
		var b: Array = buttons[i]
		holder.add_child(_button(b[0], b[1], b[2], i == 0))
	_place(parts[0])


func _button(text: String, enabled: bool, action: Callable, primary: bool, height := 58.0) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(130, height)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if primary:
		button.theme_type_variation = "PrimaryButton"
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.pressed.connect(func() -> void:
		if not _ignore_tap:
			action.call())
	Style.add_press_juice(button)
	return button


## A small square icon button (pin, close…) that sits in a card.
func _small_icon_button(icon: String, color: Color, action: Callable) -> Button:
	var b := IconButton.new()
	b.icon_name = icon
	b.icon_color = color
	b.custom_minimum_size = Vector2(52, 52)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.pressed.connect(func() -> void:
		if not _ignore_tap:
			action.call())
	return b


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
	card.mouse_filter = Control.MOUSE_FILTER_PASS # let drags reach the scroll
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	return [card, row]


## A rounded square with an icon, tinted with the icon's colour.
func _icon_tile(icon: String, color: Color, icon_size := 46.0) -> Control:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", Style.pane(Color(color, 0.16), 16, 10, Color(color, 0.35)))
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ic := IconRect.new()
	ic.icon = icon
	ic.color = color
	ic.custom_minimum_size = Vector2(icon_size, icon_size)
	tile.add_child(ic)
	return tile


## A thin bar that follows progress_fn (0..1) every frame.
func _progress_bar(progress_fn: Callable, color := Style.ACCENT) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_stylebox_override("fill", Style.box(color, 6, 0))
	bar.value = progress_fn.call()
	_live_bars.append([bar, progress_fn])
	return bar


## A flow of chips; returns the container to add chips to.
func _chip_row() -> HFlowContainer:
	var chips := HFlowContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_PASS
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	return chips


## Small rounded tag for a cost or a duration, with an optional muted note.
## on_tap, if given, runs when the chip is tapped (not dragged).
func _chip(text: String, color: Color, note := "", on_tap := Callable(), filled := false) -> PanelContainer:
	var chip := PanelContainer.new()
	var box := Style.pane(Color(color, 0.85) if filled else Color(1, 1, 1, 0.08), 12, 4, Color(1, 1, 1, 0.0 if filled else 0.1))
	box.content_margin_left = 10
	box.content_margin_right = 10
	chip.add_theme_stylebox_override("panel", box)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)
	var l := _make_label(text, Color("2a1a08") if filled else color, 17, true)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	if note != "":
		var n := _make_label(note, Style.MUTED, 17)
		n.autowrap_mode = TextServer.AUTOWRAP_OFF
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(n)
	if on_tap.is_valid():
		chip.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _ignore_tap:
				on_tap.call())
	return chip


## "2 Wood" in green when you have enough, red when you don't, with how many
## you have. Tapping it says where to find the item.
func _cost_chip(item: String, need: int) -> PanelContainer:
	var have := Game.count_available(item)
	var note := ("owned" if have > 0 else "missing") if Data.TOOLS.has(item) else "have %d" % have
	return _chip(("%d %s" % [need, Data.item_name(item)]) if not Data.TOOLS.has(item) else Data.item_name(item),
		Style.GOOD if have >= need else Style.BAD, note, func() -> void: Game.notify(Data.sources(item)))


## Cost chips for a whole cost dictionary, plus a time chip.
func _cost_chips(cost: Dictionary, seconds: float) -> HFlowContainer:
	var chips := _chip_row()
	for item in cost:
		chips.add_child(_cost_chip(item, cost[item]))
	chips.add_child(_chip(fmt_time(seconds), Style.MUTED))
	return chips


## "Need 3 more stone, 1 more fur" or "" when the cost is covered.
static func missing_text(cost: Dictionary) -> String:
	var need := []
	var gear := []
	for item in cost:
		var short: int = cost[item] - Game.count_available(item)
		if short <= 0:
			continue
		if Data.TOOLS.has(item):
			gear.append("a %s" % Data.item_name(item).to_lower())
		else:
			need.append("%d more %s" % [short, Data.item_name(item).to_lower()])
	var parts := []
	if not gear.is_empty():
		parts.append("Needs %s first" % ", ".join(gear))
	if not need.is_empty():
		parts.append("Need " + ", ".join(need))
	return " · ".join(parts)


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
