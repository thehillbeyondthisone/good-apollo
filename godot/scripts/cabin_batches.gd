extends Node3D
## Opt-in rendering optimization. Named roots and actuators remain authoritative.
## Only shared opaque rigid hardware is instanced; instruments and artwork stay
## on their normal rendering path. This node never changes simulator state.

const HARDWARE_MATERIALS := ["AQ_brushed_aluminum", "AQ_panel_edges", "AQ_rubber", "AQ_ivory_handles"]

var enabled := true
var _groups: Array[Dictionary] = []
var _records: Array[Dictionary] = []
var _records_by_source: Dictionary = {}
var _records_by_control: Dictionary = {}
var _source_root: Node3D
var _known_controls: Dictionary = {}

func install(cabin: Node3D, control_bindings: Dictionary = {}, minimum_group_size: int = 4) -> Dictionary:
	uninstall()
	if cabin == null:
		return get_stats()
	_source_root = cabin
	_known_controls = control_bindings
	if get_parent() == null:
		name = "CabinHardwareBatches"
		cabin.add_child(self)
	var candidates: Dictionary = {}
	for node: Node in cabin.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if not _eligible(mesh_node): continue
		var key := _group_key(mesh_node)
		if not candidates.has(key): candidates[key] = []
		candidates[key].append(mesh_node)
	for key: String in candidates:
		var sources: Array = candidates[key]
		if sources.size() < maxi(2, minimum_group_size): continue
		var first: MeshInstance3D = sources[0]
		var batch := MultiMeshInstance3D.new()
		batch.name = "HardwareBatch_%02d" % _groups.size()
		batch.layers = first.layers
		batch.cast_shadow = first.cast_shadow
		batch.gi_mode = first.gi_mode
		batch.material_override = first.material_override
		batch.transparency = first.transparency
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = first.mesh
		instances.instance_count = sources.size()
		batch.multimesh = instances
		add_child(batch)
		var packed_poses := PackedFloat32Array()
		packed_poses.resize(sources.size() * 12)
		var group: Dictionary = {"node": batch, "records": [], "buffer": packed_poses}
		_groups.append(group)
		for index in sources.size():
			var source: MeshInstance3D = sources[index]
			var owner_id := _control_owner(source)
			var record: Dictionary = {"source": source, "batch": batch, "groupIndex": _groups.size() - 1, "index": index,
				"originalVisible": source.visible, "controlId": owner_id}
			group.records.append(record)
			_records.append(record)
			_records_by_source[source.get_instance_id()] = record
			if not owner_id.is_empty():
				if not _records_by_control.has(owner_id): _records_by_control[owner_id] = []
				_records_by_control[owner_id].append(record)
			source.visible = false
	refresh()
	set_enabled(enabled)
	return get_stats()

func _eligible(source: MeshInstance3D) -> bool:
	if source == null or source.mesh == null or not source.is_visible_in_tree(): return false
	# Runtime readouts use procedural QuadMesh resources. Only imported ArrayMesh
	# hardware has the blend-shape API and is eligible for rigid batching.
	if not source.mesh is ArrayMesh: return false
	# Structural occluder children, skinned meshes, overlays and custom materials
	# are deliberately left alone. Hiding a mesh must never hide its child nodes.
	if source.get_child_count() > 0 or source.skin != null or source.mesh.get_blend_shape_count() > 0: return false
	if source.material_overlay != null or source.mesh.get_surface_count() != 1: return false
	if source.get_surface_override_material(0) != null or source.transparency > 0.0: return false
	if not is_zero_approx(source.visibility_range_begin) or not is_zero_approx(source.visibility_range_end): return false
	if source.global_basis.determinant() <= 0.0: return false
	var material := source.get_active_material(0) as StandardMaterial3D
	if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return false
	if not material.resource_name in HARDWARE_MATERIALS: return false
	var label := str(source.name).to_lower()
	return not label.contains("artwork") and not label.contains("readout") and not label.contains("annunciator") and not label.contains("lamp") and not label.contains("display")

func _group_key(source: MeshInstance3D) -> String:
	var material := source.get_active_material(0)
	return "%d/%d/%d/%d/%d" % [source.mesh.get_instance_id(), material.get_instance_id(),
		source.layers, source.cast_shadow, source.gi_mode]

func _control_owner(source: Node) -> String:
	var cursor := source.get_parent()
	while cursor != null and cursor != _source_root:
		var key := str(cursor.name)
		if _known_controls.has(key): return key
		cursor = cursor.get_parent()
	return ""

