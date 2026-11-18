extends SceneTree
## Desktop-only comparison at the start and after the power-down.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	if not cabin.load_errors.is_empty() or cabin.systems == null or not cabin.systems.start_powerdown():
		quit(1)
		return
	if not await capture(cabin.repository_path("output/aquarius-powerdown-start.png")):
		quit(1)
		return
	for index in range(int(cabin.systems.powerdown_snapshot.eventCount)):
		if str(cabin.systems.electrical.call("NextPowerDownEvent")).is_empty():
			quit(1)
			return
	if not cabin.systems.session_clock.advance_ticks(6000):
		quit(1)
		return
	cabin.status_time = 0.0
	var success := await capture(cabin.repository_path("output/aquarius-powerdown.png"))
	cabin.queue_free()
	await process_frame
	quit(0 if success else 1)

func capture(path: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	print("Power-down desktop capture: %s (%s)" % [path, error_string(error)])
	return error == OK
