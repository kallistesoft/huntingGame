extends Node2D
## Builds the world in code: zone 1 (camp, small animals), zone 2 (east forest,
## opens at Data.ZONE2_LEVEL), the hunter, and the UI.

const ZONE1 := Rect2(0, 0, 1800, 1300)
const ZONE2 := Rect2(1800, 0, 1600, 1300)
const CAMP := Rect2(220, 440, 520, 420)
const PLAYER_START := Vector2(480, 660)
const WORLD_SEED := 7

const Ground := preload("res://scripts/world/ground.gd")
const Player := preload("res://scripts/world/player.gd")
const ResourceNode := preload("res://scripts/world/resource_node.gd")
const Animal := preload("res://scripts/world/animal.gd")
const Station := preload("res://scripts/world/station.gd")
const Hud := preload("res://scripts/ui/hud.gd")

var player: Node2D
var hud: Control
var _rng := RandomNumberGenerator.new()
var _taken: Array[Vector3] = [] # x, y, radius of placed props, to keep them apart


func _ready() -> void:
	_rng.seed = WORLD_SEED

	var ground := Ground.new()
	ground.zone1 = ZONE1
	ground.zone2 = ZONE2
	ground.camp = CAMP
	add_child(ground)

	var entities := Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)

	player = Player.new()
	player.world = self
	player.position = Game.player_position if Game.has_player_position else PLAYER_START
	if not walk_bounds().has_point(player.position):
		player.position = PLAYER_START
	entities.add_child(player)
	var camera := Camera2D.new()
	camera.limit_left = int(ZONE1.position.x)
	camera.limit_top = int(ZONE1.position.y)
	camera.limit_right = int(ZONE2.end.x)
	camera.limit_bottom = int(ZONE1.end.y)
	camera.position_smoothing_enabled = true
	player.add_child(camera)

	_add_station(entities, "crafting", CAMP.position + Vector2(110, 110))
	_add_station(entities, "storage", CAMP.position + Vector2(300, 110))
	_add_station(entities, "house", CAMP.position + Vector2(110, 310))
	_add_station(entities, "board", CAMP.position + Vector2(400, 310))

	_add_prop(entities, "pond", Vector2(1350, 300))
	_add_prop(entities, "pond", Vector2(2700, 950))

	_scatter(entities, "tree", ZONE1, 30)
	_scatter(entities, "rock", ZONE1, 14)
	_scatter(entities, "bush", ZONE1, 12)
	_scatter(entities, "tree", ZONE2, 40)
	_scatter(entities, "rock", ZONE2, 20)
	_scatter(entities, "bush", ZONE2, 10)

	_spawn_animals(entities, "rabbit", ZONE1, 6)
	_spawn_animals(entities, "squirrel", ZONE1, 5)
	_spawn_animals(entities, "rabbit", ZONE2, 4)
	_spawn_animals(entities, "squirrel", ZONE2, 3)
	_spawn_animals(entities, "deer", ZONE2, 4)

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.player = player
	ui.add_child(hud)


## Where the hunter may walk: zone 1, plus zone 2 once unlocked.
func walk_bounds() -> Rect2:
	var bounds := ZONE1.grow(-20)
	if Game.zone2_unlocked():
		bounds = ZONE1.merge(ZONE2).grow(-20)
	return bounds


func open_station(station: Node2D) -> void:
	hud.open_station(station.kind)


func _add_station(parent: Node, kind: String, pos: Vector2) -> void:
	var s := Station.new()
	s.kind = kind
	s.position = pos
	s.world = self
	parent.add_child(s)


func _add_prop(parent: Node, kind: String, pos: Vector2) -> void:
	var r := ResourceNode.new()
	r.kind = kind
	r.position = pos
	parent.add_child(r)
	_taken.append(Vector3(pos.x, pos.y, r.radius))


func _scatter(parent: Node, kind: String, zone: Rect2, count: int) -> void:
	for i in count:
		var pos := _free_spot(zone.grow(-60), 40.0)
		if pos != Vector2.INF:
			_add_prop(parent, kind, pos)


func _free_spot(area: Rect2, radius: float) -> Vector2:
	for attempt in 40:
		var p := Vector2(
			_rng.randf_range(area.position.x, area.end.x),
			_rng.randf_range(area.position.y, area.end.y))
		if CAMP.grow(40).has_point(p):
			continue
		var ok := true
		for t in _taken:
			if Vector2(t.x, t.y).distance_to(p) < t.z + radius + 20.0:
				ok = false
				break
		if ok:
			return p
	return Vector2.INF


func _spawn_animals(parent: Node, kind: String, zone: Rect2, count: int) -> void:
	for i in count:
		var a := Animal.new()
		a.kind = kind
		a.zone = zone.grow(-30)
		a.player = player
		a.world = self
		a.position = random_point_away_from_camp(a.zone)
		parent.add_child(a)


func random_point_away_from_camp(area: Rect2) -> Vector2:
	for attempt in 20:
		var p := Vector2(
			randf_range(area.position.x, area.end.x),
			randf_range(area.position.y, area.end.y))
		if not CAMP.grow(60).has_point(p) and p.distance_to(player.position) > 300.0:
			return p
	return area.get_center()
