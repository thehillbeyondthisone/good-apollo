extends Node
## Flight Day 4, from Kerwin's read-up through the first two CM cartridge installations.

const Props = preload("res://scripts/co2_adapter_props.gd")
const Radio = preload("res://scripts/co2_radio.gd")
const GAUGE := "p2_part_press_co2"
const INITIAL_PRESSURE := 4.5
const RESULT_GET := "094:33:21"
const RESULT_DISPLAY_THRESHOLD := 0.25
const PATH_CONTROLS := {
	"ecs_suit_gas_diverter": "PULL-EGRESS", "ecs_cabin_gas_return": "EGRESS",
	"ecs_suit_circuit_relief": "CLOSE", "ecs_co2_canister_sel": "SEC",
	"ecs_secondary_co2_cover": "CLOSE", "ecs_suit_isol_cdr": "SUIT FLOW",
	"ecs_suit_isol_lmp": "SUIT FLOW",
}

var systems: Node
var cabin: Node3D
var props: Node3D
var steps: Array[Dictionary] = []
var step_index: Dictionary = {}
var stage := -1
var pressure := INITIAL_PRESSURE
var selected := ""
var install_count := 0
var fan_power := [false, false]
var sensor_power := false
var gauge: MeshInstance3D
var scene_valid := false
var radio: Radio
var result_announced := false

func setup(presenter: Node) -> void:
	systems = presenter
	cabin = systems.cabin
	radio = Radio.new()
	radio.name = "KerwinAirToGround"
	add_child(radio)
	radio.setup(cabin.repository_path("assets/audio/kerwin-co2"))
	_build_steps()
	scene_valid = cabin.bindings.has(GAUGE) and cabin.bindings.has("p2_suit_fan")
	for step: Dictionary in steps:
		if step.has("position") and not cabin.bindings.has(step.target):
			scene_valid = false
	if scene_valid:
		gauge = MeshInstance3D.new()
		gauge.name = "Co2GaugeIndex"
		var marker := BoxMesh.new()
		marker.size = Vector3(0.010, 0.001, 0.0013)
		gauge.mesh = marker
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(0.95, 0.87, 0.68)
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gauge.material_override = paint
		gauge.position = Vector3(0.003, 0.012, 0.033)
		cabin.bindings[GAUGE].root.add_child(gauge)
		gauge.hide()

