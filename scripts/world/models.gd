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


## Sets a material overlay on every mesh (the white hit flash) or clears it.
static func overlay(node: Node, m: Material) -> void:
	for mi in meshes(node):
		mi.material_overlay = m
