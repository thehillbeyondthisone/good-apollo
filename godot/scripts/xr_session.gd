extends Node3D
## Live headset interaction and measurement. Automated tests never imply headset use.

const InputRouter = preload("res://scripts/xr_input.gd")
const FlightHud = preload("res://scripts/flight_hud.gd")
const ControlHover = preload("res://scripts/control_hover.gd")
const FRAME_BUDGET_MS := 1000.0 / 72.0
const NEAR_DISTANCE := 0.055
const TOUCH_DEPTH := 0.008
const TOUCH_RELEASE_DEPTH := 0.020
const TOUCH_MAX_RADIUS := 0.014
const TOUCH_RELEASE_MARGIN := 0.004
const MAX_TIMING_SAMPLES := 21600

var cabin: Node3D
var interface: OpenXRInterface
var origin: XROrigin3D
var camera: XRCamera3D
var controllers: Array[XRController3D] = []
var router = InputRouter.new()
var focus: Dictionary = {}
var beams: Dictionary = {}
var markers: Dictionary = {}
var tips: Dictionary = {}
var touch_positions: Dictionary = {}
var touch_contacts: Dictionary = {}
var hover_status: Dictionary = {}
var help_visible := true
var report_path := ""
var initialized := false
var focused := false
var headset_seen := false
var both_hands_seen := false
var tracked_seconds := 0.0
var frame_times: Array[float] = []
var metric_samples: Dictionary = {"processMs": [], "physicsMs": [], "renderCpuMs": [], "renderSetupCpuMs": [], "renderGpuMs": [], "drawCalls": []}
var tracking_gaps := 0
var recenter_count := 0
var elapsed := 0.0
var focused_warmup := 0.0
var last_usec := 0
var save_elapsed := 0.0
var movement_cooldown := 0.0
var session_events: Array[Dictionary] = []
var started_utc := ""
var failure_reason := ""
var _last_tracking_valid := false
var _menu_pose_pending := true
var _navigation_needs_center: Dictionary = {}
var _ray_material: StandardMaterial3D
var _target_material: StandardMaterial3D
var _menu_ray_material: StandardMaterial3D
var _menu_target_material: StandardMaterial3D

func setup(owner: Node3D) -> bool:
	cabin = owner
	process_mode = Node.PROCESS_MODE_ALWAYS
	router.setup(cabin)
	started_utc = Time.get_datetime_string_from_system(true) + "Z"
	report_path = cabin.argument_value("--xr-report", cabin.repository_path("output/xr-session.json"))
	interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if interface == null or (not interface.is_initialized() and not interface.initialize()):
		failure_reason = "OpenXR could not initialize. Connect Link/SteamVR and an available headset, then relaunch with -XR."
		write_report()
		push_error(failure_reason)
		cabin._notify(failure_reason)
		return false
	initialized = true
	XRServer.world_scale = 1.0
	origin = XROrigin3D.new()
	origin.name = "StandingOrigin"
	origin.position = Vector3(0, 0, 0.70)
	add_child(origin)
	camera = XRCamera3D.new()
	camera.name = "Headset"
	camera.near = 0.025
	camera.far = 100.0
	origin.add_child(camera)
	camera.current = true
	# Ivory suit-tether filament, with an amber instrument sight on acquisition.
	_ray_material = _material(Color(0.73, 0.80, 0.79, 0.38))
	_ray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_target_material = _material(Color("#eac28b"))
	_menu_ray_material = _menu_pointer_material(Color(0.73, 0.80, 0.79, 0.45))
	_menu_target_material = _menu_pointer_material(Color("#eac28b"))
	for hand: String in ["left_hand", "right_hand"]:
		var controller := XRController3D.new()
		controller.name = hand
		controller.tracker = StringName(hand)
		controller.pose = &"aim"
		controller.show_when_tracked = true
		origin.add_child(controller)
		controllers.append(controller)
		controller.button_pressed.connect(_button_pressed.bind(controller))
		_create_pointer(controller)
	cabin.flight_hud.create_xr_status(camera)
	interface.session_focussed.connect(_session_focused)
	interface.session_visible.connect(_session_unfocused.bind("visible_without_input"))
	interface.session_stopping.connect(_session_unfocused.bind("stopping"))
	interface.session_loss_pending.connect(_session_unfocused.bind("loss_pending"))
	interface.instance_exiting.connect(_session_unfocused.bind("exiting"))
	focused = interface.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED
	get_viewport().use_xr = true
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_session_event("initialized")
	write_report()
	return true

