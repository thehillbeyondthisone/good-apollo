using Godot;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;

/// <summary>Thin transport to the unchanged upstream yaAGC process; no replacement CPU logic.</summary>
public partial class VirtualAgcBridge : Node
{
    [Signal] public delegate void DskyUpdatedEventHandler(string snapshotJson);

    private const string RopeSha256 = "ae4f9e51ac9491c3da6462233936daeffc16277cd302c43a70b8459ebcd6cca5";
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private readonly int[] _rows = new int[16];
    private readonly List<byte> _pending = new();
    private readonly Dictionary<int, char> _digitCodes = new()
    {
        [0] = ' ', [21] = '0', [3] = '1', [25] = '2', [27] = '3', [15] = '4',
        [30] = '5', [28] = '6', [19] = '7', [29] = '8', [31] = '9'
    };
    private readonly Dictionary<string, int> _keyCodes = new()
    {
        ["p4_dsky_0"] = 16, ["p4_dsky_1"] = 1, ["p4_dsky_2"] = 2, ["p4_dsky_3"] = 3,
        ["p4_dsky_4"] = 4, ["p4_dsky_5"] = 5, ["p4_dsky_6"] = 6, ["p4_dsky_7"] = 7,
        ["p4_dsky_8"] = 8, ["p4_dsky_9"] = 9, ["p4_dsky_verb"] = 17, ["p4_dsky_rset"] = 18,
        ["p4_dsky_key_rel"] = 25, ["p4_dsky_plus"] = 26, ["p4_dsky_minus"] = 27,
        ["p4_dsky_entr"] = 28, ["p4_dsky_clr"] = 30, ["p4_dsky_noun"] = 31
    };
    private TcpClient? _client;
    private NetworkStream? _stream;
    private Task? _connectionTask;
    private CancellationTokenSource? _connectionCancellation;
    private Process? _ownedProcess;
    private DateTime _ownedStartTime;
    private int _port = 19697;
    private double _retryAt;
    private double _clock;
    private double _emitAt;
    private int _channel11;
    private int _channel13;
    private int _hardwareStatus;
    private long _packetCount;
    private long _keyCount;
    private bool _enabled;
    private bool _connected;
    private bool _dirty;
    private string _status = "Not started";
    private NativeAgcCore? _nativeCore;
    private string _nativeDllHash = "";
    private string _stateError = "";
    private PreparedNativeState? _preparedState;
    private bool _nativeFaulted;
    private const int StartupDelayNanoseconds = 250_000_000;
    private bool _electricalPower = true;
    private int _startupRemainingNanoseconds;
    // Shared time that is outside the current native execution epoch.
    private long _unclockedNanoseconds;
    private sealed record NativeSave(int SchemaVersion, string Backend, string DllSha256,
        string CheckpointBase64, long PacketsReceived, long KeyPressesSent, bool ReleaseMomentariesOnRestore,
        string NativeCycles, uint QuarterNanosecondRemainder, bool? ElectricalPower,
        int StartupRemainingNanoseconds, string UnclockedNanoseconds);
    private sealed record PreparedNativeState(NativeSave Metadata, byte[] Bytes, ulong Cycles, uint QuarterNanosecondRemainder);

    public bool InitializeStepped(string buildRoot = "")
    {
        if (_enabled) return false;
        try
        {
            if (string.IsNullOrEmpty(buildRoot))
            {
                var workspaceBuild = ProjectSettings.GlobalizePath("res://../.cache/agc-power-cycle");
                buildRoot = System.IO.File.Exists(System.IO.Path.Combine(workspaceBuild, "AquariusAgc.dll"))
                    ? workspaceBuild : "D:/apollo-ref/build/agc";
            }
            var library = System.IO.Path.Combine(buildRoot, "AquariusAgc.dll");
            var rope = System.IO.Path.Combine(buildRoot, "LM131R1", "MAIN.agc.bin");
            using (var stream = System.IO.File.OpenRead(library))
                _nativeDllHash = Convert.ToHexStringLower(SHA256.HashData(stream));
            _nativeCore = new NativeAgcCore(library, rope);
            _enabled = _connected = true;
            _status = "LM131R1 live / shared fixed clock / test initialization / flight padload pending";
            SynchronizeNative();
            return true;
        }
        catch (Exception exception)
        {
            _nativeCore?.Dispose();
            _nativeCore = null;
            _enabled = _connected = false;
            _status = exception.Message;
            _stateError = exception.Message;
            return false;
        }
    }

