extends SceneTree
## Run with a dedicated APPDATA directory and without --self-test. This checks
## persistence in an actual ConfigFile without touching the operator's settings.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var first = load("res://scripts/cabin_audio.gd").new()
	root.add_child(first)
	first.enabled = true
	first.radio_enabled = false
	first.apply_profile("Quiet cabin")
	first.adjust_level("radio", 1)
	first.queue_free()
	await process_frame
	var second = load("res://scripts/cabin_audio.gd").new()
	root.add_child(second)
	var success: bool = second.enabled and not second.radio_enabled and second.profile == "Custom" and float(second.levels.radio) == 4.0 and float(second.levels.machinery) == -10.0
	print(JSON.stringify({"result": "PASS" if success else "FAIL", "checks": 5, "kind": "ConfigFile restart persistence in isolated user data"}))
	second.queue_free()
	await process_frame
	quit(0 if success else 1)
