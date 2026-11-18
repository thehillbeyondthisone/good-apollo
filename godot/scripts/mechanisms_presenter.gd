extends Node3D
## Source-qualified cabin mechanism indications. This adds no consumables or
## equipment-current model; light photometry and movable geometry are proxies.

var cabin: Node3D
var lights: Dictionary = {}
var diffusers: Dictionary = {}
var coas_reticle: Array[StandardMaterial3D] = []
var hammocks: Dictionary = {}
var status: Dictionary = {}
var derived: Dictionary = {}
var _elapsed := 0.0
var water_drops: Array[MeshInstance3D] = []
var water_time := 0.0
var _water_held := false
var water_hose: MeshInstance3D
var _hose_end := Vector3.INF
const RETICLE_LIGHT_LAYER := 1 << 1

func setup(owner: Node3D) -> void:
	cabin = owner
	for who: String in ["cdr", "lmp"]:
		_create_light("utility_" + who + "_lamp", Color(1.0, 0.87, 0.65), 1.85, 27.0, "_lens", 0.112)
		_create_light("flood_overhead_" + who + "_aim", Color(1.0, 0.85, 0.65), 2.1, 64.0, "_diffuser", 0.046)
		var id := "hammock_" + who
		if cabin.bindings.has(id):
			var actuator: Node3D = cabin.bindings[id].actuator
			var rolled := actuator.get_node_or_null(id + "_rolled") as Node3D
			var rigged := actuator.get_node_or_null(id + "_rigged") as Node3D
			if rolled != null and rigged != null:
				hammocks[id] = [rolled, rigged]
	_create_light("coas_mount", Color(0.25, 1.0, 0.42), 0.16, 0.0, "", 0.025)
	if lights.has("coas_mount"):
		lights.coas_mount.light_cull_mask = RETICLE_LIGHT_LAYER
	if cabin.bindings.has("coas_mount"):
		var scope: Node3D = cabin.bindings.coas_mount.actuator
		for line: String in ["coas_mount_reticle_x", "coas_mount_reticle_y"]:
			var mesh := scope.get_node_or_null(line) as MeshInstance3D
			if mesh != null:
				mesh.layers |= RETICLE_LIGHT_LAYER
				var material: StandardMaterial3D = cabin.lamp_diffuser(mesh)
				if material != null:
					material.emission = Color(0.54, 0.94, 0.57)
					coas_reticle.append(material)
	_create_water_feedback()
	_create_water_hose()
	refresh()

func _create_water_hose() -> void:
	var source := cabin.imported_cabin.find_child("Aft_dispenser_supply", true, false) as MeshInstance3D
	if source == null: return
	water_hose = MeshInstance3D.new()
	water_hose.name = "DispenserFlexibleSupply"
	water_hose.material_override = source.get_active_material(0)
	water_hose.layers |= cabin.AFT_SHADOW_LAYER
	add_child(water_hose)
	source.hide()

func _update_water_hose() -> void:
	if water_hose == null: return
	var dispenser: Node3D = cabin.bindings.water_dispenser_pose.actuator
	var end := dispenser.global_position
	if end.is_equal_approx(_hose_end): return
	_hose_end = end
	var curve := Curve3D.new()
	curve.bake_interval = 0.008
	curve.add_point(Vector3(0.54, 0.74, 0.938), Vector3.ZERO, Vector3(-0.10, -0.03, 0))
	curve.add_point(Vector3(0.29, 0.65, 0.94), Vector3(0.10, 0, 0), Vector3(-0.10, 0, 0))
	curve.add_point(end, dispenser.global_basis.y * -0.07, Vector3.ZERO)
	var tube := SurfaceTool.new()
	tube.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := curve.get_baked_length()
	var rings := 40
	var sides := 8
	for ring in rings + 1:
		var distance := length * float(ring) / rings
		var center := curve.sample_baked(distance, true)
		var tangent := (curve.sample_baked(minf(length, distance + 0.003), true) - curve.sample_baked(maxf(0, distance - 0.003), true)).normalized()
		var right := tangent.cross(Vector3.UP).normalized()
		if right.length_squared() < 0.1: right = Vector3.RIGHT
		var up := right.cross(tangent).normalized()
		for side in sides:
			var angle := TAU * float(side) / sides
			var normal := right * cos(angle) + up * sin(angle)
			tube.set_normal(normal)
			tube.set_uv(Vector2(float(side) / sides, distance * 12.0))
			tube.add_vertex(to_local(center + normal * 0.011))
			if ring < rings:
				var a := ring * sides + side
				var b := ring * sides + (side + 1) % sides
				for index in [a, a + sides, b, b, a + sides, b + sides]: tube.add_index(index)
	water_hose.mesh = tube.commit()

