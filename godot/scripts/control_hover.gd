extends Node3D
## A contextual placard at the hovered control, never attached to the hand.

const Hud = preload("res://scripts/flight_hud.gd")
var cabin: Node3D
var label: Label3D
var backing: MeshInstance3D
var target_id := ""

func setup(owner: Node3D) -> void:
	cabin = owner
	name = "ControlHoverStatus"
	backing = MeshInstance3D.new()
	var plate := QuadMesh.new()
	plate.size = Vector2(0.235, 0.072)
	backing.mesh = plate
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.025, 0.047, 0.050, 0.94)
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backing.material_override = paint
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backing)
	label = Label3D.new()
	label.name = "HoveredControlStatus"
	label.font = Hud.typeface(true)
	label.font_size = 44
	label.pixel_size = 0.00035
	label.width = 625
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.outline_size = 2
	label.outline_modulate = Color("#07111c")
	label.modulate = Color("#f0dfbb")
	label.position.z = 0.0006
	label.no_depth_test = false
	add_child(label)
	hide()

func value_text(id: String) -> String:
	var value: String = cabin.state_store.position_name(id)
	if cabin.state_store.is_analog(id):
		var definition: Dictionary = cabin.state_store.definitions[id]
		var axis: Dictionary = definition.get("analog", definition.get("axis", {}))
		var fraction: float = (cabin.state_store.axis_value(id) + 1.0) * 0.5
		var number := lerpf(float(axis.get("min", -1)), float(axis.get("max", 1)), fraction)
		value = "%s / %.2f %s" % [value, number, str(axis.get("unit", "")).replace("_", " ")]
	var indication := ""
	if cabin.systems != null: indication = str(cabin.systems.control_value(id))
	if cabin.mechanisms != null and not cabin.mechanisms.control_value(id).is_empty():
		indication = cabin.mechanisms.control_value(id)
	if not indication.is_empty() and indication != value:
		value += "\n" + indication
	return value

func present(id: String, tracked: bool) -> void:
	target_id = id if tracked else ""
	if not tracked or id.is_empty() or not cabin.bindings.has(id):
		hide()
		return
	var binding = cabin.bindings[id]
	var definition: Dictionary = cabin.state_store.definitions[id]
	var camera: Camera3D = cabin.active_camera
	if camera == null:
		hide()
		return
	var suffix := " / READ ONLY" if not cabin.state_store.is_interactive(id) else ""
	label.text = "%s\n%s%s" % [definition.get("label", id), value_text(id), suffix]
	var line_count := 0
	for line: String in label.text.split("\n"):
		line_count += maxi(1, ceili(float(line.length()) / 23.0))
	var height := clampf(float(line_count) * 0.018 + 0.016, 0.052, 0.18)
	(backing.mesh as QuadMesh).size.y = height
	var display_scale := clampf(camera.global_position.distance_to(binding.target_global_position()) * 0.8, 0.45, 1.25)
	# Keep the label close to its real target and above the operating hand.
	global_position = binding.target_global_position() + binding.target_surface_normal() * 0.045 + camera.global_basis.y * (height * display_scale * 0.5 + 0.025)
	global_basis = camera.global_basis.orthonormalized()
	scale = Vector3.ONE * display_scale
	show()
