extends Control
## One instrument-panel composition for the desktop screen and OpenXR surface.

signal action_requested(action: String)

const DESIGN_SIZE := Vector2(1440, 900)
const INK := Color("#07111c")
const DEEP := Color("#030b14")
const PANEL := Color("#0c1b29")
const STROKE := Color("#365265")
const COOL := Color("#a9c9db")
const PAPER := Color("#edf5ed")
const AMBER := Color("#ff9c5b")
const STEEL := Color("#80a3b9")

const MOON_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D lunar_map : source_color, filter_linear, repeat_enable;
uniform float heading = 0.38;
uniform float gain = 1.0;

void fragment() {
	vec2 face = (UV * 2.0 - 1.0) / 0.95;
	float distance = length(face);
	if (distance > 1.04) {
		discard;
	}
	float depth = sqrt(max(0.001, 1.0 - dot(face, face)));
	vec3 normal = normalize(vec3(face.x, -face.y, depth));
	vec2 map_uv = vec2(heading + atan(normal.x, normal.z) / TAU, 0.5 - asin(normal.y) / PI);
	float lunar = texture(lunar_map, map_uv).r;
	float sunward = dot(normal, normalize(vec3(-0.68, 0.42, 0.54)));
	float illumination = smoothstep(-0.08, 0.13, sunward) * (0.25 + 0.78 * max(sunward, 0.0));
	float limb = pow(1.0 - depth, 3.5) * smoothstep(0.0, 0.54, sunward);
	vec3 color = vec3(0.55, 0.68, 0.83) * (0.035 + illumination * pow(lunar, 0.85));
	color += vec3(0.34, 0.49, 0.68) * limb;
	float disc = 1.0 - smoothstep(0.995, 1.002, distance);
	float halo = (1.0 - smoothstep(1.0, 1.035, distance)) * limb * 0.28;
	vec4 tint = COLOR;
	COLOR = vec4(mix(vec3(0.22, 0.35, 0.52), color, disc), max(disc, halo) * gain) * tint;
}
"""

var _display_font: SystemFont
var _body_font: SystemFont
var _mono_font: SystemFont
var _moon: ColorRect
var _moon_material: ShaderMaterial
var _glow: Texture2D
var _stars := PackedVector2Array()
var _content: Control
var _first_button: Button
var _transition: Tween
var _scan: Tween
var _time := 0.0
var _page := ""
var _base_page := "splash"
var _pending_mission := ""
var _xr := false
var _status: Dictionary = {}

func _ready() -> void:
	name = "FlightMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_display_font = _system_font(["Bahnschrift", "Inter", "Segoe UI", "DejaVu Sans"], 650)
	_body_font = _system_font(["Segoe UI", "Inter", "DejaVu Sans"], 500)
	_mono_font = _system_font(["Consolas", "DejaVu Sans Mono", "Liberation Mono"], 500)
	_make_backdrop()
	_build_page(_base_page)

func show_page(page: String, xr: bool, status: Dictionary = {}) -> void:
	var updating_missions := page == _base_page and _page in ["missions", "restart"]
	var updating_audio := page == _base_page and _page == "audio"
	_xr = xr
	_status = status.duplicate()
	_base_page = page
	if is_node_ready():
		_build_page("audio" if updating_audio else ("missions" if updating_missions else page))

func back() -> void:
	match _page:
		"pause":
			action_requested.emit("resume")
		"controls", "missions", "quit", "audio":
			_build_page(_base_page, StringName(_page))
		"restart":
			_build_page("missions", StringName(_pending_mission))
			_pending_mission = ""

func _system_font(families: PackedStringArray, weight: int) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = families
	font.font_weight = weight
	return font

func _make_backdrop() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 19700411
	for index in range(144):
		_stars.append(Vector2(random.randf_range(14, DESIGN_SIZE.x - 14), random.randf_range(10, DESIGN_SIZE.y - 10)))
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color("#182d42"), Color("#091622"), Color(INK, 0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	var gradient := GradientTexture2D.new()
	gradient.width = 512
	gradient.height = 512
	gradient.gradient = ramp
	gradient.fill = GradientTexture2D.FILL_RADIAL
	gradient.fill_from = Vector2(0.52, 0.49)
	gradient.fill_to = Vector2(1.0, 0.49)
	_glow = gradient

	var project_file := ProjectSettings.globalize_path("res://project.godot")
	var texture_path := project_file.get_base_dir().get_base_dir().path_join("assets/textures/moon.jpg")
	if not FileAccess.file_exists(texture_path):
		return
	var image := Image.load_from_file(texture_path)
	if image == null or image.is_empty():
		return
	image.resize(1536, 768, Image.INTERPOLATE_BILINEAR)
	var shader := Shader.new()
	shader.code = MOON_SHADER
	_moon_material = ShaderMaterial.new()
	_moon_material.shader = shader
	_moon_material.set_shader_parameter("lunar_map", ImageTexture.create_from_image(image))
	_moon = ColorRect.new()
	_moon.name = "LunarSurface"
	_moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_moon.material = _moon_material
	add_child(_moon)

func _process(delta: float) -> void:
	if _moon_material != null and is_visible_in_tree():
		_time += delta
		_moon_material.set_shader_parameter("heading", 0.38 + sin(_time * 0.09) * 0.027)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN_SIZE), DEEP)
	if _glow == null:
		return
	var hero := _page in ["splash", "main"]
	var glow := Color.WHITE if hero else Color(1, 1, 1, 0.62)
	draw_texture_rect(_glow, Rect2(210, -286, 1750, 1510), false, glow)
	for index in range(_stars.size()):
		var point := _stars[index]
		var brightness := 0.12 + 0.035 * float(index % 10)
		if point.x < 655 or not hero:
			brightness *= 0.44
		draw_circle(point, 1.4 if index % 12 == 0 else 0.75, Color(COOL, brightness), true, -1.0, true)
	if hero:
		_draw_lunar_plot()
	draw_line(Vector2(72, 107), Vector2(1368, 107), Color(STROKE, 0.72), 1.0)
	draw_line(Vector2(72, 817), Vector2(1368, 817), Color(STROKE, 0.72), 1.0)
	draw_line(Vector2(72, 107), Vector2(152, 107), AMBER, 2.0)

func _draw_lunar_plot() -> void:
	var center := Vector2(1042, 446)
	var orbit := PackedVector2Array()
	for step in range(137):
		var phase := float(step) * TAU / 136.0
		var point := Vector2(cos(phase) * 408, sin(phase) * 193).rotated(-0.56)
		orbit.append(center + point)
	draw_polyline(orbit, Color(STEEL, 0.35), 1.5, true)
	for step in range(64):
		var start := float(step) * TAU / 64.0
		var end := start + 0.023
		draw_line(center + Vector2.from_angle(start) * 344, center + Vector2.from_angle(end) * 344, Color(STEEL, 0.3), 1.4, true)
		if step % 4 == 0:
			draw_line(center + Vector2.from_angle(start) * 337, center + Vector2.from_angle(start) * 344, Color(STEEL, 0.35), 1.4, true)
	var outbound := orbit[57]
	draw_circle(outbound, 9, Color(AMBER, 0.25), false, 1.5, true)
	draw_circle(outbound, 3, AMBER, true, -1, true)
	draw_line(outbound + Vector2(9, 2), outbound + Vector2(37, 34), Color(AMBER, 0.52), 1.4, true)
	draw_line(outbound + Vector2(37, 34), outbound + Vector2(106, 34), Color(AMBER, 0.52), 1.4, true)

func _build_page(page: String, focused_action := StringName()) -> void:
	var did_change := _page != page
	if focused_action.is_empty() and not did_change and _content != null:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button and _content.is_ancestor_of(focused):
			focused_action = focused.name
	if _transition != null:
		_transition.kill()
	if _scan != null:
		_scan.kill()
	if _content != null:
		remove_child(_content)
		_content.queue_free()
	_page = page
	_first_button = null
	_content = Control.new()
	_content.name = "PageContent"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_content.size = DESIGN_SIZE
	if _moon != null:
		var hero := page in ["splash", "main"]
		_moon.position = Vector2(704, 108) if hero else Vector2(916, 73)
		_moon.size = Vector2(676, 676)
		_moon_material.set_shader_parameter("gain", 1.0 if hero else 0.15)
	queue_redraw()
	_header()
	match page:
		"splash": _splash()
		"main": _main()
		"pause": _pause()
		"missions": _missions()
		"restart": _restart()
		"controls": _controls()
		"audio": _audio()
		"quit": _quit()
	_footer()
	var restore_focus := _content.get_node_or_null(NodePath(String(focused_action))) as Button if not focused_action.is_empty() else null
	if restore_focus != null and not restore_focus.disabled:
		restore_focus.grab_focus()
	elif _first_button != null:
		_first_button.grab_focus()
	if did_change:
		_content.modulate.a = 0.0
		_transition = create_tween()
		_transition.tween_property(_content, "modulate:a", 1.0, 0.23).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _header() -> void:
	# A vector delta stays sharp on desktop and on the headset's menu surface.
	var glyph := Polygon2D.new()
	glyph.polygon = PackedVector2Array([Vector2(73, 78), Vector2(91, 46), Vector2(109, 78), Vector2(98, 78), Vector2(91, 65), Vector2(84, 78)])
	glyph.color = AMBER
	_content.add_child(glyph)
	_label("AQUARIUS  /  LM-7", Rect2(128, 42, 400, 40), 23, PAPER, _display_font)
	var mode := "OPENXR" if _xr else "DESKTOP"
	if _page != "splash" and not bool(_status.get("can_enter", true)):
		mode = "LAUNCH CHECK"
	_plate(Rect2(1156, 40, 212, 43), Color(PANEL, 0.92), Color(STROKE, 0.85))
	_fill(Rect2(1174, 56, 10, 10), AMBER if mode == "LAUNCH CHECK" else COOL)
	_label(mode, Rect2(1200, 42, 160, 40), 20, PAPER, _mono_font)

func _footer() -> void:
	if _page in ["splash", "main"]:
		_label("APOLLO 13   /   11–17 APR 1970", Rect2(72, 830, 520, 43), 19, COOL, _mono_font)
	else:
		_label("LM-7  /  CABIN OPERATIONS", Rect2(72, 830, 520, 43), 19, COOL, _mono_font)
	if _page != "splash":
		var input_guide := "AIM + TRIGGER  Select" if _xr else "TAB   Navigate      ENTER   Select"
		if _page != "main":
			input_guide += "      B / Y  Back" if _xr else "      ESC  Back"
		_label(input_guide, Rect2(550, 830, 818, 43), 19, COOL, _mono_font, HORIZONTAL_ALIGNMENT_RIGHT)

func _splash() -> void:
	_label("A P O L L O   1 3", Rect2(91, 244, 620, 43), 24, AMBER, _mono_font)
	_label("AQUARIUS", Rect2(82, 279, 760, 154), 126, PAPER, _display_font)
	_label("Lunar Module 07", Rect2(94, 440, 635, 48), 30, COOL, _body_font)
	_fill(Rect2(94, 564, 460, 3), STROKE)
	var scan := _fill(Rect2(94, 564, 120, 3), AMBER)
	_scan = create_tween().set_loops()
	_scan.tween_property(scan, "position:x", 434.0, 0.8).set_trans(Tween.TRANS_SINE)
	_scan.tween_property(scan, "position:x", 94.0, 0.8).set_trans(Tween.TRANS_SINE)
	_label("INITIALIZING CABIN", Rect2(94, 584, 520, 43), 20, COOL, _mono_font)

func _main() -> void:
	_label("A P O L L O   1 3", Rect2(91, 165, 580, 38), 23, AMBER, _mono_font)
	_label("AQUARIUS", Rect2(80, 204, 780, 132), 118, PAPER, _display_font)
	_label("Lunar module simulator", Rect2(93, 351, 560, 46), 33, COOL, _body_font)
	var can_enter := bool(_status.get("can_enter", true))
	var intro := "Return to cabin" if bool(_status.get("has_session", false)) else "Enter cabin"
	_button(Rect2(93, 438, 505, 74), intro, "enter", "LM-7", true, can_enter)
	_button(Rect2(93, 525, 505, 63), "Mission chapters", "missions", "", false, can_enter)
	_button(Rect2(93, 599, 287, 63), "Flight controls", "controls")
	_button(Rect2(391, 599, 207, 63), "Audio mix", "audio")
	_button(Rect2(93, 673, 505, 63), "Exit Aquarius", "quit")
	_label("LUNAR SURFACE", Rect2(863, 716, 483, 37), 22, PAPER, _mono_font, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("NASA LUNAR RECONNAISSANCE ORBITER", Rect2(803, 749, 543, 32), 16, COOL, _mono_font, HORIZONTAL_ALIGNMENT_RIGHT)
	_notice(Rect2(93, 751, 668, 57))

func _pause() -> void:
	_heading("Session on hold", "Cabin paused", str(_status.get("chapter", "")))
	_section("FLIGHT", Vector2(93, 326), 580)
	_section("SESSION", Vector2(705, 326), 641)
	var y := 376.0
	_button(Rect2(93, y, 580, 65), "Resume flight", "resume", "B / Y" if _xr else "ESC", true)
	y += 73
	if bool(_status.get("can_confirm", false)):
		_button(Rect2(93, y, 580, 65), str(_status.get("confirm_label", "Confirm checklist step")), "confirm")
		y += 73
	_button(Rect2(93, y, 580, 65), "Mission chapters", "missions")
	_button(Rect2(93, y + 73, 580, 65), "Flight controls", "controls")
	_button(Rect2(93, y + 146, 580, 65), "Main menu", "main")
	_button(Rect2(705, 376, 641, 65), "Save checkpoint", "save")
	_button(Rect2(705, 449, 641, 65), "Restore checkpoint", "load", "", false, bool(_status.get("can_load", false)))
	_button(Rect2(705, 522, 641, 65), "Audio mix", "audio", str(_status.get("audio_profile", "Headphones")))
	_button(Rect2(705, 595, 312, 65), "Flight notebook", "notebook", "N" if not _xr else "")
	_button(Rect2(1029, 595, 317, 65), "Floating info" if _xr else "Flight HUD", "toggle_hud", _switch_text("hud_visible", true))
	if _xr:
		_button(Rect2(705, 668, 641, 65), "Recenter headset", "recenter", "MENU")
	_notice(Rect2(93, 750, 1253, 57))

func _missions() -> void:
	_heading("Apollo 13", "Mission chapters", "From lifeboat activation to reentry preparation.")
	_mission_row(339.0, "01", "Electrical power-down", "Configure the lunar module for its lifeboat role.", "powerdown", bool(_status.get("can_powerdown", true)))
	_mission_row(430.0, "02", "CO₂ adapter", "Build the improvised scrubber with Mission Control.", "co2", bool(_status.get("can_co2", not _xr)), "DESKTOP" if _xr else "UNAVAILABLE")
	_mission_row(521.0, "03", "Manual course correction", "Sight the Earth and Sun and fly the MCC-5 burn.", "correction", bool(_status.get("can_correct", false)), "DESKTOP" if _xr else "COMPLETE CO₂ ADAPTER")
	_mission_row(612.0, "04", "Odyssey power-up", "Power the command module for reentry.", "odyssey", bool(_status.get("can_odyssey", false)), "DESKTOP" if _xr else "COMPLETE MCC-5")
	_button(Rect2(93, 721, 307, 66), "Back", "back")
	_notice(Rect2(439, 726, 906, 57))

func _audio() -> void:
	_heading("Cabin acoustics", "Audio mix", str(_status.get("radio_status", "Sound check includes Houston speech at 11 seconds.")))
	var selected := str(_status.get("audio_profile", "Headphones"))
	for item: Array in [["Headphones", "audio_headphones", 93.0], ["Speakers", "audio_speakers", 519.0], ["Quiet cabin", "audio_quiet", 945.0]]:
		_button(Rect2(float(item[2]), 344, 401, 60), str(item[0]), str(item[1]), "SELECTED" if selected == str(item[0]) else "", selected == str(item[0]))
	_button(Rect2(93, 422, 613, 62), "Cabin sounds", "audio_cabin", _switch_text("audio_enabled", true))
	_button(Rect2(724, 422, 622, 62), "Mission radio", "audio_radio", _switch_text("radio_enabled", true))
	var mix: Dictionary = _status.get("audio_levels", {})
	var y := 510.0
	for item: Array in [["master", "Overall level"], ["controls", "Switches & handling"], ["machinery", "Equipment"], ["radio", "Radio speech"]]:
		var channel := str(item[0])
		var gain := float(mix.get(channel, 0))
		_label(str(item[1]), Rect2(96, y, 520, 44), 25, PAPER, _body_font)
		_fill(Rect2(700, y + 20, 310, 3), STROKE)
		_fill(Rect2(700, y + 20, 310 * clampf((gain + 30) / 36.0, 0, 1), 3), AMBER)
		_label("%+.0f dB" % gain, Rect2(1024, y, 119, 44), 22, COOL, _mono_font, HORIZONTAL_ALIGNMENT_RIGHT)
		_button(Rect2(1161, y, 80, 44), "", "audio_" + channel + "_down", "−")
		_button(Rect2(1258, y, 80, 44), "", "audio_" + channel + "_up", "+")
		y += 56
	_button(Rect2(93, 755, 307, 58), "Back", "back")
	_button(Rect2(421, 755, 410, 58), "Stop sound check" if _status.get("audio_previewing", false) else "Play sound check", "audio_preview", "24 SEC")
	_button(Rect2(850, 755, 496, 58), "Stop Houston voice" if _status.get("audio_voice_previewing", false) else "Test Houston voice", "audio_voice_preview")

func _mission_row(y: float, ordinal: String, heading: String, summary: String, action: String, available: bool, unavailable: String = "UNAVAILABLE") -> void:
	var launch := "RESTART" if _replaces_procedure(action) else "BEGIN"
	var button := _button(Rect2(93, y, 1253, 82), "", action, launch if available else unavailable, false, available)
	_label(ordinal, Rect2(21, 0, 75, 82), 24, AMBER if available else STEEL, _mono_font, HORIZONTAL_ALIGNMENT_CENTER, button)
	_label(heading, Rect2(115, 5, 615, 38), 30, PAPER if available else COOL, _display_font, HORIZONTAL_ALIGNMENT_LEFT, button)
	_label(summary, Rect2(116, 42, 740, 32), 22, COOL, _body_font, HORIZONTAL_ALIGNMENT_LEFT, button)

func _replaces_procedure(action: String) -> bool:
	return action in ["powerdown", "co2"] and str(_status.get("chapter", "")) not in ["", "Cabin checkout"]

func _restart() -> void:
	var mission := "power-down" if _pending_mission == "powerdown" else "CO₂ adapter"
	_heading("Mission chapters", "Start a fresh procedure?", "Starting %s replaces the current checklist progress." % mission)
	_button(Rect2(93, 378, 510, 72), "Keep current progress", "back", "", true)
	_button(Rect2(93, 464, 510, 66), "Start " + mission, "restart_confirmed")

func _controls() -> void:
	_heading("Input guide", "Flight controls", "OpenXR controllers" if _xr else "Keyboard and mouse")
	_section("CABIN", Vector2(93, 334), 598)
	_section("MISSION", Vector2(734, 334), 612)
	var cabin: Array
	var mission: Array
	if _xr:
		cabin = [
			["TRIGGER", "Operate cabin control"],
			["GRIP + TRIGGER", "Reverse or unlock"],
			["TOUCH TIP", "Press buttons / push breakers"],
			["TRIGGER + STICK", "Adjust a held dial or axis"],
			["LEFT STICK", "Move"],
			["RIGHT STICK", "Snap turn / adjust height"],
		]
		mission = [
			["B / Y", "Pause or go back"],
			["AIM + TRIGGER", "Select menu action"],
			["MENU", "Recenter"],
			["X", "Recall notebook"],
			["A", "Reveal procedure target"],
			["AIM + GRIP", "Grab book; release to drift"],
		]
	else:
		cabin = [
			["RIGHT MOUSE", "Hold to look around"],
			["WASD / Q · E", "Move / change height"],
			["CLICK", "Operate a control"],
			["SHIFT + CLICK", "Reverse or unlock"],
			["MOUSE WHEEL", "Adjust dial or axis"],
			["1–4", "Inspection views"],
			["F", "Locate checklist target"],
		]
		mission = [
			["ESC", "Pause or go back"],
			["F12", "Confirm checklist step"],
			["F10", "Open CO₂ adapter chapter"],
			["F5 / F9", "Save / restore checkpoint"],
			["M / R", "Toggle audio / repeat radio"],
			["P", "Pause simulation clock"],
			["F1", "Toggle flight HUD"],
		]
	_control_rows(Vector2(93, 377), 598, cabin)
	_control_rows(Vector2(734, 377), 612, mission)
	_button(Rect2(93, 731, 307, 62), "Back", "back")
	_button(Rect2(421, 731, 570, 62), "Quick cabin orientation", "onboarding")
	if _xr:
		_button(Rect2(1009, 731, 337, 62), "Floating info", "toggle_hud", _switch_text("hud_visible", true))

func _quit() -> void:
	_heading("End session", "Exit Aquarius?", "Close the lunar module simulator.")
	_button(Rect2(93, 378, 510, 72), "Return to menu", "back", "", true)
	_button(Rect2(93, 464, 510, 66), "Exit Aquarius", "exit_confirmed")

func _heading(eyebrow: String, title: String, subtitle: String) -> void:
	_label(eyebrow.to_upper(), Rect2(93, 146, 1100, 32), 21, AMBER, _mono_font)
	_label(title, Rect2(89, 181, 1257, 96), 78, PAPER, _display_font)
	if not subtitle.is_empty():
		_label(subtitle, Rect2(95, 281, 1249, 40), 26, COOL, _body_font)

func _notice(at: Rect2) -> void:
	var notice := str(_status.get("notice", ""))
	if notice.is_empty():
		return
	var label := _label(notice, at, 20, AMBER, _body_font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2

func _section(title: String, at: Vector2, width: float) -> void:
	_label(title, Rect2(at, Vector2(width, 34)), 19, COOL, _mono_font)
	_fill(Rect2(at + Vector2(0, 40), Vector2(width, 1)), STROKE)

func _control_rows(at: Vector2, width: float, rows: Array) -> void:
	for index in range(rows.size()):
		var y := at.y + 47.0 * index
		_label(rows[index][0], Rect2(at.x, y, 224, 45), 21, AMBER, _mono_font)
		_label(rows[index][1], Rect2(at.x + 226, y, width - 226, 45), 23, PAPER, _body_font)
		_fill(Rect2(at.x, y + 45, width, 1), Color(STROKE, 0.65))

func _switch_text(key: String, default_value: bool) -> String:
	return "ON" if bool(_status.get(key, default_value)) else "OFF"

func _choose(action: String) -> void:
	match action:
		"missions", "controls", "quit", "audio":
			_build_page(action)
		"back":
			back()
		"exit_confirmed":
			action_requested.emit("quit")
		"restart_confirmed":
			action_requested.emit(_pending_mission)
		"powerdown", "co2":
			if _replaces_procedure(action):
				_pending_mission = action
				_build_page("restart")
			else:
				action_requested.emit(action)
		_:
			action_requested.emit(action)

func _button(at: Rect2, title: String, action: String, detail: String = "", primary: bool = false, available: bool = true) -> Button:
	var button := Button.new()
	button.name = action
	button.position = at.position
	button.size = at.size
	button.disabled = not available
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _box(AMBER if primary else Color(PANEL, 0.89), AMBER if primary else STROKE, 1, 4 if primary else 1))
	button.add_theme_stylebox_override("hover", _box(Color("#ffc096") if primary else Color("#19374b"), AMBER, 1, 4))
	button.add_theme_stylebox_override("pressed", _box(Color("#ed8747") if primary else Color("#25495e"), AMBER, 2, 4))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, Color("#ffd0ac") if primary else COOL, 2, 4))
	button.add_theme_stylebox_override("disabled", _box(Color(PANEL, 0.70), Color(STROKE, 0.44), 1, 1))
	_content.add_child(button)
	var text_color := DEEP if primary and available else (PAPER if available else COOL)
	if not title.is_empty():
		_label(title, Rect2(24, 0, at.size.x - 88, at.size.y), 31 if primary else 27, text_color, _display_font, HORIZONTAL_ALIGNMENT_LEFT, button)
	var attendant := detail if not detail.is_empty() else ("‹" if action == "back" else "›")
	var detail_width := minf(316, at.size.x - 48.0)
	_label(attendant, Rect2(at.size.x - detail_width - 24.0, 0, detail_width, at.size.y), 19 if not detail.is_empty() else 30, DEEP if primary and available else COOL, _mono_font, HORIZONTAL_ALIGNMENT_RIGHT, button)
	button.pressed.connect(_choose.bind(action))
	if _first_button == null and available:
		_first_button = button
	return button

func _box(background: Color, border: Color, edge: int, leading: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(edge)
	box.border_width_left = leading
	box.set_corner_radius_all(3)
	return box

func _plate(at: Rect2, background: Color, border: Color) -> void:
	var plate := Panel.new()
	plate.position = at.position
	plate.size = at.size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", _box(background, border, 1))
	_content.add_child(plate)

func _fill(at: Rect2, color: Color) -> ColorRect:
	var block := ColorRect.new()
	block.position = at.position
	block.size = at.size
	block.color = color
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(block)
	return block

func _label(title: String, at: Rect2, point_size: int, color: Color, font: Font, alignment := HORIZONTAL_ALIGNMENT_LEFT, parent: Control = null) -> Label:
	var label := Label.new()
	label.text = title
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", point_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = at.position
	label.size = at.size
	(_content if parent == null else parent).add_child(label)
	return label
