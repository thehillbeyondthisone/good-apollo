extends SceneTree
## Actual desktop replay, branch gating and complete checkpoint checks. No OpenXR.

var checks := 0
var failures := PackedStringArray()
var cabin: Node

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("FAIL: " + message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.000001, "%s: %.9f versus %.9f" % [message, actual, expected])

func key_f12(restart: bool = false) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_F12
	key.pressed = true
	key.shift_pressed = restart
	cabin._unhandled_input(key)

func operate_to(id: String, label: String) -> bool:
	var positions: Array = cabin.state_store.definitions[id].positions
	var target := positions.find(label)
	if target < 0: return false
	for attempt in range(positions.size() + 1):
		var current: int = cabin.state_store.states[id]
		if current == target: return true
		cabin._operate(id, 1 if target > current else -1, "powerdown-integration", true)
	return false

func dc_current() -> float:
	var total := 0.0
	for bus: Dictionary in cabin.systems.electrical_snapshot.buses:
		if str(bus.id).ends_with("_DC"): total += float(bus.currentA)
	return total

func follow_callout(step: Dictionary) -> void:
	for action: Dictionary in step.actions:
		var id := str(action.controlId)
		if cabin.state_store.position_name(id) != str(action.position):
			check(cabin._inspect_checklist_control(id), "Desktop sight line reaches " + id)
			check(operate_to(id, str(action.position)), "Player can operate " + id)
	key_f12()

func unpack_bundle(json: String) -> Dictionary:
	return JSON.parse_string(str(JSON.parse_string(json).payload))

func pack_bundle(payload: Dictionary) -> String:
	var encoded := JSON.stringify(payload)
	return JSON.stringify({"schemaVersion": 1, "payloadSha256": encoded.sha256_text(), "payload": encoded})

