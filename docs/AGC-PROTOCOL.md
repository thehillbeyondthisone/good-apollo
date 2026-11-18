# Live LM131R1 DSKY connection

The external fallback uses the complete upstream yaAGC executable, the verified LM131R1 rope, and the upstream SocketAPI protocol. The normal shared-clock backend is documented in AGC-STEPPED.md. It does not use `--debug-dsky`, scripted display replies or replacement arithmetic logic.

## Launch and ownership

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\agc\start-agc.ps1
```

The helper starts a hidden process, verifies the pinned rope SHA-256, isolates runtime files in a unique directory, and prints a JSON session receipt containing PID, start time, executable path, port and session path. It refuses an occupied port range rather than stopping an unrelated process. Stop only its owned process with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\agc\stop-agc.ps1 -SessionPath <receipt-path>
```

For direct game supervision, use the following executable and argument vector, retain only the PID returned by creating that process, and stop that PID when the game/session powers it off. Provide a writable isolated runtime directory with `--cd` when launching without a working-directory option.

```text
D:/apollo-ref/build/agc/yaAGC.exe
--exec=D:/apollo-ref/build/agc/LM131R1/MAIN.agc.bin
--port=19697
--nodebug
--no-resume
--quiet
--dump-time=86400
--cd=<isolated-writable-runtime-directory>
```

Client endpoint: `127.0.0.1:19697`. The stock upstream server reserves ten consecutive ports; the first is sufficient for the DSKY client. Reconnect the client without restarting the CPU when its TCP connection is lost. A newly connected client receives the current output latch/status snapshot. There is no handshake or required application ping. Do not replay old button presses after reconnecting.

Rope SHA-256: `ae4f9e51ac9491c3da6462233936daeffc16277cd302c43a70b8459ebcd6cca5`. The full CLI and deterministic embedded-core fixture both pass the real V35 lamp sequence. This is test initialization: **the Apollo 13 flight erasable padload is not applied**. Present that distinction in the simulator status.

## Four-byte stream packets

TCP read boundaries are arbitrary; buffer incoming bytes. Valid packet byte prefixes are `00`, `01`, `10`, `11` respectively. If a prefix is invalid, discard one byte and resynchronize. Values are fifteen bits. Channel numbers below are explicitly identified as octal or decimal.

```text
encode(channel,value):
  b0 = channel >> 3
  b1 = 0x40 | ((channel << 3) & 0x38) | ((value >> 12) & 7)
  b2 = 0x80 | ((value >> 6) & 63)
  b3 = 0xc0 | (value & 63)

decode:
  channel = ((b0 & 31) << 3) | ((b1 >> 3) & 7)
  value   = ((b1 & 7) << 12) | ((b2 & 63) << 6) | (b3 & 63)
```

The encoded channel's `0x100` bit marks an input mask packet. It changes that client's mask for the lower eight-bit channel, rather than writing data.

## Keys

Send ordinary key presses once on channel **015 octal / 13 decimal**. Do not send ordinary releases or automatic repeats; their releases only animate the physical cap. The client test spaces presses by 250 ms.

| Key | Decimal code |
|---|---:|
| 0 | 16 |
| 1 through 9 | 1 through 9 |
| VERB | 17 |
| RSET | 18 |
| KEY REL | 25 |
| + | 26 |
| - | 27 |
| ENTR | 28 |
| CLR | 30 |
| NOUN | 31 |

PRO is a separate active-low discrete. Send the mask `(channel=0432 octal / 282 decimal, value=020000 octal / 8192 decimal)` first. Send channel `032 octal / 26 decimal` with value `0` on PRO press and `8192` on release. Restore/reapply the mask on every connection. This preserves the other channel 032 thruster-disable bits.

## Digits and signs

Channel **010 octal / 8 decimal** contains relay row `r=(value>>11)&15`, left digit code `(value>>5)&31`, right digit code `value&31`, and sign bit `value&0x400`. Retain sixteen row latches; a packet updates only one row.

Digit codes, decimal: `0=blank`, `21=0`, `3=1`, `25=2`, `27=3`, `15=4`, `30=5`, `28=6`, `19=7`, `29=8`, `31=9`. Treat other codes as invalid/unavailable rather than inventing digits.

| Row, decimal | Left | Right | Sign bit |
|---:|---|---|---|
| 11 | PROG 1 | PROG 2 | — |
| 10 | VERB 1 | VERB 2 | — |
| 9 | NOUN 1 | NOUN 2 | — |
| 8 | unused | R1 digit 1 | — |
| 7 | R1 digit 2 | R1 digit 3 | R1 plus |
| 6 | R1 digit 4 | R1 digit 5 | R1 minus |
| 5 | R2 digit 1 | R2 digit 2 | R2 plus |
| 4 | R2 digit 3 | R2 digit 4 | R2 minus |
| 3 | R2 digit 5 | R3 digit 1 | — |
| 2 | R3 digit 2 | R3 digit 3 | R3 plus |
| 1 | R3 digit 4 | R3 digit 5 | R3 minus |

Sign latches are independent; plus has display priority if both are set. Row 12 is a status-lamp row, not numeric data.

## Lamps and blanking

All masks below are hexadecimal, not ordinal bit numbers. Channel **011 octal / 9 decimal**: COMP ACTY `0x2`, UPLINK ACTY `0x4`.

Channel **0163 octal / 115 decimal** is the emulator's DSKY hardware status output, including the actual blink phase:

| Output | Mask |
|---|---:|
| TEMP | 0x8 |
| KEY REL | 0x10 |
| Blank VERB/NOUN at this instant | 0x20 |
| OPR ERR | 0x40 |
| RESTART | 0x80 |
| STBY | 0x100 |
| EL display off; blank numeric display | 0x200 |

Use the supplied blink phase; do not start a separate simulated flashing clock. Retain the underlying digit latches while blanked.

For channel 010 row 12 (`value & 0x7800 == 0x6000`), latch NO ATT `0x8`, GIMBAL LOCK `0x20`, PROG `0x100`, TRACKER `0x80`, ALT `0x10`, VEL `0x4`. The remaining two physical annunciator positions are blank on this software revision.

The upstream server reserves ten ports, `base` through `base+9`, with one connected peripheral per port. Additional observers must connect to a different reserved port. A second TCP handshake to an occupied port may enter the OS backlog without receiving a peripheral snapshot. Fresh observer snapshots include nonzero current input channels; zero values are omitted.

## Validation and source anchors

Run `node tools/agc/test-cli.cjs D:/apollo-ref/build/agc` to launch the genuine CLI, enter `V37 ENTR 00 ENTR` then `V35 ENTR`, and verify an all-eight frame plus timed lamp clear. The test owns and terminates only its child process and saves actual channel traces under the build directory.

The packet encoder/decoder is in upstream `yaAGC/agc_utilities.c`; keyboard input and snapshots in `yaAGC/SocketAPI.c`; display mapping, normal key release behavior and PRO mask in `yaDSKY/src/callbacks.c`; lamp mappings in `yaDSKY2/LM.ini`; hardware status masks in `yaAGC/agc_engine.h`. These are checked at commit `938e88d11caea1d72af72e53e6005282023f94c2` of [Virtual AGC](https://github.com/virtualagc/virtualagc/tree/938e88d11caea1d72af72e53e6005282023f94c2).

Embedded-core adapters must preserve the external channel-7 superbank latch exactly as SocketAPI does: `state->InputChannel[7] = state->OutputChannel7 = value & 0160`. Omitting that peripheral latch causes invalid fixed-bank selection and a reset loop even though the CPU core and rope are correct. Our deterministic fixture includes it.

