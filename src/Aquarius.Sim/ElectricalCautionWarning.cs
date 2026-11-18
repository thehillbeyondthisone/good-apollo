namespace Aquarius.Sim;

/// <summary>Logical lamp-test outputs, not injected subsystem failures or a photometric model.</summary>
public sealed record CautionWarningSnapshot(string SelectorPosition, bool TestPowerAvailable,
    bool TestActive, bool WarningTone, string[] TestedIndicatorIds, string Basis, string[] Limitations);

public sealed partial class ElectricalSimulation
{
    private const string LampTestSelector = "p3_lamp_tone_test";
    // AOH LM-7 Vol.I Fig.2.10-5 (PDF634), checked against the actual drawing.
    private static readonly Dictionary<string, string[]> CautionWarningTestBanks = new(StringComparer.Ordinal)
    {
        ["ALARM/TONE"] = ["p1_master_alarm", "p2_master_alarm"],
        ["C/W 1"] = ["p1_asc_press_warning", "p1_des_reg_warning", "p1_des_qty_warning",
            "p1_ces_ac_warning", "p1_ces_dc_warning", "p1_ags_warning", "p1_lgc_warning", "p1_iss_warning"],
        ["ENG PB-C/W 2"] = ["p1_rcs_tca_warning", "p1_rcs_a_reg_warning", "p1_rcs_b_reg_warning",
            "p1_dc_bus_warning", "p1_cabin_warning", "p1_suit_fan_warning", "p5_start", "p5_stop", "p6_stop"],
        ["C/W 3"] = ["p2_asc_hi_reg_caution", "p2_asc_qty_caution", "p2_eng_gmbl_caution",
            "p2_inverter_caution", "p2_battery_caution", "p2_rndz_rdr_caution", "p2_pre_amps_caution"],
        ["C/W 4"] = ["p2_ed_relays_caution", "p2_rcs_caution", "p2_heater_caution", "p2_ecs_caution",
            "p2_o2_qty_caution", "p2_glycol_caution", "p2_water_qty_caution", "p2_s_bd_rcvr_caution", "p2_c_w_pwr_caution"],
        ["COMPN T"] = ["p1_lunar_contact", "p3_lunar_contact", "p8_stage_seq_relays_sys_a",
            "p8_stage_seq_relays_sys_b", "p14_bat_fault", "p14_dc_bus_fault", "p2_suit_fan_component_caution",
            "p2_glycol_component_caution", "p2_co2_component_caution", "p2_h2o_sep_component_caution",
            "p3_rendezvous_radar_no_track"]
    };

    private void ConfigureCautionWarning()
    {
        RequireControl(LampTestSelector);
        string[] expected = ["OFF", "ALARM/TONE", "C/W 1", "ENG PB-C/W 2", "C/W 3", "C/W 4", "COMPN T", "OFF"];
        if (!allowed[LampTestSelector].SequenceEqual(expected))
            throw new ArgumentException("The sourced lamp-test selector must retain eight physical detents, including both OFF ends.");
        foreach (var id in CautionWarningTestBanks.Values.SelectMany(ids => ids))
            if (!allowed.ContainsKey(id)) throw new ArgumentException($"Unknown lamp-test output: {id}");
    }

    private CautionWarningSnapshot ApplyCautionWarningTest(Network n,
        Dictionary<string, bool> indicators, Dictionary<string, bool> powered)
    {
        bool Branch(string id) => Closed(id) && n.Voltage[definition.Breakers.Single(b => b.ControlId == id).BusId] > 0;
        var annunciatorPower = Branch("p11_cb_r03_c19") || Branch("p16_cb_r02_c03");
        var masterPower = Branch("p16_cb_r02_c04");
        var directDcPower = n.Voltage["CDR_DC"] > 0 || n.Voltage["LMP_DC"] > 0;
        bool LampPower(string id) => id switch
        {
            "p1_master_alarm" or "p2_master_alarm" => masterPower,
            // AOH3-119 (PDF789): local BAT FAULT is supplied by the LMP lighting branch;
            // DC FEEDER FAULT is directly supplied from either DC bus, with no listed CB.
            "p14_bat_fault" => Branch("p16_cb_r02_c03"),
            "p14_dc_bus_fault" => directDcPower,
            _ => annunciatorPower
        };
        // Populate all lamps even with the selector OFF, so the presenter can create
        // their outputs at startup. No new unmodelled subsystem faults are asserted.
        foreach (var id in CautionWarningTestBanks.Values.SelectMany(ids => ids).Distinct(StringComparer.Ordinal))
        {
            indicators.TryAdd(id, false);
            powered.TryAdd(id, LampPower(id));
        }
        var position = controls[LampTestSelector];
        var tested = new List<string>();
        var selectedBank = CautionWarningTestBanks.TryGetValue(position, out var selected);
        var powerAvailable = selectedBank ? selected!.Any(LampPower) : masterPower || annunciatorPower || directDcPower;
        if (selectedBank)
            foreach (var id in selected!)
                if (LampPower(id))
                {
                    indicators[id] = true;
                    tested.Add(id);
                }
        var testActive = tested.Count > 0;
        // Actual master-alarm acknowledgement remains in the normal alarm model.
        // Testing lamps never adds a fault or acknowledges an existing condition.
        var warningTone = (masterPower && CurrentAlarms(n).Any(flag => !acknowledgedAlarms.Contains(flag))) ||
                          (position == "ALARM/TONE" && masterPower);
        return new(position, powerAvailable, testActive, warningTone, tested.ToArray(),
            "LM-7 AOH Vol.I Fig.2.10-5 (PDF634), 2.10-2 (PDF624), 3-71/72 (PDF741/742), 3-119 (PDF789).",
            ["Lamp power is logical continuity; dimmer voltage and lamp current are not solved.",
             "Unmodelled warning sensors remain inactive outside the lamp test.",
             "Tone frequency is sourced at 3 kHz; reproduced amplitude and spatial acoustics are illustrative."]);
    }
}
