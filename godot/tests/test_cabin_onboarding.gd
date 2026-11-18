extends SceneTree
## Orientation pages are read-ahead guidance; they never operate the spacecraft.

const Onboarding = preload("res://scripts/cabin_onboarding.gd")
class Cabin:
	extends Node3D
	var xr_active := true

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var cabin := Cabin.new()
	root.add_child(cabin)
	var onboarding = Onboarding.new()
	for stage in Onboarding.TOTAL:
		var page: Dictionary = onboarding.page(cabin)
		check(onboarding.active and onboarding.stage == stage, "Each orientation page retains its place.")
		check(page.confirm and not page.button_label.is_empty(), "Read-ahead has an enabled, named action.")
		check(not page.action.is_empty() and not page.verify.is_empty() and not page.location.is_empty(), "Every page has FIND, DO and CHECK guidance.")
		check(page.count == "%02d / 06" % [stage + 1], "The orientation shows a bounded six-page count.")
		if stage == 1:
			onboarding.observe("grab")
			onboarding.observe("release")
			check(onboarding.page(cabin).verify.contains("observed"), "Grab and release feedback acknowledges both events.")
		elif stage == 2:
			onboarding.observe("hover")
			check(onboarding.page(cabin).verify.contains("observed"), "Hover practice can be acknowledged.")
		elif stage == 3:
			onboarding.observe("operate")
			check(onboarding.page(cabin).verify.contains("observed"), "Switch practice can be acknowledged.")
		elif stage == 4:
			onboarding.observe("locate")
			check(onboarding.page(cabin).verify.contains("observed"), "Target-location practice can be acknowledged.")
		onboarding.action(cabin)
	check(not onboarding.active and onboarding.page(cabin).is_empty(), "Finishing orientation yields to the real procedure.")
	onboarding.action(cabin)
	check(onboarding.stage == Onboarding.TOTAL, "Repeated completion cannot advance beyond the tutorial.")
	onboarding.restart()
	check(onboarding.active and onboarding.stage == 0 and onboarding.observed.is_empty(), "Replay starts a clean tutorial without touching cabin state.")
	cabin.xr_active = false
	check(onboarding.page(cabin).action.contains("Click"), "Desktop orientation names the available input.")
	for index in 5: onboarding.action(cabin)
	check(onboarding.page(cabin).action.contains("WASD"), "Desktop orientation includes navigation.")
	var path := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("output/cabin-onboarding-tests.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"checks": checks, "failures": failures, "headsetTested": false}, "\t"))
	print("Cabin onboarding: %d checks, %d failures." % [checks, failures])
	cabin.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
