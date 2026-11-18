# Cockpit source audit - 2026-11-17

The original **495-entry numbered-panel snapshot has completed its detailed
source-row review**. The expanded inventory has **620 entries: 485 interactive
entries and 135 outputs across 29 groups**. All entries have a recorded source
basis: 581 backed by detailed-table rows, 21 functional descriptions,
16 figure/equipment-list entries, and two assembly retention proxies. The 35
latest definitions comprise 15 cabin input functions and 20 movable-object or
retention states; they are not 35 additional tabled flight switches. The machine-readable
panel matrix, per-control evidence, and source disagreements are in
`reference/control-source-audit.json`.

Audited inventory SHA-256:
`9a9c57df158fb784c750ec855352d65128e0d46b5f44647bd18313204bde4026`.

The known interior functional mechanisms in the declared snapshot are now
source-qualified, and all 76 numbered stowage figure rows have dispositions.
The broader whole-vehicle gate remains **OPEN** because individual closure
counts, wearable/EVA and CSM/camera scope, measured geometry, and three source
disagreements remain unresolved. The source audit does not certify human reach
or headset operation.

## Evidence method

The authority is the downloaded LM 7 and Subsequent Apollo Operations Handbook,
Volume 1, LMA790-3-LM, 1 February 1970. Table 3-1 (PDF pages 672-682) is the
alphabetical index; detailed tables follow it. The source PDF is unchanged.
Rotated full-page renders and OCR for PDF pages 683-810 are cached under
`tmp/pdfs/inventory/details/`. OCR is a finding aid, not a digit/state approval.

`tools/audit-control-sources.py` reproduces the explicit corrections in
`reference/control-detail-overrides.json` and the audit report. The inventory
generator deep-merges those corrections while retaining every established ID.
Each entry distinguishes `visual_table`, `visual_functional_description`,
`visual_figure` and `candidate_assembly_proxy`. OCR/index links alone would not
be a completed state audit; none remain pending in this snapshot. Counts refer
to inventory entries, not unique source rows: grouped numeric-key rows can back
several key definitions. All default positions remain sandbox defaults.

`reference/cabin-mechanism-followup.json` records the additional source evidence
and all 76 stowage-row dispositions. The new software state labels are explicitly
not recovered spacecraft placards. Drogue retention and the forward hatch
hinge-pin set are assembly proxies; individual release-handle/pin counts and
kinematics are not inferred. `docs/CABIN-MECHANISMS.md` separates source-backed
mechanical constraints from declared object-model and output-availability rules.

All **495 original entries** now link to visually reviewed detailed rows, including
all **160 breaker sockets**, all DSKY/DEDA keys and displays, the complete declared
warning/caution arrays, and compound instrument assemblies. The source-confirmed
commander STOP and DES RATE omissions add two further corrected entries. The
off-panel audit adds AOT, ORDEAL, ECS, hand-controller, hatch and guard entries;
nine separately named instrument power-failure lamps are also added.

## Corrections with gameplay consequences

| Area | Source-backed correction | Source pages |
|---|---|---|
| Helium regulators | OPEN/CENTER/CLOSE; released center removes coil excitation while valves retain their commanded state | PDF 696-698, printed 3-26 to 3-28 |
| RCS valve commands | Separate neutral CENTER from open/closed valve state; ascent feed command uses ASC FEED placard | PDF 708-722, printed 3-38 to 3-52 |
| ABORT / ABORT STAGE | Push-push latching controls, reset by a second press | PDF 698-699, printed 3-28/3-29 |
| Engine buttons | Both STOP buttons latch and reset on a second press. START remains pressed until either STOP interrupts its override | PDF 751 and 757, printed 3-81 and 3-87 |
| Panel 5 omissions | Commander STOP and DES RATE control are listed in the source but absent from the original 495-entry snapshot | PDF 751, printed 3-81 |
| Timer controls | Event RESET/COUNT has RESET/UP/DOWN. Timer slew switches have TENS/CENTER/UNITS and operate while held | PDF 739-740 and 752-753, printed 3-69/70 and 3-82/83 |
| Radar test selector | Six sourced TEST/MONITOR selections; the inferred extra LDG RADAR PWR state is removed | PDF 730-731, printed 3-60/61 |
| Explosive-device switches | FIRE commands return to locked SAFE. MASTER ARM and ASC He SEL lock in their selected positions | PDF 760-762, printed 3-90 to 3-92 |
| Battery commands | CENTER preserves latched contactors; ascent feed commands spring back to center. Descent battery talkbacks also have gray/LO | PDF 791-799, printed 3-121 to 3-129 |
| Antenna command ranges | PITCH knob is -75 to +225 degrees; YAW knob is -90 to +90 degrees. These are distinct from antenna/indicator limits | PDF 787, printed 3-117 |
| Selector locks | VHF and S-band antenna selectors require a pull-out action before rotation | PDF 787-788, printed 3-117/118 |
| Communications ranging | FUNCTIONS RANGE includes RANGE in addition to OFF/RESET and TV/CWEA ENABLE | PDF 784, printed 3-114 |
| RCS quad talkbacks | Red TCA fault indication is present in addition to gray/barber-pole valve status | PDF 710-713 and 716-719, printed 3-40 to 3-49 |
| Instrument failure lamps | Nine red power-failure lamps have independent IDs, associated instruments and source rows | PDF 686, 688, 689, 707, 723-725 |

