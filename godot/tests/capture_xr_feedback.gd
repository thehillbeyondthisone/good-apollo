extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	cabin.hud.hide()
	cabin.notebook.desktop_layer.hide()
	cabin.notebook.set_process(false)
	cabin._inspect_checklist_control("p3_flood_ovhd_fwd")
	var hover = load("res://scripts/control_hover.gd").new()
	cabin.add_child(hover)
	hover.setup(cabin)
	hover.present("p3_flood_ovhd_fwd", true)
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(cabin.repository_path("output/aquarius-hover-status.png"))
	cabin.queue_free()
	await process_frame
	quit()