func refresh(control_id: String = "") -> void:
	if not is_inside_tree(): return
	var records: Array = _records if control_id.is_empty() else _records_by_control.get(control_id, [])
	var changed_groups: Dictionary = {}
	for record: Dictionary in records:
		var source: MeshInstance3D = record.source
		if not is_instance_valid(source): continue
		var batch: MultiMeshInstance3D = record.batch
		var pose := batch.global_transform.affine_inverse() * source.global_transform
		if not _ancestors_visible(source): pose.basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
		var group: Dictionary = _groups[int(record.groupIndex)]
		var buffer: PackedFloat32Array = group.buffer
		_write_pose(buffer, int(record.index), pose)
		group.buffer = buffer
		changed_groups[batch.get_instance_id()] = group
	for key: int in changed_groups:
		var group: Dictionary = changed_groups[key]
		group.node.multimesh.buffer = group.buffer
		_update_bounds(group)

func _write_pose(buffer: PackedFloat32Array, index: int, pose: Transform3D) -> void:
	# MultiMesh's 3D transform buffer is three rows of basis + translation.
	# Bulk upload also permits genuine submitted-buffer inspection in headless
	# tests: Godot's dummy renderer ignores the per-instance transform setter.
	var offset := index * 12
	var values := [pose.basis.x.x, pose.basis.y.x, pose.basis.z.x, pose.origin.x,
		pose.basis.x.y, pose.basis.y.y, pose.basis.z.y, pose.origin.y,
		pose.basis.x.z, pose.basis.y.z, pose.basis.z.z, pose.origin.z]
	for component in 12: buffer[offset + component] = values[component]

func _read_pose(buffer: PackedFloat32Array, index: int) -> Transform3D:
	var offset := index * 12
	if buffer.size() < offset + 12: return Transform3D.IDENTITY
	return Transform3D(Basis(
		Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
		Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
		Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10])),
		Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11]))

func _ancestors_visible(source: Node3D) -> bool:
	var cursor := source.get_parent()
	while cursor != null:
		if cursor is Node3D and not cursor.visible: return false
		cursor = cursor.get_parent()
	return true

func _update_bounds(group: Dictionary) -> void:
	var batch: MultiMeshInstance3D = group.node
	var mesh_bounds := batch.multimesh.mesh.get_aabb()
	var bounds := AABB()
	var first := true
	for record: Dictionary in group.records:
		var pose := _read_pose(group.buffer, int(record.index))
		var instance_bounds: AABB = pose * mesh_bounds
		bounds = instance_bounds if first else bounds.merge(instance_bounds)
		first = false
	# Custom bounds are recomputed on input changes, avoiding per-frame automatic
	# scans while ensuring moved actuators remain inside the culling volume.
	batch.multimesh.custom_aabb = bounds.grow(0.002)

func set_enabled(value: bool) -> void:
	enabled = value
	for record: Dictionary in _records:
		if is_instance_valid(record.source): record.source.visible = false if enabled else bool(record.originalVisible)
	for group: Dictionary in _groups:
		group.node.visible = enabled
	if enabled: refresh()

func get_stats() -> Dictionary:
	return {"enabled": enabled, "groups": _groups.size(), "sources": _records.size(),
		"controlsWithBatchedHardware": _records_by_control.size(),
		"estimatedDrawInstancesSaved": _records.size() - _groups.size(),
		"scope": "Shared opaque rigid hardware; artwork/readouts/output materials excluded"}

func get_batched_sources() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for record: Dictionary in _records:
		if is_instance_valid(record.source): result.append(record.source)
	return result

func sources_for_control(id: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for record: Dictionary in _records_by_control.get(id, []): result.append(record.source)
	return result

func instance_world_transform(source: MeshInstance3D) -> Transform3D:
	if not _records_by_source.has(source.get_instance_id()): return Transform3D.IDENTITY
	var record: Dictionary = _records_by_source[source.get_instance_id()]
	var batch: MultiMeshInstance3D = record.batch
	return batch.global_transform * _read_pose(batch.multimesh.buffer, int(record.index))

func uninstall() -> void:
	for record: Dictionary in _records:
		if is_instance_valid(record.source): record.source.visible = bool(record.originalVisible)
	for group: Dictionary in _groups:
		if is_instance_valid(group.node): group.node.free()
	_groups.clear()
	_records.clear()
	_records_by_source.clear()
	_records_by_control.clear()
	_known_controls = {}
	_source_root = null
