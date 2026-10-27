extends Node2D
## Placeholder ground: grass for each zone, the camp clearing, and the fence
## that closes the east forest until it is unlocked.

var zone1: Rect2
var zone2: Rect2
var camp: Rect2


func _ready() -> void:
	z_index = -10
	Game.leveled_up.connect(func(_level: int) -> void: queue_redraw())


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(zone1, Color(0.45, 0.62, 0.32))
	draw_rect(zone2, Color(0.27, 0.45, 0.25))
	draw_rect(camp, Color(0.62, 0.52, 0.36))
	draw_string(font, Vector2(camp.position.x + 12, camp.end.y - 12), "CAMP", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.6))
	draw_string(font, zone2.position + Vector2(40, 60), "EAST FOREST", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.5))

	if not Game.zone2_unlocked():
		var x := zone2.position.x
		draw_line(Vector2(x, zone2.position.y), Vector2(x, zone2.end.y), Color(0.4, 0.25, 0.1), 8.0)
		for y in range(int(zone2.position.y) + 20, int(zone2.end.y), 60):
			draw_rect(Rect2(x - 8, y, 16, 34), Color(0.5, 0.32, 0.14))
		draw_string(font, Vector2(x - 260, zone2.get_center().y), "Reach level %d to cross" % Data.ZONE2_LEVEL,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.85))
