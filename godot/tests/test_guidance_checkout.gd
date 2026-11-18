extends SceneTree
## Real-cabin water completion must be explicit and cannot skip blocked flow.
const Guidance = preload("res://scripts/procedure_guidance.gd")
var checks := 0
var failures := 0
var cabin: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func set_control(id: String, desired: String) -> void:
	var positions: Array = cabin.state_store.definitions[id].positions
	for attempt in positions.size() + 1:
		var index: int = cabin.state_store.states[id]
		if str(positions[index]) == desired: return
		cabin._operate(id, 1 if positions.find(desired) > index else -1, "checkout-test", true)

func _run() -> void:
	if not "--self-test" in OS.get_cmdline_user_args() or not "--systems-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	var guidance = Guidance.new()
	check(not guidance.action(cabin), "An unfinished checkout has no completion action.")
	check(not cabin.systems.powerdown_snapshot.get("active", false), "Rejected checkout completion does not start a mission.")
	set_control("water_dispenser_pose", "FREE")
	set_control("water_dispenser_cap", "REMOVED")
	set_control("ecs_des_h2o", "CLOSE")
	set_control("ecs_asc_h2o", "CLOSE")
	cabin._operate("water_dispenser_trigger", 1, "checkout-test")
	cabin.mechanisms.refresh()
	var page: Dictionary = guidance.page(cabin)
	check(not page.confirm and not guidance.water_observed, "Holding the trigger with no supply cannot complete checkout.")
	check(not guidance.action(cabin), "A blocked dispenser still cannot be acknowledged.")
	set_control("ecs_des_h2o", "OPEN")
	cabin.mechanisms.refresh()
	page = guidance.page(cabin)
	check(guidance.water_observed and not page.confirm, "Observed flow still requires actual trigger release.")
	cabin._release_button("checkout-test")
	cabin.mechanisms.refresh()
	page = guidance.page(cabin)
	check(page.confirm and page.action_id == "water_done" and page.button_label == "FINISH WATER CHECK", "Observed flow and shutoff expose an explicit completion button.")
	check(guidance.action(cabin), "The water completion action is handled by guidance.")
	check(not cabin.systems.powerdown_snapshot.get("active", false), "Acknowledging water checkout does not silently start power-down.")
	page = guidance.page(cabin)
	check(page.confirm and page.action_id == "start_powerdown", "The completed checkout offers the next procedure explicitly.")
	check(guidance.action(cabin) and cabin.systems.powerdown_snapshot.get("active", false), "A separate start action begins the real power-down checklist.")
	check(not guidance.action(cabin), "Generic mission confirmation stays with the real backend.")
	print("Guidance checkout: %d checks, %d failures." % [checks, failures])
	cabin.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
