extends RefCounted
## A six-page orientation. Reading ahead never changes spacecraft controls.

var active := true
var stage := 0
var observed: Dictionary = {}
const TOTAL := 6

func observe(event: String) -> void:
	if active: observed[event] = true

func restart() -> void:
	active = true
	stage = 0
	observed.clear()

func action(_cabin: Node3D) -> void:
	if not active: return
	stage += 1
	if stage >= TOTAL: active = false

func page(cabin: Node3D) -> Dictionary:
	if not active: return {}
	var xr: bool = cabin.xr_active
	var pages := [
		{
			"title": "Welcome aboard Aquarius",
			"context": "A short orientation before cabin checkout. Take your time; the notebook keeps your place.",
			"location": "CREW FLIGHT NOTEBOOK",
			"action": "Aim at NEXT PAGE and squeeze, then release the trigger." if xr else "Click NEXT PAGE to continue.",
			"gesture": "Only enabled buttons can advance. A status strip tells you when a physical action is still needed.",
			"verify": "The book explains one action at a time. You can read ahead without operating a control.",
		},
		{
			"title": "Handle a weightless notebook",
			"context": "The book stays where you leave it. Turning your head or changing a step does not reposition it.",
			"location": "NOTEBOOK COVER / EDGE",
			"action": "Hold grip near any part of the book, or aim at it and squeeze grip within 1.2 m. Move your hand; release to let it drift." if xr else "In VR, grip near the book or aim and grip within 1.2 m. Release to preserve your hand's gentle motion.",
			"gesture": "Release slowly to leave it almost still. X recalls the book if it drifts out of reach.",
			"verify": "Grab and release observed." if observed.get("grab", false) and observed.get("release", false) else "Try a gentle grab and release, then continue when comfortable.",
		},
		{
			"title": "Read a control before touching",
			"context": "Labels appear beside the control you are hovering over, rather than above your hands.",
			"location": "PANEL 3 / EXTERIOR LIGHTS",
			"target": "p3_exterior_ltg",
			"action": "Aim a controller at the highlighted switch, or bring its fingertip close without pressing." if xr else "Hover the pointer over the highlighted switch.",
			"gesture": "The tooltip shows the control name and current position. Knobs and axes also show their value.",
			"verify": "Control hover observed." if observed.get("hover", false) else "Find the hover label and read the current setting.",
		},
		{
			"title": "Operate and verify",
			"context": "Amber light and small particles mark the next control. The notebook waits for its actual state.",
			"location": "PANEL 3 / EXTERIOR LIGHTS",
			"target": "p3_exterior_ltg",
			"action": "Press trigger once to change the highlighted switch. Grip + trigger reverses it. Restore OFF after trying it." if xr else "Click the highlighted switch; Shift + click reverses it. Restore OFF after trying it.",
			"gesture": "Open guards first. Grip + trigger unlocks levers. Hold trigger + thumbstick for knobs. A fingertip presses buttons and pushes breakers in.",
			"verify": "Control operation observed." if observed.get("operate", false) else "Watch the hover status change. Mission actions complete only when their requested setting is reached.",
		},
		{
			"title": "Find your next task",
			"context": "Each procedure has FIND, DO and CHECK instructions. Control actions advance automatically; read-up callouts need confirmation.",
			"location": "NOTEBOOK / GUIDANCE",
			"target": "p3_exterior_ltg",
			"action": "Press A to reveal the current target. Follow its amber glow and particles. X recalls the notebook." if xr else "Press F to locate the current mission target. N opens or stows the notebook.",
			"gesture": "A status strip is information, not a button. CONFIRM appears only when the required positions have been verified.",
			"verify": "Target locator observed." if observed.get("locate", false) else "Locate a highlighted target, then continue to the final page.",
		},
		{
			"title": "Move, pause and begin",
			"context": "Move slowly and use the cabin structure as your reference. There is no need to chase a drifting notebook.",
			"location": "CABIN / FLIGHT MENU",
			"action": "Left stick moves; right stick turns and adjusts height. Menu recenters. B/Y opens the flight menu." if xr else "Hold right mouse to look. WASD moves; Q/E changes height. Esc opens the flight menu.",
			"gesture": "B/Y → Floating info hides the status window while keeping the book." if xr else "Save and restore live in the flight menu. A fresh cabin starts with the water dispenser.",
			"verify": "Ready: hover to read, trigger to act, grip to grab, X for the book, A for the target." if xr else "Ready: hover to read, click to act, N for the book, F for the target.",
		},
	]
	var result: Dictionary = pages[clampi(stage, 0, TOTAL - 1)].duplicate(true)
	result["chapter"] = "WELCOME ABOARD"
	result["count"] = "%02d / %02d" % [stage + 1, TOTAL]
	result["confirm"] = true
	result["button_label"] = "BEGIN PROCEDURE" if stage == TOTAL - 1 else "NEXT PAGE"
	result["action_id"] = "onboarding_next"
	return result
