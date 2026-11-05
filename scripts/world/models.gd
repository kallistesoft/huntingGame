extends RefCounted
## Real low-poly models (CC0, see assets/models/CREDITS.md) that replace the
## code-built placeholder shapes. Every spawn is optional: when a model is
## missing or fails to load, spawn() returns null and the caller keeps its
## code shape, so the game never depends on an asset being present.
##
## Models come in all sizes, so callers give the height they want and the
## model is scaled to it from its bounding box.

const MODELS := {
	# nature
	"tree_meadow": "res://assets/models/quaternius/tree_oak.glb",
	"tree_meadow_2": "res://assets/models/quaternius/tree_birch.glb",
	"tree_pine": "res://assets/models/quaternius/pine_tree.glb",
	"tree_pine_2": "res://assets/models/quaternius/pine_tree_2.glb",
	"tree_snow": "res://assets/models/quaternius/pine_tree_with_snow.glb",
	"tree_snow_2": "res://assets/models/quaternius/birch_tree_with_snow.glb",
	"rock": "res://assets/models/quaternius/rock.glb",
	"rock_2": "res://assets/models/quaternius/rock_2.glb",
	"bush": "res://assets/models/quaternius/bush.glb",
	"bush_berries": "res://assets/models/quaternius/bush_with_berries.glb",
	"grass": "res://assets/models/quaternius/grass.glb",
	"flowers": "res://assets/models/quaternius/flowers.glb",
	"stump": "res://assets/models/quaternius/stump.glb",
	# animals (animated)
	"bunny": "res://assets/models/quaternius/bunny.glb",
	"deer": "res://assets/models/quaternius/deer.glb",
	"stag": "res://assets/models/quaternius/stag.glb",
	"wolf": "res://assets/models/quaternius/wolf.glb",
	"fox": "res://assets/models/quaternius/fox.glb",
	"sheep": "res://assets/models/quaternius/sheep.glb",
	# camp
	"campfire": "res://assets/models/quaternius/campfire.glb",
	"chest": "res://assets/models/quaternius/chest.glb",
	"crate": "res://assets/models/quaternius/crate.glb",
	"barrel": "res://assets/models/quaternius/barrel.glb",
	"anvil": "res://assets/models/kenney/anvil.glb",
	# buildings, one or more per tier (station.gd)
	"tent": "res://assets/models/quaternius/tent.glb",
	"shack": "res://assets/models/quaternius/shack.glb",
	"house": "res://assets/models/quaternius/house.glb",
	"storage_hut": "res://assets/models/quaternius/storage_hut.glb",
	"storage_shed": "res://assets/models/quaternius/storage_shed.glb",
	"workbench": "res://assets/models/kenney/workbench.glb",
	"workbench_grind": "res://assets/models/kenney/workbench_grind.glb",
	"gazebo": "res://assets/models/quaternius/gazebo.glb",
	"sawmill_logs": "res://assets/models/quaternius/sawmill_logs.glb",
	"sawmill_house": "res://assets/models/quaternius/sawmill_house.glb",
	"fireplace": "res://assets/models/quaternius/fireplace.glb",
	"blacksmith": "res://assets/models/quaternius/blacksmith.glb",
	# the hunter (animated) and what they wear or hold (player.gd)
	"adventurer": "res://assets/models/quaternius/adventurer.glb",
	"hooded_adventurer": "res://assets/models/quaternius/hooded_adventurer.glb",
	"armor_leather": "res://assets/models/quaternius/armor_leather.glb",
	"armor_metal": "res://assets/models/quaternius/armor_metal.glb",
	"bag": "res://assets/models/quaternius/bag.glb",
	"backpack": "res://assets/models/quaternius/backpack.glb",
	"spear": "res://assets/models/quaternius/spear.glb",
	"bow": "res://assets/models/quaternius/bow.glb",
	"tool_axe": "res://assets/models/kenney/tool_axe.glb",
	"pickaxe": "res://assets/models/kenney/pickaxe.glb",
}

static var _scenes := {} # id -> PackedScene or null once tried


static func has(id: String) -> bool:
	return _scene(id) != null


static func _scene(id: String) -> PackedScene:
	if not _scenes.has(id):
		var path: String = MODELS.get(id, "")
		_scenes[id] = load(path) if path != "" and ResourceLoader.exists(path) else null
	return _scenes[id]


## Instantiates a model under parent, scaled so its bounding box is `height`
## metres tall (0 keeps the file's own size), standing on y = 0. Returns null
## when the model is missing.
static func spawn(id: String, parent: Node3D, height := 0.0, pos := Vector3.ZERO) -> Node3D:
	var scene := _scene(id)
	if scene == null:
		return null
	var node: Node3D = scene.instantiate()
	parent.add_child(node)
	var box := bounds(node)
	if height > 0.0 and box.size.y > 0.001:
		node.scale = Vector3.ONE * (height / box.size.y)
		box = bounds(node)
	# Feet on the ground, centred on the parent.
	node.position = pos + Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * 1.0
	return node


