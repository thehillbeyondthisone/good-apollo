extends SceneTree
## Rendered desktop timing only. This never claims headset or VR performance.

var frame_times: Array[float] = []
var frames := 0
var sample_frames := 360
var previous_usec := 0
var startup_usec := 0
var scene: Node

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Rendered benchmark needs a real rendering display.")
		quit(1)
		return
	call_deferred("_start")

func _start() -> void:
	startup_usec = Time.get_ticks_usec()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1440, 900)
	previous_usec = Time.get_ticks_usec()
	process_frame.connect(_sample)

func _sample() -> void:
	var now := Time.get_ticks_usec()
	var milliseconds := float(now - previous_usec) / 1000.0
	previous_usec = now
	frames += 1
	if frames <= 90:
		return
	frame_times.append(milliseconds)
	if frame_times.size() < sample_frames:
		return
	process_frame.disconnect(_sample)
	frame_times.sort()
	var mean := 0.0
	for value in frame_times:
		mean += value
	mean /= frame_times.size()
	var report := {
		"schemaVersion": 1,
		"kind": "Uncapped rendered desktop benchmark; headset not tested",
		"vsyncMode": DisplayServer.window_get_vsync_mode(),
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"displayServer": DisplayServer.get_name(),
		"viewport": [root.size.x, root.size.y],
		"warmupFrames": 90,
		"sampleFrames": frame_times.size(),
		"meanFrameMs": mean,
		"p50FrameMs": frame_times[int(frame_times.size() * 0.50)],
		"p95FrameMs": frame_times[int(frame_times.size() * 0.95)],
		"p99FrameMs": frame_times[int(frame_times.size() * 0.99)],
		"meanFpsEquivalent": 1000.0 / mean,
		"drawCalls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"hardwareBatches": scene.cabin_batches != null and scene.cabin_batches.enabled,
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"headsetTested": false,
		"wallSeconds": float(now - startup_usec) / 1000000.0,
	}
	var target: String = scene.argument_value("--report-path", scene.repository_path("reference/desktop-performance.json"))
	var output := FileAccess.open(target, FileAccess.WRITE)
	if output == null:
		push_error("Could not write desktop timing report")
		quit(1)
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print(JSON.stringify(report))
	quit(0)
