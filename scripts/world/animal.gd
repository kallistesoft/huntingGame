extends Node2D
## A huntable animal. Wanders inside its zone, runs from the hunter when close,
## and stops to rest after running a while, which is the moment to strike.

var kind := "rabbit"
var zone: Rect2
var player: Node2D
var world: Node2D
var hp := 1
var alive := true

var _target := Vector2.ZERO
var _wait := 0.0
var _fleeing_for := 0.0
var _resting := 0.0
var _flash := 0.0
var _respawn_at := 0.0
var _facing := 1.0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("animal")
	hp = Data.ANIMALS[kind]["hp"]
	_target = position


func _process(delta: float) -> void:
	if not alive:
		if Game.now() >= _respawn_at:
			_respawn()
		return
	var d: Dictionary = Data.ANIMALS[kind]
	_flash = maxf(0.0, _flash - delta)
	var away := position - player.position
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
		elif position.distance_to(_target) < 6.0:
			_wait = randf_range(1.0, 3.0)
			_target = (position + Vector2(randf_range(-120, 120), randf_range(-120, 120))).clamp(zone.position, zone.end)
		else:
			step = position.direction_to(_target) * d["wander_speed"] * delta

	if step.x != 0.0:
		_facing = signf(step.x)
	position = (position + step).clamp(zone.position, zone.end)
	queue_redraw()


func is_available() -> bool:
	return alive


func action_label() -> String:
	return "Hunt %s" % Data.ANIMALS[kind]["name"].to_lower()


func interact(_player: Node2D) -> void:
	if not Game.try_attack():
		return
	hp -= Game.weapon_damage()
	_flash = 0.15
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
	position = world.random_point_away_from_camp(zone)
	_target = position


func _draw() -> void:
	var d: Dictionary = Data.ANIMALS[kind]
	var s: float = d["size"]
	var color: Color = Color.WHITE if _flash > 0.0 else d["color"]
	draw_circle(Vector2(0, s * 0.6), s * 0.9, Color(0, 0, 0, 0.18))
	draw_circle(Vector2.ZERO, s, color)
	draw_circle(Vector2(s * 0.9 * _facing, -s * 0.5), s * 0.55, color)
	draw_circle(Vector2(s * 1.15 * _facing, -s * 0.6), 1.8, Color.BLACK)
	match kind:
		"rabbit":
			draw_line(Vector2(s * 0.8 * _facing, -s), Vector2(s * 0.7 * _facing, -s * 2.0), color, 3.0)
			draw_line(Vector2(s * 1.0 * _facing, -s), Vector2(s * 1.1 * _facing, -s * 2.0), color, 3.0)
		"squirrel":
			draw_circle(Vector2(-s * 1.2 * _facing, -s * 0.8), s * 0.8, color.darkened(0.15))
		"deer":
			draw_line(Vector2(s * 0.9 * _facing, -s), Vector2(s * 0.6 * _facing, -s * 1.8), Color(0.85, 0.8, 0.65), 2.5)
			draw_line(Vector2(s * 1.1 * _facing, -s), Vector2(s * 1.4 * _facing, -s * 1.8), Color(0.85, 0.8, 0.65), 2.5)
