extends RefCounted
## The action state machine is shared by real tracked controllers and the fixture.
## Samples are accepted only while the session is focused and the pose is tracked.

var cabin: Node
var hands: Dictionary = {}
var awaiting_release: Dictionary = {}
var operations: Dictionary = {}
var reverse_operations := 0
var tracking_releases := 0

func setup(owner: Node) -> void:
	cabin = owner

func hand_source(hand: String) -> String:
	return "xr:" + hand

func sample(hand: String, input: Dictionary, delta: float) -> void:
	var state: Dictionary = hands.get(hand, {"down": false, "selected": "", "step": 0, "repeat": 0.0})
	if not bool(input.get("active", false)):
		if bool(state.down):
			tracking_releases += 1
			awaiting_release[hand] = true
		cabin._release_button(hand_source(hand))
		hands.erase(hand)
		return
	var trigger := bool(input.get("trigger", false))
	var contact := str(input.get("contact", ""))
	if bool(awaiting_release.get(hand, false)):
		if trigger or not contact.is_empty(): return
		awaiting_release.erase(hand)
	# The input that started the hold owns its release. Switching from a poke
	# to a held trigger must not press the same control a second time.
	var touching := bool(state.touching) if bool(state.down) else not trigger and not contact.is_empty()
	var down := not contact.is_empty() if touching else trigger
	var reverse := not touching and bool(input.get("reverse", false))
	var stick: Vector2 = input.get("stick", Vector2.ZERO)
	if down and not bool(state.down):
		state.touching = touching
		state.selected = contact if touching else str(input.get("target", ""))
		var id := str(state.selected)
		if cabin.state_store.is_interactive(id):
			var kind := str(cabin.state_store.definitions[id].get("type", ""))
			if cabin.state_store.is_analog(id):
				cabin._set_axis(id, 0.0 if cabin.state_store.is_momentary(id) else cabin.state_store.axis_value(id), hand_source(hand), reverse)
			else:
				var direction := -1 if reverse else 1
				if kind in ["rotary","thumbwheel","valve","mechanism"]:
					var stick_value := stick.x if absf(stick.x) >= absf(stick.y) else stick.y
					if absf(stick_value) > 0.65:
						direction = int(signf(stick_value))
						state.step = direction
						state.repeat = 0.32
				var before: int = cabin.state_store.states[id]
				cabin._operate(id, direction, hand_source(hand), reverse)
				if before != int(cabin.state_store.states[id]):
					_record(id)
					if direction < 0: reverse_operations += 1
	if not down and bool(state.down):
		cabin._release_button(hand_source(hand))
		if touching and trigger: awaiting_release[hand] = true
		state.selected = ""
		state.step = 0
		state.repeat = 0.0
	if down and cabin.state_store.definitions.has(str(state.selected)):
		var id := str(state.selected)
		var definition: Dictionary = cabin.state_store.definitions[id]
		var kind := str(definition.get("type", ""))
		if cabin.state_store.is_analog(id):
			var axis: String = str(definition.get("analog", definition.get("axis", {})).get("axis", "pitch"))
			var horizontal := axis in ["yaw", "roll", "x", "horizontal"] or id.contains("_yaw") or id.contains("_roll") or id.contains("_translation_x")
			var value := stick.x if horizontal else stick.y
			if absf(value) < 0.12: value = 0.0
			# Spring-centered flight axes follow the stick directly. Latched knobs
			# and throttle retain their setting and move at the commanded rate.
			var requested := value if cabin.state_store.is_momentary(id) else clampf(cabin.state_store.axis_value(id) + value * delta, -1.0, 1.0)
			var previous: float = cabin.state_store.axis_value(id)
			cabin._set_axis(id, requested, hand_source(hand), reverse)
			if absf(value) > 0.2 and not is_equal_approx(previous, cabin.state_store.axis_value(id)): _record(id)
		elif kind in ["rotary", "thumbwheel", "valve", "mechanism"]:
			var value := stick.x if absf(stick.x) >= absf(stick.y) else stick.y
			var step := int(signf(value)) if absf(value) > 0.65 else 0
			state.repeat = maxf(0.0, float(state.repeat) - delta)
			if step != 0 and (step != int(state.step) or float(state.repeat) <= 0.0):
				var previous: int = cabin.state_store.states[id]
				cabin._operate(id, step, hand_source(hand), reverse)
				if previous != int(cabin.state_store.states[id]): _record(id)
				state.repeat = 0.32
			state.step = step
		elif kind == "joystick":
			var label := "CENTER"
			if stick.length() > 0.35:
				label = ("RIGHT" if stick.x > 0 else "LEFT") if absf(stick.x) > absf(stick.y) else ("UP" if stick.y > 0 else "DOWN")
			var index: int = definition.positions.find(label)
			if index < 0 and label == "CENTER":
				index = definition.positions.find(str(definition.get("default", definition.positions[0])))
			if index >= 0:
				var previous: int = cabin.state_store.states[id]
				cabin._set_xr_position(id, index, hand_source(hand))
				if label != "CENTER" and previous != int(cabin.state_store.states[id]): _record(id)
	state.down = down
	hands[hand] = state

func _record(id: String) -> void:
	operations[id] = int(operations.get(id, 0)) + 1

func release_all() -> void:
	for hand: String in hands.keys():
		cabin._release_button(hand_source(hand))
		if bool(hands[hand].get("down", false)): awaiting_release[hand] = true
	hands.clear()

func selected_id(hand: String) -> String:
	return str(hands.get(hand, {}).get("selected", ""))

func is_holding(hand: String) -> bool:
	return bool(hands.get(hand, {}).get("down", false))
