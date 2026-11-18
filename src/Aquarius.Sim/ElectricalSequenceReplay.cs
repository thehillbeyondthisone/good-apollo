using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Aquarius.Sim;

public sealed class PowerDownAction
{
    public string ControlId { get; set; } = "";
    public string Position { get; set; } = "";
}
public sealed class PowerDownEvent
{
    public string Id { get; set; } = "";
    public string Get { get; set; } = "";
    public int GetSeconds { get; set; }
    public string EvidenceKind { get; set; } = "";
    public string Title { get; set; } = "";
    public string Qualification { get; set; } = "";
    public string[] SourceGets { get; set; } = [];
    public PowerDownAction[] Actions { get; set; } = [];
}
public sealed class ElectricalPowerDownSequence
{
    public int SchemaVersion { get; set; }
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string InitialPreset { get; set; } = "";
    public string InventorySha256 { get; set; } = "";
    public string Qualification { get; set; } = "";
    public bool CompleteFlownConfiguration { get; set; }
    public bool IndependentFlightValidationPassed { get; set; }
    public string[] Limitations { get; set; } = [];
    public PowerDownEvent[] Events { get; set; } = [];
    public string SequenceSha256 { get; private set; } = "";

    public static ElectricalPowerDownSequence FromJson(string sequenceJson, string controlsJson)
    {
        ElectricalPowerDownSequence sequence;
        try { sequence = JsonSerializer.Deserialize<ElectricalPowerDownSequence>(sequenceJson, ElectricalSimulation.JsonOptions)
            ?? throw new ArgumentException("Empty powerdown sequence."); }
        catch(JsonException e) { throw new ArgumentException("Malformed powerdown sequence.",e); }
        string Hash(string value) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
        if (sequence.SchemaVersion != 1 || string.IsNullOrWhiteSpace(sequence.Id) || sequence.Events is not { Length: > 0 } ||
            sequence.InitialPreset != "sourced_equipment_checkout" || sequence.CompleteFlownConfiguration ||
            sequence.IndependentFlightValidationPassed || sequence.InventorySha256 != Hash(controlsJson))
            throw new ArgumentException("Invalid or incompatible partial powerdown sequence.");
        using var document = JsonDocument.Parse(controlsJson);
        var positions = document.RootElement.GetProperty("controls").EnumerateArray().ToDictionary(
            c => c.GetProperty("id").GetString()!, c => c.GetProperty("positions").EnumerateArray().Select(p => p.GetString()!).ToArray());
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var prior = -1;
        foreach (var e in sequence.Events)
        {
            if(e is null || e.Get is null) throw new ArgumentException("Null powerdown event.");
            var parts = e.Get.Split(':');
            if (parts.Length != 3 || !int.TryParse(parts[0], out var h) || !int.TryParse(parts[1], out var m) ||
                !int.TryParse(parts[2], out var s) || h < 0 || m is < 0 or > 59 || s is < 0 or > 59 ||
                e.GetSeconds != (long)h * 3600 + m * 60 + s || e.GetSeconds < prior || !seen.Add(e.Id) ||
                string.IsNullOrWhiteSpace(e.Id) || string.IsNullOrWhiteSpace(e.Title) || string.IsNullOrWhiteSpace(e.EvidenceKind) ||
                e.SourceGets is not { Length: > 0 } || e.Actions is null ||
                e.Actions.Any(a=>a is null) || e.Actions.Select(a => a.ControlId).Distinct(StringComparer.Ordinal).Count() != e.Actions.Length ||
                e.EvidenceKind is not ("instruction_only" or "readup_only" or "approximate_summary_only" or "crew_intent_readback" or "crew_state_report" or "crew_execution_report" or "crew_intent_report" or "execution_start_grouped" or "crew_acknowledgement"))
                throw new ArgumentException("Invalid powerdown event chronology/evidence.");
            prior = e.GetSeconds;
            foreach (var a in e.Actions)
                if (a.ControlId is null || !positions.TryGetValue(a.ControlId, out var p) || !p.Contains(a.Position))
                    throw new ArgumentException("Invalid powerdown control command.");
            if (e.EvidenceKind is "instruction_only" or "readup_only" or "approximate_summary_only" && e.Actions.Length != 0)
                throw new ArgumentException("Read-up/summary markers cannot operate controls.");
        }
        sequence.SequenceSha256 = Hash(sequenceJson);
        return sequence;
    }
}

