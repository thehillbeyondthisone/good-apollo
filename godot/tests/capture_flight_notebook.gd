extends SceneTree
var cabin: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _capture(name: String) -> void:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(cabin.repository_path("output/" + name + ".png"))

func _run() -> void:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	cabin.notebook.refresh()
	await _capture("aquarius-flight-notebook")
	cabin.notebook.surface.get_texture().get_image().save_png(cabin.repository_path("output/flight-notebook-page.png"))
	for id: String in ["water_dispenser_pose", "water_dispenser_cap"]:
		cabin._operate(id, 1, "water-preview")
	cabin._operate("water_dispenser_trigger", 1, "water-preview")
	cabin.mechanisms.refresh()
	var dispenser: Node3D = cabin.bindings.water_dispenser_pose.actuator
	var nozzle: Vector3 = dispenser.to_global(Vector3(0, 0.14, 0))
	cabin._aim_desktop(nozzle + Vector3(0.24, 0.20, -0.28), nozzle)
	cabin.notebook.refresh()
	await _capture("aquarius-water-dispensing")
	cabin._release_button("water-preview")
	cabin._set_inspection_view(1)
	cabin.systems.start_powerdown()
	cabin.notebook.refresh()
	await _capture("aquarius-notebook-powerdown")
	cabin.systems.electrical.call("NextPowerDownEvent")
	cabin.notebook.refresh()
	# Preview the exact XR book and controller meshes using the desktop camera;
	# this is a visual fixture, not a claim of hardware acceptance.
	cabin.xr_active = true
	cabin.hud.hide()
	cabin.notebook.recall()
	var xr = load("res://scripts/xr_session.gd").new()
	cabin.add_child(xr)
	xr.cabin = cabin
	xr._ray_material = xr._material(Color(0.73, 0.80, 0.79, 0.38))
	xr._ray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	xr._target_material = xr._material(Color("#eac28b"))
	var controller := XRController3D.new()
	controller.show_when_tracked = false
	controller.name = "right_hand"
	xr.add_child(controller)
	xr._create_pointer(controller)
	var id: String = cabin.systems.powerdown_target()
	controller.global_position = cabin.desktop_camera.global_transform * Vector3(0.15, -0.16, -0.25)
	controller.look_at(cabin.bindings[id].target_global_position())
	xr._update_pointer(controller, true, id, false)
	await _capture("aquarius-xr-notebook-preview")
	xr.cabin = null
	cabin.xr_active = false
	cabin.notebook.hide()
	cabin.systems.odyssey.start()
	cabin.notebook.refresh()
	await _capture("aquarius-odyssey-notebook")
	cabin.queue_free()
	await process_frame
	quit()