func _session_event(event: String) -> void:
	session_events.append({"event": event, "elapsedSeconds": elapsed})

func _session_focused() -> void:
	focused = true
	last_usec = 0
	focused_warmup = 0.0
	_session_event("focused")

func _session_unfocused(reason: String) -> void:
	focused = false
	last_usec = 0
	release_for_menu()
	if cabin.flight_interface != null:
		cabin.flight_interface.cancel_xr_pointer()
	_session_event(reason)
	write_report()

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _menu_pointer_material(color: Color) -> StandardMaterial3D:
	var material := _material(color)
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 30
	return material

func _create_pointer(controller: XRController3D) -> void:
	var beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.00035
	cylinder.bottom_radius = 0.0008
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	beam.mesh = cylinder
	beam.rotation.x = PI / 2.0
	beam.material_override = _ray_material
	controller.add_child(beam)
	beams[str(controller.name)] = beam
	var tip := MeshInstance3D.new()
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.003
	tip_mesh.height = 0.006
	tip_mesh.radial_segments = 8
	tip_mesh.rings = 4
	tip.mesh = tip_mesh
	tip.material_override = beam.material_override
	tip.hide()
	controller.add_child(tip)
	tips[str(controller.name)] = tip
	var marker := MeshInstance3D.new()
	var sight := TorusMesh.new()
	sight.inner_radius = 0.0055
	sight.outer_radius = 0.007
	sight.rings = 16
	sight.ring_segments = 6
	marker.mesh = sight
	marker.material_override = _target_material
	add_child(marker)
	markers[str(controller.name)] = marker
	var hover := ControlHover.new()
	add_child(hover)
	hover.setup(cabin)
	hover_status[str(controller.name)] = hover
	# Short neutral cuff with contrasting bands evokes a pressure-suit fitting.
	for index in 3:
		var cuff := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.009
		ring.outer_radius = 0.012
		ring.rings = 16
		ring.ring_segments = 6
		cuff.mesh = ring
		cuff.rotation.x = PI / 2.0
		cuff.position.z = -0.012 - index * 0.008
		cuff.material_override = _target_material if index == 1 else _material(Color("#ddd6c2"))
		controller.add_child(cuff)

func release_for_menu() -> void:
	router.release_all()
	if cabin.notebook != null:
		cabin.notebook.cancel_pointer()
		cabin.notebook.release_hands(false)
	touch_positions.clear()
	touch_contacts.clear()
	focus.clear()
	for controller: XRController3D in controllers:
		var hand := str(controller.name)
		# A trigger or stick held through a modal or lost focus must return to neutral.
		router.awaiting_release[hand] = true
		_navigation_needs_center[hand] = true
		beams[hand].hide()
		markers[hand].hide()
		tips[hand].hide()
		if hover_status.has(hand): hover_status[hand].hide()

func _grip_transform(controller: XRController3D) -> Transform3D:
	var tracker := XRServer.get_tracker(controller.tracker) as XRPositionalTracker
	var pose := tracker.get_pose(&"grip") if tracker != null else null
	return origin.global_transform * pose.transform if pose != null and pose.has_tracking_data else controller.global_transform

