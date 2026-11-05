extends Node3D
## The hunter. Moves with the on-screen joystick or WASD/arrow keys. The action
## button (or Space/E) uses the nearest thing in reach: hunt, gather, drink,
## or open a camp station. The camera never turns, so screen up is world -Z.
##
## The body is the animated "Adventurer" model (models.gd): clips for idle,
## walk, run, gather, attack, hit and knock-out. What the hunter wears hangs
## from its bones (hood, helm, armor, bag, the tool in hand) or repaints its
## own surfaces (tunic, boots). Without the model, a code-built figure with
## code-built gear takes over.

const Shapes := preload("res://scripts/world/shapes.gd")
const Models := preload("res://scripts/world/models.gd")
const REACH := 1.25 # gap allowed between the hunter and a target's edge, metres
const ACTION_COOLDOWN := 0.35
const SKIN := Color(0.93, 0.76, 0.6)
const HEIGHT := 1.85 # of the model's bounding box, metres
const HOLD_TOOL := 1.2 # seconds the axe or pick stays in hand after a swing

var world: Node3D
var move_input := Vector2.ZERO # set by the joystick, length 0..1; y is screen down

var _cooldown := 0.0
var _swing := 0.0
var _model: Node3D
var _gear: Node3D # worn pieces, rebuilt by _update_gear
var _zzz: Label3D
var _knock := Vector2.ZERO
var _zone := -1 # zone index the hunter stands in, to notice crossings

# The animated model, or null when the code figure is used.
var _rig: Node3D = null
var _skeleton: Skeleton3D = null
var _anim: AnimationPlayer = null
var _busy := 0.0 # seconds left of a one-shot clip (gather, attack, hit)
var _lying := false # death clip playing (sleep or knocked out)
var _tool_until := 0.0 # while > now, the axe or pick is shown instead of the weapon
var _tool_icon := ""
var _hand_scale := 1.0 # metres per unit in a bone attachment's space
var _hood_mesh: MeshInstance3D = null
var _shown := {} # slot -> tool id drawn by the last _update_gear (for tests)


## Whether the equipped piece of `slot` is drawn on the hunter right now.
func wears(slot: String) -> bool:
	return _shown.get(slot, "") == Game.equipped(slot) and Game.equipped(slot) != ""

# Code figure only.
var _arm: Node3D
var _spear: Node3D
var _spear_tip: MeshInstance3D
var _bow: Node3D
var _bow_mesh: MeshInstance3D


func _ready() -> void:
	_build_shape()
	Game.changed.connect(_update_gear)
	_update_gear()


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_swing = maxf(0.0, _swing - delta)
	_busy = maxf(0.0, _busy - delta)

	var dir := move_input
	var keys := Vector2(
		_key(KEY_D, KEY_RIGHT) - _key(KEY_A, KEY_LEFT),
		_key(KEY_S, KEY_DOWN) - _key(KEY_W, KEY_UP))
	if keys != Vector2.ZERO:
		dir = keys.normalized()
	var sleeping := Game.is_sleeping()
	var down := Game.is_dead()
	if sleeping or down:
		dir = Vector2.ZERO
	if dir != Vector2.ZERO:
		_face(dir)
	var bounds: Rect2 = world.walk_bounds()
	var velocity := dir.limit_length(1.0) * Game.move_speed() + _knock
	_knock = _knock.move_toward(Vector2.ZERO, 14.0 * delta)
	var next := (Shapes.flat(self) + velocity * delta).clamp(bounds.position, bounds.end)
	position = Vector3(next.x, 0, next.y)
	Game.player_position = next
	var zone := Game.zone_at(next)
	if zone != _zone:
		_zone = zone
		if zone > 0:
			Game.on_enter_zone(zone)

	_zzz.visible = sleeping
	if _rig != null:
		_animate(dir.limit_length(1.0).length(), sleeping or down)
		if _tool_until > 0.0 and Time.get_ticks_msec() / 1000.0 > _tool_until:
			_tool_until = 0.0
			_update_gear()
	else:
		_model.rotation_degrees.x = -90.0 if sleeping or down else 0.0
		_model.position.y = 0.3 if sleeping or down else absf(sin(Time.get_ticks_msec() * 0.012)) * 0.08 * dir.length()
		_arm.rotation_degrees.x = -70.0 if _swing > 0.0 else 0.0


