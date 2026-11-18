extends Node
## Presentation adapter for the headless EPS model and the unchanged upstream AGC.
## This does not provide trajectory, IMU, propulsion, ECS or flight-padload simulation.

const EPS_SAVE := "user://electrical-state.json"
const LAMP_TEST_INPUT := "lamp_test"
## Lens bounds in the 720 × 482 panel-4 artwork, center X/Y then width/height.
const DSKY_LENSES := {
	"uplink_acty": Vector4(246.5, 39, 65, 24), "temp": Vector4(318, 39, 65, 24),
	"no_att": Vector4(246.5, 69, 65, 24), "gimbal_lock": Vector4(318, 69, 65, 24),
	"stby": Vector4(246.5, 98, 65, 24), "prog": Vector4(318, 98, 65, 24),
	"key_rel": Vector4(246.5, 127, 65, 24), "restart": Vector4(318, 127, 65, 24),
	"opr_err": Vector4(246.5, 156, 65, 24), "tracker": Vector4(318, 156, 65, 24),
	"alt": Vector4(318, 185, 65, 24), "vel": Vector4(318, 215, 65, 24),
	"comptr_acty": Vector4(428.5, 45.5, 45, 37),
}
const Co2Adapter = preload("res://scripts/co2_adapter.gd")
const ManualCorrection = preload("res://scripts/manual_correction.gd")
const OdysseyPowerup = preload("res://scripts/odyssey_powerup.gd")
const POWERDOWN_CALLOUTS := {
	"hold_for_ptc": "HOUSTON · BRAND\nHold at Power-5 in the contingency checklist. Keep guidance online while we settle passive thermal control.",
	"amplifier_branch": "HOUSTON · BRAND\nPull the primary S-band power amplifier breaker. Leave the power amplifier selector in PRIMARY.",
	"lighting_selectors": "CREW REPORT · HAISE\nOverhead/forward floods and exterior lights to OFF.",
	"inverter_selector": "CREW REPORT · LOVELL / HAISE\nTake the inverter offline at the panel 14 selector.",
	"vhf_receiver": "HOUSTON · BRAND\nOpen the VHF A receiver breaker on panel 11.",
	"inverter_branch": "CREW REPORT · LOVELL\nOpen the inverter 1 breaker on panel 11.",
	"atca_pgns": "HOUSTON · LOUSMA\nOpen the four Quad TCA breakers and take ATCA (PGNS) off panel 11.",
	"final_readup": "HOUSTON · LOUSMA\nCopy the revised Power-6 and Power-7 configuration. Leave IMU standby powered for heat. LGC/DSKY and IMU operate will be open. Stand by for execution.",
	"final_execution": "HOUSTON · LOUSMA\nExecute the reviewed power-down. Work panel 11, then panel 16. Verify switches already in the requested positions.",
	"sealed_heater": "HOUSTON · LOUSMA\nLeave all four panel 16 Quad Heater breakers closed. Use the panel 3 selectors. Quad 1 is sealed closed.",
	"heater_selectors": "CREW REPORT · LOVELL\nSet the four RCS Quad Heater selectors to OFF. Use the panel 3 switches identified by Houston.",
	"lighting_branches": "HOUSTON · LOUSMA\nGo ahead and open TRACK and FLOOD on panel 16.",
	"low_power_summary": "TELMU · POSTFLIGHT SUMMARY\nVerify the low-power configuration. IMU standby remains powered. The LGC and IMU operate circuits are off.",
}
var cabin: Node3D
var electrical: Node
var agc: Node
var electrical_snapshot: Dictionary = {}
var agc_snapshot: Dictionary = {}
var modeled_ids := PackedStringArray()
var readouts: Dictionary = {}
var readout_drivers: Dictionary = {}
var readout_sizes: Dictionary = {}
var annunciators: Dictionary = {}
var integral_materials: Array[StandardMaterial3D] = []
var dsky_lens_labels: Dictionary = {}
var lighting_state: Dictionary = {}
var caution_warning_state: Dictionary = {}
var last_error := ""
var demo_running := false
var lamp_frame_seen := false
var _capture_demo_requested := false
var _autosave_elapsed := 0.0
var session_clock: Node
var _demo_generation := 0
var powerdown_snapshot: Dictionary = {}
var powerdown_card: PanelContainer
var powerdown_text: Label
var co2: Node
var correction: ManualCorrection
var odyssey: OdysseyPowerup

