extends Node
## The hunter's progress: stats, bag, storage, camp, quests. Runs survival
## drain and all timers, and saves to the device.
##
## Timers (building, crafting, sleep) are stored as real-world unix times, so
## they keep running while the app is closed. Hunger and thirst only drain
## while the game is open (see open questions in CLAUDE.md).

signal changed
signal message(text: String)
signal leveled_up(level: int)
signal demo_finished
signal died
signal respawned(at_house: bool) # after giving up: the world moves the hunter home

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTOSAVE_SECONDS := 10.0

var level := 1
var xp := 0
var energy := Data.START_ENERGY
var health := Data.MAX_HEALTH
var protected_until := 0.0 # no damage until then (after getting back up)
var hunger := 100.0
var thirst := 100.0
var inventory := {} # item id -> count, carried
var storage := {} # item id -> count, at camp
var tools := {} # tool id -> true
var structures := {} # id -> {"tier", "busy_until", "next_tier"}
var craft_job := {} # {"recipe", "done_at"} or empty
var sleep_until := 0.0
var ad_day := ""
var ads_today := 0
var quest_index := 0
var quest_progress := 0
var xp_boost_until := 0.0
var boss_defeated := false
var demo_done := false
var player_position := Vector2.ZERO
var has_player_position := false

var _autosave_left := AUTOSAVE_SECONDS
var _starve_warn_left := 0.0


func _ready() -> void:
	_reset_state()
	load_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


func _process(delta: float) -> void:
	var t := now()
	var drain := Data.SLEEP_NEED_RATE if is_sleeping() else 1.0
	hunger = maxf(0.0, hunger - Data.HUNGER_PER_SEC * delta * drain)
	thirst = maxf(0.0, thirst - Data.THIRST_PER_SEC * delta * drain)
	if not is_dead() and hunger > Data.LOW_NEED and thirst > Data.LOW_NEED:
		health = minf(Data.MAX_HEALTH, health + Data.HEALTH_REGEN * delta)
	_starve(delta)
	_update_timers(t)
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		save_game()


func now() -> float:
	return Time.get_unix_time_from_system()


func notify(text: String) -> void:
	message.emit(text)


# --- Derived values ----------------------------------------------------------

func structure_tier(id: String) -> int:
	return structures[id]["tier"]


func structure_busy(id: String) -> bool:
	return structures[id]["busy_until"] > 0.0


func max_energy() -> float:
	var tier := structure_tier("house")
	if tier == 0:
		return Data.START_ENERGY
	return Data.STRUCTURES["house"]["tiers"][tier - 1]["max_energy"]


func sleep_duration() -> float:
	var tier := structure_tier("house")
	if tier == 0:
		return Data.NO_HOUSE_SLEEP_TIME
	return Data.STRUCTURES["house"]["tiers"][tier - 1]["sleep_time"]


func storage_capacity() -> float:
	var tier := structure_tier("storage")
	if tier == 0:
		return 0.0
	return Data.STRUCTURES["storage"]["tiers"][tier - 1]["capacity"]


func carry_limit() -> float:
	var limit := Data.BASE_CARRY
	for id in tools:
		limit += Data.TOOLS[id].get("carry_bonus", 0.0)
	return limit


func bag_weight(bag: Dictionary) -> float:
	var total := 0.0
	for id in bag:
		total += Data.item_weight(id) * bag[id]
	return total


func carry_weight() -> float:
	return bag_weight(inventory)


func has_tool(id: String) -> bool:
	return tools.has(id)


## The best owned weapon, or "" if the hunter has none.
func weapon() -> String:
	if has_tool("bow"):
		return "bow"
	if has_tool("spear"):
		return "spear"
	return ""


func weapon_range() -> float:
	var w := weapon()
	return Data.TOOLS[w]["range"] if w != "" else 0.0


func weapon_damage() -> int:
	var w := weapon()
	return Data.TOOLS[w]["damage"] if w != "" else 0


