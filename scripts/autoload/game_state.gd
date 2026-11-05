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
signal crafted(recipe_id: String) # a craft job finished
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
var craft_jobs := {} # station id -> queue of {"recipe", "count", "done_at", "total"}; [0] is running
var sleep_until := 0.0
var ad_day := ""
var ads_today := 0
var quest_index := 0
var quest_progress := 0
var xp_boost_until := 0.0
var buffs := {} # kind -> {"until": unix time, "amount": value, "label": dish name}; see Data.BUFFS
var bosses_defeated := [] # boss ids (Data.BOSSES) the hunter has beaten
var demo_done := false
var player_position := Vector2.ZERO
var has_player_position := false
var visited_zones := [] # zone ids the hunter has set foot in
var notifications_on := true # phone notifications when a timer ends in the background
var sounds_on := true
var time_offset := 0.0 # dev: shifts the day/night clock (not saved)
var pinned_recipe := "" # recipe followed on the HUD, or ""
var seen_recipes := [] # recipe ids the player has seen unlocked (for the NEW badge)

var _autosave_left := AUTOSAVE_SECONDS
var _starve_warn_left := 0.0


func _ready() -> void:
	_reset_state()
	load_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()
		NotifyService.on_pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		NotifyService.on_resume()


func _process(delta: float) -> void:
	var t := now()
	var drain := (Data.SLEEP_NEED_RATE if is_sleeping() else 1.0) * gear_stat("body", "drain_mult", 1.0)
	hunger = maxf(0.0, hunger - Data.HUNGER_PER_SEC * delta * drain * (1.0 - buff_amount("hunger_slow")))
	thirst = maxf(0.0, thirst - Data.THIRST_PER_SEC * delta * drain)
	if not is_dead() and hunger > Data.LOW_NEED and thirst > Data.LOW_NEED:
		health = minf(max_health(), health + Data.HEALTH_REGEN * maxf(1.0, buff_amount("regen")) * delta)
	_starve(delta)
	_expire_buffs(t)
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
	return Data.BASE_CARRY + gear_stat("bag", "carry_bonus", 0.0) + buff_amount("carry")


func max_health() -> float:
	return Data.MAX_HEALTH + gear_stat("head", "max_health", 0.0)


# --- Equipment ---------------------------------------------------------------

## The piece in use for a slot: the highest tier owned (then the strongest), or "".
func equipped(slot: String) -> String:
	var best := ""
	var best_rank := -1
	for id in tools:
		var t: Dictionary = Data.TOOLS[id]
		if t.get("slot", "") != slot:
			continue
		var rank: int = t.get("tier", 0) * 100 + t.get("damage", 0)
		if rank > best_rank:
			best = id
			best_rank = rank
	return best


## Tier of the piece equipped in a slot (0 when empty).
func gear_tier(slot: String) -> int:
	var id := equipped(slot)
	return Data.TOOLS[id].get("tier", 0) if id != "" else 0


## A stat of the piece equipped in a slot, or the default when the slot is empty.
func gear_stat(slot: String, key: String, default: float) -> float:
	var id := equipped(slot)
	return float(Data.TOOLS[id].get(key, default)) if id != "" else default


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
	return equipped("weapon")


func weapon_range() -> float:
	var w := weapon()
	return Data.TOOLS[w]["range"] if w != "" else 0.0


func weapon_damage() -> int:
	var w := weapon()
	if w == "":
		return 0
	return ceili(Data.TOOLS[w]["damage"] * (1.0 + buff_amount("power")))


func is_sleeping() -> bool:
	return sleep_until > now()


func sleep_left() -> float:
	return maxf(0.0, sleep_until - now())


func xp_boost_left() -> float:
	return maxf(0.0, xp_boost_until - now())


# --- Food buffs --------------------------------------------------------------

func buff_left(kind: String) -> float:
	return maxf(0.0, buffs[kind]["until"] - now()) if buffs.has(kind) else 0.0


## The bonus a running buff gives (0 when none), already capped by Data.BUFFS.
func buff_amount(kind: String) -> float:
	return buffs[kind]["amount"] if buff_left(kind) > 0.0 else 0.0


## Running buff kinds, the one ending soonest first.
func active_buffs() -> Array:
	var kinds := buffs.keys().filter(func(k: String) -> bool: return buff_left(k) > 0.0)
	kinds.sort_custom(func(a: String, b: String) -> bool: return buffs[a]["until"] < buffs[b]["until"])
	return kinds