func _create_water_feedback() -> void:
	if not cabin.bindings.has("water_dispenser_pose"): return
	var parent: Node3D = cabin.bindings.water_dispenser_pose.actuator
	if parent == null: return
	var bead := SphereMesh.new()
	bead.radius = 0.0024
	bead.height = 0.0048
	bead.radial_segments = 8
	bead.rings = 4
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("#a7d4de")
	water.metallic = 0.0
	water.roughness = 0.12
	water.emission_enabled = true
	water.emission = Color("#356674")
	water.emission_energy_multiplier = 0.06
	for index in 10:
		var drop := MeshInstance3D.new()
		drop.name = "WaterBead%d" % index
		drop.mesh = bead
		drop.material_override = water
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(drop)
		drop.hide()
		water_drops.append(drop)

func _create_light(id: String, color: Color, distance: float, angle: float, lens_suffix: String, offset: float) -> void:
	if not cabin.bindings.has(id): return
	var parent: Node3D = cabin.bindings[id].actuator
	if parent == null: return
	var light: Light3D = OmniLight3D.new() if angle == 0.0 else SpotLight3D.new()
	light.name = "FixtureLight"
	light.light_color = color
	light.light_energy = 0
	light.shadow_enabled = false
	light.position.y = offset
	if light is OmniLight3D:
		light.omni_range = distance
	else:
		light.spot_range = distance
		light.spot_angle = angle
		light.spot_angle_attenuation = 0.82
		light.rotation.x = PI / 2.0
	parent.add_child(light)
	lights[id] = light
	if not lens_suffix.is_empty():
		var lens := parent.get_node_or_null(id + lens_suffix) as MeshInstance3D
		if lens != null:
			var material: StandardMaterial3D = cabin.lamp_diffuser(lens)
			if material != null:
				diffusers[id] = material

func _position(id: String) -> String:
	return cabin.state_store.position_name(id)

func _breaker_powered(id: String) -> bool:
	if cabin.systems == null: return false
	for breaker: Dictionary in cabin.systems.electrical_snapshot.get("breakers", []):
		if str(breaker.get("controlId", "")) == id: return bool(breaker.get("powered", false))
	return false

func _fraction(id: String) -> float:
	if not cabin.state_store.definitions.has(id): return 0.0
	if cabin.state_store.is_analog(id): return (cabin.state_store.axis_value(id) + 1.0) * 0.5
	var count: int = cabin.state_store.definitions[id].positions.size()
	return float(cabin.state_store.states[id]) / float(maxi(1,count - 1))

func _requirements_met(requirements: Array) -> bool:
	for rule: Dictionary in requirements:
		if rule.has("anyOf"):
			var any_met := false
			for option: Dictionary in rule.anyOf:
				if _requirements_met([option]): any_met = true
			if not any_met: return false
		elif rule.has("breakerId"):
			if not _breaker_powered(str(rule.breakerId)): return false
		else:
			if not _position(str(rule.get("controlId", ""))) in rule.get("allowedPositions", []): return false
	return true

