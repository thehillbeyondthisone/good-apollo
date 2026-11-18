extends Node3D
## Spatial CC0 Foley and state-driven machinery. Designed acoustic proxies,
## not Apollo hardware recordings. The sourced 3 kHz warning stays procedural.

const MIX := "AQ Mix"
const CONTROLS := "AQ Controls"
const MACHINERY := "AQ Machinery"
const RADIO := "AQ Radio"
const WARNING := "AQ Warning"
const SETTINGS := "user://audio-mix.cfg"
const WARNING_TONE_FREQUENCY_HZ := 3000.0
const POOL_SIZE := 16
const FAMILY_FILES := {
	"toggle": ["toggle_1", "toggle_2", "toggle_3", "toggle_4"],
	"breaker": ["breaker_1", "breaker_2", "breaker_3"],
	"button": ["button_1", "button_2", "button_3"],
	"release": ["release_1", "release_2"],
	"detent": ["detent_1", "detent_2", "detent_3"],
	"latch": ["latch_1", "latch_2", "latch_3"],
	"body": ["body_1", "body_2", "body_3"],
	"fabric": ["fabric_1", "fabric_2", "fabric_3"],
	"fastener": ["fastener"],
}
const FAMILY_GAIN := {"toggle": -7.0, "breaker": -9.0, "button": -12.0,
	"release": -16.0, "detent": -15.0, "latch": -12.0, "body": -18.0,
	"fabric": -13.0, "fastener": -15.0}

var enabled := false:
	set(value):
		enabled = value
		if not value: _stop_all()
		_update_warning_tone()
var radio_enabled := true:
	set(value):
		radio_enabled = value
		if AudioServer.get_bus_index(RADIO) >= 0:
			AudioServer.set_bus_mute(AudioServer.get_bus_index(RADIO), not value)
var levels := {"master": -2.0, "controls": 0.0, "machinery": 0.0, "radio": 0.0}
var profile := "Headphones"
var streams: Dictionary = {}
var manifest: Dictionary = {}
var load_errors := PackedStringArray()
var click_players: Array[AudioStreamPlayer3D] = []
var fan_player: AudioStreamPlayer3D
var pump_player: AudioStreamPlayer3D
var water_player: AudioStreamPlayer3D
var warning_tone_player: AudioStreamPlayer3D
var warning_tone_active := false
var fan_target := 0.0
var pump_target := 0.0
var water_target := 0.0
var fan_level := 0.0
var pump_level := 0.0
var water_level := 0.0
var voice_active := false
var duck_amount := 0.0
var _age := 0
var _audio_time := 0.0
var _ages: Dictionary = {}
var _last_variant: Dictionary = {}
var _last_trigger: Dictionary = {}
var _axis_steps: Dictionary = {}
var _random := RandomNumberGenerator.new()

static func install_mix() -> void:
	if AudioServer.get_bus_index(MIX) >= 0: return
	for bus_name: String in [MIX, CONTROLS, MACHINERY, RADIO, WARNING]:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master" if bus_name == MIX else MIX)
	# Only Aquarius' own output is processed; the global Master is untouched.
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(MIX), limiter)
	var room := AudioEffectReverb.new()
	room.room_size = 0.18
	room.damping = 0.85
	room.predelay_msec = 12.0
	room.hipass = 0.45
	room.wet = 0.055
	room.dry = 1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(CONTROLS), room)
	var voice := AudioEffectCompressor.new()
	voice.threshold = -19.0
	voice.ratio = 2.0
	voice.attack_us = 1800.0
	voice.release_ms = 160.0
	voice.gain = 1.5
	AudioServer.add_bus_effect(AudioServer.get_bus_index(RADIO), voice)

static func asset_root() -> String:
	return ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("assets/audio/cabin")