## Starts (or restarts) the buffs of a dish. A kind never stacks with
## itself: eating it again resets the timer to the dish's duration. Only
## MAX_BUFFS kinds run at once; a new one replaces the one ending soonest.
func _apply_buffs(item: Dictionary, label: String) -> void:
	for b in item.get("buffs", []):
		var kind: String = b["kind"]
		var spec: Dictionary = Data.BUFFS[kind]
		if buff_left(kind) <= 0.0:
			var running := active_buffs()
			if running.size() >= Data.MAX_BUFFS:
				var dropped: String = running[0]
				notify("%s replaces %s." % [spec["name"], Data.BUFFS[dropped]["name"]])
				buffs.erase(dropped)
		buffs[kind] = {"until": now() + b["minutes"] * 60.0, "amount": minf(b["amount"], spec["max"]), "label": label}


func _expire_buffs(t: float) -> void:
	for kind in buffs.keys():
		if buffs[kind]["until"] <= t:
			notify("The %s wore off." % str(buffs[kind]["label"]).to_lower())
			buffs.erase(kind)
			changed.emit()


func move_speed() -> float:
	var speed := Data.PLAYER_SPEED * gear_stat("feet", "speed_mult", 1.0) * (1.0 + buff_amount("speed"))
	if energy <= 0.0:
		speed *= Data.EXHAUSTED_SPEED
	for need in [hunger, thirst]:
		if need <= 0.0:
			speed *= Data.EMPTY_NEED_SPEED
		elif need < Data.LOW_NEED:
			speed *= Data.LOW_NEED_SPEED
	return speed


# --- Zones -------------------------------------------------------------------

## Whether zone i (index in Data.ZONES, or the one after the last) is open.
func zone_unlocked(i: int) -> bool:
	return zone_blocker(i) == ""


## Why zone i is still closed ("" if it is open): level and/or boss.
func zone_blocker(i: int) -> String:
	if i <= 0:
		return ""
	var z: Dictionary = Data.zone(i)
	if z.is_empty():
		return "There is nothing further yet."
	var parts := []
	if level < z["unlock"]["level"]:
		parts.append("reach level %d" % z["unlock"]["level"])
	var boss: String = z["unlock"]["boss"]
	if boss != "" and not bosses_defeated.has(boss):
		parts.append("defeat the %s" % Data.BOSSES[boss]["name"])
	return "" if parts.is_empty() else "To enter %s: %s." % [z["name"], " and ".join(parts)]


## Index of the furthest unlocked zone that exists.
func highest_zone() -> int:
	var top := 0
	for i in range(1, Data.ZONES.size()):
		if zone_unlocked(i):
			top = i
	return top


## Walking through the gate into zone i. Into a zone that is not built yet
## (Data.NEXT_ZONE) it ends the demo.
func cross_into(i: int) -> void:
	var blocker := zone_blocker(i)
	if blocker != "":
		notify(blocker)
		return
	if i >= Data.ZONES.size():
		quest_event("travel", Data.zone(i)["id"], 1)
		demo_done = true
		changed.emit()
		save_game()
		demo_finished.emit()
		return
	on_enter_zone(i)


## The hunter set foot in zone i (through a gate or across an open border).
## The first visit counts for "travel" quests.
func on_enter_zone(i: int) -> void:
	var z: Dictionary = Data.ZONES[i]
	if visited_zones.has(z["id"]):
		return
	visited_zones.append(z["id"])
	notify("You enter %s." % z["name"])
	quest_event("travel", z["id"], 1)
	changed.emit()
	save_game()


## Index of the zone a ground position is in (-1 outside every zone).
func zone_at(pos: Vector2) -> int:
	for i in Data.ZONES.size():
		if Data.ZONES[i]["rect"].has_point(pos):
			return i
	return -1


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
	if Data.TOOLS.has(id):
		return 1 if has_tool(id) else 0
	return inventory.get(id, 0) + storage.get(id, 0)


func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if count_available(id) < cost[id]:
			return false
	return true


## Takes from camp storage first, then from the bag.
func _pay(cost: Dictionary) -> void:
	for id in cost:
		if Data.TOOLS.has(id):
			tools.erase(id) # an upgrade consumes the old piece
			continue
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
	amount *= 1.0 - gear_stat("body", "armor", 0.0)
	notify("%s -%d health" % [source, amount])
	Sfx.play("hurt")
	_lose_health(amount)


