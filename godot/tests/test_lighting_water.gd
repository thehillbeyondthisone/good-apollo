extends SceneTree
## Real glTF alignment, locator, task gating and power-linked lighting regression.
var cabin: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func set_control(id: String, desired: String) -> void:
	var definition: Dictionary = cabin.state_store.definitions[id]
	var index: int = definition.positions.find(desired)
	check(index >= 0, "Requested state exists: " + id + "/" + desired)
	for attempt in definition.positions.size() + 1:
		var current: int = cabin.state_store.states[id]
		if current == index: return
		cabin._operate(id, 1 if index > current else -1, "lighting-water-test", true)

func locate(id: String) -> void:
	cabin.notebook.refresh()
	check(cabin.notebook.current_page.target == id, "Notebook names the next actual control: " + id)
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	cabin._unhandled_input(key)
	var camera: Camera3D = cabin.desktop_camera
	var target: Vector3 = cabin.bindings[id].target_global_position()
	check(cabin._pick(camera.global_position, camera.global_position.direction_to(target)) == id, "F brings the visible notebook target into usable view: " + id)
	check(camera.global_basis.y.dot(Vector3.UP) > 0.8, "Located water control remains upright: " + id)
	check(cabin.notebook.find_button.visible, "FIND remains available on a control page.")
	for label: Label in cabin.notebook.fields.values():
		check(label.get_line_count() * label.get_line_height() <= float(label.get_meta("page_height")), "Water instruction fits its printed section.")

func check_assembly() -> void:
	var dispenser: Node3D = cabin.bindings.water_dispenser_pose.actuator
	var cap: Node3D = cabin.bindings.water_dispenser_cap.actuator
	var nozzle := dispenser.to_global(Vector3(0, 0.120, 0))
	check(nozzle.distance_to(cap.global_position) < 0.0001, "Fitted cap seats on the actual nozzle, including both actuator offsets.")
	check(cabin.mechanisms.water_hose != null, "Supply hose has moving geometry.")
	if cabin.mechanisms.water_hose != null:
		var vertices: PackedVector3Array = cabin.mechanisms.water_hose.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var center := Vector3.ZERO
		for index in range(vertices.size() - 8, vertices.size()): center += cabin.mechanisms.water_hose.to_global(vertices[index])
		center /= 8.0
		check(center.distance_to(dispenser.global_position) < 0.0001, "Hose end meets the moving dispenser collar.")

func _run() -> void:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	await physics_frame
	check(cabin.load_errors.is_empty(), "Production cabin loads all controls.")
	set_control("ecs_des_h2o", "CLOSE")
	set_control("ecs_asc_h2o", "CLOSE")
	set_control("water_dispenser_cap", "FITTED")
	check_assembly()
	locate("water_dispenser_pose")
	cabin.notebook.confirm()
	check(not cabin.notebook.guidance.water_acknowledged, "Incomplete water checkout cannot be acknowledged.")
	set_control("water_dispenser_pose", "FREE")
	await physics_frame
	check_assembly()
	check(cabin._inspect_checklist_control("water_dispenser_pose"), "Unstowed dispenser body remains selectable without the cap stealing its target.")
	locate("ecs_des_h2o")
	set_control("ecs_des_h2o", "OPEN")
	await physics_frame
	locate("water_dispenser_cap")
	set_control("water_dispenser_cap", "REMOVED")
	await physics_frame
	var dispenser: Node3D = cabin.bindings.water_dispenser_pose.actuator
	var cap: Node3D = cabin.bindings.water_dispenser_cap.actuator
	var offset := cap.global_position - dispenser.to_global(Vector3(0, 0.12, 0))
	check(absf(offset.dot(dispenser.global_basis.y)) < 0.0001 and offset.length() > 0.05, "Removed cap parks beside the nozzle, clear of its water path.")
	locate("water_dispenser_trigger")
	check(cabin.notebook.current_page.action.contains("HOLD"), "Dispensing explicitly teaches the hold gesture.")
	cabin._operate("water_dispenser_trigger", 1, "lighting-water-test")
	cabin.notebook.refresh()
	check(cabin.notebook.guidance.water_observed and not cabin.notebook.confirm_button.visible, "Flow is observed and release is required before completion.")
	cabin._release_button("lighting-water-test")
	cabin.notebook.refresh()
	check(cabin.notebook.confirm_button.visible and cabin.notebook.confirm_button.text == "FINISH WATER CHECK", "Shutoff unlocks the explicitly named completion action.")
	cabin.notebook.confirm()
	check(cabin.notebook.guidance.water_acknowledged and not cabin.systems.powerdown_snapshot.get("active", false), "Acknowledging checkout does not start another procedure.")
	# Verify real EPS controls, not direct light property mutations.
	cabin.systems.apply_preset("electrical_checkout")
	var environment: Environment = cabin.get_node("CabinEnvironment").environment
	var ambient_color := environment.ambient_light_color
	cabin._set_axis("p5_flood_ovhd_fwd", 1.0, "lighting-water-test")
	var bright: float = cabin.forward_floods[0].light_energy
	cabin._set_axis("p5_flood_ovhd_fwd", 0.0, "lighting-water-test")
	check(cabin.forward_floods[0].light_energy > 0 and cabin.forward_floods[0].light_energy < bright, "Live dimmer reduces fixture light.")
	set_control("p3_flood_ovhd_fwd", "OFF")
	check(not cabin.forward_floods[0].visible and not cabin.aft_flood_bounce.visible and not cabin.cabin_bounce.visible, "Flood OFF removes fixtures and both reflected-light contributions.")
	set_control("shade_cdr", "DEPLOYED")
	check(not cabin.window_spill[0].visible and cabin.window_spill[1].visible, "CDR shade removes only its own window spill.")
	set_control("shade_lmp", "DEPLOYED")
	check(not cabin.window_spill[1].visible, "LMP shade closes the other exterior light path.")
	cabin.systems.apply_preset("cold_dark")
	check(environment.ambient_light_energy < 0.03 and environment.ambient_light_color == ambient_color, "Cold darkness preserves neutral light color with only a small visibility floor.")
	check(cabin.forward_shadow_key != null, "Cabin relief has a bounded fixture shadow key.")
	cabin._set_inspection_view(4)
	cabin._update_desktop_shadow_key()
	check(cabin.aft_flood_bounce.shadow_enabled and not cabin.forward_shadow_key.shadow_enabled, "Looking aft transfers the single fixture shadow map.")
	var file := FileAccess.open(cabin.repository_path("output/lighting-water-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "headsetTested": false}, "\t"))
	print("Lighting / water: %d checks, %d failures." % [checks, failures.size()])
	cabin.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