func _consume_notebook_hand(hand: String, trigger: bool, delta: float) -> void:
	router.sample(hand, {"active": false}, delta)
	if trigger: router.awaiting_release[hand] = true
	touch_positions.erase(hand)
	touch_contacts.erase(hand)
	focus.erase(hand)
	beams[hand].hide()
	markers[hand].hide()
	tips[hand].hide()
	if hover_status.has(hand): hover_status[hand].hide()

func _tracked(controller: XRController3D) -> bool:
	if not focused or not controller.get_is_active(): return false
	var pose := controller.get_pose()
	return pose != null and pose.has_tracking_data

func _target(controller: XRController3D) -> String:
	# Close pointing selects the same bounded collider as a far ray. The nearest
	# interactive center wins only inside the hand-sized near radius. Query the
	# existing target areas first instead of scanning all cabin bindings per hand.
	var query: PhysicsShapeQueryParameters3D = get_meta("_near_target_query") if has_meta("_near_target_query") else null
	if query == null:
		query = PhysicsShapeQueryParameters3D.new()
		var shape := SphereShape3D.new()
		shape.radius = NEAR_DISTANCE
		query.shape = shape
		query.collision_mask = 8
		query.collide_with_areas = true
		query.collide_with_bodies = false
		query.margin = 0.0
		set_meta("_near_target_query", query)
	query.transform = Transform3D(Basis.IDENTITY, controller.global_position)
	var nearby := get_world_3d().direct_space_state.intersect_shape(query, 128)
	var closest := NEAR_DISTANCE
	var result := ""
	for hit: Dictionary in nearby:
		var collider := hit.get("collider") as Area3D
		if collider == null: continue
		var id := str(collider.get_meta("control_id", ""))
		if not cabin.bindings.has(id) or not cabin.state_store.is_interactive(id): continue
		var binding = cabin.bindings[id]
		var target: Vector3 = binding.target_global_position()
		var distance: float = controller.global_position.distance_to(target)
		var normal: Vector3 = binding.target_surface_normal()
		if distance < closest and normal.dot(controller.global_position - target) >= -0.005 and not _occluded(controller.global_position, target):
			closest = distance
			result = id
	if not result.is_empty(): return result
	result = cabin._pick(controller.global_position, -controller.global_basis.z)
	if not cabin.bindings.has(result): return ""
	var normal: Vector3 = cabin.bindings[result].target_surface_normal()
	if normal.dot(controller.global_position - cabin.bindings[result].target_global_position()) < -0.005:
		return ""
	return result

