extends Node3D
## The Great Boar, boss of the demo. Lives in its lair in the east forest.
## When the hunter comes close it paws the ground (wind-up, glows red), then
## charges in a straight line. A charge that connects costs energy and knocks
## the hunter back. After each charge it is dizzy: the moment to strike, for
## double damage. If the hunter leaves, it walks home and slowly heals.

const Shapes := preload("res://scripts/world/shapes.gd")
const Fx := preload("res://scripts/world/fx.gd")
const HIT_COLOR := Color(1, 1, 1)
const RAGE_COLOR := Color(1, 0.15, 0.1, 0.55)

enum State { IDLE, ALERT, WINDUP, CHARGE, DIZZY, DEAD }

var player: Node3D
var world: Node3D
var hp := 0.0
var alive := true
var radius := 1.1 # body size, so weapon reach is measured from its edge

var _state := State.IDLE
var _timer := 0.0
var _charge_dir := Vector2.ZERO
var _charge_hit := false
var _phase := 0.0
var _time := 0.0
var _flash := 0.0
var _home_target := Vector2.ZERO
var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _meshes: Array[MeshInstance3D] = []
var _stars: Label3D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("animal")
	add_to_group("boss")
	hp = Data.BOSS["hp"]
	_build_shape()
	_stars = Shapes.label(self, "✦ ✦ ✦", Vector3(0, Data.BOSS["size"] * 3.0, 0), 40)
	_stars.modulate = Color(1, 0.9, 0.3)
	_stars.visible = false
	_home_target = _lair()
	if Game.boss_defeated:
		alive = false
		visible = false
		_state = State.DEAD


func _lair() -> Vector2:
	return Data.BOSS["lair"]


func _process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_time += delta
	_timer -= delta
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_set_overlay(null)

	var b: Dictionary = Data.BOSS
	var here := Shapes.flat(self)
	var to_player := Shapes.flat(player) - here
	var player_near: bool = to_player.length() < b["aggro_radius"] and not Game.is_sleeping() \
		and _lair().distance_to(Shapes.flat(player)) < b["lair_radius"] * 2.0
	var step := Vector2.ZERO
	var speed := 0.0

	match _state:
		State.IDLE:
			hp = minf(b["hp"], hp + b["regen_per_sec"] * delta)
			if player_near:
				_state = State.ALERT
				_timer = 0.6
			elif here.distance_to(_home_target) > 0.3:
				step = here.direction_to(_home_target) * b["walk_speed"] * delta
				speed = 0.3
			elif _timer <= 0.0:
				_home_target = _lair() + Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))
				_timer = randf_range(2.0, 4.0)
		State.ALERT:
			if not player_near:
				_state = State.IDLE
				_home_target = _lair()
			else:
				_face(to_player, delta)
				if to_player.length() > 2.5:
					step = to_player.normalized() * b["walk_speed"] * delta
					speed = 0.3
				if _timer <= 0.0:
					_state = State.WINDUP
					_timer = b["windup"]
		State.WINDUP:
			_face(to_player, delta)
			# Rage glow pulses faster as the charge gets close.
			var pulse := 0.5 + 0.5 * sin(_time * 30.0)
			_set_overlay(Shapes.material(Color(RAGE_COLOR, RAGE_COLOR.a * pulse)) if _flash <= 0.0 else null)
			if _timer <= 0.0:
				_set_overlay(null)
				_state = State.CHARGE
				_timer = b["charge_time"]
				_charge_dir = to_player.normalized() if to_player.length() > 0.01 else Vector2(0, 1)
				_charge_hit = false
		State.CHARGE:
			step = _charge_dir * b["charge_speed"] * delta
			speed = 1.0
			if not _charge_hit and to_player.length() < b["size"] * 1.6:
				_charge_hit = true
				player.knockback(_charge_dir * b["knockback"])
				Game.on_boss_hit_player()
				world.shake(0.35)
				world.vibrate(120)
			if _timer <= 0.0:
				_state = State.DIZZY
				_timer = b["dizzy"]
				_stars.visible = true
		State.DIZZY:
			_stars.rotation.y = _time * 4.0
			if _timer <= 0.0:
				_stars.visible = false
				_state = State.ALERT if player_near else State.IDLE
				_timer = 1.0

	var area := Rect2(_lair() - Vector2.ONE * b["lair_radius"], Vector2.ONE * b["lair_radius"] * 2.0)
	var next := (here + step).clamp(area.position, area.end)
	if _state == State.CHARGE and next != here + step:
		_timer = 0.0 # hit the edge of the lair: stop the charge
	position = Vector3(next.x, 0, next.y)
	if step != Vector2.ZERO and _state != State.CHARGE:
		_face(step, delta)
	_animate(delta, speed)


func _face(dir: Vector2, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.y), minf(1.0, 8.0 * delta))


