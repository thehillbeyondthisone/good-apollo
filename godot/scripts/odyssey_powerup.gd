extends Node
## Two-bus, budgeted desktop reconstruction of Odyssey's reentry activation.

const Data = preload("res://scripts/odyssey_checklist.gd")
const Radio = preload("res://scripts/co2_radio.gd")
const Station = preload("res://scripts/odyssey_station.gd")
const AMP_LIMIT := 20.0
const MIN_VOLTS := 24.0
const BATTERY_C_AH := 36.0
const BATTERY_B_AH := 37.0
const LOADS := {
	"instrument": [0.65, 0.0, 0.0],
	"heater": [1.45, 0.6, 1.1],
	"computer_standby": [0.50, 0.0, 0.0],
	"computer": [2.20, 0.70, 1.4],
	"caution": [0.65, 0.0, 0.0],
	"inverter": [1.45, 1.2, 2.0],
	"telcom_1": [2.05, 0.4, 1.2],
	"telcom_2": [1.65, 0.4, 1.2],
	"radio": [1.20, 0.2, 0.8],
	"sce": [0.45, 0.0, 0.0],
	"pmp": [0.40, 0.0, 0.0],
	"amp_low": [1.50, 0.2, 0.8],
	"amp_high": [4.0, 0.5, 0.8],
	"post_a": [0.25, 0.0, 0.0],
	"post_b": [0.25, 0.0, 0.0],
	"imu": [3.10, 1.7, 2.0],
	"optics": [1.10, 0.6, 1.5],
	"gn": [0.45, 0.0, 0.0],
	"heat_controls": [2.9, 0.0, 0.0],
	"logic": [1.25, 0.0, 0.0],
	"flood_dim": [1.1, 0.0, 0.0],
	"flood": [3.20, 1.0, 1.4],
}

var systems: Node
var radio: Radio
var station: Station
var steps: Array[Dictionary] = []
var required: Dictionary = {}
var dsky_start := -1
var stage := -1
var positions: Dictionary = {}
var computer_mode := 0 # Standby, awake, integration suspended, P00.
var seconds := 0.0
var startup: Dictionary = {}
var connected: Dictionary = {}
var power_a := false
var power_b := false
var from_lm := false
var voltage_a := 0.0
var voltage_b := 0.0
var current_a := 0.0
var current_b := 0.0
var steady_b := 0.0
var battery_c_used := 0.0
var battery_b_used := 0.0
var peak := 0.0
var notice := ""

func setup(presenter: Node) -> void:
	systems = presenter
	radio = Radio.new()
	radio.name = "OdysseyCAPCOM"
	add_child(radio)
	radio.setup(systems.cabin.repository_path("assets/audio/odyssey"))
	for call: Array in Data.CALLOUTS:
		for action: Array in call[2]:
			if action[0] == "dsky" and dsky_start < 0:
				dsky_start = steps.size()
			if Data.CONTROLS.has(action[0]) and action[0] != "main_meter":
				required[action[0]] = action[1]
			steps.append({"get": call[0], "caption": call[1], "id": action[0], "desired": action[1]})
	station = Station.new()
	station.setup(self)
	systems.cabin.hud.get_parent().add_child(station)
	station.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	station.hide()

func active() -> bool:
	return stage >= 0

func complete() -> bool:
	return active() and stage == steps.size() and ready()

