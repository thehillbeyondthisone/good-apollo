extends SceneTree
## Deterministic audition through the real Godot spatial mixer and bus effects.
## --write-movie ../tmp/audio-render/mix.avi --fixed-fps 60

var sound: Node3D
var baseline: Node3D
var voice: AudioStreamPlayer
var elapsed := 0.0
var cue := 0
var events: Array[Array] = []
var limit := 38.0

func _initialize() -> void:
	_setup.call_deferred()

func _setup() -> void:
	root.size = Vector2i(64, 64)
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 1.4, -0.3)
	camera.current = true
	sound = load("res://scripts/cabin_audio.gd").new()
	world.add_child(sound)
	sound.enabled = false
	baseline = load("res://tests/fixtures/cabin_audio_baseline.gd").new()
	world.add_child(baseline)
	baseline.enabled = true
	baseline.set_power(1)
	voice = load("res://scripts/co2_radio.gd").new()
	world.add_child(voice)
	voice.setup(sound.asset_root().get_base_dir().path_join("mcc5"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--duration="): limit = float(arg.get_slice("=", 1))
	events = [
		[0.8, "old_toggle", -0.4], [1.7, "old_toggle", 0.4], [2.6, "old_breaker", -0.4], [3.5, "old_toggle", 0.4],
		[4.8, "new", 0],
		[6.0, "toggle", -0.4], [6.65, "toggle", 0.4], [7.3, "button", -0.2], [7.55, "release", -0.2],
		[8.3, "breaker", 0.5], [8.9, "breaker", 0.45],
		[9.6, "detent", -0.25], [9.79, "detent", -0.25], [9.98, "detent", -0.25], [10.17, "detent", -0.25],
		[11.0, "latch", 0.4], [12.2, "fabric", -0.4], [13.25, "fastener", 0.4],
		[14.6, "water_on", 0.35], [16.6, "water_off", 0.35],
		[18.0, "radio", 0], [20.1, "toggle", -0.3], [22.0, "button", 0.3],
		[27.8, "toggle", -0.4], [28.5, "breaker", 0.4],
		[30.0, "shutdown", 0], [33.0, "toggle", -0.4], [34.2, "latch", 0.4],
	]

func _process(delta: float) -> bool:
	if sound == null: return false
	elapsed += delta
	sound.set_voice_active(voice.playing)
	while cue < events.size() and elapsed >= float(events[cue][0]):
		_event(str(events[cue][1]), float(events[cue][2]))
		cue += 1
	if elapsed >= limit:
		quit()
	return false

func _event(kind: String, side: float) -> void:
	var point := Vector3(side, 1.35, -0.95)
	match kind:
		"old_toggle": baseline.play_control("toggle", point)
		"old_breaker": baseline.play_control("breaker", point)
		"new":
			baseline.enabled = false
			sound.enabled = true
			sound.set_power(1)
		"button": sound.play_control("pushbutton", point)
		"detent": sound.play_control("rotary", point, "showcase_dial")
		"water_on": sound.set_water_flow(true, point)
		"water_off": sound.set_water_flow(false, point)
		"radio": voice.present("103:51:07")
		"shutdown": sound.set_power(0)
		"fabric", "fastener", "release": sound.play_foley(kind, point)
		_: sound.play_control("mechanism" if kind == "latch" else kind, point)
