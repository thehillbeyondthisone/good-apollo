# Electrical checkout

The cabin supports two deliberately separate electrical load modes. Aggregate presets reproduce the selected bus-current calibration. **F11** selects `sourced_equipment_checkout`, where 20 source-valued equipment entries replace that aggregate. The HUD then reads **KNOWN EQUIPMENT / PARTIAL LOAD COVERAGE**. This is a partial equipment checkout, not a reconstructed flown configuration or a complete spacecraft power budget.

The catalog covers selected communications equipment and operating states, two ORDEAL supply loads, and the EPS displays. Switch positions and breaker continuity select the identified loads. Reported watts become current at the solved bus voltage; identified AC real power reaches the inverter's DC source once. Inverter losses, power factor, unknown loads, battery chemistry, and thermal breaker curves remain outside this model. Breaker ratings are protective limits, not assumed operating consumption. See [electrical.json](../reference/electrical.json) and [electrical-provenance.json](../reference/electrical-provenance.json) for values and qualifications.

Launch the desktop cabin normally and press F11, or use:

```powershell
./tools/run-cabin.ps1 -Preset sourced_equipment_checkout
```

F2 restores the aggregate electrical checkout, F3 selects the minimum-load aggregate calibration, and F4 disconnects the battery sources. The current readout follows the selected `POWER/TEMP MON` battery; bus-selector positions do not invent an undefined AMPS measurement. F5/F9 saves and restores the complete controls/EPS/native-computer session when the shared CPU backend is active. Reference fingerprints reject incompatible checkpoints. The independent external-computer fallback cannot save its CPU memory.

**F12** starts/advances the [source-qualified power-down guide](ELECTRICAL-POWERDOWN.md);
**Shift+F12** restarts. It applies 13 events/93 commands from the partial equipment
checkout. Historical timestamps do not advance the shared clock. The source
ledger now separates known equipment, CM-export input and synthetic faults;
aggregate calibration stays unclassified. EPS save schema2 requires these
ledgers and rejects older saves atomically. Fresh checkout plus F5 creates a
compatible complete session.

For an explicit synthetic export-input accounting example, run:

```powershell
& D:/apollo-ref/tools/dotnet-10/dotnet.exe run --project src/Aquarius.Sim.Cli -- cm-export-checkout 3600 7 LMP_DC
& D:/apollo-ref/tools/dotnet-10/dotnet.exe run --project src/Aquarius.Sim.Cli -- powerdown
./tools/run-cabin.ps1 -PowerDownTest
```

The first command debits 7 source Ah for one hour's 7 A input, separately from
known equipment. It does not model the physical charger circuit, charger
losses, restored CM battery charge or a historical transfer schedule. Export
cannot be appended to an aggregate that may already contain it.

# Lamp and tone test

Operate `LAMP/TONE TEST` on panel3 with click/trigger to advance and Shift-click or grip+trigger to reverse. Its eight physical detents include an OFF at each end, and travel stops at the endpoints. Both OFF positions disable testing. The electrical model stores the common OFF label; the physical control state preserves which endpoint the handle occupies.

| Test detent | Powered lamp outputs |
| --- | --- |
| ALARM/TONE | Both MASTER ALARM lamps and warning tone |
| C/W1 | ASC PRESS, DES REG, DES QTY, CES AC, CES DC, AGS, LGC, ISS |
| ENG PB-C/W2 | RCS TCA, RCS A REG, RCS B REG, DC BUS, CABIN, SUIT/FAN; START and both STOP lamps |
| C/W3 | ASC HI REG, ASC QTY, ENG GMBL, INVERTER, BATTERY, RNDZ RDR, PRE AMPS |
| C/W4 | ED RELAYS, RCS, HEATER, ECS, O2 QTY, GLYCOL, WATER QTY, S-BD RCVR, C/W PWR |
| COMPN T | Both lunar-contact lamps, both stage-sequence relay lamps, BAT FAULT, DC FEEDER FAULT, SUIT FAN, GLYCOL, CO2, H2O SEP component lamps, RR NO TRACK |

These memberships come from the visually checked **LM-7 AOH Vol.I Fig.2.10-5, PDF634**, cross-checked against the selector description on PDF741/742. The selector completes a common return. Bank-test illumination uses the annunciator-lighting supply independently of the CWEA instrumentation breaker. ALARM/TONE requires the LMP `LTG MASTER ALARM` branch (`p16_cb_r02_c04`). General annunciator test supplies are `p11_cb_r03_c19` or `p16_cb_r02_c03`; the local BAT FAULT lamp requires the LMP lighting branch. DC FEEDER FAULT has its separately documented direct DC supply (PDF789). Lamp-test power is a logical continuity model; dimmer voltages and lamp consumption are not solved.

Testing illuminates lamps without pressing engine buttons, creating sensor failures, or altering actual-warning acknowledgements. An existing modeled fault can remain illuminated while another bank is tested. Pressing a MASTER ALARM button acknowledges an actual warning and silences its tone while leaving the caution lit. It does not defeat a selected ALARM/TONE test.

**M** enables or mutes procedural audio; startup remains muted. The warning signal follows both actual unacknowledged modeled alarms and the powered tone-test detent. The generated waveform is **3kHz**, as specified on AOH PDF624. Reproduced gain and spatial acoustics are illustrative. Table2.10-2, PDF630 supplies the rendered colors: red warning/master-alarm lamps, yellow caution/component lamps, and blue lunar-contact lamps. Other subsystem sensor faults, complete master-alarm flash timing, and exact LGC supply transient behavior remain open. [LGC power](LGC-POWER.md)

# Verification

The dedicated pure-core suite checks all source banks, independent feeds, normal-warning preservation, acknowledgement, recurrence, atomic save rejection, and deterministic restore. [caution-warning-tests.json](../reference/caution-warning-tests.json) records **346 passing checks** with inventory and electrical-definition fingerprints.

The actual imported cabin fixture checks the physical selector, duplicate OFF endpoints, rendered lamp materials and sourced colors, generated-waveform frequency, tone mute/start/stop, bridge restore, and load-mode HUD. [caution-warning-integration.json](../reference/caution-warning-integration.json) records its current result. [audio-lifecycle.json](../reference/audio-lifecycle.json) separately covers muted startup and teardown. These are offline checks; headset testing remains deferred and acoustic reproduction has not been validated in hardware.

```powershell
& D:/apollo-ref/tools/dotnet-10/dotnet.exe run --project tests/Aquarius.CautionWarning.Verify -- .
# After tools/build-godot.ps1, using the portable Godot console executable:
godot --headless --path godot --script res://tests/test_caution_warning.gd -- --self-test --systems-test --manual-clock --no-agc
```

The lighting color basis is Table2.10-2 (PDF630, revised1February1970).
It gives blue lunar-contact lamps; an older control-table row on PDF742 says
red. This implementation follows the revised lighting table and preserves that
source distinction. Color rendering and brightness are presentation values.

The equipment runner passes124 checks and the actual desktop/native-session
fixture passes44. Run `tests/Aquarius.Equipment.Verify`, then
`godot/tests/test_equipment_loads.gd` with `--self-test --systems-test
--manual-clock` for the corresponding two layers. Updated desktop views are
`output/aquarius-electrical-checkout.png`, `aquarius-caution-lamp-test.png`
and `aquarius-component-lamp-test.png`.
