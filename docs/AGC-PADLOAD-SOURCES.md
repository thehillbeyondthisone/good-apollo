# LM131R1 erasable parameter sources

The exact fixed-memory rope runs and passes the real V35 lamp test. Its present runtime uses upstream zero-erasable test initialization. **No mission padload is applied.**

The source candidate dataset in `reference/lm131r1-prelaunch.json` remains `approvedForLoading=false`. A source comparison is useful research; it does not establish the flown activation checkpoint. The parameter list is sparse, the last memo page names subsequent changes without all final words, and the scans contain unresolved numeric readings.

Three transcriptions are preserved separately:

| Source | Date and identity | Pages | Data |
|---|---|---|---|
| Final prelaunch memo | 26 March 1970, 70-FS5-78, LM131 Rev 1 | PDF 2–22, printed 1–21 | 174 symbol groups, 272 words |
| RTCC FMU V71 table, enclosure 2 of that memo | 26 March 1970 memo | PDF 23, columns A–L | 12 blocks, 182 data words |
| Handbook copy | 30 March 1970, SNA-8-D-027(II), Rev 2 Amendment 61, Table LM7/4.5.1-1 | PDF 1–21 | 272 words |

The original PDFs and their hashes are recorded in the generated JSON. Scans are from [Virtual AGC's memo](https://www.ibiblio.org/apollo/Documents/padload_13_lm.pdf) and [handbook copy](https://www.ibiblio.org/apollo/Documents/LM7_Pad_loads.pdf). Dates identify the documents; a later date alone does not decide a disputed value.

The following are **unresolved scan readings**, not a claim that eleven intentional mission revisions occurred. Scan damage or printing may account for some differences. Neither variant is selected for loading.

| Octal address | Symbol | Memo reading (PDF page) | Handbook reading (PDF page) | V71 reading |
|---|---|---|---|---|
|1327|CSMMASS|10245 (2)|10246 (1)|not listed|
|1350|E32C31RM|03363 (2)|03367 (1)|not listed|
|1746|REFSMMAT+11|31571 (6)|31671 (5)|not listed|
|2462|AAPFG*|77754 (12)|77764 (11)|77754, H21|
|2463|AAPFG*+1|67646 (12)|67645 (11)|67646, H22|
|2467|GAINAPPR+1|00000 (13)|00010 (12)|00000, I04|
|2527|LRVF|00116 (15)|00115 (14)|00116, K04|
|2536|LRWVFF|03145 (16)|03146 (15)|03146, K13|
|2540|TAUROD|11300 (16)|14300 (15)|14300, K15|
|2546|MAXFORCE|00013 (16)|00017 (15)|00013, K23|
|3372|VELBIAS+1|36331 (20)|35331 (19)|not listed|

V71 row numbers above are octal, as printed. The memo and V71 agree on 180 of 182 overlapping words. The two complete table transcriptions have 261 matching words and 11 unresolved readings. This comparison does not independently certify every digit.

The wider source-page review corrected initial transcription mistakes: SKALSKAL 1353 is 00000; ELBIAS 1356=00044 was omitted; PIPASCFX 1453 is 64417; SHAFTVAR 2010 and TRUNVAR 2011 are 00103. The omitted ELBIAS row changes the earlier provisional count from 173 groups/271 words to 174 groups/272 words. The LRWVFF discrepancy remains unresolved; an earlier intermediate statement calling it a resolved transcription mistake was incorrect.

`tools/agc/validate-padload.py` verifies all 174 assembled symbol/offset addresses, 272 unique erasable addresses, 15-bit octal ranges, 12 V71 block counts, 182 V71 addresses, and 272 computed odd-parity encodings. Source tables contain data words without parity; a computed parity self-check cannot verify an original parity bit. Structural validation errors are empty. Source disagreements are retained in the output and loading approval stays false.

`tools/agc/render-padload-evidence.py` produces full source-page frames and unfiltered numeric-column crops in `reference/extracts/agc-padload/`, with PDF page, render scale, crop bounds and SHA256 metadata. Full frames include the document context and handbook revision/date footer. No source PDFs are modified.

The memo's final page separately lists planned changes to R03 masses, TEPHEM, rendezvous weights and RLS. These are recorded as research notes, never merged into a fabricated activation load. A future load requires source adjudication and a documented initialization epoch/load mechanism before its own exact address/value and V35 regression checks.
