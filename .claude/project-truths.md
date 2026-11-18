# Project truths - verified 2026-11-17

- **User instruction:** Headset testing is finished for now. Continue game
  development with automated/headless/desktop checks; test VR much later.
  Do not ask for more headset time or launch VR without renewed instruction.
- Latest user-authorized work: component-current prediction incl manual midcourse,
  then battery history. Offline `flight-validation` now executes8configs,
  6current comparisons and3conditional histories with31optional LM-8 proxies.
  See docs/ELECTRICAL-VALIDATION.md and output/electrical-flight-summary.md.
  Thermal sensitivity is not an accuracy interval; no load/duty fits telemetry.
  Midcourse17.639A with thermostats open vs~25reported,42.439A continuous demand.
  Conditional remaining955.225Ah vs410total; the continuous case exhausts.
  Unknown LGC/IMU operating loads, duty, sharing and initial history keep gateOPEN.
  Flight70/history28863checks PASS; current25report consolidation48944assertions.
- Latest offline electrical slice: F12 starts/advances13 source-qualified
  power-down events/93commands;ShiftF12 restarts;presets cancel. GET labels do
  not advance elapsed time. Starting state is partial source checkout,not a
  flown checkpoint. Readups/summary markers never operate controls.
- Separate source ledgers conserve known-equipment,CMexport,synthetic faults
  and unclassified aggregate Ah/Wh. Export is explicit DC-bus scenario input;
  aggregate+export rejects. Historical charger routing/losses,restoredCMcharge
  and reported stage-delivery boundary remain unresolved. No full-flight pass.
- EPS save schema2 requires strict ledger conservation/source energy and rejects
  schema1 saves without overwriting them. Whole-session source cursor is staged
  and validated with EPS,CPU,controls and clock. Definition hash unchanged.
- Accounting100,sequence165,actualscene374 PASS. Rendered output/aquarius-powerdown.png
  inspected desktop only. Modeled LGC/DSKY loss halts the stepped CPU while EPS
  time continues; power restoration retains core erasable and runs the actual
  restart vector after nominal250ms inhibit. Exact voltage transients remain open.
- Launch Aquarius.cmd runs the desktop build. The default backend shares a
  10ms clock between EPS and the native LM131R1 CPU; external CLI is explicit.
- Current inventory: 620 entries, 485 inputs, 135 outputs, 29 groups and 160
  breakers. SHA256 9a9c57df158fb784c750ec855352d65128e0d46b5f44647bd18313204bde4026.
  All original 495 panel entries visually audited and all 76 stowage rows
  dispositioned. 581 table +21 description +16 figure +2 assembly proxy;
  zero source-pending entries, three explicit source conflicts.
- All 35 new cabin functions/object states are implemented as qualified
  presentation proxies. assets/mechanism-layout.json separates invented
  placement/travel from sourced control states. Full vehicle denominator,
  individual closure counts, controller geometry and reach remain open.
- Current evidence: electrical606, interaction8585 (also batched), systems83,
  checkpoint46, default10, syntheticXR64, spatial222, actionMap119, batching35,
  mechanismFixture104 and actualSceneMechanisms90 pass. Reports are consolidated
  by tools/verify-reports.cjs; that consolidator does not rerun simulations.
- COAS and lamp child targets follow moving assemblies. Armrest detents,
  retention locks, power-gated lights and dispenser path availability are
  tested through the actual scene and native whole-session restore. Six test-only
  shared-mesh batch witnesses are explicitly qualified; no fluid physics claim.
- Exact LM131R1 fixed rope SHA256
  ae4f9e51ac9491c3da6462233936daeffc16277cd302c43a70b8459ebcd6cca5.
  Native CPU adapter preserves upstream instruction bytes and complete active
  CPU/peripheral state. AGS FP7 remains unavailable.
- Erasable initialization is test mode. 272 parameter candidates /174 groups
  retain 11 unresolved readings; approvedForLoading=false. Never silently load
  or label as an exact flown checkpoint.
- Electrical Phase4 milestone now has20 sourced equipment load entries and
  working warning-bank/tone checkout. F11 selects the partial equipment mode;
  F2/F3 retain aggregate calibration. Never add aggregate and component loads.
  New checks: equipment124core+44actualscene;CWEA346core+154actualscene. All pass.
- Full electrical flight validation remains OPEN. TELMU and transcript review
  supersede the old92.52Ah residual assumption: deep powerdown near82:30, final
  reactivation133:29, unequal early bus sharing and battery-specific events.
  Chronology scenarios are not independent validation.129Ah export accounting
  is unresolved;189.6Ah usable reserve differs from410Ah total remaining.
  reference/electrical-flight-audit.json and output reports retain limitations.
- Current electrical definition SHA256
  55ee8cace567b9f408aed0c4ac68ee378c01f5a178c749555b3d6fd8ed3bbd0b.
  Equipment evidence generator+electrical generator reproduce byte-for-byte.
  Earlier EPS/whole-session saves reject atomically and are retained; explicit
  fresh checkout/F5 establishes a current checkpoint.
- Earlier585-entry SteamVR run: user accepted controls and labels; compositor
  86.25 submissions/s over60s,0reprojected,3/5175drops,p95GPU6.05ms. Later rays
  disappeared. Minimal Touch-only map is a candidate fix; sustained hardware
  reliability and the current620 geometry are untested. User's final feedback
  was mostly flawless and testing deferred. Never infer frame performance from
  display refresh or claim overall VR acceptance.
- Windows-safe app name is Aquarius - LM-7 Cabin Study; the previous pipe broke
  SteamVR binding filenames. VR launchers use Mobile/Vulkan and per-process
  runtime overrides. Desktop stays Compatibility. No system runtime changed.
- Latest electrical GPU captures inspected: output/aquarius-electrical-checkout.png,
  aquarius-caution-lamp-test.png and aquarius-component-lamp-test.png. Lamp colors
  follow revised AOH lighting table: red warning, yellow caution, blue contact;
  older contact-table red wording is retained as an explicit source distinction.
  Warning tone3kHz; sound remains muted by default. No headset launched.
- Earlier inspected GPU views: output/aquarius-cabin-mechanisms.png,
  aquarius-aft-mechanisms.png, aquarius-shades-deployed.png and
  aquarius-coas-overhead.png. Rear shell is intentionally an open cutaway;
  measured panel placements remain provisional.
- IMU/radar/engine/trajectory/propulsion/life-support coupling remain unimplemented.
  LGC supply interruption/restart is modeled with qualified hardware timing.
  1x pause/replay tested; stable electrical-only history stepping is separately
  verified and does not establish accelerated native CPU/session validation.
- D:\apollo-ref holds references, sources, builds and portable tools. Godot
  .NET4.7.2, SDK10.0.404 and LLVM-MinGW checksums are recorded. No global PATH
  changes, project relocation, commits, pushes, publishing or messages sent.
- Source pins: VirtualAGC938e88d11caea1d72af72e53e6005282023f94c2;
  NASSPa4ed25511e626823f9c83b457cf9371375b82094. NASSP is reference only.
- Mission anchors are visually verified against Mission ReportTable3-I except
  the approximate activation window. Historical events are not trajectory data.
- NASA Earth/cloud/star imagery has illustrative orientation. Digital source
  example values are cleared and live EPS/DSKY outputs replace them. Audio is
  procedural, muted by default and explicitly released on teardown.
- Project remains inside OneDrive with no .git directory. Original user Blender
  scenes are preserved; only the generated Aquarius scene is rebuilt/exported.
