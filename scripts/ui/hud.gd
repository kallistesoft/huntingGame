extends Control
## On-screen UI: stats card, quest card, round icon buttons, toasts, the
## sleep/exhausted card, level-up banner, and touch controls (joystick on the
## left half, contextual action button bottom right). Touches are read in
## _input so the joystick and the action button work with two fingers at once.

const GamePanel := preload("res://scripts/ui/panel.gd")
const Style := preload("res://scripts/ui/style.gd")
const Icons := preload("res://scripts/ui/icons.gd")
const IconRect := preload("res://scripts/ui/icon_rect.gd")
const IconButton := preload("res://scripts/ui/icon_button.gd")
const JOY_RADIUS := 80.0
const ACTION_RADIUS := 78.0
const TOP_BAR_HEIGHT := 230.0
const MESSAGE_SECONDS := 2.6
const MAX_MESSAGES := 3

var player: Node3D

var _stats := {} # name -> {bar, label, shown}
var _level_badge: Control
var _shown_xp := 0.0
var _boost_label: Label
var _quest_label: Label
var _quest_bar: ProgressBar
var _quest_card: PanelContainer
var _bag_button: Button
var _messages: VBoxContainer
var _prompt: PanelContainer
var _prompt_label: Label
var _prompt_sleep: Button
var _prompt_ad: Button
var _banner: Label
var _panel: Control

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _act_index := -1
var _action_icon := ""
var _action_text := ""
var _action_pulse := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Style.make_theme()

	_build_stats()
	_build_quest()
	_build_buttons()

	_messages = VBoxContainer.new()
	_messages.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_messages.position.y = 100
	_messages.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_messages.alignment = BoxContainer.ALIGNMENT_BEGIN
	_messages.add_theme_constant_override("separation", 6)
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_messages)
	Game.message.connect(_show_message)

	_build_prompt()

	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_override("font", Style.font_bold())
	_banner.add_theme_font_size_override("font_size", 72)
	_banner.add_theme_color_override("font_color", Style.ACCENT)
	_banner.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.0))
	_banner.add_theme_constant_override("outline_size", 18)
	_banner.visible = false
	add_child(_banner)
	Game.leveled_up.connect(_on_level_up)

	_panel = GamePanel.new()
	add_child(_panel)


# --- Building the HUD ----------------------------------------------------------

