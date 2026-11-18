extends SceneTree
## Actual glTF cabin, EPS and menu integration. No subjective acoustic claims.

var checks := 0
var failures := PackedStringArray()
var cabin: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func position(id: String, label: String) -> void:
	var index: int = cabin.state_store.definitions[id].positions.find(label)
	check(index >= 0, "Declared position: " + id + " / " + label)
	if index >= 0:
		cabin.state_store.set_position(id, index)
		cabin._apply_position(id)
		cabin.systems.control_changed(id, label, true)

func _run() -> void:
	if not "--self-test" in OS.get_cmdline_user_args() or not "--systems-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	check(cabin.load_errors.is_empty(), "Actual cabin imports")
	var audio = cabin.cabin_audio
	check(audio.load_errors.is_empty(), "Complete sound palette loads in cabin")
	check(cabin.systems.apply_preset("electrical_checkout"), "Powered checkout available")
	position("p11_cb_r04_c05", "PUSHED")
	position("p11_cb_r04_c08", "PUSHED")
	position("p2_suit_fan", "1")
	position("p2_glycol_selector", "PUMP 1")
	check(audio.fan_target == 1 and audio.pump_target == 1, "Actual selectors and powered branches run both machines")
	position("p11_cb_r04_c05", "PULLED")
	check(audio.fan_target == 0 and audio.pump_target == 1, "Fan breaker silences only fan, despite live cabin buses")
	position("p16_cb_r03_c15", "PUSHED")
	position("p2_suit_fan", "2")
	check(audio.fan_target == 1, "Second fan follows the independent LMP branch")
	position("p2_glycol_selector", "INST (SEC)")
	check(audio.pump_target == 0, "Instrumentation mode does not invent a running secondary pump")
	audio.enabled = true
	var before: int = audio._age
	cabin._operate("p11_cb_r04_c05", 1, "audio-test")
	check(audio._age >= before + 2, "Desktop breaker action emits spatial mechanism and panel-body layers")
	before = audio._age
	cabin._set_xr_position("p2_suit_fan", 0, "left_hand")
	check(audio._age > before, "VR absolute selector path emits audio")
	before = audio._age
	cabin._set_xr_position("p2_suit_fan", 0, "left_hand")
	check(audio._age == before, "Unchanged VR sampling emits no extra clicks")
	before = audio._age
	cabin._set_axis("aot_reticle", 0.6, "left_hand", true)
	check(audio._age > before, "VR continuous knob emits a bounded mechanical detent")
	var voice = cabin.systems.co2.radio
	voice.present("090:09:17")
	check(voice.bus == "AQ Radio" and voice.playing, "Archival speech plays through dedicated radio mix")
	check(voice.volume_db != -5, "Measured clip gain replaces the old uniform voice attenuation")
	cabin.systems.co2.stage = 0
	cabin._process(0.016)
	check(audio.voice_active, "Actual playing CAPCOM activates speech priority")
	cabin._toggle_radio_audio()
	check(not audio.radio_enabled and voice.muted and not voice.playing and audio.enabled, "Radio mute leaves cabin sound enabled")
	cabin._toggle_radio_audio()
	var chapter_voice = load("res://scripts/co2_radio.gd").new()
	cabin.add_child(chapter_voice)
	chapter_voice.setup(cabin.repository_path("assets/audio/mcc5"))
	chapter_voice.muted = true
	chapter_voice.present("103:51:07")
	check(chapter_voice.playing and not chapter_voice.muted, "A new chapter reads the current global radio setting before autoplay")
	chapter_voice.stop()
	voice.repeat()
	cabin._toggle_cabin_audio()
	check(voice.playing and audio.radio_enabled and not audio.enabled, "Cabin mute leaves radio playing")
	voice.stop()
	var flight = load("res://scripts/flight_interface.gd").new()
	cabin.add_child(flight)
	cabin.flight_interface = flight
	flight.setup(cabin)
	cabin._show_flight_menu("pause")
	flight.menu._choose("audio")
	check(flight.menu._page == "audio" and paused, "Audio page opens while cabin remains paused")
	check(flight.menu.find_child("audio_radio", true, false) is Button, "Independent radio toggle is reachable in VR menu")
	cabin.handle_flight_action("audio_quiet")
	check(flight.menu._page == "audio" and audio.profile == "Quiet cabin", "Mix updates preserve audio subpage")
	cabin.handle_flight_action("audio_controls_down")
	check(float(audio.levels.controls) == -8 and audio.profile == "Custom", "Menu controls adjust the real mix")
	var equipment_target: float = audio.fan_target
	cabin.handle_flight_action("audio_preview")
	check(is_instance_valid(cabin._audio_audition) and cabin._audio_audition.can_process() and audio.fan_target == equipment_target, "Sound check runs while the real cabin remains paused and unchanged")
	cabin.handle_flight_action("audio_preview")
	await process_frame
	check(not is_instance_valid(cabin._audio_audition), "Sound check cancels without leaving looping voices")
	var chapter_state: Dictionary = cabin.systems.co2.save_state()
	cabin.handle_flight_action("audio_voice_preview")
	check(is_instance_valid(cabin._audio_audition) and cabin._audio_audition.voice_only and cabin._audio_audition.voice.playing and cabin._audio_audition.voice.cue_get == "090:09:17", "Houston voice test starts real archival speech immediately in the paused menu")
	check(cabin._audio_audition.sound.fan_target == 0 and cabin._audio_audition.sound.pump_target == 0 and audio.fan_target == equipment_target, "Voice-only check does not start machinery or change the live equipment")
	check(cabin.systems.co2.save_state() == chapter_state, "Testing Houston voice preserves actual chapter progress")
	cabin.handle_flight_action("audio_voice_preview")
	await process_frame
	check(not is_instance_valid(cabin._audio_audition), "Houston voice test can be stopped immediately")
	cabin.handle_flight_action("audio_radio")
	cabin.handle_flight_action("audio_voice_preview")
	check(not is_instance_valid(cabin._audio_audition) and cabin.status_message.contains("Mission radio is off"), "Muted radio gives a useful voice-test explanation")
	cabin.handle_flight_action("audio_radio")
	cabin.handle_flight_action("audio_preview")
	cabin.handle_flight_action("audio_preview")
	cabin.handle_flight_action("audio_preview")
	var replacement: int = cabin._audio_audition.get_instance_id()
	await process_frame
	check(is_instance_valid(cabin._audio_audition) and cabin._audio_audition.get_instance_id() == replacement, "Rapid preview restart cannot orphan the new sound-check session")
	cabin.handle_flight_action("audio_preview")
	await process_frame
	flight.back()
	check(flight.menu._page == "pause", "Back returns to pause page")
	paused = false
	cabin.queue_free()
	await process_frame
	var report := {"result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": Array(failures), "headsetTested": false}
	var path := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("reference/audio-integration.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
