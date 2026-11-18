extends RefCounted
## One actionable instruction at a time, derived from the real procedure state.

const Correction = preload("res://scripts/manual_correction.gd")
const OdysseyData = preload("res://scripts/odyssey_checklist.gd")
var water_observed := false
var water_acknowledged := false

func action(cabin: Node3D) -> bool:
	# Handle book-only checkout actions without using the mission confirmation
	# path, which would otherwise silently start a power-down checklist.
	var instruction := page(cabin)
	if not instruction.get("confirm", false): return false
	match str(instruction.get("action_id", "")):
		"water_done":
			water_acknowledged = true
			return true
		"start_powerdown":
			return cabin.systems.start_powerdown()
	return false

func control_page(cabin: Node3D, chapter: String, heading: String, id: String, desired: String, context: String, count: String) -> Dictionary:
	var definition: Dictionary = cabin.state_store.definitions.get(id, {})
	var panel := str(definition.get("panel", "CABIN")).replace("_", " ")
	var location := "PANEL " + panel
	if "_cb_r" in id:
		location += " / ROW %d / BREAKER %d" % [int(id.get_slice("_", 2).substr(1)), int(id.get_slice("_", 3).substr(1))]
	var name := str(definition.get("label", id.replace("_", " ")))
	var action := "Set %s to %s." % [name, desired]
	var gesture := "Aim and press the trigger to advance. Grip + trigger reverses."
	if not cabin.xr_active: gesture = "Click to advance. Shift + click reverses."
	match str(definition.get("type", "")):
		"breaker":
			action = ("Pull out " if desired in ["PULLED", "OPEN"] else "Push in ") + name + "."
			gesture = "Grip + trigger pulls; trigger or a fingertip press pushes." if cabin.xr_active else "Shift + click pulls; click pushes."
		"pushbutton":
			action = ("Release " if desired == "RELEASED" else "Press and hold ") + name + "."
			gesture = "Hold the trigger while aiming at the button; release to stop." if cabin.xr_active else "Hold the left mouse button; release to stop."
		"lever-lock":
			gesture = "Hold grip + trigger to unlock, then move to the called position." if cabin.xr_active else "Ctrl + click unlocks the lever. Shift + click reverses."
		"axis", "rotary", "valve", "thumbwheel":
			gesture = "Hold trigger and move the thumbstick. Grip + trigger reverses a detent." if cabin.xr_active else "Click or Shift + click selects a detent; use the wheel for fine adjustment."
	var guard := str(definition.get("mechanism", {}).get("guardId", ""))
	if not guard.is_empty() and cabin.state_store.position_name(guard) != "OPEN":
		return control_page(cabin, chapter, "Open the safety guard", guard, "OPEN", context, count)
	return {"chapter": chapter, "title": heading, "count": count, "target": id,
		"context": context, "location": location, "action": action, "gesture": gesture,
		"verify": "Verify %s reads %s. Current: %s." % [name, desired, cabin.state_store.position_name(id)], "confirm": false,
		"button_label": "AWAITING CONTROL"}

func page(cabin: Node3D) -> Dictionary:
	var systems: Node = cabin.systems
	if systems == null: return {}
	if systems.odyssey.active(): return _odyssey(cabin)
	if systems.correction.active(): return _correction(cabin)
	if systems.co2.stage >= 0: return _co2(cabin)
	var snapshot: Dictionary = systems.powerdown_snapshot
	if snapshot.get("active", false):
		var event = snapshot.get("nextEvent")
		if not event is Dictionary:
			return {"chapter": "ELECTRICAL POWER-DOWN", "title": "Configuration complete", "count": "COMPLETE", "context": "All power-down callouts are verified.", "action": "Review the completed configuration.", "verify": "Use Mission chapters for the next available procedure.", "confirm": false}
		var count := "%02d / %02d" % [int(snapshot.currentIndex) + 1, int(snapshot.eventCount)]
		var context: String = systems.POWERDOWN_CALLOUTS.get(event.id, event.title)
		var pending: Array = snapshot.get("pendingActions", [])
		if not pending.is_empty():
			var action: Dictionary = pending[0]
			var result := control_page(cabin, "ELECTRICAL POWER-DOWN", event.title, str(action.controlId), str(action.position), context, count)
			result["verify"] += "\n%d control position(s) remain in this callout." % pending.size()
			return result
		return {"chapter": "ELECTRICAL POWER-DOWN", "title": event.title, "count": count, "context": context,
			"action": "Read the callout and check the configuration.", "verify": "All requested positions are set. Confirm to continue.", "confirm": true}
	return _water(cabin)

