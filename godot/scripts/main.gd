extends Node3D

const StateStore = preload("res://scripts/control_state.gd")
const Binding = preload("res://scripts/control_binding.gd")
const FlightHud = preload("res://scripts/flight_hud.gd")
const FlightInterface = preload("res://scripts/flight_interface.gd")
const SessionCoordinator = preload("res://scripts/session_coordinator.gd")
const SAVE_PATH := "user://control-state.json"
const INTERACTION_DISTANCE := 2.2
const FLOOD_SHADOW_LAYER := 1 << 2
const AFT_SHADOW_LAYER := 1 << 3

var inventory: Dictionary = {}
var state_store = StateStore.new()
var bindings: Dictionary = {}
var load_errors := PackedStringArray()
var imported_cabin: Node3D
var desktop_camera: Camera3D
var active_camera: Camera3D
var xr_origin: XROrigin3D
var xr_controllers: Array[XRController3D] = []
var xr_active := false
var cabin_batches: Node3D
var _applying_all_positions := false
var xr_session: Node3D
var focused_id := ""
var held_button_ids: Dictionary = {}
var yaw := 0.0
var pitch := 0.0
var status_message := ""
var status_time := 0.0
var flight_interface: Node
var flight_hud: Control
var hud: Control
var title_label: Label
var mode_label: Label
var focus_label: Label
var help_label: Label
var crosshair: Label
var checklist_marker: Label
var cabin_audio: Node3D
var systems: Node
var mechanisms: Node3D
var notebook: Node3D
var forward_floods: Array[SpotLight3D] = []
var forward_diffusers: Array[StandardMaterial3D] = []
var forward_shadow_key: SpotLight3D
var aft_flood_bounce: SpotLight3D
var window_spill: Array[SpotLight3D] = []
var cabin_bounce: OmniLight3D
var _capture_elapsed := 0.0
var _capture_frame := 0
var _capture_done := false
var _initialized := false
var _entered_cabin := false
var _hud_enabled := true
var _launch_failure := ""
var _audio_audition: Node3D

func repository_path(relative: String) -> String:
	return ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join(relative)

func argument_value(prefix: String, fallback: String = "") -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix + "="):
			return argument.substr(prefix.length() + 1)
	return fallback

func _ready() -> void:
	get_tree().auto_accept_quit = false
	_create_hud()
	_create_desktop_camera()
	var arguments := OS.get_cmdline_user_args()
	var launch_menu := DisplayServer.get_name() != "headless" and not "--self-test" in arguments
	if launch_menu:
		flight_interface = FlightInterface.new()
		flight_interface.name = "FlightInterface"
		add_child(flight_interface)
		flight_interface.setup(self)
		_show_flight_menu("splash")
		await RenderingServer.frame_post_draw
	if "--xr" in arguments:
		_try_openxr()
		if not _launch_failure.is_empty():
			if not launch_menu or float(argument_value("--xr-duration", "0")) > 0.0:
				get_tree().quit(2)
			else:
				_show_flight_menu("main", _launch_failure)
			return
		if launch_menu:
			_show_flight_menu("splash")
			await get_tree().create_timer(0.25).timeout
	_load_flight()
	if launch_menu:
		await get_tree().create_timer(0.9).timeout
		_show_flight_menu("main", status_message if status_time > 0.0 else "")

func _load_flight() -> void:
	_load_inventory()
	_load_cabin()
	if imported_cabin != null:
		load("res://scripts/cabin_occlusion.gd").install(imported_cabin)
	_bind_controls()
	mode_label.text = "CABIN STUDY / %d PROVISIONAL INVENTORY ENTRIES" % bindings.size()
	_create_environment()
	_create_audio()
	if not "--self-test" in OS.get_cmdline_user_args():
		var saved_errors: PackedStringArray = state_store.load_file(SAVE_PATH)
		if not saved_errors.is_empty():
			_notify("Saved state could not be loaded; defaults retained.")
	_apply_all_positions()
	if imported_cabin != null and (not "--self-test" in OS.get_cmdline_user_args() or "--systems-test" in OS.get_cmdline_user_args() or not argument_value("--capture-path").is_empty()):
		systems = load("res://scripts/systems_presenter.gd").new()
		systems.name = "SystemsPresentation"
		add_child(systems)
		systems.setup(self)
		flight_hud.style_checklist(systems.powerdown_card, systems.powerdown_text)
	if imported_cabin != null:
		mechanisms = load("res://scripts/mechanisms_presenter.gd").new()
		mechanisms.name = "CabinMechanisms"
		add_child(mechanisms)
		mechanisms.setup(self)
	if systems != null and mechanisms != null:
		notebook = load("res://scripts/flight_notebook.gd").new()
		notebook.name = "FlightNotebook"
		add_child(notebook)
		notebook.setup(self)
	if argument_value("--capture-view", "1") != "1":
		_set_inspection_view(int(argument_value("--capture-view", "1")))
	var arguments := OS.get_cmdline_user_args()
	var rendered_play := DisplayServer.get_name() != "headless" and not "--self-test" in arguments
	if imported_cabin != null and (rendered_play or "--xr" in arguments or "--hardware-batches" in arguments) and not "--no-hardware-batches" in arguments:
		cabin_batches = load("res://scripts/cabin_batches.gd").new()
		cabin_batches.install(imported_cabin, bindings)
	if load_errors.is_empty():
		print("Aquarius loaded: %d inventory entries, %d bound nodes." % [state_store.definitions.size(), bindings.size()])
	else:
		for message: String in load_errors:
			push_error(message)
		_notify("Prototype has %d loading issues. See console." % load_errors.size())
	_initialized = load_errors.is_empty()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and systems != null and systems.correction != null:
		systems.correction.release_hands()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_flight()

func _quit_flight() -> void:
	if xr_session != null:
		xr_session.write_report()
	if _initialized and not "--self-test" in OS.get_cmdline_user_args() and (flight_interface == null or _entered_cabin):
		# Preserve an incompatible startup checkpoint until an explicit save.
		if systems == null or systems.session_clock == null or systems.session_clock.autosave_allowed:
			_save(true)
	get_tree().quit(2 if not _launch_failure.is_empty() else 0)

