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
	"fur": Color("d98b4a"), "antler": Color("efe6cf"),
}

static var _font: FontFile
static var _font_bold: FontFile


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
	t.set_stylebox("normal", "Button", box(CARD_HI, 18, 14))
	t.set_stylebox("hover", "Button", box(CARD_HI.lightened(0.08), 18, 14))
	t.set_stylebox("pressed", "Button", box(CARD_HI.darkened(0.2), 18, 14))
	t.set_stylebox("disabled", "Button", box(Color(CARD_HI, 0.45), 18, 14))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# Orange button for the main action in a row (Build, Craft, Buy…).
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(ACCENT, 18, 14))
	t.set_stylebox("hover", "PrimaryButton", box(ACCENT.lightened(0.1), 18, 14))
	t.set_stylebox("pressed", "PrimaryButton", box(ACCENT.darkened(0.2), 18, 14))
	t.set_stylebox("disabled", "PrimaryButton", box(Color(CARD_HI, 0.45), 18, 14))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(state, "PrimaryButton", Color("2a1a08"))

	t.set_stylebox("panel", "PanelContainer", box(BG, 28, 20))
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(CARD, 18, 14))
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", box(SHADE, 22, 10))

	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.35), 6, 0))
	t.set_stylebox("fill", "ProgressBar", box(Color.WHITE, 6, 0))

	var line := StyleBoxLine.new()
	line.color = Color(TEXT, 0.12)
	line.thickness = 2
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
		c.button_down.connect(func() -> void: c.create_tween().tween_property(c, "scale", Vector2.ONE * 0.9, 0.06))
		c.button_up.connect(func() -> void:
			c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
