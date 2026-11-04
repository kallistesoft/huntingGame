extends Node3D
## A tree, rock or berry bush to gather from, or a pond to drink from.
## Gathered-out nodes grow back after Data.RESOURCES[kind].respawn seconds.

const Shapes := preload("res://scripts/world/shapes.gd")

var kind := "tree":
	set(value):
		kind = value
		radius = 1.5 if kind == "pond" else 0.5
var radius := 0.5
var world: Node3D
var remaining := 0
var _regrow_at := 0.0
var _full: Node3D # parts hidden once gathered out
var _empty: Node3D # parts shown once gathered out
var _fade := 0.0 # 0 solid .. 1 see-through, when standing between the camera and the hunter
var _fade_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("interactable")
	_full = Node3D.new()
	_empty = Node3D.new()
	add_child(_full)
	add_child(_empty)
	_build_shape()
	if kind != "pond":
		remaining = Data.RESOURCES[kind]["amount"]
	for child in _full.get_children():
		if child is MeshInstance3D:
			_fade_meshes.append(child)
	_refresh()


func _process(delta: float) -> void:
	if kind != "pond" and remaining <= 0 and Game.now() >= _regrow_at:
		remaining = Data.RESOURCES[kind]["amount"]
		_refresh()
	if kind == "tree" or kind == "grass":
		_update_fade(delta)


## Trees and tall grass between the camera and the hunter go see-through so
## they don't hide them. The camera sits above and behind (+z), so what is
## in the way is a bit in front of the hunter on the screen.
func _update_fade(delta: float) -> void:
	var hunter := Shapes.flat(world.player)
	var here := Shapes.flat(self)
	var dz := here.y - hunter.y
	var blocking := dz > 0.5 and dz < 7.0 and absf(here.x - hunter.x) < 2.5
	var target := 0.75 if blocking else 0.0
	if absf(target - _fade) < 0.01:
		return
	_fade = lerpf(_fade, target, minf(1.0, 8.0 * delta))
	for m in _fade_meshes:
		m.transparency = _fade


func fade_amount() -> float:
	return _fade


func is_available() -> bool:
	return kind == "pond" or remaining > 0


func action_label() -> String:
	match kind:
		"pond": return "Drink"
		"tree": return "Chop"
		"rock", "iron_rock", "silver_rock": return "Mine"
		"grass": return "Cut grass"
		"herb": return "Pick herbs"
		_: return "Pick berries"


func action_icon() -> String:
	match kind:
		"pond": return "water"
		"tree": return "axe"
		"rock", "iron_rock", "silver_rock": return "pick"
		"grass": return "grass"
		"herb": return "herb"
		_: return "berries"


func interact(_player: Node3D) -> void:
	if kind == "pond":
		Game.drink()
		world.fx_drink(self)
		return
	var got := Game.gather(kind, remaining)
	if got <= 0:
		return
	remaining -= got
	world.fx_gather(self, Data.RESOURCES[kind]["item"], got, Game.xp_with_boost(Data.RESOURCES[kind]["xp"]))
	if remaining <= 0:
		_regrow_at = Game.now() + Data.RESOURCES[kind]["respawn"]
	_refresh()
	# A little shake so each hit is visible.
	var tween := create_tween()
	tween.tween_property(_full, "rotation_degrees:z", 6.0, 0.05)
	tween.tween_property(_full, "rotation_degrees:z", 0.0, 0.1)


func _refresh() -> void:
	var empty := kind != "pond" and remaining <= 0
	_full.visible = not empty
	_empty.visible = empty


