extends SceneTree
## Exercises the actual notebook surfaces, manual pose and controller-tip path.
var failures := 0
var checks := 0
var cabin: Node3D
var notebook: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func point_for(button: Button, z := 0.0) -> Vector3:
	var uv := button.get_rect().get_center() / Vector2(notebook.SIZE)
	return notebook.book.to_global(Vector3((uv.x - 0.5) * notebook.BOOK_SIZE.x, (0.5 - uv.y) * notebook.BOOK_SIZE.y, z))

func click_ray(button: Button) -> void:
	var origin: Vector3 = notebook.book.global_position + notebook.book.global_basis.z * 0.5
	var ray: Vector3 = origin.direction_to(point_for(button))
	notebook.sample_pointer("right", origin, ray, false, true)
	notebook.sample_pointer("right", origin, ray, true, true)
	notebook.sample_pointer("right", origin, ray, false, true)

func _run() -> void:
	if not "--self-test" in OS.get_cmdline_user_args() or not "--systems-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	notebook = cabin.notebook
	notebook.onboarding = load("res://scripts/cabin_onboarding.gd").new()
	cabin.xr_active = true
	notebook.recall()
	notebook._process(0.016)
	notebook.refresh()
	var recalled: Vector3 = notebook.body.global_position
	for frame in 4: await physics_frame
	check(notebook.body.global_position.distance_to(recalled) < 0.005, "A newly spawned recalled book retains its pose across physics synchronization.")
	check(notebook.confirm_button.visible and not notebook.confirm_button.disabled and notebook.confirm_button.text == "NEXT PAGE", "Onboarding starts with a real enabled Next Page button.")
	click_ray(notebook.confirm_button)
	check(notebook.onboarding.stage == 1, "The real controller ray clicks the real onboarding button.")
	var near_point: Vector3 = point_for(notebook.confirm_button, 0.04)
	var press_point: Vector3 = point_for(notebook.confirm_button, 0.003)
	notebook.sample_touch("right", near_point, true)
	check(notebook.sample_touch("right", press_point, true), "Controller fingertip crossing presses a book button.")
	notebook.sample_touch("right", near_point, true)
	check(notebook.onboarding.stage == 2, "Withdrawing the touch tip releases and advances the page.")

	var fixed: Transform3D = notebook.body.global_transform
	cabin.desktop_camera.rotate_y(0.7)
	cabin.desktop_camera.position += Vector3(0.2, 0.1, 0)
	notebook._process(0.1)
	check(notebook.body.global_transform.is_equal_approx(fixed), "Head movement does not reposition or resize the book.")
	click_ray(notebook.confirm_button)
	check(notebook.body.global_transform.is_equal_approx(fixed), "A new instruction does not reposition the book.")
	for index in range(6):
		notebook.onboarding.stage = index
		notebook.refresh()
		for label: Label in notebook.fields.values():
			check(label.get_line_count() * label.get_line_height() <= float(label.get_meta("page_height")), "Onboarding text fits its section.")

	var hand := Transform3D(Basis.IDENTITY, notebook.book.global_position + notebook.book.global_basis.z * 0.04)
	notebook.sample_hand("left", hand, true, true, 0.016)
	check(not notebook.is_held_by("left"), "Grip already held on entry cannot unexpectedly grab.")
	notebook.sample_hand("left", hand, false, true, 0.016)
	check(notebook.sample_hand("left", hand, true, true, 0.016) and notebook.is_held_by("left"), "Fresh nearby grip acquires the physical book.")
	var desired := hand
	desired.origin += Vector3(0.015, 0.006, 0)
	notebook.sample_hand("left", desired, true, true, 0.05)
	check(not notebook.body.global_transform.is_equal_approx(fixed), "Held book follows hand motion.")
	notebook.sample_hand("left", desired, false, true, 0.016)
	check(not notebook.is_held_by("left") and notebook.body.linear_velocity.length() > 0.02, "Released notebook inherits hand momentum.")
	notebook.recall()
	check(notebook.body.linear_velocity.is_zero_approx(), "Explicit recall resets drift.")
	notebook.sample_hand("left", hand, false, true, 0.016)
	hand.origin = notebook.book.global_position
	notebook.sample_hand("left", hand, true, true, 0.016)
	notebook.sample_hand("left", hand, true, false, 0.016)
	check(not notebook.is_held_by("left") and notebook.body.linear_velocity.is_zero_approx(), "Tracking loss releases the notebook without a false throw.")

	# Squeeze before arriving, broad edge acquisition, and short aim assistance.
	notebook.recall()
	var approach: Transform3D = notebook.book.global_transform
	approach.origin = notebook.book.to_global(Vector3(0, 0, 0.30))
	notebook.sample_hand("approach", approach, false, true, 0.016)
	check(not notebook.sample_hand("approach", approach, true, true, 0.016), "Squeezing outside reach does not acquire an unaimed book.")
	approach.origin = notebook.book.to_global(Vector3(notebook.BOOK_SIZE.x * 0.5 + 0.09, 0, 0.07))
	check(notebook.sample_hand("approach", approach, true, true, 0.016), "An already squeezed hand acquires within the forgiving edge reach.")
	notebook.release_hands(false)
	var aimed: Transform3D = notebook.book.global_transform
	aimed.origin = notebook.book.to_global(Vector3(0, 0, 0.80))
	notebook.sample_hand("aim", aimed, false, true, 0.016, aimed)
	check(notebook.sample_hand("aim", aimed, true, true, 0.016, aimed), "Aim plus grip acquires a book beyond direct hand reach.")
	var second: Transform3D = notebook.book.global_transform
	notebook.sample_hand("second", second, false, true, 0.016)
	check(not notebook.sample_hand("second", second, true, true, 0.016) and notebook.is_held_by("aim"), "A second hand cannot steal the held book.")
	notebook.release_hands(false)
	aimed.origin = notebook.book.to_global(Vector3(0, 0, 1.30))
	check(not notebook.can_grab(aimed, aimed), "Aim assistance has a bounded 1.2 m reach.")
	aimed.origin = notebook.book.to_global(Vector3(0.30, 0, 0.80))
	check(not notebook.can_grab(aimed, aimed), "An off-target aim does not grab the notebook.")
	aimed.origin = notebook.book.to_global(Vector3(0, 0, 0.80))
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 16
	var barrier := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.50, 0.60, 0.02)
	barrier.shape = box
	blocker.add_child(barrier)
	cabin.add_child(blocker)
	blocker.global_transform = notebook.book.global_transform
	blocker.global_position = notebook.book.to_global(Vector3(0, 0, 0.40))
	await physics_frame
	check(not notebook.can_grab(aimed, aimed), "Aim assistance cannot grab through cabin structure.")
	blocker.queue_free()
	await physics_frame
	notebook.sample_hand("aim", aimed, true, false, 0.016, aimed)
	check(not notebook.sample_hand("aim", aimed, true, true, 0.016, aimed), "Held grip after tracking loss must be released before reacquiring.")
	notebook.onboarding.active = false
	notebook.refresh()
	check(not notebook.confirm_button.visible and notebook.awaiting_label.visible, "Unfinished physical actions show a status strip, not a fake button.")
	var book_pose: Transform3D = notebook.body.global_transform
	notebook.highlighter._reveal_seconds = 0.0
	click_ray(notebook.find_button)
	check(notebook.highlighter._reveal_seconds > 7.9, "The actual FIND button reveals guidance through the controller-ray click path.")
	check(notebook.body.global_transform.is_equal_approx(book_pose), "Finding a target leaves the physical notebook where the crew placed it.")
	var report := {"checks": checks, "failures": failures, "headsetTested": false}
	var file := FileAccess.open(cabin.repository_path("output/notebook-hands-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Notebook hands: %d checks, %d failures." % [checks, failures])
	cabin.xr_active = false
	cabin.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
