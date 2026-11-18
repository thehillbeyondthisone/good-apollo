extends Node
## One main-thread clock and an all-or-nothing checkpoint for the stepped backend.
const StateStore = preload("res://scripts/control_state.gd")
const TICK_NS := 10000000
const PRESENTATION_INTERVAL_NS := 50000000
const SESSION_SAVE := "user://session-state-v1.json"

var systems: Node
var completed_ns := 0
var pending_ns := 0
var eps_epoch_ns := 0
var paused := false
var last_error := ""
var inventory_hash := ""
var electrical_hash := ""
var autosave_allowed := true
var last_published_ns := 0
var lgc_supply := true

func setup(presenter: Node) -> void:
	systems = presenter
	inventory_hash = FileAccess.get_sha256(systems.cabin.repository_path("reference/controls.json"))
	electrical_hash = FileAccess.get_sha256(systems.cabin.repository_path("reference/electrical.json"))
	systems.electrical.call("SetAutomaticStep", false)
	# The coordinator publishes native display outputs alongside EPS. Avoid a
	# second presentation signal path; the actual CPU still steps every10ms.
	if systems.agc.is_connected("DskyUpdated", systems._on_agc):
		systems.agc.disconnect("DskyUpdated", systems._on_agc)
	sync_lgc_power(bool(systems.electrical.call("HasLgcPower")))

func sync_lgc_power(powered: bool) -> bool:
	if lgc_supply == powered:
		return true
	if not systems.agc.call("SetElectricalPower", powered):
		last_error = str(systems.agc.call("GetLastStateError"))
		paused = true
		return false
	lgc_supply = powered
	systems.cancel_demo()
	systems._on_agc(str(systems.agc.call("GetSnapshotJson")))
	return true

func _physics_process(delta: float) -> void:
	if paused or systems == null or "--manual-clock" in OS.get_cmdline_user_args():
		return
	pending_ns += int(round(delta * 1000000000.0))
	var stepped := false
	while pending_ns >= TICK_NS:
		if not advance_ticks(1, false):
			paused = true
			systems.cabin._notify("Shared simulation clock stopped: " + last_error)
			return
		pending_ns -= TICK_NS
		stepped = true
	if stepped and completed_ns - last_published_ns >= PRESENTATION_INTERVAL_NS:
		publish()

func advance_ticks(count: int, publish_after: bool = true) -> bool:
	if count < 0 or count > 360000:
		last_error = "Shared step count is out of range."
		return false
	for index in range(count):
		# CPU runs on the supply at the start of the quantum. Trips and source
		# exhaustion discovered in the EPS step take effect at its endpoint.
		if not systems.agc.call("AdvanceNanoseconds", TICK_NS):
			last_error = str(systems.agc.call("GetLastStateError"))
			return false
		if not systems.electrical.call("AdvanceShared", float(TICK_NS) / 1000000000.0):
			last_error = str(systems.electrical.call("GetLastError"))
			return false
		systems.co2.advance(float(TICK_NS) / 1000000000.0)
		systems.correction.advance(float(TICK_NS) / 1000000000.0)
		systems.odyssey.advance(float(TICK_NS) / 1000000000.0)
		completed_ns += TICK_NS
		if not sync_lgc_power(bool(systems.electrical.call("HasLgcPower"))):
			return false
	if publish_after:
		publish()
	return true

func publish() -> void:
	last_published_ns = completed_ns
	systems.electrical.call("PublishSnapshot")
	systems._on_agc(str(systems.agc.call("GetSnapshotJson")))

func reset_electrical_epoch() -> void:
	# Calibration presets deliberately reset the EPS trial, while the CPU continues.
	eps_epoch_ns = completed_ns