func _animate(delta: float, speed: float) -> void:
	var s: float = Data.BOSS["size"]
	if _state == State.WINDUP:
		# Paws the ground with a front leg and lowers the head.
		_legs[0].rotation.x = 0.6 * sin(_time * 18.0)
		_head.rotation.x = lerpf(_head.rotation.x, 0.35, minf(1.0, 10.0 * delta))
		_body.position.y = 0.0
		return
	_phase += delta * (16.0 if speed > 0.5 else 6.0) * float(speed > 0.0)
	var swing := (0.8 if speed > 0.5 else 0.35) * sin(_phase) * float(speed > 0.0)
	_legs[0].rotation.x = swing
	_legs[3].rotation.x = swing
	_legs[1].rotation.x = -swing
	_legs[2].rotation.x = -swing
	_body.position.y = absf(sin(_phase)) * s * (0.15 if speed > 0.5 else 0.03) * float(speed > 0.0)
	var head_down := 0.3 if _state == State.CHARGE else (-0.15 if _state == State.DIZZY else 0.0)
	_head.rotation.x = lerpf(_head.rotation.x, head_down, minf(1.0, 8.0 * delta))
	_body.rotation.z = sin(_time * 5.0) * 0.12 if _state == State.DIZZY else 0.0


func is_available() -> bool:
	return alive


func action_label() -> String:
	return "Fight the %s" % Data.BOSS["name"]


func action_icon() -> String:
	return Game.weapon()


func is_dizzy() -> bool:
	return _state == State.DIZZY


func interact(_player: Node3D) -> void:
	if not Game.try_attack():
		return
	var damage := Game.weapon_damage() * (Data.BOSS["dizzy_damage_mult"] if is_dizzy() else 1)
	hp -= damage
	_flash = 0.12
	_set_overlay(Shapes.material(HIT_COLOR))
	world.fx_hit(self)
	if is_dizzy():
		Fx.float_text(world, global_position + Vector3(0, 2.4, 0), "Critical! -%d" % damage, Color(1, 0.85, 0.3))
	if _state == State.IDLE:
		_state = State.ALERT
		_timer = 0.4
	if hp > 0.0:
		return
	alive = false
	_state = State.DEAD
	_stars.visible = false
	_set_overlay(null)
	Game.on_boss_killed()
	world.fx_kill_boss(self)
	var t := create_tween()
	t.tween_property(_body, "rotation:z", PI / 2.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		Fx.burst(world, global_position + Vector3(0, 0.6, 0), Color(0.85, 0.8, 0.7), 30, 0.18, 3.0, -3.0))
	t.tween_interval(1.4)
	t.tween_property(_body, "scale", Vector3.ONE * 0.01, 0.5)
	t.tween_callback(func() -> void: visible = false)


func _set_overlay(m: Material) -> void:
	for mi in _meshes:
		mi.material_overlay = m


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := Shapes.add(parent, mesh, color, pos, scale)
	_meshes.append(mi)
	return mi


## Built facing +Z like the other animals.
func _build_shape() -> void:
	var s: float = Data.BOSS["size"]
	var c: Color = Data.BOSS["color"]
	_body = _pivot(self, Vector3.ZERO)
	_torso = _pivot(_body, Vector3(0, s * 1.1, 0))
	_mesh(_torso, Shapes.capsule(s * 0.75, s * 2.6), c, Vector3.ZERO, Vector3(1.0, 1.0, 1.0)).rotation_degrees.x = 90
	for i in 6: # bristly mane along the back
		var spike := _mesh(_torso, Shapes.cylinder(s * 0.14, s * 0.55, 0.0), c.darkened(0.4), Vector3(0, s * 0.7, s * (0.7 - i * 0.28)))
		spike.rotation_degrees.x = -20
	for side in [[-1, 1], [1, 1], [-1, -1], [1, -1]]: # FL, FR, BL, BR
		var hip := _pivot(_body, Vector3(side[0] * s * 0.42, s * 0.8, side[1] * s * 0.75))
		_mesh(hip, Shapes.cylinder(s * 0.17, s * 0.8, s * 0.12), c.darkened(0.25), Vector3(0, -s * 0.4, 0))
		_legs.append(hip)
	_head = _pivot(_torso, Vector3(0, s * 0.05, s * 1.25))
	_mesh(_head, Shapes.sphere(s * 0.55), c.lightened(0.05), Vector3(0, 0, s * 0.2), Vector3(1, 0.9, 1.15))
	_mesh(_head, Shapes.cylinder(s * 0.24, s * 0.4, s * 0.28), Color(0.55, 0.38, 0.35), Vector3(0, -s * 0.1, s * 0.75)).rotation_degrees.x = 90
	for x in [-1, 1]:
		_mesh(_head, Shapes.sphere(s * 0.08), Color(0.9, 0.1, 0.05), Vector3(x * s * 0.28, s * 0.2, s * 0.6)) # eyes
		var tusk := _mesh(_head, Shapes.cylinder(s * 0.07, s * 0.55, 0.0), Color(0.97, 0.94, 0.85), Vector3(x * s * 0.3, -s * 0.05, s * 0.85))
		tusk.rotation_degrees = Vector3(-40, 0, x * 20)
		var ear := _mesh(_head, Shapes.cylinder(s * 0.14, s * 0.3, 0.0), c.darkened(0.2), Vector3(x * s * 0.35, s * 0.5, 0))
		ear.rotation_degrees.z = -x * 30