func _build_steps() -> void:
	_part("stage_lmp", "090:09:17", "lmp", "bench_lmp", "Gather the two square Odyssey LiOH cartridges, gray tape, two liquid-cooling garment packs and a stiff LM cue card. Bring the first cartridge to the work area.")
	for side: String in ["lmp", "cdr"]:
		if side == "cdr":
			_part("stage_cdr", "091:12:30", "cdr", "bench_cdr", "Prepare a second unit for the commander's hose. Leave its red hose unattached until we call for it.")
		var repeats := side == "cdr"
		for entry: Array in [
			["outer", "090:22:50", "scissors", "pack", "Cut along an outer bag heat seal. Keep the inner bag intact."],
			["inner", "090:24:55", "scissors", "pack", "Pull out the inner bag and cut along one heat seal."],
			["stow", "090:26:22", "pack", "stowage", "Put the garment back in the outer bag. Keep the empty inner bag."],
			["belts", "090:27:37", "tape", side, "Wind two gray tape belts around the cartridge, near the top and bottom, with the adhesive facing out."],
			["anchors", "090:33:30", "tape", side, "Anchor the belts with two strips at right angles. Run them along the ribs so the screens stay clear."],
			["arch", "090:37:32", "card", side, "Bend the stiff cue card into an arch over the strap end. Tuck it under the ribs to keep the bag clear of the screen."],
			["arch_tape", "090:38:13", "tape", side, "Tape over the arch and anchor it to the side belts."],
			["plug", "090:43:41", "towel", side, "Plug the center bypass hole on the bottom with a piece of towel."],
			["bag", "090:47:21", "bag", side, "Slip the inner garment bag over the arch. Line up the corners with the open ends of the arch."],
			["seam", "090:49:20", "tape", side, "Press the plastic to the sticky belts. Pleat the slack and tape a snug seal around the lower belt."],
			["reinforce", "090:55:15", "tape", side, "Add four reinforcing strips across the ribs, two in each direction."],
			["split", "090:58:03", "scissors", "red_" + side, "Separate the paired red return hose and blue outlet hose by opening the Beta-cloth sleeve and ties."],
			["snip", "091:01:00", "scissors", side, "Snip one upper bag corner for the red return hose."],
			["hose", "091:01:00", "red_" + side, side, "Slip the red return hose in toward the center of the arch. Turn the nozzle sideways if it will not fit pointing down."],
			["hose_seal", "091:01:00", "tape", side, "Seal the plastic snugly around the red hose."],
			["plug_tape", "091:10:53", "tape", side, "Secure the towel plug with short tape strips, leaving the screened inlet clear."],
		]:
			if repeats and entry[0] in ["snip", "hose", "hose_seal"]:
				continue
			_part(side + "_" + entry[0], entry[1], entry[2], entry[3], entry[4], repeats)
	for side: String in ["lmp", "cdr"]:
		_control(side + "_isolate", "093:31:56", "ecs_suit_isol_" + side, "SUIT DISC", "Temporarily select SUIT DISC on the %s side while taping its outlet." % side.to_upper())
		_part(side + "_outlet_tape", "093:27:39", "tape", "blue_" + side, "Tape over half the %s blue outlet. Leave the red return hose clear." % side.to_upper())
		_control(side + "_restore_flow", "093:32:03", "ecs_suit_isol_" + side, "SUIT FLOW", "Restore SUIT FLOW on the %s side before moving on." % side.to_upper())
	_part("cdr_snip", "093:44:17", "scissors", "cdr", "Cut a diagonal opening in a corner of the commander's bag, as on the first unit.")
	_part("cdr_hose", "093:44:17", "red_cdr", "cdr", "Insert the commander's red return hose into the second bag. Aim the nozzle down or sideways.")
	_part("cdr_hose_seal", "093:44:17", "tape", "cdr", "Tape the bag around the second red hose to seal the joint.")
	_control("select_primary", "093:52:59", "ecs_co2_canister_sel", "PRIM", "Select PRIMARY before removing the spent lunar-module secondary cartridge.")
	_control("open_secondary", "093:52:59", "ecs_secondary_co2_cover", "OPEN", "Open the secondary canister compartment to remove the spent cartridge.")
	_part("remove_secondary", "093:52:59", "spent", "stowage", "Remove and stow the spent LM cartridge. The empty compartment will be part of the new circuit.")
	_control("close_secondary", "093:54:33", "ecs_secondary_co2_cover", "CLOSE", "Close the cover on the empty secondary compartment.")
	_part("mount_lmp", "093:54:39", "lmp", "mount_eps", "Secure the LMP cartridge beside the EPS panel with its screened bottom exposed to cabin air.")
	_part("mount_cdr", "093:54:39", "cdr", "mount_tunnel", "Secure the commander's cartridge at the docking tunnel, with its screened bottom exposed.")
	_part("route_lmp", "093:56:31", "blue_lmp", "route_window", "Keep the blue outlet away from the intake. Route the LMP outlet beside the LMP window.")
	_part("route_cdr", "093:56:31", "blue_cdr", "route_tunnel", "Route the extended commander's blue outlet up the tunnel toward Odyssey.")
	_control("diverter", "093:58:17", "ecs_suit_gas_diverter", "PULL-EGRESS", "Pull the Suit Gas Diverter to EGRESS.")
	_control("return", "093:58:33", "ecs_cabin_gas_return", "EGRESS", "Set Cabin Gas Return to EGRESS to draw air through the new filters.")
	_control("relief", "093:59:45", "ecs_suit_circuit_relief", "CLOSE", "Close Suit Circuit Relief.")
	_control("select_secondary", "094:00:03", "ecs_co2_canister_sel", "SEC", "Select SECONDARY so the suit fan draws through the adapters and the empty compartment.")
	install_count = steps.size()
	for index in range(install_count):
		step_index[steps[index].id] = index

func _part(id: String, get: String, item: String, target: String, message: String, repeat := false) -> void:
	steps.append({"id": id, "get": get, "item": Props.PREFIX + item, "target": Props.PREFIX + target, "message": message, "repeat": repeat})