func setup(owner_cabin: Node3D) -> void:
	cabin = owner_cabin
	_create_powerdown_card()
	var use_stepped := not "--external-agc" in OS.get_cmdline_user_args() and not "--agc-attach" in OS.get_cmdline_user_args()
	_create_readouts()
	co2 = Co2Adapter.new()
	co2.name = "CarbonDioxideAdapter"
	add_child(co2)
	co2.setup(self)
	correction = ManualCorrection.new()
	correction.name = "ManualCourseCorrection"
	add_child(correction)
	correction.setup(self)
	odyssey = OdysseyPowerup.new()
	odyssey.name = "OdysseyPowerup"
	add_child(odyssey)
	odyssey.setup(self)
	_collect_panel_materials(cabin.imported_cabin)
	var eps_script = load("res://scripts/ElectricalBridge.cs")
	if eps_script == null or not eps_script.can_instantiate():
		last_error = "C# bridge is not built; run tools/build-godot.ps1."
		cabin._notify(last_error)
		return
	electrical = eps_script.new()
	electrical.name = "HeadlessElectricalAdapter"
	add_child(electrical)
	electrical.connect("ElectricalUpdated", _on_electrical)
	var initialized: bool = electrical.call("Initialize", cabin.repository_path("reference/electrical.json"), cabin.repository_path("reference/controls.json"), cabin.argument_value("--preset", "electrical_checkout"))
	if not initialized:
		last_error = electrical.call("GetLastError")
		cabin._notify("Electrical setup failed: " + last_error)
		return
	if not electrical.call("InitializePowerDown", cabin.repository_path("reference/electrical-powerdown-sequence.json")):
		cabin._notify("Power-down checklist unavailable: " + str(electrical.call("GetLastError")))
	modeled_ids = electrical.call("GetModeledControlIds")
	if "--self-test" in OS.get_cmdline_user_args():
		electrical.call("SetAutomaticStep", false)
	elif not use_stepped and FileAccess.file_exists(EPS_SAVE):
		if not electrical.call("LoadStateJson", FileAccess.get_file_as_string(EPS_SAVE)):
			cabin._notify("EPS save rejected; checkout preset retained.")
	_on_electrical(electrical.call("GetSnapshotJson"))
	_create_annunciators()
	var agc_script = load("res://scripts/VirtualAgcBridge.cs")
	if agc_script != null and agc_script.can_instantiate() and not "--no-agc" in OS.get_cmdline_user_args():
		agc = agc_script.new()
		agc.name = "UpstreamVirtualAgc"
		add_child(agc)
		agc.connect("DskyUpdated", _on_agc)
		var port := int(cabin.argument_value("--agc-port", "19697"))
		var initialized_agc := false
		if use_stepped:
			initialized_agc = bool(agc.call("InitializeStepped", ""))
		if not initialized_agc:
			if use_stepped:
				cabin._notify("Shared CPU unavailable; using the external process with independent state.")
			initialized_agc = bool(agc.call("Initialize", "D:/apollo-ref/build/agc", port, "--agc-attach" in OS.get_cmdline_user_args()))
		if not initialized_agc:
			cabin._notify("AGC unavailable; EPS study remains active.")
		_on_agc(agc.call("GetSnapshotJson"))
		if agc.call("IsStepped"):
			session_clock = load("res://scripts/session_coordinator.gd").new()
			session_clock.name = "SharedSimulationClock"
			add_child(session_clock)
			session_clock.setup(self)
			if not "--self-test" in OS.get_cmdline_user_args() and cabin.argument_value("--preset").is_empty() and FileAccess.file_exists("user://session-state-v1.json"):
				if not session_clock.load_file():
					session_clock.autosave_allowed = false
					cabin._notify("Checkpoint rejected: " + str(session_clock.last_error))
	_capture_demo_requested = "--capture-lamp-test" in OS.get_cmdline_user_args()
	if agc != null:
		print("AGC backend: %s / flight padload pending" % str(agc_snapshot.get("backend", "unavailable")))
	_refresh_outputs()

