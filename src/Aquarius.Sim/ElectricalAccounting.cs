using System.Text.Json.Serialization;

namespace Aquarius.Sim;

/// <summary>Charge and energy at the LM source boundary, not charge restored to a CM battery.</summary>
public sealed record ElectricalConsumptionSnapshot(double ConsumedAh, double ConsumedWh,
    double CurrentA, double PowerW);

public sealed record ElectricalAccountingSnapshot(ElectricalConsumptionSnapshot Source,
    ElectricalConsumptionSnapshot LmEquipment, ElectricalConsumptionSnapshot CmExport,
    ElectricalConsumptionSnapshot SyntheticFault, ElectricalConsumptionSnapshot UnclassifiedAggregate,
    string CmExportSourceBusId, double CmExportDemandA)
{
    public bool RestoredCmChargeModeled => false;
    public string Boundary => "LM battery-source charge/energy. CM export is input drawn from the LM bus; restored CM battery charge is not modeled.";
    public string Qualification => "Known equipment only in sourced-components mode. Aggregate calibration is unclassified and cannot receive an additional export demand. No flight waveform or usable-reserve model is implied.";
}

public sealed partial class ElectricalSimulation
{
    private sealed class ConsumptionState
    {
        [JsonRequired] public double Ah { get; set; }
        [JsonRequired] public double Wh { get; set; }
        public void Add(double ah, double wh) { Ah += ah; Wh += wh; }
    }

    private sealed class AccountingState
    {
        [JsonRequired] public ConsumptionState LmEquipment { get; set; } = new();
        [JsonRequired] public ConsumptionState CmExport { get; set; } = new();
        [JsonRequired] public ConsumptionState SyntheticFault { get; set; } = new();
        [JsonRequired] public ConsumptionState UnclassifiedAggregate { get; set; } = new();
        [JsonRequired] public string CmExportSourceBusId { get; set; } = "LMP_DC";
        [JsonRequired] public double CmExportDemandA { get; set; }
    }

    private sealed record DemandPartition(double Equipment, double Export, double Fault, double Aggregate)
    {
        public double Total => Equipment + Export + Fault + Aggregate;
    }

    private AccountingState accounting = new();

    /// <summary>
    /// Explicit scenario input at the LM DC bus. This is neither a charger-efficiency
    /// model nor an inferred historical schedule. An aggregate current may already
    /// include export, so positive export is accepted only with sourced loads.
    /// </summary>
    public void SetCmExportDemand(string sourceBusId, double currentA)
    {
        if (sourceBusId is not ("CDR_DC" or "LMP_DC")) throw new ArgumentException("CM export requires a declared DC source bus.", nameof(sourceBusId));
        if (!double.IsFinite(currentA) || currentA < 0) throw new ArgumentOutOfRangeException(nameof(currentA));
        if (currentA > 0 && loadModel != "sourced_components")
            throw new ArgumentException("An aggregate current has no resolved export boundary; additional CM export would risk double counting.", nameof(currentA));
        accounting.CmExportSourceBusId = sourceBusId;
        accounting.CmExportDemandA = currentA;
    }

    private void AttributeConsumption(Network n, string batteryId, double ah, double wh)
    {
        if (!n.BatteryDemand.TryGetValue(batteryId, out var d) || d.Total <= 0) return;
        accounting.LmEquipment.Add(ah * d.Equipment / d.Total, wh * d.Equipment / d.Total);
        accounting.CmExport.Add(ah * d.Export / d.Total, wh * d.Export / d.Total);
        accounting.SyntheticFault.Add(ah * d.Fault / d.Total, wh * d.Fault / d.Total);
        accounting.UnclassifiedAggregate.Add(ah * d.Aggregate / d.Total, wh * d.Aggregate / d.Total);
    }

    private ElectricalAccountingSnapshot AccountingSnapshot(Network n)
    {
        double Current(Func<DemandPartition, double> select) => n.BatteryDemand.Sum(p => select(p.Value));
        double Power(Func<DemandPartition, double> select) => n.BatteryDemand.Sum(p => select(p.Value) * n.BatteryVoltage[p.Key]);
        ElectricalConsumptionSnapshot Part(ConsumptionState value, Func<DemandPartition, double> select) => new(value.Ah, value.Wh, Current(select), Power(select));
        return new(new(batteries.Values.Sum(b => b.ConsumedAh), batteries.Values.Sum(b => b.ConsumedWh),
                n.BatteryCurrent.Values.Sum(), n.BatteryCurrent.Sum(p => p.Value * n.BatteryVoltage[p.Key])),
            Part(accounting.LmEquipment, d => d.Equipment), Part(accounting.CmExport, d => d.Export),
            Part(accounting.SyntheticFault, d => d.Fault), Part(accounting.UnclassifiedAggregate, d => d.Aggregate),
            accounting.CmExportSourceBusId, accounting.CmExportDemandA);
    }

    private static void ValidateAccounting(AccountingState? state, string model, IEnumerable<BatteryState> sources)
    {
        if (state is null || state.LmEquipment is null || state.CmExport is null || state.SyntheticFault is null || state.UnclassifiedAggregate is null)
            throw new ArgumentException("Missing source accounting ledger.");
        var parts = new[] { state.LmEquipment, state.CmExport, state.SyntheticFault, state.UnclassifiedAggregate };
        if (parts.Any(p => !double.IsFinite(p.Ah) || p.Ah < 0 || !double.IsFinite(p.Wh) || p.Wh < 0) ||
            state.CmExportSourceBusId is not ("CDR_DC" or "LMP_DC") ||
            !double.IsFinite(state.CmExportDemandA) || state.CmExportDemandA < 0)
            throw new ArgumentException("Invalid source accounting ledger.");
        if ((model == "aggregate" && (state.CmExportDemandA != 0 || state.CmExport.Ah != 0 || state.CmExport.Wh != 0 || state.LmEquipment.Ah != 0 || state.LmEquipment.Wh != 0)) ||
            (model == "sourced_components" && (state.UnclassifiedAggregate.Ah != 0 || state.UnclassifiedAggregate.Wh != 0)))
            throw new ArgumentException("Saved source accounting contradicts the load boundary.");
        if (Math.Abs(parts.Sum(p => p.Ah) - sources.Sum(b => b.ConsumedAh)) > 1e-6 ||
            Math.Abs(parts.Sum(p => p.Wh) - sources.Sum(b => b.ConsumedWh)) > 1e-6)
            throw new ArgumentException("Saved source accounting is not conserved.");
    }
}
