using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Aquarius.Sim;

var root = new DirectoryInfo(Environment.CurrentDirectory);
while (root != null && !File.Exists(Path.Combine(root.FullName, "reference", "electrical.json"))) root = root.Parent;
if (root == null) throw new InvalidOperationException("Run from the Aquarius repository.");
var electrical = File.ReadAllText(Path.Combine(root.FullName, "reference", "electrical.json"));
var controls = File.ReadAllText(Path.Combine(root.FullName, "reference", "controls.json"));
var definition = JsonSerializer.Deserialize<ElectricalDefinition>(electrical, ElectricalSimulation.JsonOptions)!;
var checks = new List<object>();
var failures = new List<string>();
string Hash(string x) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(x)));
void Check(bool condition, string name)
{
    checks.Add(new { name, passed = condition });
    if (!condition) failures.Add(name);
}
void Near(double actual, double expected, string name, double tolerance = 1e-7) => Check(Math.Abs(actual - expected) <= tolerance, name);
void Reject(Action<JsonObject> change, string name)
{
    var node = JsonSerializer.SerializeToNode(Fixture(), ElectricalSimulation.JsonOptions)!.AsObject();
    change(node);
    try { ElectricalFlightValidation.Run(node.ToJsonString(), electrical, controls); Check(false, name); }
    catch (ArgumentException) { Check(true, name); }
}
ElectricalFlightManifest Fixture()
{
    var off = definition.EquipmentLoads.SelectMany(l => l.BreakerIds).Distinct()
        .ToDictionary(id => id, _ => "PULLED");
    var on = new Dictionary<string, string>(off) { ["p16_cb_r04_c08"] = "PUSHED" };
    ElectricalFlightConfiguration Config(string id, Dictionary<string, string> states) => new()
    {
        Id = id, Title = "Synthetic 30 W fixture and sourced EPS display", SourceIds = ["fixture_input"],
        Qualification = "Synthetic software fixture, not flight evidence.",
        Controls = states, Assumptions = ["Ideal 30 V sources, original checkout feeds, fixed equipment."],
        AdditionalLoadDutyFractions = new() { ["fixture_30w"] = 1 },
        UnknownLoads = ["All other vehicle loads excluded."]
    };
    return new()
    {
        SchemaVersion = 1, Title = "Flight-runner verification fixture", Qualification = "Software-only fixture.",
        InventorySha256 = Hash(controls), ElectricalSha256 = Hash(electrical),
        Sources = [
            new() { Id = "fixture_input", Role = "model_input", Title = "Synthetic fixture specification", Url = "fixture://input",
                Locator = "30 W on EPS display branch", Qualification = "Invented exclusively for software verification." },
            new() { Id = "fixture_observation", Role = "validation_observation", Title = "Independent fixture expectation", Url = "fixture://expected",
                Locator = "32 W / 30 V", Qualification = "Hand-calculated test expectation, not telemetry." }
        ],
        AdditionalEquipmentLoads = [new() { Id = "fixture_30w", Label = "Synthetic 30 W fixture", BusId = "LMP_DC",
            BreakerIds = ["p16_cb_r04_c08"], PowerW = 30, SourceId = "fixture_input", Qualification = "Synthetic fixed load." }],
        UncertainDutyLoadIds = ["fixture_30w"],
        Configurations = [Config("on", on), Config("off", off)],
        CurrentComparisons = [new() { Id = "current", ConfigurationId = "on", ObservedMinA = 32.0 / 30, ObservedMaxA = 32.0 / 30,
            AdditionalToleranceA = 1e-10, SourceIds = ["fixture_observation"], Qualification = "Software expectation." }],
        HistoryCases = [new() {
            Id = "branch_duty", Title = "Sourced switch events with explicit elapsed time", InitialConfigurationId = "on",
            StartGetSeconds = 1000, EndGetSeconds = 4600, SourceIds = ["fixture_input"],
            InitialRemainingAh = definition.Batteries.ToDictionary(b => b.Id, b => b.CapacityAh / 2),
            InitialConsumedAh = definition.Batteries.ToDictionary(b => b.Id, b => b.Id == "BAT1" ? 1.0 : 0.0),
            Qualifications = ["Rated capacities divided by two are test inputs, not recovered flight state."],
            Events = [
                new() { GetSeconds = 2800, Controls = new() { ["p16_cb_r04_c08"] = "PULLED" }, SourceIds = ["fixture_input"], Qualification = "Branch off at half hour." },
                new() { GetSeconds = 3700, Controls = new() { ["p16_cb_r04_c08"] = "PUSHED" }, SourceIds = ["fixture_input"], Qualification = "Branch on for final quarter hour." }
            ],
            Samples = [
                new() { Id = "before_off", GetSeconds = 2800, Metric = "sourceCurrentA", BeforeEvents = true,
                    ObservedMin = 32.0 / 30, ObservedMax = 32.0 / 30, Tolerance = 1e-10, SourceIds = ["fixture_observation"], Qualification = "Incoming state before opening branch." },
                new() { Id = "after_off", GetSeconds = 2800, Metric = "sourceCurrentA",
                    ObservedMin = 0, ObservedMax = 0, Tolerance = 0, SourceIds = ["fixture_observation"], Qualification = "State after opening branch." },
                new() { Id = "charge", GetSeconds = 4600, Metric = "totalConsumedAh",
                    ObservedMin = 1.8, ObservedMax = 1.8, Tolerance = 1e-8, SourceIds = ["fixture_observation"], Qualification = "0.8 Ah during replay plus separate 1 Ah baseline." },
                new() { Id = "battery_history", GetSeconds = 4600, BatteryId = "BAT1", Metric = "batteryConsumedAh",
                    SourceIds = ["fixture_observation"], Qualification = "Baseline reported separately from new consumption." }
            ]
        }]
    };
}
ElectricalFlightValidationReport Run(ElectricalFlightManifest manifest) => ElectricalFlightValidation.Run(
    JsonSerializer.Serialize(manifest, ElectricalSimulation.JsonOptions), electrical, controls);
