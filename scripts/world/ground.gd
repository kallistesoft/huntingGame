extends Node3D
## Placeholder ground built from Data.ZONES: a grass plane, tufts and label
## per zone, the camp clearing, every boss lair, and a fence across the west
## edge of each zone whose entry is a fence, shown until the zone is unlocked.

const Shapes := preload("res://scripts/world/shapes.gd")
const Models := preload("res://scripts/world/models.gd")

var camp: Rect2

var _fences := {} # zone index -> fence node


func _ready() -> void:
	# Wild land around the playable zones so the camera never shows the void.
	var whole: Rect2 = Data.ZONES[0]["rect"]
	for z in Data.ZONES:
		whole = whole.merge(z["rect"])
	_plane(whole.grow(40), Color(0.22, 0.34, 0.18), -0.02)

	for i in Data.ZONES.size():
		var z: Dictionary = Data.ZONES[i]
		var rect: Rect2 = z["rect"]
		_plane(rect, z["ground"], 0.0)
		if z["label"] != "":
			Shapes.label(self, z["label"], Vector3(rect.position.x + 4, 1.5, rect.position.y + 3), 96)
		_add_grass(rect, z["grass_count"], z["grass"], i)
		if z["flowers"] > 0:
			_add_flowers(rect, z["flowers"])
		if z["boss"] != "":
			_add_lair(Data.BOSSES[z["boss"]])
		if z["entry"].get("kind", "") == "fence":
			_add_fence(i)
		elif z["entry"].get("kind", "") == "pass":
			_add_boulder_wall(rect, z["entry"]["position"])

	_plane(camp, Color(0.62, 0.52, 0.36), 0.01)
	var camp_label := Shapes.label(self, "CAMP", Vector3(camp.position.x + 1.2, 0.05, camp.end.y - 0.6), 96)
	camp_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	camp_label.rotation_degrees.x = -90
	camp_label.modulate = Color(1, 1, 1, 0.6)
	camp_label.no_depth_test = false

	_refresh_fences()
	Game.leveled_up.connect(func(_level: int) -> void: _refresh_fences())
	Game.changed.connect(_refresh_fences)


func _refresh_fences() -> void:
	for i in _fences:
		_fences[i].visible = not Game.zone_unlocked(i)


func _plane(rect: Rect2, color: Color, height: float) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = rect.size
	var center := rect.get_center()
	Shapes.add(self, mesh, color, Vector3(center.x, height, center.y))


## Posts and two rails along the west edge of zone i, with the level needed.
func _add_fence(i: int) -> void:
	var z: Dictionary = Data.ZONES[i]
	var rect: Rect2 = z["rect"]
	var fence := Node3D.new()
	add_child(fence)
	_fences[i] = fence
	var x := rect.position.x
	var wood := Color(0.5, 0.32, 0.14)
	var zpos := rect.position.y + 0.5
	while zpos < rect.end.y:
		Shapes.add(fence, Shapes.box(Vector3(0.2, 1.2, 0.2)), wood, Vector3(x, 0.6, zpos))
		zpos += 1.5
	for h in [0.4, 0.9]:
		Shapes.add(fence, Shapes.box(Vector3(0.1, 0.12, rect.size.y)), wood.darkened(0.2), Vector3(x, h, rect.get_center().y))
	var need: String = "Reach level %d to cross" % z["unlock"]["level"]
	if z["unlock"]["boss"] != "":
		need += " and defeat the %s" % Data.BOSSES[z["unlock"]["boss"]]["name"]
	Shapes.label(fence, need, Vector3(x - 0.5, 2.0, rect.get_center().y), 64)


