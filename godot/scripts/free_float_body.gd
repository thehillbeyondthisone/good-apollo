extends RigidBody3D
## Cabin-relative free flight. Only a held prop follows a tracked hand.
var held_by := ""
var hand_offset := Transform3D.IDENTITY
var _last_pose := Transform3D.IDENTITY
var _samples: Array[Dictionary] = []
var _pending_pose := Transform3D.IDENTITY
var _pose_pending := false

func configure(dimensions: Vector3, mass_kg: float) -> void:
	mass = mass_kg
	gravity_scale = 0.0
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.006
	angular_damp = 0.008
	continuous_cd = true
	collision_layer = 64
	collision_mask = 16 | 64
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var contact := PhysicsMaterial.new()
	contact.bounce = 0.22
	contact.friction = 0.35
	physics_material_override = contact
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	collision.shape = box
	add_child(collision)

func place(pose: Transform3D) -> void:
	end_hold(false)
	global_transform = pose
	force_update_transform()
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	_samples.clear()
	_pending_pose = pose
	_pose_pending = true

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Commit an explicit recall at the physics synchronization point as well as
	# on the scene node, including when a newly spawned body was still frozen.
	if _pose_pending:
		state.transform = _pending_pose
		state.linear_velocity = linear_velocity
		state.angular_velocity = angular_velocity
		_pose_pending = false

func begin_hold(hand: String, hand_pose: Transform3D) -> void:
	_pose_pending = false
	held_by = hand
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	hand_offset = hand_pose.affine_inverse() * global_transform
	_last_pose = global_transform
	_samples.clear()

func move_held(hand_pose: Transform3D, delta: float) -> void:
	if held_by.is_empty(): return
	var desired := hand_pose * hand_offset
	# A rotation can intersect a panel even when its translation is zero.
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = get_child(0).shape
	overlap.transform = desired
	overlap.collision_mask = 16 | 64
	overlap.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(overlap, 1).is_empty():
		desired.basis = global_basis
	var query := PhysicsTestMotionParameters3D.new()
	query.from = global_transform
	query.motion = desired.origin - global_position
	query.margin = 0.001
	var contact := PhysicsTestMotionResult3D.new()
	if PhysicsServer3D.body_test_motion(get_rid(), query, contact):
		desired.origin = global_position + query.motion * contact.get_collision_safe_fraction()
		desired.basis = global_basis
	var dt := maxf(delta, 0.001)
	var translation := (desired.origin - _last_pose.origin) / dt
	var rotation := desired.basis.get_rotation_quaternion() * _last_pose.basis.get_rotation_quaternion().inverse()
	var angle := rotation.get_angle()
	if angle > PI: angle -= TAU
	var spin := rotation.get_axis() * angle / dt
	_samples.append({"linear": translation.limit_length(1.8), "angular": spin.limit_length(4.0), "dt": dt})
	var age := 0.0
	for index in range(_samples.size() - 1, -1, -1):
		age += float(_samples[index].dt)
		if age > 0.10:
			_samples = _samples.slice(index + 1)
			break
	global_transform = desired
	_last_pose = desired

func end_hold(throw_on_release: bool = true) -> void:
	if held_by.is_empty(): return
	held_by = ""
	freeze = false
	sleeping = false
	var velocity := Vector3.ZERO
	var spin := Vector3.ZERO
	var seconds := 0.0
	if throw_on_release:
		for sample: Dictionary in _samples:
			velocity += Vector3(sample.linear) * float(sample.dt)
			spin += Vector3(sample.angular) * float(sample.dt)
			seconds += float(sample.dt)
	linear_velocity = velocity / seconds if seconds > 0 else Vector3.ZERO
	angular_velocity = spin / seconds if seconds > 0 else Vector3.ZERO
	_pending_pose = global_transform
	_pose_pending = true
	_samples.clear()
