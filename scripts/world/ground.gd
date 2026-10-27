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

	_add_lair()
	_add_grass(zone1, 1400, Color(0.42, 0.62, 0.3))
	_add_grass(zone2, 1300, Color(0.3, 0.5, 0.26))
	_add_flowers(zone1, 160)

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


## Swaying grass tufts, drawn in one batch with a MultiMesh. Kept off the camp.
func _add_grass(zone: Rect2, count: int, color: Color) -> void:
	var blade := Shapes.cylinder(0.05, 0.4, 0.0)
	blade.radial_segments = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blade
	var spots := []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(zone.position.x) + 11
	while spots.size() < count:
		var p := Vector2(rng.randf_range(zone.position.x, zone.end.x), rng.randf_range(zone.position.y, zone.end.y))
		if not camp.grow(0.3).has_point(p) and p.distance_to(Data.BOSS["lair"]) > Data.BOSS["lair_radius"]:
			spots.append(p)
	mm.instance_count = spots.size() * 3
	var i := 0
	for p in spots:
		var tint := color * rng.randf_range(0.8, 1.15)
		for b in 3: # three blades per tuft
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.35, 0.35))
			var size := rng.randf_range(0.7, 1.3)
			var offset := Vector3(rng.randf_range(-0.12, 0.12), 0.2 * size, rng.randf_range(-0.12, 0.12))
			mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * size), Vector3(p.x, 0, p.y) + offset))
			mm.set_instance_color(i, Color(tint, 1.0))
			i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Shapes.sway_material(Color.WHITE, 0.25)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _add_flowers(zone: Rect2, count: int) -> void:
	var colors := [Color(1, 0.95, 0.5), Color(1, 1, 1), Color(0.85, 0.6, 1.0), Color(1, 0.6, 0.6)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var head := Shapes.sphere(0.06)
	for c in colors:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = head
		mm.instance_count = count / colors.size()
		for i in mm.instance_count:
			var p := Vector2(rng.randf_range(zone.position.x, zone.end.x), rng.randf_range(zone.position.y, zone.end.y))
			if camp.grow(0.3).has_point(p):
				p.y += camp.size.y + 1.0
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, 0.22, p.y)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Shapes.sway_material(c, 0.25)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## The Great Boar's lair: a trampled dirt clearing ringed with rocks and bones.
func _add_lair() -> void:
	var lair: Vector2 = Data.BOSS["lair"]
	var r: float = Data.BOSS["lair_radius"]
	Shapes.add(self, Shapes.cylinder(r, 0.02), Color(0.42, 0.33, 0.24), Vector3(lair.x, 0.015, lair.y))
	for i in 18:
		var a := i * TAU / 18.0
		var p := Vector3(lair.x + cos(a) * (r + 0.3), 0.2, lair.y + sin(a) * (r + 0.3))
		Shapes.add(self, Shapes.sphere(0.45), Color(0.45, 0.45, 0.48), p, Vector3(1.0, 0.7 + 0.3 * (i % 3), 1.0))
	for i in 5:
		var a := i * 1.3
		var bone := Shapes.add(self, Shapes.capsule(0.06, 0.6), Color(0.92, 0.9, 0.82),
			Vector3(lair.x + cos(a) * r * 0.6, 0.06, lair.y + sin(a) * r * 0.5))
		bone.rotation_degrees = Vector3(90, i * 47, 0)
	Shapes.label(self, Data.BOSS["name"] + "'s lair", Vector3(lair.x, 2.4, lair.y + r + 1.0), 44)
