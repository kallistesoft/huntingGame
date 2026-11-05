extends RefCounted
## UI look: colour palette, font and the shared Theme (rounded cards,
## buttons, bars). Change the palette here to restyle the whole UI.

const BG := Color("1b2a21f2") # sheets and cards background
const CARD := Color("2b3d31")
const CARD_HI := Color("364c3d")
const ACCENT := Color("f2a541") # main call-to-action
const TEXT := Color("f6f2e7")
const MUTED := Color("a8b6a9")
const GOOD := Color("8ad07a")
const BAD := Color("ff7b69")
const SHADE := Color(0, 0, 0, 0.42) # translucent pills over the 3D view
const GLASS := Color(0.04, 0.07, 0.05, 0.5) # tint of frosted panels over the world
const GLASS_SHEET := Color(0.03, 0.06, 0.04, 0.82) # the full-screen window
const LINE := Color(1, 1, 1, 0.14) # hairline borders

const GlassBox := preload("res://scripts/ui/glass_box.gd")

const HEALTH := Color("ff5d5d")
const ENERGY := Color("ffd23f")
const FOOD := Color("f08a4b")
const WATER := Color("4fb3ff")
const XP := Color("b892ff")
const BAG := Color("d9c3a0")

## Colour of each item, used by gather effects.
const ITEM_COLORS := {
	"wood": Color("a0703f"), "stone": Color("b9bcc2"), "berries": Color("e23d5a"),
	"raw_meat": Color("e0726b"), "cooked_meat": Color("b4683a"), "hide": Color("c8a17a"),
	"fur": Color("d98b4a"), "antler": Color("efe6cf"), "tusk": Color("f3eedc"), "bone": Color("ece6d2"),
	"fibre": Color("b5bf6a"), "rope": Color("d8b36a"), "leather": Color("a0703f"), "thick_leather": Color("7a4e28"),
	"iron_ore": Color("b07a58"), "iron_bar": Color("9fb4c7"), "herbs": Color("7cc46b"), "horn": Color("d9cfb8"),
	"wolf_pelt": Color("8e8e99"), "bear_pelt": Color("4e3524"), "claw": Color("e8e0cc"),
	"silver_ore": Color("b9c2cc"), "silver_bar": Color("dfe6ee"), "thick_fur": Color("eef0f4"), "ice_pelt": Color("cfd8e6"),
	"mammoth_pelt": Color("6b4a33"), "mammoth_tusk": Color("f1ead6"),
}

static var _font: FontFile
static var _font_bold: FontFile


## UI scale for the device. The project's 1.35 is tuned for a phone (the
## owner's: 2424×1080 at 420 dpi); a tablet has far more inches for the same
## 720 UI rows, so it scales down to 1.0 and keeps the same physical size of
## text, which stops the stats card from covering 40% of a 16:10 screen.
const PHONE_UNIT_INCHES := 1.35 * (1080.0 / 720.0) / 420.0
static func ui_scale(screen_height_px: float, dpi: float) -> float:
	if screen_height_px <= 0.0 or dpi <= 0.0:
		return 1.35
	var px_per_unit := screen_height_px / 720.0
	return clampf(PHONE_UNIT_INCHES * dpi / px_per_unit, 1.0, 1.35)


static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/nunito-semibold.woff2")
		_font.fallbacks = [ThemeDB.fallback_font]
	return _font


static func font_bold() -> Font:
	if _font_bold == null:
		_font_bold = load("res://assets/fonts/nunito-extrabold.woff2")
		_font_bold.fallbacks = [ThemeDB.fallback_font]
	return _font_bold


static func box(color: Color, radius := 16, pad := 12) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(pad)
	b.anti_aliasing = true
	return b


## Flat translucent box with a hairline border: cards, chips, buttons.
static func pane(color: Color, radius := 16, pad := 12, line := LINE) -> StyleBoxFlat:
	var b := box(color, radius, pad)
	b.border_color = line
	b.set_border_width_all(1)
	return b


## Turns a PanelContainer into frosted glass over whatever is behind it.
static func glass(panel: PanelContainer, radius := 20.0, pad := 12.0, tint := GLASS, blur := 3.0) -> void:
	var gb := GlassBox.new(radius, pad, tint, blur, 0.0 if radius == 0.0 else 0.16) # no hairline on full-screen sheets
	panel.add_theme_stylebox_override("panel", gb)
	gb.attach(panel)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 22

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))

	t.set_font("font", "Button", font_bold())
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT.darkened(0.1))
	t.set_color("font_disabled_color", "Button", Color(TEXT, 0.35))
	# Pill buttons: translucent white with a hairline border.
	t.set_stylebox("normal", "Button", pane(Color(1, 1, 1, 0.10), 22, 14))
	t.set_stylebox("hover", "Button", pane(Color(1, 1, 1, 0.16), 22, 14))
	t.set_stylebox("pressed", "Button", pane(Color(1, 1, 1, 0.05), 22, 14, Color(1, 1, 1, 0.08)))
	t.set_stylebox("disabled", "Button", pane(Color(1, 1, 1, 0.04), 22, 14, Color(1, 1, 1, 0.06)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# Orange button for the main action in a row (Build, Craft, Buy…), with a
	# darker bottom edge for a little depth.
	t.set_type_variation("PrimaryButton", "Button")
	var primary := pane(ACCENT, 22, 14, ACCENT.lightened(0.25))
	primary.border_width_bottom = 3
	primary.border_color = ACCENT.darkened(0.35)
	t.set_stylebox("normal", "PrimaryButton", primary)
	var primary_hover := primary.duplicate()
	primary_hover.bg_color = ACCENT.lightened(0.08)
	t.set_stylebox("hover", "PrimaryButton", primary_hover)
	var primary_down := primary.duplicate()
	primary_down.bg_color = ACCENT.darkened(0.15)
	primary_down.border_width_bottom = 1
	t.set_stylebox("pressed", "PrimaryButton", primary_down)
	t.set_stylebox("disabled", "PrimaryButton", pane(Color(1, 1, 1, 0.04), 22, 14, Color(1, 1, 1, 0.06)))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(state, "PrimaryButton", Color("2a1a08"))

	t.set_stylebox("panel", "PanelContainer", pane(Color(1, 1, 1, 0.06), 24, 20))
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", pane(Color(1, 1, 1, 0.07), 18, 14, Color(1, 1, 1, 0.10)))
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", pane(SHADE, 22, 10))

	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.35), 8, 0))
	t.set_stylebox("fill", "ProgressBar", box(Color.WHITE, 8, 0))

	var line := StyleBoxLine.new()
	line.color = Color(TEXT, 0.08)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)

	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.2), 4, 0))
	t.set_stylebox("grabber", "VScrollBar", box(Color(TEXT, 0.3), 4, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(TEXT, 0.45), 4, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(Color(TEXT, 0.55), 4, 0))
	return t


## Small press animation: the control shrinks while held and pops back.
static func add_press_juice(c: Control) -> void:
	c.resized.connect(func() -> void: c.pivot_offset = c.size / 2.0)
	c.pivot_offset = c.size / 2.0
	if c is BaseButton:
		c.button_down.connect(func() -> void:
			Sfx.play("ui_tap", 0.15)
			c.create_tween().tween_property(c, "scale", Vector2.ONE * 0.9, 0.06))
		c.button_up.connect(func() -> void:
			c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