func _lose_health(amount: float) -> void:
	health = maxf(0.0, health - amount)
	if is_dead():
		sleep_until = 0.0
		died.emit()
	changed.emit()


## Inside the camp or next to an outpost campfire: starvation does no harm.
func in_safe_zone() -> bool:
	if Data.CAMP.has_point(player_position):
		return true
	for z in Data.ZONES:
		if z["outpost"] != null and player_position.distance_to(z["outpost"]) <= Data.CAMPFIRE_SAFE_RADIUS:
			return true
	return false


## Food or water at 0 drains health; both at 0 drain twice as fast. Not in a
## safe zone: there the hunter is only reminded to eat before heading out.
func _starve(delta: float) -> void:
	var empty := int(hunger <= 0.0) + int(thirst <= 0.0)
	if empty == 0 or is_dead():
		_starve_warn_left = 0.0
		return
	var safe := in_safe_zone()
	if not safe:
		health = maxf(0.0, health - Data.STARVE_DAMAGE * empty * delta)
	_starve_warn_left -= delta
	if _starve_warn_left <= 0.0:
		_starve_warn_left = 8.0
		var need := "food and water" if empty == 2 else ("food" if hunger <= 0.0 else "water")
		if safe:
			notify("You are starving. Find %s before you leave the fire." % need)
		else:
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
		health = max_health() * Data.REVIVE_HEALTH
		protected_until = now() + Data.REVIVE_GRACE
		notify("You get back up!" if hunger > 0.0 and thirst > 0.0 else "You get back up! Eat and drink quickly.")
		changed.emit()
		save_game())


## Death choice 2: wake up in the house (or at camp) and lose everything in the bag.
func give_up() -> void:
	if not is_dead():
		return
	inventory = {}
	health = max_health()
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
	energy = maxf(0.0, energy - amount * (1.0 - buff_amount("energy_save")))
	if energy <= 0.0:
		notify("You are exhausted. Time to sleep.")


## One hit on a tree/rock/bush. Returns how many items were gathered.
func gather(kind: String, remaining: int) -> int:
	var r: Dictionary = Data.RESOURCES[kind]
	if not _can_act():
		return 0
	var item: String = r["item"]
	if r.has("needs_tier") and gear_tier(r["slot"]) < r["needs_tier"]:
		notify("Too hard for your tools: you need a %s or better." % Data.tool_of_tier(r["slot"], r["needs_tier"]).to_lower())
		return 0
	var amount := int(gear_stat(r["slot"], "yield", 1.0)) if r["slot"] != "" else 1
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
## An aggressive animal (wolf) got its teeth in.
func on_animal_bite(kind: String) -> void:
	var a: Dictionary = Data.ANIMALS[kind]
	damage(a["bite"], a["bite_text"])


func on_boss_hit_player(kind: String) -> void:
	var b: Dictionary = Data.BOSSES[kind]
	damage(b["hit_damage"], b["hit_text"])


func on_boss_killed(kind: String) -> void:
	var b: Dictionary = Data.BOSSES[kind]
	if not bosses_defeated.has(kind):
		bosses_defeated.append(kind)
	var lost := false
	for id in b["drops"]:
		var n: int = b["drops"][id]
		if add_to_bag(id, n) < n:
			lost = true
	notify("You defeated the %s!" % b["name"])
	if lost:
		notify("Bag full: some loot was left behind.")
	gain_xp(b["xp"])
	quest_event("boss", kind, 1)
	_announce_unlocks()
	changed.emit()
	save_game()


