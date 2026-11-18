using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Aquarius.Sim;

var root = new DirectoryInfo(Environment.CurrentDirectory);
while (root != null && !File.Exists(Path.Combine(root.FullName, "reference/electrical.json"))) root = root.Parent;
if (root == null) throw new InvalidOperationException("Run from the project.");
var electrical = File.ReadAllText(Path.Combine(root.FullName, "reference/electrical.json"));
var inventory = File.ReadAllText(Path.Combine(root.FullName, "reference/controls.json"));
var data = JsonSerializer.Deserialize<ElectricalDefinition>(electrical, ElectricalSimulation.JsonOptions)!;
var checks = 0;
var failures = new List<string>();
void Check(bool value, string why) { checks++; if (!value) { failures.Add(why); Console.Error.WriteLine("FAIL: " + why); } }
void Near(double actual, double expected, string why, double tolerance = 1e-7) => Check(Math.Abs(actual - expected) <= tolerance, $"{why}: {actual:R} vs {expected:R}");
bool Reject(Action action) { try { action(); return false; } catch (ArgumentException) { return true; } }
void Conserved(ElectricalSimulation sim, string why)
{
    var snapshot = sim.GetSnapshot(); var a = snapshot.Accounting!;
    var parts = new[] { a.LmEquipment, a.CmExport, a.SyntheticFault, a.UnclassifiedAggregate };
    Near(parts.Sum(p => p.ConsumedAh), snapshot.ConsumedAh, why + ": source Ah partition");
    Near(parts.Sum(p => p.ConsumedWh), snapshot.ConsumedWh, why + ": source Wh partition", 1e-6);
    Near(parts.Sum(p => p.CurrentA), snapshot.Batteries.Sum(b => b.CurrentA), why + ": source current partition");
    Near(parts.Sum(p => p.PowerW), snapshot.Batteries.Sum(b => b.CurrentA * b.VoltageV), why + ": source power partition");
    Near(snapshot.InitialTotalAh - snapshot.Batteries.Sum(b => b.RemainingAh), snapshot.ConsumedAh, why + ": remaining charge");
}

// Independent accounting fixture: 90 W on CDR DC and 23 W at the AC output.
// These values deliberately do not fit a historical current/capacity anchor.
var fixture = JsonNode.Parse(electrical)!;
fixture["equipmentLoads"] = JsonSerializer.SerializeToNode(new[] {
    new EquipmentLoadDefinition { Id="fixture_dc", BusId="CDR_DC", BreakerIds=["p11_cb_r04_c19"], PowerW=90, SourceId="TEST_ONLY", Qualification="Independent accounting fixture" },
    new EquipmentLoadDefinition { Id="fixture_ac", BusId="AC_B", BreakerIds=["p11_cb_r01_c04"], PowerW=23, SourceId="TEST_ONLY", Qualification="Independent accounting fixture" }
}, ElectricalSimulation.JsonOptions);
var p = fixture["presets"]!.AsArray().Single(p => (string?)p!["id"] == "electrical_checkout")!.DeepClone();
p["id"] = "fixture_power"; p["loadModel"] = "sourced_components"; p["aggregateCurrentA"] = 0;
fixture["presets"]!.AsArray().Add(p);
var fixtureJson = fixture.ToJsonString();
ElectricalSimulation Fixture() { var s = ElectricalSimulation.FromJson(fixtureJson, inventory); s.ApplyPreset("fixture_power"); return s; }
var trial = Fixture(); trial.SetCmExportDemand("LMP_DC", 7); trial.FixedStep(3600);
var ledger = trial.GetSnapshot().Accounting!;
Near(ledger.LmEquipment.ConsumedWh, 113, "Equipment energy includes AC conversion once", 1e-6);
Near(ledger.LmEquipment.ConsumedAh, 113.0 / 30, "Equipment source charge");
Near(ledger.CmExport.ConsumedAh, 7, "One hour CM export is 7 source Ah");
Near(ledger.CmExport.ConsumedWh, 210, "CM export is measured at 30 V source input", 1e-6);
Near(ledger.Source.ConsumedWh, 323, "Equipment plus CM input debited once", 1e-6);
Check(!ledger.RestoredCmChargeModeled, "CM restored battery charge is explicitly unmodeled");
Conserved(trial, "Combined DC/AC equipment and CM export");
trial.SetCmExportDemand("LMP_DC", 0); trial.FixedStep(3600);
Near(trial.GetSnapshot().Accounting!.CmExport.ConsumedAh, 7, "Intermittent transfer stops without erasing prior export");
Near(trial.GetSnapshot().Accounting!.LmEquipment.ConsumedWh, 226, "LM load continues while export is off", 1e-6);
Conserved(trial, "Intermittent transfer");

