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
void Near(double actual, double expected, string why, double tolerance = 1e-8) =>
    Check(double.IsFinite(actual) && Math.Abs(actual - expected) <= tolerance, $"{why}: {actual:R} vs {expected:R}");
bool Reject(Action action) { try { action(); return false; } catch (ArgumentException) { return true; } catch (InvalidOperationException) { return true; } }
void Compare(JsonElement actual, JsonElement expected, string path)
{
    if (actual.ValueKind != expected.ValueKind) { Check(false, path + ": value kind"); return; }
    switch (actual.ValueKind)
    {
        case JsonValueKind.Object:
            Check(actual.EnumerateObject().Count() == expected.EnumerateObject().Count(), path + ": property count");
            foreach (var p in expected.EnumerateObject())
                if (actual.TryGetProperty(p.Name, out var other)) Compare(other, p.Value, path + "." + p.Name);
                else Check(false, path + ": missing " + p.Name);
            break;
        case JsonValueKind.Array:
            Check(actual.GetArrayLength() == expected.GetArrayLength(), path + ": array length");
            for (var i = 0; i < Math.Min(actual.GetArrayLength(), expected.GetArrayLength()); i++) Compare(actual[i], expected[i], path + "[" + i + "]");
            break;
        case JsonValueKind.Number:
            var value = expected.GetDouble();
            Near(actual.GetDouble(), value, path, 1e-8 + 1e-10 * Math.Abs(value));
            break;
        default: Check(actual.GetRawText() == expected.GetRawText(), path); break;
    }
}
void Same(ElectricalSimulation accelerated, ElectricalSimulation ordinary, string why) =>
    Compare(JsonSerializer.SerializeToElement(accelerated.GetSnapshot(), ElectricalSimulation.JsonOptions),
        JsonSerializer.SerializeToElement(ordinary.GetSnapshot(), ElectricalSimulation.JsonOptions), why);

// Independent synthetic loads permit analytical expectations without borrowing
// any historical current target as equipment input.
var fixture = JsonNode.Parse(electrical)!;
fixture["equipmentLoads"] = JsonSerializer.SerializeToNode(new[] {
    new EquipmentLoadDefinition { Id="history_dc_cdr", BusId="CDR_DC", BreakerIds=["p11_cb_r04_c19"], PowerW=90, SourceId="TEST_ONLY", Qualification="Independent history fixture" },
    new EquipmentLoadDefinition { Id="history_dc_lmp", BusId="LMP_DC", BreakerIds=["p16_cb_r04_c08"], PowerW=30, SourceId="TEST_ONLY", Qualification="Independent history fixture" },
    new EquipmentLoadDefinition { Id="history_ac", BusId="AC_B", BreakerIds=["p11_cb_r01_c04"], PowerW=23, SourceId="TEST_ONLY", Qualification="Independent history fixture" }
}, ElectricalSimulation.JsonOptions);
var powered = fixture["presets"]!.AsArray().Single(p => (string?)p!["id"] == "electrical_checkout")!.DeepClone();
powered["id"] = "history_fixture"; powered["loadModel"] = "sourced_components"; powered["aggregateCurrentA"] = 0;
fixture["presets"]!.AsArray().Add(powered);
var fixtureJson = fixture.ToJsonString();
ElectricalSimulation Fixture(string? json = null) { var s = ElectricalSimulation.FromJson(json ?? fixtureJson, inventory); s.ApplyPreset("history_fixture"); return s; }
Dictionary<string, double> Charge(double value = 100) => data.Batteries.ToDictionary(b => b.Id, b => Math.Min(value, b.CapacityAh), StringComparer.Ordinal);
void Isolate(ElectricalSimulation sim) { foreach (var tie in data.Ties) foreach (var id in tie.BreakerIds) Check(sim.SetControl(id, "PULLED"), "isolate tie " + id); }