func _create_readouts() -> void:
	var layout_path: String = cabin.repository_path("assets/display-layout.json")
	if not FileAccess.file_exists(layout_path):
		return
	var document = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	if not document is Dictionary:
		return
	for id: String in document.get("displays", {}):
		if not cabin.bindings.has(id):
			continue
		var specification: Dictionary = document.displays[id]
		var label := _make_readout(cabin.bindings[id].root, float(specification.widthM), float(specification.heightM), "--")
		readouts[id] = label
		readout_sizes[id] = Vector2(float(specification.widthM), float(specification.heightM))
		readout_drivers[id] = str(specification.get("driver", "unmodeled"))
	for id: String in ["p14_volts", "p14_amps"]:
		if cabin.bindings.has(id):
			readouts[id] = _make_readout(cabin.bindings[id].root, 0.039, 0.013, "--")
			readout_sizes[id] = Vector2(0.039, 0.013)
			readout_drivers[id] = "eps"

func _create_powerdown_card() -> void:
	powerdown_card = PanelContainer.new()
	powerdown_card.name = "PowerDownChecklist"
	powerdown_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.065, 0.94)
	style.border_color = Color(0.32, 0.48, 0.51)
	style.border_width_left = 2
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	powerdown_card.add_theme_stylebox_override("panel", style)
	powerdown_card.custom_minimum_size.x = 510
	cabin.hud.add_child(powerdown_card)
	powerdown_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	powerdown_card.offset_left = -544
	powerdown_card.offset_right = -34
	powerdown_card.offset_top = 112
	powerdown_text = cabin._hud_label(powerdown_card, 17, Color(0.86, 0.93, 0.92))
	powerdown_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	powerdown_card.hide()

func _make_readout(parent: Node3D, width: float, height: float, text: String) -> Label3D:
	var screen := MeshInstance3D.new()
	screen.name = "LiveReadoutBacking"
	var plane := QuadMesh.new()
	plane.size = Vector2(width, height)
	screen.mesh = plane
	screen.rotation.x = -PI / 2.0
	screen.position.y = _surface_height(parent, 0.0004)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.004, 0.009, 0.008)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override = material
	parent.add_child(screen)
	var label := Label3D.new()
	label.name = "LiveReadout"
	label.text = text
	label.font_size = 64
	var font_path: String = cabin.repository_path("assets/fonts/aquarius-segments.ttf")
	if FileAccess.file_exists(font_path):
		var font := FontFile.new()
		font.data = FileAccess.get_file_as_bytes(font_path)
		label.font = font
	label.rotation.x = -PI / 2.0
	label.position.y = _surface_height(parent, 0.0008)
	label.modulate = Color(0.47, 1.0, 0.70)
	label.outline_size = 0
	label.font_size = 64
	label.pixel_size = height / 64.0
	label.no_depth_test = false
	label.shaded = false
	parent.add_child(label)
	return label

func _surface_height(control: Node3D, clearance: float) -> float:
	# Control roots already stand 4 mm off the structure. Locate the actual
	# artwork in the control's coordinates instead of adding another fixed gap.
	var panel := str(cabin.state_store.definitions.get(str(control.name), {}).get("panel", ""))
	var artwork := control.get_parent().get_node_or_null("Panel_" + panel + "_artwork") as Node3D
	return control.to_local(artwork.global_position).y + clearance if artwork != null else clearance

func _create_annunciators() -> void:
	var wanted: Dictionary = electrical_snapshot.get("indicators", {}).duplicate()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 0.98, 0.94), Color(0.70, 0.70, 0.70)])
	var frosting := GradientTexture2D.new()
	frosting.gradient = gradient
	frosting.width = 48
	frosting.height = 24
	frosting.fill = GradientTexture2D.FILL_RADIAL
	frosting.fill_from = Vector2(0.48, 0.45)
	frosting.fill_to = Vector2(1.0, 1.0)
	for id: String in cabin.state_store.definitions:
		if id.begins_with("p4_dsky_") and id.ends_with("_light"):
			wanted[id] = false
	for id: String in wanted:
		if not cabin.bindings.has(id):
			continue
		var lamp := MeshInstance3D.new()
		lamp.name = "LiveAnnunciator"
		var plane := QuadMesh.new()
		plane.size = Vector2(0.014, 0.006)
		lamp.mesh = plane
		lamp.rotation.x = -PI / 2.0
		var indicator: Node3D = cabin.bindings[id].root
		lamp.position.y = _surface_height(indicator, 0.0006)
		var lens_key := id.trim_prefix("p4_dsky_").trim_suffix("_light")
		if id.begins_with("p4_dsky_") and DSKY_LENSES.has(lens_key):
			_fit_dsky_lens(lamp, plane, indicator, lens_key, id)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = frosting
		material.albedo_color = Color(0.035, 0.029, 0.018)
		lamp.material_override = material
		indicator.add_child(lamp)
		annunciators[id] = material