// Isolate the buses and use different taps: energy must use each served source,
// not a global 30 V multiplier or equal shares across an open cross-tie.
trial = Fixture();
foreach (var tie in data.Ties) foreach (var id in tie.BreakerIds) trial.SetControl(id, "PULLED");
foreach (var battery in data.Batteries.Where(b => b.Stage == "descent" && b.NormalBusId == "LMP_DC"))
{ trial.SetControl(battery.HighControlId, "OFF/RESET"); trial.SetControl(battery.LowControlId, "ON"); }
trial.SetCmExportDemand("LMP_DC", 7); trial.FixedStep(3600);
ledger = trial.GetSnapshot().Accounting!;
Near(ledger.LmEquipment.ConsumedWh, 113, "CDR loads retain their independent high-tap energy", 1e-6);
Near(ledger.CmExport.ConsumedWh, 196, "LMP export uses actual low-tap voltage", 1e-6);
Near(ledger.CmExport.ConsumedAh, 7, "Different source voltages preserve input charge");
Near(trial.GetSnapshot().Batteries.Where(b => b.Id is "BAT1" or "BAT2").Sum(b => b.ConsumedAh), 7, "Open cross-ties keep export on its declared bus");
Near(trial.GetSnapshot().Batteries.Where(b => b.Id is "BAT3" or "BAT4").Sum(b => b.ConsumedAh), 113.0 / 30, "Other bus supplies only its own load");
Conserved(trial, "Independent unequal-voltage buses");
foreach (var battery in data.Batteries.Where(b => b.Stage == "descent" && b.NormalBusId == "LMP_DC")) trial.SetControl(battery.LowControlId, "OFF/RESET");
trial.FixedStep(3600);
Near(trial.GetSnapshot().Accounting!.CmExport.ConsumedAh, 7, "Unpowered export bus supplies no charge");
Near(trial.GetSnapshot().Accounting!.CmExport.CurrentA, 0, "Demand on unpowered bus is unserved");
Near(trial.GetSnapshot().Accounting!.CmExportDemandA, 7, "Demand and served current remain distinct");
Conserved(trial, "Unserved export");

// The source bank changes voltage inside one fixed tick as high-tap batteries
// empty before a low-tap backup. Integrate the actual subintervals and stop at depletion.
trial = Fixture();
foreach (var battery in data.Batteries.Where(b => b.Stage == "descent"))
{ trial.SetControl(battery.HighControlId, "OFF/RESET"); trial.SetControl(battery.LowControlId, "OFF/RESET"); }
trial.SetControl("p14_se_bat_1_hi_voltage", "ON"); trial.SetControl("p14_se_bat_2_low_voltage", "ON");
var empty = JsonNode.Parse(trial.SaveJson())!;
foreach (var battery in empty["batteries"]!.AsObject()) battery.Value!["remainingAh"] = battery.Key is "BAT1" or "BAT2" ? .00001 : 0;
empty["initialTotalAh"] = .00002; trial.LoadJson(empty.ToJsonString());
trial.SetCmExportDemand("LMP_DC", 7); trial.FixedStep(.25);
ledger = trial.GetSnapshot().Accounting!;
Near(ledger.Source.ConsumedAh, .00002, "Sub-tick depletion consumes only available source charge", 1e-12);
Near(ledger.Source.ConsumedWh, .00001 * (30 + 28), "Sub-tick feed handoff uses both actual voltages", 1e-12);
Check(trial.GetSnapshot().Batteries.All(b => b.RemainingAh == 0), "Exhausted source bank cannot go negative");
Near(ledger.CmExport.CurrentA, 0, "Fully depleted source stops export");
Conserved(trial, "Sub-tick source handoff and depletion");

