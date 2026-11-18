extends RefCounted
## Presentation state only. This deliberately has no electrical or flight-computer effects.

const READ_ONLY_TYPES := ["indicator", "meter", "display", "talkback", "light", "tape"]

var definitions: Dictionary = {}
var states: Dictionary = {}
var axis_values: Dictionary = {}

func configure(controls: Array) -> PackedStringArray:
	definitions.clear()
	states.clear()
	axis_values.clear()
	var errors := PackedStringArray()
	for value in controls:
		if not value is Dictionary:
			errors.append("Control entry must be an object.")
			continue
		var definition: Dictionary = value
		var id := str(definition.get("id", ""))
		var positions: Array = definition.get("positions", [])
		if id.is_empty() or positions.is_empty():
			errors.append("Control requires an ID and at least one position: %s" % id)
			continue
		if definitions.has(id):
			errors.append("Duplicate control ID: %s" % id)
			continue
		var initial := str(definition.get("default", positions[0]))
		var initial_index := positions.find(initial)
		if initial_index < 0:
			errors.append("Default position not declared: %s" % id)
			continue
		definitions[id] = definition
		states[id] = initial_index
		if is_analog(id):
			axis_values[id] = normalized_for_position(id, initial_index)
	return errors

func is_analog(id: String) -> bool:
	if not definitions.has(id) or definitions[id].positions.size() < 2:
		return false
	var definition: Dictionary = definitions[id]
	return str(definition.get("type", "")) == "axis" or definition.get("analog", null) is Dictionary

static func normalized_position(definition: Dictionary, index: int) -> float:
	var positions: Array = definition.get("positions", [])
	var metadata: Dictionary = definition.get("analog", definition.get("axis", {}))
	var minimum := float(metadata.get("min", -1.0))
	var maximum := float(metadata.get("max", 1.0))
	var label := str(positions[index])
	if label.is_valid_float() and maximum > minimum:
		return clampf((float(label) - minimum) / (maximum - minimum) * 2.0 - 1.0, -1.0, 1.0)
	return float(index) / float(maxi(1, positions.size() - 1)) * 2.0 - 1.0

func normalized_for_position(id: String, index: int) -> float:
	return normalized_position(definitions[id], index)

func position_for_normalized(id: String, value: float) -> int:
	var closest := INF
	var result := 0
	for index in range(definitions[id].positions.size()):
		var distance := absf(normalized_for_position(id, index) - value)
		if distance < closest:
			closest = distance
			result = index
	return result

func is_interactive(id: String) -> bool:
	if not definitions.has(id):
		return false
	var definition: Dictionary = definitions[id]
	return bool(definition.get("interactive", true)) and not str(definition.get("type", "indicator")) in READ_ONLY_TYPES and definition.positions.size() > 1

func is_momentary(id: String) -> bool:
	if not definitions.has(id):
		return false
	var definition: Dictionary = definitions[id]
	if definition.has("momentary"):
		return bool(definition.momentary)
	return str(definition.get("type", "")) in ["pushbutton", "joystick", "axis"] or bool(definition.get("springReturn", false)) or bool(definition.get("mechanism", {}).get("springReturn", false))

func is_guard_open(id: String, next_index: int = -1) -> bool:
	if not definitions.has(id):
		return false
	var mechanism: Dictionary = definitions[id].get("mechanism", {})
	var required: Dictionary = mechanism.get("requiredControlPosition", {})
	if not required.is_empty() and position_name(str(required.get("id", ""))) != str(required.get("position", "")):
		return false
	var guarded_positions: Array = mechanism.get("guardedPositions", [])
	if next_index >= 0 and not guarded_positions.is_empty() and not str(definitions[id].positions[next_index]) in guarded_positions:
		return true
	var guard_id := str(mechanism.get("guardId", ""))
	if guard_id.is_empty():
		return true
	return definitions.has(guard_id) and position_name(guard_id) == "OPEN"

func is_lever_locked(id: String) -> bool:
	return definitions.has(id) and bool(definitions[id].get("leverLock", definitions[id].get("mechanism", {}).get("leverLock", false)))

func is_motion_allowed(id: String, next_index: int, unlocked: bool = false) -> bool:
	if not definitions.has(id) or next_index < 0 or next_index >= definitions[id].positions.size(): return false
	var definition: Dictionary = definitions[id]
	var target := str(definition.positions[next_index])
	var mechanism: Dictionary = definition.get("mechanism", {})
	for requirement: Dictionary in definition.get("motionRequires", mechanism.get("motionRequires", [])):
		var applies: Array = requirement.get("appliesToPositions", [])
		if not applies.is_empty() and not target in applies: continue
		var required_id := str(requirement.get("controlId", ""))
		if not position_name(required_id) in requirement.get("allowedPositions", []): return false
	var release: Dictionary = definition.get("detentRelease", mechanism.get("detentRelease", {}))
	if str(release.get("gesture", "")) == "grip" and not unlocked:
		var exempt: Array = release.get("exceptFromPositions", release.get("exemptFromPositions", ["STOWED_UP"]))
		if not position_name(id) in exempt: return false
	return true

func set_axis(id: String, value: float, unlocked: bool = false) -> bool:
	if not is_analog(id) or not is_interactive(id) or not is_finite(value) or absf(value) > 1.0:
		return false
	var index := position_for_normalized(id, value)
	if (is_lever_locked(id) and not unlocked) or not is_guard_open(id, index) or not is_motion_allowed(id, index, unlocked): return false
	axis_values[id] = value
	states[id] = index
	return true

