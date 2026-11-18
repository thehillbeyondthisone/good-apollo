extends SceneTree
const FreeFloat = preload("res://scripts/free_float_body.gd")
var checks := 0
var failures := PackedStringArray()
var stage: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func body_at(position: Vector3) -> RigidBody3D:
	var body := FreeFloat.new()
	body.configure(Vector3(0.32, 0.439, 0.012), 0.25)
	stage.add_child(body)
	body.place(Transform3D(Basis.IDENTITY, position))
	return body

func frames(count: int) -> void:
	for frame in count: await physics_frame

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var body := body_at(Vector3(0, 5, 0))
	await frames(3)
	check(is_zero_approx(body.gravity_scale), "Prop has zero cabin-relative gravity.")
	check(body.collision_mask == (16 | 64), "Prop collides with structure layer 16 and other loose objects.")
	check(body.continuous_cd, "Fast thin props use continuous collision detection.")
	body.linear_velocity = Vector3(0.20, 0.10, -0.08)
	body.angular_velocity = Vector3(0, 0.4, 0.15)
	var start: Vector3 = body.global_position
	var orientation := body.global_basis.get_rotation_quaternion()
	await frames(60)
	check(body.global_position.x - start.x > 0.15, "Released prop drifts instead of remaining pinned to a hand or camera.")
	check(body.global_position.y - start.y > 0.07, "Free prop retains upward momentum without gravitational fall.")
	check(body.linear_velocity.length() > 0.20, "Gentle air damping preserves most one-second momentum.")
	check(orientation.angle_to(body.global_basis.get_rotation_quaternion()) > 0.25 and body.angular_velocity.length() > 0.35, "Released prop keeps its spin.")
	body.place(Transform3D(Basis.IDENTITY, Vector3(2, 5, 0)))
	body.linear_velocity = Vector3(0.015, 0, 0)
	await frames(90)
	check(not body.sleeping and body.linear_velocity.x > 0.010, "Even slow zero-gravity drift does not auto-sleep.")
	# Hold and release with measured linear and angular hand motion.
	body.place(Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)))
	var hand_pose := Transform3D(Basis.IDENTITY, Vector3(0, 5, 0))
	body.begin_hold("left", hand_pose)
	for sample in 8:
		hand_pose.origin.x += 0.01
		hand_pose.basis = Basis(Vector3.UP, (sample + 1) * 0.01)
		body.move_held(hand_pose, 0.02)
	check(body.freeze and body.held_by == "left", "Only a held prop follows the tracked hand.")
	body.end_hold()
	check(not body.freeze and body.held_by.is_empty(), "Releasing grip returns the prop to physical free flight.")
	check(absf(body.linear_velocity.x - 0.5) < 0.03, "Release inherits averaged hand translation velocity.")
	check(absf(body.angular_velocity.y - 0.5) < 0.03, "Release inherits averaged hand angular velocity.")
	body.begin_hold("right", hand_pose)
	hand_pose.origin.x += 0.03
	body.move_held(hand_pose, 0.02)
	body.end_hold(false)
	check(body.held_by.is_empty() and not body.freeze and body.linear_velocity.is_zero_approx() and body.angular_velocity.is_zero_approx(), "Tracking loss safely releases without an invented throw.")
	# Add a representative layer-16 cabin wall and verify an actual body collision.
	var wall := StaticBody3D.new()
	wall.collision_layer = 16
	wall.collision_mask = 64
	wall.position = Vector3(0.7, 5, 0)
	var shape := CollisionShape3D.new()
	var block := BoxShape3D.new()
	block.size = Vector3(0.08, 3, 3)
	shape.shape = block
	wall.add_child(shape)
	stage.add_child(wall)
	body.place(Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)))
	await frames(3)
	body.linear_velocity = Vector3(0.6, 0, 0)
	var crossed_wall := false
	for frame in 100:
		await physics_frame
		crossed_wall = crossed_wall or body.global_position.x > 0.65
	check(not crossed_wall and body.global_position.x < 0.55, "Free prop physically collides with layer-16 structure.")
	check(body.linear_velocity.x < 0.05, "Structure collision changes the incoming drift velocity.")
	body.place(Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)))
	await frames(3)
	body.begin_hold("left", Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)))
	body.move_held(Transform3D(Basis.IDENTITY, Vector3(1.2, 5, 0)), 0.02)
	check(body.global_position.x < 0.55, "A held hand sweep cannot drag the notebook through cabin structure.")
	body.end_hold(false)
	body.place(Transform3D(Basis.IDENTITY, Vector3(0.49, 5, 0)))
	await frames(3)
	body.begin_hold("left", Transform3D(Basis.IDENTITY, Vector3(0.49, 5, 0)))
	body.move_held(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0.49, 5, 0)), 0.02)
	check(body.global_basis.x.dot(Vector3.RIGHT) > 0.999, "Pure hand rotation cannot turn the wide page through a cabin wall.")
	body.end_hold(false)
	var report := {"checks": checks, "failures": failures, "headsetTested": false}
	var file := FileAccess.open(ProjectSettings.globalize_path("res://../output/free-float-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Free float: %d checks, %d failures." % [checks, failures.size()])
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
