extends SceneTree

const StateStore = preload("res://scripts/control_state.gd")
const Binding = preload("res://scripts/control_binding.gd")
const Presenter = preload("res://scripts/mechanisms_presenter.gd")
var checks := 0
var failures := PackedStringArray()

class FixtureCabin:
	extends Node3D
	var state_store = StateStore.new()
	var bindings: Dictionary = {}
	var systems: Node
	var cabin_audio: Node3D
	var imported_cabin: Node3D = self
	func _notify(_message: String) -> void:
		pass

class FixtureSystems:
	extends Node
	var electrical_snapshot: Dictionary = {"breakers": []}
	var lighting_state: Dictionary = {"flood": 0.8}

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func _definition(id: String, type: String, positions: Array, extra: Dictionary = {}) -> Dictionary:
	var result := {"id":id,"type":type,"positions":positions,"default":positions[0],"interactive":true}
	result.merge(extra,true)
	return result

func _binding(cabin: Node3D, definition: Dictionary) -> RefCounted:
	var root := Node3D.new()
	root.name = str(definition.id)
	root.rotation_degrees = Vector3(10, 15, 20)
	var actuator := Node3D.new()
	actuator.name = "actuator"
	actuator.position = Vector3(0,0.006,0)
	root.add_child(actuator)
	cabin.add_child(root)
	var binding = Binding.new()
	binding.setup(definition,root)
	cabin.bindings[definition.id] = binding
	return binding

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var cabin := FixtureCabin.new()
	root.add_child(cabin)
	cabin.systems = FixtureSystems.new()
	cabin.add_child(cabin.systems)
	var controls := [
		_definition("coas_barrel_lock","mechanism",["SECURED","RELEASED"]),
		_definition("coas_mount","mechanism",["LEFT_WINDOW","REMOVED","DOCKING_WINDOW"],{"motionRequires":[{"controlId":"coas_barrel_lock","allowedPositions":["RELEASED"]}],"presentation":{"motion":{"kind":"poses","worldPositionsBlenderM":[[0,0,0],[0.2,0.3,0.4],[0.5,0.6,0.7]],"worldRotationsBlenderDeg":[[0,0,0],[0,0,0],[90,0,0]]}}}),
		_definition("coas_illumination","axis",["MIN","MID","MAX"],{"momentary":false,"emissionRequires":[{"controlId":"coas_cap","allowedPositions":["REMOVED"]}]}),
		_definition("coas_cap","mechanism",["FITTED","REMOVED"]),
		_definition("coas_filter","mechanism",["REMOVED","FITTED"]),
		_definition("p8_coas","toggle",["OFF","FWD","OVHD"]),
		_definition("shade_cdr","mechanism",["STOWED","DEPLOYED"],{"presentation":{"motion":{"kind":"scale","axis":"y","values":[0.025,1]}}}),
		_definition("armrest","mechanism",["STOWED_UP","ADJUST_1","ADJUST_2"],{"detentRelease":{"gesture":"grip","exceptFromPositions":["STOWED_UP"]},"mechanism":{"wrap":false},"presentation":{"motion":{"kind":"rotate","axis":"x","values":[90,20,-20]}}}),
		_definition("axis_locked","axis",["MIN","MID","MAX"],{"momentary":false,"motionRequires":[{"controlId":"coas_barrel_lock","allowedPositions":["RELEASED"]}]}),
		_definition("utility_cdr_lamp","mechanism",["STOWED","REMOVED","CLAMPED"],{"motionRequires":[{"controlId":"utility_cdr_clamp","allowedPositions":["OPEN"]}],"presentation":{"motion":{"kind":"translate","axis":"z","values":[0,0.1,0.2]}}}),
		_definition("utility_cdr_clamp","mechanism",["CLOSED","OPEN"]),
		_definition("utility_cdr_plug","mechanism",["DISCONNECTED","CONNECTED"]),
		_definition("util_cdr","rotary",["OFF","DIM","BRIGHT"]),
		_definition("utility_lmp_lamp","mechanism",["STOWED","FREE","CLAMPED"]),
		_definition("utility_lmp_plug","mechanism",["DISCONNECTED","CONNECTED"]),
		_definition("util_lmp","rotary",["OFF","DIM","BRIGHT"]),
		_definition("flood_overhead_cdr_aim","axis",["MIN","MID","MAX"],{"momentary":false}),
		_definition("water_dispenser_trigger","pushbutton",["RELEASED","PRESSED"],{"flowRequires":[{"controlId":"water_dispenser_cap","allowedPositions":["REMOVED"]}]}),
		_definition("water_dispenser_pose","mechanism",["STOWED","REMOVED"]),
		_definition("water_dispenser_cap","mechanism",["FITTED","REMOVED"]),
		_definition("ecs_asc_h2o","valve",["CLOSE","OPEN"]),
		_definition("ecs_des_h2o","valve",["CLOSE","OPEN"]),
		_definition("limited_mount","mechanism",["STOWED","FREE","INSTALLED"],{"motionRequires":[{"controlId":"coas_barrel_lock","allowedPositions":["RELEASED"],"appliesToPositions":["INSTALLED"]}]}),
	]
	check(cabin.state_store.configure(controls).is_empty(), "Mechanism fixture configures")
	for definition: Dictionary in controls:
		var binding = _binding(cabin,definition)
		check(binding.motion_errors.is_empty(), "Presentation motion accepted: " + str(definition.id))
	check(not cabin.state_store.actuate("coas_mount",1), "Secured barrel lock blocks COAS remounting")
	check(not cabin.state_store.set_axis("axis_locked",0.4), "Motion dependency also blocks analog travel")
	check(cabin.state_store.actuate("limited_mount",1), "Target-specific requirement permits unrelated movement")
	check(not cabin.state_store.actuate("limited_mount",1), "Target-specific requirement blocks installation")
	cabin.state_store.actuate("coas_barrel_lock",1)
	check(cabin.state_store.actuate("coas_mount",1), "Released barrel permits remounting")
	check(cabin.state_store.set_axis("axis_locked",0.4), "Released dependency permits analog travel")
	check(cabin.state_store.actuate("armrest",1), "Downward motion leaves stowed armrest without latch gesture")
	check(not cabin.state_store.actuate("armrest",1), "Other armrest detents require grip latch gesture")
	check(cabin.state_store.actuate("armrest",1,true), "Grip latch gesture permits next armrest detent")
	var mount = cabin.bindings.coas_mount
	mount.apply_position(0)
	check(mount.actuator.transform.is_equal_approx(mount.initial_actuator_transform), "World-pose default preserves exported transform")
	var target_before: Vector3 = mount.target_global_position()
	mount.apply_position(1)
	var target_after: Vector3 = mount.target_global_position()
	check((target_after-target_before).is_equal_approx(Vector3(0.2,0.4,-0.3)), "World translation converts Blender coordinates exactly")
	check(mount.interaction_area.get_parent() == mount.actuator, "Moved assembly collider follows actuator")
	mount.apply_position(2)
	var actual_delta: Basis = mount.root.global_basis * mount.actuator.basis * mount.initial_actuator_transform.basis.inverse() * mount.root.global_basis.inverse()
	check(actual_delta.is_equal_approx(Binding.blender_rotation([90,0,0])), "World rotation applies converted basis delta")
	var shade = cabin.bindings.shade_cdr
	shade.apply_position(1)
	check(shade.interaction_area.get_parent() == shade.root, "Scaling a flexible sheet leaves its target at the fixed attachment")
	var utility = cabin.bindings.utility_cdr_lamp
	utility.apply_position(1)
	check(is_equal_approx(utility.actuator.position.y-utility.initial_actuator_transform.origin.y,0.1), "Local Blender Z translates along Godot Y")
	var presenter := Presenter.new()
	cabin.add_child(presenter)
	presenter.setup(cabin)
	check(not presenter.derived.utility_cdr_lamp.emitting, "Unpowered utility light stays dark")
	check(cabin.state_store.actuate("util_cdr",1), "Physical utility selector remains operable without power")
	cabin.state_store.set_position("util_cdr",2)
	cabin.state_store.set_position("utility_cdr_plug",1)
	cabin.systems.electrical_snapshot.breakers = [{"controlId":"p11_cb_r03_c18","powered":true},{"controlId":"p11_cb_r02_c15","powered":true},{"controlId":"p16_cb_r02_c01","powered":true}]
	presenter.refresh()
	check(presenter.derived.utility_cdr_lamp.emitting, "Powered plugged utility light illuminates")
	cabin.state_store.set_position("util_lmp",2)
	cabin.state_store.set_position("utility_lmp_plug",1)
	presenter.refresh()
	check(presenter.lights.utility_cdr_lamp.light_energy > presenter.lights.utility_lmp_lamp.light_energy, "CDR utility mode is brighter than corresponding powered LMP mode")
	cabin.state_store.set_position("util_cdr",1)
	cabin.state_store.set_position("util_lmp",1)
	presenter.refresh()
	check(presenter.lights.utility_cdr_lamp.light_energy > presenter.lights.utility_lmp_lamp.light_energy, "CDR DIM mode also remains brighter than LMP DIM")
	cabin.state_store.set_position("utility_cdr_plug",0)
	presenter.refresh()
	check(not presenter.derived.utility_cdr_lamp.emitting, "Unplugging utility removes illumination")
	check(presenter.derived.flood_overhead_cdr_aim.emitting, "Powered flood output follows existing flood gain")
	cabin.state_store.set_position("coas_mount",0)
	cabin.state_store.set_position("coas_cap",1)
	cabin.state_store.set_position("p8_coas",1)
	cabin.state_store.set_axis("coas_illumination",0.5)
	presenter.refresh()
	check(presenter.derived.coas_mount.emitting, "Correct mount/power/cap/brightness illuminate COAS")
	cabin.state_store.set_position("shade_cdr",1)
	presenter.refresh()
	check(presenter.derived.coas_mount.emitting and presenter.derived.coas_mount.viewObscuredByShade, "Shade obscures external view without cutting internal COAS illumination")
	check(cabin.state_store.actuate("water_dispenser_trigger",1), "Dispenser trigger moves with feed closed and cap fitted")
	presenter.refresh()
	check(not presenter.derived.water_dispenser_trigger.flowPathAvailable, "Closed supply and cap block derived water path")
	cabin.state_store.set_position("ecs_des_h2o",1)
	cabin.state_store.set_position("water_dispenser_cap",1)
	presenter.refresh()
	check(presenter.derived.water_dispenser_trigger.flowPathAvailable, "Open feed and removed cap allow held water path")
	check(not presenter.derived.water_dispenser_trigger.flowRateModeled and not presenter.get_snapshot().consumablesPhysics, "Water indication makes no flow-rate or consumption claim")
	cabin.state_store.release("water_dispenser_trigger")
	presenter.refresh()
	check(not presenter.derived.water_dispenser_trigger.flowPathAvailable, "Releasing dispenser trigger closes derived path")
	var repo_root := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir()
	var inventory_path := repo_root.path_join("reference/controls.json")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--inventory="): inventory_path = argument.trim_prefix("--inventory=")
	var inventory = JSON.parse_string(FileAccess.get_file_as_string(inventory_path))
	var layout = JSON.parse_string(FileAccess.get_file_as_string(repo_root.path_join("assets/mechanism-layout.json")))
	var source_store = StateStore.new()
	check(source_store.configure(inventory.get("controls",[])).is_empty(), "Current source inventory configures")
	var declared_mechanisms := 0
	for id: String in layout.get("controls",{}):
		if id in ["util_cdr","util_lmp"]: continue
		if not source_store.definitions.has(id): continue
		declared_mechanisms += 1
		var definition: Dictionary = source_store.definitions[id]
		for field: String in ["motionRequires","flowRequires","emissionRequires"]:
			_check_requirements(source_store,definition.get(field,[]),id+" "+field)
	check(declared_mechanisms == 35, "All thirty-five source-backed mechanism additions exist in the inventory")
	var report := {"schemaVersion":1,"result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":Array(failures),"headsetTested":false,"kind":"Source-qualified mechanism constraints, transforms and derived light/path software fixture","consumablesPhysics":false,"sourceInventorySha256":FileAccess.get_sha256(inventory_path),"sourceMechanisms":declared_mechanisms}
	var target := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("reference/mechanism-runtime-tests.json")
	var file := FileAccess.open(target,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print(JSON.stringify(report))
	cabin.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_requirements(store: RefCounted, requirements: Array, context: String) -> void:
	for requirement: Dictionary in requirements:
		if requirement.has("anyOf"):
			_check_requirements(store,requirement.anyOf,context)
		elif requirement.has("breakerId"):
			check(store.definitions.has(str(requirement.breakerId)), "Sourced breaker dependency exists: " + context)
		else:
			var id := str(requirement.get("controlId",""))
			check(store.definitions.has(id), "Sourced mechanism dependency exists: " + context + " -> " + id)
			if store.definitions.has(id):
				for label: String in requirement.get("allowedPositions",[]):
					check(label in store.definitions[id].positions, "Dependency position is source-declared: " + context + " -> " + label)