func _occluded(start: Vector3, end: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(start, end, 16)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _touch_target(hand: String, tip: Vector3, target: String, can_start: bool) -> String:
	var previous: Vector3 = touch_positions.get(hand, tip)
	touch_positions[hand] = tip
	if touch_contacts.has(hand):
		# Keep the original press surface while the actuator animates under the tip.
		var held: Dictionary = touch_contacts[hand]
		var offset: Vector3 = tip - held.center
		var normal: Vector3 = held.normal
		if absf(offset.dot(normal)) <= TOUCH_RELEASE_DEPTH and offset.slide(normal).length() <= float(held.radius) + TOUCH_RELEASE_MARGIN:
			return str(held.id)
		touch_contacts.erase(hand)
		return ""
	if not can_start or not cabin.bindings.has(target) or not cabin.state_store.is_interactive(target):
		return ""
	var kind := str(cabin.state_store.definitions[target].get("type", ""))
	var pushable: bool = kind == "pushbutton" or (kind == "breaker" and cabin.state_store.position_name(target) == "PULLED")
	if not pushable: return ""
	var binding = cabin.bindings[target]
	var center: Vector3 = binding.target_global_position()
	var normal: Vector3 = binding.target_surface_normal()
	var offset := tip - center
	var depth := offset.dot(normal)
	var previous_depth := (previous - center).dot(normal)
	var radius := minf(TOUCH_MAX_RADIUS, binding.target_shape.radius)
	if depth < -0.005 or depth > TOUCH_DEPTH or previous_depth <= TOUCH_DEPTH:
		return ""
	if offset.slide(normal).length() > radius: return ""
	var crossing := previous.lerp(tip, (previous_depth - TOUCH_DEPTH) / (previous_depth - depth))
	if (crossing - center).slide(normal).length() > radius or _occluded(previous, tip): return ""
	touch_contacts[hand] = {"id": target, "center": center, "normal": normal, "radius": radius}
	return target

func _sample_controller(hand: String, tip: Vector3, input: Dictionary, delta: float) -> String:
	var contact := ""
	if bool(input.active):
		contact = _touch_target(hand, tip, str(input.target), not bool(input.trigger) and not router.is_holding(hand))
	else:
		touch_positions.erase(hand)
		touch_contacts.erase(hand)
	input.contact = contact
	router.sample(hand, input, delta)
	if not contact.is_empty() and router.selected_id(hand) != contact:
		touch_contacts.erase(hand)
		return ""
	return contact

func _process(delta: float) -> void:
	if not initialized: return
	elapsed += delta
	save_elapsed += delta
	movement_cooldown = maxf(0, movement_cooldown - delta)
	# Polling covers the case where the session was focused before signals connected.
	var previous_focus := focused
	focused = interface.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED
	if previous_focus and not focused:
		_session_unfocused("unfocused")
	# XRCamera3D consumes head/default. The interface-wide tracking status is
	# informational and is not reliably maintained by every Godot/runtime pair.
	var presence_supported := interface.is_user_presence_supported()
	var valid_head := _valid_head_pose(_head_pose(), presence_supported, interface.is_user_present() if presence_supported else true)
	var menu_open: bool = cabin.flight_menu_is_open()
	if menu_open and valid_head and _menu_pose_pending:
		cabin.flight_interface.reposition_xr_menu()
		_menu_pose_pending = false
	var tracked_hands := 0
	for controller: XRController3D in controllers:
		var hand := str(controller.name)
		var tracked := _tracked(controller)
		if tracked: tracked_hands += 1
		var trigger := controller.is_button_pressed(&"trigger_click") or controller.get_float(&"trigger") > 0.65
		if menu_open:
			if hover_status.has(hand): hover_status[hand].hide()
			_sample_menu_controller(controller, hand, tracked and valid_head, trigger)
			continue
		if cabin.notebook != null:
			var grip := controller.is_button_pressed(&"grip_click") or controller.get_float(&"grip") > (0.20 if cabin.notebook.is_held_by(hand) else 0.35)
			if cabin.notebook.sample_hand(hand, _grip_transform(controller), grip, tracked and valid_head, delta, controller.global_transform):
				_consume_notebook_hand(hand, trigger, delta)
				continue
			if cabin.notebook.sample_touch(hand, controller.global_position, tracked and valid_head):
				_consume_notebook_hand(hand, trigger, delta)
				continue
			var distance: float = cabin.notebook.sample_pointer(hand, controller.global_position, -controller.global_basis.z.normalized(), trigger, tracked and valid_head)
			if distance > 0.0:
				_consume_notebook_hand(hand, trigger, delta)
				_draw_surface_pointer(controller, hand, tracked, distance)
				continue
		var target := _target(controller) if tracked else ""
		var contact := _sample_controller(hand, controller.global_position, {
			"active": tracked,
			"trigger": trigger,
			"reverse": controller.is_button_pressed(&"grip_click") or controller.get_float(&"grip") > 0.6,
			"target": target,
			"stick": controller.get_vector2(&"primary") if tracked else Vector2.ZERO,
		}, delta)
		focus[hand] = target if contact.is_empty() else contact
		_update_pointer(controller, tracked, str(focus[hand]), not contact.is_empty())
	if not menu_open:
		_navigate_after_input(delta)
	cabin.focused_id = str(focus.get("right_hand", ""))
	if cabin.focused_id.is_empty(): cabin.focused_id = str(focus.get("left_hand", ""))
	if valid_head: headset_seen = true
	if tracked_hands == 2: both_hands_seen = true
	var valid := valid_head and tracked_hands == 2
	if _last_tracking_valid and not valid: tracking_gaps += 1
	_last_tracking_valid = valid
	_measure_frame(valid and not menu_open, delta)
	_update_hud(tracked_hands, menu_open)
	if save_elapsed >= 5.0:
		save_elapsed = 0
		write_report()
	var duration := float(cabin.argument_value("--xr-duration", "0"))
	if duration > 0 and elapsed >= duration:
		write_report()
		get_tree().quit(0 if headset_seen else 2)

func _sample_menu_controller(controller: XRController3D, hand: String, tracked: bool, trigger: bool) -> void:
	var direction := -controller.global_basis.z.normalized()
	var distance: float = cabin.flight_interface.sample_xr_pointer(hand, controller.global_position, direction, trigger, tracked)
	_draw_surface_pointer(controller, hand, tracked, distance)

func _draw_surface_pointer(controller: XRController3D, hand: String, tracked: bool, distance: float) -> void:
	var direction := -controller.global_basis.z.normalized()
	var hit := tracked and distance > 0.0
	var length := distance if hit else 0.55
	var beam: MeshInstance3D = beams[hand]
	beam.visible = tracked
	var ray_material := _menu_target_material if hit else _menu_ray_material
	if beam.material_override != ray_material:
		beam.material_override = ray_material
	beam.scale.y = length
	beam.position.z = -length * 0.5
	var marker: MeshInstance3D = markers[hand]
	marker.visible = hit
	if marker.material_override != _menu_target_material:
		marker.material_override = _menu_target_material
	if hit:
		marker.global_position = controller.global_position + direction * maxf(0.0, distance - 0.008)
		marker.quaternion = Quaternion(Vector3.UP, controller.global_basis.z.normalized())
	tips[hand].hide()

func _navigate_after_input(delta: float) -> void:
	# Sample both hands before moving the origin so navigation cannot create a poke.
	var before_navigation := origin.transform
	for controller: XRController3D in controllers:
		var hand := str(controller.name)
		if not _tracked(controller) or router.is_holding(hand) or (cabin.notebook != null and cabin.notebook.is_held_by(hand)):
			continue
		var stick := controller.get_vector2(&"primary")
		if _navigation_needs_center.has(hand):
			if stick.length() <= 0.3:
				_navigation_needs_center.erase(hand)
			continue
		_navigate(controller, stick, delta)
	if origin.transform != before_navigation:
		touch_positions.clear()
		if cabin.notebook != null: cabin.notebook.observe("navigation")

func _head_pose() -> XRPose:
	var tracker := XRServer.get_tracker(&"head") as XRPositionalTracker
	return tracker.get_pose(&"default") if tracker != null else null

func _valid_head_pose(pose: XRPose, presence_supported: bool = false, user_present: bool = true) -> bool:
	return focused and pose != null and pose.has_tracking_data and pose.tracking_confidence != XRPose.XR_TRACKING_CONFIDENCE_NONE and (not presence_supported or user_present)

func _head_diagnostics() -> Dictionary:
	var pose := _head_pose()
	var presence_supported := interface.is_user_presence_supported() if initialized else false
	return {
		"tracker": "head",
		"pose": "default",
		"poseExists": pose != null,
		"hasTrackingData": pose.has_tracking_data if pose != null else false,
		"trackingConfidence": int(pose.tracking_confidence) if pose != null else 0,
		"position": [pose.transform.origin.x, pose.transform.origin.y, pose.transform.origin.z] if pose != null else [],
		"userPresenceSupported": presence_supported,
		"userPresent": interface.is_user_present() if presence_supported else null,
		"interfaceTrackingStatusInformational": int(interface.get_tracking_status()) if initialized else null,
		"eligibilitySource": "Focused head/default pose with fresh tracking data and nonzero confidence; user presence enforced only when supported",
	}

func _measure_frame(valid: bool, delta: float) -> void:
	var now := Time.get_ticks_usec()
	if valid:
		tracked_seconds += delta
		focused_warmup += delta
		if focused_warmup >= 3.0 and last_usec > 0 and frame_times.size() < MAX_TIMING_SAMPLES:
			frame_times.append(float(now - last_usec) / 1000.0)
			_sample_metrics()
		last_usec = now
	else:
		last_usec = 0
		focused_warmup = 0.0

func _sample_metrics() -> void:
	metric_samples.processMs.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	metric_samples.physicsMs.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	metric_samples.drawCalls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var viewport_rid := get_viewport().get_viewport_rid()
	metric_samples.renderCpuMs.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid))
	metric_samples.renderSetupCpuMs.append(RenderingServer.get_frame_setup_time_cpu())
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
	# Some renderers do not expose GPU timestamps. Do not turn unavailable zero
	# readings into a claim that rendering consumed no GPU time.
	if gpu_ms > 0.0: metric_samples.renderGpuMs.append(gpu_ms)

