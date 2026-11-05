extends SceneTree
## Prints what Godot imported from each glb in assets/models: node tree,
## bone names, animation names and the bounding box in metres. Run:
##   godot --headless --path . -s tools/inspect_models.gd [name ...]
## Handy when wiring a new model into scripts/world/models.gd.

const Models := preload("res://scripts/world/models.gd")


var _done := false


## Runs on the first frame: the root is only inside the tree once the loop
## has started, and bounds() needs global transforms.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var wanted: PackedStringArray = OS.get_cmdline_user_args()
	var root := Node3D.new()
	get_root().add_child(root)
	for id in Models.MODELS:
		if not wanted.is_empty() and not (id in wanted):
			continue
		var node := Models.spawn(id, root)
		if node == null:
			print("== %s: MISSING (%s)" % [id, Models.MODELS[id]])
			continue
		var box := Models.bounds(node)
		print("== %s  size %.2f x %.2f x %.2f  (%s)" % [id, box.size.x, box.size.y, box.size.z, Models.MODELS[id].get_file()])
		if wanted.is_empty():
			continue
		_dump(node, 1)
		var anim := Models.animation_player(node)
		if anim != null:
			print("   animations: ", ", ".join(anim.get_animation_list()))
	return true


func _dump(node: Node, depth: int) -> void:
	var line := "   ".repeat(depth) + node.name + " (" + node.get_class() + ")"
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var mats := PackedStringArray()
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			mats.append(m.resource_name if m != null else "-")
		line += "  surfaces: " + ", ".join(mats) + ("  skin" if mi.skin != null else "")
		if node.get_parent() is BoneAttachment3D:
			var aabb := mi.get_aabb()
			line += "  pos %s rot %s aabb %s..%s" % [mi.position, mi.rotation_degrees, aabb.position, aabb.end]
	if node is Skeleton3D:
		var sk: Skeleton3D = node
		var names := PackedStringArray()
		for i in sk.get_bone_count():
			names.append(sk.get_bone_name(i))
		line += "  bones(%d): %s" % [sk.get_bone_count(), ", ".join(names)]
	print(line)
	for child in node.get_children():
		_dump(child, depth + 1)
