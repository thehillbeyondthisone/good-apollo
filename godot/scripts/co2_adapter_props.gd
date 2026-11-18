extends Node3D
## Pickable workshop props. The work area and exact staging locations are reconstructed.

const PREFIX := "co2_prop_"
const WORK_CENTER := Vector3(0.0, 1.08, 0.83)
const LABELS := {
	"lmp": "LMP square Odyssey cartridge", "cdr": "CDR square Odyssey cartridge",
	"bench_lmp": "LMP work position", "bench_cdr": "CDR work position",
	"pack": "liquid-cooling garment pack", "scissors": "crew scissors", "bag": "inner LCG bag",
	"stowage": "stowage pouch", "card": "stiff EVA cue card", "tape": "gray tape roll",
	"towel": "towel scrap", "red_lmp": "LMP red return hose", "red_cdr": "CDR red return hose",
	"blue_lmp": "LMP blue outlet", "blue_cdr": "CDR blue outlet", "spent": "spent LM secondary cartridge",
	"mount_eps": "EPS panel mount", "mount_tunnel": "docking tunnel mount",
	"route_window": "LMP window outlet position", "route_tunnel": "Odyssey tunnel outlet position",
}
const PALETTE := {
	"metal": Color(0.64, 0.66, 0.65), "screen": Color(0.10, 0.13, 0.14),
	"tape": Color(0.37, 0.40, 0.41), "card": Color(0.87, 0.78, 0.55),
	"cloth": Color(0.76, 0.73, 0.61), "bag": Color(0.74, 0.87, 0.87, 0.27),
	"dark": Color(0.15, 0.19, 0.21), "tray": Color(0.22, 0.27, 0.28),
	"red": Color(0.58, 0.15, 0.08), "blue": Color(0.11, 0.29, 0.58),
	"mark": Color(0.64, 0.53, 0.29),
}

var scenario: Node
var objects: Dictionary = {}
var targets: Dictionary = {}
var materials: Dictionary = {}
var details: Dictionary = {}
var positions: Dictionary = {}
var routes: Dictionary = {}