func save_json() -> String:
	if systems == null or not systems.agc.call("IsStepped"):
		last_error = "A complete checkpoint requires the stepped CPU backend."
		return ""
	var eps_state = systems.electrical.call("SaveStateJson")
	var agc_state = systems.agc.call("SaveStateJson")
	if not eps_state is String or not agc_state is String or eps_state.is_empty() or agc_state.is_empty():
		last_error = "A subsystem could not supply a checkpoint."
		return ""
	if not JSON.parse_string(eps_state) is Dictionary or not JSON.parse_string(agc_state) is Dictionary:
		last_error = "A subsystem supplied an invalid checkpoint."
		return ""
	var payload := {
		"schemaVersion": 1, "kind": "aquarius-stepped-session",
		"inventorySha256": inventory_hash, "electricalSha256": electrical_hash,
		"clock": {"quantumNanoseconds": TICK_NS, "completedNanoseconds": str(completed_ns), "pendingNanoseconds": str(pending_ns), "electricalEpochNanoseconds": str(eps_epoch_ns), "paused": paused},
		"controls": systems.cabin.state_store.get_save_payload(),
		"electrical": eps_state, "agc": agc_state,
		"powerDown": str(systems.electrical.call("SavePowerDownStateJson")),
		"momentaryRestorePolicy": "release physical momentaries and PRO; preserve other CPU inputs",
		"automationRestorePolicy": "cancel pending demonstration inputs",
		"flightPadloadApplied": false
	}
	if systems.co2.stage >= 0:
		payload["co2Adapter"] = systems.co2.save_state()
	if systems.correction.active():
		payload["manualCorrection"] = systems.correction.save_state()
	if systems.odyssey.active():
		payload["odysseyPowerup"] = systems.odyssey.save_state()
	var encoded := JSON.stringify(payload)
	return JSON.stringify({"schemaVersion": 1, "payloadSha256": encoded.sha256_text(), "payload": encoded}, "\t")

func _reject(message: String) -> bool:
	last_error = message
	if systems != null:
		systems.electrical.call("AbortPreparedState")
		systems.agc.call("AbortPreparedState")
	return false