func _build_stats() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "Pill"
	card.position = Vector2(14, 12)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	_level_badge = Control.new()
	_level_badge.custom_minimum_size = Vector2(76, 76)
	_level_badge.draw.connect(_draw_level_badge)
	row.add_child(_level_badge)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	for spec in [["energy", Style.ENERGY], ["food", Style.FOOD], ["water", Style.WATER], ["bag", Style.BAG]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		col.add_child(line)
		var icon := IconRect.new()
		icon.icon = spec[0]
		icon.color = spec[1]
		icon.custom_minimum_size = Vector2(20, 20)
		line.add_child(icon)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(150, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.add_theme_stylebox_override("fill", Style.box(spec[1], 6, 0))
		line.add_child(bar)
		var label := Label.new()
		label.custom_minimum_size = Vector2(84, 0)
		label.add_theme_font_size_override("font_size", 16)
		line.add_child(label)
		_stats[spec[0]] = {"bar": bar, "label": label, "shown": -1.0}

	_boost_label = Label.new()
	_boost_label.add_theme_font_size_override("font_size", 16)
	_boost_label.add_theme_color_override("font_color", Style.XP)
	col.add_child(_boost_label)


func _build_quest() -> void:
	_quest_card = PanelContainer.new()
	_quest_card.theme_type_variation = "Pill"
	_quest_card.position = Vector2(14, 168)
	_quest_card.custom_minimum_size = Vector2(368, 0)
	_quest_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_quest_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_quest_card.add_child(row)
	var icon := IconRect.new()
	icon.icon = "quest"
	icon.color = Style.ACCENT
	icon.custom_minimum_size = Vector2(26, 26)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	_quest_label = Label.new()
	_quest_label.add_theme_font_size_override("font_size", 17)
	col.add_child(_quest_label)
	_quest_bar = ProgressBar.new()
	_quest_bar.custom_minimum_size = Vector2(0, 8)
	_quest_bar.show_percentage = false
	_quest_bar.add_theme_stylebox_override("fill", Style.box(Style.ACCENT, 4, 0))
	col.add_child(_quest_bar)


func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.position = Vector2(-14, 12)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	for spec in [["food", "Eat", Style.FOOD, Game.eat_best],
			["sleep", "Sleep", Color("c9b8ff"), Game.start_sleep],
			["bag", "Bag", Style.BAG, func() -> void: _panel.open_bag()],
			["shop", "Shop", Style.ACCENT, func() -> void: _panel.open_shop()],
			["menu", "Menu", Style.TEXT, func() -> void: _panel.open_menu()]]:
		var b := IconButton.new()
		b.icon_name = spec[0]
		b.caption = spec[1]
		b.icon_color = spec[2]
		b.pressed.connect(spec[3])
		row.add_child(b)
		if spec[0] == "bag":
			_bag_button = b


func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.position.y -= 24
	add_child(_prompt)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_prompt.add_child(vbox)
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_prompt_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)
	_prompt_sleep = Button.new()
	_prompt_sleep.custom_minimum_size = Vector2(180, 60)
	_prompt_sleep.pressed.connect(Game.start_sleep)
	Style.add_press_juice(_prompt_sleep)
	row.add_child(_prompt_sleep)
	_prompt_ad = Button.new()
	_prompt_ad.theme_type_variation = "PrimaryButton"
	_prompt_ad.custom_minimum_size = Vector2(240, 60)
	_prompt_ad.pressed.connect(Game.watch_ad_for_energy)
	Style.add_press_juice(_prompt_ad)
	row.add_child(_prompt_ad)


func open_station(kind: String) -> void:
	_release_touches()
	_panel.open_station(kind)


# --- Per-frame refresh -------------------------------------------------------

func _process(delta: float) -> void:
	var smooth := minf(1.0, 8.0 * delta)
	_set_stat("energy", Game.energy, Game.max_energy(), "%d/%d" % [ceili(Game.energy), Game.max_energy()], smooth)
	_set_stat("food", Game.hunger, 100.0, "%d%%" % ceili(Game.hunger), smooth)
	_set_stat("water", Game.thirst, 100.0, "%d%%" % ceili(Game.thirst), smooth)
	_set_stat("bag", Game.carry_weight(), Game.carry_limit(), "%.1f/%d kg" % [Game.carry_weight(), Game.carry_limit()], smooth)
	var lp := Game.level_progress()
	var xp_ratio: float = float(lp[0]) / lp[1] if lp[1] > 0 else 1.0
	_shown_xp = lerpf(_shown_xp, xp_ratio, smooth) if xp_ratio >= _shown_xp else xp_ratio
	_level_badge.queue_redraw()
	_boost_label.visible = Game.xp_boost_left() > 0.0
	if _boost_label.visible:
		_boost_label.text = "×%d XP · %s" % [Data.XP_BOOST_MULT, GamePanel.fmt_time(Game.xp_boost_left())]

	var q := Game.current_quest()
	_quest_card.visible = not q.is_empty()
	if not q.is_empty():
		_quest_label.text = "%s  %d/%d" % [q["text"], Game.quest_progress_count(), q["count"]]
		_quest_bar.max_value = q["count"]
		_quest_bar.value = Game.quest_progress_count()

	var target: Node3D = player.find_target()
	_action_icon = target.action_icon() if target != null else ""
	_action_text = target.action_label() if target != null else ""
	_action_pulse += delta * 4.0

	_update_prompt()

	if _panel.visible or AdService.is_showing():
		_release_touches()
	elif _act_index != -1:
		player.do_action() # holding the button repeats, limited by the cooldown
	queue_redraw()


func _set_stat(stat: String, value: float, max_value: float, text: String, smooth: float) -> void:
	var s: Dictionary = _stats[stat]
	var bar: ProgressBar = s["bar"]
	s["shown"] = value if s["shown"] < 0.0 else lerpf(s["shown"], value, smooth)
	bar.max_value = max_value
	bar.value = s["shown"]
	s["label"].text = text
	var low := stat in ["energy", "food", "water"] and value < max_value * 0.2
	s["label"].add_theme_color_override("font_color", Style.BAD if low else Style.TEXT)


func _update_prompt() -> void:
	_prompt_ad.text = "+%d energy · ad (%d)" % [Data.AD_ENERGY_REWARD, Game.ads_left_today()]
	_prompt_ad.disabled = Game.ads_left_today() <= 0
	var was_visible := _prompt.visible
	if Game.is_sleeping():
		_prompt.visible = true
		_prompt_label.text = "Sleeping… %s" % GamePanel.fmt_time(Game.sleep_left())
		_prompt_sleep.visible = false
	elif Game.energy <= 0.0:
		_prompt.visible = true
		_prompt_label.text = "Exhausted! You are slow and can't work or hunt."
		_prompt_sleep.visible = true
		_prompt_sleep.text = "Sleep %s" % GamePanel.fmt_time(Game.sleep_duration())
	else:
		_prompt.visible = false
	if _prompt.visible and not was_visible:
		_prompt.modulate.a = 0.0
		_prompt.create_tween().tween_property(_prompt, "modulate:a", 1.0, 0.25)


# --- Effects -------------------------------------------------------------------

## Little coloured dots fly from a screen point into the Bag button.
func fly_to_bag(from: Vector2, color: Color, count: int) -> void:
	var to := _bag_button.get_global_rect().get_center()
	for i in mini(count, 4):
		var dot := Control.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.draw.connect(func() -> void:
			dot.draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.35))
			dot.draw_circle(Vector2.ZERO, 7.0, color))
		dot.position = from + Vector2(randf_range(-14, 14), randf_range(-14, 14))
		add_child(dot)
		var start := dot.position
		var mid := start.lerp(to, 0.5) + Vector2(0, -80)
		var t := dot.create_tween()
		t.tween_interval(0.08 * i)
		t.tween_method(func(k: float) -> void: # curved path
			dot.position = start.lerp(mid, k).lerp(mid.lerp(to, k), k), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.tween_callback(func() -> void:
			dot.queue_free()
			_bump(_bag_button))


func _bump(c: Control) -> void:
	c.pivot_offset = c.size / 2.0
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2.ONE * 1.15, 0.06)
	t.tween_property(c, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_level_up(level: int) -> void:
	_banner.text = "LEVEL %d!" % level
	_banner.visible = true
	_banner.pivot_offset = _banner.size / 2.0
	_banner.scale = Vector2.ONE * 0.3
	_banner.modulate.a = 1.0
	var t := _banner.create_tween()
	t.tween_property(_banner, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.1)
	t.tween_property(_banner, "modulate:a", 0.0, 0.4)
	t.tween_callback(func() -> void: _banner.visible = false)


func _show_message(text: String) -> void:
	var pill := PanelContainer.new()
	pill.theme_type_variation = "Pill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	pill.add_child(l)
	_messages.add_child(pill)
	while _messages.get_child_count() > MAX_MESSAGES:
		_messages.get_child(0).free()
	pill.modulate.a = 0.0
	var t := pill.create_tween()
	t.tween_property(pill, "modulate:a", 1.0, 0.15)
	t.tween_interval(MESSAGE_SECONDS)
	t.tween_property(pill, "modulate:a", 0.0, 0.4)
	t.tween_callback(pill.queue_free)


# --- Touch controls ----------------------------------------------------------

func _action_center() -> Vector2:
	return size - Vector2(ACTION_RADIUS + 40, ACTION_RADIUS + 40)


func _joystick_zone() -> Rect2:
	return Rect2(0, TOP_BAR_HEIGHT, size.x * 0.5, size.y - TOP_BAR_HEIGHT)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not event.pressed:
			if event.index == _joy_index:
				_joy_index = -1
				player.move_input = Vector2.ZERO
			if event.index == _act_index:
				_act_index = -1
			return
		if _panel.visible or AdService.is_showing() or _prompt_hit(event.position):
			return
		if event.position.distance_to(_action_center()) <= ACTION_RADIUS:
			_act_index = event.index
			player.do_action()
		elif _joy_index == -1 and _joystick_zone().has_point(event.position):
			_joy_index = event.index
			_joy_origin = event.position
			_joy_pos = event.position
	elif event is InputEventScreenDrag and event.index == _joy_index:
		_joy_pos = event.position
		player.move_input = ((_joy_pos - _joy_origin) / JOY_RADIUS).limit_length(1.0)


func _prompt_hit(pos: Vector2) -> bool:
	return _prompt.visible and _prompt.get_global_rect().has_point(pos)


func _release_touches() -> void:
	_joy_index = -1
	_act_index = -1
	if player != null:
		player.move_input = Vector2.ZERO


# --- Drawing -------------------------------------------------------------------

func _draw_level_badge() -> void:
	var c := _level_badge.size / 2.0
	var r := c.x - 4.0
	_level_badge.draw_circle(c, r, Color(0, 0, 0, 0.35))
	_level_badge.draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.12), 6.0, true)
	if _shown_xp > 0.0:
		_level_badge.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * _shown_xp, 48, Style.XP, 6.0, true)
	var f := Style.font_bold()
	_level_badge.draw_string(f, c + Vector2(-r, 10), str(Game.level), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 30, Style.TEXT)
	_level_badge.draw_string(f, c + Vector2(-r, -14), "LVL", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 11, Style.MUTED)


