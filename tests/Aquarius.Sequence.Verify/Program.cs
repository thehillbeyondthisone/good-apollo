using System.Text.Json;
using System.Text.Json.Nodes;
using Aquarius.Sim;

var root=new DirectoryInfo(Environment.CurrentDirectory);
while(root != null && !File.Exists(Path.Combine(root.FullName,"reference/electrical.json"))) root=root.Parent;
if(root == null) throw new InvalidOperationException("Run from the project.");
string Read(string p)=>File.ReadAllText(Path.Combine(root.FullName,p));
var electrical=Read("reference/electrical.json");
var inventory=Read("reference/controls.json");
var sequenceJson=Read("reference/electrical-powerdown-sequence.json");
var sequence=ElectricalPowerDownSequence.FromJson(sequenceJson,inventory);
var checks=0;
var failures=new List<string>();
void Check(bool ok,string why) { checks++; if(!ok) { failures.Add(why); Console.Error.WriteLine("FAIL: "+why); } }
bool Reject(Action action) { try { action(); return false; } catch(ArgumentException) { return true; } }
ElectricalSimulation Sim()=>ElectricalSimulation.FromJson(electrical,inventory);
var sim=Sim();
var replay=new ElectricalSequenceReplay(sim,sequence);
Check(!replay.Active && replay.NextEvent() == null,"An inactive guided review cannot apply commands");
replay.Start();
Check(replay.Active && replay.CurrentIndex==0,"Start selects first unapplied event");
Check(sim.GetSnapshot().LoadModel=="sourced_components" && !sim.GetSnapshot().CompleteEquipmentLoadCoverage,"Partial source equipment seed remains explicit");
Check(sim.GetSnapshot().Loads.All(l=>!l.Id.StartsWith("aggregate_")),"No aggregate target added to equipment replay");
string Position(string id)=>sim.GetSnapshot().ControlPositions[id];
var trace=new List<object>();
while(replay.CurrentIndex<sequence.Events.Length)
{
    var before=sim.SaveJson();
    var ev=replay.NextEvent()!;
    var s=sim.GetSnapshot();
    Check(s.SimulationTimeSeconds==0 && s.ConsumedAh==0,"Historical GET never advances live simulation: "+ev.Id);
    foreach(var command in ev.Actions) Check(s.ControlPositions[command.ControlId]==command.Position,"Applied exact sourced command "+ev.Id+"/"+command.ControlId);
    if(ev.Actions.Length==0) Check(sim.SaveJson()==before,"Read-up/summary marker does not alter EPS: "+ev.Id);
    Check(Enumerable.Range(1,4).All(n=>Position($"p16_cb_r04_c0{n}")=="PUSHED"),"Heater branches, including sealed Quad1, stay closed: "+ev.Id);
    if(ev.Id=="final_readup") Check(Position("p11_cb_r04_c19")=="PUSHED","Read-up does not prematurely remove PGNS");
    if(ev.Id=="atca_pgns") Check(Enumerable.Range(2,4).All(n=>Position($"p11_cb_r02_c0{n}")=="PULLED"),"Panel11 TCA removals precede final procedure read-up");
    if(ev.Id=="final_execution")
    {
        Check(Position("p11_cb_r04_c19")=="PULLED" && Position("p11_cb_r04_c21")=="PULLED" && Position("p11_cb_r04_c20")=="PUSHED","DSKY and IMU operate off while IMU standby remains");
        Check(Position("p11_cb_r04_c15")=="PULLED" && Position("p16_cb_r03_c02")=="PUSHED","Only LMP audio branch retained in reviewed pair");
    }
    trace.Add(new {ev.Id,ev.Get,ev.EvidenceKind,knownDcCurrentA=s.Buses.Where(b=>b.Id.EndsWith("_DC")).Sum(b=>b.CurrentA),actions=ev.Actions.Length});
}
Check(replay.NextEvent()==null && replay.CurrentIndex==sequence.Events.Length,"Completion is stable and does not wrap");
Check(Position("p12_pwr_ampl")=="PRIM" && Position("p16_cb_r03_c05")=="PULLED","PRIMARY selection does not bypass open amplifier branch");
Check(Position("p16_cb_r02_c01")=="PULLED" && Position("p16_cb_r02_c02")=="PULLED","Later TRACK/FLOOD amendment overrides initial closed branches");
Check(Enumerable.Range(1,4).All(n=>Position($"p3_rcs_sys_a_b_2_quad_{n}")=="OFF"),"Heater selectors are independently OFF");

