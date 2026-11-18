extends SceneTree
## Run with --self-test --systems-test --manual-clock on a rendered desktop.

var cabin

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var success := await _capture_sequence()
	cabin.queue_free()
	await process_frame
	quit(0 if success else 1)

func _capture_sequence() -> bool:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	if not cabin.load_errors.is_empty() or cabin.systems == null or cabin.systems.session_clock == null:
		push_error("The graphics pass requires the actual cabin and native AGC.")
		return false
	var systems: Node = cabin.systems
	var clock: Node = systems.session_clock
	cabin.hud.hide()
	var camera: Camera3D = cabin.desktop_camera
	if cabin.forward_floods.size() != 2 or not cabin.forward_floods[0].visible or not cabin.forward_floods[1].visible:
		push_error("Checkout requires two illuminated forward floods.")
		return false
	if not clock.advance_ticks(31) or not await _capture("checkout"):
		return false
	systems.run_lamp_test()
	for step in range(160):
		if systems.lamp_frame_seen:
			break
		if not clock.advance_ticks(5):
			return false
		await process_frame
	if not systems.lamp_frame_seen:
		push_error("The running LM131R1 did not reach the all-eights lamp frame.")
		return false
	if not await _capture("lamp-test"):
		return false
	cabin._set_inspection_view(2)
	if not await _capture("dsky-detail"):
		return false
	cabin._set_inspection_view(1)
	if not systems.start_powerdown():
		return false
	for index in range(int(systems.powerdown_snapshot.eventCount)):
		if str(systems.electrical.call("NextPowerDownEvent")).is_empty():
			return false
	if not clock.advance_ticks(6000):
		return false
	if cabin.forward_floods[0].visible or cabin.forward_floods[1].visible or systems.lighting_state.integral > 0.0 or not systems.readouts.p4_dsky_prog_display.text.is_empty():
		push_error("Power-down must extinguish the floods, integral lighting and DSKY.")
		return false
	if not await _capture("power-down"):
		return false
	if not _operate_to("utility_cdr_lamp", "FREE") or not _operate_to("utility_cdr_plug", "CONNECTED") or not _operate_to("util_cdr", "BRIGHT"):
		push_error("The CDR utility light could not be readied.")
		return false
	cabin.mechanisms.refresh()
	if not cabin.mechanisms.derived.utility_cdr_lamp.emitting:
		push_error("The utility light is unpowered in this configuration.")
		return false
	if not await _capture("utility-lamp"):
		return false
	return await _capture_coas(camera)

func _operate_to(id: String, position: String) -> bool:
	var positions: Array = cabin.state_store.definitions[id].positions
	var target := positions.find(position)
	if target < 0:
		return false
	for attempt in range(positions.size()):
		var current: int = cabin.state_store.states[id]
		if current == target:
			return true
		cabin._operate(id, 1 if target > current else -1, "graphics-capture", true)
	return false

func _capture_coas(camera: Camera3D) -> bool:
	if not _operate_to("util_cdr", "OFF") or not _operate_to("coas_cap", "REMOVED") or not _operate_to("p8_coas", "FWD"):
		return false
	cabin._set_axis("coas_illumination", 0.60, "graphics-capture")
	cabin._release_button("graphics-capture")
	cabin.mechanisms.refresh()
	var scope: Node3D = cabin.bindings.coas_mount.actuator
	var axis := scope.global_basis.y.normalized()
	var up := -scope.global_basis.z.normalized()
	var globe := cabin.imported_cabin.find_child("Earth_preview", true, false) as MeshInstance3D
	if globe == null:
		return false
	# The 105-hour alignment is staged for this still using the cabin's existing
	# globe and reticle. The interactive exterior retains its illustrative pose.
	globe.global_position = scope.global_position - axis * 24.0 + up * 0.04
	var phase := globe.material_override as ShaderMaterial
	if phase == null:
		return false
	phase.set_shader_parameter("sun_direction", up)
	camera.global_position = scope.global_position + axis * 0.330
	camera.look_at(scope.global_position, up)
	camera.fov = 10.5
	return await _capture("coas-earth")

func _capture(name: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = cabin.repository_path("output/aquarius-graphics-" + name + ".png")
	var error := root.get_texture().get_image().save_png(path)
	print("Graphics pass capture: %s (%s)" % [path, error_string(error)])
	return error == OK
