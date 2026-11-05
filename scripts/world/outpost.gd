extends Node3D
## One part of a zone outpost: the chest, which opens the camp storage from
## afar, or the campfire, where the hunter can sleep on the ground.

const Shapes := preload("res://scripts/world/shapes.gd")
const Models := preload("res://scripts/world/models.gd")

var part := "chest" # "chest" or "fire"
var world: Node3D
var radius := 0.8
var _flame: Node3D
var _time := 0.0


func _ready() -> void:
	add_to_group("interactable")
	match part:
		"chest" when Models.has("chest"):
			Models.spawn("chest", self, 0.75)
			Shapes.label(self, "Outpost chest", Vector3(0, 1.6, 0), 36)
		"fire" when Models.has("campfire"):
			Models.spawn("campfire", self, 0.6)
			_flame = Node3D.new()
			add_child(_flame)
			Shapes.add(_flame, Shapes.cylinder(0.18, 0.55, 0.0), Color(1.0, 0.55, 0.1), Vector3(0, 0.5, 0))
			Shapes.add(_flame, Shapes.cylinder(0.1, 0.38, 0.0), Color(1.0, 0.9, 0.3), Vector3(0, 0.45, 0))
			Shapes.label(self, "Campfire", Vector3(0, 1.6, 0), 36)
		"chest":
			var wood := Color(0.45, 0.3, 0.18)
			Shapes.add(self, Shapes.box(Vector3(1.1, 0.6, 0.7)), wood, Vector3(0, 0.3, 0))
			Shapes.add(self, Shapes.box(Vector3(1.15, 0.12, 0.75)), wood.darkened(0.3), Vector3(0, 0.64, 0))
			Shapes.add(self, Shapes.box(Vector3(0.12, 0.2, 0.08)), Color(0.75, 0.65, 0.3), Vector3(0, 0.45, 0.38))
			Shapes.label(self, "Outpost chest", Vector3(0, 1.6, 0), 36)
		"fire":
			for i in 8:
				var a := i * TAU / 8.0
				Shapes.add(self, Shapes.sphere(0.16), Color(0.5, 0.5, 0.52), Vector3(cos(a) * 0.55, 0.1, sin(a) * 0.55), Vector3(1.2, 0.7, 1.0))
			for i in 3:
				var log := Shapes.add(self, Shapes.cylinder(0.07, 0.7), Color(0.35, 0.22, 0.1), Vector3(0, 0.1, 0))
				log.rotation_degrees = Vector3(90, i * 60, 0)
			_flame = Node3D.new()
			add_child(_flame)
			Shapes.add(_flame, Shapes.cylinder(0.22, 0.6, 0.0), Color(1.0, 0.55, 0.1), Vector3(0, 0.4, 0))
			Shapes.add(_flame, Shapes.cylinder(0.12, 0.4, 0.0), Color(1.0, 0.9, 0.3), Vector3(0, 0.35, 0))
			Shapes.label(self, "Campfire", Vector3(0, 1.6, 0), 36)


func _process(delta: float) -> void:
	if _flame != null:
		_time += delta
		_flame.scale = Vector3(1.0 + 0.08 * sin(_time * 9.0), 1.0 + 0.15 * sin(_time * 13.0), 1.0 + 0.08 * cos(_time * 11.0))


func is_available() -> bool:
	return true


func action_label() -> String:
	return "Open chest" if part == "chest" else "Rest by the fire"


func action_icon() -> String:
	return "bag" if part == "chest" else "sleep"


func interact(_player: Node3D) -> void:
	if part == "chest":
		world.open_outpost()
	else:
		Game.start_sleep(true)
