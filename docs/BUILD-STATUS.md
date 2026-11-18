# Build status - 2026-11-17

The desktop cabin is playable through **Launch Aquarius.cmd**. Development
continues with automated and rendered desktop checks. The user ended headset
testing and explicitly deferred further physical review until much later.

## Current verified work

| Area | Result and evidence |
|---|---|
| Source audit | 620 entries across 29 groups: 485 inputs and 135 outputs. All original 495 panel entries visually reviewed; all 76 stowage rows dispositioned. 581 table, 21 description, 16 figure and 2 assembly-proxy entries; no source-pending entries. Three source conflicts remain explicit. [Audit](CONTROL-AUDIT.md) |
| Control coverage | 620 named glTF nodes and 485 moving inputs; 8,585 interaction checks pass, also with hardware batching. Guards, locks, spring returns, latching buttons, continuous controls and finite rotary stops are represented. [Inventory](CONTROL-INVENTORY.md) |
| Cabin mechanisms | 35 additions: shades, armrests, restraints, local COAS hardware, portable lamps, reflectors, umbilical PTTs, dispenser, Tool B, drogue, hatch maintenance hardware and hammocks. 104 state/transform checks and 90 actual-scene integration checks pass. [Mechanisms](CABIN-MECHANISMS.md) |
| Moving assemblies | COAS cap/knob/filter and portable lamp selectors/clamps follow their assembly and remain targetable after relocation. The full-scene check found and corrected a lamp clamp hidden behind a breaker backing. Exact physical placement remains provisional. |
| Electrical core | Six batteries, four buses and 160 breaker branches; 606 checks pass. Retained ECA relay commands survive physical CENTER return. Source-confirmed rating transcription errors corrected. [Fidelity](ELECTRICAL.md) |
| Equipment load gameplay | F11 selects20 source-valued load entries, with124 core and44 actual-cabin checks. Switches/breakers change demand; AC energy is debited once. Unknown draw is excluded and labeled partial. [Checkout](ELECTRICAL-CHECKOUT.md) |
| Hands-on power-down | F12 starts a 13-callout procedure covering 93 positions. The player operates or verifies the controls. Floods, integral lighting and the DSKY respond to power loss, and the estimated temperature falls on a compressed timescale. 165 core and 510 actual-cabin checks pass. [Guide](ELECTRICAL-POWERDOWN.md) |
| Source accounting | 100 checks pass for separate known-equipment, CM-export, synthetic-fault and aggregate ledgers. Mixed-voltage feeds, open ties and within-tick exhaustion conserve Ah/Wh. Historical export definitions remain unresolved. |
| Component flight comparisons | Eight source-constrained configurations, six held-out current comparisons and three conditional battery histories execute with 31 optional LM-8 power proxies; 70 runner checks pass. Thermal sensitivity, missing operating loads and conditional battery initialization prevent an accuracy pass. [Validation](ELECTRICAL-VALIDATION.md) |
| Electrical history integration | 28,863 checks compare stable-span integration with ordinary fixed ticks, including protection/exhaustion boundaries, fractional save/restore and independent Ah/Wh budgets. This is electrical-only replay, not native CPU time-acceleration acceptance. |
| Caution/warning checkout | Exact lamp-test banks, sourced colors and muted warning tone;346 core and154 scene checks pass. Normal warning acknowledgement remains independent of testing. |
| Real flight software | Exact byte-matched LM131R1 rope in the unchanged upstream CPU. Genuine all-eights/lamp-clear output verified through the independent CLI and native adapter. Flight padload remains pending. |
| LGC power cycle | The modeled LGC/DSKY breaker and supply bus halt the stepped CPU while EPS time continues. Power restoration retains magnetic-core erasable words and enters the actual LM131R1 restart after a nominal 250 ms startup inhibit. Native and actual-cabin tests cover restart, dark display, input gating, and off/startup checkpoints. [LGC power](LGC-POWER.md) |
| Whole-session restore | Shared 10ms clock; staged restore of controls, EPS, complete CPU/peripheral state, display latches and timing. 46 checkpoint and 10 default-backend checks pass. New mechanism poses and continuous values also pass actual-scene restoration. |
| XR software | 64 input, 222 spatial-target, 119 action-map and 35 batching checks pass without a headset. The 222 checks include 210 actual-cabin comparisons against a full-scan target oracle. [Details](VR-TEST.md) |
| Cabin lighting | Warm fixture pools, cooler shade-gated window spill, local deck return and lower neutral ambient replace the unrestricted exterior fill. One fixture shadow map follows the forward/aft view, including the active XR camera; integral legends, utility lamps and reflected spill follow their electrical controls. [Forward](../output/lighting-forward.png) · [Aft](../output/lighting-aft.png) · [Utility lamp](../output/lighting-utility.png) · [Mobile renderer](../output/lighting-mobile-forward.png). A 360-frame Compatibility desktop run at 1440 × 900 with batching and the shared simulation measured 4.05 ms mean / 8.07 ms p95. [Timing report](../output/lighting-performance.json). Light gains remain illustrative; physical headset performance is unverified. |
| Water checkout clarity | Cap/nozzle alignment corrected in the generated Blender/glTF assembly; the removed cap parks sideways and the supply hose follows the body. FIND and desktop F follow the visible book step, with upright inspection, specific part/gesture instructions and release-gated completion. 90 lighting/water checks and 2,334 notebook checks pass. [Water instructions](FLIGHT-NOTEBOOK.md) · [Dispenser](../output/lighting-dispenser-flow.png) · [Report](../output/lighting-water-tests.json) |
| Aft cabin | Enclosed pressure bulkhead, labeled ECS modules, coupled hoses, ascent-engine cover, crew provisions and two usable hammock positions. Wrapped webbing, stitching and netting show how articles are retained. The aft area receives reflected spill from the powered cabin floods. [Aft view](../output/aquarius-aft-crew-stowage.png) · [ECS detail](../output/aquarius-aft-ecs-detail.png) · [Cold and dark](../output/aquarius-aft-dark.png) |