func setup(owner: Node) -> void:
	scenario = owner
	for key: String in PALETTE:
		var material := StandardMaterial3D.new()
		material.albedo_color = PALETTE[key]
		material.roughness = 0.67
		if material.albedo_color.a < 1.0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		materials[key] = material
	_box(self, WORK_CENTER, Vector3(0.88, 0.027, 0.47), "tray")
	_box(self, WORK_CENTER + Vector3(0, 0.023, 0.227), Vector3(0.88, 0.032, 0.015), "dark")
	_box(self, WORK_CENTER + Vector3(-0.432, 0.023, 0), Vector3(0.015, 0.032, 0.47), "dark")
	_box(self, WORK_CENTER + Vector3(0.432, 0.023, 0), Vector3(0.015, 0.032, 0.47), "dark")
	var task_fill := OmniLight3D.new()
	task_fill.position = WORK_CENTER + Vector3(0, 0.37, -0.17)
	task_fill.light_color = Color(0.88, 0.88, 0.78)
	task_fill.light_energy = 0.36
	task_fill.omni_range = 0.85
	add_child(task_fill)
	# Local coordinates for tools and unfinished cartridges.
	for id: String in LABELS:
		var node := Node3D.new()
		node.name = PREFIX + id
		add_child(node)
		objects[id] = node
		var hit := Area3D.new()
		hit.collision_layer = 0
		hit.collision_mask = 0
		hit.monitoring = false
		hit.monitorable = false
		hit.set_meta("control_id", PREFIX + id)
		var shape := SphereShape3D.new()
		shape.radius = 0.055 if id in ["lmp", "cdr", "spent", "pack", "stowage"] else 0.039
		var collider := CollisionShape3D.new()
		collider.shape = shape
		hit.add_child(collider)
		node.add_child(hit)
		targets[id] = hit
	positions = {
		"lmp": WORK_CENTER + Vector3(0.31, 0.072, 0.15), "cdr": WORK_CENTER + Vector3(-0.31, 0.072, 0.15),
		"bench_lmp": WORK_CENTER + Vector3(0.125, 0.072, 0.02), "bench_cdr": WORK_CENTER + Vector3(-0.125, 0.072, 0.02),
		"scissors": WORK_CENTER + Vector3(0.31, 0.036, -0.16), "tape": WORK_CENTER + Vector3(0.176, 0.047, -0.16),
		"card": WORK_CENTER + Vector3(0.035, 0.034, -0.16), "towel": WORK_CENTER + Vector3(-0.104, 0.036, -0.16),
		"bag": WORK_CENTER + Vector3(-0.25, 0.037, -0.16), "pack": WORK_CENTER + Vector3(-0.33, 0.046, -0.02),
		"stowage": WORK_CENTER + Vector3(-0.328, 0.07, 0.19),
		"red_lmp": WORK_CENTER + Vector3(0.35, 0.039, -0.015), "red_cdr": WORK_CENTER + Vector3(-0.04, 0.039, 0.18),
		"blue_lmp": WORK_CENTER + Vector3(0.31, 0.039, 0.064), "blue_cdr": WORK_CENTER + Vector3(-0.16, 0.039, 0.17),
		"mount_eps": Vector3(0.82, 1.26, 0.54), "mount_tunnel": Vector3(-0.24, 1.83, 0.40),
		"route_window": Vector3(0.82, 1.62, -0.61), "route_tunnel": Vector3(-0.39, 1.90, 0.46),
		"spent": scenario.cabin.bindings["ecs_secondary_co2_cover"].target_global_position() +
			scenario.cabin.bindings["ecs_secondary_co2_cover"].target_surface_normal() * 0.11,
	}
	for side: String in ["lmp", "cdr"]:
		_build_canister(side)
		for color: String in ["red", "blue"]:
			var hose: Node3D = objects[color + "_" + side]
			_tube(hose, Vector3(-0.035, 0, 0), Vector3(0.035, 0, 0), 0.014, "dark")
			_tube(hose, Vector3(-0.050, 0, 0), Vector3(-0.020, 0, 0), 0.019, color)
			_feature(side + "_outlet_tape" if color == "blue" else side + "_split", hose,
				Vector3(-0.05, 0.006, 0), Vector3(0.010, 0.022, 0.035), "tape" if color == "blue" else "cloth")
			if color == "red":
				_feature(side + "_hose_seal", hose, Vector3(-0.026, 0.0, 0), Vector3(0.015, 0.039, 0.036), "tape")
	var roll := TorusMesh.new()
	roll.inner_radius = 0.021
	roll.outer_radius = 0.041
	roll.rings = 24
	roll.ring_segments = 12
	_mesh(objects.tape, roll, Vector3.ZERO, "tape").scale.y = 0.63
	for sign_value: int in [-1, 1]:
		_mesh(objects.scissors, roll, Vector3(sign_value * 0.017, 0, 0.013), "dark").scale = Vector3(0.39, 0.14, 0.39)
		_tube(objects.scissors, Vector3(sign_value * 0.006, 0, 0.012), Vector3(sign_value * -0.017, 0, -0.037), 0.004, "metal")
	_box(objects.card, Vector3.ZERO, Vector3(0.094, 0.004, 0.067), "card")
	for row in range(4):
		_box(objects.card, Vector3(0, 0.0025, -0.020 + row * 0.011), Vector3(0.066 - row * 0.006, 0.001, 0.002), "dark")
	_box(objects.towel, Vector3.ZERO, Vector3(0.062, 0.013, 0.052), "cloth").rotation.y = 0.24
	_box(objects.pack, Vector3.ZERO, Vector3(0.132, 0.047, 0.105), "cloth")
	_box(objects.pack, Vector3(0, 0.024, 0), Vector3(0.139, 0.009, 0.110), "bag")
	_box(objects.bag, Vector3.ZERO, Vector3(0.108, 0.009, 0.087), "bag")
	_box(objects.stowage, Vector3(0, -0.024, 0), Vector3(0.138, 0.070, 0.088), "cloth")
	_tube(objects.spent, Vector3(0, -0.04, 0), Vector3(0, 0.034, 0), 0.049, "metal")
	for id: String in ["bench_lmp", "bench_cdr", "mount_eps", "mount_tunnel", "route_window", "route_tunnel"]:
		_box(objects[id], Vector3(0, -0.040, 0), Vector3(0.083, 0.012, 0.063), "mark")
	var ecs: Vector3 = scenario.cabin.bindings["ecs_suit_gas_diverter"].target_global_position()
	_route("mount_lmp", [positions.mount_eps + Vector3(0.099, 0.091, -0.05), Vector3(0.96, 1.53, 0.53),
		Vector3(0.56, 1.87, 0.84), Vector3(0.23, 1.72, 1.0), ecs + Vector3(0, 0.09, 0.10)])
	_route("mount_cdr", [positions.mount_tunnel + Vector3(0.099, 0.091, -0.05), Vector3(-0.08, 1.89, 0.72),
		Vector3(0.20, 1.78, 0.99), ecs + Vector3(0.04, 0.11, 0.10)])
	_route("route_lmp", [positions.route_window + Vector3(0.033, 0, 0), Vector3(0.97, 1.62, -0.50),
		Vector3(0.99, 1.73, 0.33), Vector3(0.75, 1.91, 0.88), ecs + Vector3(0.08, 0.15, 0.10)])
	_route("route_cdr", [positions.route_tunnel + Vector3(0.033, 0, 0), Vector3(-0.36, 1.98, 0.60),
		Vector3(-0.12, 1.93, 0.87), ecs + Vector3(0.12, 0.10, 0.10)])
	refresh()