## Picks the model's clip: lying down, a one-shot in progress, or idle /
## walk / run from the joystick.
func _animate(speed: float, lying: bool) -> void:
	if lying:
		if not _lying:
			_lying = true
			Models.play_once(_anim, ["death"], 0.8)
		return
	_lying = false
	if _busy > 0.0:
		return
	if speed > 0.6:
		Models.play(_anim, ["|run"], 1.0)
	elif speed > 0.02:
		Models.play(_anim, ["|walk"], 1.1)
	else:
		Models.play(_anim, ["|idle"], 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_SPACE, KEY_E]:
			do_action()


## Pushes the hunter away, e.g. when the boss charge hits.
func knockback(v: Vector2) -> void:
	_knock = v * 3.0
	_face(-v)
	if _rig != null and not _lying:
		_busy = 0.5
		Models.play_once(_anim, ["hitrecieve"], 0.5)


func _key(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0


func _face(dir: Vector2) -> void:
	rotation.y = atan2(dir.x, dir.y)


func do_action() -> void:
	if _cooldown > 0.0 or Game.is_sleeping() or Game.is_dead():
		return
	_cooldown = ACTION_COOLDOWN
	var target := find_target()
	if target == null:
		if _animal_nearby() and Game.weapon() == "":
			Game.notify("You need a spear to hunt. Craft one at the crafting place.")
		return
	var to_target := Shapes.flat(target) - Shapes.flat(self)
	if to_target.length() > 0.01:
		_face(to_target)
	_swing = 0.2
	if _rig != null:
		var fight := target.is_in_group("animal") or target.is_in_group("boss")
		_busy = 0.4
		Models.play_once(_anim, ["sword_slash"] if fight else ["interact"], 0.4)
		var icon: String = target.action_icon() if target.has_method("action_icon") else ""
		var show := icon if icon in ["axe", "pick"] else ""
		if show != _tool_icon:
			_tool_icon = show
			_update_gear()
		_tool_until = Time.get_ticks_msec() / 1000.0 + HOLD_TOOL if show != "" else 0.0
	target.interact(self)


## The nearest usable thing in reach. Animals are reachable from the weapon's range;
## the boss comes first whenever it is in range.
func find_target() -> Node3D:
	var best: Node3D = null
	var best_gap := INF
	var here := Shapes.flat(self)
	for node in get_tree().get_nodes_in_group("interactable"):
		if not node.is_available():
			continue
		var gap: float = here.distance_to(Shapes.flat(node))
		var reach := REACH
		if node.is_in_group("animal"):
			if Game.weapon() == "":
				continue
			reach = Game.weapon_range()
		if "radius" in node:
			gap -= node.radius
		if gap <= reach and node.is_in_group("boss"):
			return node # in a boss fight, never chop a tree by mistake
		if gap <= reach and gap < best_gap:
			best = node
			best_gap = gap
	return best


func _animal_nearby() -> bool:
	for node in get_tree().get_nodes_in_group("animal"):
		if node.is_available() and Shapes.flat(self).distance_to(Shapes.flat(node)) < 2.25:
			return true
	return false


## Rebuilds what the hunter wears from the equipped pieces: weapon or tool in
## hand, hood/helm, tunic/armor, boots and a bag on the back, coloured by tier.
func _update_gear() -> void:
	if _rig == null:
		_update_gear_shapes()
		return
	for child in _gear.get_children():
		child.queue_free()
	if _hood_mesh != null:
		_hood_mesh.queue_free()
		_hood_mesh = null
	if _tool_until > 0.0 and Time.get_ticks_msec() / 1000.0 > _tool_until:
		_tool_until = 0.0
		_tool_icon = ""
	_shown.clear()
	for slot in Data.SLOTS:
		_shown[slot] = Game.equipped(slot)

	# In the right hand: the axe or pick just used, else the weapon.
	var w := Game.weapon()
	var tool_id := Game.equipped(_tool_icon) if _tool_icon != "" else ""
	if tool_id != "":
		var t: int = Data.TOOLS[tool_id]["tier"]
		var held := _hold("Middle1.R", "tool_axe" if _tool_icon == "axe" else "pickaxe", 0.62, 0.22)
		if held != null:
			Models.paint(held, ["wood"], Color(0.45, 0.3, 0.14))
			Models.paint(held, ["metal", "rock"], _tier_metal(t))
	elif w != "":
		var t: int = Data.TOOLS[w]["tier"]
		if Data.TOOLS[w]["icon"] == "bow":
			var bow := _hold("Wrist.L", "bow", 1.1, 0.5, Vector3(90, 0, 0))
			if bow != null and t >= 3:
				Models.paint(bow, ["DarkWood", "LightWood"], _tier_metal(t).darkened(0.3))
		else:
			var spear := _hold("Middle1.R", "spear", 1.9, 0.75)
			if spear != null:
				Models.paint(spear, ["Steel", "LightSteel"], _tier_metal(t))

	# Head: the borrowed hood at tier 1, a cap with tusks or a crest above.
	var head := Game.equipped("head")
	if head != "":
		var t: int = Data.TOOLS[head]["tier"]
		Models.hide_surfaces(_rig, ["Hair"])
		if t == 1 and _hood() != null:
			pass
		else:
			var on_head := _attach("Head")
			var c := _tier_cloth(t) if t < 3 else _tier_metal(t)
			var cap := Shapes.add(on_head, Shapes.sphere(0.125 / _hand_scale), c, _m(Vector3(0, 0.09, -0.01)), Vector3(1, 0.8, 1.05))
			cap.rotation_degrees.x = -10.0
			if t == 2:
				for x in [-1, 1]:
					Shapes.add(on_head, Shapes.cylinder(0.018 / _hand_scale, 0.14 / _hand_scale, 0.0), Color(0.97, 0.94, 0.85), _m(Vector3(x * 0.12, 0.2, 0.02))).rotation_degrees.z = -x * 35
			elif t >= 3:
				Shapes.add(on_head, Shapes.box(_m(Vector3(0.04, 0.07, 0.24))), c.darkened(0.2), _m(Vector3(0, 0.24, -0.01)))

	# Body: the shirt is repainted; from tier 2 a chest piece sits over it.
	var body := Game.equipped("body")
	if body != "":
		var t: int = Data.TOOLS[body]["tier"]
		Models.paint(_rig, ["Green"], _tier_cloth(t))
		Models.paint(_rig, ["LightGreen"], _tier_cloth(t).darkened(0.25))
		if t >= 2:
			var chest := _attach("Chest")
			var armor := Models.spawn("armor_leather" if t == 2 else "armor_metal", chest, 0.4 / _hand_scale)
			if armor != null:
				armor.position = _m(Vector3(0, -0.22, 0.0))
				if t == 3:
					Models.paint(armor, ["LightSteel"], Color(0.5, 0.5, 0.56))
				elif t == 4:
					Models.paint(armor, ["LightSteel"], Color(0.9, 0.9, 0.95))

	var feet := Game.equipped("feet")
	if feet != "":
		var c := _tier_cloth(Data.TOOLS[feet]["tier"])
		Models.paint(_rig, ["Grey"], c)
		Models.paint(_rig, ["Black"], c.darkened(0.45))

	# Bag: a satchel at tiers 1-2, a real backpack above; the bedroll that
	# comes with the model goes away once a backpack covers it.
	var bag := Game.equipped("bag")
	var bedroll := _rig.find_child("Backpack", true, false)
	if bag != "":
		var t: int = Data.TOOLS[bag]["tier"]
		var back := _attach("Chest")
		var pack := Models.spawn("bag" if t <= 2 else "backpack", back, [0.3, 0.38, 0.46, 0.52][t - 1] / _hand_scale)
		if pack != null:
			pack.position = _m(Vector3(0, -0.1 if t <= 2 else 0.0, -0.17 if t <= 2 else -0.22))
			pack.rotation_degrees.y = 180.0
			if t == 1:
				Models.paint(pack, ["Brown"], _tier_cloth(1))
			elif t == 4:
				Models.paint(pack, ["Green", "LightGreen"], _tier_cloth(4))
		if bedroll != null:
			bedroll.visible = t <= 2
	elif bedroll != null:
		bedroll.visible = true


## A new attachment following `bone`, kept under _gear so a refresh clears it.
func _attach(bone: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	_gear.add_child(att)
	att.use_external_skeleton = true
	att.external_skeleton = att.get_path_to(_skeleton)
	att.bone_name = bone
	return att


## Puts a model in a hand: its long axis along the fingers (the bone's -X,
## where the kit's own sword points), `grip` metres from its lower end.
func _hold(bone: String, id: String, length: float, grip: float, extra_rot := Vector3.ZERO) -> Node3D:
	var att := _attach(bone)
	var node := Models.spawn(id, att, length / _hand_scale)
	if node == null:
		return null
	var pivot := Node3D.new()
	att.add_child(pivot)
	node.reparent(pivot, false)
	node.position.y = -grip / _hand_scale
	pivot.rotation_degrees = Vector3(0, 0, 90) + extra_rot
	return node


## The hood of the hooded adventurer, skinned onto the hunter's skeleton. It
## has to live under the skeleton, so _update_gear frees it by hand.
func _hood() -> MeshInstance3D:
	_hood_mesh = Models.borrow_surface("hooded_adventurer", "Medieval_Head", "DarkBrown", _skeleton)
	if _hood_mesh != null:
		Models.paint(_hood_mesh, ["DarkBrown"], _tier_cloth(1))
	return _hood_mesh


## Metres to the units of a bone attachment's space.
func _m(v: Vector3) -> Vector3:
	return v / _hand_scale


## Cloth colour by tier: fur, leather, wolf pelt, mammoth pelt.
static func _tier_cloth(tier: int) -> Color:
	return [Color(0.78, 0.56, 0.33), Color(0.47, 0.3, 0.16), Color(0.5, 0.5, 0.56), Color(0.9, 0.9, 0.95)][clampi(tier, 1, 4) - 1]


## Tool-head colour by tier: stone, bone, iron, silver.
static func _tier_metal(tier: int) -> Color:
	return [Color(0.6, 0.6, 0.62), Color(0.92, 0.88, 0.78), Color(0.55, 0.62, 0.72), Color(0.86, 0.88, 0.93)][clampi(tier, 1, 4) - 1]


## Built facing +Z so rotation.y = atan2(x, z) points it where it walks.
func _build_shape() -> void:
	_model = Node3D.new()
	add_child(_model)
	_gear = Node3D.new()
	_model.add_child(_gear)
	_zzz = Shapes.label(self, "Zzz", Vector3(0, 1.4, 0))
	_rig = Models.spawn("adventurer", _model, HEIGHT)
	if _rig != null:
		_skeleton = _rig.find_child("Skeleton3D", true, false) as Skeleton3D
		_anim = Models.animation_player(_rig)
	if _skeleton == null or _anim == null:
		if _rig != null:
			_rig.queue_free()
			_rig = null
		_build_figure()
		return
	# Bone attachments place themselves in world space, so the gear holder
	# must not add the hunter's own transform on top.
	_gear.top_level = true
	_hand_scale = _skeleton.global_transform.basis.get_scale().x
	Models.play(_anim, ["|idle"])


## The code-built hunter, used when the model is missing.
func _build_figure() -> void:
	Shapes.add(_model, Shapes.capsule(0.28, 1.2), SKIN, Vector3(0, 0.75, 0))
	Shapes.add(_model, Shapes.sphere(0.24), SKIN, Vector3(0, 1.55, 0))
	Shapes.add(_model, Shapes.sphere(0.25), Color(0.35, 0.22, 0.12), Vector3(0, 1.65, -0.05), Vector3(1, 0.7, 1))
	Shapes.add(_model, Shapes.cylinder(0.31, 0.25), Color(0.55, 0.42, 0.25), Vector3(0, 0.55, 0)) # loincloth
	_arm = Node3D.new()
	_arm.position = Vector3(0.32, 1.15, 0)
	_model.add_child(_arm)
	Shapes.add(_arm, Shapes.capsule(0.08, 0.6), SKIN, Vector3(0, -0.25, 0))
	_spear = Node3D.new()
	_arm.add_child(_spear)
	var shaft := Shapes.add(_spear, Shapes.cylinder(0.03, 1.8), Color(0.5, 0.33, 0.15), Vector3(0, -0.5, 0.3))
	shaft.rotation_degrees.x = 80
	_spear_tip = Shapes.add(_spear, Shapes.cylinder(0.06, 0.2, 0.0), Color(0.6, 0.6, 0.62), Vector3(0, -0.35, 1.2))
	_spear_tip.rotation_degrees.x = 90
	_bow = Node3D.new()
	_arm.add_child(_bow)
	var bow_mesh := TorusMesh.new()
	bow_mesh.inner_radius = 0.38
	bow_mesh.outer_radius = 0.42
	_bow_mesh = Shapes.add(_bow, bow_mesh, Color(0.45, 0.28, 0.12), Vector3(0, -0.5, 0.2), Vector3(1, 1, 0.5))
	_bow_mesh.rotation_degrees.z = 90


## Gear on the code-built figure: simple shapes coloured by tier.
func _update_gear_shapes() -> void:
	var w := Game.weapon()
	_spear.visible = w != "" and Data.TOOLS[w]["icon"] == "spear"
	_bow.visible = w != "" and Data.TOOLS[w]["icon"] == "bow"
	if w != "":
		var metal := _tier_metal(Data.TOOLS[w].get("tier", 1))
		_spear_tip.material_override = Shapes.material(metal)
		_bow_mesh.material_override = Shapes.material(Color(0.45, 0.28, 0.12) if Data.TOOLS[w]["tier"] < 3 else metal)
	for child in _gear.get_children():
		child.queue_free()
	_shown.clear()
	for slot in Data.SLOTS:
		_shown[slot] = Game.equipped(slot)
	var head := Game.equipped("head")
	if head != "":
		var t: int = Data.TOOLS[head]["tier"]
		var c := _tier_cloth(t) if t < 3 else _tier_metal(t)
		Shapes.add(_gear, Shapes.sphere(0.29), c, Vector3(0, 1.62, -0.03), Vector3(1, 0.75, 1))
		if t == 2:
			for x in [-1, 1]:
				Shapes.add(_gear, Shapes.cylinder(0.03, 0.22, 0.0), Color(0.97, 0.94, 0.85), Vector3(x * 0.2, 1.8, 0)).rotation_degrees.z = -x * 35
		elif t >= 3:
			Shapes.add(_gear, Shapes.box(Vector3(0.06, 0.12, 0.4)), c.darkened(0.2), Vector3(0, 1.86, -0.03)) # crest
	var body := Game.equipped("body")
	if body != "":
		var t: int = Data.TOOLS[body]["tier"]
		var c := _tier_cloth(t)
		Shapes.add(_gear, Shapes.cylinder(0.32, 0.62), c, Vector3(0, 1.02, 0))
		if t >= 2:
			for x in [-1, 1]:
				Shapes.add(_gear, Shapes.sphere(0.13), c.darkened(0.2), Vector3(x * 0.3, 1.3, 0)) # shoulder pads
		if t >= 3:
			Shapes.add(_gear, Shapes.cylinder(0.3, 0.14), Color(0.6, 0.6, 0.65), Vector3(0, 1.36, 0)) # fur collar
	var feet := Game.equipped("feet")
	if feet != "":
		var c := _tier_cloth(Data.TOOLS[feet]["tier"])
		for x in [-1, 1]:
			Shapes.add(_gear, Shapes.box(Vector3(0.16, 0.22, 0.28)), c, Vector3(x * 0.12, 0.11, 0.04))
	var bag := Game.equipped("bag")
	if bag != "":
		var t: int = Data.TOOLS[bag]["tier"]
		var c := _tier_cloth(t)
		var sz := 0.22 + 0.08 * t
		Shapes.add(_gear, Shapes.box(Vector3(sz, sz * 1.2, 0.18)), c, Vector3(0, 1.0, -0.33))
		Shapes.add(_gear, Shapes.box(Vector3(sz * 1.05, 0.06, 0.2)), c.darkened(0.3), Vector3(0, 1.0 + sz * 0.55, -0.33)) # flap
