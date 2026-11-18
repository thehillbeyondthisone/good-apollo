extends SceneTree

var checks := 0
var failures := PackedStringArray()
var scene: Node3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func seek(index: int) -> void:
	for attempt in range(9):
		var current: int = scene.state_store.states.p3_lamp_tone_test
		if current == index:
			return
		scene._operate("p3_lamp_tone_test", 1 if current < index else -1, "caution-warning-test")
	check(false, "Physical test selector reaches detent %d" % index)

func cw() -> Dictionary:
	return scene.systems.electrical_snapshot.get("cautionWarning", {})

func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	check(scene.load_errors.is_empty(), "Actual cabin imports without errors")
	var systems: Node = scene.systems
	check(systems != null and systems.electrical != null, "Actual cabin uses C# electrical adapter")
	if systems == null or systems.electrical == null:
		quit(1)
		return
	check(systems.apply_preset("electrical_checkout"), "Calibration checkout powers actual test circuit")
	check("p3_lamp_tone_test" in systems.modeled_ids, "Actual selector is routed to EPS")
	check(not scene.cabin_audio.enabled, "Procedural audio remains muted until enabled")
	var tone_stream: AudioStreamWAV = scene.cabin_audio.warning_tone_player.stream
	var tone_data := tone_stream.data
	var positive_crossings := 0
	for sample in range(1, tone_data.size() >> 1):
		if tone_data.decode_s16((sample - 1) * 2) <= 0 and tone_data.decode_s16(sample * 2) > 0:
			positive_crossings += 1
	var measured_frequency := float(positive_crossings) * tone_stream.mix_rate / (float(tone_data.size()) / 2.0)
	check(absf(measured_frequency - 3000.0) < 1.0, "Generated waveform matches sourced 3kc warning tone")
	check(cw().get("testPowerAvailable", false) and not cw().get("testActive", true), "Powered OFF reports available feeds without activating a test")
	scene._operate("p16_cb_r02_c14", 1, "caution-warning-test")
	var bank_sizes := [2, 8, 9, 7, 9, 11]
	for index in range(1, 7):
		seek(index)
		check(int(scene.state_store.states.p3_lamp_tone_test) == index, "Actual rotary reaches source detent %d" % index)
		check(cw().get("testActive", false), "Actual bank %d works with instrumentation breaker open" % index)
		var tested: Array = cw().get("testedIndicatorIds", [])
		check(tested.size() == bank_sizes[index - 1], "Actual bank %d has the sourced output count" % index)
		for id: String in tested:
			check(systems.annunciators.has(id), "Source test lamp has an actual in-cabin material: " + id)
			if systems.annunciators.has(id):
				var color: Color = systems.annunciators[id].albedo_color
				check(maxf(color.r, color.b) > 0.9, "Actual test output illuminates in-cabin lamp: " + id)
		check(scene.cabin_audio.warning_tone_active == (index == 1), "Only ALARM/TONE bank requests tone")
		check(scene.state_store.position_name("p5_start") == "RELEASED", "Engine lamp test does not press physical START")
		if index == 2:
			var warning_color: Color = systems.annunciators.p1_asc_press_warning.albedo_color
			check(warning_color.r > 0.9 and warning_color.g < 0.2, "Actual warning test uses source aviation-red lamp color")
	seek(7)
	check(int(scene.state_store.states.p3_lamp_tone_test) == 7 and not cw().get("testActive", true), "Final physical OFF remains at index7 after EPS feedback")
	systems.electrical.call("Advance", 0.25)
	check(int(scene.state_store.states.p3_lamp_tone_test) == 7, "Periodic electrical refresh preserves duplicate final OFF")
	scene._operate("p3_lamp_tone_test", 1, "caution-warning-test")
	check(int(scene.state_store.states.p3_lamp_tone_test) == 7, "Final OFF endpoint cannot wrap")
	scene._operate("p3_lamp_tone_test", -1, "caution-warning-test")
	check(int(scene.state_store.states.p3_lamp_tone_test) == 6 and cw().get("selectorPosition", "") == "COMPN T", "Reverse from final OFF returns to adjacent component-test detent")
	var contact_color: Color = systems.annunciators.p1_lunar_contact.albedo_color
	check(contact_color.b > contact_color.r, "Actual lunar-contact test uses sourced blue lamp color")
	var component_color: Color = systems.annunciators.p2_glycol_component_caution.albedo_color
	check(component_color.r > 0.9 and component_color.g > 0.5 and component_color.b < 0.2, "Actual component caution test uses source aviation-yellow lamp color")
	seek(1)
	check(scene.cabin_audio.warning_tone_active and not scene.cabin_audio.warning_tone_player.playing, "Tone request respects mute")
	scene.cabin_audio.enabled = true
	check(scene.cabin_audio.warning_tone_player.playing, "Enabling sound starts the selected procedural warning tone")
	scene._operate("p1_master_alarm", 1, "caution-warning-test")
	scene._release_button("caution-warning-test")
	check(scene.cabin_audio.warning_tone_active, "Master acknowledgement cannot defeat selected tone test")
	scene._operate("p16_cb_r02_c04", 1, "caution-warning-test")
	check(not scene.cabin_audio.warning_tone_active and not scene.cabin_audio.warning_tone_player.playing, "Actual master-alarm breaker stops tone immediately")
	seek(2)
	check(cw().get("testedIndicatorIds", []).size() == 8, "Other lamp-test bank keeps its independent lighting feed")
	scene._operate("p11_cb_r03_c19", 1, "caution-warning-test")
	scene._operate("p16_cb_r02_c03", 1, "caution-warning-test")
	check(not cw().get("testActive", true), "Opening actual ANN feeds extinguishes warning bank")
	var dark_color: Color = systems.annunciators.p1_asc_press_warning.albedo_color
	check(dark_color.r < 0.1, "Unpowered warning bank becomes dark in actual cabin")
	seek(6)
	check(cw().get("testedIndicatorIds", []) == ["p14_dc_bus_fault"], "Actual DCFEEDER lamp keeps documented direct DC supply")
	check(systems.apply_preset("electrical_checkout"), "Restore normal circuit for actual-warning path")
	systems.electrical.call("SetBatteryFault", "BAT1", true)
	check(scene.cabin_audio.warning_tone_active, "Actual synthetic battery warning requests sourced warning tone")
	scene._operate("p1_master_alarm", 1, "caution-warning-test")
	scene._release_button("caution-warning-test")
	check(not scene.cabin_audio.warning_tone_active and systems.electrical_snapshot.indicators.p2_battery_caution, "Actual acknowledgement silences tone and keeps battery caution")
	systems.electrical.call("SetBatteryFault", "BAT1", false)
	seek(6)
	var saved: String = systems.electrical.call("SaveStateJson")
	seek(0)
	check(bool(systems.electrical.call("LoadStateJson", saved)), "Bridge restores lamp-test physical selection")
	check(int(scene.state_store.states.p3_lamp_tone_test) == 6 and cw().get("testedIndicatorIds", []).size() == 11, "Restored selector relights actual source component bank")
	check(systems.apply_preset("sourced_equipment_checkout"), "Sourced-equipment preset is available through presenter API")
	check("KNOWN EQUIPMENT" in scene.mode_label.text and "PARTIAL LOAD COVERAGE" in scene.mode_label.text, "Actual HUD labels component currents with partial coverage")
	check(not "EPS AGGREGATE" in scene.mode_label.text, "Known-equipment mode does not retain calibration-mode HUD label")
	check(systems.apply_preset("electrical_checkout"), "Aggregate mode can still be selected")
	check("EPS AGGREGATE" in scene.mode_label.text, "Aggregate preset retains aggregate HUD labeling")
	scene.cabin_audio.enabled = false
	var report := {"schemaVersion":1,"result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":Array(failures),"sourceInventorySha256":FileAccess.get_sha256(scene.repository_path("reference/controls.json")),"electricalDefinitionSha256":FileAccess.get_sha256(scene.repository_path("reference/electrical.json")),"basis":"LM-7 AOH Fig2.10-5 PDF634; PDF624,630,741,742,789","headsetTested":false,"audioEvidence":"Offline procedural stream lifecycle; no headset acoustic or measured-amplitude validation","kind":"Actual glTF cabin, EPS bridge, lamp material and warning-tone integration"}
	var file := FileAccess.open(scene.repository_path("reference/caution-warning-integration.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