func _metric_summary(values: Array) -> Dictionary:
	if values.is_empty(): return {"available": false, "samples": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total += float(value)
	return {"available": true, "samples": sorted.size(), "mean": total / sorted.size(), "p95": float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]), "max": float(sorted[-1])}

func _render_configuration() -> Dictionary:
	var viewport := get_viewport() if is_inside_tree() else null
	var runtime_target := interface.get_render_target_size() if initialized else Vector2.ZERO
	return {
		"requestedRenderer": cabin.argument_value("--xr-renderer", "project default"),
		"hardwareBatching": cabin.cabin_batches.get_stats() if cabin.cabin_batches != null else {"enabled": false},
		"runtimeRenderTargetSize": [runtime_target.x, runtime_target.y],
		"renderTargetSizeMultiplier": float(interface.render_target_size_multiplier) if initialized else 1.0,
		"viewportScaling3DScale": viewport.scaling_3d_scale if viewport != null else 1.0,
		"viewportMsaa3D": viewport.msaa_3d if viewport != null else 0,
		"foveationLevel": interface.foveation_level if initialized else 0,
		"vrsMode": viewport.vrs_mode if viewport != null else 0,
		"resolutionPolicy": "Runtime-recommended target; no application resolution reduction",
	}

func _update_pointer(controller: XRController3D, tracked: bool, target: String, touching: bool) -> void:
	var hand := str(controller.name)
	var beam: MeshInstance3D = beams[hand]
	var marker: MeshInstance3D = markers[hand]
	var tip: MeshInstance3D = tips[hand]
	if hover_status.has(hand):
		# One shared target gets one placard, even with two hands aimed at it.
		var duplicate: bool = hand == "left_hand" and str(focus.get("right_hand", "")) == target and not target.is_empty()
		hover_status[hand].present(target, tracked and not duplicate)
		if tracked and not target.is_empty() and cabin.bindings.has(target) and cabin.notebook != null:
			cabin.notebook.observe("hover")
	if beam.material_override != _ray_material:
		beam.material_override = _ray_material
		marker.material_override = _target_material
	beam.visible = tracked and not touching
	marker.visible = tracked and not touching and not target.is_empty()
	tip.visible = tracked
	var length := 0.5
	if not target.is_empty():
		var binding = cabin.bindings[target]
		var target_position: Vector3 = binding.target_global_position() + binding.target_surface_normal() * 0.012
		length = controller.global_position.distance_to(target_position)
		marker.global_position = target_position
		marker.quaternion = Quaternion(Vector3.UP, binding.target_surface_normal())
	beam.scale.y = maxf(0.01, length)
	beam.position.z = -length * 0.5