`reference/build-verification.json` consolidates completed reports and checks
current inventory, layout, glTF, electrical and native/rope fingerprints. It
verifies recorded evidence; it does not rerun simulations.

## Headset evidence and deferral

On the earlier **585-entry build**, SteamVR stereo and both controllers were
observed. The user confirmed working controls and readable labels. A 60-second
compositor run recorded 5,175 submissions (86.25/s), zero reprojected frames,
3 dropped frames and 6.05ms p95 GPU time at recommended resolution.

Later the user reported missing controller rays. A minimal Touch-only action
map is implemented and passes structural checks, but sustained hardware
reliability is unconfirmed. The user subsequently described the game as working
flawlessly for the most part and ended testing. No physical acceptance is
inferred for the new 620-entry geometry. Further headset review is deferred.

## Use the desktop build

- **1 / 2 / 3 / 4**: forward cabin, DSKY close-up, electrical panel, aft cabin.
- **F2 / F3 / F4**: powered checkout, calibrated 12A case, cold/dark.
- **F6**: actual LM131R1 Verb35 lamp test. **F11**: partial sourced-equipment loads.
- **F12** starts or confirms a power-down callout. **F** locates the next control. **Shift+F12** restarts.
- **P**: pause shared clock. **F5 / F9**: whole-session save/restore.
- Click to operate; Shift reverses; Ctrl/Shift unlocks a lever or armrest
  detent. Mouse wheel adjusts a focused continuous knob. **M** enables sound.

Presets are inspection/calibration cases, not recovered flown configurations.
The normal backend shares one clock between EPS and the native CPU;
`-ExternalAgc` selects the independent upstream executable for comparison.

## Open fidelity gates

- **Vehicle inventory and geometry:** Exact panel placements, individual
  closure counts, articulation ranges and full controller grip/cross-axis
  geometry still need engineering evidence. New shapes and poses are qualified
  presentation proxies. The reconstructed aft shell encloses the midsection. Wearable/EVA,
  camera and CSM-interface scope needs its own denominator.
- **Physical VR:** Complete reach/position review and sustained controller
  reliability remain open and deferred. Historical compositor timing does not
  certify current geometry, wireless transport or every view.
- **Electrical flight validation:** Component draws, relay/protection details
  and full CWEA wiring remain incomplete. Primary TELMU/transcript review
  supersedes the old92.52Ah coarse residual: deep powerdown was near82:30 and
  final reactivation started133:29. Source-calibrated chronology scenarios are
  not independent validation. Export accounting, unequal battery/bus sharing
  and total-versus-usable reserve remain explicit. [Audit](ELECTRICAL-FLIGHT-AUDIT.md)
  The implemented guide covers explicit power-down commands, with grouped
  execution where individual times are unknown. It does not supply full-mission
  switching/dwell history. The separate source ledger prevents duplicate export
  debit; the historical stage-delivery definition and actual charger path still
  need evidence. No held-out whole-flight prediction is claimed.
  The audit now includes discrete per-battery and bus telemetry, the CM charge
  sequence and meter readings, and three spot checks against pre-export loads.
  The 12.5 A illustrative coast load misses the reported ~25 A midcourse
  correction load. Component subtotals are now evaluated in the separate optional
  research runner. Whole-vehicle current accuracy remains open: LM-8 transfer
  uncertainty, heater and jet duty, omitted LGC/IMU operating loads and comparison
  tolerances are unresolved. Conditional battery histories expose missing demand
  and initial state; they do not reproduce the flown reserve.
  [Results](ELECTRICAL-VALIDATION.md)
- **Mission memory:** 272 prelaunch-word candidates retain 11 unresolved
  cross-source readings. They are neither approved nor loaded. CPU erasable
  initialization remains explicitly test mode.
- **Guidance and physics:** Exact LGC voltage transients and hardware turn-on
  timing remain open. IMU/radar/engine coupling, trajectory, propulsion and
  life support are not coupled. Dispenser-path
  availability is an indication, not fluid flow or resource depletion.
- **Time acceleration:** Shared 1x stepping/pause/replay is tested; accelerated
  flight is not validated. Historical event anchors do not restore mission state.

The project remains a prototype. Passing software checks does not complete the
vehicle engineering, flight-validation or physical usability gates.

EPS schema 2 rejects older electrical saves. This build also rejects complete
sessions from older native adapters because they lack LGC power-phase state and
use a different binary fingerprint. Rejected startup saves are retained until
an explicit F5 save.
Physical VR remains deferred. The completed desktop guide is shown in
[this capture](../output/aquarius-powerdown.png).
