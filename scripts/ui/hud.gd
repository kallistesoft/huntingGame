extends Control
## On-screen UI: stat bars, top buttons, messages, the sleep/exhausted
## prompt, and touch controls (joystick on the left half, action button
## bottom right). Touches are read in _input so the joystick and the action
## button work with two fingers at once.

const GamePanel := preload("res://scripts/ui/panel.gd")
const JOY_RADIUS := 80.0
const ACTION_RADIUS := 80.0
const TOP_BAR_HEIGHT := 230.0
const MESSAGE_SECONDS := 3.0
const MAX_MESSAGES := 4

var player: Node3D

var _bars := {} # name -> [ProgressBar, Label]
var _level_label: Label
var _quest_label: Label
var _hint_label: Label
var _messages: VBoxContainer
var _prompt: PanelContainer
var _prompt_label: Label
var _prompt_sleep: Button
var _prompt_ad: Button
var _panel: Control

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _act_index := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Theme.new()
	t.default_font_size = 20
	theme = t

	_build_stats()
	_build_buttons()

	_quest_label = Label.new()
	_quest_label.position = Vector2(16, TOP_BAR_HEIGHT - 6)
	_quest_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	_quest_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_quest_label.add_theme_constant_override("outline_size", 6)
	add_child(_quest_label)

	_messages = VBoxContainer.new()
	_messages.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_messages.position.y = 60
	_messages.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_messages)
	Game.message.connect(_show_message)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint_label.add_theme_constant_override("outline_size", 6)
	add_child(_hint_label)

	_build_prompt()

	_panel = GamePanel.new()
	add_child(_panel)


func _build_stats() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_level_label = Label.new()
	_level_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_level_label.add_theme_constant_override("outline_size", 6)
	box.add_child(_level_label)
	for spec in [["XP", Color(0.6, 0.4, 0.9)], ["Energy", Color(1.0, 0.8, 0.2)],
			["Food", Color(0.9, 0.45, 0.2)], ["Water", Color(0.3, 0.6, 1.0)], ["Bag", Color(0.6, 0.6, 0.6)]]:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(240, 24)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = spec[1]
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.5)
		bar.add_theme_stylebox_override("background", bg)
		var label := Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		bar.add_child(label)
		box.add_child(bar)
		_bars[spec[0]] = [bar, label]


func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.position = Vector2(-16, 12)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for spec in [["Eat", Game.eat_best], ["Sleep", Game.start_sleep], ["Bag", func() -> void: _panel.open_bag()],
			["Shop", func() -> void: _panel.open_shop()], ["Menu", func() -> void: _panel.open_menu()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(96, 56)
		b.pressed.connect(spec[1])
		row.add_child(b)


func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.position.y -= 24
	add_child(_prompt)
	var vbox := VBoxContainer.new()
	_prompt.add_child(vbox)
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_prompt_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)
	_prompt_sleep = Button.new()
	_prompt_sleep.custom_minimum_size = Vector2(160, 56)
	_prompt_sleep.pressed.connect(Game.start_sleep)
	row.add_child(_prompt_sleep)
	_prompt_ad = Button.new()
	_prompt_ad.custom_minimum_size = Vector2(160, 56)
	_prompt_ad.pressed.connect(Game.watch_ad_for_energy)
	row.add_child(_prompt_ad)


func open_station(kind: String) -> void:
	_release_touches()
	_panel.open_station(kind)


# --- Per-frame refresh -------------------------------------------------------

func _process(_delta: float) -> void:
	var lp := Game.level_progress()
	_level_label.text = "Level %d" % Game.level
	if Game.xp_boost_left() > 0.0:
		_level_label.text += "   ×%d XP %s" % [Data.XP_BOOST_MULT, GamePanel.fmt_time(Game.xp_boost_left())]
	if lp[1] > 0:
		_set_bar("XP", lp[0], lp[1], "XP %d / %d" % [lp[0], lp[1]])
	else:
		_set_bar("XP", 1, 1, "Max level")
	_set_bar("Energy", Game.energy, Game.max_energy(), "Energy %d / %d" % [ceili(Game.energy), Game.max_energy()])
	_set_bar("Food", Game.hunger, 100, "Food %d%%" % ceili(Game.hunger))
	_set_bar("Water", Game.thirst, 100, "Water %d%%" % ceili(Game.thirst))
	_set_bar("Bag", Game.carry_weight(), Game.carry_limit(), "Bag %.1f / %d kg" % [Game.carry_weight(), Game.carry_limit()])

	var q := Game.current_quest()
	_quest_label.text = "Quest: %s (%d/%d)" % [q["text"], Game.quest_progress_count(), q["count"]] if not q.is_empty() else ""

	var target: Node3D = player.find_target()
	_hint_label.text = target.action_label() if target != null else ""
	_hint_label.size = Vector2(320, 30)
	_hint_label.position = _action_center() - Vector2(160, ACTION_RADIUS + 40)

	_update_prompt()

	if _panel.visible or AdService.is_showing():
		_release_touches()
	elif _act_index != -1:
		player.do_action() # holding the button repeats, limited by the cooldown
	queue_redraw()


func _set_bar(bar_name: String, value: float, max_value: float, text: String) -> void:
	var bar: ProgressBar = _bars[bar_name][0]
	bar.max_value = max_value
	bar.value = value
	_bars[bar_name][1].text = text


func _update_prompt() -> void:
	var ad_text := "Ad: +%d energy (%d left)" % [Data.AD_ENERGY_REWARD, Game.ads_left_today()]
	if Game.is_sleeping():
		_prompt.visible = true
		_prompt_label.text = "Sleeping… %s left" % GamePanel.fmt_time(Game.sleep_left())
		_prompt_sleep.visible = false
	elif Game.energy <= 0.0:
		_prompt.visible = true
		_prompt_label.text = "Exhausted! You are slow and can't work or hunt."
		_prompt_sleep.visible = true
		_prompt_sleep.text = "Sleep (%s)" % GamePanel.fmt_time(Game.sleep_duration())
	else:
		_prompt.visible = false
	_prompt_ad.text = ad_text
	_prompt_ad.disabled = Game.ads_left_today() <= 0


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


func _draw() -> void:
	var c := _action_center()
	draw_circle(c, ACTION_RADIUS, Color(1, 1, 1, 0.35 if _act_index != -1 else 0.2))
	draw_arc(c, ACTION_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0)
	draw_string(get_theme_default_font(), c - Vector2(ACTION_RADIUS, -10), "ACTION",
		HORIZONTAL_ALIGNMENT_CENTER, ACTION_RADIUS * 2, 24, Color.WHITE)
	if _joy_index != -1:
		draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.15))
		draw_circle(_joy_origin + (_joy_pos - _joy_origin).limit_length(JOY_RADIUS), 32, Color(1, 1, 1, 0.4))
	else:
		var hint := Vector2(150, size.y - 150)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
		draw_circle(hint, 32, Color(1, 1, 1, 0.15))


func _show_message(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_messages.add_child(l)
	while _messages.get_child_count() > MAX_MESSAGES:
		_messages.get_child(0).free()
	var tween := l.create_tween()
	tween.tween_interval(MESSAGE_SECONDS)
	tween.tween_property(l, "modulate:a", 0.0, 0.5)
	tween.tween_callback(l.queue_free)