func _control(id: String, get: String, target: String, position: String, message: String) -> void:
	steps.append({"id": id, "get": get, "target": target, "position": position, "message": message})

func start() -> void:
	# Scenario entry states for the in-service secondary cartridge and suit fan.
	for id: String in ["ecs_co2_canister_sel", "ecs_suit_isol_cdr", "ecs_suit_isol_lmp", "ecs_suit_gas_diverter",
			"ecs_cabin_gas_return", "ecs_suit_circuit_relief", "ecs_secondary_co2_cover", "p2_suit_fan"]:
		var positions: Array = cabin.state_store.definitions[id].positions
		var label := "SEC" if id == "ecs_co2_canister_sel" else ("1" if id == "p2_suit_fan" else str(PATH_CONTROLS.get(id, "")))
		if id in ["ecs_suit_gas_diverter", "ecs_cabin_gas_return", "ecs_suit_circuit_relief"]:
			label = str(cabin.state_store.definitions[id].default)
		cabin.state_store.set_position(id, positions.find(label))
		cabin._apply_position(id)
	restore({"stage": 0, "pressure": INITIAL_PRESSURE})
	cabin._aim_desktop(Props.WORK_CENTER + Vector3(0, 0.59, -0.33), Props.WORK_CENTER)

func cancel() -> void:
	if stage >= 0:
		restore({})

func done(id: String) -> bool:
	return stage > int(step_index[id])

func target() -> String:
	if stage < 0:
		return ""
	if stage >= install_count:
		return GAUGE
	var step := steps[stage]
	return step.get("item", step.target) if selected.is_empty() else step.target

func locate() -> bool:
	var id := target()
	if id.begins_with(Props.PREFIX):
		return props.locate(id)
	return not id.is_empty() and cabin._inspect_checklist_control(id)

func click(id: String) -> void:
	if stage < 0 or stage >= install_count:
		return
	var step := steps[stage]
	if step.has("position"):
		return
	if id == step.item:
		selected = "" if selected == id else id
		props.refresh()
	elif id == step.target and selected == step.item:
		if step.id == "remove_secondary":
			if cabin.state_store.position_name("ecs_co2_canister_sel") != "PRIM" or cabin.state_store.position_name("ecs_secondary_co2_cover") != "OPEN":
				cabin._notify("Select PRIMARY and open the secondary compartment before removing the cartridge.")
				return
		_finish_action()
	else:
		cabin._notify("Follow the marked part or destination. F locates it.")
	systems._update_powerdown_card()

func control_changed(id: String) -> void:
	if stage < 0 or stage >= install_count:
		return
	var step := steps[stage]
	if id == step.target and step.has("position") and cabin.state_store.position_name(id) == step.position:
		_finish_action()

func verify_position() -> bool:
	if stage < 0 or stage >= install_count:
		return false
	var step := steps[stage]
	if not step.has("position") or cabin.state_store.position_name(step.target) != step.position:
		return false
	_finish_action()
	return true

func _finish_action() -> void:
	stage += 1
	selected = ""
	props.refresh()
	if stage < install_count:
		radio.present(steps[stage]["get"])
	systems._update_powerdown_card()

func _restore_callout() -> void:
	for index in range(mini(stage, install_count - 1), -1, -1):
		var source_get: String = steps[index]["get"]
		if radio.clips.has(source_get):
			radio.present(source_get, index == stage)
			return

func update_supplies() -> void:
	if stage < 0:
		return
	fan_power = [systems._breaker_powered("p11_cb_r04_c05"), systems._breaker_powered("p16_cb_r03_c15")]
	sensor_power = systems._breaker_powered("p16_cb_r03_c18")

func airflow() -> bool:
	if stage < install_count:
		return false
	var fan: String = cabin.state_store.position_name("p2_suit_fan")
	if fan == "OFF" or not fan_power[int(fan) - 1]:
		return false
	for id: String in PATH_CONTROLS:
		if cabin.state_store.position_name(id) != PATH_CONTROLS[id]:
			return false
	return true

func advance(seconds: float) -> void:
	if stage < 0:
		return
	var flowing := airflow()
	# Scenario approximation. The curve compresses the observed trend into a short wait.
	var equilibrium := 0.20 if flowing else (12.5 if stage >= install_count else 7.6)
	pressure = lerpf(equilibrium, pressure, exp(-seconds / (7.0 if flowing else 90.0)))

