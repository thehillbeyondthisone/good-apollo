extends Node
## Apollo 13 MCC-5. Local attitude and impulse model for the hand-flown maneuver.

const Radio = preload("res://scripts/co2_radio.gd")
const SolarSight = preload("res://scripts/manual_correction_sight.gd")

enum Phase { OFF, PREP, EARTH, SUN, PAD, GO, ARM, ULLAGE, BURN, TRIM, COMPLETE, RETRY }
enum View { CABIN, COAS, AOT }
const CUES := {
	Phase.PREP: "100:16:16", Phase.EARTH: "103:51:07", Phase.SUN: "103:43:43",
	Phase.PAD: "104:33:43", Phase.GO: "105:12:04", Phase.ARM: "105:17:01",
	Phase.TRIM: "105:19:05", Phase.COMPLETE: "105:19:46",
}
const PREP := {
	"p1_bal_cpl": "OFF", "p3_dead_band": "MIN", "p3_pitch_mode_cont": "PULSE",
	"p3_roll_mode_cont": "PULSE", "p3_yaw_mode_cont": "DIR",
	"p3_ags_mode_control": "ATT HOLD", "p1_guid_cont": "AGS",
	"p16_cb_r02_c08": "PUSHED", "p16_cb_r02_c10": "PUSHED", "p16_cb_r02_c12": "PUSHED",
	"p16_cb_r02_c06": "PUSHED", "p6_ags_status": "OPERATE",
	"p11_cb_r02_c15": "PUSHED", "coas_mount": "LEFT_WINDOW", "coas_cap": "REMOVED",
	"shade_cdr": "ROLLED", "p8_coas": "FWD", "coas_illumination": "MID",
}
const ARM := {
	"p3_eng_gmbl": "OFF", "p11_cb_r03_c12": "PUSHED", "p11_cb_r03_c15": "PUSHED",
	"p16_cb_r02_c07": "PUSHED", "p16_cb_r01_c01": "PUSHED", "p5_stop_guard": "OPEN", "p5_stop": "RELEASED",
	"ttca_cdr_select": "THROTTLE", "ttca_cdr_throttle": "MIN", "ttca_lmp_select": "JETS",
	"p1_att_transl": "4 JETS",
	"p1_eng_arm": "DES",
}
const EARTH_AT_ALIGNMENT := Vector3(0, 0.04, -24.0)
const SUN_AT_ALIGNMENT := Vector3(0, 0.998, -0.065)
const INITIAL_ATTITUDE := Vector3(1.55, 2.05, -14.0)
const INITIAL_RATE := Vector3(0.035, -0.04, 0.24)
const BURN_SECONDS := 14.0
const ULLAGE_SECONDS := 10.0
const DPS_ACCEL := 7.4 / BURN_SECONDS
const RCS_ACCEL := 0.23
const TRIM_TARGET := 7.6
const KEYS := {
	KEY_UP: ["ttca_cdr_translation_y", 1.0], KEY_DOWN: ["ttca_cdr_translation_y", -1.0],
	KEY_LEFT: ["aca_cdr_yaw", 1.0], KEY_RIGHT: ["aca_cdr_yaw", -1.0],
	KEY_Z: ["ttca_cdr_translation_z", 1.0], KEY_X: ["ttca_cdr_translation_z", -1.0],
	KEY_SPACE: ["ttca_lmp_translation_x", 1.0],
}

var systems: Node
var cabin: Node3D
var radio: Radio
var globe: MeshInstance3D
var solar_sight: SolarSight
var scope: Node3D
var reticle_scales: Dictionary = {}
var original_globe_position: Vector3
var original_sun_direction: Variant
var phase := Phase.OFF
var view := View.CABIN
var scene_valid := false
var attitude := INITIAL_ATTITUDE
var rates := INITIAL_RATE
var ullage_time := 0.0
var burn_time := 0.0
var delta_v := Vector3.ZERO
var peak_error := 0.0
var peak_rate := 0.0
var hands := {}
var retry_reason := ""

