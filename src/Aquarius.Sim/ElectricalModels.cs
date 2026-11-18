namespace Aquarius.Sim;

public sealed class ElectricalDefinition
{
    public int SchemaVersion { get; set; }
    public double FixedStepSeconds { get; set; } = 0.25;
    public BatteryDefinition[] Batteries { get; set; } = [];
    public BreakerDefinition[] Breakers { get; set; } = [];
    public BusTieDefinition[] Ties { get; set; } = [];
    public InverterDefinition[] Inverters { get; set; } = [];
    public AggregateLoadDefinition[] Loads { get; set; } = [];
    public EquipmentLoadDefinition[] EquipmentLoads { get; set; } = [];
    public PoweredControlDefinition[] PoweredControls { get; set; } = [];
    public ElectricalPreset[] Presets { get; set; } = [];
}

public sealed class BatteryDefinition
{
    public string Id { get; set; } = "";
    public string Stage { get; set; } = "";
    public double CapacityAh { get; set; }
    public double NominalVoltageV { get; set; }
    public double LowTapVoltageV { get; set; }
    public string NormalBusId { get; set; } = "";
    public string BackupBusId { get; set; } = "";
    public string HighControlId { get; set; } = "";
    public string LowControlId { get; set; } = "";
    public string NormalControlId { get; set; } = "";
    public string BackupControlId { get; set; } = "";
    public string[] FeedBreakerIds { get; set; } = [];
}

public sealed class BreakerDefinition
{
    public string ControlId { get; set; } = "";
    public string Label { get; set; } = "";
    public string BusId { get; set; } = "";
    public string Role { get; set; } = "";
    public double? RatedCurrentA { get; set; }
}
public sealed class BusTieDefinition
{
    public string Id { get; set; } = "";
    public string BusA { get; set; } = "";
    public string BusB { get; set; } = "";
    public string[] BreakerIds { get; set; } = [];
}
public sealed class InverterDefinition
{
    public string Id { get; set; } = "";
    public string InputBreakerId { get; set; } = "";
    public string SourceBusId { get; set; } = "";
    public string Selection { get; set; } = "";
    public string AcABreakerId { get; set; } = "";
    public string AcBBreakerId { get; set; } = "";
}
public sealed class AggregateLoadDefinition
{
    public string Id { get; set; } = "";
    public string BusId { get; set; } = "";
    public double NominalShare { get; set; }
}
public sealed class PoweredControlDefinition
{
    public string ControlId { get; set; } = "";
    public string[] BreakerIds { get; set; } = [];
    public SwitchRequirement[] SwitchRequirements { get; set; } = [];
}
public sealed class SwitchRequirement
{
    public string ControlId { get; set; } = "";
    public string[] AllowedPositions { get; set; } = [];
}
public sealed class ElectricalPreset
{
    public string Id { get; set; } = "";
    public string Description { get; set; } = "";
    public double AggregateCurrentA { get; set; }
    public string LoadModel { get; set; } = "aggregate";
    public double? InitialTotalRemainingAh { get; set; }
    public Dictionary<string, string> Controls { get; set; } = [];
}

public sealed record BatterySnapshot(string Id, string Stage, double VoltageV,
    double RemainingAh, double CapacityAh, double CurrentA, double ConsumedAh,
    double ConsumedWh, bool Connected, bool Fault);
public sealed record BusSnapshot(string Id, double VoltageV, double CurrentA, bool Powered);
public sealed record LoadSnapshot(string Id, string BusId, double CurrentA, bool Powered,
    bool CurrentKnown, string Model, double PowerW = 0, string SourceId = "");
public sealed record BreakerSnapshot(string ControlId, string BusId, bool Closed, bool Tripped,
    bool Powered, double CurrentA, bool CurrentKnown, double? RatedCurrentA);
public sealed record ElectricalSnapshot(double SimulationTimeSeconds, string Preset,
    BatterySnapshot[] Batteries, BusSnapshot[] Buses, LoadSnapshot[] Loads,
    BreakerSnapshot[] Breakers, Dictionary<string, bool> Indicators,
    Dictionary<string, double> MeterValues, Dictionary<string, bool> MeterValid,
    Dictionary<string, bool> PoweredControls, Dictionary<string, string> ControlPositions,
    double InitialTotalAh, double ConsumedAh, double ConsumedWh,
    string Fidelity, string[] Limitations)
{
    public string LoadModel { get; init; } = "aggregate";
    public bool CompleteEquipmentLoadCoverage { get; init; }
    public CautionWarningSnapshot? CautionWarning { get; init; }
    public ElectricalAccountingSnapshot? Accounting { get; init; }
}
