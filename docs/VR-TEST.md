# Headset acceptance

The operator resumed headset review on 2026-11-17 after reconnecting SteamVR
and reported that the application worked. The reconnect report observed head
tracking, both controllers and application focus. The operator identified
floating panel displays, unwanted hand text and missing water feedback, and
requested a guided flight notebook. The resulting readout, pointer, dispenser
and [notebook changes](FLIGHT-NOTEBOOK.md) have offline regression and rendered
checks. The operator's next review identified the disabled-action affordance,
automatic book movement and unclear guidance. The current build replaces these
with explicit confirmation, a hand-grabbable rigid book, six-page orientation,
contextual hover status and glow/particle beacons. X recalls the book; A reveals
the target. The latest follow-up widens book acquisition to 14 cm around its
surface, accepts grip held while approaching, adds aim-and-grip within 1.2 m,
and uses lighter squeeze thresholds. Menu/focus recovery still requires grip
release. **Floating info** in the pause or Flight controls menu hides the small
status window while keeping the notebook available; recalling the book does not
restore that window. **Audio mix → Test Houston voice** auditions speech
immediately. These changes await headset follow-up. Sustained controller reliability,
reach, readability and the full physical acceptance gate remain unconfirmed.

Launch with the Quest connected through Link/SteamVR and the controllers awake:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -XR
```

Double-click **Launch Aquarius VR.cmd** to use the normal active runtime. For
Steam Link, start Steam Link inside the headset and connect to this PC first.
SteamVR must show the headset and controllers connected.

For Quest Link/Air Link, enter the PC Link environment inside the headset, then
double-click **Launch Aquarius Quest Link.cmd**. It selects the installed Meta
runtime for Aquarius alone. Equivalent explicit commands are:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -XR -XRRuntime SteamVR
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -XR -XRRuntime Meta
```

`-XRRuntime Default` leaves normal runtime selection in place, including any
existing `XR_RUNTIME_JSON` setting. Explicit `SteamVR` or `Meta` sets that
environment variable only for the launch and restores its prior value on exit.
These launchers do not change the installed system OpenXR default. A missing
selected runtime manifest is reported before launching the application.

