extends SceneTree
## Headless geometry/state verification. No claim of GPU or headset performance.

var checks := 0
var failures := PackedStringArray()
var reported_pose_mismatch := false

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("FAIL: " + message)

func _matching_poses(batcher: Node) -> bool:
	for source: MeshInstance3D in batcher.get_batched_sources():
		if not batcher.instance_world_transform(source).is_equal_approx(source.global_transform):
			if not reported_pose_mismatch:
				print("Batch diagnostic source=", source.get_path(), " sourcePose=", source.global_transform, " instancePose=", batcher.instance_world_transform(source), " renderer=", RenderingServer.get_current_rendering_method())
				reported_pose_mismatch = true
			return false
	return true

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	check(scene.load_errors.is_empty(), "Unbatched source cabin loads with all control bindings")
	var before: Dictionary = scene.state_store.get_save_payload()
	var binding_count: int = scene.bindings.size()
	var batcher = load("res://scripts/cabin_batches.gd").new()
	var stats: Dictionary = batcher.install(scene.imported_cabin, scene.bindings)
	check(int(stats.groups) > 10 and int(stats.sources) > 1000, "Repeated hardware is represented by a small number of instance groups")
	check(int(stats.estimatedDrawInstancesSaved) > 1000, "Batch construction replaces over one thousand individual hardware submissions")
	check(scene.bindings.size() == binding_count and scene.state_store.get_save_payload() == before, "Batching preserves all control roots, bindings and saved simulator input state")
	var sources: Array[MeshInstance3D] = batcher.get_batched_sources()
	check(sources.all(func(source: MeshInstance3D) -> bool: return not source.visible), "Original hardware meshes are hidden rather than rendered twice")
	check(_matching_poses(batcher), "Every batch instance initially matches its hidden source world transform")
	var artwork: Array[Node] = scene.imported_cabin.find_children("*_artwork", "MeshInstance3D", true, false)
	var procedural_readout := MeshInstance3D.new()
	procedural_readout.mesh = QuadMesh.new()
	procedural_readout.name = "LiveReadoutBackingRegression"
	scene.imported_cabin.add_child(procedural_readout)
	check(not batcher._eligible(procedural_readout) and procedural_readout.visible, "Procedural live-readout QuadMesh stays on its own render path")
	procedural_readout.free()
	check(not artwork.is_empty() and artwork.all(func(node: Node) -> bool: return node.visible), "Panel artwork and its dimmable materials remain individually visible")
	for id: String in ["p11_cb_r04_c19", "p1_rate_err_mon", "p12_antenna_s_band", "p8_stage_guard", "aca_cdr_pitch", "hatch_forward_relief_dump"]:
		var moving: Array[MeshInstance3D] = batcher.sources_for_control(id)
		check(not moving.is_empty(), "Batched moving hardware exists for " + id)
		if moving.is_empty(): continue
		var original_poses: Array[Transform3D] = []
		for source: MeshInstance3D in moving: original_poses.append(source.global_transform)
		var definition: Dictionary = scene.state_store.definitions[id]
		var alternate: int = (int(scene.state_store.states[id]) + 1) % definition.positions.size()
		scene.state_store.set_position(id, alternate)
		scene._apply_position(id)
		batcher.refresh(id)
		var changed := false
		for index in moving.size():
			if not moving[index].global_transform.is_equal_approx(original_poses[index]): changed = true
		check(changed, "Operating " + id + " moves actual hidden geometry")
		check(_matching_poses(batcher), "Batch world poses follow " + id + " without modifying its root or actuator")
	check(scene.state_store.apply_save_payload(before, true).is_empty(), "Original complete input checkpoint restores")
	scene._apply_all_positions()
	batcher.refresh()
	check(_matching_poses(batcher), "Batch poses match all restored switch and continuous values")
	# Parent movement must also move batches; actuator visibility must be preserved.
	var prior_transform: Transform3D = scene.imported_cabin.transform
	scene.imported_cabin.position += Vector3(0.1, 0.02, -0.04)
	check(_matching_poses(batcher), "Moving the complete cabin preserves relative instance poses")
	scene.imported_cabin.transform = prior_transform
	var moving_root: Node3D = scene.bindings["p11_cb_r04_c19"].root
	moving_root.visible = false
	batcher.refresh("p11_cb_r04_c19")
	var hidden_sources: Array[MeshInstance3D] = batcher.sources_for_control("p11_cb_r04_c19")
	check(hidden_sources.all(func(source: MeshInstance3D) -> bool: return is_zero_approx(batcher.instance_world_transform(source).basis.determinant())), "Hidden parent also suppresses its batched geometry")
	moving_root.visible = true
	batcher.refresh("p11_cb_r04_c19")
	check(_matching_poses(batcher), "Showing the parent restores its batch poses")
	batcher.set_enabled(false)
	check(sources.all(func(source: MeshInstance3D) -> bool: return source.visible), "Disabling batching reversibly restores every original mesh")
	batcher.set_enabled(true)
	check(sources.all(func(source: MeshInstance3D) -> bool: return not source.visible) and _matching_poses(batcher), "Re-enabling batching restores the same geometry with no duplicates")
	batcher.uninstall()
	check(sources.all(func(source: MeshInstance3D) -> bool: return source.visible) and int(batcher.get_stats().sources) == 0, "Uninstall removes batches and restores original visibility")
	check(scene.bindings.size() == binding_count and scene.state_store.get_save_payload() == before, "Complete batching lifecycle leaves persisted input state unchanged")
	var report := {"result": "PASS" if failures.is_empty() else "FAIL", "checks": checks,
		"failures": Array(failures), "batching": stats, "headsetTested": false, "renderedComparisonPerformed": false}
	var path: String = scene.repository_path("reference/cabin-batching-tests.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print(JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