func setup(presenter: Node) -> void:
	systems = presenter
	cabin = systems.cabin
	radio = Radio.new()
	radio.name = "MidcourseCAPCOM"
	add_child(radio)
	radio.setup(cabin.repository_path("assets/audio/mcc5"))
	if cabin.imported_cabin == null or not cabin.bindings.has("coas_mount"):
		return
	scope = cabin.bindings.coas_mount.actuator
	globe = cabin.imported_cabin.find_child("Earth_preview", true, false) as MeshInstance3D
	if globe == null or not globe.material_override is ShaderMaterial:
		return
	for id: String in PREP.keys() + ARM.keys() + ["aot_azimuth", "aot_reticle", "p5_start", "p6_stop"]:
		if not cabin.bindings.has(id):
			return
	original_globe_position = globe.global_position
	original_sun_direction = globe.material_override.get_shader_parameter("sun_direction")
	for id: String in ["coas_mount_reticle_x", "coas_mount_reticle_y"]:
		var line := scope.get_node_or_null(id) as MeshInstance3D
		if line != null:
			reticle_scales[line] = line.scale
	solar_sight = SolarSight.new()
	solar_sight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cabin.hud.add_child(solar_sight)
	cabin.hud.move_child(solar_sight, 0)
	solar_sight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	solar_sight.hide()
	scene_valid = true

func active() -> bool:
	return phase != Phase.OFF

func start() -> void:
	cancel()
	radio.muted = systems.co2.radio.muted
	systems.co2.radio.stop()
	attitude = INITIAL_ATTITUDE
	rates = INITIAL_RATE
	ullage_time = 0.0
	burn_time = 0.0
	delta_v = Vector3.ZERO
	peak_error = 0.0
	peak_rate = 0.0
	retry_reason = ""
	_reset_start()
	_enter(Phase.PREP)

func cancel() -> void:
	if not active():
		return
	phase = Phase.OFF
	release_hands()
	radio.clear()
	set_view(View.CABIN)
	globe.global_position = original_globe_position
	globe.material_override.set_shader_parameter("sun_direction", original_sun_direction)

func _enter(next: Phase) -> void:
	phase = next
	cabin.status_time = 0.0
	if CUES.has(phase):
		radio.present(CUES[phase])
	match phase:
		Phase.EARTH, Phase.GO, Phase.ULLAGE:
			set_view(View.COAS)
		Phase.SUN:
			set_view(View.AOT)
	systems._update_powerdown_card()

func set_view(next: View) -> void:
	if not scene_valid:
		return
	if view == View.COAS and next != View.COAS:
		cabin.desktop_camera.fov = 57.0
		cabin._set_inspection_view(1)
	view = next
	solar_sight.visible = view == View.AOT
	for line: MeshInstance3D in reticle_scales:
		var thickness := Vector3(0.25, 0.25, 0.25)
		thickness[line.mesh.get_aabb().size.max_axis_index()] = 1.0
		line.scale = reticle_scales[line] * thickness if view == View.COAS else reticle_scales[line]
	if view != View.CABIN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		cabin.crosshair.hide()
	if view == View.COAS:
		var axis := scope.global_basis.y.normalized()
		cabin._aim_desktop(scope.global_position + axis * 0.330, scope.global_position, -scope.global_basis.z.normalized())
		cabin.desktop_camera.fov = 10.5
	update_view()

func update_view() -> void:
	if not active():
		return
	var axes := Basis(scope.global_basis.x.normalized(), -scope.global_basis.z.normalized(), scope.global_basis.y.normalized())
	var sky := Basis.from_euler(attitude * PI / 180.0).inverse()
	globe.global_position = scope.global_position + axes * sky * EARTH_AT_ALIGNMENT
	globe.material_override.set_shader_parameter("sun_direction", axes * sky * SUN_AT_ALIGNMENT)
	if view == View.AOT:
		solar_sight.sun_offset = Vector2(-attitude.y - attitude.z * 0.09, attitude.x)
		solar_sight.detent_set = _position("aot_azimuth") == "F"
		solar_sight.cursor_degrees = (cabin.state_store.axis_value("aot_reticle") + 1.0) * 180.0
		solar_sight.queue_redraw()

