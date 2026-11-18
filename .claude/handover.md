# Handover - 2026-11-17

Read project-truths.md and docs/BUILD-STATUS.md for the current contract.

## User direction

The user authorized gates 1 (cabin/control audit) and 2 (VR), then performed
several worn-headset tests. They have now explicitly finished testing, described
the game as working flawlessly for the most part, and asked us to continue game
development and test VR much later. No more headset requests or launches now.

## Latest electrical iteration

- User explicitly requested sourced current prediction including manual midcourse,
  then battery history. Added docs/ELECTRICAL-VALIDATION.md and the offline CLI
  `flight-validation [reportPath]`:8configs/6current comparisons/3histories,
  with31optional LM-8 power proxies and10explicit thermal-demand fractions.
  Base20-load definition stays pinned. Source PDFs have reviewed SHA guards.
- output/electrical-flight-summary.md is the human review; full JSON and1248row
  hourly/target per-battery CSV are alongside. Observation values never enter
  loads. Thermal-open midcourse17.639A vs reported~25; continuous42.439A.
  These are sensitivity cases, not uncertainty bounds. Gate remains OPEN.
- Conditional full history starts2179Ah with assumed proportional allocation;
  thermal-open final955.225Ah vs410total observed; continuous demand exhausts
  sources. Missing LGC/IMU operating power, duty, initial history and unequal
  sharing prevent flight acceptance. Battery3 samples precede forced withdrawal.
- New verification: flight runner70, stable history28863 PASS. Existing EPS606,
  equipment124,CWEA346,accounting100,sequence165 rerun PASS. Godot build has
  zero warnings/errors; actual shared native/EPS checkpoint46 rerun PASS.
  Consolidator25reports/48944recorded checks. No headset launched.
- Raw sandbox Godot needed workspace-local APPDATA/LOCALAPPDATA and --log-file;
  `.cache/godot-runtime/...console.exe` ran checkpoint successfully. The first
  ordinary launcher sandbox attempt failed to find assemblies/write user log.
  No elevated run or global profile/runtime change was needed.

- Continued offline at user request; no headset runtime launched or requested.
- Implemented13events/93commands source-qualified guided power-down. F12 starts
  with no event, then advances one event per press;ShiftF12 restarts. Presets
  cancel. GET labels never fast-forward the shared clock. Baseline is partial
  equipment checkout, not recovered flight state. Readups are markers; unknown
  per-switch times grouped honestly. Independent review moved four TCA pulls
  earlier based on82:02:54 crew report. Quad1heaterCB remains sealed closed;
  heater switches turn off separately. New docs/ELECTRICAL-POWERDOWN.md.
- Separate conserved source ledgers for known equipment,CMexport,synthetic
  faults and unclassified aggregate. Export is explicit bus-level scenario
  input, not a recovered charger route or restoredCMcharge. Aggregate+export
  rejected to prevent duplicate debit. No historical waveform default.
- New accounting100core,sequence165core,actualscene355checks PASS. Existing
  core606,equipment124+44,caution346,checkpoint46 PASS. Bridge builds clean.
  tools/verify-reports.cjs now consolidates23reports/19981recorded checks.
- New EPS save schema2 requires all ledger fields and conserved physical source
  energy. Whole session stores sequence fingerprint/cursor; malformed cursor
  rejects before any subsystem commit. Old schema1 saves retained and rejected.
  EPS definition hash unchanged55ee8cace567b9f408aed0c4ac68ee378c01f5a178c749555b3d6fd8ed3bbd0b.
- CLI commands: powerdown [stepCount],cm-export-checkout [seconds] [amps] [bus].
  First command is guided no-dwell review, second is synthetic accounting.
  Launcher-PowerDownTest and godot/tests/test_powerdown.gd verify actual scene.
- Desktop output/aquarius-powerdown.png rendered and visually inspected with
  explicit --xr-mode off. HUD wraps and states LGC BRANCH OFF;CPU CONTINUES.
  CPU power-cycle behavior remains unmodeled. Full-flight gate remains OPEN.
- Remaining: full equipment/duty-cycle and mission switching/dwell history,
  historical delivery/export and total/usable definitions,physical charger
  circuit/losses,battery-specific unequal sharing,held-out anchors/tolerances,
  complete sensors/protection and CPU electrical shutdown/restart.

## Previous electrical iteration

- User asked to proceed to the next major gate while deferring headset testing.
  Implemented the Phase4 sourced-equipment/CWEA software milestone; full-flight
  validation stays open and is explicitly distinguished from software success.
- 20 source-valued equipment entries from AOH tables509/205/409 and detailed
  switch/supply rows. F11 selects sourced_equipment_checkout with no aggregate
  double-counting. F2/F3 retain legacy calibrations. Unknown demand is excluded
  and labeled PARTIAL LOAD COVERAGE. No VHF TX/duty-cycle draw invented.
- New core ElectricalLoads.cs, partial ElectricalSimulation routing, persisted
  loadModel/preset consistency. AC real power reaches DC once; injected feeder
  faults count once. Independent review caught/fixed AC-feeder doublecount;
  boundary and direct-feeder regressions included.
- Equipment124core+44actualcabin PASS. CautionWarning346core+154actualscene PASS;
  legacy606,systems83,checkpoint46,default10,batches35,mechanisms90 pass.
  Consolidator20reports/19361recordedassertions (includes repeated interaction
  suite in normal/batched modes) with current source/asset/native pins.
- CWEA LAMP/TONE TEST banks, colors and3kHz sound work independently of sensor
  faults/acknowledgement. Both finite OFF endpoints preserve physical index.
  Audio remains muted by default; lifecycle and waveform checked offline.
