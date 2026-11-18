extends Node3D
## A hand-positioned free-floating flight book. Movement is deliberate.

const Guidance = preload("res://scripts/procedure_guidance.gd")
const FloatingBody = preload("res://scripts/free_float_body.gd")
const Hud = preload("res://scripts/flight_hud.gd")
const SIZE := Vector2i(700, 960)
const PAPER := Color("#e5dfcb")
const INK := Color("#273b3c")
const AMBER := Color("#a25c2e")
const BOOK_SIZE := Vector2(0.32, 0.439)
const GRAB_REACH := 0.14
const GRAB_RAY_REACH := 1.2
var cabin: Node3D
var guidance = Guidance.new()
var current_page: Dictionary = {}
var surface: SubViewport
var book: MeshInstance3D
var body: RigidBody3D
var onboarding: RefCounted
var desktop: TextureRect
var desktop_layer: CanvasLayer
var station_page: TextureRect
var fields: Dictionary = {}
var confirm_button: Button
var stow_button: Button
var find_button: Button
var awaiting_label: Label
var target_ring: MeshInstance3D
var panel_frame: Node3D
var expanded := true
var _poll := 0.0
var _phase := 0.0
var _signature := ""
var _callout := ""
var _triggers: Dictionary = {}
var _pointer_hand := ""
var _pointer_down := false
var _book_pose_set := false
var _grab_armed: Dictionary = {}
var _touches: Dictionary = {}
var _touch_history: Dictionary = {}
var highlighter: Node3D

func setup(owner: Node3D) -> void:
	cabin = owner
	process_mode = Node.PROCESS_MODE_ALWAYS
	surface = SubViewport.new()
	surface.name = "FlightNotebookPages"
	surface.size = SIZE
	surface.disable_3d = true
	surface.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(surface)
	_build_page()
	body = FloatingBody.new()
	body.name = "FreeFloatingFlightBook"
	add_child(body)
	body.configure(Vector3(BOOK_SIZE.x, BOOK_SIZE.y, 0.008), 0.25)
	var cover := MeshInstance3D.new()
	var cover_mesh := BoxMesh.new()
	cover_mesh.size = Vector3(BOOK_SIZE.x + 0.004, BOOK_SIZE.y + 0.004, 0.008)
	cover.mesh = cover_mesh
	var cover_material := StandardMaterial3D.new()
	cover_material.albedo_color = Color("#47524c")
	cover.material_override = cover_material
	body.add_child(cover)
	book = MeshInstance3D.new()
	book.name = "CrewFlightNotebook"
	var sheet := QuadMesh.new()
	sheet.size = BOOK_SIZE
	book.mesh = sheet
	var paper := StandardMaterial3D.new()
	paper.albedo_texture = surface.get_texture()
	paper.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	book.material_override = paper
	book.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(book)
	book.position.z = 0.0045
	book.hide()
	body.freeze = true
	desktop_layer = CanvasLayer.new()
	desktop_layer.layer = 18
	add_child(desktop_layer)
	desktop = TextureRect.new()
	desktop.texture = surface.get_texture()
	desktop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desktop.mouse_filter = Control.MOUSE_FILTER_STOP
	desktop.gui_input.connect(_desktop_input.bind(desktop))
	desktop_layer.add_child(desktop)
	var slot := cabin.systems.odyssey.station.find_child("ProcedureNotebookSlot", true, false) as PanelContainer
	if slot != null:
		for child: Control in slot.get_children(): child.hide()
		station_page = TextureRect.new()
		station_page.texture = surface.get_texture()
		station_page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		station_page.gui_input.connect(_desktop_input.bind(station_page))
		slot.add_child(station_page)
	cabin.systems.powerdown_card.modulate.a = 0.0
	if not "--self-test" in OS.get_cmdline_user_args() or "--onboarding-test" in OS.get_cmdline_user_args():
		onboarding = load("res://scripts/cabin_onboarding.gd").new()
	_create_highlights()
	refresh()

