extends SceneTree
## Exercises the same controller state machine and cabin methods as a live rig.
## Synthetic samples are deliberately reported as software-only evidence.

const Router = preload("res://scripts/xr_input.gd")
const Session = preload("res://scripts/xr_session.gd")
const Binding = preload("res://scripts/control_binding.gd")
var checks := 0
var failures := PackedStringArray()
var cabin: Node
var router = Router.new()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func sample(hand: String, target: String, down: bool, reverse: bool = false, stick: Vector2 = Vector2.ZERO, active: bool = true) -> void:
	router.sample(hand, {"active": active, "trigger": down, "reverse": reverse, "target": target, "stick": stick}, 0.016)

func _run() -> void:
	var app_name := str(ProjectSettings.get_setting("application/config/name", ""))
	var safe_name := not app_name.is_empty() and app_name == app_name.strip_edges() and not app_name.ends_with(".")
	for invalid: String in ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]:
		if app_name.contains(invalid): safe_name = false
	check(safe_name, "Application name is safe for SteamVR-generated Windows binding filenames")
	# Use the actual cabin methods with a small inventory. Asset coverage has its
	# own full integration suite; these tests isolate controller edge sequences.
	cabin = load("res://scripts/main.gd").new()
	var fixture := [
		{"id":"toggle", "type":"toggle", "positions":["OFF","ON"], "default":"OFF"},
		{"id":"button", "type":"pushbutton", "positions":["RELEASED","PRESSED"], "default":"RELEASED"},
		{"id":"button2", "type":"pushbutton", "positions":["RELEASED","PRESSED"], "default":"RELEASED"},
		{"id":"rotary", "type":"rotary", "positions":["A","B","C","D"], "default":"A"},
		{"id":"limited_rotary", "type":"rotary", "positions":["OFF","TEST","OFF"], "default":"OFF", "mechanism":{"wrap":false,"offAtBothEnds":true}},
		{"id":"read_only", "type":"indicator", "positions":["OFF","ON"], "default":"OFF", "interactive":false},
		{"id":"axis", "type":"axis", "positions":["NEGATIVE","CENTER","POSITIVE"], "default":"CENTER", "axis":{"axis":"pitch"}},
		{"id":"throttle", "type":"axis", "positions":["MIN","MID","MAX"], "default":"MIN", "momentary":false, "axis":{"axis":"throttle"}},
		{"id":"pitch_knob", "type":"rotary", "positions":["-75","0","90","225"], "default":"0", "analog":{"min":-75,"max":225,"unit":"deg"}},
		{"id":"brightness", "type":"thumbwheel", "positions":["MIN","MID","MAX"], "default":"MIN", "analog":{"min":0,"max":1,"unit":"normalized"}},
		{"id":"latch", "type":"pushbutton", "positions":["RELEASED","LATCHED"], "default":"RELEASED", "momentary":false, "mechanism":{"resetBy":["button2"]}},
		{"id":"guard", "type":"guard", "positions":["CLOSED","OPEN"], "default":"CLOSED"},
		{"id":"protected", "type":"pushbutton", "positions":["RELEASED","PRESSED"], "default":"RELEASED", "mechanism":{"guardId":"guard"}},
		{"id":"locked", "type":"toggle", "positions":["OFF","ON"], "default":"OFF", "leverLock":true},
		{"id":"joystick", "type":"joystick", "positions":["CENTER","UP","DOWN","LEFT","RIGHT"], "default":"CENTER"},
	]
	check(cabin.state_store.configure(fixture).is_empty(), "Fixture definitions configure")
	check(not cabin.state_store.actuate("limited_rotary", -1) and cabin.state_store.states.limited_rotary == 0, "Limited rotary cannot reverse past first endpoint")
	check(cabin.state_store.actuate("limited_rotary", 1) and cabin.state_store.actuate("limited_rotary", 1) and cabin.state_store.states.limited_rotary == 2, "Limited rotary reaches distinct second OFF endpoint")
	check(not cabin.state_store.actuate("limited_rotary", 1) and cabin.state_store.states.limited_rotary == 2, "Limited rotary cannot wrap past final endpoint")
	check(cabin.state_store.actuate("limited_rotary", -1) and cabin.state_store.position_name("limited_rotary") == "TEST", "Limited rotary reverses away from final endpoint")
	for id: String in ["throttle", "latch", "pitch_knob", "brightness"]:
		var visual := Node3D.new()
		visual.name = id
		var actuator := Node3D.new()
		actuator.name = "actuator"
		visual.add_child(actuator)
		cabin.add_child(visual)
		var binding = Binding.new()
		binding.setup(cabin.state_store.definitions[id], visual)
		cabin.bindings[id] = binding
	router.setup(cabin)
	sample("right","rotary",true,false,Vector2(1,0))
	check(cabin.state_store.position_name("rotary") == "B", "Selecting with deflected stick advances only one detent")
	sample("right","rotary",true,false,Vector2(1,0))
	check(cabin.state_store.position_name("rotary") == "B", "Held selection waits for repeat delay before another detent")
	sample("right","rotary",false)
	cabin.state_store.set_position("rotary",0)
	sample("right", "toggle", true)
	check(cabin.state_store.position_name("toggle") == "ON", "Trigger advances toggle")
	sample("right", "toggle", true)
	check(cabin.state_store.position_name("toggle") == "ON", "Held trigger does not repeatedly advance")
	sample("right", "toggle", false)
	sample("right", "rotary", true, true)
	check(cabin.state_store.position_name("rotary") == "D", "Grip plus trigger reverses")
	check(router.reverse_operations == 1, "Reverse action recorded")
	sample("right", "rotary", true, false, Vector2(-1,0))
	check(cabin.state_store.position_name("rotary") == "C", "Held rotary thumbstick steps reverse")
	sample("right", "rotary", false)
	sample("left", "button", true)
	check(cabin.state_store.position_name("button") == "PRESSED", "Momentary pressed through cabin path")
	sample("left", "toggle", true)
	check(cabin.state_store.position_name("button") == "PRESSED", "Moving hover retains original held button")
	sample("left", "toggle", false)
	check(cabin.state_store.position_name("button") == "RELEASED", "Release targets held button despite hover change")
	sample("left", "button", true)
	sample("right", "button2", true)
	sample("left", "", true, false, Vector2.ZERO, false)
	check(cabin.state_store.position_name("button") == "RELEASED", "Tracking loss releases held input")
	check(cabin.state_store.position_name("button2") == "PRESSED", "One tracking loss preserves other hand")
	check(router.tracking_releases == 1, "Tracking-loss release counted")
	router.release_all()
	check(cabin.held_button_ids.is_empty(), "Focus-loss cleanup removes every held source")
	check(cabin.state_store.position_name("button2") == "RELEASED", "Focus-loss cleanup releases other hand")
	sample("right", "button2", true)
	check(cabin.state_store.position_name("button2") == "RELEASED", "Held trigger after focus return waits for release before rearming")
	sample("left", "button", false)
	sample("right", "button2", false)
	sample("left", "button", true)
	sample("right", "button", true)
	sample("left", "button", false)
	check(cabin.state_store.position_name("button") == "PRESSED", "Two hands on one button preserve remaining press")
	sample("right", "button", false)
	check(cabin.state_store.position_name("button") == "RELEASED", "Last source releases shared momentary")
	sample("right", "read_only", true)
	check(cabin.state_store.position_name("read_only") == "OFF", "Indicator remains read-only")
	sample("right", "", false)
	sample("right", "protected", true)
	check(cabin.state_store.position_name("protected") == "RELEASED", "Closed guard blocks trigger")
	sample("right", "protected", false)
	sample("right", "guard", true)
	sample("right", "guard", false)
	sample("right", "protected", true)
	check(cabin.state_store.position_name("protected") == "PRESSED", "Independent open guard permits trigger")
	sample("right", "protected", false)
	sample("right", "locked", true)
	check(cabin.state_store.position_name("locked") == "OFF", "Locked lever rejects ungripped action")
	sample("right", "locked", false)
	sample("right", "locked", true, true)
	check(cabin.state_store.position_name("locked") == "ON", "Grip unlocks lever")
	sample("right", "locked", false)
	sample("right", "axis", true, false, Vector2(0,0.67))
	check(is_equal_approx(cabin.state_store.axis_value("axis"), 0.67), "Continuous thumbstick reaches normalized axis")
	check(cabin.held_button_ids.has("xr:right"), "Axis held source registered")
	sample("right", "toggle", true, false, Vector2(0,-0.4))
	check(is_equal_approx(cabin.state_store.axis_value("axis"), -0.4), "Held axis remains locked while aim moves")
	sample("right", "toggle", false)
	check(is_zero_approx(cabin.state_store.axis_value("axis")), "Released axis recenters")
	sample("right", "throttle", true)
	check(is_equal_approx(cabin.state_store.axis_value("throttle"), -1.0), "Selecting latched axis does not jump to midpoint")
	sample("right", "throttle", true, false, Vector2(0,1))
	var throttle_value: float = cabin.state_store.axis_value("throttle")
	check(throttle_value > -1.0 and throttle_value < -0.9, "Thumbstick changes latched axis continuously")
	sample("right", "throttle", false)
	check(is_equal_approx(cabin.state_store.axis_value("throttle"), throttle_value), "Latched axis retains setting after release")
	cabin.state_store.set_axis("throttle", 0.42)
	cabin._apply_position("throttle")
	var continuous_pose: Transform3D = cabin.bindings["throttle"].actuator.transform
	var saved: Dictionary = cabin.state_store.get_save_payload()
	cabin.state_store.set_axis("throttle", -0.8)
	cabin._apply_position("throttle")
	check(cabin.state_store.apply_save_payload(saved).is_empty(), "Latched analog payload restores")
	cabin._apply_position("throttle")
	check(cabin.bindings["throttle"].actuator.transform.is_equal_approx(continuous_pose), "Restored analog actuator keeps continuous value instead of quantized detent")
	cabin._operate("latch", 1, "fixture")
	check(not cabin.bindings["latch"].actuator.transform.is_equal_approx(cabin.bindings["latch"].initial_actuator_transform), "Latched button moves its actuator")
	cabin._operate("button2", 1, "fixture_stop")
	check(cabin.state_store.position_name("latch") == "RELEASED", "Stop control resets linked latch")
	check(cabin.bindings["latch"].actuator.transform.is_equal_approx(cabin.bindings["latch"].initial_actuator_transform), "Linked latch reset updates the visual actuator")
	cabin._release_button("fixture_stop")
	check(cabin.state_store.is_analog("pitch_knob") and cabin.state_store.is_analog("brightness"), "Existing knob and thumbwheel types expose continuous metadata")
	check(is_equal_approx(cabin.state_store.axis_value("pitch_knob"), -0.5), "Uneven numeric samples preserve source zero-degree default")
	check(cabin.state_store.position_for_normalized("pitch_knob", 0.1) == 2, "Source ninety-degree sample maps to actual physical range")
	cabin.state_store.set_axis("pitch_knob", 0.34)
	cabin._apply_position("pitch_knob")
	var knob_pose: Transform3D = cabin.bindings["pitch_knob"].actuator.transform
	var knob_save: Dictionary = cabin.state_store.get_save_payload()
	cabin.state_store.set_position("pitch_knob", 0)
	cabin._apply_position("pitch_knob")
	check(cabin.state_store.apply_save_payload(knob_save).is_empty(), "Continuous rotary payload restores")
	cabin._apply_position("pitch_knob")
	check(is_equal_approx(cabin.state_store.axis_value("pitch_knob"), 0.34) and cabin.bindings["pitch_knob"].actuator.transform.is_equal_approx(knob_pose), "Rotary value and visual restore between source samples")
	var states_before: Dictionary = cabin.state_store.states.duplicate()
	var axes_before: Dictionary = cabin.state_store.axis_values.duplicate()
	var bad_save: Dictionary = knob_save.duplicate(true)
	bad_save.axes.pitch_knob = 1.01
	check(not cabin.state_store.apply_save_payload(bad_save).is_empty(), "Out-of-range continuous value rejected")
	check(cabin.state_store.states == states_before and cabin.state_store.axis_values == axes_before, "Invalid continuous value leaves every live state unchanged")
	bad_save = knob_save.duplicate(true)
	bad_save.states.pitch_knob = 0
	check(not cabin.state_store.apply_save_payload(bad_save).is_empty(), "Continuous value and sampled label disagreement rejected")
	check(not cabin.state_store.set_axis("brightness", NAN) and not cabin.state_store.set_axis("brightness", INF), "Non-finite knob inputs rejected")
	sample("right", "brightness", true, false, Vector2(0,1))
	var brightness_value: float = cabin.state_store.axis_value("brightness")
	check(brightness_value > -1.0 and brightness_value < -0.9, "XR stick continuously adjusts existing thumbwheel")
	sample("right", "brightness", false)
	check(is_equal_approx(cabin.state_store.axis_value("brightness"), brightness_value), "Continuous thumbwheel remains latched on trigger release")
	cabin.focused_id = "brightness"
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	cabin._unhandled_input(wheel)
	check(is_equal_approx(cabin.state_store.axis_value("brightness"),clampf(brightness_value+0.1,-1.0,1.0)), "Desktop wheel adjusts continuous analog value")
	check(not cabin.held_button_ids.has("mouse-wheel"), "Desktop wheel leaves no held input source")
	sample("right", "joystick", true, false, Vector2(-1,0))
	check(cabin.state_store.position_name("joystick") == "LEFT", "Stick steers held slew joystick")
	sample("right", "joystick", false)
	check(cabin.state_store.position_name("joystick") == "CENTER", "Slew joystick releases to center")
	var session = Session.new()
	session.cabin = cabin
	session.router.setup(cabin)
	session.focused = true
	var head_pose := XRPose.new()
	head_pose.has_tracking_data = true
	head_pose.tracking_confidence = XRPose.XR_TRACKING_CONFIDENCE_HIGH
	check(session._valid_head_pose(head_pose), "Fresh head pose authorizes sampling without interface-wide status")
	head_pose.has_tracking_data = false
	check(not session._valid_head_pose(head_pose), "Stale head pose cannot authorize sampling")
	head_pose.has_tracking_data = true
	head_pose.tracking_confidence = XRPose.XR_TRACKING_CONFIDENCE_NONE
	check(not session._valid_head_pose(head_pose), "Head pose without tracking confidence is rejected")
	head_pose.tracking_confidence = XRPose.XR_TRACKING_CONFIDENCE_HIGH
	check(not session._valid_head_pose(head_pose, true, false), "Supported absent-user status pauses sampling")
	check(session._valid_head_pose(head_pose, false, false), "Unsupported user-presence extension cannot discard valid head pose")
	session.focused = false
	check(not session._valid_head_pose(head_pose), "Unfocused session cannot authorize head sampling")
	var report: Dictionary = session.build_report()
	check(report.result == "UNAVAILABLE" and not report.gatePassed, "Uninitialized session cannot report headset pass")
	check(not report.headsetPoseObserved and report.frameTiming.sampleFrames == 0, "Synthetic tests produce no headset measurements")
	session.cabin = null
	session.free()
	var target: String = cabin.repository_path("reference/xr-input-tests.json")
	var file := FileAccess.open(target, FileAccess.WRITE)
	var result := {"schemaVersion":1, "result":"PASS" if failures.is_empty() else "FAIL", "checks":checks, "failures":Array(failures), "headsetTested":false, "kind":"Synthetic controller actions through the shared live interaction router", "note":"Physical reach, legibility, comfort and compositor frame timing are not established by these tests."}
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print(JSON.stringify(result))
	cabin.free()
	quit(0 if failures.is_empty() else 1)
