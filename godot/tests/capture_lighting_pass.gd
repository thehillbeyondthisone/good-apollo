extends SceneTree
## Render the actual production renderer, controls and batched cabin hardware.
var cabin: Node3D

func _initialize() -> void:
	_run.call_deferred()

func set_control(id: String, desired: String) -> void:
	var definition: Dictionary = cabin.state_store.definitions[id]
	var index: int = definition.positions.find(desired)
	for attempt in definition.positions.size() + 1:
		var current: int = cabin.state_store.states[id]
		if current == index: return
		cabin._operate(id, 1 if index > current else -1, "lighting-capture", true)

func capture(label: String) -> void:
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var prefix: String = cabin.argument_value("--lighting-prefix", "lighting")
	var path: String = cabin.repository_path("output/" + prefix + "-" + label + ".png")
	root.get_texture().get_image().save_png(path)
	print("Lighting capture: ", path)

func _run() -> void:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	cabin.hud.hide()
	cabin.notebook.desktop_layer.hide()
	cabin.notebook.highlighter.hide()
	await capture("forward")
	cabin._set_inspection_view(4)
	await capture("aft")
	cabin._aim_desktop(Vector3(0.36, 1.14, 0.28), Vector3(0.19, 0.99, 0.90))
	await capture("dispenser-bracketed")
	set_control("water_dispenser_pose", "FREE")
	set_control("ecs_des_h2o", "OPEN")
	set_control("water_dispenser_cap", "REMOVED")
	var target: Vector3 = cabin.bindings.water_dispenser_pose.actuator.global_position
	cabin._aim_desktop(target + Vector3(0.24, 0.16, -0.40), target + Vector3(0, 0, -0.06))
	cabin._operate("water_dispenser_trigger", 1, "lighting-capture")
	await capture("dispenser-flow")
	cabin._release_button("lighting-capture")
	cabin.notebook.desktop_layer.show()
	cabin.notebook.refresh()
	await capture("water-complete")
	cabin.notebook.desktop_layer.hide()
	cabin.systems.apply_preset("cold_dark")
	cabin._set_inspection_view(1)
	await capture("dark-windows")
	set_control("shade_cdr", "DEPLOYED")
	set_control("shade_lmp", "DEPLOYED")
	await capture("dark-shades")
	set_control("utility_cdr_lamp", "FREE")
	cabin.systems.apply_preset("electrical_checkout")
	set_control("p3_flood_ovhd_fwd", "OFF")
	cabin._set_axis("p5_integral", -1.0, "lighting-capture")
	set_control("utility_cdr_plug", "CONNECTED")
	set_control("util_cdr", "BRIGHT")
	await capture("utility")
	cabin.queue_free()
	await process_frame
	quit()
