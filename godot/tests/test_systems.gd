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

func snapshot(bridge: Node) -> Dictionary:
	return JSON.parse_string(str(bridge.call("GetSnapshotJson")))

func bus(state: Dictionary, id: String) -> Dictionary:
	for value: Dictionary in state.get("buses", []):
		if value.get("id", "") == id: return value
	return {}

func dc_current(state: Dictionary) -> float:
	return float(bus(state, "CDR_DC").get("currentA", 0.0)) + float(bus(state, "LMP_DC").get("currentA", 0.0))

func battery(state: Dictionary, id: String) -> Dictionary:
	for value: Dictionary in state.get("batteries", []):
		if value.get("id", "") == id: return value
	return {}

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	check(scene.load_errors.is_empty(), "Cabin/inventory load without errors")
	var systems = scene.systems
	check(systems != null and systems.electrical != null, "Godot instantiates the headless C# EPS adapter")
	if systems == null or systems.electrical == null:
		quit(1)
		return
	var eps: Node = systems.electrical
	check(bool(eps.call("IsAvailable")), "Headless EPS definition initializes")
	check(systems.readouts.size() == 15, "Thirteen source digital windows and two live EPS readouts exist")
	check(systems.apply_preset("electrical_checkout"), "Electrical checkout calibration preset loads")
	# Sourced continuous dimmers start at their minimum. Turn them through the
	# actual input path before checking branch-powered illumination.
	scene._operate("p5_flood_ovhd_fwd", 1)
	scene._operate("p5_integral", 1)
	var powered := snapshot(eps)
	check(powered.get("batteries", []).size() == 6, "All six batteries are represented")
	check(powered.get("breakers", []).size() == 160, "All 160 declared breakers are connected")
	check(is_equal_approx(dc_current(powered), 12.0), "Checkout aggregate bus current is 12 A")
	check(is_equal_approx(float(bus(powered, "CDR_DC").get("voltageV", 0)), 30.0), "CDR DC bus exposes the configured 30 V surrogate")
	check(bool(bus(powered, "AC_A").get("powered", false)), "Inverter energizes AC bus A")
	check(scene.state_store.position_name("p11_cb_r04_c19") == "PUSHED", "EPS preset physically pushes DSKY breaker")
	check(bool(powered.poweredControls.get("p4_dsky_prog_display", false)), "DSKY display is powered through its branch")
	check(str(systems.readouts.p14_volts.text) == "30.0", "Live voltage readout comes from EPS snapshot")
	check(float(systems.lighting_state.get("flood", 0)) > 0, "Flood illumination responds to its energized breaker")
	check(float(systems.lighting_state.get("integral", 0)) > 0, "Integral illumination responds to its AC breaker")
	var dim_gain := float(systems.lighting_state.get("flood", 0))
	scene._operate("p5_flood_ovhd_fwd", 1)
	check(float(systems.lighting_state.get("flood", 0)) > dim_gain, "Actual panel-5 flood dimmer changes the rendered flood gain")
	scene._operate("p3_flood_ovhd_fwd", 1)
	check(is_zero_approx(float(systems.lighting_state.get("flood", -1))), "Flood routing OFF removes its rendered light")
	scene._operate("p3_flood_ovhd_fwd", -1)
	check(float(systems.lighting_state.get("flood", 0)) > 0, "Flood routing restores the selected dimmer gain")
	# Operate through the real desktop handler's method, not directly through the core.
	var low_id := "p14_se_bat_1_low_voltage"
	check(bool(eps.call("SetControl", low_id, "CENTER")), "Low-tap physical switch can return to CENTER")
	scene._operate(low_id, 1)
	check(scene.state_store.position_name(low_id) == "CENTER", "ECA interlock rejection restores the physical low-tap CENTER detent")
	check(bool(eps.call("SetControl", "p14_se_bat_1_hi_voltage", "CENTER")), "High-tap handle can return to CENTER while relay stays latched")
	scene._operate(low_id, 1)
	check(scene.state_store.position_name(low_id) == "CENTER" and bool(battery(snapshot(eps), "BAT1").connected), "Latched high relay still blocks low command when both handles are CENTER")
	scene._operate("p14_se_bat_1_hi_voltage", -1)
	scene._operate("p14_se_bat_1_hi_voltage", 1)
	check(scene.state_store.position_name("p14_se_bat_1_hi_voltage") == "CENTER" and not bool(battery(snapshot(eps), "BAT1").connected), "Physical OFF then CENTER retains disconnected high relay")
	scene._operate(low_id, 1)
	scene._operate(low_id, -1)
	check(scene.state_store.position_name(low_id) == "CENTER" and bool(battery(snapshot(eps), "BAT1").connected) and is_equal_approx(float(battery(snapshot(eps), "BAT1").voltageV), 28.0), "Physical low ON then CENTER keeps the sourced low-tap relay connected")
	scene._operate("p14_se_bat_1_hi_voltage", 1)
	check(scene.state_store.position_name("p14_se_bat_1_hi_voltage") == "CENTER", "Retained low relay rejects high ON and restores its physical CENTER")
	check(systems.apply_preset("electrical_checkout"), "Checkout restores source states after tap-latch tests")
	check(scene.state_store.position_name("p14_des_bats") == "CENTER", "Preset releases spring-return DES BATS handle after setting relay")
	scene._operate("p14_des_bats", -1, "integration")
	check(scene.state_store.position_name("p14_des_bats") == "CENTER" and bool(bus(snapshot(eps), "CDR_DC").powered), "Locked DES BATS does not operate without the unlock input")
	scene._operate("p14_des_bats", -1, "integration", true)
	check(scene.state_store.position_name("p14_des_bats") == "DEAD FACE" and not bool(bus(snapshot(eps), "CDR_DC").powered), "Unlocked physical DES BATS command disconnects descent feeds")
	scene._release_button("integration")
	check(scene.state_store.position_name("p14_des_bats") == "CENTER" and not bool(bus(snapshot(eps), "LMP_DC").powered), "Releasing DES BATS returns CENTER and preserves deadface relay")
	scene._operate("p14_bat_5_normal_se_feed", 1, "integration")
	scene._release_button("integration")
	check(scene.state_store.position_name("p14_bat_5_normal_se_feed") == "CENTER" and bool(battery(snapshot(eps), "BAT5").connected), "Ascent-feed input releases to CENTER while retaining a connected battery")
	var latch_checkpoint: String = eps.call("SaveStateJson")
	scene._operate("p14_bat_5_normal_se_feed", -1, "integration")
	scene._release_button("integration")
	check(not bool(battery(snapshot(eps), "BAT5").connected), "Physical ascent-feed OFF remains disconnected after release")
	check(bool(eps.call("LoadStateJson", latch_checkpoint)) and scene.state_store.position_name("p14_bat_5_normal_se_feed") == "CENTER" and bool(battery(snapshot(eps), "BAT5").connected), "Bridge restores the ascent relay with released physical CENTER")
	var bad_latches: Dictionary = JSON.parse_string(latch_checkpoint)
	bad_latches.feedCommands["p14_bat_5_normal_se_feed"] = "CENTER"
	check(not bool(eps.call("LoadStateJson", JSON.stringify(bad_latches))), "Bridge rejects CENTER as an electrical relay command")
	check(str(eps.call("SaveStateJson")) == latch_checkpoint, "Rejected relay save leaves bridge state unchanged")
	check(systems.apply_preset("electrical_checkout"), "Checkout restores all power after relay integration tests")
	scene._operate("p16_cb_r02_c01", 1)
	check(is_zero_approx(float(systems.lighting_state.get("flood", -1))), "Pulling the flood breaker darkens flood lighting")
	scene._operate("p16_cb_r02_c01", 1)
	check(float(systems.lighting_state.get("flood", 0)) > 0, "Closing the flood breaker restores flood lighting")
	scene._operate("p11_cb_r01_c19", 1)
	check(is_zero_approx(float(systems.lighting_state.get("integral", -1))), "Pulling integral lighting breaker removes panel emission")
	scene._operate("p11_cb_r01_c19", 1)
	# AMPS is explicitly unavailable for a bus-selector position.
	check(bool(eps.call("SetControl", "p14_power_temp_mon", "CDR BUS")), "Meter selector accepts CDR bus")
	check(str(systems.readouts.p14_amps.text) == "--", "Undefined bus-position AMPS is shown unavailable, not invented zero")
	check(bool(eps.call("SetControl", "p14_power_temp_mon", "BAT 1")), "Meter selector returns to a valid battery")
	check(str(systems.readouts.p14_amps.text) != "--", "Battery current readout becomes valid")
	check(str(systems.readouts.p14_volts.text) == "30.0", "C# bus voltage reaches the visible EPS readout")
	check(bool(eps.call("SetBatteryFault", "BAT1", true)), "Explicit synthetic battery fault reaches the core")
	check(bool(systems.electrical_snapshot.indicators.get("p1_master_alarm", false)), "Powered master alarm illuminates for the active warning")
	check(systems.annunciators.p1_master_alarm.albedo_color.r > 0.9, "Master alarm output changes the actual in-cabin material")
	scene._operate("p1_master_alarm", 1)
	scene._release_button()
	check(not bool(systems.electrical_snapshot.indicators.get("p1_master_alarm", true)), "Physical master alarm pushbutton acknowledges the active warning")
	eps.call("SetBatteryFault", "BAT1", false)
	eps.call("SetBatteryFault", "BAT1", true)
	check(bool(systems.electrical_snapshot.indicators.get("p1_master_alarm", false)), "A recurring warning relights the in-cabin master alarm")
	eps.call("SetBatteryFault", "BAT1", false)
	var presentation_id := ""
	for id: String in scene.state_store.definitions:
		if not id in systems.modeled_ids and scene.state_store.is_interactive(id) and not scene.state_store.is_momentary(id):
			presentation_id = id
			break
	check(not presentation_id.is_empty(), "There is an explicitly unmodeled presentation control")
	if not presentation_id.is_empty():
		scene._operate(presentation_id, 1)
		var changed: int = scene.state_store.states[presentation_id]
		eps.call("Advance", 0.25)
		check(scene.state_store.states[presentation_id] == changed, "EPS refresh does not reset unrelated presentation controls")
	check(bool(eps.call("InjectBranchFault", "p16_cb_r02_c01", 6.0)), "Explicit synthetic overcurrent can be injected for verification")
	eps.call("Advance", 0.25)
	check(scene.state_store.position_name("p16_cb_r02_c01") == "PULLED", "Synthetic trip physically opens its breaker")
	check(is_zero_approx(float(systems.lighting_state.get("flood", -1))), "Tripped branch removes flood illumination")
	check(systems.apply_preset("minimum_lifeboat_12a"), "Minimum-load calibration preset loads")
	var before_hour := snapshot(eps)
	check(bool(eps.call("Advance", 3600.0)), "Headless EPS advances one hour through its fixed ticks")
	var after_hour := snapshot(eps)
	check(is_equal_approx(float(after_hour.consumedAh) - float(before_hour.consumedAh), 12.0), "One calibrated hour consumes 12 Ah through the engine bridge")
	var saved: String = eps.call("SaveStateJson")
	eps.call("Advance", 10.0)
	check(bool(eps.call("LoadStateJson", saved)), "Bridge restores saved electrical state")
	check(str(eps.call("SaveStateJson")) == saved, "Electrical save/restore preserves deterministic core state")
	var before_bad: String = eps.call("SaveStateJson")
	check(not bool(eps.call("LoadStateJson", "{ malformed")), "Malformed electrical save is rejected")
	check(str(eps.call("SaveStateJson")) == before_bad, "Rejected electrical save does not partially apply")
	var null_map: Dictionary = JSON.parse_string(saved)
	null_map["controls"] = null
	check(not bool(eps.call("LoadStateJson", JSON.stringify(null_map))), "Null electrical control map is contained by the engine adapter")
	check(str(eps.call("SaveStateJson")) == before_bad, "Null-map save rejection preserves all electrical state")
	var guard_path := "user://eps-save-guard-%d.json" % Time.get_ticks_usec()
	var guard_file := FileAccess.open(guard_path, FileAccess.WRITE)
	guard_file.store_string(saved)
	guard_file.close()
	var failed_bridge: Node = load("res://scripts/ElectricalBridge.cs").new()
	scene.add_child(failed_bridge)
	check(not bool(failed_bridge.call("Initialize", "missing-electrical-file", "missing-control-file", "electrical_checkout")), "Failed electrical adapter reports unavailable")
	systems.electrical = failed_bridge
	check(not systems.save_state(guard_path), "Unavailable EPS cannot overwrite a saved state")
	check(FileAccess.get_file_as_string(guard_path) == saved, "Existing valid EPS save survives failed-adapter save attempt")
	systems.electrical = eps
	failed_bridge.queue_free()
	guard_file = FileAccess.open(guard_path, FileAccess.WRITE)
	guard_file.store_string("{ malformed")
	guard_file.close()
	scene.state_store.set_position(low_id, 0)
	scene._apply_position(low_id)
	check(not systems.load_state(guard_path), "Presenter reports a rejected electrical save")
	check(scene.state_store.position_name(low_id) == str(snapshot(eps).controlPositions[low_id]), "Rejected load restores physical controls from authoritative EPS state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(guard_path))
	check(systems.apply_preset("electrical_checkout"), "Checkout is restored for actual DSKY verification")
	var real_agc_passed := false
	if systems.agc != null:
		var deadline := Time.get_ticks_msec() + 6000
		while Time.get_ticks_msec() < deadline and not systems.agc_snapshot.get("connected", false):
			await create_timer(0.05).timeout
		check(systems.agc_snapshot.get("connected", false), "Owned real LM131R1 computer connects to the cabin")
		if systems.agc_snapshot.get("connected", false):
			systems.run_lamp_test()
			deadline = Time.get_ticks_msec() + 9000
			while Time.get_ticks_msec() < deadline and not systems.lamp_frame_seen:
				await create_timer(0.03).timeout
			check(systems.lamp_frame_seen, "Physical DSKY key path drives real LM131R1 V35 output")
			var rendered_digits := ""
			for id: String in systems.readouts:
				if id.begins_with("p4_dsky_"): rendered_digits += str(systems.readouts[id].text)
			check(rendered_digits.count("8") == 21, "All 21 actual AGC numeric eights reach in-cabin labels")
			check(scene.state_store.position_name("p4_dsky_entr") == "RELEASED", "Automated demo releases its physical key caps")
			scene._operate("p11_cb_r04_c19", 1)
			var blank := true
			for id: String in systems.readouts:
				if id.begins_with("p4_dsky_") and not str(systems.readouts[id].text).is_empty(): blank = false
			check(blank, "Opening the live DSKY breaker blanks all computer readouts")
			var before_keys: int = systems.agc_snapshot.get("keyPressesSent", 0)
			scene._operate("p4_dsky_verb", 1)
			scene._release_button()
			var raw: Dictionary = JSON.parse_string(str(systems.agc.call("GetSnapshotJson")))
			check(int(raw.get("keyPressesSent", 0)) == before_keys, "Unpowered DSKY keys do not reach the live AGC")
			scene._operate("p11_cb_r04_c19", 1)
			check(not str(systems.readouts.p4_dsky_r1_display.text).is_empty(), "Restoring DSKY power reveals the retained real row latches")
			real_agc_passed = systems.lamp_frame_seen and rendered_digits.count("8") == 21
			while systems.demo_running:
				await create_timer(0.05).timeout
	else:
		check(false, "Real AGC adapter exists for integration verification")
	check(systems.apply_preset("cold_dark"), "Cold-dark calibration preset loads")
	var dark := snapshot(eps)
	check(dark.buses.all(func(value: Dictionary) -> bool: return not value.get("powered", true)), "Cold-dark preset de-energizes every modeled bus")
	check(is_zero_approx(float(systems.lighting_state.get("flood", -1))) and is_zero_approx(float(systems.lighting_state.get("integral", -1))), "Cold-dark preset removes both power-dependent lighting groups")
	check(str(systems.readouts.p14_volts.text).is_empty(), "Unpowered EPS meter is blank")
	check(systems.readouts.values().all(func(label: Label3D) -> bool: return label.text.is_empty()), "Cold-dark blanks every powered and unmodeled digital window")
	check(not systems.agc_snapshot.get("flightPadloadApplied", true), "Live computer remains explicitly test-initialized")
	var owned_pid := int(systems.agc.call("GetOwnedProcessId")) if systems.agc != null else 0
	scene.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	var process_probe: Node = load("res://scripts/VirtualAgcBridge.cs").new()
	root.add_child(process_probe)
	check(owned_pid > 0 and not bool(process_probe.call("IsProcessAlive", owned_pid)), "Closing the cabin stops only its owned AGC process")
	process_probe.queue_free()
	var report := {
		"schemaVersion": 1, "result": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks, "failures": Array(failures), "realAgcCabinLampTestPassed": real_agc_passed,
		"headsetTested": false, "flightPadloadApplied": false,
		"electricalFidelity": "aggregate-calibrated partial model; not independent flight validation",
		"clockCoupling": "EPS fixed ticks; AGC external real time"
	}
	var report_path := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("reference/systems-integration.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Cabin / EPS / real AGC integration: %s; %d checks; %d failures; realV35=%s." % [report.result, checks, failures.size(), real_agc_passed])
	quit(0 if failures.is_empty() else 1)