var fixture = Fixture();
var report = Run(fixture);
Check(!report.IndependentFlightValidationPassed && !report.CompleteEquipmentLoadCoverage, "Software agreement never completes the flight gate");
Near(report.Configurations[0].SourceCurrentA, 32.0 / 30, "Equipment watts predict source current without aggregate calibration");
Near(report.Configurations[1].SourceCurrentA, 0, "Source switch branch removes its demand");
Check(report.CurrentComparisons[0].Comparison.WithinTolerance == true, "Explicit tolerance enables numerical assessment");
Check(report.Configurations[0].ProtectionTrippedBreakerIds.Length == 0, "Valid fixture survives protection settling");
Near(report.Configurations[0].Snapshot.SimulationTimeSeconds, definition.FixedStepSeconds, "Static prediction settles one actual protection tick");
var history = report.HistoryCases.Single();
Near(history.SourceConsumedAh, 0.8, "Time-tagged branch switching integrates 45 active minutes");
Near(history.SourceConsumedWh, 24, "Independent Wh expectation for switched 32 W demand");
Near(history.ChargeConservationErrorAh, 0, "History source charge conservation");
Near(history.AccountingConservationErrorAh, 0, "History accounting Ah conservation");
Near(history.AccountingConservationErrorWh, 0, "History accounting Wh conservation");
Near(history.Samples.Single(s => s.Id == "charge").Comparison.Prediction, 1.8, "Historical baseline is a report-only offset");
Near(history.FinalAccounting.Source.ConsumedAh, 0.8, "Historical baseline never contaminates conserved source ledger");
Near(history.Samples.Single(s => s.Id == "before_off").Comparison.Prediction, 32.0 / 30, "Before-events sample is not forced to zero by withdrawal");
Near(history.Samples.Single(s => s.Id == "after_off").Comparison.Prediction, 0, "After-events sample follows switch operation");
Check(history.Samples.Single(s => s.Id == "before_off").EventPhase == "before_events", "Sample phase is reported explicitly");
Check(history.Samples.Single(s => s.Id == "battery_history").Comparison.Status == "NO_OBSERVATION", "Unobserved history is not marked a pass");
var predictionSeries = Fixture();
predictionSeries.HistoryCases[0].Samples = [.. predictionSeries.HistoryCases[0].Samples,
    new() { Id = "prediction_only", GetSeconds = 3200, Metric = "totalConsumedAh", SourceIds = [], Qualification = "Prediction-only snapshot, no telemetry observation." }];
Check(Run(predictionSeries).HistoryCases[0].Samples.Single(s => s.Id == "prediction_only").Comparison.Status == "NO_OBSERVATION",
    "Prediction-only time series requires no invented observation receipt");

