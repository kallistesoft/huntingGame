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
	await _test_batch_pin_and_speed_up()
	await _test_panels()
	_test_collect_quest()
	await _test_levels_and_zone()
	await _test_death()
	await _test_boss_and_pass()
	await _test_zone3()
	await _test_gear_chain()
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
	for station in Game.craft_jobs:
		Game.craft_jobs[station]["done_at"] = Game.now() - 1.0
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
	check(Game.craft_jobs.has("crafting"), "spear crafting started")
	await _finish_timers()
	check(Game.has_tool("spear"), "spear crafted and equipped")
	check(Game.quest_index == 3, "quest 'Craft a wooden spear' completed")


func _test_hunt() -> void:
	print("Hunting")
	for i in 2:
		var rabbit := _nearest(func(n: Node) -> bool: return n.get("kind") == "rabbit" and n.is_available() and n.zone.end.x <= Data.ZONES[0]["rect"].end.x)
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


func _test_batch_pin_and_speed_up() -> void:
	print("Batch crafting, pinned recipe, speed-up ad")
	Game.storage["raw_meat"] = 6
	Game.storage["wood"] = 30
	Game.inventory = {}
	check(Game.max_craft_count("cooked_meat") == 6, "can cook 6 meat at once")
	check(Game.max_craft_count("stone_axe") == 1, "tools are crafted one at a time")
	Game.start_craft("cooked_meat", 5)
	check(Game.craft_job_at("crafting").get("count", 0) == 5 and Game.storage.get("raw_meat", 0) == 1, "batch of 5 took 5 meat")
	var left_before := Game.craft_left("crafting")
	var ads_before := Game.ads_left_today()
	Game.speed_up("craft:crafting")
	await get_tree().create_timer(AdService.PLACEHOLDER_SECONDS + 0.5).timeout
	check(Game.craft_left("crafting") < left_before * 0.6, "speed-up ad halved the craft time")
	check(Game.ads_left_today() == ads_before - 1, "speed-up used one daily ad")
	await _finish_timers()
	check(Game.storage.get("cooked_meat", 0) >= 5, "batch delivered 5 cooked meat to storage")

	Game.toggle_pin("bow")
	check(Game.pinned_recipe == "bow", "recipe pinned")
	await _frames(2)
	check(world.hud._pinned_card.visible, "pinned card shown on the HUD")
	Game.toggle_pin("bow")
	check(Game.pinned_recipe == "", "pin removed")
	check(Data.sources("fur").begins_with("Fur:") and "rabbit" in Data.sources("fur"), "fur sources name rabbits")
	check("Wait" not in Data.sources("wood") and "trees" in Data.sources("wood"), "wood comes from trees")
	Game.seen_recipes = []
	check(not Game.unseen_recipes().is_empty(), "unlocked recipes are new until seen")
	Game.mark_recipes_seen()
	check(Game.unseen_recipes().is_empty(), "recipes marked as seen")


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
	var need: int = Data.ZONES[1]["unlock"]["level"]
	check(not Game.zone_unlocked(1) or Game.level >= need, "zone 2 locked below level %d" % need)
	if not Game.zone_unlocked(1):
		check(world.walk_bounds().end.x <= Data.ZONES[0]["rect"].end.x, "walk bounds stop at the fence while locked")
	Game.gain_xp(Data.LEVEL_XP[need - 1])
	check(Game.level >= need, "reached level %d" % need)
	check(Game.zone_unlocked(1) and world.walk_bounds().end.x > Data.ZONES[0]["rect"].end.x, "east forest is walkable")
	check(Game.highest_zone() == 1, "highest zone is the east forest")
	await _frames(2)
	var chest := _nearest(func(n: Node) -> bool: return n.get("part") == "chest")
	check(chest != null, "east forest has an outpost chest")
	Game.storage = {"wood": 3}
	Game.inventory = {"stone": 2}
	player.position = chest.position + Vector3(1.0, 0, 0)
	player._cooldown = 0.0
	player.do_action()
	await _frames(2)
	check(world.hud._panel.visible and world.hud._panel._title.text == "Outpost chest", "outpost chest opens the storage window")
	Game.deposit_all()
	check(Game.storage.get("stone", 0) == 2 and Game.inventory.is_empty(), "outpost chest shares the camp storage")
	world.hud._panel.close()
	await _frames(2)


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

	# Starvation: food and water at 0 drain health until the hunter collapses.
	Game.hunger = 0.0
	Game.thirst = 0.0
	Game.health = 10.0
	await get_tree().create_timer(1.0).timeout
	check(Game.health < 9.0, "starving drains health")
	Game.health = 0.5
	await get_tree().create_timer(1.0).timeout
	check(Game.is_dead(), "starvation knocks the hunter out")
	Game.give_up()
	check(Game.hunger >= Data.WAKE_NEEDS and Game.thirst >= Data.WAKE_NEEDS, "waking at home restores some food and water")
	await _frames(2)