func _fit_dsky_lens(lamp: MeshInstance3D, plane: QuadMesh, indicator: Node3D, key: String, id: String) -> void:
	var artwork := indicator.get_parent().get_node_or_null("Panel_4_artwork") as MeshInstance3D
	if artwork == null:
		return
	var meters_per_pixel := Vector2(artwork.scale.x / 720.0, artwork.scale.z / 482.0)
	var bounds: Vector4 = DSKY_LENSES[key]
	var center := (Vector2(bounds.x, bounds.y) - Vector2(360, 241)) * meters_per_pixel
	lamp.position.x = center.x - indicator.position.x
	lamp.position.y = _surface_height(indicator, 0.0006)
	lamp.position.z = center.y - indicator.position.z
	plane.size = Vector2(bounds.z, bounds.w) * meters_per_pixel
	var legend := Label3D.new()
	legend.name = "LensLegend"
	legend.text = key.replace("_", " ").to_upper()
	if key in ["uplink_acty", "gimbal_lock", "comptr_acty"]:
		legend.text = legend.text.replace(" ", "\n")
	if key == "comptr_acty":
		legend.text = "CMPTR\nACTY"
	legend.font_size = 32
	legend.pixel_size = 0.00016
	legend.line_spacing = -3.0
	legend.outline_size = 0
	legend.position.z = 0.00025
	legend.modulate = Color(0.36, 0.34, 0.30)
	lamp.add_child(legend)
	dsky_lens_labels[id] = legend