## Tells the player when a zone has just opened (after a level or a boss).
func _announce_unlocks() -> void:
	for i in range(1, Data.ZONES.size() + 1):
		var z: Dictionary = Data.zone(i)
		var u: Dictionary = z["unlock"]
		var boss_ok: bool = u["boss"] == "" or bosses_defeated.has(u["boss"])
		if level == u["level"] and boss_ok:
			notify("%s is open!" % z["name"].capitalize())
		elif level == u["level"] and not boss_ok:
			notify("Defeat the %s to enter %s." % [Data.BOSSES[u["boss"]]["name"], z["name"]])


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
	var item: Dictionary = Data.ITEMS[id]
	var heals: bool = item.has("heal") and health < max_health()
	var feeds: bool = item.get("food", 0.0) > 0.0 and hunger < 99.0
	var quenches: bool = item.get("water", 0.0) > 0.0 and thirst < 99.0
	if not (feeds or quenches or heals or item.has("buffs")):
		notify("You are not hungry." if item.get("food", 0.0) > 0.0 else "You are not thirsty.")
		return
	_remove(inventory, id, 1)
	hunger = minf(100.0, hunger + item.get("food", 0.0))
	thirst = minf(100.0, thirst + item.get("water", 0.0))
	if item.has("heal"):
		health = minf(max_health(), health + item["heal"])
	_apply_buffs(item, Data.item_name(id))
	var verb := "drink" if item.get("food", 0.0) <= 0.0 else "eat"
	notify("You %s %s: %s." % [verb, Data.item_name(id).to_lower(), Data.food_text(id)])
	Sfx.play("eat")
	changed.emit()


func eat_best() -> void:
	for id in Data.FOOD_ORDER:
		if inventory.get(id, 0) > 0:
			eat(id)
			return
	notify("No food in your bag.")


## outside: sleeping on the ground (an outpost campfire), whatever the house tier.
func start_sleep(outside := false) -> void:
	if is_sleeping():
		return
	if energy >= max_energy():
		notify("You are not tired.")
		return
	sleep_until = now() + (Data.NO_HOUSE_SLEEP_TIME if outside else sleep_duration())
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
	if is_sleeping():
		# Owner's rule (2026-11-05): an ad while asleep ends the night at once,
		# fully rested, as if the timer had run out.
		_wake_up()
	else:
		energy = minf(max_energy(), energy + Data.AD_ENERGY_REWARD)
		notify("+%d energy" % Data.AD_ENERGY_REWARD)
	changed.emit()
	save_game()


## Halves the time left on a build (target = structure id) or on the craft
## job (target = "craft") after a rewarded ad. Shares the daily ad cap.
func speed_up(target: String) -> void:
	if AdService.is_showing():
		return
	if ads_left_today() <= 0:
		notify("No more ads today. Come back tomorrow.")
		return
	if _time_left(target) <= 0.0:
		return
	AdService.show_rewarded(func(rewarded: bool) -> void:
		if not rewarded:
			return
		var left := _time_left(target)
		if left <= 0.0:
			return
		_roll_ad_day()
		ads_today += 1
		if target.begins_with("craft:"):
			for job in craft_jobs[target.trim_prefix("craft:")]:
				job["done_at"] -= left / 2.0 # the queue behind it moves up too
		else:
			structures[target]["busy_until"] = now() + left / 2.0
		notify("Time halved: %d s left." % ceili(left / 2.0))
		changed.emit()
		save_game())


func _time_left(target: String) -> float:
	if target.begins_with("craft:"):
		return craft_left(target.trim_prefix("craft:"))
	if structures.has(target) and structure_busy(target):
		return maxf(0.0, structures[target]["busy_until"] - now())
	return 0.0


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
	if next.get("house_tier", 0) > structure_tier("house"):
		return "Needs house tier %d" % next["house_tier"]
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
	NotifyService.ensure_permission()
	notify("Building %s…" % Data.STRUCTURES[id]["name"].to_lower())
	changed.emit()
	save_game()


func craft_blocker(recipe_id: String) -> String:
	var r: Dictionary = Data.RECIPES[recipe_id]
	if structure_tier(r["station"]) < r["tier"]:
		return "Needs %s tier %d" % [Data.STRUCTURES[r["station"]]["name"].to_lower(), r["tier"]]
	if r.has("tool") and has_tool(r["tool"]):
		return "Owned"
	if craft_queue(r["station"]).size() >= queue_slots():
		return "Queue full"
	if not can_afford(r["cost"]):
		return "Missing materials"
	return ""


func queue_slots() -> int:
	return Data.QUEUE_SLOTS


## The jobs lined up at a station, running one first ([] when idle).
func craft_queue(station: String) -> Array:
	return craft_jobs.get(station, [])


## Craft time multiplier of a station at its current tier (tier 2 rack: 0.5).
func station_speed(station: String) -> float:
	var tier := structure_tier(station)
	if tier == 0:
		return 1.0
	return Data.STRUCTURES[station]["tiers"][tier - 1].get("speed", 1.0)


