extends Node3D
## A camp spot: crafting place, storage, house (built and upgraded with
## timers), or the quest board. Interacting opens its panel in the HUD.

const Shapes := preload("res://scripts/world/shapes.gd")
const Style := preload("res://scripts/ui/style.gd")
const Models := preload("res://scripts/world/models.gd")

var kind := "crafting"
var world: Node3D
var radius := 1.1

var _model: Node3D
var _label: Label3D
var _shown_tier := -1
var _bar: Node3D # progress over the roof while building or crafting
var _bar_fill: Node3D
var _bar_label: Label3D


func _ready() -> void:
	add_to_group("interactable")
	_label = Shapes.label(self, "", Vector3(0, 3.3 if kind == "house" else 2.2, 0), 40)
	if kind == "board":
		_build_board()
		_label.text = "Quests"
	else:
		_build_bar(4.1 if kind == "house" else 3.0)
	Game.changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if kind != "board":
		_update_bar()


## A bar above the building: dark track, orange fill that grows from the
## left, and a line of text. Tilted to face the fixed camera.
func _build_bar(height: float) -> void:
	_bar = Node3D.new()
	_bar.position = Vector3(0, height, 0)
	_bar.rotation_degrees.x = -35.0
	_bar.visible = false
	add_child(_bar)
	Shapes.add(_bar, Shapes.box(Vector3(1.7, 0.05, 0.22)), Color(0.08, 0.1, 0.08), Vector3(0, 0, 0))
	_bar_fill = Node3D.new()
	_bar_fill.position = Vector3(-0.8, 0.01, 0)
	_bar.add_child(_bar_fill)
	Shapes.add(_bar_fill, Shapes.box(Vector3(1.6, 0.06, 0.16)), Style.ACCENT, Vector3(0.8, 0, 0))
	_bar_label = Shapes.label(self, "", Vector3(0, height + 0.45, 0), 34)
	_bar_label.modulate = Style.ACCENT
	_bar_label.visible = false


func _update_bar() -> void:
	var text := ""
	var frac := 0.0
	if Game.structure_busy(kind):
		var next_tier: int = Game.structures[kind]["next_tier"]
		var total: float = Data.STRUCTURES[kind]["tiers"][next_tier - 1]["time"]
		var left: float = Game.structures[kind]["busy_until"] - Game.now()
		frac = 1.0 - clampf(left / total, 0.0, 1.0)
		text = "Tier %d · %s" % [next_tier, _fmt(left)]
	elif not Game.craft_queue(kind).is_empty():
		var job: Dictionary = Game.craft_job_at(kind)
		frac = 1.0 - clampf(Game.craft_left(kind) / Game.craft_total(kind), 0.0, 1.0)
		text = Data.recipe_name(job["recipe"]) + (" ×%d" % job["count"] if job["count"] > 1 else "") + " · " + _fmt(Game.craft_left(kind))
		var more := Game.craft_queue(kind).size() - 1
		if more > 0:
			text += "  +%d" % more
	_bar.visible = text != ""
	_bar_label.visible = text != ""
	if text == "":
		return
	_bar_fill.scale.x = maxf(0.01, frac)
	_bar_label.text = text


func is_available() -> bool:
	return true


func title() -> String:
	return "Quest board" if kind == "board" else Data.STRUCTURES[kind]["name"]


func action_label() -> String:
	if kind == "board":
		return "Read quests"
	if Game.structure_tier(kind) == 0 and not Game.structure_busy(kind):
		return "Build %s" % title().to_lower()
	return "Open %s" % title().to_lower()


func action_icon() -> String:
	if kind == "board":
		return "quest"
	if Game.structure_tier(kind) == 0 and not Game.structure_busy(kind):
		return "build"
	return "door"


func interact(_player: Node3D) -> void:
	world.open_station(self)


