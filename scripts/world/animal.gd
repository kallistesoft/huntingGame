extends Node3D
## A huntable animal. Wanders inside its zone, runs from the hunter when close,
## and stops to rest after running a while, which is the moment to strike.
## Placeholder animation is done in code: rabbits and squirrels hop, deer walk
## and gallop on swinging legs, idle animals sniff and twitch, and a killed
## animal falls over, puffs and fades before it is gone.

const Shapes := preload("res://scripts/world/shapes.gd")
const Fx := preload("res://scripts/world/fx.gd")
const HIT_COLOR := Color(1, 1, 1)
const DEATH_FALL := 0.35
const DEATH_LIE := 0.7
const DEATH_SHRINK := 0.3

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
var _phase := 0.0 # gait cycle
var _time := 0.0
var _sniff_at := 0.0 # time of the next sniff while idle
var _dying := false

# Animated parts (pivots). Legs only exist on deer, ears on rabbits, tail on rabbits/squirrels.
var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _ears: Array[Node3D] = []
var _tail: Node3D
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("animal")
	hp = Data.ANIMALS[kind]["hp"]
	_target = Shapes.flat(self)
	_time = randf() * 10.0
	_build_shape()


func _process(delta: float) -> void:
	if not alive:
		if not _dying and Game.now() >= _respawn_at:
			_respawn()
		return
	_time += delta
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
	var moved := next.distance_to(here)
	position = Vector3(next.x, 0, next.y)
	if step != Vector2.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(step.x, step.y), minf(1.0, 12.0 * delta))
	_animate(delta, moved / delta / d["flee_speed"] if delta > 0.0 else 0.0)


## speed: 0 standing, ~0.25 walking, 1 running flat out.
func _animate(delta: float, speed: float) -> void:
	var s: float = Data.ANIMALS[kind]["size"]
	var moving := speed > 0.02
	var running := speed > 0.5

	if kind == "deer":
		_phase += delta * (13.0 if running else 6.0) * float(moving)
		var swing := (0.75 if running else 0.4) * sin(_phase) * float(moving)
		# Diagonal pairs move together: front-left with back-right.
		_legs[0].rotation.x = swing
		_legs[3].rotation.x = swing
		_legs[1].rotation.x = -swing
		_legs[2].rotation.x = -swing
		_body.position.y = absf(sin(_phase)) * s * (0.25 if running else 0.06) * float(moving)
		_torso.rotation.x = cos(_phase) * (0.08 if running else 0.0) * float(moving)
	else:
		# Hop: up in an arc, squashed on landing, stretched in the air.
		_phase += delta * (15.0 if running else 8.0) * float(moving)
		var arc := absf(sin(_phase)) if moving else 0.0
		_body.position.y = arc * s * (1.3 if running else 0.6)
		var squash := 1.0 - 0.18 * (1.0 - arc) * float(moving)
		_torso.scale = Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))
		_torso.rotation.x = -cos(_phase) * 0.3 * float(moving)

	# Head: dips to sniff now and then while idle, steady while running.
	var sniff := 0.0
	if not moving:
		if _time >= _sniff_at + 1.2:
			_sniff_at = _time + randf_range(1.5, 4.0)
		if _time >= _sniff_at:
			sniff = 0.5 + 0.12 * sin(_time * 22.0)
	_head.rotation.x = lerpf(_head.rotation.x, sniff, minf(1.0, 10.0 * delta))
	_head.rotation.y = sin(_time * 0.9) * 0.35 * float(not moving)

	for i in _ears.size():
		var twitch := 0.25 * sin(_time * 3.0 + i * 1.7) + (0.4 if (int(_time * 1.3 + i) % 5 == 0) else 0.0)
		_ears[i].rotation.x = -0.5 if running else twitch # flat back when running
	if _tail != null:
		_tail.rotation.x = (0.5 if running else 0.0) + sin(_time * (14.0 if moving else 4.0)) * 0.25


func is_available() -> bool:
	return alive


func action_label() -> String:
	return "Hunt %s" % Data.ANIMALS[kind]["name"].to_lower()


func action_icon() -> String:
	return Game.weapon()


func interact(_player: Node3D) -> void:
	if not Game.try_attack():
		return
	hp -= Game.weapon_damage()
	_flash = 0.15
	_set_flash(true)
	world.fx_hit(self)
	if hp > 0:
		Game.notify("Hit! The %s is hurt." % Data.ANIMALS[kind]["name"].to_lower())
		_resting = 0.0
		return
	alive = false
	_respawn_at = Game.now() + Data.ANIMALS[kind]["respawn"]
	Game.on_animal_killed(kind)
	world.fx_kill(self, kind)
	_play_death()


func _play_death() -> void:
	_dying = true
	_set_flash(false)
	var t := create_tween()
	t.tween_property(_body, "rotation:z", PI / 2.0, DEATH_FALL).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_body, "position:y", Data.ANIMALS[kind]["size"] * 0.3, DEATH_FALL)
	t.tween_callback(_puff)
	t.tween_interval(DEATH_LIE)
	t.tween_property(_body, "scale", Vector3.ONE * 0.01, DEATH_SHRINK).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		visible = false
		_dying = false)


