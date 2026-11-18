extends Control
## Flight instrumentation shared by the desktop overlay and headset panels.

const INK := Color("#07111c")
const PANEL := Color("#0c1b29")
const STROKE := Color("#365265")
const COOL := Color("#a9c9db")
const PAPER := Color("#edf5ed")
const ACCENT := Color("#ff9c5b")
const XR_SURFACE := Vector2i(1040, 410)

static var _display_font: SystemFont
static var _instrument_font: SystemFont

var title_label: Label
var mode_label: Label
var focus_label: Label
var help_label: Label
var crosshair: Label
var checklist_marker: Label

var _instrument_layer: Control
var _telemetry_card: PanelContainer
var _electrical_label: Label
var _clock_label: Label
var _agc_label: Label
var _qualifications_label: Label
var _interaction_stack: VBoxContainer
var _focus_card: PanelContainer
var _toast_card: PanelContainer
var _toast_text: Label
var _shortcuts: PanelContainer
var _marker_phase := 0.0
var _last_mode := ""
var _checklist_card: PanelContainer
var _checklist_source: Label
var _checklist_heading: Label
var _checklist_body: Label

var _xr_mesh: MeshInstance3D
var _xr_viewport: SubViewport
var _xr_telemetry: PanelContainer
var _xr_tracking_heading: Label
var _xr_tracking_body: Label
var _xr_systems: Label
var _xr_system_summary := ""
var _xr_toast: PanelContainer
var _xr_toast_text: Label
var _xr_objective: PanelContainer
var _xr_objective_heading: Label
var _xr_objective_body: Label


class Reticle extends Label:
	var objective := false
	var phase := 0.0

	func _draw() -> void:
		var center := size * 0.5
		if objective:
			var radius := 10.0 + sin(phase) * 1.3
			draw_arc(center, radius, 0.0, TAU, 36, Color("#07111c"), 4.0, true)
			draw_arc(center, radius, 0.0, TAU, 36, Color("#ff9c5b"), 1.4, true)
			for index in 4:
				var axis := Vector2.RIGHT.rotated(index * PI * 0.5)
				draw_line(center + axis * (radius + 3.0), center + axis * (radius + 7.0), Color("#ff9c5b"), 1.3, true)
			return
		var rim := Color("#edf5ed")
		draw_circle(center, 3.0, Color("#07111c"), true, -1.0, true)
		draw_circle(center, 1.4, rim, true, -1.0, true)
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(center + direction * 6.0, center + direction * 11.0, Color("#07111c"), 3.5, true)
			draw_line(center + direction * 6.0, center + direction * 11.0, rim, 1.2, true)


class CabinGlyph extends Control:
	func _draw() -> void:
		var tint := Color("#ff9c5b")
		draw_arc(Vector2(16, 16), 14.0, -PI * 0.39, PI * 1.39, 35, Color("#365265"), 1.0, true)
		draw_polyline(PackedVector2Array([Vector2(5, 23), Vector2(10, 23), Vector2(12, 17), Vector2(8, 15), Vector2(12, 10), Vector2(20, 10), Vector2(24, 15), Vector2(20, 17), Vector2(22, 23), Vector2(27, 23)]), tint, 1.25, true)
		draw_line(Vector2(11, 19), Vector2(21, 19), tint, 1.25, true)
		draw_circle(Vector2(16, 5), 1.3, tint, true, -1.0, true)


func _ready() -> void:
	name = "FlightHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_instrument_layer = Control.new()
	_instrument_layer.name = "Instruments"
	_instrument_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_instrument_layer)
	_instrument_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_telemetry()
	_build_interaction()
	_build_reticles()
	resized.connect(_layout_desktop)
	_layout_desktop()


static func typeface(instrument: bool) -> SystemFont:
	if _display_font == null:
		_display_font = SystemFont.new()
		_display_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "DIN Alternate", "DejaVu Sans"])
		_display_font.font_weight = 600
		_instrument_font = SystemFont.new()
		_instrument_font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Menlo"])
	return _instrument_font if instrument else _display_font


func _text(parent: Control, value: String, font_size: int, color: Color, instrument := false, wrap := false) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", typeface(instrument))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 4)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = value
	parent.add_child(label)
	return label


static func plate_style(primary: Color, gutter := 15.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL, 0.95)
	style.set_border_width_all(1)
	style.border_width_left = 2
	style.border_color = primary
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 3
	style.content_margin_left = gutter + 2
	style.content_margin_right = gutter
	style.content_margin_top = gutter
	style.content_margin_bottom = gutter
	style.shadow_color = Color(INK, 0.28)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style