var changedObservation = Fixture();
changedObservation.CurrentComparisons[0].ObservedMinA = 100;
changedObservation.CurrentComparisons[0].ObservedMaxA = 100;
changedObservation.HistoryCases[0].Samples[2].ObservedMin = 100;
changedObservation.HistoryCases[0].Samples[2].ObservedMax = 100;
var changed = Run(changedObservation);
Near(changed.Configurations[0].SourceCurrentA, report.Configurations[0].SourceCurrentA, "Changing held-out current cannot alter prediction");
Near(changed.HistoryCases[0].SourceConsumedAh, history.SourceConsumedAh, "Changing held-out reserve cannot alter battery history");
Check(changed.CurrentComparisons[0].Comparison.Status == "OUTSIDE_INTERVAL", "Mismatch is reported without a fitted residual");
var noTolerance = Fixture(); noTolerance.CurrentComparisons[0].AdditionalToleranceA = null;
Check(Run(noTolerance).CurrentComparisons[0].Comparison.WithinTolerance is null, "Missing tolerance remains unassessed");

var duty = Fixture(); duty.Configurations[0].AdditionalLoadDutyFractions["fixture_30w"] = 0;
Near(Run(duty).Configurations[0].SourceCurrentA, 2.0 / 30, "Zero additional-load duty removes only overlay equipment");
duty.Configurations[0].AdditionalLoadDutyFractions["fixture_30w"] = 0.5;
Near(Run(duty).Configurations[0].SourceCurrentA, 17.0 / 30, "Explicit fractional duty has independent watts prediction");
Check(Run(duty).Configurations[0].EffectiveElectricalSha256 != report.Configurations[0].EffectiveElectricalSha256, "Duty assumptions change effective configuration fingerprint");
var protection = Fixture(); protection.AdditionalEquipmentLoads[0].PowerW = 10000;
var protectedReport = Run(protection);
Check(protectedReport.Configurations[0].ProtectionTrippedBreakerIds.Contains("p16_cb_r04_c08"), "Overrating additional load exposes actual protective trip");
Near(protectedReport.Configurations[0].SourceCurrentA, 0, "Comparison uses post-protection sustainable source current");
Check(protectedReport.Configurations[0].PreProtectionSourceCurrentA > 300, "Pre-protection current remains inspectable");
var logical = Fixture(); logical.Configurations[0].Controls["p3_flood_ovhd_fwd"] = "OFF";
logical.HistoryCases[0].Events[0].Controls["p3_flood_ovhd_fwd"] = "OFF";
var logicalReport = Run(logical);
Check(logicalReport.Configurations[0].SkippedUnmodeledCommands.GetValueOrDefault("p3_flood_ovhd_fwd") == "OFF", "Inventory-valid unmodeled configuration command is reported");
Check(logicalReport.HistoryCases[0].Events[0].SkippedUnmodeledCommands.GetValueOrDefault("p3_flood_ovhd_fwd") == "OFF", "Inventory-valid unmodeled event command is reported");
Near(logicalReport.Configurations[0].SourceCurrentA, report.Configurations[0].SourceCurrentA, "Unmodeled command invents no demand");

var export = Fixture(); export.Configurations[0].CmExportDemandA = 3;
export.HistoryCases[0].Events[0].CmExportDemandA = 0;
var exported = Run(export);
Near(exported.Configurations[0].SourceCurrentA, 3 + 32.0 / 30, "Export contributes once to predicted source current");
Near(exported.HistoryCases[0].FinalAccounting.CmExport.ConsumedAh, 1.5, "Separate export ledger integrates explicit half-hour interval");
Near(exported.HistoryCases[0].FinalAccounting.LmEquipment.ConsumedAh, 0.8, "Export never increases LM equipment ledger");

