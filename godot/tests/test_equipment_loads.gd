extends SceneTree
## Desktop input, real EPS bridge and native checkpoint proof. No OpenXR.

var checks := 0
var failures := PackedStringArray()
var cabin: Node

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("FAIL: " + message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual-expected) < 0.000001, "%s: %.9f versus %.9f" % [message,actual,expected])

func operate_to(id: String, label: String) -> bool:
	var positions: Array = cabin.state_store.definitions[id].positions
	var target := positions.find(label)
	for attempt in range(positions.size()+1):
		var current: int = cabin.state_store.states[id]
		if current == target: return true
		cabin._operate(id,1 if target > current else -1,"equipment-integration",true)
	return false

func dc_current() -> float:
	var total := 0.0
	for bus: Dictionary in cabin.systems.electrical_snapshot.buses:
		if str(bus.id).ends_with("_DC"): total += float(bus.currentA)
	return total

func _run() -> void:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	await physics_frame
	check(cabin.load_errors.is_empty() and cabin.systems != null,"Actual cabin and electrical bridge initialize")
	check(not cabin.xr_active,"Headset runtime remains disabled")
	var systems = cabin.systems
	var clock = systems.session_clock
	check(clock != null and bool(systems.agc.call("IsStepped")),"Actual native CPU shares the EPS clock")
	if clock == null:
		quit(1)
		return
	var key := InputEventKey.new()
	key.keycode = KEY_F11
	key.pressed = true
	cabin._unhandled_input(key)
	check(systems.electrical_snapshot.loadModel == "sourced_components","F11 selects sourced equipment accounting through the desktop input path")
	check(not bool(systems.electrical_snapshot.completeEquipmentLoadCoverage),"Unknown equipment coverage remains explicit")
	check(cabin.mode_label.text.contains("KNOWN EQUIPMENT") and cabin.mode_label.text.contains("PARTIAL LOAD COVERAGE"),"HUD identifies partial demand instead of total flown current")
	for load: Dictionary in systems.electrical_snapshot.loads:
		check(not str(load.id).begins_with("aggregate_") and not str(load.sourceId).is_empty(),"Each active catalog entry has source identity and no aggregate duplicate: "+str(load.id))
	check(operate_to("p12_s_band_xmtr_rcvr","PRIM") and operate_to("p12_pwr_ampl","PRIM"),"Actual selectors energize the primary transceiver and amplifier")
	var before := dc_current()
	check(operate_to("p12_pwr_ampl","OFF"),"Common control path disables the power amplifier")
	near(before-dc_current(),72.0/30.0,"Source72W amplifier changes bus current by2.4A")
	check(operate_to("p12_pwr_ampl","PRIM"),"Amplifier reenergizes")
	cabin._operate("p16_cb_r03_c05",-1,"equipment-integration")
	near(before-dc_current(),72.0/30.0,"Pulling the actual amplifier breaker removes its current")
	cabin._operate("p16_cb_r03_c05",1,"equipment-integration")
	near(dc_current(),before,"Closing the actual breaker restores demand")
	check(operate_to("ordeal_earth_lunar","PWR OFF"),"ORDEAL can be powered down")
	before = dc_current()
	check(operate_to("ordeal_earth_lunar","EARTH"),"ORDEAL Earth mode energizes its DC and AC paths")
	near(dc_current()-before,8.0/30.0,"ORDEAL4WDC+4WAC reaches batteries once through ideal conversion")
	var live := dc_current()
	check(clock.advance_ticks(100),"Native CPU and source-load EPS advance together for one second")
	near(float(systems.electrical_snapshot.consumedWh),live*30.0/3600.0,"Actual scene conserves source watts over the shared clock")
	var saved: String = clock.save_json()
	check(not saved.is_empty(),"Complete source-load session checkpoint is available")
	var saved_time: int = clock.completed_ns
	check(systems.apply_preset("minimum_lifeboat_12a"),"Legacy aggregate calibration remains selectable")
	near(dc_current(),12.0,"Legacy12A calibration is preserved")
	check(clock.restore_json(saved),"Whole-session native restore reinstates source-load mode")
	check(systems.electrical_snapshot.loadModel == "sourced_components" and clock.completed_ns == saved_time,"Accounting model and exact shared time restore together")
	near(dc_current(),live,"Restored switch/relay states reproduce demand")
	check(cabin.state_store.position_name("ordeal_earth_lunar") == "EARTH" and cabin.state_store.position_name("p12_pwr_ampl") == "PRIM","Physical source-load selectors restore with EPS state")
	var report := {"schemaVersion":1,"result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":Array(failures),
		"kind":"Actual desktop F11, sourced electrical controls and complete native checkpoint integration","headsetTested":false,"flightValidationPassed":false,
		"electricalSha256":FileAccess.get_sha256(cabin.repository_path("reference/electrical.json")),"inventorySha256":FileAccess.get_sha256(cabin.repository_path("reference/controls.json"))}
	var file := FileAccess.open(cabin.repository_path("reference/equipment-load-integration.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("Equipment scene integration: %s; %d checks; %d failures." % [report.result,checks,failures.size()])
	cabin.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