func _collect_panel_materials(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D and str(node.name).ends_with("_artwork"):
		for surface in range(node.mesh.get_surface_count()):
			var material = node.get_active_material(surface)
			if material is StandardMaterial3D and material.emission_enabled:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				integral_materials.append(material)
	for child in node.get_children():
		_collect_panel_materials(child)

func _on_electrical(json: String) -> void:
	var value = JSON.parse_string(json)
	if not value is Dictionary:
		return
	electrical_snapshot = value
	powerdown_snapshot = JSON.parse_string(str(electrical.call("GetPowerDownSnapshotJson")))
	co2.update_supplies()
	var positions: Dictionary = value.get("controlPositions", {})
	for id: String in modeled_ids:
		if positions.has(id) and cabin.state_store.definitions.has(id):
			# The test selector has two physical OFF detents. An EPS label can
			# confirm an existing position without moving the handle to its twin.
			if cabin.state_store.position_name(id) == str(positions[id]):
				continue
			var index: int = cabin.state_store.definitions[id].positions.find(str(positions[id]))
			if index >= 0:
				if int(cabin.state_store.states[id]) != index:
					cabin.state_store.set_position(id, index)
					cabin._apply_position(id)
	if session_clock != null and not session_clock.sync_lgc_power(_breaker_powered("p11_cb_r04_c19")):
		cabin._notify("LGC supply change failed: " + str(session_clock.last_error))
	_refresh_outputs()

func _on_agc(json: String) -> void:
	var value = JSON.parse_string(json)
	if not value is Dictionary:
		return
	agc_snapshot = value
	var digits := ""
	for reading in value.get("readouts", {}).values():
		digits += str(reading)
	if demo_running and digits.count("8") == 21:
		lamp_frame_seen = true
	_refresh_outputs()
	if _capture_demo_requested and not demo_running and value.get("connected", false):
		_capture_demo_requested = false
		run_lamp_test()

func _breaker_powered(id: String) -> bool:
	for breaker: Dictionary in electrical_snapshot.get("breakers", []):
		if str(breaker.get("controlId", "")) == id:
			return bool(breaker.get("powered", false))
	return false

func _dimmer(id: String) -> float:
	if cabin.state_store.is_analog(id):
		return lerpf(0.2, 1.0, (cabin.state_store.axis_value(id) + 1.0) * 0.5)
	if not cabin.state_store.definitions.has(id):
		return 1.0
	var count: int = cabin.state_store.definitions[id].positions.size()
	return lerpf(0.2, 1.0, float(cabin.state_store.states[id]) / float(maxi(1, count - 1)))

func _refresh_outputs() -> void:
	if cabin == null:
		return
	var power: Dictionary = electrical_snapshot.get("poweredControls", {})
	var meters: Dictionary = electrical_snapshot.get("meterValues", {})
	var meter_valid: Dictionary = electrical_snapshot.get("meterValid", {})
	var computer_powered := bool(power.get("p4_dsky_prog_display", false))
	for id: String in readouts:
		var label: Label3D = readouts[id]
		var driver := str(readout_drivers.get(id, "unmodeled"))
		var next_text := ""
		if driver == "agc":
			next_text = str(agc_snapshot.get("readouts", {}).get(id, "")) if computer_powered else ""
		elif driver == "eps":
			next_text = ("%.1f" % float(meters.get(id, 0.0)) if meter_valid.get(id, false) else "--") if power.get(id, false) else ""
		elif correction.active() and id in ["p1_event_timer", "p6_deda_address", "p6_deda_data"]:
			next_text = correction.readout(id) if power.get(id, false) else ""
		else:
			next_text = "--" if power.get(id, false) else ""
		if label.text != next_text:
			label.text = next_text
			var longest := maxi(next_text.length(), 2)
			var window_size: Vector2 = readout_sizes[id]
			label.pixel_size = minf(window_size.y / 64.0, window_size.x / float(longest * 40))
	var indicators: Dictionary = electrical_snapshot.get("indicators", {}).duplicate()
	for id: String in agc_snapshot.get("lamps", {}):
		indicators[id] = computer_powered and bool(agc_snapshot.lamps[id])
	for id: String in annunciators:
		var material: StandardMaterial3D = annunciators[id]
		var lit: bool = indicators.get(id, false)
		var next_color := _annunciator_color(id) if lit else Color(0.035, 0.029, 0.018)
		if material.albedo_color != next_color:
			material.albedo_color = next_color
		if dsky_lens_labels.has(id):
			dsky_lens_labels[id].modulate = Color(0.15, 0.085, 0.033) if lit else Color(0.36, 0.34, 0.30) * (1.0 if computer_powered else 0.45)
	var flood := _dimmer("p5_flood_ovhd_fwd") if _breaker_powered("p16_cb_r02_c01") else 0.0
	if cabin.state_store.position_name("p3_flood_ovhd_fwd") == "OFF":
		flood = 0.0
	var integral := _dimmer("p5_integral") if _breaker_powered("p11_cb_r01_c19") else 0.0
	lighting_state = {"flood": flood, "integral": integral, "photometry": "illustrative; no component wattages inferred"}
	for fixture: SpotLight3D in cabin.forward_floods:
		fixture.light_energy = 1.85 * flood
		fixture.visible = flood > 0.0
	for diffuser: StandardMaterial3D in cabin.forward_diffusers:
		diffuser.emission_energy_multiplier = 1.7 * flood
	if cabin.aft_flood_bounce != null:
		cabin.aft_flood_bounce.light_energy = 1.65 * flood
		cabin.aft_flood_bounce.visible = flood > 0.0
	var world := cabin.get_node_or_null("CabinEnvironment") as WorldEnvironment
	if world != null:
		world.environment.ambient_light_energy = 0.025 + 0.055 * flood
	if cabin.cabin_bounce != null:
		cabin.cabin_bounce.light_energy = 0.22 * flood
		cabin.cabin_bounce.visible = flood > 0.0
	for index in cabin.window_spill.size():
		var shade := "shade_cdr" if index == 0 else "shade_lmp"
		var open: bool = cabin.state_store.position_name(shade) != "DEPLOYED"
		cabin.window_spill[index].visible = open
	for material: StandardMaterial3D in integral_materials:
		var emission := 0.25 * integral
		if not is_equal_approx(material.emission_energy_multiplier, emission):
			material.emission_energy_multiplier = emission
	caution_warning_state = electrical_snapshot.get("cautionWarning", {})
	if cabin.cabin_audio != null:
		cabin.cabin_audio.update_equipment(electrical_snapshot, cabin.state_store)
		cabin.cabin_audio.call("set_warning_tone", bool(caution_warning_state.get("warningTone", false)))
	_update_status()
	co2.update_gauge()
	correction.update_view()
	_update_powerdown_card()
	if odyssey.active():
		odyssey.station.update_meters()

func _update_powerdown_card() -> void:
	if powerdown_card == null:
		return
	# Keep source text synchronized for compatibility; the flight book owns its presentation.
	powerdown_card.visible = bool(powerdown_snapshot.get("active", false)) and not odyssey.active()
	if not powerdown_card.visible:
		return
	if correction.active():
		powerdown_text.text = correction.card_text()
		return
	if co2.stage >= 0:
		powerdown_text.text = co2.card_text()
		return
	var temperature := float(powerdown_snapshot.cabinTemperatureF)
	var conditions := "CABIN EST. %.1f°F / %.1f°C · COMPRESSED COOLING" % [temperature, (temperature - 32.0) * 5.0 / 9.0]
	var step = powerdown_snapshot.get("nextEvent")
	if not step is Dictionary:
		var next := "F12 for CO₂ adapter · Shift+F12 to restart" if not cabin.xr_active else "B/Y opens the flight menu"
		powerdown_text.text = "POWER-DOWN COMPLETE     GET %s\n%s\n\n%s" % [powerdown_snapshot.lastEvent["get"], conditions, next]
		return
	var pending: Array = powerdown_snapshot.pendingActions
	var lines := PackedStringArray([
		"POWER-DOWN   %d / %d     GET %s" % [int(powerdown_snapshot.currentIndex) + 1, int(powerdown_snapshot.eventCount), step["get"]],
		conditions, "", POWERDOWN_CALLOUTS.get(step.id, step.title), ""
	])
	if pending.is_empty():
		var prompt := "B/Y · Confirm checklist step" if cabin.xr_active else "F12 to acknowledge"
		lines.append(prompt if step.actions.is_empty() else "Positions verified · " + prompt)
	else:
		var count := "%d to verify" % pending.size()
		lines.append(count if cabin.xr_active else count + " · F locates the next control")
		for action: Dictionary in pending.slice(0, 3):
			var id := str(action.controlId)
			var definition: Dictionary = cabin.state_store.definitions[id]
			var location := "P%s" % definition.panel
			if "_cb_r" in id:
				location += " R%d/%02d" % [int(id.get_slice("_", 2).substr(1)), int(id.get_slice("_", 3).substr(1))]
			lines.append("%s · %s → %s" % [location, definition.label, action.position])
	powerdown_text.text = "\n".join(lines)

func powerdown_target() -> String:
	if correction.active():
		return correction.target()
	if co2.stage >= 0:
		return co2.target()
	var pending: Array = powerdown_snapshot.get("pendingActions", [])
	return "" if pending.is_empty() else str(pending[0].controlId)

func _annunciator_color(id: String) -> Color:
	# AOH Table2.10-2: red warning/master alarm, yellow caution, blue contact.
	if id in ["p1_lunar_contact", "p3_lunar_contact"]:
		return Color(0.22, 0.55, 1.0)
	if (id.begins_with("p1_") and id.ends_with("_warning")) or id in ["p1_master_alarm", "p2_master_alarm"]:
		return Color(1.0, 0.10, 0.04)
	return Color(1.0, 0.57, 0.12)

func _update_status() -> void:
	if cabin.mode_label == null:
		return
	var powered_buses := 0
	var current := 0.0
	for bus: Dictionary in electrical_snapshot.get("buses", []):
		if bus.get("powered", false): powered_buses += 1
		if str(bus.get("id", "")).ends_with("_DC"): current += float(bus.get("currentA", 0.0))
	var load_description := "KNOWN EQUIPMENT %.1f A / PARTIAL LOAD COVERAGE" % current if electrical_snapshot.get("loadModel", "aggregate") == "sourced_components" else "EPS AGGREGATE %.1f A" % current
	var cpu_status := "LIVE" if agc_snapshot.get("connected", false) else "OFFLINE"
	match agc_snapshot.get("cpuPowerState", ""):
		"off": cpu_status = "LGC OFF"
		"starting": cpu_status = "LGC STARTING"
	cabin.mode_label.text = "%d PROVISIONAL ENTRIES / %s / %d ENERGIZED BUSES / LM131R1 %s / FLIGHT PADLOAD PENDING" % [cabin.bindings.size(), load_description, powered_buses, cpu_status]
	if session_clock != null:
		cabin.mode_label.text += " / SHARED CLOCK PAUSED" if session_clock.paused else " / SHARED CLOCK 1X"
	else:
		cabin.mode_label.text += " / EXTERNAL CLOCK"
		if not _breaker_powered("p11_cb_r04_c19") and agc_snapshot.get("connected", false):
			cabin.mode_label.text += " / LGC BRANCH OFF / EXTERNAL CPU INDEPENDENT"
	if powerdown_snapshot.get("active", false):
		if correction.active():
			cabin.mode_label.text += "\nMCC-5 / MANUAL ATTITUDE AND DPS"
		else:
			cabin.mode_label.text += "\nCO₂ ADAPTER / COMPRESSED COAST" if co2.stage >= 0 else "\nHANDS-ON POWER-DOWN / PARTIAL FLIGHT CHECKLIST"
	var accounting: Dictionary = electrical_snapshot.get("accounting", {})
	if float(accounting.get("cmExportDemandA", 0.0)) > 0.0:
		cabin.mode_label.text += " / CM EXPORT %.2f Ah" % float(accounting.get("cmExport", {}).get("consumedAh", 0.0))

func control_changed(id: String, position_label: String, pressed: bool = true) -> bool:
	var accepted := true
	if electrical != null and id in modeled_ids:
		accepted = bool(electrical.call("SetControl", id, position_label))
		if not accepted:
			var reason := str(electrical.call("GetLastError"))
			cabin._notify("Electrical interlock rejected that position." if reason.is_empty() else reason)
	if agc != null and id.begins_with("p4_dsky_"):
		if pressed and id != "p4_dsky_pro" and session_clock != null and session_clock.paused:
			cabin._notify("Resume the shared clock with P before entering computer keys.")
			_refresh_outputs()
			return accepted
		var powered := bool(electrical_snapshot.get("poweredControls", {}).get(id, false))
		if powered or not pressed:
			agc.call("SetKey", id, pressed)
	if accepted:
		co2.control_changed(id)
		correction.control_changed(id, pressed)
	_refresh_outputs()
	return accepted

func apply_preset(name: String) -> bool:
	if electrical == null:
		return false
	var accepted := bool(electrical.call("ApplyPreset", name))
	if accepted:
		odyssey.cancel()
		correction.cancel()
		co2.cancel()
		_refresh_outputs()
		if session_clock != null:
			session_clock.reset_electrical_epoch()
		cabin._notify("EPS preset: %s / partial sourced equipment" % name if electrical_snapshot.get("loadModel", "aggregate") == "sourced_components" else "EPS calibration preset: %s / not a flown checklist configuration" % name)
	return accepted

func start_powerdown() -> bool:
	odyssey.cancel()
	correction.cancel()
	co2.cancel()
	if electrical == null or not bool(electrical.call("StartPowerDown")):
		cabin._notify("Power-down could not start: " + str(electrical.call("GetLastError")) if electrical != null else "Electrical model unavailable.")
		return false
	cancel_demo()
	if session_clock != null:
		session_clock.reset_electrical_epoch()
	cabin._notify("Follow the flight notebook and amber control highlights. Confirm completed callouts in the book. B/Y opens the menu." if cabin.xr_active else "Follow the flight notebook. N opens or stows it; F locates the control. Confirm completed callouts in the book.")
	return true

func confirm_powerdown_callout() -> void:
	if odyssey.active():
		odyssey.confirm()
	elif correction.phase == correction.Phase.COMPLETE and not cabin.xr_active:
		odyssey.start()
		_refresh_outputs()
	elif correction.active():
		correction.confirm()
	elif co2.stage >= 0:
		if co2.result_announced and co2.airflow() and co2.gauge_text() == "0.2" and correction.scene_valid and not cabin.xr_active:
			correction.start()
			_refresh_outputs()
			return
		if not co2.verify_position():
			cabin._notify("Follow the current CO₂ callout. F locates the required part or control.")
	elif not powerdown_snapshot.get("active", false):
		start_powerdown()
	elif not powerdown_snapshot.get("nextEvent") is Dictionary:
		if not cabin.xr_active:
			start_co2(false)
	elif not bool(electrical.call("ConfirmPowerDownCallout")):
		cabin._notify("Set the remaining checklist positions before proceeding.")

func start_co2(restart: bool) -> bool:
	if session_clock == null or not co2.scene_valid:
		cabin._notify("CO₂ adapter requires the desktop cabin with the shared simulation clock.")
		return false
	if co2.stage >= 0 and not restart:
		if correction.active():
			cabin._notify("MCC-5 is active. Shift+F10 restarts the CO₂ chapter.")
			return false
		co2.locate()
		return true
	if restart or not powerdown_snapshot.get("active", false):
		if not start_powerdown():
			return false
		for index in range(int(powerdown_snapshot.eventCount)):
			if str(electrical.call("NextPowerDownEvent")).is_empty():
				cabin._notify("CO₂ cold-cabin start could not prepare the electrical configuration.")
				return false
	if not bool(electrical.call("EnterColdCoast")):
		cabin._notify("Finish power-down to carry it forward, or use Shift+F10 for a fresh cold-cabin start.")
		return false
	co2.start()
	_refresh_outputs()
	cabin._notify("Cold coast · Follow Kerwin’s first callout. F locates the marked supplies.")
	return true

func save_state(path: String = EPS_SAVE) -> bool:
	if electrical == null or not bool(electrical.call("IsAvailable")):
		return false
	var payload := str(electrical.call("SaveStateJson"))
	if payload.is_empty():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(payload)
	file.flush()
	var success := file.get_error() == OK
	file.close()
	return success

func load_state(path: String = EPS_SAVE) -> bool:
	if electrical == null or not bool(electrical.call("IsAvailable")):
		return false
	var success := false
	if FileAccess.file_exists(path):
		success = bool(electrical.call("LoadStateJson", FileAccess.get_file_as_string(path)))
	# On failure, restore physical controls from the still-active authoritative model.
	_on_electrical(str(electrical.call("GetSnapshotJson")))
	return success

func control_value(id: String) -> String:
	if id == co2.GAUGE and co2.stage >= 0:
		var value: String = co2.gauge_text()
		return "CO₂ SENSOR OFF" if value.is_empty() else value + " mmHg"
	if readouts.has(id):
		return str(readouts[id].text) if not str(readouts[id].text).is_empty() else "UNPOWERED / BLANK"
	return ""

func run_lamp_test() -> void:
	if session_clock != null and bool(session_clock.paused):
		cabin._notify("Resume the shared clock with P before the lamp test.")
		return
	if demo_running or agc == null or not agc_snapshot.get("connected", false):
		cabin._notify("Live AGC connection is required for the lamp test.")
		return
	if not electrical_snapshot.get("poweredControls", {}).get("p4_dsky_verb", false):
		cabin._notify("DSKY is unpowered. F2 loads the electrical checkout preset.")
		return
	if not agc.call("CanAcceptKey"):
		cabin._notify("Wait for the LGC to finish starting before running the lamp test.")
		return
	demo_running = true
	_demo_generation += 1
	var generation := _demo_generation
	lamp_frame_seen = false
	cabin._notify("Real LM131R1 lamp test / test initialization; flight padload pending")
	for key: String in ["verb", "3", "7", "entr", "0", "0", "entr"]:
		cabin._operate("p4_dsky_" + key, 1, LAMP_TEST_INPUT)
		if not await _wait_demo(0.10, generation): return
		cabin._release_button(LAMP_TEST_INPUT)
		if not await _wait_demo(0.15, generation): return
	if not await _wait_demo(0.75, generation): return
	for key: String in ["verb", "3", "5", "entr"]:
		cabin._operate("p4_dsky_" + key, 1, LAMP_TEST_INPUT)
		if not await _wait_demo(0.10, generation): return
		cabin._release_button(LAMP_TEST_INPUT)
		if not await _wait_demo(0.15, generation): return
	if not await _wait_demo(7.0, generation): return
	demo_running = false

func cancel_demo() -> void:
	_demo_generation += 1
	demo_running = false
	cabin._release_button(LAMP_TEST_INPUT)

func _wait_demo(seconds: float, generation: int) -> bool:
	if session_clock != null:
		var target: int = session_clock.completed_ns + int(round(seconds * 1000000000.0))
		while session_clock.completed_ns < target:
			if generation != _demo_generation: return false
			await get_tree().process_frame
	else:
		await get_tree().create_timer(seconds).timeout
	return generation == _demo_generation

func _process(delta: float) -> void:
	if electrical == null:
		return
	_autosave_elapsed += delta
	if _autosave_elapsed >= 10.0 and not "--self-test" in OS.get_cmdline_user_args():
		_autosave_elapsed = 0
		if session_clock != null:
			if session_clock.autosave_allowed:
				session_clock.save_file()
		else:
			save_state()
