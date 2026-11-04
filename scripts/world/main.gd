extends Node3D
## Builds the 3D world in code from Data.ZONES: ground, props, animals,
## bosses, gates and outposts per zone, plus the camp, the hunter, the camera
## and the UI. Map rectangles are on the ground plane: Rect2 x = world x,
## Rect2 y = world z.

const CAMP := Rect2(5.5, 11, 16, 10.5)
const PLAYER_START := Vector2(12, 16.5)
const HOUSE_SPOT := Vector2(2.75, 7.75) # house position inside the camp
const WORLD_SEED := 7
const CAMERA_OFFSET := Vector3(0, 13, 9) # above and behind the hunter
const CAMERA_FOLLOW := 6.0
const DAY_SECONDS := 720.0 # one full day/night cycle, real time

const Shapes := preload("res://scripts/world/shapes.gd")
const Fx := preload("res://scripts/world/fx.gd")
const Style := preload("res://scripts/ui/style.gd")
const Ground := preload("res://scripts/world/ground.gd")
const Player := preload("res://scripts/world/player.gd")
const ResourceNode := preload("res://scripts/world/resource_node.gd")
const Animal := preload("res://scripts/world/animal.gd")
const Station := preload("res://scripts/world/station.gd")
const Boss := preload("res://scripts/world/boss.gd")
const ZoneGate := preload("res://scripts/world/zone_gate.gd")
const Outpost := preload("res://scripts/world/outpost.gd")
const Hud := preload("res://scripts/ui/hud.gd")

var player: Node3D
var hud: Control
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var _sky_material: ProceduralSkyMaterial
var _rng := RandomNumberGenerator.new()
var _shake := 0.0
var _taken: Array[Vector3] = [] # x, z, radius of placed props, to keep them apart


func _ready() -> void:
	_rng.seed = WORLD_SEED
	_add_environment()

	var ground := Ground.new()
	ground.camp = CAMP
	add_child(ground)

	player = Player.new()
	player.world = self
	var start := Game.player_position if Game.has_player_position else PLAYER_START
	if not walk_bounds().has_point(start):
		start = PLAYER_START
	player.position = Vector3(start.x, 0, start.y)
	add_child(player)

	camera = Camera3D.new()
	camera.fov = 50
	add_child(camera)
	_place_camera(1.0)

	_add_station("crafting", CAMP.position + Vector2(2.75, 2.75))
	_add_station("storage", CAMP.position + Vector2(7.5, 2.75))
	_add_station("house", CAMP.position + HOUSE_SPOT)
	_add_station("tanning", CAMP.position + Vector2(13.0, 2.75))
	_add_station("forge", CAMP.position + Vector2(14.0, 7.75))
	_add_station("board", CAMP.position + Vector2(9.5, 7.75))

	# Reserve the spots that must stay clear of trees and rocks, then fill
	# each zone from its data.
	for i in Data.ZONES.size():
		var z: Dictionary = Data.ZONES[i]
		if z["boss"] != "":
			var b: Dictionary = Data.BOSSES[z["boss"]]
			_taken.append(Vector3(b["lair"].x, b["lair"].y, b["lair_radius"]))
		if z["outpost"] != null:
			_taken.append(Vector3(z["outpost"].x, z["outpost"].y, 3.0))
	for i in range(1, Data.ZONES.size() + 1):
		var entry: Dictionary = Data.zone(i)["entry"]
		if entry.get("kind", "") == "pass":
			_taken.append(Vector3(entry["position"].x - 1.0, entry["position"].y, 4.0))

	for i in Data.ZONES.size():
		var z: Dictionary = Data.ZONES[i]
		for pond in z["ponds"]:
			_add_prop("pond", pond)
		if z["boss"] != "":
			var boss := Boss.new()
			boss.kind = z["boss"]
			boss.player = player
			boss.world = self
			boss.position = Vector3(Data.BOSSES[z["boss"]]["lair"].x, 0, Data.BOSSES[z["boss"]]["lair"].y)
			add_child(boss)
		if z["outpost"] != null:
			_add_outpost(z["outpost"])
	for i in range(1, Data.ZONES.size() + 1):
		var entry: Dictionary = Data.zone(i)["entry"]
		if entry.get("kind", "") == "pass":
			var gate := ZoneGate.new()
			gate.target_zone = i
			gate.position = Vector3(entry["position"].x, 0, entry["position"].y)
			gate.rotation_degrees.y = entry.get("facing", 0)
			add_child(gate)

	for z in Data.ZONES:
		for kind in z["resources"]:
			_scatter(kind, z["rect"], z["resources"][kind])
	for z in Data.ZONES:
		for kind in z["animals"]:
			_spawn_animals(kind, z["rect"], z["animals"][kind])

	Game.respawned.connect(_on_respawned)
	Game.crafted.connect(_on_crafted)

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.player = player
	ui.add_child(hud)