func _test_boss_and_pass() -> void:
	print("Boss and mountain pass")
	var boss: Node3D = world.boss_node("boar")
	var mountains := 2
	Game.cross_into(mountains)
	check(not Game.visited_zones.has("mountains"), "mountain pass closed before the boss")
	check("Great Boar" in Game.zone_blocker(mountains), "gate blocker names the boss")

	# A charge that connects hurts and pushes the hunter back.
	Game.health = Data.MAX_HEALTH
	player.position = boss.position + Vector3(0, 0, 1.5)
	await _frames(2)
	boss._state = boss.State.CHARGE
	boss._timer = 0.5
	boss._charge_dir = Vector2(0, 1)
	boss._charge_hit = false
	await _frames(10)
	check(Game.health <= Data.MAX_HEALTH - Data.BOSSES["boar"]["hit_damage"] + 0.5, "boar charge hurts")

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
	check(Game.bosses_defeated.has("boar"), "Great Boar defeated")
	check(Game.inventory.get("tusk", 0) == Data.BOSSES["boar"]["drops"]["tusk"], "boar dropped tusks")

	check(not Game.zone_unlocked(mountains), "mountains still need level %d" % Data.ZONES[mountains]["unlock"]["level"])
	Game.dev_set_level(Data.ZONES[mountains]["unlock"]["level"])
	check(Game.zone_unlocked(mountains), "level + boar open the mountains")
	Game.cross_into(mountains)
	check(Game.visited_zones.has("mountains") and not Game.demo_done, "crossing the pass enters the mountains, demo goes on")
	check(world.walk_bounds().end.x > Data.ZONES[1]["rect"].end.x, "mountains are walkable")


func _test_zone3() -> void:
	print("Zone 3: iron, wolves, the Great Bear, the northern pass")
	Game.inventory = {}
	Game.energy = 100.0
	Game.tools = {"spear": true, "bow": true, "stone_pick": true}
	var ore := _nearest(func(n: Node) -> bool: return n.get("kind") == "iron_rock" and n.is_available())
	check(ore != null, "iron rocks in the mountains")
	check(Game.gather("iron_rock", 4) == 0, "stone pickaxe can't mine iron")
	Game.tools["bone_pick"] = true
	check(Game.gather("iron_rock", 4) == 3, "bone pickaxe mines 3 ore per hit")
	Game.inventory["herbs"] = 1
	Game.health = 50.0
	Game.hunger = 100.0
	Game.eat("herbs")
	check(Game.health >= 79.0 and Game.inventory.get("herbs", 0) == 0, "herbs heal even when not hungry")

	var wolf := _nearest(func(n: Node) -> bool: return n.get("kind") == "wolf" and n.is_available())
	check(wolf != null, "wolves roam the mountains")
	Game.health = Game.max_health()
	Game.protected_until = 0.0
	player.position = wolf.position + Vector3(0.5, 0, 0)
	await get_tree().create_timer(2.2).timeout
	check(Game.health < Game.max_health() - 5.0, "a wolf bites the hunter")
	player.position = Vector3(90, 0, 16)
	await _frames(2)

	var bear: Node3D = world.boss_node("bear")
	check(bear != null and bear.alive, "the Great Bear waits in its lair")
	Game.health = Game.max_health()
	var guard := 0
	while bear.alive and guard < 400:
		guard += 1
		Game.energy = 100.0
		Game.health = Game.max_health()
		player.position = bear.position + Vector3(3.0, 0, 0)
		player._cooldown = 0.0
		player.do_action()
		await _frames(3)
	check(Game.bosses_defeated.has("bear"), "Great Bear defeated")
	check(Game.inventory.get("bear_pelt", 0) == Data.BOSSES["bear"]["drops"]["bear_pelt"], "bear dropped pelts")

	Game.dev_set_tier("house", 2)
	Game.dev_set_tier("crafting", 3)
	var forge := _nearest(func(n: Node) -> bool: return n.get("kind") == "forge")
	check(forge != null, "the camp has a forge plot")
	Game.dev_set_tier("forge", 1)
	Game.storage = {"iron_ore": 10, "wood": 10, "bone": 5, "rope": 5}
	Game.craft_jobs = {}
	Game.start_craft("iron_bar", 2)
	check(Game.craft_jobs.has("forge"), "forge smelts iron bars")
	await _finish_timers()
	check(Game.storage.get("iron_bar", 0) == 2, "2 iron bars in storage")
	Game.tools["bone_axe"] = true
	Game.start_craft("iron_axe")
	await _finish_timers()
	check(Game.has_tool("iron_axe") and not Game.has_tool("bone_axe") and Game.gather("tree", 6) == 4, "iron axe replaced the bone axe: 4 wood per hit")

	var north := Data.ZONES.size()
	Game.cross_into(north)
	check(not Game.demo_done, "northern pass closed below level %d" % Data.NEXT_ZONE["unlock"]["level"])
	Game.dev_set_level(Data.NEXT_ZONE["unlock"]["level"])
	Game.cross_into(north)
	check(Game.demo_done, "northern pass ends the demo")
	await _frames(2)
	check(world.hud._end_screen.visible, "end of demo screen shown")
	world.hud._end_screen.visible = false
	Game.tools.erase("iron_axe")
	Game.tools.erase("bone_pick")
	Game.inventory = {}


