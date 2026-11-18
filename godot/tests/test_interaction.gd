extends SceneTree

const StateStore = preload("res://scripts/control_state.gd")
var failures := PackedStringArray()
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		if failures.size() <= 10:
			push_error("FAIL: " + message)

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	await process_frame
	check(scene.load_errors.is_empty(), "Cabin and inventory load without errors: %s" % str(scene.load_errors))
	var store = scene.state_store
	var ids: Array = store.definitions.keys()
	check(not ids.is_empty(), "Inventory has controls")
	check(scene.bindings.size() == ids.size(), "All inventory IDs bind to scene nodes")
	var interactive_count := 0
	var read_only_count := 0
	var actuator_count := 0
	var max_reach := 0.0
	for id: String in ids:
		if not scene.bindings.has(id):
			continue
		var binding = scene.bindings[id]
		var position: Vector3 = binding.target_global_position()
		check(absf(position.x) < 2.0 and position.y >= -0.05 and position.y < 2.6 and absf(position.z) < 2.0, "Control %s lies inside metre-scale cabin bounds: %s" % [id, position])
		max_reach = maxf(max_reach, position.distance_to(Vector3(0, 1.62, 0.70)))
		var surface_normal: Vector3 = binding.target_surface_normal()
		# The target center sits2cm above its exported surface, so16cm from
		# that center preserves the original18cm inspection-ray origin.
		var picked: String = scene._pick(position + surface_normal * 0.16, -surface_normal)
		check(picked == id, "Pointer ray reaches control %s (hit %s)" % [id, picked])
		var initial: int = store.states[id]
		var count: int = store.definitions[id].positions.size()
		var prerequisites: Dictionary = {}
		var mechanism: Dictionary = store.definitions[id].get("mechanism", {})
		var guard_id := str(mechanism.get("guardId", ""))
		if not guard_id.is_empty():
			prerequisites[guard_id] = store.states[guard_id]
			store.set_position(guard_id, store.definitions[guard_id].positions.find("OPEN"))
		var required: Dictionary = mechanism.get("requiredControlPosition", {})
		if not required.is_empty():
			var required_id := str(required.id)
			prerequisites[required_id] = store.states[required_id]
			store.set_position(required_id, store.definitions[required_id].positions.find(str(required.position)))
		for rule: Dictionary in store.definitions[id].get("motionRequires", mechanism.get("motionRequires", [])):
			var applies: Array = rule.get("appliesToPositions", [])
			var next_label := str(store.definitions[id].positions[posmod(initial + 1, count)])
			if not applies.is_empty() and not next_label in applies:
				continue
			var required_id := str(rule.get("controlId", ""))
			var allowed: Array = rule.get("allowedPositions", [])
			if store.definitions.has(required_id) and not allowed.is_empty():
				prerequisites[required_id] = store.states[required_id]
				store.set_position(required_id, store.definitions[required_id].positions.find(str(allowed[0])))
		check(not store.set_position(id, -1) and not store.set_position(id, count), "Out-of-range states rejected for %s" % id)
		if store.is_interactive(id):
			interactive_count += 1
			if binding.actuator != null:
				actuator_count += 1
			check(binding.actuator != null, "Moving actuator exists for %s" % id)
			var before: Transform3D = binding.actuator.transform if binding.actuator != null else Transform3D.IDENTITY
			if binding.actuator != null:
				check(before.is_equal_approx(binding.initial_actuator_transform), "Default pose matches exported cabin: %s" % id)
			if store.is_lever_locked(id):
				check(not store.actuate(id, 1), "Lever lock blocks actuation until unlocked: %s" % id)
			check(store.actuate(id, 1, true), "Control can be operated with its prerequisites: %s" % id)
			scene._apply_position(id)
			if binding.actuator != null:
				check(not binding.actuator.transform.is_equal_approx(before), "Operating %s changes its actuator pose" % id)
			if str(store.definitions[id].get("type", "")) == "pushbutton" and store.is_momentary(id):
				check(store.states[id] == count - 1, "Pushbutton presses to active state: %s" % id)
				check(store.release(id), "Pushbutton releases: %s" % id)
				check(store.states[id] == initial, "Pushbutton returns to default: %s" % id)
			else:
				check(store.states[id] == posmod(initial + 1, count), "Position advances correctly: %s" % id)
				check(store.actuate(id, -1, true) and store.states[id] == initial, "Position reverses correctly: %s" % id)
			var previous_pose := Transform3D.IDENTITY
			for index in range(count):
				check(store.set_position(id, index), "Declared position %d applies: %s" % [index, id])
				scene._apply_position(id)
				check(store.position_name(id) == str(store.definitions[id].positions[index]), "Declared position %d has correct label: %s" % [index, id])
				if binding.actuator != null:
					if index > 0:
						check(not previous_pose.is_equal_approx(binding.actuator.transform), "Adjacent declared positions have distinct poses: %s / %d" % [id, index])
					previous_pose = binding.actuator.transform
				if store.is_momentary(id):
					store.actuate(id, 1, true)
					check(store.release(id) and store.states[id] == initial, "Momentary control returns to rest: %s" % id)
			if str(store.definitions[id].get("type", "")) == "breaker" and binding.actuator != null:
				var pulled: int = store.definitions[id].positions.find("PULLED")
				var pushed: int = store.definitions[id].positions.find("PUSHED")
				store.set_position(id, pulled)
				scene._apply_position(id)
				var pulled_y: float = binding.actuator.position.y
				store.set_position(id, pushed)
				scene._apply_position(id)
				check(binding.actuator.position.y < pulled_y, "PUSHED breaker travels inward: %s" % id)
		else:
			read_only_count += 1
			check(not store.actuate(id, 1) and store.states[id] == initial, "Read-only instrument cannot be actuated: %s" % id)
		store.set_position(id, initial)
		scene._apply_position(id)
		for prerequisite_id: String in prerequisites:
			store.set_position(prerequisite_id, int(prerequisites[prerequisite_id]))
	# Safety mechanisms and continuous axes are exercised through the common path.
	store.reset()
	check(not store.actuate("p8_stage", 1, true), "STAGE guard blocks FIRE while closed")
	check(store.actuate("p8_stage_guard", 1), "STAGE guard opens independently")
	check(store.actuate("p8_stage", 1, true), "Unlocked STAGE can command FIRE with guard open")
	check(store.release("p8_stage") and store.position_name("p8_stage") == "SAFE", "STAGE spring returns SAFE")
	check(not store.actuate("hatch_forward_door", 1), "Latched hatch cannot swing open")
	check(store.actuate("hatch_forward_latch", 1) and store.actuate("hatch_forward_door", 1), "Unlatched hatch can open")
	store.reset()
	check(store.actuate("p1_abort", 1) and not store.release("p1_abort") and store.position_name("p1_abort") == "PRESSED", "ABORT push-push latch remains set on release")
	check(store.actuate("p1_abort", 1) and store.position_name("p1_abort") == "RELEASED", "Second ABORT push resets latch")
	for axis_id: String in store.axis_values:
		check(store.set_axis(axis_id, 0.42) and is_equal_approx(store.axis_value(axis_id), 0.42), "Axis accepts continuous normalized input: %s" % axis_id)
		check(not store.set_axis(axis_id, NAN), "Axis rejects non-finite input: %s" % axis_id)
		if store.is_momentary(axis_id):
			check(store.release(axis_id) and is_zero_approx(store.axis_value(axis_id)), "Spring axis returns center: %s" % axis_id)
	store.reset()
	check(not store.actuate("__unknown_control__", 1), "Unknown controls cannot create state")
	# Save a non-default pattern, mutate it, then restore from disk.
	for id: String in ids:
		store.set_position(id, store.definitions[id].positions.size() - 1)
	var expected: Dictionary = store.states.duplicate()
	for id: String in ids:
		if store.is_momentary(id):
			var definition: Dictionary = store.definitions[id]
			expected[id] = definition.positions.find(str(definition.get("default", definition.positions[0])))
	var save_path: String = scene.argument_value("--test-save-path", "user://interaction-test-state.json")
	check(store.save_file(save_path) == OK, "State file saves")
	store.reset()
	check(store.load_file(save_path).is_empty(), "State file reloads")
	check(store.states == expected, "Latched positions round-trip; momentary controls restore released")
	var state_before_bad_save: Dictionary = store.states.duplicate()
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string('{"schemaVersion":1,"states":{"__unknown_control__":9999}}')
	file.close()
	check(not store.load_file(save_path).is_empty(), "Unknown ID in state file is rejected")
	check(store.states == state_before_bad_save, "Rejected state file leaves all states unchanged")
	file = FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string("{ malformed json")
	file.close()
	check(not store.load_file(save_path).is_empty(), "Malformed JSON state rejected")
	check(store.states == state_before_bad_save, "Malformed state leaves all positions unchanged")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var report := {
		"schemaVersion": 1,
		"engineVersion": Engine.get_version_info().string,
		"result": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks,
		"failures": Array(failures),
		"inventoryEntries": ids.size(),
		"boundNodes": scene.bindings.size(),
		"interactiveControls": interactive_count,
		"readOnlyInstruments": read_only_count,
		"movingActuators": actuator_count,
		"maximumDistanceFromDesktopStartM": max_reach,
		"coverageDenominator": "Current declared inventory scope only; not the complete spacecraft.",
		"headsetTested": false,
		"systemsSimulated": false
	}
	var report_path: String = scene.argument_value("--report-path")
	if not report_path.is_empty():
		var report_file := FileAccess.open(report_path, FileAccess.WRITE)
		if report_file != null:
			report_file.store_string(JSON.stringify(report, "\t"))
			report_file.close()
		else:
			check(false, "Could not write report: %s" % report_path)
	report.result = "PASS" if failures.is_empty() else "FAIL"
	print("Aquarius checks: %s; %d checks; %d inventory entries; %d bound nodes; %d/%d moving actuators; %d failures." % [report.result, checks, ids.size(), scene.bindings.size(), actuator_count, interactive_count, failures.size()])
	if failures.size() > 10:
		print("Remaining failures are in the coverage JSON report.")
	quit(0 if failures.is_empty() else 1)
