extends RefCounted
## Maps one inventory ID to one imported glTF node and its moving actuator.

const StateStore = preload("res://scripts/control_state.gd")

var definition: Dictionary
var root: Node3D
var actuator: Node3D
var initial_actuator_transform := Transform3D.IDENTITY
var interaction_area: Area3D
var target_shape: SphereShape3D
var target_collision: CollisionShape3D
var presentation_motion: Dictionary = {}
var pose_transforms: Array[Transform3D] = []
var motion_errors := PackedStringArray()

func setup(control_definition: Dictionary, visual_root: Node3D) -> void:
	definition = control_definition
	root = visual_root
	actuator = root.find_child("actuator", true, false) as Node3D
	if actuator == null:
		actuator = root.find_child(str(definition.id) + "__actuator", true, false) as Node3D
	if actuator != null:
		initial_actuator_transform = actuator.transform
	presentation_motion = definition.get("presentation", {}).get("motion", {})
	_prepare_motion()
	interaction_area = Area3D.new()
	interaction_area.name = "InteractionTarget"
	interaction_area.collision_layer = 8
	interaction_area.collision_mask = 0
	interaction_area.monitoring = false
	interaction_area.set_meta("control_id", str(definition.id))
	var shape := SphereShape3D.new()
	target_shape = shape
	shape.radius = 0.023
	if str(definition.get("type", "")) in ["meter", "display"]:
		shape.radius = 0.040
	var collision := CollisionShape3D.new()
	target_collision = collision
	collision.shape = shape
	# Blender's local +Z panel normal becomes glTF/Godot local +Y.
	collision.position.y = 0.02
	var target_offset: Array = definition.get("presentation", {}).get("targetLocalBlenderM", [])
	if target_offset.size() == 3:
		collision.position = blender_vector(target_offset)
	interaction_area.add_child(collision)
	if actuator != null and not presentation_motion.is_empty() and str(presentation_motion.get("kind", "")) != "scale":
		interaction_area.transform = initial_actuator_transform.affine_inverse()
		actuator.add_child(interaction_area)
	else:
		root.add_child(interaction_area)

func target_global_position() -> Vector3:
	return target_collision.global_position if target_collision != null else root.global_position

func target_surface_normal() -> Vector3:
	var normal: Array = definition.get("presentation", {}).get("targetNormalLocalBlenderM", [])
	if normal.size() == 3 and interaction_area != null:
		return (interaction_area.global_basis * blender_vector(normal)).normalized()
	return interaction_area.global_basis.y.normalized() if interaction_area != null else root.global_basis.y.normalized()

static func blender_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[2]), -float(value[1]))

static func blender_rotation(value: Array) -> Basis:
	var conversion := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	var radians := Vector3(deg_to_rad(float(value[0])), deg_to_rad(float(value[1])), deg_to_rad(float(value[2])))
	return conversion * Basis.from_euler(radians, EULER_ORDER_XYZ) * conversion.inverse()

func _prepare_motion() -> void:
	if presentation_motion.is_empty(): return
	var kind := str(presentation_motion.get("kind", ""))
	var count: int = definition.positions.size()
	var default_index: int = definition.positions.find(str(definition.get("default", definition.positions[0])))
	if kind == "poses":
		var positions: Array = presentation_motion.get("worldPositionsBlenderM", [])
		var rotations: Array = presentation_motion.get("worldRotationsBlenderDeg", [])
		if positions.size() != count or (not rotations.is_empty() and rotations.size() != count):
			motion_errors.append("World-pose data must match every declared position: " + str(definition.id))
			return
		var default_position := blender_vector(positions[default_index])
		var default_rotation := blender_rotation(rotations[default_index]) if not rotations.is_empty() else Basis.IDENTITY
		var root_basis := root.global_basis if root.is_inside_tree() else root.basis
		for index in range(count):
			var next_pose := initial_actuator_transform
			next_pose.origin += root_basis.inverse() * (blender_vector(positions[index]) - default_position)
			if not rotations.is_empty():
				var world_delta := blender_rotation(rotations[index]) * default_rotation.inverse()
				next_pose.basis = root_basis.inverse() * world_delta * root_basis * initial_actuator_transform.basis
			pose_transforms.append(next_pose)
	elif kind in ["rotate", "translate", "scale"]:
		var values: Array = presentation_motion.get("values", [])
		if values.size() != count:
			motion_errors.append("Motion values must match every declared position: " + str(definition.id))
		elif kind == "scale" and is_zero_approx(float(values[default_index])):
			motion_errors.append("Default presentation scale must be nonzero: " + str(definition.id))
	else:
		motion_errors.append("Unknown presentation motion: " + str(definition.id))