func _load_inventory() -> void:
	var path := argument_value("--inventory", repository_path("reference/controls.json"))
	if not FileAccess.file_exists(path):
		load_errors.append("Inventory not found: %s" % path)
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		load_errors.append("Inventory is not a JSON object: %s" % path)
		return
	inventory = parser.data
	var layout_path := repository_path("assets/mechanism-layout.json")
	if FileAccess.file_exists(layout_path):
		var layout = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
		if layout is Dictionary and layout.get("controls", null) is Dictionary:
			for definition: Dictionary in inventory.get("controls", []):
				if layout.controls.has(str(definition.get("id", ""))):
					definition["presentation"] = layout.controls[str(definition.id)].duplicate(true)
		else:
			load_errors.append("Mechanism layout must be an object with a controls object.")
	load_errors.append_array(state_store.configure(inventory.get("controls", [])))

func _load_cabin() -> void:
	var path := argument_value("--cabin", repository_path("assets/aquarius-cabin.glb"))
	if not FileAccess.file_exists(path):
		load_errors.append("Cabin glTF not found: %s" % path)
		return
	var document := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var error := document.append_from_file(path, gltf_state)
	if error != OK:
		load_errors.append("Cabin glTF import failed (%s): %s" % [error_string(error), path])
		return
	imported_cabin = document.generate_scene(gltf_state) as Node3D
	if imported_cabin == null:
		load_errors.append("Cabin glTF did not produce a Node3D scene.")
		return
	imported_cabin.name = "Cabin"
	add_child(imported_cabin)

func _index_nodes(node: Node, result: Dictionary) -> void:
	var key := str(node.name)
	if node is Node3D:
		if not result.has(key):
			result[key] = node
	for child in node.get_children():
		_index_nodes(child, result)

func _bind_controls() -> void:
	if imported_cabin == null:
		return
	var nodes: Dictionary = {}
	_index_nodes(imported_cabin, nodes)
	for id: String in state_store.definitions:
		if not nodes.has(id):
			load_errors.append("Inventory control has no glTF node: %s" % id)
			continue
		var binding = Binding.new()
		binding.setup(state_store.definitions[id], nodes[id])
		load_errors.append_array(binding.motion_errors)
		bindings[id] = binding
		if state_store.is_interactive(id) and binding.actuator == null:
			load_errors.append("Interactive control has no moving actuator: %s" % id)
	for id: String in bindings:
		var nearest := INF
		var origin: Vector3 = bindings[id].root.global_position
		for other_id: String in bindings:
			if other_id != id:
				nearest = minf(nearest, origin.distance_to(bindings[other_id].root.global_position))
		bindings[id].fit_target_radius(nearest)

func _create_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.004, 0.007, 0.013)
	var stars_path := repository_path("assets/textures/stars.png")
	if FileAccess.file_exists(stars_path):
		var stars_image := Image.load_from_file(stars_path)
		if stars_image != null and not stars_image.is_empty():
			var panorama := PanoramaSkyMaterial.new()
			panorama.panorama = ImageTexture.create_from_image(stars_image)
			panorama.energy_multiplier = 0.18
			var sky := Sky.new()
			sky.sky_material = panorama
			environment.sky = sky
			environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.60, 0.65, 0.70)
	environment.ambient_light_energy = 0.035
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.name = "CabinEnvironment"
	world.environment = environment
	add_child(world)
	# Admit exterior light at window portals. An unrestricted directional fill
	# previously illuminated the pressure shell and instruments through the walls.
	if imported_cabin == null:
		return
	_mark_flood_shadow_casters()
	for station: String in ["CDR", "LMP"]:
		var side := -1.0 if station == "CDR" else 1.0
		var portal := SpotLight3D.new()
		portal.name = "WindowSpill" + station
		portal.position = Vector3(side * 0.70, 1.53, -0.94)
		portal.light_color = Color(0.68, 0.81, 1.0)
		portal.light_energy = 0.55 if station == "CDR" else 0.22
		portal.spot_range = 1.8
		portal.spot_angle = 48.0
		portal.spot_attenuation = 1.6
		portal.spot_angle_attenuation = 0.65
		portal.light_specular = 0.5
		# Bounded window fill shares the cabin's single fixture-shadow budget.
		portal.shadow_enabled = false
		add_child(portal)
		portal.look_at(Vector3(side * 0.16, 0.95, 0.20))
		window_spill.append(portal)
	for station: String in ["CDR", "LMP"]:
		var lens := imported_cabin.find_child("Forward_flood_diffuser_" + station, true, false) as MeshInstance3D
		if lens == null:
			continue
		var flood := SpotLight3D.new()
		flood.name = "ForwardFlood" + station
		flood.light_color = Color(1.0, 0.91, 0.79)
		flood.spot_range = 2.5
		flood.spot_angle = 64.0
		flood.spot_angle_attenuation = 0.55
		flood.spot_attenuation = 1.35
		flood.light_specular = 0.65
		flood.light_energy = 0.0
		# One shadowed key light defines the hardware relief. The other fixture fills it.
		flood.shadow_enabled = station == "CDR"
		if flood.shadow_enabled:
			forward_shadow_key = flood
		flood.shadow_caster_mask = FLOOD_SHADOW_LAYER
		flood.shadow_bias = 0.025
		flood.shadow_normal_bias = 0.35
		flood.shadow_blur = 1.5
		add_child(flood)
		flood.global_position = lens.global_position + Vector3(0, -0.025, 0)
		var side := -1.0 if station == "CDR" else 1.0
		flood.look_at(Vector3(0.34 * side, 1.17, -0.83), Vector3.UP)
		forward_floods.append(flood)
		var lens_material := lamp_diffuser(lens)
		if lens_material != null:
			forward_diffusers.append(lens_material)
	var aft := imported_cabin.find_child("Aft_midsection", true, false) as Node3D
	if aft != null:
		# Broad reflected spill from the existing cabin floods into the midsection.
		aft_flood_bounce = SpotLight3D.new()
		aft_flood_bounce.name = "AftFloodBounce"
		aft_flood_bounce.position = Vector3(-0.32, 1.94, 0.08)
		aft_flood_bounce.light_color = Color(1.0, 0.91, 0.80)
		aft_flood_bounce.light_energy = 0.0
		aft_flood_bounce.spot_range = 2.55
		aft_flood_bounce.spot_angle = 66.0
		aft_flood_bounce.spot_angle_attenuation = 0.50
		aft_flood_bounce.spot_attenuation = 1.3
		aft_flood_bounce.light_specular = 0.15
		_mark_aft_shadow_casters(aft)
		aft_flood_bounce.shadow_caster_mask = AFT_SHADOW_LAYER
		aft_flood_bounce.shadow_opacity = 0.85
		aft_flood_bounce.shadow_blur = 1.25
		aft_flood_bounce.shadow_bias = 0.025
		aft_flood_bounce.shadow_normal_bias = 0.35
		add_child(aft_flood_bounce)
		aft_flood_bounce.look_at(Vector3(-0.12, 1.02, 0.98), Vector3.UP)
	# Low diffuse return from the deck. It follows flood power and adds no shiny
	# phantom bulb in metal highlights. Keep this local rather than lifting black.
	cabin_bounce = OmniLight3D.new()
	cabin_bounce.name = "DeckReflectedLight"
	cabin_bounce.position = Vector3(0.0, 0.48, -0.05)
	cabin_bounce.omni_range = 1.7
	cabin_bounce.omni_attenuation = 1.8
	cabin_bounce.light_color = Color(0.78, 0.76, 0.70)
	cabin_bounce.light_specular = 0.0
	cabin_bounce.light_energy = 0.0
	add_child(cabin_bounce)
	_style_earth()

