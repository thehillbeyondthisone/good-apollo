extends SceneTree
const Highlight = preload("res://scripts/procedure_highlight.gd")
var checks := 0
var failures := PackedStringArray()
var cabin: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	if not "--self-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	var highlight := Highlight.new()
	cabin.add_child(highlight)
	highlight.setup(cabin)
	check(highlight.motes.size() == 18, "Guidance uses a fixed 18-mote pool.")
	check(not highlight.target_ring.material_override.no_depth_test, "Task ring respects geometry depth.")
	check(not highlight.halo.material_override.shader.code.contains("depth_test_disabled"), "Soft glow respects geometry depth.")
	check(highlight.spill.omni_range <= 0.2 and not highlight.spill.shadow_enabled, "Local spill is bounded and adds no shadow-map pass.")
	for id: String in ["p16_cb_r03_c05", "p4_dsky_verb", "ecs_des_h2o", "water_dispenser_trigger"]:
		highlight.update_target(id, true)
		check(highlight.target_valid and highlight.target_ring.visible and highlight.halo.visible, "Target affordance is visible: " + id)
		var binding = cabin.bindings[id]
		check((highlight.target_position - binding.target_global_position()).dot(binding.target_surface_normal()) >= 0.0079, "Glow emerges ahead of control geometry: " + id)
		check(highlight.motes.all(func(mote): return mote.visible), "All pooled motes are active at the target: " + id)
		highlight._process(0.25)
		check(highlight.motes.all(func(mote): return mote.global_position.distance_to(highlight.target_position) < 0.10), "Motes stay near the called-out control: " + id)
	highlight.update_target("p16_cb_r03_c05", true)
	check(highlight.panel_frame.visible, "Called-out breaker frames its actual parent panel.")
	var first: Vector3 = highlight.motes[0].global_position
	highlight._process(0.4)
	check(first.distance_to(highlight.motes[0].global_position) > 0.001, "Particles visibly drift away from the control.")
	highlight.update_target("", true)
	check(not highlight.target_valid and not highlight.halo.visible and not highlight.spill.visible, "Missing target clears halo and light.")
	highlight.update_target("p16_cb_r03_c05", false)
	check(not highlight.target_ring.visible and highlight.motes.all(func(mote): return not mote.visible), "Menus and disabled guidance clear ring and particles.")
	if "--highlight-capture" in OS.get_cmdline_user_args():
		highlight.update_target("p16_cb_r03_c05", true)
		cabin._inspect_checklist_control("p16_cb_r03_c05")
		cabin.hud.hide()
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(cabin.repository_path("output/procedure-highlight-preview.png"))
	var report := {"checks": checks, "failures": failures, "headsetTested": false}
	var file := FileAccess.open(cabin.repository_path("output/procedure-highlight-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Procedure highlight: %d checks, %d failures." % [checks, failures.size()])
	cabin.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
