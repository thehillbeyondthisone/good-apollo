extends SceneTree
## Actual-control hover feedback and controller shortcut regression without XR.

class SessionDouble:
	extends "res://scripts/xr_session.gd"
	func _tracked(_controller: XRController3D) -> bool:
		return true

class NotebookDouble:
	extends Node3D
	var recalls := 0
	var reveals := 0
	var releases := 0
	var was_throw := true
	func recall() -> void: recalls += 1
	func reveal_target() -> void: reveals += 1
	func release_hands(throw_on_release := false) -> void:
		releases += 1
		was_throw = throw_on_release
	func cancel_pointer() -> void: pass
	func observe(_event: String) -> void: pass

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	if not "--self-test" in OS.get_cmdline_user_args() or not "--systems-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	var cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	var session := SessionDouble.new()
	cabin.add_child(session)
	session.cabin = cabin
	session.router.setup(cabin)
	session._ray_material = session._material(Color.WHITE)
	session._target_material = session._material(Color("#eac28b"))
	var left := XRController3D.new()
	left.name = "left_hand"
	var right := XRController3D.new()
	right.name = "right_hand"
	for controller: XRController3D in [left, right]:
		session.add_child(controller)
		session.controllers.append(controller)
		session._create_pointer(controller)
		check(controller.find_children("*", "Label3D", true, false).is_empty(), "No status label is attached to a controller.")
	var hover: Node3D = session.hover_status.right_hand
	hover.present("p3_flood_ovhd_fwd", false)
	check(not hover.visible, "Untracked hover has no placard.")
	hover.present("p3_flood_ovhd_fwd", true)
	check(hover.visible and hover.label.text.contains(cabin.state_store.definitions.p3_flood_ovhd_fwd.label), "Hovered real control displays its name beside the control.")
	check(hover.label.text.contains(cabin.state_store.position_name("p3_flood_ovhd_fwd")), "Hover displays the actual current control position.")
	var center: Vector3 = cabin.bindings.p3_flood_ovhd_fwd.target_global_position()
	check(hover.global_position.distance_to(center) < 0.2, "Hover is anchored near the cabin control rather than the controller.")
	check(not hover.label.no_depth_test, "Hover labels respect cabin depth.")
	cabin._set_axis("ttca_cdr_throttle", 0.75, "hover-test")
	hover.present("ttca_cdr_throttle", true)
	check(hover.label.text.contains(" / "), "Analog control hover includes its continuous value.")
	cabin.state_store.set_position("water_dispenser_cap", 0)
	cabin._operate("water_dispenser_trigger", 1, "hover-water")
	cabin.mechanisms.refresh()
	hover.present("water_dispenser_trigger", true)
	check(hover.label.text.contains("CAP"), "Hover includes live mechanism feedback, including blocked water prerequisites.")
	cabin._release_button("hover-water")
	hover.present("", true)
	check(not hover.visible and hover.target_id.is_empty(), "Leaving a target immediately removes the placard.")
	session.focus = {"right_hand": "p3_flood_ovhd_fwd"}
	session._update_pointer(left, true, "p3_flood_ovhd_fwd", false)
	check(not session.hover_status.left_hand.visible, "Two hands targeting one control do not duplicate the status placard.")

	var actual_book: Node3D = cabin.notebook
	actual_book.set_process(false)
	var notebook := NotebookDouble.new()
	cabin.add_child(notebook)
	cabin.notebook = notebook
	var before: String = cabin.systems.electrical.call("SaveStateJson")
	session._button_pressed("ax_button", left)
	session._button_pressed("ax_button", right)
	check(notebook.recalls == 1 and notebook.reveals == 1, "X recalls the notebook and A reveals the procedure target.")
	check(cabin.systems.electrical.call("SaveStateJson") == before, "Controller shortcuts do not apply an electrical checkout preset.")
	session.release_for_menu()
	check(notebook.releases == 1 and not notebook.was_throw, "Focus/menu handoff releases the notebook without a throw.")
	check(not session.hover_status.right_hand.visible, "Focus/menu handoff hides hover status.")
	cabin.notebook = actual_book
	session.cabin = null
	cabin.queue_free()
	await process_frame
	print("XR feedback: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