func _navigate(controller: XRController3D, stick: Vector2, delta: float) -> void:
	var hand := str(controller.name)
	if hand == "left_hand" and stick.length() > 0.3:
		var heading := camera.global_basis
		var movement := heading.x * stick.x + heading.z * -stick.y
		movement.y = 0
		origin.position += movement.limit_length() * 0.35 * delta
		origin.position.x = clampf(origin.position.x, -0.85, 0.85)
		origin.position.z = clampf(origin.position.z, -0.25, 1.05)
	elif hand == "right_hand" and movement_cooldown <= 0:
		if absf(stick.x) > 0.7:
			var angle := -signf(stick.x) * PI / 6.0
			var head := camera.global_position
			origin.global_position = head + Basis(Vector3.UP, angle) * (origin.global_position - head)
			origin.rotate_y(angle)
			movement_cooldown = 0.35
		elif absf(stick.y) > 0.7:
			origin.position.y = clampf(origin.position.y + signf(stick.y) * 0.08, -0.45, 0.45)
			movement_cooldown = 0.3

func recenter() -> void:
	release_for_menu()
	if cabin.flight_interface != null:
		cabin.flight_interface.cancel_xr_pointer()
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	origin.position = Vector3(0, 0, 0.70)
	origin.rotation = Vector3.ZERO
	_menu_pose_pending = true
	recenter_count += 1
	_session_event("recentered")