func _text(parent: Control, key: String, rect: Rect2, size: int, color := INK) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = ""
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", Hud.typeface(true))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.set_meta("page_height", rect.size.y)
	label.set_meta("page_font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	fields[key] = label
	return label

func _rect(parent: Control, rect: Rect2, color: Color) -> void:
	var patch := ColorRect.new()
	patch.position = rect.position
	patch.size = rect.size
	patch.color = color
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(patch)

func _build_page() -> void:
	var page := Control.new()
	page.size = Vector2(SIZE)
	surface.add_child(page)
	_rect(page, Rect2(0, 0, 700, 960), Color("#545e5b"))
	_rect(page, Rect2(12, 8, 680, 944), PAPER)
	_rect(page, Rect2(48, 8, 2, 944), Color("#c5b7a0"))
	for y in range(90, 900, 148):
		_rect(page, Rect2(5, y, 32, 10), Color("#293839"))
		_rect(page, Rect2(7, y, 30, 3), Color("#afb8b2"))
	_rect(page, Rect2(69, 45, 580, 3), INK)
	_text(page, "identity", Rect2(70, 60, 510, 34), 21).text = "APOLLO 13 / CREW FLIGHT BOOK"
	_text(page, "chapter", Rect2(70, 104, 580, 30), 19, AMBER)
	_text(page, "title", Rect2(70, 145, 580, 85), 31)
	_text(page, "context", Rect2(70, 238, 580, 116), 22)
	_rect(page, Rect2(70, 364, 580, 2), Color("#b5b09c"))
	_text(page, "find", Rect2(70, 380, 580, 55), 21, AMBER)
	_text(page, "action", Rect2(70, 445, 580, 180), 25)
	_text(page, "gesture", Rect2(70, 627, 580, 88), 20)
	_text(page, "check", Rect2(70, 727, 580, 30), 21, AMBER).text = "03 / CHECK"
	_text(page, "verify", Rect2(70, 763, 580, 90), 21)
	confirm_button = _button(page, Rect2(70, 867, 310, 50), "CONFIRM / CONTINUE")
	confirm_button.pressed.connect(confirm)
	awaiting_label = _text(page, "awaiting", Rect2(70, 865, 310, 57), 18, AMBER)
	stow_button = _button(page, Rect2(540, 867, 110, 50), "STOW")
	stow_button.pressed.connect(toggle_focus)
	find_button = _button(page, Rect2(390, 867, 140, 50), "FIND")
	find_button.pressed.connect(reveal_target)
	_text(page, "footer", Rect2(70, 927, 580, 22), 14).text = "LM-7    AQUARIUS    /    FLIGHT PROCEDURES"

func _button(parent: Control, rect: Rect2, text: String) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = text
	button.add_theme_font_override("font", Hud.typeface(true))
	button.add_theme_font_size_override("font_size", 18)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#b8b7a5") if state == "disabled" else (Color("#c6cbbb") if state == "normal" else Color("#e6b680"))
		style.set_border_width_all(2)
		style.border_color = Color("#7a8276")
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), INK)
	parent.add_child(button)
	return button

func _create_highlights() -> void:
	highlighter = load("res://scripts/procedure_highlight.gd").new()
	add_child(highlighter)
	highlighter.setup(cabin)
	target_ring = highlighter.target_ring
	panel_frame = highlighter.panel_frame

