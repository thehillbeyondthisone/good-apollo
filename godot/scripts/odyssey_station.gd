extends Control
## Desktop switch panels for the subset of Odyssey's hardware used by the checklist.

const Data = preload("res://scripts/odyssey_checklist.gd")
const FlightHud = preload("res://scripts/flight_hud.gd")
const PAPER := FlightHud.PAPER
const COOL := FlightHud.COOL
const ACCENT := FlightHud.ACCENT
const GREEN := Color("#b5d3a0")
const RED := Color("#ff9a83")

class BenchGrid extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var ink := Color(FlightHud.STROKE, 0.23)
		for x in range(0, int(size.x), 26):
			draw_line(Vector2(x, 0), Vector2(x, size.y), ink)
		for y in range(0, int(size.y), 26):
			draw_line(Vector2(0, y), Vector2(size.x, y), ink)

class SwitchButton extends Button:
	var caption: Label
	var position_label: Label
	var setting := ""
	var normalized := 0.0
	var switch_kind := "toggle"
	var marked := false

	func configure(label: String, kind: String) -> void:
		switch_kind = kind
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		flat = true
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(105, 94)
		caption = Label.new()
		caption.text = label
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_theme_font_size_override("font_size", 13)
		caption.add_theme_color_override("font_color", Color("#e1daca"))
		add_child(caption)
		caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		caption.offset_left = 7
		caption.offset_right = -7
		caption.offset_top = 6
		caption.offset_bottom = 31
		position_label = Label.new()
		position_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		position_label.add_theme_font_size_override("font_size", 12)
		add_child(position_label)
		position_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		position_label.offset_top = -23
		position_label.offset_bottom = -5
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func update_setting(value: String, angle: float, highlighted: bool) -> void:
		setting = value
		normalized = angle
		marked = highlighted
		position_label.text = setting
		position_label.add_theme_color_override("font_color", Color("#efba78") if marked else Color("#b7bdac"))
		queue_redraw()

	func _draw() -> void:
		var line := Color("#6c6555")
		if marked:
			line = Color("#dcb071")
		elif is_hovered():
			line = Color("#a49d87")
		var bounds := Rect2(Vector2(0.5, 0.5), size - Vector2.ONE)
		draw_rect(bounds, Color("#393b37") if is_hovered() else Color("#2c302e"))
		draw_rect(bounds, line, false, 2.0 if marked else 1.0)
		for x: float in [9.0, size.x - 9.0]:
			draw_circle(Vector2(x, size.y - 11), 2.5, Color("#121717"), true, -1, true)
		var pivot := Vector2(size.x * 0.5, size.y * 0.55)
		draw_circle(pivot, 16, Color("#151b1b"), true, -1, true)
		draw_arc(pivot, 15.0, 0.0, TAU, 28, Color("#74746b"), 1.0, true)
		if switch_kind == "breaker":
			if setting == "OPEN":
				draw_circle(pivot, 12.0, Color("#e0ddd1"), true, -1, true)
			draw_circle(pivot, 9.5 if setting == "OPEN" else 8.0, Color("#252928"), true, -1, true)
			draw_arc(pivot, 8.0 if setting == "OPEN" else 6.5, PI, TAU, 20, Color("#6e746d"), 1.6, true)
		elif switch_kind == "rotary":
			draw_circle(pivot, 11.0, Color("#77796a"), true, -1, true)
			draw_circle(pivot, 9.5, Color("#353a36"), true, -1, true)
			draw_line(pivot, pivot + Vector2.UP.rotated(normalized * 1.35) * 8.0, Color("#e4dbbc"), 2.0, true)
		else:
			var tip := pivot + Vector2(normalized * 9, -7)
			draw_line(pivot, tip, Color("#b2b3a3"), 6.0, true)
			draw_circle(tip, 4.0, Color("#dedccf"), true, -1, true)

var scenario: Node
var selected_panel := ""
var panels: Dictionary = {}
var tabs: Dictionary = {}
var switches: Dictionary = {}
var dsky_keys: Dictionary = {}
var scroll: ScrollContainer
var identity: Label
var source_label: Label
var current_label: Label
var bus_label: Label
var peak_label: Label
var distribution: Array[Label] = []
var meter_bar: ProgressBar
var call_label: Label
var action_label: Label
var notice_label: Label
var guidance_label: Label
var dsky_label: Label
var confirm_button: Button
var _meter_fill: StyleBoxFlat

