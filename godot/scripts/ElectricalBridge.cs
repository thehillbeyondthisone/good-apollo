using System.Text.Json;
using Aquarius.Sim;
using Godot;

/// <summary>Thin engine adapter. Electrical equations and saved state live in Aquarius.Sim.</summary>
public partial class ElectricalBridge : Node
{
    [Signal] public delegate void ElectricalUpdatedEventHandler(string snapshotJson);

    private ElectricalSimulation? _simulation;
    private bool _automaticStep = true;
    private double _emitAccumulator;
    private string _lastError = "Not initialized";
    private string _electricalJson = "";
    private string _controlsJson = "";
    private ElectricalSimulation? _preparedSimulation;
    private ElectricalPowerDownSequence? _powerDownSequence;
    private ElectricalSequenceReplay? _powerDownReplay;
    private ElectricalSequenceReplay? _preparedPowerDownReplay;

    public bool Initialize(string electricalPath, string controlsPath, string preset = "electrical_checkout")
    {
        try
        {
            _electricalJson = System.IO.File.ReadAllText(electricalPath);
            _controlsJson = System.IO.File.ReadAllText(controlsPath);
            _simulation = ElectricalSimulation.FromJson(_electricalJson, _controlsJson);
            _simulation.ApplyPreset(preset);
            _lastError = "";
            EmitSnapshot();
            return true;
        }
        catch (Exception exception)
        {
            _simulation = null;
            _lastError = exception.Message;
            return false;
        }
    }

    public bool IsAvailable() => _simulation != null;
    public bool HasLgcPower() => _simulation?.IsBreakerPowered("p11_cb_r04_c19") == true;
    public string GetLastError() => _lastError;
    public void SetAutomaticStep(bool enabled) => _automaticStep = enabled;

    public bool InitializePowerDown(string sequencePath)
    {
        if (_simulation == null) return false;
        try
        {
            _powerDownSequence = ElectricalPowerDownSequence.FromJson(
                System.IO.File.ReadAllText(sequencePath), _controlsJson);
            _powerDownReplay = new ElectricalSequenceReplay(_simulation, _powerDownSequence);
            _lastError = "";
            return true;
        }
        catch (Exception exception) { _lastError = exception.Message; return false; }
    }

    public bool StartPowerDown()
    {
        if (_powerDownReplay == null) return false;
        try
        {
            _powerDownReplay.Start();
            _lastError = "";
            EmitSnapshot();
            return true;
        }
        catch (Exception exception) { _lastError = exception.Message; return false; }
    }

    public string NextPowerDownEvent()
    {
        if (_powerDownReplay == null) return "";
        try
        {
            var step = _powerDownReplay.NextEvent();
            _lastError = "";
            EmitSnapshot();
            return step == null ? "" : JsonSerializer.Serialize(step, ElectricalSimulation.JsonOptions);
        }
        catch (Exception exception) { _lastError = exception.Message; return ""; }
    }

    public bool ConfirmPowerDownCallout()
    {
        if (_powerDownReplay?.ConfirmCallout() != true) return false;
        EmitSnapshot();
        return true;
    }

    public bool EnterColdCoast()
    {
        if (_powerDownReplay?.EnterColdCoast() != true) return false;
        EmitSnapshot();
        return true;
    }

    public string SavePowerDownStateJson() => _powerDownReplay?.GetStateJson() ?? "";

    public string GetPowerDownSnapshotJson()
    {
        if (_powerDownReplay == null || _powerDownSequence == null) return "{}";
        var active = _powerDownReplay.Active;
        var index = _powerDownReplay.CurrentIndex;
        return JsonSerializer.Serialize(new {
            active, currentIndex = index, eventCount = _powerDownSequence.Events.Length,
            lastEvent = active && index > 0 ? _powerDownSequence.Events[index - 1] : null,
            nextEvent = _powerDownReplay.NextCallout,
            pendingActions = _powerDownReplay.PendingActions(),
            cabinTemperatureF = _powerDownReplay.CabinTemperatureF
        }, ElectricalSimulation.JsonOptions);
    }

    public bool PreparePowerDownStateJson(string json)
    {
        if (_preparedSimulation == null || _powerDownSequence == null) return false;
        try
        {
            var candidate = new ElectricalSequenceReplay(_preparedSimulation, _powerDownSequence);
            candidate.RestoreStateJson(json);
            _preparedPowerDownReplay = candidate;
            _lastError = "";
            return true;
        }
        catch (Exception exception) { _lastError = exception.Message; return false; }
    }

    public bool SetCmExportDemand(string sourceBusId, double currentA)
    {
        if (_simulation == null) return false;
        try
        {
            _simulation.SetCmExportDemand(sourceBusId, currentA);
            _lastError = "";
            EmitSnapshot();
            return true;
        }
        catch (ArgumentException exception) { _lastError = exception.Message; return false; }
    }

    public override void _PhysicsProcess(double delta)
    {
        if (!_automaticStep || _simulation == null) return;
        Step(delta);
        _emitAccumulator += delta;
        if (_emitAccumulator >= 0.1)
        {
            _emitAccumulator %= 0.1;
            EmitSnapshot();
        }
    }

    public bool SetControl(string id, string positionLabel)
    {
        if (_simulation == null) return false;
        if (_powerDownReplay?.Active == true && id == "p16_cb_r04_c01" && positionLabel == "PULLED")
        {
            _lastError = "Panel 16 Quad 1 heater breaker was sealed closed on Aquarius.";
            EmitSnapshot();
            return false;
        }
        _lastError = "";
        var accepted = _simulation.SetControl(id, positionLabel);
        EmitSnapshot();
        return accepted;
    }

