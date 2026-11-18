extends Node3D
## Depth-tested task affordance: a local halo, gentle spill and a bounded mote pool.
## The halo supplies visible softness on Mobile without requiring screen bloom.

const COLOR := Color("#ffd28b")
const MOTE_COUNT := 18
var cabin: Node3D
var target_ring: MeshInstance3D
var panel_frame: Node3D
var halo: MeshInstance3D
var spill: OmniLight3D
var motes: Array[MeshInstance3D] = []
var direction_label: Label3D
var target_id := ""
var target_position := Vector3.ZERO
var target_normal := Vector3.UP
var particle_radius := 0.025
var target_valid := false
var _showing := false
var _time := 0.0
var _reveal_seconds := 0.0
var _paint: StandardMaterial3D

func setup(owner_cabin: Node3D) -> void:
	cabin = owner_cabin
	_paint = StandardMaterial3D.new()
	_paint.albedo_color = COLOR
	_paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_paint.emission_enabled = true
	_paint.emission = COLOR
	_paint.emission_energy_multiplier = 1.4
	var ring := TorusMesh.new()
	ring.inner_radius = 0.0235
	ring.outer_radius = 0.025
	ring.rings = 32
	ring.ring_segments = 6
	target_ring = _mesh("ProcedureControlHighlight", ring, _paint)
	var glow := Shader.new()
	glow.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.34, 1.0);
