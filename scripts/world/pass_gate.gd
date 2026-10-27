extends Node3D
## The mountain pass at the far end of the east forest: the way to the next
## area. Needs Data.NEXT_AREA.level and the Great Boar defeated. In the demo,
## crossing it ends the demo.

const Shapes := preload("res://scripts/world/shapes.gd")

var radius := 1.6
var _label: Label3D


func _ready() -> void:
	add_to_group("interactable")
	var stone := Color(0.55, 0.55, 0.58)
	for x in [-1, 1]:
		Shapes.add(self, Shapes.box(Vector3(0.9, 3.4, 0.9)), stone, Vector3(x * 1.6, 1.7, 0))
	Shapes.add(self, Shapes.box(Vector3(4.2, 0.8, 1.0)), stone.darkened(0.15), Vector3(0, 3.6, 0))
	for i in 5: # mountains behind the pass
		var peak := Shapes.add(self, Shapes.cylinder(2.2 + i % 2, 5.0 + (i % 3) * 1.5, 0.0), Color(0.45, 0.47, 0.52),
			Vector3(-5.0 + i * 2.5, 2.5 + (i % 3) * 0.75, -3.0 - (i % 2) * 1.5))
		Shapes.add(peak, Shapes.cylinder(0.75, 1.2, 0.0), Color(0.95, 0.96, 1.0), Vector3(0, 2.0 + (i % 3) * 0.75, 0))
	_label = Shapes.label(self, "", Vector3(0, 4.8, 0), 40)
	Game.changed.connect(_refresh)
	Game.leveled_up.connect(func(_l: int) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	var blocker := Game.next_area_blocker()
	_label.text = Data.NEXT_AREA["name"] + ("\nOpen!" if blocker == "" else "\nNeeds level %d + %s" % [Data.NEXT_AREA["level"], Data.BOSS["name"]])
	_label.modulate = Color(0.6, 1.0, 0.6) if blocker == "" else Color.WHITE


func is_available() -> bool:
	return true


func action_label() -> String:
	return "Take the mountain pass"


func action_icon() -> String:
	return "door"


func interact(_player: Node3D) -> void:
	Game.take_mountain_pass()
