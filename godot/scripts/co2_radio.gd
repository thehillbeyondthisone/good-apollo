extends AudioStreamPlayer
## One local CAPCOM transmission at a time. The captions are driven by the checklist.

var cue_get := ""
var muted := false
var clips: Dictionary = {}
var directory := ""
var mix_gains: Dictionary = {}

func setup(asset_directory: String) -> void:
	directory = asset_directory
	load("res://scripts/cabin_soundscape.gd").install_mix()
	bus = "AQ Radio"
	muted = AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))
	volume_db = 0.0
	var mix_path: String = load("res://scripts/cabin_soundscape.gd").asset_root().path_join("manifest.json")
	if FileAccess.file_exists(mix_path):
		var mix_data = JSON.parse_string(FileAccess.get_file_as_string(mix_path))
		if mix_data is Dictionary: mix_gains = mix_data.get("radioGainDb", {})
	var manifest_path := directory.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path):
		return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if manifest is Dictionary and manifest.get("schemaVersion") == 1 and manifest.get("clips") is Dictionary:
		clips = manifest.clips

func present(source_get: String, autoplay := true) -> void:
	if source_get == cue_get or not clips.has(source_get):
		return
	var file := str(clips[source_get].get("file", ""))
	if file.is_empty() or file.get_file() != file:
		return
	var next := AudioStreamWAV.load_from_file(directory.path_join(file))
	if next == null:
		return
	stop()
	stream = next
	volume_db = float(mix_gains.get(directory.get_file() + "/" + file, -5.0))
	cue_get = source_get
	muted = AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))
	if autoplay and not muted:
		play()

func repeat() -> bool:
	muted = AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))
	if stream == null or muted:
		return false
	stop()
	play()
	return true

func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), muted)
	if muted:
		stop()

func clear() -> void:
	stop()
	stream = null
	cue_get = ""