## The job running at a station, or {}.
func craft_job_at(station: String) -> Dictionary:
	var q := craft_queue(station)
	return q[0] if not q.is_empty() else {}


## Drops a waiting job (never the running one) and gives its materials back.
func cancel_craft(station: String, index: int) -> void:
	var q := craft_queue(station)
	if index <= 0 or index >= q.size():
		return
	var job: Dictionary = q[index]
	var r: Dictionary = Data.RECIPES[job["recipe"]]
	for id in r["cost"]:
		if Data.TOOLS.has(id):
			tools[id] = true
		else:
			_add(storage, id, r["cost"][id] * job["count"])
	for i in range(index + 1, q.size()):
		q[i]["done_at"] -= job["total"]
	q.remove_at(index)
	notify("%s taken out of the queue; materials are back in storage." % Data.recipe_name(job["recipe"]))
	changed.emit()
	save_game()


## How many of a recipe the materials allow (1 for tools, which are made once).
func max_craft_count(recipe_id: String) -> int:
	var r: Dictionary = Data.RECIPES[recipe_id]
	if r.has("tool"):
		return 1
	var n := 99
	for id in r["cost"]:
		n = mini(n, count_available(id) / int(r["cost"][id]))
	return maxi(n, 0)


func start_craft(recipe_id: String, count := 1) -> void:
	if craft_blocker(recipe_id) != "":
		return
	var r: Dictionary = Data.RECIPES[recipe_id]
	count = clampi(count, 1, max_craft_count(recipe_id))
	var cost := {}
	for id in r["cost"]:
		cost[id] = r["cost"][id] * count
	_pay(cost)
	var station: String = r["station"]
	var total: float = r["time"] * count * station_speed(station)
	var q := craft_queue(station)
	var start: float = q[-1]["done_at"] if not q.is_empty() else now() # chained behind the queue
	q.append({"recipe": recipe_id, "count": count, "done_at": start + total, "total": total})
	craft_jobs[station] = q
	NotifyService.ensure_permission()
	changed.emit()
	save_game()


func toggle_notifications() -> void:
	notifications_on = not notifications_on
	notify("Notifications %s." % ("on" if notifications_on else "off"))
	changed.emit()
	save_game()


func toggle_pin(recipe_id: String) -> void:
	pinned_recipe = "" if pinned_recipe == recipe_id else recipe_id
	changed.emit()
	save_game()


## Recipes unlocked at their station's tier, not owned, not yet seen.
## station = "" means every station.
func unseen_recipes(station := "") -> Array:
	var out := []
	for id in Data.RECIPES:
		var r: Dictionary = Data.RECIPES[id]
		if station != "" and r["station"] != station:
			continue
		if r["tier"] <= structure_tier(r["station"]) and not (r.has("tool") and has_tool(r["tool"])) and not seen_recipes.has(id):
			out.append(id)
	return out


func mark_recipes_seen(station := "") -> void:
	var fresh := unseen_recipes(station)
	if fresh.is_empty():
		return
	seen_recipes.append_array(fresh)
	changed.emit()
	save_game()


func craft_left(station: String) -> float:
	var job := craft_job_at(station)
	return maxf(0.0, job["done_at"] - now()) if not job.is_empty() else 0.0


## Full duration of the job running at a station (for progress bars).
func craft_total(station: String) -> float:
	var job := craft_job_at(station)
	return job["total"] if not job.is_empty() else 1.0


## The night is over: full energy and health.
func _wake_up() -> void:
	sleep_until = 0.0
	energy = max_energy()
	health = max_health()
	notify("You wake up rested.")


func _update_timers(t: float) -> void:
	if sleep_until > 0.0 and t >= sleep_until:
		_wake_up()
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

	for station in craft_jobs.keys():
		while not craft_jobs[station].is_empty() and t >= craft_jobs[station][0]["done_at"]:
			_finish_craft(craft_jobs[station].pop_front())
		if craft_jobs[station].is_empty():
			craft_jobs.erase(station)


func _finish_craft(job: Dictionary) -> void:
	var recipe_id: String = job["recipe"]
	var count: int = job.get("count", 1)
	var r: Dictionary = Data.RECIPES[recipe_id]
	if r.has("tool"):
		tools[r["tool"]] = true
		if pinned_recipe == recipe_id:
			pinned_recipe = ""
	else:
		_add(storage, r["item"], r["count"] * count)
	notify("Crafted: %s%s%s" % [Data.recipe_name(recipe_id), " ×%d" % count if count > 1 else "", "" if r.has("tool") else " (in storage)"])
	gain_xp(Data.craft_xp(r) * count)
	quest_event("craft", recipe_id, count)
	changed.emit()
	crafted.emit(recipe_id)