func refresh() -> void:
	if cabin.systems != null: cabin.systems.powerdown_card.hide()
	current_page = onboarding.page(cabin) if onboarding != null and onboarding.active else guidance.page(cabin)
	var signature := JSON.stringify(current_page)
	if signature == _signature: return
	_signature = signature
	var callout := str(current_page.get("chapter", "")) + str(current_page.get("count", "")) + str(current_page.get("target", ""))
	if callout != _callout:
		_callout = callout
		highlighter.reveal_target(5.0)
	for key: String in ["title", "context", "gesture", "verify"]:
		fields[key].text = str(current_page.get(key, ""))
	fields.chapter.text = "%s  /  %s" % [current_page.get("chapter", ""), current_page.get("count", "")]
	fields.find.text = "01 / FIND   " + str(current_page.get("location", "FLIGHT BOOK"))
	fields.action.text = "02 / DO\n" + str(current_page.get("action", ""))
	confirm_button.disabled = not current_page.get("confirm", false)
	confirm_button.visible = not confirm_button.disabled
	confirm_button.text = str(current_page.get("button_label", "CONFIRM STEP"))
	awaiting_label.visible = confirm_button.disabled
	find_button.visible = not str(current_page.get("target", "")).is_empty()
	awaiting_label.text = str(current_page.get("awaiting", "DO THE ACTION ABOVE / AUTO-ADVANCES")) if current_page.has("target") else "FOLLOW THE INSTRUCTION ABOVE"
	_update_stow_text()
	for label: Label in fields.values():
		var font_size: int = label.get_meta("page_font_size")
		label.add_theme_font_size_override("font_size", font_size)
		while label.get_line_count() * label.get_line_height() > float(label.get_meta("page_height")) and font_size > 16:
			font_size -= 1
			label.add_theme_font_size_override("font_size", font_size)
	# Keep the former HUD source available to tests and desktop compatibility,
	# while presenting the actual procedure on paper rather than twice in XR.
	if cabin.systems != null: cabin.systems.powerdown_card.hide()
	surface.render_target_update_mode = SubViewport.UPDATE_ONCE

func confirm() -> void:
	if not current_page.get("confirm", false): return
	if onboarding != null and onboarding.active:
		onboarding.action(cabin)
	elif guidance.action(cabin):
		pass
	elif cabin.systems.odyssey.active():
		cabin.systems.odyssey.confirm()
	elif cabin.systems.correction.active() and cabin.systems.correction.phase != Guidance.Correction.Phase.COMPLETE:
		cabin.systems.correction.confirm()
	else:
		cabin.systems.confirm_powerdown_callout()
	refresh()

func toggle_focus() -> void:
	if cabin.systems.odyssey.active():
		cabin.systems.odyssey.radio.repeat()
		return
	if cabin.xr_active:
		if expanded:
			expanded = false
			release_hands(false)
			cancel_pointer()
		else:
			recall()
	else:
		expanded = not expanded
	_update_stow_text()

func observe(event: String) -> void:
	if onboarding != null and onboarding.active:
		onboarding.observe(event)

func recall() -> void:
	if not cabin.xr_active: cabin._hud_enabled = true
	expanded = true
	release_hands(false)
	cancel_pointer()
	var camera: Camera3D = cabin.active_camera
	if camera != null:
		var clear := false
		for offset: Vector3 in [Vector3(-0.17, 0.02, -0.56), Vector3(-0.14, 0.02, -0.44), Vector3(-0.10, 0.02, -0.32), Vector3(0, 0.18, -0.35), Vector3(0.16, 0.02, -0.44)]:
			var pose := Transform3D(camera.global_basis, camera.global_transform * offset)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = body.get_child(0).shape
			query.transform = pose
			query.collision_mask = 16 | 64
			query.exclude = [body.get_rid()]
			if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
			body.place(pose)
			_book_pose_set = true
			clear = true
			break
		if not clear:
			cabin._notify("Move back from the panel, then press X to recall the notebook into clear space.")
	_update_stow_text()
	observe("recall")

func reveal_target() -> void:
	observe("locate")
	var id: String = str(current_page.get("target", ""))
	if id.is_empty():
		cabin._notify("Read the current flight-book instruction. No control is required for this step.")
		return
	highlighter.update_target(id, true)
	highlighter.reveal_target()
	if not cabin.xr_active and cabin.bindings.has(id): cabin._inspect_checklist_control(id)
	var definition: Dictionary = cabin.state_store.definitions.get(id, {})
	cabin._notify("LOOK FOR THE AMBER BEACON / " + str(definition.get("label", id.replace("_", " "))))

func _update_stow_text() -> void:
	var radio: bool = cabin.systems.odyssey.active()
	stow_button.text = "REPEAT RADIO" if radio else ("STOW" if expanded else "OPEN")
	stow_button.position.x = 433 if radio else 540
	stow_button.size.x = 217 if radio else 110
	surface.render_target_update_mode = SubViewport.UPDATE_ONCE

