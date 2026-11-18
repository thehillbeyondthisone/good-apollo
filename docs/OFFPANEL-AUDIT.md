# Expanded cabin control source audit - 2026-11-17

The active inventory contains **620 entries, 485 interactive entries and 135
outputs, across 29 groups**. The additions preserve every original ID and cover the AOT,
ORDEAL, both crew hand controllers, aft ECS controls, utility controls, the radar
gyro selector, hatch mechanisms, three separate covers/guards, and two missing
panel 5 controls. Nine instrument power-failure lamps and 35 cabin mechanism
functions/object states are also represented. The latter comprise 15 manual
cabin input functions and 20 movable-object/retention states, with software
labels and prototype motion explicitly qualified.

This closes the omission of these named functional groups from the declared
inventory. It does not close the full-vehicle denominator, measured geometry,
headset usability, optical behavior, propulsion, or life-support validation.

## Source method and reproducibility

The authority is the locally downloaded *Apollo Operations Handbook, LM 7 and
Subsequent, Volume 1*, LMA790-3-LM, 1 February 1970. Complete rendered source
pages were visually read, including table headings, continuation rows, power
columns and remarks. OCR was not used to choose the added control states.
The latest 35 definitions instead use functional descriptions, figures and
equipment lists; their inspection labels are software abstractions, not table
placards. Two definitions represent retention assemblies whose individual
actuator counts remain unknown.

`tools/build-offpanel-inventory.py` regenerates the source transcription in
`reference/offpanel-controls.json`. `tools/build-control-inventory.py` then
combines the original panel transcription, these additions, expansion patches,
and `reference/control-detail-overrides.json`. Nested source and mechanism
corrections are merged without deleting existing metadata.

| Added group | Entries | Source PDF pages | Printed pages / figure |
|---|---:|---|---|
| Panel 5 STOP, DES RATE, STOP cover | 3 | 751, 827 | 3-81; Fig. 3-2 |
| Panel 6 STOP cover | 1 | 757, 827 | 3-87; Fig. 3-2 |
| Panel 8 STAGE guard | 1 | 762, 827 | 3-92; Fig. 3-2 |
| AOT | 8 | 819-820 | 3-149 through 3-150 |
| ORDEAL | 7 | 821-823, 827 | 3-151 through 3-153/3-154; Fig. 3-2 |
| CDR and LMP ACA | 8 | 820 | 3-150 |
| CDR and LMP TTCA | 12 | 820-821 | 3-150 through 3-151 |
| Utility lights | 2 | 823 | 3-153/3-154 |
| RR GYRO SEL | 1 | 823 | 3-153/3-154 |
| Aft ECS | 27 | 811-818, 825 | 3-141 through 3-148; Fig. 3-1 |
| Forward hatch mechanisms | 6 | 24-26, 817-818 | 1-8 through 1-10; 3-147/3-148 |
| Overhead hatch mechanisms | 5 | 29-30, 817-818 | 1-13/1-14; 3-147/3-148 |
| Instrument power-failure lamps | 9 | 686, 688–689, 707, 723–725 | Detailed instrument rows |
| Cabin mechanism input functions | 15 | 633, 656–657, 660, 663–664, 741 | Functional descriptions / figures |
| Movable-object and retention states | 20 | 24–26, 633, 656–660, 664 | Descriptions / figures; two assembly proxies |
| **Total added** | **125** | | |

Every named functional row in the detailed AOT/ACA/TTCA/ORDEAL/utility/ECS table
span is represented. Paired physical instances are separate IDs. Explicit
multiple-axis controls have an input per axis. This is a declared counting
convention: it does not make an axis a separate physical hand controller.

## Mechanisms and source boundaries

- The CDR STOP control and DES RATE switch were absent from the original
  snapshot. STOP is a push-push latch. DES RATE has +1 FPS, center and -1 FPS
  positions, with spring return to center.
- AOT azimuth has LR, L, F, R, RR and CL positions. Focus, reticle rotation and
  illumination expose normalized continuous travel where exact gearing or
  travel was not established. Reticle-angle display is inventoried; optics are
  not coupled to the LGC.
- ORDEAL ALT SET has the sourced range of 10-310 nautical miles. The SLEW
  neutral position is visible in Fig. 3-2; spring-return behavior is not asserted
  by the inspected table.
- ACA yaw, pitch and roll correspond to rotations about LM X, Y and Z,
  respectively. Both grips have a separate push-to-talk control.
- TTCA is one three-axis tee handle. JETS/THROTTLE selects the meaning of its
  X-axis travel. Separate translation-X and throttle input nodes make both
  functions inspectable in the prototype; they do not assert that the real
  vehicle had two handles. Y and Z translation remain available in either mode.
  Throttle endpoints are 10 and 92.5 percent of maximum thrust. Friction-control
  travel is normalized; no physical hand force is simulated.
- ECS WATER TANK SELECT requires its safety trigger to be lifted before SEC.
  Relief/dump valves have separate squeeze-release triggers. The exterior
  spring-loaded PULL TO DUMP lever is inventoried separately from each interior
  lever. Exterior proxies are inspection controls, not claims of reach from
  inside the cabin.
- SUIT ISOL references 7H6/7H7 and relief/dump references 7H11/7H20 appear as
  pairs in the inspected table. The dataset preserves candidate designations
  without asserting an unproven per-side/per-hatch allocation.
- Forward and overhead hatches each have distinct latch and door actions.
  Forward emergency lockpin release is also inventoried. Source text requires
  cabin depressurization before opening; pressure forces and a pressure
  interlock are not simulated. The overhead interior handle opens by an
  approximately 90-degree counterclockwise rotation.
- STOP covers and the STAGE guard are separately actuated from source Fig. 3-2.
  Their blocking interaction is a declared sandbox rule. No independently
  hinged ABORT STAGE cover was inferred from its square pushbutton housing.

## Geometry and verification still required

All normalized positions, added panel sizes and three-dimensional placements
are interaction-study values. The source explicitly describes a 32-inch-square
forward hatch and a 32-inch-diameter docking tunnel; those dimensions do not
establish every panel dimension or the full cabin envelope. Full closure still
requires a measured drawing audit and human reach/readability testing.

The source-qualified snapshot now includes the known shade, support/restraint,
local COAS, utility-light, umbilical PTT, dispenser and emergency-tool mechanisms.
All 76 numbered stowage rows have dispositions. Named instrument scales/needles
remain sub-elements of their physical assemblies; nine failure lamps are separate
entries. Unknown individual stowage closures, wearable/EVA controls, camera
controls and CSM interfaces are excluded from the current cockpit scope, with
their wider denominator explicitly open. Full mechanism shape, travel, physical
coupling and measured placement still require engineering evidence.

The generator checks duplicate IDs, panel membership, valid states and axis
ranges, and reciprocal guard/interlock references. Engine binding and input
tests must be rerun against the new inventory and regenerated glTF before
reporting the expanded snapshot as verified. The observed 585-entry hardware
benchmark does not certify the later 35 mechanisms. Further physical testing
is deferred by explicit user request; automated and desktop development
continues. Reach, occlusion, legibility and performance remain scoped to the
specific inventory and build actually observed.
