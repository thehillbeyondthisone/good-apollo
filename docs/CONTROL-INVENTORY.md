# LM-7 control inventory

The current inventory contains **620 tracked entries across 29 groups**:
**485 inputs and 135 outputs**. All original 495 numbered-panel entries have
been reviewed against detailed source rows. The expansion includes off-panel
controls, guards, two missing Panel 5 controls, instrument failure lamps, and
35 cabin mechanism/object-state additions.
See [the source audit](CONTROL-AUDIT.md), [off-panel audit](OFFPANEL-AUDIT.md)
and [cabin mechanisms](CABIN-MECHANISMS.md) for evidence and qualifications.

The active inventory SHA-256 is
`9a9c57df158fb784c750ec855352d65128e0d46b5f44647bd18313204bde4026`.
All 620 IDs bind to the rebuilt cabin; all 485 inputs have moving actuators.
The 8,585-check interaction suite passes with and without hardware batching.
Source states are separate from provisional mesh dimensions, poses and motion
angles. Assembly proxies do not establish individual closure counts. Complete
vehicle scope, exact controller geometry and measured placement remain open;
physical headset follow-up is deferred by the user.

The following sections retain the original 495-entry snapshot as a historical
baseline; its counts and hash are not the current integration contract.

The original 495-entry integration snapshot had SHA-256:

```text
05b78cbcafa8b3c74b9d1f546c50d828b02173014580c8f03f5d238040e6ed22
```

## Evidence and coordinate convention

The primary source is the downloaded Apollo Operations Handbook, *LM 7 and Subsequent, Volume 1*, LMA790-3-LM, dated 1 February 1970. Figure 3-2, *Controls and Displays*, is on **PDF page 827**, printed **3-157/3-158**. Every entry points to this figure. Figure 1-7, *Cabin Interior (Looking Forward)*, is on PDF page 25, printed 1-9; it supplies the visual panel arrangement, not measured dimensions.

`reference/extracts/panel-crops.json` records the exact figure crop rectangles. `reference/extracts/panel-{number}.png` contains the corresponding source artwork. These are crops of the original diagram, not newly drawn legends. The metadata records the original 2376 x 1134 base-render coordinates and 6336 x 3024 high-resolution image. `tools/extract-handbook-panels.py` reproduces the crops with pypdfium2 and Pillow.

Each entry has a stable ID, panel, label, control type, candidate positions, sandbox default, interactive flag, source, confidence and provisional flag. Its `layout.u` runs from 0 on the left to 1 on the right of the panel crop; `layout.v` runs from 0 at the bottom to 1 at the top. Dimensions in the `panels` list are explicitly approximate, in metres. Positions are diagram-relative anchors, not measured 3D switch coordinates.

## Tracked entries

| Panel | Entries | Principal content |
|---|---:|---|
| 1 | 56 | Commander instruments, caution/warning, propulsion and abort |
| 2 | 68 | LMP instruments, RCS valves, ECS monitors and selectors |
| 3 | 36 | Radar, stabilization/control, event timer and lighting |
| 4 | 42 | DSKY keys, annunciators/displays and enable switches |
| 5 | 13 | Engine start, +X translation, mission timer and lighting |
| 6 | 21 | DEDA, AGS status and engine stop |
| 8 | 31 | Explosive devices, vents and commander audio |
| 11 | 89 | Commander circuit breakers |
| 12 | 38 | LMP audio, communications modes and antennas |
| 14 | 30 | Electrical power and battery contactors |
| 16 | 71 | LMP circuit breakers |
| **Total** | **495** | **370 interactive; 125 output/display entries** |

The interactive types are 135 toggles, 160 breakers, 42 pushbuttons, 18 rotaries, 14 thumbwheels and one radar slew joystick. Output entries comprise 87 indicators, 25 meters and 13 displays. Compound instruments are presently counted as assemblies; individual needles/tapes within an instrument are not separate inventory entries.

## Source checks performed

All pictured breaker sockets in the tracked panel 11 and 16 crops were counted row by row: 19+19+19+21+11 = 89 and 16+18+18+19 = 71. Their labels and positions were transcribed from the figure. They use row/column IDs to distinguish repeated placards on different buses.

Sixteen entries also carry detailed control-table page references and electrical reference designations. The key mechanism checks are:

- PDF 727, section/index page 3-57: GLYCOL selector 7S3, GLYCOL component caution 7DS3, SUIT FAN selector 7S1 and SUIT FAN component caution 7DS1. The two circular caution lamps are output entries, not extra switches. The reproduced page footer appears to read 2-57; the control index identifies it as 3-57.
- PDF 762-763, printed 3-92/3-93: STAGE SEQ RELAYS SYS A/B are component caution lights 2DS1/2DS2, not pushbuttons.
- PDF 763-765, printed 3-93 through 3-95: commander audio S-band T/R, ICS T/R, relay, mode, audio control and VHF A switch positions.
- PDF 779, printed 3-109: UP DATA LINK and LMP S-band/ICS T/R switch positions.

The generator asserts unique IDs, normalized coordinates within the texture bounds, and defaults that belong to each entry's position list. The frozen JSON passed those checks. Integration tests must use the frozen hash above; further audit changes should produce a new explicit snapshot.

## Limits and follow-up audit

The full-vehicle denominator has not been established. Reporting 370/370 bindings can demonstrate coverage of this snapshot's interactive entries, but cannot establish that every LM switch is modelled or functional.

The following remain outside this snapshot or need detailed review:

- AOT and ORDEAL controls, utility lights, hand controllers and their axes, hatches, and aft ECS controls/valves.
- Separate guard actuation, lever locks, spring return, momentary switch semantics and safety interlocks.
- Instrument power-failure flags, blank/unplacarded cells, and individual scales/needles within compound meters.
- Exact LM-7 physical dimensions, reach envelopes and source-versus-flown-configuration differences.
- A complete detailed-table audit of placarded states, reference designations and circuit/bus connections for the remaining entries.
- Continuous analog ranges and detents. Thumbwheels/brightness knobs and antenna controls currently use sampled sandbox states.

All defaults are **interaction-sandbox defaults**, not Apollo 13 activation/power-down checklist states. All entries remain provisional even where the source table has been checked. No inventory entry alone demonstrates electrical, propulsion, life-support or guidance behavior. The diagram's example instrument digits are static source artwork; live instruments must render actual simulator values separately.

Later EPS-table review corrected the panel 14 POWER/TEMP MON placards to CDR BUS, SE BUS and AC BUS (AOH PDF 790, printed 3-120), removing the mistakenly separate BUS token. The correction changes the snapshot hash and number of positions for that control; all 495 IDs and the 370 interactive-control count remain unchanged. The EPS core and integration tests use the corrected physical placards.

