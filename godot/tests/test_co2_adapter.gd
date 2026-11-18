extends SceneTree
## Exercise the desktop chapter with the live cabin and EPS/AGC clock.

var failures := PackedStringArray()
var checks := 0
var cabin: Node3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func key(code: Key, shift := false, pressed := true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	cabin._unhandled_input(event)

func operate_to(id: String, label: String) -> bool:
	var positions: Array = cabin.state_store.definitions[id].positions
	var target := positions.find(label)
	for attempt in range(positions.size() + 1):
		var current: int = cabin.state_store.states[id]
		if current == target:
			return true
		cabin._operate(id, 1 if target > current else -1, "mouse", true)
	return false

func click_expected(id: String) -> void:
	await physics_frame
	await process_frame
	var co2: Node = cabin.systems.co2
	check(co2.target() == id, "Expected target: " + id)
	check(co2.locate(), "F locates the target: " + id + " at " + str(co2.stage))
	var eye: Vector3 = cabin.desktop_camera.global_position
	var direction: Vector3 = -cabin.desktop_camera.global_basis.z
	var picked: String = cabin._pick(eye, direction)
	check(picked == id, "Camera center can pick " + id + " (hit " + picked + ")")
	# Keep exercising the state machine if a sight-line assertion fails.
	cabin.focused_id = id
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	cabin._unhandled_input(click)

func capture(suffix: String) -> void:
	if not "--co2-capture" in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = cabin.repository_path("output/aquarius-co2-" + suffix + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Captured " + path)

func capture_correction(suffix: String) -> void:
	if not "--mcc5-capture" in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = cabin.repository_path("tmp/mcc5-" + suffix + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Captured " + path)

func pulse(clock: Node, control: Key, ticks: int) -> void:
	key(control)
	check(clock.advance_ticks(ticks), "Shared clock applied held steering input")
	key(control, false, false)
	check(clock.advance_ticks(105), "Steering released to neutral")

func configure_correction(correction: Node, settings: Dictionary) -> void:
	for index in range(settings.size()):
		var id: String = correction.target()
		if id.is_empty():
			return
		check(settings.has(id), "Checklist identifies a real setup control: " + id)
		if not settings.has(id):
			return
		key(KEY_F)
		var eye: Vector3 = cabin.desktop_camera.global_position
		check(cabin._pick(eye, -cabin.desktop_camera.global_basis.z) == id, "F brings the marked control into reach: " + id)
		check(operate_to(id, settings[id]), "Pilot can set " + id)

func run_correction(systems: Node, clock: Node) -> void:
	var mcc: Node = systems.correction
	key(KEY_F12)
	check(mcc.phase == mcc.Phase.PREP and systems.co2.airflow(), "F12 carries the two running adapters into the cold MCC-5 cabin")
	if mcc.phase != mcc.Phase.PREP:
		return
	check(systems.agc_snapshot.cpuPowerState == "off", "Primary computer stays off")
	check(mcc.radio.cue_get == "100:16:16" and mcc.radio.playing, "Duke's original prep read-up is on the radio")
	key(KEY_M)
	check(mcc.radio.muted and not mcc.radio.playing and systems.powerdown_text.text.contains("100:16:16"), "Mute keeps MCC-5 captions")
	key(KEY_M)
	key(KEY_R)
	check(mcc.radio.playing, "R repeats the MCC-5 call")
	key(KEY_ENTER)
	check(mcc.phase == mcc.Phase.PREP, "Missing setup positions block alignment")
	configure_correction(mcc, mcc.PREP)
	key(KEY_ENTER)
	check(mcc.phase == mcc.Phase.EARTH and mcc.view == mcc.View.COAS and mcc.radio.cue_get == "103:51:07", "Brand's original Earth call opens the real sight")
	await capture_correction("acquire")
	key(KEY_ENTER)
	check(mcc.phase == mcc.Phase.EARTH, "Pointing elsewhere cannot satisfy the optical alignment")
	var before: Vector3 = mcc.globe.global_position
	pulse(clock, KEY_RIGHT, 165)
	check(not mcc.globe.global_position.is_equal_approx(before), "Actual attitude keys move Earth in the fixed COAS")
	pulse(clock, KEY_Z, 175)
	await capture_correction("earth")
	key(KEY_ENTER)
	check(mcc.phase == mcc.Phase.SUN and mcc.radio.cue_get == "103:43:43", "Earth alignment opens Brand's original Sun call")
	if mcc.phase != mcc.Phase.SUN:
		return
	configure_correction(mcc, {"aot_azimuth": "F", "aot_reticle": "MIN"})
	key(KEY_F)
	check(mcc.view == mcc.View.AOT and mcc.solar_sight.detent_set, "Detent 2 displays the forward AOT field")
	pulse(clock, KEY_DOWN, 125)
	await capture_correction("sun")
	key(KEY_ENTER)
	check(mcc.phase == mcc.Phase.PAD and mcc.radio.cue_get == "104:33:43", "Sun check leads into Lousma's original PAD")
	key(KEY_ENTER)
	check(mcc.phase == mcc.Phase.GO and mcc.radio.cue_get == "105:12:04", "Lousma clears the aligned crew")
	key(KEY_ENTER)
	check(mcc.phase == mcc.Phase.ARM and mcc.radio.cue_get == "105:17:01", "Final checklist uses Lousma's recorded gimbal call")
	configure_correction(mcc, mcc.ARM)
	key(KEY_ENTER)
	check(mcc.phase == mcc.Phase.ULLAGE, "Cockpit configuration permits manual ullage")
	if mcc.phase != mcc.Phase.ULLAGE:
		return
	key(KEY_ENTER)
	check(mcc.phase == mcc.Phase.ULLAGE and cabin.state_store.position_name("p5_start") == "RELEASED", "Premature START cannot latch or ignite")
	pulse(clock, KEY_SPACE, 340)
	check(is_zero_approx(mcc.ullage_time), "Releasing +X early resets ullage")
	key(KEY_SPACE)
	check(clock.advance_ticks(1000) and is_equal_approx(mcc.ullage_time, 10.0), "Four jets settle fuel for ten shared-clock seconds")
	key(KEY_ENTER)
	check(mcc.phase == mcc.Phase.BURN and cabin.state_store.position_name("p5_start") == "PRESSED", "ENTER presses the physical START and ignites the DPS")
	key(KEY_SPACE, false, false)
	check(clock.advance_ticks(600) and is_equal_approx(mcc.burn_time, 6.0), "Burn continues on the shared clock under hand control")
	var midburn: String = clock.save_json()
	var roll_before: float = mcc.attitude.z
	pulse(clock, KEY_X, 30)
	check(mcc.attitude.z < roll_before, "Manual TTCA roll input counteracts the modeled DPS drift")
	key(KEY_BACKSPACE)
	check(mcc.phase == mcc.Phase.RETRY, "Early cutoff is recoverable and cannot count as a successful burn")
	check(clock.restore_json(midburn) and mcc.phase == mcc.Phase.BURN and is_equal_approx(mcc.burn_time, 6.0), "Checkpoint restores a running burn at its original elapsed time")
	pulse(clock, KEY_X, 30)
	check(clock.advance_ticks(665) and is_equal_approx(mcc.burn_time, 14.0), "Pilot reaches the 14-second cutoff time")
	await capture_correction("burn")
	key(KEY_BACKSPACE)
	check(mcc.phase == mcc.Phase.TRIM and mcc.radio.cue_get == "105:19:05", "Physical engine STOP cuts thrust and plays Lousma's trim call")
	check(is_equal_approx(snappedf(mcc.delta_v.z, 0.1), 7.4), "A correctly timed burn reads about 7.4 ft/s on 470")
	pulse(clock, KEY_SPACE, 88)
	check(mcc.phase == mcc.Phase.COMPLETE and mcc.radio.cue_get == "105:19:46", "Manual plus-X trim reaches 7.6 ft/s and plays the original confirmation")
	check(systems.readouts["p6_deda_data"].text == "+7.6" and systems.readouts["p1_event_timer"].text == "00:14", "The powered cabin instruments show the trim and cutoff")
	var result: String = clock.save_json()
	check(systems.apply_preset("electrical_checkout") and not mcc.active(), "Leaving MCC-5 restores the inspection exterior and clears its radio")
	check(clock.restore_json(result) and mcc.phase == mcc.Phase.COMPLETE and clock.save_json() == result, "Completed maneuver round-trips without losing the adapters")
	key(KEY_R)
	check(mcc.radio.playing and mcc.radio.cue_get == "105:19:46", "Archived result can be repeated after a restore")

func capture_odyssey(suffix: String) -> void:
	if not "--odyssey-capture" in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = cabin.repository_path("tmp/odyssey-" + suffix + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Captured " + path)

func run_odyssey(systems: Node, clock: Node) -> void:
	var odyssey: Node = systems.odyssey
	key(KEY_F12)
	check(odyssey.active() and systems.correction.phase == systems.correction.Phase.COMPLETE, "F12 opens Odyssey from the completed burn")
	if not odyssey.active():
		return
	check(odyssey.radio.cue_get == "138:52:35" and odyssey.radio.playing, "Kerwin's original Main A load-shed call plays on entering Odyssey")
	check(odyssey.from_lm and odyssey.power_a and odyssey.power_b, "Pre-entry Main A uses battery C while the LM powers Main B")
	check(float(systems.electrical_snapshot.accounting.cmExportDemandA) > 0, "The existing LM EPS accounts for the Odyssey export load")
	key(KEY_M)
	check(not odyssey.radio.playing and odyssey.station.call_label.text.contains("138:52:35"), "Muting Odyssey keeps the caption")
	key(KEY_M)
	key(KEY_R)
	check(odyssey.radio.playing, "R repeats Odyssey's transmission")
	await capture_odyssey("startup")
	var initial_current: float = odyssey.total_current()
	var tested_transfer := false
	var tested_overload := false
	for index in range(odyssey.steps.size()):
		var step: Dictionary = odyssey.current_step()
		check(odyssey.stage == index, "Odyssey verifies each separate action")
		if odyssey.stage != index:
			return
		var id: String = step.id
		var get: String = step["get"]
		if not get.is_empty():
			check(odyssey.radio.cue_get == get and odyssey.radio.stream != null, "Real transmission follows checklist action " + get)
		if id == "dsky":
			if step.desired == "PRO":
				await capture_odyssey("dsky")
			var dsky_button: Button = odyssey.station.dsky_keys[step.desired]
			dsky_button.pressed.emit()
		elif id.is_empty():
			if index == odyssey.steps.size() - 1:
				check(odyssey.peak <= 20.0, "The checklist can be flown without exceeding the 20 A ceiling")
				var normal_load: float = odyssey.total_current()
				odyssey.operate("amp")
				key(KEY_F12)
				tested_overload = not odyssey.within_budget() and odyssey.stage == index and odyssey.total_current() > normal_load
				check(tested_overload, "High amplifier power exceeds the current limit and blocks final verification")
				odyssey.operate("amp", -1)
				check(clock.advance_ticks(230) and odyssey.within_budget(), "Selecting low power recovers within the budget")
			key(KEY_F12)
		else:
			var control: Button = odyssey.station.switches[id]
			for attempt in range(4):
				if odyssey.positions[id] == step.desired:
					break
				control.pressed.emit()
			if odyssey.stage == index:
				key(KEY_F12)
		check(clock.advance_ticks(225), "Shared clock settles Odyssey's startup loads")
		if id == "scs_logic":
			check(odyssey.total_current() < initial_current, "Both load-shed controls reduce actual Main A demand")
		if id == "lm_power_2":
			tested_transfer = not odyssey.from_lm and not odyssey.power_b and odyssey.power_a and odyssey.connected.computer_standby == 1
			check(tested_transfer, "Removing the umbilical leaves the CMC on its protected Main A feed")
			check(is_zero_approx(float(systems.electrical_snapshot.accounting.cmExportDemandA)), "Removing the LM feed stops its EPS export load")
			var transfer: String = clock.save_json()
			check(clock.restore_json(transfer) and clock.save_json() == transfer and not odyssey.power_b, "The isolated Main B checkpoint restores exactly")
		if id == "main_b_bat_b":
			check(odyssey.power_b and not odyssey.from_lm and odyssey.voltage_b >= 24.0, "Closing the battery tie energizes Main B from Odyssey")
	check(tested_transfer and tested_overload and odyssey.complete(), "Handoff, load recovery and all switch positions end with Odyssey online")
	check(odyssey.computer_mode == 3 and odyssey.total_current() < 20.0 and odyssey.voltage_a >= 24.0 and odyssey.voltage_b >= 24.0,
		"CMC P00, both bus voltages and the current limit are satisfied")
	await capture_odyssey("online")
	var snapshot: String = clock.save_json()
	odyssey.operate("main_b_bat_b")
	odyssey.operate("flood")
	check(odyssey.total_current() < 20.0 and odyssey.voltage_a < 24.0 and not odyssey.within_budget(),
		"The recorded 24 V floor still blocks a concentrated Main A load below 20 A")
	check(clock.restore_json(snapshot) and odyssey.complete(), "Restoring both bus feeds removes the voltage sag")
	check(systems.apply_preset("electrical_checkout") and not odyssey.active(), "Leaving the chapter closes the Odyssey station")
	check(clock.restore_json(snapshot) and clock.save_json() == snapshot and odyssey.complete(), "Completed Odyssey and its battery use restore")

func _run() -> void:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	var systems: Node = cabin.systems
	var clock: Node = systems.session_clock
	var co2: Node = systems.co2
	check(clock != null and co2 != null, "Desktop clock and CO₂ scenario are available")
	if clock == null or co2 == null:
		quit(1)
		return
	key(KEY_F12)
	key(KEY_F10)
	check(co2.stage == -1 and systems.powerdown_snapshot.currentIndex == 0, "F10 preserves an unfinished power-down")
	key(KEY_F10, true)
	check(co2.stage == 0 and systems.powerdown_snapshot.currentIndex == systems.powerdown_snapshot.eventCount, "F10 cold start prepares the completed power-down")
	if co2.stage < 0:
		quit(1)
		return
	check(systems.agc_snapshot.cpuPowerState == "off" and systems.powerdown_snapshot.cabinTemperatureF <= 54.0, "Cabin starts cold with the LGC off")
	check(not co2.airflow() and co2.gauge_text() == "4.5", "The live panel starts with the scenario baseline and no adapter flow")
	check(systems.powerdown_text.text.contains("090:09:17"), "The first Kerwin callout is visible")
	check(co2.radio.cue_get == "090:09:17" and co2.radio.stream != null and co2.radio.playing, "Cold start plays the archived supplies callout")
	key(KEY_M)
	check(co2.radio.muted and not co2.radio.playing and systems.powerdown_text.text.contains("090:09:17"), "Radio mute stops the transmission and keeps the caption")
	key(KEY_M)
	key(KEY_R)
	check(co2.radio.playing and co2.radio.cue_get == "090:09:17", "R repeats the current historical transmission")
	await capture("start")
	var start_save: String = clock.save_json()
	co2.click(str(co2.steps[0].target))
	check(co2.stage == 0, "Destination-first click cannot complete work")
	for index in range(co2.install_count):
		var step: Dictionary = co2.steps[index]
		check(co2.stage == index and not co2.airflow(), "Installation is required before filtration: " + str(step.id))
		if step.has("position"):
			await physics_frame
			await process_frame
			check(co2.locate(), "F can reach ECS control: " + str(step.target))
			check(operate_to(step.target, step.position), "Player can set ECS control: " + str(step.target))
		else:
			await click_expected(step.item)
			await click_expected(step.target)
		if co2.stage != index + 1:
			check(false, "Action did not advance: " + str(step.id))
			break
		if co2.stage < co2.install_count and co2.radio.clips.has(co2.steps[co2.stage]["get"]):
			check(co2.radio.cue_get == co2.steps[co2.stage]["get"] and co2.radio.stream != null, "Historical cue follows the current action")
		if step.id == "lmp_hose_seal":
			await capture("assembly")
			var mid: String = clock.save_json()
			check(clock.restore_json(start_save) and co2.stage == 0, "Restore reconstructs the original props")
			check(clock.restore_json(mid) and clock.save_json() == mid and co2.done("lmp_hose_seal"), "In-progress assembly round-trips")
	var before: float = co2.pressure
	var index_before: float = co2.gauge.position.z
	check(co2.stage == co2.install_count and co2.airflow(), "Two installed adapters and the real ECS positions enable airflow")
	check(clock.advance_ticks(650) and co2.pressure < before - 1.0 and co2.pressure > 0.2, "Panel reading falls over shared-clock time")
	check(not co2.result_announced and co2.radio.cue_get != "094:33:21", "The result report waits while the gauge is above 0.2")
	var after: float = co2.pressure
	check(operate_to("p11_cb_r04_c05", "PULLED") and clock.advance_ticks(100) and co2.pressure > after, "Loss of the running suit fan interrupts removal")
	check(operate_to("p11_cb_r04_c05", "PUSHED") and co2.airflow(), "Restoring fan power resumes removal")
	check(operate_to("p16_cb_r03_c18", "PULLED") and co2.gauge_text() == "" and co2.airflow(), "Sensor loss blanks the gauge independently of airflow")
	check(clock.advance_ticks(3600) and co2.pressure < 0.25 and not co2.result_announced, "Kerwin waits while the gauge is blank even after CO₂ reaches 0.2")
	check(operate_to("p16_cb_r03_c18", "PUSHED") and co2.gauge_text() == "0.2", "Restoring sensor power displays the historical Houston reading")
	check(co2.gauge.visible and co2.gauge.position.z > index_before and systems.powerdown_text.text.contains("094:33:21"), "The in-cabin index moves down its scale and Houston's result is visible")
	check(co2.result_announced and co2.radio.cue_get == "094:33:21" and co2.radio.playing, "Only the live 0.2 reading triggers Kerwin's original report")
	co2.radio.stop()
	check(clock.advance_ticks(50) and not co2.radio.playing, "A stable reading does not replay the result")
	key(KEY_R)
	check(co2.radio.playing and co2.radio.cue_get == "094:33:21", "R repeats the historical result after success")
	check(co2.locate(), "F locates the result on panel 2")
	cabin.status_time = 0.0
	await capture("result")
	var completed: String = clock.save_json()
	check(systems.apply_preset("electrical_checkout") and co2.stage < 0 and not co2.props.visible, "Leaving the chapter removes its supplies and gauge")
	check(clock.restore_json(completed) and clock.save_json() == completed and co2.airflow(), "Installed state, gas reading and EPS restore together")
	check(co2.result_announced and co2.radio.cue_get == "094:33:21" and not co2.radio.playing, "Restored result can be repeated without an automatic duplicate call")
	key(KEY_F12, true)
	for index in range(int(systems.powerdown_snapshot.eventCount)):
		systems.electrical.call("NextPowerDownEvent")
	check(operate_to("p14_power_temp_mon", "BAT 2"), "Set an unrelated cockpit position for the handoff")
	key(KEY_F12)
	check(co2.stage == 0 and cabin.state_store.position_name("p14_power_temp_mon") == "BAT 2", "F12 handoff preserves completed power-down state")
	check(clock.restore_json(completed), "Return to the finished adapter for the flight test")
	await run_correction(systems, clock)
	await run_odyssey(systems, clock)
	print("Mission desktop integration: %s; %d checks; %d failures." % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