Mechanical command release must preserve downstream relay/valve latches.
Adding CENTER to the inventory must not make an already connected battery
disconnect. Mechanism corrections do not establish propulsion or life-support
simulation, which remain separate work.

## Physical scale anchors

Full-page visual review establishes the following, independently of perspective
measurements from the cabin illustration:

| Constraint | Value | Authority |
|---|---|---|
| Crew-compartment cylinder diameter | 92 inches / 2.3368 m | PDF 22, printed 1-6 |
| Crew-compartment depth | 42 inches / 1.0668 m | PDF 22, printed 1-6 |
| Flight-station centerline separation | 44 inches / 1.1176 m | PDF 22, printed 1-6 |
| Crew-compartment deck | approximately 36 x 55 inches / 0.9144 x 1.397 m | PDF 22, printed 1-6 |
| Forward hatch | approximately 32 inches / 0.8128 m square; inward opening | PDF 24-26, printed 1-8 to 1-10 |
| Main panels 1/2 | canted forward 10 degrees | PDF 24, printed 1-8 |
| Center panels 3/4 | slope down and aft 45 degrees to horizontal | PDF 24, printed 1-8 |
| Side panels 8/12 | canted up 15 degrees from horizontal | PDF 24, printed 1-8 |
| Panel 14 | canted up 36.5 degrees from horizontal | PDF 24, printed 1-8 |
| Breaker rows | canted 15 degrees to the line of sight | PDF 24, printed 1-8 |

These are constraints on the cabin construction. They do not establish exact
panel widths, every switch's three-dimensional location, standing-eye height,
or a human reach envelope. Figure 1-7 (PDF 25, printed 1-9) provides arrangement,
not a scale drawing from which all dimensions can be certified.

## Source reconciliation and remaining gate conditions

- The original numbered-panel rows have been reconciled against their detailed
  tables. Missing commander STOP, DES RATE and nine failure lamps were added.
  Named scales/needles remain sub-elements of their physical instrument
  assemblies, with the grouping explicit in metadata.
- All breaker reference designations and detailed-table ratings were reviewed.
  Comparing them against the earlier EPS data exposed positional transcription
  errors; the report keeps this comparison separate from flight validation.
  A discrepancy ledger is regenerated from the active EPS definition so fixed
  errors disappear from the outstanding set. Fig. 2.5-2 pages 381-383 provides
  the independent schematic check. Sixteen earlier EPS rating transcriptions
  were corrected. One genuine rating discrepancy remains: 4CB121 / RCS SYS B
  PQGS DISP is 2 A in the detailed table (PDF 802) and 3 A in the schematic
  (PDF 381); the explicit model conflict retains 3 A pending adjudication.
- Resolve the VHF antenna selector discrepancy: Fig. 3-2 depicts PLSS TEST,
  while the detailed table at PDF 787 lists AFT/FWD/EVA. The figure-derived
  state is retained with the discrepancy explicit.
- Resolve the system-A quad-2 talkback functional wording: its gray-display row
  says valves closed, while adjacent quad rows say open (PDF 711). All three
  visual states are inventoried; contradictory text is not used to invent a
  flight-system transfer rule.
- All 35 known cabin mechanism candidates now have source-qualified definitions:
  shades, armrests, reels, COAS local hardware, portable utility lamps/clamps,
  overhead reflector aiming, umbilical PTTs, dispenser, Tool B, drogue and
  retention objects. Every stowage row is accounted for as a mechanism, loose
  item, passive geometry, retained package, existing assembly or wearable item.
  Unknown individual closures, full controller/optical shape and articulation,
  wearable/EVA controls, camera operation and CSM-side interfaces remain outside
  the certified cockpit denominator; their wider scope is explicitly open.
- Validate source constraints in the exported cabin and establish remaining
  panel dimensions without treating perspective artwork as measured geometry.
- Further worn-headset testing is **deferred by explicit user request** while
  automated and desktop development continues. The recorded 585-entry session
  includes operator feedback and an 86.25-Hz compositor run; it does not certify
  every control/position, measured reach, or the 35 later mechanism definitions.
  See `output/xr-operator-review.json` and `output/steamvr-compositor.json`.
  Pointer tests launched centimeters in front of each control do not establish
  a human reach pass.
