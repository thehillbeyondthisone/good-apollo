extends SceneTree
## Explicit core Touch bindings. Avoid optional generic/hand/palm profiles while
## validating the Steam Link controller path on this Quest setup.

func _initialize() -> void:
	var action_map := OpenXRActionMap.new()
	var action_set := OpenXRActionSet.new()
	action_set.resource_name = "godot"
	action_set.localized_name = "Aquarius cabin controls"
	var actions: Dictionary = {}
	var definitions := [
		["trigger", "Trigger", OpenXRAction.OPENXR_ACTION_FLOAT],
		["trigger_click", "Trigger pressed", OpenXRAction.OPENXR_ACTION_BOOL],
		["grip", "Grip", OpenXRAction.OPENXR_ACTION_FLOAT],
		["grip_click", "Grip pressed", OpenXRAction.OPENXR_ACTION_BOOL],
		["primary", "Thumbstick", OpenXRAction.OPENXR_ACTION_VECTOR2],
		["menu_button", "Recenter", OpenXRAction.OPENXR_ACTION_BOOL],
		["ax_button", "A or X", OpenXRAction.OPENXR_ACTION_BOOL],
		["by_button", "B or Y", OpenXRAction.OPENXR_ACTION_BOOL],
		["default_pose", "Default pose", OpenXRAction.OPENXR_ACTION_POSE],
		["aim_pose", "Aim pose", OpenXRAction.OPENXR_ACTION_POSE],
		["grip_pose", "Grip pose", OpenXRAction.OPENXR_ACTION_POSE],
	]
	for definition: Array in definitions:
		var action := OpenXRAction.new()
		action.resource_name = str(definition[0])
		action.localized_name = str(definition[1])
		action.action_type = int(definition[2])
		action.toplevel_paths = PackedStringArray(["/user/hand/left", "/user/hand/right"])
		actions[action.resource_name] = action
		action_set.add_action(action)
	action_map.add_action_set(action_set)
	var profile := OpenXRInteractionProfile.new()
	profile.interaction_profile_path = "/interaction_profiles/oculus/touch_controller"
	var bindings: Array = []
	for hand: String in ["left", "right"]:
		var base := "/user/hand/" + hand + "/input/"
		for name: String in ["default_pose", "aim_pose"]:
			bindings.append(_binding(actions[name], base + "aim/pose"))
		bindings.append(_binding(actions.grip_pose, base + "grip/pose"))
		bindings.append(_binding(actions.trigger, base + "trigger/value"))
		bindings.append(_binding(actions.trigger_click, base + "trigger/value"))
		bindings.append(_binding(actions.grip, base + "squeeze/value"))
		bindings.append(_binding(actions.grip_click, base + "squeeze/value"))
		bindings.append(_binding(actions.primary, base + "thumbstick"))
		bindings.append(_binding(actions.ax_button, base + ("x/click" if hand == "left" else "a/click")))
		bindings.append(_binding(actions.by_button, base + ("y/click" if hand == "left" else "b/click")))
	bindings.append(_binding(actions.menu_button, "/user/hand/left/input/menu/click"))
	profile.bindings = bindings
	action_map.add_interaction_profile(profile)
	var error := ResourceSaver.save(action_map, "res://openxr_action_map.tres")
	print("Core Touch OpenXR action map: %d actions / %d bindings / %s" % [actions.size(), bindings.size(), error_string(error)])
	quit(0 if error == OK else 1)

func _binding(action: OpenXRAction, path: String) -> OpenXRIPBinding:
	var binding := OpenXRIPBinding.new()
	binding.action = action
	binding.binding_path = path
	return binding
