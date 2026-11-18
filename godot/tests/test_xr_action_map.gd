extends SceneTree
## Structural bindings check only. Hardware stability requires the live retake.

var checks := 0
var failures := PackedStringArray()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func _initialize() -> void:
	var action_map := load("res://openxr_action_map.tres") as OpenXRActionMap
	check(action_map != null, "Action map loads")
	if action_map == null:
		quit(1)
		return
	check(action_map.get_action_set_count() == 1, "One cabin action set")
	check(action_map.get_interaction_profile_count() == 1, "Only the core Touch profile is suggested")
	var action_set := action_map.get_action_set(0)
	var actions: Dictionary = {}
	for action: OpenXRAction in action_set.actions:
		check(not actions.has(action.resource_name), "Unique action name: " + action.resource_name)
		actions[action.resource_name] = action
		check(action.toplevel_paths == PackedStringArray(["/user/hand/left", "/user/hand/right"]), "Only hand subactions: " + action.resource_name)
	var required := {"trigger":OpenXRAction.OPENXR_ACTION_FLOAT, "trigger_click":OpenXRAction.OPENXR_ACTION_BOOL, "grip":OpenXRAction.OPENXR_ACTION_FLOAT, "grip_click":OpenXRAction.OPENXR_ACTION_BOOL, "primary":OpenXRAction.OPENXR_ACTION_VECTOR2, "menu_button":OpenXRAction.OPENXR_ACTION_BOOL, "ax_button":OpenXRAction.OPENXR_ACTION_BOOL, "by_button":OpenXRAction.OPENXR_ACTION_BOOL, "default_pose":OpenXRAction.OPENXR_ACTION_POSE, "aim_pose":OpenXRAction.OPENXR_ACTION_POSE, "grip_pose":OpenXRAction.OPENXR_ACTION_POSE}
	check(actions.size() == required.size(), "Exactly the essential action set")
	for name: String in required:
		check(actions.has(name) and int(actions[name].action_type) == int(required[name]), "Required action has correct type: " + name)
	var profile := action_map.get_interaction_profile(0)
	check(profile.interaction_profile_path == "/interaction_profiles/oculus/touch_controller", "Core Oculus Touch interaction profile")
	var pairs: Dictionary = {}
	var per_action: Dictionary = {}
	for binding: OpenXRIPBinding in profile.bindings:
		var name := str(binding.action.resource_name)
		var path := binding.binding_path
		var pair := name + "=" + path
		check(not pairs.has(pair), "No duplicate action/path binding: " + pair)
		pairs[pair] = true
		per_action[name] = int(per_action.get(name,0)) + 1
		check(path.begins_with("/user/hand/left/input/") or path.begins_with("/user/hand/right/input/"), "Binding belongs to a core hand input: " + path)
		check(not path.contains("grip_surface") and not path.contains("palm") and not path.contains("_ext"), "No optional palm or hand extension binding: " + path)
	for name: String in required:
		check(int(per_action.get(name,0)) == (1 if name == "menu_button" else 2), "Every essential action has its intended hand bindings: " + name)
	for hand: String in ["left", "right"]:
		for name: String in ["default_pose", "aim_pose"]:
			check(pairs.has(name + "=/user/hand/" + hand + "/input/aim/pose"), "Aim/default pose bound for " + hand)
		check(pairs.has("grip_pose=/user/hand/" + hand + "/input/grip/pose"), "Grip pose bound for " + hand)
	check(profile.bindings.size() == 21, "Twenty-one core Touch bindings")
	var report := {"schemaVersion":1, "result":"PASS" if failures.is_empty() else "FAIL", "checks":checks, "failures":Array(failures), "actions":actions.size(), "bindings":profile.bindings.size(), "profiles":[profile.interaction_profile_path], "headsetTested":false, "kind":"Core Touch action-map structure; live controller reliability remains a hardware check"}
	var target := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("reference/xr-action-map-tests.json")
	var file := FileAccess.open(target, FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
