extends SceneTree
## Run on a rendered desktop with --self-test --systems-test --manual-clock --hardware-batches.

var cabin

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	await physics_frame
	var success := await _capture_sequence()
	cabin.queue_free()
	await process_frame
	quit(0 if success else 1)

func _capture_sequence() -> bool:
	var light: SpotLight3D = cabin.aft_flood_bounce
	if not cabin.load_errors.is_empty() or cabin.systems == null or cabin.systems.session_clock == null or light == null or light.light_energy <= 0.0:
		push_error("The actual aft wall and powered flood spill must load.")
		return false
	for id: String in ["hammock_cdr", "hammock_lmp"]:
		if not _check_hammock(id, false) or not _check_hammock_target(id):
			return false
	var wall_ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1.28, 1.37), Vector3(0, 1.28, 0.99), 16)
	var wall_hit := root.world_3d.direct_space_state.intersect_ray(wall_ray)
	if wall_hit.is_empty() or wall_hit.collider.get_parent().name != "Aft_pressure_bulkhead":
		push_error("The aft pressure wall must occlude controller rays.")
		return false
	for id: String in ["ecs_des_o2", "ecs_water_tank_select", "ecs_secondary_co2_cover", "ecs_suit_temp"]:
		var target: Vector3 = cabin.bindings[id].target_global_position()
		if cabin._pick(target + Vector3(0,0,-0.27), Vector3.BACK) != id:
			push_error("The ECS fascia must leave its controls pickable: " + id)
			return false
	cabin.hud.hide()
	var aft_key := InputEventKey.new()
	aft_key.keycode = KEY_4
	aft_key.pressed = true
	cabin._unhandled_input(aft_key)
	if cabin.desktop_camera.global_basis.z.z > -0.5:
		push_error("Desktop view 4 must face the aft wall.")
		return false
	if not await _capture("crew-stowage"):
		return false
	if not light.shadow_enabled or cabin.forward_shadow_key.shadow_enabled:
		push_error("The aft view must switch the desktop shadow map to the aft light.")
		return false
	cabin._aim_desktop(Vector3(-0.11, 1.39, 0.04), Vector3(-0.68, 1.20, 0.91))
	if not await _capture("stowage-detail"):
		return false
	cabin._aim_desktop(Vector3(0.27, 1.37, 0.17), Vector3(0.58, 1.20, 1.02))
	if not await _capture("ecs-detail"):
		return false
	cabin._set_inspection_view(4)
	for id: String in ["hammock_cdr", "hammock_lmp"]:
		cabin._operate(id, 1, "aft-capture")
		cabin._release_button("aft-capture")
		if not _check_hammock(id, true):
			return false
	var flood_selector: String = cabin.state_store.position_name("p3_flood_ovhd_fwd")
	if flood_selector != "OFF":
		cabin._operate("p3_flood_ovhd_fwd", -1 if flood_selector == "ALL" else 1, "aft-capture")
		cabin._release_button("aft-capture")
	cabin._aim_desktop(Vector3(0.12, 1.51, -0.43), Vector3(-0.06, 0.82, 0.93))
	if not await _capture("hammocks"):
		return false
	for id: String in ["hammock_cdr", "hammock_lmp"]:
		if not _check_hammock_target(id):
			return false
		cabin._operate(id, -1, "aft-capture")
		cabin._release_button("aft-capture")
		if not _check_hammock(id, false):
			return false
	if not cabin.systems.apply_preset("cold_dark") or light.visible:
		push_error("Losing flood power must extinguish aft spill.")
		return false
	cabin._set_inspection_view(4)
	return await _capture("dark")

func _check_hammock(id: String, deployed: bool) -> bool:
	var variants: Array = cabin.mechanisms.hammocks.get(id, [])
	var expected := "DEPLOYED" if deployed else "STOWED"
	if variants.size() != 2 or cabin.state_store.position_name(id) != expected or variants[0].visible == deployed or variants[1].visible != deployed:
		push_error("Hammock meshes do not reflect the %s state for %s." % [expected, id])
		return false
	return true

func _check_hammock_target(id: String) -> bool:
	var target: Vector3 = cabin.bindings[id].target_global_position()
	var offset := Vector3(0.13, 0.21, -0.31)
	if cabin._pick(target + offset, -offset.normalized()) != id:
		push_error("The hammock's visible position must remain pickable: " + id)
		return false
	return true

func _capture(name: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = cabin.repository_path("output/aquarius-aft-" + name + ".png")
	var error := root.get_texture().get_image().save_png(path)
	print("Aft cabin capture: %s (%s)" % [path, error_string(error)])
	return error == OK
