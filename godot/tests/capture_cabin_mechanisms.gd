extends SceneTree
## Reproducible desktop-only visual review. Pass --self-test --systems-test.

var cabin: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _capture(name: String, position: Vector3, target: Vector3) -> void:
	cabin.desktop_camera.global_position = position
	cabin.desktop_camera.look_at(target, Vector3.UP)
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = cabin.repository_path("output/" + name + ".png")
	var error := root.get_texture().get_image().save_png(path)
	print("Desktop mechanism capture: %s (%s)" % [path, error_string(error)])

func _set_control(id: String, label: String) -> void:
	var index: int = cabin.state_store.definitions[id].positions.find(label)
	if index >= 0:
		cabin.state_store.set_position(id, index)
		cabin._apply_position(id)

func _run() -> void:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	if not cabin.load_errors.is_empty():
		quit(1)
		return
	cabin.hud.visible = false
	await _capture("aquarius-cabin-mechanisms", Vector3(0,1.62,0.70), Vector3(0,1.52,-0.7))
	await _capture("aquarius-aft-mechanisms", Vector3(0,1.61,-0.45), Vector3(0,1.12,1.03))
	_set_control("shade_cdr", "DEPLOYED")
	_set_control("shade_lmp", "DEPLOYED")
	await _capture("aquarius-shades-deployed", Vector3(0,1.62,0.70), Vector3(0,1.52,-0.7))
	_set_control("shade_cdr", "ROLLED")
	_set_control("shade_lmp", "ROLLED")
	_set_control("coas_barrel_lock", "RELEASED")
	_set_control("coas_mount", "DOCKING_WINDOW")
	await _capture("aquarius-coas-overhead", Vector3(-0.25,1.42,0.15), Vector3(-0.68,1.94,-0.45))
	cabin.queue_free()
	await process_frame
	quit(0)
