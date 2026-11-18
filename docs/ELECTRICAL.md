# Electrical model - sourced loads and caution/warning

This is a partial Phase 4 implementation. It supplies deterministic charge accounting, battery/feed/bus connectivity, circuit-breaker state, twenty source-valued equipment load entries, lamp/tone testing, selected real warning conditions and engine-independent persistence. The full flown power-profile validation gate remains **open**.

## Sources and established values

| Evidence | Location | Used for |
|---|---|---|
| LM 7 and Subsequent AOH Vol. 1 | PDF 377-380, printed 2.5-1 through 2.5-4 | DC buses, inverters, normal power distribution and cross-ties |
| AOH Figure 2.5-2, three sheets | PDF 381-383, printed 2.5-5, 2.5-6, 2.5-6A/2.5-6B | Breaker source buses and rated amperages |
| AOH battery descriptions | PDF 397 and 399, printed 2.5-19 and 2.5-21 | Four descent batteries rated 400 Ah each; two ascent batteries rated 296 Ah each; nominal 30 V |
| AOH control tables | PDF 685, printed 3-15 | DC BUS warning threshold below 26.5 V on either DC bus |
| AOH control tables | PDF 789-790, printed 3-119/3-120 | Panel 14 volt/amp selection and descent amp-display scaling |
| Apollo 13 Mission Report | Small PDF 45, printed 6-1; high-resolution PDF 37 | Reported initial powerdown 900 W/30 A; later about 360 W/12 A; delivered stage charge |
| Mission Report batteries/consumables | Small PDF 62-64, printed 7-6 through 7-8; high-resolution PDF 54-56 | 2179 Ah available at LM power-up; roughly 7 A CM charging for 15 hours; approximately 129 Ah transferred; 410 Ah remaining at undocking; actual capacity curve |
| Flight Director current-profile sheet | `09-a13-fdlog-lm-current-profile.pdf`, PDF 1 | Handwritten planning profile: solid LM line 11.9, 14.7 and 40.7 A at late mission times |

The AOH ratings specify operating conditions. Descent capacity is quoted at 25 A, 28 V for 16 hours and +80 F; ascent capacity at 50 A, 28 V for 5.92 hours and +80 F. They are not a temperature-independent electrochemical guarantee.

The Flight Director sheet is marked as an available/planned current profile and distinguishes a dashed CM line. It is not treated as measured telemetry. Upright read-only extracts are in `reference/extracts/lm-current-profile-p01.png` and `-p03.png`.

The small Mission Report PDF includes Change 1 replacement pages near its front. PDF 6/7 repeat corrected printed pages 7-7/7-8; the main-body values and both report copies were compared. No replacement of printed 6-1 was found.

## Implemented scope

`src/Aquarius.Sim` targets .NET 10 with no Godot or third-party package dependency. `reference/electrical.json`, produced by `tools/build-electrical-reference.py`, contains the source-backed topology and explicitly qualified calibration data. Its provenance pins the current 620-entry cabin inventory. The 160 breaker IDs and scoped EPS topology remain stable; adding cabin mechanisms does not establish additional component currents or subsystem physics.

