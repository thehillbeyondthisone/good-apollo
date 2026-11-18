extends Node
## Presents one menu canvas on the desktop or on a world-space OpenXR panel.

const Menu = preload("res://scripts/flight_menu.gd")
const MENU_SIZE := Vector2i(1440, 900)
const PANEL_WIDTH := 1.44
const PANEL_SIZE := Vector2(PANEL_WIDTH, PANEL_WIDTH * MENU_SIZE.y / MENU_SIZE.x)
const OUTSIDE := Vector2(-100, -100)

var cabin: Node3D
var page := ""
var menu: Control
var _surface: SubViewport
var _screen: Control
var _matte: ColorRect
var _image: TextureRect
var _panel: MeshInstance3D
var _xr := false
var _pointer_hand := ""
var _pointer_down := false
var _pointer_position := OUTSIDE
var _triggers: Dictionary = {}
var _hand_positions: Dictionary = {}

func setup(owner_cabin: Node3D) -> void:
	cabin = owner_cabin
	process_mode = Node.PROCESS_MODE_ALWAYS
	_surface = SubViewport.new()
	_surface.name = "FlightMenuCanvas"
	_surface.size = MENU_SIZE
	_surface.disable_3d = true
	_surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_surface)
	menu = Menu.new()
	_surface.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.action_requested.connect(cabin.handle_flight_action, CONNECT_DEFERRED)

	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_screen = Control.new()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_matte = ColorRect.new()
	_matte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(_matte)
	_matte.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_image = TextureRect.new()
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.texture = _surface.get_texture()
	_screen.add_child(_image)
	_screen.resized.connect(_fit_desktop)
	_screen.hide()
	_fit_desktop()

func show_page(next: String, xr: bool, status: Dictionary) -> void:
	var placement_changed := page.is_empty() or _xr != xr
	page = next
	_xr = xr
	menu.show()
	_surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_screen.visible = not _xr
	_matte.color = Color("#060d16") if page != "pause" else Color(0.026, 0.051, 0.086, 0.83)
	if _xr:
		if _panel == null:
			_create_panel()
		_panel.show()
		if placement_changed:
			reposition_xr_menu()
	menu.show_page(page, _xr, status)

func dismiss() -> void:
	cancel_xr_pointer()
	page = ""
	menu.hide()
	_screen.hide()
	if _panel != null:
		_panel.hide()
	_surface.render_target_update_mode = SubViewport.UPDATE_DISABLED

func back() -> void:
	cancel_xr_pointer()
	menu.back()

func _fit_desktop() -> void:
	var bounds := _screen.size
	var scale_factor := minf(bounds.x / MENU_SIZE.x, bounds.y / MENU_SIZE.y)
	_image.size = Vector2(MENU_SIZE) * scale_factor
	_image.position = (bounds - _image.size) * 0.5

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if event.pressed and not event.echo:
			cabin.toggle_flight_menu()
		get_viewport().set_input_as_handled()
		return
	if page.is_empty():
		return
	get_viewport().set_input_as_handled()
	if _xr or not (event is InputEventMouse or event is InputEventKey):
		return
	if event is InputEventMouse:
		if _image.size.x <= 0.0:
			return
		var mapped := event.duplicate() as InputEventMouse
		var ratio := float(MENU_SIZE.x) / _image.size.x
		mapped.position = (event.position - _image.position) * ratio
		mapped.global_position = mapped.position
		if mapped is InputEventMouseMotion:
			mapped.relative *= ratio
		_surface.push_input(mapped, true)
	else:
		_surface.push_input(event.duplicate(), true)

func _create_panel() -> void:
	_panel = MeshInstance3D.new()
	_panel.name = "FlightMenuPanel"
	var quad := QuadMesh.new()
	quad.size = PANEL_SIZE
	_panel.mesh = quad
	_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.disable_fog = true
	material.render_priority = 24
	material.albedo_texture = _surface.get_texture()
	_panel.material_override = material
	cabin.add_child(_panel)

func reposition_xr_menu() -> void:
	if _panel == null or page.is_empty() or cabin.active_camera == null:
		return
	cancel_xr_pointer()
	var camera: Camera3D = cabin.active_camera
	var toward_viewer := camera.global_basis.z.slide(Vector3.UP).normalized()
	if toward_viewer.is_zero_approx():
		toward_viewer = Vector3.BACK
	_panel.global_transform = Transform3D(
		Basis(Vector3.UP.cross(toward_viewer), Vector3.UP, toward_viewer),
		camera.global_position - toward_viewer * 1.30 - Vector3.UP * 0.10
	)

func sample_xr_pointer(hand: String, ray_origin: Vector3, ray_direction: Vector3, trigger_down: bool, tracked: bool) -> float:
	if _panel == null or page.is_empty() or not _xr:
		return -1.0
	if not tracked:
		_triggers.erase(hand)
		_hand_positions.erase(hand)
		if _pointer_hand == hand:
			_cancel_click()
		return -1.0
	var new_press: bool = trigger_down and not _triggers.get(hand, true)
	_triggers[hand] = trigger_down
	var direction := _panel.global_basis.inverse() * ray_direction
	var origin := _panel.to_local(ray_origin)
	var distance := -origin.z / direction.z if direction.z < -0.0001 else -1.0
	var hit := origin + direction * distance
	var uv := Vector2(hit.x / PANEL_SIZE.x + 0.5, 0.5 - hit.y / PANEL_SIZE.y)
	var on_panel := distance > 0.0 and Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv)
	var position := uv * Vector2(MENU_SIZE) if on_panel else OUTSIDE
	var previous: Vector2 = _hand_positions.get(hand, OUTSIDE)
	_hand_positions[hand] = position
	if _pointer_down and _pointer_hand != hand:
		return distance if on_panel else -1.0
	if on_panel:
		# A resting second hand should not steal hover from the active ray.
		if not _pointer_hand.is_empty() and _pointer_hand != hand and not new_press and previous.distance_squared_to(position) < 64.0:
			return distance
		_pointer_hand = hand
		_move_pointer(position)
		if new_press and not _pointer_down:
			_click_pointer(true)
		elif not trigger_down and _pointer_down:
			_click_pointer(false)
	elif _pointer_hand == hand:
		_move_pointer(OUTSIDE)
		if not trigger_down and _pointer_down:
			_click_pointer(false)
		if not _pointer_down:
			_pointer_hand = ""
	return distance if on_panel else -1.0

func cancel_xr_pointer() -> void:
	if _panel != null:
		_cancel_click()
	_triggers.clear()
	_hand_positions.clear()

func _cancel_click() -> void:
	_move_pointer(OUTSIDE)
	if _pointer_down:
		_click_pointer(false)
	_pointer_hand = ""

func _move_pointer(position: Vector2) -> void:
	if _pointer_position.is_equal_approx(position):
		return
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	motion.relative = position - _pointer_position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _pointer_down else 0
	_pointer_position = position
	_surface.push_input(motion, true)

func _click_pointer(down: bool) -> void:
	_pointer_down = down
	var click := InputEventMouseButton.new()
	click.position = _pointer_position
	click.global_position = _pointer_position
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	click.pressed = down
	_surface.push_input(click, true)