func _test_gear_chain() -> void:
	print("Materials, tanning rack and gear")
	Game.inventory = {}
	Game.craft_jobs = {}
	Game.energy = 100.0
	Game.dev_set_tier("house", 0)
	check(Game.build_blocker("tanning") != "Needs house tier 1", "tanning rack tier 1 needs no house")
	Game.dev_set_tier("tanning", 1)
	Game.dev_set_tier("crafting", 1)
	Game.storage = {"wood": 30, "stone": 20, "rope": 5}
	check(Game.build_blocker("crafting") == "Needs house tier 1", "crafting place tier 2 waits for the house")
	Game.dev_set_tier("house", 1)
	Game.dev_set_tier("crafting", 2)
	Game.storage = {"fibre": 30, "hide": 6, "bone": 8, "fur": 12, "wood": 20, "stone": 10, "leather": 10, "tusk": 1}
	var tree := _nearest(func(n: Node) -> bool: return n.get("kind") == "grass" and n.is_available())
	check(tree != null, "tall grass grows in the meadow")
	Game.start_craft("rope", 3)
	Game.start_craft("leather", 2)
	check(Game.craft_jobs.has("crafting") and Game.craft_jobs.has("tanning"), "crafting place and tanning rack work at the same time")
	await _finish_timers()
	check(Game.storage.get("rope", 0) >= 3 and Game.storage.get("leather", 0) >= 12, "rope and leather delivered to storage")
	var base_speed := Game.move_speed()
	Game.start_craft("fibre_wraps")
	await _finish_timers()
	check(Game.has_tool("fibre_wraps") and Game.move_speed() > base_speed * 1.1, "fibre wraps make the hunter faster")
	Game.start_craft("leather_boots")
	await _finish_timers()
	check(Game.has_tool("leather_boots") and not Game.has_tool("fibre_wraps"), "boots upgrade consumed the wraps")
	await _frames(2)
	check(player._gear.get_child_count() >= 2, "boots show on the hunter")
	check(Game.equipped("feet") == "leather_boots" and Game.move_speed() > base_speed * 1.25, "leather boots are equipped and faster")
	Game.tools["fur_tunic"] = true
	Game.start_craft("leather_armor")
	await _finish_timers()
	Game.health = Game.max_health()
	Game.protected_until = 0.0
	Game.damage(30.0, "Test")
	check(Game.has_tool("leather_armor") and absf(Game.health - (Game.max_health() - 15.0)) < 0.5, "leather armor halves damage")
	Game.tools["fur_hood"] = true
	check(Game.max_health() == Data.MAX_HEALTH + 25.0, "fur hood raises max health")
	Game.tools["stone_axe"] = true
	Game.tools["bone_axe"] = true
	check(Game.gather("tree", 6) == 3, "bone axe gives 3 wood per hit")
	Game.tools["bone_spear"] = true
	check(Game.weapon() == "bow", "bow stays the weapon in use over the bone spear")
	Game.tools.erase("bow")
	check(Game.weapon() == "bone_spear" and Game.weapon_damage() == 2, "bone spear replaces the wooden spear")
	check(Game.unseen_recipes("tanning").size() <= 1, "tanning rack lists only its own recipes")
	for id in ["fur_hood", "fur_tunic", "leather_armor", "leather_boots", "bone_axe", "bone_spear"]:
		Game.tools.erase(id)
	Game.tools["bow"] = true


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
	check(Game.bosses_defeated.has("boar") and Game.demo_done, "boss and demo end restored")
	# A save from before bosses were a list still counts the boar as beaten.
	Game.bosses_defeated = []
	var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "level": 5, "boss_defeated": true}))
	f.close()
	Game.load_game()
	check(Game.bosses_defeated == ["boar"], "old boss_defeated flag migrates to the list")
