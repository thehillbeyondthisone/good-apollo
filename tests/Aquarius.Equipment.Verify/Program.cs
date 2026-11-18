using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using Aquarius.Sim;

var root = new DirectoryInfo(Environment.CurrentDirectory);
while (root != null && !File.Exists(Path.Combine(root.FullName,"reference/electrical.json"))) root = root.Parent;
if (root == null) throw new InvalidOperationException("Run from the project.");
var electrical = File.ReadAllText(Path.Combine(root.FullName,"reference/electrical.json"));
var inventory = File.ReadAllText(Path.Combine(root.FullName,"reference/controls.json"));
var checks = 0;
var failures = new List<string>();
void Check(bool value, string message) { checks++; if (!value) { failures.Add(message); Console.Error.WriteLine("FAIL: "+message); } }
void Near(double actual, double expected, string why, double tolerance = 1e-7) => Check(Math.Abs(actual-expected) <= tolerance, $"{why}: {actual:R} versus {expected:R}");
bool Reject(Action action) { try { action(); return false; } catch (ArgumentException) { return true; } }
double DcCurrent(ElectricalSnapshot s) => s.Buses.Where(b => b.Id.EndsWith("_DC")).Sum(b => b.CurrentA);
ElectricalSimulation Actual() { var s = ElectricalSimulation.FromJson(electrical,inventory); s.ApplyPreset("sourced_equipment_checkout"); return s; }

// Exercise the sourced catalog individually, including every declared switch
// condition and supply path. Source watts are not derived from breaker ratings.
var data = JsonSerializer.Deserialize<ElectricalDefinition>(electrical,ElectricalSimulation.JsonOptions)!;
Check(data.EquipmentLoads.Length > 0,"An actual source-qualified catalog is present");
var actual = Actual();
Check(actual.GetSnapshot().LoadModel == "sourced_components" && !actual.GetSnapshot().CompleteEquipmentLoadCoverage,"Known-load scope is explicit");
Check(actual.GetSnapshot().Loads.All(l => !l.Id.StartsWith("aggregate_")),"Aggregate calibration is never added to sourced equipment");
foreach (var load in data.EquipmentLoads)
{
    var s = Actual();
    foreach (var req in load.SwitchRequirements) Check(s.SetControl(req.ControlId,req.AllowedPositions[0]),load.Id+": operating selector is modeled");
    foreach (var id in load.BreakerIds) s.SetControl(id,"PUSHED");
    var snapshot = s.GetSnapshot();
    var measured = snapshot.Loads.Single(l => l.Id == load.Id);
    Check(measured.Powered && measured.SourceId == load.SourceId,load.Id+": energized with its source evidence");
    var voltage = snapshot.Buses.Single(b => b.Id == load.BusId).VoltageV;
    Near(measured.CurrentA,load.CurrentA ?? load.PowerW!.Value/voltage,load.Id+": sourced operating draw");
    foreach (var id in load.BreakerIds)
    {
        s.SetControl(id,"PULLED");
        Near(s.GetSnapshot().Loads.Single(l => l.Id == load.Id).CurrentA,0,load.Id+": disconnected supply removes this load");
        s.SetControl(id,"PUSHED");
    }
    foreach (var req in load.SwitchRequirements)
    {
        var off = snapshot.ControlPositions.Keys.Contains(req.ControlId)
            ? JsonNode.Parse(inventory)!["controls"]!.AsArray().Single(c => (string?)c!["id"] == req.ControlId)!["positions"]!.AsArray()
                .Select(v => v!.GetValue<string>()).FirstOrDefault(p => !req.AllowedPositions.Contains(p)) : null;
        if (off == null) continue;
        s.SetControl(req.ControlId,off);
        Near(s.GetSnapshot().Loads.Single(l => l.Id == load.Id).CurrentA,0,load.Id+": off-selector removes the load");
        s.SetControl(req.ControlId,req.AllowedPositions[0]);
    }
}

