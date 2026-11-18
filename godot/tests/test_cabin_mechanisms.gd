extends SceneTree
## Full imported-cabin/EPS/native-checkpoint integration, with OpenXR disabled.

var checks := 0
var failures := PackedStringArray()
var scene: Node
var ray_diagnostics: Array[Dictionary] = []
var controlled_batch_witnesses := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func operate_to(id: String, label: String, unlocked: bool = false) -> bool:
	if not scene.state_store.definitions.has(id): return false
	var target: int = scene.state_store.definitions[id].positions.find(label)
	if target < 0: return false
	for attempt in range(scene.state_store.definitions[id].positions.size()+1):
		var current: int = scene.state_store.states[id]
		if current == target: return true
		scene._operate(id,1 if target > current else -1,"mechanism-integration",unlocked)
		if current == int(scene.state_store.states[id]): return false
	return int(scene.state_store.states[id]) == target

func is_descendant(node: Node, ancestor: Node) -> bool:
	return ancestor.is_ancestor_of(node)

func ray_reaches(id: String) -> bool:
	var binding = scene.bindings[id]
	var center: Vector3 = binding.target_global_position()
	var normal: Vector3 = binding.target_surface_normal()
	var picked: String = scene._pick(center+normal*0.18,-normal)
	if picked != id:
		var query := PhysicsRayQueryParameters3D.create(center+normal*0.18,center-normal*2.02,24)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(query)
		var details := {"controlId":id,"pickedId":picked,"center":str(center),"normal":str(normal),"collider":str(hit.collider.get_path()) if not hit.is_empty() else "none","hitPosition":str(hit.get("position","none"))}
		ray_diagnostics.append(details)
		print("Mechanism ray diagnostic: "+JSON.stringify(details))
	return picked == id

func relative_to(node: Node3D, parent: Node3D) -> Transform3D:
	return parent.global_transform.affine_inverse()*node.global_transform

func delivered_ah() -> float:
	var total := 0.0
	for battery: Dictionary in scene.systems.electrical_snapshot.get("batteries",[]): total += float(battery.get("deliveredAh",0))
	return total

func check_batches(ids: Array[String], context: String) -> int:
	var examined := 0
	for id: String in ids:
		for source: MeshInstance3D in scene.cabin_batches.sources_for_control(id):
			examined += 1
			check(scene.cabin_batches.instance_world_transform(source).is_equal_approx(source.global_transform),context+": batched pose follows "+id+"/"+str(source.name))
	return examined

func install_batch_witnesses(ids: Array[String]) -> void:
	# Current custom mechanism meshes need not satisfy the production batcher's
	# shared-resource/group-size rules. Reuse one real imported hardware resource
	# as explicit test-only witnesses under the actual moving parent/child nodes.
	var sources: Array = scene.cabin_batches.get_batched_sources()
	check(not sources.is_empty(),"Production cabin provides an imported shared-hardware resource for controlled batch witnesses")
	if sources.is_empty(): return
	var template: MeshInstance3D = sources[0]
	for id: String in ids:
		var witness := MeshInstance3D.new()
		witness.name = "IntegrationBatchWitness_%02d" % controlled_batch_witnesses
		witness.mesh = template.mesh
		witness.material_override = template.material_override
		witness.layers = template.layers
		witness.cast_shadow = template.cast_shadow
		witness.gi_mode = template.gi_mode
		witness.position = Vector3(0.018,0.018,0.018)
		scene.bindings[id].actuator.add_child(witness)
		controlled_batch_witnesses += 1
	scene.cabin_batches.install(scene.imported_cabin,scene.bindings)

