using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Nodes;

namespace Aquarius.Sim;

public sealed class ElectricalFlightSource
{
    public string Id { get; set; } = "";
    public string Role { get; set; } = "";
    public string Title { get; set; } = "";
    public string Url { get; set; } = "";
    public string Locator { get; set; } = "";
    public string Qualification { get; set; } = "";
}

public sealed class ElectricalFlightConfiguration
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string[] SourceIds { get; set; } = [];
    public string Qualification { get; set; } = "";
    public string InitialPreset { get; set; } = "sourced_equipment_checkout";
    public Dictionary<string, string> Controls { get; set; } = [];
    public string[] Assumptions { get; set; } = [];
    public string[] UnknownLoads { get; set; } = [];
    public Dictionary<string, double> AdditionalLoadDutyFractions { get; set; } = [];
    public bool Complete { get; set; }
    public string CmExportSourceBusId { get; set; } = "LMP_DC";
    public double CmExportDemandA { get; set; }
}

public sealed class ElectricalFlightCurrentComparison
{
    public string Id { get; set; } = "";
    public string ConfigurationId { get; set; } = "";
    public double? ObservedMinA { get; set; }
    public double? ObservedMaxA { get; set; }
    public double? AdditionalToleranceA { get; set; }
    public string[] SourceIds { get; set; } = [];
    public string Qualification { get; set; } = "";
}

public sealed class ElectricalFlightHistoryEvent
{
    public int GetSeconds { get; set; }
    public Dictionary<string, string> Controls { get; set; } = [];
    public string[] SourceIds { get; set; } = [];
    public string Qualification { get; set; } = "";
    public string? CmExportSourceBusId { get; set; }
    public double? CmExportDemandA { get; set; }
}

public sealed class ElectricalFlightHistorySample
{
    public string Id { get; set; } = "";
    public int GetSeconds { get; set; }
    public string? BatteryId { get; set; }
    public string Metric { get; set; } = "";
    public double? ObservedMin { get; set; }
    public double? ObservedMax { get; set; }
    public double? Tolerance { get; set; }
    public string[] SourceIds { get; set; } = [];
    public string Qualification { get; set; } = "";
    public bool BeforeEvents { get; set; }
}

public sealed class ElectricalFlightHistoryCase
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string InitialConfigurationId { get; set; } = "";
    public int StartGetSeconds { get; set; }
    public int EndGetSeconds { get; set; }
    public Dictionary<string, double>? InitialRemainingAh { get; set; }
    // Historical delivered charge before the replay epoch is a separately
    // reported offset. It never changes the simulation's conserved ledgers.
    public Dictionary<string, double>? InitialConsumedAh { get; set; }
    public string[] SourceIds { get; set; } = [];
    public ElectricalFlightHistoryEvent[] Events { get; set; } = [];
    public ElectricalFlightHistorySample[] Samples { get; set; } = [];
    public string[] Qualifications { get; set; } = [];
}

public sealed class ElectricalFlightManifest
{
    public int SchemaVersion { get; set; }
    public string Title { get; set; } = "";
    public string Qualification { get; set; } = "";
    public string InventorySha256 { get; set; } = "";
    public string ElectricalSha256 { get; set; } = "";
    public ElectricalFlightSource[] Sources { get; set; } = [];
    public EquipmentLoadDefinition[] AdditionalEquipmentLoads { get; set; } = [];
    public string[] UncertainDutyLoadIds { get; set; } = [];
    public ElectricalFlightConfiguration[] Configurations { get; set; } = [];
    public ElectricalFlightCurrentComparison[] CurrentComparisons { get; set; } = [];
    public ElectricalFlightHistoryCase[] HistoryCases { get; set; } = [];
}

public sealed record ElectricalFlightAgreement(double Prediction, double? ObservedMin,
    double? ObservedMax, double? AdditionalTolerance, double? DifferenceFromMidpoint,
    double? DistanceOutsideObservedInterval, bool? WithinTolerance, string Status);
public sealed record ElectricalFlightConfigurationResult(string Id, string Title,
    string[] SourceIds, string Qualification, string[] Assumptions, string[] UnknownLoads,
    Dictionary<string, string> SkippedUnmodeledCommands,
    Dictionary<string, double> AdditionalLoadDutyFractions, string EffectiveElectricalSha256,
    double SettlingSeconds, double PreProtectionSourceCurrentA, string[] ProtectionTrippedBreakerIds,
    double SourceCurrentA, ElectricalSnapshot Snapshot);