func _route(id: String, points: Array) -> void:
	var node := Node3D.new()
	add_child(node)
	routes[id] = node
	var curve := Curve3D.new()
	curve.bake_interval = 0.045
	for index in range(points.size()):
		var previous: Vector3 = points[maxi(index - 1, 0)]
		var next: Vector3 = points[mini(index + 1, points.size() - 1)]
		var tangent := (next - previous) * 0.14
		curve.add_point(points[index], -tangent, tangent)
	var path := curve.get_baked_points()
	for index in range(1, path.size()):
		_tube(node, path[index - 1], path[index], 0.013, "dark")

func _build_canister(side: String) -> void:
	var node: Node3D = objects[side]
	_box(node, Vector3.ZERO, Vector3(0.151, 0.114, 0.145), "metal")
	for end: int in [-1, 1]:
		_box(node, Vector3(0, 0.058 * end, 0), Vector3(0.13, 0.006, 0.121), "screen")
		for row in range(6):
			_box(node, Vector3(-0.055 + row * 0.022, end * 0.062, 0), Vector3(0.003, 0.004, 0.124), "metal")
	_box(node, Vector3(0, 0.065, 0), Vector3(0.019, 0.008, 0.13), "cloth")
	for y: float in [-0.042, 0.035]:
		_feature(side + "_belts", node, Vector3(0, y, 0), Vector3(0.155, 0.018, 0.148), "tape")
	for z: float in [-0.047, 0.044]:
		_feature(side + "_anchors", node, Vector3(0, 0.066, z), Vector3(0.157, 0.006, 0.010), "tape")
	for segment in range(9):
		var angle := PI * (segment + 0.5) / 9.0
		var point := Vector3(cos(angle) * 0.061, 0.063 + sin(angle) * 0.043, 0)
		_feature(side + "_arch", node, point, Vector3(0.026, 0.004, 0.094), "card").rotation.z = angle - PI / 2.0
	_feature(side + "_arch_tape", node, Vector3(0, 0.110, 0), Vector3(0.047, 0.005, 0.014), "tape")
	_feature(side + "_plug", node, Vector3(0, -0.064, 0), Vector3(0.033, 0.012, 0.032), "cloth")
	_feature(side + "_plug_tape", node, Vector3(0, -0.071, 0), Vector3(0.077, 0.004, 0.017), "tape")
	_feature(side + "_bag", node, Vector3(0, 0.045, 0), Vector3(0.168, 0.140, 0.160), "bag")
	_feature(side + "_seam", node, Vector3(0, -0.018, 0), Vector3(0.173, 0.019, 0.165), "tape")
	for x: float in [-0.047, 0.047]:
		_feature(side + "_reinforce", node, Vector3(x, 0.102, 0), Vector3(0.009, 0.005, 0.161), "tape")
		_feature(side + "_reinforce", node, Vector3(0, 0.116, x), Vector3(0.149, 0.005, 0.009), "tape")
	_feature(side + "_snip", node, Vector3(0.072, 0.095, -0.047), Vector3(0.025, 0.014, 0.025), "screen")
	_feature("mount_" + side, node, Vector3(0, 0, -0.078), Vector3(0.174, 0.026, 0.009), "cloth")

