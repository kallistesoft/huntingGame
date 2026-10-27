extends Node3D
## The hunter. Moves with the on-screen joystick or WASD/arrow keys. The action
## button (or Space/E) uses the nearest thing in reach: hunt, gather, drink,
## or open a camp station. The camera never turns, so screen up is world -Z.

const Shapes := preload("res://scripts/world/shapes.gd")
const REACH := 1.25 # gap allowed between the hunter and a target's edge, metres
const ACTION_COOLDOWN := 0.35
const SKIN := Color(0.93, 0.76, 0.6)

var world: Node3D
var move_input := Vector2.ZERO # set by the joystick, length 0..1; y is screen down

var _cooldown := 0.0
var _swing := 0.0
var _model: Node3D
var _arm: Node3D
var _spear: Node3D
var _bow: Node3D
var _zzz: Label3D


func _ready() -> void:
	_build_shape()
	Game.changed.connect(_update_gear)
	_update_gear()


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_swing = maxf(0.0, _swing - delta)

	var dir := move_input
	var keys := Vector2(
		_key(KEY_D, KEY_RIGHT) - _key(KEY_A, KEY_LEFT),
		_key(KEY_S, KEY_DOWN) - _key(KEY_W, KEY_UP))
	if keys != Vector2.ZERO:
		dir = keys.normalized()
	var sleeping := Game.is_sleeping()
	if sleeping:
		dir = Vector2.ZERO
	if dir != Vector2.ZERO:
		_face(dir)
	var bounds: Rect2 = world.walk_bounds()
	var next := (Shapes.flat(self) + dir.limit_length(1.0) * Game.move_speed() * delta).clamp(bounds.position, bounds.end)
	position = Vector3(next.x, 0, next.y)
	Game.player_position = next

	_model.rotation_degrees.x = -90.0 if sleeping else 0.0
	_model.position.y = 0.3 if sleeping else absf(sin(Time.get_ticks_msec() * 0.012)) * 0.08 * dir.length()
	_zzz.visible = sleeping
	_arm.rotation_degrees.x = -70.0 if _swing > 0.0 else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_SPACE, KEY_E]:
			do_action()


func _key(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0


func _face(dir: Vector2) -> void:
	rotation.y = atan2(dir.x, dir.y)


func do_action() -> void:
	if _cooldown > 0.0 or Game.is_sleeping():
		return
	_cooldown = ACTION_COOLDOWN
	var target := find_target()
	if target == null:
		if _animal_nearby() and Game.weapon() == "":
			Game.notify("You need a spear to hunt. Craft one at the crafting place.")
		return
	var to_target := Shapes.flat(target) - Shapes.flat(self)
	if to_target.length() > 0.01:
		_face(to_target)
	_swing = 0.2
	target.interact(self)


## The nearest usable thing in reach. Animals are reachable from the weapon's range.
func find_target() -> Node3D:
	var best: Node3D = null
	var best_gap := INF
	var here := Shapes.flat(self)
	for node in get_tree().get_nodes_in_group("interactable"):
		if not node.is_available():
			continue
		var gap: float = here.distance_to(Shapes.flat(node))
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
		if node.is_available() and Shapes.flat(self).distance_to(Shapes.flat(node)) < 2.25:
			return true
	return false


func _update_gear() -> void:
	var w := Game.weapon()
	_spear.visible = w == "spear"
	_bow.visible = w == "bow"


## Built facing +Z so rotation.y = atan2(x, z) points it where it walks.
func _build_shape() -> void:
	_model = Node3D.new()
	add_child(_model)
	Shapes.add(_model, Shapes.capsule(0.28, 1.2), SKIN, Vector3(0, 0.75, 0))
	Shapes.add(_model, Shapes.sphere(0.24), SKIN, Vector3(0, 1.55, 0))
	Shapes.add(_model, Shapes.sphere(0.25), Color(0.35, 0.22, 0.12), Vector3(0, 1.65, -0.05), Vector3(1, 0.7, 1))
	Shapes.add(_model, Shapes.cylinder(0.31, 0.25), Color(0.55, 0.42, 0.25), Vector3(0, 0.55, 0)) # loincloth
	_arm = Node3D.new()
	_arm.position = Vector3(0.32, 1.15, 0)
	_model.add_child(_arm)
	Shapes.add(_arm, Shapes.capsule(0.08, 0.6), SKIN, Vector3(0, -0.25, 0))
	_spear = Node3D.new()
	_arm.add_child(_spear)
	var shaft := Shapes.add(_spear, Shapes.cylinder(0.03, 1.8), Color(0.5, 0.33, 0.15), Vector3(0, -0.5, 0.3))
	shaft.rotation_degrees.x = 80
	Shapes.add(_spear, Shapes.cylinder(0.06, 0.2, 0.0), Color(0.6, 0.6, 0.62), Vector3(0, -0.35, 1.2)).rotation_degrees.x = 90
	_bow = Node3D.new()
	_arm.add_child(_bow)
	var bow_mesh := TorusMesh.new()
	bow_mesh.inner_radius = 0.38
	bow_mesh.outer_radius = 0.42
	var bow := Shapes.add(_bow, bow_mesh, Color(0.45, 0.28, 0.12), Vector3(0, -0.5, 0.2), Vector3(1, 1, 0.5))
	bow.rotation_degrees.z = 90
	_zzz = Shapes.label(self, "Zzz", Vector3(0, 1.4, 0))