/// <summary>Guided review, with historical labels independent of simulation time.</summary>
public sealed class ElectricalSequenceReplay
{
    // Presentation model for the scenario. The cold endpoint is within NASA's
    // reported 49–55 F LM range. The warm start and response rate are illustrative.
    private const double WarmCabinF = 68;
    private const double ColdCabinF = 52;
    private const double ThermalTimeSeconds = 45;
    private readonly ElectricalSimulation simulation;
    private readonly ElectricalPowerDownSequence sequence;
    public ElectricalSequenceReplay(ElectricalSimulation simulation, ElectricalPowerDownSequence sequence)
    {
        this.simulation=simulation;
        this.sequence=sequence;
        simulation.RegisterPowerDownActions(sequence.Events.SelectMany(e=>e.Actions));
    }
    public bool Active { get; private set; }
    public int CurrentIndex { get; private set; }
    public double CabinTemperatureF { get; private set; } = WarmCabinF;
    public PowerDownEvent? NextCallout => Active && CurrentIndex < sequence.Events.Length ? sequence.Events[CurrentIndex] : null;
    public void Start()
    {
        simulation.ApplyPreset(sequence.InitialPreset);
        CurrentIndex = 0;
        CabinTemperatureF = WarmCabinF;
        Active = true;
    }
    public void Cancel() { Active = false; CurrentIndex = 0; CabinTemperatureF = WarmCabinF; }

    public PowerDownAction[] PendingActions()
    {
        if (NextCallout is not { } next) return [];
        var expected = next.Actions.ToDictionary(action => action.ControlId);
        for (var index = CurrentIndex - 1; index >= 0; index--)
            foreach (var action in sequence.Events[index].Actions)
                expected.TryAdd(action.ControlId, action);
        return expected.Values.Where(action => !simulation.MatchesPowerDownAction(action)).ToArray();
    }

    public bool ConfirmCallout()
    {
        if (NextCallout == null || PendingActions().Length != 0) return false;
        CurrentIndex++;
        return true;
    }

    public bool EnterColdCoast()
    {
        if (!Active || CurrentIndex != sequence.Events.Length) return false;
        // The next chapter skips several hours of cold coast without modeling their battery history.
        CabinTemperatureF = Math.Min(CabinTemperatureF, 54.0);
        return true;
    }

    public void AdvanceCabinTemperature(double seconds)
    {
        if (!Active) return;
        var poweredFraction = simulation.PowerDownHeatFraction();
        var target = ColdCabinF + (WarmCabinF - ColdCabinF) * poweredFraction;
        CabinTemperatureF = target + (CabinTemperatureF - target) * Math.Exp(-seconds / ThermalTimeSeconds);
    }