    public bool ApplyPreset(string name)
    {
        if (_simulation == null) return false;
        try
        {
            _simulation.ApplyPreset(name);
            _powerDownReplay?.Cancel();
            _lastError = "";
            EmitSnapshot();
            return true;
        }
        catch (ArgumentException exception)
        {
            _lastError = exception.Message;
            return false;
        }
    }

    public bool Advance(double seconds)
    {
        if (_simulation == null) return false;
        try
        {
            Step(seconds);
            EmitSnapshot();
            return true;
        }
        catch (ArgumentOutOfRangeException exception)
        {
            _lastError = exception.Message;
            return false;
        }
    }

    public bool AdvanceShared(double seconds)
    {
        if (_simulation == null) return false;
        try { Step(seconds); return true; }
        catch (ArgumentException exception) { _lastError = exception.Message; return false; }
    }

    private void Step(double seconds)
    {
        _simulation!.FixedStep(seconds);
        _powerDownReplay?.AdvanceCabinTemperature(seconds);
    }

    public void PublishSnapshot() => EmitSnapshot();

    public bool PrepareStateJson(string json)
    {
        _preparedSimulation = null;
        _preparedPowerDownReplay = null;
        if (_simulation == null) return false;
        try
        {
            var candidate = ElectricalSimulation.FromJson(_electricalJson, _controlsJson);
            candidate.LoadJson(json);
            _preparedSimulation = candidate;
            _lastError = "";
            return true;
        }
        catch (Exception exception) { _lastError = exception.Message; return false; }
    }

    public void AbortPreparedState()
    {
        _preparedSimulation = null;
        _preparedPowerDownReplay = null;
    }

    public string GetPreparedSnapshotJson() => _preparedSimulation == null ? "{}" :
        JsonSerializer.Serialize(_preparedSimulation.GetSnapshot(), ElectricalSimulation.JsonOptions);

    public bool WriteAtomicText(string path, string text)
    {
        var temporary = path + ".writing-" + Guid.NewGuid().ToString("N");
        try
        {
            var directory = System.IO.Path.GetDirectoryName(path);
            if (string.IsNullOrEmpty(directory)) throw new ArgumentException("Checkpoint directory is required.");
            System.IO.Directory.CreateDirectory(directory);
            using (var file = new System.IO.FileStream(temporary, System.IO.FileMode.CreateNew,
                System.IO.FileAccess.Write, System.IO.FileShare.None))
            {
                var bytes = System.Text.Encoding.UTF8.GetBytes(text);
                file.Write(bytes);
                file.Flush(true);
            }
            System.IO.File.Move(temporary, path, true);
            _lastError = "";
            return true;
        }
        catch (Exception exception)
        {
            _lastError = exception.Message;
            try { if (System.IO.File.Exists(temporary)) System.IO.File.Delete(temporary); }
            catch (System.IO.IOException) { }
            return false;
        }
    }

    public bool CommitPreparedState(bool emitSnapshot = true)
    {
        if (_preparedSimulation == null) return false;
        _simulation = _preparedSimulation;
        _powerDownReplay = _preparedPowerDownReplay ?? (_powerDownSequence == null ? null :
            new ElectricalSequenceReplay(_simulation, _powerDownSequence));
        _preparedSimulation = null;
        _preparedPowerDownReplay = null;
        if (emitSnapshot) EmitSnapshot();
        return true;
    }

    public string[] GetModeledControlIds() => _simulation?.ModeledControlIds.ToArray() ?? [];
    public string[] GetAvailablePresets() => _simulation?.AvailablePresets.ToArray() ?? [];
    public string GetSnapshotJson() => _simulation == null
        ? JsonSerializer.Serialize(new { available = false, error = _lastError })
        : JsonSerializer.Serialize(_simulation.GetSnapshot(), ElectricalSimulation.JsonOptions);
    public string SaveStateJson()
    {
        if (_simulation == null) return "";
        try { return _simulation.SaveJson(); }
        catch (Exception exception) { _lastError = exception.Message; return ""; }
    }

    public bool LoadStateJson(string json)
    {
        if (_simulation == null) return false;
        try
        {
            _simulation.LoadJson(json);
            if (_powerDownSequence != null)
                _powerDownReplay = new ElectricalSequenceReplay(_simulation, _powerDownSequence);
            _lastError = "";
            EmitSnapshot();
            return true;
        }
        catch (Exception exception)
        {
            _lastError = exception.Message;
            return false;
        }
    }

    public bool InjectBranchFault(string controlId, double currentA)
    {
        if (_simulation == null) return false;
        try
        {
            _simulation.InjectBranchFault(controlId, currentA);
            return true;
        }
        catch (ArgumentException exception)
        {
            _lastError = exception.Message;
            return false;
        }
    }

    public bool SetBatteryFault(string batteryId, bool fault)
    {
        if (_simulation == null) return false;
        try
        {
            _simulation.SetBatteryFault(batteryId, fault);
            EmitSnapshot();
            return true;
        }
        catch (ArgumentException exception)
        {
            _lastError = exception.Message;
            return false;
        }
    }

    private void EmitSnapshot() => EmitSignal(SignalName.ElectricalUpdated, GetSnapshotJson());
}