func is_sleeping() -> bool:
	return sleep_until > now()


func sleep_left() -> float:
	return maxf(0.0, sleep_until - now())


func xp_boost_left() -> float:
	return maxf(0.0, xp_boost_until - now())


func move_speed() -> float:
	var speed := Data.PLAYER_SPEED
	if energy <= 0.0:
		speed *= Data.EXHAUSTED_SPEED
	for need in [hunger, thirst]:
		if need <= 0.0:
			speed *= Data.EMPTY_NEED_SPEED
		elif need < Data.LOW_NEED:
			speed *= Data.LOW_NEED_SPEED
	return speed


func zone2_unlocked() -> bool:
	return level >= Data.ZONE2_LEVEL


## Returns [xp into this level, xp needed for this level]; needed is 0 at max level.
func level_progress() -> Array:
	if level >= Data.LEVEL_XP.size():
		return [0, 0]
	var base: int = Data.LEVEL_XP[level - 1]
	var next: int = Data.LEVEL_XP[level]
	return [xp - base, next - base]


func ads_left_today() -> int:
	_roll_ad_day()
	return Data.ADS_PER_DAY - ads_today


# --- Items -------------------------------------------------------------------

func count_available(id: String) -> int:
	return inventory.get(id, 0) + storage.get(id, 0)


func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if count_available(id) < cost[id]:
			return false
	return true


## Takes from camp storage first, then from the bag.
func _pay(cost: Dictionary) -> void:
	for id in cost:
		var left: int = cost[id]
		var from_storage := mini(left, storage.get(id, 0))
		_remove(storage, id, from_storage)
		_remove(inventory, id, left - from_storage)


func _add(bag: Dictionary, id: String, n: int) -> void:
	if n > 0:
		bag[id] = bag.get(id, 0) + n


func _remove(bag: Dictionary, id: String, n: int) -> void:
	if n <= 0:
		return
	bag[id] = bag.get(id, 0) - n
	if bag[id] <= 0:
		bag.erase(id)


## How many of an item still fit in the bag.
func bag_room_for(id: String) -> int:
	var w := Data.item_weight(id)
	if w <= 0.0:
		return 999999
	return maxi(0, floori((carry_limit() - carry_weight()) / w + 0.0001))


## Adds up to n items to the bag and returns how many fit.
func add_to_bag(id: String, n: int) -> int:
	var added := mini(n, bag_room_for(id))
	_add(inventory, id, added)
	return added


# --- Actions -----------------------------------------------------------------

func is_dead() -> bool:
	return health <= 0.0


func damage(amount: float, source: String) -> void:
	if is_dead() or now() < protected_until:
		return
	notify("%s -%d health" % [source, amount])
	_lose_health(amount)


func _lose_health(amount: float) -> void:
	health = maxf(0.0, health - amount)
	if is_dead():
		sleep_until = 0.0
		died.emit()
	changed.emit()


## Food or water at 0 drains health; both at 0 drain twice as fast.
func _starve(delta: float) -> void:
	var empty := int(hunger <= 0.0) + int(thirst <= 0.0)
	if empty == 0 or is_dead():
		_starve_warn_left = 0.0
		return
	health = maxf(0.0, health - Data.STARVE_DAMAGE * empty * delta)
	_starve_warn_left -= delta
	if _starve_warn_left <= 0.0:
		_starve_warn_left = 8.0
		var need := "food and water" if empty == 2 else ("food" if hunger <= 0.0 else "water")
		notify("You are starving! Find %s or you will collapse." % need)
	if is_dead():
		_lose_health(0.0)


## Death choice 1: watch a rewarded ad and get back up where you fell.
func revive_with_ad() -> void:
	if not is_dead() or AdService.is_showing():
		return
	AdService.show_rewarded(func(rewarded: bool) -> void:
		if not rewarded or not is_dead():
			return
		health = Data.MAX_HEALTH * Data.REVIVE_HEALTH
		protected_until = now() + Data.REVIVE_GRACE
		notify("You get back up!" if hunger > 0.0 and thirst > 0.0 else "You get back up! Eat and drink quickly.")
		changed.emit()
		save_game())


