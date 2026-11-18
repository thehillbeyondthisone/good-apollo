extends SceneTree

var failures := PackedStringArray()
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func unpack_bundle(json: String) -> Dictionary:
	return JSON.parse_string(str(JSON.parse_string(json).payload))

func pack_bundle(payload: Dictionary) -> String:
	var encoded := JSON.stringify(payload)
	return JSON.stringify({"schemaVersion": 1, "payloadSha256": encoded.sha256_text(), "payload": encoded})

func normalize_native_numbers(data: Dictionary) -> Dictionary:
	for key: String in ["schemaVersion", "packetsReceived", "keyPressesSent", "quarterNanosecondRemainder", "startupRemainingNanoseconds"]:
		data[key] = int(data[key])
	return data

func tail(scene: Node, clock: Node) -> void:
	for key: String in ["verb", "3", "7"]:
		scene._operate("p4_dsky_" + key, 1)
		clock.advance_ticks(5)
		scene._release_button()
	scene._operate("p14_power_temp_mon", 1)
	scene._operate("p5_flood_ovhd_fwd", 1)
	clock.advance_ticks(35)
	scene._operate("p11_cb_r04_c19", 1)
	clock.advance_ticks(10)
	scene._operate("p11_cb_r04_c19", 1)
	clock.advance_ticks(40)

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	var systems = scene.systems
	check(systems != null and systems.session_clock != null, "Optional stepped mode creates one shared coordinator")
	if systems == null or systems.session_clock == null:
		quit(1)
		return
	var clock = systems.session_clock
	check(bool(systems.agc.call("IsStepped")), "Cabin uses the actual native CPU backend")
	check(int(systems.agc.call("GetOwnedProcessId")) == 0, "Shared-clock cabin has no external CPU process")
	check(clock.advance_ticks(75), "Both subsystems advance through the same 75 fixed ticks")
	check(int(systems.agc_snapshot.nativeCycles) == 64000, "Shared .75 seconds is exactly 64000 AGC cycles")
	check(is_equal_approx(float(systems.electrical_snapshot.simulationTimeSeconds), 0.75), "EPS elapsed time matches the shared clock")
	clock.advance_ticks(1)
	check(int(systems.agc_snapshot.quarterNanosecondRemainder) != 0, "Checkpoint case includes nonzero native subcycle carry")
	clock.pending_ns = 1234567
	clock.paused = true
	var paused_cpu: String = systems.agc.call("SaveStateJson")
	var paused_eps: String = systems.electrical.call("SaveStateJson")
	clock._physics_process(0.5)
	check(str(systems.agc.call("SaveStateJson")) == paused_cpu and str(systems.electrical.call("SaveStateJson")) == paused_eps, "Pause advances neither CPU nor EPS")
	var saved: String = clock.save_json()
	check(not saved.is_empty(), "Whole-session checkpoint serializes")
	var saved_payload := unpack_bundle(saved)
	check(saved_payload.controls.states.size() == scene.state_store.definitions.size(), "Checkpoint includes every declared control")
	var path := "user://checkpoint-test-%d.json" % Time.get_ticks_usec()
	check(clock.save_file(path), "Whole-session checkpoint writes atomically")
	check(FileAccess.get_file_as_string(path) == saved, "On-disk checkpoint equals the validated in-memory bundle")
	clock.paused = false
	tail(scene, clock)
	var expected_tail: String = clock.save_json()
	check(clock.restore_json(saved), "Whole session stages and restores")
	check(clock.paused and clock.pending_ns == 1234567, "Pause and pending shared-clock carry restore")
	check(clock.save_json() == saved, "Controls, EPS, CPU, relay latches and clock restore canonically")
	clock.paused = false
	tail(scene, clock)
	check(clock.save_json() == expected_tail, "Identical post-restore inputs reproduce the complete canonical session")
	var before_reject: String = clock.save_json()
	var bad := unpack_bundle(before_reject)
	var agc_data := normalize_native_numbers(JSON.parse_string(str(bad.agc)))
	var raw := Marshalls.base64_to_raw(str(agc_data.checkpointBase64))
	raw[-1] = raw[-1] ^ 0x5a
	agc_data.checkpointBase64 = Marshalls.raw_to_base64(raw)
	bad.agc = JSON.stringify(agc_data)
	check(not clock.restore_json(pack_bundle(bad)), "Corrupt CPU payload is rejected after EPS staging")
	check(clock.save_json() == before_reject, "Corrupt CPU payload cannot half-restore EPS, controls or clock")
	bad = unpack_bundle(before_reject)
	agc_data = normalize_native_numbers(JSON.parse_string(str(bad.agc)))
	agc_data.dllSha256 = "0".repeat(64)
	bad.agc = JSON.stringify(agc_data)
	check(not clock.restore_json(pack_bundle(bad)), "Foreign native DLL fingerprint is rejected")
	check(clock.save_json() == before_reject, "Foreign CPU payload leaves the complete session unchanged")
	bad = unpack_bundle(before_reject)
	agc_data = normalize_native_numbers(JSON.parse_string(str(bad.agc)))
	var forged_clock: int = int(bad.clock.completedNanoseconds) + clock.TICK_NS
	bad.clock.completedNanoseconds = str(forged_clock)
	agc_data.nativeCycles = str((forged_clock * 4) / 46875)
	agc_data.quarterNanosecondRemainder = (forged_clock * 4) % 46875
	bad.agc = JSON.stringify(agc_data)
	check(not clock.restore_json(pack_bundle(bad)), "Coordinated wrapper/shared-clock edits cannot bypass native payload timing")
	check(str(clock.last_error).contains("timing metadata"), "Clock validation reads authoritative staged native timing before EPS clock comparison")
	check(clock.save_json() == before_reject, "Forged matching clock metadata leaves all live state unchanged")
	bad = unpack_bundle(before_reject)
	bad.electrical = "{ malformed"
	check(not clock.restore_json(pack_bundle(bad)), "Corrupt EPS state is rejected before CPU mutation")
	check(clock.save_json() == before_reject, "Corrupt EPS state leaves CPU, controls and clock unchanged")
	bad = unpack_bundle(before_reject)
	bad.controls.states["p11_cb_r04_c19"] = 1 - int(bad.controls.states["p11_cb_r04_c19"])
	check(not clock.restore_json(pack_bundle(bad)), "Inconsistent physical and EPS switch positions are rejected")
	check(clock.save_json() == before_reject, "Inconsistent control payload does not partially restore")
	bad = unpack_bundle(before_reject)
	bad.clock.completedNanoseconds = str(int(bad.clock.completedNanoseconds) + 10000000)
	check(not clock.restore_json(pack_bundle(bad)), "CPU/shared-clock mismatch is rejected")
	check(clock.save_json() == before_reject, "Clock mismatch leaves the whole session unchanged")
	bad = unpack_bundle(before_reject)
	bad.inventorySha256 = "0".repeat(64)
	check(not clock.restore_json(pack_bundle(bad)), "Foreign control inventory is rejected")
	check(clock.save_json() == before_reject, "Foreign inventory leaves the whole session unchanged")
	check(systems.apply_preset("minimum_lifeboat_12a"), "Calibration preset can reset the EPS trial epoch")
	clock.advance_ticks(100)
	var epoch_save: String = clock.save_json()
	check(clock.restore_json(epoch_save), "EPS epoch offset and continuing CPU clock restore coherently")
	check(clock.save_json() == epoch_save, "Preset trial epoch is included in the canonical session")
	var before_demo: String = clock.save_json()
	systems.run_lamp_test()
	check(systems.demo_running, "Demonstration starts through the normal presenter path")
	check(clock.restore_json(before_demo), "Restoring a checkpoint during a demonstration succeeds")
	check(not systems.demo_running, "Restore cancels pending demonstration inputs")
	await process_frame
	check(clock.save_json() == before_demo, "Cancelled asynchronous demonstration cannot inject stale future keys")
	check(systems.apply_preset("electrical_checkout"), "Powered checkout is restored for held-key verification")
	var input_before: int = systems.agc.call("GetInputChannel", 26)
	scene._operate("p4_dsky_pro", 1)
	check((int(systems.agc.call("GetInputChannel", 26)) & 8192) == 0, "Physical PRO press reaches actual native input032")
	var held_save: String = clock.save_json()
	scene._release_button()
	clock.advance_ticks(3)
	check(clock.restore_json(held_save), "Checkpoint captured with PRO held restores")
	check(scene.state_store.position_name("p4_dsky_pro") == "RELEASED" and scene.held_button_ids.is_empty(), "Restore releases physical momentary controls")
	check(int(systems.agc.call("GetInputChannel", 26)) == (input_before | 8192), "Restore releases only PRO's active-low discrete")
	check(clock.load_file(path), "Atomic on-disk checkpoint restores through the same validation path")
	clock.paused = false
	for key: String in ["verb", "3", "7", "entr", "0", "0", "entr"]:
		scene._operate("p4_dsky_" + key, 1)
		clock.advance_ticks(25)
		scene._release_button()
	clock.advance_ticks(75)
	for key: String in ["verb", "3", "5", "entr"]:
		scene._operate("p4_dsky_" + key, 1)
		clock.advance_ticks(25)
		scene._release_button()
	var native_cabin_eights := false
	var native_test_alarm := false
	var native_test_clear := false
	for tick in range(800):
		clock.advance_ticks(1)
		var digits := ""
		for id: String in systems.readouts:
			if id.begins_with("p4_dsky_"): digits += str(systems.readouts[id].text)
		if digits.count("8") == 21: native_cabin_eights = true
		if systems.agc_snapshot.get("lampTestAlarm", false): native_test_alarm = true
		if native_test_alarm and not systems.agc_snapshot.get("lampTestAlarm", true): native_test_clear = true
	check(native_cabin_eights and native_test_alarm and native_test_clear, "Physical cabin keys drive genuine V35 through the shared native clock")
	check(is_equal_approx(float(systems.electrical_snapshot.simulationTimeSeconds), float(clock.completed_ns - clock.eps_epoch_ns) / 1000000000.0), "EPS remains on the same clock throughout the native lamp test")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	scene.queue_free()
	await process_frame
	var report := {"schemaVersion": 1, "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": Array(failures), "realUpstreamCpu": true, "sharedQuantumNanoseconds": 10000000, "nativeSubcycleCarry": true, "atomicRestore": true, "heldProNormalizedReleased": true, "flightPadloadApplied": false, "headsetTested": false}
	var report_path := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("reference/checkpoint-integration.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Shared-clock checkpoint integration: %s; %d checks; %d failures." % [report.result, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
