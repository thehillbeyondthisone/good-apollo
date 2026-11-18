using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Aquarius.Sim;

/// <summary>
/// Deterministic EPS model with separate aggregate calibration and sourced
/// equipment operating-load modes. Unknown equipment demand remains explicit.
/// </summary>
public sealed partial class ElectricalSimulation
{
    public static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
        { WriteIndented = true };
    private static readonly string[] BusIds = ["CDR_DC", "LMP_DC", "AC_A", "AC_B"];
    private readonly ElectricalDefinition definition;
    private readonly string definitionHash;
    private readonly SortedDictionary<string, string[]> allowed = new(StringComparer.Ordinal);
    private readonly SortedDictionary<string, string> controls = new(StringComparer.Ordinal);
    private readonly SortedDictionary<string, string> defaults = new(StringComparer.Ordinal);
    // Physical CENTER detents do not erase electrically latched ECA commands.
    private readonly SortedDictionary<string, string> feedCommands = new(StringComparer.Ordinal);
    private readonly HashSet<string> acknowledgedAlarms = new(StringComparer.Ordinal);
    private readonly HashSet<string> momentaryControls = new(StringComparer.Ordinal);
    private readonly SortedDictionary<string, BatteryState> batteries = new(StringComparer.Ordinal);
    private readonly SortedDictionary<string, bool> tripped = new(StringComparer.Ordinal);
    private readonly SortedDictionary<string, double> branchFaults = new(StringComparer.Ordinal);
    private readonly HashSet<string> modeled = new(StringComparer.Ordinal);
    private double remainder;
    private long ticks;
    private double aggregateCurrent;
    private string loadModel = "aggregate";
    private double initialTotalAh;
    private string preset = "cold_dark";

    private sealed class BatteryState
    {
        public BatteryState() { }
        public double RemainingAh { get; set; }
        public double ConsumedAh { get; set; }
        public double ConsumedWh { get; set; }
        public bool Fault { get; set; }
    }
    private sealed record Feed(string BatteryId, string BusId, double VoltageV);
    private sealed class Network
    {
        public Dictionary<string, double> Voltage { get; } = BusIds.ToDictionary(k => k, _ => 0.0);
        public Dictionary<string, double> BusCurrent { get; } = BusIds.ToDictionary(k => k, _ => 0.0);
        public Dictionary<string, double> BatteryCurrent { get; } = [];
        public Dictionary<string, double> BatteryVoltage { get; } = [];
        public Dictionary<string, double> LoadCurrent { get; } = [];
        public Dictionary<string, double> FaultCurrent { get; } = [];
        public Dictionary<string, double> BranchCurrent { get; } = [];
        public Dictionary<string, double> EquipmentDcCurrent { get; } = BusIds.ToDictionary(k => k, _ => 0.0);
        public Dictionary<string, double> FaultDcCurrent { get; } = BusIds.ToDictionary(k => k, _ => 0.0);
        public Dictionary<string, double> AggregateDcCurrent { get; } = BusIds.ToDictionary(k => k, _ => 0.0);
        public Dictionary<string, double> ExportDcCurrent { get; } = BusIds.ToDictionary(k => k, _ => 0.0);
        public Dictionary<string, DemandPartition> BatteryDemand { get; } = [];
        public List<Feed> Feeds { get; } = [];
    }