## Death choice 2: wake up in the house (or at camp) and lose everything in the bag.
func give_up() -> void:
	if not is_dead():
		return
	inventory = {}
	health = Data.MAX_HEALTH
	hunger = maxf(hunger, Data.WAKE_NEEDS)
	thirst = maxf(thirst, Data.WAKE_NEEDS)
	sleep_until = 0.0
	var at_house := structure_tier("house") > 0
	notify("You wake up %s. Everything in your bag is lost." % ("in your house" if at_house else "at camp"))
	respawned.emit(at_house)
	changed.emit()
	save_game()


func _can_act() -> bool:
	if is_dead():
		return false
	if is_sleeping():
		return false
	if energy <= 0.0:
		notify("Too tired. Sleep, or watch an ad for +%d energy." % Data.AD_ENERGY_REWARD)
		return false
	return true


func _spend_energy(amount: float) -> void:
	energy = maxf(0.0, energy - amount)
	if energy <= 0.0:
		notify("You are exhausted. Time to sleep.")


## One hit on a tree/rock/bush. Returns how many items were gathered.
func gather(kind: String, remaining: int) -> int:
	var r: Dictionary = Data.RESOURCES[kind]
	if not _can_act():
		return 0
	var item: String = r["item"]
	var amount := 1
	if r["tool"] != "" and has_tool(r["tool"]):
		amount = 2
	amount = mini(amount, remaining)
	amount = add_to_bag(item, amount)
	if amount <= 0:
		notify("Your bag is full. Empty it at the storage.")
		return 0
	_spend_energy(r["energy"])
	gain_xp(r["xp"])
	quest_event("gather", item, amount)
	changed.emit()
	return amount


## Uses energy for a weapon strike. Returns false if the hunter can't attack.
func try_attack() -> bool:
	if weapon() == "":
		notify("You need a spear to hunt. Craft one at the crafting place.")
		return false
	if not _can_act():
		return false
	_spend_energy(Data.ATTACK_ENERGY)
	changed.emit()
	return true


## The Great Boar's charge connected.
func on_boss_hit_player() -> void:
	damage(Data.BOSS["hit_damage"], "The boar rams you!")


func on_boss_killed() -> void:
	boss_defeated = true
	var lost := false
	for id in Data.BOSS["drops"]:
		var n: int = Data.BOSS["drops"][id]
		if add_to_bag(id, n) < n:
			lost = true
	notify("You defeated the %s!" % Data.BOSS["name"])
	if lost:
		notify("Bag full: some loot was left behind.")
	gain_xp(Data.BOSS["xp"])
	quest_event("boss", "boar", 1)
	changed.emit()
	save_game()


## Why the hunter can't take the mountain pass yet, or "" if they can.
func next_area_blocker() -> String:
	var parts := []
	if level < Data.NEXT_AREA["level"]:
		parts.append("reach level %d" % Data.NEXT_AREA["level"])
	if not boss_defeated:
		parts.append("defeat the %s" % Data.BOSS["name"])
	return "" if parts.is_empty() else "To cross: " + " and ".join(parts) + "."


func take_mountain_pass() -> void:
	var blocker := next_area_blocker()
	if blocker != "":
		notify(blocker)
		return
	quest_event("travel", "mountains", 1)
	demo_done = true
	changed.emit()
	save_game()
	demo_finished.emit()


func on_animal_killed(kind: String) -> void:
	var a: Dictionary = Data.ANIMALS[kind]
	var lost := false
	for id in a["drops"]:
		var n: int = a["drops"][id]
		var added := add_to_bag(id, n)
		quest_event("collect", "%s:%s" % [kind, id], added)
		if added < n:
			lost = true
	if lost:
		notify("Bag full: some of the %s was left behind." % a["name"].to_lower())
	gain_xp(a["xp"])
	quest_event("hunt", kind, 1)
	changed.emit()