var initial = Fixture();
var before = initial.SaveJson();
var bad = Charge(); bad.Remove("BAT6");
Check(Reject(() => initial.SetInitialBatteryRemainingAh(bad)), "missing initial source rejected");
Check(before == initial.SaveJson(), "missing initial source atomic");
bad = Charge(); bad["FOREIGN"] = 1;
Check(Reject(() => initial.SetInitialBatteryRemainingAh(bad)), "foreign initial source rejected");
Check(before == initial.SaveJson(), "foreign initial source atomic");
foreach (var value in new[] { -1.0, 400.01, double.NaN, double.PositiveInfinity })
{
    bad = Charge(); bad["BAT1"] = value;
    Check(Reject(() => initial.SetInitialBatteryRemainingAh(bad)), "invalid initial source rejected " + value);
    Check(before == initial.SaveJson(), "invalid initial source atomic " + value);
}
var declared = Charge(); declared["BAT1"] = 20; declared["BAT5"] = 0;
initial.SetInitialBatteryRemainingAh(declared);
Near(initial.GetSnapshot().InitialTotalAh, declared.Values.Sum(), "declared initial total");
foreach (var b in initial.GetSnapshot().Batteries) Near(b.RemainingAh, declared[b.Id], "declared initial " + b.Id);
var loaded = Fixture(); loaded.LoadJson(initial.SaveJson()); Same(initial, loaded, "initial charge save roundtrip");
initial.AdvanceStableHistory(.01);
before = initial.SaveJson();
Check(Reject(() => initial.SetInitialBatteryRemainingAh(Charge())), "fractional elapsed time blocks reinitialization");
Check(before == initial.SaveJson(), "elapsed reinitialization rejection atomic");

var fast = Fixture(); var slow = Fixture();
foreach (var s in new[] { fast, slow }) { s.SetInitialBatteryRemainingAh(Charge()); Isolate(s); s.SetCmExportDemand("LMP_DC", 2); }
foreach (var seconds in new[] { 17.13, 282.12, 300.01 })
{
    fast.AdvanceStableHistory(seconds); slow.FixedStep(seconds); Same(fast, slow, "isolated sources " + seconds);
}
var checkpoint = fast.SaveJson();
loaded = Fixture(); loaded.LoadJson(checkpoint);
loaded.AdvanceStableHistory(99.99); fast.AdvanceStableHistory(99.99); slow.FixedStep(99.99);
Same(fast, slow, "fractional continuation"); Same(loaded, fast, "history checkpoint continuation");

fast = Fixture(); slow = Fixture();
foreach (var s in new[] { fast, slow })
{
    s.SetInitialBatteryRemainingAh(Charge()); Isolate(s);
    foreach (var b in data.Batteries.Where(b => b.Stage == "descent" && b.NormalBusId == "LMP_DC"))
    { s.SetControl(b.HighControlId, "OFF/RESET"); s.SetControl(b.LowControlId, "ON"); }
    s.SetCmExportDemand("LMP_DC", 2);
}
fast.AdvanceStableHistory(600); slow.FixedStep(600); Same(fast, slow, "different tap voltages");
Near(fast.GetSnapshot().Accounting!.CmExport.ConsumedWh, 2 * 28.0 / 6, "export uses LMP low tap", 1e-7);

fast = Fixture(); slow = Fixture();
foreach (var s in new[] { fast, slow })
{
    var small = Charge(0); small["BAT1"] = .00001; small["BAT2"] = .00002;
    s.SetInitialBatteryRemainingAh(small);
    s.SetControl("p14_se_bat_2_hi_voltage", "OFF/RESET"); s.SetControl("p14_se_bat_2_low_voltage", "ON");
    s.SetCmExportDemand("LMP_DC", 2);
}
fast.AdvanceStableHistory(7.125); slow.FixedStep(7.125); Same(fast, slow, "subtick depletion and tap handoff");
Near(fast.GetSnapshot().ConsumedAh, .00003, "all depleted source charge consumed", 1e-12);
Check(fast.GetSnapshot().Batteries.All(b => b.RemainingAh == 0), "depleted bank is nonnegative");