func restore_json(json: String) -> bool:
	if systems == null or not systems.agc.call("IsStepped"):
		return _reject("The active backend cannot restore complete CPU checkpoints.")
	var envelope = JSON.parse_string(json)
	if not envelope is Dictionary or envelope.get("schemaVersion", 0) != 1 or not envelope.get("payload", null) is String:
		return _reject("Unsupported session envelope.")
	var encoded: String = envelope.payload
	if encoded.length() > 12000000 or encoded.sha256_text() != str(envelope.get("payloadSha256", "")):
		return _reject("Session checksum mismatch.")
	var payload = JSON.parse_string(encoded)
	if not payload is Dictionary or payload.get("schemaVersion", 0) != 1 or payload.get("kind", "") != "aquarius-stepped-session":
		return _reject("Unsupported session payload.")
	if payload.get("inventorySha256", "") != inventory_hash or payload.get("electricalSha256", "") != electrical_hash:
		return _reject("Session reference fingerprints do not match this project.")
	if not payload.get("controls", null) is Dictionary or not payload.get("clock", null) is Dictionary or not payload.get("electrical", null) is String or not payload.get("agc", null) is String:
		return _reject("Incomplete session payload.")
	if systems.cabin.xr_active and (payload.has("co2Adapter") or payload.has("manualCorrection") or payload.has("odysseyPowerup")):
		return _reject("This checkpoint uses desktop mission controls. Open Aquarius in desktop mode to continue it.")
	var clock: Dictionary = payload.clock
	if clock.get("quantumNanoseconds", 0) != TICK_NS or not clock.get("paused", null) is bool:
		return _reject("Saved clock quantum/pause state is incompatible.")
	for field: String in ["completedNanoseconds", "pendingNanoseconds", "electricalEpochNanoseconds"]:
		if not clock.get(field, null) is String or not str(clock[field]).is_valid_int():
			return _reject("Invalid saved clock integer.")
	var next_completed := int(clock.completedNanoseconds)
	var next_pending := int(clock.pendingNanoseconds)
	var next_epoch := int(clock.electricalEpochNanoseconds)
	if next_completed < 0 or next_completed > 1000000000000000 or next_completed % TICK_NS != 0 or next_pending < 0 or next_pending >= TICK_NS or next_epoch < 0 or next_epoch > next_completed or next_epoch % TICK_NS != 0:
		return _reject("Saved clock position is out of range.")
	var staged_controls = StateStore.new()
	var control_errors: PackedStringArray = staged_controls.configure(systems.cabin.inventory.get("controls", []))
	control_errors.append_array(staged_controls.apply_save_payload(payload.controls, true))
	if not control_errors.is_empty():
		return _reject("Control checkpoint rejected: " + control_errors[0])
	if not systems.electrical.call("PrepareStateJson", str(payload.electrical)):
		return _reject("Electrical checkpoint rejected: " + str(systems.electrical.call("GetLastError")))
	if not payload.get("powerDown", null) is String or not systems.electrical.call("PreparePowerDownStateJson", str(payload.powerDown)):
		return _reject("Power-down cursor rejected: " + str(systems.electrical.call("GetLastError")))
	var co2_state = payload.get("co2Adapter", {})
	if not systems.co2.valid_state(co2_state):
		return _reject("CO₂ adapter checkpoint is invalid.")
	if not co2_state.is_empty():
		var coast: Dictionary = JSON.parse_string(str(payload.powerDown))
		if not coast.active or int(coast.currentIndex) != int(systems.powerdown_snapshot.eventCount):
			return _reject("CO₂ adapter checkpoint requires the completed power-down.")
	var correction_state = payload.get("manualCorrection", {})
	if not systems.correction.valid_state(correction_state):
		return _reject("Manual course correction checkpoint is invalid.")
	if not correction_state.is_empty() and (co2_state.get("stage", -1) != systems.co2.install_count or not co2_state.get("resultAnnounced", false)):
		return _reject("Manual course correction requires the completed CO₂ adapter.")
	var odyssey_state = payload.get("odysseyPowerup", {})
	if not systems.odyssey.valid_state(odyssey_state):
		return _reject("Odyssey power-up checkpoint is invalid.")
	if not odyssey_state.is_empty() and correction_state.get("phase") != systems.correction.Phase.COMPLETE:
		return _reject("Odyssey power-up requires the completed manual course correction.")
	if not odyssey_state.is_empty() and systems.cabin.xr_active:
		return _reject("The Odyssey switch station is a desktop chapter.")
	if not systems.agc.call("PrepareStateJson", str(payload.agc)):
		return _reject("CPU checkpoint rejected: " + str(systems.agc.call("GetLastStateError")))
	var staged_eps: Dictionary = JSON.parse_string(str(systems.electrical.call("GetPreparedSnapshotJson")))
	var staged_time: Dictionary = JSON.parse_string(str(systems.agc.call("GetPreparedTimingJson")))
	if not str(staged_time.get("nativeCycles", "")).is_valid_int() or not str(staged_time.get("unclockedNanoseconds", "")).is_valid_int():
		return _reject("CPU checkpoint clock is missing.")
	var cycles := int(staged_time.nativeCycles)
	var carry := int(staged_time.get("quarterNanosecondRemainder", -1))
	var unclocked := int(staged_time.unclockedNanoseconds)
	if cycles < 0 or cycles > 100000000000 or carry < 0 or carry >= 46875 or unclocked < 0 or unclocked > next_completed or cycles * 46875 + carry != (next_completed - unclocked) * 4:
		return _reject("CPU checkpoint and shared clock disagree.")
	var staged_supply := false
	for branch: Dictionary in staged_eps.get("breakers", []):
		if branch.get("controlId", "") == "p11_cb_r04_c19":
			staged_supply = bool(branch.get("powered", false))
			break
	if staged_time.get("electricalPower", null) != staged_supply:
		return _reject("CPU checkpoint and electrical supply disagree.")
	var eps_elapsed := float(staged_eps.get("simulationTimeSeconds", -1.0))
	if absf(eps_elapsed - float(next_completed - next_epoch) / 1000000000.0) > 0.000001:
		return _reject("Electrical checkpoint and shared clock disagree.")
	for id: String in systems.modeled_ids:
		var label: String = staged_controls.position_name(id)
		if str(staged_eps.get("controlPositions", {}).get(id, "")) != label:
			return _reject("Physical and electrical switch states disagree: " + id)
	# All validation above is side-effect free. Both commits run on this main thread;
	# native commit stages its full payload again before touching the CPU.
	if not systems.agc.call("CommitPreparedState", false):
		return _reject("CPU commit failed; electrical/control state was not changed.")
	systems.electrical.call("CommitPreparedState", false)
	lgc_supply = staged_supply
	systems.cancel_demo()
	systems.cabin.state_store.states = staged_controls.states.duplicate()
	systems.cabin.state_store.axis_values = staged_controls.axis_values.duplicate()
	systems.cabin.held_button_ids.clear()
	completed_ns = next_completed
	pending_ns = next_pending
	eps_epoch_ns = next_epoch
	paused = bool(clock.paused)
	systems.cabin._apply_all_positions()
	systems.co2.restore(co2_state)
	systems.correction.restore(correction_state)
	systems.odyssey.restore(odyssey_state)
	publish()
	last_error = ""
	return true

func save_file(path: String = SESSION_SAVE) -> bool:
	var data := save_json()
	if data.is_empty(): return false
	var success := bool(systems.electrical.call("WriteAtomicText", ProjectSettings.globalize_path(path), data))
	if success:
		autosave_allowed = true
	else:
		last_error = str(systems.electrical.call("GetLastError"))
	return success

func load_file(path: String = SESSION_SAVE) -> bool:
	if not FileAccess.file_exists(path):
		return _reject("No complete session checkpoint exists.")
	return restore_json(FileAccess.get_file_as_string(path))