func _draw() -> void:
	var c := _action_center()
	var active := _action_icon != ""
	var pressed := _act_index != -1
	var r := ACTION_RADIUS * (0.94 if pressed else 1.0)
	if active and not pressed:
		var glow := 0.5 + 0.5 * sin(_action_pulse)
		draw_circle(c, r + 6 + glow * 6, Color(Style.ACCENT, 0.18 * (1.0 - glow * 0.5)))
	draw_circle(c, r, Color(0, 0, 0, 0.4))
	draw_circle(c, r - 6, Color(Style.ACCENT, 0.9) if active else Color(1, 1, 1, 0.14))
	if active:
		Icons.draw(self, _action_icon, c, r * 0.85, Color("2a1a08"))
		var f := Style.font_bold()
		var w := f.get_string_size(_action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 28
		var pill := Rect2(c + Vector2(-w / 2.0, -r - 46), Vector2(w, 34))
		draw_style_box(Style.box(Style.SHADE, 17, 0), pill)
		draw_string(f, pill.position + Vector2(0, 24), _action_text, HORIZONTAL_ALIGNMENT_CENTER, w, 18, Style.TEXT)
	else:
		Icons.draw(self, "check", c, r * 0.5, Color(1, 1, 1, 0.25))

	if _joy_index != -1:
		draw_circle(_joy_origin, JOY_RADIUS, Color(0, 0, 0, 0.25))
		draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0, true)
		draw_circle(_joy_origin + (_joy_pos - _joy_origin).limit_length(JOY_RADIUS), 34, Color(1, 1, 1, 0.75))
	else:
		var hint := Vector2(150, size.y - 150)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.22), 3.0, true)
		draw_circle(hint, 30, Color(1, 1, 1, 0.16))