func _position(id: String) -> String:
	return cabin.state_store.position_name(id)

func _first_unset(positions: Dictionary) -> String:
	for id: String in positions:
		if _position(id) != positions[id]:
			return id
		if id in ["aot_reticle", "ttca_cdr_throttle"] and not is_equal_approx(cabin.state_store.axis_value(id), -1.0):
			return id
	return ""

func target() -> String:
	match phase:
		Phase.PREP:
			if _position("coas_mount") != "LEFT_WINDOW" and _position("coas_barrel_lock") != "RELEASED":
				return "coas_barrel_lock"
			return _first_unset(PREP)
		Phase.SUN:
			return _first_unset({"aot_azimuth": "F", "aot_reticle": "MIN"})
		Phase.ARM, Phase.ULLAGE:
			return _first_unset(ARM)
	return ""

func locate() -> bool:
	var id := target()
	if not id.is_empty():
		set_view(View.CABIN)
		return cabin._inspect_checklist_control(id)
	if phase in [Phase.EARTH, Phase.SUN, Phase.GO, Phase.ULLAGE, Phase.BURN, Phase.TRIM]:
		set_view(View.AOT if phase == Phase.SUN else View.COAS)
		return true
	return false

func handle_key(event: InputEventKey) -> bool:
	if not active():
		return false
	if KEYS.has(event.keycode):
		if not event.echo:
			_hand_key(event.keycode, event.pressed)
		return true
	if not event.pressed or event.echo:
		return false
	match event.keycode:
		KEY_V:
			set_view(View.COAS if view != View.COAS else (View.AOT if phase in [Phase.EARTH, Phase.SUN, Phase.PAD, Phase.GO] else View.CABIN))
		KEY_ENTER, KEY_KP_ENTER:
			confirm()
		KEY_BACKSPACE:
			if phase == Phase.BURN:
				cabin._operate("p5_stop", 1, "mcc5-stop")
		_:
			return false
	return true

func _hand_key(key: Key, pressed: bool) -> void:
	if phase < Phase.EARTH or phase > Phase.TRIM:
		return
	var id: String = KEYS[key][0]
	if pressed:
		hands[key] = true
	else:
		hands.erase(key)
	var value := 0.0
	for held: Key in hands:
		if KEYS[held][0] == id:
			value += KEYS[held][1]
	var source := "mcc5-" + id
	if is_zero_approx(value):
		cabin._release_button(source)
	else:
		cabin._set_axis(id, value, source)

func release_hands() -> void:
	hands.clear()
	for id: String in ["ttca_cdr_translation_y", "ttca_cdr_translation_z", "aca_cdr_yaw", "ttca_lmp_translation_x"]:
		cabin._release_button("mcc5-" + id)

func confirm() -> void:
	match phase:
		Phase.PREP, Phase.ARM:
			if not target().is_empty():
				cabin._notify("Set the highlighted cockpit control first. F locates it.")
				return
			if phase == Phase.PREP:
				_enter(Phase.EARTH)
			else:
				_enter(Phase.ULLAGE)
		Phase.EARTH:
			if _earth_aligned() and _stable():
				_enter(Phase.SUN)
			else:
				cabin._notify("Center Earth left to right and level its terminator before confirming.")
		Phase.SUN:
			if target().is_empty() and absf(attitude.x) <= 0.65 and _earth_aligned() and _stable():
				_enter(Phase.PAD)
			else:
				cabin._notify("Check AOT F detent, zero cursor and the Sun at the top. Verify Earth again if it has drifted.")
		Phase.PAD:
			_enter(Phase.GO)
		Phase.GO:
			_enter(Phase.ARM)
		Phase.ULLAGE:
			cabin._operate("p5_start", 1, "mcc5-start")
		Phase.RETRY:
			start()
		Phase.BURN, Phase.TRIM, Phase.COMPLETE:
			return

func _earth_aligned() -> bool:
	return absf(attitude.y) <= 0.65 and absf(attitude.z) <= 2.5