func reset_measurement() -> void:
	frame_times.clear()
	for values: Array in metric_samples.values(): values.clear()
	tracked_seconds = 0
	focused_warmup = 0
	last_usec = 0
	_session_event("measurement_restarted")
	cabin._notify("XR frame measurement restarted; keep both controllers tracked for at least 60 seconds.")

func _button_pressed(action: String, controller: XRController3D) -> void:
	if not _tracked(controller): return
	if action == "menu_button":
		recenter()
	elif action == "by_button":
		if cabin.notebook != null: cabin.notebook.observe("menu")
		cabin.toggle_flight_menu()
	elif cabin.flight_menu_is_open():
		return
	elif action == "ax_button" and str(controller.name) == "left_hand":
		if cabin.notebook != null: cabin.notebook.recall()
	elif action == "ax_button" and str(controller.name) == "right_hand":
		if cabin.notebook != null: cabin.notebook.reveal_target()

func _update_hud(tracked_hands: int, menu_open: bool) -> void:
	var current := "OPENXR FOCUSED" if focused else "OPENXR AWAITING FOCUS"
	var tracking := "%s   ·   %d/2 CONTROLLERS\nB/Y FLIGHT MENU   ·   MENU RECENTER" % [current, tracked_hands]
	var objective := ""
	if cabin.notebook == null and cabin.systems != null and cabin.systems.powerdown_card != null and cabin.systems.powerdown_card.visible:
		objective = cabin.systems.powerdown_text.text
	var notification := str(cabin.status_message) if cabin.status_time > 0 else ""
	cabin.flight_hud.present_xr_status(tracking, objective, notification, help_visible and not menu_open)

func _interactive_count() -> int:
	var count := 0
	for id: String in cabin.state_store.definitions:
		if cabin.state_store.is_interactive(id): count += 1
	return count

