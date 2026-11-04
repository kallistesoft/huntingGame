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


## Leaves and grass that sway in the wind; the higher the vertex, the more it moves.
const SWAY_SHADER := """
shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float strength = 0.06;
void vertex() {
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * 1.7 + origin.x * 0.37 + origin.z * 0.23;
	float h = max(world_vertex.y, 0.0);
	VERTEX.x += sin(t) * strength * h;
	VERTEX.z += cos(t * 0.8) * strength * 0.6 * h;
}
void fragment() {
	ALBEDO = albedo.rgb * COLOR.rgb;
	ROUGHNESS = 0.85;
}
"""

## Pond water with moving ripples and a light rim.
const WATER_SHADER := """
shader_type spatial;
uniform vec4 deep : source_color = vec4(0.12, 0.38, 0.72, 1.0);
uniform vec4 shallow : source_color = vec4(0.45, 0.78, 0.95, 1.0);
uniform float radius = 1.5;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = world_pos.xz;
	float ripple = sin(p.x * 3.1 + TIME * 1.6) * sin(p.y * 2.7 - TIME * 1.3);
	float edge = clamp(length(world_pos.xz - NODE_POSITION_WORLD.xz) / radius, 0.0, 1.0);
	vec3 col = mix(deep.rgb, shallow.rgb, smoothstep(0.55, 1.0, edge) + ripple * 0.08);
	col += vec3(0.9) * smoothstep(0.6, 0.95, ripple) * 0.12;
	ALBEDO = col;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
}
"""

static var _sway_shader: Shader
static var _sway_materials := {}
static var _water_shader: Shader


static func sway_material(color: Color, strength := 0.06) -> ShaderMaterial:
	var key := [color, strength]
	if not _sway_materials.has(key):
		if _sway_shader == null:
			_sway_shader = Shader.new()
			_sway_shader.code = SWAY_SHADER
		var m := ShaderMaterial.new()
		m.shader = _sway_shader
		m.set_shader_parameter("albedo", color)
		m.set_shader_parameter("strength", strength)
		_sway_materials[key] = m
	return _sway_materials[key]


static func water_material(radius: float) -> ShaderMaterial:
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = _water_shader
	m.set_shader_parameter("radius", radius)
	return m


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
	l.font = load("res://scripts/ui/style.gd").font_bold()
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