func drink() -> void:
	if is_sleeping():
		return
	thirst = minf(100.0, thirst + Data.DRINK_AMOUNT)
	notify("You drink fresh water.")
	changed.emit()


func eat(id: String) -> void:
	if inventory.get(id, 0) <= 0:
		return
	if hunger >= 99.0:
		notify("You are not hungry.")
		return
	_remove(inventory, id, 1)
	hunger = minf(100.0, hunger + Data.ITEMS[id]["food"])
	notify("You eat %s." % Data.item_name(id).to_lower())
	changed.emit()


func eat_best() -> void:
	for id in Data.FOOD_ORDER:
		if inventory.get(id, 0) > 0:
			eat(id)
			return
	notify("No food in your bag.")


func start_sleep() -> void:
	if is_sleeping():
		return
	if energy >= max_energy():
		notify("You are not tired.")
		return
	sleep_until = now() + sleep_duration()
	notify("You fall asleep…")
	changed.emit()
	save_game()


func watch_ad_for_energy() -> void:
	if AdService.is_showing():
		return
	if ads_left_today() <= 0:
		notify("No more energy ads today. Come back tomorrow.")
		return
	if energy >= max_energy() and not is_sleeping():
		notify("Your energy is already full.")
		return
	AdService.show_rewarded(_on_energy_ad_done)


func _on_energy_ad_done(rewarded: bool) -> void:
	if not rewarded:
		return
	_roll_ad_day()
	ads_today += 1
	var was_sleeping := is_sleeping()
	sleep_until = 0.0
	energy = minf(max_energy(), energy + Data.AD_ENERGY_REWARD)
	notify("+%d energy%s" % [Data.AD_ENERGY_REWARD, " — you get up" if was_sleeping else ""])
	changed.emit()
	save_game()


func buy_pack(id: String) -> void:
	StoreService.purchase(id, func(ok: bool) -> void:
		if ok:
			_grant_pack(id))


func _grant_pack(id: String) -> void:
	var p: Dictionary = Data.PACKS[id]
	for item in p.get("items", {}):
		_add(storage, item, p["items"][item])
	for tool in p.get("tools", []):
		tools[tool] = true
	if p.has("energy"):
		energy = minf(max_energy(), energy + p["energy"])
	if p.has("xp_boost_minutes"):
		xp_boost_until = maxf(now(), xp_boost_until) + p["xp_boost_minutes"] * 60.0
	notify("%s received. Items are in the camp storage." % p["name"])
	changed.emit()
	save_game()


# --- Camp: storage, building, crafting ---------------------------------------

func deposit_all() -> void:
	if structure_tier("storage") == 0:
		return
	var room := storage_capacity() - bag_weight(storage)
	var moved := 0
	for id in inventory.keys():
		var w := Data.item_weight(id)
		var n: int = inventory[id]
		if w > 0.0:
			n = mini(n, floori(room / w + 0.0001))
		if n <= 0:
			continue
		_remove(inventory, id, n)
		_add(storage, id, n)
		room -= w * n
		moved += n
	if not inventory.is_empty():
		notify("Storage is full. Upgrade it to hold more.")
	elif moved > 0:
		notify("Bag emptied into storage.")
	changed.emit()


func take_from_storage(id: String, n: int) -> void:
	n = mini(n, storage.get(id, 0))
	var added := add_to_bag(id, n)
	_remove(storage, id, added)
	if added < n:
		notify("Your bag is full.")
	changed.emit()


## Why the next tier can't be built right now, or "" if it can.
func build_blocker(id: String) -> String:
	var tiers: Array = Data.STRUCTURES[id]["tiers"]
	var tier := structure_tier(id)
	if structure_busy(id):
		return "Already building"
	if tier >= tiers.size():
		return "Max tier"
	var next: Dictionary = tiers[tier]
	if level < next["level"]:
		return "Needs level %d" % next["level"]
	if not can_afford(next["cost"]):
		return "Missing materials"
	return ""


