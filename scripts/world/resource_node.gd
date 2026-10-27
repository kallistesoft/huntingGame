extends Node2D
## A tree, rock or berry bush to gather from, or a pond to drink from.
## Gathered-out nodes grow back after Data.RESOURCES[kind].respawn seconds.

var kind := "tree":
	set(value):
		kind = value
		radius = 60.0 if kind == "pond" else 20.0
var radius := 20.0
var remaining := 0
var _regrow_at := 0.0


func _ready() -> void:
	add_to_group("interactable")
	if kind != "pond":
		remaining = Data.RESOURCES[kind]["amount"]


func _process(_delta: float) -> void:
	if kind != "pond" and remaining <= 0 and Game.now() >= _regrow_at:
		remaining = Data.RESOURCES[kind]["amount"]
		queue_redraw()


func is_available() -> bool:
	return kind == "pond" or remaining > 0


func action_label() -> String:
	match kind:
		"pond": return "Drink"
		"tree": return "Chop"
		"rock": return "Mine"
		_: return "Pick berries"


func interact(_player: Node2D) -> void:
	if kind == "pond":
		Game.drink()
		return
	var got := Game.gather(kind, remaining)
	if got <= 0:
		return
	remaining -= got
	if remaining <= 0:
		_regrow_at = Game.now() + Data.RESOURCES[kind]["respawn"]
	queue_redraw()


func _draw() -> void:
	var empty := remaining <= 0
	match kind:
		"pond":
			draw_circle(Vector2.ZERO, radius, Color(0.25, 0.5, 0.85))
			draw_circle(Vector2(-15, -12), radius * 0.35, Color(0.45, 0.68, 0.95))
		"tree":
			draw_rect(Rect2(-5, -6, 10, 18), Color(0.4, 0.26, 0.12))
			if not empty:
				draw_circle(Vector2(0, -22), 24, Color(0.16, 0.42, 0.16))
				draw_circle(Vector2(-8, -28), 12, Color(0.22, 0.52, 0.2))
		"rock":
			var r := 8.0 if empty else radius
			draw_circle(Vector2.ZERO, r, Color(0.5, 0.5, 0.52))
			draw_circle(Vector2(-r * 0.3, -r * 0.3), r * 0.4, Color(0.65, 0.65, 0.67))
		"bush":
			draw_circle(Vector2.ZERO, radius, Color(0.2, 0.5, 0.22))
			if not empty:
				for p in [Vector2(-8, -5), Vector2(6, -8), Vector2(2, 6), Vector2(-4, 9)]:
					draw_circle(p, 3.5, Color(0.8, 0.1, 0.2))