func _process(delta: float) -> void:
	_phase += delta
	_poll += delta
	if _poll > 0.1:
		_poll = 0.0
		refresh()
	var showing: bool = not cabin.flight_menu_is_open() and (cabin.xr_active or cabin._hud_enabled) and not current_page.is_empty()
	desktop.visible = showing and not cabin.xr_active and not cabin.systems.odyssey.active()
	if desktop.visible:
		var width := 350.0 if expanded else 126.0
		desktop.position = Vector2(get_viewport().get_visible_rect().size.x - width - 24, 100)
		desktop.size = Vector2(width, width * SIZE.y / SIZE.x)
	book.visible = showing and cabin.xr_active and expanded
	body.visible = book.visible
	if book.visible and not _book_pose_set: recall()
	if body.held_by.is_empty(): body.freeze = not book.visible
	_update_highlights(showing)

func _update_highlights(showing: bool) -> void:
	highlighter.update_target(str(current_page.get("target", "")), showing)

func is_held_by(hand: String) -> bool:
	return body.held_by == hand

func release_hands(throw_on_release: bool = false) -> void:
	body.end_hold(throw_on_release)
	_grab_armed.clear()
	_touches.clear()
	_touch_history.clear()

func sample_hand(hand: String, pose: Transform3D, grip: bool, tracked: bool, delta: float, aim_pose: Variant = null) -> bool:
	if not tracked or not book.visible:
		if is_held_by(hand): body.end_hold(false)
		_grab_armed.erase(hand)
		return false
	# Release once after focus/tracking returns. Thereafter a squeeze can begin
	# before the hand reaches the book, without requiring another precise press.
	if not grip: _grab_armed[hand] = true
	if is_held_by(hand):
		if not grip:
			body.end_hold(true)
			observe("release")
		else:
			body.move_held(pose, delta)
		return true
	if not body.held_by.is_empty() or not grip or not _grab_armed.get(hand, false): return false
	if not can_grab(pose, aim_pose): return false
	cancel_pointer()
	body.begin_hold(hand, pose)
	_grab_armed[hand] = false
	observe("grab")
	return true

func can_grab(pose: Transform3D, aim_pose: Variant = null) -> bool:
	var point := book.to_local(pose.origin)
	var closest := Vector3(clampf(point.x, -BOOK_SIZE.x * 0.5, BOOK_SIZE.x * 0.5), clampf(point.y, -BOOK_SIZE.y * 0.5, BOOK_SIZE.y * 0.5), 0)
	var start := pose.origin
	var end := book.to_global(closest)
	if point.distance_to(closest) > GRAB_REACH:
		if aim_pose == null: return false
		var aim: Transform3D = aim_pose
		var local_origin := book.to_local(aim.origin)
		var direction := book.global_basis.inverse() * -aim.basis.z.normalized()
		if absf(direction.z) < 0.0001: return false
		var distance := -local_origin.z / direction.z
		if distance <= 0 or distance > GRAB_RAY_REACH: return false
		var hit := local_origin + direction * distance
		if absf(hit.x) > BOOK_SIZE.x * 0.5 + 0.04 or absf(hit.y) > BOOK_SIZE.y * 0.5 + 0.04: return false
		start = aim.origin
		end = book.to_global(hit)
	var query := PhysicsRayQueryParameters3D.create(start, end, 16 | 64)
	query.exclude = [body.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func sample_touch(hand: String, tip: Vector3, tracked: bool) -> bool:
	if not tracked or not book.visible or is_held_by(hand):
		if _touches.has(hand): cancel_pointer(hand)
		_touches.erase(hand)
		_touch_history.erase(hand)
		return false
	var point := book.to_local(tip)
	var previous: Vector3 = _touch_history.get(hand, point)
	_touch_history[hand] = point
	var uv := Vector2(point.x / BOOK_SIZE.x + 0.5, 0.5 - point.y / BOOK_SIZE.y)
	var within := Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv)
	if _touches.has(hand):
		if not within or point.z > 0.028 or point.z < -0.014:
			_touch_click(hand, uv * Vector2(SIZE) if within else Vector2(-100, -100), false)
			_touches.erase(hand)
		return true
	if _pointer_down or not within or previous.z <= 0.014 or point.z > 0.010 or point.z < -0.008: return false
	_touches[hand] = true
	_touch_click(hand, uv * Vector2(SIZE), true)
	return true