func axis_value(id: String) -> float:
	return float(axis_values.get(id, 0.0))

func position_name(id: String) -> String:
	if not definitions.has(id):
		return "UNKNOWN"
	return str(definitions[id].positions[int(states[id])])

func set_position(id: String, index: int) -> bool:
	if not definitions.has(id):
		return false
	if index < 0 or index >= definitions[id].positions.size():
		return false
	states[id] = index
	if is_analog(id):
		axis_values[id] = normalized_for_position(id, index)
	return true

func actuate(id: String, direction: int = 1, unlocked: bool = false) -> bool:
	if not is_interactive(id) or (is_lever_locked(id) and not unlocked):
		return false
	var count: int = definitions[id].positions.size()
	var next_index := count - 1 if str(definitions[id].get("type", "")) == "pushbutton" and is_momentary(id) else posmod(int(states[id]) + direction, count)
	if not bool(definitions[id].get("mechanism", {}).get("wrap", true)):
		next_index = clampi(int(states[id]) + direction, 0, count - 1)
		if next_index == int(states[id]): return false
	if not is_guard_open(id, next_index) or not is_motion_allowed(id, next_index, unlocked):
		return false
	if str(definitions[id].get("type", "")) == "pushbutton" and is_momentary(id):
		states[id] = count - 1
	else:
		set_position(id, next_index)
	for other_id: String in definitions:
		if id in definitions[other_id].get("mechanism", {}).get("resetBy", []) and int(states[id]) != definitions[id].positions.find(str(definitions[id].get("default", definitions[id].positions[0]))):
			var other: Dictionary = definitions[other_id]
			set_position(other_id, other.positions.find(str(other.get("default", other.positions[0]))))
	return true

func release(id: String) -> bool:
	if not is_momentary(id):
		return false
	var definition: Dictionary = definitions[id]
	states[id] = definition.positions.find(str(definition.get("default", definition.positions[0])))
	if axis_values.has(id):
		axis_values[id] = normalized_for_position(id, int(states[id]))
	return true

func reset() -> void:
	for id: String in definitions:
		var definition: Dictionary = definitions[id]
		states[id] = definition.positions.find(str(definition.get("default", definition.positions[0])))
		if axis_values.has(id):
			axis_values[id] = normalized_for_position(id, int(states[id]))

func get_save_payload() -> Dictionary:
	var persisted := states.duplicate()
	# Momentary controls represent a held input, not a latched spacecraft state.
	for id: String in definitions:
		if is_momentary(id):
			var definition: Dictionary = definitions[id]
			persisted[id] = definition.positions.find(str(definition.get("default", definition.positions[0])))
	var persisted_axes := axis_values.duplicate()
	for id: String in persisted_axes:
		if is_momentary(id):
			persisted_axes[id] = normalized_for_position(id, int(persisted[id]))
	return {"schemaVersion": 1, "purpose": "presentation-state-only", "states": persisted, "axes": persisted_axes}

func save_file(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(get_save_payload(), "\t"))
	file.close()
	return OK

func load_file(path: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not FileAccess.file_exists(path):
		return errors
	var document := JSON.new()
	var parse_error := document.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK or not document.data is Dictionary:
		errors.append("Saved state is not a JSON object.")
		return errors
	return apply_save_payload(document.data)

func apply_save_payload(payload: Dictionary, require_complete: bool = false) -> PackedStringArray:
	var errors := PackedStringArray()
	if payload.get("schemaVersion", 0) != 1 or not payload.get("states", null) is Dictionary:
		errors.append("Unsupported saved-state schema.")
		return errors
	if require_complete and payload.states.size() != definitions.size():
		errors.append("Checkpoint must contain every declared control.")
		return errors
	# Validate before changing state, so a damaged save cannot half-apply.
	var candidate := states.duplicate()
	for id: String in payload.states:
		if not definitions.has(id):
			errors.append("Saved state contains an unknown control: %s" % id)
			continue
		var value = payload.states[id]
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)):
			errors.append("Saved state has a non-integral position: %s" % id)
			continue
		var index := int(value)
		if index < 0 or index >= definitions[id].positions.size():
			errors.append("Saved state position is out of bounds: %s" % id)
			continue
		candidate[id] = index
	var candidate_axes := axis_values.duplicate()
	var saved_axes = payload.get("axes", {})
	if not saved_axes is Dictionary:
		errors.append("Saved axes must be an object.")
	else:
		if require_complete and saved_axes.size() != axis_values.size():
			errors.append("Checkpoint must contain every continuous control value.")
		for id: String in saved_axes:
			var value = saved_axes[id]
			if not candidate_axes.has(id) or not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 1.0:
				errors.append("Saved axis is invalid: %s" % id)
				continue
			var index := position_for_normalized(id, float(value))
			if int(candidate[id]) != index:
				errors.append("Saved axis position and value disagree: %s" % id)
			candidate_axes[id] = float(value)
	if errors.is_empty():
		for id: String in definitions:
			if is_momentary(id):
				var definition: Dictionary = definitions[id]
				candidate[id] = definition.positions.find(str(definition.get("default", definition.positions[0])))
		states = candidate
		for id: String in axis_values:
			axis_values[id] = normalized_for_position(id, int(states[id])) if is_momentary(id) or not saved_axes.has(id) else candidate_axes[id]
	return errors