func _panel(parent: Control, panel_name: String, color: Color, padding := 12.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", plate_style(color, padding))
	parent.add_child(panel)
	return panel


func _stack(parent: Control, spacing: int) -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", spacing)
	parent.add_child(stack)
	return stack


func _row(parent: Control, spacing: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", spacing)
	parent.add_child(row)
	return row


func _divider(parent: Control) -> void:
	var rule := ColorRect.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.color = Color(STROKE, 0.85)
	rule.custom_minimum_size.y = 1
	parent.add_child(rule)


func _build_telemetry() -> void:
	_telemetry_card = _panel(_instrument_layer, "FlightTelemetry", STROKE)
	_telemetry_card.minimum_size_changed.connect(_fit_height.bind(_telemetry_card), CONNECT_DEFERRED)
	var stack := _stack(_telemetry_card, 6)
	var heading := _row(stack, 10)
	var glyph := CabinGlyph.new()
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.custom_minimum_size = Vector2(32, 32)
	heading.add_child(glyph)
	title_label = _text(heading, "AQUARIUS / LM-7", 25, PAPER)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock_label = _text(heading, "", 13, COOL, true)
	_divider(stack)
	_electrical_label = _text(stack, "CABIN STUDY", 15, COOL, true, true)
	_agc_label = _text(stack, "", 14, PAPER, true, true)
	_qualifications_label = _text(stack, "", 13, COOL, true, true)
	# The presenter supplies the canonical unabridged status string here.
	mode_label = _text(self, "CABIN STUDY", 14, PAPER)
	mode_label.hide()


func _build_interaction() -> void:
	_interaction_stack = _stack(_instrument_layer, 9)
	_interaction_stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_interaction_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_interaction_stack.minimum_size_changed.connect(_fit_height.bind(_interaction_stack, true), CONNECT_DEFERRED)
	_toast_card = _panel(_interaction_stack, "FlightNotice", ACCENT)
	var toast := _stack(_toast_card, 3)
	_text(toast, "FLIGHT NOTICE", 13, ACCENT, true)
	_toast_text = _text(toast, "", 18, PAPER, false, true)
	_toast_card.hide()
	_focus_card = _panel(_interaction_stack, "ControlFocus", STROKE)
	var focus_stack := _stack(_focus_card, 3)
	_text(focus_stack, "CONTROL IN SIGHT", 13, COOL, true)
	focus_label = _text(focus_stack, "", 20, PAPER, false, true)
	_focus_card.hide()
	help_label = _text(_interaction_stack, "RMB LOOK   /   WASD MOVE   /   CLICK OPERATE", 14, COOL, true, true)
	help_label.add_theme_color_override("font_shadow_color", Color(INK, 0.98))
	help_label.add_theme_constant_override("shadow_offset_x", 1)
	help_label.add_theme_constant_override("shadow_offset_y", 2)
	_shortcuts = _panel(_instrument_layer, "FlightShortcuts", STROKE, 7.0)
	_shortcuts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_shortcuts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_shortcuts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var shortcuts := _row(_shortcuts, 9)
	_key_prompt(shortcuts, "ESC", "MENU")
	_key_prompt(shortcuts, "F1", "HUD")


func _key_prompt(parent: Control, key: String, meaning: String) -> void:
	var keycap := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = STROKE
	style.set_corner_radius_all(2)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	keycap.add_theme_stylebox_override("panel", style)
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(keycap)
	_text(keycap, key, 13, PAPER, true)
	_text(parent, meaning, 13, COOL, true)


func _build_reticles() -> void:
	var aim := Reticle.new()
	aim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_instrument_layer.add_child(aim)
	aim.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	aim.offset_left = -13
	aim.offset_right = 13
	aim.offset_top = -13
	aim.offset_bottom = 13
	aim.hide()
	crosshair = aim
	var marker := Reticle.new()
	marker.objective = true
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.size = Vector2(36, 36)
	marker.hide()
	_instrument_layer.add_child(marker)
	checklist_marker = marker


func _layout_desktop() -> void:
	var edge := 28.0 if size.x >= 1000 else 16.0
	var telemetry_width := minf(clampf(size.x * 0.27, 350.0, 450.0), size.x * 0.49 - edge)
	_telemetry_card.position = Vector2(edge, edge)
	_telemetry_card.size.x = telemetry_width
	_fit_height.call_deferred(_telemetry_card)
	_interaction_stack.offset_left = edge
	_interaction_stack.offset_right = edge + minf(clampf(size.x * 0.30, 420.0, 540.0), size.x * 0.60 - edge)
	_interaction_stack.offset_bottom = -edge
	_interaction_stack.offset_top = -edge
	_shortcuts.offset_right = -edge
	_shortcuts.offset_bottom = -edge
	_shortcuts.offset_left = _shortcuts.offset_right
	_shortcuts.offset_top = _shortcuts.offset_bottom
	if _checklist_card != null:
		var width := minf(clampf(size.x * 0.31, 330.0, 520.0), size.x * 0.50 - edge)
		_checklist_card.offset_left = -edge - width
		_checklist_card.offset_right = -edge
		_checklist_card.offset_top = edge
		_checklist_card.offset_bottom = edge


func _fit_height(card: Control, anchor_bottom := false) -> void:
	if anchor_bottom:
		card.offset_top = card.offset_bottom
	else:
		card.offset_bottom = card.offset_top


func style_checklist(card: PanelContainer, source: Label) -> void:
	_checklist_card = card
	_checklist_source = source
	_checklist_card.reparent(_instrument_layer, false)
	_checklist_card.custom_minimum_size = Vector2.ZERO
	_checklist_card.add_theme_stylebox_override("panel", plate_style(ACCENT))
	_checklist_card.minimum_size_changed.connect(_fit_height.bind(_checklist_card), CONNECT_DEFERRED)
	var lines := _stack(card, 8)
	_text(lines, "MISSION CHECKLIST", 13, ACCENT, true)
	_checklist_heading = _text(lines, "", 23, PAPER, false, true)
	_divider(lines)
	_checklist_body = _text(lines, "", 17, COOL, false, true)
	source.hide()
	_layout_desktop()


func set_instruments_visible(enabled: bool) -> void:
	_instrument_layer.visible = enabled


func present_focus(has_target: bool, notification: String) -> void:
	var show_target := has_target and not focus_label.text.is_empty()
	if show_target != _focus_card.visible:
		_focus_card.visible = show_target
		if show_target:
			_fade_in(_focus_card)
	if notification != _toast_text.text:
		_toast_text.text = notification
		_toast_card.visible = not notification.is_empty()
		if _toast_card.visible:
			_fade_in(_toast_card)


func _fade_in(card: Control) -> void:
	card.modulate.a = 0.52
	create_tween().tween_property(card, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not _instrument_layer.is_visible_in_tree():
		return
	if _last_mode != mode_label.text:
		_sync_telemetry()
	if _checklist_source != null and _checklist_card.visible:
		_sync_readout(_checklist_source.text, _checklist_heading, _checklist_body)
	if checklist_marker.visible:
		_marker_phase = fmod(_marker_phase + delta * 4.0, TAU)
		checklist_marker.phase = _marker_phase
		checklist_marker.queue_redraw()


func _sync_telemetry() -> void:
	_last_mode = mode_label.text
	var lines := _last_mode.split("\n", true, 1)
	var tokens := lines[0].split(" / ", false)
	var power := PackedStringArray()
	var guidance := PackedStringArray()
	var qualifications := PackedStringArray()
	var xr_systems := PackedStringArray()
	var xr_guidance := ""
	_clock_label.text = ""
	for token: String in tokens:
		if token == "SHARED CLOCK PAUSED":
			_clock_label.text = "PAUSED"
		elif token == "SHARED CLOCK 1X":
			_clock_label.text = "CLOCK 1×"
		elif token == "EXTERNAL CLOCK":
			_clock_label.text = "EXT CLOCK"
		elif token.begins_with("EPS ") or token.begins_with("KNOWN EQUIPMENT") or "ENERGIZED BUSES" in token or token == "CABIN STUDY":
			power.append(token)
			var compact := token.replace("EPS AGGREGATE", "EPS").replace("ENERGIZED ", "")
			if compact == "1 BUSES":
				compact = "1 BUS"
			if token.begins_with("KNOWN EQUIPMENT"):
				compact = token.replace("KNOWN EQUIPMENT", "EQUIP") + " PARTIAL"
			if token != "CABIN STUDY":
				xr_systems.append(compact)
		elif token.begins_with("LM131R1") or token.begins_with("LGC ") or token == "EXTERNAL CPU INDEPENDENT":
			guidance.append(token)
			if token.begins_with("LM131R1 "):
				xr_guidance = "LGC " + token.trim_prefix("LM131R1 ").trim_prefix("LGC ")
			elif token == "EXTERNAL CPU INDEPENDENT":
				xr_guidance = "LGC BRANCH OFF · EXT CPU"
		else:
			qualifications.append(token)
	if lines.size() > 1 and not lines[1].is_empty():
		qualifications.append(lines[1])
	_clock_label.add_theme_color_override("font_color", ACCENT if _clock_label.text == "PAUSED" else COOL)
	_electrical_label.text = "  /  ".join(power)
	_agc_label.text = "  /  ".join(guidance)
	_agc_label.visible = not guidance.is_empty()
	_qualifications_label.text = "  /  ".join(qualifications)
	_qualifications_label.visible = not qualifications.is_empty()
	var xr_computer := PackedStringArray()
	if not xr_guidance.is_empty():
		xr_computer.append(xr_guidance)
	if _clock_label.text == "PAUSED":
		xr_computer.append("CLOCK PAUSED")
	_xr_system_summary = ("%s\n%s" % ["  ·  ".join(xr_systems), "  ·  ".join(xr_computer)]).strip_edges()


func _sync_readout(text_value: String, heading: Label, body: Label) -> bool:
	var lines := text_value.split("\n", true, 1)
	var header := lines[0]
	var detail := lines[1] if lines.size() > 1 else ""
	if heading.text == header and body.text == detail:
		return false
	heading.text = header
	body.text = detail
	body.visible = not detail.is_empty()
	return true


static func style_xr_hand(label: Label3D) -> void:
	label.font = typeface(true)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 10
	label.outline_modulate = INK
	label.modulate = PAPER


func create_xr_status(camera: Node3D) -> void:
	_xr_viewport = SubViewport.new()
	_xr_viewport.name = "HeadsetInstrumentation"
	_xr_viewport.disable_3d = true
	_xr_viewport.size = XR_SURFACE
	_xr_viewport.transparent_bg = true
	_xr_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	camera.add_child(_xr_viewport)
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = Vector2(XR_SURFACE)
	_xr_viewport.add_child(canvas)
	var hud_stack := _stack(canvas, 10)
	hud_stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hud_stack.offset_left = 24
	hud_stack.offset_right = 482
	hud_stack.offset_bottom = -26
	hud_stack.offset_top = -26
	hud_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud_stack.minimum_size_changed.connect(_fit_height.bind(hud_stack, true), CONNECT_DEFERRED)
	_xr_toast = _panel(hud_stack, "FlightNotice", ACCENT, 12)
	_xr_toast_text = _text(_xr_toast, "", 22, PAPER, false, true)
	_xr_toast.hide()
	_xr_telemetry = _panel(hud_stack, "HeadsetTracking", STROKE, 12)
	var tracking := _stack(_xr_telemetry, 6)
	_xr_tracking_heading = _text(tracking, "", 20, PAPER, true, true)
	_divider(tracking)
	_xr_systems = _text(tracking, "", 18, PAPER, true, true)
	_xr_systems.hide()
	_xr_tracking_body = _text(tracking, "", 18, COOL, true, true)
	_xr_objective = _panel(canvas, "MissionChecklist", ACCENT, 13)
	_xr_objective.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_xr_objective.offset_left = -538
	_xr_objective.offset_right = -22
	_xr_objective.offset_bottom = -26
	_xr_objective.offset_top = -26
	_xr_objective.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_xr_objective.minimum_size_changed.connect(_fit_height.bind(_xr_objective, true), CONNECT_DEFERRED)
	var checklist := _stack(_xr_objective, 7)
	_xr_objective_heading = _text(checklist, "", 24, PAPER, false, true)
	_divider(checklist)
	_xr_objective_body = _text(checklist, "", 22, COOL, false, true)
	_xr_objective.hide()
	_xr_mesh = MeshInstance3D.new()
	_xr_mesh.name = "HeadsetFlightHud"
	var plane := QuadMesh.new()
	plane.size = Vector2(1.03, 1.03 * float(XR_SURFACE.y) / float(XR_SURFACE.x))
	_xr_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_texture = _xr_viewport.get_texture()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 16
	_xr_mesh.material_override = material
	_xr_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_xr_mesh.position = Vector3(0.0, -0.30, -1.22)
	_xr_mesh.hide()
	camera.add_child(_xr_mesh)


func present_xr_status(tracking: String, objective: String, notification: String, hud_visible: bool) -> void:
	if _xr_mesh == null:
		return
	var changed := hud_visible != _xr_mesh.visible
	_xr_mesh.visible = hud_visible
	if not hud_visible:
		return
	if _last_mode != mode_label.text:
		_sync_telemetry()
	if _xr_systems.text != _xr_system_summary:
		_xr_systems.text = _xr_system_summary
		_xr_systems.visible = not _xr_system_summary.is_empty()
		changed = true
	changed = _sync_readout(tracking, _xr_tracking_heading, _xr_tracking_body) or changed
	changed = _sync_readout(objective, _xr_objective_heading, _xr_objective_body) or changed
	_xr_objective.visible = not objective.is_empty()
	if notification != _xr_toast_text.text:
		_xr_toast_text.text = notification
		_xr_toast.visible = not notification.is_empty()
		changed = true
	if changed:
		_xr_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