func _update_desktop_shadow_key() -> void:
	if forward_shadow_key == null or aft_flood_bounce == null:
		return
	# Only render the shadow map for the end in view. Keep the previous key while looking sideways.
	var view_depth := active_camera.global_basis.z.z
	if view_depth < -0.24 and not aft_flood_bounce.shadow_enabled:
		forward_shadow_key.shadow_enabled = false
		aft_flood_bounce.shadow_enabled = true
	elif view_depth > 0.24 and aft_flood_bounce.shadow_enabled:
		aft_flood_bounce.shadow_enabled = false
		forward_shadow_key.shadow_enabled = true

func _mark_aft_shadow_casters(aft: Node3D) -> void:
	# Cast from the large foreground shapes. The small fittings and webbing share their shade.
	for node: Node in aft.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var label := str(mesh.name)
		if label.ends_with("_fabric") or label.begins_with("Aft_stowage_shelf") or label.begins_with("Aft_data_storage_electronics") or label.begins_with("Aft_oxygen_umbilical") or label.begins_with("Aft_ecs_canister") or label.begins_with("Aft_occluder_") or label in ["Aft_pressure_bulkhead", "Aft_ECS_fascia"]:
			mesh.layers |= AFT_SHADOW_LAYER
	for id: String in bindings:
		if str(bindings[id].definition.get("panel", "")) != "ECS" and not id.begins_with("water_dispenser_"): continue
		for mesh: Node in bindings[id].root.find_children("*", "MeshInstance3D", true, false):
			mesh.layers |= AFT_SHADOW_LAYER

func _mark_flood_shadow_casters() -> void:
	# Keep contact shadows on the foreground hardware and window structure.
	# The remaining cabin still receives light without another depth submission.
	for node: Node in imported_cabin.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var label := str(mesh.name)
		if label.begins_with("window_frame") or label.begins_with("window_crash_bar") or label.begins_with("AOT_") or label.begins_with("guard_") or label.begins_with("toggle_tip") or label.ends_with("_backing") or label.begins_with("Forward_") or label in ["Floor", "Roof", "Instrument_support_wall"] or label.begins_with("lower_sidewall") or label.begins_with("upper_sidewall"):
			mesh.layers |= FLOOD_SHADOW_LAYER

func lamp_diffuser(lens: MeshInstance3D) -> StandardMaterial3D:
	if lens == null:
		return null
	var source := lens.get_active_material(0) as StandardMaterial3D
	if source == null:
		return null
	var material := source.duplicate() as StandardMaterial3D
	material.emission_enabled = true
	material.emission = Color(1.0, 0.84, 0.60)
	material.emission_energy_multiplier = 0.0
	lens.material_override = material
	# Real light starts just outside the diffuser so the fixture cannot shadow itself.
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return material

func _style_earth() -> void:
	var globe := imported_cabin.find_child("Earth_preview", true, false) as MeshInstance3D
	if globe == null:
		return
	var source := globe.get_active_material(0) as StandardMaterial3D
	if source == null or source.albedo_texture == null:
		return
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/earth_preview.gdshader")
	material.set_shader_parameter("globe_map", source.albedo_texture)
	material.set_shader_parameter("sun_direction", Vector3(0.08, 0.99, 0.14))
	globe.material_override = material

func _create_audio() -> void:
	if ResourceLoader.exists("res://scripts/cabin_audio.gd"):
		cabin_audio = load("res://scripts/cabin_audio.gd").new()
		cabin_audio.name = "CabinAudio"
		cabin_audio.set("enabled", DisplayServer.get_name() != "headless" and not "--self-test" in OS.get_cmdline_user_args())
		add_child(cabin_audio)

func _create_desktop_camera() -> void:
	if DisplayServer.get_name() != "headless" and not "--xr" in OS.get_cmdline_user_args():
		get_viewport().msaa_3d = Viewport.MSAA_2X
	desktop_camera = Camera3D.new()
	desktop_camera.name = "DesktopInspectionCamera"
	desktop_camera.near = 0.025
	desktop_camera.far = 100.0
	desktop_camera.fov = 57.0
	add_child(desktop_camera)
	_set_inspection_view(1)
	desktop_camera.current = true
	active_camera = desktop_camera