public sealed record ElectricalFlightCurrentResult(string Id, string ConfigurationId,
    string[] SourceIds, string Qualification, ElectricalFlightAgreement Comparison);
public sealed record ElectricalFlightHistorySampleResult(string Id, int GetSeconds,
    string? BatteryId, string Metric, string EventPhase, string[] SourceIds, string Qualification,
    ElectricalFlightAgreement Comparison, BatterySnapshot[] Batteries,
    ElectricalAccountingSnapshot Accounting);
public sealed record ElectricalFlightHistoryEventResult(int GetSeconds,
    Dictionary<string, string> SkippedUnmodeledCommands, string[] SourceIds, string Qualification);
public sealed record ElectricalFlightHistoryResult(string Id, string Title, int StartGetSeconds,
    int EndGetSeconds, string InitialConfigurationId, string[] SourceIds,
    string[] Qualifications, Dictionary<string, double>? InitialConsumedAh,
    double SourceConsumedAh, double SourceConsumedWh, double InitialTotalAh,
    double TotalRemainingAh, double ChargeConservationErrorAh,
    double AccountingConservationErrorAh, double AccountingConservationErrorWh,
    BatterySnapshot[] FinalBatteries, ElectricalAccountingSnapshot FinalAccounting,
    ElectricalFlightHistoryEventResult[] Events,
    ElectricalFlightHistorySampleResult[] Samples);
public sealed record ElectricalFlightValidationReport(int SchemaVersion, string Kind,
    string ManifestSha256, string InventorySha256, string ElectricalSha256, string EffectiveElectricalSha256,
    bool IndependentFlightValidationPassed, bool CompleteEquipmentLoadCoverage,
    string Qualification, string[] Limitations, ElectricalFlightSource[] Sources,
    EquipmentLoadDefinition[] AdditionalEquipmentLoads, string[] UncertainDutyLoadIds,
    ElectricalFlightConfigurationResult[] Configurations,
    ElectricalFlightCurrentResult[] CurrentComparisons,
    ElectricalFlightHistoryResult[] HistoryCases);