func _water(cabin: Node3D) -> Dictionary:
	if water_acknowledged:
		return {"chapter": "CABIN CHECKOUT / WATER", "title": "Checkout acknowledged", "count": "COMPLETE",
			"context": "You have dispensed water and checked shutoff. Replace the nozzle cap when finished.",
			"location": "FLIGHT NOTEBOOK", "action": "Start the electrical power-down procedure, or choose a chapter from the flight menu.",
			"verify": "The next procedure guides each switch and breaker position.", "confirm": true,
			"button_label": "START POWER-DOWN", "action_id": "start_powerdown"}
	var water: Dictionary = cabin.mechanisms.derived.get("water_dispenser_trigger", {}) if cabin.mechanisms != null else {}
	if water.get("flowPathAvailable", false): water_observed = true
	var id := "water_dispenser_pose"
	var desired := "FREE"
	var heading := "Unstow the dispenser"
	var count := "01 / 05"
	if cabin.state_store.position_name(id) == desired:
		id = "ecs_des_h2o"
		desired = "OPEN"
		heading = "Open a water feed"
		count = "02 / 05"
		if water.get("supplyPathOpen", false):
			id = "water_dispenser_cap"
			desired = "REMOVED"
			heading = "Remove the nozzle cap"
			count = "03 / 05"
			if water.get("capRemoved", false):
				id = "water_dispenser_trigger"
				desired = "HELD"
				heading = "Dispense water"
				count = "04 / 05"
				if water_observed:
					desired = "RELEASED"
					heading = "Release and check shutoff"
					count = "05 / 05"
	var result := control_page(cabin, "CABIN CHECKOUT / WATER", heading, id, desired,
		"Practice using the cabin water dispenser. Do the action below; the book advances as each control changes.", count)
	var select := "Aim at it and press the controller trigger once." if cabin.xr_active else "Click it once. Press F to bring the current target into view."
	match id:
		"water_dispenser_pose":
			result.location = "AFT CABIN / BELOW THE ECS WATER CONTROLS"
			result.action = "Select the ivory dispenser body to release it from its bracket. It moves out into the cabin."
			result.gesture = select + " Select the body, not the small nozzle cap or side button."
			result.verify = "BRACKETED changes to FREE. The next page appears automatically."
		"ecs_des_h2o":
			result.location = "AFT ECS PANEL / WATER / DES H₂O"
			result.action = "Turn DES H₂O to OPEN. ASC H₂O also supplies the dispenser; either feed is enough."
			result.gesture = select
			result.verify = "One water feed reads OPEN. The book then points to the nozzle cap."
		"water_dispenser_cap":
			result.location = "DISPENSER / ROUND CAP AT THE NOZZLE TIP"
			result.action = "Select the round ivory nozzle cap. It moves to the side and leaves the metal nozzle clear."
			result.gesture = select
			result.verify = "The cap reads REMOVED. Next, use the small button on the side of the dispenser."
		"water_dispenser_trigger":
			result.location = "DISPENSER / SMALL IVORY SIDE BUTTON"
			result.action = "Aim at the small side button and HOLD the controller trigger. Release after you see water beads." if cabin.xr_active else "Point at the small side button and HOLD the left mouse button. Release after you see water beads."
			result.gesture = "Keep aiming at the side button while holding. A short press is enough to verify flow."
	if id == "water_dispenser_trigger":
		result["verify"] = "Look for water beads leaving the nozzle. Release the trigger to stop." if not water_observed else "Verify the water beads stop when you release the trigger."
		if water_observed and not water.get("triggerHeld", false):
			result.title = "Water checkout complete"
			result.erase("target")
			result.location = "FLIGHT NOTEBOOK / FINISH WATER CHECK"
			result.action = "Select FINISH WATER CHECK below to acknowledge the completed checkout."
			result.gesture = "You can replace the cap and bracket the dispenser after use. START POWER-DOWN is a separate next procedure."
			result.verify = "Dispenser shutoff verified. Acknowledge this checkout, then choose your next procedure."
			result.confirm = true
			result.button_label = "FINISH WATER CHECK"
			result.action_id = "water_done"
		elif water_observed:
			result.action = "Release the controller trigger now to stop the water." if cabin.xr_active else "Release the left mouse button now to stop the water."
			result.gesture = "The book waits for the physical dispenser button to return to RELEASED."
	return result

func _co2(cabin: Node3D) -> Dictionary:
	var co2: Node = cabin.systems.co2
	if co2.stage >= co2.install_count:
		return {"chapter": "CO₂ ADAPTER", "title": "Verify cabin CO₂", "count": "MONITOR", "target": co2.GAUGE,
			"location": "PANEL 2", "context": "Both adapters are installed. Keep the suit fan and the secondary circuit operating.",
			"action": "Read the CO₂ gauge. Wait for 0.2 mmHg.", "verify": "Current: %s mmHg. Follow the final Houston call." % co2.gauge_text(), "confirm": co2.result_announced}
	var step: Dictionary = co2.steps[co2.stage]
	var count := "%02d / %02d" % [co2.stage + 1, co2.install_count]
	if step.has("position"):
		var result := control_page(cabin, "CO₂ ADAPTER", "Configure the air path", step.target, step.position, step.message, count)
		result.confirm = cabin.state_store.position_name(step.target) == step.position
		return result
	var picking: bool = co2.selected.is_empty()
	var id: String = co2.target()
	return {"chapter": "CO₂ ADAPTER", "title": "Select the part" if picking else "Apply the part", "count": count, "context": step.message,
		"target": id, "location": "CABIN WORK AREA", "action": "Click the highlighted %s." % id.trim_prefix("co2_prop_").replace("_", " "),
		"gesture": "Select the part first, then click the highlighted destination.", "verify": "The next instruction appears after this assembly action is complete.", "confirm": false}