func _hud_label(parent: Control, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	flight_hud = FlightHud.new()
	hud = flight_hud
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_label = flight_hud.title_label
	mode_label = flight_hud.mode_label
	focus_label = flight_hud.focus_label
	help_label = flight_hud.help_label
	crosshair = flight_hud.crosshair
	checklist_marker = flight_hud.checklist_marker

func _try_openxr() -> void:
	xr_session = load("res://scripts/xr_session.gd").new()
	xr_session.name = "XRSession"
	add_child(xr_session)
	if not xr_session.setup(self):
		_launch_failure = xr_session.failure_reason
		return
	xr_origin = xr_session.origin
	xr_controllers = xr_session.controllers
	active_camera = xr_session.camera
	xr_active = true
	_update_hud_visibility()

func flight_menu_is_open() -> bool:
	return flight_interface != null and not flight_interface.page.is_empty()

func toggle_flight_menu() -> void:
	if flight_interface == null:
		return
	if flight_menu_is_open():
		flight_interface.back()
	else:
		_show_flight_menu("pause")

func _show_flight_menu(page: String, notice := "") -> void:
	if not flight_menu_is_open():
		if xr_active:
			xr_session.release_for_menu()
		for source: String in held_button_ids.keys():
			_release_button(source)
		if systems != null:
			systems.correction.release_hands()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		crosshair.hide()
		focused_id = ""
	get_tree().paused = true
	flight_interface.show_page(page, xr_active, _flight_menu_status(notice))
	_update_hud_visibility()

func _enter_cabin() -> void:
	_stop_audio_audition()
	_entered_cabin = true
	flight_interface.dismiss()
	get_tree().paused = false
	_update_hud_visibility()

func _flight_menu_status(notice: String) -> Dictionary:
	var can_enter := _initialized and _launch_failure.is_empty()
	var can_powerdown: bool = can_enter and systems != null and systems.electrical != null and systems.electrical.call("IsAvailable")
	var can_co2: bool = can_powerdown and not xr_active and systems.session_clock != null and systems.co2.scene_valid
	var checkpoint := SessionCoordinator.SESSION_SAVE if systems != null and systems.session_clock != null else SAVE_PATH
	var has_save := FileAccess.file_exists(checkpoint)
	var chapter := "Cabin checkout"
	var confirm_label := ""
	if can_powerdown and systems.powerdown_snapshot.get("active", false):
		chapter = "Electrical power-down"
		if systems.powerdown_snapshot.get("nextEvent") is Dictionary:
			confirm_label = "Confirm checklist step"
		elif can_co2:
			confirm_label = "Continue to CO₂ adapter"
	if can_co2 and systems.co2.stage >= 0:
		chapter = "CO₂ adapter"
		confirm_label = "Continue to MCC-5" if _can_begin_correction() else "Confirm checklist step"
	if can_co2 and systems.correction.active():
		chapter = "MCC-5 course correction"
		confirm_label = "Continue to Odyssey" if systems.correction.phase == systems.correction.Phase.COMPLETE else "Confirm checklist step"
	if can_co2 and systems.odyssey.active():
		chapter = "Odyssey power-up"
		confirm_label = "Confirm checklist step"
	return {
		"can_enter": can_enter,
		"has_session": _entered_cabin or (has_save and (systems == null or systems.session_clock == null or systems.session_clock.autosave_allowed)),
		"can_powerdown": can_powerdown,
		"can_co2": can_co2,
		"can_correct": can_co2 and _can_begin_correction(),
		"can_odyssey": can_co2 and systems.correction.phase == systems.correction.Phase.COMPLETE,
		"can_confirm": not confirm_label.is_empty(),
		"confirm_label": confirm_label,
		"can_load": can_enter and has_save,
		"audio_enabled": cabin_audio != null and cabin_audio.enabled,
		"radio_enabled": cabin_audio != null and cabin_audio.radio_enabled,
		"audio_profile": cabin_audio.profile if cabin_audio != null else "Headphones",
		"audio_levels": cabin_audio.levels.duplicate() if cabin_audio != null else {},
		"audio_previewing": is_instance_valid(_audio_audition) and not _audio_audition.voice_only,
		"audio_voice_previewing": is_instance_valid(_audio_audition) and _audio_audition.voice_only,
		"radio_status": "Houston calls begin in CO₂ adapter (desktop). Checkout and power-down use text." if _active_radio() == null else "Houston calls play with chapter instructions. Sound check includes speech at 11 seconds.",
		"hud_visible": _hud_enabled,
		"chapter": chapter,
		"notice": notice,
	}

func _can_begin_correction() -> bool:
	return not xr_active and not systems.correction.active() and systems.correction.scene_valid and systems.co2.result_announced and systems.co2.airflow() and systems.co2.gauge_text() == "0.2"

func handle_flight_action(action: String) -> void:
	if not flight_menu_is_open() or (not _initialized and action != "quit"):
		return
	if action.begins_with("audio_"):
		_handle_audio_action(action)
		return
	match action:
		"enter", "resume":
			if _initialized:
				_enter_cabin()
		"main":
			_show_flight_menu("main")
		"quit":
			_quit_flight()
		"powerdown", "co2", "correction", "odyssey":
			var started := false
			if action == "powerdown":
				started = systems.start_powerdown()
			elif action == "co2" and not xr_active:
				started = systems.start_co2(true)
			elif action == "correction" and _can_begin_correction():
				systems.confirm_powerdown_callout()
				started = systems.correction.active()
			elif action == "odyssey" and not xr_active and systems.correction.phase == systems.correction.Phase.COMPLETE:
				if not systems.odyssey.active():
					systems.confirm_powerdown_callout()
				started = systems.odyssey.active()
			if started:
				_enter_cabin()
			else:
				_show_flight_menu(flight_interface.page, status_message)
		"confirm":
			systems.confirm_powerdown_callout()
			_enter_cabin()
		"save":
			_save()
			_show_flight_menu(flight_interface.page, status_message)
		"load":
			if _restore_checkpoint():
				_enter_cabin()
			else:
				_show_flight_menu(flight_interface.page, status_message)
		"toggle_audio":
			_toggle_audio()
			_show_flight_menu(flight_interface.page, status_message)
		"toggle_hud":
			_hud_enabled = not _hud_enabled
			_update_hud_visibility()
			_show_flight_menu(flight_interface.page)
		"recenter":
			if xr_active:
				xr_session.recenter()
		"notebook":
			if not xr_active: _hud_enabled = true
			_enter_cabin()
			if notebook != null:
				notebook.recall()
		"onboarding":
			_enter_cabin()
			if notebook != null:
				notebook.onboarding = load("res://scripts/cabin_onboarding.gd").new()
				notebook.refresh()
				notebook.recall()

func _update_hud_visibility() -> void:
	hud.visible = not xr_active and not flight_menu_is_open()
	flight_hud.set_instruments_visible(_hud_enabled)
	if xr_active:
		xr_session.help_visible = _hud_enabled

func _unhandled_input(event: InputEvent) -> void:
	if not xr_active and systems != null and systems.odyssey.active():
		if _odyssey_input(event):
			return
	if not xr_active and systems != null and systems.correction.active():
		var correction = systems.correction
		if event is InputEventKey and correction.handle_key(event):
			return
		if correction.view != correction.View.CABIN:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				correction.set_view(correction.View.CABIN)
			elif event is InputEventMouse:
				return
	if event is InputEventMouseButton and not xr_active:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
			crosshair.visible = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_operate(focused_id, -1 if event.shift_pressed else 1, "mouse", event.shift_pressed or event.ctrl_pressed)
			else:
				_release_button()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if state_store.is_analog(focused_id):
				_set_axis(focused_id,clampf(state_store.axis_value(focused_id)+direction*0.1,-1.0,1.0),"mouse-wheel",event.ctrl_pressed or event.shift_pressed)
				_release_button("mouse-wheel")
			elif state_store.definitions.has(focused_id) and str(state_store.definitions[focused_id].get("type", "")) in ["rotary", "thumbwheel"]:
				_operate(focused_id,direction,"mouse-wheel",event.ctrl_pressed or event.shift_pressed)
				_release_button("mouse-wheel")
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not xr_active:
		yaw -= event.relative.x * 0.0026
		pitch = clampf(pitch - event.relative.y * 0.0026, -1.25, 1.25)
		desktop_camera.rotation = Vector3(pitch, yaw, 0)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			crosshair.visible = false
		elif event.keycode == KEY_F1:
			_hud_enabled = not _hud_enabled
			_update_hud_visibility()
		elif event.keycode == KEY_N and notebook != null:
			if not _hud_enabled:
				_hud_enabled = true
				_update_hud_visibility()
			notebook.toggle_focus()
		elif event.keycode == KEY_F8 and xr_session != null:
			xr_session.reset_measurement()
		elif event.keycode == KEY_F7 and cabin_batches != null:
			cabin_batches.set_enabled(not bool(cabin_batches.enabled))
			_notify("Cabin hardware batching %s" % ("on" if cabin_batches.enabled else "off"))
			if xr_session != null:
				xr_session.reset_measurement()
		elif event.keycode == KEY_F10 and xr_session != null:
			xr_session.write_report()
			_notify("XR evidence written to " + str(xr_session.report_path))
		elif event.keycode == KEY_F10 and systems != null and not xr_active:
			systems.start_co2(event.shift_pressed)
		elif event.keycode == KEY_F2 and systems != null:
			systems.apply_preset("electrical_checkout")
		elif event.keycode == KEY_F3 and systems != null:
			systems.apply_preset("minimum_lifeboat_12a")
		elif event.keycode == KEY_F4 and systems != null:
			systems.apply_preset("cold_dark")
		elif event.keycode == KEY_F11 and systems != null:
			systems.apply_preset("sourced_equipment_checkout")
		elif event.keycode == KEY_F12 and systems != null:
			if event.shift_pressed:
				if systems.correction.active():
					systems.correction.start()
				else:
					systems.start_powerdown()
			else:
				systems.confirm_powerdown_callout()
		elif event.keycode == KEY_F and not xr_active and systems != null:
			if notebook != null:
				notebook.reveal_target()
				return
			var target: String = systems.powerdown_target()
			var located: bool
			if systems.correction.active():
				located = systems.correction.locate()
			else:
				located = systems.co2.locate() if systems.co2.stage >= 0 else _inspect_checklist_control(target)
			if not target.is_empty() and not located:
				_notify("Move closer to the indicated panel to see this control.")
		elif event.keycode == KEY_F6 and systems != null:
			systems.run_lamp_test()
		elif event.keycode == KEY_P and systems != null and systems.session_clock != null:
			systems.session_clock.paused = not bool(systems.session_clock.paused)
			_notify("Shared simulation clock paused." if systems.session_clock.paused else "Shared simulation clock resumed.")
		elif event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4] and not xr_active:
			if systems != null and systems.correction.active():
				systems.correction.set_view(systems.correction.View.CABIN)
			_set_inspection_view(int(event.keycode - KEY_1) + 1)
		elif event.keycode == KEY_M and cabin_audio != null:
			if event.shift_pressed: _toggle_cabin_audio()
			else: _toggle_audio()
		elif event.keycode == KEY_R and systems != null and systems.co2.stage >= 0:
			var radio = systems.correction.radio if systems.correction.active() else systems.co2.radio
			if not radio.repeat():
				_notify("Press M to unmute the radio." if radio.muted else "No radio callout to repeat yet.")
		elif event.keycode == KEY_F5:
			_save()
		elif event.keycode == KEY_F9:
			_restore_checkpoint()
		elif event.keycode == KEY_HOME and not xr_active:
			if systems != null and systems.correction.active():
				systems.correction.set_view(systems.correction.View.CABIN)
			_set_inspection_view(1)