// Controlled electrical fixtures establish accounting independently of the
// real catalog. These input watts and gate mappings are test inputs only.
var fixture = JsonNode.Parse(electrical)!;
fixture["equipmentLoads"] = JsonSerializer.SerializeToNode(new[] {
    new EquipmentLoadDefinition { Id="fixture_dc",BusId="CDR_DC",BreakerIds=["p11_cb_r04_c19"],PowerW=90,SourceId="TEST_ONLY",Qualification="Synthetic accounting fixture",SwitchRequirements=[new(){ControlId="p14_power_temp_mon",AllowedPositions=["BAT 1"]}] },
    new EquipmentLoadDefinition { Id="fixture_ac",BusId="AC_B",BreakerIds=["p11_cb_r01_c04"],PowerW=23,SourceId="TEST_ONLY",Qualification="Synthetic accounting fixture" }
},ElectricalSimulation.JsonOptions);
var fp = fixture["presets"]!.AsArray().Single(p => (string?)p!["id"] == "electrical_checkout")!.DeepClone();
fp["id"]="fixture_power"; fp["loadModel"]="sourced_components"; fp["aggregateCurrentA"]=0;
fixture["presets"]!.AsArray().Add(fp);
var fixtureJson = fixture.ToJsonString();
ElectricalSimulation Fixture() { var s=ElectricalSimulation.FromJson(fixtureJson,inventory); s.ApplyPreset("fixture_power"); return s; }
var trial = Fixture();
Near(DcCurrent(trial.GetSnapshot()),113.0/30,"90WDC +23WAC reaches DC sources once");
Near(trial.GetSnapshot().Batteries.Sum(b => b.CurrentA),113.0/30,"Source current equals bus input demand");
trial.FixedStep(3600);
Near(trial.GetSnapshot().ConsumedWh,113,"One hour conserves DC and AC real energy",1e-6);
Near(trial.GetSnapshot().ConsumedAh,113.0/30,"One hour conserves source charge");
trial.SetControl("p14_power_temp_mon","BAT 2");
Near(DcCurrent(trial.GetSnapshot()),23.0/30,"Operating gate removes only its own load");
trial.SetControl("p11_cb_r01_c04","PULLED");
Near(DcCurrent(trial.GetSnapshot()),0,"Removing both loads gives zero known demand");
trial=Fixture();
trial.SetControl("p11_cb_r05_c10","PULLED");
Near(DcCurrent(trial.GetSnapshot()),3,"Inverter supply interruption removes AC input demand");
trial=Fixture();
foreach (var number in Enumerable.Range(1,4))
{
    var owner=number<3?"se":"cdr";
    trial.SetControl($"p14_{owner}_bat_{number}_hi_voltage","OFF/RESET");
    trial.SetControl($"p14_{owner}_bat_{number}_low_voltage","ON");
}
Near(DcCurrent(trial.GetSnapshot()),113.0/28,"Constant-power loads draw more current at the low tap");
trial.FixedStep(3600);
Near(trial.GetSnapshot().ConsumedWh,113,"Low-tap conversion conserves real energy",1e-6);
trial=Fixture();
trial.InjectBranchFault("p11_cb_r04_c19",5);
trial.FixedStep(.25);
Check(trial.GetSnapshot().Breakers.Single(b => b.ControlId=="p11_cb_r04_c19").Tripped,"Operating load plus fault trips the protective surrogate");
Near(DcCurrent(trial.GetSnapshot()),23.0/30,"Tripped branch removes operating demand and fault together");
trial=Fixture(); trial.InjectBranchFault("p11_cb_r05_c10",29.5); trial.FixedStep(.25);
Check(trial.GetSnapshot().Breakers.Single(b => b.ControlId=="p11_cb_r05_c10").Tripped,"Inverter input includes its own fault plus converted AC demand");
trial=Fixture(); trial.InjectBranchFault("p11_cb_r01_c10",3); trial.FixedStep(.25);
var feeder=trial.GetSnapshot().Breakers.Single(b=>b.ControlId=="p11_cb_r01_c10");
Check(!feeder.Tripped,"A3A AC-feeder fault plus0.2A equipment stays below its5A rating");
Near(feeder.CurrentA,3.2,"AC-feeder demand is counted once when its own fault is on that bus");
trial.InjectBranchFault("p11_cb_r01_c10",4.9); trial.FixedStep(.25);
Check(trial.GetSnapshot().Breakers.Single(b=>b.ControlId=="p11_cb_r01_c10").Tripped,"AC-feeder fault plus downstream operating load trips above5A");
var feederFixture=JsonNode.Parse(fixtureJson)!;
feederFixture["equipmentLoads"]![1]!["breakerIds"]=JsonSerializer.SerializeToNode(new[]{"p11_cb_r01_c10"});
var feederTrial=ElectricalSimulation.FromJson(feederFixture.ToJsonString(),inventory); feederTrial.ApplyPreset("fixture_power");
Near(feederTrial.GetSnapshot().Breakers.Single(b=>b.ControlId=="p11_cb_r01_c10").CurrentA,.2,"An operating load directly on an AC feeder is also counted once");