func _label(parent: Control, font_size: int, tint: Color, instrument := false) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FlightHud.typeface(instrument))
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("line_spacing", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _box(color: Color, border: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	return style

func _button(parent: Control, caption: String, hardware := false) -> Button:
	var button := Button.new()
	button.text = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if hardware:
		button.add_theme_color_override("font_color", Color("#e1daca"))
		button.add_theme_stylebox_override("normal", _box(Color("#333732"), Color("#676350"), 6))
		button.add_theme_stylebox_override("hover", _box(Color("#45483b"), Color("#ecb26d"), 6))
		button.add_theme_stylebox_override("pressed", _box(Color("#67634f"), Color("#ecb26d"), 6))
	else:
		button.add_theme_font_override("font", FlightHud.typeface(true))
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_color_override("font_color", COOL)
		button.add_theme_color_override("font_pressed_color", ACCENT)
		button.add_theme_color_override("font_hover_pressed_color", ACCENT)
		button.add_theme_stylebox_override("normal", FlightHud.plate_style(FlightHud.STROKE, 8))
		button.add_theme_stylebox_override("hover", FlightHud.plate_style(COOL, 8))
		button.add_theme_stylebox_override("pressed", FlightHud.plate_style(ACCENT, 8))
		button.custom_minimum_size.y = 48
	var focus_style := _box(Color.TRANSPARENT, PAPER, 0)
	focus_style.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus_style)
	parent.add_child(button)
	return button

func _rule(parent: Control) -> void:
	var rule := ColorRect.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.color = FlightHud.STROKE
	rule.custom_minimum_size.y = 1
	parent.add_child(rule)

func setup(owner_scenario: Node) -> void:
	scenario = owner_scenario
	var background := ColorRect.new()
	background.color = FlightHud.INK
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margins := MarginContainer.new()
	add_child(margins)
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 26)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 14)
	margins.add_child(frame)
	var header := HBoxContainer.new()
	frame.add_child(header)
	var title_block := VBoxContainer.new()
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_block)
	_label(title_block, 13, ACCENT, true).text = "COMMAND MODULE"
	var nameplate := _label(title_block, 42, PAPER)
	nameplate.text = "ODYSSEY"
	identity = _label(header, 16, COOL, true)
	identity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity.text = "REACTIVATION   /   EI −2:30"
	_rule(frame)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	frame.add_child(body)
	var work := VBoxContainer.new()
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work.add_theme_constant_override("separation", 11)
	body.add_child(work)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	work.add_child(nav)
	for panel: String in Data.PANELS:
		var tab := _button(nav, "PANEL " + panel if panel != "DSKY" else "DSKY")
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(select_panel.bind(panel))
		tabs[panel] = tab
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", FlightHud.plate_style(FlightHud.STROKE, 12))
	plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	work.add_child(plate)
	plate.add_child(BenchGrid.new())
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	plate.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	for panel: String in Data.PANELS:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 7)
		grid.add_theme_constant_override("v_separation", 7)
		stack.add_child(grid)
		panels[panel] = grid
	for id: String in Data.CONTROLS:
		var definition: Array = Data.CONTROLS[id]
		var button := SwitchButton.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.configure(definition[1], "breaker" if definition[2] == Data.BREAKER else ("rotary" if definition[2].size() > 2 else "toggle"))
		button.pressed.connect(_operate.bind(id))
		panels[definition[0]].add_child(button)
		switches[id] = button
	panels.DSKY.queue_free()
	var dsky := VBoxContainer.new()
	dsky.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dsky.add_theme_constant_override("separation", 20)
	stack.add_child(dsky)
	panels.DSKY = dsky
	var display := PanelContainer.new()
	display.add_theme_stylebox_override("panel", _box(Color("#0b1510"), Color("#777866"), 21))
	dsky.add_child(display)
	dsky_label = _label(display, 27, GREEN, true)
	dsky_label.text = "CMC   STANDBY"
	var keyboard := HBoxContainer.new()
	keyboard.add_theme_constant_override("separation", 8)
	dsky.add_child(keyboard)
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 8)
	keyboard.add_child(left)
	for key: String in ["VERB", "NOUN"]:
		_add_dsky_key(left, key)
	var keys := GridContainer.new()
	keys.columns = 5
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.add_theme_constant_override("h_separation", 8)
	keys.add_theme_constant_override("v_separation", 8)
	keyboard.add_child(keys)
	for key: String in Data.DSKY_CENTER:
		_add_dsky_key(keys, key)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 8)
	keyboard.add_child(right)
	for key: String in ["ENTR", "RSET"]:
		_add_dsky_key(right, key)
	var bus_strip := HBoxContainer.new()
	bus_strip.add_theme_constant_override("separation", 6)
	work.add_child(bus_strip)
	for index in range(3):
		var feed := PanelContainer.new()
		feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		feed.add_theme_stylebox_override("panel", FlightHud.plate_style(FlightHud.STROKE, 10))
		bus_strip.add_child(feed)
		distribution.append(_label(feed, 15, COOL, true))
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 435.0
	side.add_theme_constant_override("separation", 12)
	body.add_child(side)
	var power := PanelContainer.new()
	power.add_theme_stylebox_override("panel", FlightHud.plate_style(FlightHud.STROKE, 16))
	side.add_child(power)
	var readings := VBoxContainer.new()
	readings.add_theme_constant_override("separation", 7)
	power.add_child(readings)
	source_label = _label(readings, 15, COOL, true)
	current_label = _label(readings, 36, PAPER, true)
	meter_bar = ProgressBar.new()
	meter_bar.max_value = 24.0
	meter_bar.show_percentage = false
	meter_bar.custom_minimum_size.y = 8.0
	meter_bar.add_theme_stylebox_override("background", _box(FlightHud.INK, FlightHud.STROKE, 1))
	_meter_fill = _box(GREEN, Color.TRANSPARENT, 1)
	meter_bar.add_theme_stylebox_override("fill", _meter_fill)
	readings.add_child(meter_bar)
	bus_label = _label(readings, 17, PAPER, true)
	peak_label = _label(readings, 14, COOL, true)
	var card := PanelContainer.new()
	card.name = "ProcedureNotebookSlot"
	card.add_theme_stylebox_override("panel", FlightHud.plate_style(ACCENT, 16))
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(card)
	var checklist := VBoxContainer.new()
	checklist.add_theme_constant_override("separation", 12)
	card.add_child(checklist)
	_label(checklist, 13, ACCENT, true).text = "REACTIVATION CHECKLIST"
	_rule(checklist)
	call_label = _label(checklist, 19, PAPER)
	call_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_label = _label(checklist, 18, ACCENT)
	action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_button = _button(checklist, "VERIFY   F12")
	confirm_button.add_theme_stylebox_override("normal", _box(ACCENT, ACCENT, 8))
	confirm_button.add_theme_stylebox_override("hover", _box(Color("#ffc497"), PAPER, 8))
	confirm_button.add_theme_stylebox_override("pressed", _box(Color("#e78749"), PAPER, 8))
	confirm_button.add_theme_color_override("font_color", FlightHud.INK)
	confirm_button.add_theme_color_override("font_hover_color", FlightHud.INK)
	confirm_button.add_theme_color_override("font_pressed_color", FlightHud.INK)
	confirm_button.add_theme_color_override("font_focus_color", FlightHud.INK)
	confirm_button.pressed.connect(scenario.confirm)
	notice_label = _label(checklist, 16, ACCENT)
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guidance_label = _label(checklist, 15, COOL, true)
	guidance_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	guidance_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_rule(frame)
	var help := _label(frame, 14, COOL, true)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "ESC MENU   ·   CLICK OPERATE   ·   SHIFT+CLICK REVERSE   ·   F FIND CONTROL   ·   R REPEAT RADIO   ·   M MUTE   ·   F5 / F9 SAVE / RESTORE   ·   P PAUSE CLOCK"
	select_panel("2 / 7")

