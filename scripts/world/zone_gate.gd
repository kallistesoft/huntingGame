extends Node3D
## A pass between two zones: stone pillars with mountains behind. Shows what
## the next zone needs (level, boss) and lets the hunter cross once it is
## open. Crossing into a zone that is not built yet ends the demo.

const Shapes := preload("res://scripts/world/shapes.gd")

var target_zone := 1 # index in Data.ZONES, or ZONES.size() for the zone to come
var radius := 1.6
var _label: Label3D


func _ready() -> void:
	add_to_group("interactable")
	var stone := Color(0.55, 0.55, 0.58)
	for x in [-1, 1]:
		Shapes.add(self, Shapes.box(Vector3(0.9, 3.4, 0.9)), stone, Vector3(x * 1.6, 1.7, 0))
	Shapes.add(self, Shapes.box(Vector3(4.2, 0.8, 1.0)), stone.darkened(0.15), Vector3(0, 3.6, 0))
	# Mountains behind the pass, only when nothing is built beyond it yet.
	for i in (5 if target_zone >= Data.ZONES.size() else 0):
		var peak := Shapes.add(self, Shapes.cylinder(2.2 + i % 2, 5.0 + (i % 3) * 1.5, 0.0), Color(0.45, 0.47, 0.52),
			Vector3(-5.0 + i * 2.5, 2.5 + (i % 3) * 0.75, -3.0 - (i % 2) * 1.5))
		Shapes.add(peak, Shapes.cylinder(0.75, 1.2, 0.0), Color(0.95, 0.96, 1.0), Vector3(0, 2.0 + (i % 3) * 0.75, 0))
	_label = Shapes.label(self, "", Vector3(0, 4.8, 0), 40)
	Game.changed.connect(_refresh)
	Game.leveled_up.connect(func(_l: int) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	var z: Dictionary = Data.zone(target_zone)
	var u: Dictionary = z["unlock"]
	var need := "Needs level %d" % u["level"]
	if u["boss"] != "":
		need += " + %s" % Data.BOSSES[u["boss"]]["name"]
	var open := Game.zone_unlocked(target_zone)
	_label.text = z["entry"]["name"] + ("\nOpen!" if open else "\n" + need)
	_label.modulate = Color(0.6, 1.0, 0.6) if open else Color.WHITE


func is_available() -> bool:
	return true


func action_label() -> String:
	return "Take the %s" % Data.zone(target_zone)["entry"]["name"].to_lower()


func action_icon() -> String:
	return "door"


func interact(_player: Node3D) -> void:
	Game.cross_into(target_zone)
