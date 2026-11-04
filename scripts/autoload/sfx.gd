extends Node
## Sound effects: Sfx.play("hit"). Streams are the placeholder WAVs in
## assets/sounds (made by tools/gen_sounds.py), played from a small pool of
## players so overlapping sounds don't cut each other off. Game.sounds_on
## mutes everything.

const DIR := "res://assets/sounds/"
const POOL := 8
const VOLUME_DB := -8.0

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.volume_db = VOLUME_DB
		p.bus = "Master"
		add_child(p)
		_players.append(p)


## Plays a named sound; pitch_jitter randomises the pitch a little so the
## same sound twice in a row doesn't sound mechanical.
func play(name: String, pitch_jitter := 0.08) -> void:
	if Game.get("sounds_on") == false:
		return
	var stream := _stream(name)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var path := DIR + name + ".wav"
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
		if _streams[name] == null:
			push_warning("Sfx: no sound named '%s'" % name)
	return _streams[name]