/// <summary>
/// Runs component-only switch configurations and time-tagged battery histories.
/// Observations are compared only after execution; no observed current, reserve,
/// midpoint or difference is used to construct a load or replenish a battery.
/// </summary>
public static class ElectricalFlightValidation
{
    private static readonly JsonSerializerOptions ManifestOptions = new(ElectricalSimulation.JsonOptions)
        { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    private static string Hash(string value) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value)));

    public static ElectricalFlightValidationReport Run(string manifestJson, string electricalJson, string controlsJson)
    {
        ElectricalFlightManifest data;
        try { data = JsonSerializer.Deserialize<ElectricalFlightManifest>(manifestJson, ManifestOptions)
            ?? throw new ArgumentException("Empty electrical flight manifest."); }
        catch (JsonException error) { throw new ArgumentException("Malformed electrical flight manifest.", nameof(manifestJson), error); }
        Validate(data, electricalJson, controlsJson);
        var effectiveJson = EffectiveDefinition(data, electricalJson);
        var configs = data.Configurations.ToDictionary(c => c.Id, StringComparer.Ordinal);
        var predictions = data.Configurations.Select(c =>
        {
            var configJson = EffectiveDefinition(data, electricalJson, c);
            var sim = MakeConfiguration(c, configJson, controlsJson);
            var preProtectionCurrent = sim.GetSnapshot().Accounting!.Source.CurrentA;
            sim.FixedStep(sim.FixedTimeStepSeconds);
            var s = sim.GetSnapshot();
            var skipped = c.Controls.Where(p => !sim.ModeledControlIds.Contains(p.Key)).ToDictionary(p => p.Key, p => p.Value);
            return new ElectricalFlightConfigurationResult(c.Id, c.Title, c.SourceIds, c.Qualification,
                c.Assumptions, c.UnknownLoads, skipped, c.AdditionalLoadDutyFractions, Hash(configJson),
                sim.FixedTimeStepSeconds, preProtectionCurrent, s.Breakers.Where(b => b.Tripped).Select(b => b.ControlId).ToArray(),
                s.Accounting!.Source.CurrentA, s);
        }).ToArray();
        var currents = predictions.ToDictionary(c => c.Id, c => c.SourceCurrentA, StringComparer.Ordinal);
        var comparisons = data.CurrentComparisons.Select(c => new ElectricalFlightCurrentResult(
            c.Id, c.ConfigurationId, c.SourceIds, c.Qualification,
            Compare(currents[c.ConfigurationId], c.ObservedMinA, c.ObservedMaxA, c.AdditionalToleranceA))).ToArray();
        var histories = data.HistoryCases.Select(h => RunHistory(h, configs[h.InitialConfigurationId],
            EffectiveDefinition(data, electricalJson, configs[h.InitialConfigurationId]), controlsJson)).ToArray();
        return new(1, "Component-load predictions and qualified battery-history replay", Hash(manifestJson),
            Hash(controlsJson), Hash(electricalJson), Hash(effectiveJson), false, false, data.Qualification,
            ["Unknown equipment demand is excluded; numerical agreement does not establish complete flight validation.",
             "Source and observation roles are separate; measurements never set aggregate loads or unknown residuals.",
             "Additional-load duty fractions are explicit constant scenario assumptions, not recovered thermostat histories.",
             "Initial preset and configuration assumptions are explicit. Unspecified controls retain the named sandbox preset.",
             "Inventory-valid commands without modeled electrical behavior are retained in skipped-command reports; their physical state and draw are not simulated.",
             "Ideal voltage sources share equally within each conducting bus group; actual unequal battery sharing is not recovered.",
             "Battery remaining charge uses total ideal capacity, not temperature-dependent usable reserve.",
             "Initial consumed-Ah offsets, when supplied, are historical inputs outside the replay's conserved ledgers.",
             "Current configurations settle one normal protection tick; any tripped breakers are reported.",
             "History samples explicitly select before/after same-time events. Elapsed GET intervals advance the EPS model only.",
             "No computer memory, fluid system, trajectory or native whole-session time is advanced by this offline report.",
             "A null comparison tolerance is not assessed; no acceptance band is inferred from missing evidence."],
            data.Sources, data.AdditionalEquipmentLoads, data.UncertainDutyLoadIds, predictions, comparisons, histories);
    }

    private static string EffectiveDefinition(ElectricalFlightManifest manifest, string baseJson, ElectricalFlightConfiguration? configuration = null)
    {
        if (manifest.AdditionalEquipmentLoads.Length == 0) return baseJson;
        var node = JsonNode.Parse(baseJson)!;
        var loads = node["equipmentLoads"]!.AsArray();
        foreach (var load in manifest.AdditionalEquipmentLoads)
        {
            var duty = configuration?.AdditionalLoadDutyFractions.GetValueOrDefault(load.Id, 1) ?? 1;
            if (duty == 0) continue;
            var value = JsonSerializer.SerializeToNode(load, ElectricalSimulation.JsonOptions)!;
            if (load.PowerW.HasValue) value["powerW"] = load.PowerW.Value * duty;
            else value["currentA"] = load.CurrentA!.Value * duty;
            loads.Add(value);
        }
        return node.ToJsonString(ElectricalSimulation.JsonOptions);
    }

    private static ElectricalSimulation MakeConfiguration(ElectricalFlightConfiguration c, string electricalJson, string controlsJson)
    {
        var sim = ElectricalSimulation.FromJson(electricalJson, controlsJson);
        sim.ApplyPreset(c.InitialPreset);
        ApplyControls(sim, c.Controls, controlsJson);
        sim.SetCmExportDemand(c.CmExportSourceBusId, c.CmExportDemandA);
        if (sim.GetSnapshot().LoadModel != "sourced_components") throw new ArgumentException("Flight predictions require component-only loads.");
        return sim;
    }

    private static Dictionary<string, string> ApplyControls(ElectricalSimulation sim, Dictionary<string, string> values, string controlsJson)
    {
        using var inventory = JsonDocument.Parse(controlsJson);
        var positions = inventory.RootElement.GetProperty("controls").EnumerateArray().ToDictionary(
            c => c.GetProperty("id").GetString()!, c => c.GetProperty("positions").EnumerateArray().Select(p => p.GetString()!).ToArray());
        var modeled = sim.ModeledControlIds.ToHashSet(StringComparer.Ordinal);
        var skipped = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var item in values)
        {
            if (!positions.TryGetValue(item.Key, out var allowed) || !allowed.Contains(item.Value))
                throw new ArgumentException($"Unknown inventory control or invalid flight command: {item.Key}/{item.Value}");
            if (!modeled.Contains(item.Key)) { skipped.Add(item.Key, item.Value); continue; }
            if (!sim.SetControl(item.Key, item.Value))
                throw new ArgumentException($"Invalid or interlocked flight command: {item.Key}/{item.Value}");
        }
        return skipped;
    }

    private static ElectricalFlightHistoryResult RunHistory(ElectricalFlightHistoryCase h,
        ElectricalFlightConfiguration c, string electricalJson, string controlsJson)
    {
        var sim = MakeConfiguration(c, electricalJson, controlsJson);
        if (h.InitialRemainingAh is not null) sim.SetInitialBatteryRemainingAh(h.InitialRemainingAh);
        var initial = sim.GetSnapshot();
        var times = h.Events.Select(e => e.GetSeconds).Concat(h.Samples.Select(s => s.GetSeconds))
            .Append(h.EndGetSeconds).Distinct().Order().ToArray();
        var sampleResults = new List<ElectricalFlightHistorySampleResult>();
        var eventResults = new List<ElectricalFlightHistoryEventResult>();
        var now = h.StartGetSeconds;
        foreach (var at in times)
        {
            var seconds = at - now;
            while (seconds > 0)
            {
                var batch = Math.Min(seconds, 86400);
                sim.AdvanceStableHistory(batch);
                seconds -= batch;
            }
            now = at;
            void TakeSamples(bool beforeEvents)
            {
                foreach (var sample in h.Samples.Where(s => s.GetSeconds == at && s.BeforeEvents == beforeEvents))
                {
                    var snapshot = sim.GetSnapshot();
                    var value = Metric(snapshot, sample, h.InitialConsumedAh);
                    sampleResults.Add(new(sample.Id, at, sample.BatteryId, sample.Metric,
                        beforeEvents ? "before_events" : "after_events", sample.SourceIds,
                        sample.Qualification, Compare(value, sample.ObservedMin, sample.ObservedMax, sample.Tolerance),
                        snapshot.Batteries, snapshot.Accounting!));
                }
            }
            TakeSamples(true);
            foreach (var e in h.Events.Where(e => e.GetSeconds == at))
            {
                var skipped = ApplyControls(sim, e.Controls, controlsJson);
                eventResults.Add(new(e.GetSeconds, skipped, e.SourceIds, e.Qualification));
                if (e.CmExportDemandA.HasValue)
                    sim.SetCmExportDemand(e.CmExportSourceBusId ?? sim.GetSnapshot().Accounting!.CmExportSourceBusId, e.CmExportDemandA.Value);
            }
            TakeSamples(false);
        }
        var final = sim.GetSnapshot();
        var a = final.Accounting!;
        var parts = new[] { a.LmEquipment, a.CmExport, a.SyntheticFault, a.UnclassifiedAggregate };
        return new(h.Id, h.Title, h.StartGetSeconds, h.EndGetSeconds, h.InitialConfigurationId,
            h.SourceIds, h.Qualifications, h.InitialConsumedAh, final.ConsumedAh, final.ConsumedWh,
            initial.InitialTotalAh, final.Batteries.Sum(b => b.RemainingAh),
            final.Batteries.Sum(b => b.RemainingAh) + final.ConsumedAh - initial.InitialTotalAh,
            parts.Sum(p => p.ConsumedAh) - a.Source.ConsumedAh,
            parts.Sum(p => p.ConsumedWh) - a.Source.ConsumedWh,
            final.Batteries, a, eventResults.ToArray(), sampleResults.ToArray());
    }

    private static double Metric(ElectricalSnapshot s, ElectricalFlightHistorySample sample, Dictionary<string, double>? baseline)
    {
        var battery = sample.BatteryId is null ? null : s.Batteries.Single(b => b.Id == sample.BatteryId);
        return sample.Metric switch
        {
            "sourceCurrentA" => s.Accounting!.Source.CurrentA,
            "totalConsumedAh" => s.ConsumedAh + (baseline?.Values.Sum() ?? 0),
            "totalRemainingAh" => s.Batteries.Sum(b => b.RemainingAh),
            "batteryConsumedAh" => battery!.ConsumedAh + (baseline?.GetValueOrDefault(battery.Id) ?? 0),
            "batteryRemainingAh" => battery!.RemainingAh,
            "batteryCurrentA" => battery!.CurrentA,
            _ => throw new ArgumentException($"Unsupported history metric: {sample.Metric}")
        };
    }

    private static ElectricalFlightAgreement Compare(double prediction, double? min, double? max, double? tolerance)
    {
        if (min is null) return new(prediction, null, null, tolerance, null, null, null, "NO_OBSERVATION");
        var outside = prediction < min ? min - prediction : prediction > max ? prediction - max : 0;
        var within = tolerance.HasValue ? prediction >= min - tolerance && prediction <= max + tolerance : (bool?)null;
        return new(prediction, min, max, tolerance, prediction - (min + max) / 2, outside, within,
            !tolerance.HasValue ? "NOT_ASSESSED_NO_TOLERANCE" : within == true ? "WITHIN_INTERVAL_PARTIAL_COVERAGE" : "OUTSIDE_INTERVAL");
    }

    private static void Validate(ElectricalFlightManifest d, string electricalJson, string controlsJson)
    {
        static bool Blank(string? s) => string.IsNullOrWhiteSpace(s);
        static void Require(bool test, string message) { if (!test) throw new ArgumentException(message); }
        static void Texts(string[]? values, string label, bool nonempty = true) => Require(values is not null &&
            (!nonempty || values.Length > 0) && values.All(s => !Blank(s)) && values.Distinct(StringComparer.Ordinal).Count() == values.Length,
            $"Missing, duplicate or blank {label}.");
        static void Interval(double? min, double? max, double? tol) => Require(
            min.HasValue == max.HasValue && (!min.HasValue || double.IsFinite(min.Value) &&
            double.IsFinite(max!.Value) && min >= 0 && max >= min) &&
            (!tol.HasValue || double.IsFinite(tol.Value) && tol >= 0), "Invalid observed interval/tolerance.");
        Require(d.SchemaVersion == 1 && !Blank(d.Title) && !Blank(d.Qualification) &&
            d.InventorySha256 == Hash(controlsJson) && d.ElectricalSha256 == Hash(electricalJson), "Flight manifest version/reference mismatch.");
        Require(d.Sources is { Length: > 0 } && d.Configurations is { Length: > 0 } &&
            d.CurrentComparisons is not null && d.HistoryCases is not null && d.AdditionalEquipmentLoads is not null, "Missing flight manifest collections.");
        var sources = new Dictionary<string, ElectricalFlightSource>(StringComparer.Ordinal);
        foreach (var s in d.Sources!)
        {
            Require(s is not null && !Blank(s.Id) && s.Role is "model_input" or "validation_observation" &&
                !Blank(s.Title) && !Blank(s.Url) && !Blank(s.Locator) && !Blank(s.Qualification) && sources.TryAdd(s.Id, s), "Invalid/duplicate flight source receipt.");
        }
        void SourceIds(string[]? ids, string role)
        {
            Texts(ids, "source identifiers");
            Require(ids!.All(id => sources.TryGetValue(id, out var source) && source.Role == role), "Unknown source or observation used as a model input.");
        }
        foreach (var load in d.AdditionalEquipmentLoads!)
            Require(load is not null && sources.TryGetValue(load.SourceId, out var source) && source.Role == "model_input",
                "Additional equipment load requires a model-input source receipt.");
        Texts(d.UncertainDutyLoadIds, "uncertain-duty equipment identifiers", false);
        Require(d.UncertainDutyLoadIds.All(id => d.AdditionalEquipmentLoads.Any(l => l.Id == id)),
            "Every uncertain-duty identifier must name an additional equipment load.");
        // Validate the unscaled overlay too: a zero-duty scenario must not hide
        // malformed power values, duplicate IDs or an invalid supply path.
        ElectricalSimulation.FromJson(EffectiveDefinition(d, electricalJson), controlsJson);
        var configs = new HashSet<string>(StringComparer.Ordinal);
        var batteryDefs = JsonSerializer.Deserialize<ElectricalDefinition>(electricalJson, ElectricalSimulation.JsonOptions)!.Batteries;
        var batteryIds = batteryDefs.Select(b => b.Id).ToHashSet(StringComparer.Ordinal);
        foreach (var c in d.Configurations!)
        {
            Require(c is not null && !Blank(c.Id) && configs.Add(c.Id) && !Blank(c.Title) && !Blank(c.Qualification) &&
                c.InitialPreset == "sourced_equipment_checkout" && !c.Complete && c.Controls is not null,
                "Invalid/duplicate partial flight configuration.");
            SourceIds(c!.SourceIds, "model_input"); Texts(c.UnknownLoads, "unknown equipment loads"); Texts(c.Assumptions, "configuration assumptions");
            Require(c.AdditionalLoadDutyFractions is not null &&
                c.AdditionalLoadDutyFractions.Keys.ToHashSet(StringComparer.Ordinal).SetEquals(d.UncertainDutyLoadIds) &&
                c.AdditionalLoadDutyFractions.All(v => double.IsFinite(v.Value) && v.Value >= 0 && v.Value <= 1),
                "Every declared uncertain-duty load requires one explicit finite fraction from zero to one; other equipment cannot be rescaled.");
            MakeConfiguration(c, EffectiveDefinition(d, electricalJson, c), controlsJson);
        }
        var idsSeen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var c in d.CurrentComparisons!)
        {
            Require(c is not null && !Blank(c.Id) && idsSeen.Add(c.Id) && configs.Contains(c.ConfigurationId) && !Blank(c.Qualification), "Invalid current comparison.");
            SourceIds(c!.SourceIds, "validation_observation"); Interval(c.ObservedMinA, c.ObservedMaxA, c.AdditionalToleranceA);
        }
        idsSeen.Clear();
        foreach (var h in d.HistoryCases!)
        {
            Require(h is not null && !Blank(h.Id) && idsSeen.Add(h.Id) && !Blank(h.Title) && configs.Contains(h.InitialConfigurationId) &&
                h.StartGetSeconds >= 0 && h.EndGetSeconds > h.StartGetSeconds &&
                h.Events is not null && h.Samples is not null, "Invalid flight history case.");
            SourceIds(h!.SourceIds, "model_input"); Texts(h.Qualifications, "history qualifications");
            void BatteryInputs(Dictionary<string, double>? values)
            {
                if (values is null) return;
                Require(values.Keys.ToHashSet(StringComparer.Ordinal).SetEquals(batteryIds) &&
                    values.All(v => double.IsFinite(v.Value) && v.Value >= 0 && v.Value <= batteryDefs.Single(b => b.Id == v.Key).CapacityAh),
                    "Historical initial battery values require every source, within rated capacity.");
            }
            BatteryInputs(h.InitialRemainingAh); BatteryInputs(h.InitialConsumedAh);
            Require(h.InitialConsumedAh is null || h.InitialConsumedAh.Values.All(v => v == 0) || h.InitialRemainingAh is not null,
                "Nonzero historical delivered charge requires an explicit compatible initial remaining-capacity allocation.");
            if (h.InitialRemainingAh is not null && h.InitialConsumedAh is not null)
                Require(batteryIds.All(id => h.InitialRemainingAh[id] + h.InitialConsumedAh[id] <= batteryDefs.Single(b => b.Id == id).CapacityAh + 1e-8),
                    "Initial battery remaining plus historical delivered charge exceeds capacity.");
            var prior = h.StartGetSeconds;
            foreach (var e in h.Events!)
            {
                Require(e is not null && e.GetSeconds >= prior && e.GetSeconds <= h.EndGetSeconds && e.Controls is not null && !Blank(e.Qualification), "Invalid or unordered history event.");
                SourceIds(e!.SourceIds, "model_input");
                Require(e.CmExportSourceBusId is null || e.CmExportDemandA.HasValue, "Export bus event requires an explicit demand.");
                Require(!e.CmExportDemandA.HasValue || double.IsFinite(e.CmExportDemandA.Value) && e.CmExportDemandA >= 0 &&
                    (e.CmExportSourceBusId is null or "LMP_DC" or "CDR_DC"), "Invalid export demand event.");
                prior = e.GetSeconds;
            }
            var sampleIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (var s in h.Samples!)
            {
                Require(s is not null && !Blank(s.Id) && sampleIds.Add(s.Id) && !Blank(s.Qualification) &&
                    s.GetSeconds >= h.StartGetSeconds && s.GetSeconds <= h.EndGetSeconds, "Invalid history sample.");
                var needsBattery = s!.Metric is "batteryConsumedAh" or "batteryRemainingAh" or "batteryCurrentA";
                Require(s.Metric is "sourceCurrentA" or "totalConsumedAh" or "totalRemainingAh" || needsBattery, "Unknown historical metric.");
                Require(needsBattery ? s.BatteryId is not null && batteryIds.Contains(s.BatteryId) : s.BatteryId is null, "Historical sample battery/metric mismatch.");
                Interval(s.ObservedMin, s.ObservedMax, s.Tolerance);
                if (s.ObservedMin.HasValue || s.SourceIds is not { Length: 0 })
                    SourceIds(s.SourceIds, "validation_observation");
            }
        }
    }
}