    public bool IsStepped() => _nativeCore != null;
    public string GetLastStateError() => _stateError;
    public bool CanAcceptKey() => _connected && (_nativeCore == null || (_electricalPower && _startupRemainingNanoseconds == 0 && !_nativeFaulted));

    public bool SetElectricalPower(bool powered)
    {
        if (_nativeCore == null || _nativeFaulted) return false;
        if (_electricalPower == powered) return true;
        try
        {
            if (powered)
            {
                var timing = _nativeCore.GetTiming();
                var elapsed = checked((long)(timing.Cycles * 46875UL + timing.QuarterNanosecondRemainder) / 4);
                var nextUnclocked = checked(_unclockedNanoseconds + elapsed);
                _nativeCore.ColdRestart();
                _unclockedNanoseconds = nextUnclocked;
                _startupRemainingNanoseconds = StartupDelayNanoseconds;
            }
            else
            {
                _nativeCore.SetKey(0, false);
                _startupRemainingNanoseconds = 0;
            }
            _electricalPower = powered;
            SynchronizeNative();
            return true;
        }
        catch (Exception exception)
        {
            _stateError = exception.Message;
            _nativeFaulted = true;
            return false;
        }
    }

    private void SynchronizeNative()
    {
        if (_nativeCore == null) return;
        _packetCount += _nativeCore.DrainOutputs();
        var display = _nativeCore.GetDsky();
        for (var index = 0; index < 16; index++) _rows[index] = (int)display.Rows[index];
        _channel11 = (int)display.Channel11;
        _channel13 = (int)display.Channel13;
        _hardwareStatus = (int)display.Channel163;
        _dirty = true;
    }

    public bool AdvanceNanoseconds(long nanoseconds)
    {
        if (_nativeCore == null || _nativeFaulted || nanoseconds < 0 || nanoseconds > 1_000_000_000) return false;
        try
        {
            var inhibited = _electricalPower ? Math.Min(nanoseconds, _startupRemainingNanoseconds) : nanoseconds;
            if (nanoseconds > inhibited)
            {
                _nativeCore.StepNanoseconds((ulong)(nanoseconds - inhibited));
                SynchronizeNative();
            }
            _unclockedNanoseconds = checked(_unclockedNanoseconds + inhibited);
            if (_electricalPower) _startupRemainingNanoseconds -= (int)inhibited;
            return true;
        }
        catch (Exception exception)
        {
            _stateError = exception.Message;
            _nativeFaulted = true;
            return false;
        }
    }

    public int GetInputChannel(int channel)
    {
        if (_nativeCore == null || channel < 0 || channel > 255) return -1;
        return (int)_nativeCore.GetInput((uint)channel);
    }

    public string SaveStateJson()
    {
        if (_nativeCore == null || _nativeFaulted) return "";
        try
        {
            var bytes = _nativeCore.Save();
            var timing = _nativeCore.GetTiming();
            return JsonSerializer.Serialize(new NativeSave(2, "stepped", _nativeDllHash,
                Convert.ToBase64String(bytes), _packetCount, _keyCount, true,
                timing.Cycles.ToString(System.Globalization.CultureInfo.InvariantCulture), timing.QuarterNanosecondRemainder,
                _electricalPower, _startupRemainingNanoseconds,
                _unclockedNanoseconds.ToString(System.Globalization.CultureInfo.InvariantCulture)), JsonOptions);
        }
        catch (Exception exception) { _stateError = exception.Message; return ""; }
    }

