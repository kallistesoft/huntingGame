extends Node
## Local notifications for the idle side of the game: when the app goes to
## the background, one notification is scheduled for every timer still
## running (building, crafting, sleeping), and they are all cancelled when
## the app comes back. Wraps the NotificationScheduler Android plugin
## (addons/NotificationSchedulerPlugin); without it, every call is a no-op,
## so desktop, headless tests and the plain-APK export keep working.

# The addon's scripts by path: their class_names are only known once the
# editor has scanned the project, which a fresh checkout has not done.
const SchedulerScript := preload("res://addons/NotificationSchedulerPlugin/NotificationScheduler.gd")
const ChannelScript := preload("res://addons/NotificationSchedulerPlugin/model/NotificationChannel.gd")
const DataScript := preload("res://addons/NotificationSchedulerPlugin/model/NotificationData.gd")

const CHANNEL_ID := "camp_timers"
const ICON := "ic_default_notification" # assets/NotificationSchedulerPlugin/android/drawable
const ID_BUILD := 100 # + structure index
const ID_CRAFT := 200 # + station index
const ID_SLEEP := 300
const ID_TEST := 900
const MIN_DELAY := 5.0 # seconds; shorter timers are not worth a notification

var _scheduler: Node = null # NotificationScheduler node when the plugin is present
var _channel_ready := false
var _asked := false # permission asked once per launch


func _ready() -> void:
	if not Engine.has_singleton("NotificationSchedulerPlugin"):
		return
	_scheduler = SchedulerScript.new()
	add_child(_scheduler)
	_scheduler.initialization_completed.connect(_on_initialized)
	_scheduler.initialize()


func available() -> bool:
	return _scheduler != null


func _on_initialized() -> void:
	var channel: RefCounted = ChannelScript.new()
	channel.set_id(CHANNEL_ID).set_name("Camp timers") \
		.set_description("A build, a craft or a night's sleep has finished.") \
		.set_importance(ChannelScript.Importance.DEFAULT)
	_scheduler.create_notification_channel(channel)
	_channel_ready = true


## Asks for the notification permission (Android 13+) the first time a timer
## starts, which is when the player understands why.
func ensure_permission() -> void:
	if _scheduler == null or _asked or not _channel_ready:
		return
	_asked = true
	if not _scheduler.has_post_notifications_permission():
		_scheduler.request_post_notifications_permission()


## What would be scheduled right now: [{id, title, text, delay}], from the
## game state alone, so it can be checked without the plugin.
func planned() -> Array:
	var out := []
	var now := Game.now()
	var index := 0
	for kind in Data.STRUCTURES:
		if Game.structure_busy(kind):
			var delay: float = Game.structures[kind]["busy_until"] - now
			if delay >= MIN_DELAY:
				out.append({"id": ID_BUILD + index, "delay": delay,
					"title": "%s ready" % Data.STRUCTURES[kind]["name"],
					"text": "Tier %d is finished at the camp." % Game.structures[kind]["next_tier"]})
		var q := Game.craft_queue(kind)
		if not q.is_empty():
			var last: Dictionary = q[-1]
			var delay: float = last["done_at"] - now
			if delay >= MIN_DELAY:
				var what := Data.recipe_name(last["recipe"]) + (" ×%d" % last["count"] if last["count"] > 1 else "")
				out.append({"id": ID_CRAFT + index, "delay": delay,
					"title": "%s done" % what,
					"text": "The %s has finished%s." % [Data.STRUCTURES[kind]["name"].to_lower(), " its queue" if q.size() > 1 else ""]})
		index += 1
	if Game.is_sleeping() and Game.sleep_left() >= MIN_DELAY:
		out.append({"id": ID_SLEEP, "delay": Game.sleep_left(),
			"title": "You're rested", "text": "Energy is back to %d. Time to hunt." % Game.max_energy()})
	return out


## The app went to the background: schedule one notification per timer.
func on_pause() -> void:
	if _scheduler == null:
		return
	_cancel_all()
	if not Game.notifications_on:
		return
	for n in planned():
		_schedule(n)


## The app is back: nothing should fire while the player is looking.
func on_resume() -> void:
	if _scheduler == null:
		return
	_cancel_all()


## Dev menu: a notification in a few seconds, to check the pipeline.
func test_in(seconds: int) -> void:
	if _scheduler == null:
		Game.notify("Notifications need the Android build with the plugin.")
		return
	ensure_permission()
	_schedule({"id": ID_TEST, "delay": seconds, "title": "Hunting Game", "text": "Test notification: the pipeline works."})
	Game.notify("Test notification in %d s. Put the app in the background." % seconds)


func _schedule(n: Dictionary) -> void:
	var data: RefCounted = DataScript.new()
	data.set_id(n["id"]).set_channel_id(CHANNEL_ID).set_title(n["title"]).set_content(n["text"]) \
		.set_small_icon_name(ICON).set_delay(int(ceil(n["delay"])))
	_scheduler.schedule(data)


func _cancel_all() -> void:
	for i in Data.STRUCTURES.size():
		_scheduler.cancel(ID_BUILD + i)
		_scheduler.cancel(ID_CRAFT + i)
	_scheduler.cancel(ID_SLEEP)
	_scheduler.cancel(ID_TEST)