func gauge_text() -> String:
	return "%.1f" % pressure if stage >= 0 and sensor_power else ""

func update_gauge() -> void:
	if gauge == null:
		return
	gauge.visible = stage >= 0 and sensor_power
	if gauge.visible:
		# Position against the existing panel 2 strip scale (0–30 mmHg).
		gauge.position.z = lerpf(0.033, -0.0265, clampf(pressure / 30.0, 0.0, 1.0))
		if not result_announced and pressure < RESULT_DISPLAY_THRESHOLD and airflow():
			result_announced = true
			radio.present(RESULT_GET)

func card_text() -> String:
	var temp := float(systems.powerdown_snapshot.cabinTemperatureF)
	var telemetry := "CABIN %.1f°F  /  CO₂ %s mmHg" % [temp, gauge_text()] if sensor_power else "CABIN %.1f°F  /  CO₂ SENSOR OFF" % temp
	var radio_hint := " · M unmutes radio" if radio.muted else (" · R repeats radio" if not radio.cue_get.is_empty() else "")
	if stage >= install_count:
		if not airflow():
			return "CO₂ ADAPTER · SUIT LOOP\n%s\n\nAirflow interrupted. Check the suit fan, hose isolation valves and ECS routing.\n\nF to locate the CO₂ gauge%s" % [telemetry, radio_hint]
		if not result_announced or pressure >= RESULT_DISPLAY_THRESHOLD:
			return "CO₂ ADAPTER · FILTERING\n%s\n\nBoth adapters are drawing through the suit loop. Watch the reading fall.\n\nF to locate the CO₂ gauge%s" % [telemetry, radio_hint]
		return "CO₂ ADAPTER · INSTALLATION COMPLETE\n%s\n\n094:33:21 GET · HOUSTON / KERWIN\nHouston reported 0.2 mmHg and confirmed the setup was working.\n\nF to locate the CO₂ gauge%s\nF12 for manual course correction" % [telemetry, radio_hint]
	var step := steps[stage]
	var mission_time := "CDR REPEAT · %s GET" % step["get"] if step.get("repeat", false) else "%s GET" % step["get"]
	var action: String
	if step.has("position"):
		action = "%s → %s" % [cabin.state_store.definitions[step.target].label, step.position]
		if cabin.state_store.position_name(step.target) == step.position:
			action += " · F12 to verify"
	else:
		var id := target()
		action = ("Pick up " if selected.is_empty() else "Use here: ") + str(props.label_for(id))
	return "CO₂ ADAPTER  %d / %d\n%s\n\nHOUSTON · KERWIN  /  %s\n%s\n\n%s\nF to locate · Click to act%s" % [stage + 1, install_count, telemetry, mission_time, step.message, action, radio_hint]

func save_state() -> Dictionary:
	return {"version": 1, "stage": stage, "pressure": pressure, "resultAnnounced": result_announced} if stage >= 0 else {}

func valid_state(state: Variant) -> bool:
	if not state is Dictionary:
		return false
	if state.is_empty():
		return true
	var index = state.get("stage")
	var value = state.get("pressure")
	var announced = state.get("resultAnnounced", false)
	return scene_valid and state.get("version") == 1 and (index is float or index is int) and \
		index >= 0 and index < install_count + 1 and int(index) == index and \
		(value is float or value is int) and is_finite(value) and value >= 0.199 and value <= 12.5 and \
		announced is bool and (not announced or index == install_count)

func restore(state: Dictionary) -> void:
	stage = int(state.get("stage", -1))
	pressure = float(state.get("pressure", INITIAL_PRESSURE))
	result_announced = state.get("resultAnnounced", stage == install_count and pressure < RESULT_DISPLAY_THRESHOLD)
	radio.clear()
	if result_announced:
		radio.present(RESULT_GET, false)
	elif stage >= 0:
		_restore_callout()
	selected = ""
	if stage >= 0 and props == null:
		props = Props.new()
		cabin.add_child(props)
		props.setup(self)
	if props != null:
		props.refresh()
	update_supplies()
	update_gauge()
