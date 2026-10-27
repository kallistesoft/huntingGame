extends RefCounted
## Placeholder 3D art: helpers that add simple coloured shapes to a node.
## Real models will replace these later.

static var _materials := {}


static func material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_materials[color] = m
	return _materials[color]


static func add(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material(color)
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m


static func cylinder(radius: float, height: float, top_radius := -1.0) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top_radius < 0.0 else top_radius
	m.height = height
	m.radial_segments = 16
	return m


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	return m


static func label(parent: Node3D, text: String, pos: Vector3, font_size := 48) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = font_size
	l.pixel_size = 0.01
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	parent.add_child(l)
	return l


## Ground position (x, z) of a 3D node, for distance checks on the map.
static func flat(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x, node.global_position.z)
