using System.Text.Json;
using System.Text.Json.Nodes;
using Aquarius.Sim;

var root = new DirectoryInfo(Environment.CurrentDirectory);
while (root != null && !File.Exists(Path.Combine(root.FullName,"reference","electrical.json"))) root=root.Parent;
if (root==null) throw new InvalidOperationException("Run from repository.");
var data=File.ReadAllText(Path.Combine(root.FullName,"reference","electrical.json"));
var inventory=File.ReadAllText(Path.Combine(root.FullName,"reference","controls.json"));
var checks=0;var failures=new List<string>();
void Check(bool condition,string message){checks++;if(!condition){failures.Add(message);Console.Error.WriteLine("FAIL "+message);}}
void Near(double actual,double expected,double tolerance,string message)=>Check(Math.Abs(actual-expected)<=tolerance,$"{message}: expected{expected:R}, actual{actual:R}");
bool Reject(Action action){try{action();return false;}catch(ArgumentException){return true;}}
ElectricalSimulation New(string preset="minimum_lifeboat_12a"){var s=ElectricalSimulation.FromJson(data,inventory);s.ApplyPreset(preset);return s;}
BusSnapshot Bus(ElectricalSimulation s,string id)=>s.GetSnapshot().Buses.Single(b=>b.Id==id);
var sim=New();
Check(sim.GetSnapshot().Breakers.Length==160,"All160 frozen breaker IDs have logical branches");
using(var parsed=JsonDocument.Parse(inventory))
{
 var expected=parsed.RootElement.GetProperty("controls").EnumerateArray().Where(c=>c.GetProperty("type").GetString()=="breaker").Select(c=>c.GetProperty("id").GetString()).Order().ToArray();
 Check(expected.SequenceEqual(sim.GetSnapshot().Breakers.Select(b=>b.ControlId).Order()),"EPS breakers exactly match frozen inventory");
}
Check(sim.GetSnapshot().Loads.All(l=>sim.GetSnapshot().Buses.Any(b=>b.Id==l.BusId)),"No declared load has an orphan bus");
var badData=JsonNode.Parse(data)!;badData["loads"]![0]!["busId"]="ORPHAN";
Check(Reject(()=>ElectricalSimulation.FromJson(badData.ToJsonString(),inventory)),"Orphan load definition rejected");
sim=New("cold_dark");sim.FixedStep(3600);
Near(sim.GetSnapshot().ConsumedAh,0,1e-12,"Cold-and-dark consumes no charge");
Check(sim.GetSnapshot().Buses.All(b=>!b.Powered),"Cold-and-dark has no energized bus");
Near(sim.GetSnapshot().Batteries.Sum(b=>b.RemainingAh),2192,1e-9,"Rated total capacity400*4+296*2");
sim=New();var first=sim.GetSnapshot();sim.FixedStep(3600);var after=sim.GetSnapshot();
Near(after.ConsumedAh,12,1e-8,"12A for1h conserves12Ah");
Near(after.ConsumedWh,360,1e-7,"Ideal30V12A for1h delivers360Wh");
Near(after.InitialTotalAh-after.Batteries.Sum(b=>b.RemainingAh),after.ConsumedAh,1e-7,"Charge balance closes");
Near(after.MeterValues["p14_amps"],6,1e-10,"Panel14 descent amp scale shows2x selected3A battery draw");
Near(Bus(sim,"CDR_DC").VoltageV,30,1e-10,"High-tap ideal bus is30V");
Check(sim.SetControl("p14_power_temp_mon","CDR BUS"),"Corrected source placard CDR BUS accepted");Check(!sim.GetSnapshot().MeterValid["p14_amps"],"AMPS reading invalid for bus selector per AOH");
Check(!sim.SetControl("p14_power_temp_mon","BUS"),"Fictitious standalone BUS position rejected");
sim=New("initial_powerdown_30a");sim.FixedStep(7200);Near(sim.GetSnapshot().ConsumedAh,60,1e-7,"30A2h consumes60Ah");
sim=New();
sim.SetControl("p14_cdr_bat_3_hi_voltage","OFF/RESET");sim.SetControl("p14_cdr_bat_4_hi_voltage","OFF/RESET");
Near(Bus(sim,"CDR_DC").VoltageV,30,1e-12,"Closed BAL LOADS pair permits opposite-bus feed");
sim.SetControl("p11_cb_r05_c03","PULLED");Near(Bus(sim,"CDR_DC").VoltageV,0,1e-12,"Opening one tie endpoint isolates unpowered CDR bus");
Near(Bus(sim,"LMP_DC").CurrentA,6,1e-12,"Isolated powered LMP bus retains its aggregate share");
sim.SetControl("p11_cb_r05_c04","PUSHED");sim.SetControl("p16_cb_r04_c16","PUSHED");
Near(Bus(sim,"CDR_DC").VoltageV,30,1e-12,"Emergency100A cross-bus tie restores unpowered bus");
sim=New();Check(!sim.SetControl("p14_se_bat_1_low_voltage","ON"),"ECA interlock refuses simultaneousHV/LV contactors");
sim.SetControl("p14_se_bat_1_hi_voltage","OFF/RESET");Check(sim.SetControl("p14_se_bat_1_low_voltage","ON"),"LV contactor accepted afterHV opens");
Near(sim.GetSnapshot().Batteries.Single(b=>b.Id=="BAT1").VoltageV,28,1e-12,"LV source reports coarse28V surrogate even while diode blocked");
sim.SetControl("p14_des_bats","DEAD FACE");Check(sim.GetSnapshot().Buses.Where(b=>b.Id.EndsWith("_DC")).All(b=>!b.Powered),"Deadface disconnects all descent feeds");
sim.SetControl("p14_bat_5_normal_se_feed","ON");Check(Bus(sim,"LMP_DC").Powered,"Ascent normal contactor powersLMP after deadface");

