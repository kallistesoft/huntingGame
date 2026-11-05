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
		return
	var size := 1.0 + 0.1 * (tier - 1) # each tier is a bit bigger
	_model.scale = Vector3.ONE * size
	var wood := Color(0.5, 0.33, 0.18)
	var dark := wood.darkened(0.3)
	var stone := Color(0.5, 0.5, 0.52)
	var thatch := Color(0.72, 0.6, 0.3)
	var tile := Color(0.5, 0.18, 0.12)
	match kind:
		"crafting":
			# Tier 1: a bench with an anvil stone. Tier 2: a tool rack and a
			# fire pit. Tier 3: a roof on four posts and a second bench.
			Shapes.add(_model, Shapes.box(Vector3(r * 1.8, 0.12, r * 1.1)), wood.lightened(0.1), Vector3(0, 0.85, 0))
			for x in [-1, 1]:
				for z in [-1, 1]:
					Shapes.add(_model, Shapes.box(Vector3(0.12, 0.85, 0.12)), dark, Vector3(x * r * 0.8, 0.42, z * r * 0.45))
			if Models.spawn("anvil", _model, 0.4, Vector3(-0.3, 0.91, 0)) == null:
				Shapes.add(_model, Shapes.box(Vector3(0.5, 0.25, 0.3)), stone, Vector3(-0.3, 1.03, 0)) # anvil stone
			if tier >= 2:
				Shapes.add(_model, Shapes.cylinder(0.35, 0.3), Color(0.35, 0.3, 0.28), Vector3(r * 1.3, 0.15, 0)) # fire pit
				Shapes.add(_model, Shapes.cylinder(0.12, 0.3, 0.0), Color(1.0, 0.55, 0.1), Vector3(r * 1.3, 0.45, 0)) # ember
				Shapes.add(_model, Shapes.box(Vector3(0.1, 1.6, 0.1)), dark, Vector3(-r * 1.1, 0.8, -r * 0.7)) # tool rack
				Shapes.add(_model, Shapes.box(Vector3(0.9, 0.08, 0.08)), dark, Vector3(-r * 0.75, 1.5, -r * 0.7))
				Shapes.add(_model, Shapes.box(Vector3(0.22, 0.14, 0.05)), stone, Vector3(-r * 0.55, 1.25, -r * 0.7)) # hanging axe head
				Shapes.add(_model, Shapes.cylinder(0.025, 0.5), wood, Vector3(-r * 0.55, 1.1, -r * 0.7))
			if tier >= 3:
				for x in [-1, 1]:
					for z in [-1, 1]:
						Shapes.add(_model, Shapes.box(Vector3(0.14, 2.2, 0.14)), dark, Vector3(x * r * 1.4, 1.1, z * r * 1.1))
				var roof := PrismMesh.new()
				roof.size = Vector3(r * 3.2, 0.7, r * 2.6)
				Shapes.add(_model, roof, thatch, Vector3(0, 2.55, 0))
				Shapes.add(_model, Shapes.box(Vector3(r * 0.9, 0.1, r * 0.8)), wood.lightened(0.1), Vector3(r * 0.5, 0.7, -r * 0.9)) # second bench
				Shapes.add(_model, Shapes.box(Vector3(0.35, 0.2, 0.25)), Color(0.35, 0.37, 0.42), Vector3(r * 0.5, 0.85, -r * 0.9)) # iron anvil
		"storage":
			# Tier 1: a crate. Tier 2: a shed with a flat roof and barrels.
			# Tier 3: a barn with a pitched roof and a wide door.
			if tier == 1:
				if Models.spawn("crate", _model, 1.1) == null:
					Shapes.add(_model, Shapes.box(Vector3(r * 1.8, 1.0, r * 1.2)), wood, Vector3(0, 0.5, 0))
					Shapes.add(_model, Shapes.box(Vector3(r * 1.9, 0.12, r * 1.3)), dark, Vector3(0, 1.06, 0))
			else:
				var h := 1.5 if tier == 2 else 2.0
				Shapes.add(_model, Shapes.box(Vector3(r * 2.0, h, r * 1.6)), wood, Vector3(0, h / 2.0, 0))
				for i in 4: # plank lines
					Shapes.add(_model, Shapes.box(Vector3(r * 2.02, 0.04, r * 1.62)), dark, Vector3(0, 0.3 + i * (h - 0.4) / 3.0, 0))
				Shapes.add(_model, Shapes.box(Vector3(0.9, h * 0.6, 0.06)), dark, Vector3(0, h * 0.3, r * 0.8)) # door
				if tier == 2:
					Shapes.add(_model, Shapes.box(Vector3(r * 2.3, 0.12, r * 1.9)), dark, Vector3(0, h + 0.06, 0))
				else:
					var roof := PrismMesh.new()
					roof.size = Vector3(r * 2.4, 0.9, r * 2.0)
					Shapes.add(_model, roof, tile, Vector3(0, h + 0.45, 0))
					Shapes.add(_model, Shapes.box(Vector3(0.5, 0.5, 0.06)), Color(0.85, 0.9, 1.0), Vector3(0, h * 0.75, r * 0.81)) # loft window
				for i in tier - 1: # barrels beside it
					if Models.spawn("barrel", _model, 0.75, Vector3(r * 1.4, 0, -r * 0.5 + i * 0.7)) == null:
						Shapes.add(_model, Shapes.cylinder(0.3, 0.7), wood.lightened(0.2), Vector3(r * 1.4, 0.35, -r * 0.5 + i * 0.7))
						Shapes.add(_model, Shapes.cylinder(0.31, 0.06), dark, Vector3(r * 1.4, 0.35, -r * 0.5 + i * 0.7))
		"house":
			# Tier 1: a hut. Tier 2: chimney and window. Tier 3: a porch under
			# a wider roof and a second window.
			Shapes.add(_model, Shapes.box(Vector3(r * 1.9, 1.6, r * 1.9)), Color(0.62, 0.4, 0.25), Vector3(0, 0.8, 0))
			var roof := PrismMesh.new()
			roof.size = Vector3(r * 2.3, 1.1, r * (2.3 if tier < 3 else 3.1))
			Shapes.add(_model, roof, tile, Vector3(0, 2.15, 0 if tier < 3 else r * 0.4))
			Shapes.add(_model, Shapes.box(Vector3(0.5, 0.9, 0.05)), Color(0.3, 0.18, 0.1), Vector3(0, 0.45, r * 0.96)) # door
			if tier >= 2:
				Shapes.add(_model, Shapes.box(Vector3(0.3, 0.8, 0.3)), stone, Vector3(r * 0.6, 2.5, -0.3)) # chimney
				Shapes.add(_model, Shapes.box(Vector3(0.45, 0.45, 0.05)), Color(0.85, 0.9, 1.0), Vector3(-r * 0.5, 1.0, r * 0.96)) # window
			if tier >= 3:
				for x in [-1, 1]:
					Shapes.add(_model, Shapes.box(Vector3(0.12, 1.5, 0.12)), dark, Vector3(x * r * 0.95, 0.75, r * 1.5)) # porch posts
				Shapes.add(_model, Shapes.box(Vector3(r * 2.1, 0.08, r * 0.9)), wood, Vector3(0, 0.04, r * 1.35)) # porch floor
				Shapes.add(_model, Shapes.box(Vector3(0.45, 0.45, 0.05)), Color(0.85, 0.9, 1.0), Vector3(r * 0.95, 1.0, -r * 0.3)) # side window
		"tanning":
			# One stretched hide per tier, plus a drying line at tier 3.
			for i in tier:
				var z := -i * 0.7
				for x in [-1, 1]:
					Shapes.add(_model, Shapes.box(Vector3(0.14, 1.9 - i * 0.2, 0.14)), wood, Vector3(x * r * 0.9, 0.95 - i * 0.1, z))
				Shapes.add(_model, Shapes.box(Vector3(r * 1.95, 0.1, 0.1)), dark, Vector3(0, 1.85 - i * 0.2, z))
				var hide: Color = [Color(0.78, 0.6, 0.4), Color(0.62, 0.42, 0.26), Color(0.5, 0.5, 0.55)][i]
				Shapes.add(_model, Shapes.box(Vector3(r * 1.3, 1.15 - i * 0.1, 0.06)), hide, Vector3(0, 1.15 - i * 0.1, z))
			if tier >= 3:
				Shapes.add(_model, Shapes.cylinder(0.02, r * 2.4), dark, Vector3(0, 1.4, r * 0.9)).rotation_degrees.z = 90
				for i in 3:
					Shapes.add(_model, Shapes.box(Vector3(0.35, 0.5, 0.04)), Color(0.55, 0.52, 0.58), Vector3(-r * 0.7 + i * r * 0.7, 1.12, r * 0.9))
		"forge":
			# A stone hearth with a chimney stack, a glowing mouth and an anvil.
			Shapes.add(_model, Shapes.box(Vector3(r * 1.6, 1.2, r * 1.2)), stone, Vector3(0, 0.6, 0))
			Shapes.add(_model, Shapes.box(Vector3(0.6, 1.6, 0.6)), stone.darkened(0.15), Vector3(-r * 0.4, 1.9, -r * 0.2)) # stack
			Shapes.add(_model, Shapes.box(Vector3(0.6, 0.45, 0.1)), Color(1.0, 0.5, 0.1), Vector3(0.1, 0.55, r * 0.61)) # glowing mouth
			Shapes.add(_model, Shapes.cylinder(0.3, 0.6), dark, Vector3(r * 1.2, 0.3, 0.2)) # anvil stump
			if Models.spawn("anvil", _model, 0.45, Vector3(r * 1.2, 0.6, 0.2)) == null:
				Shapes.add(_model, Shapes.box(Vector3(0.45, 0.22, 0.28)), Color(0.35, 0.37, 0.42), Vector3(r * 1.2, 0.75, 0.2)) # anvil
			Shapes.add(_model, Shapes.box(Vector3(0.5, 0.25, 0.8)), wood, Vector3(-r * 1.2, 0.35, 0.3)) # bellows
			Shapes.add(_model, Shapes.cylinder(0.04, 0.9), dark, Vector3(-r * 1.2, 0.55, -0.2)).rotation_degrees.x = 90


func _build_board() -> void:
	var wood := Color(0.4, 0.26, 0.12)
	for x in [-1, 1]:
		Shapes.add(self, Shapes.box(Vector3(0.12, 1.8, 0.12)), wood, Vector3(x * 0.7, 0.9, 0))
	Shapes.add(self, Shapes.box(Vector3(1.7, 1.0, 0.08)), Color(0.6, 0.42, 0.22), Vector3(0, 1.4, 0))
	Shapes.add(self, Shapes.box(Vector3(0.5, 0.4, 0.02)), Color(0.95, 0.92, 0.8), Vector3(-0.35, 1.5, 0.05))
	Shapes.add(self, Shapes.box(Vector3(0.45, 0.5, 0.02)), Color(0.95, 0.92, 0.8), Vector3(0.35, 1.35, 0.05))