func refresh() -> void:
	visible = scenario.stage >= 0
	for id: String in positions:
		objects[id].position = positions[id]
		objects[id].visible = visible
	var active_step: Dictionary = scenario.steps[scenario.stage] if visible and scenario.stage < scenario.install_count else {}
	var side := "cdr" if scenario.done("lmp_plug_tape") else "lmp"
	objects.pack.visible = visible and not scenario.done(side + "_stow") and not active_step.is_empty()
	objects.pack.scale.y = 0.70 if scenario.done(side + "_inner") else (0.88 if scenario.done(side + "_outer") else 1.0)
	objects.bag.visible = visible and scenario.done(side + "_stow") and not scenario.done(side + "_bag")
	objects.spent.visible = visible and active_step.get("id") == "remove_secondary"
	for id: String in ["bench_lmp", "bench_cdr", "mount_eps", "mount_tunnel", "route_window", "route_tunnel"]:
		objects[id].visible = visible and active_step.get("target") == PREFIX + id
	for which: String in ["lmp", "cdr"]:
		if scenario.done("stage_" + which):
			objects[which].position = positions["bench_" + which]
		if scenario.done("mount_" + which):
			objects[which].position = positions["mount_eps" if which == "lmp" else "mount_tunnel"]
		if scenario.done(which + "_hose"):
			objects["red_" + which].position = objects[which].position + Vector3(0.076, 0.091, -0.05)
		if scenario.done("route_" + which):
			objects["blue_" + which].position = positions["route_window" if which == "lmp" else "route_tunnel"]
	for id: String in details:
		for node: Node3D in details[id]:
			node.visible = scenario.done(id) if not id.ends_with("_split") else not scenario.done(id)
	for id: String in routes:
		routes[id].visible = scenario.done(id)
	if not scenario.selected.is_empty():
		objects[scenario.selected.trim_prefix(PREFIX)].position.y += 0.017
	for id: String in objects:
		var eligible: bool = visible and objects[id].visible and (active_step.get("item") == PREFIX + id or active_step.get("target") == PREFIX + id)
		targets[id].collision_layer = 32 if eligible else 0

func label_for(id: String) -> String:
	return LABELS.get(id.trim_prefix(PREFIX), "")

func point(id: String) -> Vector3:
	return objects[id.trim_prefix(PREFIX)].global_position

func locate(id: String) -> bool:
	var key := id.trim_prefix(PREFIX)
	var spot := point(id)
	var cabin: Node3D = scenario.cabin
	var work_view := WORK_CENTER + Vector3(0, 0.60, -0.31)
	var notes: Array[Vector3] = [work_view, spot + Vector3(0, 0.26, -0.39), spot + Vector3(0, -0.19, -0.32), Vector3(0, 1.46, 0.65)]
	if key == "spent":
		var cover = cabin.bindings["ecs_secondary_co2_cover"]
		notes.push_front(spot + cover.target_surface_normal() * 0.24)
	for candidate: Vector3 in notes:
		var eye: Vector3 = cabin._clamp_desktop_position(candidate)
		if cabin._pick(eye, eye.direction_to(spot)) == id:
			cabin._aim_desktop(eye, spot)
			return true
	return false

func _feature(id: String, parent: Node3D, position_on_mesh: Vector3, size_on_mesh: Vector3, material: String) -> MeshInstance3D:
	var node := _box(parent, position_on_mesh, size_on_mesh, material)
	if not details.has(id):
		details[id] = []
	details[id].append(node)
	return node

func _box(parent: Node3D, location: Vector3, dimensions: Vector3, material: String) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = dimensions
	return _mesh(parent, shape, location, material)

func _tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: String) -> void:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = a.distance_to(b)
	shape.radial_segments = 12
	var pipe := _mesh(parent, shape, (a + b) * 0.5, material)
	pipe.quaternion = Quaternion(Vector3.UP, a.direction_to(b))

func _mesh(parent: Node3D, shape: Mesh, location: Vector3, material: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = materials[material]
	node.position = location
	parent.add_child(node)
	return node