func _process(delta: float) -> void:
	_place_camera(minf(1.0, CAMERA_FOLLOW * delta))
	_update_daylight()


## Where we are in the day, 0..1: 0 dawn, 0.25 noon, 0.5 dusk, 0.75 midnight.
## Driven by the clock (plus a dev offset) so it's the same across launches.
func day_phase() -> float:
	return fposmod((Game.now() + Game.time_offset) / DAY_SECONDS, 1.0)


## Four key looks blended around the clock. Night keeps about half the
## light with a blue tint so the game stays readable.
const DAYLIGHT := [
	# phase, sun energy, sun colour, ambient colour, ambient energy, sky top, sky horizon, fog
	[0.0, 0.8, Color(1.0, 0.8, 0.6), Color(0.8, 0.7, 0.75), 0.45, Color(0.55, 0.55, 0.8), Color(0.95, 0.75, 0.6), Color(0.85, 0.7, 0.65)],   # dawn
	[0.25, 1.25, Color(1.0, 0.95, 0.85), Color(0.72, 0.78, 0.9), 0.5, Color(0.32, 0.55, 0.85), Color(0.78, 0.86, 0.92), Color(0.72, 0.82, 0.9)], # noon
	[0.5, 0.85, Color(1.0, 0.7, 0.5), Color(0.8, 0.65, 0.7), 0.45, Color(0.4, 0.4, 0.75), Color(0.95, 0.65, 0.5), Color(0.8, 0.62, 0.6)],     # dusk
	[0.75, 0.55, Color(0.6, 0.7, 1.0), Color(0.45, 0.55, 0.85), 0.5, Color(0.08, 0.1, 0.25), Color(0.25, 0.3, 0.5), Color(0.3, 0.35, 0.55)],   # night
]


## The blended look for a phase: [sun energy, sun colour, ambient colour,
## ambient energy, sky top, sky horizon, fog].
static func daylight_at(phase: float) -> Array:
	var n := DAYLIGHT.size()
	for i in n:
		var a: Array = DAYLIGHT[i]
		var b: Array = DAYLIGHT[(i + 1) % n]
		var end: float = b[0] if i + 1 < n else 1.0
		if phase >= a[0] and phase < end:
			var t: float = (phase - a[0]) / (end - a[0])
			t = t * t * (3.0 - 2.0 * t) # smooth step
			var out := []
			for k in range(1, a.size()):
				out.append(lerp(a[k], b[k], t))
			return out
	return DAYLIGHT[0].slice(1)


func _update_daylight() -> void:
	var phase := day_phase()
	var look := daylight_at(phase)
	sun.light_energy = look[0]
	sun.light_color = look[1]
	env.ambient_light_color = look[2]
	env.ambient_light_energy = look[3]
	_sky_material.sky_top_color = look[4]
	_sky_material.sky_horizon_color = look[5]
	env.fog_light_color = look[6]
	# The sun crosses the sky from dawn to dusk and sits low at night.
	var angle := -20.0 - 60.0 * sin(phase * TAU) if phase < 0.5 else -30.0
	sun.rotation_degrees = Vector3(angle, -30 + 60 * phase, 0)


func _place_camera(weight: float) -> void:
	camera.position = camera.position.lerp(player.position + CAMERA_OFFSET, weight)
	camera.look_at(camera.position - CAMERA_OFFSET)
	if _shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * _shake
		camera.v_offset = randf_range(-1.0, 1.0) * _shake
		_shake = maxf(0.0, _shake - get_process_delta_time() * 1.5)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _add_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.55, 0.85)
	sky_material.sky_horizon_color = Color(0.78, 0.86, 0.92)
	sky_material.ground_horizon_color = Color(0.6, 0.66, 0.6)
	sky_material.ground_bottom_color = Color(0.25, 0.3, 0.22)
	_sky_material = sky_material
	var sky := Sky.new()
	sky.sky_material = sky_material
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.9)
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.82, 0.9)
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)