func build_report() -> Dictionary:
	var sorted := frame_times.duplicate()
	sorted.sort()
	var mean := 0.0
	var missed := 0
	for value: float in sorted:
		mean += value
		if value > FRAME_BUDGET_MS: missed += 1
	if not sorted.is_empty(): mean /= sorted.size()
	var p95: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))] if not sorted.is_empty() else 0.0
	var missing: Array[String] = []
	for id: String in cabin.state_store.definitions:
		if cabin.state_store.is_interactive(id) and not router.operations.has(id): missing.append(id)
	var metrics: Dictionary = {}
	for key: String in metric_samples:
		metrics[key] = _metric_summary(metric_samples[key])
	return {
		"schemaVersion": 1,
		"kind": "Live OpenXR application cadence and controller-operation evidence",
		"startedUtc": started_utc,
		"updatedUtc": Time.get_datetime_string_from_system(true) + "Z",
		"result": "UNAVAILABLE" if not initialized else "INCOMPLETE",
		"failureReason": failure_reason,
		"openxrInitialized": initialized,
		"runtime": interface.get_system_info() if initialized else {},
		"runtimeManifestOverride": OS.get_environment("XR_RUNTIME_JSON"),
		"viewCount": interface.get_view_count() if initialized else 0,
		"headsetPoseObserved": headset_seen,
		"headDiagnostics": _head_diagnostics(),
		"bothControllersObserved": both_hands_seen,
		"controllerDiagnostics": _controller_diagnostics(),
		"currentlyFocused": focused,
		"trackedSeconds": tracked_seconds,
		"trackingGaps": tracking_gaps,
		"trackingLossReleases": router.tracking_releases,
		"interactiveControls": _interactive_count(),
		"exercisedControls": router.operations,
		"unexercisedControls": missing,
		"reverseOperations": router.reverse_operations,
		"recenterCount": recenter_count,
		"inventorySha256": FileAccess.get_sha256(cabin.argument_value("--inventory", cabin.repository_path("reference/controls.json"))),
		"loadingIssues": Array(cabin.load_errors),
		"engine": Engine.get_version_info().string,
		"processId": OS.get_process_id(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"renderConfiguration": _render_configuration(),
		"performanceMonitors": metrics,
		"monitorNotes": "Cadence samples cover cabin operation, with timing suspended in flight menus. Process/physics are Godot performance-monitor readings and may update at one-second intervals. Render CPU/GPU are measured viewport times in milliseconds; unavailable GPU timestamps are marked unavailable. These readings exclude compositor and streaming/encoding latency.",
		"adapter": RenderingServer.get_video_adapter_name(),
		"reportedDisplayRefreshHz": float(interface.display_refresh_rate) if initialized else 0.0,
		"frameTiming": {"sampleFrames": sorted.size(), "sampleLimit": MAX_TIMING_SAMPLES, "meanMs": mean, "p95Ms": p95, "maxMs": sorted[-1] if not sorted.is_empty() else 0.0, "targetHz": 72, "budgetMs": FRAME_BUDGET_MS, "overBudgetFrames": missed, "observedCadenceHz": 1000.0 / mean if mean > 0 else 0.0, "warmupTrackedSeconds": 3.0},
		"sessionEvents": session_events,
		"physicalAcceptance": {"reach": "pending operator review", "legibility": "pending operator review", "allControlPositions": "pending operator review", "comfort": "pending operator review", "compositorDroppedFrames": "not measured by application"},
		"gatePassed": false,
		"note": "Application intervals do not measure compositor/reprojection. Physical reach and readability require operator confirmation; runtime initialization alone never passes the headset gate.",
	}

func _controller_diagnostics() -> Array:
	var diagnostics: Array = []
	for controller: XRController3D in controllers:
		var tracker = XRServer.get_tracker(controller.tracker)
		var poses: Dictionary = {}
		if tracker != null:
			for pose_name: String in ["aim", "grip", "default"]:
				var pose = tracker.get_pose(pose_name)
				poses[pose_name] = {"exists": pose != null, "tracked": pose.has_tracking_data if pose != null else false}
		diagnostics.append({"hand": str(controller.name), "tracker": str(controller.tracker), "trackerPresent": tracker != null, "active": controller.get_is_active(), "trackingData": controller.get_has_tracking_data(), "pose": str(controller.pose), "poses": poses, "trigger": controller.get_float(&"trigger"), "grip": controller.get_float(&"grip")})
	return diagnostics

func write_report() -> void:
	if report_path.is_empty(): return
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write XR report: " + report_path)
		return
	file.store_string(JSON.stringify(build_report(), "\t"))
	file.close()

func _exit_tree() -> void:
	if cabin != null and is_instance_valid(cabin):
		router.release_all()
		write_report()
