extends Node3D
## Placeholder ground: grass for each zone, the camp clearing, and the fence
## that closes the east forest until it is unlocked.

const Shapes := preload("res://scripts/world/shapes.gd")

var zone1: Rect2
var zone2: Rect2
var camp: Rect2

var _fence: Node3D


func _ready() -> void:
	# Wild land around the playable zones so the camera never shows the void.
	_plane(zone1.merge(zone2).grow(40), Color(0.22, 0.34, 0.18), -0.02)
	_plane(zone1, Color(0.36, 0.52, 0.26), 0.0)
	_plane(zone2, Color(0.24, 0.4, 0.22), 0.0)
	_plane(camp, Color(0.62, 0.52, 0.36), 0.01)
	var camp_label := Shapes.label(self, "CAMP", Vector3(camp.position.x + 1.2, 0.05, camp.end.y - 0.6), 96)
	camp_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	camp_label.rotation_degrees.x = -90
	camp_label.modulate = Color(1, 1, 1, 0.6)
	camp_label.no_depth_test = false
	Shapes.label(self, "EAST FOREST", Vector3(zone2.position.x + 4, 1.5, zone2.position.y + 3), 96)

	_fence = Node3D.new()
	add_child(_fence)
	var x := zone2.position.x
	var wood := Color(0.5, 0.32, 0.14)
	var z := zone2.position.y + 0.5
	while z < zone2.end.y:
		Shapes.add(_fence, Shapes.box(Vector3(0.2, 1.2, 0.2)), wood, Vector3(x, 0.6, z))
		z += 1.5
	for h in [0.4, 0.9]:
		Shapes.add(_fence, Shapes.box(Vector3(0.1, 0.12, zone2.size.y)), wood.darkened(0.2), Vector3(x, h, zone2.get_center().y))
	Shapes.label(_fence, "Reach level %d to cross" % Data.ZONE2_LEVEL, Vector3(x - 0.5, 2.0, zone2.get_center().y), 64)
	_fence.visible = not Game.zone2_unlocked()
	Game.leveled_up.connect(func(_level: int) -> void: _fence.visible = not Game.zone2_unlocked())


func _plane(rect: Rect2, color: Color, height: float) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = rect.size
	var center := rect.get_center()
	Shapes.add(self, mesh, color, Vector3(center.x, height, center.y))
