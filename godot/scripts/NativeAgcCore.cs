using System.Runtime.InteropServices;
using System.Reflection;

/// <summary>Main-thread ABI adapter to the pinned, unchanged upstream CPU core.</summary>
internal sealed class NativeAgcCore : IDisposable
{
    private const string LibraryName = "AquariusAgc";
    private static IntPtr _library;
    private IntPtr _context;
    private readonly int _creatingThread = Environment.CurrentManagedThreadId;

    static NativeAgcCore()
    {
        NativeLibrary.SetDllImportResolver(typeof(NativeAgcCore).Assembly, ResolveLibrary);
    }

    private static IntPtr ResolveLibrary(string name, Assembly assembly, DllImportSearchPath? searchPath) =>
        name == LibraryName ? _library : IntPtr.Zero;

    public NativeAgcCore(string libraryPath, string ropePath)
    {
        if (_library == IntPtr.Zero) _library = NativeLibrary.Load(libraryPath);
        if (Aagc_GetAbiVersion() != 1 || !NativeLibrary.TryGetExport(_library, "Aagc_ColdRestart", out _))
            throw new InvalidOperationException("The native AGC library must support electrical restart. Rebuild it with tools/agc/build-stepped.ps1.");
        _context = Aagc_Create(ropePath);
        if (_context == IntPtr.Zero) throw new InvalidOperationException(LastError());
    }

    private void AssertThread()
    {
        if (_context == IntPtr.Zero) throw new ObjectDisposedException(nameof(NativeAgcCore));
        if (Environment.CurrentManagedThreadId != _creatingThread)
            throw new InvalidOperationException("Native AGC calls must stay on their creating main thread.");
    }

    private static string LastError() => Marshal.PtrToStringUTF8(Aagc_LastError()) ?? "Unknown native AGC error.";
    private static void Check(int result) { if (result < 0) throw new InvalidOperationException(LastError()); }

    public void StepNanoseconds(ulong nanoseconds)
    {
        AssertThread();
        Check(Aagc_StepNanoseconds(_context, nanoseconds));
    }

    public void ColdRestart()
    {
        AssertThread();
        Check(Aagc_ColdRestart(_context));
    }

    public void SetKey(uint code, bool pressed)
    {
        AssertThread();
        Check(Aagc_SetKey(_context, code, pressed ? 1u : 0u));
    }

    public uint GetInput(uint channel)
    {
        AssertThread();
        Check(Aagc_GetInput(_context, channel, out var value));
        return value;
    }

    public long DrainOutputs()
    {
        AssertThread();
        long count = 0;
        int result;
        while ((result = Aagc_PollOutput(_context, out _, out _)) == 1) count++;
        Check(result);
        return count;
    }

    public (uint[] Rows, uint Channel11, uint Channel13, uint Channel163, ulong Cycles) GetDsky()
    {
        AssertThread();
        var rows = new uint[16];
        Check(Aagc_GetDsky(_context, rows, out var channel11, out var channel13, out var channel163, out var cycles));
        return (rows, channel11, channel13, channel163, cycles);
    }

    public (ulong Cycles, uint QuarterNanosecondRemainder) GetTiming()
    {
        AssertThread();
        Check(Aagc_GetTiming(_context, out var cycles, out var remainder));
        return (cycles, remainder);
    }

    public byte[] Save()
    {
        AssertThread();
        var size = Aagc_CheckpointSize(_context);
        if (size < 152 || size > 5_000_000) throw new InvalidOperationException("Native checkpoint size is invalid.");
        var bytes = new byte[size];
        Check(Aagc_Save(_context, bytes, size));
        return bytes;
    }

    public (ulong Cycles, uint QuarterNanosecondRemainder) InspectCheckpoint(byte[] bytes)
    {
        AssertThread();
        if (bytes.Length < 152 || bytes.Length > 5_000_000) throw new InvalidOperationException("Native checkpoint size is invalid.");
        Check(Aagc_GetCheckpointTiming(_context, bytes, (uint)bytes.Length, out var cycles, out var remainder));
        return (cycles, remainder);
    }

    public void Load(byte[] bytes)
    {
        AssertThread();
        Check(Aagc_Load(_context, bytes, (uint)bytes.Length));
    }

    public void Dispose()
    {
        if (_context == IntPtr.Zero) return;
        AssertThread();
        Aagc_Destroy(_context);
        _context = IntPtr.Zero;
    }

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern uint Aagc_GetAbiVersion();
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern IntPtr Aagc_LastError();
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern IntPtr Aagc_Create([MarshalAs(UnmanagedType.LPUTF8Str)] string ropePath);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern void Aagc_Destroy(IntPtr context);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern int Aagc_StepNanoseconds(IntPtr context, ulong nanoseconds);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern int Aagc_ColdRestart(IntPtr context);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern int Aagc_SetKey(IntPtr context, uint code, uint pressed);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern int Aagc_GetInput(IntPtr context, uint channel, out uint value);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern int Aagc_PollOutput(IntPtr context, out uint channel, out uint value);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern int Aagc_GetDsky(IntPtr context, [Out] uint[] rows, out uint channel11, out uint channel13, out uint channel163, out ulong cycles);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern int Aagc_GetTiming(IntPtr context, out ulong cycles, out uint remainder);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern uint Aagc_CheckpointSize(IntPtr context);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern int Aagc_Save(IntPtr context, [Out] byte[] bytes, uint size);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern int Aagc_GetCheckpointTiming(IntPtr context, [In] byte[] bytes, uint size, out ulong cycles, out uint quarterNanosecondRemainder);
    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)] private static extern int Aagc_Load(IntPtr context, [In] byte[] bytes, uint size);
}