    public bool PrepareStateJson(string json)
    {
        _preparedState = null;
        if (_nativeCore == null) return false;
        try
        {
            var saved = JsonSerializer.Deserialize<NativeSave>(json, JsonOptions)
                ?? throw new ArgumentException("AGC save is empty.");
            if (saved.SchemaVersion != 2 || saved.Backend != "stepped" || saved.DllSha256 != _nativeDllHash ||
                !saved.ReleaseMomentariesOnRestore || saved.PacketsReceived < 0 || saved.KeyPressesSent < 0)
                throw new ArgumentException("AGC checkpoint version/backend/build is incompatible.");
            if (!ulong.TryParse(saved.NativeCycles, out var metadataCycles) || saved.QuarterNanosecondRemainder >= 46875)
                throw new ArgumentException("AGC checkpoint timing metadata is invalid.");
            if (!long.TryParse(saved.UnclockedNanoseconds, out var unclocked) || unclocked < 0 ||
                saved.ElectricalPower == null || saved.StartupRemainingNanoseconds < 0 || saved.StartupRemainingNanoseconds > StartupDelayNanoseconds ||
                (saved.StartupRemainingNanoseconds > 0 && (saved.ElectricalPower != true || metadataCycles != 0 || saved.QuarterNanosecondRemainder != 0)))
                throw new ArgumentException("AGC checkpoint power state is invalid.");
            if (saved.CheckpointBase64 == null || saved.CheckpointBase64.Length > 7_000_000)
                throw new ArgumentException("AGC checkpoint is too large.");
            var bytes = Convert.FromBase64String(saved.CheckpointBase64);
            var timing = _nativeCore.InspectCheckpoint(bytes);
            if (metadataCycles != timing.Cycles || saved.QuarterNanosecondRemainder != timing.QuarterNanosecondRemainder)
                throw new ArgumentException("AGC checkpoint timing metadata does not match its native payload.");
            _preparedState = new PreparedNativeState(saved, bytes, timing.Cycles, timing.QuarterNanosecondRemainder);
            _stateError = "";
            return true;
        }
        catch (Exception exception)
        {
            _stateError = exception.Message;
            return false;
        }
    }

    public void AbortPreparedState() => _preparedState = null;

    public string GetPreparedTimingJson() => _preparedState == null ? "{}" : JsonSerializer.Serialize(new
    {
        nativeCycles = _preparedState.Cycles.ToString(System.Globalization.CultureInfo.InvariantCulture),
        quarterNanosecondRemainder = _preparedState.QuarterNanosecondRemainder,
        electricalPower = _preparedState.Metadata.ElectricalPower,
        unclockedNanoseconds = _preparedState.Metadata.UnclockedNanoseconds,
        startupRemainingNanoseconds = _preparedState.Metadata.StartupRemainingNanoseconds
    });

    public bool CommitPreparedState(bool emitSnapshot = true)
    {
        if (_nativeCore == null || _preparedState == null) return false;
        try
        {
            var prepared = _preparedState;
            _nativeCore.Load(prepared.Bytes);
            // A held physical key is released by restore; preserve all other input032 bits.
            _nativeCore.SetKey(0, false);
            _packetCount = prepared.Metadata.PacketsReceived;
            _keyCount = prepared.Metadata.KeyPressesSent;
            _electricalPower = prepared.Metadata.ElectricalPower == true;
            _startupRemainingNanoseconds = prepared.Metadata.StartupRemainingNanoseconds;
            _unclockedNanoseconds = long.Parse(prepared.Metadata.UnclockedNanoseconds, System.Globalization.CultureInfo.InvariantCulture);
            _preparedState = null;
            _nativeFaulted = false;
            SynchronizeNative();
            if (emitSnapshot) EmitSignal(SignalName.DskyUpdated, GetSnapshotJson());
            return true;
        }
        catch (Exception exception)
        {
            _stateError = exception.Message;
            return false;
        }
    }

