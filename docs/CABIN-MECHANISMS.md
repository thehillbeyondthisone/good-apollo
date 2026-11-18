# Cabin mechanism follow-up — 2026-11-17

The source investigation resolves the broad “shades/stowage/aiming” placeholder
into concrete hardware. **All 76 numbered rows** in the AOH aft and forward
stowage foldouts now have a disposition in
`reference/cabin-mechanism-followup.json`: 31 aft rows and 45 forward rows.
These are overlapping equipment packages and arrangements, not 76 independent
controls. All **35 source-qualified additions** are now included in the
**620-entry inventory**, with 15 cabin input functions and 20 movable-object or
retention states. Every pre-existing 585 definition and ID is preserved. The
machine-readable audit records the active inventory hash and evidence category.
The follow-up ledger preserves its original 585-entry baseline observations;
its `inventoryStatus` and “candidate” wording describe that source investigation.
The active definitions and reconciliation are in `reference/controls.json` and
`reference/control-source-audit.json`.

The remaining whole-vehicle gate is still open. The handbook gives usable
mechanisms and some dimensions, but does not establish every closure, exact
mounting coordinate, wearable control, or CSM interface. None of these gaps is
declared unrecoverable; engineering assembly drawings are the next source class.

## Added cabin mechanisms

| Hardware | Source-backed behavior | Authority: PDF page / printed page |
|---|---|---|
| Three window shades | Rolled and retained at bottom; unroll, flatten against frame and engage snaps. Approximate light transmission 0.1%. | 660 / 2.11-24; 664 / 2.11-28 item 2 |
| Four armrests | Four adjustment positions plus fully up stowage and fully down docking. Spring detents; forward latch buttons. | 655–656 / 2.11-19–20; 664 item 6 |
| Two restraint reel controls | About 30 lbf downward force; locked reels prevent payout but allow reeling in. Commander has docking-ring pin adjustment. | 656 / 2.11-20; 664 items 5, 44, 45 |
| COAS local hardware | Brightness knob, barrel lock, removable cap/filter, relocation between left and overhead window mounts. Panel 8 power selection is already represented. | 657 / 2.11-21; 664 items 1, 26, 28 |
| Two utility lamps | Portable lights with cords and clamps, removed from stowage and plugged overhead. Selectors are already represented. | 633 / 2.10-9; 664 item 10 |
| Two overhead flood reflectors | Rotatable reflectors, separate from portable utility lamps. The source does not call the two forward reflectors rotatable. | 741 / 3-71, 16S6 remarks |
| Two umbilical PTT switches | Named on the commander and pilot oxygen umbilicals, separately from the two ACA grip PTTs. | 663 / 2.11-27 item 26 |
| Crew umbilical connections | Oxygen quick disconnects plus separate electrical and water connections. Oxygen hoses have 1.25-inch inside diameter and 70-degree PGA elbows. | 653 / 2.11-17 |
| Water dispenser/fire extinguisher | Trigger supplies water; removable protective cap, mounting bracket and coiled hose extending about 72 inches. | 653–654 / 2.11-17–18; 663 item 25 |
| Emergency Tool B | Ball-lock head retention; 6.25-inch length, 4.25-inch shaft, 7/16-inch hex drive; rated 1,475 in-lbf. | 659 / 2.11-23 |
| Docking drogue | Release handles free the cone from three tunnel mounting lugs; remove from either tunnel end and stow left of commander. | 658 / 2.11-22; 663 item 1; 664 item 43 |
| Hatch maintenance hardware | Forward quick-release hinge pins and removable antibacterial filter; these are additional to the 11 inventoried hatch definitions. | 24–26 / 1-8–10 |
| Hammocks and equipment retention | Hammocks, stowage straps, bungees, bags and hooks are explicitly named. Their closure/anchor geometry is not specified by the foldouts. | 663–664 / 2.11-27–28 |

The armrest's **4-inch deflection under 300 lbf** describes shock absorption. It
does not supply its normal adjustment range. Likewise the COAS elevation scale
of −10 to +31.5 degrees is a reticle graduation, not a mounting hinge limit.
The COAS overall length is 8 inches. Shade snap counts and reflector aiming
angles remain unspecified.