func _odyssey_input(event: InputEvent) -> bool:
	var odyssey = systems.odyssey
	if not event is InputEventKey or not event.pressed or event.echo:
		return true
	match event.keycode:
		KEY_F:
			odyssey.station.show_target(true)
		KEY_F12:
			if event.shift_pressed:
				odyssey.start()
			else:
				odyssey.confirm()
		KEY_M:
			odyssey.radio.toggle_mute()
			odyssey.station.update_meters()
		KEY_R:
			if not odyssey.radio.repeat():
				odyssey.notice = "Press M to unmute the recorded calls."
				odyssey.station.refresh()
		KEY_P:
			systems.session_clock.paused = not bool(systems.session_clock.paused)
			odyssey.notice = "Shared simulation clock paused." if systems.session_clock.paused else ""
			odyssey.station.refresh()
		KEY_F5:
			var saved: bool = systems.session_clock.save_file()
			odyssey.notice = "Checkpoint saved." if saved else str(systems.session_clock.last_error)
			odyssey.station.refresh()
		KEY_F9:
			var restored: bool = systems.session_clock.load_file()
			odyssey.notice = "Checkpoint restored." if restored else str(systems.session_clock.last_error)
			odyssey.station.refresh()
		KEY_F2, KEY_F3, KEY_F4, KEY_F10, KEY_F11:
			return false
	return true

