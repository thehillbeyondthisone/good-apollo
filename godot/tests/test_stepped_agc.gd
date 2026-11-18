extends SceneTree

var failures := PackedStringArray()
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func state(bridge: Node) -> Dictionary:
	return JSON.parse_string(str(bridge.call("GetSnapshotJson")))

func native_metadata(json: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(json)
	# Godot parses JSON numbers as doubles; retain the C# integer wire types.
	for key: String in ["schemaVersion", "packetsReceived", "keyPressesSent", "quarterNanosecondRemainder", "startupRemainingNanoseconds"]:
		data[key] = int(data[key])
	return data

func step(bridge: Node, nanoseconds: int) -> bool:
	return bool(bridge.call("AdvanceNanoseconds", nanoseconds))

func send(bridge: Node, key: String, duration_ns: int = 250000000) -> void:
	check(bool(bridge.call("SetKey", "p4_dsky_" + key, true)), "Native key press accepted: " + key)
	check(step(bridge, duration_ns), "CPU advances between distinct key presses")
	bridge.call("SetKey", "p4_dsky_" + key, false)

func _run() -> void:
	var script = load("res://scripts/VirtualAgcBridge.cs")
	var bridge: Node = script.new()
	root.add_child(bridge)
	check(bool(bridge.call("InitializeStepped", "")), "Pinned native CPU initializes through C# ABI wrapper")
	if not bridge.call("IsStepped"):
		print(bridge.call("GetLastStateError"))
		quit(1)
		return
	check(bridge.call("GetOwnedProcessId") == 0, "Stepped backend has no external process")
	check(state(bridge).get("backend", "") == "stepped", "Snapshot identifies shared-clock backend")
	for index in range(3): check(step(bridge, 250000000), "Exact quarter-second step %d" % index)
	check(int(state(bridge).nativeCycles) == 64000 and int(state(bridge).quarterNanosecondRemainder) == 0, "Three quarter-seconds equal exactly 64000 physical machine cycles")
	check(step(bridge, 1), "One-nanosecond fractional step applies")
	check(int(state(bridge).quarterNanosecondRemainder) == 4, "Subcycle carry is retained in quarter nanoseconds")
	var saved: String = bridge.call("SaveStateJson")
	step(bridge, 10000000)
	var after: String = bridge.call("SaveStateJson")
	check(bool(bridge.call("PrepareStateJson", saved)) and bool(bridge.call("CommitPreparedState", true)), "Native state stages and restores")
	check(str(bridge.call("SaveStateJson")) == saved, "Native state restores exact canonical bytes and counters")
	step(bridge, 10000000)
	check(str(bridge.call("SaveStateJson")) == after, "Identical post-restore tick replays identical canonical state")
	var before_bad: String = bridge.call("SaveStateJson")
	check(bool(bridge.call("PrepareStateJson", JSON.stringify(native_metadata(before_bad)))), "Integer-normalized Godot JSON reaches valid native staging")
	bridge.call("AbortPreparedState")
	var bad: Dictionary = native_metadata(before_bad)
	var bytes := Marshalls.base64_to_raw(str(bad.checkpointBase64))
	bytes[-1] = bytes[-1] ^ 0x5a
	bad.checkpointBase64 = Marshalls.raw_to_base64(bytes)
	check(not bool(bridge.call("PrepareStateJson", JSON.stringify(bad))), "Corrupt native payload is rejected before mutation")
	check(str(bridge.call("SaveStateJson")) == before_bad, "Rejected native payload leaves the CPU unchanged")
	bad = native_metadata(before_bad)
	bad.dllSha256 = "0".repeat(64)
	check(not bool(bridge.call("PrepareStateJson", JSON.stringify(bad))), "Foreign adapter fingerprint is rejected")
	check(str(bridge.call("SaveStateJson")) == before_bad, "Foreign fingerprint leaves CPU unchanged")
	bad = native_metadata(before_bad)
	bad.nativeCycles = str(int(bad.nativeCycles) + 1)
	check(not bool(bridge.call("PrepareStateJson", JSON.stringify(bad))), "CPU timing metadata must match the validated native bytes")
	check(str(bridge.call("SaveStateJson")) == before_bad, "Rejected timing metadata leaves CPU unchanged")
	bad = native_metadata(before_bad)
	bad.quarterNanosecondRemainder = (int(bad.quarterNanosecondRemainder) + 1) % 46875
	check(not bool(bridge.call("PrepareStateJson", JSON.stringify(bad))), "Subcycle metadata must match the validated native bytes")
	check(str(bridge.call("SaveStateJson")) == before_bad, "Rejected subcycle metadata leaves CPU unchanged")
	var baseline: int = bridge.call("GetInputChannel", 26)
	bridge.call("SetKey", "p4_dsky_pro", true)
	check(int(bridge.call("GetInputChannel", 26)) == (baseline & ~8192), "Native PRO assertion preserves all other bits")
	var held: String = bridge.call("SaveStateJson")
	bridge.call("SetKey", "p4_dsky_pro", false)
	check(bool(bridge.call("PrepareStateJson", held)) and bool(bridge.call("CommitPreparedState", true)), "Checkpoint captured during held PRO restores")
	check(int(bridge.call("GetInputChannel", 26)) == (baseline | 8192), "Restoring a released physical input does not latch PRO down")
	for key: String in ["verb", "3", "7", "entr", "0", "0", "entr"]: send(bridge, key)
	step(bridge, 750000000)
	for key: String in ["verb", "3", "5", "entr"]: send(bridge, key)
	var eights := false
	var test_alarm := false
	var test_cleared := false
	for index in range(800):
		step(bridge, 10000000)
		var current := state(bridge)
		var digits := ""
		for reading in current.readouts.values(): digits += str(reading)
		if digits.count("8") == 21: eights = true
		if current.get("lampTestAlarm", false): test_alarm = true
		if test_alarm and not current.get("lampTestAlarm", true): test_cleared = true
	check(eights and test_alarm and test_cleared, "Stepped real LM131R1 produces V35 eights and timed test-alarm clear")
	for key: String in ["verb", "3", "5"]: send(bridge, key, 50000000)
	check(str(state(bridge).readouts.p4_dsky_verb_display) == "35", "Distinct 50 ms key presses survive the 10 ms shared quantum")
	bridge.queue_free()
	await process_frame
	var second: Node = script.new()
	root.add_child(second)
	check(bool(second.call("InitializeStepped", "")), "Native context is released on node exit")
	second.queue_free()
	await process_frame
	var report := {"schemaVersion": 1, "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": Array(failures), "realUpstreamCpu": true, "flightPadloadApplied": false, "v35Passed": eights and test_alarm and test_cleared, "subcycleReplay": true, "sharedQuantumNanoseconds": 10000000}
	var path := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("reference/agc-native-integration.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Godot/native CPU interop: %s; %d checks; %d failures." % [report.result, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