func _ready() -> void:
	install_mix()
	_random.seed = 131970 if "--self-test" in OS.get_cmdline_user_args() else Time.get_ticks_usec()
	var manifest_path := asset_root().path_join("manifest.json")
	if FileAccess.file_exists(manifest_path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if data is Dictionary: manifest = data
	for family: String in FAMILY_FILES:
		for file: String in FAMILY_FILES[family]: _load_sample(file)
	for file: String in ["ventilation", "pump", "water"]: _load_sample(file, true)
	for index in POOL_SIZE:
		var player := _player("MechanismVoice%d" % index, CONTROLS, Vector3.ZERO, 0.8)
		player.panning_strength = 0.72
		click_players.append(player)
	fan_player = _player("SuitCircuitVentilation", MACHINERY, Vector3(0.80, 1.15, 0.80), 2.0)
	fan_player.panning_strength = 0.32
	fan_player.stream = streams.get("ventilation")
	pump_player = _player("PrimaryGlycolPump", MACHINERY, Vector3(-0.65, 0.75, 0.90), 1.8)
	pump_player.panning_strength = 0.42
	pump_player.stream = streams.get("pump")
	water_player = _player("DispenserFlow", CONTROLS, Vector3.ZERO, 0.55)
	water_player.stream = streams.get("water")
	warning_tone_player = _player("CautionWarningTone", WARNING, Vector3(0, 1.6, 0), 4.0)
	warning_tone_player.stream = _make_warning_tone()
	warning_tone_player.volume_db = -28.0
	if not "--self-test" in OS.get_cmdline_user_args(): _load_settings()
	radio_enabled = radio_enabled
	_apply_mix()
	_update_warning_tone()

func _load_sample(file: String, loop := false) -> void:
	if streams.has(file): return
	var path := asset_root().path_join(file + ".wav")
	if not FileAccess.file_exists(path):
		load_errors.append("Missing cabin sound: " + file)
		return
	var stream := AudioStreamWAV.load_from_file(path)
	if stream == null:
		load_errors.append("Invalid cabin sound: " + file)
		return
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / 2
	streams[file] = stream

func _player(label: String, bus_name: String, origin: Vector3, size: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = label
	player.bus = bus_name
	player.position = origin
	player.unit_size = size
	player.max_distance = 6.0
	player.max_db = 0.0
	player.attenuation_filter_cutoff_hz = 8500.0
	player.attenuation_filter_db = -9.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	player.volume_db = -80.0
	add_child(player)
	return player

func control_family(kind: String, id := "", released := false) -> String:
	if released: return "release"
	if id.begins_with("shade_") or id.begins_with("hammock_") or "restraint" in id or "stowage" in id:
		return "fastener" if "restraint" in id or "stowage" in id else "fabric"
	if kind == "breaker": return "breaker"
	if kind in ["rotary", "thumbwheel", "knob", "axis", "joystick"]: return "detent"
	if kind in ["pushbutton", "button", "key"]: return "button"
	if kind in ["mechanism", "guard", "valve"] or "hatch" in id or "guard" in id or "armrest" in id or id.begins_with("ecs_"):
		return "latch"
	return "toggle"

func play_control(kind: String, world_position: Vector3, id := "", released := false) -> void:
	if not enabled: return
	var family := control_family(kind, id, released)
	var now := roundi(_audio_time * 1000.0)
	var key := id if not id.is_empty() else kind
	# Continuous tracked dials must not turn controller sampling into a buzz.
	if family == "detent" and now - int(_last_trigger.get(key, -1000)) < 65: return
	_last_trigger[key] = now
	_play_family(family, world_position)
	if family == "breaker": _play_family("body", world_position, -5.0, 0.85)
	elif family == "latch": _play_family("body", world_position, -7.0, 0.94)

func play_foley(family: String, world_position: Vector3) -> void:
	if enabled and FAMILY_FILES.has(family): _play_family(family, world_position)

func play_axis(id: String, world_position: Vector3, value: float) -> void:
	var hand_control := id.begins_with("aca_") or id.begins_with("ttca_")
	var step := int(absf(value) > 0.08) if hand_control else roundi(value * 10.0)
	var previous := int(_axis_steps.get(id, 0))
	_axis_steps[id] = step
	if not enabled or step == previous: return
	if hand_control:
		if step == 1: _play_family("body", world_position, -5.0)
	else:
		play_control("axis", world_position, id)

func _play_family(family: String, world_position: Vector3, gain := 0.0, pitch := 1.0) -> void:
	if click_players.is_empty(): return
	var files: Array = FAMILY_FILES[family]
	var variant := _random.randi_range(0, files.size() - 1)
	if files.size() > 1 and variant == int(_last_variant.get(family, -1)):
		variant = (variant + _random.randi_range(1, files.size() - 1)) % files.size()
	_last_variant[family] = variant
	if not streams.has(files[variant]): return
	var player := click_players[0]
	for candidate in click_players:
		if not candidate.playing:
			player = candidate
			break
		if int(_ages.get(candidate.get_instance_id(), 0)) < int(_ages.get(player.get_instance_id(), 0)):
			player = candidate
	player.stop()
	player.global_position = world_position
	player.stream = streams[files[variant]]
	player.volume_db = float(FAMILY_GAIN[family]) + gain + _random.randf_range(-0.8, 0.8)
	player.pitch_scale = pitch * _random.randf_range(0.975, 1.025)
	_age += 1
	_ages[player.get_instance_id()] = _age
	player.play()

func set_power(fraction: float) -> void:
	# Audition/legacy entry point. Live cabin uses individual branch gates below.
	fan_target = clampf(fraction, 0, 1)
	pump_target = fan_target

func update_equipment(snapshot: Dictionary, store) -> void:
	var branches := {}
	for branch: Dictionary in snapshot.get("breakers", []):
		branches[str(branch.get("controlId", ""))] = bool(branch.get("powered", false))
	var fan := str(store.position_name("p2_suit_fan"))
	var fan_branch := "p11_cb_r04_c05" if fan == "1" else "p16_cb_r03_c15"
	fan_target = 1.0 if fan in ["1", "2"] and branches.get(fan_branch, false) else 0.0
	var pump := str(store.position_name("p2_glycol_selector"))
	var pump_branch := "p11_cb_r04_c08" if pump == "PUMP 1" else "p11_cb_r04_c07"
	pump_target = 1.0 if pump in ["PUMP 1", "PUMP 2"] and branches.get(pump_branch, false) else 0.0

func set_water_flow(active: bool, world_position: Vector3) -> void:
	water_target = 1.0 if active else 0.0
	if is_instance_valid(water_player): water_player.global_position = world_position

func set_voice_active(active: bool) -> void:
	voice_active = active and radio_enabled

func set_warning_tone(active: bool) -> void:
	warning_tone_active = active
	_update_warning_tone()

func _update_warning_tone() -> void:
	if not is_instance_valid(warning_tone_player): return
	if enabled and warning_tone_active and is_inside_tree():
		if not warning_tone_player.playing: warning_tone_player.play()
	else:
		warning_tone_player.stop()

func _process(delta: float) -> void:
	_audio_time += delta
	var duck_target := 1.0 if voice_active else 0.0
	duck_amount = lerpf(duck_amount, duck_target, 1.0 - exp(-delta / (0.08 if voice_active else 0.65)))
	_apply_mix()
	if not enabled: return
	fan_level = _smooth(fan_level, fan_target, delta, 1.0, 1.65)
	pump_level = _smooth(pump_level, pump_target, delta, 0.6, 1.2)
	water_level = _smooth(water_level, water_target, delta, 0.04, 0.07)
	_update_loop(fan_player, fan_level, -12.0, 0.72 + 0.28 * fan_level)
	_update_loop(pump_player, pump_level, -13.0, 0.83 + 0.17 * pump_level)
	_update_loop(water_player, water_level, -4.0, 1.0)

func _smooth(value: float, target: float, delta: float, attack: float, release: float) -> float:
	return move_toward(value, target, delta / (attack if target > value else release))

func _update_loop(player: AudioStreamPlayer3D, level: float, gain: float, pitch: float) -> void:
	if player == null or player.stream == null: return
	if level <= 0.001:
		player.stop()
		return
	player.volume_db = gain + linear_to_db(level)
	player.pitch_scale = pitch
	if not player.playing: player.play()

func _apply_mix() -> void:
	for pair: Array in [[MIX, float(levels.master)], [CONTROLS, float(levels.controls) - 2.5 * duck_amount],
		[MACHINERY, float(levels.machinery) - 7.0 * duck_amount], [RADIO, float(levels.radio)]]:
		var index := AudioServer.get_bus_index(str(pair[0]))
		if index >= 0: AudioServer.set_bus_volume_db(index, float(pair[1]))

func adjust_level(channel: String, direction: float) -> void:
	if not levels.has(channel): return
	levels[channel] = clampf(float(levels[channel]) + direction * 3.0, -30.0, 6.0 if channel != "master" else 0.0)
	profile = "Custom"
	_apply_mix()
	save_settings()

func apply_profile(next: String) -> void:
	profile = next
	match next:
		"Quiet cabin": levels = {"master": -5.0, "controls": -5.0, "machinery": -10.0, "radio": 1.0}
		"Speakers": levels = {"master": -2.0, "controls": 1.0, "machinery": 2.0, "radio": 2.0}
		_: levels = {"master": -2.0, "controls": 0.0, "machinery": 0.0, "radio": 0.0}
	_apply_mix()
	save_settings()

func save_settings() -> void:
	if "--self-test" in OS.get_cmdline_user_args(): return
	var config := ConfigFile.new()
	config.set_value("mix", "enabled", enabled)
	config.set_value("mix", "radio_enabled", radio_enabled)
	config.set_value("mix", "profile", profile)
	for channel: String in levels: config.set_value("levels", channel, levels[channel])
	config.save(SETTINGS)

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS) != OK: return
	enabled = bool(config.get_value("mix", "enabled", enabled))
	radio_enabled = bool(config.get_value("mix", "radio_enabled", true))
	profile = str(config.get_value("mix", "profile", "Headphones"))
	for channel: String in levels:
		levels[channel] = clampf(float(config.get_value("levels", channel, levels[channel])), -30.0, 0.0 if channel == "master" else 6.0)

func _stop_all() -> void:
	for player in click_players: player.stop()
	for player in [fan_player, pump_player, water_player, warning_tone_player]:
		if is_instance_valid(player): player.stop()
	fan_level = 0.0
	pump_level = 0.0
	water_level = 0.0

func _exit_tree() -> void:
	_stop_all()
	for player in click_players: player.stream = null
	for player in [fan_player, pump_player, water_player, warning_tone_player]:
		if is_instance_valid(player): player.stream = null
	click_players.clear()
	streams.clear()

func _make_warning_tone() -> AudioStreamWAV:
	var rate := 44100
	var bytes := PackedByteArray()
	bytes.resize(rate * 2)
	for index in range(rate):
		var sample := sin(TAU * WARNING_TONE_FREQUENCY_HZ * float(index) / float(rate)) * 0.25
		bytes.encode_s16(index * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = rate
	stream.data = bytes
	return stream