## Boulders along the west edge of a mountain zone, with a gap at its pass.
func _add_boulder_wall(rect: Rect2, gate: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rect.position.x) * 3
	var zpos := rect.position.y + 0.6
	while zpos < rect.end.y:
		if absf(zpos - gate.y) > 2.6:
			var r := rng.randf_range(0.9, 1.5)
			Shapes.add(self, Shapes.sphere(r), Color(0.47, 0.48, 0.52), Vector3(rect.position.x + rng.randf_range(-0.3, 0.3), r * 0.45, zpos), Vector3(1.0, 0.75, 1.1))
		zpos += 1.9
	# Snowy peaks beyond the zone's north and south edges, outside the walkable area.
	for i in 7:
		var x := rect.position.x + 2.0 + i * (rect.size.x - 4.0) / 6.0
		for zz in [rect.position.y - 9.0, rect.end.y + 9.0]:
			var r := 2.4 + (i % 2) * 0.6
			var peak := Shapes.add(self, Shapes.cylinder(r, 6.0 + (i % 3) * 1.5, 0.0), Color(0.45, 0.47, 0.52), Vector3(x, 3.0 + (i % 3) * 0.75, zz))
			Shapes.add(peak, Shapes.cylinder(r * 0.3, 1.4, 0.0), Color(0.95, 0.96, 1.0), Vector3(0, 2.3 + (i % 3) * 0.75, 0))


## Swaying grass tufts, drawn in one batch with a MultiMesh. Kept off the
## camp and out of boss lairs.
func _add_grass(zone: Rect2, count: int, color: Color, seed_offset: int) -> void:
	var blade: Mesh = Shapes.cylinder(0.05, 0.4, 0.0)
	blade.radial_segments = 4
	var model_mesh := _grass_mesh()
	var tuft_scale := 1.0
	if model_mesh != null:
		blade = model_mesh
		tuft_scale = 0.45 / maxf(0.01, model_mesh.get_aabb().size.y)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blade
	var spots := []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(zone.position.x) + 11 + seed_offset
	var guard := 0
	while spots.size() < count and guard < count * 4:
		guard += 1
		var p := Vector2(rng.randf_range(zone.position.x, zone.end.x), rng.randf_range(zone.position.y, zone.end.y))
		if not camp.grow(0.3).has_point(p) and not _in_lair(p):
			spots.append(p)
	mm.instance_count = spots.size() * 3
	var i := 0
	for p in spots:
		var tint := color * rng.randf_range(0.8, 1.15)
		for b in 3: # three blades per tuft
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.35, 0.35))
			var size := rng.randf_range(0.7, 1.3) * tuft_scale
			var offset := Vector3(rng.randf_range(-0.12, 0.12), 0.2 * size if model_mesh == null else 0.0, rng.randf_range(-0.12, 0.12))
			mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * size), Vector3(p.x, 0, p.y) + offset))
			mm.set_instance_color(i, Color(tint, 1.0))
			i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if model_mesh == null:
		mmi.material_override = Shapes.sway_material(Color.WHITE, 0.25)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## The grass model's mesh, for the tufts, or null to keep the blades.
static var _grass_mesh_cache: Mesh = null
static var _grass_mesh_tried := false
func _grass_mesh() -> Mesh:
	if _grass_mesh_tried:
		return _grass_mesh_cache
	_grass_mesh_tried = true
	if not Models.has("grass"):
		return null
	var holder := Node3D.new()
	add_child(holder)
	var node := Models.spawn("grass", holder, 1.0)
	var meshes := Models.meshes(node)
	if not meshes.is_empty():
		var mi := meshes[0]
		var mesh: Mesh = mi.mesh.duplicate()
		for i in mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m != null:
				mesh.surface_set_material(i, m)
		_grass_mesh_cache = mesh
	holder.queue_free()
	return _grass_mesh_cache


func _in_lair(p: Vector2) -> bool:
	for id in Data.BOSSES:
		var b: Dictionary = Data.BOSSES[id]
		if p.distance_to(b["lair"]) <= b["lair_radius"]:
			return true
	return false


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


## A boss lair: a trampled dirt clearing ringed with rocks and bones.
func _add_lair(b: Dictionary) -> void:
	var lair: Vector2 = b["lair"]
	var r: float = b["lair_radius"]
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
	Shapes.label(self, b["name"] + "'s lair", Vector3(lair.x, 2.4, lair.y + r + 1.0), 44)
