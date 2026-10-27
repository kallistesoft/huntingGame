extends Node2D
## The hunter. Moves with the on-screen joystick or WASD/arrow keys. The action
## button (or Space/E) uses the nearest thing in reach: hunt, gather, drink,
## or open a camp station.

const REACH := 50.0 # gap allowed between the hunter and a target's edge
const ACTION_COOLDOWN := 0.35

var world: Node2D
var move_input := Vector2.ZERO # set by the joystick, length 0..1

var _cooldown := 0.0
var _swing := 0.0
var _facing := Vector2.RIGHT


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_swing = maxf(0.0, _swing - delta)

	var dir := move_input
	var keys := Vector2(
		_key(KEY_D, KEY_RIGHT) - _key(KEY_A, KEY_LEFT),
		_key(KEY_S, KEY_DOWN) - _key(KEY_W, KEY_UP))
	if keys != Vector2.ZERO:
		dir = keys.normalized()
	if Game.is_sleeping():
		dir = Vector2.ZERO
	if dir != Vector2.ZERO:
		_facing = dir.normalized()
	position = (position + dir.limit_length(1.0) * Game.move_speed() * delta).clamp(
		world.walk_bounds().position, world.walk_bounds().end)
	Game.player_position = position
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_SPACE, KEY_E]:
			do_action()


func _key(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0


func do_action() -> void:
	if _cooldown > 0.0 or Game.is_sleeping():
		return
	_cooldown = ACTION_COOLDOWN
	var target := find_target()
	if target == null:
		if _animal_nearby() and Game.weapon() == "":
			Game.notify("You need a spear to hunt. Craft one at the crafting place.")
		return
	if not target.global_position.is_equal_approx(global_position):
		_facing = global_position.direction_to(target.global_position)
	_swing = 0.2
	target.interact(self)


## The nearest usable thing in reach. Animals are reachable from the weapon's range.
func find_target() -> Node2D:
	var best: Node2D = null
	var best_gap := INF
	for node in get_tree().get_nodes_in_group("interactable"):
		if not node.is_available():
			continue
		var gap: float = global_position.distance_to(node.global_position)
		var reach := REACH
		if node.is_in_group("animal"):
			if Game.weapon() == "":
				continue
			reach = Game.weapon_range()
		else:
			gap -= node.radius
		if gap <= reach and gap < best_gap:
			best = node
			best_gap = gap
	return best


func _animal_nearby() -> bool:
	for node in get_tree().get_nodes_in_group("animal"):
		if node.is_available() and global_position.distance_to(node.global_position) < 90.0:
			return true
	return false


func _draw() -> void:
	draw_circle(Vector2(0, 14), 12, Color(0, 0, 0, 0.2))
	draw_circle(Vector2.ZERO, 14, Color(0.93, 0.76, 0.6))
	draw_circle(Vector2(0, -4), 8, Color(0.35, 0.22, 0.12)) # hair
	draw_rect(Rect2(-10, 2, 20, 8), Color(0.55, 0.42, 0.25)) # loincloth
	var hand := _facing * 16.0
	var w := Game.weapon()
	if w == "spear":
		var tip := hand + _facing * (34.0 if _swing > 0.0 else 22.0)
		draw_line(hand - _facing * 14.0, tip, Color(0.5, 0.33, 0.15), 3.0)
		draw_circle(tip, 3.0, Color(0.6, 0.6, 0.62))
	elif w == "bow":
		draw_arc(hand, 12.0, _facing.angle() - 1.2, _facing.angle() + 1.2, 10, Color(0.45, 0.28, 0.12), 3.0)
	elif _swing > 0.0:
		draw_circle(hand + _facing * 6.0, 5.0, Color(0.93, 0.76, 0.6))
	if Game.is_sleeping():
		draw_string(ThemeDB.fallback_font, Vector2(10, -20), "Zzz", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