# --- XP and quests -----------------------------------------------------------

## XP actually gained for a base amount, with any active boost.
func xp_with_boost(amount: int) -> int:
	return roundi(amount * Data.XP_BOOST_MULT) if xp_boost_left() > 0.0 else amount


func gain_xp(amount: int) -> void:
	xp += xp_with_boost(amount)
	while level < Data.LEVEL_XP.size() and xp >= Data.LEVEL_XP[level]:
		level += 1
		_announce_unlocks()
		leveled_up.emit(level)
	_check_quest()


func current_quest() -> Dictionary:
	var all := Data.quests()
	if quest_index >= all.size():
		return {}
	return all[quest_index]


func quest_progress_count() -> int:
	var q := current_quest()
	if q.is_empty():
		return 0
	match q["type"]:
		"build": return 1 if structure_tier(q["target"]) >= q.get("tier", 1) else 0
		"travel": return 1 if visited_zones.has(q["target"]) or (demo_done and q["target"] == Data.NEXT_ZONE["id"]) else 0
		"level": return level
		"boss": return 1 if bosses_defeated.has(q["target"]) else 0
	return quest_progress


func quest_event(type: String, target: String, n: int) -> void:
	var q := current_quest()
	if not q.is_empty() and q["type"] == type:
		var wanted: String = q["target"]
		if wanted == target or (Data.QUEST_GROUPS.has(wanted) and target in Data.QUEST_GROUPS[wanted]):
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
	craft_jobs = {}
	sleep_until = 0.0
	ad_day = ""
	ads_today = 0
	quest_index = 0
	quest_progress = 0
	xp_boost_until = 0.0
	buffs = {}
	bosses_defeated = []
	demo_done = false
	player_position = Vector2.ZERO
	has_player_position = false
	pinned_recipe = ""
	seen_recipes = []
	notifications_on = true
	visited_zones = [Data.ZONES[0]["id"]]
	sounds_on = true


