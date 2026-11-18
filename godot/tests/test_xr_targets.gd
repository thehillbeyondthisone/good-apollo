extends SceneTree
## Spatial broad-phase verification with real cabin target areas and controlled
## near/far boundary fixtures. No OpenXR runtime or rendered window is opened.

const Binding = preload("res://scripts/control_binding.gd")
var checks := 0
var failures := PackedStringArray()
var cabin: Node3D
var session: Node3D
var controller: XRController3D

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("FAIL: " + message)

func aim(position: Vector3, direction: Vector3) -> void:
	controller.global_position = position
	controller.look_at(position + direction, Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.95 else Vector3.UP)

func fixture(id: String, position: Vector3, interactive: bool = true, kind := "toggle", positions := ["OFF", "ON"]) -> Node3D:
	var definition := {"id": id, "type": kind if interactive else "indicator", "interactive": interactive,
		"positions": positions, "default": positions[0]}
	cabin.state_store.definitions[id] = definition
	cabin.state_store.states[id] = 0
	var visual := Node3D.new()
	visual.name = id
	visual.position = position
	cabin.add_child(visual)
	var binding = Binding.new()
	binding.setup(definition, visual)
	cabin.bindings[id] = binding
	return visual

func sample_at(hand: String, position: Vector3, trigger := false, active := true, grip := false) -> String:
	aim(position, Vector3.FORWARD)
	return session._sample_controller(hand, controller.global_position, {
		"active": active, "trigger": trigger, "reverse": grip, "target": session._target(controller),
	}, 0.016)

func check_touch() -> void:
	var id := "p4_dsky_verb"
	var binding = cabin.bindings[id]
	var center: Vector3 = binding.target_global_position()
	var normal: Vector3 = binding.target_surface_normal()
	var away := center + normal * 0.035
	var press := center + normal * 0.004
	var hand := "right_hand"
	check(sample_at(hand, press).is_empty() and not cabin.held_button_ids.has("xr:" + hand), "First tracked frame inside a DSKY key does not activate it")
	check(sample_at(hand, away).is_empty(), "Close DSKY hover shows a target without pressing it")
	check(sample_at(hand, press) == id and cabin.state_store.position_name(id) == "PRESSED", "Front contact presses the real DSKY key through the shared cabin path")
	check(sample_at(hand, center + normal * 0.012) == id and cabin.state_store.position_name(id) == "PRESSED", "Small tip motion does not release the depressed key")
	check(sample_at("left_hand", away).is_empty() and sample_at("left_hand", press) == id, "Each hand tracks its own contact")
	check(sample_at(hand, away, true).is_empty() and cabin.state_store.position_name(id) == "PRESSED", "Withdrawal releases only the withdrawing hand even if its trigger is down")
	check(sample_at("left_hand", press, false, false).is_empty() and cabin.state_store.position_name(id) == "RELEASED", "Tracking loss releases the last contacting hand")
	check(sample_at(hand, away, true).is_empty() and cabin.state_store.position_name(id) == "RELEASED", "A trigger held during withdrawal cannot press again until released")
	check(sample_at("left_hand", press).is_empty() and cabin.state_store.position_name(id) == "RELEASED", "Tracking recovery inside the key does not create a new press")
	sample_at(hand, away)
	sample_at(hand, away, true)
	check(sample_at(hand, press, true).is_empty() and cabin.state_store.position_name(id) == "PRESSED", "Moving into contact during a trigger hold keeps the original trigger operation")
	check(sample_at(hand, press).is_empty() and cabin.state_store.position_name(id) == "RELEASED", "Releasing a trigger inside a key does not transfer the hold to contact")
	sample_at(hand, away)
	sample_at(hand, press)
	session._session_unfocused("software_test")
	check(cabin.state_store.position_name(id) == "RELEASED" and session.touch_contacts.is_empty(), "Session focus loss releases and clears contact")
	check(sample_at(hand, press).is_empty(), "Focus recovery inside the key waits for a fresh front approach")
	sample_at(hand, away)
	session.touch_positions.clear()
	check(sample_at(hand, press).is_empty(), "Cleared approach history cannot convert virtual movement into a press")
	var side: Vector3 = binding.target_collision.global_basis.x.normalized() * (binding.target_shape.radius + 0.002)
	sample_at(hand, away)
	check(sample_at(hand, press + side).is_empty(), "A tip outside the fitted key radius cannot press the key")
	check(sample_at(hand, press).is_empty(), "Sliding sideways across the key at press depth does not actuate it")
	var guarded_id := "fixture_guarded_button"
	var guarded_center: Vector3 = cabin.bindings[guarded_id].target_global_position()
	sample_at(hand, guarded_center + Vector3.UP * 0.035)
	sample_at(hand, guarded_center + Vector3.UP * 0.004)
	check(cabin.state_store.position_name(guarded_id) == "RELEASED", "Contact respects the cabin's closed-guard interlock")
	sample_at(hand, guarded_center + Vector3.UP * 0.035)
	cabin.state_store.set_position("fixture_guard", 1)
	check(sample_at(hand, guarded_center + Vector3.UP * 0.004) == guarded_id and cabin.state_store.position_name(guarded_id) == "PRESSED", "Opening the guard permits a fresh contact press")
	sample_at(hand, guarded_center + Vector3.UP * 0.035)
	var breaker_id := "fixture_touch_breaker"
	var breaker_center: Vector3 = cabin.bindings[breaker_id].target_global_position()
	sample_at(hand, breaker_center + Vector3.UP * 0.035)
	check(sample_at(hand, breaker_center + Vector3.UP * 0.004, false, true, true) == breaker_id and cabin.state_store.position_name(breaker_id) == "PUSHED", "Touch pushes a pulled breaker in even when grip is held")
	sample_at(hand, breaker_center + Vector3.UP * 0.035)
	check(sample_at(hand, breaker_center + Vector3.UP * 0.004).is_empty() and cabin.state_store.position_name(breaker_id) == "PUSHED", "Touch cannot pull out a pushed breaker")