func _set_inspection_view(index: int) -> void:
	desktop_camera.fov = 68.0 if index == 4 else 57.0
	if index == 1:
		desktop_camera.position = Vector3(0, 1.36, 0.92)
		desktop_camera.look_at(Vector3(0, 1.20, -0.91), Vector3.UP)
	elif index == 2 and bindings.has("p4_dsky_r1_display"):
		var control: Node3D = bindings["p4_dsky_r1_display"].root
		var target := control.global_position
		desktop_camera.global_position = target + control.global_basis.y.normalized() * 0.43
		desktop_camera.look_at(target, -control.global_basis.z.normalized())
	elif index == 3 and bindings.has("p14_volts"):
		var control: Node3D = bindings["p14_volts"].root
		var target := control.global_position
		desktop_camera.global_position = target + control.global_basis.y.normalized() * 0.55
		desktop_camera.look_at(target, -control.global_basis.z.normalized())
	elif index == 4:
		desktop_camera.position = Vector3(0, 1.34, -0.43)
		desktop_camera.look_at(Vector3(0, 1.04, 1.08), Vector3.UP)
	yaw = desktop_camera.rotation.y
	pitch = desktop_camera.rotation.x

func _clamp_desktop_position(position: Vector3) -> Vector3:
	return position.clamp(Vector3(-1.10, 0.65, -0.45), Vector3(1.10, 1.95, 1.06))

func _aim_desktop(origin: Vector3, target: Vector3, up := Vector3.UP) -> void:
	desktop_camera.global_position = origin
	desktop_camera.look_at(target, up)
	yaw = desktop_camera.rotation.y
	pitch = desktop_camera.rotation.x

func _inspect_checklist_control(id: String) -> bool:
	if not bindings.has(id):
		return false
	var binding = bindings[id]
	var target: Vector3 = binding.target_global_position()
	var normal: Vector3 = binding.target_surface_normal()
	for distance: float in [0.24, 0.34, 0.16, 0.08]:
		var origin := _clamp_desktop_position(target + normal * distance)
		if origin.distance_to(target) < 0.04 or _pick(origin, origin.direction_to(target)) != id:
			continue
		var up: Vector3 = Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else -binding.root.global_basis.z.normalized()
		_aim_desktop(origin, target, up)
		return true
	return false

func _process(delta: float) -> void:
	if cabin_audio != null:
		var voice = _active_radio()
		if voice != null:
			voice.muted = not cabin_audio.radio_enabled
			if voice.muted and voice.playing: voice.stop()
		cabin_audio.set_voice_active(voice != null and voice.playing and not voice.muted)
	if desktop_camera == null:
		return
	if systems != null and systems.odyssey.active():
		return
	_update_desktop_shadow_key()
	if not xr_active and (systems == null or systems.correction.view == systems.correction.View.CABIN):
		var movement := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W): movement.z -= 1
		if Input.is_physical_key_pressed(KEY_S): movement.z += 1
		if Input.is_physical_key_pressed(KEY_A): movement.x -= 1
		if Input.is_physical_key_pressed(KEY_D): movement.x += 1
		if Input.is_physical_key_pressed(KEY_Q): movement.y -= 1
		if Input.is_physical_key_pressed(KEY_E): movement.y += 1
		var speed := 0.30 if Input.is_physical_key_pressed(KEY_CTRL) else 0.75
		var horizontal := Basis(Vector3.UP, yaw) * Vector3(movement.x, 0, movement.z)
		desktop_camera.position += (horizontal + Vector3.UP * movement.y).normalized() * speed * delta
		desktop_camera.position = _clamp_desktop_position(desktop_camera.position)
	if status_time > 0:
		status_time -= delta
	_update_focus_text()
	var capture_path := argument_value("--capture-path")
	if not capture_path.is_empty() and not _capture_done:
		_capture_frame += 1
		_capture_elapsed += delta
		var capture_ready := _capture_elapsed >= float(argument_value("--capture-delay", "1.0"))
		if "--capture-lamp-test" in OS.get_cmdline_user_args():
			capture_ready = systems != null and bool(systems.get("lamp_frame_seen"))
		if capture_ready:
			_capture_done = true
			_capture(capture_path)
		elif _capture_elapsed > 25.0:
			push_error("Capture timed out waiting for live systems.")
			get_tree().quit(1)

func _physics_process(_delta: float) -> void:
	if active_camera == null:
		return
	if systems != null and systems.odyssey.active():
		return
	if not xr_active:
		var point := get_viewport().get_visible_rect().size / 2.0 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else get_viewport().get_mouse_position()
		focused_id = _pick(active_camera.project_ray_origin(point), active_camera.project_ray_normal(point))
		_update_checklist_marker()

