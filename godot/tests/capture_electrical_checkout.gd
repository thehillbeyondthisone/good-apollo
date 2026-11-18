extends SceneTree
## Desktop-only visual proof of sourced load mode and the physical lamp selector.

var cabin: Node

func _initialize() -> void:
	call_deferred("_run")

func operate_to(id: String, label: String) -> void:
	var target: int = cabin.state_store.definitions[id].positions.find(label)
	for attempt in range(9):
		var current: int = cabin.state_store.states[id]
		if current == target: return
		cabin._operate(id,1 if target > current else -1,"desktop-capture",true)

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = cabin.repository_path("output/"+name+".png")
	print("Electrical capture: %s (%s)" % [path,error_string(root.get_texture().get_image().save_png(path))])

func _run() -> void:
	cabin = load("res://main.tscn").instantiate()
	root.add_child(cabin)
	await process_frame
	if not cabin.load_errors.is_empty() or cabin.systems == null:
		quit(1)
		return
	var key := InputEventKey.new()
	key.keycode = KEY_F11
	key.pressed = true
	cabin._unhandled_input(key)
	operate_to("p3_lamp_tone_test","C/W 1")
	await capture("aquarius-electrical-checkout")
	operate_to("p3_lamp_tone_test","C/W 3")
	await capture("aquarius-caution-lamp-test")
	operate_to("p3_lamp_tone_test","COMPN T")
	cabin._set_inspection_view(3)
	await capture("aquarius-component-lamp-test")
	cabin.queue_free()
	await process_frame
	quit(0)