    private ElectricalSimulation(ElectricalDefinition data, string dataHash, string controlsJson)
    {
        definition = data;
        definitionHash = dataHash;
        if (data.SchemaVersion != 1) throw new ArgumentException("Unsupported EPS schema.");
        if (data.FixedStepSeconds <= 0 || !double.IsFinite(data.FixedStepSeconds))
            throw new ArgumentException("Invalid fixed time step.");
        using var document = JsonDocument.Parse(controlsJson);
        foreach (var c in document.RootElement.GetProperty("controls").EnumerateArray())
        {
            var id = c.GetProperty("id").GetString()!;
            allowed.Add(id, c.GetProperty("positions").EnumerateArray().Select(v => v.GetString()!).ToArray());
            defaults.Add(id, c.GetProperty("default").GetString()!);
            var momentary = c.TryGetProperty("momentary", out var explicitMomentary)
                ? explicitMomentary.GetBoolean()
                : (c.TryGetProperty("springReturn", out var springReturn) && springReturn.GetBoolean()) ||
                  (c.TryGetProperty("mechanism", out var mechanism) &&
                   mechanism.TryGetProperty("springReturn", out var mechanismSpring) && mechanismSpring.GetBoolean()) ||
                  c.GetProperty("type").GetString() is "pushbutton" or "joystick" or "axis";
            if (momentary) momentaryControls.Add(id);
        }
        foreach (var b in data.Breakers)
        {
            RequireControl(b.ControlId);
            if (!BusIds.Contains(b.BusId)) throw new ArgumentException($"Orphan breaker bus: {b.ControlId}");
            if (b.RatedCurrentA is <= 0) throw new ArgumentException($"Invalid breaker rating: {b.ControlId}");
            tripped.Add(b.ControlId, false);
        }
        foreach (var b in data.Batteries)
        {
            if (b.CapacityAh <= 0 || b.NominalVoltageV <= 0 || !BusIds.Contains(b.NormalBusId))
                throw new ArgumentException($"Invalid battery: {b.Id}");
            batteries.Add(b.Id, new BatteryState());
            foreach (var id in new[] { b.HighControlId, b.LowControlId, b.NormalControlId, b.BackupControlId })
                if (id.Length > 0) { RequireControl(id); feedCommands[id] = "OFF/RESET"; }
            foreach (var id in b.FeedBreakerIds) RequireBreaker(id);
        }
        foreach (var tie in data.Ties)
        {
            if (!BusIds.Contains(tie.BusA) || !BusIds.Contains(tie.BusB)) throw new ArgumentException("Orphan tie bus.");
            foreach (var id in tie.BreakerIds) RequireBreaker(id);
        }
        foreach (var load in data.Loads)
            if (!BusIds.Contains(load.BusId) || load.NominalShare < 0)
                throw new ArgumentException($"Orphan or invalid load: {load.Id}");
        if (Math.Abs(data.Loads.Sum(l => l.NominalShare) - 1) > 1e-12)
            throw new ArgumentException("Aggregate load shares must sum to one.");
        foreach (var c in data.PoweredControls)
        {
            if (!allowed.ContainsKey(c.ControlId)) throw new ArgumentException($"Unknown powered output: {c.ControlId}");
            foreach (var id in c.BreakerIds) RequireBreaker(id);
            foreach (var req in c.SwitchRequirements) RequireControl(req.ControlId);
        }
        foreach (var id in new[] { "p14_des_bats", "p14_inverter", "p14_power_temp_mon", "p1_master_alarm", "p2_master_alarm" })
            RequireControl(id);
        ConfigureEquipmentLoads();
        ConfigureCautionWarning();
        feedCommands["p14_des_bats"] = "DEAD FACE";
        ApplyPreset("cold_dark");
    }

