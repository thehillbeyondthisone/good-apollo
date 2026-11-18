extends SceneTree
## Verify the normal application's backend selection and automatic shared stepping.

var failures := PackedStringArray()
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func _run() -> void:
	check(not "--stepped-agc" in OS.get_cmdline_user_args() and not "--external-agc" in OS.get_cmdline_user_args(), "Smoke test supplies no CPU selection override")
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var systems = scene.systems
	check(scene.load_errors.is_empty() and scene.bindings.size() == scene.state_store.definitions.size(), "Normal scene binds every declared inventory entry")
	check(systems != null and systems.session_clock != null and bool(systems.agc.call("IsStepped")), "Normal scene defaults to the shared native CPU")
	if systems == null or systems.session_clock == null:
		quit(1)
		return
	check(int(systems.agc.call("GetOwnedProcessId")) == 0, "Default scene launches no external CPU process")
	var clock = systems.session_clock
	for index in range(6):
		await physics_frame
	check(clock.completed_ns > 0, "Default shared clock automatically advances")
	var timing: Dictionary = JSON.parse_string(str(systems.agc.call("GetSnapshotJson")))
	check(int(timing.nativeCycles) * 46875 + int(timing.quarterNanosecondRemainder) == int(clock.completed_ns) * 4, "Automatic CPU timing follows the shared integer clock exactly")
	var current_eps: Dictionary = JSON.parse_string(str(systems.electrical.call("GetSnapshotJson")))
	check(is_equal_approx(float(current_eps.simulationTimeSeconds), float(clock.completed_ns) / 1000000000.0), "Authoritative EPS timing follows the same clock exactly")
	var presentation_lag := float(clock.completed_ns) / 1000000000.0 - float(systems.electrical_snapshot.simulationTimeSeconds)
	check(presentation_lag >= -0.000001 and presentation_lag <= 0.050001, "Display publication lags the authoritative model by at most50ms")
	clock.publish()
	check(is_equal_approx(float(systems.electrical_snapshot.simulationTimeSeconds), float(current_eps.simulationTimeSeconds)), "Explicit publication immediately synchronizes the display")
	clock.paused = true
	var saved: String = clock.save_json()
	for index in range(3):
		await physics_frame
	check(not saved.is_empty() and clock.save_json() == saved, "Pausing default mode freezes the complete deterministic session")
	scene.queue_free()
	await process_frame
	await process_frame
	var report := {"schemaVersion": 1, "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": Array(failures), "defaultBackend": "stepped", "automaticSharedClock": true, "headsetTested": false}
	var path := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("reference/default-backend.json")
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	print("Default backend integration: %s; %d checks; %d failures." % [report.result, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