func save_game() -> void:
	_autosave_left = AUTOSAVE_SECONDS
	var data := {
		"version": SAVE_VERSION,
		"level": level, "xp": xp,
		"energy": energy, "health": health, "hunger": hunger, "thirst": thirst,
		"inventory": inventory, "storage": storage, "tools": tools.keys(),
		"structures": structures, "craft_jobs": craft_jobs,
		"sleep_until": sleep_until, "ad_day": ad_day, "ads_today": ads_today,
		"quest_index": quest_index, "quest_progress": quest_progress,
		"xp_boost_until": xp_boost_until, "buffs": buffs,
		"bosses_defeated": bosses_defeated, "demo_done": demo_done,
		"player_position": [player_position.x, player_position.y],
		"pinned_recipe": pinned_recipe, "seen_recipes": seen_recipes, "visited_zones": visited_zones,
		"notifications_on": notifications_on,
		"sounds_on": sounds_on,
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
	for late in ["tailor", "kitchen"]:
		if not saved_structures.has(late) and saved_structures.has("crafting"):
			# Save from before this station split off the crafting place: it
			# opens at the crafting place's tier, so what the player could
			# already make stays craftable.
			structures[late]["tier"] = structures["crafting"]["tier"]
	craft_jobs = {}
	var saved_jobs: Dictionary = data.get("craft_jobs", {})
	if data.has("craft_job") and not data["craft_job"].is_empty():
		saved_jobs["crafting"] = data["craft_job"] # save from before jobs were per station
	for station in saved_jobs:
		if not Data.STRUCTURES.has(station):
			continue
		var entries: Array = saved_jobs[station] if saved_jobs[station] is Array else [saved_jobs[station]] # one job per station before the queue
		var q := []
		for job in entries:
			if job is Dictionary and job.has("recipe") and Data.RECIPES.has(job["recipe"]):
				var r: Dictionary = Data.RECIPES[job["recipe"]]
				var count := int(job.get("count", 1))
				q.append({"recipe": job["recipe"], "count": count, "done_at": float(job.get("done_at", 0.0)),
					"total": float(job.get("total", r["time"] * count * station_speed(station)))})
		if not q.is_empty():
			craft_jobs[station] = q
	sleep_until = float(data.get("sleep_until", 0.0))
	ad_day = str(data.get("ad_day", ""))
	ads_today = int(data.get("ads_today", 0))
	quest_index = int(data.get("quest_index", 0))
	quest_progress = int(data.get("quest_progress", 0))
	xp_boost_until = float(data.get("xp_boost_until", 0.0))
	buffs = {}
	var saved_buffs: Dictionary = data.get("buffs", {})
	for kind in saved_buffs:
		var b = saved_buffs[kind]
		if Data.BUFFS.has(kind) and b is Dictionary and float(b.get("until", 0.0)) > now():
			buffs[kind] = {"until": float(b["until"]), "amount": minf(float(b.get("amount", 0.0)), Data.BUFFS[kind]["max"]), "label": str(b.get("label", "buff"))}
	bosses_defeated = []
	for id in data.get("bosses_defeated", []):
		if Data.BOSSES.has(id):
			bosses_defeated.append(id)
	if bool(data.get("boss_defeated", false)) and not bosses_defeated.has("boar"):
		bosses_defeated.append("boar") # save from before bosses were a list
	demo_done = bool(data.get("demo_done", false))
	var pos: Array = data.get("player_position", [])
	if pos.size() == 2:
		player_position = Vector2(pos[0], pos[1])
		has_player_position = true
	visited_zones = [Data.ZONES[0]["id"]]
	for id in data.get("visited_zones", []):
		if not visited_zones.has(id):
			visited_zones.append(id)
	if not data.has("visited_zones") and level >= Data.ZONES[1]["unlock"]["level"]:
		visited_zones.append(Data.ZONES[1]["id"]) # older save: the forest was already open
	notifications_on = bool(data.get("notifications_on", true))
	sounds_on = bool(data.get("sounds_on", true))
	pinned_recipe = str(data.get("pinned_recipe", ""))
	if not Data.RECIPES.has(pinned_recipe):
		pinned_recipe = ""
	_check_quest() # quests judged on state (build, boss, travel) may already be done
	seen_recipes = []
	if data.has("seen_recipes"):
		for id in data["seen_recipes"]:
			if Data.RECIPES.has(id):
				seen_recipes.append(id)
	else:
		# Older save: don't flag everything already unlocked as new.
		seen_recipes = unseen_recipes()


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


# --- Dev helpers (debug builds; see the Dev section of the menu) -------------

func dev_give_materials() -> void:
	for id in Data.ITEMS:
		_add(storage, id, 20)
		add_to_bag(id, 5)
	notify("Dev: materials added.")
	changed.emit()


## Dresses the hunter in every piece of one tier (0 strips everything), to
## look at the gear without crafting it.
func dev_set_gear(tier: int) -> void:
	tools.clear()
	for id in Data.TOOLS:
		if Data.TOOLS[id].get("tier", 0) == tier:
			tools[id] = true
	changed.emit()
	save_game()


func dev_set_tier(kind: String, tier: int) -> void:
	structures[kind] = {"tier": tier, "busy_until": 0.0, "next_tier": 0}
	_check_quest()
	changed.emit()
	save_game()


func dev_set_level(target: int) -> void:
	target = clampi(target, 1, Data.LEVEL_XP.size())
	level = target
	xp = Data.LEVEL_XP[target - 1]
	leveled_up.emit(level)
	_check_quest()
	changed.emit()
	save_game()


func dev_finish_timers() -> void:
	for id in structures:
		if structure_busy(id):
			structures[id]["busy_until"] = now() - 1.0
	for station in craft_jobs:
		for job in craft_jobs[station]:
			job["done_at"] = now() - 1.0
	sleep_until = minf(sleep_until, now() - 1.0) if sleep_until > 0.0 else 0.0
	_update_timers(now())
	changed.emit()


func dev_reset_seen() -> void:
	seen_recipes = []
	changed.emit()


func dev_defeat_boss(kind: String) -> void:
	if not bosses_defeated.has(kind):
		bosses_defeated.append(kind)
	_check_quest()
	changed.emit()
	save_game()


func toggle_sounds() -> void:
	sounds_on = not sounds_on
	if sounds_on:
		Sfx.play("ui_tap")
	changed.emit()
	save_game()


func dev_advance_time(seconds: float) -> void:
	time_offset += seconds
	changed.emit()