func _update_checklist_marker() -> void:
	checklist_marker.hide()
	var id: String = systems.powerdown_target() if systems != null else ""
	var target: Vector3
	if bindings.has(id):
		target = bindings[id].target_global_position()
	elif id.begins_with("co2_prop_"):
		target = systems.co2.props.point(id)
	else:
		return
	if not desktop_camera.is_position_in_frustum(target):
		return
	var origin := desktop_camera.global_position
	if _pick(origin, origin.direction_to(target)) != id:
		return
	checklist_marker.position = desktop_camera.unproject_position(target) - checklist_marker.size * 0.5
	checklist_marker.show()

func _pick(origin: Vector3, direction: Vector3) -> String:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * INTERACTION_DISTANCE, 8 | 16 | 32)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	return str(hit.collider.get_meta("control_id", ""))

func _operate(id: String, direction: int, input_source: String = "mouse", unlocked: bool = false) -> void:
	if id.is_empty():
		return
	if id.begins_with("co2_prop_") and systems != null:
		var before_stage: int = systems.co2.stage
		var handled_item: String = systems.co2.selected
		systems.co2.click(id)
		if cabin_audio != null and systems.co2.stage != before_stage:
			var material_hint := handled_item + " " + id
			var family := "latch"
			if "tape" in material_hint: family = "fastener"
			elif "bag" in material_hint or "pack" in material_hint or "towel" in material_hint or "card" in material_hint: family = "fabric"
			elif "scissors" in material_hint: family = "button"
			cabin_audio.play_foley(family, systems.co2.props.point(id))
		if not "--self-test" in OS.get_cmdline_user_args():
			_save(false)
		return
	var linked_before: Dictionary = {}
	for other_id: String in state_store.definitions:
		if id in state_store.definitions[other_id].get("mechanism", {}).get("resetBy", []):
			linked_before[other_id] = state_store.states[other_id]
	if not state_store.actuate(id, direction, unlocked):
		return
	if state_store.is_momentary(id):
		if held_button_ids.has(input_source) and held_button_ids[input_source] != id:
			_release_button(input_source)
		held_button_ids[input_source] = id
	_apply_position(id)
	if systems != null:
		systems.control_changed(id, state_store.position_name(id), true)
	if notebook != null: notebook.observe("operate")
	for other_id: String in linked_before:
		if int(linked_before[other_id]) != int(state_store.states[other_id]):
			_apply_position(other_id)
			if systems != null:
				systems.control_changed(other_id, state_store.position_name(other_id), false)
	if cabin_audio != null and bindings.has(id):
		_play_control_audio(id)
	if not "--self-test" in OS.get_cmdline_user_args():
		_save(false)

func _set_axis(id: String, value: float, input_source: String, unlocked: bool = false) -> void:
	if not state_store.has_method("set_axis") or not state_store.set_axis(id, value, unlocked):
		return
	if held_button_ids.has(input_source) and held_button_ids[input_source] != id:
		_release_button(input_source)
	held_button_ids[input_source] = id
	_apply_position(id)
	if systems != null:
		systems.control_changed(id, state_store.position_name(id), true)
	if cabin_audio != null and bindings.has(id):
		cabin_audio.play_axis(id, bindings[id].root.global_position, state_store.axis_value(id))

func _set_xr_position(id: String, index: int, input_source: String) -> void:
	var previous: int = state_store.states.get(id, -1)
	if not state_store.is_interactive(id) or not state_store.is_guard_open(id, index) or not state_store.set_position(id, index): return
	if state_store.is_momentary(id): held_button_ids[input_source] = id
	_apply_position(id)
	if systems != null: systems.control_changed(id, state_store.position_name(id), true)
	if previous != int(state_store.states[id]): _play_control_audio(id)

func _release_button(input_source: String = "mouse") -> void:
	if held_button_ids.has(input_source):
		var id: String = held_button_ids[input_source]
		held_button_ids.erase(input_source)
		# Two tracked hands may press the same physical momentary. Releasing one
		# source must leave the other source's press active.
		if id in held_button_ids.values(): return
		state_store.release(id)
		_apply_position(id)
		if systems != null:
			systems.control_changed(id, state_store.position_name(id), false)
		if cabin_audio != null and bindings.has(id):
			_play_control_audio(id, true)
		if not "--self-test" in OS.get_cmdline_user_args():
			_save(false)

func _apply_position(id: String) -> void:
	if bindings.has(id):
		if state_store.is_analog(id):
			bindings[id].apply_axis(state_store.axis_value(id))
		else:
			bindings[id].apply_position(int(state_store.states[id]))
	if cabin_batches != null and not _applying_all_positions:
		if str(state_store.definitions[id].get("type", "")) == "mechanism":
			cabin_batches.refresh()
		else:
			cabin_batches.refresh(id)
	if mechanisms != null and not _applying_all_positions:
		mechanisms.refresh()

func _apply_all_positions() -> void:
	_applying_all_positions = true
	for id: String in bindings:
		_apply_position(id)
	_applying_all_positions = false
	if cabin_batches != null:
		cabin_batches.refresh()
	if mechanisms != null:
		mechanisms.refresh()

func _save(notify: bool = true) -> void:
	if systems != null and systems.session_clock != null:
		if notify:
			var success: bool = systems.session_clock.save_file()
			_notify("Complete controls/EPS/AGC checkpoint saved." if success else "Checkpoint save failed: " + str(systems.session_clock.last_error))
		return
	var error: Error = state_store.save_file(SAVE_PATH)
	var eps_saved := true
	if systems != null:
		eps_saved = bool(systems.save_state())
	if notify or error != OK or not eps_saved:
		if error != OK:
			_notify("Control save failed: %s" % error_string(error))
		elif not eps_saved:
			_notify("Control positions saved; EPS save failed.")
		else:
			_notify("Control/EPS state saved. External AGC memory is not saved.")