func _stable() -> bool:
	return rates.length() < 0.28

func _engine_ready() -> bool:
	return _position("p1_eng_arm") == "DES" and _position("p3_eng_gmbl") == "OFF" \
		and _position("ttca_cdr_select") == "THROTTLE" and systems._breaker_powered("p11_cb_r03_c12") \
		and systems._breaker_powered("p11_cb_r03_c15") and systems._breaker_powered("p16_cb_r02_c07")

func _minimum_throttle() -> bool:
	return is_equal_approx(cabin.state_store.axis_value("ttca_cdr_throttle"), -1.0)

func _rcs_ready() -> bool:
	return _position("p1_guid_cont") == "AGS" and _position("p3_ags_mode_control") == "ATT HOLD" \
		and _position("p6_ags_status") == "OPERATE" and systems._breaker_powered("p16_cb_r02_c06") \
		and systems._breaker_powered("p16_cb_r02_c10") and systems._breaker_powered("p16_cb_r02_c12")

func _ullage_commanded() -> bool:
	return _rcs_ready() and _position("p1_att_transl") == "4 JETS" and _position("ttca_lmp_select") == "JETS" \
		and cabin.state_store.axis_value("ttca_lmp_translation_x") > 0.5

func _reset_start() -> void:
	var id := "p5_start"
	cabin.state_store.set_position(id, 0)
	cabin._apply_position(id)

func control_changed(id: String, pressed: bool) -> void:
	if not active() or not pressed:
		return
	if id == "p5_start" and _position(id) == "PRESSED":
		_try_ignite()
	elif phase == Phase.BURN and id in ["p5_stop", "p6_stop"] and _position(id) == "PRESSED":
		_cutoff()

func _try_ignite() -> void:
	if phase == Phase.BURN:
		return
	if systems.session_clock.paused or phase != Phase.ULLAGE or ullage_time < ULLAGE_SECONDS - 0.0001 \
		or not _ullage_commanded() or not _engine_ready() or not _minimum_throttle() \
		or not _earth_aligned() or absf(attitude.x) > 1.0 or not _stable():
		_reset_start()
		cabin._notify("START inhibited. Verify alignment, engine setup, 10% throttle and ten seconds of continuous ullage.")
		return
	_enter(Phase.BURN)

func _cutoff() -> void:
	if burn_time < 13.0 or burn_time > 15.0 or peak_error > 6.0 or peak_rate >= 10.0 or delta_v.z > TRIM_TARGET + 0.05:
		_fail("Burn outside the timing, attitude or impulse limits.")
		return
	_enter(Phase.TRIM)

func _fail(reason: String) -> void:
	retry_reason = reason
	_reset_start()
	_enter(Phase.RETRY)
	release_hands()

func advance(seconds: float) -> void:
	if phase < Phase.EARTH or phase > Phase.TRIM:
		return
	var flying := phase == Phase.BURN
	var thrust: float = (10.0 + (cabin.state_store.axis_value("ttca_cdr_throttle") + 1.0) * 41.25) / 10.0 if flying else 0.0
	var biased_rate := Vector3(0.10, 0.09, 0.28) * thrust
	var command := Vector3.ZERO
	if _rcs_ready():
		command = Vector3(cabin.state_store.axis_value("ttca_cdr_translation_y"),
			cabin.state_store.axis_value("aca_cdr_yaw"), cabin.state_store.axis_value("ttca_cdr_translation_z"))
		rates = rates.move_toward(command * Vector3(1.25, 1.25, 8.0) + biased_rate, seconds * 9.0)
	else:
		rates += biased_rate * seconds
	attitude += rates * seconds
	for axis in range(3):
		attitude[axis] = wrapf(attitude[axis], -180.0, 180.0)
	match phase:
		Phase.ULLAGE:
			ullage_time = minf(ullage_time + seconds, ULLAGE_SECONDS) if _ullage_commanded() else 0.0
		Phase.BURN:
			if not _engine_ready():
				_fail("Descent engine command or power was lost.")
				return
			burn_time += seconds
			peak_error = maxf(peak_error, maxf(absf(attitude.z), Vector2(attitude.x, attitude.y).length()))
			peak_rate = maxf(peak_rate, maxf(absf(rates.x), maxf(absf(rates.y), absf(rates.z))))
			_add_impulse(DPS_ACCEL * thrust * seconds)
			if peak_rate >= 10.0:
				cabin._notify("Rate limit. Cut off the engine with BACKSPACE.")
		Phase.TRIM:
			if _ullage_commanded():
				_add_impulse(RCS_ACCEL * seconds)
			elif is_equal_approx(snappedf(delta_v.z, 0.1), TRIM_TARGET):
				_enter(Phase.COMPLETE)
				release_hands()
			if delta_v.z >= TRIM_TARGET + 0.05:
				_fail("Plus-X trim overshot Houston's target.")

