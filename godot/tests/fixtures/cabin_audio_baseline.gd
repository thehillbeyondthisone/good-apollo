extends Node3D
## Procedural mechanical sounds. No mission recordings or third-party audio.
## Silent unless the user enables sound; safe for overnight builds/captures.

var enabled := false:
	set(value):
		enabled = value
		if fan_player != null:
			fan_player.volume_db = -34.0 if enabled else -80.0
			if enabled and is_inside_tree():
				_start_fan()
			else:
				_stop_fan()
		_update_warning_tone()
var power_fraction := 0.0
var fan_player: AudioStreamPlayer3D
var fan_playback: AudioStreamGeneratorPlayback
var click_players: Array[AudioStreamPlayer3D] = []
var click_stream: AudioStreamWAV
var breaker_stream: AudioStreamWAV
var sample_clock := 0
var filtered_noise := 0.0
var random := RandomNumberGenerator.new()
const WARNING_TONE_FREQUENCY_HZ := 3000.0
var warning_tone_active := false
var warning_tone_player: AudioStreamPlayer3D

func _ready() -> void:
	random.seed = 131970
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.16
	fan_player = AudioStreamPlayer3D.new()
	fan_player.name = "ProceduralCabinVentilation"
	fan_player.stream = generator
	fan_player.position = Vector3(0.9, 1.1, 0.9)
	fan_player.unit_size = 1.5
	fan_player.max_distance = 4.0
	fan_player.volume_db = -34.0 if enabled else -80.0
	add_child(fan_player)
	if enabled:
		_start_fan()
	click_stream = _make_click(0.045, 0.7)
	breaker_stream = _make_click(0.075, 0.45)
	for index in range(6):
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 0.7
		player.max_distance = 4.0
		player.volume_db = -24.0
		add_child(player)
		click_players.append(player)
	# LM-7 AOH2.10-2 specifies a 3kc audio tone. Gain and acoustic position
	# are illustrative; this procedural signal is not a mission recording.
	warning_tone_player = AudioStreamPlayer3D.new()
	warning_tone_player.name = "CautionWarningTone"
	warning_tone_player.stream = _make_warning_tone()
	warning_tone_player.position = Vector3(0.0, 1.6, 0.0)
	warning_tone_player.unit_size = 4.0
	warning_tone_player.max_distance = 8.0
	warning_tone_player.volume_db = -28.0
	add_child(warning_tone_player)
	_update_warning_tone()

func set_power(fraction: float) -> void:
	power_fraction = clampf(fraction, 0.0, 1.0)

func set_warning_tone(active: bool) -> void:
	warning_tone_active = active
	_update_warning_tone()

func _update_warning_tone() -> void:
	if not is_instance_valid(warning_tone_player):
		return
	if enabled and warning_tone_active and is_inside_tree():
		if not warning_tone_player.playing:
			warning_tone_player.play()
	else:
		warning_tone_player.stop()

func _start_fan() -> void:
	if not is_instance_valid(fan_player) or fan_player.playing:
		return
	fan_player.play()
	fan_playback = fan_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _stop_fan() -> void:
	fan_playback = null
	if is_instance_valid(fan_player):
		fan_player.stop()

func _exit_tree() -> void:
	set_process(false)
	_stop_fan()
	if is_instance_valid(fan_player):
		fan_player.stream = null
	for player in click_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	click_players.clear()
	click_stream = null
	breaker_stream = null
	fan_player = null
	if is_instance_valid(warning_tone_player):
		warning_tone_player.stop()
		warning_tone_player.stream = null
	warning_tone_player = null

func play_control(kind: String, world_position: Vector3) -> void:
	if not enabled or click_players.is_empty():
		return
	var player: AudioStreamPlayer3D = click_players[0]
	for candidate in click_players:
		if not candidate.playing:
			player = candidate
			break
	player.global_position = world_position
	player.stream = breaker_stream if kind == "breaker" else click_stream
	player.pitch_scale = 0.9 if kind == "rotary" else 1.0
	player.play()

func _process(_delta: float) -> void:
	if not enabled or fan_playback == null:
		return
	var available := fan_playback.get_frames_available()
	for index in range(available):
		filtered_noise = lerpf(filtered_noise, random.randf_range(-1.0, 1.0), 0.055)
		var time := float(sample_clock) / 22050.0
		var vibration := sin(TAU * 93.0 * time) * 0.035 + sin(TAU * 187.0 * time) * 0.012
		var sample := (filtered_noise * 0.25 + vibration) * power_fraction
		fan_playback.push_frame(Vector2(sample, sample))
		sample_clock += 1

func _make_click(duration: float, tone: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = int(tone * 1000.0)
	for index in range(samples):
		var time := float(index) / rate
		var envelope := exp(-time * 120.0)
		var impulse := noise.randf_range(-1.0, 1.0) * 0.38
		impulse += sin(TAU * (950.0 + 800.0 * tone) * time) * 0.18
		if time > 0.014:
			impulse += noise.randf_range(-1.0, 1.0) * exp(-(time - 0.014) * 190.0) * 0.10
		bytes.encode_s16(index * 2, int(clampf(impulse * envelope, -1, 1) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream

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
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = rate
	stream.data = bytes
	return stream