// DC and AC faults are explicit diagnostic demand, not LM operating equipment.
trial = Fixture(); trial.SetCmExportDemand("LMP_DC", 7);
trial.InjectBranchFault("p11_cb_r04_c19", 1); trial.InjectBranchFault("p11_cb_r01_c04", .1); trial.FixedStep(3600);
ledger = trial.GetSnapshot().Accounting!;
Near(ledger.SyntheticFault.ConsumedWh, 30 + 11.5, "AC fault conversion and DC fault each debit source once", 1e-6);
Near(ledger.LmEquipment.ConsumedWh, 113, "Synthetic faults do not inflate equipment subtotal", 1e-6);
Near(ledger.CmExport.ConsumedAh, 7, "Fault demand does not inflate CM subtotal");
Conserved(trial, "Equipment, export and synthetic faults");

var aggregate = ElectricalSimulation.FromJson(electrical, inventory); aggregate.ApplyPreset("minimum_lifeboat_12a");
var before = aggregate.SaveJson();
Check(Reject(() => aggregate.SetCmExportDemand("LMP_DC", 7)) && aggregate.SaveJson() == before, "Aggregate-plus-export ambiguity rejects without mutation");
aggregate.FixedStep(3600);
Near(aggregate.GetSnapshot().Accounting!.UnclassifiedAggregate.ConsumedAh, 12, "Aggregate remains unclassified at source boundary");
Near(aggregate.GetSnapshot().Accounting!.LmEquipment.ConsumedAh, 0, "Aggregate never masquerades as equipment-derived housekeeping");
Conserved(aggregate, "Aggregate accounting");
foreach (var invalid in new[] { double.NaN, double.PositiveInfinity, -1.0 })
{ before = trial.SaveJson(); Check(Reject(() => trial.SetCmExportDemand("LMP_DC", invalid)) && trial.SaveJson() == before, "Invalid export demand rejects atomically"); }
before = trial.SaveJson();
Check(Reject(() => trial.SetCmExportDemand("AC_A", 1)) && trial.SaveJson() == before, "AC bus cannot become a CM DC export input");

trial.FixedStep(.37); var saved = trial.SaveJson(); trial.FixedStep(3.11); var replay = trial.SaveJson();
trial.LoadJson(saved); trial.FixedStep(3.11);
Check(trial.SaveJson() == replay, "Export demand and all ledger categories replay with fractional time");
void RejectSave(Action<JsonNode> corrupt, string why)
{ var bad = JsonNode.Parse(saved)!; corrupt(bad); var prior = trial.SaveJson(); Check(Reject(() => trial.LoadJson(bad.ToJsonString())) && trial.SaveJson() == prior, why); }
RejectSave(s => s["accounting"] = null, "Missing ledger rejects before live state changes");
RejectSave(s => s["schemaVersion"] = 1, "Pre-ledger save schema rejects explicitly");
RejectSave(s => s["accounting"]!["cmExport"] = null, "Missing subtotal rejects atomically");
RejectSave(s => s["accounting"]!["cmExport"]!["ah"] = -1, "Negative ledger charge rejects atomically");
RejectSave(s => s["accounting"]!["cmExport"]!["wh"] = 0, "Nonconserved ledger energy rejects atomically");
RejectSave(s => s["accounting"]!["cmExport"]!["ah"] = 0, "Nonconserved ledger charge rejects atomically");
RejectSave(s => s["accounting"]!["cmExportSourceBusId"] = "AC_B", "Foreign saved export bus rejects atomically");
RejectSave(s => s["accounting"]!["cmExportDemandA"] = -1, "Negative saved export demand rejects atomically");
RejectSave(s => s["accounting"]!["unclassifiedAggregate"]!["ah"] = 1, "Component save cannot inject aggregate consumption");
foreach (var field in new[] { "lmEquipment", "cmExport", "syntheticFault", "unclassifiedAggregate", "cmExportSourceBusId", "cmExportDemandA" })
    RejectSave(s => s["accounting"]!.AsObject().Remove(field), "Omitted ledger " + field + " rejects atomically");