    public bool Initialize(string buildRoot = "D:/apollo-ref/build/agc", int port = 19697, bool attachExisting = false)
    {
        if (_enabled) return true;
        _port = port;
        try
        {
            if (!attachExisting)
            {
                var executable = System.IO.Path.Combine(buildRoot, "yaAGC.exe");
                var rope = System.IO.Path.Combine(buildRoot, "LM131R1", "MAIN.agc.bin");
                if (!System.IO.File.Exists(executable) || !System.IO.File.Exists(rope))
                    throw new InvalidOperationException("Built yaAGC executable or LM131R1 rope is unavailable.");
                using (var file = System.IO.File.OpenRead(rope))
                {
                    if (!Convert.ToHexStringLower(SHA256.HashData(file)).Equals(RopeSha256, StringComparison.Ordinal))
                        throw new InvalidOperationException("LM131R1 rope does not match its verified SHA-256.");
                }
                for (var candidate = port; candidate < port + 10; candidate++)
                {
                    var listener = new TcpListener(IPAddress.Loopback, candidate);
                    try { listener.Start(); }
                    catch (SocketException) { throw new InvalidOperationException($"AGC port {candidate} is occupied; no existing process was changed."); }
                    finally { listener.Stop(); }
                }
                var sessionDirectory = ProjectSettings.GlobalizePath("user://agc-sessions/" + Guid.NewGuid().ToString("N"));
                System.IO.Directory.CreateDirectory(sessionDirectory);
                var start = new ProcessStartInfo(executable)
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden,
                    WorkingDirectory = sessionDirectory
                };
                foreach (var argument in new[]
                {
                    "--exec=" + rope, "--port=" + port, "--nodebug", "--no-resume", "--quiet",
                    "--dump-time=86400", "--cd=" + sessionDirectory
                }) start.ArgumentList.Add(argument);
                _ownedProcess = Process.Start(start) ?? throw new InvalidOperationException("Could not start yaAGC.");
                _ownedStartTime = _ownedProcess.StartTime;
            }
            _enabled = true;
            _status = attachExisting ? "Attaching to explicitly selected yaAGC" : "Starting owned upstream yaAGC";
            _dirty = true;
            return true;
        }
        catch (Exception exception)
        {
            _status = exception.Message;
            _dirty = true;
            return false;
        }
    }

    public override void _Process(double delta)
    {
        _clock += delta;
        if (_enabled && _nativeCore == null)
        {
            if (_ownedProcess is { HasExited: true })
            {
                Disconnect("Owned yaAGC process exited.");
                _enabled = false;
            }
            if (_enabled && !_connected && _clock >= _retryAt) TryConnect();
            if (_enabled && _connected) ReadPackets();
        }
        if (_dirty && _clock >= _emitAt)
        {
            _emitAt = _clock + 0.03;
            _dirty = false;
            EmitSignal(SignalName.DskyUpdated, GetSnapshotJson());
        }
    }

    private void TryConnect()
    {
        if (_connectionTask == null)
        {
            _client = new TcpClient { NoDelay = true };
            _connectionCancellation = new CancellationTokenSource(TimeSpan.FromSeconds(1));
            _connectionTask = _client.ConnectAsync(IPAddress.Loopback, _port, _connectionCancellation.Token).AsTask();
            return;
        }
        if (!_connectionTask.IsCompleted) return;
        if (_connectionTask.IsCompletedSuccessfully && _client != null)
        {
            _stream = _client.GetStream();
            _connected = true;
            _pending.Clear();
            Array.Clear(_rows);
            _channel11 = 0;
            _channel13 = 0;
            _hardwareStatus = 0;
            _status = "LM131R1 live / test initialization / flight padload pending";
            SendPacket(282, 8192); // Client mask for active-low PRO discrete only.
            SendPacket(26, 8192);  // Release PRO on every connection; never replay old presses.
            _dirty = true;
        }
        else
        {
            _client?.Dispose();
            _client = null;
            _retryAt = _clock + 0.5;
        }
        _connectionTask = null;
        _connectionCancellation?.Dispose();
        _connectionCancellation = null;
    }

    private void ReadPackets()
    {
        if (_client == null || _stream == null) return;
        try
        {
            if (_client.Client.Poll(0, SelectMode.SelectRead) && _client.Available == 0)
            {
                Disconnect("yaAGC transport disconnected; waiting to reconnect.");
                return;
            }
            var buffer = new byte[4096];
            while (_stream.DataAvailable)
            {
                var count = _stream.Read(buffer, 0, buffer.Length);
                if (count == 0) { Disconnect("yaAGC stream closed."); return; }
                for (var index = 0; index < count; index++) _pending.Add(buffer[index]);
            }
            while (_pending.Count >= 4)
            {
                if ((_pending[0] & 0xC0) != 0 || (_pending[1] & 0xC0) != 0x40 ||
                    (_pending[2] & 0xC0) != 0x80 || (_pending[3] & 0xC0) != 0xC0)
                {
                    _pending.RemoveAt(0);
                    continue;
                }
                var uBit = (_pending[0] & 0x20) != 0;
                var channel = ((_pending[0] & 0x1F) << 3) | ((_pending[1] >> 3) & 7);
                var value = ((_pending[1] & 7) << 12) | ((_pending[2] & 63) << 6) | (_pending[3] & 63);
                _pending.RemoveRange(0, 4);
                _packetCount++;
                if (uBit) continue;
                if (channel == 8) _rows[(value >> 11) & 15] = value;
                else if (channel == 9) _channel11 = value;
                else if (channel == 11) _channel13 = value;
                else if (channel == 115) _hardwareStatus = value;
                _dirty = true;
            }
        }
        catch (Exception exception) when (exception is System.IO.IOException or SocketException or ObjectDisposedException)
        {
            Disconnect("yaAGC transport interrupted; waiting to reconnect.");
        }
    }

    private void Disconnect(string message)
    {
        _stream?.Dispose();
        _client?.Dispose();
        _stream = null;
        _client = null;
        _connected = false;
        _status = message;
        _retryAt = _clock + 0.5;
        _dirty = true;
    }

    private bool SendPacket(int channel, int value)
    {
        if (!_connected || _stream == null) return false;
        try
        {
            _stream.Write(new byte[]
            {
                (byte)((channel >> 3) & 0x3F),
                (byte)(0x40 | ((channel << 3) & 0x38) | ((value >> 12) & 7)),
                (byte)(0x80 | ((value >> 6) & 63)), (byte)(0xC0 | (value & 63))
            });
            return true;
        }
        catch (Exception exception) when (exception is System.IO.IOException or SocketException or ObjectDisposedException)
        {
            Disconnect("yaAGC write failed; key was not replayed.");
            return false;
        }
    }

    public bool SetKey(string controlId, bool pressed)
    {
        if (_nativeCore != null)
        {
            if (!CanAcceptKey()) return false;
            var nativeCode = controlId == "p4_dsky_pro" ? 0 : _keyCodes.GetValueOrDefault(controlId, -1);
            if (nativeCode < 0) return false;
            _nativeCore.SetKey((uint)nativeCode, pressed);
            if (pressed && nativeCode != 0) _keyCount++;
            SynchronizeNative();
            return true;
        }
        if (controlId == "p4_dsky_pro") return SendPacket(26, pressed ? 0 : 8192);
        if (!pressed || !_keyCodes.TryGetValue(controlId, out var code)) return false;
        var sent = SendPacket(13, code);
        if (sent) _keyCount++;
        return sent;
    }

    public int GetOwnedProcessId() => _ownedProcess is { HasExited: false } ? _ownedProcess.Id : 0;

    public bool IsProcessAlive(int processId)
    {
        if (processId <= 0) return false;
        try
        {
            using var process = Process.GetProcessById(processId);
            return !process.HasExited;
        }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
        catch (System.ComponentModel.Win32Exception) { return true; } // Unknown is never proof of cleanup.
    }

    private char Left(int row) => _digitCodes.GetValueOrDefault((_rows[row] >> 5) & 31, '?');
    private char Right(int row) => _digitCodes.GetValueOrDefault(_rows[row] & 31, '?');
    private char Sign(int plusRow, int minusRow) => (_rows[plusRow] & 0x400) != 0 ? '+' : (_rows[minusRow] & 0x400) != 0 ? '-' : ' ';

    public string GetSnapshotJson()
    {
        var active = CanAcceptKey();
        var powered = active && (_hardwareStatus & 0x200) == 0;
        var verbNounVisible = powered && (_hardwareStatus & 0x20) == 0;
        var values = new Dictionary<string, string>
        {
            ["p4_dsky_prog_display"] = powered ? $"{Left(11)}{Right(11)}" : "",
            ["p4_dsky_verb_display"] = verbNounVisible ? $"{Left(10)}{Right(10)}" : "",
            ["p4_dsky_noun_display"] = verbNounVisible ? $"{Left(9)}{Right(9)}" : "",
            ["p4_dsky_r1_display"] = powered ? $"{Sign(7, 6)}{Right(8)}{Left(7)}{Right(7)}{Left(6)}{Right(6)}" : "",
            ["p4_dsky_r2_display"] = powered ? $"{Sign(5, 4)}{Left(5)}{Right(5)}{Left(4)}{Right(4)}{Left(3)}" : "",
            ["p4_dsky_r3_display"] = powered ? $"{Sign(2, 1)}{Right(3)}{Left(2)}{Right(2)}{Left(1)}{Right(1)}" : ""
        };
        var status = _rows[12];
        var lamps = new Dictionary<string, bool>
        {
            ["p4_dsky_comptr_acty_light"] = (_channel11 & 0x2) != 0,
            ["p4_dsky_uplink_acty_light"] = (_channel11 & 0x4) != 0,
            ["p4_dsky_temp_light"] = (_hardwareStatus & 0x8) != 0,
            ["p4_dsky_key_rel_light"] = (_hardwareStatus & 0x10) != 0,
            ["p4_dsky_opr_err_light"] = (_hardwareStatus & 0x40) != 0,
            ["p4_dsky_restart_light"] = (_hardwareStatus & 0x80) != 0,
            ["p4_dsky_stby_light"] = (_hardwareStatus & 0x100) != 0,
            ["p4_dsky_no_att_light"] = (status & 0x8) != 0,
            ["p4_dsky_gimbal_lock_light"] = (status & 0x20) != 0,
            ["p4_dsky_prog_light"] = (status & 0x100) != 0,
            ["p4_dsky_tracker_light"] = (status & 0x80) != 0,
            ["p4_dsky_alt_light"] = (status & 0x10) != 0,
            ["p4_dsky_vel_light"] = (status & 0x4) != 0
        };
        if (!active) foreach (var key in lamps.Keys.ToArray()) lamps[key] = false;
        return JsonSerializer.Serialize(new
        {
            Connected = _connected, Status = _status, Rope = "LM131R1", FlightPadloadApplied = false,
            Initialization = "test initialization", CpuClock = _nativeCore == null ? "external real time; not simulation-stepped" : "shared fixed simulation clock",
            Backend = _nativeCore == null ? "external_cli" : "stepped",
            NativeCycles = _nativeCore?.GetTiming().Cycles.ToString() ?? "",
            QuarterNanosecondRemainder = _nativeCore?.GetTiming().QuarterNanosecondRemainder ?? 0,
            CpuPowerState = _nativeCore == null ? "external" : !_electricalPower ? "off" : _startupRemainingNanoseconds > 0 ? "starting" : "operating",
            StartupRemainingNanoseconds = _startupRemainingNanoseconds,
            PoweredByAgcHardwareStatus = powered, LampTestAlarm = active && (_channel13 & 0x200) != 0, Readouts = values, Lamps = lamps,
            PacketsReceived = _packetCount, KeyPressesSent = _keyCount
        }, JsonOptions);
    }

    public override void _ExitTree()
    {
        _nativeCore?.Dispose();
        _nativeCore = null;
        SendPacket(26, 8192);
        _enabled = false;
        _connectionCancellation?.Cancel();
        Disconnect("Stopped");
        if (_ownedProcess != null)
        {
            try
            {
                if (!_ownedProcess.HasExited && _ownedProcess.StartTime == _ownedStartTime)
                {
                    _ownedProcess.Kill(false);
                    _ownedProcess.WaitForExit(1000);
                }
            }
            catch (InvalidOperationException) { }
            finally { _ownedProcess.Dispose(); _ownedProcess = null; }
        }
        _connectionCancellation?.Dispose();
    }
}