func _add_impulse(magnitude: float) -> void:
	var pitch := deg_to_rad(attitude.x)
	var yaw := deg_to_rad(attitude.y)
	delta_v += Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(pitch) * cos(yaw)) * magnitude

func readout(id: String) -> String:
	match id:
		"p6_deda_address":
			return "470"
		"p6_deda_data":
			return "%+.1f" % delta_v.z
		"p1_event_timer":
			var elapsed := int(floor(burn_time + 0.000001))
			return "%02d:%02d" % [elapsed / 60, elapsed % 60]
	return "--"

func save_state() -> Dictionary:
	return {
		"version": 1, "phase": phase, "attitude": [attitude.x, attitude.y, attitude.z],
		"rates": [rates.x, rates.y, rates.z], "impulse": [delta_v.x, delta_v.y, delta_v.z],
		"burnTime": burn_time, "peakError": peak_error, "peakRate": peak_rate,
		"retryReason": retry_reason,
	}

func _within(value: Variant, limit: float) -> bool:
	return (value is float or value is int) and is_finite(value) and absf(value) <= limit

func valid_state(state: Variant) -> bool:
	if not state is Dictionary:
		return false
	if state.is_empty():
		return true
	var step = state.get("phase")
	if not scene_valid or state.get("version") != 1 or not _within(step, Phase.RETRY) or step < Phase.PREP or step != int(step):
		return false
	for field: String in ["attitude", "rates", "impulse"]:
		var components = state.get(field)
		if not components is Array or components.size() != 3:
			return false
		for component in components:
			if not _within(component, 180.0 if field == "attitude" else 1000000.0):
				return false
	for field: String in ["burnTime", "peakError", "peakRate"]:
		var amount = state.get(field)
		if not _within(amount, 1000000.0) or amount < 0.0:
			return false
	var reason = state.get("retryReason")
	return reason is String and reason.length() <= 128

func restore(state: Dictionary) -> void:
	cancel()
	if state.is_empty():
		return
	phase = int(state.phase) as Phase
	attitude = Vector3(state.attitude[0], state.attitude[1], state.attitude[2])
	rates = Vector3(state.rates[0], state.rates[1], state.rates[2])
	delta_v = Vector3(state.impulse[0], state.impulse[1], state.impulse[2])
	burn_time = state.burnTime
	ullage_time = 0.0
	peak_error = state.peakError
	peak_rate = state.peakRate
	retry_reason = state.retryReason
	radio.muted = systems.co2.radio.muted
	var cue_phase := int(phase)
	while cue_phase > Phase.OFF:
		if CUES.has(cue_phase):
			radio.present(CUES[cue_phase], false)
			break
		cue_phase -= 1
	if phase == Phase.SUN and target().is_empty():
		set_view(View.AOT)
	elif phase in [Phase.EARTH, Phase.GO, Phase.ULLAGE, Phase.BURN, Phase.TRIM, Phase.COMPLETE]:
		set_view(View.COAS)
	else:
		update_view()