func _refresh() -> void:
	if kind == "board":
		return
	var tier := Game.structure_tier(kind)
	if tier != _shown_tier:
		var upgraded := _shown_tier >= 0 and tier > _shown_tier
		_shown_tier = tier
		_build_structure(tier)
		if upgraded:
			world.fx_built(self, tier)
			var target := _model.scale
			_model.scale = target * 0.6
			_model.create_tween().tween_property(_model, "scale", target, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var text := title() if tier > 0 else "Build: " + title()
	if tier > 0:
		text += " " + "★".repeat(tier)
	_label.text = text


static func _fmt(seconds: float) -> String:
	var s := ceili(maxf(0.0, seconds))
	return "%d:%02d" % [s / 60, s % 60]


## Where each kit model's door or working side is (degrees around Y), so it
## can be turned towards +Z, the side the camera sees.
const FACING := {"tent": 0.0, "shack": 0.0, "house": 0.0, "storage_hut": 0.0, "storage_shed": 0.0,
	"gazebo": 0.0, "sawmill_house": 0.0, "fireplace": 0.0, "blacksmith": 0.0}


func _build_structure(tier: int) -> void:
	if _model != null:
		_model.queue_free()
	_model = Node3D.new()
	add_child(_model)
	var r := radius
	if tier == 0:
		# Empty plot: four low posts and a string outline.
		for x in [-1, 1]:
			for z in [-1, 1]:
				Shapes.add(_model, Shapes.box(Vector3(0.12, 0.4, 0.12)), Color(0.5, 0.32, 0.14), Vector3(x * r, 0.2, z * r))
		Shapes.add(_model, Shapes.box(Vector3(r * 2, 0.02, r * 2)), Color(1, 1, 1, 0.25), Vector3(0, 0.02, 0))
		_place_signs(0.0)
		return
	var wood := Color(0.5, 0.33, 0.18)
	var dark := wood.darkened(0.3)
	var stone := Color(0.5, 0.5, 0.52)
	match kind:
		"crafting":
			# Tier 1: a workbench. Tier 2: a grindstone and an anvil bench beside
			# it. Tier 3: a roof over the lot and a log pile. Tier 4: a timber
			# workshop with its own saw and logs.
			if tier >= 4 and _building("sawmill_house", 3.6) != null:
				_building("sawmill_logs", 0.6, Vector3(r * 1.9, 0, r * 0.4))
			elif _building("workbench", 0.95, Vector3(0, 0, r * 0.15)) != null:
				if tier >= 2:
					_building("anvil", 0.85, Vector3(r * 1.2, 0, -r * 0.3))
					_building("workbench_grind", 0.9, Vector3(-r * 1.2, 0, -r * 0.3))
				if tier >= 3:
					_building("gazebo", 3.2, Vector3(0, 0, -r * 0.1))
					_building("sawmill_logs", 0.55, Vector3(r * 1.9, 0, r * 0.9))
			else:
				_build_crafting_shapes(tier, wood, dark, stone)
		"storage":
			# Tier 1: a crate. Tier 2: a plank hut on a deck. Tier 3: a stone
			# shed with a tiled roof, crates and barrels.
			var id: String = ["crate", "storage_hut", "storage_shed"][clampi(tier, 1, 3) - 1]
			if _building(id, [1.1, 2.8, 3.0][clampi(tier, 1, 3) - 1]) != null:
				for i in tier - 1: # barrels beside it
					_building("barrel", 0.75, Vector3(r * 1.6, 0, -r * 0.5 + i * 0.7))
			else:
				_build_storage_shapes(tier, wood, dark)
		"house":
			# Tier 1: a tent. Tier 2: a plank shack. Tier 3: a timber house with
			# a tiled roof and crates by the door.
			var id: String = ["tent", "shack", "house"][clampi(tier, 1, 3) - 1]
			var home := _building(id, [2.4, 2.6, 2.9][clampi(tier, 1, 3) - 1])
			if home == null:
				_build_house_shapes(tier, dark, stone)
			elif tier == 1: # the kit's army-green canvas becomes stitched hides
				Models.paint(home, ["Green"], Color(0.66, 0.5, 0.3))
				Models.paint(home, ["LightGreen"], Color(0.78, 0.62, 0.4))
		"tailor":
			# Tier 1: a dyed canvas tent. Tier 2: a stool and a cloth rack
			# beside it. Tier 3: a plank hut with crates of cloth. Tier 4: a
			# timber workshop with barrels of dye.
			var id: String = ["tent", "tent", "shack", "house"][clampi(tier, 1, 4) - 1]
			var shop := _building(id, [2.2, 2.2, 2.5, 2.8][clampi(tier, 1, 4) - 1])
			if shop == null:
				_build_tailor_shapes(tier, wood, dark)
			elif tier <= 2: # the kit's army-green canvas becomes dyed cloth
				Models.paint(shop, ["Green"], Color(0.36, 0.46, 0.62))
				Models.paint(shop, ["LightGreen"], Color(0.55, 0.64, 0.78))
			if tier >= 2: # cloth rack and stool
				for x in [-1, 1]:
					Shapes.add(_model, Shapes.box(Vector3(0.1, 1.3, 0.1)), wood, Vector3(r * 1.5 + x * 0.5, 0.65, 0.4))
				Shapes.add(_model, Shapes.box(Vector3(1.1, 0.06, 0.06)), dark, Vector3(r * 1.5, 1.3, 0.4))
				Shapes.add(_model, Shapes.box(Vector3(0.9, 0.8, 0.04)), Color(0.72, 0.4, 0.38), Vector3(r * 1.5, 0.9, 0.4))
				Shapes.add(_model, Shapes.cylinder(0.2, 0.4), wood, Vector3(r * 1.3, 0.2, -0.6))
			if tier >= 3:
				_building("crate", 0.7, Vector3(-r * 1.3, 0, r * 0.9))
			if tier >= 4:
				for i in 2:
					_building("barrel", 0.75, Vector3(-r * 1.4, 0, -r * 0.4 + i * 0.7))
		"kitchen":
			# Tier 1: a cooking fire with a spit. Tier 2: a clay oven beside it.
			# Tier 3: a stone hearth with a prep table and a barrel. Tier 4: a
			# smokehouse behind the hearth, crates of provisions in front.
			if tier >= 4:
				var smokehouse := _building("shack", 2.4, Vector3(-r * 0.5, 0, -r * 0.9))
				if smokehouse != null:
					Models.tint(smokehouse, Color(0.55, 0.5, 0.48)) # weathered, smoke-stained
				else:
					Shapes.add(_model, Shapes.box(Vector3(1.8, 1.6, 1.4)), dark, Vector3(-r * 0.5, 0.8, -r * 0.9))
				Shapes.add(_model, Shapes.cylinder(0.14, 0.9), stone.darkened(0.2), Vector3(-r * 0.9, 1.9, -r * 1.1)) # chimney
				_building("crate", 0.65, Vector3(r * 1.3, 0, r * 1.0))
			if tier >= 3:
				var hearth := _building("fireplace", 1.9, Vector3(r * 0.6 if tier >= 4 else 0.0, 0, r * 0.3))
				if hearth != null:
					Shapes.add(_model, Shapes.box(Vector3(0.5, 0.35, 0.1)), Color(1.0, 0.55, 0.15), Vector3(r * 0.6 if tier >= 4 else 0.0, 0.4, r * 0.75)) # fire
				else:
					_build_kitchen_fire(stone)
				Shapes.add(_model, Shapes.box(Vector3(1.2, 0.08, 0.6)), wood, Vector3(-r * 1.3, 0.8, r * 0.6)) # prep table
				for x in [-1, 1]:
					Shapes.add(_model, Shapes.cylinder(0.05, 0.8), dark, Vector3(-r * 1.3 + x * 0.5, 0.4, r * 0.6))
				_building("barrel", 0.7, Vector3(r * 1.4, 0, -r * 0.3))
			else:
				if _building("campfire", 0.8, Vector3(0, 0, r * 0.2)) == null:
					_build_kitchen_fire(stone)
				for x in [-1, 1]: # the spit
					Shapes.add(_model, Shapes.box(Vector3(0.08, 1.0, 0.08)), dark, Vector3(x * 0.6, 0.5, r * 0.2))
				Shapes.add(_model, Shapes.cylinder(0.025, 1.3), dark, Vector3(0, 0.95, r * 0.2)).rotation_degrees.z = 90
				Shapes.add(_model, Shapes.capsule(0.12, 0.45), Color(0.72, 0.4, 0.3), Vector3(0, 0.95, r * 0.2)).rotation_degrees.z = 90
			if tier == 2 or tier == 3: # clay oven: a dome on a stone base
				var at := Vector3(-r * 1.2, 0, -r * 0.5) if tier == 2 else Vector3(r * 1.3, 0, r * 0.9)
				Shapes.add(_model, Shapes.box(Vector3(1.0, 0.35, 1.0)), stone, at + Vector3(0, 0.175, 0))
				Shapes.add(_model, Shapes.sphere(0.48), Color(0.74, 0.5, 0.36), at + Vector3(0, 0.45, 0))
				Shapes.add(_model, Shapes.box(Vector3(0.3, 0.22, 0.12)), Color(0.12, 0.08, 0.06), at + Vector3(0, 0.4, 0.44))
		"tanning":
			# One stretched hide per tier, plus a drying line at tier 3. No kit
			# has a tanning rack, so this one stays code-built.
			for i in tier:
				var z := -i * 0.7
				for x in [-1, 1]:
					Shapes.add(_model, Shapes.box(Vector3(0.14, 1.9 - i * 0.2, 0.14)), wood, Vector3(x * r * 0.9, 0.95 - i * 0.1, z))
				Shapes.add(_model, Shapes.box(Vector3(r * 1.95, 0.1, 0.1)), dark, Vector3(0, 1.85 - i * 0.2, z))
				var hide: Color = [Color(0.78, 0.6, 0.4), Color(0.62, 0.42, 0.26), Color(0.5, 0.5, 0.55), Color(0.9, 0.9, 0.94)][i]
				Shapes.add(_model, Shapes.box(Vector3(r * 1.3, 1.15 - i * 0.1, 0.06)), hide, Vector3(0, 1.15 - i * 0.1, z))
			if tier >= 3:
				Shapes.add(_model, Shapes.cylinder(0.02, r * 2.4), dark, Vector3(0, 1.4, r * 0.9)).rotation_degrees.z = 90
				for i in 3:
					Shapes.add(_model, Shapes.box(Vector3(0.35, 0.5, 0.04)), Color(0.55, 0.52, 0.58), Vector3(-r * 0.7 + i * r * 0.7, 1.12, r * 0.9))
			_building("barrel", 0.7, Vector3(r * 1.5, 0, r * 0.6))
		"forge":
			# Tier 1: a stone hearth with a glowing mouth and an anvil on a
			# stump. Tier 2: the whole smithy, chimney included.
			if tier >= 2 and _building("blacksmith", 3.6) != null:
				Shapes.add(_model, Shapes.box(Vector3(0.5, 0.4, 0.1)), Color(1.0, 0.5, 0.1), Vector3(-r * 0.2, 0.5, r * 1.21)) # glow by the door
			elif _building("fireplace", 2.2) != null:
				Shapes.add(_model, Shapes.box(Vector3(0.6, 1.4, 0.6)), stone.darkened(0.15), Vector3(-r * 0.3, 1.9, -r * 0.2)) # stack
				Shapes.add(_model, Shapes.box(Vector3(0.6, 0.4, 0.1)), Color(1.0, 0.5, 0.1), Vector3(0.0, 0.45, r * 0.52)) # glowing mouth
			else:
				_build_forge_shapes(wood, dark, stone)
			Shapes.add(_model, Shapes.cylinder(0.3, 0.6), dark, Vector3(r * 1.4, 0.3, 0.3)) # anvil stump
			if _building("anvil", 0.45, Vector3(r * 1.4, 0.6, 0.3)) == null:
				Shapes.add(_model, Shapes.box(Vector3(0.45, 0.22, 0.28)), Color(0.35, 0.37, 0.42), Vector3(r * 1.4, 0.75, 0.3))
	_place_signs(Models.bounds(_model).end.y)


## Spawns a kit model as part of the building, turned to face the camera.
## Buildings (those in FACING) are sized by their footprint so they stay on
## their plot; props by their height.
func _building(id: String, size: float, pos := Vector3.ZERO) -> Node3D:
	if not FACING.has(id):
		return Models.spawn(id, _model, size, pos)
	var node := Models.spawn_fit(id, _model, size, pos)
	if node != null:
		node.rotation_degrees.y = FACING[id]
	return node


## Lifts the label and the progress bar above whatever was built.
func _place_signs(top: float) -> void:
	var base := 3.3 if kind == "house" else 2.2
	_label.position.y = maxf(base, top + 0.6)
	if _bar != null:
		_bar.position.y = maxf(base + 0.8, top + 1.3)
		_bar_label.position.y = _bar.position.y + 0.45


# --- Code-built fallbacks, used when a kit model is missing -----------------

func _build_crafting_shapes(tier: int, wood: Color, dark: Color, stone: Color) -> void:
	var r := radius
	Shapes.add(_model, Shapes.box(Vector3(r * 1.8, 0.12, r * 1.1)), wood.lightened(0.1), Vector3(0, 0.85, 0))
	for x in [-1, 1]:
		for z in [-1, 1]:
			Shapes.add(_model, Shapes.box(Vector3(0.12, 0.85, 0.12)), dark, Vector3(x * r * 0.8, 0.42, z * r * 0.45))
	Shapes.add(_model, Shapes.box(Vector3(0.5, 0.25, 0.3)), stone, Vector3(-0.3, 1.03, 0)) # anvil stone
	if tier >= 2:
		Shapes.add(_model, Shapes.cylinder(0.35, 0.3), Color(0.35, 0.3, 0.28), Vector3(r * 1.3, 0.15, 0)) # fire pit
		Shapes.add(_model, Shapes.cylinder(0.12, 0.3, 0.0), Color(1.0, 0.55, 0.1), Vector3(r * 1.3, 0.45, 0)) # ember
		Shapes.add(_model, Shapes.box(Vector3(0.1, 1.6, 0.1)), dark, Vector3(-r * 1.1, 0.8, -r * 0.7)) # tool rack
		Shapes.add(_model, Shapes.box(Vector3(0.9, 0.08, 0.08)), dark, Vector3(-r * 0.75, 1.5, -r * 0.7))
	if tier >= 3:
		for x in [-1, 1]:
			for z in [-1, 1]:
				Shapes.add(_model, Shapes.box(Vector3(0.14, 2.2, 0.14)), dark, Vector3(x * r * 1.4, 1.1, z * r * 1.1))
		var roof := PrismMesh.new()
		roof.size = Vector3(r * 3.2, 0.7, r * 2.6)
		Shapes.add(_model, roof, Color(0.72, 0.6, 0.3), Vector3(0, 2.55, 0))


func _build_storage_shapes(tier: int, wood: Color, dark: Color) -> void:
	var r := radius
	if tier == 1:
		Shapes.add(_model, Shapes.box(Vector3(r * 1.8, 1.0, r * 1.2)), wood, Vector3(0, 0.5, 0))
		Shapes.add(_model, Shapes.box(Vector3(r * 1.9, 0.12, r * 1.3)), dark, Vector3(0, 1.06, 0))
		return
	var h := 1.5 if tier == 2 else 2.0
	Shapes.add(_model, Shapes.box(Vector3(r * 2.0, h, r * 1.6)), wood, Vector3(0, h / 2.0, 0))
	Shapes.add(_model, Shapes.box(Vector3(0.9, h * 0.6, 0.06)), dark, Vector3(0, h * 0.3, r * 0.8)) # door
	if tier == 2:
		Shapes.add(_model, Shapes.box(Vector3(r * 2.3, 0.12, r * 1.9)), dark, Vector3(0, h + 0.06, 0))
	else:
		var roof := PrismMesh.new()
		roof.size = Vector3(r * 2.4, 0.9, r * 2.0)
		Shapes.add(_model, roof, Color(0.5, 0.18, 0.12), Vector3(0, h + 0.45, 0))


## A canvas ridge tent: two leaning panels on a pole, bigger with the tier.
## A ring of stones with logs and a flame, when the campfire model is missing.
func _build_kitchen_fire(stone: Color) -> void:
	for i in 8:
		var a := i * TAU / 8.0
		Shapes.add(_model, Shapes.sphere(0.14), stone, Vector3(cos(a) * 0.5, 0.1, sin(a) * 0.5 + radius * 0.2))
	Shapes.add(_model, Shapes.cylinder(0.07, 0.7), Color(0.4, 0.26, 0.14), Vector3(0, 0.12, radius * 0.2)).rotation_degrees.z = 90
	Shapes.add(_model, Shapes.cylinder(0.07, 0.7), Color(0.4, 0.26, 0.14), Vector3(0, 0.12, radius * 0.2)).rotation_degrees.x = 90
	Shapes.add(_model, Shapes.sphere(0.22), Color(1.0, 0.55, 0.15), Vector3(0, 0.32, radius * 0.2))


func _build_tailor_shapes(tier: int, wood: Color, dark: Color) -> void:
	var cloth := Color(0.36, 0.46, 0.62) if tier <= 2 else Color(0.6, 0.45, 0.3)
	var w := 1.6 + tier * 0.2
	for x in [-1, 1]:
		var panel := Shapes.add(_model, Shapes.box(Vector3(w * 0.75, 0.05, w)), cloth, Vector3(x * w * 0.3, 0.65, 0))
		panel.rotation_degrees.z = -x * 55.0
	Shapes.add(_model, Shapes.cylinder(0.05, 1.3), wood, Vector3(0, 0.65, 0))
	Shapes.add(_model, Shapes.box(Vector3(0.06, 0.06, w)), dark, Vector3(0, 1.3, 0))


func _build_house_shapes(tier: int, dark: Color, stone: Color) -> void:
	var r := radius
	Shapes.add(_model, Shapes.box(Vector3(r * 1.9, 1.6, r * 1.9)), Color(0.62, 0.4, 0.25), Vector3(0, 0.8, 0))
	var roof := PrismMesh.new()
	roof.size = Vector3(r * 2.3, 1.1, r * (2.3 if tier < 3 else 3.1))
	Shapes.add(_model, roof, Color(0.5, 0.18, 0.12), Vector3(0, 2.15, 0 if tier < 3 else r * 0.4))
	Shapes.add(_model, Shapes.box(Vector3(0.5, 0.9, 0.05)), Color(0.3, 0.18, 0.1), Vector3(0, 0.45, r * 0.96)) # door
	if tier >= 2:
		Shapes.add(_model, Shapes.box(Vector3(0.3, 0.8, 0.3)), stone, Vector3(r * 0.6, 2.5, -0.3)) # chimney
	if tier >= 3:
		for x in [-1, 1]:
			Shapes.add(_model, Shapes.box(Vector3(0.12, 1.5, 0.12)), dark, Vector3(x * r * 0.95, 0.75, r * 1.5)) # porch posts


func _build_forge_shapes(wood: Color, dark: Color, stone: Color) -> void:
	var r := radius
	Shapes.add(_model, Shapes.box(Vector3(r * 1.6, 1.2, r * 1.2)), stone, Vector3(0, 0.6, 0))
	Shapes.add(_model, Shapes.box(Vector3(0.6, 1.6, 0.6)), stone.darkened(0.15), Vector3(-r * 0.4, 1.9, -r * 0.2)) # stack
	Shapes.add(_model, Shapes.box(Vector3(0.6, 0.45, 0.1)), Color(1.0, 0.5, 0.1), Vector3(0.1, 0.55, r * 0.61)) # glowing mouth
	Shapes.add(_model, Shapes.box(Vector3(0.5, 0.25, 0.8)), wood, Vector3(-r * 1.2, 0.35, 0.3)) # bellows
	Shapes.add(_model, Shapes.cylinder(0.04, 0.9), dark, Vector3(-r * 1.2, 0.55, -0.2)).rotation_degrees.x = 90


func _build_board() -> void:
	var wood := Color(0.4, 0.26, 0.12)
	for x in [-1, 1]:
		Shapes.add(self, Shapes.box(Vector3(0.12, 1.8, 0.12)), wood, Vector3(x * 0.7, 0.9, 0))
	Shapes.add(self, Shapes.box(Vector3(1.7, 1.0, 0.08)), Color(0.6, 0.42, 0.22), Vector3(0, 1.4, 0))
	Shapes.add(self, Shapes.box(Vector3(0.5, 0.4, 0.02)), Color(0.95, 0.92, 0.8), Vector3(-0.35, 1.5, 0.05))
	Shapes.add(self, Shapes.box(Vector3(0.45, 0.5, 0.02)), Color(0.95, 0.92, 0.8), Vector3(0.35, 1.35, 0.05))