func _add_dsky_key(parent: Control, key: String) -> void:
	var button := _button(parent, key, true)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(85, 61)
	button.pressed.connect(scenario.press_dsky.bind(key))
	dsky_keys[key] = button

func _operate(id: String) -> void:
	scenario.operate(id, -1 if Input.is_key_pressed(KEY_SHIFT) else 1)

func select_panel(panel: String) -> void:
	if not panels.has(panel):
		return
	selected_panel = panel
	for name: String in panels:
		panels[name].visible = name == panel
		tabs[name].set_pressed_no_signal(name == panel)
	scroll.scroll_vertical = 0

func show_target(focus := false) -> void:
	var step: Dictionary = scenario.current_step()
	var id: String = step.get("id", "")
	var target: Control
	if switches.has(id):
		var panel: String = Data.CONTROLS[id][0]
		if panel != selected_panel:
			select_panel(panel)
		target = switches[id]
	elif id == "dsky":
		select_panel("DSKY")
		target = dsky_keys[step.desired]
	if focus and target != null:
		target.grab_focus()
		scroll.call_deferred("ensure_control_visible", target)

func refresh() -> void:
	if not scenario.active():
		return
	var step: Dictionary = scenario.current_step()
	var id: String = step.get("id", "")
	var desired: String = step.get("desired", "")
	for control: String in switches:
		var settings: Array = Data.CONTROLS[control][2]
		var position: String = scenario.positions[control]
		var button: SwitchButton = switches[control]
		button.update_setting(position, 2.0 * float(settings.find(position)) / float(settings.size() - 1) - 1.0, control == id)
	for key: String in dsky_keys:
		dsky_keys[key].modulate = Color("#ecb26d") if id == "dsky" and key == desired else Color("#e1daca")
	call_label.text = step.get("caption", "")
	if not step.get("get", "").is_empty():
		var voice := "MATTINGLY" if step["get"] < "130:00:00" else "KERWIN"
		call_label.text = "%s GET   HOUSTON / %s\n\n%s" % [step["get"], voice, call_label.text]
	identity.text = "REACTIVATION   /   %02d OF %02d" % [mini(scenario.stage + 1, scenario.steps.size()), scenario.steps.size()]
	action_label.text = "PANEL %s   %s → %s" % [Data.CONTROLS[id][0], Data.CONTROLS[id][1], desired] if switches.has(id) else ("DSKY   " + desired if id == "dsky" else "")
	notice_label.text = scenario.notice
	confirm_button.visible = id != "dsky" and not step.is_empty()
	dsky_label.text = ["CMC   STANDBY", "VERB   37  FLASH", "VERB   96  /  INTEGRATION HOLD", "PROG   00"][scenario.computer_mode] if scenario.computer_powered() else "CMC   UNPOWERED"
	update_meters()