// CENTER is a physical detent, while the ECA contactors keep the last command.
// Exercise actual source connectivity, rather than merely comparing saved fields.
for (var number = 1; number <= 4; number++)
{
 var owner = number < 3 ? "se" : "cdr";
 var hi = $"p14_{owner}_bat_{number}_hi_voltage";
 var lo = $"p14_{owner}_bat_{number}_low_voltage";
 var batteryId = $"BAT{number}";
 bool Connected() => sim.GetSnapshot().Batteries.Single(b => b.Id == batteryId).Connected;
 sim = New();
 Check(sim.SetControl(hi,"CENTER") && Connected(),$"{batteryId} high-tap CENTER retains connected relay");
 Check(!sim.SetControl(lo,"ON"),$"{batteryId} high-tap relay blocks low ON even with high handle CENTER");
 Check(sim.SetControl(hi,"OFF/RESET") && sim.SetControl(hi,"CENTER") && !Connected(),$"{batteryId} high OFF remains disconnected after CENTER");
 Check(sim.SetControl(lo,"ON") && sim.SetControl(lo,"CENTER") && Connected(),$"{batteryId} low-tap CENTER retains connected relay");
 Near(sim.GetSnapshot().Batteries.Single(b=>b.Id==batteryId).VoltageV,28,1e-12,$"{batteryId} retained low-tap command selects28V");
 Check(!sim.SetControl(hi,"ON"),$"{batteryId} low-tap relay blocks high ON even with low handle CENTER");
 Check(sim.SetControl(lo,"OFF/RESET") && sim.SetControl(lo,"CENTER") && !Connected(),$"{batteryId} low OFF remains disconnected after CENTER");
}
sim=New();
Check(sim.SetControl("p14_des_bats","CENTER") && sim.GetSnapshot().Batteries.Count(b=>b.Stage=="descent"&&b.Connected)==4,"DES BATS CENTER retains prior CONNECT command");
Check(sim.SetControl("p14_des_bats","DEAD FACE") && sim.SetControl("p14_des_bats","CENTER") && sim.GetSnapshot().Batteries.All(b=>!b.Connected),"DES BATS CENTER retains prior DEAD FACE command");
Check(sim.SetControl("p14_des_bats","CONNECT") && sim.SetControl("p14_des_bats","CENTER") && sim.GetSnapshot().Batteries.Count(b=>b.Connected)==4,"DES BATS reconnect remains latched at CENTER");
foreach (var (controlId, busId) in new[] {
 ("p14_bat_5_normal_se_feed","LMP_DC"), ("p14_bat_5_back_up_cdr_feed","CDR_DC"),
 ("p14_bat_6_normal_cdr_feed","CDR_DC"), ("p14_bat_6_back_up_se_feed","LMP_DC") })
{
 sim=New("cold_dark");
 Check(sim.SetControl(controlId,"ON") && sim.SetControl(controlId,"CENTER") && Bus(sim,busId).Powered,$"{controlId} powers its sourced bus after CENTER");
 Check(sim.GetSnapshot().Buses.Where(b=>b.Id.EndsWith("_DC")&&b.Id!=busId).All(b=>!b.Powered),$"{controlId} does not energize the isolated opposite bus");
 var relaySave=sim.SaveJson();var relayRestore=New("cold_dark");relayRestore.LoadJson(relaySave);
 Check(Bus(relayRestore,busId).Powered && relayRestore.GetSnapshot().ControlPositions[controlId]=="CENTER",$"{controlId} restores retained power and released CENTER handle");
 Check(sim.SetControl(controlId,"OFF/RESET") && sim.SetControl(controlId,"CENTER") && !Bus(sim,busId).Powered,$"{controlId} retains OFF after CENTER");
 // Simulate saving while the command input is physically held.
 sim.SetControl(controlId,"ON");relayRestore.LoadJson(sim.SaveJson());
 Check(relayRestore.GetSnapshot().ControlPositions[controlId]=="CENTER"&&Bus(relayRestore,busId).Powered,$"{controlId} held ON restores released while retaining relay");
}
sim=New();sim.SetControl("p14_des_bats","DEAD FACE");
var deadfaceRestore=New();deadfaceRestore.LoadJson(sim.SaveJson());
Check(deadfaceRestore.GetSnapshot().ControlPositions["p14_des_bats"]=="CENTER" && deadfaceRestore.GetSnapshot().Batteries.All(b=>!b.Connected),"Held DEAD FACE restores released center with descent relays disconnected");
sim.SetControl("p14_des_bats","CONNECT");deadfaceRestore.LoadJson(sim.SaveJson());
Check(deadfaceRestore.GetSnapshot().ControlPositions["p14_des_bats"]=="CENTER" && deadfaceRestore.GetSnapshot().Batteries.Count(b=>b.Connected)==4,"Held CONNECT restores released center with descent relays connected");
sim=New();sim.SetControl("p14_se_bat_1_hi_voltage","CENTER");
sim.FixedStep(.125);var centerSave=sim.SaveJson();var centerRestore=New();centerRestore.LoadJson(centerSave);
Check(centerSave==centerRestore.SaveJson(),"Latched ECA save/load is byte-deterministic with fractional EPS time");
Check(!centerRestore.SetControl("p14_se_bat_1_low_voltage","ON"),"Restored high relay interlock still blocks low ON with high handle CENTER");
var centerBefore=sim.SaveJson();
void RejectLatchSave(Action<JsonNode> mutate,string label)
{
 var damaged=JsonNode.Parse(centerBefore)!;mutate(damaged);
 Check(Reject(()=>sim.LoadJson(damaged.ToJsonString())),label+" rejected");
 Check(sim.SaveJson()==centerBefore,label+" leaves whole EPS unchanged");
}
RejectLatchSave(s=>s["feedCommands"]!.AsObject().Remove("p14_se_bat_1_hi_voltage"),"Missing relay key");
RejectLatchSave(s=>s["feedCommands"]!["unknown_relay"]="ON","Foreign relay key");
RejectLatchSave(s=>s["feedCommands"]!["p14_se_bat_1_hi_voltage"]="CENTER","CENTER is not a retained relay command");
RejectLatchSave(s=>s["feedCommands"]!["p14_se_bat_1_hi_voltage"]="INVALID","Unknown relay state");
RejectLatchSave(s=>s["controls"]!["p14_se_bat_1_hi_voltage"]="OFF/RESET","Physical command disagrees with retained relay");
RejectLatchSave(s=>{s["controls"]!["p14_se_bat_1_low_voltage"]="CENTER";s["feedCommands"]!["p14_se_bat_1_low_voltage"]="ON";},"Both tap relays ON while both physical handles CENTER");
RejectLatchSave(s=>s["feedCommands"]=null,"Null relay state");
RejectLatchSave(s=>s["batteries"]!["BAT1"]=null,"Null saved battery");

