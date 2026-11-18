# Deterministic LM131R1 CPU adapter

The native adapter runs the unchanged, pinned Virtual AGC CPU and exact LM131R1 fixed rope under a caller-controlled clock. The desktop launcher prepares the workspace adapter at `.cache/agc-power-cycle/AquariusAgc.dll` from the pinned tools and rope in `D:\apollo-ref`. The adapter starts with upstream default channels and zero erasable test initialization. **No Apollo 13 padload or flown activation checkpoint is applied.** The external upstream `yaAGC.exe` remains the independent reference and fallback.

Every one of 287 DSKY/alarm output events matches the original deterministic fixture's cycle, channel and value. Its V35 frame matches the genuine upstream CLI/TCP frame. Save/restore/replay reproduces full checkpoint bytes and output event schedules. A separate synthetic stress test activates nonzero coarse XYZ and gyro accumulators before checkpointing and proves their replay. The power restart test seeds synthetic erasable words and checks that LM131R1 increments the retained restart counter.

## Clock and ABI

The stable Cdecl ABI1 is declared in `tools/agc/aquarius-agc.h`. Functions use fixed-width integers and an opaque context pointer. Only one context may exist per loaded DLL, and all operations must use the creating thread. This is deliberate: upstream still has shared peripheral statics. A second context is rejected.

| Call | Contract |
|---|---|
|`Aagc_Create(ropePathUtf8)` / `Aagc_Destroy(handle)`|Verify exact rope hash, initialize and own one CPU; no process or sockets|
|`Aagc_ColdRestart(handle)`|Clear volatile CPU and adapter state and begin a new power epoch at octal 4000, retaining physical erasable and the exact loaded rope and parity|
|`Aagc_StepCycles(handle, uint64 cycles)`|Advance exactly that many physical machine cycles|
|`Aagc_StepNanoseconds(handle, uint64 ns)`|Add integer elapsed time and retain subcycle carry|
|`Aagc_StepSeconds(handle, double seconds)`|Convenience conversion rounded to nearest nanosecond; accepts 0–3600 seconds|
|`Aagc_SetInput(handle, channel, value, mask)`|Apply masked upstream input; DSKY and uplink channels trigger their actual interrupts|
|`Aagc_GetInput(handle, channel, out value)`|Read current upstream input without stepping|
|`Aagc_SetKey(handle, code, pressed)`|Code 0=active-low held PRO; normal DSKY codes generate one press interrupt; ordinary release sends no key|
|`Aagc_PollOutput(handle, out channel, out value)`|Return1 for an event,0 for empty, negative for error|
|`Aagc_PollOutputAt(..., out cycle)`|Same queue, with precise CPU cycle timestamp for verification|
|`Aagc_GetDsky(handle, rows16, out ch11, out ch13, out ch163, out cycles)`|Current relay rows and hardware status, independent of pending event queue|
|`Aagc_GetTiming(handle, out cycles, out quarterNsRemainder)`|Full authoritative clock position|
|`Aagc_IncrementCounter(handle, counter, type)`|Upstream unprogrammed increment interface for future peripheral models|
|`Aagc_CheckpointSize(handle)` / `Aagc_Save(handle, bytes, size)`|Query exact size, then save canonical bytes without draining output|
|`Aagc_ValidateCheckpoint(handle, bytes, size)` / `Aagc_Load(...)`|Stage and verify everything before any live CPU/global/queue/time mutation|
|`Aagc_GetCheckpointTiming(handle, bytes, size, out cycles, out quarterNsRemainder)`|Validate/stage the blob and return its authoritative payload clock without loading it|

Mutation calls return 0 on success and a negative value on error. `Aagc_Create` returns null on failure. `Aagc_LastError()` returns borrowed UTF8 error text. Row and channel numbers are decimal ABI integers; channel semantics and masks are described in [AGC-PROTOCOL.md](AGC-PROTOCOL.md).

One machine cycle is exactly 12/1024000 seconds, or 11718.75 nanoseconds. The adapter stores time as completed cycles plus a remainder in quarter nanoseconds: one cycle = 46875 quarter nanoseconds. Thus three calls of 250000000 nanoseconds produce exactly 64000 cycles and zero remainder. A one-nanosecond step then produces remainder 4 without inventing a CPU cycle. Save/restore includes this remainder. `StepCycles` advances whole cycles and preserves the fractional remainder. Integer nanoseconds are the authoritative integration API; repeated decimal `StepSeconds` calls have a documented nearest-nanosecond conversion.

## Electrical restart boundary

