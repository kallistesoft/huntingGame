extends Button
## Round icon button with a small caption under the icon.

const Icons := preload("res://scripts/ui/icons.gd")
const Style := preload("res://scripts/ui/style.gd")

var icon_name := "menu"
var caption := ""
var icon_color := Color.WHITE


func _ready() -> void:
	custom_minimum_size = Vector2(74, 74)
	var round := Style.box(Style.SHADE, 37, 0)
	add_theme_stylebox_override("normal", round)
	add_theme_stylebox_override("hover", Style.box(Color(Style.SHADE, 0.55), 37, 0))
	add_theme_stylebox_override("pressed", Style.box(Color(0, 0, 0, 0.6), 37, 0))
	Style.add_press_juice(self)


func _draw() -> void:
	Icons.draw(self, icon_name, Vector2(size.x / 2.0, size.y * 0.42), size.y * 0.42, icon_color)
	var f := Style.font_bold()
	draw_string(f, Vector2(0, size.y * 0.86), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Style.TEXT)