sim=New("electrical_checkout");Near(Bus(sim,"AC_A").VoltageV,115,1e-12,"Selected inverter feeds115VAC busA");
sim.SetControl("p11_cb_r05_c10","PULLED");Check(!Bus(sim,"AC_A").Powered&&!Bus(sim,"AC_B").Powered,"Pulling inverter input breaker removes bothAC buses");
Check(Bus(sim,"CDR_DC").Powered,"Inverter isolation does not removeDC power");
sim=New("electrical_checkout");sim.InjectBranchFault("p11_cb_r01_c02",1);sim.FixedStep(3600);
Near(sim.GetSnapshot().ConsumedWh,475,1e-6,"Ideal inverter conserves115W AC fault-load plus360W aggregate for1h");
sim=New("electrical_checkout");sim.InjectBranchFault("p11_cb_r01_c02",3);sim.FixedStep(.25);
Check(sim.GetSnapshot().Breakers.Single(b=>b.ControlId=="p11_cb_r01_c02").Tripped,"AC branch fault trips its2A surrogate breaker");
sim=New();Check(sim.GetSnapshot().PoweredControls["p4_dsky_verb"],"DSKY branch initially energized");
sim.InjectBranchFault("p11_cb_r04_c19",6);sim.FixedStep(.25);
Check(!sim.GetSnapshot().Breakers.Single(b=>b.ControlId=="p11_cb_r04_c19").Tripped,"6A fault remains below corrected7.5A LGC/DSKY breaker rating");
sim.InjectBranchFault("p11_cb_r04_c19",8);sim.FixedStep(.25);var tripped=sim.GetSnapshot().Breakers.Single(b=>b.ControlId=="p11_cb_r04_c19");
Check(tripped.Tripped&&!tripped.Closed&&!tripped.Powered,"8A fault trips corrected7.5A LGC/DSKY surrogate breaker");
Check(!sim.GetSnapshot().PoweredControls["p4_dsky_verb"],"Tripped LGC/DSKY breaker deenergizes mappedDSKY controls");
Check(!sim.SetControl("p11_cb_r04_c19","PUSHED"),"Tripped breaker requires manual pull/reset before push");
Check(sim.SetControl("p11_cb_r04_c19","PULLED")&&sim.SetControl("p11_cb_r04_c19","PUSHED"),"Manual breaker reset accepted");
sim.FixedStep(.25);Check(sim.GetSnapshot().Breakers.Single(b=>b.ControlId=="p11_cb_r04_c19").Tripped,"Persistent fault retrips reset breaker");
sim=New();
foreach(var b in sim.GetSnapshot().Breakers)
{
 Check(sim.SetControl(b.ControlId,"PULLED"),"Breaker opens logically:"+b.ControlId);
 Check(!sim.GetSnapshot().Breakers.Single(x=>x.ControlId==b.ControlId).Closed,"Breaker open is observable:"+b.ControlId);
 Check(sim.SetControl(b.ControlId,"PUSHED"),"Breaker closes logically:"+b.ControlId);
}
sim=New();sim.FixedStep(123.125);var saved=sim.SaveJson();var restored=New();restored.LoadJson(saved);
foreach(var s in new[]{.1,.2,.05,30.125,2.875,300.0}){sim.FixedStep(s);restored.FixedStep(s);}
Check(sim.SaveJson()==restored.SaveJson(),"Save/load replay is byte-deterministic including fractional remainder");
var beforeBad=sim.SaveJson();var badSave=JsonNode.Parse(beforeBad)!;badSave["batteries"]!["BAT1"]!["remainingAh"]=-1;
Check(Reject(()=>sim.LoadJson(badSave.ToJsonString())),"Negative saved battery charge rejected");
Check(sim.SaveJson()==beforeBad,"Rejected save makes no partial mutation");
badSave=JsonNode.Parse(beforeBad)!;badSave["definitionHash"]="wrong";Check(Reject(()=>sim.LoadJson(badSave.ToJsonString())),"Reference hash mismatch rejected");
Check(Reject(()=>sim.FixedStep(double.NaN))&&Reject(()=>sim.FixedStep(-1)),"Invalid time steps rejected");
Check(sim.SaveJson()==beforeBad,"Invalid steps leave state unchanged");
sim=New();var nearEmpty=JsonNode.Parse(sim.SaveJson())!;
foreach(var b in nearEmpty["batteries"]!.AsObject())b.Value!["remainingAh"]=b.Key is "BAT1" or "BAT2" or "BAT3" or "BAT4" ?.001:0;
nearEmpty["initialTotalAh"]=.004;sim.LoadJson(nearEmpty.ToJsonString());sim.FixedStep(10);
Near(sim.GetSnapshot().ConsumedAh,.004,1e-12,"Mid-step depletion never creates charge");
Near(sim.GetSnapshot().ConsumedWh,.12,1e-10,"Mid-step depletion conserves delivered energy");
Check(sim.GetSnapshot().Batteries.All(b=>b.RemainingAh>=0),"Battery charge never negative");
Check(!Bus(sim,"CDR_DC").Powered&&!Bus(sim,"LMP_DC").Powered,"Exhausted battery bank deenergizesDC buses");
sim=New();sim.SetBatteryFault("BAT1",true);sim.SetControl("p14_power_temp_mon","BAT 1");
Check(sim.GetSnapshot().Indicators["p2_battery_caution"]&&sim.GetSnapshot().Batteries.Single(b=>b.Id=="BAT1").Connected,"Sensor-only fault drives caution without inventing a battery disconnection");
Check(sim.GetSnapshot().Indicators["p14_bat_fault"],"Selected faulted battery drives localBATFAULT indication");
sim=New("electrical_checkout");sim.SetBatteryFault("BAT1",true);
Check(sim.GetSnapshot().Indicators["p1_master_alarm"],"Powered master alarm responds to battery caution");
sim.SetControl("p1_master_alarm","PRESSED");
Check(!sim.GetSnapshot().Indicators["p1_master_alarm"]&&sim.GetSnapshot().Indicators["p2_battery_caution"],"Master alarm acknowledges while caution remains lit");
saved=sim.SaveJson();restored=New();restored.LoadJson(saved);
Check(!restored.GetSnapshot().Indicators["p2_master_alarm"],"Alarm acknowledgement survives save/load");
Check(restored.GetSnapshot().ControlPositions["p1_master_alarm"]=="RELEASED","Saved input does not restore a held momentary alarm button");
sim.SetBatteryFault("BAT1",false);sim.SetBatteryFault("BAT1",true);
Check(sim.GetSnapshot().Indicators["p1_master_alarm"],"Recurring caution raises a new master alarm");
badSave=JsonNode.Parse(sim.SaveJson())!;badSave["controls"]!["p14_se_bat_1_low_voltage"]="ON";
Check(Reject(()=>sim.LoadJson(badSave.ToJsonString())),"Save cannot bypass HV/LV contactor interlock");
var report=new{result=failures.Count==0?"PASS":"FAIL",checks,failures,breakers=160,headlessCore=true,
 fidelity="PartialEPS; aggregate calibrated; no fullflight validation claim",flightValidationGate="OPEN"};
var reportArg=args.FirstOrDefault(a=>a.StartsWith("--report="));
if(reportArg!=null)File.WriteAllText(reportArg[9..],JsonSerializer.Serialize(report,ElectricalSimulation.JsonOptions));
Console.WriteLine(JsonSerializer.Serialize(report,ElectricalSimulation.JsonOptions));
Environment.ExitCode=failures.Count==0?0:1;
