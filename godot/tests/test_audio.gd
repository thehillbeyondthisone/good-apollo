extends SceneTree

var failures := PackedStringArray()
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var sound = load("res://scripts/cabin_audio.gd").new()
	root.add_child(sound)
	await process_frame
	check(not sound.enabled and not sound.fan_player.playing, "Muted test startup creates no looping playback")
	check(sound.load_errors.is_empty() and sound.streams.size() == 28, "All licensed sample families load")
	for item: Dictionary in sound.manifest.assets.values():
		check(FileAccess.get_sha256(sound.asset_root().path_join(str(item.file))) == item.sha256, "Shipped sample matches source manifest: " + str(item.file))
	check(sound.control_family("toggle") == "toggle" and sound.control_family("breaker") == "breaker", "Switch and breaker families are distinct")
	check(sound.control_family("mechanism", "shade_cdr") == "fabric" and sound.control_family("mechanism", "restraint_cdr") == "fastener", "Soft cabin mechanisms use appropriate Foley")
	sound.enabled = true
	sound.set_power(1.0)
	sound._process(1.0)
	check(sound.fan_player.playing and sound.pump_player.playing, "Powered equipment starts spatial sample loops")
	check(sound.fan_level == 1 and sound.fan_player.pitch_scale == 1, "Equipment reaches running pitch after spin-up")
	sound.play_control("toggle", Vector3(0.3, 1.4, -0.5), "toggle_test")
	var last: int = sound._last_variant.toggle
	sound.play_control("toggle", Vector3(-0.3, 1.4, -0.5), "toggle_test")
	check(sound._last_variant.toggle != last, "Consecutive physical switch clicks use different recordings")
	var before: int = sound._age
	sound.play_control("rotary", Vector3.ZERO, "dial")
	sound.play_control("rotary", Vector3.ZERO, "dial")
	check(sound._age == before + 1, "Rapid tracked dial sampling is rate-limited")
	sound.set_voice_active(true)
	sound._process(1.0)
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(sound.MACHINERY)) < -6.9, "Speech reduces equipment by seven dB")
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(sound.WARNING)) == 0, "Speech never ducks the warning bus")
	sound.set_voice_active(false)
	sound._process(4.0)
	check(sound.duck_amount < 0.01, "Mix recovers after speech")
	sound.set_power(0)
	sound._process(0.5)
	check(sound.fan_player.playing and sound.fan_level > 0 and sound.fan_player.pitch_scale < 1, "Power loss coasts down instead of cutting the loop")
	sound._process(2.0)
	check(not sound.fan_player.playing and not sound.pump_player.playing, "Power loss ends all machinery playback")
	sound.set_water_flow(true, Vector3(0.5, 1, 0.8))
	sound._process(0.1)
	check(sound.water_player.playing and sound.water_player.global_position == Vector3(0.5, 1, 0.8), "Water sound follows the unbracketed dispenser")
	sound.set_water_flow(false, Vector3.ZERO)
	sound._process(0.1)
	check(not sound.water_player.playing, "Release of the water trigger ends its loop")
	sound.set_warning_tone(true)
	sound.play_control("breaker", Vector3.ZERO)
	sound.enabled = false
	await process_frame
	var all_stopped: bool = not sound.fan_player.playing and not sound.water_player.playing and not sound.warning_tone_player.playing
	for player in sound.click_players: all_stopped = all_stopped and not player.playing
	check(all_stopped, "Muting immediately stops loops, warning and one-shot tails")
	sound.enabled = true
	sound.set_power(1)
	sound._process(0.1)
	check(sound.fan_player.playing and sound.warning_tone_player.playing, "Audio can be enabled again")
	sound.apply_profile("Quiet cabin")
	check(float(sound.levels.machinery) == -10, "Quiet cabin preset prioritizes speech")
	for index in 20: sound.adjust_level("master", 1)
	check(float(sound.levels.master) == 0, "Master boost is bounded")
	sound.apply_profile("Headphones")
	sound.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(sound), "Audio node teardown completes")
	var report := {"result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": Array(failures), "driver": "headless dummy; no audible output"}
	var target := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("reference/audio-lifecycle.json")
	var output := FileAccess.open(target, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
