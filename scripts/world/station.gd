extends Node2D
## A camp spot: crafting place, storage, house (built and upgraded with
## timers), or the quest board. Interacting opens its panel in the HUD.

var kind := "crafting"
var world: Node2D
var radius := 45.0


func _ready() -> void:
	add_to_group("interactable")
	Game.changed.connect(queue_redraw)


func _process(_delta: float) -> void:
	if kind != "board" and Game.structure_busy(kind):
		queue_redraw()


func is_available() -> bool:
	return true


func title() -> String:
	return "Quest board" if kind == "board" else Data.STRUCTURES[kind]["name"]


func action_label() -> String:
	if kind == "board":
		return "Read quests"
	if Game.structure_tier(kind) == 0 and not Game.structure_busy(kind):
		return "Build %s" % title().to_lower()
	return "Open %s" % title().to_lower()


func interact(_player: Node2D) -> void:
	world.open_station(self)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if kind == "board":
		draw_rect(Rect2(-4, -10, 8, 40), Color(0.4, 0.26, 0.12))
		draw_rect(Rect2(-36, -50, 72, 44), Color(0.6, 0.42, 0.22))
		draw_rect(Rect2(-28, -44, 24, 16), Color(0.95, 0.92, 0.8))
		draw_rect(Rect2(2, -40, 24, 20), Color(0.95, 0.92, 0.8))
		_label(font, "Quests")
		return

	var tier := Game.structure_tier(kind)
	var box := Rect2(-radius, -radius, radius * 2, radius * 2)
	if tier == 0:
		draw_rect(box, Color(1, 1, 1, 0.5), false, 3.0)
	else:
		var colors := {
			"crafting": Color(0.55, 0.36, 0.2),
			"storage": Color(0.45, 0.3, 0.18),
			"house": Color(0.62, 0.4, 0.25),
		}
		var c: Color = colors[kind].lightened(0.08 * (tier - 1))
		draw_rect(box, c)
		if kind == "house":
			draw_colored_polygon(PackedVector2Array([
				Vector2(-radius - 8, -radius), Vector2(radius + 8, -radius), Vector2(0, -radius - 34)]),
				Color(0.5, 0.18, 0.12))
			draw_rect(Rect2(-10, radius - 28, 20, 28), Color(0.3, 0.18, 0.1))
		elif kind == "storage":
			draw_line(Vector2(-radius, 0), Vector2(radius, 0), c.darkened(0.3), 3.0)
		else:
			draw_rect(Rect2(-radius + 8, -12, radius * 2 - 16, 12), c.darkened(0.3))
		for i in tier:
			draw_circle(Vector2(-radius + 10 + i * 14, -radius + 10), 5, Color(1, 0.85, 0.2))

	if Game.structure_busy(kind):
		var s: Dictionary = Game.structures[kind]
		var total: float = Data.STRUCTURES[kind]["tiers"][s["next_tier"] - 1]["time"]
		var done := 1.0 - clampf((s["busy_until"] - Game.now()) / total, 0.0, 1.0)
		draw_rect(Rect2(-radius, radius + 6, radius * 2, 8), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-radius, radius + 6, radius * 2 * done, 8), Color(1, 0.8, 0.2))
	_label(font, title() if tier > 0 else "Build: " + title())


func _label(font: Font, text: String) -> void:
	draw_string(font, Vector2(-110, -radius - 42), text, HORIZONTAL_ALIGNMENT_CENTER, 220, 16, Color.WHITE)