    public PowerDownEvent? NextEvent()
    {
        if (!Active || CurrentIndex >= sequence.Events.Length) return null;
        var next = sequence.Events[CurrentIndex];
        simulation.ApplyPowerDownActions(next.Actions);
        CurrentIndex++;
        return next;
    }
    private sealed class ReplayState
    {
        public int SchemaVersion { get; set; }
        public string SequenceSha256 { get; set; } = "";
        public bool Active { get; set; }
        public int CurrentIndex { get; set; }
        public double CabinTemperatureF { get; set; } = WarmCabinF;
    }
    private ReplayState Parse(string json)
    {
        ReplayState s;
        try {
            using var doc=JsonDocument.Parse(json);
            if(doc.RootElement.ValueKind!=JsonValueKind.Object ||
                !doc.RootElement.TryGetProperty("schemaVersion",out _) || !doc.RootElement.TryGetProperty("sequenceSha256",out _) ||
                !doc.RootElement.TryGetProperty("active",out _) || !doc.RootElement.TryGetProperty("currentIndex",out _))
                throw new ArgumentException("Incomplete replay state.");
            s = JsonSerializer.Deserialize<ReplayState>(json, ElectricalSimulation.JsonOptions) ?? throw new ArgumentException("Empty replay state.");
        }
        catch (JsonException e) { throw new ArgumentException("Malformed replay state.", e); }
        if (s.SchemaVersion != 1 || s.SequenceSha256 != sequence.SequenceSha256 || s.CurrentIndex < 0 ||
            s.CurrentIndex > sequence.Events.Length || (!s.Active && s.CurrentIndex != 0) ||
            !double.IsFinite(s.CabinTemperatureF) || s.CabinTemperatureF is < ColdCabinF or > WarmCabinF ||
            (!s.Active && s.CabinTemperatureF != WarmCabinF))
            throw new ArgumentException("Incompatible powerdown replay state.");
        return s;
    }
    public string GetStateJson() => JsonSerializer.Serialize(new ReplayState
        { SchemaVersion=1, SequenceSha256=sequence.SequenceSha256, Active=Active, CurrentIndex=CurrentIndex,
          CabinTemperatureF=CabinTemperatureF }, ElectricalSimulation.JsonOptions);
    public void ValidateStateJson(string json) => Parse(json);
    public void RestoreStateJson(string json)
    {
        var s=Parse(json);
        Active=s.Active; CurrentIndex=s.CurrentIndex;
        CabinTemperatureF = s.CabinTemperatureF;
    }
}

public sealed partial class ElectricalSimulation
{
    internal bool MatchesPowerDownAction(PowerDownAction action) => Is(action.ControlId, action.Position) &&
        (action.Position != "PUSHED" || !tripped.GetValueOrDefault(action.ControlId));

    internal double PowerDownHeatFraction()
    {
        var network = Solve();
        var flood = network.Voltage["LMP_DC"] > 0 && Closed("p16_cb_r02_c01") && !Is("p3_flood_ovhd_fwd", "OFF");
        var inverter = network.Voltage["AC_A"] > 0 || network.Voltage["AC_B"] > 0;
        var guidanceBus = network.Voltage["CDR_DC"] > 0;
        var lgc = guidanceBus && Closed("p11_cb_r04_c19");
        var imu = guidanceBus && Closed("p11_cb_r04_c21");
        return ((flood ? 2 : 0) + (inverter ? 2 : 0) + (lgc ? 3 : 0) + (imu ? 3 : 0)) / 10.0;
    }

    internal void RegisterPowerDownActions(IEnumerable<PowerDownAction> actions)
    {
        var entries=actions.ToArray();
        foreach(var a in entries)
            if (!allowed.TryGetValue(a.ControlId,out var p) || !p.Contains(a.Position) || feedCommands.ContainsKey(a.ControlId))
                throw new ArgumentException("Invalid powerdown action registration.");
        foreach(var a in entries) modeled.Add(a.ControlId);
    }
    internal void ApplyPowerDownActions(PowerDownAction[] actions)
    {
        // Validate the entire batch before any mutation. Sequence commands are
        // branch/selector operations; ECA feed commands need a separate ordering policy.
        foreach (var a in actions)
            if (!allowed.TryGetValue(a.ControlId,out var p) || !p.Contains(a.Position) ||
                feedCommands.ContainsKey(a.ControlId) ||
                (tripped.TryGetValue(a.ControlId,out var trip) && trip && a.Position != "PULLED"))
                throw new ArgumentException("Powerdown command cannot be applied to current electrical state.");
        foreach (var a in actions)
        {
            if (modeled.Contains(a.ControlId)) SetControl(a.ControlId,a.Position);
            // Unquantified selectors are still saved as physical logical state.
            else controls[a.ControlId]=a.Position;
        }
    }
}
