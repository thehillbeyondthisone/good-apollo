extends SceneTree
## Real-cabin procedure, water-feedback and notebook input regression.
var failures := 0
var checks := 0
var cabin: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func check_page() -> void:
	for label: Label in cabin.notebook.fields.values():
		check(label.get_line_count() * label.get_line_height() <= float(label.get_meta("page_height")), "Page text fits its printed section: " + label.text.left(60))

func set_control(id: String, desired: String) -> void:
	var definition: Dictionary = cabin.state_store.definitions[id]
	var index: int = definition.positions.find(desired)
	for attempt in definition.positions.size() + 1:
		var current: int = cabin.state_store.states[id]
		if current == index: return
		cabin._operate(id, 1 if index > current else -1, "notebook-test", true)

func _run() -> void:
	if not "--self-test" in OS.get_cmdline_user_args() or not "--systems-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	var notebook: Node3D = cabin.notebook
	check(notebook != null, "Actual cabin creates the procedure book.")
	for id: String in cabin.systems.readouts:
		var label: Label3D = cabin.systems.readouts[id]
		var binding = cabin.bindings[id]
		var artwork := binding.root.get_parent().get_node_or_null("Panel_" + str(binding.definition.panel) + "_artwork") as Node3D
		if artwork != null:
			var height := (label.global_position - artwork.global_position).dot(binding.root.global_basis.y.normalized())
			check(height > 0 and height < 0.0011, "Readout is flush with panel artwork: " + id)
	set_control("ecs_des_h2o", "CLOSE")
	set_control("ecs_asc_h2o", "CLOSE")
	set_control("water_dispenser_cap", "FITTED")
	cabin._operate("water_dispenser_trigger", 1, "notebook-test")
	cabin.mechanisms.refresh()
	check(cabin.mechanisms.water_drops.all(func(drop): return not drop.visible), "Closed supply and fitted cap produce no water beads.")
	check(cabin.mechanisms.control_value("water_dispenser_trigger").contains("CAP"), "Blocked dispenser identifies the missing prerequisite.")
	cabin._release_button("notebook-test")
	set_control("water_dispenser_pose", "FREE")
	cabin.mechanisms.refresh()
	notebook.refresh()
	check(notebook.current_page.target == "ecs_des_h2o", "Book directs crew to a water-feed valve.")
	set_control("ecs_des_h2o", "OPEN")
	cabin.mechanisms.refresh()
	notebook.refresh()
	check(notebook.current_page.target == "water_dispenser_cap", "Book follows real feed state to cap removal.")
	set_control("water_dispenser_cap", "REMOVED")
	cabin._operate("water_dispenser_trigger", 1, "notebook-test")
	cabin.mechanisms.refresh()
	notebook.refresh()
	check(cabin.mechanisms.water_drops.all(func(drop): return drop.visible), "Held trigger with an open path renders water at the moving dispenser.")
	check(notebook.guidance.water_observed and notebook.current_page.count == "05 / 05", "Notebook observes actual dispensing and requests shutoff.")
	cabin._release_button("notebook-test")
	cabin.mechanisms.refresh()
	notebook.refresh()
	check(cabin.mechanisms.water_drops.all(func(drop): return not drop.visible), "Releasing trigger immediately removes water feedback.")
	check(notebook.current_page.title == "Water checkout complete", "Book verifies shutoff after actual dispensing.")
	check(not cabin.mechanisms.get_snapshot().consumablesPhysics, "Water feedback does not invent consumable depletion.")

	cabin.systems.start_powerdown()
	for event_index in int(cabin.systems.powerdown_snapshot.eventCount):
		var limit := 150
		while not cabin.systems.powerdown_snapshot.pendingActions.is_empty() and limit > 0:
			limit -= 1
			notebook.refresh()
			check_page()
			check(not notebook.current_page.confirm and not notebook.current_page.target.is_empty(), "Pending power-down action supplies a target and gates confirmation.")
			var action: Dictionary = cabin.systems.powerdown_snapshot.pendingActions[0]
			var before: int = cabin.systems.powerdown_snapshot.currentIndex
			notebook.confirm()
			check(cabin.systems.powerdown_snapshot.currentIndex == before, "Book cannot skip an incomplete real procedure.")
			set_control(str(action.controlId), str(action.position))
		check(limit > 0, "Power-down pending controls can be completed.")
		notebook.refresh()
		check_page()
		check(notebook.current_page.confirm, "A completed real callout unlocks book confirmation.")
		notebook.confirm()
		check(cabin.systems.powerdown_snapshot.currentIndex == event_index + 1, "Book confirmation advances exactly one callout.")

	check(cabin.systems.start_co2(true), "CO2 chapter starts with the shared simulation.")
	var co2: Node = cabin.systems.co2
	while co2.stage < co2.install_count:
		notebook.refresh()
		check_page()
		check(notebook.current_page.target == co2.target() and not notebook.current_page.action.is_empty(), "CO2 book follows the next actual part or control.")
		var step: Dictionary = co2.steps[co2.stage]
		if step.has("position"):
			set_control(step.target, step.position)
			if co2.steps[mini(co2.stage, co2.install_count - 1)] == step: co2.verify_position()
		else:
			co2.click(step.item)
			notebook.refresh()
			check(notebook.current_page.target == step.target, "Selecting an assembly part retargets its destination in the book.")
			co2.click(step.target)
	co2.cancel()
	cabin.systems.correction.start()
	for phase in range(1, 12):
		cabin.systems.correction.phase = phase
		notebook.refresh()
		check_page()
		check(not notebook.current_page.action.is_empty() and not notebook.current_page.verify.is_empty(), "Every correction phase has an instruction and verification.")
	cabin.systems.correction.cancel()
	cabin.systems.odyssey.start()
	for index in cabin.systems.odyssey.steps.size():
		cabin.systems.odyssey.stage = index
		notebook.refresh()
		check_page()
		check(not notebook.current_page.action.is_empty() and not notebook.current_page.location.is_empty(), "Every Odyssey action has a location and instruction.")
	cabin.systems.odyssey.cancel()

	# Check the same world-plane hit path used by tracked controllers, without XR.
	notebook.book.show()
	notebook.book.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, -0.7))
	notebook.expanded = true
	notebook.refresh()
	var button: Button = notebook.stow_button
	var uv: Vector2 = button.get_rect().get_center() / Vector2(notebook.SIZE)
	var target: Vector3 = notebook.book.to_global(Vector3((uv.x - 0.5) * notebook.BOOK_SIZE.x, (0.5 - uv.y) * notebook.BOOK_SIZE.y, 0))
	var eye := Vector3(0, 1, 0)
	var ray := eye.direction_to(target)
	notebook.sample_pointer("left", eye, ray, true, true)
	notebook.sample_pointer("left", eye, ray, false, true)
	check(notebook.expanded, "Trigger held on entry cannot click the book.")
	notebook.sample_pointer("left", eye, ray, true, true)
	notebook.sample_pointer("left", eye, ray, true, false)
	check(notebook.expanded, "Lost tracking cancels a pending notebook click.")
	notebook.sample_pointer("left", eye, ray, false, true)
	notebook.sample_pointer("left", eye, ray, true, true)
	notebook.sample_pointer("left", eye, ray, false, true)
	check(not notebook.expanded, "A fresh trigger click stows the physical notebook.")
	var report := {"checks": checks, "failures": failures, "headsetTested": false}
	var file := FileAccess.open(cabin.repository_path("output/flight-notebook-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Flight notebook: %d checks, %d failures." % [checks, failures])
	cabin.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
