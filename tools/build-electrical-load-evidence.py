"""Build a reviewed, partial LM-7 equipment-input-power evidence ledger.

This does not change the EPS definition or assign the unknown remainder of a
flight current budget. Source page numbers are one-based PDF page numbers.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ID = 'lm7-aoh-v1'
SOURCE_PATH = 'D:/apollo-ref/lm-systems/a13-lm-aoh-v1-lm7-subs-300ppi.pdf'
SOURCE_SHA = '1623f208023279cbe7de6aea14e95bd95fbc8c4e9d51791ff55e68ee04d338f2'


def build(inventory_path, electrical_path):
    inventory = json.loads(inventory_path.read_text(encoding='utf-8'))
    electrical = json.loads(electrical_path.read_text(encoding='utf-8'))
    controls = {c['id']: c for c in inventory['controls']}
    breakers = {b['controlId']: b for b in electrical['breakers']}
    evidence = []

    def ev(ident, page, printed, locator, finding, **metadata):
        evidence.append(dict(id=ident, sourceId=SOURCE_ID, pdfPage=page,
                             printedPage=printed, locator=locator,
                             review='visual_complete_page', finding=finding,
                             **metadata))

    comm = 'Table 2.7-5, Communications Subsystem - Performance and Design Data'
    ev('comms_input_power', 509, '2.7-45', comm,
       'The columns explicitly distinguish D-C input watts and A-C input watts. Equipment-level requirements are not protective breaker ratings or RF output power.',
       classification='equipment_input_power', rows=[
           dict(equipment='S-band transmitter-receiver', mode='primary or secondary', dcW=36.0, acW=0),
           dict(equipment='S-band power amplifier and diplexer', mode='primary or secondary', dcW=72.0, acW=0),
           dict(equipment='S-band steerable antenna electronics', mode='slew', dcW=7.6, acW=27.9),
           dict(equipment='S-band steerable antenna electronics', mode='auto', dcW=0.7, acW=4.0),
           dict(equipment='S-band steerable antenna heaters', mode='on', dcW=51.7, acW=0),
           dict(equipment='VHF A transmitter', mode='voice transmitting', dcW=30.0, acW=0),
           dict(equipment='VHF A transmitter', mode='not transmitting', dcW=3.5, acW=0),
           dict(equipment='VHF A receiver', mode='on', dcW=1.2, acW=0),
           dict(equipment='VHF B transmitter', mode='voice transmitting', dcW=28.9, acW=0),
           dict(equipment='VHF B transmitter', mode='data', dcW=31.7, acW=0),
           dict(equipment='VHF B transmitter', mode='not transmitting', dcW=3.5, acW=0),
           dict(equipment='VHF B receiver', mode='on', dcW=1.2, acW=0),
           dict(equipment='Ranging tone transfer assembly', mode='on', dcW=5.0, acW=0),
           dict(equipment='Premodulation processor', mode='on', dcW=4.3, acW=0),
           dict(equipment='Audio center (one)', mode='on', dcW=4.8, acW=0),
           dict(equipment='Digital uplink assembly', mode='uplink data', dcW=12.5, acW=0),
           dict(equipment='Digital uplink assembly', mode='voice backup', dcW=2.5, acW=0),
           dict(equipment='Biomedical sensors', mode='on', dcW=3.0, acW=0),
           dict(equipment='CS displays', mode='on', dcW=3.0, acW=0),
           dict(equipment='TV camera', mode='on', dcW=6.0, acW=0)])
    ev('sband_tr_supply', 782, '3-112', 'Table 3-1, panel 12, 13S8',
       'PRIM selects primary converter through panel 16 primary T/R breaker from LMP DC; SEC selects secondary converter through panel 11 secondary T/R breaker from CDR DC; OFF interrupts both. Either powered selection enables the power amplifier.')
    ev('sband_pa_supply', 783, '3-113', 'Table 3-1, panel 12, 13S2',
       'PRIM selects amplifier power supply 1 from LMP DC; SEC selects power supply 2 from CDR DC. The transmitter-receiver selector must be PRIM or SEC to enable the amplifier. The 18.6 W and 14.8 W values in this control table are minimum RF output, not electrical input.')
    ev('vhf_a_supply', 784, '3-114', 'Table 3-1, panel 12, 13S7 and 13S10',
       'VHF A transmitter is supplied through its panel 16 LMP DC breaker; VHF A receiver ON supplies its regulator through the panel 11 CDR DC breaker; OFF interrupts receiver power.')
    ev('vhf_b_biomed_supply', 785, '3-115', 'Table 3-1, panel 12, 13S12, 13S15 and 13S3',
       'VHF B transmitter uses CDR DC; receiver uses LMP DC. BIOMED LEFT or RIGHT selects one suit biomedical supply through COMM PMP; OFF interrupts both. VHF B transmitter function wording is internally reversed relative to the VOICE/DATA row labels; transmit-mode loads are withheld.')
    ev('antenna_supply', 786, '3-116', 'Table 3-1, panel 12, 14S3',
       'AUTO and SLEW apply AC and DC antenna electronics power. OFF interrupts both supplies. DC is through panel 16 COMM S-BD ANT on LMP DC; AC is through panel 11 AC BUS B S-BD ANT.')
    ev('dua_supply', 779, '3-109', 'Table 3-1, panel 12, 13S16',
       'UPDATA LINK VOICE BU enables backup voice mode, DATA enables digital uplink, and OFF disables both. Supply is panel 11 COMM UP DATA LINK from CDR DC.')
    ev('comms_branch_mapping', 383, '2.5-6A/2.5-6B', 'Figure 2.5-2, EPS functional diagram, communications branches',
       'Identified COMM PMP, COMM DISP and SE AUDIO branches are on LMP DC; CDR AUDIO and UP DATA LINK are on CDR DC. Branch labels are mapped to stable panel breaker IDs using the detailed inventory. Audio route/volume switches are not treated as power switches.',
       relatedPdfPages=[381, 382], classification='source_circuit_mapping')
    ev('ordeal_power', 205, '2.1-163', 'Table 2.1-25, Orbital Rate Display - Earth and Lunar',
       'ORDEAL requires 4 W DC and 4 W AC. AC supply is 115 +/- 2.5 V rms single phase 400 Hz; specified power factor is 0.9 minimum. DC supply is 28 +/- 3 V.',
       classification='equipment_input_power', dcW=4.0, acW=4.0, minimumAcPowerFactor=0.9)
    ev('ordeal_supply', 822, '3-152', 'Table 3-1, ORDEAL, 9S25',
       'EARTH and LUNAR select the scale factor with power applied; PWR OFF removes AC and DC. Supplies are CDR DC through FLIGHT DISPLAYS ORDEAL and AC BUS B through AC BUS B ORDEAL, both panel 11. Lighting brightness is separate and no per-brightness input-power decomposition is supplied.')
    ev('eps_input_power', 409, '2.5-31', 'Table 2.5-3, EPS Performance and Design Data (continued)',
       'EPS displays require 2 W. Ascent ECAs list 10 W steady state and descent ECAs 20 W steady state; both list 84 W momentarily during battery switching. The plural ECA rows do not establish a per-box/per-bus partition.',
       classification='equipment_input_power', epsDisplaysW=2.0,
       ascentEcasSteadyW=10.0, descentEcasSteadyW=20.0, ecaSwitchingW=84.0)
    ev('eps_display_supply', 383, '2.5-6A/2.5-6B', 'Figure 2.5-2, panel 16 EPS DISP branch',
       'The EPS display branch is supplied from LMP DC and corresponds to stable breaker p16_cb_r04_c08.', classification='source_circuit_mapping')
    ev('cabin_fan', 439, '2.6-27', 'Section 2.6.3.1.7, Cabin Fan',
       'LM-7 cabin fan input is described as 35 W average and 110 W peak at 28 V. These are not a sourced constant-power operating mode or a thermal/mechanical duty cycle.',
       classification='average_and_peak_equipment_input', averageW=35.0, peakW=110.0)
    ev('suit_fans_unquantified', 436, '2.6-24', 'Suit fan functional description',
       'Describes 28 V brushless fan motors, airflow and speed, but does not quantify electrical operating watts or current.', classification='voltage_only_not_draw')
    ev('coolant_pumps_unquantified', 449, '2.6-37', 'Coolant pump assembly functional description',
       'Describes three 28 V pump motors (two primary and one secondary), but does not quantify electrical operating watts or current.', classification='voltage_only_not_draw')
    ev('ags_primary_design', 204, '2.1-162', 'Table 2.1-23, Abort Guidance Section',
       'AGS primary power lists 90 W DC and 3.5 W AC. Operating versus standby allocation, per-box allocation and the switched supply paths require further work before runtime use.',
       classification='aggregate_design_requirement', dcW=90.0, acW=3.5)
    ev('inverter_capacity', 408, '2.5-30', 'Table 2.5-3, Inverters',
       'Normal 0 to 350 VA output and 525 VA ten-minute overload are inverter capacities, not operating loss or idle consumption. No efficiency or idle draw is derived from them.', classification='capacity_not_load')
    ev('lighting_voltage_only', 636, '2.10-12', 'Interior lighting performance table',
       'The power entries are supply voltages and frequencies, not input wattages. They do not quantify a lighting load.', classification='voltage_only_not_draw')

    loads = []

    def req(control, positions):
        return dict(controlId=control, allowedPositions=positions)

    def load(ident, label, bus, breaker, watts, requirements, evidence_ids, qualification):
        loads.append(dict(id=ident, label=label, busId=bus, breakerIds=[breaker],
                          switchRequirements=requirements, powerW=watts,
                          sourceId=SOURCE_ID, qualification=qualification,
                          evidenceIds=evidence_ids))

    operating = 'Handbook operating input requirement represented as a constant real-power load; voltage dependence, warm-up and unlisted transients are not quantified.'
    for mode, bus, breaker in [('PRIM', 'LMP_DC', 'p16_cb_r03_c06'), ('SEC', 'CDR_DC', 'p11_cb_r04_c11')]:
        load('sband_tr_' + mode.lower(), 'S-band transmitter-receiver ' + mode, bus, breaker, 36.0,
             [req('p12_s_band_xmtr_rcvr', [mode])], ['comms_input_power', 'sband_tr_supply'],
             operating + ' The 36 W is the combined transmitter-receiver equipment requirement, counted once for the selected supply.')
    for mode, bus, breaker in [('PRIM', 'LMP_DC', 'p16_cb_r03_c05'), ('SEC', 'CDR_DC', 'p11_cb_r04_c12')]:
        load('sband_pa_' + mode.lower(), 'S-band power amplifier and diplexer ' + mode, bus, breaker, 72.0,
             [req('p12_pwr_ampl', [mode]), req('p12_s_band_xmtr_rcvr', ['PRIM', 'SEC'])],
             ['comms_input_power', 'sband_pa_supply', 'sband_tr_supply'],
             operating + ' 72 W is electrical input; RF output wattages are not substituted. Enable follows T/R selector position; internal cross-equipment loss-of-supply behavior is not independently quantified.')
    for mode, dc, ac in [('AUTO', 0.7, 4.0), ('SLEW', 7.6, 27.9)]:
        for suffix, bus, breaker, watts in [('dc', 'LMP_DC', 'p16_cb_r03_c07', dc), ('ac', 'AC_B', 'p11_cb_r01_c03', ac)]:
            load('sband_antenna_' + mode.lower() + '_' + suffix,
                 'S-band antenna electronics ' + mode + ' ' + suffix.upper(), bus, breaker, watts,
                 [req('p12_track_mode', [mode])], ['comms_input_power', 'antenna_supply'],
                 operating + (' AC watts are real-power equivalent in the ideal inverter model; reactive current and power factor are not asserted.' if suffix == 'ac' else '') +
                 ' Each supply is represented independently; partial-supply failure effects on the other input are not quantified.')
    for side, bus, breaker, switch in [('a', 'CDR_DC', 'p11_cb_r04_c14', 'p12_vhf_a_rcvr'), ('b', 'LMP_DC', 'p16_cb_r03_c04', 'p12_vhf_b_rcvr')]:
        load('vhf_' + side + '_receiver', 'VHF ' + side.upper() + ' receiver', bus, breaker, 1.2,
             [req(switch, ['ON'])], ['comms_input_power', 'vhf_a_supply' if side == 'a' else 'vhf_b_biomed_supply'], operating)
    for ident, label, bus, breaker, watts in [
            ('premodulation_processor', 'Premodulation processor', 'LMP_DC', 'p16_cb_r03_c08', 4.3),
            ('cdr_audio_center', 'CDR audio center', 'CDR_DC', 'p11_cb_r04_c15', 4.8),
            ('lmp_audio_center', 'LMP audio center', 'LMP_DC', 'p16_cb_r03_c02', 4.8),
            ('communications_displays', 'Communications displays', 'LMP_DC', 'p16_cb_r03_c01', 3.0)]:
        load(ident, label, bus, breaker, watts, [], ['comms_input_power', 'comms_branch_mapping'],
             operating + ' On-state is represented by its energized, closed supply branch; no unestablished route, volume or display-selector power gate is invented.')
    for mode, suffix, watts in [('DATA', 'data', 12.5), ('VOICE-BU', 'voice_backup', 2.5)]:
        load('digital_uplink_' + suffix, 'Digital uplink assembly ' + suffix.replace('_', ' '),
             'CDR_DC', 'p11_cb_r04_c10', watts, [req('p12_updata_link', [mode])],
             ['comms_input_power', 'dua_supply'], operating)
    load('selected_biomedical_sensors', 'Selected crew biomedical sensors', 'LMP_DC', 'p16_cb_r03_c08', 3.0,
         [req('p12_telemetry_biomed', ['LEFT', 'RIGHT'])], ['comms_input_power', 'vhf_b_biomed_supply'],
         operating + ' One selected suit source is counted; disconnected wearable interfaces and physiological sensor behavior are outside this partial model.')
    for suffix, bus, breaker in [('dc', 'CDR_DC', 'p11_cb_r02_c16'), ('ac', 'AC_B', 'p11_cb_r01_c04')]:
        load('ordeal_' + suffix, 'ORDEAL ' + suffix.upper(), bus, breaker, 4.0,
             [req('ordeal_earth_lunar', ['EARTH', 'LUNAR'])], ['ordeal_power', 'ordeal_supply'],
             operating + ' Brightness-dependent decomposition is unavailable; 4 W represents the listed equipment requirement.' +
             (' Source specifies minimum 0.9 power factor; runtime consumes 4 W real-power equivalent through an ideal inverter and makes no RMS or reactive-current claim.' if suffix == 'ac' else '') +
             ' Each input is represented independently; partial-supply failure effects on the other input are not quantified.')
    load('eps_displays', 'EPS displays', 'LMP_DC', 'p16_cb_r04_c08', 2.0, [],
         ['eps_input_power', 'eps_display_supply'], operating + ' Display branch powered state is used; selector position is not treated as an on/off switch.')

    assert len(loads) == 20
    evidence_ids = {e['id'] for e in evidence}
    for item in loads:
        assert item['powerW'] > 0 and 'currentA' not in item
        assert item['evidenceIds'] and set(item['evidenceIds']) <= evidence_ids
        for breaker_id in item['breakerIds']:
            assert breaker_id in controls and breaker_id in breakers, breaker_id
            assert breakers[breaker_id]['busId'] == item['busId'], item['id']
            assert controls[breaker_id]['type'] == 'breaker', breaker_id
        for requirement in item['switchRequirements']:
            control = controls[requirement['controlId']]
            assert requirement['allowedPositions']
            assert set(requirement['allowedPositions']) <= set(control['positions']), requirement
    assert len({item['id'] for item in loads}) == len(loads)
    source = Path(SOURCE_PATH)
    actual_source_sha = hashlib.sha256(source.read_bytes()).hexdigest() if source.exists() else None
    if actual_source_sha is not None:
        assert actual_source_sha == SOURCE_SHA, 'Source PDF changed: repeat visual evidence review.'
    return dict(
        schemaVersion=1,
        title='LM-7 partial source-valued equipment input-power evidence',
        status='PARTIAL: twenty branch/state-gated real-power loads; not a full vehicle budget or independent flight validation',
        inventorySha256=hashlib.sha256(inventory_path.read_bytes()).hexdigest(),
        sources=[dict(id=SOURCE_ID, title='Apollo Operations Handbook, LM 7 and Subsequent, Volume 1, LMA790-3-LM',
                      path=SOURCE_PATH, sha256=SOURCE_SHA,
                      url='https://apollojournals.org/afj/ap13fj/pdf-hr/a13-lm-aoh-v1-lm7-subs-300ppi.pdf',
                      revision='1 February 1970', pageNumbering='One-based PDF pages; printed pages recorded independently')],
        modelBoundary=[
            'Every runtime value is published equipment input watts. Breaker rated amperage is protection capacity and is never used to infer equipment draw.',
            'These loads replace the aggregate load model only in an explicitly partial sourced-components mode. Never add them to the calibrated aggregate presets.',
            'Published design/operating requirements are approximated as constant real power; they do not establish measured mission telemetry or a discharge curve.',
            'All entries require an energized bus and their closed supply breaker. Switch requirements are additional AND gates; positions within one requirement are OR alternatives.',
            'PRIM/SEC, antenna AUTO/SLEW and digital uplink modes are mutually exclusive because they share one source switch, not because their wattages were adjusted to match a total.',
            'AC input watts contribute real power through the existing ideal inverter. No RMS apparent-current, inverter loss, efficiency or reactive-current model is introduced.',
            'No unknown residual load is added. No watts or allocations were chosen to fit the 12 A, 30 A, 92.52 Ah discrepancy or any historical endpoint.',
            'Individual equipment states are software operating abstractions constrained by sourced switch functions; missing equipment failure/duty-cycle details remain explicit.'
        ],
        evidence=evidence,
        runtimeLoads=loads,
        unsupportedModes=[
            dict(id='vhf_transmitter_modes', evidenceIds=['comms_input_power', 'vhf_a_supply', 'vhf_b_biomed_supply'],
                 publishedInputW=dict(aVoice=30.0, aIdle=3.5, bVoice=28.9, bData=31.7, bIdle=3.5),
                 reason='No included VHF transmitter load: selector position alone cannot distinguish PTT/VOX/ranging/data carrier activity from not-transmitting. A fixed 3.5 W while keyed would be wrong.',
                 rootNeeds=['Couple actual keying state to selected radio channel, PTT and VOX routing.', 'Establish VOICE/RNG carrier duty and VHF B DATA semantics before mode-dependent loading.', 'Resolve the reversed VHF B function wording on PDF 785 using an independent circuit/source.']),
            dict(id='antenna_heater_duty', evidenceIds=['comms_input_power'], powerW=51.7,
                 reason='Heater ON requirement is sourced; thermostat switching/duty and enabled thermal state are not established by a closed breaker.'),
            dict(id='ranging_tone_transfer', evidenceIds=['comms_input_power'], powerW=5.0,
                 reason='ON requirement is sourced; exact supply and mode gates need independent circuit confirmation.'),
            dict(id='tv_camera', evidenceIds=['comms_input_power'], powerW=6.0,
                 reason='Camera ON requirement is sourced; the camera local power control/interface is outside the current cabin inventory. COMM TV breaker alone does not prove camera ON.'),
            dict(id='eca_steady_and_switching', evidenceIds=['eps_input_power'],
                 reason='Plural ECA design rows do not establish per-box/per-bus allocation or switching duration; not split equally or multiplied by assumed box count.'),
            dict(id='cabin_fan', evidenceIds=['cabin_fan'],
                 reason='35 W average and 110 W peak are not a constant-power load/duty cycle. Motor/control supply paths also need resolved circuit-level gating.'),
            dict(id='suit_fans_and_coolant_pumps', evidenceIds=['suit_fans_unquantified', 'coolant_pumps_unquantified'],
                 reason='Operating watts/current absent in the reviewed LM-7 functional descriptions. 28 V supply and breaker ratings cannot establish draw.'),
            dict(id='ags_modes', evidenceIds=['ags_primary_design'],
                 reason='90 W DC plus 3.5 W AC is a combined primary design requirement; no proven standby/operate/per-box allocation included.'),
            dict(id='inverter_and_lighting', evidenceIds=['inverter_capacity', 'lighting_voltage_only'],
                 reason='VA output capacity and lighting supply voltages are not operating power draws; inverter idle/loss and dimmer load laws remain unknown.')],
        sourceQualifications=[
            dict(id='lm7_cabin_fan_configuration', evidenceIds=['cabin_fan'],
                 qualification='Use the LM-7 35 W average / 110 W peak values. Later/general ECS descriptions can differ; their 62 W / 210 W values are not silently substituted.'),
            dict(id='sband_rf_vs_dc', evidenceIds=['sband_pa_supply', 'comms_input_power'],
                 qualification='Minimum RF output of 18.6 W primary or 14.8 W secondary is not the 72 W electrical input.'),
            dict(id='cross_supply_failures',
                 qualification='The source shows each supply independently. Modeling loss of one supply as suppressing another input requires additional evidence; no speculative cross-bus load gate is introduced.')],
        validation=dict(runtimeLoadCount=len(loads), inputPowerUnit='W real power',
                        allStableControlIdsValid=True, allStatesValid=True,
                        allSupplyPathsOnDeclaredBus=True, noBreakerRatingUsedAsDraw=True,
                        noInferredResidualOrHistoricalFit=True,
                        sourcePdfShaVerified=actual_source_sha == SOURCE_SHA,
                        completeVehicleLoadCoverage=False,
                        independentFlightValidationPassed=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', type=Path, default=ROOT / 'reference/controls.json')
    parser.add_argument('--electrical', type=Path, default=ROOT / 'reference/electrical.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'reference/electrical-load-evidence.json')
    args = parser.parse_args()
    data = build(args.inventory, args.electrical)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(output=str(args.output), runtimeLoads=len(data['runtimeLoads']),
                          evidencePages=len(data['evidence']), inventorySha256=data['inventorySha256'],
                          outputSha256=hashlib.sha256(args.output.read_bytes()).hexdigest())))


if __name__ == '__main__':
    main()