## Like spawn(), but scaled so the model's wider horizontal side is `width`
## metres: buildings have to fit their plot whatever their roof height.
static func spawn_fit(id: String, parent: Node3D, width: float, pos := Vector3.ZERO) -> Node3D:
	var node := spawn(id, parent, 0.0, pos)
	if node == null:
		return null
	var box := bounds(node)
	var side := maxf(box.size.x, box.size.z)
	if side > 0.001:
		node.scale = Vector3.ONE * (width / side)
		node.position = Vector3.ZERO
		box = bounds(node)
		node.position = pos - Vector3(box.get_center().x, box.position.y, box.get_center().z)
	return node


## Bounding box of every mesh under node, in the node's parent space.
static func bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in meshes(node):
		var aabb: AABB = mi.get_aabb()
		var xform: Transform3D = node.get_parent().global_transform.affine_inverse() * mi.global_transform if node.get_parent() != null else mi.transform
		var local := xform * aabb
		out = local if first else out.merge(local)
		first = false
	return out


static func meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(meshes(child))
	return out


## The model's AnimationPlayer, or null.
static func animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := animation_player(child)
		if found != null:
			return found
	return null


## Plays the first animation whose name contains one of the hints (case
## insensitive), looping. Returns the name played, or "".
static func play(anim: AnimationPlayer, hints: Array, speed := 1.0) -> String:
	if anim == null:
		return ""
	for hint in hints:
		for name in anim.get_animation_list():
			if String(name).to_lower().contains(String(hint).to_lower()):
				if anim.current_animation != String(name):
					anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
					anim.play(name)
				anim.speed_scale = speed
				return String(name)
	return ""


## Multiplies the albedo of every material under node (a white fox, a dark
## boar). Materials are duplicated so other instances keep their colour.
static func tint(node: Node, color: Color) -> void:
	for mi in meshes(node):
		for i in mi.get_surface_override_material_count():
			var m: Material = mi.get_active_material(i)
			if m is BaseMaterial3D:
				var d: BaseMaterial3D = m.duplicate()
				d.albedo_color = d.albedo_color * color
				mi.set_surface_override_material(i, d)


## Repaints the surfaces whose material is named in `names` (the kit's own
## names: "Steel", "Green"...) with a flat colour; the other surfaces keep
## theirs. Unlike tint() this can lighten, so a dark shirt can become fur.
static func paint(node: Node, names: Array, color: Color) -> void:
	for mi in meshes(node):
		for i in mi.get_surface_override_material_count():
			var m: Material = mi.get_active_material(i)
			if m is BaseMaterial3D and m.resource_name in names:
				var d: BaseMaterial3D = m.duplicate()
				d.albedo_color = color
				mi.set_surface_override_material(i, d)


## Makes the named surfaces invisible (hair under a helmet). A surface can't
## be hidden on its own, so it gets a fully transparent material.
static func hide_surfaces(node: Node, names: Array) -> void:
	for mi in meshes(node):
		for i in mi.get_surface_override_material_count():
			var m: Material = mi.get_active_material(i)
			if m != null and m.resource_name in names:
				var d := StandardMaterial3D.new()
				d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				d.albedo_color = Color(0, 0, 0, 0)
				d.no_depth_test = true
				mi.set_surface_override_material(i, d)


## Plays a clip once at a speed that makes it last `duration` seconds, then
## holds its last frame. Returns the name played, or "".
static func play_once(anim: AnimationPlayer, hints: Array, duration := 0.0) -> String:
	if anim == null:
		return ""
	for hint in hints:
		for name in anim.get_animation_list():
			if String(name).to_lower().contains(String(hint).to_lower()):
				var a := anim.get_animation(name)
				a.loop_mode = Animation.LOOP_NONE
				anim.speed_scale = a.length / duration if duration > 0.0 else 1.0
				anim.play(name)
				anim.seek(0.0, true)
				return String(name)
	return ""


## One skinned surface of a model, moved onto another skeleton: the hood of
## the hooded adventurer on the hunter. Both must share the same rig (the
## bind poses are matched by bone name). Returns null when anything is off.
static func borrow_surface(id: String, mesh_name: String, material_name: String, skeleton: Skeleton3D) -> MeshInstance3D:
	var scene := _scene(id)
	if scene == null:
		return null
	var donor: Node = scene.instantiate()
	var src: MeshInstance3D = null
	for mi in meshes(donor):
		if mi.name == mesh_name and mi.skin != null:
			src = mi
	var out: MeshInstance3D = null
	if src != null:
		var mesh := ArrayMesh.new()
		for i in src.mesh.get_surface_count():
			var m := src.mesh.surface_get_material(i)
			if m != null and m.resource_name == material_name:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.mesh.surface_get_arrays(i))
				mesh.surface_set_material(mesh.get_surface_count() - 1, m)
		if mesh.get_surface_count() > 0:
			out = MeshInstance3D.new()
			out.mesh = mesh
			out.skin = src.skin
			skeleton.add_child(out)
			out.skeleton = out.get_path_to(skeleton)
	donor.free()
	return out


## Sets a material overlay on every mesh (the white hit flash) or clears it.
static func overlay(node: Node, m: Material) -> void:
	for mi in meshes(node):
		mi.material_overlay = m