func _run() -> void:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	await physics_frame
	check(cabin.load_errors.is_empty() and cabin.systems != null, "Actual cabin and systems initialize")
	check(not cabin.xr_active, "Headset runtime remains disabled")
	var systems: Node = cabin.systems
	var clock: Node = systems.session_clock
	check(clock != null and bool(systems.agc.call("IsStepped")), "Actual native CPU and EPS use the shared clock")
	if clock == null:
		quit(1)
		return
	var sequence_path: String = cabin.repository_path("reference/electrical-powerdown-sequence.json")
	var sequence = JSON.parse_string(FileAccess.get_file_as_string(sequence_path))
	check(sequence is Dictionary and sequence.get("events", null) is Array, "Source-qualified sequence data is present")
	if not sequence is Dictionary or not sequence.get("events", null) is Array:
		quit(1)
		return
	var events: Array = sequence.events
	check(not bool(sequence.completeFlownConfiguration) and not bool(sequence.independentFlightValidationPassed), "Replay does not certify a complete flown configuration or flight budget")
	check(str(sequence.qualification).contains("CPU") and str(sequence.qualification).contains("Unknown"), "Source qualifications retain CPU and equipment coverage limits")
	check(not bool(systems.powerdown_snapshot.get("active", false)), "Replay is initially inactive")
	check(clock.advance_ticks(31) and int(systems.agc_snapshot.nativeCycles) > 0, "Powered checkout establishes live CPU time before the power-down")
	key_f12()
	check(bool(systems.powerdown_snapshot.get("active", false)) and int(systems.powerdown_snapshot.currentIndex) == 0, "First F12 starts the source replay without consuming its first event")
	check(int(systems.powerdown_snapshot.eventCount) == events.size(), "Presenter exposes the complete recorded event count")
	check(systems.electrical_snapshot.loadModel == "sourced_components" and not bool(systems.electrical_snapshot.completeEquipmentLoadCoverage), "Replay starts with partial source equipment accounting")
	check(cabin.mode_label.text.contains("HANDS-ON POWER-DOWN") and cabin.mode_label.text.contains("PARTIAL LOAD COVERAGE"), "HUD distinguishes checklist and incomplete demand")
	check(systems.powerdown_text.text.contains("HOUSTON · BRAND") and systems.powerdown_text.text.contains("Power-5"), "Scenario starts with the historical hold callout")
	near(float(systems.powerdown_snapshot.cabinTemperatureF), 68.0, "Scenario starts at the warm training baseline")
	var warm_flood := float(systems.lighting_state.flood)
	var warm_integral := float(systems.lighting_state.integral)
	var world := cabin.get_node("CabinEnvironment") as WorldEnvironment
	var warm_ambient := world.environment.ambient_light_energy
	check(warm_flood > 0.0 and warm_integral > 0.0, "Powered cabin starts with flood and integral illumination")
	check(not operate_to("p16_cb_r04_c01", "PULLED") and cabin.status_message.contains("sealed closed"), "Player cannot pull the sealed Quad 1 heater breaker")
	var initial_current := dc_current()
	var start_completed: int = clock.completed_ns
	var staged_save := ""
	var staged_index := 0
	var mapped_actions := 0
	var prior_get := -1
	for index in range(events.size()):
		var event: Dictionary = events[index]
		var before_eps := str(systems.electrical.call("SaveStateJson"))
		var before_current := dc_current()
		if not systems.powerdown_target().is_empty():
			key_f12()
			check(int(systems.powerdown_snapshot.currentIndex) == index and str(systems.electrical.call("SaveStateJson")) == before_eps, "F12 cannot apply or skip a pending operation: " + str(event.id))
		if str(event.id) == "lighting_selectors":
			check(cabin._inspect_checklist_control("p3_flood_ovhd_fwd"), "Desktop sight line reaches the flood selector")
			check(operate_to("p3_flood_ovhd_fwd", "OFF"), "Player can partially complete a callout")
			var partial_save: String = clock.save_json()
			check(operate_to("p3_flood_ovhd_fwd", "OVHD/FWD"), "Player can change the state after saving")
			check(clock.restore_json(partial_save) and systems.powerdown_target() == "p3_exterior_ltg", "Restoring mid-callout preserves the completed flood operation and next target")
			check(operate_to("p16_cb_r03_c05", "PUSHED"), "Player can reverse an earlier ordinary breaker")
			check(systems.powerdown_snapshot.pendingActions.any(func(action): return action.controlId == "p16_cb_r03_c05"), "A reversed earlier operation must be corrected before proceeding")
			check(operate_to("p16_cb_r03_c05", "PULLED"), "Player can correct the earlier breaker position")
		follow_callout(event)
		check(int(systems.powerdown_snapshot.currentIndex) == index + 1 and str(systems.powerdown_snapshot.lastEvent.id) == str(event.id), "Verified positions allow exactly one historical callout to advance: " + str(event.id))
		check(int(event.getSeconds) >= prior_get and str(systems.powerdown_snapshot.lastEvent["get"]) == str(event["get"]), "Historical GET labels retain source order: " + str(event.id))
		prior_get = int(event.getSeconds)
		check(clock.completed_ns == start_completed and is_zero_approx(float(systems.electrical_snapshot.simulationTimeSeconds)), "Historical GET does not fast-forward CPU or electrical time: " + str(event.id))
		if event.actions.is_empty():
			check(str(systems.electrical.call("SaveStateJson")) == before_eps, "Read-up/summary marker changes no electrical state: " + str(event.id))
		for action: Dictionary in event.actions:
			mapped_actions += 1
			var id := str(action.controlId)
			check(cabin.state_store.position_name(id) == str(action.position), "Source action reaches its actual cabin control: " + id)
			check(str(systems.electrical_snapshot.controlPositions.get(id, "")) == str(action.position), "Source action is retained in electrical logical state: " + id)
		for quad in range(1, 5):
			check(cabin.state_store.position_name("p16_cb_r04_c%02d" % quad) == "PUSHED", "A/B-2 heater supply remains closed throughout replay: quad%d" % quad)
		if str(event.id) == "amplifier_branch":
			near(before_current - dc_current(), 72.0 / 30.0, "Opening the source amplifier branch removes exactly its72W known demand")
			check(cabin.state_store.position_name("p12_pwr_ampl") == "PRIM", "Amplifier selector remains PRIMARY with its breaker open")
		if str(event.id) == "final_readup":
			check(cabin.state_store.position_name("p11_cb_r04_c19") == "PUSHED", "Read-up leaves LGC branch energized until the execution step")
		if str(event.id) == "atca_pgns":
			for column in range(2, 6):
				check(cabin.state_store.position_name("p11_cb_r02_c%02d" % column) == "PULLED", "Reported TCA removal precedes final deep-powerdown read-up: column%d" % column)
		if str(event.id) == "lighting_selectors":
			check(is_zero_approx(float(systems.lighting_state.flood)) and world.environment.ambient_light_energy < warm_ambient, "Flood OFF darkens the rendered cabin immediately")
			check(operate_to("p14_power_temp_mon", "BAT 2"), "Manual control adjustment remains available during guided review")
			staged_save = clock.save_json()
			staged_index = index + 1
			check(not staged_save.is_empty(), "Intermediate replay and manual override have a complete checkpoint")
	check(int(systems.powerdown_snapshot.currentIndex) == events.size(), "All recorded source events complete")
	check(systems.powerdown_text.text.contains("POWER-DOWN COMPLETE") and systems.powerdown_text.text.contains("CO₂ adapter"), "The finished power-down offers the CO₂ chapter")
	check(is_zero_approx(float(systems.lighting_state.integral)), "Inverter OFF removes integral panel lighting")
	near(float(systems.powerdown_snapshot.cabinTemperatureF), 68.0, "Flipping controls alone does not instantly cool the cabin")
	check(cabin.state_store.position_name("p11_cb_r04_c19") == "PULLED" and cabin.state_store.position_name("p11_cb_r04_c20") == "PUSHED" and cabin.state_store.position_name("p11_cb_r04_c21") == "PULLED", "Final LGC/DSKY and IMU operate are open while IMU standby remains closed")
	check(cabin.state_store.position_name("p11_cb_r04_c15") == "PULLED" and cabin.state_store.position_name("p16_cb_r03_c02") == "PUSHED", "Final configuration retains only the LMP audio supply")
	for quad in range(1, 5):
		check(cabin.state_store.position_name("p3_rcs_sys_a_b_2_quad_%d" % quad) == "OFF", "Final panel3 heater selector is OFF: quad%d" % quad)
	check(cabin.state_store.position_name("p16_cb_r02_c01") == "PULLED" and cabin.state_store.position_name("p16_cb_r02_c02") == "PULLED", "Final confirmed lighting amendment opens Track and Flood branches")
	check(not bool(systems.electrical_snapshot.poweredControls.get("p4_dsky_prog_display", true)), "LGC/DSKY branch deenergization removes display power")
	for id: String in systems.readouts:
		if id.begins_with("p4_dsky_"): check(str(systems.readouts[id].text).is_empty(), "Unpowered actual DSKY readout is blank: " + id)
	check(cabin.mode_label.text.contains("LGC OFF") and systems.agc_snapshot.cpuPowerState == "off", "Final source action halts the stepped LGC")
	check(systems.agc_snapshot.lamps.values().all(func(lit): return not lit), "Unpowered DSKY lamps go out")
	check(cabin.state_store.position_name("p14_power_temp_mon") == "BAT 2", "Later replay actions preserve an unrelated manual control override")
	check(dc_current() > 0.0 and dc_current() < initial_current, "Final partial known demand is reduced and remains powered")
	var stopped_cycles := int(systems.agc_snapshot.nativeCycles)
	var stopped_carry := int(systems.agc_snapshot.quarterNanosecondRemainder)
	var keys_before := int(systems.agc_snapshot.keyPressesSent)
	cabin._operate("p4_dsky_verb", 1)
	cabin._release_button()
	check(clock.advance_ticks(37) and int(clock.completed_ns) == start_completed + 370000000, "Shared clock continues while the LGC is off")
	near(float(systems.electrical_snapshot.simulationTimeSeconds), 0.37, "Electrical time continues after LGC shutdown")
	check(float(systems.powerdown_snapshot.cabinTemperatureF) < 68.0, "Cabin cools when simulation time advances in low power")
	check(stopped_cycles > 0 and int(systems.agc_snapshot.nativeCycles) == stopped_cycles and int(systems.agc_snapshot.quarterNanosecondRemainder) == stopped_carry, "Neither machine cycles nor fractional carry advance while off")
	check(int(systems.agc_snapshot.keyPressesSent) == keys_before, "Physical keys entered while off do not reach the LGC")
	var completed_save: String = clock.save_json()
	check(operate_to("p11_cb_r04_c19", "PUSHED") and systems.agc_snapshot.cpuPowerState == "starting", "Closing the branch starts an inhibited native restart")
	check(int(systems.agc_snapshot.nativeCycles) == 0 and int(systems.agc_snapshot.startupRemainingNanoseconds) == 250000000, "Power restoration creates a new native epoch with the nominal inhibit")
	check(not bool(systems.agc.call("SetKey", "p4_dsky_verb", true)), "Keys are ignored during startup")
	check(clock.advance_ticks(24) and int(systems.agc_snapshot.nativeCycles) == 0 and int(systems.agc_snapshot.startupRemainingNanoseconds) == 10000000, "No native instructions run before the full inhibit elapses")
	var starting_save: String = clock.save_json()
	check(clock.advance_ticks(1) and int(systems.agc_snapshot.nativeCycles) == 0 and systems.agc_snapshot.cpuPowerState == "operating", "First execution interval begins after 250 ms")
	check(clock.advance_ticks(75) and int(systems.agc_snapshot.nativeCycles) == 64000, "Actual rope resumes at the native rate after startup")
	var restarted_save: String = clock.save_json()
	check(clock.restore_json(starting_save) and clock.save_json() == starting_save, "Checkpoint restores during the startup inhibit")
	check(clock.advance_ticks(76) and clock.save_json() == restarted_save, "Restored startup produces identical native and EPS state")
	var mismatched := unpack_bundle(completed_save)
	var forged: Dictionary = JSON.parse_string(str(mismatched.agc))
	for field: String in ["schemaVersion", "packetsReceived", "keyPressesSent", "quarterNanosecondRemainder", "startupRemainingNanoseconds"]:
		forged[field] = int(forged[field])
	forged.electricalPower = true
	mismatched.agc = JSON.stringify(forged)
	check(not clock.restore_json(pack_bundle(mismatched)) and str(clock.last_error).contains("electrical supply"), "Checkpoint rejects a native power state that disagrees with the saved branch")
	check(clock.save_json() == restarted_save, "Supply mismatch leaves the live session unchanged")
	check(clock.restore_json(completed_save) and clock.save_json() == completed_save and systems.agc_snapshot.cpuPowerState == "off", "Off checkpoint restores canonically without an unintended restart")
	check(clock.restore_json(staged_save), "Intermediate complete checkpoint restores the source replay cursor")
	check(int(systems.powerdown_snapshot.currentIndex) == staged_index and cabin.state_store.position_name("p14_power_temp_mon") == "BAT 2", "Replay cursor and manual control restore together")
	check(clock.save_json() == staged_save, "Intermediate cursor, EPS, cabin controls and native state round-trip canonically")
	near(float(systems.powerdown_snapshot.cabinTemperatureF), 68.0, "Restored checkpoint reinstates its saved temperature")
	follow_callout(events[staged_index])
	check(int(systems.powerdown_snapshot.currentIndex) == staged_index + 1, "Restored cursor resumes the hands-on procedure at its next callout")
	var before_reject: String = clock.save_json()
	for field: String in ["negative", "past_end", "inactive", "fingerprint", "temperature"]:
		var bad := unpack_bundle(before_reject)
		var replay: Dictionary = JSON.parse_string(str(bad.powerDown))
		if field == "negative": replay.currentIndex = -1
		elif field == "past_end": replay.currentIndex = events.size() + 1
		elif field == "inactive": replay.active = false
		elif field == "fingerprint": replay.sequenceSha256 = "0".repeat(64)
		else: replay.cabinTemperatureF = -10
		# Typed JSON integer fields must stay integer when reserialized by GDScript.
		replay.schemaVersion = int(replay.schemaVersion)
		replay.currentIndex = int(replay.currentIndex)
		bad.powerDown = JSON.stringify(replay)
		check(not clock.restore_json(pack_bundle(bad)), "Invalid source replay cursor rejects: " + field)
		check(clock.save_json() == before_reject, "Rejected source replay cursor leaves all live state unchanged: " + field)
	check(systems.apply_preset("minimum_lifeboat_12a"), "Aggregate calibration remains available after guided replay")
	check(not bool(systems.powerdown_snapshot.get("active", true)), "Selecting a preset cancels the replay cursor")
	near(dc_current(), 12.0, "Aggregate calibration does not add the source equipment subtotal")
	key_f12(true)
	check(bool(systems.powerdown_snapshot.get("active", false)) and int(systems.powerdown_snapshot.currentIndex) == 0, "Shift+F12 restarts source review from a fresh equipment trial")
	near(float(systems.powerdown_snapshot.cabinTemperatureF), 68.0, "Restart resets the training temperature")
	check(bool(systems.electrical.call("SetCmExportDemand", "LMP_DC", 7.0)), "Actual source-load bridge accepts explicit CM input demand")
	check(clock.advance_ticks(100), "Native CPU and EPS advance together through one second of explicit CM export")
	var accounting: Dictionary = systems.electrical_snapshot.get("accounting", {})
	var cm: Dictionary = accounting.get("cmExport", {})
	near(float(cm.get("consumedAh", -1.0)), 7.0 / 3600.0, "One shared second exports exactly7A at the LM charge boundary")
	near(float(cm.get("consumedWh", -1.0)), 210.0 / 3600.0, "One shared second exports exactly210W at the30V LM source")
	near(float(accounting.get("cmExportDemandA", -1.0)), 7.0, "Actual bridge preserves requested export demand independently of its integral")
	var partition_ah := 0.0
	var partition_wh := 0.0
	var partition_current := 0.0
	var partition_power := 0.0
	for category: String in ["lmEquipment", "cmExport", "syntheticFault", "unclassifiedAggregate"]:
		var part: Dictionary = accounting.get(category, {})
		partition_ah += float(part.get("consumedAh", -1000.0))
		partition_wh += float(part.get("consumedWh", -1000.0))
		partition_current += float(part.get("currentA", -1000.0))
		partition_power += float(part.get("powerW", -1000.0))
	var source: Dictionary = accounting.get("source", {})
	near(partition_ah, float(systems.electrical_snapshot.consumedAh), "Actual scene attributes every consumed source Ah once")
	near(partition_wh, float(systems.electrical_snapshot.consumedWh), "Actual scene attributes every consumed source Wh once")
	near(partition_current, float(source.get("currentA", -1.0)), "Actual scene current categories sum to source demand")
	near(partition_power, float(source.get("powerW", -1.0)), "Actual scene power categories sum to source power")
	var export_save: String = clock.save_json()
	check(not export_save.is_empty(), "Complete native checkpoint includes CM demand and consumed ledger")
	check(bool(systems.electrical.call("SetCmExportDemand", "LMP_DC", 0.0)) and clock.advance_ticks(25), "Intermittent export can stop while both subsystems continue")
	near(float(systems.electrical_snapshot.accounting.cmExport.consumedAh), 7.0 / 3600.0, "Stopping export preserves charge already delivered")
	check(clock.restore_json(export_save) and clock.save_json() == export_save, "Native CPU, replay cursor, export demand and ledger restore canonically together")
	near(float(systems.electrical_snapshot.accounting.cmExportDemandA), 7.0, "Complete restore reinstates the explicit CM input demand")
	check(systems.apply_preset("minimum_lifeboat_12a"), "Aggregate calibration clears the explicit export trial")
	var aggregate_save: String = clock.save_json()
	check(not bool(systems.electrical.call("SetCmExportDemand", "LMP_DC", 7.0)), "Actual bridge rejects ambiguous aggregate-plus-export demand")
	check(clock.save_json() == aggregate_save, "Rejected aggregate-plus-export request leaves the entire live session unchanged")
	check(systems.apply_preset("electrical_checkout") and clock.advance_ticks(25), "Powered checkout is ready to test a breaker trip")
	systems.run_lamp_test()
	check(systems.demo_running and cabin.held_button_ids.has("lamp_test"), "Lamp test begins with a held demonstration key")
	check(bool(systems.electrical.call("InjectBranchFault", "p11_cb_r04_c19", 8.0)) and clock.advance_ticks(25, false), "EPS trips the branch on the shared clock without display publication")
	check(systems.agc_snapshot.cpuPowerState == "off" and not systems.demo_running and not cabin.held_button_ids.has("lamp_test"), "Breaker loss halts CPU and releases the demonstration key immediately")
	check(systems.apply_preset("cold_dark") and operate_to("p11_cb_r04_c19", "PUSHED") and systems.agc_snapshot.cpuPowerState == "off", "Closed breaker cannot start the LGC while its supply bus is dark")
	var report := {"schemaVersion": 1, "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": Array(failures),
		"kind": "Hands-on desktop power-down, cooling and complete native checkpoint integration", "sourceEvents": events.size(), "mappedActions": mapped_actions,
		"headsetTested": false, "independentFlightValidationPassed": false, "completeFlownConfiguration": false, "lgcPowerCycleModeled": true,
		"separateCmExportCheckpoint": true,
		"sequenceSha256": FileAccess.get_sha256(sequence_path), "electricalSha256": FileAccess.get_sha256(cabin.repository_path("reference/electrical.json")),
		"inventorySha256": FileAccess.get_sha256(cabin.repository_path("reference/controls.json"))}
	var file := FileAccess.open(cabin.repository_path("reference/powerdown-integration.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Power-down scene integration: %s; %d checks; %d failures." % [report.result, checks, failures.size()])
	cabin.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
