extends RefCounted
## Static cabin structure blocks controller rays. No visual mesh is changed.

static func install(cabin: Node3D) -> int:
	if cabin == null:
		return 0
	var count := 0
	for node: Node in cabin.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var label := str(node.name)
		var structural := label.contains("_backing") or label in ["Floor", "Roof", "Forward_hatch", "Docking_hatch", "Instrument_support_wall", "Forward_lower_wall", "Forward_top_rail", "Aft_pressure_bulkhead"] or label.begins_with("lower_sidewall") or label.begins_with("upper_sidewall") or label.begins_with("Forward_window_surround") or label.begins_with("Aft_occluder_")
		if not structural or mesh_instance.mesh == null:
			continue
		var body := StaticBody3D.new()
		body.name = "CabinOccluder"
		body.collision_layer = 16
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		collision.shape = mesh_instance.mesh.create_trimesh_shape()
		body.add_child(collision)
		mesh_instance.add_child(body)
		count += 1
	return count