func start() -> void:
	radio.clear()
	if not active():
		radio.muted = systems.correction.radio.muted
	systems.correction.radio.stop()
	systems.correction.set_view(systems.correction.View.CABIN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for id: String in Data.CONTROLS:
		positions[id] = Data.CONTROLS[id][3]
	stage = 0
	computer_mode = 0
	seconds = 0.0
	battery_c_used = 0.0
	battery_b_used = 0.0
	peak = 0.0
	startup.clear()
	notice = ""
	_solve()
	_update_export()
	station.show()
	_show_step()

func cancel(update_export := true) -> void:
	if not active():
		return
	stage = -1
	station.hide()
	radio.clear()
	if update_export:
		systems.electrical.call("SetCmExportDemand", "LMP_DC", 0.0)

func _closed(id: String) -> bool:
	return positions.get(id, "") == "CLOSED"

func _a_if(enabled: bool) -> int:
	return 1 if enabled and power_a else 0

func _b_if(enabled: bool) -> int:
	return 2 if enabled and power_b else 0

func _pair(a: String, b: String) -> int:
	return _a_if(_closed(a)) | _b_if(_closed(b))

func _ac_feed(selection: String, inverter: int) -> int:
	if selection == "AC1" and positions.ac_bus_1 == "ON":
		return inverter
	if selection == "AC2" and positions.ac_bus_2 == "ON":
		return inverter
	return 0

func computer_powered() -> bool:
	return _pair("computer_a", "computer_b") != 0

func _solve(track_new_loads := false) -> void:
	power_a = _closed("battery_c") and _closed("main_a_bat_c") and battery_c_used < BATTERY_C_AH
	var lm_live := false
	for bus: Dictionary in systems.electrical_snapshot.get("buses", []):
		if bus.get("id") == "LMP_DC":
			lm_live = bool(bus.get("powered", false))
			break
	from_lm = lm_live and (_closed("lm_power_1") or _closed("lm_power_2"))
	power_b = from_lm or (_closed("battery_b") and _closed("main_b_bat_b") and battery_b_used < BATTERY_B_AH)
	var dsky := _pair("computer_a", "computer_b")
	if dsky == 0 and computer_mode != 0:
		computer_mode = 0
		stage = mini(stage, dsky_start)
		notice = "CMC lost both feeds. Restore power and repeat the DSKY wake-up."
		_show_step()
	var inv := 0
	if _closed("inv_power_1") and _closed("inv_control_1"):
		inv = _a_if(positions.inv_source == "MAIN A") | _b_if(positions.inv_source == "MAIN B")
	var tel1 := _ac_feed(positions.telcom_1, inv)
	var tel2 := _ac_feed(positions.telcom_2, inv)
	var gn := _ac_feed(positions.gn_power, inv)
	if positions.gn_power == "AC1" and not _closed("gn_ac_1") or positions.gn_power == "AC2" and not _closed("gn_ac_2"):
		gn = 0
	var transmit := tel1 if positions.transponder != "OFF" else 0
	var next := {
		"instrument": _pair("instrument_a", "instrument_b"), "heater": _pair("heater_a", "heater_b"),
		"computer_standby": dsky if computer_mode == 0 else 0, "computer": dsky if computer_mode > 0 else 0,
		"caution": _pair("cw_a", "cw_b"), "inverter": inv, "telcom_1": tel1, "telcom_2": tel2,
		"radio": transmit, "sce": tel1 if positions.sce != "OFF" else 0,
		"pmp": tel2 if positions.pmp != "OFF" else 0,
		"amp_low": transmit if positions.amp == "LOW" else 0, "amp_high": transmit if positions.amp == "HIGH" else 0,
		"post_a": _a_if(_closed("post_a")), "post_b": _b_if(_closed("post_b")),
		"imu": _pair("imu_a", "imu_b"), "optics": _pair("optics_a", "optics_b"), "gn": gn,
		"heat_controls": _a_if(positions.rcs_heater == "ON"), "logic": _a_if(positions.scs_logic == "ON"),
		"flood_dim": _a_if(positions.flood == "DIM"), "flood": _a_if(positions.flood == "FLOOD"),
	}
	current_a = 0.0
	current_b = 0.0
	steady_b = 0.0
	for id: String in next:
		var supply: int = next[id]
		if supply == 0:
			startup.erase(id)
			continue
		var load: Array = LOADS[id]
		if track_new_loads and int(connected.get(id, 0)) == 0 and float(load[2]) > 0.0:
			startup[id] = seconds
		var extra := 0.0
		if startup.has(id):
			var remaining := 1.0 - (seconds - float(startup[id])) / float(load[2])
			if remaining > 0.0:
				extra = float(load[1]) * remaining
			else:
				startup.erase(id)
		var share := 0.5 if supply == 3 else 1.0
		if supply & 1:
			current_a += (float(load[0]) + extra) * share
		if supply & 2:
			current_b += (float(load[0]) + extra) * share
			steady_b += float(load[0]) * share
	connected = next
	voltage_a = maxf(0.0, 28.35 - current_a * 0.23 - battery_c_used * 0.08) if power_a else 0.0
	voltage_b = maxf(0.0, 28.25 - current_b * 0.17 - battery_b_used * 0.08) if power_b else 0.0
	if from_lm:
		voltage_b = maxf(0.0, 28.5 - current_b * 0.12)
	peak = maxf(peak, total_current())

func _update_export() -> void:
	# Use the existing sourced-load path for the modeled steady transfer.
	var snapshot: Dictionary = systems.electrical_snapshot
	if snapshot.get("loadModel") != "sourced_components":
		return
	var demand := steady_b if from_lm else 0.0
	if not is_equal_approx(float(snapshot.get("accounting", {}).get("cmExportDemandA", 0.0)), demand):
		systems.electrical.call("SetCmExportDemand", "LMP_DC", demand)

func advance(delta: float) -> void:
	if not active():
		return
	seconds += delta
	battery_c_used += current_a * delta / 3600.0
	if not from_lm:
		battery_b_used += current_b * delta / 3600.0
	_solve()

func total_current() -> float:
	return current_a + current_b

func within_budget() -> bool:
	return total_current() <= AMP_LIMIT + 0.0001 and power_a and voltage_a >= MIN_VOLTS and (not power_b or voltage_b >= MIN_VOLTS)

func current_step() -> Dictionary:
	return steps[stage] if active() and stage < steps.size() else {}

func ready() -> bool:
	if not active() or not within_budget() or from_lm or not power_b or computer_mode != 3:
		return false
	for id: String in required:
		if positions[id] != required[id]:
			return false
	for id: String in ["radio", "sce", "pmp", "computer", "imu", "optics", "gn"]:
		if connected.get(id, 0) == 0:
			return false
	return true

func _show_step(autoplay := true) -> void:
	var step := current_step()
	if step.has("get") and not step.get("get", "").is_empty():
		radio.present(step["get"], autoplay)
	station.show_target()
	station.refresh()

func _advance_step() -> void:
	stage += 1
	notice = ""
	_show_step()

func operate(id: String, direction := 1) -> void:
	if not active() or not Data.CONTROLS.has(id):
		return
	if systems.session_clock.paused:
		notice = "Resume the shared clock with P."
		station.refresh()
		return
	var settings: Array = Data.CONTROLS[id][2]
	positions[id] = settings[posmod(settings.find(positions[id]) + direction, settings.size())]
	notice = ""
	_solve(true)
	_update_export()
	if current_step().get("id", "") == id and current_step().desired == positions[id]:
		confirm()
	else:
		station.refresh()

func press_dsky(key: String) -> void:
	if not active():
		return
	var step := current_step()
	if systems.session_clock.paused or not within_budget() or _pair("computer_a", "computer_b") == 0:
		notice = "DSKY entry needs a live computer feed and the load within limits."
	elif step.get("id") != "dsky" or step.get("desired") != key:
		notice = "Use the next key called out on the checklist."
	else:
		var program := computer_mode
		if key == "PRO" and computer_mode == 0:
			computer_mode = 1
		elif key == "ENTR" and step["get"] == "127:54:55":
			computer_mode = 2
		elif key == "ENTR" and stage + 1 < steps.size() and steps[stage + 1]["get"] == "140:27:44":
			computer_mode = 3
		_solve(true)
		_update_export()
		if within_budget():
			_advance_step()
			return
		computer_mode = program
		_solve()
		_update_export()
		notice = "Shed optional load before waking the computer."
	station.refresh()

func confirm() -> void:
	var step := current_step()
	if step.is_empty():
		return
	if systems.session_clock.paused:
		notice = "Resume the shared clock with P."
	elif not within_budget():
		notice = "Hold. Let startup current settle or shed optional loads."
	elif step.id == "dsky":
		notice = "Press the highlighted DSKY key."
	elif not step.id.is_empty() and positions[step.id] != step.desired:
		notice = "Set the indicated control, then verify."
	elif stage == steps.size() - 1 and not ready():
		notice = "Restore the checklist positions and both battery feeds before final verification."
	else:
		_advance_step()
		return
	station.refresh()

func save_state() -> Dictionary:
	return {"version": 1, "stage": stage, "positions": positions.duplicate(), "computer": computer_mode,
		"seconds": seconds, "startup": startup.duplicate(), "peak": peak,
		"batteryCUsed": battery_c_used, "batteryBUsed": battery_b_used}

func _valid_number(value: Variant, limit: float) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value <= limit

func valid_state(state: Variant) -> bool:
	if not state is Dictionary:
		return false
	if state.is_empty():
		return true
	if state.get("version") != 1 or not _valid_number(state.get("stage"), steps.size()) or state.stage != int(state.stage):
		return false
	if not _valid_number(state.get("computer"), 3.0) or int(state.computer) != state.computer:
		return false
	for field: String in ["seconds", "peak", "batteryCUsed", "batteryBUsed"]:
		if not _valid_number(state.get(field), 3600000.0):
			return false
	if not state.get("positions") is Dictionary or not state.get("startup") is Dictionary:
		return false
	for id: String in Data.CONTROLS:
		if state.positions.get(id) not in Data.CONTROLS[id][2]:
			return false
	for id: String in state.startup:
		if not LOADS.has(id) or not _valid_number(state.startup[id], state.seconds) or LOADS[id][2] == 0:
			return false
	return true

func restore(state: Dictionary) -> void:
	cancel(false)
	if state.is_empty():
		return
	systems.correction.set_view(systems.correction.View.CABIN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stage = int(state.stage)
	positions = state.positions.duplicate()
	computer_mode = int(state.computer)
	seconds = state.seconds
	startup = state.startup.duplicate()
	battery_c_used = state.batteryCUsed
	battery_b_used = state.batteryBUsed
	peak = state.peak
	notice = ""
	_solve()
	station.show()
	for index in range(mini(stage, steps.size() - 1), -1, -1):
		if not steps[index]["get"].is_empty():
			radio.present(steps[index]["get"], false)
			break
	_show_step(false)