The restart uses the upstream initializer's volatile CPU and input defaults, clears queued outputs and peripheral state, and places Z at octal 4000. It preserves the physical magnetic-core words starting at octal 0010, including the interrupt storage words. Addresses 0000–0007 instead correspond to the central register region. This follows the memory map in MIT's [computer subsystem report R-700, Table 3-IV and §3.6](https://www.ibiblio.org/apollo/Documents/R-700.pdf) and the full power cycle retention test in [Digital Development Memo 382](https://www.ibiblio.org/apollo/Documents/dd_memo_382.pdf).

The unchanged rope starts at the [interrupt lead-in at 4000](https://www.ibiblio.org/apollo/listings/LM131R1/INTERRUPT_LEAD_INS.agc.html) and enters [GOPROG](https://www.ibiblio.org/apollo/listings/LM131R1/FRESH_START_AND_RESTART.agc.html), where the software increments `REDOCTR`. The cabin supplies the loss-of-power hold and nominal startup inhibit. The adapter uses deterministic latch and channel defaults. Individual hardware startup effects such as stray CDU counter pulses and potential RESTART lamp indication are outside these defaults. Software-controlled standby continues to use the upstream CPU's own logic.

## Complete checkpoint coverage

Upstream `MakeCoreDump` omits newer CPU state and peripheral globals, so this adapter does not use that format. It explicitly encodes each `agc_t` field, including registers, all erasable/fixed banks and parity words, channel inputs, channel7 superbank latch, relay rows, index, interrupts, all CPU bitflags, alarm/warning filters, pending instruction delays, downlink timing, scaler, standby and DSKY hardware/blink phase. The `agc_clientdata` pointer is omitted and rebound to the live context after a successful restore. Struct padding and compiler bitfield layout never enter the file.

The payload also encodes all live upstream peripheral statics: three CDU FIFOs and their pointers/counts/interval/next-update times, CDU checker, PIPA debug flag, gyro count/timer and prior channel14, IMU timing/channel state, all three function-local coarse CDU residual accumulators, and RHC inputs. It includes fractional time, adapter fault flag and the complete ordered pending output queue with cycle timestamps.

Debug execution, coverage logging, DEDA monitoring and network peripheral routines are fixed off in this adapter. Their unused diagnostic arrays/pointers are not checkpoint state. CPU branch/debug interrupt masks remain at their normal enabled defaults. Peripheral input requests and output callbacks are local; no wall clock, TCP handle or background thread participates in CPU advancement.

The binary format uses explicit little-endian fields. Its 152-byte header contains an 8-byte magic, 32-bit schema/ABI/payload-size/reserved words, and four 32-byte SHA256 values: exact rope, upstream source aggregate, adapter/build aggregate and payload digest. Loading rejects a different schema, ABI, rope, source or adapter build; truncated/corrupt payloads; changed fixed memory/parity; and invalid queue, flag, counter or remainder bounds. Validation allocates and checks a staging context. Failure leaves live CPU, shared statics, clock and queue unchanged. This behavior has explicit regression checks.

Native load preserves a held PRO exactly. A cabin save system may separately choose to release momentary controls on restore, but it must apply that policy after loading and label it in its own metadata. It should stage validation of both EPS and AGC before mutating either subsystem. Faulted adapter states can be saved for diagnostics but fail staged validation/loading; a usable load therefore cannot carry an output fault into the post-load PRO release. Save files from external real-time CLI mode are not interchangeable with this complete native format.

Shared-session validation must derive the saved AGC clock from `Aagc_GetCheckpointTiming`, then compare it against wrapper/session metadata. Agreement between two duplicated metadata fields is insufficient: both could disagree with an otherwise valid native payload. The timing query performs the same full staged validation as load, changes no live state, and leaves output parameters unchanged if validation fails.

## Reproducible build and proof

For a manual workspace build, run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/agc/build-stepped.ps1 -BuildRoot .cache/agc-power-cycle`, then run `tools/agc/test-stepped.py --build-root .cache/agc-power-cycle` with the bundled Python runtime. The workspace build and test write evidence under `.cache/agc-power-cycle/stepped/`. The recorded workspace run passes 65 checks in `reference/agc-stepped-test.json` and identifies the tested build in `reference/agc-stepped-build.json`. To update a writable `D:\apollo-ref\build\agc` installation instead, omit the build root options from both commands.

The pinned LLVM-MinGW compiler builds upstream C unchanged with `-O0 -fno-lto`. Its COFF `llvm-objcopy` cannot globalize local symbols, so the build appends only `.globl` linkage directives to the compiler-emitted assembly. The original assembly is retained. The build requires the exact set and sizes of 13 local-data symbols, exposes the 11 live CPU statics, then independently extracts and hashes both object `.text` sections. The instruction bytes must match exactly or the build fails. No instruction/source/rope modifications are accepted.

The build rejects changed upstream CPU, header and initializer hashes. Checkpoint compatibility also binds the adapter C and header, build script and pinned compiler version. Changing adapter code requires a new build and invalidates older checkpoint fingerprints by design. The linker omits timestamps so rebuilding the same inputs reproduces the DLL fingerprint. `reference/agc-stepped-build.json` records source/build/DLL hashes, compiler flags and the complete static symbol audit.

Full-state replay includes pending outputs, fractional time, nonempty CDU FIFOs and synthetic nonzero coarse XYZ/gyro accumulators. Every one of the first 4096 native machine-cycle boundaries saves, validates, restores and reserializes canonically. This includes pending-instruction phases where the upstream scaler has legitimately crossed 80 before its next service, and validation accepts those states. A restored 196609-event queue grows to the declared 262144-event limit and faults explicitly when it passes the limit. Faulted and incompatible or corrupt checkpoints fail before commit.

Callers should drain the bounded output queue each shared simulation tick. An allocation or full-queue error stops advancement and reports the fault. Sensor coupling, engine and IMU physics, mass state and flown erasable initialization remain outside the adapter.