func legacy_target() -> String:
	# A full scan is the reference oracle: the broad phase may prune candidates,
	# but must retain exact moving-center/front-face/occlusion choices.
	var closest := 0.055
	var result := ""
	for id: String in cabin.bindings:
		var binding = cabin.bindings[id]
		var normal: Vector3 = binding.target_surface_normal()
		var target: Vector3 = binding.target_global_position()
		var distance: float = controller.global_position.distance_to(target)
		if distance < closest and normal.dot(controller.global_position - target) >= -0.005 and cabin.state_store.is_interactive(id) and not session._occluded(controller.global_position, target):
			closest = distance
			result = id
	if not result.is_empty(): return result
	result = cabin._pick(controller.global_position, -controller.global_basis.z)
	if not result.is_empty():
		var binding = cabin.bindings[result]
		if binding.target_surface_normal().dot(controller.global_position - binding.target_global_position()) < -0.005: return ""
	return result

func _run() -> void:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	session = load("res://scripts/xr_session.gd").new()
	session.cabin = cabin
	session.router.setup(cabin)
	cabin.add_child(session)
	controller = XRController3D.new()
	controller.show_when_tracked = false
	cabin.add_child(controller)
	var first := fixture("fixture_near_a", Vector3(4, 1, 0), true, "pushbutton", ["RELEASED", "PRESSED"])
	var second := fixture("fixture_near_b", Vector3(4.02, 1, 0))
	var output := fixture("fixture_output", Vector3(4.4, 1, 0), false)
	fixture("fixture_touch_breaker", Vector3(4.6, 1, 0), true, "breaker", ["PULLED", "PUSHED"])
	fixture("fixture_guarded_button", Vector3(4.3, 1, 0.3), true, "pushbutton", ["RELEASED", "PRESSED"])
	fixture("fixture_guard", Vector3(4.36, 1, 0.3), true, "guard", ["CLOSED", "OPEN"])
	cabin.state_store.definitions.fixture_guarded_button.mechanism = {"guardId": "fixture_guard"}
	await physics_frame
	await process_frame
	check(cabin.load_errors.is_empty(), "Full cabin and spatial interaction targets load")
	var target := first.global_position + Vector3.UP * 0.02
	aim(target + Vector3.UP * 0.054, Vector3.FORWARD)
	check(session._target(controller) == "fixture_near_a", "Interactive center inside 55mm selects without a pointing ray")
	var cached: PhysicsShapeQueryParameters3D = session.get_meta("_near_target_query")
	var query_id := cached.get_instance_id()
	var shape_id := cached.shape.get_instance_id()
	check(cached.collision_mask == 8 and cached.collide_with_areas and not cached.collide_with_bodies, "Broad phase queries only existing interaction areas")
	aim(target + Vector3.UP * 0.056, Vector3.FORWARD)
	check(session._target(controller).is_empty(), "Collider overlap cannot select a center outside 55mm")
	aim(target + Vector3.UP * 0.3, Vector3.DOWN)
	check(session._target(controller) == "fixture_near_a", "Unchanged far ray selects the front-facing collider beyond near range")
	aim(first.global_position - Vector3.UP * 0.01, Vector3.FORWARD)
	check(session._target(controller).is_empty(), "Near selection rejects the rear face of a control")
	aim(output.global_position + Vector3.UP * 0.06, Vector3.FORWARD)
	check(session._target(controller).is_empty(), "Near output remains read-only")
	aim(target + Vector3.UP * 0.035 + Vector3.RIGHT * 0.009, Vector3.FORWARD)
	check(session._target(controller) == "fixture_near_a", "Exact center distance selects the closer of overlapping areas")
	aim(target + Vector3.UP * 0.035 + Vector3.RIGHT * 0.011, Vector3.FORWARD)
	check(session._target(controller) == "fixture_near_b", "Nearest choice changes across the equal-distance boundary")
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 16
	blocker.collision_mask = 0
	blocker.position = target + Vector3.UP * 0.020
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.007
	collision.shape = sphere
	blocker.add_child(collision)
	cabin.add_child(blocker)
	await physics_frame
	await process_frame
	aim(target + Vector3.UP * 0.04, Vector3.FORWARD)
	check(session._target(controller) != "fixture_near_a" and session._target(controller) == legacy_target(), "Structural occlusion rejects a blocked near center while retaining other valid targets")
	sample_at("right_hand", target + Vector3.UP * 0.04)
	check(sample_at("right_hand", target + Vector3.UP * 0.004).is_empty() and cabin.state_store.position_name("fixture_near_a") == "RELEASED", "A sampled tip cannot cross a structural blocker to press a control")
	sample_at("right_hand", target, false, false)
	blocker.queue_free()
	await physics_frame
	await process_frame
	var compared := 0
	var maximum_hits := 0
	var ids: Array = cabin.bindings.keys()
	for index in range(ids.size()):
		var id: String = ids[index]
		var binding = cabin.bindings[id]
		var normal: Vector3 = binding.target_surface_normal()
		var center: Vector3 = binding.target_global_position()
		cached.transform = Transform3D(Basis.IDENTITY, center)
		maximum_hits = maxi(maximum_hits, cabin.get_world_3d().direct_space_state.intersect_shape(cached, 128).size())
		if index % 9 != 0: continue
		for separation: float in [0.04, 0.056, -0.035]:
			aim(center + normal * separation, normal)
			check(session._target(controller) == legacy_target(), "Spatial query preserves real cabin selection at %s / %.3fm" % [id, separation])
			compared += 1
	check(maximum_hits < 128, "Every actual target neighborhood remains below the 128-hit query limit")
	var reused: PhysicsShapeQueryParameters3D = session.get_meta("_near_target_query")
	check(reused.get_instance_id() == query_id and reused.shape.get_instance_id() == shape_id, "Both hands reuse the same query and sphere without per-frame allocation")
	check_touch()
	var report := {"result": "PASS" if failures.is_empty() else "FAIL", "checks": checks,
		"failures": Array(failures), "realCabinComparisons": compared, "maximumNearbyAreas": maximum_hits,
		"headsetTested": false, "nearDistanceM": 0.055, "queryHitLimit": 128}
	var file := FileAccess.open(cabin.repository_path("reference/xr-target-tests.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print(JSON.stringify(report))
	session.cabin = null
	cabin.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