func _puff() -> void:
	Fx.burst(self, Vector3(0, Data.ANIMALS[kind]["size"], 0), Color(0.9, 0.88, 0.82), 14, 0.12, 2.2, -2.0)


func _respawn() -> void:
	hp = Data.ANIMALS[kind]["hp"]
	alive = true
	visible = true
	_resting = 0.0
	_fleeing_for = 0.0
	_body.rotation = Vector3.ZERO
	_body.scale = Vector3.ONE
	var p: Vector2 = world.random_point_away_from_camp(zone)
	position = Vector3(p.x, 0, p.y)
	_target = p


func _set_flash(on: bool) -> void:
	for mi in _meshes:
		mi.material_overlay = Shapes.material(HIT_COLOR) if on else null


## A pivot node: children placed relative to it rotate around this point.
func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := Shapes.add(parent, mesh, color, pos, scale)
	_meshes.append(mi)
	return mi


## Built facing +Z, so rotation.y = atan2(x, z) points it along its motion.
func _build_shape() -> void:
	var s: float = Data.ANIMALS[kind]["size"]
	var c: Color = Data.ANIMALS[kind]["color"]
	_body = _pivot(self, Vector3.ZERO)
	if kind == "deer":
		_torso = _pivot(_body, Vector3(0, s * 1.6, 0))
		_mesh(_torso, Shapes.capsule(s * 0.6, s * 2.6), c).rotation_degrees.x = 90
		for side in [[-1, 1], [1, 1], [-1, -1], [1, -1]]: # FL, FR, BL, BR
			var hip := _pivot(_body, Vector3(side[0] * s * 0.35, s * 1.3, side[1] * s * 0.8))
			_mesh(hip, Shapes.cylinder(s * 0.12, s * 1.3, s * 0.08), c.darkened(0.2), Vector3(0, -s * 0.65, 0))
			_legs.append(hip)
		var neck := _pivot(_torso, Vector3(0, s * 0.4, s * 1.0))
		_mesh(neck, Shapes.cylinder(s * 0.2, s * 0.9, s * 0.15), c, Vector3(0, s * 0.35, s * 0.1)).rotation_degrees.x = 25
		_head = _pivot(neck, Vector3(0, s * 0.8, s * 0.25))
		_mesh(_head, Shapes.sphere(s * 0.38), c, Vector3(0, 0, s * 0.15), Vector3(1, 1, 1.4))
		_mesh(_head, Shapes.sphere(s * 0.08), Color(0.1, 0.08, 0.06), Vector3(0, -s * 0.05, s * 0.65))
		for x in [-1, 1]:
			var antler := _mesh(_head, Shapes.cylinder(s * 0.05, s * 1.0, s * 0.02), Color(0.85, 0.8, 0.65), Vector3(x * s * 0.25, s * 0.55, -s * 0.05))
			antler.rotation_degrees.z = -x * 25
			var tine := _mesh(_head, Shapes.cylinder(s * 0.04, s * 0.45, s * 0.02), Color(0.85, 0.8, 0.65), Vector3(x * s * 0.42, s * 0.65, s * 0.15))
			tine.rotation_degrees = Vector3(35, 0, -x * 50)
		return

	_torso = _pivot(_body, Vector3(0, s, 0))
	_mesh(_torso, Shapes.sphere(s), c, Vector3.ZERO, Vector3(0.9, 0.85, 1.2))
	_head = _pivot(_torso, Vector3(0, s * 0.45, s * 0.75))
	_mesh(_head, Shapes.sphere(s * 0.6), c, Vector3(0, s * 0.1, s * 0.25))
	_mesh(_head, Shapes.sphere(s * 0.1), Color(0.1, 0.08, 0.06), Vector3(0, s * 0.05, s * 0.8))
	for x in [-1, 1]:
		_mesh(_head, Shapes.sphere(s * 0.09), Color(0.05, 0.05, 0.05), Vector3(x * s * 0.3, s * 0.25, s * 0.55))
	if kind == "rabbit":
		for x in [-1, 1]:
			var ear := _pivot(_head, Vector3(x * s * 0.2, s * 0.55, s * 0.1))
			_mesh(ear, Shapes.capsule(s * 0.14, s * 1.1), c, Vector3(0, s * 0.5, 0), Vector3(1, 1, 0.6))
			_mesh(ear, Shapes.capsule(s * 0.07, s * 0.8), Color(0.95, 0.75, 0.75), Vector3(0, s * 0.5, s * 0.05), Vector3(1, 1, 0.4))
			ear.rotation_degrees.z = -x * 10
			_ears.append(ear)
		_tail = _pivot(_torso, Vector3(0, s * 0.1, -s * 1.05))
		_mesh(_tail, Shapes.sphere(s * 0.3), Color.WHITE)
	else:
		_tail = _pivot(_torso, Vector3(0, s * 0.2, -s * 0.9))
		_mesh(_tail, Shapes.capsule(s * 0.45, s * 2.2), c.darkened(0.15), Vector3(0, s * 0.9, -s * 0.35)).rotation_degrees.x = -20
