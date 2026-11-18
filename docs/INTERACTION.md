# Cabin interaction study

The Godot presentation loads the generated cabin and source inventory directly, runs a partial headless electrical model, and connects the physical DSKY to the unchanged upstream CPU running LM131R1. A shared simulation clock is the default. The whole-spacecraft inventory, full electrical flight-validation and headset exit tests remain open.

## Launch

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1
```

The launcher finds portable Godot under `D:\apollo-ref\tools`, or accepts `-GodotPath <executable>`. It builds the C# adapters using the official packages bundled with Godot and prepares the native AGC library in `.cache/agc-power-cycle`. Both builds use local tools and dependencies. `-SkipBuild` is available for an already-built checkout.

- Hold right mouse to look; use WASD to move and Q/E to change height. Ctrl slows movement; Home restores the initial view.
- Click a control to advance it, Shift+click to reverse/unlock it, or Ctrl+click to unlock while advancing. The mouse wheel adjusts a focused continuous control; Ctrl/Shift supplies its unlock gesture.
- Pushbuttons release with the mouse button. The radar slew joystick returns to its sandbox default on release.
- F5 saves, F9 loads, and F1 hides the HUD. Momentary inputs always restore released.
- Indicators, meters and displays are inspectable outputs; clicking them does not operate them.
- F2 loads electrical checkout, F3 the minimum-load calibration case, and F4 cold-dark. These are clearly identified calibration presets, not reconstructed flown checklists.
- F6 enters the test initialization and genuine Verb 35 lamp-test sequence through the physical DSKY key path. It requires an energized DSKY branch and a connected computer.
- 1 returns to the cabin view, 2 shows the DSKY closely, and 3 shows the electrical panel.
- M toggles procedural cabin sounds, which are muted by default. During the CO₂ and MCC-5 chapters, M toggles the historical radio and R repeats the latest call. Captions remain visible with the radio muted.
- P pauses/resumes both simulation systems on the shared clock.

The explicit `-ExternalAgc` fallback uses the independent upstream process. Presentation state then lives at `user://control-state.json`; electrical state at `user://electrical-state.json`. Electrical state includes battery consumption and model timing and autosaves every ten seconds. Latched control positions also autosave after operation. These are sandbox states, not flown activation states. **F5/F9 does not save or restore the external AGC**; it continues independently. A rejected EPS save leaves the active EPS model authoritative and restores physical switch positions from it. An unavailable adapter cannot overwrite an existing electrical save.

The live EPS path supplies voltage/current readouts, modeled caution/master-alarm outputs, battery/bus/breaker continuity, and power-dependent flood/panel illumination. Dimmer gains and rendering photometry are illustrative; they do not invent component wattages. The model uses source-calibrated aggregate loads, not a complete component load schedule. See [the electrical model](ELECTRICAL.md).

The DSKY receives relay-row, sign, blink and annunciator outputs from the verified LM131R1 rope. Opening the LGC/DSKY breaker blanks the display, blocks input and halts the stepped CPU. After restoring branch power, wait for `LGC STARTING` to clear. The native restart retains magnetic-core erasable memory. Initial checkout uses test memory. The external process runs on its independent clock while the cabin gates its DSKY. An app-owned external process stops when the app exits. [LGC power](LGC-POWER.md) · [Upstream connection protocol](AGC-PROTOCOL.md)

## Shared clock and complete checkpoints

The shared clock ticks every 10 ms. The EPS continues while LGC power is off or
the LGC is starting. Automatic display
publication runs at most every 50ms to keep rendering work out of the simulation
loop. Control feedback and explicit snapshot/checkpoint publication remain
immediate; authoritative timing and complete restores are tested independently
of this bounded display delay.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1
```

Normal launch loads the verified native adapter to the unchanged upstream CPU. A single main-thread clock advances the CPU and EPS in fixed 10 ms quanta at 1x. The CPU's integer subcycle remainder is preserved. P pauses both systems; the F6 demonstration also pauses its key schedule. Faster simulation rates are not exposed. `-Stepped` remains a compatible explicit selection. `-ExternalAgc` (or raw engine argument `--external-agc`) selects the independent process fallback; explicit `--agc-attach` also selects that backend. If native initialization fails, the app labels its external fallback and retains the independent-state limitation above.

F5 writes `user://session-state-v1.json` through a flushed temporary file and atomic replacement. F9 stages and validates the complete controls, EPS, CPU state, DSKY relay latches, pending time, pause state and calibration epoch before changing live state. It checks that the saved supply state matches the EPS and that native execution time plus time outside the current CPU epoch matches the shared clock. Reference, native build and checkpoint fingerprints reject incompatible saves. A rejected startup checkpoint is preserved until an explicit successful F5 save.

Restoring releases physical momentary controls and the active-low PRO discrete, and cancels pending demonstration inputs. Other CPU inputs and pending ordinary key interrupts are preserved. Calibration presets reset the EPS trial epoch and apply their breaker and bus power states at the current shared time. [Native CPU and checkpoint details](AGC-STEPPED.md)

## Model contract

`reference/controls.json` supplies stable IDs, positions, types and source references. `assets/aquarius-cabin.glb` supplies named nodes and geometry. Both paths are resolved from the repository root; Godot user arguments `--inventory=<path>` and `--cabin=<path>` can override them.

Every inventory ID appears as a glTF node; interactive nodes contain `<id>__actuator` or `actuator`. The Blender export converts local panel-normal +Z to Godot local +Y. Runtime movement is relative to each exported default transform. Targets adapt to neighboring control spacing to keep densely packed breaker rows separate.