func _declared_requirements(id: String, field: String) -> bool:
	if not cabin.state_store.definitions.has(id): return false
	var definition: Dictionary = cabin.state_store.definitions[id]
	return _requirements_met(definition.get(field, definition.get("mechanism", {}).get(field, [])))

func _set_light(id: String, energy: float) -> void:
	if lights.has(id):
		lights[id].light_energy = energy
		lights[id].visible = energy > 0
	if diffusers.has(id):
		diffusers[id].emission_energy_multiplier = minf(energy, 2.0)
	derived[id] = {"emitting": energy > 0, "illustrativeLightEnergy": energy}

func refresh() -> void:
	if cabin == null: return
	_update_water_hose()
	status.clear()
	derived.clear()
	for id: String in hammocks:
		var deployed := _position(id) == "DEPLOYED"
		hammocks[id][0].visible = not deployed
		hammocks[id][1].visible = deployed
	for who: String in ["cdr", "lmp"]:
		var lamp_id := "utility_" + who + "_lamp"
		if cabin.state_store.definitions.has(lamp_id):
			var plug_id := "utility_" + who + "_plug"
			var switch_id := "util_" + who
			var setting := _position(switch_id)
			var ready := _breaker_powered("p11_cb_r03_c18") and _position(plug_id) == "CONNECTED" and _declared_requirements(lamp_id, "emissionRequires")
			var gain := 1.0 if setting == "BRIGHT" else (0.25 if setting == "DIM" else 0.0)
			# AOH specifies CDR modes are brighter than the corresponding LMP
			# modes. This proxy preserves that ordering, not a measured ratio.
			var side_gain := 1.2 if who == "cdr" else 1.0
			_set_light(lamp_id, 2.2 * gain * side_gain if ready else 0.0)
			if ready and lights.has(lamp_id) and _position(lamp_id) != "STOWED":
				var breaker_id := "p11_cb_r03_c18" if who == "cdr" else "p16_cb_r02_c01"
				if cabin.bindings.has(breaker_id):
					var beam: SpotLight3D = lights[lamp_id]
					var breaker: Node3D = cabin.bindings[breaker_id].root
					beam.look_at(breaker.global_position, Vector3.UP)
			elif lights.has(lamp_id):
				lights[lamp_id].rotation = Vector3(PI / 2.0, 0, 0)
			derived[lamp_id]["intensityQualification"] = "CDR brighter than corresponding LMP mode is sourced; numerical gains are illustrative"
			status[lamp_id] = "LIGHT ON / " + setting if ready and gain > 0 else "LIGHT OFF"
			status[plug_id] = _position(plug_id) + " / " + str(status[lamp_id])
		var reflector_id := "flood_overhead_" + who + "_aim"
		if cabin.state_store.definitions.has(reflector_id):
			var gain := float(cabin.systems.lighting_state.get("flood",0)) if cabin.systems != null else 0.0
			var ready := _breaker_powered("p16_cb_r02_c01") and _declared_requirements(reflector_id, "emissionRequires")
			_set_light(reflector_id, gain * 0.85 if ready else 0.0)
			status[reflector_id] = "FLOOD ILLUMINATED" if ready and gain > 0 else "FLOOD OFF / AIM REMAINS MOVABLE"
	if cabin.state_store.definitions.has("coas_mount"):
		var illumination: Dictionary = cabin.state_store.definitions.get("coas_illumination",{})
		var mount := _position("coas_mount")
		var selector := _position(str(illumination.get("powerSelectorId","p8_coas")))
		var selector_map: Dictionary = illumination.get("powerSelectorMap",{"LEFT_WINDOW":"FWD","DOCKING_WINDOW":"OVHD"})
		var aligned := selector_map.has(mount) and selector == str(selector_map[mount])
		var ready := aligned and _breaker_powered("p11_cb_r02_c15") and _position("coas_cap") == "REMOVED" and _declared_requirements("coas_illumination", "emissionRequires")
		var gain := _fraction("coas_illumination")
		_set_light("coas_mount", gain * 0.18 if ready else 0.0)
		for line: StandardMaterial3D in coas_reticle:
			line.emission_energy_multiplier = gain * 0.65 if ready else 0.0
		var obscuration: Dictionary = illumination.get("viewObscurationMap",{"LEFT_WINDOW":"shade_cdr","DOCKING_WINDOW":"shade_docking"})
		var shade_id := str(obscuration.get(mount,""))
		var obscured := mount in ["LEFT_WINDOW", "DOCKING_WINDOW"] and int(cabin.state_store.states.get(shade_id,0)) > 0
		derived.coas_mount["viewObscuredByShade"] = obscured
		derived.coas_mount["opticalAlignmentModeled"] = false
		var text := "RETICLE ILLUMINATED" if ready and gain > 0 else "RETICLE DARK"
		if obscured: text += " / EXTERNAL VIEW OBSCURED BY SHADE"
		for id: String in ["coas_mount", "coas_illumination", "coas_cap", "coas_filter"]: status[id] = text
	if cabin.state_store.definitions.has("water_dispenser_trigger"):
		var trigger := _position("water_dispenser_trigger")
		var definition: Dictionary = cabin.state_store.definitions.water_dispenser_trigger
		var held := trigger != str(definition.get("default", definition.positions[0]))
		var supplied := _position("ecs_asc_h2o") == "OPEN" or _position("ecs_des_h2o") == "OPEN"
		var cap_off := _position("water_dispenser_cap") == "REMOVED"
		var available := held and supplied and cap_off and _declared_requirements("water_dispenser_trigger", "flowRequires")
		derived["water_dispenser_trigger"] = {"triggerHeld": held, "supplyPathOpen": supplied, "capRemoved": cap_off, "flowPathAvailable": available, "flowRateModeled": false, "waterConsumptionModeled": false}
		status.water_dispenser_trigger = "DISPENSING / RELEASE TO STOP" if available else ("RELEASED / HOLD SIDE BUTTON" if not held else ("REMOVE NOZZLE CAP" if not cap_off else "OPEN ASC OR DES WATER FEED"))
		status.water_dispenser_pose = _position("water_dispenser_pose") + (" / SELECT BODY TO UNSTOW" if _position("water_dispenser_pose") == "BRACKETED" else " / SELECT BODY TO REBRACKET")
		status.water_dispenser_cap = _position("water_dispenser_cap") + (" / SELECT CAP TO REMOVE" if not cap_off else " / SELECT CAP TO REPLACE")
		for drop: MeshInstance3D in water_drops: drop.visible = available
		if cabin.cabin_audio != null and cabin.bindings.has("water_dispenser_pose"):
			cabin.cabin_audio.set_water_flow(available, cabin.bindings.water_dispenser_pose.actuator.global_position)
		if held and not _water_held:
			cabin._notify("Water dispensing. Release the trigger to stop." if available else str(status.water_dispenser_trigger).capitalize() + ". See the flight notebook.")
		_water_held = held

func control_value(id: String) -> String:
	return str(status.get(id, ""))

func get_snapshot() -> Dictionary:
	return {"derived":derived.duplicate(true), "status":status.duplicate(true), "photometry":"illustrative light gains only; no sourced lumens or component currents", "consumablesPhysics":false}

func _process(delta: float) -> void:
	water_time += delta
	# Short beads leave the nozzle without terrestrial gravity. Visual feedback only.
	if derived.get("water_dispenser_trigger", {}).get("flowPathAvailable", false):
		for index in water_drops.size():
			var travel := fmod(water_time * 0.9 + float(index) / water_drops.size(), 1.0)
			water_drops[index].position = Vector3(sin(index * 2.4) * travel * 0.002, 0.121 + travel * 0.065, cos(index * 2.4) * travel * 0.002)
			water_drops[index].scale = Vector3.ONE * (1.0 - travel * 0.65)
	_elapsed += delta
	if _elapsed >= 0.05:
		_elapsed = 0
		refresh()
