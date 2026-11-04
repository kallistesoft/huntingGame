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
var _spear_tip: MeshInstance3D
var _bow: Node3D
var _bow_mesh: MeshInstance3D
var _gear: Node3D # worn pieces, rebuilt by _update_gear
var _zzz: Label3D
var _knock := Vector2.ZERO
var _zone := -1 # zone index the hunter stands in, to notice crossings


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
	var down := Game.is_dead()
	if sleeping or down:
		dir = Vector2.ZERO
	if dir != Vector2.ZERO:
		_face(dir)
	var bounds: Rect2 = world.walk_bounds()
	var velocity := dir.limit_length(1.0) * Game.move_speed() + _knock
	_knock = _knock.move_toward(Vector2.ZERO, 14.0 * delta)
	var next := (Shapes.flat(self) + velocity * delta).clamp(bounds.position, bounds.end)
	position = Vector3(next.x, 0, next.y)
	Game.player_position = next
	var zone := Game.zone_at(next)
	if zone != _zone:
		_zone = zone
		if zone > 0:
			Game.on_enter_zone(zone)

	_model.rotation_degrees.x = -90.0 if sleeping or down else 0.0
	_model.position.y = 0.3 if sleeping or down else absf(sin(Time.get_ticks_msec() * 0.012)) * 0.08 * dir.length()
	_zzz.visible = sleeping
	_arm.rotation_degrees.x = -70.0 if _swing > 0.0 else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_SPACE, KEY_E]:
			do_action()


## Pushes the hunter away, e.g. when the boss charge hits.
func knockback(v: Vector2) -> void:
	_knock = v * 3.0
	_face(-v)