void fragment() {
    float r = length((UV - vec2(0.5)) * 2.0);
    float soft = pow(max(0.0, 1.0 - r), 2.0);
    float ring = exp(-pow((r - 0.47) * 7.0, 2.0));
    ALBEDO = tint.rgb;
    EMISSION = tint.rgb * 0.3;
    ALPHA = (soft * 0.16 + ring * 0.21) * tint.a;
}
"""
	var glow_material := ShaderMaterial.new()
	glow_material.shader = glow
	var quad := QuadMesh.new()
	quad.size = Vector2(0.13, 0.13)
	halo = _mesh("ProcedureSoftHalo", quad, glow_material)
	spill = OmniLight3D.new()
	spill.name = "ProcedureSoftSpill"
	spill.light_color = COLOR
	spill.light_energy = 0.004
	spill.omni_range = 0.13
	spill.omni_attenuation = 2.5
	spill.shadow_enabled = false
	add_child(spill)
	var bead := SphereMesh.new()
	bead.radius = 0.0009
	bead.height = 0.0018
	bead.radial_segments = 6
	bead.rings = 3
	for index in MOTE_COUNT:
		motes.append(_mesh("ProcedureMote%02d" % index, bead, _paint))
	panel_frame = Node3D.new()
	panel_frame.name = "ProcedurePanelHighlight"
	add_child(panel_frame)
	for side in [-1, 1]:
		for edge in 2:
			var bar := BoxMesh.new()
			bar.size = Vector3(1.0, 0.001, 0.004) if edge == 0 else Vector3(0.004, 0.001, 1.0)
			var line := _mesh("PanelEdge", bar, _paint, panel_frame)
			line.position = Vector3(0, 0.003, side * 0.5) if edge == 0 else Vector3(side * 0.5, 0.003, 0)
	direction_label = Label3D.new()
	direction_label.name = "ProcedureDirection"
	direction_label.font_size = 30
	direction_label.pixel_size = 0.00035
	direction_label.outline_size = 7
	direction_label.modulate = COLOR
	direction_label.outline_modulate = Color("#20272a")
	direction_label.no_depth_test = false
	add_child(direction_label)
	_set_visible(false)

func _mesh(label: String, geometry: Mesh, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = geometry
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	return visual

func _set_visible(value: bool) -> void:
	target_ring.visible = value
	halo.visible = value
	spill.visible = value
	for mote: MeshInstance3D in motes: mote.visible = value
	if not value:
		panel_frame.hide()
		direction_label.hide()

func reveal_target(seconds := 8.0) -> void:
	_reveal_seconds = maxf(_reveal_seconds, seconds)

func update_target(id: String, showing: bool) -> void:
	target_id = id
	_showing = showing
	target_valid = false
	panel_frame.hide()
	if not showing or id.is_empty():
		_set_visible(false)
		return
	if cabin.bindings.has(id):
		var binding = cabin.bindings[id]
		target_normal = binding.target_surface_normal()
		var origin: Vector3 = binding.target_global_position()
		# Find the foremost rigid geometry of this control, so the halo does not
		# sit behind a handle or button. Cap the extent for large assembly proxies.
		var front := 0.0
		if binding.actuator != null:
			for mesh: Node in binding.actuator.find_children("*", "MeshInstance3D", true, false):
				var visual := mesh as MeshInstance3D
				if visual.mesh == null or str(visual.name).begins_with("WaterBead"): continue
				var bounds := visual.mesh.get_aabb()
				for corner in 8:
					front = maxf(front, (visual.to_global(bounds.get_endpoint(corner)) - origin).dot(target_normal))
		target_position = origin + target_normal * (clampf(front, 0.0, 0.08) + 0.008)
		particle_radius = clampf(binding.target_shape.radius, 0.012, 0.040)
		var artwork := _panel_artwork(binding.root, str(binding.definition.get("panel", "")))
		if artwork != null:
			panel_frame.global_transform = artwork.global_transform
			panel_frame.show()
	elif id.begins_with("co2_prop_") and cabin.systems != null and cabin.systems.co2.props != null:
		target_position = cabin.systems.co2.props.point(id)
		target_normal = cabin.active_camera.global_basis.z.normalized()
		particle_radius = 0.035
	else:
		_set_visible(false)
		return
	target_valid = true
	_set_visible(true)
	_update_visuals()

func _panel_artwork(control: Node3D, panel: String) -> Node3D:
	var ancestor: Node = control.get_parent()
	while ancestor != null and ancestor != cabin:
		var direct := ancestor.get_node_or_null("Panel_" + panel + "_artwork") as Node3D
		if direct != null: return direct
		ancestor = ancestor.get_parent()
	return null

func _process(delta: float) -> void:
	_time += delta
	_reveal_seconds = maxf(0.0, _reveal_seconds - delta)
	if target_valid and _showing:
		_update_visuals()

func _update_visuals() -> void:
	var pulse := 1.0 + sin(_time * 2.5) * 0.10
	target_ring.global_position = target_position
	target_ring.global_basis = Basis(Quaternion(Vector3.UP, target_normal))
	target_ring.scale = Vector3.ONE * particle_radius / 0.024 * pulse
	halo.global_position = target_position + target_normal * 0.003
	var camera: Camera3D = cabin.active_camera
	if camera != null: halo.global_basis = camera.global_basis.orthonormalized()
	halo.scale = Vector3.ONE * maxf(0.65, particle_radius / 0.024) * pulse
	spill.global_position = target_position + target_normal * 0.035
	spill.light_energy = 0.004 * pulse
	var up := Vector3.FORWARD if absf(target_normal.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var tangent := target_normal.cross(up).normalized()
	var bitangent := target_normal.cross(tangent).normalized()
	for index in MOTE_COUNT:
		# Each mote starts at the control rim, drifts out and fades by shrinking.
		# No randomness allocation or new nodes occur while rendering a frame.
		var age := fmod(_time * 0.48 + float(index) / MOTE_COUNT, 1.0)
		var angle := index * 2.399963 + age * 0.4
		var radial := tangent * cos(angle) + bitangent * sin(angle)
		motes[index].global_position = target_position + radial * (particle_radius * 0.8 + age * 0.012) + target_normal * (age * 0.065)
		motes[index].scale = Vector3.ONE * sin(age * PI) * 1.7
	direction_label.hide()
	if camera == null or _reveal_seconds <= 0.0: return
	var local := camera.to_local(target_position)
	var on_screen := camera.is_position_in_frustum(target_position)
	if on_screen: return
	var toward := "TURN RIGHT  →" if local.x >= 0 else "←  TURN LEFT"
	if local.z >= 0: toward = "LOOK BEHIND  /  " + toward
	direction_label.text = toward
	direction_label.global_transform = Transform3D(camera.global_basis, camera.global_transform * Vector3(0, -0.14, -0.65))
	direction_label.show()