`assets/mechanism-layout.json` supplies explicitly provisional assembly poses and
travel. Imported COAS, lamp and dispenser children move with their parent
actuators; moving-part targets follow those poses. Mechanical prerequisites
block motion, while electrical light availability and dispenser water-path
availability remain derived outputs. See [the mechanism implementation and
proof](CABIN-MECHANISMS.md#runtime-implementation-and-proof).

This is a development project with external assets. Standalone export packaging is not configured yet.

## Verification

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -Test
```

The source-qualified inventory has **620 entries: 485 operable entries and 135
outputs across 29 groups**. Operable entries include movable-object and
retention states, not just numbered-panel inputs. The headless audit passes
**8,585 checks**, with **620/620 bound nodes**, **485/485 moving actuators**, and
zero failures. Results are in
`reference/interaction-coverage.json`. Inventory SHA-256:
`9a9c57df158fb784c750ec855352d65128e0d46b5f44647bd18313204bde4026`.
All original 495 entries now have detailed source-row review; the complete
vehicle denominator remains open. See [the source audit](CONTROL-AUDIT.md).

Checks cover imported glTF bindings, metre-scale cabin bounds, pointer rays
with structural occluders, default poses, every declared position, reverse
travel, lever locks, guards, latching ABORT buttons, hatch latches, continuous
axes, source-qualified mechanism prerequisites, released momentaries and atomic
save rejection. Rays originate 18 cm
in front of each control; they do not establish human reach or headset usability.
Continuous values persist separately from their nearest declared label; numeric
samples need not be uniformly spaced. Physical CENTER detents preserve separate
electrical ECA commands. The denominator is the declared inventory.

Additional checks run through the engine adapters and the genuine native CPU:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -SystemsTest
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -AgcTest
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -NativeAgcTest
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -CheckpointTest
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -DefaultTest
```

The full cabin/EPS/AGC flow passes **83 checks** (`reference/systems-integration.json`): actual key operation produces all 21 numeric eights in the in-cabin DSKY; branch power blanks and blocks the display; interlocks, inward breaker travel, live lighting/dimmers, synthetic trip, warning acknowledgement/recurrence, a 12 Ah calibrated hour, and save rejection/restore are tested. Separate native transport checks pass **30 checks** (`reference/agc-integration.json`), including timed lamp clear, active-low PRO preserving other input bits, release on detachment, and owned-process cleanup. Stock SocketAPI allows one peripheral per reserved port; observer/attachment tests use different ports.

The native C# interop gate passes **55 checks** (`reference/agc-native-integration.json`), including exact cycle/subcycle timing, 50 ms key cadence, canonical replay, authoritative checkpoint timing and incompatible/corrupt native checkpoint rejection. The complete shared-clock cabin gate passes **46 checks** (`reference/checkpoint-integration.json`): controls/EPS/CPU replay, calibration epoch, pause/carry, held-PRO release, cancelled demonstration inputs, source/build validation and corruption leaving the whole live session unchanged. **Eight default-launch checks** (`reference/default-backend.json`) verify native selection without an override, automatic CPU/EPS lockstep and pause. `-SystemsTest` explicitly selects the external backend. These are software checks, not flight validation.

The runtime viewport was rendered on the RTX 4060 and inspected at `output/aquarius-runtime.png`; the genuine V35 close-up is `output/aquarius-lamp-test.png`. `output/aquarius-stepped-lamp-test.png` captures the same real lamp sequence using the shared clock. Regenerate them with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -CapturePath output\aquarius-runtime.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -CapturePath output\aquarius-lamp-test.png -LampTest -View 2
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -CapturePath output\aquarius-stepped-lamp-test.png -Stepped -LampTest -View 2
```

## OpenXR

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -XR
```

The project has two tracked rays, near targeting, direct presses of pushbuttons
and pulled breakers with the controller tip, contextual status placards beside
hovered controls (including positions and available live indications),
unlock/reverse gestures, continuous knobs/axes, inspection movement, recentering
and live acceptance recording. Explicit XR initialization failure writes an
UNAVAILABLE report and exits. The synthetic input fixture passes 64 checks.
Targeting and touch pass 243 checks, including 210 comparisons with an independent
full-cabin scan and direct contact with a DSKY key. Hardware batching passes 35 software
checks. The new mechanism fixture passes 104 checks, and the actual imported
cabin/EPS/native-checkpoint integration passes 90 checks. These are offline
results; they do not extend earlier headset evidence to the new geometry.
The action map is an explicit core Oculus Touch profile with 11 actions and 21
bindings; its structural fixture passes 119 checks. Optional generic-controller,
bare-hand and palm-pose profiles are omitted while investigating repeated
SteamVR binding loads. Sustained reliability of this final map remains unconfirmed.

During the 2026-11-17 headset trial the operator confirmed working controls and
readable labels on an earlier build. Later controller loss remains a follow-up
item. The operator ended testing and deferred further headset review; development
continues offline. Full physical reach, all control positions and final operator
acceptance remain open. See [headset acceptance](VR-TEST.md) for recorded timing
evidence and the remaining Phase 3 checks.

## API references

- [Godot runtime glTF loading](https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html)
- [OpenXR settings and compatibility backend initialization](https://docs.godotengine.org/en/stable/tutorials/xr/openxr_settings.html)
- [XR setup](https://docs.godotengine.org/en/stable/tutorials/xr/setting_up_xr.html)
- [OpenXR action maps](https://docs.godotengine.org/en/stable/classes/class_openxractionmap.html)
