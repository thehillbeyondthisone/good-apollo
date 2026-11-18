using System.Text.Json;
using Aquarius.Sim;

var root = new DirectoryInfo(Environment.CurrentDirectory);
while (root != null && !File.Exists(Path.Combine(root.FullName, "reference", "electrical.json"))) root = root.Parent;
if (root == null) throw new InvalidOperationException("Run from the goodapollo repository.");
var electrical = File.ReadAllText(Path.Combine(root.FullName, "reference", "electrical.json"));
var controls = File.ReadAllText(Path.Combine(root.FullName, "reference", "controls.json"));
var command = args.FirstOrDefault() ?? "snapshot";
if (command == "flight-validation")
{
    var manifest = File.ReadAllText(Path.Combine(root.FullName, "reference", "electrical-flight-configurations.json"));
    var report = ElectricalFlightValidation.Run(manifest, electrical, controls);
    var json = JsonSerializer.Serialize(report, ElectricalSimulation.JsonOptions);
    if (args.Length > 1)
    {
        var path = Path.GetFullPath(args[1]);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, json + Environment.NewLine);
        Console.WriteLine(JsonSerializer.Serialize(new { reportPath = path,
            report.IndependentFlightValidationPassed, report.CompleteEquipmentLoadCoverage,
            configurations = report.Configurations.Length, comparisons = report.CurrentComparisons.Length,
            historyCases = report.HistoryCases.Length }, ElectricalSimulation.JsonOptions));
    }
    else Console.WriteLine(json);
    return;
}
if (command is "reported-budget" or "profile-audit")
{
    // These are source-based accounting scenarios, not simulation runs. Their
    // chronology, assumptions and calculations have one reproducible authority.
    var auditPath = Path.Combine(root.FullName, "reference", "electrical-flight-audit.json");
    using var audit = JsonDocument.Parse(File.ReadAllText(auditPath));
    if (audit.RootElement.GetProperty("schemaVersion").GetInt32() != 1)
        throw new InvalidDataException("Unsupported electrical flight audit schema.");
    var report = audit.RootElement.GetProperty(command == "profile-audit" ? "profileAudit" : "reportedBudget");
    Console.WriteLine(JsonSerializer.Serialize(report, ElectricalSimulation.JsonOptions));
    return;
}
if (command == "powerdown")
{
    var sequence = ElectricalPowerDownSequence.FromJson(
        File.ReadAllText(Path.Combine(root.FullName, "reference", "electrical-powerdown-sequence.json")), controls);
    var model = ElectricalSimulation.FromJson(electrical, controls);
    var replay = new ElectricalSequenceReplay(model, sequence);
    replay.Start();
    var count = args.Length > 1 ? int.Parse(args[1], System.Globalization.CultureInfo.InvariantCulture) : sequence.Events.Length;
    if (count < 0 || count > sequence.Events.Length) throw new ArgumentOutOfRangeException(nameof(count));
    var steps = new List<object>();
    for (var index = 0; index < count; index++)
    {
        var step = replay.NextEvent();
        var snapshot = model.GetSnapshot();
        steps.Add(new { step, knownSourceCurrentA = snapshot.Buses.Where(b => b.Id.EndsWith("_DC")).Sum(b => b.CurrentA) });
    }
    Console.WriteLine(JsonSerializer.Serialize(new {
        kind = "Source-confirmed guided switching replay", flightValidationPassed = false,
        qualification = "Sourced-equipment checkout seed; unknown loads excluded. Mission GET labels do not advance elapsed time. Physical-only actions are reported but have no invented electrical demand.",
        steps, replayState = JsonSerializer.Deserialize<JsonElement>(replay.GetStateJson()), snapshot = model.GetSnapshot()
    }, ElectricalSimulation.JsonOptions));
    return;
}
if (command == "cm-export-checkout")
{
    var model = ElectricalSimulation.FromJson(electrical, controls);
    model.ApplyPreset("sourced_equipment_checkout");
    var seconds = args.Length > 1 ? double.Parse(args[1], System.Globalization.CultureInfo.InvariantCulture) : 3600;
    var amps = args.Length > 2 ? double.Parse(args[2], System.Globalization.CultureInfo.InvariantCulture) : 8;
    model.SetCmExportDemand(args.ElementAtOrDefault(3) ?? "CDR_DC", amps);
    model.FixedStep(seconds);
    Console.WriteLine(JsonSerializer.Serialize(new {
        kind = "Synthetic CM-export accounting checkout", flightValidationPassed = false,
        qualification = "Explicit ideal DC-bus export demand; not a recovered CM circuit, charge history or restored CM battery charge.",
        snapshot = model.GetSnapshot()
    }, ElectricalSimulation.JsonOptions));
    return;
}
if (command != "snapshot") throw new ArgumentException("Commands: snapshot [preset] [seconds], powerdown [stepCount], cm-export-checkout [seconds] [amps] [sourceBus], flight-validation [reportPath], profile-audit, reported-budget");
var sim = ElectricalSimulation.FromJson(electrical, controls);
sim.ApplyPreset(args.ElementAtOrDefault(1) ?? "minimum_lifeboat_12a");
if (args.Length > 2) sim.FixedStep(double.Parse(args[2], System.Globalization.CultureInfo.InvariantCulture));
Console.WriteLine(JsonSerializer.Serialize(sim.GetSnapshot(), ElectricalSimulation.JsonOptions));
