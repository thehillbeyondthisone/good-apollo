extends SceneTree
## Run with --headless --script res://tests/test_flight_interface.gd -- --self-test --systems-test.

const FlightInterface = preload("res://scripts/flight_interface.gd")

var _failures := 0
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, detail: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(detail)

func _run() -> void:
	if not "--self-test" in OS.get_cmdline_user_args() or not "--systems-test" in OS.get_cmdline_user_args():
		push_error("Supply --self-test --systems-test to use an isolated cabin.")
		quit(2)
		return
	var cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	if cabin.systems == null or cabin.systems.session_clock == null:
		push_error("The flight interface test requires the built, stepped cabin.")
		quit(2)
		return
	var flight := FlightInterface.new()
	cabin.add_child(flight)
	cabin.flight_interface = flight
	flight.setup(cabin)
	cabin._show_flight_menu("main")
	await process_frame
	_check(paused and not cabin.hud.visible, "Main menu gates simulation and the cabin HUD.")
	_press(KEY_ENTER)
	await process_frame
	_check(not paused and cabin.hud.visible, "Keyboard selects Enter cabin.")

	var clock = cabin.systems.session_clock
	var start: int = clock.completed_ns
	_press(KEY_ESCAPE)
	for frame in 3:
		await physics_frame
	_check(paused and flight.page == "pause" and clock.completed_ns == start, "Escape opens pause and stops stepping.")
	clock.paused = true
	cabin.handle_flight_action("toggle_hud")
	_press(KEY_ESCAPE)
	await process_frame
	_check(not paused and clock.paused and not cabin.title_label.is_visible_in_tree(), "Resume preserves the clock's independent pause and HUD toggle.")
	clock.paused = false

	cabin._show_flight_menu("pause")
	flight.show_page("pause", true, cabin._flight_menu_status(""))
	var button := flight.menu.find_child("resume", true, false) as Button
	var uv := button.get_global_rect().get_center() / Vector2(FlightInterface.MENU_SIZE)
	var target := flight._panel.to_global(Vector3((uv.x - 0.5) * FlightInterface.PANEL_SIZE.x, (0.5 - uv.y) * FlightInterface.PANEL_SIZE.y, 0.0))
	var wrist: Vector3 = cabin.active_camera.global_position - Vector3(0.18, 0.36, 0.18)
	var ray := wrist.direction_to(target)
	var hand := "left_hand"
	_check(flight.sample_xr_pointer(hand, wrist, ray, true, true) > 0, "Controller ray intersects the rendered button plane.")
	flight.sample_xr_pointer(hand, wrist, ray, false, true)
	await process_frame
	_check(paused, "Trigger held when the menu opens cannot select.")
	flight.sample_xr_pointer(hand, wrist, ray, true, true)
	flight.sample_xr_pointer(hand, wrist, ray, true, false)
	flight.sample_xr_pointer(hand, wrist, ray, false, true)
	await process_frame
	_check(paused, "Tracking loss cancels a pending click.")
	flight.sample_xr_pointer(hand, wrist, ray, true, true)
	flight.sample_xr_pointer(hand, wrist, ray, false, true)
	await process_frame
	_check(not paused and not cabin.flight_menu_is_open(), "A fresh XR trigger click selects Resume.")

	_press(KEY_ESCAPE)
	cabin.handle_flight_action("powerdown")
	_check(cabin.systems.powerdown_snapshot.active and not paused, "Selecting power-down starts the actual checklist.")
	_press(KEY_ESCAPE)
	_check(flight.menu.find_child("confirm", true, false) is Button, "An active checklist adds the confirmation action.")
	cabin.handle_flight_action("confirm")
	_check(not paused, "Checklist confirmation returns to the cabin.")
	cabin.xr_active = true
	cabin.xr_session = load("res://scripts/xr_session.gd").new()
	cabin.add_child(cabin.xr_session)
	cabin.xr_session.cabin = cabin
	cabin.xr_session.router.setup(cabin)
	cabin.flight_hud.create_xr_status(cabin.active_camera)
	cabin._show_flight_menu("pause")
	cabin.handle_flight_action("toggle_hud")
	_check(cabin._hud_enabled and cabin.xr_session.help_visible, "Floating-info toggle enables the XR status window.")
	cabin.handle_flight_action("toggle_hud")
	_check(not cabin._hud_enabled and not cabin.xr_session.help_visible, "Floating-info toggle independently hides the XR status window.")
	cabin.handle_flight_action("notebook")
	cabin.notebook._process(0.016)
	_check(cabin.notebook.book.visible and not cabin._hud_enabled, "Menu notebook recall leaves floating info hidden and the book usable.")
	cabin.notebook.recall()
	_check(not cabin._hud_enabled, "Controller notebook recall preserves the hidden-info choice.")
	cabin.flight_hud.present_xr_status("Tracking", "", "", cabin.xr_session.help_visible)
	_check(not cabin.flight_hud._xr_mesh.visible, "Hidden floating info actually hides the headset mesh.")
	cabin.xr_active = false
	cabin.queue_free()
	await process_frame
	print("Flight interface: %d checks, %d failures." % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _press(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