func update_meters() -> void:
	if not scenario.active():
		return
	source_label.text = "DC LOAD   /   AQUARIUS FEEDING MAIN B" if scenario.from_lm else "DC LOAD   /   ODYSSEY ENTRY BATTERIES"
	var current: float = scenario.total_current()
	var caution: bool = not scenario.within_budget()
	current_label.text = "%.1f A   /   %.0f A LIMIT" % [current, scenario.AMP_LIMIT]
	var meter_tint := RED if caution else (ACCENT if current >= 18.0 else GREEN)
	current_label.add_theme_color_override("font_color", meter_tint)
	meter_bar.value = current
	_meter_fill.bg_color = meter_tint
	var a := "%.1f V" % scenario.voltage_a if scenario.power_a else "OPEN"
	var b := "%.1f V" % scenario.voltage_b if scenario.power_b else "OPEN"
	bus_label.text = "MAIN A   %s     MAIN B   %s" % [a, b]
	var selected: String = scenario.positions.main_meter
	var readout: float = scenario.voltage_a if selected == "MAIN A" else (scenario.voltage_b if selected == "MAIN B" else 28.25)
	peak_label.text = "VOLTS SELECT   %s / %.1f V\nPEAK   %.1f A   ·   ENTRY BATTERY USED   %.2f Ah" % [
		selected, readout, scenario.peak, scenario.battery_c_used + scenario.battery_b_used]
	distribution[0].text = "MAIN A   ·   %.1f A\n%s" % [scenario.current_a, "BATTERY C" if scenario.power_a else "FEED OPEN"]
	var main_b_source := "AQUARIUS" if scenario.from_lm else ("BATTERY B" if scenario.power_b else "FEED OPEN")
	distribution[1].text = "MAIN B   ·   %.1f A\n%s" % [scenario.current_b, main_b_source]
	var inverter_live: bool = scenario.connected.get("inverter", 0) != 0
	var ac1 := "ON" if inverter_live and scenario.positions.ac_bus_1 == "ON" else "OFF"
	var ac2 := "ON" if inverter_live and scenario.positions.ac_bus_2 == "ON" else "OFF"
	distribution[2].text = "INVERTER 1   ·   %s\nAC 1 %s    /    AC 2 %s" % ["LIVE" if inverter_live else "OFF", ac1, ac2]
	var status := "HOLD   ·   24 V MIN / 20 A LIMIT"
	if not caution:
		status = "WITHIN LIMITS"
	if scenario.complete():
		status = "ODYSSEY ONLINE"
		if scenario.peak > scenario.AMP_LIMIT + 0.0001:
			status += "   ·   PEAK EXCEEDED BUDGET"
		call_label.text = "Odyssey is online on entry batteries. Communications, computer and guidance are available."
	elif scenario.current_step().is_empty():
		status = "POWER CONFIGURATION CHANGED"
		call_label.text = "Restore the entry configuration and bring the live load within limits."
	guidance_label.text = "%s\n%s" % [status, "Radio muted · M to unmute" if scenario.radio.muted else "R repeats the latest Houston call"]
	guidance_label.add_theme_color_override("font_color", RED if caution else GREEN)