func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	check(scene.load_errors.is_empty(),"Actual inventory, layout and glTF load without errors")
	check(not scene.xr_active,"Offline fixture does not initialize OpenXR")
	check(scene.bindings.size() == scene.state_store.definitions.size(),"Every active inventory entry binds to the imported cabin")
	check(scene.systems != null and scene.systems.session_clock != null,"Actual cabin has the shared EPS/native CPU clock")
	check(scene.mechanisms != null and scene.cabin_batches != null,"Derived mechanism presenter and hardware batching initialize")
	if scene.systems == null or scene.systems.session_clock == null or scene.mechanisms == null or scene.cabin_batches == null:
		scene.queue_free()
		await process_frame
		quit(1)
		return
	var systems = scene.systems
	var clock = systems.session_clock
	var pose_ids: Array[String] = ["coas_mount","coas_cap","coas_illumination","utility_cdr_lamp","util_cdr","utility_cdr_clamp"]
	install_batch_witnesses(pose_ids)
	check(systems.apply_preset("electrical_checkout"),"Actual powered checkout initializes")
	check(int(systems.agc.call("GetOwnedProcessId")) == 0,"Native backend owns no external CPU process")
	var coas = scene.bindings.coas_mount
	for id: String in ["coas_cap","coas_illumination","coas_barrel_lock","coas_filter"]:
		check(is_descendant(scene.bindings[id].root,coas.actuator),"Imported COAS child is parented to the moving assembly: "+id)
	var cap_relative: Transform3D = relative_to(scene.bindings.coas_cap.root,coas.actuator)
	var illumination_relative: Transform3D = relative_to(scene.bindings.coas_illumination.root,coas.actuator)
	var cap_initial: Vector3 = scene.bindings.coas_cap.target_global_position()
	scene._operate("coas_mount",1,"mechanism-integration")
	check(scene.state_store.position_name("coas_mount") == "LEFT_WINDOW","Common input path rejects movement with COAS barrel secured")
	check(operate_to("coas_barrel_lock","RELEASED"),"Common input releases the COAS barrel lock")
	check(operate_to("coas_mount","DOCKING_WINDOW"),"Common input relocates COAS to the overhead mount")
	check(relative_to(scene.bindings.coas_cap.root,coas.actuator).is_equal_approx(cap_relative),"COAS cap retains its local assembly placement")
	check(relative_to(scene.bindings.coas_illumination.root,coas.actuator).is_equal_approx(illumination_relative),"COAS illumination knob follows remounting")
	check(not scene.bindings.coas_cap.target_global_position().is_equal_approx(cap_initial),"COAS cap interaction target moves with the actual glTF assembly")
	await physics_frame
	check(ray_reaches("coas_cap"),"Actual remounted COAS cap remains ray-pickable")
	check(ray_reaches("coas_illumination"),"Actual remounted COAS knob remains ray-pickable")
	var lamp = scene.bindings.utility_cdr_lamp
	for id: String in ["util_cdr","utility_cdr_clamp"]:
		check(is_descendant(scene.bindings[id].root,lamp.actuator),"Imported portable-lamp component follows the assembly: "+id)
	check(operate_to("utility_cdr_clamp","SECURED"),"Portable clamp can be secured through the input path")
	scene._operate("utility_cdr_lamp",1,"mechanism-integration")
	check(scene.state_store.position_name("utility_cdr_lamp") == "STOWED","Secured clamp blocks free lamp movement")
	check(operate_to("utility_cdr_clamp","RELEASED"),"Portable clamp releases")
	var selector_initial: Transform3D = scene.bindings.util_cdr.root.global_transform
	var selector_relative: Transform3D = relative_to(scene.bindings.util_cdr.root,lamp.actuator)
	check(operate_to("utility_cdr_lamp","FREE"),"Released lamp moves to the free proxy pose")
	check(not scene.bindings.util_cdr.root.global_transform.is_equal_approx(selector_initial),"Real utility selector geometry moves with the lamp")
	check(relative_to(scene.bindings.util_cdr.root,lamp.actuator).is_equal_approx(selector_relative),"Utility selector retains its local assembly pose")
	await physics_frame
	check(ray_reaches("util_cdr"),"Moved portable-lamp selector remains ray-pickable")
	check(operate_to("utility_cdr_clamp","SECURED") and operate_to("utility_cdr_lamp","CLAMPED"),"Secured clamp permits the clamped lamp proxy pose")
	await physics_frame
	check(ray_reaches("utility_cdr_clamp"),"Clamped lamp's clamp target follows its geometry")
	scene._operate("utility_cdr_lamp",-1,"mechanism-integration")
	check(scene.state_store.position_name("utility_cdr_lamp") == "CLAMPED","Secured clamp prevents leaving clamped pose")
	check(operate_to("utility_cdr_clamp","RELEASED") and operate_to("utility_cdr_lamp","FREE"),"Releasing clamp permits free movement again")
	check(operate_to("drogue_retention","SECURED"),"Drogue starts retained in tunnel")
	var drogue_initial: String = scene.state_store.position_name("drogue_pose")
	scene._operate("drogue_pose",1,"mechanism-integration")
	check(scene.state_store.position_name("drogue_pose") == drogue_initial,"Retention handles block drogue removal")
	check(operate_to("drogue_retention","RELEASED"),"Drogue retention handles release")
	var drogue_next: String = scene.state_store.definitions.drogue_pose.positions[1]
	check(operate_to("drogue_pose",drogue_next),"Released drogue can leave tunnel")
	scene._operate("drogue_retention",-1,"mechanism-integration")
	check(scene.state_store.position_name("drogue_retention") == "RELEASED","Retention cannot secure while drogue is out of tunnel")
	check(operate_to("utility_cdr_plug","CONNECTED") and operate_to("util_cdr","BRIGHT"),"Actual utility plug and selector provide the requested mode")
	scene.mechanisms.refresh()
	check(scene.mechanisms.lights.utility_cdr_lamp.light_energy > 0,"Actual portable Light3D emits through its powered EPS branch")
	scene._operate("p11_cb_r03_c18",1,"mechanism-integration")
	scene.mechanisms.refresh()
	check(is_zero_approx(scene.mechanisms.lights.utility_cdr_lamp.light_energy),"Opening real utility branch removes Light3D emission")
	check(operate_to("util_cdr","DIM"),"Unpowered utility selector remains mechanically operable")
	scene._operate("p11_cb_r03_c18",1,"mechanism-integration")
	scene.mechanisms.refresh()
	check(scene.mechanisms.lights.utility_cdr_lamp.light_energy > 0,"Restoring utility branch restores selected dim mode")
	check(operate_to("coas_cap","REMOVED") and operate_to("p8_coas","OVHD"),"COAS cap and power selector match overhead mount")
	scene._set_axis("coas_illumination",0.42,"mechanism-analog")
	scene._release_button("mechanism-analog")
	scene.mechanisms.refresh()
	check(scene.mechanisms.lights.coas_mount.light_energy > 0,"Actual COAS Light3D reflects valid branch/mount/cap/intensity")
	scene._operate("p11_cb_r02_c15",1,"mechanism-integration")
	scene.mechanisms.refresh()
	check(is_zero_approx(scene.mechanisms.lights.coas_mount.light_energy),"Opening actual COAS branch removes reticle emission")
	scene._set_axis("coas_illumination",0.18,"mechanism-analog")
	scene._release_button("mechanism-analog")
	check(is_equal_approx(scene.state_store.axis_value("coas_illumination"),0.18),"Unpowered COAS intensity knob remains mechanically operable")
	scene._operate("p11_cb_r02_c15",1,"mechanism-integration")
	scene._set_axis("coas_illumination",0.42,"mechanism-analog")
	scene._release_button("mechanism-analog")
	check(operate_to("ecs_des_h2o","CLOSE") and operate_to("ecs_asc_h2o","CLOSE") and operate_to("water_dispenser_cap","FITTED"),"Existing feed valves and dispenser cap can close")
	var charge_before := delivered_ah()
	scene._operate("water_dispenser_trigger",1,"mechanism-water")
	scene.mechanisms.refresh()
	check(scene.state_store.position_name("water_dispenser_trigger") != "RELEASED","Common input moves actual dispenser trigger with supply closed")
	check(not scene.mechanisms.derived.water_dispenser_trigger.flowPathAvailable,"Closed feed and fitted cap block only derived water-path availability")
	scene._release_button("mechanism-water")
	check(operate_to("ecs_des_h2o","OPEN") and operate_to("water_dispenser_cap","REMOVED"),"Actual feed and cap operations open dispenser path")
	scene._operate("water_dispenser_trigger",1,"mechanism-water")
	scene.mechanisms.refresh()
	check(scene.mechanisms.derived.water_dispenser_trigger.flowPathAvailable,"Held actual trigger exposes open water path")
	check(is_equal_approx(delivered_ah(),charge_before),"Manual-clock water indications consume no invented electrical charge")
	check(not scene.mechanisms.get_snapshot().consumablesPhysics,"Derived mechanism path makes no consumables-physics claim")
	var saved_poses: Dictionary = {}
	var saved_targets: Dictionary = {}
	for id: String in pose_ids:
		saved_poses[id] = scene.bindings[id].actuator.global_transform
		saved_targets[id] = scene.bindings[id].target_global_position()
	var batch_sources := check_batches(pose_ids,"Before checkpoint")
	check(batch_sources >= controlled_batch_witnesses and controlled_batch_witnesses > 0,"Controlled imported-hardware witnesses enter real batches under movable assemblies")
	var saved: String = clock.save_json()
	check(not saved.is_empty(),"Whole-session checkpoint includes actual mechanism states")
	scene._release_button("mechanism-water")
	check(operate_to("coas_mount","LEFT_WINDOW"),"Checkpoint mutation relocates COAS away from saved mount")
	check(operate_to("utility_cdr_clamp","SECURED") and operate_to("utility_cdr_lamp","CLAMPED"),"Checkpoint mutation changes actual portable lamp pose")
	scene._set_axis("coas_illumination",-0.6,"mechanism-analog")
	scene._release_button("mechanism-analog")
	check(clock.restore_json(saved),"Shared native CPU/EPS checkpoint restores complete mechanism session")
	check(scene.state_store.position_name("coas_mount") == "DOCKING_WINDOW" and scene.state_store.position_name("utility_cdr_lamp") == "FREE","Checkpoint restores both movable assembly state labels")
	check(is_equal_approx(scene.state_store.axis_value("coas_illumination"),0.42),"Checkpoint restores continuous COAS intensity exactly")
	for id: String in pose_ids:
		check(scene.bindings[id].actuator.global_transform.is_equal_approx(saved_poses[id]),"Checkpoint restores actual parent/child glTF actuator pose: "+id)
		check(scene.bindings[id].target_global_position().is_equal_approx(saved_targets[id]),"Checkpoint restores moved interaction target: "+id)
	check(scene.state_store.position_name("water_dispenser_trigger") == "RELEASED" and scene.held_button_ids.is_empty(),"Checkpoint releases actual held trigger and input ownership")
	scene.mechanisms.refresh()
	check(not scene.mechanisms.derived.water_dispenser_trigger.flowPathAvailable,"Restored released trigger closes derived flow availability")
	check(clock.save_json() == saved,"Restored session is canonical including continuous mechanism state")
	check_batches(pose_ids,"After checkpoint")
	await physics_frame
	check(ray_reaches("coas_illumination"),"Restored overhead COAS knob remains pickable")
	check(ray_reaches("util_cdr"),"Restored free portable-lamp selector remains pickable")
	var report := {"schemaVersion":1,"result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":Array(failures),"rayDiagnostics":ray_diagnostics,"inventoryEntries":scene.state_store.definitions.size(),"boundNodes":scene.bindings.size(),"sourceInventorySha256":FileAccess.get_sha256(scene.repository_path("reference/controls.json")),"mechanismLayoutSha256":FileAccess.get_sha256(scene.repository_path("assets/mechanism-layout.json")),"batchedSourcesExamined":batch_sources,"controlledBatchWitnesses":controlled_batch_witnesses,"batchEvidenceQualification":"Test-only copies of an actual imported shared mesh under real moving mechanism nodes; current custom mechanism geometry may remain unbatched by production eligibility rules.","headsetTested":false,"consumablesPhysics":false,"wholeSessionRestore":true,"kind":"Actual glTF cabin mechanism, electrical branch and native checkpoint integration"}
	var report_path: String = scene.repository_path("reference/cabin-mechanisms-integration.json")
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print(JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
