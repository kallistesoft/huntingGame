extends Node3D
## A camp spot: crafting place, storage, house (built and upgraded with
## timers), or the quest board. Interacting opens its panel in the HUD.

const Shapes := preload("res://scripts/world/shapes.gd")
const Style := preload("res://scripts/ui/style.gd")

var kind := "crafting"
var world: Node3D
var radius := 1.1

var _model: Node3D
var _label: Label3D
var _shown_tier := -1


func _ready() -> void:
	add_to_group("interactable")
	_label = Shapes.label(self, "", Vector3(0, 3.6 if kind == "house" else 2.6, 0), 40)
	if kind == "board":
		_build_board()
		_label.text = "Quests"
	Game.changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if kind != "board" and Game.structure_busy(kind):
		_refresh()


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
	if Game.structure_busy(kind):
		text += "\nBuilding… %s" % _fmt(Game.structures[kind]["busy_until"] - Game.now())
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
	var size := 1.0 + 0.12 * (tier - 1) # each tier is a bit bigger
	_model.scale = Vector3.ONE * size
	match kind:
		"crafting":
			var wood := Color(0.55, 0.36, 0.2)
			Shapes.add(_model, Shapes.box(Vector3(r * 1.8, 0.12, r * 1.1)), wood, Vector3(0, 0.85, 0))
			for x in [-1, 1]:
				for z in [-1, 1]:
					Shapes.add(_model, Shapes.box(Vector3(0.12, 0.85, 0.12)), wood.darkened(0.3), Vector3(x * r * 0.8, 0.42, z * r * 0.45))
			Shapes.add(_model, Shapes.box(Vector3(0.5, 0.25, 0.3)), Color(0.5, 0.5, 0.52), Vector3(-0.3, 1.03, 0)) # anvil stone
			if tier >= 2:
				Shapes.add(_model, Shapes.cylinder(0.35, 0.3), Color(0.35, 0.3, 0.28), Vector3(r * 1.3, 0.15, 0)) # fire pit
			if tier >= 3:
				Shapes.add(_model, Shapes.box(Vector3(r * 1.8, 0.08, r * 1.3)), Color(0.5, 0.18, 0.12), Vector3(0, 2.0, 0)) # roof
		"storage":
			var wood := Color(0.45, 0.3, 0.18)
			Shapes.add(_model, Shapes.box(Vector3(r * 1.8, 1.0, r * 1.2)), wood, Vector3(0, 0.5, 0))
			Shapes.add(_model, Shapes.box(Vector3(r * 1.9, 0.12, r * 1.3)), wood.darkened(0.3), Vector3(0, 1.06, 0))
			for i in tier - 1:
				Shapes.add(_model, Shapes.box(Vector3(0.6, 0.6, 0.6)), wood.lightened(0.15), Vector3(r * 1.25, 0.3 + i * 0.6, -0.2))
		"house":
			Shapes.add(_model, Shapes.box(Vector3(r * 1.9, 1.6, r * 1.9)), Color(0.62, 0.4, 0.25), Vector3(0, 0.8, 0))
			var roof := PrismMesh.new()
			roof.size = Vector3(r * 2.3, 1.1, r * 2.3)
			Shapes.add(_model, roof, Color(0.5, 0.18, 0.12), Vector3(0, 2.15, 0))
			Shapes.add(_model, Shapes.box(Vector3(0.5, 0.9, 0.05)), Color(0.3, 0.18, 0.1), Vector3(0, 0.45, r * 0.96)) # door
			if tier >= 2:
				Shapes.add(_model, Shapes.box(Vector3(0.3, 0.8, 0.3)), Color(0.5, 0.5, 0.52), Vector3(r * 0.6, 2.5, -0.3)) # chimney


func _build_board() -> void:
	var wood := Color(0.4, 0.26, 0.12)
	for x in [-1, 1]:
		Shapes.add(self, Shapes.box(Vector3(0.12, 1.8, 0.12)), wood, Vector3(x * 0.7, 0.9, 0))
	Shapes.add(self, Shapes.box(Vector3(1.7, 1.0, 0.08)), Color(0.6, 0.42, 0.22), Vector3(0, 1.4, 0))
	Shapes.add(self, Shapes.box(Vector3(0.5, 0.4, 0.02)), Color(0.95, 0.92, 0.8), Vector3(-0.35, 1.5, 0.05))
	Shapes.add(self, Shapes.box(Vector3(0.45, 0.5, 0.02)), Color(0.95, 0.92, 0.8), Vector3(0.35, 1.35, 0.05))