// The high source empties within tick one. Its low-tap successor raises
// constant-power branch current above the test rating. Protection must wait
// until tick two, exactly as FixedStep does; it cannot fire mid-tick.
var tripFixture = JsonNode.Parse(fixtureJson)!;
tripFixture["equipmentLoads"] = JsonSerializer.SerializeToNode(new[] {
    new EquipmentLoadDefinition { Id="tap_trip", BusId="CDR_DC", BreakerIds=["p11_cb_r04_c19"], PowerW=30, SourceId="TEST_ONLY", Qualification="Synthetic protection boundary" }
}, ElectricalSimulation.JsonOptions);
tripFixture["breakers"]!.AsArray().Single(b => (string?)b!["controlId"] == "p11_cb_r04_c19")!["ratedCurrentA"] = 1.02;
fast = Fixture(tripFixture.ToJsonString()); slow = Fixture(tripFixture.ToJsonString());
foreach (var s in new[] { fast, slow })
{
    var small = Charge(0); small["BAT3"] = .00001; small["BAT4"] = 1;
    s.SetInitialBatteryRemainingAh(small); Isolate(s);
    s.SetControl("p14_cdr_bat_4_hi_voltage", "OFF/RESET"); s.SetControl("p14_cdr_bat_4_low_voltage", "ON");
}
fast.AdvanceStableHistory(.25); slow.FixedStep(.25); Same(fast, slow, "pre-trip exhaustion tick");
Check(!fast.GetSnapshot().Breakers.Single(b => b.ControlId == "p11_cb_r04_c19").Tripped, "new overload waits for next tick");
fast.AdvanceStableHistory(10); slow.FixedStep(10); Same(fast, slow, "post-exhaustion protection tick");
Check(fast.GetSnapshot().Breakers.Single(b => b.ControlId == "p11_cb_r04_c19").Tripped, "next tick trips overload");

fast = Fixture(); slow = Fixture();
foreach (var s in new[] { fast, slow }) s.InjectBranchFault("p11_cb_r04_c19", 20);
fast.AdvanceStableHistory(30); slow.FixedStep(30); Same(fast, slow, "initial synthetic overload");

// A whole stable day has a separate analytical check and does not depend on
// running the ordinary solver hundreds of thousands of times.
fast = Fixture(); fast.SetInitialBatteryRemainingAh(Charge()); fast.SetCmExportDemand("LMP_DC", 2);
fast.AdvanceStableHistory(86400);
Near(fast.GetSnapshot().SimulationTimeSeconds, 86400, "one day clock");
Near(fast.GetSnapshot().ConsumedAh, 24 * (143.0 / 30 + 2), "one day source Ah", 1e-8);
Near(fast.GetSnapshot().ConsumedWh, 24 * (143 + 60), "one day source Wh", 1e-7);
Near(fast.GetSnapshot().Accounting!.CmExport.ConsumedAh, 48, "one day separate export charge", 1e-8);
Near(fast.GetSnapshot().Accounting!.UnclassifiedAggregate.ConsumedAh, 0, "no aggregate history residual");
loaded = Fixture(); loaded.LoadJson(fast.SaveJson()); Same(loaded, fast, "one day saved ledger");
before = fast.SaveJson();
foreach (var seconds in new[] { -1.0, double.NaN, double.PositiveInfinity, 86400.01 })
{
    Check(Reject(() => fast.AdvanceStableHistory(seconds)), "invalid history duration rejected " + seconds);
    Check(before == fast.SaveJson(), "invalid history duration atomic " + seconds);
}

var report = new {
    schemaVersion=1, status=failures.Count == 0 ? "PASS" : "FAIL", checks, failures,
    electricalSha256=Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(electrical))),
    inventorySha256=Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(inventory))),
    scope="Electrical-only stable-span equivalence, explicit initial battery charge, protection/depletion boundaries and conserved ledgers. No historical flight validation is claimed."
};
var reportPath = Path.Combine(root.FullName, "output/electrical-history-tests.json");
Directory.CreateDirectory(Path.GetDirectoryName(reportPath)!);
File.WriteAllText(reportPath, JsonSerializer.Serialize(report, ElectricalSimulation.JsonOptions) + "\n");
Console.WriteLine(JsonSerializer.Serialize(new { report.status, checks, failures=failures.Count, report=reportPath }));
Environment.ExitCode = failures.Count == 0 ? 0 : 1;
