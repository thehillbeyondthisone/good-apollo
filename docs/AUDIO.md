# Cabin audio

Aquarius now has a spatial Foley palette, independent equipment layers and a
speech-priority mix. Normal desktop/VR play enables sound by default; saved
preferences take precedence. `--self-test` and headless runs start the cabin
muted and do not read or write the operator's audio preferences.

Open **Audio mix** from the main or pause menu. **Play sound check** runs a
24-second audition while the real cabin remains paused. It does not change
controls, equipment state, checklists or checkpoints. Stop it with the same
button, leave the audio page, or resume flight. The audition respects the mix
levels and cabin/radio switches. Settings persist separately from flight saves.

**Test Houston voice** on the same page plays the first CO₂ chapter recording
immediately, without starting a mission or audition machinery. Press it again
to stop. If Mission radio is off, the menu explains that it must be enabled.
This gives VR operators a direct speech-output check. The full sound check's
speech segment starts at 10.5 seconds.

The orientation, water checkout and electrical power-down currently use written
instructions with no spoken narrator. Mission speech begins with Kerwin's first
call at **090:09:17 GET**, when the **CO₂ adapter** chapter starts, and follows
its instruction changes. That chapter is currently desktop-only, so ordinary
VR checkout/power-down has no Houston dialogue. Enabling Mission radio alone
does not add narration to these procedures.

**M** retains its chapter-dependent radio/cabin behavior. **Shift+M** always
toggles cabin sounds. **R** repeats the current radio call. The audio menu is
the common desktop and OpenXR surface, with controller aim/trigger and keyboard
navigation.

## What changes in the cabin

The 28 mono PCM samples form nine families: recorded toggle switches,
breakers, pushbuttons, releases, rotary detents, latches, panel-body impacts,
soft handling and fabric fasteners. Multi-sample families avoid immediate
repeats; pitch/gain variation stays small. Breakers and latches add a quieter
body impact. Sixteen spatial voices use oldest-voice stealing under saturation.

Both desktop and VR actuation paths emit sound. Unchanged absolute VR
positions remain silent. Continuous knobs use quantized movement and a 65 ms
cooldown; attitude/translation handles use a quiet engagement sound instead of
ratcheting continuously. Momentary releases sound separately. CO₂ assembly
steps add handling Foley only when an assembly action actually completes.

Suit fan 1 requires selector `1` and powered breaker `p11_cb_r04_c05`; fan 2
requires selector `2` and powered breaker `p16_cb_r03_c15`. The primary glycol
layer requires `PUMP 1` / `p11_cb_r04_c08` or `PUMP 2` / `p11_cb_r04_c07`.
`INST (SEC)` does not run a pump layer. These mappings use the existing
[equipment evidence](../reference/electrical-flight-loads.json); they do not
add electrical loads or a physical fan/pump model. Equipment spins up and
coasts down in volume and pitch. Muting stops voices immediately.

The dispenser layer uses the existing cap, feed-valve and held-trigger flow
conditions. Its source follows the movable nozzle. It fades out on release or
loss of the open flow path. It adds no water consumption model.

## Mix

All Aquarius sounds route through their own `AQ Mix` bus and a -1 dB limiter.
The global Godot Master bus is untouched. Controls receive a small, damped room
reflection. Machinery is wider and quieter; sources stay anchored to the cabin.
Godot stereo panning follows the active camera/head orientation. This pass does
not implement an HRTF or calibrated acoustic propagation.

Archival CAPCOM stays non-positional as headset speech. The 65 existing radio
files are unchanged. The builder measures gated speech and peaks to choose
per-clip gain; a gentle bus compressor manages speech dynamics. During an
active transmission, machinery ducks 7 dB and controls 2.5 dB, with an 80 ms
attack and 650 ms recovery. The warning bus does not duck. Its sourced 3 kHz
procedural tone and electrical acknowledgement behavior remain intact.

