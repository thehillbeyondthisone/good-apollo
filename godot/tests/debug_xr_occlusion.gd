extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await physics_frame
	await process_frame
	var rows: Array[Dictionary] = []
	for id: String in cabin.bindings:
		var binding = cabin.bindings[id]
		var target: Vector3 = binding.root.global_position
		var normal: Vector3 = binding.root.global_basis.y.normalized()
		var start := target + normal * 0.18
		if cabin._pick(start, -normal) == id: continue
		var query := PhysicsRayQueryParameters3D.create(start, start - normal * 2.2, 24)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var hit: Dictionary = cabin.get_world_3d().direct_space_state.intersect_ray(query)
		var details := {"id": id, "target": str(target), "start": str(start), "normal": str(normal), "hit": str(hit.get("position", "none"))}
		if not hit.is_empty():
			var collider: Node3D = hit.collider
			details["collider"] = str(collider.get_path())
			details["parent"] = str(collider.get_parent().name)
			details["parentPosition"] = str(collider.get_parent().global_position)
			if collider.get_parent() is MeshInstance3D:
				var mesh_node: MeshInstance3D = collider.get_parent()
				details["occluderWorldAabb"] = str(mesh_node.global_transform * mesh_node.get_aabb())
		rows.append(details)
	print(JSON.stringify(rows))
	var file := FileAccess.open(cabin.repository_path("output/xr-occlusion-debug.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t"))
	file.close()
	cabin.queue_free()
	await process_frame
	quit()
