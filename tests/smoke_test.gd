extends Node

const Shapes := preload("res://scripts/world/shapes.gd")
## Plays through the core loop automatically and checks the results.
## Run headless from the project folder:
##   godot --headless --path . res://tests/smoke_test.tscn
## Exits with the number of failed checks. Deletes the save file when done.

var failures := 0
var world: Node3D
var player: Node3D


func _ready() -> void:
	Game._reset_state()
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	player = world.player
	await _frames(2)

	await _test_gather()
	await _test_build_and_craft()
	await _test_hunt()
	await _test_energy_sleep_and_ad()
	await _test_pack_and_storage()
	await _test_panels()
	_test_collect_quest()
	_test_levels_and_zone()
	await _test_death()
	await _test_boss_and_pass()
	_test_save_load()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	print("SMOKE TEST: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(failures)


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _nearest(group_filter: Callable) -> Node3D:
	var best: Node3D = null
	for node in get_tree().get_nodes_in_group("interactable"):
		if group_filter.call(node) and (best == null or
				player.position.distance_to(node.position) < player.position.distance_to(best.position)):
			best = node
	return best


## Walks up to a node (teleport) and presses the action button once.
func _act_on(node: Node3D) -> void:
	var r: float = node.get("radius") if node.get("radius") != null else 0.0
	player.position = node.position + Vector3(r + 0.25, 0, 0)
	player._cooldown = 0.0
	player.do_action()
	await _frames(1)


func _gather(kind: String, item: String, count: int) -> void:
	var guard := 0
	while Game.inventory.get(item, 0) < count and guard < 100:
		guard += 1
		var node := _nearest(func(n: Node) -> bool: return n.get("kind") == kind and n.is_available())
		await _act_on(node)


func _finish_timers() -> void:
	for id in Game.structures:
		if Game.structures[id]["busy_until"] > 0.0:
			Game.structures[id]["busy_until"] = Game.now() - 1.0
	if not Game.craft_job.is_empty():
		Game.craft_job["done_at"] = Game.now() - 1.0
	await _frames(2)


func _test_gather() -> void:
	print("Gathering")
	await _gather("tree", "wood", 5)
	check(Game.inventory.get("wood", 0) >= 5, "chopped 5 wood by hand")
	check(Game.energy < Data.START_ENERGY, "chopping costs energy")
	check(Game.quest_index == 1, "quest 'Gather 5 wood' completed")
	await _gather("rock", "stone", 1)
	check(Game.inventory.get("stone", 0) >= 1, "mined stone")
	var pond := _nearest(func(n: Node) -> bool: return n.get("kind") == "pond")
	Game.thirst = 10.0
	await _act_on(pond)
	check(Game.thirst > 99.0, "drank at the pond")


func _test_build_and_craft() -> void:
	print("Building and crafting")
	Game.start_build("crafting")
	check(Game.structure_busy("crafting"), "crafting place under construction")
	await _finish_timers()
	check(Game.structure_tier("crafting") == 1, "crafting place built")
	check(Game.quest_index == 2, "quest 'Build the crafting place' completed")
	await _gather("tree", "wood", 3)
	Game.start_craft("spear")
	check(not Game.craft_job.is_empty(), "spear crafting started")
	await _finish_timers()
	check(Game.has_tool("spear"), "spear crafted and equipped")
	check(Game.quest_index == 3, "quest 'Craft a wooden spear' completed")


func _test_hunt() -> void:
	print("Hunting")
	for i in 2:
		var rabbit := _nearest(func(n: Node) -> bool: return n.get("kind") == "rabbit" and n.is_available() and n.zone.end.x <= 45)
		var guard := 0
		while rabbit.alive and guard < 10:
			guard += 1
			await _act_on(rabbit)
	check(Game.inventory.get("raw_meat", 0) >= 2, "2 rabbits gave meat")
	check(Game.inventory.get("fur", 0) >= 2, "2 rabbits gave fur")
	check(Game.quest_index == 4, "quest 'Harvest 2 rabbit fur' completed")


func _test_energy_sleep_and_ad() -> void:
	print("Energy, sleep and rewarded ad")
	Game.energy = 0.0
	var tree := _nearest(func(n: Node) -> bool: return n.get("kind") == "tree" and n.is_available())
	var wood_before: int = Game.inventory.get("wood", 0)
	await _act_on(tree)
	check(Game.inventory.get("wood", 0) == wood_before, "can't gather at 0 energy")
	check(Game.move_speed() < Data.PLAYER_SPEED, "exhausted hunter is slower")
	Game.start_sleep()
	check(Game.is_sleeping(), "fell asleep")
	Game.sleep_until = Game.now() - 1.0
	await _frames(2)
	check(not Game.is_sleeping() and Game.energy == Game.max_energy(), "woke up with full energy")

	Game.energy = 0.0
	Game.start_sleep()
	Game.watch_ad_for_energy()
	check(AdService.is_showing(), "placeholder ad is showing")
	await get_tree().create_timer(AdService.PLACEHOLDER_SECONDS + 0.5).timeout
	check(Game.energy == Data.AD_ENERGY_REWARD, "ad gave +10 energy")
	check(not Game.is_sleeping(), "ad woke the hunter up")
	check(Game.ads_left_today() == Data.ADS_PER_DAY - 1, "daily ad count went down")


func _test_pack_and_storage() -> void:
	print("Shop pack and storage")
	Game.buy_pack("starter")
	check(Game.storage.get("wood", 0) >= 20, "starter pack delivered wood to storage")
	check(Game.xp_boost_left() > 0.0, "starter pack started the XP boost")
	Game.start_build("storage")
	await _finish_timers()
	check(Game.structure_tier("storage") == 1, "storage built from pack materials")
	Game.deposit_all()
	check(Game.inventory.is_empty(), "bag emptied into storage")
	Game.take_from_storage("raw_meat", 1)
	check(Game.inventory.get("raw_meat", 0) == 1, "took meat back from storage")
	Game.hunger = 50.0
	Game.eat_best()
	check(Game.hunger > 50.0, "ate meat")


func _test_panels() -> void:
	print("UI panels")
	var panel: Control = world.hud._panel
	for kind in ["crafting", "storage", "house", "board"]:
		world.hud.open_station(kind)
		await _frames(2)
		check(panel.visible and panel._content.get_child_count() > 0, "%s panel has content" % kind)
	for fn in [panel.open_bag, panel.open_shop, panel.open_menu]:
		fn.call()
		await _frames(2)
		check(panel._content.get_child_count() > 0, "%s panel has content" % fn.get_method())
	panel.close()


func _test_collect_quest() -> void:
	print("Collect quest")
	var index := -1
	for i in Data.QUESTS.size():
		if Data.QUESTS[i]["target"] == "rabbit:fur" and Data.QUESTS[i]["count"] == 10:
			index = i
	Game.quest_index = index
	Game.quest_progress = 0
	Game.inventory = {}
	for i in 9:
		Game.on_animal_killed("rabbit")
	check(Game.quest_index == index and Game.quest_progress_count() == 9, "9 rabbit fur counted")
	Game.on_animal_killed("squirrel")
	check(Game.quest_progress_count() == 9, "squirrel fur doesn't count")
	Game.on_animal_killed("rabbit")
	check(Game.quest_index == index + 1, "quest 'Harvest 10 rabbit fur' completed")
	Game.inventory = {}


func _test_levels_and_zone() -> void:
	print("Levels and zone 2")
	check(not Game.zone2_unlocked() or Game.level >= Data.ZONE2_LEVEL, "zone 2 locked below level %d" % Data.ZONE2_LEVEL)
	Game.gain_xp(Data.LEVEL_XP[Data.ZONE2_LEVEL - 1])
	check(Game.level >= Data.ZONE2_LEVEL, "reached level %d" % Data.ZONE2_LEVEL)
	check(world.walk_bounds().end.x > world.ZONE1.end.x, "east forest is walkable")


func _test_death() -> void:
	print("Death: revive with an ad, or give up")
	Game.inventory = {"wood": 3, "raw_meat": 2}
	Game.storage = {"stone": 4}
	Game.damage(1000.0, "Test")
	check(Game.is_dead(), "hunter knocked out at 0 health")
	await _frames(2)
	check(world.hud._death_screen.visible, "knocked-out screen shown")
	var wood_before: int = Game.inventory.get("wood", 0)
	var tree := _nearest(func(n: Node) -> bool: return n.get("kind") == "tree" and n.is_available())
	await _act_on(tree)
	check(Game.inventory.get("wood", 0) == wood_before, "can't act while knocked out")

	Game.revive_with_ad()
	await get_tree().create_timer(AdService.PLACEHOLDER_SECONDS + 0.5).timeout
	check(not Game.is_dead() and absf(Game.health - Data.MAX_HEALTH * Data.REVIVE_HEALTH) < 2.0, "ad revive gives 50% health")
	check(Game.inventory.get("raw_meat", 0) == 2, "ad revive keeps the bag")
	await _frames(2)
	check(not world.hud._death_screen.visible, "knocked-out screen closed")
	Game.damage(10.0, "Test")
	check(Game.health > Data.MAX_HEALTH * Data.REVIVE_HEALTH - 5.0, "short protection after getting back up")

	Game.protected_until = 0.0
	player.position = Vector3(40, 0, 20)
	Game.damage(1000.0, "Test")
	Game.give_up()
	await _frames(2)
	check(not Game.is_dead() and Game.health == Data.MAX_HEALTH, "give up: full health")
	check(Game.inventory.is_empty(), "give up: bag is lost")
	check(Game.storage.get("stone", 0) == 4, "give up: storage is kept")
	check(Shapes.flat(player).distance_to(world.CAMP.get_center()) < 8.0, "give up: back at camp")


func _test_boss_and_pass() -> void:
	print("Boss and mountain pass")
	var boss: Node3D = world.boss
	Game.take_mountain_pass()
	check(not Game.demo_done, "mountain pass closed before the boss")

	# A charge that connects hurts and pushes the hunter back.
	Game.health = Data.MAX_HEALTH
	player.position = boss.position + Vector3(0, 0, 1.5)
	await _frames(2)
	boss._state = boss.State.CHARGE
	boss._timer = 0.5
	boss._charge_dir = Vector2(0, 1)
	boss._charge_hit = false
	await _frames(10)
	check(Game.health <= Data.MAX_HEALTH - Data.BOSS["hit_damage"] + 0.5, "boar charge hurts")

	Game.tools["bow"] = true
	Game.inventory = {}
	var guard := 0
	while boss.alive and guard < 300:
		guard += 1
		Game.energy = 100.0
		player.position = boss.position + Vector3(3.0, 0, 0)
		player._cooldown = 0.0
		player.do_action()
		await _frames(3)
	check(Game.boss_defeated, "Great Boar defeated")
	check(Game.inventory.get("tusk", 0) == Data.BOSS["drops"]["tusk"], "boar dropped tusks")

	while Game.level < Data.NEXT_AREA["level"]:
		Game.gain_xp(100)
	Game.take_mountain_pass()
	check(Game.demo_done, "mountain pass ends the demo")
	await _frames(2)
	check(world.hud._end_screen.visible, "end of demo screen shown")
	world.hud._end_screen.visible = false


func _test_save_load() -> void:
	print("Save and load")
	Game.save_game()
	var level := Game.level
	var storage := Game.storage.duplicate()
	var tier := Game.structure_tier("crafting")
	Game._reset_state()
	Game.load_game()
	check(Game.level == level, "level restored")
	check(Game.storage == storage, "storage restored")
	check(Game.structure_tier("crafting") == tier, "camp restored")
	check(Game.has_tool("spear"), "tools restored")
	check(Game.boss_defeated and Game.demo_done, "boss and demo end restored")