// Save replay includes the selected accounting mode. Invalid reference/data or
// a mode that double-counts aggregate demand must not mutate a running trial.
actual=Actual(); actual.FixedStep(.37);
var saved=actual.SaveJson();
actual.FixedStep(3.1); var replay=actual.SaveJson();
actual.LoadJson(saved); actual.FixedStep(3.1);
Check(actual.SaveJson()==replay,"Sourced load mode has deterministic fractional-time replay");
var before=actual.SaveJson();
var bad=JsonNode.Parse(saved)!;bad["loadModel"]="invented";
Check(Reject(()=>actual.LoadJson(bad.ToJsonString())) && actual.SaveJson()==before,"Foreign saved load model rejects atomically");
bad=JsonNode.Parse(saved)!;bad["aggregateCurrent"]=12;
Check(Reject(()=>actual.LoadJson(bad.ToJsonString())) && actual.SaveJson()==before,"Saved aggregate plus component double-counting rejects atomically");
foreach(var field in new[]{"busId","sourceId","qualification","powerW","breakerIds","switchRequirements"})
{
    var broken=JsonNode.Parse(fixtureJson)!;
    broken["equipmentLoads"]![0]![field]=field switch {
        "busId"=>JsonValue.Create("FOREIGN"),"sourceId" or "qualification"=>JsonValue.Create(""),
        "powerW"=>JsonValue.Create(-1),"breakerIds"=>JsonSerializer.SerializeToNode(new[]{"p11_cb_r01_c04"}),
        _=>JsonSerializer.SerializeToNode(new[]{new{controlId="foreign_control",allowedPositions=new[]{"ON"}}})};
    Check(Reject(()=>ElectricalSimulation.FromJson(broken.ToJsonString(),inventory)),"Invalid equipment "+field+" rejected");
}
var nullLoad=JsonNode.Parse(fixtureJson)!;nullLoad["equipmentLoads"]![0]=null;
Check(Reject(()=>ElectricalSimulation.FromJson(nullLoad.ToJsonString(),inventory)),"Null equipment row rejects cleanly");
var nullCondition=JsonNode.Parse(fixtureJson)!;nullCondition["equipmentLoads"]![0]!["switchRequirements"]![0]=null;
Check(Reject(()=>ElectricalSimulation.FromJson(nullCondition.ToJsonString(),inventory)),"Null operating-state row rejects cleanly");
var report=new {schemaVersion=1,result=failures.Count==0?"PASS":"FAIL",checks,failures,
    kind="Source catalog gates and independent DC/AC accounting fixtures",sourceLoads=data.EquipmentLoads.Length,
    electricalSha256=Convert.ToHexStringLower(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(electrical))),
    controlsSha256=Convert.ToHexStringLower(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(inventory))),
    completeFlightValidation=false,headsetTested=false};
var reportPath=args.FirstOrDefault(a=>a.StartsWith("--report="))?[9..] ?? Path.Combine(root.FullName,"output/equipment-load-tests.json");
File.WriteAllText(reportPath,JsonSerializer.Serialize(report,ElectricalSimulation.JsonOptions));
Console.WriteLine($"Equipment load verification: {report.result}; {checks} checks; {failures.Count} failures.");
Environment.ExitCode=failures.Count==0?0:1;
