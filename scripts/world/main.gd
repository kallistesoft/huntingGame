extends Node3D
## Builds the 3D world in code: zone 1 (camp, small animals), zone 2 (east
## forest, opens at Data.ZONE2_LEVEL), the hunter, the camera and the UI.
## Map rectangles are on the ground plane: Rect2 x = world x, Rect2 y = world z.

const ZONE1 := Rect2(0, 0, 45, 32.5)
const ZONE2 := Rect2(45, 0, 40, 32.5)
const CAMP := Rect2(5.5, 11, 13, 10.5)
const PLAYER_START := Vector2(12, 16.5)
const WORLD_SEED := 7
const CAMERA_OFFSET := Vector3(0, 13, 9) # above and behind the hunter
const CAMERA_FOLLOW := 6.0

const Shapes := preload("res://scripts/world/shapes.gd")
const Ground := preload("res://scripts/world/ground.gd")
const Player := preload("res://scripts/world/player.gd")
const ResourceNode := preload("res://scripts/world/resource_node.gd")
const Animal := preload("res://scripts/world/animal.gd")
const Station := preload("res://scripts/world/station.gd")
const Hud := preload("res://scripts/ui/hud.gd")

var player: Node3D
var hud: Control
var camera: Camera3D
var _rng := RandomNumberGenerator.new()
var _taken: Array[Vector3] = [] # x, z, radius of placed props, to keep them apart


func _ready() -> void:
	_rng.seed = WORLD_SEED
	_add_environment()

	var ground := Ground.new()
	ground.zone1 = ZONE1
	ground.zone2 = ZONE2
	ground.camp = CAMP
	add_child(ground)

	player = Player.new()
	player.world = self
	var start := Game.player_position if Game.has_player_position else PLAYER_START
	if not walk_bounds().has_point(start):
		start = PLAYER_START
	player.position = Vector3(start.x, 0, start.y)
	add_child(player)

	camera = Camera3D.new()
	camera.fov = 50
	add_child(camera)
	_place_camera(1.0)

	_add_station("crafting", CAMP.position + Vector2(2.75, 2.75))
	_add_station("storage", CAMP.position + Vector2(7.5, 2.75))
	_add_station("house", CAMP.position + Vector2(2.75, 7.75))
	_add_station("board", CAMP.position + Vector2(10, 7.75))

	_add_prop("pond", Vector2(34, 7.5))
	_add_prop("pond", Vector2(67, 24))

	_scatter("tree", ZONE1, 30)
	_scatter("rock", ZONE1, 14)
	_scatter("bush", ZONE1, 12)
	_scatter("tree", ZONE2, 40)
	_scatter("rock", ZONE2, 20)
	_scatter("bush", ZONE2, 10)

	_spawn_animals("rabbit", ZONE1, 6)
	_spawn_animals("squirrel", ZONE1, 5)
	_spawn_animals("rabbit", ZONE2, 4)
	_spawn_animals("squirrel", ZONE2, 3)
	_spawn_animals("deer", ZONE2, 4)

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.player = player
	ui.add_child(hud)


func _process(delta: float) -> void:
	_place_camera(minf(1.0, CAMERA_FOLLOW * delta))


func _place_camera(weight: float) -> void:
	camera.position = camera.position.lerp(player.position + CAMERA_OFFSET, weight)
	camera.look_at(camera.position - CAMERA_OFFSET)


func _add_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.45
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)


## Where the hunter may walk: zone 1, plus zone 2 once unlocked.
func walk_bounds() -> Rect2:
	var bounds := ZONE1.grow(-0.5)
	if Game.zone2_unlocked():
		bounds = ZONE1.merge(ZONE2).grow(-0.5)
	return bounds


func open_station(station: Node3D) -> void:
	hud.open_station(station.kind)


func _add_station(kind: String, pos: Vector2) -> void:
	var s := Station.new()
	s.kind = kind
	s.position = Vector3(pos.x, 0, pos.y)
	s.world = self
	add_child(s)


func _add_prop(kind: String, pos: Vector2) -> void:
	var r := ResourceNode.new()
	r.kind = kind
	r.position = Vector3(pos.x, 0, pos.y)
	add_child(r)
	_taken.append(Vector3(pos.x, pos.y, r.radius))


func _scatter(kind: String, zone: Rect2, count: int) -> void:
	for i in count:
		var pos := _free_spot(zone.grow(-1.5), 1.0)
		if pos != Vector2.INF:
			_add_prop(kind, pos)


func _free_spot(area: Rect2, radius: float) -> Vector2:
	for attempt in 40:
		var p := Vector2(
			_rng.randf_range(area.position.x, area.end.x),
			_rng.randf_range(area.position.y, area.end.y))
		if CAMP.grow(1.0).has_point(p):
			continue
		var ok := true
		for t in _taken:
			if Vector2(t.x, t.y).distance_to(p) < t.z + radius + 0.5:
				ok = false
				break
		if ok:
			return p
	return Vector2.INF


func _spawn_animals(kind: String, zone: Rect2, count: int) -> void:
	for i in count:
		var a := Animal.new()
		a.kind = kind
		a.zone = zone.grow(-0.75)
		a.player = player
		a.world = self
		var p := random_point_away_from_camp(a.zone)
		a.position = Vector3(p.x, 0, p.y)
		add_child(a)


func random_point_away_from_camp(area: Rect2) -> Vector2:
	for attempt in 20:
		var p := Vector2(
			randf_range(area.position.x, area.end.x),
			randf_range(area.position.y, area.end.y))
		if not CAMP.grow(1.5).has_point(p) and p.distance_to(Shapes.flat(player)) > 7.5:
			return p
	return area.get_center()