foreach (var category in new[] { "lmEquipment", "cmExport", "syntheticFault", "unclassifiedAggregate" })
    foreach (var field in new[] { "ah", "wh" })
        RejectSave(s => s["accounting"]![category]!.AsObject().Remove(field), "Omitted " + category + " " + field + " rejects atomically");
RejectSave(s => {
    // Change source and ledger identically so conservation alone would pass.
    s["batteries"]!["BAT1"]!["consumedWh"] = s["batteries"]!["BAT1"]!["consumedWh"]!.GetValue<double>() + 100;
    s["accounting"]!["cmExport"]!["wh"] = s["accounting"]!["cmExport"]!["wh"]!.GetValue<double>() + 100;
}, "Conserved but physically impossible source energy rejects atomically");
RejectSave(s => {
    s["batteries"]!["BAT1"]!["consumedWh"] = 0;
    s["accounting"]!["cmExport"]!["wh"] = 0;
    s["accounting"]!["lmEquipment"]!["wh"] = 0;
    s["accounting"]!["syntheticFault"]!["wh"] = 0;
    foreach (var b in s["batteries"]!.AsObject()) b.Value!["consumedWh"] = 0;
}, "Conserved zero energy with positive delivered charge rejects atomically");
RejectSave(s => {
    var change = 400.0;
    s["batteries"]!["BAT1"]!["consumedAh"] = s["batteries"]!["BAT1"]!["consumedAh"]!.GetValue<double>() + change;
    s["batteries"]!["BAT1"]!["consumedWh"] = s["batteries"]!["BAT1"]!["consumedWh"]!.GetValue<double>() + change * 30;
    s["accounting"]!["cmExport"]!["ah"] = s["accounting"]!["cmExport"]!["ah"]!.GetValue<double>() + change;
    s["accounting"]!["cmExport"]!["wh"] = s["accounting"]!["cmExport"]!["wh"]!.GetValue<double>() + change * 30;
    s["initialTotalAh"] = s["initialTotalAh"]!.GetValue<double>() + change;
}, "Conserved source history exceeding rated capacity rejects atomically");
var aggregateSave = aggregate.SaveJson(); var aggregateBad = JsonNode.Parse(aggregateSave)!;
aggregateBad["accounting"]!["cmExportDemandA"] = 7;
Check(Reject(() => aggregate.LoadJson(aggregateBad.ToJsonString())) && aggregate.SaveJson() == aggregateSave, "Saved aggregate-plus-export ambiguity rejects atomically");
trial.ApplyPreset("fixture_power");
Near(trial.GetSnapshot().Accounting!.Source.ConsumedAh, 0, "Preset resets source ledger epoch");
Near(trial.GetSnapshot().Accounting!.CmExportDemandA, 0, "Preset clears explicit export scenario");
Conserved(trial, "Fresh accounting epoch");

var report = new { schemaVersion = 1, result = failures.Count == 0 ? "PASS" : "FAIL", checks, failures,
    kind = "LM source-boundary accounting with separate known equipment, CM export, synthetic faults and unclassified aggregate; independent synthetic fixtures",
    electricalSha256 = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(electrical))),
    controlsSha256 = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(inventory))),
    saveSchemaVersion = 2, completeFlightValidation = false, historicalTransferBoundaryResolved = false, restoredCmChargeModeled = false, headsetTested = false };
var reportPath = args.FirstOrDefault(a => a.StartsWith("--report="))?[9..] ?? Path.Combine(root.FullName, "output/electrical-accounting-tests.json");
File.WriteAllText(reportPath, JsonSerializer.Serialize(report, ElectricalSimulation.JsonOptions));
Console.WriteLine($"Electrical accounting verification: {report.result}; {checks} checks; {failures.Count} failures.");
Environment.ExitCode = failures.Count == 0 ? 0 : 1;