- Six batteries track remaining Ah, delivered Ah and delivered Wh. A fixed 0.25-second accumulator preserves fractional time across saves. Source exhaustion inside a tick is integrated up to depletion without creating charge or allowing negative capacity.
- Descent batteries 1/2 feed the LMP bus; 3/4 feed the CDR bus. The two 100 A battery-feed breakers on each side are represented. High/low contactor commands obey the sourced mutual interlock; deadface disconnects descent feeds.
- Panel 14 CENTER is a physical switch position, separate from the retained ECA relay command. Returning to CENTER preserves the prior ON, OFF/RESET, CONNECT or DEAD FACE command. The high/low interlock checks retained relays even when the opposite handle is centered. Explicitly momentary or source-marked spring-return inputs release after presets and restore; their relay commands persist in the saved EPS state.
- Ascent batteries 5/6 have normal LMP/CDR feeds and opposite-bus backup feed commands. Both 30 A balance-load and 100 A emergency cross-tie endpoint pairs connect the DC buses when their endpoints are closed.
- Two selectable ideal inverters feed the AC A/B buses through the appropriate input/tie breakers. Energized AC output is represented as 115 V.
- Every one of the frozen inventory's 160 breakers has a logical source-bus connection, open/closed state, nominal rating and trip flag: 89 on panel 11 and 71 on panel 16. Opening or tripping a mapped branch removes power from its declared outputs.
- Complete detailed-table review corrected 16 positional rating-transcription errors, cross-checked against the identified Fig. 2.5-2 breakers. For example, LGC/DSKY is 7.5 A, IMU STBY is 5 A and IMU OPR is 20 A. The generated branch entries retain the reference designation, table page and schematic-page evidence. RCS SYS B PQGS DISP remains an explicit source conflict: the diagram gives 3 A and the detailed table gives 2 A; the active model retains the diagram's 3 A pending adjudication.
- One hundred control/output power mappings cover DSKY, DEDA, selected instruments and annunciators. FDAI mappings require both their declared DC and AC branches. These are a scoped set, not the complete LM wiring diagram.
- A limited caution/warning path implements DC BUS, BATTERY, INVERTER and selected BAT FAULT indications, plus master-alarm acknowledgement and recurrence. Sensor fault injection can illuminate a battery warning without inventing a battery contactor failure, which allows later modelling of the reported false battery 2 warning.
- Panel 14 shows selected battery voltage/current. For descent batteries the gauge reading is twice the actual battery current, as stated in the AOH. AMPS is explicitly invalid in bus-monitor positions. The AC monitor uses the existing voltmeter scale rather than claiming its needle directly reads 115 on a 20-40 V face.

`PoweredControls` and breaker continuity are separate from equipment power consumption. An unquantified branch reports `currentKnown=false`; its numeric zero is not a claim that the real equipment draws zero watts.

## Equipment loads and aggregate calibration

**F11** selects the new `sourced_equipment_checkout` mode. Twenty entries
cover selected communications equipment/states, ORDEAL DC/AC inputs and EPS
displays. The catalog and source pages are recorded in
`reference/electrical-load-evidence.json`; its generator validates the actual
primary-source PDF fingerprint and every supply/state gate.

Equipment watts are routed through closed supply branches and operating
selectors. Constant-power current changes with bus voltage. AC real power is
converted once through the ideal inverter; the displayed AC amps are a
real-power equivalent, not measured RMS current. Source demand and explicit
fault demand contribute once to the protective surrogate, including faults on
an inverter feeder itself. Full current coverage of unquantified branches
remains false. Published design requirements are not measured telemetry.

The HUD identifies **KNOWN EQUIPMENT / PARTIAL LOAD COVERAGE**. Unknown
loads are excluded from this subtotal. No residual is invented to make it
match a historical aggregate. The F11 checkout is not a flown configuration.
See [electrical checkout](ELECTRICAL-CHECKOUT.md) for controls and lamp testing.

The existing aggregate presets remain separate. Their two **bus-level
aggregate loads** use an assumed equal bus split and calibrate to a published
operating aggregate. They do not add the equipment catalog. Pulling an
unquantified branch affects its logical power but does not remove an invented
wattage from an aggregate calibration.

| Preset | Aggregate draw | Meaning |
|---|---:|---|
| `cold_dark` | 0 A | All source feeds disconnected; headless test condition |
| `minimum_lifeboat_12a` | 12 A | Calibration to the later Mission Report operating aggregate |
| `initial_powerdown_30a` | 30 A | Calibration to the initial Mission Report operating aggregate |
| `late_profile_14_7a` | 14.7 A | Calibration to the late Flight Director planning sheet |
| `electrical_checkout` | 12 A | All declared breakers closed, inverter 1 selected, for visual/logic checkout |

These presets are **not complete flown checklist configurations**. Powered presets distribute the reported 2179 Ah initial total across the six rated capacities proportionally; that per-battery distribution is an assumption. User controls, fault inputs and subsequent depletion then operate on that state.

The voltage model is deliberately coarse: ideal 30 V high-tap sources and 28 V low-tap sources, with ideal diode isolation and equal sharing among conducting sources. The 28 V low-tap value is a modelling surrogate, not a recovered discharge curve. Inverter losses, idle consumption, wiring resistance, battery chemistry/temperature, ECA protection time curves and detailed relay latching are not modelled.

Synthetic fault injection exercises protection and deenergization. Quantified branch demand plus an injected fault above the nominal rating trips the breaker at the next fixed tick. This is an instantaneous protective surrogate; nominal ampere ratings alone do not establish real thermal breaker time-current behavior. AC fault-load energy is reflected back to DC sources through the ideal inverter and is included in conserved Wh.

## Equipment and warning verification

