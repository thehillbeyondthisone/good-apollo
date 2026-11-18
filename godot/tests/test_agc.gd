extends SceneTree

var failures := PackedStringArray()
var checks := 0
var all_eights_seen := false
var alarm_clear_seen := false
var alarm_on_at := 0
var last_snapshot: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func _on_snapshot(json: String) -> void:
	var snapshot: Dictionary = JSON.parse_string(json)
	last_snapshot = snapshot
	var digits := ""
	for value in snapshot.get("readouts", {}).values():
		digits += str(value)
	if digits.count("8") == 21:
		all_eights_seen = true
	if all_eights_seen and snapshot.get("lampTestAlarm", false) and alarm_on_at == 0:
		alarm_on_at = Time.get_ticks_msec()
	if alarm_on_at > 0 and Time.get_ticks_msec() - alarm_on_at > 1000 and not snapshot.get("lampTestAlarm", true):
		alarm_clear_seen = true

func _wait_connected(bridge: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		last_snapshot = JSON.parse_string(bridge.call("GetSnapshotJson"))
		if last_snapshot.get("connected", false):
			return true
		await create_timer(0.05).timeout
	return false

func _send(bridge: Node, key: String) -> void:
	check(bool(bridge.call("SetKey", key, true)), "Upstream received key " + key)
	await create_timer(0.25).timeout
	bridge.call("SetKey", key, false)

func _observe_pro_channel(port: int) -> int:
	var observer := StreamPeerTCP.new()
	if observer.connect_to_host("127.0.0.1", port) != OK:
		return -1
	var bytes := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < deadline:
		observer.poll()
		var available := observer.get_available_bytes()
		if available > 0:
			var response := observer.get_data(available)
			if response[0] != OK: break
			bytes.append_array(response[1])
			while bytes.size() >= 4:
				if (bytes[0] & 0xc0) != 0 or (bytes[1] & 0xc0) != 0x40 or (bytes[2] & 0xc0) != 0x80 or (bytes[3] & 0xc0) != 0xc0:
					bytes = bytes.slice(1)
					continue
				var channel := ((int(bytes[0]) & 31) << 3) | ((int(bytes[1]) >> 3) & 7)
				var value := ((int(bytes[1]) & 7) << 12) | ((int(bytes[2]) & 63) << 6) | (int(bytes[3]) & 63)
				var mask_packet := (bytes[0] & 0x20) != 0
				bytes = bytes.slice(4)
				if channel == 26 and not mask_packet:
					observer.disconnect_from_host()
					return value
		await create_timer(0.01).timeout
	observer.disconnect_from_host()
	return -1

func _run() -> void:
	var script = load("res://scripts/VirtualAgcBridge.cs")
	check(script != null and script.can_instantiate(), "Compiled AGC bridge is available")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var bridge: Node = script.new()
	root.add_child(bridge)
	bridge.connect("DskyUpdated", _on_snapshot)
	check(bool(bridge.call("Initialize", "D:/apollo-ref/build/agc", 19777, false)), "Owned genuine yaAGC process starts")
	var pid: int = bridge.call("GetOwnedProcessId")
	check(pid > 0, "AGC bridge retains its own child PID")
	var connected: bool = await _wait_connected(bridge)
	check(connected, "Godot connects to the upstream SocketAPI endpoint")
	if connected:
		await _send(bridge, "p4_dsky_verb")
		await _send(bridge, "p4_dsky_3")
		await _send(bridge, "p4_dsky_7")
		await _send(bridge, "p4_dsky_entr")
		await _send(bridge, "p4_dsky_0")
		await _send(bridge, "p4_dsky_0")
		await _send(bridge, "p4_dsky_entr")
		await create_timer(0.75).timeout
		await _send(bridge, "p4_dsky_verb")
		await _send(bridge, "p4_dsky_3")
		await _send(bridge, "p4_dsky_5")
		await _send(bridge, "p4_dsky_entr")
		var deadline := Time.get_ticks_msec() + 9000
		while Time.get_ticks_msec() < deadline and not (all_eights_seen and alarm_clear_seen):
			await create_timer(0.05).timeout
		check(all_eights_seen, "Real LM131R1 V35 emits all 21 numeric eights through Godot decoder")
		check(alarm_on_at > 0 and alarm_clear_seen, "Real channel013 test alarm asserts then clears after the lamp interval")
		check(last_snapshot.get("packetsReceived", 0) > 0, "Real channel packets were received")
		check(last_snapshot.get("keyPressesSent", 0) == 11, "Each ordinary key press was sent once")
		check(not last_snapshot.get("flightPadloadApplied", true), "Test initialization is explicitly identified; no flight padload claim")
		var baseline: int = await _observe_pro_channel(19778)
		check(baseline >= 0 and (baseline & 8192) != 0, "Independent upstream observer sees PRO released")
		check(bool(bridge.call("SetKey", "p4_dsky_pro", true)), "PRO press is sent through the masked discrete")
		await create_timer(0.05).timeout
		var pressed: int = await _observe_pro_channel(19778)
		check(pressed == (baseline & ~8192), "PRO press changes only input032 bit020000")
		bridge.call("SetKey", "p4_dsky_pro", false)
		await create_timer(0.05).timeout
		check(int(await _observe_pro_channel(19778)) == baseline, "PRO release preserves every other input032 bit")
		var attached: Node = script.new()
		root.add_child(attached)
		check(bool(attached.call("Initialize", "", 19779, true)) and bool(await _wait_connected(attached)), "Explicit attachment connects without owning the CPU")
		check(int(attached.call("GetOwnedProcessId")) == 0, "Attached bridge has no child ownership")
		attached.call("SetKey", "p4_dsky_pro", true)
		await create_timer(0.05).timeout
		check(int(await _observe_pro_channel(19778)) == (baseline & ~8192), "Attached client can assert its PRO discrete")
		attached.queue_free()
		await process_frame
		await create_timer(0.05).timeout
		check(int(await _observe_pro_channel(19778)) == baseline, "Detaching releases a held PRO discrete")
		check(bool(bridge.call("IsProcessAlive", pid)), "Detaching does not stop an externally owned CPU")
		last_snapshot = JSON.parse_string(str(bridge.call("GetSnapshotJson")))
	bridge.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	var process_probe: Node = script.new()
	root.add_child(process_probe)
	check(pid > 0 and not bool(process_probe.call("IsProcessAlive", pid)), "Only the bridge-owned child is stopped on exit")
	process_probe.queue_free()
	var report := {"schemaVersion": 1, "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": Array(failures), "realUpstreamCli": true, "rope": "LM131R1", "flightPadloadApplied": false, "all21NumericEightsObserved": all_eights_seen, "lampClearObserved": alarm_clear_seen, "lastSnapshot": last_snapshot}
	var report_path := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("reference/agc-integration.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Godot / real yaAGC integration: %s; %d checks; all21eights=%s; timedLampClear=%s." % [report.result, checks, all_eights_seen, alarm_clear_seen])
	quit(0 if failures.is_empty() else 1)