// Cursor restoration is staged independently of EPS and binds exact source data.
var state=replay.GetStateJson();
var eps=sim.SaveJson();
replay.ValidateStateJson(state);
Check(replay.GetStateJson()==state && sim.SaveJson()==eps,"Validate changes neither cursor nor live EPS");
var restoredSim=Sim(); var restored=new ElectricalSequenceReplay(restoredSim,sequence);
restoredSim.LoadJson(eps); restored.RestoreStateJson(state);
Check(restored.CurrentIndex==replay.CurrentIndex && restored.Active && restoredSim.SaveJson()==eps,"Cursor and EPS restore independently");
foreach(var mutate in new Action<JsonNode>[] { n=>n["currentIndex"]=-1,n=>n["currentIndex"]=1000,n=>n["sequenceSha256"]="wrong",n=>n["schemaVersion"]=2,n=>n["active"]=false })
{
    var bad=JsonNode.Parse(state)!; mutate(bad);
    Check(Reject(()=>replay.RestoreStateJson(bad.ToJsonString())),"Reject incompatible cursor");
    Check(replay.GetStateJson()==state && sim.SaveJson()==eps,"Bad cursor leaves live state unchanged");
}
Check(Reject(()=>replay.RestoreStateJson("{")),"Reject malformed cursor JSON");
foreach(var field in new[] {"schemaVersion","sequenceSha256","active","currentIndex"})
{
    var bad=JsonNode.Parse(state)!.AsObject(); bad.Remove(field);
    Check(Reject(()=>replay.RestoreStateJson(bad.ToJsonString())),"Reject missing replay field: "+field);
    Check(replay.GetStateJson()==state && sim.SaveJson()==eps,"Missing field leaves cursor and EPS intact: "+field);
}
replay.Cancel();
Check(!replay.Active && replay.CurrentIndex==0 && sim.SaveJson()==eps,"Cancel leaves electrical state intact");

// Replay on an electrical fork reproduces both exact controls and fixed-step accounting.
var aSim=Sim(); var a=new ElectricalSequenceReplay(aSim,sequence); a.Start();
for(var n=0;n<9;n++) a.NextEvent();
aSim.FixedStep(.37);
var midpointEps=aSim.SaveJson(); var midpointCursor=a.GetStateJson();
var bSim=Sim(); var b=new ElectricalSequenceReplay(bSim,sequence); bSim.LoadJson(midpointEps); b.RestoreStateJson(midpointCursor);
while(a.NextEvent()!=null) aSim.FixedStep(.13);
while(b.NextEvent()!=null) bSim.FixedStep(.13);
Check(aSim.SaveJson()==bSim.SaveJson() && a.GetStateJson()==b.GetStateJson(),"Mid-sequence restore reproduces exact fractional-time continuation");

// Failure of a later command rejects an entire multi-control event before any edit.
var atomicSim=Sim(); var atomic=new ElectricalSequenceReplay(atomicSim,sequence); atomic.Start();
while(atomic.CurrentIndex<8) atomic.NextEvent();
atomicSim.InjectBranchFault("p16_cb_r03_c02",100); atomicSim.FixedStep(.25);
var atomicBefore=atomicSim.SaveJson(); var atomicCursor=atomic.GetStateJson();
Check(Reject(()=>atomic.NextEvent()),"A tripped retained supply rejects the grouped event");
Check(atomicSim.SaveJson()==atomicBefore && atomic.GetStateJson()==atomicCursor,"Rejected event changes neither earlier commands nor cursor");

foreach(var mutate in new Action<JsonNode>[] {
    n=>n["inventorySha256"]="wrong",
    n=>n["completeFlownConfiguration"]=true,
    n=>n["independentFlightValidationPassed"]=true,
    n=>n["events"]![0]!["getSeconds"]=0,
    n=>n["events"]![1]!["actions"]![0]!["position"]="UNKNOWN",
    n=>n["events"]![1]!["evidenceKind"]="readup_only"
})
{
    var bad=JsonNode.Parse(sequenceJson)!; mutate(bad);
    Check(Reject(()=>ElectricalPowerDownSequence.FromJson(bad.ToJsonString(),inventory)),"Reject malformed or falsely promoted sequence data");
}
var report=new {result=failures.Count==0?"PASS":"FAIL",checks,failures,
    electricalSha256=Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(electrical))),
    controlsSha256=Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(inventory))),
    sequenceSha256=sequence.SequenceSha256,events=sequence.Events.Length,actions=sequence.Events.Sum(e=>e.Actions.Length),
    completeFlownConfiguration=false,independentFlightValidationPassed=false,simulationTimePolicy="Guided NextEvent does not advance time; GET is source label only",trace};
File.WriteAllText(Path.Combine(root.FullName,"output/electrical-sequence-tests.json"),JsonSerializer.Serialize(report,ElectricalSimulation.JsonOptions)+"\n");
Console.WriteLine(JsonSerializer.Serialize(new {report.result,checks,failures,report.events,report.actions}));
return failures.Count==0?0:1;