The new equipment runner passes **124 checks**: every catalog supply/state
gate, independent DC/AC Wh and Ah conservation, low-tap current, combined
operating/fault protection, AC feeder counting, deterministic replay and
atomic rejection of malformed data or double-counted saves. Its report is
`output/equipment-load-tests.json`.

The actual-cabin equipment fixture passes **44 checks**, including the F11
keyboard path, a 72W amplifier's current change through both switch and
breaker, ORDEAL's two supplies, and complete native-clock checkpoint restore.
The warning runner passes **346 checks**; **154 actual-scene checks** cover
lamp materials/colors, duplicate OFF endpoints, power isolation, real-alarm
acknowledgement, generated tone frequency and muted audio lifecycle.

The electrical data fingerprint changed. Earlier electrical/whole-session
checkpoints reject atomically and are retained; start a fresh checkout and
save explicitly with F5. CPU instruction bytes, fixed rope and inventory IDs
are unchanged.

## Verification and the remaining flight gate

The desktop now includes a [source-qualified power-down guide](ELECTRICAL-POWERDOWN.md):
13 events and 93 branch/selector commands, advanced with F12. Read-up markers
operate no controls, and uncertain individual switch times remain qualified.
Mission GET labels never advance the shared simulation clock. The guide starts
from equipment checkout; it does not load a complete flown configuration.

The source accounting ledger separates known LM equipment, CM export,
synthetic fault demand and unclassified aggregate calibration. Each battery's
actual delivered Ah and Wh are attributed once, including different source
voltages, isolated buses and exhaustion within a tick. Export demand is an
explicit ideal DC-bus scenario input; the charger route, losses, protection
and restored CM battery charge are unmodeled. Positive export is rejected in
aggregate mode because that aggregate may already include it. No historical
export waveform is enabled by default.

`tests/Aquarius.Accounting.Verify` passes 100 checks. The dedicated sequence
runner and actual-cabin replay fixture verify chronology, source commands,
manual overrides and complete native-clock restore. Current evidence lives
in `output/electrical-accounting-tests.json`, `output/electrical-sequence-tests.json`
and `reference/powerdown-integration.json`. These verify software behavior;
they do not resolve the historical stage-delivery boundary or reserve metrics.

EPS saves now use schema 2, with required accounting fields, exact subtotal
conservation checks and physically possible ideal-source energy bounds. The
definition fingerprint is unchanged, but earlier schema 1 saves reject
atomically and remain on disk. Whole-session saves also bind the source
sequence fingerprint and cursor. Fresh checkout and an explicit F5 save
establish a compatible checkpoint.

`tests/Aquarius.Sim.Verify` is a console verification runner with no NuGet test framework. Its report is `output/electrical-core-tests.json`. The current run passes 606 checks, including:

- Exact set equality with all 160 frozen breaker IDs; no orphan aggregate loads; rejection of invalid data.
- 12 A for one hour consumes 12 Ah/360 Wh at the ideal 30 V; 30 A for two hours consumes 60 Ah.
- Battery feed, deadface, balance and emergency cross-tie behavior; HV/LV interlock; inverter isolation.
- DC and AC branch trips, reset/retrip, mapped DSKY deenergization and AC/DC energy conservation.
- Sub-tick exhaustion, nonnegative remaining capacity and conservation through complete depletion.
- Deterministic save/load/replay with fractional time; rejection without partial mutation of damaged or mismatched state; saved contactors cannot bypass interlocks.
- Master-alarm acknowledgement, persistence and recurring warning; released input devices do not restore a held alarm button.
- All four descent high/low pairs retain ON/OFF at CENTER, and mutual interlocks still hold with centered handles. DES BATS retains CONNECT/DEAD FACE; all four ascent normal/backup feed commands retain their sourced isolated-bus connectivity after release.
- Checkpoints preserve ECA relays while restoring spring-return inputs released; missing, foreign, neutral or contradictory relay states reject before any mutation. The corrected 7.5 A LGC/DSKY surrogate stays closed for a synthetic 6 A branch fault and trips for 8 A.

The engine-level cabin/EPS/real-AGC check passes 83 checks, including physical CENTER transitions, lever-lock rejection without unlock input, spring release, retained ascent-feed state through bridge restore and atomic rejection of a corrupted relay save. These are input-path and deterministic-state checks, not headset or flown-profile evidence.

These are software and accounting checks, not a flight validation pass.

