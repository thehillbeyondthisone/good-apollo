extends Node3D
## A temporary, isolated audition while the flight menu holds the real cabin.
## Never changes switches, mission progress, or the operator's saved mix.

var cabin: Node3D
var sound: Node3D
var voice: AudioStreamPlayer
var elapsed := 0.0
var next_event := 0
var voice_only := false
const EVENTS := [[1.3, "toggle", -0.4], [2.0, "toggle", 0.4],
	[2.8, "button", -0.2], [3.0, "release", -0.2], [3.7, "breaker", 0.4],
	[4.5, "detent", -0.25], [4.7, "detent", -0.25], [4.9, "detent", -0.25],
	[5.8, "fabric", -0.4], [6.8, "fastener", 0.4], [8.0, "water", 0.3],
	[9.7, "dry", 0.3], [10.5, "radio", 0.0], [19.7, "shutdown", 0.0],
	[22.0, "latch", 0.4]]

func setup(owner_cabin: Node3D, only_voice := false) -> void:
	cabin = owner_cabin
	voice_only = only_voice
	process_mode = Node.PROCESS_MODE_ALWAYS
	global_transform = cabin.active_camera.global_transform
	sound = load("res://scripts/cabin_audio.gd").new()
	add_child(sound)
	sound.levels = cabin.cabin_audio.levels.duplicate()
	sound.radio_enabled = cabin.cabin_audio.radio_enabled
	sound.enabled = cabin.cabin_audio.enabled
	if not voice_only: sound.set_power(1)
	sound.fan_player.position = Vector3(0.8, -0.3, 0.8)
	sound.pump_player.position = Vector3(-0.65, -0.65, 0.9)
	voice = load("res://scripts/co2_radio.gd").new()
	add_child(voice)
	voice.setup(cabin.repository_path("assets/audio/kerwin-co2" if voice_only else "assets/audio/mcc5"))
	if voice_only: voice.present("090:09:17")

func _process(delta: float) -> void:
	if sound == null: return
	if not cabin.flight_menu_is_open() or cabin.flight_interface.menu._page != "audio":
		queue_free()
		return
	elapsed += delta
	sound.set_voice_active(voice.playing and not voice.muted)
	if voice_only:
		if elapsed > 0.2 and not voice.playing: queue_free()
		return
	while next_event < EVENTS.size() and elapsed >= float(EVENTS[next_event][0]):
		_event(str(EVENTS[next_event][1]), float(EVENTS[next_event][2]))
		next_event += 1
	if elapsed >= 24.0: queue_free()

func _event(kind: String, side: float) -> void:
	var point := to_global(Vector3(side, -0.08, -0.7))
	match kind:
		"button": sound.play_control("pushbutton", point)
		"detent": sound.play_control("rotary", point, "audition_dial")
		"water": sound.set_water_flow(true, point)
		"dry": sound.set_water_flow(false, point)
		"radio": voice.present("103:51:07")
		"shutdown": sound.set_power(0)
		"fabric", "fastener", "release": sound.play_foley(kind, point)
		_: sound.play_control("mechanism" if kind == "latch" else kind, point)