func _apply_motion(index: int, next_index: int = -1, blend: float = 0.0) -> bool:
	if presentation_motion.is_empty() or not motion_errors.is_empty(): return false
	var kind := str(presentation_motion.get("kind", ""))
	if kind == "poses":
		actuator.transform = pose_transforms[index] if next_index < 0 else pose_transforms[index].interpolate_with(pose_transforms[next_index], blend)
		return true
	var values: Array = presentation_motion.get("values", [])
	var default_index: int = definition.positions.find(str(definition.get("default", definition.positions[0])))
	var value := float(values[index]) if next_index < 0 else lerpf(float(values[index]), float(values[next_index]), blend)
	var delta := value - float(values[default_index])
	var name := str(presentation_motion.get("axis", "x"))
	var axis := Vector3.RIGHT if name == "x" else (Vector3.FORWARD if name == "y" else Vector3.UP)
	if kind == "rotate": actuator.rotate_object_local(axis, deg_to_rad(delta))
	elif kind == "translate": actuator.position += axis * delta
	elif kind == "scale":
		var ratio := value / float(values[default_index])
		actuator.scale *= Vector3.ONE + axis.abs() * (ratio - 1.0)
	return true

func fit_target_radius(nearest_center_distance: float) -> void:
	# Dense breaker rows need separate targets; a fixed generous radius steals clicks.
	target_shape.radius = minf(target_shape.radius, nearest_center_distance * 0.35)

func apply_position(index: int) -> void:
	if actuator == null:
		return
	actuator.transform = initial_actuator_transform
	if _apply_motion(index): return
	var count: int = definition.positions.size()
	var fraction := float(index) / float(maxi(1, count - 1))
	var default_index: int = definition.positions.find(str(definition.get("default", definition.positions[0])))
	var default_fraction := float(default_index) / float(maxi(1, count - 1))
	var kind := str(definition.get("type", ""))
	if str(definition.id).begins_with("hatch_") and str(definition.id).ends_with("_door"):
		actuator.rotate_object_local(Vector3.BACK, deg_to_rad(-100.0 * (fraction - default_fraction)))
	elif kind in ["toggle", "lever-lock", "guarded"]:
		actuator.rotate_object_local(Vector3.RIGHT, deg_to_rad(36.0 * (fraction - default_fraction)))
	elif kind in ["rotary", "valve"]:
		actuator.rotate_object_local(Vector3.UP, deg_to_rad(160.0 * (fraction - default_fraction)))
	elif kind == "breaker":
		actuator.position.y -= 0.012 * (fraction - default_fraction)
	elif kind == "pushbutton":
		actuator.position.y -= 0.008 * (fraction - default_fraction)
	elif kind == "thumbwheel":
		actuator.rotate_object_local(Vector3.RIGHT, float(index - default_index) * PI / 5.0)
	elif kind == "guard":
		actuator.rotate_object_local(Vector3.RIGHT, deg_to_rad(-105.0 * (fraction - default_fraction)))
	elif kind == "axis":
		apply_axis(float(index - 1))
	elif kind == "joystick":
		var position_label := str(definition.positions[index]).to_upper()
		if position_label == "UP": actuator.rotate_object_local(Vector3.RIGHT, deg_to_rad(-18))
		elif position_label == "DOWN": actuator.rotate_object_local(Vector3.RIGHT, deg_to_rad(18))
		elif position_label == "RIGHT": actuator.rotate_object_local(Vector3.BACK, deg_to_rad(-18))
		elif position_label == "LEFT": actuator.rotate_object_local(Vector3.BACK, deg_to_rad(18))

func apply_axis(value: float) -> void:
	if actuator == null:
		return
	actuator.transform = initial_actuator_transform
	if not presentation_motion.is_empty() and motion_errors.is_empty():
		var previous := 0
		var count: int = definition.positions.size()
		for index in range(1, count):
			var upper := StateStore.normalized_position(definition, index)
			if value <= upper or index == count - 1:
				var lower := StateStore.normalized_position(definition, previous)
				var fraction := clampf((value - lower) / maxf(0.000001, upper - lower), 0.0, 1.0)
				if _apply_motion(previous, index, fraction): return
			previous = index
	var axis_name := str(definition.get("axis", {}).get("axis", "pitch"))
	var default_index: int = definition.positions.find(str(definition.get("default", definition.positions[0])))
	var travel := clampf(value, -1.0, 1.0) - StateStore.normalized_position(definition, default_index)
	var kind := str(definition.get("type", ""))
	if kind in ["rotary", "valve"]:
		actuator.rotate_object_local(Vector3.UP, deg_to_rad(80.0 * travel))
	elif kind == "thumbwheel":
		actuator.rotate_object_local(Vector3.RIGHT, travel * float(definition.positions.size() - 1) * PI / 10.0)
	elif axis_name in ["x", "y", "z"] or axis_name.ends_with(" translation"):
		if axis_name.begins_with("LM-X"): axis_name = "x"
		elif axis_name.begins_with("LM-Y"): axis_name = "y"
		elif axis_name.begins_with("LM-Z"): axis_name = "z"
		var direction := Vector3.RIGHT if axis_name == "x" else (Vector3.FORWARD if axis_name == "y" else Vector3.UP)
		actuator.position += direction * travel * 0.025
	else:
		if axis_name == "LM-X rotation": axis_name = "yaw"
		elif axis_name == "LM-Y rotation": axis_name = "pitch"
		elif axis_name == "LM-Z rotation": axis_name = "roll"
		var direction := Vector3.RIGHT if axis_name == "pitch" else (Vector3.UP if axis_name == "yaw" else Vector3.BACK)
		actuator.rotate_object_local(direction, deg_to_rad(18.0 * travel))