func _build_shape() -> void:
	match kind:
		"pond":
			var water := Shapes.add(_full, Shapes.cylinder(radius, 0.06), Color.WHITE, Vector3(0, 0.03, 0))
			water.material_override = Shapes.water_material(radius)
			for i in 10: # stones around the edge
				var a := i * TAU / 10.0 + 0.3
				Shapes.add(_full, Shapes.sphere(0.18), Color(0.55, 0.55, 0.57),
					Vector3(cos(a) * (radius + 0.05), 0.05, sin(a) * (radius + 0.05)), Vector3(1.2, 0.6, 1.0))
		"tree":
			var trunk := Color(0.4, 0.26, 0.12)
			Shapes.add(_full, Shapes.cylinder(0.18, 1.6, 0.14), trunk, Vector3(0, 0.8, 0))
			var low := Shapes.add(_full, Shapes.cylinder(0.9, 1.8, 0.0), Color.WHITE, Vector3(0, 2.2, 0))
			low.material_override = Shapes.sway_material(Color(0.16, 0.42, 0.16), 0.02)
			var high := Shapes.add(_full, Shapes.cylinder(0.7, 1.4, 0.0), Color.WHITE, Vector3(0, 3.0, 0))
			high.material_override = Shapes.sway_material(Color(0.2, 0.5, 0.2), 0.02)
			Shapes.add(_empty, Shapes.cylinder(0.2, 0.3), trunk, Vector3(0, 0.15, 0))
		"rock":
			var grey := Color(0.5, 0.5, 0.52)
			Shapes.add(_full, Shapes.sphere(0.5), grey, Vector3(0, 0.25, 0), Vector3(1.2, 0.8, 1.0))
			Shapes.add(_full, Shapes.sphere(0.3), grey.lightened(0.15), Vector3(0.35, 0.2, 0.2))
			Shapes.add(_empty, Shapes.sphere(0.18), grey, Vector3(0, 0.1, 0), Vector3(1, 0.6, 1))
		"iron_rock":
			var grey := Color(0.42, 0.4, 0.42)
			Shapes.add(_full, Shapes.sphere(0.55), grey, Vector3(0, 0.28, 0), Vector3(1.25, 0.85, 1.05))
			Shapes.add(_full, Shapes.sphere(0.28), grey.lightened(0.1), Vector3(-0.4, 0.2, 0.25))
			for v in [Vector3(0.2, 0.45, 0.35), Vector3(-0.15, 0.55, -0.3), Vector3(0.45, 0.25, -0.1)]:
				Shapes.add(_full, Shapes.sphere(0.12), Color(0.75, 0.45, 0.28), v, Vector3(1.4, 0.6, 1.0)) # rusty veins
			Shapes.add(_empty, Shapes.sphere(0.2), grey, Vector3(0, 0.1, 0), Vector3(1, 0.6, 1))
		"silver_rock":
			var pale := Color(0.6, 0.62, 0.66)
			Shapes.add(_full, Shapes.sphere(0.55), pale, Vector3(0, 0.28, 0), Vector3(1.2, 0.9, 1.1))
			Shapes.add(_full, Shapes.sphere(0.3), pale.darkened(0.1), Vector3(0.4, 0.18, -0.2))
			for v in [Vector3(-0.2, 0.5, 0.3), Vector3(0.25, 0.55, -0.25), Vector3(-0.4, 0.3, -0.1)]:
				Shapes.add(_full, Shapes.sphere(0.11), Color(0.93, 0.95, 1.0), v, Vector3(1.5, 0.5, 1.0)) # bright veins
			Shapes.add(_empty, Shapes.sphere(0.2), pale, Vector3(0, 0.1, 0), Vector3(1, 0.6, 1))
		"herb":
			var leaf := Color(0.35, 0.62, 0.35)
			for i in 5:
				var a := i * TAU / 5.0
				var l := Shapes.add(_full, Shapes.sphere(0.14), Color.WHITE, Vector3(cos(a) * 0.2, 0.22, sin(a) * 0.2), Vector3(1.0, 0.4, 1.6))
				l.material_override = Shapes.sway_material(leaf, 0.08)
				l.rotation.y = -a
			for q in [Vector3(0.08, 0.45, 0.05), Vector3(-0.1, 0.5, -0.06), Vector3(0.0, 0.55, 0.1)]:
				Shapes.add(_full, Shapes.sphere(0.06), Color(0.98, 0.98, 0.9), q)
			Shapes.add(_empty, Shapes.sphere(0.14), leaf.darkened(0.3), Vector3(0, 0.08, 0), Vector3(1, 0.5, 1))
		"grass":
			var blade := Color(0.55, 0.68, 0.3)
			for i in 7:
				var a := i * TAU / 7.0
				var b := Shapes.add(_full, Shapes.cylinder(0.05, 1.1, 0.0), Color.WHITE, Vector3(cos(a) * 0.22, 0.55, sin(a) * 0.22))
				b.material_override = Shapes.sway_material(blade.lightened(0.1 * (i % 3)), 0.12)
				b.rotation_degrees = Vector3(cos(a) * 14, 0, -sin(a) * 14)
			Shapes.add(_empty, Shapes.cylinder(0.3, 0.12), blade.darkened(0.35), Vector3(0, 0.06, 0))
		"bush":
			var leaves := Color(0.2, 0.5, 0.22)
			Shapes.add(_full, Shapes.sphere(0.5), Color.WHITE, Vector3(0, 0.4, 0)).material_override = Shapes.sway_material(leaves, 0.05)
			for p in [Vector3(0.3, 0.6, 0.3), Vector3(-0.35, 0.5, 0.2), Vector3(0.1, 0.8, -0.3), Vector3(-0.1, 0.45, 0.45)]:
				Shapes.add(_full, Shapes.sphere(0.08), Color(0.85, 0.1, 0.2), p)
			Shapes.add(_empty, Shapes.sphere(0.45), leaves.darkened(0.2), Vector3(0, 0.35, 0))
