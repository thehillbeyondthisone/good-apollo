using System.Security.Cryptography;
using System.Text.Json;
using Aquarius.Sim;

var repo = args.Length > 0 ? Path.GetFullPath(args[0]) : Directory.GetCurrentDirectory();
var controlsPath = Path.Combine(repo, "reference/controls.json");
var electricalPath = Path.Combine(repo, "reference/electrical.json");
var controlJson = File.ReadAllText(controlsPath);
var electricalJson = File.ReadAllText(electricalPath);
var sim = ElectricalSimulation.FromJson(electricalJson, controlJson);
var failures = new List<string>();
var checks = 0;
void Check(bool condition, string message)
{
    checks++;
    if (!condition) { failures.Add(message); Console.Error.WriteLine("FAIL: " + message); }
}
void Set(string id, string value) => Check(sim.SetControl(id, value), $"Accept {id} {value}");
CautionWarningSnapshot Cw() => sim.GetSnapshot().CautionWarning ?? throw new Exception("CWEA snapshot missing.");
string[] expectedPositions = ["OFF", "ALARM/TONE", "C/W 1", "ENG PB-C/W 2", "C/W 3", "C/W 4", "COMPN T", "OFF"];
using var inventory = JsonDocument.Parse(controlJson);
var selector = inventory.RootElement.GetProperty("controls").EnumerateArray().Single(c => c.GetProperty("id").GetString() == "p3_lamp_tone_test");
Check(selector.GetProperty("positions").EnumerateArray().Select(p => p.GetString()).SequenceEqual(expectedPositions), "Source selector has eight physical detents and both OFF ends");
Check(!selector.GetProperty("mechanism").GetProperty("wrap").GetBoolean(), "Selector cannot wrap between its OFF endpoints");
Check(sim.ModeledControlIds.Contains("p3_lamp_tone_test"), "EPS models the existing physical test selector");
Set("p3_lamp_tone_test", "ALARM/TONE");
Check(!Cw().TestActive && !Cw().WarningTone, "Cold dark has no powered test lamps or tone");
sim.ApplyPreset("electrical_checkout");
Set("p16_cb_r02_c14", "PULLED");
Dictionary<string, string[]> expected = new()
{
    ["ALARM/TONE"] = ["p1_master_alarm", "p2_master_alarm"],
    ["C/W 1"] = ["p1_asc_press_warning", "p1_des_reg_warning", "p1_des_qty_warning", "p1_ces_ac_warning", "p1_ces_dc_warning", "p1_ags_warning", "p1_lgc_warning", "p1_iss_warning"],
    ["ENG PB-C/W 2"] = ["p1_rcs_tca_warning", "p1_rcs_a_reg_warning", "p1_rcs_b_reg_warning", "p1_dc_bus_warning", "p1_cabin_warning", "p1_suit_fan_warning", "p5_start", "p5_stop", "p6_stop"],
    ["C/W 3"] = ["p2_asc_hi_reg_caution", "p2_asc_qty_caution", "p2_eng_gmbl_caution", "p2_inverter_caution", "p2_battery_caution", "p2_rndz_rdr_caution", "p2_pre_amps_caution"],
    ["C/W 4"] = ["p2_ed_relays_caution", "p2_rcs_caution", "p2_heater_caution", "p2_ecs_caution", "p2_o2_qty_caution", "p2_glycol_caution", "p2_water_qty_caution", "p2_s_bd_rcvr_caution", "p2_c_w_pwr_caution"],
    ["COMPN T"] = ["p1_lunar_contact", "p3_lunar_contact", "p8_stage_seq_relays_sys_a", "p8_stage_seq_relays_sys_b", "p14_bat_fault", "p14_dc_bus_fault", "p2_suit_fan_component_caution", "p2_glycol_component_caution", "p2_co2_component_caution", "p2_h2o_sep_component_caution", "p3_rendezvous_radar_no_track"]
};
var allTested = expected.Values.SelectMany(v => v).ToHashSet(StringComparer.Ordinal);
foreach (var bank in expected)
{
    Set("p3_lamp_tone_test", bank.Key);
    var snapshot = sim.GetSnapshot();
    var cw = Cw();
    Check(cw.TestActive && cw.TestPowerAvailable, $"{bank.Key} tests independently of CWEA instrumentation power");
    Check(cw.TestedIndicatorIds.ToHashSet().SetEquals(bank.Value), $"{bank.Key} matches the source circuit bank");
    foreach (var id in allTested)
        Check(snapshot.Indicators[id] == bank.Value.Contains(id), $"{bank.Key} does not energize an unintended test lamp: {id}");
    Check(cw.WarningTone == (bank.Key == "ALARM/TONE"), $"{bank.Key} does not create a false audible warning");
    Check(snapshot.ControlPositions["p5_start"] == "RELEASED" && snapshot.ControlPositions["p5_stop"] == "RELEASED", "Testing engine lamps does not press engine controls");
}
Set("p3_lamp_tone_test", "ALARM/TONE");
Set("p1_master_alarm", "PRESSED");
Check(Cw().WarningTone && sim.GetSnapshot().Indicators["p2_master_alarm"], "Acknowledgement does not defeat the selected ALARM/TONE test");
Set("p1_master_alarm", "RELEASED");
Set("p16_cb_r02_c04", "PULLED");
Check(!Cw().WarningTone && !Cw().TestActive, "Opening MASTER ALARM branch removes its test lamps and tone");
Set("p3_lamp_tone_test", "C/W 1");
Check(Cw().TestedIndicatorIds.Length == 8, "Passive bank-test grounding still works with MASTER ALARM power removed");
Set("p11_cb_r03_c19", "PULLED");
Set("p16_cb_r02_c03", "PULLED");
Check(!Cw().TestActive && Cw().TestedIndicatorIds.Length == 0, "Both ANN lighting feeds open remove bank-test illumination");
Set("p3_lamp_tone_test", "COMPN T");
Check(Cw().TestedIndicatorIds.SequenceEqual(["p14_dc_bus_fault"]), "DC FEEDER lamp has its documented direct DC supply");
Set("p11_cb_r03_c19", "PUSHED");
Check(!Cw().TestedIndicatorIds.Contains("p14_bat_fault"), "BAT FAULT local lamp needs the LMP lighting branch");
Set("p16_cb_r02_c03", "PUSHED");
Check(Cw().TestedIndicatorIds.Length == 11, "Both source component lamp feeds restored");
var savedTest = sim.SaveJson();
Set("p3_lamp_tone_test", "OFF");
Check(!Cw().TestActive && !Cw().WarningTone, "OFF removes every test without latching a fault");
sim.LoadJson(savedTest);
Check(Cw().SelectorPosition == "COMPN T" && Cw().TestedIndicatorIds.Length == 11, "Saved physical selector restores deterministic test outputs");
Check(sim.SaveJson() == savedTest, "Lamp test adds no hidden timer or non-deterministic saved state");
var invalid = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(savedTest)!;
var invalidControls = invalid["controls"].Deserialize<Dictionary<string, string>>()!;
invalidControls["p3_lamp_tone_test"] = "UNSOURCED ALL";
invalid["controls"] = JsonSerializer.SerializeToElement(invalidControls);
try { sim.LoadJson(JsonSerializer.Serialize(invalid)); Check(false, "Invalid selector save must reject"); }
catch (ArgumentException) { Check(true, "Invalid selector save rejects"); }
Check(sim.SaveJson() == savedTest, "Rejected selector save is atomic");
sim.ApplyPreset("electrical_checkout");
sim.SetBatteryFault("BAT1", true);
Check(Cw().WarningTone, "A real modeled unacknowledged battery warning drives tone");
Set("p3_lamp_tone_test", "C/W 1");
Check(sim.GetSnapshot().Indicators["p2_battery_caution"], "Bank test preserves a real caution in another bank");
Set("p1_master_alarm", "PRESSED");
Set("p1_master_alarm", "RELEASED");
Check(!Cw().WarningTone && sim.GetSnapshot().Indicators["p2_battery_caution"], "Acknowledging real warning silences tone without extinguishing caution");
Set("p3_lamp_tone_test", "ALARM/TONE");
Check(Cw().WarningTone, "Tone test remains independent of acknowledged actual fault");
Set("p3_lamp_tone_test", "OFF");
Check(!Cw().WarningTone, "Leaving tone test preserves real-warning acknowledgement");
sim.SetBatteryFault("BAT1", false);
sim.SetBatteryFault("BAT1", true);
Check(Cw().WarningTone, "Recurring actual fault re-arms audible warning");
var report = new { result = failures.Count == 0 ? "PASS" : "FAIL", passed = failures.Count == 0, checks, failures, inventorySha256 = Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(controlsPath))), electricalDefinitionSha256 = Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(electricalPath))), basis = "LM-7 AOH Fig.2.10-5 PDF634; PDF624,741,742,789", vrLaunched = false };
Directory.CreateDirectory(Path.Combine(repo, "reference"));
File.WriteAllText(Path.Combine(repo, "reference/caution-warning-tests.json"), JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
Console.WriteLine($"Caution/warning verification: {checks} checks, {failures.Count} failures.");
return failures.Count == 0 ? 0 : 1;