func _restore_checkpoint() -> bool:
	if systems != null and systems.session_clock != null:
		var restored: bool = systems.session_clock.load_file()
		_notify("Complete controls/EPS/AGC checkpoint restored." if restored else "Checkpoint rejected: " + str(systems.session_clock.last_error))
		return restored
	var errors: PackedStringArray = state_store.load_file(SAVE_PATH)
	if not errors.is_empty():
		_notify("Load rejected: %s" % errors[0])
		return false
	var eps_restored: bool = systems == null or systems.load_state()
	_apply_all_positions()
	_notify("Control/EPS state restored; the external AGC continues independently." if eps_restored else "EPS restore failed; active electrical state retained.")
	return eps_restored

func _active_radio() -> AudioStreamPlayer:
	if systems == null:
		return null
	if systems.odyssey.active():
		return systems.odyssey.radio
	if systems.correction.active():
		return systems.correction.radio
	return systems.co2.radio if systems.co2.stage >= 0 else null

func _play_control_audio(id: String, released := false, override_kind := "") -> void:
	if cabin_audio == null or not bindings.has(id): return
	var kind := override_kind if not override_kind.is_empty() else str(state_store.definitions[id].get("type", "toggle"))
	cabin_audio.play_control(kind, bindings[id].root.global_position, id, released)

func _toggle_cabin_audio() -> void:
	if cabin_audio == null: return
	cabin_audio.enabled = not cabin_audio.enabled
	cabin_audio.save_settings()
	_notify("Cabin audio on." if cabin_audio.enabled else "Cabin audio muted.")

func _toggle_radio_audio() -> void:
	if cabin_audio == null: return
	cabin_audio.radio_enabled = not cabin_audio.radio_enabled
	var radio = _active_radio()
	if radio != null:
		radio.muted = not cabin_audio.radio_enabled
		if radio.muted: radio.stop()
		systems._update_powerdown_card()
	cabin_audio.save_settings()
	_notify("Radio on. Press R to repeat." if cabin_audio.radio_enabled else "Radio muted.")

func _toggle_audio() -> void:
	if _active_radio() != null: _toggle_radio_audio()
	else: _toggle_cabin_audio()

func _handle_audio_action(action: String) -> void:
	if cabin_audio == null: return
	match action:
		"audio_preview", "audio_voice_preview":
			var only_voice := action == "audio_voice_preview"
			if only_voice and not cabin_audio.radio_enabled:
				_notify("Mission radio is off. Turn it on above, then test Houston voice.")
			elif is_instance_valid(_audio_audition) and _audio_audition.voice_only == only_voice:
				_stop_audio_audition()
			else:
				_stop_audio_audition()
				_audio_audition = load("res://scripts/audio_sound_check.gd").new()
				add_child(_audio_audition)
				_audio_audition.setup(self, only_voice)
				_audio_audition.tree_exited.connect(_audio_audition_finished.bind(_audio_audition.get_instance_id()))
		"audio_cabin": _toggle_cabin_audio()
		"audio_radio": _toggle_radio_audio()
		"audio_headphones": cabin_audio.apply_profile("Headphones")
		"audio_quiet": cabin_audio.apply_profile("Quiet cabin")
		"audio_speakers": cabin_audio.apply_profile("Speakers")
		_:
			var parts := action.split("_")
			if parts.size() == 3: cabin_audio.adjust_level(parts[1], 1.0 if parts[2] == "up" else -1.0)
	if is_instance_valid(_audio_audition):
		_audio_audition.sound.levels = cabin_audio.levels.duplicate()
		_audio_audition.sound.radio_enabled = cabin_audio.radio_enabled
		_audio_audition.sound.enabled = cabin_audio.enabled
		_audio_audition.voice.muted = not cabin_audio.radio_enabled
	flight_interface.show_page(flight_interface.page, xr_active, _flight_menu_status(status_message))

func _stop_audio_audition() -> void:
	if not is_instance_valid(_audio_audition): return
	_audio_audition.sound.enabled = false
	_audio_audition.voice.stop()
	_audio_audition.queue_free()
	_audio_audition = null
	if cabin_audio != null: cabin_audio._apply_mix()

func _audio_audition_finished(instance_id: int) -> void:
	if is_instance_valid(_audio_audition) and _audio_audition.get_instance_id() != instance_id: return
	_audio_audition = null
	if is_instance_valid(cabin_audio): cabin_audio._apply_mix()
	if is_instance_valid(flight_interface) and flight_menu_is_open():
		flight_interface.show_page(flight_interface.page, xr_active, _flight_menu_status(""))

func _notify(message: String) -> void:
	status_message = message
	status_time = 5.0

func _update_focus_text() -> void:
	if focus_label == null:
		return
	if not focused_id.is_empty() and state_store.definitions.has(focused_id):
		var definition: Dictionary = state_store.definitions[focused_id]
		var suffix := "" if state_store.is_interactive(focused_id) else "  /  READ ONLY"
		var value := str(systems.control_value(focused_id)) if systems != null else ""
		if mechanisms != null and not mechanisms.control_value(focused_id).is_empty():
			value = mechanisms.control_value(focused_id)
		if value.is_empty(): value = state_store.position_name(focused_id)
		focus_label.text = "%s  /  %s  /  %s%s" % [definition.get("panel", ""), definition.get("label", focused_id), value, suffix]
		crosshair.modulate = Color(1.0, 0.72, 0.25)
	elif focused_id.begins_with("co2_prop_") and systems != null:
		focus_label.text = systems.co2.props.label_for(focused_id)
		crosshair.modulate = Color(1.0, 0.72, 0.25)
	elif status_time > 0:
		focus_label.text = status_message
		crosshair.modulate = Color.WHITE
	else:
		focus_label.text = ""
		crosshair.modulate = Color.WHITE
	flight_hud.present_focus(not focused_id.is_empty(), status_message if status_time > 0 else "")

func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Screenshots require a rendering display, not --headless.")
		if "--quit-after-capture" in OS.get_cmdline_user_args(): get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("Capture saved: %s (%s)" % [path, error_string(error)])
	if "--quit-after-capture" in OS.get_cmdline_user_args():
		get_tree().quit(0 if error == OK else 1)