The [Apollo 13 final stowage list](https://apollojournals.org/afj/ap13fj/pdf/as13b-stowage-list-final-197007.pdf)
provides selected mission-specific corroboration, recorded once in the JSON
ledger. Its cover is dated **21 April 1970**, despite the URL filename. The
handbook foldouts give arrangements and approximate areas; they do not certify
the exact as-flown position of every article.

The aft graphics pass uses AOH Figure 2.11-15 (PDF 663) for the crew provisions,
helmet bag, PLSS remote units, umbilicals and ascent-engine cover. Figure 3-1
(PDF 825) supplies the ECS equipment reference. The Apollo 13 final stowage
list (PDF 58, printed 54, O3049 and O3050) puts both hammock rolls under the
LHSSC, the left-hand side stowage compartment. Operate each roll to deploy it
and click the deployed hammock to stow it. The exact rack geometry, visible
packing, material colors and deployed tether locations are reconstructed.
The aft lighting is simulated spill from the existing floods. [Aft view](../output/aquarius-aft-crew-stowage.png)

## Controller ranges and forces

The two ACA grips and two TTCA handles already have functional definitions.
Their current normalized input representation is not a certified mechanical
replica. The following source values can guide a later coupled physical model:

| Assembly | Established values | Authority |
|---|---|---|
| ACA | Out of detent above 0.5 degrees; direction/pulse switching at about 2.5 degrees; hardover at 12 degrees or more. Proportional output 0.28 V/degree over 1–11 degrees. | PDF 164–165 / 2.1-122–123 |
| ACA stops | Figure labels soft stop 10 degrees +2/−0 and hard stop 13 degrees ±1. The 10-degree dimension is stop travel, not a neutral mounting cant. The figure supplies no complete mounting transform or grip envelope. | Fig. 2.1-40, PDF 165 |
| TTCA throttle | 0-degree reference corresponds to 10% thrust, 51-degree soft stop to 50.6%, and 66 degrees to 92.5%. | Fig. 2.1-42, PDF 167 / 2.1-125 |
| TTCA JETS | Neutral is marked 33 degrees; the 9.5-degree arc spans both bounding travel rays. It is total indicated travel, not ±9.5 each way. Symmetric ±4.75 endpoints remain an inference. Detent switch closes at 0.25-inch displacement. | Fig. 2.1-42 and text, PDF 167 |
| TTCA friction | Minimum setting requires 0.25–1.0 lbf; maximum setting 2.5–3.5 lbf to move handle up/down. No knob-angle transfer curve supplied. | PDF 821 / 3-151, 1H3/1H4 |
| TTCA response | Nonlinear throttle curve and 5-degree dead space associated with friction jump at the breakpoint. A linear angle-to-thrust mapping would not reproduce this. | Fig. 2.1-52, PDF 183 / 2.1-141 |

The ACA axis mapping is vehicle yaw about X, pitch about Y, and roll about Z
(PDF 820 / 3-150). TTCA Y/Z translation remains available in either selector
position (PDF 821). Its selector lever positions are drawn 45 degrees apart.
Neither source provides all Y/Z travel limits or full grip/base dimensions.

[NASA TN D-7884](https://ntrs.nasa.gov/api/citations/19750010202/downloads/19750010202.pdf),
Table III (PDF 15, printed 8), adds ACA maximum height/length/width:
**10.06 × 6.69 × 4.00 inches**, with a 36-inch cable and 4.5-lb mass including
cables. Figure 8 provides an LM torque plot. These improve the scale anchors;
they are not a complete dimensioned shape. Its Table V describes the **CM THC**
and must not supply TTCA dimensions. Generic appendix requirements and the
retrospective TTCA narrative differ from LM-7 AOH; the ledger preserves those
differences and retains the mission-era values.

## Implemented state contract

The ledger proposed stable IDs for the concrete additions, now promoted into
the active inventory as 15 cabin input functions and 20 movable-object/retention
states. They are a functional implementation list, not a certified count of
independent physical controls.
The dispenser feed identity is resolved: existing `ecs_des_h2o` and
`ecs_asc_h2o` supply the dispenser (PDF 446 / 2.6-34, §§2.6.4.3.1–2), so a
separate feed-valve definition would duplicate them. Assembly proxies for drogue
retention and hatch hinge pins do not assert a count of individual actuators.

The candidate list records dependencies: shade snaps release before roll-up;
armrest detents release before adjustment; locked reels still allow reeling in;
COAS power follows mounting location; lamp plugs and selectors both affect
power; clamps retain lamp pose; dispenser cap/feed/trigger are separate states;
drogue retention releases before removal; hatch hinge pins remain distinct from
the existing emergency latch lockpin. Inferred object constraints are labeled
as such, and software state labels must not become invented spacecraft placards.

The runtime contract must distinguish a mechanical block from availability of
an output:

| Relationship | Source or interpretation | Implementation contract |
|---|---|---|
| Armrest adjustment | Functional description, PDF 656 | Require detent release for adjustment; retain the described downward-force exception for leaving stowage. A composite release gesture is an abstraction of the named latch buttons. |
| Restraint reel locked | Functional description, PDF 656 | Block rope payout, allow reeling in. A binary lock node alone does not simulate rope mechanics or the 30-lbf force. |
| Shade snaps | Functional description, PDF 660 | Snaps retain the deployed sheet. A two-state shade node can combine release/rolling, but does not establish separate snap count or travel. |
| COAS lock and relocation | Barrel lock in Fig. 2.11-10; release-before-remount is a mechanical inference | Lock can retain mount state; report the inferred dependency. Do not imply a sourced lock angle. |
| COAS power, cap and brightness | Functional description, PDF 657 | Power/mount/cap affect visible reticle output. They do not prove that the brightness knob is mechanically blocked. |
| Lamp clamp and pose | Portable cord/clamp hardware; retaining pose is an inference | Clamp retains lamp pose; release permits repositioning. A proxy pose is not a recovered aiming range. |
| Lamp plug and selector | Functional description, PDF 633 | Connected plug and active selector permit emission. Selector movement remains possible when unplugged. |
| Dispenser cap, feed and trigger | Use procedure, PDF 653–654; feed identity PDF 446 | Feed availability and removed cap permit useful water delivery. Pressing a dry trigger remains possible; no cap-trigger mechanical lock is established. |
| Drogue retention and pose | Functional description, PDF 658 | Release retention before removal. One retention proxy does not claim a single real release handle. |
| Forward hinge pins | Hatch description/figure, PDF 24–26 | Maintenance retention for door removal, distinct from normal latch and emergency latch lockpin. Individual pin kinematics remain unknown. |

PTT and dispenser inputs remain attached to the held object while the pointer
moves. Trigger release, lost tracking or loss of input focus ends the held
command. That release behavior is an input-system requirement; it does not supply
missing switch-stroke or force measurements.

Wearable controls, CSM tunnel interfaces, camera operation and unidentified
stowage closures remain separate candidate families with explicit resolution
requirements. Loose food, checklists, film, medical items and replacement
cartridges can be picked up/stowed without inventing dedicated panel switches.

## Runtime implementation and proof

All 35 additions bind to named glTF nodes and actuators. The runtime applies
source-qualified locks and retention prerequisites, the armrest release gesture,
continuous adjustments, and assembly motion from `assets/mechanism-layout.json`.
Children and interaction targets follow the moving COAS, portable lamps and
dispenser. Placements, pose angles and travel remain explicit presentation
proxies; software state labels are not added as spacecraft placards.

Utility, overhead-flood and COAS lights follow their existing EPS branches and
mechanical/output conditions. CDR utility intensity remains qualitatively above
the corresponding LMP mode, using illustrative gains. A deployed shade obscures
the external COAS view without cutting its internal reticle power. The dispenser
reports logical water-path availability from its trigger, cap and existing feed
valves; it adds no flow rate, pressure, thermal or consumables model. Unpowered
knobs and dry triggers remain physically operable.

`reference/mechanism-runtime-tests.json` passes **104 offline checks**.
`reference/cabin-mechanisms-integration.json` passes **90 checks** against the
actual 620-node cabin, real EPS branches and native whole-session checkpoints.
The integration verifies moved targets, parent/child poses, continuous value
restoration and released held triggers. Six test-only copies of an actual
imported shared mesh explicitly witness batch-buffer motion and restoration;
this does not imply that every new custom mechanism mesh is batched. Neither
fixture performs headset testing or certifies the provisional geometry.

## Boundaries and source adjudications

- Fixed handgrips and crash bars are passive geometry; their presence does not
  imply a movable flight input.
- The LM 5 waste-transfer hose/valve description must not be copied into LM 7.
  The next paragraph explicitly assigns six directly connected 900-cc
  containers to LM 6 and subsequent (PDF 654–655).
- PLSS, OPS, helmets and suit hardware are not merely passive stowage. The
  handbook describes fan, pump, SSC mode, volume, oxygen and heater controls.
  A wearable/EVA scope needs its own denominator.
- Twelve final docking latches belong to the CM docking ring. The LM-side
  electrical umbilical, deadfacing switches, probe release and CM hatch sockets
  need an explicit simulator interface boundary (PDF 35, 658–659).
- Camera controls and mount releases cannot be counted from a package row.
  The camera source documents and engineering assemblies are needed if camera
  operation is included.
- The forward stowage figure is called an LM 6 arrangement in the illustrations
  list, while its revised foldout has drawing number 300LM7-2. Generic placement
  is not promoted to exact Apollo 13 geometry without corroboration.

## What this closes

The source category is now resolved for shades, armrests, restraint reels, local
COAS hardware, portable lamp movement, overhead reflector aiming, umbilical
PTTs, dispenser and emergency tool. The JSON gives each item known states,
numeric anchors where present, exact page references, and the dimensions still
needed. Every foldout row is accounted for, including articles that should be
pickup/stow objects or passive geometry instead of artificial panel controls.

The 35 source-qualified definitions have been promoted under stable IDs in
the 620-entry snapshot. Exact scale, closure
count, articulation limits, full controller geometry and human reach still
require their own evidence and validation.

Further physical testing is **deferred by the user's explicit request**;
automated and desktop checks continue. The 585-entry hardware benchmark and
operator feedback in `output/steamvr-compositor.json` and
`output/xr-operator-review.json` do not certify the 35 new mechanisms' geometry,
reach or performance. This source report does not claim that certification.