XR launches select Godot's Mobile renderer with Vulkan. Desktop launches retain
the project's Compatibility renderer. [Godot recommends Mobile for desktop XR](https://docs.godotengine.org/en/4.7/tutorials/xr/setting_up_xr.html);
the change enables its multiview rendering path without reducing the headset's
recommended render target or application resolution scale. For a controlled
comparison or a driver fallback, select Compatibility explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -XR -XRRenderer Mobile -XRReportPath output\xr-mobile.json
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -XR -XRRenderer Compatibility -XRReportPath output\xr-compatibility.json
```

The active OpenXR runtime must have an available headset. If initialization
fails, Aquarius writes an `UNAVAILABLE` report and displays the runtime error
in the launch menu. Cabin entry is disabled and exiting returns code 2.
Timed test runs return code 2 immediately.

## Controller operation

Both hands have a visible aim ray and amber targeting sight. Hovering a control
shows its name, current position and available live status beside that control.
The placard disappears when neither hand is targeting it; it does not trail a hand.
A controller within 5.5 cm of an interactive target
selects it directly. Otherwise the aim ray selects the control in front of it.
The small blue dot at the start of each ray marks the controller's touch tip.
In this build, "finger" touch means that controller-tip proxy. Native skeletal
bare-hand tracking is not enabled by the current core Touch action map.

| Input | Action |
|---|---|
| Move the tip into the face of a pushbutton | Press it |
| Move the tip into the face of a pulled breaker | Push it in |
| Trigger | Advance a control; hold a momentary button |
| Grip + trigger | Reverse; unlock a lever lock |
| Hold trigger + thumbstick | Adjust a rotary/valve or continuously move an axis |
| Left thumbstick, no held control | Slow cabin movement |
| Right thumbstick left/right, no held control | 30-degree snap turn |
| Right thumbstick up/down, no held control | Adjust virtual standing height |
| Menu | Recenter at the cabin start, retaining physical height |
| Grip near the notebook, or aim + grip within 1.2 m | Grab and reposition it; release to let it drift |
| X | Recall the notebook within reach |
| A | Reveal the current procedure target |
| B/Y | Open the flight menu or go back |
| Aim at a menu button and press/release trigger | Select the menu action |
| Aim at a notebook button or touch its face | Select the notebook action |
| Desktop F8 | Restart frame measurement |
| Desktop F10 | Write the current report |

Open a separate guard before operating its protected control. Use grip + trigger
to pull a breaker out. A touch press starts when the tip approaches the control
from the front. Withdraw the tip to release a momentary button. Held trigger
controls stay selected while the aim moves. Lost tracking or session focus
releases momentary controls and returns spring-centered axes to rest. After
tracking or focus returns, release any held trigger and approach again for touch.
The flight menu includes the **Floating info** toggle and checklist acknowledgment.
Latched controls such as throttle and focus move gradually while the thumbstick
is deflected and retain their setting when released. Axis labels show the
sourced range and unit where available; this does not add subsystem coupling.
Existing rotary, valve and thumbwheel meshes also accept continuous movement
when their inventory entry declares `analog` data. Numeric source samples map
through the declared range; other sampled labels retain evenly spaced anchors.
Continuous values persist separately from the nearest sampled label in the
compatible `axes` save field. A disagreement between them rejects the save.
The virtual movement bounds are inspection conveniences, not a validated cabin
collision or human reach model.

## Next VR chapter: CO₂ adapter

The existing desktop chapter already supplies the assembly sequence, staged
props, recorded Houston calls, suit-loop controls, CO₂ gauge/trend and checkpoint
state. This is a VR interaction port rather than a new mission simulation.
The chapter remains disabled in VR until the following work is implemented:

- Route controller targeting and actions to assembly props. The current XR
  target/router paths accept inventory controls and discard the `co2_prop_`
  targets handled by desktop picking. Add forgiving part grabs, held-part
  feedback, destination snapping, cancel/release and two-hand ownership.
- Check the workshop and installed hose/cartridge positions for headset reach,
  visibility and structural obstruction. Keep the notebook readable during
  assembly and give the current part/destination clear guidance.
- Replace mouse-specific notebook instructions, expose repeat-radio in the
  headset, and connect chapter launch and completed-power-down handoff. Removing
  the menu's desktop guard alone would leave assembly unusable.
- Exercise every assembly and valve step through controller inputs, including
  pause/tracking loss, save/restore, radio progression and powered CO₂ decline;
  then complete a headset playthrough and performance/reach review.

For planning, a first controller-playable port is roughly 1–2 focused development
days; forgiving physical handling plus regression checks and headset iteration
is roughly 3–5 days total. These are scope estimates, not measured commitments.
MCC-5 and Odyssey remain separate later ports. Adding spoken guidance to the
orientation or power-down is also separate from the archival CO₂ radio port.

## Physical check for a future review

1. Confirm stereo rendering, correct apparent scale, tracked head motion and
   both controller rays. Recenter while facing the forward panels.
2. Check readability at normal operating distance and while leaning toward
   dense breaker rows. Report overlapping targets or illegible placards.
3. Exercise toggle, locked lever, guard, breaker, rotary, thumbwheel, valve,
   pushbutton and each hand-controller axis. Check reverse travel and release.
   Press adjacent DSKY keys with the touch tip, then push in and pull out a breaker.
4. With a momentary held, open the runtime dashboard or interrupt tracking.
   After returning, verify the input is released.
5. Visit each panel, AOT, ORDEAL, side/aft ECS controls and hatch mechanisms.
   Check physical reach without relying on long-range rays. The report records
   exercised IDs but cannot infer whether the person reached them naturally.
6. Press F8 and operate/look around for at least 60 seconds with both controllers
   tracked. Inspect SteamVR's compositor timing for dropped/reprojected frames.
7. Save through B/Y → Save checkpoint (or desktop F5), change a latched control,
   restore through B/Y → Restore checkpoint (or desktop F9), and confirm
   the restored state in the headset. Momentary inputs must restore released.
8. Press F10 or close the app and review `output/xr-session.json`.

The report updates every five seconds. It records the inventory fingerprint,
runtime focus/tracking, exercised controls, reverse actions, recentering and
application frame intervals after a three-second tracked warmup. Sampling pauses
when the session loses focus or either controller is untracked. Optional
`-XRDuration 90 -XRReportPath output\xr-session.json` bounds a run in seconds.
Choose **Enter cabin** in the launch menu to begin the flight measurements.
Frame samples are capped at the first 21,600 eligible frames; F8 restarts them.
Reports include runtime target dimensions and scale, rendering configuration,
draw calls, process/physics monitors, and measured render CPU/GPU time where the
renderer provides it. Missing GPU timestamps are marked unavailable. These
values do not measure SteamVR compositor or Steam Link encoding/network time.
Head sampling uses the fresh `head/default` pose consumed by Godot's XR camera,
with its tracking confidence and supported user-presence signal. The report
retains interface-wide tracking status as diagnostic information; it does not
use that status to discard a valid tracked pose.

At 72 Hz the application frame budget is 13.889 ms. Compare mean, p95 and worst
intervals alongside compositor timing; an application-cadence report alone
cannot measure missed display frames or reprojection. A headset refresh rate of
zero means the runtime did not expose the refresh-rate extension.

Reports remain `INCOMPLETE` pending operator review of reach, readability, all
control positions and compositor behavior. Initializing OpenXR, exercising a
single control or passing synthetic tests does not close the headset gate.

## Historical 585-entry headset run - 2026-11-17

The user confirmed that controls worked and labels were readable in the worn
SteamVR headset. The input report observed the head, both controllers and real
switch/guard operations. `output/xr-operator-review.json` preserves that feedback;
it does not certify every reach position or the later rendering comparison.

That build's optimized Mobile/Vulkan path kept the runtime's recommended 2528 x 2704
render target per view and scale 1.0. Shared hardware was drawn in 29 MultiMesh
groups; named control roots, actuators, artwork and readouts remain intact.
F7 reversibly disables/enables batching and restarts the application timing
sample. CPU/EPS continue at 10ms; display publication is bounded to 50ms, with
control changes still applied immediately.

The read-only compositor measurement in `output/steamvr-compositor.json`
validated the Aquarius scene PID and recorded 60 seconds: 5,175 submissions
(86.25 per second), zero reprojected frames and 3 dropped frames (0.058%).
GPU time was 5.15ms mean, 6.05ms p95 and 8.75ms maximum. This exceeds the 72Hz
throughput target for that historical run. Application-loop intervals remain separate
from compositor delivery and show more scheduling jitter; neither metric
certifies wireless transport or every cabin viewpoint. It predates the current
620-entry cabin and its 35 additional mechanism definitions; it does not
validate their reach, rendering cost or the final core Touch map's reliability.

`tools/measure-steamvr.py` reads Valve's IVRCompositor_029 as a background
client, refuses a scene PID mismatch and changes no runtime settings. Use the
renderer child PID from the active Godot process and run:

```powershell
python tools/measure-steamvr.py --pid <Aquarius-renderer-PID> --duration 60 --output output/steamvr-compositor.json
```

The overall VR gate remains open for a complete reach/position audit and final
operator review of the optimized view. The broader inventory gate is tracked
separately in [the cabin mechanism follow-up](CABIN-MECHANISMS.md).

## Software checks

The explicit action map suggests only `/interaction_profiles/oculus/touch_controller`:
11 essential actions and 21 bindings, with 119 structural checks passing in
`reference/xr-action-map-tests.json`. Optional generic-controller, bare-hand and
palm-pose profiles implicated by repeated SteamVR binding-load messages are
omitted. This does not establish support for other controller profiles or
bare-hand tracking. Rebuild and verify the map without starting OpenXR using the
configured Godot executable:

```powershell
godot --headless --path godot --script res://scripts/generate_xr_action_map.gd
godot --headless --path godot --script res://tests/test_xr_action_map.gd
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -XRTest
```

`reference/xr-input-tests.json` passes **64 checks** covering synthetic controller samples through the
same live input state machine and cabin operation methods. It tests reverse,
held selection, two-hand isolation, loss-of-tracking release, guards, locks,
continuous axes and readonly outputs. It explicitly records `headsetTested=false`.

The current 620-entry build also passes **243 targeting and touch checks**, including
**210 real-cabin comparisons** with the full-scan oracle and direct presses of a
real DSKY key (`reference/xr-target-tests.json`), and **35 batching checks**
(`reference/cabin-batching-tests.json`). The mechanism-specific fixture passes
**104 checks**; the actual cabin/EPS/native-checkpoint test passes **90 checks**
(`reference/cabin-mechanisms-integration.json`). The latter tests moved glTF
assemblies and targets, real branch-controlled lights and complete restore;
six explicitly marked copies of an imported shared mesh serve as controlled
batch-pose witnesses. These offline checks do not claim a new headset pass.

The Windows application title must not contain `|` or other characters invalid
in filenames. SteamVR embeds the title in its generated controller-binding
filenames; an invalid title can leave a visible cabin with no controller inputs.
The software check guards this requirement.

Implementation follows Godot's [OpenXR startup settings](https://docs.godotengine.org/en/4.7/tutorials/xr/openxr_settings.html),
[controller inputs](https://docs.godotengine.org/en/4.7/classes/class_xrcontroller3d.html)
and [session focus signals](https://docs.godotengine.org/en/4.7/classes/class_openxrinterface.html).
