# Phase 0 status — 2026-11-16

The foundations gate passed on 2026-11-17: references are downloaded, both source repositories are pinned, portable Godot .NET and a C toolchain are ready, and the exact LM131R1 software passes the Verb35 lamp test through both the CPU fixture and the real upstream yaAGC TCP interface. See [native build evidence](PHASE0-AGC.md).

## Downloaded library

Location: `D:\apollo-ref`, outside OneDrive. All 25 priority-0 direct files in `reference/manifest.json` are present: 24 PDFs and the DE440 SPK kernel. Total: **1,567,201,385 bytes (1.46 GiB)**.

| Category | Files | MiB |
|---|---:|---:|
| LM systems handbooks and mass properties | 5 | 880.0 |
| Apollo 13 procedures and Flight Director logs | 8 | 98.5 |
| Voice transcripts | 2 | 239.9 |
| Mission reports, trajectory notes and crew debriefing | 6 | 139.9 |
| Guidance computer padload documents | 3 | 22.0 |
| DE440 planetary ephemeris | 1 | 114.2 |

The initial files-only run did not clone repositories or mirror web pages. Subsequent setup cloned both repositories and provisioned portable tools on D:; the project remains in its existing folder.

## Verification

- All 25 URLs passed live HEAD checks before transfer.
- Downloads used `.part` files, HTTP failure detection, retries and range resume.
- Completed files matched server-reported byte counts and PDF/SPK signatures. PDFs also passed a final EOF marker check.
- `D:\apollo-ref\download-receipt.json` records each source URL, resolved URL, destination, size, SHA-256 hash and verification time. These are local integrity hashes, not publisher-provided checksums.
- A second run under Windows PowerShell verified all 25 files against their recorded hashes and current server sizes: **0 downloads, 25 verified, 0 failures**. No `.part` files remain.
- Eight local HTTP regression checks passed: successful download/receipt, skipping a complete file, rejecting HTML and HTTP 404, resuming seeded and interrupted transfers, handling servers that ignore Range, and rejecting a changed file. Run with `node tools/test-fetch-reference.cjs` (requires permission for localhost networking in a sandbox).

To recheck completed files or resume an interrupted files-only run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\fetch-reference.ps1 -DataRoot D:\apollo-ref -MaxPriority 0 -FilesOnly
```

To check source URLs without downloading:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\fetch-reference.ps1 -MaxPriority 0 -FilesOnly -DryRun
```

## Foundation exit evidence

- Virtual AGC and NASSP are shallow-cloned under `D:\apollo-ref\source`, with exact commits recorded in `reference/source-provenance.json`.
- Godot .NET4.7.2 and .NET SDK10.0.404 are portable under `D:\apollo-ref\tools`. The LLVM-MinGW C toolchain is under `D:\apollo-ref\toolchain`; published archive checksums were verified.
- yaYUL assembles the LM131R1 rope byte-for-byte identically to its independently reconstructed reference image. The source-built upstream yaAGC boots that image and passes the real Verb35 all-eights/lamp-clear test without debug-DSKY mode.
- Mission anchor times were visually verified against Mission Report Table3-I, except the approximate LM activation window. See `reference/mission-events.json`.

The source-verified flight erasable padload, spacecraft I/O coupling and synchronized accelerated AGC save states are later guidance work. The current boot uses explicitly labeled test initialization; the foundations exit does not imply full flown-state fidelity.