func _touch_click(hand: String, point: Vector2, down: bool) -> void:
	_pointer_hand = hand
	_pointer_down = down
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	surface.push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.position = point
	click.global_position = point
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	click.pressed = down
	surface.push_input(click, true)
	if not down: _pointer_hand = ""
	surface.render_target_update_mode = SubViewport.UPDATE_ONCE

func _desktop_input(event: InputEvent, view: TextureRect) -> void:
	if event is InputEventMouseMotion:
		var motion := event.duplicate() as InputEventMouseMotion
		motion.position = event.position / view.size * Vector2(SIZE)
		motion.global_position = motion.position
		surface.push_input(motion, true)
		surface.render_target_update_mode = SubViewport.UPDATE_ONCE
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not expanded and view == desktop and event.pressed:
			toggle_focus()
			return
		var click := event.duplicate() as InputEventMouseButton
		click.position = event.position / view.size * Vector2(SIZE)
		click.global_position = click.position
		surface.push_input(click, true)
		surface.render_target_update_mode = SubViewport.UPDATE_ONCE

func cancel_pointer(hand: String = "") -> void:
	if hand.is_empty() or _pointer_hand == hand:
		if _pointer_down:
			var move := InputEventMouseMotion.new()
			move.position = Vector2(-100, -100)
			move.global_position = move.position
			move.button_mask = MOUSE_BUTTON_MASK_LEFT
			surface.push_input(move, true)
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.position = Vector2(-100, -100)
			release.global_position = release.position
			surface.push_input(release, true)
		_pointer_down = false
		_pointer_hand = ""
	if hand.is_empty():
		_triggers.clear()
	else:
		_triggers.erase(hand)

func sample_pointer(hand: String, origin: Vector3, direction: Vector3, trigger: bool, tracked: bool) -> float:
	if not tracked or not book.visible:
		cancel_pointer(hand)
		return -1.0
	var fresh: bool = trigger and not _triggers.get(hand, true)
	_triggers[hand] = trigger
	var local_origin := book.to_local(origin)
	var local_direction := book.global_basis.inverse() * direction
	var distance := -local_origin.z / local_direction.z if local_direction.z < -0.0001 else -1.0
	var hit := local_origin + local_direction * distance
	var uv := Vector2(hit.x / BOOK_SIZE.x + 0.5, 0.5 - hit.y / BOOK_SIZE.y)
	var on_page := distance > 0.0 and Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv)
	if _pointer_down and _pointer_hand != hand: return distance if on_page else -1.0
	if on_page and not expanded:
		if fresh: toggle_focus()
		return distance
	var cursor := uv * Vector2(SIZE) if on_page else Vector2(-100, -100)
	if on_page or _pointer_hand == hand:
		var move := InputEventMouseMotion.new()
		move.position = cursor
		move.global_position = cursor
		move.button_mask = MOUSE_BUTTON_MASK_LEFT if _pointer_down else 0
		surface.push_input(move, true)
		if on_page and fresh and not _pointer_down:
			_pointer_down = true
			_pointer_hand = hand
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_LEFT
			down.pressed = true
			down.position = cursor
			down.global_position = cursor
			down.button_mask = MOUSE_BUTTON_MASK_LEFT
			surface.push_input(down, true)
		elif not trigger and _pointer_down:
			var up := InputEventMouseButton.new()
			up.button_index = MOUSE_BUTTON_LEFT
			up.position = cursor
			up.global_position = cursor
			surface.push_input(up, true)
			_pointer_down = false
			_pointer_hand = ""
		surface.render_target_update_mode = SubViewport.UPDATE_ONCE
	return distance if on_page else -1.0