`reference/electrical-flight-audit.json`, reproduced by `tools/build-electrical-flight-audit.py`, now supplies the CLI's historical reports. It records 26 source-qualified current/capacity/configuration anchors, seven time-tagged switching events, source receipts, and explicitly assumed scenario intervals. `profile-audit` and `reported-budget` read its calculated report sections; they do not run an independently derived flight simulation. The detailed findings and primary-source locators are in `docs/ELECTRICAL-FLIGHT-AUDIT.md`.

The earlier **92.52 Ah residual is a superseded coarse comparison**, not the current flown schedule. The primary TELMU report places the completed deep powerdown at about **82:30 GET**, with a **12.5 A average**, after initial loads of 28–50 A. Contemporaneous PAO reports place final reactivation at **133:29**, with a reported peak near 70 A of unknown duration, then roughly 40 A by 134:42. Keeping 12 A until 136 h misses a real operating interval. Moving only that late boundary in the old calculation changes the residual to **20.29 Ah**; a separately labeled TELMU chronology illustration gives **−52.96 Ah**. Neither result is an independent validation pass, because aggregate observations and assumed constant intervals define the scenarios themselves. The former automatic 50 Ah acceptance test has been removed; no NASA acceptance tolerance was established.

The transfer accounting remains explicitly unresolved. Reported descent delivery 1434.7 Ah plus ascent delivery 200 Ah gives 1634.7 Ah, while the power-up-to-undocking total-capacity change is 1769 Ah. Subtracting a further 129 Ah CM export produces 415.3 Ah remaining, only 5.3 Ah above the reported 410 Ah, **but no reviewed source explicitly defines the stage-delivery figures as excluding export**. Numerical proximity is not evidence of that boundary. A source-current model must debit CM export exactly once; it must not add an external load to a measured total that already includes it. The TELMU report's **189.6 Ah usable reserve** is also distinct from the Mission Report's **410 Ah total remaining** and cannot replace it as the same validation target.

The [component-validation runner](ELECTRICAL-VALIDATION.md) now executes eight source-constrained configurations and three conditional battery histories with 31 optional LM-8 design-power proxies, explicit thermostat sensitivity and separate CM export. It exposes current and reserve mismatches rather than accepting a fitted residual. The remaining historical gate requires LM-7 load applicability, LGC/IMU operating-versus-heater overlap, complete switching/duty history, unequal source sharing, initial battery history and defensible tolerances. Component draws or aggregate observations used for calibration cannot simultaneously serve as independent validation targets. Exact software conservation remains a separate gate from agreement with flight history.

## API and running locally

```csharp
var sim = ElectricalSimulation.FromJson(electricalJson, controlsJson);
sim.ApplyPreset("minimum_lifeboat_12a");
sim.SetControl("p14_power_temp_mon", "BAT 1");
sim.FixedStep(1.0);
ElectricalSnapshot snapshot = sim.GetSnapshot();
string saved = sim.SaveJson();
sim.LoadJson(saved);
```

Other public inputs are `InjectBranchFault(breakerId, amps)` and `SetBatteryFault(batteryId, flag)`. `ModeledControlIds` is the authoritative input scope; presentation-only controls are intentionally absent. Snapshot fields include batteries, buses, aggregate loads, all breakers, power mappings, meter validity, indicator flags and current control positions.

The POWER/TEMP MON source-table audit corrected the inventory to the physical CDR BUS, SE BUS and AC BUS placards and removed a mistakenly separate BUS token. The core rejects that fictitious position. The control's ID and overall inventory counts are unchanged. EDS battery monitoring, including ED/OFF/ED VOLTS, is outside the modelled power-source scope.

Use the verified portable SDK configured in `reference/runtime-tools.json`. In this sandbox set `DOTNET_CLI_HOME` and `NUGET_PACKAGES` to writable local cache directories. From the repository:

```powershell
dotnet run --project tests/Aquarius.Sim.Verify -- --report=output/electrical-core-tests.json
dotnet run --project src/Aquarius.Sim.Cli -- snapshot minimum_lifeboat_12a 3600
dotnet run --project src/Aquarius.Sim.Cli -- profile-audit
dotnet run --project src/Aquarius.Sim.Cli -- reported-budget
```

Godot's bridge owns live display/lighting integration. Full Phase 4 still requires sourced component load decomposition and the flown switching/load timeline, complete caution/warning wiring, relay/protection behavior, and agreement with actual published flight data under a stated defensible tolerance.

