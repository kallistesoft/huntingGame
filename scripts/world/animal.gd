extends Node3D
## A huntable animal. Wanders inside its zone, runs from the hunter when close,
## and stops to rest after running a while, which is the moment to strike.

const Shapes := preload("res://scripts/world/shapes.gd")
const HIT_COLOR := Color(1, 1, 1)

var kind := "rabbit"
var zone: Rect2 # on the ground plane (x, z)
var player: Node3D
var world: Node3D
var hp := 1
var alive := true

var _target := Vector2.ZERO
var _wait := 0.0
var _fleeing_for := 0.0
var _resting := 0.0
var _flash := 0.0
var _respawn_at := 0.0
var _hop := 0.0
var _body: Node3D
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("animal")
	hp = Data.ANIMALS[kind]["hp"]
	_target = Shapes.flat(self)
	_build_shape()


func _process(delta: float) -> void:
	if not alive:
		if Game.now() >= _respawn_at:
			_respawn()
		return
	var d: Dictionary = Data.ANIMALS[kind]
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_set_flash(false)
	var here := Shapes.flat(self)
	var away := here - Shapes.flat(player)
	var step := Vector2.ZERO

	if _resting > 0.0:
		_resting -= delta
	elif away.length() < d["flee_radius"]:
		_fleeing_for += delta
		if _fleeing_for >= Data.FLEE_STAMINA:
			_fleeing_for = 0.0
			_resting = Data.FLEE_REST
		step = away.normalized() * d["flee_speed"] * delta
	else:
		_fleeing_for = maxf(0.0, _fleeing_for - delta)
		if _wait > 0.0:
			_wait -= delta
		elif here.distance_to(_target) < 0.15:
			_wait = randf_range(1.0, 3.0)
			_target = (here + Vector2(randf_range(-3, 3), randf_range(-3, 3))).clamp(zone.position, zone.end)
		else:
			step = here.direction_to(_target) * d["wander_speed"] * delta

	var next := (here + step).clamp(zone.position, zone.end)
	position = Vector3(next.x, 0, next.y)
	if step != Vector2.ZERO:
		rotation.y = atan2(step.x, step.y)
		_hop += delta * (14.0 if step.length() > d["wander_speed"] * delta * 1.5 else 8.0)
		_body.position.y = absf(sin(_hop)) * d["size"] * 0.6
	else:
		_body.position.y = 0.0


func is_available() -> bool:
	return alive


func action_label() -> String:
	return "Hunt %s" % Data.ANIMALS[kind]["name"].to_lower()


func interact(_player: Node3D) -> void:
	if not Game.try_attack():
		return
	hp -= Game.weapon_damage()
	_flash = 0.15
	_set_flash(true)
	if hp > 0:
		Game.notify("Hit! The %s is hurt." % Data.ANIMALS[kind]["name"].to_lower())
		return
	alive = false
	visible = false
	_respawn_at = Game.now() + Data.ANIMALS[kind]["respawn"]
	Game.on_animal_killed(kind)


func _respawn() -> void:
	hp = Data.ANIMALS[kind]["hp"]
	alive = true
	visible = true
	_resting = 0.0
	_fleeing_for = 0.0
	var p: Vector2 = world.random_point_away_from_camp(zone)
	position = Vector3(p.x, 0, p.y)
	_target = p


func _set_flash(on: bool) -> void:
	for mi in _meshes:
		mi.material_overlay = Shapes.material(HIT_COLOR) if on else null


## Built facing +Z, so rotation.y = atan2(x, z) points it along its motion.
func _build_shape() -> void:
	var d: Dictionary = Data.ANIMALS[kind]
	var s: float = d["size"]
	var c: Color = d["color"]
	_body = Node3D.new()
	add_child(_body)
	var parts := []
	match kind:
		"deer":
			parts.append(Shapes.add(_body, Shapes.capsule(s * 0.6, s * 2.6), c, Vector3(0, s * 1.6, 0), Vector3.ONE))
			parts[-1].rotation_degrees.x = 90
			for x in [-1, 1]:
				for z in [-1, 1]:
					parts.append(Shapes.add(_body, Shapes.cylinder(s * 0.12, s * 1.2), c.darkened(0.2), Vector3(x * s * 0.35, s * 0.6, z * s * 0.8)))
			parts.append(Shapes.add(_body, Shapes.sphere(s * 0.45), c, Vector3(0, s * 2.4, s * 1.2)))
			for x in [-1, 1]:
				var antler := Shapes.add(_body, Shapes.cylinder(s * 0.06, s * 1.0), Color(0.85, 0.8, 0.65), Vector3(x * s * 0.25, s * 3.0, s * 1.1))
				antler.rotation_degrees.z = -x * 25
				parts.append(antler)
		_:
			parts.append(Shapes.add(_body, Shapes.sphere(s), c, Vector3(0, s, 0), Vector3(0.9, 0.85, 1.2)))
			parts.append(Shapes.add(_body, Shapes.sphere(s * 0.6), c, Vector3(0, s * 1.5, s * 0.9)))
			if kind == "rabbit":
				for x in [-1, 1]:
					parts.append(Shapes.add(_body, Shapes.capsule(s * 0.15, s * 1.1), c, Vector3(x * s * 0.2, s * 2.3, s * 0.8)))
				parts.append(Shapes.add(_body, Shapes.sphere(s * 0.3), Color.WHITE, Vector3(0, s * 1.1, -s * 1.1)))
			else:
				var tail := Shapes.add(_body, Shapes.capsule(s * 0.45, s * 2.2), c.darkened(0.15), Vector3(0, s * 1.6, -s * 1.1))
				tail.rotation_degrees.x = -25
				parts.append(tail)
	for p in parts:
		_meshes.append(p)