The three presets are **Headphones**, **Speakers**, and **Quiet cabin**. Level
changes are 3 dB steps, bounded from -30 to +6 dB; overall level stops at 0 dB.
Settings live in `user://audio-mix.cfg`. The warning follows overall level and
the cabin switch, independently of radio mute.

## Sources and reproducibility

All new effects are CC0. No paid library or new noncommercial restriction was
introduced. Existing mission-radio recordings retain their separate credits
and license terms in their own manifests.

| Source | Creator | Use |
|---|---|---|
| [Interface Sounds](https://kenney.nl/assets/interface-sounds) | Kenney | Buttons, breakers, releases, detents |
| [Impact Sounds](https://kenney.nl/assets/impact-sounds) | Kenney | Light metal/body impacts and soft handling |
| [Small Toggle Switch](https://freesound.org/people/loganzsound/sounds/877305/) | loganzsound | Close-miked mechanical toggles |
| [Fan, setting 3](https://freesound.org/people/giddster/sounds/437340/) | giddster | Ventilation and filtered pump texture |
| [Velcro Pull 01](https://freesound.org/people/Rudmer_Rotteveel/sounds/536231/) | Rudmer_Rotteveel | Fastener handling |
| [Water dispenser-16.wav](https://freesound.org/people/COSP_LCS13/sounds/186235/) | COSP_LCS13 | Dispenser flow texture |

The fan, pump, water, room response and mechanism choices are **designed
acoustic proxies, not Apollo hardware recordings**. The pump texture is derived
from the fan recording. Soft handling uses edited carpet Foley. The Freesound
inputs are the site's high-quality MP3 previews; converting them to PCM does
not recover lossless originals. Kenney inputs are the original pack OGG files.

[The asset manifest](../assets/audio/cabin/manifest.json) records source URLs,
input/output hashes, trims, filtering, speed, mono conversion and loop edits.
Original Kenney license files are included. The six source pages are preserved
in `reference/audio-source-pages/` as evidence of their CC0 labels. Embedded
third-party Mapbox tokens have been redacted from the archived HTML.

Run `tools/build-cabin-audio.py` with Python, NumPy and FFmpeg, using the sources
in `tmp/audio-sources/`. It builds 48 kHz, 16-bit mono WAVs, with 0.5-second
crossfades on loops. It also recomputes radio playback gains without modifying
the radio source files. Supply `--ffmpeg PATH` to use a different executable.

## Review artifacts and verification

- [33-second showcase](../output/aquarius-audio-showcase.wav): controls, handling,
  dispenser, original CAPCOM, then equipment shutdown. This is the actual Godot
  spatial mixer and bus processing, not a separately sweetened mix.
- [38-second comparison](../output/aquarius-audio-comparison.wav): starts with
  4.8 seconds of the previous procedural implementation at its original levels,
  then the new mix. The versions are not loudness matched.
- [Audio menu](../output/aquarius-audio-menu.png).
- [Signal checks](../reference/audio-signal-quality.json): PCM headroom, loop
  joins, radio byte provenance, rendered levels, stereo placement and shutdown.
- [Audio lifecycle](../reference/audio-lifecycle.json) and
  [actual cabin integration](../reference/audio-integration.json).

Targeted runs cover audio lifecycle, actual EPS/controls/menu integration,
settings persistence, warning-tone behavior, mechanism fixtures, flight menus,
and synthetic VR routing. Signal checks include all original radio file hashes.
Headset listening and subjective acoustic quality have not been verified.

The broader mission-desktop integration runner still has 20 navigation
assertions that expect **F** to move the camera directly to controls. The
current flight-notebook path handles **F** instead. The same 20 failures occur
with the pre-audio `main.gd` backup; the other 650 assertions pass, including
mission-radio mute/repeat behavior. This audio pass does not change that path.

For an offline render use the graphics renderer, not the headless dummy
renderer, with `res://tests/render_audio_showcase.gd`, `--write-movie`,
`--fixed-fps 60` and `--self-test`. The fixture preserves the previous procedural
implementation for comparison. `tools/check-cabin-audio.py` checks the exported
comparison and shipped source data. Normal game launch uses no movie mode.