## After giving up: back to the house door, or the middle of camp.
func _on_respawned(at_house: bool) -> void:
	var spot := PLAYER_START
	if at_house:
		spot = CAMP.position + HOUSE_SPOT + Vector2(0, 1.8) # in front of the door
	player.position = Vector3(spot.x, 0, spot.y)
	camera.position = player.position + CAMERA_OFFSET


## Where the hunter may walk: every unlocked zone.
func walk_bounds() -> Rect2:
	var bounds: Rect2 = Data.ZONES[0]["rect"]
	for i in range(1, Data.ZONES.size()):
		if Game.zone_unlocked(i):
			bounds = bounds.merge(Data.ZONES[i]["rect"])
	return bounds.grow(-0.5)


## The whole map, unlocked or not.
func map_bounds() -> Rect2:
	var bounds: Rect2 = Data.ZONES[0]["rect"]
	for z in Data.ZONES:
		bounds = bounds.merge(z["rect"])
	return bounds


## The boss node of a kind ("boar"), or null.
func boss_node(kind: String) -> Node3D:
	for node in get_tree().get_nodes_in_group("boss"):
		if node.kind == kind:
			return node
	return null


# --- Feedback effects ---------------------------------------------------------

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func vibrate(ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


func fx_gather(node: Node3D, item: String, n: int, xp: int) -> void:
	var color: Color = Style.ITEM_COLORS.get(item, Color.WHITE)
	var top := node.global_position + Vector3(0, 1.4, 0)
	Fx.burst(self, node.global_position + Vector3(0, 0.7, 0), color, 8)
	Fx.float_text(self, top, "+%d %s" % [n, Data.item_name(item)], Style.TEXT)
	Fx.float_text(self, top + Vector3(0, -0.4, 0), "+%d XP" % xp, Style.XP, 0.12)
	hud.fly_to_bag(camera.unproject_position(top), color, n)
	Sfx.play("chop" if item in ["wood", "stone", "iron_ore", "silver_ore"] else "pick")
	shake(0.05)
	vibrate(15)


func fx_drink(node: Node3D) -> void:
	Fx.burst(self, Vector3(player.position.x, 0.2, player.position.z), Style.WATER, 10, 0.06, 2.0)
	Fx.float_text(self, player.position + Vector3(0, 2.0, 0), "+Water", Style.WATER)
	Sfx.play("eat")


func fx_hit(node: Node3D) -> void:
	Fx.burst(self, node.global_position + Vector3(0, 0.4, 0), Color(0.95, 0.92, 0.85), 8, 0.06, 2.0)
	Sfx.play("hit")
	shake(0.12)
	vibrate(30)


func fx_kill(node: Node3D, kind: String) -> void:
	var d: Dictionary = Data.ANIMALS[kind]
	var top := node.global_position + Vector3(0, 1.4, 0)
	var line := 0
	for item in d["drops"]:
		Fx.float_text(self, top + Vector3(0, 0.45 * line, 0), "+%d %s" % [d["drops"][item], Data.item_name(item)], Style.TEXT, 0.12 * line)
		hud.fly_to_bag(camera.unproject_position(top), Style.ITEM_COLORS.get(item, Color.WHITE), d["drops"][item])
		line += 1
	Fx.float_text(self, top + Vector3(0, -0.45, 0), "+%d XP" % Game.xp_with_boost(d["xp"]), Style.XP, 0.12 * line)
	Sfx.play("kill")
	shake(0.22)
	vibrate(60)


func fx_built(node: Node3D, tier: int) -> void:
	Fx.burst(self, node.global_position + Vector3(0, 1.0, 0), Style.ACCENT, 24, 0.1, 5.0)
	Fx.burst(self, node.global_position + Vector3(0, 1.0, 0), Style.ENERGY, 16, 0.07, 4.0)
	Fx.float_text(self, node.global_position + Vector3(0, 3.2, 0), "Tier %d!" % tier, Style.ACCENT)
	Sfx.play("build_done", 0.0)
	shake(0.15)
	vibrate(40)


## A new piece of equipment is worn: a burst on the hunter and its name.
func _on_crafted(recipe_id: String) -> void:
	var r: Dictionary = Data.RECIPES[recipe_id]
	Sfx.play("craft_done", 0.0)
	if not r.has("tool"):
		return
	Fx.burst(self, player.position + Vector3(0, 1.0, 0), Style.ACCENT, 26, 0.1, 4.5)
	Fx.float_text(self, player.position + Vector3(0, 2.3, 0), "Equipped: %s" % Data.recipe_name(recipe_id), Style.ACCENT)
	shake(0.1)
	vibrate(30)


func fx_kill_boss(node: Node3D) -> void:
	var b: Dictionary = Data.BOSSES[node.kind]
	var top := node.global_position + Vector3(0, 2.6, 0)
	var line := 0
	for item in b["drops"]:
		Fx.float_text(self, top + Vector3(0, 0.45 * line, 0), "+%d %s" % [b["drops"][item], Data.item_name(item)], Style.TEXT, 0.12 * line)
		hud.fly_to_bag(camera.unproject_position(top), Style.ITEM_COLORS.get(item, Color.WHITE), 3)
		line += 1
	Fx.float_text(self, top + Vector3(0, -0.45, 0), "+%d XP" % Game.xp_with_boost(b["xp"]), Style.XP, 0.12 * line)
	Fx.burst(self, node.global_position + Vector3(0, 1.0, 0), Style.ACCENT, 40, 0.12, 6.0)
	Sfx.play("kill", 0.0)
	Sfx.play("level_up", 0.0)
	shake(0.4)
	vibrate(150)


func open_station(station: Node3D) -> void:
	hud.open_station(station.kind)


func open_outpost() -> void:
	hud.open_outpost()


func _add_station(kind: String, pos: Vector2) -> void:
	var s := Station.new()
	s.kind = kind
	s.position = Vector3(pos.x, 0, pos.y)
	s.world = self
	add_child(s)


## An outpost is a chest (shares the camp storage) and a campfire (sleep).
func _add_outpost(pos: Vector2) -> void:
	for spec in [["chest", Vector2(-1.2, 0)], ["fire", Vector2(1.2, 0.4)]]:
		var o := Outpost.new()
		o.part = spec[0]
		o.world = self
		var p: Vector2 = pos + spec[1]
		o.position = Vector3(p.x, 0, p.y)
		add_child(o)


func _add_prop(kind: String, pos: Vector2) -> void:
	var r := ResourceNode.new()
	r.kind = kind
	r.position = Vector3(pos.x, 0, pos.y)
	r.world = self
	add_child(r)
	_taken.append(Vector3(pos.x, pos.y, r.radius))


func _scatter(kind: String, zone: Rect2, count: int) -> void:
	for i in count:
		var pos := _free_spot(zone.grow(-1.5), 1.0)
		if pos != Vector2.INF:
			_add_prop(kind, pos)


func _free_spot(area: Rect2, radius: float) -> Vector2:
	for attempt in 40:
		var p := Vector2(
			_rng.randf_range(area.position.x, area.end.x),
			_rng.randf_range(area.position.y, area.end.y))
		if CAMP.grow(1.0).has_point(p):
			continue
		var ok := true
		for t in _taken:
			if Vector2(t.x, t.y).distance_to(p) < t.z + radius + 0.5:
				ok = false
				break
		if ok:
			return p
	return Vector2.INF


func _spawn_animals(kind: String, zone: Rect2, count: int) -> void:
	for i in count:
		var a := Animal.new()
		a.kind = kind
		a.zone = zone.grow(-0.75)
		a.player = player
		a.world = self
		var p := random_point_away_from_camp(a.zone)
		a.position = Vector3(p.x, 0, p.y)
		add_child(a)


func random_point_away_from_camp(area: Rect2) -> Vector2:
	for attempt in 20:
		var p := Vector2(
			randf_range(area.position.x, area.end.x),
			randf_range(area.position.y, area.end.y))
		if not CAMP.grow(1.5).has_point(p) and p.distance_to(Shapes.flat(player)) > 7.5:
			return p
	return area.get_center()