Reject(n => n["inventorySha256"] = "wrong", "Stale inventory fingerprints reject");
Reject(n => n["electricalSha256"] = "wrong", "Stale electrical fingerprints reject");
Reject(n => n["configurations"]![0]!["sourceIds"]![0] = "fixture_observation", "Held-out observation cannot initialize configuration");
Reject(n => n["currentComparisons"]![0]!["sourceIds"]![0] = "fixture_input", "Input source cannot masquerade as held-out comparison");
Reject(n => n["historyCases"]![0]!["events"]![0]!["sourceIds"]![0] = "fixture_observation", "Held-out observation cannot drive history event");
Reject(n => n["historyCases"]![0]!["sourceIds"]![0] = "fixture_observation", "Held-out observation cannot initialize battery history");
Reject(n => n["additionalEquipmentLoads"]![0]!["sourceId"] = "fixture_observation", "Observed current cannot become an equipment draw");
Reject(n => n["configurations"]![0]!["complete"] = true, "Incomplete component scope cannot claim full vehicle coverage");
Reject(n => n["configurations"]![0]!["unknownLoads"] = new JsonArray(), "Unknown loads must be explicit");
Reject(n => n["configurations"]![0]!["controls"]!["p16_cb_r04_c08"] = "UNKNOWN", "Invalid switch positions reject");
Reject(n => n["configurations"]![0]!["controls"]!["p3_flood_ovhd_fwd"] = "UNKNOWN", "Invalid positions reject even for unmodeled controls");
Reject(n => n["configurations"]![0]!["controls"]!["unknown_control"] = "OFF", "Unknown inventory controls never silently skip");
Reject(n => n["configurations"]![0]!["initialPreset"] = "minimum_lifeboat_12a", "Aggregate calibration is prohibited in flight predictions");
Reject(n => n["currentComparisons"]![0]!["additionalToleranceA"] = -1, "Negative acceptance tolerance rejects");
Reject(n => n["currentComparisons"]![0]!["observedMaxA"] = null, "Half-specified observation range rejects");
Reject(n => n["historyCases"]![0]!["initialRemainingAh"]!.AsObject().Remove("BAT1"), "Partial initial battery allocation rejects");
Reject(n => n["historyCases"]![0]!["initialRemainingAh"]!["BAT1"] = 1000, "Excess initial battery capacity rejects");
Reject(n => n["historyCases"]![0]!["initialRemainingAh"] = null, "Historical delivered baseline requires compatible remaining-capacity inputs");
Reject(n => n["historyCases"]![0]!["events"]![0]!["getSeconds"] = 999, "Events before replay epoch reject");
Reject(n => n["historyCases"]![0]!["events"]![1]!["getSeconds"] = 2000, "Out-of-order source events reject");
Reject(n => n["historyCases"]![0]!["samples"]![0]!["batteryId"] = "BAT1", "Metric/source scope mismatch rejects");
Reject(n => n["historyCases"]![0]!["samples"]![0]!["sourceIds"] = new JsonArray(), "Observed historical sample requires an observation source");
Reject(n => n["configurations"]![0]!["additionalLoadDutyFractions"]!["eps_displays"] = 0.5, "Base load catalog cannot be rescaled by scenario duty");
Reject(n => n["configurations"]![0]!["additionalLoadDutyFractions"]!.AsObject().Remove("fixture_30w"), "Declared uncertain heater duty cannot silently default");
Reject(n => n["uncertainDutyLoadIds"]![0] = "eps_displays", "Only added equipment can be declared uncertain-duty");
Reject(n => n["configurations"]![0]!["additionalLoadDutyFractions"]!["fixture_30w"] = 2, "Duty fraction above unity rejects");
Reject(n => {
    n["additionalEquipmentLoads"]![0]!["powerW"] = -30;
    n["configurations"]![0]!["additionalLoadDutyFractions"]!["fixture_30w"] = 0;
    n["configurations"]![1]!["additionalLoadDutyFractions"]!["fixture_30w"] = 0;
}, "Zero-duty scenarios cannot hide malformed overlay loads");
Reject(n => n["unrecognizedCalibrationResidual"] = 12.5, "Unknown manifest fields reject rather than silently calibrate");

var realPath = Path.Combine(root.FullName, "reference", "electrical-flight-configurations.json");
string? manifestSha256 = null;
if (File.Exists(realPath))
{
    var realManifest = File.ReadAllText(realPath);
    manifestSha256 = Hash(realManifest);
    var real = ElectricalFlightValidation.Run(realManifest, electrical, controls);
    Check(real.Configurations.Length > 0 && real.CurrentComparisons.Length > 0 && real.HistoryCases.Length > 0,
        "Real source manifest executes current and battery-history predictions");
    Check(!real.IndependentFlightValidationPassed && !real.CompleteEquipmentLoadCoverage, "Real manifest preserves open fidelity gate");
    foreach (var h in real.HistoryCases)
    {
        Near(h.ChargeConservationErrorAh, 0, $"Real history {h.Id}: conserved Ah", 1e-5);
        Near(h.AccountingConservationErrorWh, 0, $"Real history {h.Id}: conserved Wh", 1e-4);
    }
}
var result = new { result = failures.Count == 0 ? "PASS" : "FAIL", passed = failures.Count == 0, checks = checks.Count, failures, inventorySha256 = Hash(controls),
    electricalSha256 = Hash(electrical), manifestSha256, independentFlightValidationPassed = false, cases = checks };
var reportPath = args.FirstOrDefault(a => a.StartsWith("--report="))?[9..] ?? Path.Combine(root.FullName, "output", "electrical-flight-tests.json");
Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(reportPath))!);
File.WriteAllText(reportPath, JsonSerializer.Serialize(result, ElectricalSimulation.JsonOptions) + "\n");
Console.WriteLine(JsonSerializer.Serialize(new { result.passed, result.checks, failures, reportPath }, ElectricalSimulation.JsonOptions));
Environment.ExitCode = failures.Count == 0 ? 0 : 1;
