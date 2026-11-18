extends SceneTree
var cabin: Node3D

func _initialize() -> void:
	_run.call_deferred()

func capture(name: String) -> void:
	for index in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(cabin.repository_path("output/" + name + ".png"))

func _run() -> void:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	cabin.xr_active = true
	cabin.hud.hide()
	cabin.notebook.onboarding = load("res://scripts/cabin_onboarding.gd").new()
	cabin.notebook.recall()
	cabin.notebook.refresh()
	await capture("aquarius-onboarding-vr-preview")
	assert(cabin.notebook.book.is_visible_in_tree() and cabin.desktop_camera.is_position_in_frustum(cabin.notebook.body.global_position), "Recalled notebook remains rendered within view after physics synchronization.")
	cabin.notebook.surface.get_texture().get_image().save_png(cabin.repository_path("output/onboarding-page.png"))
	cabin.notebook.onboarding.stage = 3
	cabin.notebook.refresh()
	cabin._inspect_checklist_control("p3_exterior_ltg")
	cabin.desktop_camera.position += cabin.desktop_camera.global_basis.z * 0.35
	cabin.notebook.recall()
	var hover: Node3D = load("res://scripts/control_hover.gd").new()
	cabin.add_child(hover)
	hover.setup(cabin)
	hover.present("p3_exterior_ltg", true)
	await capture("aquarius-onboarding-control-glow")
	cabin.xr_active = false
	cabin.queue_free()
	await process_frame
	quit()