func _key(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0


func _face(dir: Vector2) -> void:
	rotation.y = atan2(dir.x, dir.y)


func do_action() -> void:
	if _cooldown > 0.0 or Game.is_sleeping() or Game.is_dead():
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


## The nearest usable thing in reach. Animals are reachable from the weapon's range;
## the boss comes first whenever it is in range.
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
		if "radius" in node:
			gap -= node.radius
		if gap <= reach and node.is_in_group("boss"):
			return node # in a boss fight, never chop a tree by mistake
		if gap <= reach and gap < best_gap:
			best = node
			best_gap = gap
	return best


func _animal_nearby() -> bool:
	for node in get_tree().get_nodes_in_group("animal"):
		if node.is_available() and Shapes.flat(self).distance_to(Shapes.flat(node)) < 2.25:
			return true
	return false


## Rebuilds what the hunter wears from the equipped pieces: weapon in hand,
## hood/helm, tunic/armor, boots and a bag on the back, coloured by tier.
func _update_gear() -> void:
	var w := Game.weapon()
	_spear.visible = w != "" and Data.TOOLS[w]["icon"] == "spear"
	_bow.visible = w != "" and Data.TOOLS[w]["icon"] == "bow"
	if w != "":
		var metal := _tier_metal(Data.TOOLS[w].get("tier", 1))
		_spear_tip.material_override = Shapes.material(metal)
		_bow_mesh.material_override = Shapes.material(Color(0.45, 0.28, 0.12) if Data.TOOLS[w]["tier"] < 3 else metal)
	for child in _gear.get_children():
		child.queue_free()
	var head := Game.equipped("head")
	if head != "":
		var t: int = Data.TOOLS[head]["tier"]
		var c := _tier_cloth(t) if t < 3 else _tier_metal(t)
		Shapes.add(_gear, Shapes.sphere(0.29), c, Vector3(0, 1.62, -0.03), Vector3(1, 0.75, 1))
		if t == 2:
			for x in [-1, 1]:
				Shapes.add(_gear, Shapes.cylinder(0.03, 0.22, 0.0), Color(0.97, 0.94, 0.85), Vector3(x * 0.2, 1.8, 0)).rotation_degrees.z = -x * 35
		elif t == 3:
			Shapes.add(_gear, Shapes.box(Vector3(0.06, 0.12, 0.4)), c.darkened(0.2), Vector3(0, 1.86, -0.03)) # crest
	var body := Game.equipped("body")
	if body != "":
		var t: int = Data.TOOLS[body]["tier"]
		var c := _tier_cloth(t)
		Shapes.add(_gear, Shapes.cylinder(0.32, 0.62), c, Vector3(0, 1.02, 0))
		if t >= 2:
			for x in [-1, 1]:
				Shapes.add(_gear, Shapes.sphere(0.13), c.darkened(0.2), Vector3(x * 0.3, 1.3, 0)) # shoulder pads
		if t >= 3:
			Shapes.add(_gear, Shapes.cylinder(0.3, 0.14), Color(0.6, 0.6, 0.65), Vector3(0, 1.36, 0)) # fur collar
	var feet := Game.equipped("feet")
	if feet != "":
		var c := _tier_cloth(Data.TOOLS[feet]["tier"])
		for x in [-1, 1]:
			Shapes.add(_gear, Shapes.box(Vector3(0.16, 0.22, 0.28)), c, Vector3(x * 0.12, 0.11, 0.04))
	var bag := Game.equipped("bag")
	if bag != "":
		var t: int = Data.TOOLS[bag]["tier"]
		var c := _tier_cloth(t)
		var sz := 0.22 + 0.08 * t
		Shapes.add(_gear, Shapes.box(Vector3(sz, sz * 1.2, 0.18)), c, Vector3(0, 1.0, -0.33))
		Shapes.add(_gear, Shapes.box(Vector3(sz * 1.05, 0.06, 0.2)), c.darkened(0.3), Vector3(0, 1.0 + sz * 0.55, -0.33)) # flap


## Cloth colour by tier: fur, leather, wolf pelt.
static func _tier_cloth(tier: int) -> Color:
	return [Color(0.78, 0.56, 0.33), Color(0.47, 0.3, 0.16), Color(0.5, 0.5, 0.56), Color(0.9, 0.9, 0.95)][clampi(tier, 1, 4) - 1]


## Tool-head colour by tier: stone, bone, iron.
static func _tier_metal(tier: int) -> Color:
	return [Color(0.6, 0.6, 0.62), Color(0.92, 0.88, 0.78), Color(0.55, 0.62, 0.72), Color(0.86, 0.88, 0.93)][clampi(tier, 1, 4) - 1]


## Built facing +Z so rotation.y = atan2(x, z) points it where it walks.
func _build_shape() -> void:
	_model = Node3D.new()
	add_child(_model)
	Shapes.add(_model, Shapes.capsule(0.28, 1.2), SKIN, Vector3(0, 0.75, 0))
	Shapes.add(_model, Shapes.sphere(0.24), SKIN, Vector3(0, 1.55, 0))
	Shapes.add(_model, Shapes.sphere(0.25), Color(0.35, 0.22, 0.12), Vector3(0, 1.65, -0.05), Vector3(1, 0.7, 1))
	Shapes.add(_model, Shapes.cylinder(0.31, 0.25), Color(0.55, 0.42, 0.25), Vector3(0, 0.55, 0)) # loincloth
	_gear = Node3D.new()
	_model.add_child(_gear)
	_arm = Node3D.new()
	_arm.position = Vector3(0.32, 1.15, 0)
	_model.add_child(_arm)
	Shapes.add(_arm, Shapes.capsule(0.08, 0.6), SKIN, Vector3(0, -0.25, 0))
	_spear = Node3D.new()
	_arm.add_child(_spear)
	var shaft := Shapes.add(_spear, Shapes.cylinder(0.03, 1.8), Color(0.5, 0.33, 0.15), Vector3(0, -0.5, 0.3))
	shaft.rotation_degrees.x = 80
	_spear_tip = Shapes.add(_spear, Shapes.cylinder(0.06, 0.2, 0.0), Color(0.6, 0.6, 0.62), Vector3(0, -0.35, 1.2))
	_spear_tip.rotation_degrees.x = 90
	_bow = Node3D.new()
	_arm.add_child(_bow)
	var bow_mesh := TorusMesh.new()
	bow_mesh.inner_radius = 0.38
	bow_mesh.outer_radius = 0.42
	_bow_mesh = Shapes.add(_bow, bow_mesh, Color(0.45, 0.28, 0.12), Vector3(0, -0.5, 0.2), Vector3(1, 1, 0.5))
	_bow_mesh.rotation_degrees.z = 90
	_zzz = Shapes.label(self, "Zzz", Vector3(0, 1.4, 0))