func _correction(cabin: Node3D) -> Dictionary:
	var correction: Node = cabin.systems.correction
	var id: String = correction.target()
	var count := "%02d / 10" % mini(int(correction.phase), 10)
	if not id.is_empty():
		var settings: Dictionary = Correction.PREP if correction.phase == Correction.Phase.PREP else (Correction.ARM if correction.phase in [Correction.Phase.ARM, Correction.Phase.ULLAGE] else {"aot_azimuth": "F", "aot_reticle": "MIN"})
		return control_page(cabin, "MCC-5 / COURSE CORRECTION", "Configure the next control", id, str(settings.get(id, "RELEASED")), "Work each highlighted control, then verify the configuration.", count)
	var instructions := {
		Correction.Phase.PREP: ["Acquire the Earth", "Verify the attitude-control settings. Select Continue for the Earth sight.", "Use the COAS to establish yaw and roll."],
		Correction.Phase.EARTH: ["Align the Earth", "Press V for COAS. Use left/right arrows for yaw; Z/X for roll. Center Earth and level the terminator, daylight up.", "Press Continue when the Earth is centered and level."],
		Correction.Phase.SUN: ["Align the Sun", "Press V for AOT. Use up/down arrows for pitch. Place the Sun at the top of the cursor.", "Press Continue with the Sun aligned."],
		Correction.Phase.PAD: ["Read the maneuver PAD", "Plan four-jet ullage for 10 seconds, then 10% throttle. Manually stop the DPS burn at 14 seconds.", "Keep attitude rates below 10 degrees per second. Continue when ready."],
		Correction.Phase.GO: ["Accept Houston's go", "Review the maneuver and prepare for final engine checks.", "Continue to configure the engine."],
		Correction.Phase.ARM: ["Prepare ullage", "Verify DESCENT arm, manual minimum throttle and engine gimbal OFF.", "Continue to the ullage timer."],
		Correction.Phase.ULLAGE: ["Hold four-jet ullage", "Hold Space for +X ullage. At 10 seconds, keep holding and press Enter to start the engine. Release Space after ignition.", "Ullage: %.1f / 10.0 s" % correction.ullage_time],
		Correction.Phase.BURN: ["Fly the DPS burn", "Maintain the Earth alignment with arrows and Z/X. Watch the event timer. At 14 seconds press Backspace or ENGINE STOP.", "Burn: %.1f / 14.0 s" % correction.burn_time],
		Correction.Phase.TRIM: ["Trim the velocity", "Tap or hold Space for +X translation. Release at +7.6 ft/s on DEDA 470.", "DEDA 470: %+.1f / +7.6 ft/s" % correction.delta_v.z],
		Correction.Phase.COMPLETE: ["Correction complete", "Review the final velocity and burn time.", "Continue to Odyssey power-up."],
		Correction.Phase.RETRY: ["Review and retry", correction.retry_reason, "Continue to reset the maneuver."],
	}
	var instruction: Array = instructions.get(correction.phase, ["Review", "Follow Houston's call.", "Review the current configuration."])
	if correction.phase == Correction.Phase.RETRY and str(instruction[1]).is_empty(): instruction[1] = "Reset the maneuver and repeat the alignment and burn checks."
	return {"chapter": "MCC-5 / COURSE CORRECTION", "title": instruction[0], "count": count,
		"context": "Earth and Sun alignment / manual propulsion", "action": instruction[1], "verify": instruction[2],
		"confirm": correction.phase not in [Correction.Phase.ULLAGE, Correction.Phase.BURN, Correction.Phase.TRIM]}

func _odyssey(cabin: Node3D) -> Dictionary:
	var scenario: Node = cabin.systems.odyssey
	var step: Dictionary = scenario.current_step()
	if step.is_empty(): return {"chapter": "ODYSSEY POWER-UP", "title": "Power-up complete" if scenario.complete() else "Check power configuration", "count": "VERIFY", "action": "Verify both main buses remain above 24 V and the load below 20 A.", "verify": scenario.notice, "confirm": false}
	var id: String = step.id
	var location := "MISSION CONTROL"
	var action := "Read the Houston call, then confirm."
	if OdysseyData.CONTROLS.has(id):
		location = "PANEL " + str(OdysseyData.CONTROLS[id][0])
		action = "Set %s to %s." % [OdysseyData.CONTROLS[id][1], step.desired]
	elif id == "dsky":
		location = "DSKY"
		action = "Press the highlighted %s key." % step.desired
	return {"chapter": "ODYSSEY POWER-UP", "title": "Reactivate the command module", "count": "%02d / %02d" % [scenario.stage + 1, scenario.steps.size()],
		"context": step.caption, "location": location, "action": action, "gesture": "Use the highlighted station control. Each position or key advances one step.",
		"verify": "Keep both main buses at or above 24 V. Keep load at or below 20 A.\n" + scenario.notice,
		"confirm": id.is_empty() or (id != "dsky" and scenario.positions.get(id, "") == step.desired)}
