# Component-current and battery-history validation

The offline validation path now executes switch-selected equipment demand and
time-tagged source connections before comparing recorded currents and battery
history. **The full electrical flight-validation gate remains open.**

Read the generated [comparison summary](../output/electrical-flight-summary.md)
for current predictions, numerical differences and conditional reserve results.
The [full report](../output/electrical-flight-validation.json) contains per-load
contributions, modeled and skipped commands, source receipts, protection trips,
comparison phase and per-battery snapshots. The
[battery time series](../output/electrical-battery-history.csv) contains hourly
and target-time model outputs; it is not a telemetry tape.

## What executes

Eight configurations cover activation, deep coast, the manual midcourse burn
and subsequent power-down. Each runs with two fixed thermal-demand hypotheses:
thermostats open, or continuous demand wherever their supply is available.
These are sensitivity cases, not uncertainty bounds or a recovered thermal
waveform. No intermediate fraction is selected to match a measured current.

The existing LM-7 equipment catalog is supplemented in this offline runner by
31 optional research entries: 21 nominal branches and 10 thermal-demand loads.
Their watts come from the visually reviewed **LM-8 Systems Handbook Table 5-III**,
PDF 63-66, printed 5-7 through 5-10. LM-7 handbook control and circuit descriptions
constrain their supply paths and operating selectors. Every transferred watt
value retains its explicit LM-8-to-LM-7 applicability assumption. Source hashes
are pinned; changed or missing PDFs reject regeneration.

The table's input-watts column is distinct from breaker ratings, RF output,
heat load and printed ampere values. Conflicting ampere entries are retained as
source discrepancies. Ambiguous multi-bus allocation, dual-feed AEA sharing,
momentary valve/jet demand and incompatible RCS quantity-device bus assignments
are excluded. Source evidence and exclusions live in
[electrical-flight-loads.json](../reference/electrical-flight-loads.json).

Three histories execute actual elapsed GET intervals in the electrical model:

- Two conditional 57:44-141:30 histories begin with the reported 2179 Ah,
  distributed proportionally by rated capacity. That allocation and exact
  starting epoch are assumptions. Events include the guided deep power-down,
  Battery 2 isolation/restoration, midcourse preparation and power-down,
  Batteries 6/5 connection, partial reactivation and Battery 3 removal.
- An 82:30-106:03 sandbox history isolates incremental consumption through
  Battery 2 switching and the manual midcourse burn. It makes no absolute
  comparison with the cumulative 394 Ah Battery 3 delivery or 410 Ah endpoint.

The conditional mission cases include a separately accounted nominal CM-export
input during selected documented charging windows. Flat 8 A between those
calls, uncertain stop times and zero demand outside the selected windows are
scenario assumptions; other CM loads and charger losses remain unmodeled.
Export is debited once from the LM sources. No CM-restored charge is inferred.

## What the comparisons establish

Recorded 96-hour coast, midcourse and post-midcourse currents occur only in
observation records. Mutating those observations cannot change a prediction.
The manual burn's approximately 25 A is evaluated at its configuration, never
integrated over an invented preparation interval or used as a residual load.
The corresponding source is the
[crew/PAO transcript](https://apollojournals.org/afj/ap13fj/19day5-themanualcoursecorrection.html).

The first results expose the missing operating/duty history rather than close
the accuracy gate: heater-open midcourse demand falls below the reported value;
continuous thermal demand exceeds it. The continuous-demand full history can
exhaust the connected descent sources before the burn. Its resulting zero
current is starvation, not agreement with a flown current taper.

Battery 3 current and delivery are sampled **before** its prescribed 139:16
removal. Forcing the contactor off therefore cannot create a zero-current
acceptance result. The final 410 Ah total reserve remains distinct from the
reported 189.6 Ah usable reserve. No new accuracy allowance is inferred from
table decimals, rounded PAO reports or numerical proximity. Real comparisons
have null tolerances and remain `NOT_ASSESSED_NO_TOLERANCE`.

Absolute battery-history discrepancies also include explicitly omitted LGC/DSKY
and IMU operating loads during activation/reactivation. Their standby-heater
overlap is unresolved. Ideal 30 V sources, equal connected-source sharing,
unknown initial battery states, omitted demand and incomplete switch history
prevent a whole-flight battery prediction. The conditional cases demonstrate
the calculation path and expose those gaps; they do not recover the flight.

## Reproduce and verify

Use the portable Python executable and .NET SDK recorded for this machine.
Set `DOTNET_CLI_HOME` and `NUGET_PACKAGES` to writable local caches.

```powershell
$pythonExe = 'C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1112-611-0_26.1112.611.0_x64__3k8sg7r9htsxt/dependencies/python/python.exe'
& $pythonExe tools/build-electrical-flight-loads.py
node tools/build-electrical-flight-configurations.cjs
& D:/apollo-ref/tools/dotnet-10/dotnet.exe run --project tests/Aquarius.Flight.Verify -- .
& D:/apollo-ref/tools/dotnet-10/dotnet.exe run --project tests/Aquarius.History.Verify -- .
& D:/apollo-ref/tools/dotnet-10/dotnet.exe run --project src/Aquarius.Sim.Cli -- flight-validation output/electrical-flight-validation.json
node tools/summarize-electrical-flight.cjs
node tools/verify-reports.cjs
```

`AdvanceStableHistory` accelerates stable electrical intervals only. It uses
the ordinary solver/integration rules, retains individual ticks around source
exhaustion or protection changes, and preserves fractional time. Verification
compares complete snapshots with ordinary fixed stepping across isolated buses,
different source voltages, depletion, trip cascades and save/restore, plus an
independent 24-hour Ah/Wh calculation. Summation order can differ at floating-point
rounding precision. This is not validation of accelerated native CPU sessions.

## Remaining acceptance work

Resolve LM-7 equipment applicability and operating-versus-heater overlap,
especially LGC/IMU demand in the high-power periods. Establish heater thermal
states and jet/actuator duty independently of the current observations. Recover
initial battery histories and unequal sharing, complete switching and CM export
history, then declare instrument/timing/model tolerances before assessing the
held-out currents and reserve endpoints. Physical headset testing remains deferred.