- Root inspected output/aquarius-electrical-checkout.png,
  aquarius-caution-lamp-test.png and aquarius-component-lamp-test.png.
- Current EPS SHA55ee8cace567b9f408aed0c4ac68ee378c01f5a178c749555b3d6fd8ed3bbd0b.
  Old EPS/whole-session saves reject atomically and remain preserved. Fresh
  checkout plus F5 creates a compatible save. Inventory/nativeCPU/rope unchanged.
- New primary TELMU source stable D:/apollo-ref/a13-mission-data/a13-mission-ops-report.pdf,
  SHA b1a44d48ec4fd350b90caa0d6579c1eff7b0d69292a7a316cf8c5c6d0fd70545.
  Source audit26anchors+7exactswitchevents corrects deep powerdown82:30 and
  final powerup133:29. Old92.52Ah coarse residual is superseded. New scenarios
  retain uncertainty and false validation flags; CM129Ah export inclusion is
  unresolved;189.6 usable is not410 total. CLI audits read this artifact.
- Next full electrical gate needs broader equipment/duty-cycle coverage,
  time-tagged switch replay, separate export ledger and held-out anchors with
  predeclared uncertainty. Full sensor/relay/protection and CPU powercycle
  coupling remain open. See docs/ELECTRICAL-CHECKOUT.md, ELECTRICAL-FLIGHT-AUDIT.md,
  reference/electrical-gate-status.json and updatedELECTRICAL.md.

## Completed iteration

- 620 entries /485 inputs /135 outputs /29 groups. All original495 panel entries
 visually audited;76 stowage rows dispositioned; zero source-pending entries.
 Source-qualified does not mean full engineering/measured geometry complete.
- 35 new mechanism/object definitions implemented, plus source-corrected locks,
 latches, spring returns, independent guards, continuous values and finite stops.
- Build sources: tools/build-offpanel-inventory.py, build-control-inventory.py,
 build-mechanism-layout.py, cabin-mechanism-shapes.py and build-cabin.py.
 Blender script generates only Aquarius_Visual_Slice and preserves user scenes.
- Current source hash9a9c57df158fb784c750ec855352d65128e0d46b5f44647bd18313204bde4026.
 Layout hashfb5b0518733a99aece68e76c5e8fb5e6eb3cfffcd78c4aa5fc85d7bed3d38f03.
 assets/cabin-build.json pins both. Canonical generation reproducibility checked.
- Mechanisms presenter gates light emission from actual EPS branches plus
 switches/plugs/mount/cap. It indicates dispenser path availability without
 inventing water rate, storage depletion or electrical draw.
- Moving glTF assemblies retain child controls and targets. Portable clamp
 originally behind Panel11 backing corrected by clamped pose BlenderY.38.
- All current counts and report fingerprints are in reference/build-verification.json.
 Interaction8585 passes both normal and batched;actualSceneMechanisms90 checks
 real power gating, common input path, moving rays and native checkpoint restore.
- Updated desktop front/aft/shades/overhead-COAS captures inspected. Rear shell
 intentionally open as cutaway. Exact source dimensions/placements still open.

## VR context - deferred

- Initially no rays: pipe in application name produced invalid Windows binding
 filenames. Windows-safe title fixed it; user confirmed controls/readablelabels.
- Compatibility renderer missed72Hz. Mobile/Vulkan, hardware batching, spatial
 queries and bounded20Hz presentation updates preserve10ms simulation stepping.
 Historical585 build compositor:86.25/s,0reprojected,3/5175drops,p95GPU6.05ms.
- Later rays missing: SteamVR repeated binding reloads/refusal. New explicit
 Touch-only11action/21binding map passes119 software checks. Sustained hardware
 stability remains unconfirmed. Do not claim this hardware fix or620 geometry
 accepted. output/xr-operator-review.json preserves full feedback sequence.
- No Aquarius XR process intentionally left running. SteamVR/user apps untouched.

## Launch and verify

- Launch Aquarius.cmd or tools/run-cabin.ps1. Default shared native CPU/EPS;
 -ExternalAgc preserves wall-clock upstream comparison.
- Keys1/2/3 views;F2 checkout;F3 12A;F4 cold;F6 realVerb35;P pause;F5/F9 complete
 save/restore;M optional sound. Mousewheel continuous,Shift reverse,Ctrl unlock.
- Test,SystemsTest,CheckpointTest,DefaultTest,XRTest are headless launcher flags.
 Additional scripts in godot/tests exercise mechanisms, actionmap, spatialquery,
 batches and actual620 scene. capture_cabin_mechanisms.gd renders desktop only.
- Use portable Godot console under D:\apollo-ref\tools\godot-4.7.2 and set
 DOTNET_ROOT to D:\apollo-ref\tools\dotnet-10 for raw runs. Sandbox .NET runs
 can stall; approved escalated headless runs worked. Always pass absolute report
 paths for raw Godot fixture report overrides.
- tools/verify-reports.cjs verifies recorded reports/current source+asset pins;
 it is not a replacement for running changed behavior tests.

## Next development boundaries

Exact panel/closure/controller engineering geometry, three source conflicts,
full-flight EPS residual, flown padload disagreements, guidance/sensor/engine
coupling, actual LGC power loss, trajectory, propulsion, life support and time
acceleration remain open. These need concrete source-backed implementation
slices and automated validation. Do not hide gaps with calibrated invented loads
or promote test initialization to flown state. Follow user direction to continue
offline and defer physical VR validation.

No .git exists. Nothing committed, published or sent to third parties.
