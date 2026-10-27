extends Node3D
## A tree, rock or berry bush to gather from, or a pond to drink from.
## Gathered-out nodes grow back after Data.RESOURCES[kind].respawn seconds.

const Shapes := preload("res://scripts/world/shapes.gd")

var kind := "tree":
	set(value):
		kind = value
		radius = 1.5 if kind == "pond" else 0.5
var radius := 0.5
var remaining := 0
var _regrow_at := 0.0
var _full: Node3D # parts hidden once gathered out
var _empty: Node3D # parts shown once gathered out


func _ready() -> void:
	add_to_group("interactable")
	_full = Node3D.new()
	_empty = Node3D.new()
	add_child(_full)
	add_child(_empty)
	_build_shape()
	if kind != "pond":
		remaining = Data.RESOURCES[kind]["amount"]
	_refresh()


func _process(_delta: float) -> void:
	if kind != "pond" and remaining <= 0 and Game.now() >= _regrow_at:
		remaining = Data.RESOURCES[kind]["amount"]
		_refresh()


func is_available() -> bool:
	return kind == "pond" or remaining > 0


func action_label() -> String:
	match kind:
		"pond": return "Drink"
		"tree": return "Chop"
		"rock": return "Mine"
		_: return "Pick berries"


func interact(_player: Node3D) -> void:
	if kind == "pond":
		Game.drink()
		return
	var got := Game.gather(kind, remaining)
	if got <= 0:
		return
	remaining -= got
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
			Shapes.add(_full, Shapes.cylinder(radius, 0.06), Color(0.25, 0.5, 0.85), Vector3(0, 0.03, 0))
		"tree":
			var trunk := Color(0.4, 0.26, 0.12)
			Shapes.add(_full, Shapes.cylinder(0.18, 1.6, 0.14), trunk, Vector3(0, 0.8, 0))
			Shapes.add(_full, Shapes.cylinder(0.9, 1.8, 0.0), Color(0.16, 0.42, 0.16), Vector3(0, 2.2, 0))
			Shapes.add(_full, Shapes.cylinder(0.7, 1.4, 0.0), Color(0.2, 0.5, 0.2), Vector3(0, 3.0, 0))
			Shapes.add(_empty, Shapes.cylinder(0.2, 0.3), trunk, Vector3(0, 0.15, 0))
		"rock":
			var grey := Color(0.5, 0.5, 0.52)
			Shapes.add(_full, Shapes.sphere(0.5), grey, Vector3(0, 0.25, 0), Vector3(1.2, 0.8, 1.0))
			Shapes.add(_full, Shapes.sphere(0.3), grey.lightened(0.15), Vector3(0.35, 0.2, 0.2))
			Shapes.add(_empty, Shapes.sphere(0.18), grey, Vector3(0, 0.1, 0), Vector3(1, 0.6, 1))
		"bush":
			var leaves := Color(0.2, 0.5, 0.22)
			Shapes.add(_full, Shapes.sphere(0.5), leaves, Vector3(0, 0.4, 0))
			for p in [Vector3(0.3, 0.6, 0.3), Vector3(-0.35, 0.5, 0.2), Vector3(0.1, 0.8, -0.3), Vector3(-0.1, 0.45, 0.45)]:
				Shapes.add(_full, Shapes.sphere(0.08), Color(0.85, 0.1, 0.2), p)
			Shapes.add(_empty, Shapes.sphere(0.45), leaves.darkened(0.2), Vector3(0, 0.35, 0))
