extends SceneTree
## Visual QA of the real desktop/VR menu canvas, with isolated user data.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	var flight = load("res://scripts/flight_interface.gd").new()
	cabin.add_child(flight)
	cabin.flight_interface = flight
	flight.setup(cabin)
	cabin.cabin_audio.enabled = true
	cabin._show_flight_menu("pause")
	flight.menu._choose("audio")
	for frame in 30: await process_frame
	if "--record-sound-check" in OS.get_cmdline_user_args():
		cabin.handle_flight_action("audio_preview")
		while is_instance_valid(cabin._audio_audition): await process_frame
	await RenderingServer.frame_post_draw
	var path: String = cabin.repository_path("output/aquarius-audio-menu.png")
	var error := root.get_texture().get_image().save_png(path)
	print("Audio menu capture: " + error_string(error))
	flight.back()
	cabin._show_flight_menu("main")
	for frame in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(cabin.repository_path("output/aquarius-audio-main-menu.png"))
	# Capture the same canvas used by headset pointers without initializing XR.
	flight.show_page("pause", true, cabin._flight_menu_status(""))
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	flight._surface.get_texture().get_image().save_png(cabin.repository_path("output/aquarius-vr-info-menu.png"))
	flight.show_page("controls", true, cabin._flight_menu_status(""))
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	flight._surface.get_texture().get_image().save_png(cabin.repository_path("output/aquarius-vr-grab-controls.png"))
	paused = false
	cabin.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