func start_build(id: String) -> void:
	if build_blocker(id) != "":
		return
	var tier := structure_tier(id)
	var next: Dictionary = Data.STRUCTURES[id]["tiers"][tier]
	_pay(next["cost"])
	structures[id]["next_tier"] = tier + 1
	structures[id]["busy_until"] = now() + next["time"]
	notify("Building %s…" % Data.STRUCTURES[id]["name"].to_lower())
	changed.emit()
	save_game()


func craft_blocker(recipe_id: String) -> String:
	var r: Dictionary = Data.RECIPES[recipe_id]
	if structure_tier("crafting") < r["tier"]:
		return "Needs crafting place tier %d" % r["tier"]
	if r.has("tool") and has_tool(r["tool"]):
		return "Owned"
	if not craft_job.is_empty():
		return "Busy"
	if not can_afford(r["cost"]):
		return "Missing materials"
	return ""


func start_craft(recipe_id: String) -> void:
	if craft_blocker(recipe_id) != "":
		return
	var r: Dictionary = Data.RECIPES[recipe_id]
	_pay(r["cost"])
	craft_job = {"recipe": recipe_id, "done_at": now() + r["time"]}
	changed.emit()
	save_game()


func craft_left() -> float:
	if craft_job.is_empty():
		return 0.0
	return maxf(0.0, craft_job["done_at"] - now())


func _update_timers(t: float) -> void:
	if sleep_until > 0.0 and t >= sleep_until:
		sleep_until = 0.0
		energy = max_energy()
		health = Data.MAX_HEALTH
		notify("You wake up rested.")
		changed.emit()

	for id in structures:
		var s: Dictionary = structures[id]
		if s["busy_until"] > 0.0 and t >= s["busy_until"]:
			s["tier"] = s["next_tier"]
			s["busy_until"] = 0.0
			notify("%s is ready (tier %d)." % [Data.STRUCTURES[id]["name"], s["tier"]])
			gain_xp(Data.BUILD_XP_PER_TIER * s["tier"])
			_check_quest()
			changed.emit()

	if not craft_job.is_empty() and t >= craft_job["done_at"]:
		var recipe_id: String = craft_job["recipe"]
		var r: Dictionary = Data.RECIPES[recipe_id]
		craft_job = {}
		if r.has("tool"):
			tools[r["tool"]] = true
		else:
			_add(storage, r["item"], r["count"])
		notify("Crafted: %s%s" % [Data.recipe_name(recipe_id), "" if r.has("tool") else " (in storage)"])
		gain_xp(Data.CRAFT_XP)
		quest_event("craft", recipe_id, 1)
		changed.emit()


# --- XP and quests -----------------------------------------------------------

## XP actually gained for a base amount, with any active boost.
func xp_with_boost(amount: int) -> int:
	return roundi(amount * Data.XP_BOOST_MULT) if xp_boost_left() > 0.0 else amount


func gain_xp(amount: int) -> void:
	xp += xp_with_boost(amount)
	while level < Data.LEVEL_XP.size() and xp >= Data.LEVEL_XP[level]:
		level += 1
		if level == Data.ZONE2_LEVEL:
			notify("Level %d: the east forest is open!" % level)
		leveled_up.emit(level)
	_check_quest()


func current_quest() -> Dictionary:
	if quest_index >= Data.QUESTS.size():
		return {}
	return Data.QUESTS[quest_index]


func quest_progress_count() -> int:
	var q := current_quest()
	if q.is_empty():
		return 0
	match q["type"]:
		"build": return 1 if structure_tier(q["target"]) >= 1 else 0
		"level": return level
		"boss": return 1 if boss_defeated else 0
	return quest_progress


func quest_event(type: String, target: String, n: int) -> void:
	var q := current_quest()
	if not q.is_empty() and q["type"] == type and q["target"] == target:
		quest_progress += n
	_check_quest()