func card_text() -> String:
	var lines := PackedStringArray(["MCC-5   ·   MANUAL COURSE CORRECTION",
		"CABIN %.1f°F   /   LM GUIDANCE COMPUTER OFF" % float(systems.powerdown_snapshot.cabinTemperatureF), ""])
	var id := target()
	var hint := "M unmutes radio" if radio.muted else "R repeats radio · M mutes"
	match phase:
		Phase.PREP:
			lines.append("100:16:16 GET · HOUSTON / DUKE\nBalance Couple OFF. Deadband MIN. Pitch and roll PULSE, yaw DIRECT. Use AGS attitude hold.")
			if id.is_empty():
				lines.append("ENTER to acquire Earth")
		Phase.EARTH:
			lines.append("103:51:07 GET · HOUSTON / BRAND\nCenter Earth left to right and level the terminator with daylight up. Use yaw and roll, then ENTER. Pitch comes from the Sun.")
		Phase.SUN:
			lines.append("103:43:43 GET · HOUSTON / BRAND\nAOT detent 2 (F), cursor zero. Use pitch to put the Sun at the top of the cursor, then ENTER.")
		Phase.PAD:
			lines.append("104:33:43 GET · HOUSTON / LOUSMA\nManeuver PAD · 4 jets for 10 s · 10% throttle\nManual cutoff at 14 s · Rate limit 10°/s\n\nENTER to acknowledge the PAD")
		Phase.GO:
			lines.append("105:12:04 GET · HOUSTON / LOUSMA\nHouston gives the crew the choice of when to start.\n\nENTER for final engine checks")
		Phase.ARM:
			lines.append("105:17:01 GET · HOUSTON / LOUSMA\nVerify engine gimbal OFF. Set up manual throttle and arm DESCENT.")
			if id.is_empty():
				lines.append("ENTER to prepare ullage")
		Phase.ULLAGE:
			lines.append("105:18:18 GET · ULLAGE\nHold SPACE for four-jet +X ullage. At 10.0 s, keep holding and press ENTER for ENGINE START. Release after ignition.\n\nULLAGE   %04.1f / 10.0 s" % ullage_time)
		Phase.BURN:
			lines.append("105:18:28 GET · DPS BURN\nHold the Earth alignment. Cut off at 14.0 s with BACKSPACE or ENGINE STOP.\n\nEVENT TIMER   %04.1f / 14.0 s   ·   %s\nDEDA 470   %+.1f ft/s" % [burn_time, "10% THROTTLE" if _minimum_throttle() else "THROTTLE ABOVE 10%", delta_v.z])
		Phase.TRIM:
			lines.append("105:19:05 GET · HOUSTON / LOUSMA\nTrim +X to 7.6 ft/s. Tap or hold SPACE, then release on target.\n\nDEDA 470   %+.1f / +7.6 ft/s" % delta_v.z)
		Phase.COMPLETE:
			lines.append("105:19:46 GET · HOUSTON / LOUSMA\nCorrection complete.\n\nDPS   %.1f s   /   DEDA 470   %+.1f ft/s\nF12 for Odyssey power-up · Shift+F12 to fly again" % [burn_time, delta_v.z])
		Phase.RETRY:
			lines.append("%s\n\nDPS   %.1f s   /   DEDA 470   %+.1f ft/s\nENTER to retry" % [retry_reason, burn_time, delta_v.z])
	if not id.is_empty():
		var settings := PREP if phase == Phase.PREP else (ARM if phase in [Phase.ARM, Phase.ULLAGE] else {"aot_azimuth": "F", "aot_reticle": "MIN"})
		var desired := str(settings.get(id, "RELEASED"))
		lines.append("PANEL %s · %s → %s · F LOCATE" % [cabin.state_store.definitions[id].panel, cabin.state_store.definitions[id].label, desired])
		if id == "p1_eng_arm":
			lines.append("Ctrl+click releases the center lock.")
	elif phase >= Phase.EARTH and phase <= Phase.TRIM:
		lines.append("←/→ yaw · ↑/↓ pitch · Z/X roll · V sight")
		if phase in [Phase.EARTH, Phase.SUN, Phase.ULLAGE, Phase.BURN]:
			lines.append("Rates °/s   P %+.1f   Y %+.1f   R %+.1f" % [rates.x, rates.y, rates.z])
	lines.append(hint)
	return "\n".join(lines)
