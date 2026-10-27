extends Node
## Rewarded ads. PLACEHOLDER: shows a fake full-screen "ad" for a few seconds,
## then grants the reward. Nothing is loaded from AdMob yet.
##
## To wire AdMob later (Android first, then iOS):
## 1. Install a Godot 4 AdMob plugin that supports Android and iOS.
## 2. Fill in the IDs below. During development use Google's TEST ids only;
##    showing or tapping real ads on your own device can get the account banned.
## 3. Replace the body of show_rewarded() with the plugin's load/show calls and
##    call on_done.call(true) only from the plugin's "user earned reward" event.
## The rest of the game only calls show_rewarded(), so nothing else changes.

const ANDROID_APP_ID := "" # ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyy
const ANDROID_REWARDED_UNIT_ID := ""
const IOS_APP_ID := ""
const IOS_REWARDED_UNIT_ID := ""

const PLACEHOLDER_SECONDS := 3.0

var _showing := false


func is_showing() -> bool:
	return _showing


## Shows a rewarded ad. on_done receives true when the reward is earned.
func show_rewarded(on_done: Callable) -> void:
	if _showing:
		return
	_showing = true

	var layer := CanvasLayer.new()
	layer.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	bg.add_child(label)
	add_child(layer)

	var left := PLACEHOLDER_SECONDS
	while left > 0.0:
		label.text = "PLACEHOLDER AD\n(AdMob rewarded ad goes here)\n\n%d" % ceili(left)
		await get_tree().create_timer(0.25).timeout
		left -= 0.25

	layer.queue_free()
	_showing = false
	on_done.call(true)
