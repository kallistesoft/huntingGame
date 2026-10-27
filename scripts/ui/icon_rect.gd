extends Control
## Shows one icon from icons.gd, filling the control.

const Icons := preload("res://scripts/ui/icons.gd")

var icon := "xp":
	set(value):
		icon = value
		queue_redraw()
var color := Color.WHITE:
	set(value):
		color = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	Icons.draw(self, icon, size / 2.0, minf(size.x, size.y), color)
