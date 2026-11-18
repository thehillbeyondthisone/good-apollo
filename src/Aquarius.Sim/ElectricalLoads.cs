namespace Aquarius.Sim;

/// <summary>A sourced operating load, separate from a protective breaker rating.</summary>
public sealed class EquipmentLoadDefinition
{
    public string Id { get; set; } = "";
    public string Label { get; set; } = "";
    public string BusId { get; set; } = "";
    public string[] BreakerIds { get; set; } = [];
    public SwitchRequirement[] SwitchRequirements { get; set; } = [];
    public double? PowerW { get; set; }
    public double? CurrentA { get; set; }
    public string SourceId { get; set; } = "";
    public string Qualification { get; set; } = "";
}

public sealed partial class ElectricalSimulation
{
    private void ConfigureEquipmentLoads()
    {
        if (definition.EquipmentLoads is null) throw new ArgumentException("Missing equipment load catalog.");
        var ids = definition.Loads.Select(l => l.Id).ToHashSet(StringComparer.Ordinal);
        foreach (var load in definition.EquipmentLoads)
        {
            if (load is null) throw new ArgumentException("Null equipment load entry.");
            if (string.IsNullOrWhiteSpace(load.Id) || !ids.Add(load.Id) ||
                !BusIds.Contains(load.BusId) || string.IsNullOrWhiteSpace(load.SourceId) ||
                string.IsNullOrWhiteSpace(load.Qualification))
                throw new ArgumentException($"Invalid equipment load identity/source: {load.Id}");
            if (load.PowerW.HasValue == load.CurrentA.HasValue ||
                !double.IsFinite(load.PowerW ?? load.CurrentA ?? double.NaN) ||
                (load.PowerW ?? load.CurrentA) <= 0)
                throw new ArgumentException($"Equipment load requires one positive watts/amps value: {load.Id}");
            if (load.BreakerIds is null || load.SwitchRequirements is null || load.BreakerIds.Length == 0 || load.BreakerIds.Distinct().Count() != load.BreakerIds.Length)
                throw new ArgumentException($"Equipment load requires a unique supply path: {load.Id}");
            foreach (var id in load.BreakerIds)
            {
                RequireBreaker(id);
                if (definition.Breakers.Single(b => b.ControlId == id).BusId != load.BusId)
                    throw new ArgumentException($"Equipment supply breaker is on a different bus: {load.Id}/{id}");
            }
            foreach (var requirement in load.SwitchRequirements)
            {
                if (requirement is null) throw new ArgumentException($"Null equipment operating state: {load.Id}");
                RequireControl(requirement.ControlId);
                if (requirement.AllowedPositions is null || requirement.AllowedPositions.Length == 0 ||
                    requirement.AllowedPositions.Any(p => !allowed[requirement.ControlId].Contains(p)))
                    throw new ArgumentException($"Invalid equipment operating state: {load.Id}");
            }
        }
        foreach (var p in definition.Presets)
        {
            if (p.LoadModel is not ("aggregate" or "sourced_components") ||
                !double.IsFinite(p.AggregateCurrentA) || p.AggregateCurrentA < 0 ||
                (p.LoadModel == "sourced_components" && (p.AggregateCurrentA != 0 || definition.EquipmentLoads.Length == 0)))
                throw new ArgumentException($"Invalid or double-counted load model: {p.Id}");
        }
    }

    private bool EquipmentEnabled(EquipmentLoadDefinition load, Network n) =>
        n.Voltage[load.BusId] > 0 && load.BreakerIds.All(Closed) &&
        load.SwitchRequirements.All(r => r.AllowedPositions.Contains(controls[r.ControlId]));

    private double EquipmentAmps(EquipmentLoadDefinition load, Network n) =>
        EquipmentEnabled(load, n) ? load.CurrentA ?? load.PowerW!.Value / n.Voltage[load.BusId] : 0;

    private LoadSnapshot[] LoadSnapshots(Network n) => loadModel == "aggregate"
        ? definition.Loads.Select(l => new LoadSnapshot(l.Id, l.BusId, n.LoadCurrent.GetValueOrDefault(l.Id),
            n.Voltage[l.BusId] > 0, true, "Source-calibrated aggregate; component decomposition unknown",
            n.LoadCurrent.GetValueOrDefault(l.Id) * n.Voltage[l.BusId])).ToArray()
        : definition.EquipmentLoads.Select(l => new LoadSnapshot(l.Id, l.BusId, n.LoadCurrent.GetValueOrDefault(l.Id),
            EquipmentEnabled(l, n), true, l.Qualification,
            n.LoadCurrent.GetValueOrDefault(l.Id) * n.Voltage[l.BusId], l.SourceId)).ToArray();
}