    public static ElectricalSimulation FromJson(string electricalJson, string controlsJson)
    {
        var data = JsonSerializer.Deserialize<ElectricalDefinition>(electricalJson, JsonOptions)
            ?? throw new ArgumentException("Electrical definition is empty.");
        var hash = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(electricalJson)));
        return new ElectricalSimulation(data, hash, controlsJson);
    }
    public IReadOnlyList<string> ModeledControlIds => modeled.Order(StringComparer.Ordinal).ToArray();
    public IReadOnlyList<string> AvailablePresets => definition.Presets.Select(p => p.Id).ToArray();
    public double FixedTimeStepSeconds => definition.FixedStepSeconds;
    private void RequireControl(string id)
    {
        if (!allowed.ContainsKey(id)) throw new ArgumentException($"Unknown control: {id}");
        modeled.Add(id);
    }
    private void RequireBreaker(string id)
    {
        if (!tripped.ContainsKey(id)) throw new ArgumentException($"Unknown breaker: {id}");
    }
    private bool Is(string id, string value) => controls.TryGetValue(id, out var current) && current == value;
    private bool CommandIs(string id, string value) => feedCommands.TryGetValue(id, out var current) && current == value;
    private bool Closed(string id) => Is(id, "PUSHED") && !tripped[id];

    public void ApplyPreset(string id)
    {
        var p = definition.Presets.SingleOrDefault(p => p.Id == id)
            ?? throw new ArgumentException($"Unknown electrical preset: {id}");
        controls.Clear();
        foreach (var d in defaults) controls[d.Key] = d.Value;
        foreach (var c in p.Controls)
        {
            if (!allowed.TryGetValue(c.Key, out var values) || !values.Contains(c.Value))
                throw new ArgumentException($"Invalid preset state: {c.Key}/{c.Value}");
            controls[c.Key] = c.Value;
        }
        foreach (var key in feedCommands.Keys.ToArray())
            feedCommands[key] = controls[key] == "CENTER" ? (key == "p14_des_bats" ? "DEAD FACE" : "OFF/RESET") : controls[key];
        foreach (var key in momentaryControls) controls[key] = defaults[key];
        var full = definition.Batteries.Sum(b => b.CapacityAh);
        var scale = Math.Clamp((p.InitialTotalRemainingAh ?? full) / full, 0, 1);
        foreach (var b in definition.Batteries)
            batteries[b.Id] = new BatteryState { RemainingAh = b.CapacityAh * scale };
        foreach (var k in tripped.Keys.ToArray()) tripped[k] = false;
        branchFaults.Clear();
        acknowledgedAlarms.Clear();
        aggregateCurrent = p.AggregateCurrentA;
        loadModel = p.LoadModel;
        initialTotalAh = batteries.Values.Sum(b => b.RemainingAh);
        preset = p.Id;
        ticks = 0;
        remainder = 0;
        accounting = new();
    }

    public bool SetControl(string id, string positionLabel)
    {
        if (!modeled.Contains(id) || !allowed[id].Contains(positionLabel)) return false;
        // Real descent ECA contactors are electrically interlocked (AOH2.5-21).
        foreach (var b in definition.Batteries.Where(b => b.Stage == "descent"))
        {
            if (positionLabel == "ON" &&
                ((id == b.HighControlId && CommandIs(b.LowControlId, "ON")) ||
                 (id == b.LowControlId && CommandIs(b.HighControlId, "ON")))) return false;
        }
        if (tripped.ContainsKey(id))
        {
            if (positionLabel == "PULLED") tripped[id] = false;
            else if (tripped[id]) return false;
        }
        controls[id] = positionLabel;
        if (feedCommands.ContainsKey(id) && positionLabel != "CENTER") feedCommands[id] = positionLabel;
        if ((id == "p1_master_alarm" || id == "p2_master_alarm") && positionLabel == "PRESSED")
            acknowledgedAlarms.UnionWith(CurrentAlarms(Solve()));
        RefreshAlarmAcknowledgements();
        return true;
    }

    /// <summary>Synthetic test/fault input; no claim of a flown current waveform.</summary>
    public void InjectBranchFault(string breakerControlId, double currentA)
    {
        RequireBreaker(breakerControlId);
        if (currentA < 0 || !double.IsFinite(currentA)) throw new ArgumentOutOfRangeException(nameof(currentA));
        if (currentA == 0) branchFaults.Remove(breakerControlId);
        else branchFaults[breakerControlId] = currentA;
    }
    public void SetBatteryFault(string batteryId, bool fault)
    {
        if (!batteries.TryGetValue(batteryId, out var b)) throw new ArgumentException("Unknown battery.");
        b.Fault = fault;
        RefreshAlarmAcknowledgements();
    }

    public void FixedStep(double seconds)
    {
        if (seconds < 0 || !double.IsFinite(seconds) || seconds > 86400)
            throw new ArgumentOutOfRangeException(nameof(seconds), "Step must be finite and at most one day.");
        remainder += seconds;
        while (remainder + 1e-12 >= definition.FixedStepSeconds)
        {
            Integrate(definition.FixedStepSeconds);
            remainder -= definition.FixedStepSeconds;
            if (remainder < 0 && remainder > -1e-10) remainder = 0;
            ticks++;
        }
    }

    private void Integrate(double seconds)
    {
        // The available source documents give ratings, not complete thermal trip curves.
        // Compare quantified operating demand plus explicit faults; unknown draws
        // remain excluded rather than invented from the protective amp rating.
        var first = Solve();
        foreach (var b in definition.Breakers)
            if (b.RatedCurrentA is double rating && first.BranchCurrent.GetValueOrDefault(b.ControlId) > rating)
            {
                tripped[b.ControlId] = true;
                controls[b.ControlId] = "PULLED";
            }
        var left = seconds;
        while (left > 1e-12)
        {
            var net = Solve();
            var duration = left;
            foreach (var b in net.BatteryCurrent)
                if (b.Value > 0) duration = Math.Min(duration, batteries[b.Key].RemainingAh * 3600 / b.Value);
            if (duration <= 1e-12) break;
            foreach (var b in net.BatteryCurrent)
            {
                var state = batteries[b.Key];
                var ah = Math.Min(state.RemainingAh, b.Value * duration / 3600);
                state.RemainingAh = Math.Max(0, state.RemainingAh - ah);
                if (state.RemainingAh < 1e-12) state.RemainingAh = 0;
                state.ConsumedAh += ah;
                state.ConsumedWh += ah * net.BatteryVoltage.GetValueOrDefault(b.Key);
                AttributeConsumption(net, b.Key, ah, ah * net.BatteryVoltage.GetValueOrDefault(b.Key));
            }
            left -= duration;
        }
        RefreshAlarmAcknowledgements();
    }

    private HashSet<string> CurrentAlarms(Network n)
    {
        var result = new HashSet<string>(StringComparer.Ordinal);
        if (!Closed("p16_cb_r02_c14") || n.Voltage["LMP_DC"] <= 0) return result;
        if (n.Voltage["CDR_DC"] < 26.5 || n.Voltage["LMP_DC"] < 26.5) result.Add("dc_bus");
        if (batteries.Values.Any(b => b.Fault)) result.Add("battery");
        if (!Is("p14_inverter", "OFF") && n.Voltage["AC_A"] < 112) result.Add("inverter");
        return result;
    }
    private void RefreshAlarmAcknowledgements()
    {
        var active = CurrentAlarms(Solve());
        acknowledgedAlarms.RemoveWhere(flag => !active.Contains(flag));
    }

    private Network Solve()
    {
        var n = new Network();
        foreach (var b in definition.Batteries)
        {
            n.BatteryCurrent[b.Id] = 0;
            n.BatteryVoltage[b.Id] = batteries[b.Id].RemainingAh > 1e-12 ? b.NominalVoltageV : 0;
            if (batteries[b.Id].RemainingAh <= 1e-12) continue;
            if (b.Stage == "descent")
            {
                if (!CommandIs("p14_des_bats", "CONNECT") || !b.FeedBreakerIds.Any(Closed)) continue;
                var voltage = CommandIs(b.HighControlId, "ON") ? b.NominalVoltageV : CommandIs(b.LowControlId, "ON") ? b.LowTapVoltageV : 0;
                if (voltage > 0)
                {
                    n.BatteryVoltage[b.Id] = voltage;
                    n.Feeds.Add(new Feed(b.Id, b.NormalBusId, voltage));
                }
            }
            else
            {
                if (CommandIs(b.NormalControlId, "ON")) n.Feeds.Add(new Feed(b.Id, b.NormalBusId, b.NominalVoltageV));
                if (CommandIs(b.BackupControlId, "ON")) n.Feeds.Add(new Feed(b.Id, b.BackupBusId, b.NominalVoltageV));
            }
        }
        var tied = definition.Ties.Any(t => t.BreakerIds.All(Closed));
        var groups = tied ? new[] { new[] { "CDR_DC", "LMP_DC" } } : new[] { new[] { "CDR_DC" }, new[] { "LMP_DC" } };
        foreach (var group in groups)
        {
            var voltage = n.Feeds.Where(f => group.Contains(f.BusId)).Select(f => f.VoltageV).DefaultIfEmpty(0).Max();
            foreach (var bus in group) n.Voltage[bus] = voltage;
        }
        var inverter = definition.Inverters.SingleOrDefault(i => Is("p14_inverter", i.Selection) &&
            Closed(i.InputBreakerId) && n.Voltage[i.SourceBusId] > 0);
        if (inverter is not null)
        {
            if (Closed(inverter.AcABreakerId)) n.Voltage["AC_A"] = 115;
            if (Closed(inverter.AcBBreakerId)) n.Voltage["AC_B"] = 115;
        }
        if (loadModel == "aggregate")
        {
            foreach (var load in definition.Loads)
            {
                var amps = n.Voltage[load.BusId] > 0 ? aggregateCurrent * load.NominalShare : 0;
                n.LoadCurrent[load.Id] = amps;
                n.BusCurrent[load.BusId] += amps;
                n.AggregateDcCurrent[load.BusId] += amps;
            }
        }
        else
        {
            foreach (var load in definition.EquipmentLoads)
            {
                var amps = EquipmentAmps(load, n);
                n.LoadCurrent[load.Id] = amps;
                n.BusCurrent[load.BusId] += amps;
                n.EquipmentDcCurrent[load.BusId] += amps;
                foreach (var id in load.BreakerIds)
                    n.BranchCurrent[id] = n.BranchCurrent.GetValueOrDefault(id) + amps;
            }
        }
        foreach (var fault in branchFaults)
        {
            var branch = definition.Breakers.Single(b => b.ControlId == fault.Key);
            if (n.Voltage[branch.BusId] <= 0 || !Closed(fault.Key)) continue;
            n.FaultCurrent[fault.Key] = fault.Value;
            n.BranchCurrent[fault.Key] = n.BranchCurrent.GetValueOrDefault(fault.Key) + fault.Value;
            n.BusCurrent[branch.BusId] += fault.Value;
            n.FaultDcCurrent[branch.BusId] += fault.Value;
        }
        if (n.Voltage[accounting.CmExportSourceBusId] > 0)
        {
            n.ExportDcCurrent[accounting.CmExportSourceBusId] = accounting.CmExportDemandA;
            n.BusCurrent[accounting.CmExportSourceBusId] += accounting.CmExportDemandA;
        }
        if (inverter is not null)
        {
            // Real watts are conserved through the explicitly ideal inverter.
            // AC amps here are real-power equivalents; phase/current waveform
            // and unknown power factor do not become measured RMS currents.
            var inputCurrent = new[] { "AC_A", "AC_B" }.Sum(bus => n.BusCurrent[bus] * n.Voltage[bus]) /
                n.Voltage[inverter.SourceBusId];
            n.BranchCurrent[inverter.InputBreakerId] = n.BranchCurrent.GetValueOrDefault(inverter.InputBreakerId) + inputCurrent;
            n.BusCurrent[inverter.SourceBusId] += inputCurrent;
            foreach (var category in new[] { n.EquipmentDcCurrent, n.FaultDcCurrent, n.AggregateDcCurrent })
                category[inverter.SourceBusId] += new[] { "AC_A", "AC_B" }.Sum(bus => category[bus] * n.Voltage[bus]) /
                    n.Voltage[inverter.SourceBusId];
            if (n.Voltage["AC_A"] > 0) n.BranchCurrent[inverter.AcABreakerId] = n.BusCurrent["AC_A"];
            if (n.Voltage["AC_B"] > 0) n.BranchCurrent[inverter.AcBBreakerId] = n.BusCurrent["AC_B"];
        }
        foreach (var group in groups)
        {
            var voltage = n.Voltage[group[0]];
            var providers = n.Feeds.Where(f => group.Contains(f.BusId) && Math.Abs(f.VoltageV - voltage) < 1e-9)
                .Select(f => f.BatteryId).Distinct().Order(StringComparer.Ordinal).ToArray();
            var total = group.Sum(bus => n.BusCurrent[bus]);
            foreach (var id in providers)
            {
                n.BatteryCurrent[id] = total / providers.Length;
                n.BatteryVoltage[id] = voltage;
                n.BatteryDemand[id] = new(group.Sum(bus => n.EquipmentDcCurrent[bus]) / providers.Length,
                    group.Sum(bus => n.ExportDcCurrent[bus]) / providers.Length,
                    group.Sum(bus => n.FaultDcCurrent[bus]) / providers.Length,
                    group.Sum(bus => n.AggregateDcCurrent[bus]) / providers.Length);
            }
        }
        return n;
    }

    public bool IsBreakerPowered(string controlId)
    {
        var branch = definition.Breakers.Single(b => b.ControlId == controlId);
        return Closed(controlId) && Solve().Voltage[branch.BusId] > 0;
    }

    public ElectricalSnapshot GetSnapshot()
    {
        var n = Solve();
        var breakerSnapshots = definition.Breakers.Select(b => new BreakerSnapshot(b.ControlId, b.BusId,
            Closed(b.ControlId), tripped[b.ControlId], Closed(b.ControlId) && n.Voltage[b.BusId] > 0,
            n.BranchCurrent.GetValueOrDefault(b.ControlId), loadModel == "aggregate" && (branchFaults.ContainsKey(b.ControlId) || n.BranchCurrent.ContainsKey(b.ControlId)), b.RatedCurrentA)).ToArray();
        var liveBreakers = breakerSnapshots.ToDictionary(b => b.ControlId);
        var powered = definition.PoweredControls.ToDictionary(c => c.ControlId,
            c => c.BreakerIds.All(id => liveBreakers[id].Powered) &&
                 c.SwitchRequirements.All(r => r.AllowedPositions.Contains(controls[r.ControlId])));
        var cw = liveBreakers["p16_cb_r02_c14"].Powered;
        var annunciatorPower = liveBreakers["p11_cb_r03_c19"].Powered || liveBreakers["p16_cb_r02_c03"].Powered;
        var batteryFault = batteries.Values.Any(b => b.Fault);
        var masterAlarmPower = liveBreakers["p16_cb_r02_c04"].Powered;
        var masterAlarm = masterAlarmPower && CurrentAlarms(n).Any(flag => !acknowledgedAlarms.Contains(flag));
        powered["p1_master_alarm"] = masterAlarmPower;
        powered["p2_master_alarm"] = masterAlarmPower;
        var indicators = new Dictionary<string, bool>
        {
            ["p1_dc_bus_warning"] = cw && annunciatorPower && (n.Voltage["CDR_DC"] < 26.5 || n.Voltage["LMP_DC"] < 26.5),
            ["p2_battery_caution"] = cw && annunciatorPower && batteryFault,
            ["p2_inverter_caution"] = cw && annunciatorPower && !Is("p14_inverter", "OFF") && n.Voltage["AC_A"] < 112,
            ["p14_bat_fault"] = false,
            ["p1_master_alarm"] = masterAlarm,
            ["p2_master_alarm"] = masterAlarm
        };
        var meters = new Dictionary<string, double> { ["p14_volts"] = 0, ["p14_amps"] = 0 };
        var valid = new Dictionary<string, bool> { ["p14_volts"] = powered.GetValueOrDefault("p14_volts"), ["p14_amps"] = false };
        var selected = controls["p14_power_temp_mon"];
        var selectedBattery = definition.Batteries.SingleOrDefault(b => selected == b.Id.Replace("BAT", "BAT "));
        if (selectedBattery is not null)
        {
            var b = selectedBattery;
            meters["p14_volts"] = n.BatteryVoltage[b.Id];
            meters["p14_amps"] = n.BatteryCurrent[b.Id] * (b.Stage == "descent" ? 2 : 1);
            valid["p14_amps"] = valid["p14_volts"];
            indicators["p14_bat_fault"] = batteryFault && batteries[b.Id].Fault && n.Voltage["LMP_DC"] > 0 && annunciatorPower;
        }
        else if (selected == "CDR BUS") meters["p14_volts"] = n.Voltage["CDR_DC"];
        else if (selected == "SE BUS") meters["p14_volts"] = n.Voltage["LMP_DC"];
        else if (selected == "AC BUS") meters["p14_volts"] = n.Voltage["AC_A"] / 3.125;
        else valid["p14_volts"] = false;
        if (!valid["p14_volts"]) meters["p14_volts"] = 0;
        if (!valid["p14_amps"]) meters["p14_amps"] = 0;
        var cwSnapshot = ApplyCautionWarningTest(n, indicators, powered);
        var bs = definition.Batteries.Select(b => new BatterySnapshot(b.Id, b.Stage, n.BatteryVoltage[b.Id],
            batteries[b.Id].RemainingAh, b.CapacityAh, n.BatteryCurrent[b.Id], batteries[b.Id].ConsumedAh,
            batteries[b.Id].ConsumedWh, n.Feeds.Any(f => f.BatteryId == b.Id), batteries[b.Id].Fault)).ToArray();
        return new ElectricalSnapshot(ticks * definition.FixedStepSeconds + remainder, preset, bs,
            BusIds.Select(id => new BusSnapshot(id, n.Voltage[id], n.BusCurrent[id], n.Voltage[id] > 0)).ToArray(),
            LoadSnapshots(n),
            breakerSnapshots, indicators, meters, valid, powered, new Dictionary<string, string>(controls),
            initialTotalAh, bs.Sum(b => b.ConsumedAh), bs.Sum(b => b.ConsumedWh),
            loadModel == "aggregate" ? "Partial EPS: ideal sources, logical wiring, calibrated aggregate loads; full flight validation open." :
                "Partial EPS: sourced operating loads only; incomplete equipment coverage and ideal conversion; full flight validation open.",
            ["Unquantified component loads are not zero-watt assertions.", "No battery temperature/chemical derating or voltage discharge curve.",
             "Instantaneous fault-current breaker trip surrogate; no thermal time-current curves.", "Ideal inverter has no losses or separately quantified idle draw.",
             "Source totals constrain calibration; the complete flown load schedule is not reconstructed.",
             "Sourced-component mode covers only identified loads; unknown equipment draw is not included.",
             "AC load current is a real-power equivalent, not a measured RMS current or recovered power-factor model."])
            { LoadModel = loadModel, CompleteEquipmentLoadCoverage = false, CautionWarning = cwSnapshot, Accounting = AccountingSnapshot(n) };
    }

    private sealed class SaveState
    {
        public SaveState() { }
        public int SchemaVersion { get; set; } = 2;
        public string DefinitionHash { get; set; } = "";
        public long Ticks { get; set; }
        public double Remainder { get; set; }
        public string Preset { get; set; } = "";
        public double AggregateCurrent { get; set; }
        public string LoadModel { get; set; } = "aggregate";
        public double InitialTotalAh { get; set; }
        public SortedDictionary<string, string> Controls { get; set; } = [];
        public SortedDictionary<string, string> FeedCommands { get; set; } = [];
        public SortedDictionary<string, BatteryState> Batteries { get; set; } = [];
        public SortedDictionary<string, bool> Tripped { get; set; } = [];
        public SortedDictionary<string, double> BranchFaults { get; set; } = [];
        public string[] AcknowledgedAlarms { get; set; } = [];
        public AccountingState? Accounting { get; set; }
    }
    public string SaveJson() => JsonSerializer.Serialize(new SaveState
    {
        DefinitionHash = definitionHash, Ticks = ticks, Remainder = remainder, Preset = preset,
        AggregateCurrent = aggregateCurrent, LoadModel = loadModel, InitialTotalAh = initialTotalAh,
        Accounting = accounting,
        Controls = SavedControlPositions(), Batteries = new(batteries, StringComparer.Ordinal),
        FeedCommands = new(feedCommands, StringComparer.Ordinal),
        Tripped = new(tripped, StringComparer.Ordinal), BranchFaults = new(branchFaults, StringComparer.Ordinal),
        AcknowledgedAlarms = acknowledgedAlarms.Order(StringComparer.Ordinal).ToArray()
    }, JsonOptions);

    private SortedDictionary<string, string> SavedControlPositions()
    {
        var positions = new SortedDictionary<string, string>(controls, StringComparer.Ordinal);
        // A released input device must not restore a held button after a crash.
        foreach (var id in momentaryControls) positions[id] = defaults[id];
        return positions;
    }

    public void LoadJson(string json)
    {
        SaveState s;
        try { s = JsonSerializer.Deserialize<SaveState>(json, JsonOptions) ?? throw new ArgumentException("Empty EPS save."); }
        catch (JsonException error) { throw new ArgumentException("Malformed or incomplete EPS save.", nameof(json), error); }
        if (s.SchemaVersion != 2 || s.DefinitionHash != definitionHash) throw new ArgumentException("EPS save/reference mismatch.");
        if (s.LoadModel is not ("aggregate" or "sourced_components") ||
            (s.LoadModel == "sourced_components" && (s.AggregateCurrent != 0 || definition.EquipmentLoads.Length == 0)))
            throw new ArgumentException("Invalid saved equipment load model.");
        var savedPreset = definition.Presets.SingleOrDefault(p => p.Id == s.Preset);
        if (savedPreset is null || savedPreset.LoadModel != s.LoadModel || savedPreset.AggregateCurrentA != s.AggregateCurrent)
            throw new ArgumentException("Saved load mode and calibration preset disagree.");
        if (s.Controls is null || s.FeedCommands is null || s.Batteries is null ||
            s.Tripped is null || s.BranchFaults is null || s.AcknowledgedAlarms is null)
            throw new ArgumentException("Incomplete EPS save.");
        if (s.Ticks < 0 || !double.IsFinite(s.Remainder) || s.Remainder < 0 || s.Remainder >= definition.FixedStepSeconds ||
            !double.IsFinite(s.AggregateCurrent) || s.AggregateCurrent < 0 || !double.IsFinite(s.InitialTotalAh)) throw new ArgumentException("Invalid EPS save time/load.");
        if (!s.Controls.Keys.ToHashSet(StringComparer.Ordinal).SetEquals(controls.Keys) ||
            !s.Batteries.Keys.ToHashSet(StringComparer.Ordinal).SetEquals(batteries.Keys) ||
            !s.FeedCommands.Keys.ToHashSet(StringComparer.Ordinal).SetEquals(feedCommands.Keys) ||
            !s.Tripped.Keys.ToHashSet(StringComparer.Ordinal).SetEquals(tripped.Keys))
            throw new ArgumentException("Incomplete EPS save.");
        foreach (var c in s.Controls) if (!allowed[c.Key].Contains(c.Value)) throw new ArgumentException("Invalid saved control.");
        foreach (var c in s.FeedCommands)
        {
            if (c.Value == "CENTER" || !allowed[c.Key].Contains(c.Value)) throw new ArgumentException("Invalid saved ECA command.");
            if (s.Controls[c.Key] != "CENTER" && s.Controls[c.Key] != c.Value)
                throw new ArgumentException("Saved ECA command and physical switch disagree.");
        }
        foreach (var b in definition.Batteries.Where(b => b.Stage == "descent"))
            if ((s.Controls[b.HighControlId] == "ON" && s.Controls[b.LowControlId] == "ON") ||
                (s.FeedCommands[b.HighControlId] == "ON" && s.FeedCommands[b.LowControlId] == "ON"))
                throw new ArgumentException("Saved contactors bypass the HV/LV interlock.");
        foreach (var t in s.Tripped)
            if (t.Value && s.Controls[t.Key] != "PULLED") throw new ArgumentException("Saved tripped breaker is not open.");
        foreach (var b in definition.Batteries)
        {
            var state = s.Batteries[b.Id];
            if (state is null || !double.IsFinite(state.RemainingAh) || state.RemainingAh < 0 || state.RemainingAh > b.CapacityAh ||
                !double.IsFinite(state.ConsumedAh) || state.ConsumedAh < 0 || !double.IsFinite(state.ConsumedWh) || state.ConsumedWh < 0)
                throw new ArgumentException("Invalid saved battery.");
            var taps = b.Stage == "descent" && b.LowTapVoltageV > 0
                ? new[] { b.NominalVoltageV, b.LowTapVoltageV } : new[] { b.NominalVoltageV };
            // Only the established ideal tap voltages constrain this check. It
            // does not infer electrochemical energy, losses or usable reserve.
            var energyTolerance = 1e-6 * Math.Max(1, state.ConsumedAh);
            if (state.RemainingAh + state.ConsumedAh > b.CapacityAh + 1e-6 ||
                state.ConsumedWh < state.ConsumedAh * taps.Min() - energyTolerance ||
                state.ConsumedWh > state.ConsumedAh * taps.Max() + energyTolerance)
                throw new ArgumentException("Saved battery charge/energy exceeds its ideal-source history bounds.");
        }
        if (Math.Abs(s.Batteries.Values.Sum(b => b.RemainingAh + b.ConsumedAh) - s.InitialTotalAh) > 1e-6)
            throw new ArgumentException("Saved charge is not conserved.");
        ValidateAccounting(s.Accounting, s.LoadModel, s.Batteries.Values);
        foreach (var f in s.BranchFaults) if (!tripped.ContainsKey(f.Key) || !double.IsFinite(f.Value) || f.Value < 0)
            throw new ArgumentException("Invalid saved branch fault.");
        if (s.AcknowledgedAlarms.Any(flag => flag is not ("dc_bus" or "battery" or "inverter")))
            throw new ArgumentException("Invalid saved alarm acknowledgement.");
        // All validation precedes mutation; rejection cannot partially apply.
        controls.Clear(); foreach (var c in s.Controls) controls[c.Key] = c.Value;
        foreach (var key in momentaryControls) controls[key] = defaults[key];
        feedCommands.Clear(); foreach (var c in s.FeedCommands) feedCommands[c.Key] = c.Value;
        batteries.Clear(); foreach (var b in s.Batteries) batteries[b.Key] = b.Value;
        tripped.Clear(); foreach (var b in s.Tripped) tripped[b.Key] = b.Value;
        branchFaults.Clear(); foreach (var f in s.BranchFaults) branchFaults[f.Key] = f.Value;
        acknowledgedAlarms.Clear(); acknowledgedAlarms.UnionWith(s.AcknowledgedAlarms);
        ticks = s.Ticks; remainder = s.Remainder; preset = s.Preset;
        aggregateCurrent = s.AggregateCurrent; loadModel = s.LoadModel; initialTotalAh = s.InitialTotalAh;
        accounting = s.Accounting!;
        RefreshAlarmAcknowledgements();
    }
}
