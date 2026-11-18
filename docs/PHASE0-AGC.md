# Native guidance-computer build — 2026-11-17

The exact LM131R1 rope is rebuilt and running. Both the deterministic embedded-core fixture and the complete upstream yaAGC CLI pass a real Verb 35 DSKY lamp test. The Apollo 13 flight erasable padload remains pending.

## Source snapshots

| Repository | Branch | Commit | Location |
|---|---|---|---|
| [Virtual AGC](https://github.com/virtualagc/virtualagc) | master | 938e88d11caea1d72af72e53e6005282023f94c2 | D:\apollo-ref\source\virtualagc |
| [NASSP](https://github.com/orbiternassp/NASSP) | Orbiter2016 | a4ed25511e626823f9c83b457cf9371375b82094 | D:\apollo-ref\source\NASSP |

Both are shallow clones with clean working trees. Commit IDs identify this build independently of moving branch names. NASSP was downloaded for reference; it was not built, and its models/assets have not been copied into the game.

## Complete upstream build

Portable LLVM-MinGW 20261104 (Clang 23.1.5, x64 Windows GNU/POSIX-thread target) is installed under D:\apollo-ref\toolchain. Its ZIP was checked against the official GitHub release SHA-256 digest before extraction. No global PATH or system installation was changed. See reference/agc-toolchain.json for its pinned source and hash.

The primary reproducible build compiles the complete upstream yaYUL assembler, complete upstream yaAGC CLI/debugger/socket interface, and our test fixture with the upstream CPU core. All upstream source files, including flight program, assembler and CPU, are unchanged. Outputs live outside OneDrive under D:\apollo-ref\build\agc.

The rebuilt 73,728-byte LM131R1\MAIN.agc.bin matches the repository's independently reconstructed Luminary131PlusLM131R1ModuleDump.bin byte for byte:

```text
SHA-256 ae4f9e51ac9491c3da6462233936daeffc16277cd302c43a70b8459ebcd6cca5
```

Reproduce:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\agc\setup-toolchain.ps1 -DataRoot D:\apollo-ref
powershell -NoProfile -ExecutionPolicy Bypass -File tools\agc\build-cli.ps1 -DataRoot D:\apollo-ref
node tools/agc/test-cli.cjs D:/apollo-ref/build/agc
```

The first command reuses a valid cached compiler archive. The build command assembles and hash-compares the rope, builds the full CLI, and runs the deterministic fixture. The Node command separately boots the genuine upstream CLI and communicates over its actual socket protocol.

An alternate tools/agc/build-agc.ps1 build uses the existing VS2019 compiler. Four yaYUL macros and six static initializers need syntax-only corrections in disposable build copies for that compiler; the source checkout remains unchanged. This alternate build also produces the exact rope and passes the same fixture. The external fallback uses the complete LLVM-MinGW CLI. Normal launch now uses the deterministic native adapter to the same unchanged CPU; see AGC-STEPPED.md.

## V35 evidence

Both tests use the emulator's default input channels and zero-filled erasable RAM, enter V37 ENTR 00 ENTR, then V35 ENTR through the actual keyboard interrupt/input channel. Neither uses --debug-dsky or predefined test display replies.

The deterministic fixture records actual channels 010, 011, 013, 0163 and hardware alarm channel 077. It observed all 21 numeric positions showing eight with lamp status bits set at machine cycle 602748, followed by the timed lamp-test output clearing. The full 1,173,326-cycle test completed with zero hardware alarms and no parity failure. This passes under both MSVC and Clang.

The independent CLI/TCP test also observed the all-eight frame and timed clear. Its process is supervised and terminated by the test itself. This demonstrates the actual source-built CLI, fixed rope, socket protocol, input handling and display output work together.

An earlier fixture failed because it omitted channel 7's peripheral superbank latch. The CPU deliberately delegates this latch to the I/O adapter; upstream SocketAPI.c preserves it. Adding the same behavior to our adapter fixed the reset loop without modifying the CPU or rope. The cause was the fixture's peripheral emulation, not an MSVC incompatibility or a flight-software defect.

## Integration and limitations

Launch/supervise the real CLI with tools/agc/start-agc.ps1 and stop-agc.ps1, or use the exact process argument vector and protocol in docs/AGC-PROTOCOL.md. The launcher verifies the pinned rope hash, isolates runtime files, starts a hidden process, and stops only the PID whose executable/start time matches its receipt. Launch/stop/idempotent-stop behavior passed a separate smoke test.

A separate [deterministic stepped adapter](AGC-STEPPED.md) now supplies an ABI1 native DLL with exact physical-cycle time carry and complete versioned CPU/peripheral checkpoints. Its 54-check native suite passes, including every startup boundary across 4096 cycles, unchanged-core trace/CLI lamp-frame equivalence, nonzero hidden-state replay and atomic rejection. Godot integration is tracked separately; the external CLI remains a reference/fallback. `reference/agc-stepped-build.json` and `reference/agc-stepped-test.json` record the exact evidence.

No Apollo 13 erasable padload is applied yet. Existing documents' legacy OCR is inadequate for blindly loading octal words. The current result validates exact fixed-memory software and the live DSKY interface, not complete mission-state fidelity or spacecraft sensor/engine coupling. The combined native executable uses GPL code; our fixture is marked GPL-2.0-or-later.

The separate [padload source findings](AGC-PADLOAD-SOURCES.md) preserve 174 symbol groups / 272 candidate words, a second complete handbook transcription, and the 182-word V71 table. All symbol/address/range and computed odd-parity checks pass, but eleven scan readings remain unresolved between complete tables and two memo/V71 readings differ. The dataset explicitly remains `approvedForLoading=false`; neither source date nor a successful structural validator selects a flown value.

Evidence files:

- reference/source-provenance.json: exact source revisions, rope hash, build and test results.
- reference/agc-toolchain.json: official portable compiler provenance and archive digest.
- D:\apollo-ref\build\agc\LM131R1\assembly.log: assembler listing.
- D:\apollo-ref\build\agc\lamp-result.json and lamp-test.csv: deterministic assertions and real CPU output.
- D:\apollo-ref\build\agc\cli-lamp-result.json and cli-channel-trace.json: independently observed live TCP output.
- D:\apollo-ref\build\agc\cli-lamp.log: native CLI output.