func _check_quest() -> void:
	while true:
		var q := current_quest()
		if q.is_empty() or quest_progress_count() < q["count"]:
			return
		quest_index += 1
		quest_progress = 0
		notify("Quest complete: %s (+%d XP)" % [q["text"], q["xp"]])
		gain_xp(q["xp"])


# --- Save / load -------------------------------------------------------------

func _roll_ad_day() -> void:
	var today := Time.get_date_string_from_system()
	if ad_day != today:
		ad_day = today
		ads_today = 0


func _reset_state() -> void:
	level = 1
	xp = 0
	energy = Data.START_ENERGY
	health = Data.MAX_HEALTH
	protected_until = 0.0
	hunger = 100.0
	thirst = 100.0
	inventory = {}
	storage = {}
	tools = {}
	structures = {}
	for id in Data.STRUCTURES:
		structures[id] = {"tier": 0, "busy_until": 0.0, "next_tier": 0}
	craft_job = {}
	sleep_until = 0.0
	ad_day = ""
	ads_today = 0
	quest_index = 0
	quest_progress = 0
	xp_boost_until = 0.0
	boss_defeated = false
	demo_done = false
	player_position = Vector2.ZERO
	has_player_position = false


func save_game() -> void:
	_autosave_left = AUTOSAVE_SECONDS
	var data := {
		"version": SAVE_VERSION,
		"level": level, "xp": xp,
		"energy": energy, "health": health, "hunger": hunger, "thirst": thirst,
		"inventory": inventory, "storage": storage, "tools": tools.keys(),
		"structures": structures, "craft_job": craft_job,
		"sleep_until": sleep_until, "ad_day": ad_day, "ads_today": ads_today,
		"quest_index": quest_index, "quest_progress": quest_progress,
		"xp_boost_until": xp_boost_until,
		"boss_defeated": boss_defeated, "demo_done": demo_done,
		"player_position": [player_position.x, player_position.y],
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Save file is unreadable; starting fresh.")
		return
	level = int(data.get("level", 1))
	xp = int(data.get("xp", 0))
	energy = float(data.get("energy", Data.START_ENERGY))
	health = float(data.get("health", Data.MAX_HEALTH))
	hunger = float(data.get("hunger", 100.0))
	thirst = float(data.get("thirst", 100.0))
	inventory = _int_dict(data.get("inventory", {}))
	storage = _int_dict(data.get("storage", {}))
	tools = {}
	for id in data.get("tools", []):
		if Data.TOOLS.has(id):
			tools[id] = true
	var saved_structures: Dictionary = data.get("structures", {})
	for id in structures:
		if saved_structures.has(id):
			var s: Dictionary = saved_structures[id]
			structures[id] = {
				"tier": int(s.get("tier", 0)),
				"busy_until": float(s.get("busy_until", 0.0)),
				"next_tier": int(s.get("next_tier", 0)),
			}
	var job: Dictionary = data.get("craft_job", {})
	if job.has("recipe") and Data.RECIPES.has(job["recipe"]):
		craft_job = {"recipe": job["recipe"], "done_at": float(job.get("done_at", 0.0))}
	sleep_until = float(data.get("sleep_until", 0.0))
	ad_day = str(data.get("ad_day", ""))
	ads_today = int(data.get("ads_today", 0))
	quest_index = int(data.get("quest_index", 0))
	quest_progress = int(data.get("quest_progress", 0))
	xp_boost_until = float(data.get("xp_boost_until", 0.0))
	boss_defeated = bool(data.get("boss_defeated", false))
	demo_done = bool(data.get("demo_done", false))
	var pos: Array = data.get("player_position", [])
	if pos.size() == 2:
		player_position = Vector2(pos[0], pos[1])
		has_player_position = true


func _int_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for id in d:
		if Data.ITEMS.has(id) and int(d[id]) > 0:
			out[id] = int(d[id])
	return out


func reset_progress() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_reset_state()
	get_tree().reload_current_scene()
