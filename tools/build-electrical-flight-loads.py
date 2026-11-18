"""Build an optional, explicitly cross-vehicle electrical research overlay.

LM-8 branch input watts are transferred as declared proxies for selected LM-7
equipment.  This file does not modify the normal twenty-load equipment catalog,
establish flown initial conditions, or fit a historical current observation.
Thermostatic heaters remain demand-dependent candidates, never always-on loads.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LM8_PATH = Path('D:/apollo-ref/lm-systems/HSI-208818.pdf')
LM7_PATH = Path('D:/apollo-ref/lm-systems/a13-lm-aoh-v1-lm7-subs-300ppi.pdf')
LM8_REVIEWED_SHA256 = '01ca5997b95e1181b1f1b71ef27ae1a27ce8a09c0cfbfe4415365540810ab863'
LM7_REVIEWED_SHA256 = '1623f208023279cbe7de6aea14e95bd95fbc8c4e9d51791ff55e68ee04d338f2'


def sha(path):
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(8 * 1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def verified_review_source(path, reviewed_sha256):
    if not path.is_file():
        raise FileNotFoundError(f'Reviewed primary source is required: {path}')
    actual_sha256 = sha(path)
    if actual_sha256 != reviewed_sha256:
        raise ValueError(f'Primary source changed: {path}. Repeat complete-page visual '
                         'review before updating the reviewed SHA256 and evidence.')
    return actual_sha256


def build(inventory_path, electrical_path):
    lm8_sha256 = verified_review_source(LM8_PATH, LM8_REVIEWED_SHA256)
    lm7_sha256 = verified_review_source(LM7_PATH, LM7_REVIEWED_SHA256)
    inventory = json.loads(inventory_path.read_text(encoding='utf-8'))
    electrical = json.loads(electrical_path.read_text(encoding='utf-8'))
    controls = {c['id']: c for c in inventory['controls']}
    by_ref = {c.get('referenceDesignation'): c['id'] for c in inventory['controls']
              if c.get('referenceDesignation')}
    breakers = {b['controlId']: b for b in electrical['breakers']}
    evidence = []
    loads = []
    heaters = []

    def req(ident, *positions):
        return dict(controlId=ident, allowedPositions=list(positions))

    def ev(ident, source, page, printed, locator, finding, **extra):
        evidence.append(dict(id=ident, sourceId=source, pdfPage=page,
                             printedPage=printed, locator=locator,
                             review='visual_complete_page', finding=finding,
                             **extra))

    for page, printed in [(63, '5-7'), (64, '5-8'), (65, '5-9'), (66, '5-10')]:
        ev(f'lm8_branch_table_{page}', 'lm8-systems-handbook', page, printed,
           'Table 5-III, Circuit Breakers, LOAD AT 28 VDC OR 115 VAC / WATTS',
           'The equipment-input WATTS column is separate from breaker RATING (AMPS), '
           'AMPS and HEAT LOAD columns. The page explicitly says LM-8 BASIC. '
           'LM-7 equality is a transfer assumption, not established by this table.')
    ev('lm7_ecs_selectors', 'lm7-aoh-v1', 727, '3-57', 'Table 3-1, 7S3 and 7S1',
       'GLYCOL selects primary pump 1 or 2; INST (SEC) selects instrumentation, '
       'not the secondary pump motor. SUIT FAN 1/2 selects its motor and OFF '
       'removes fan power. Automatic transfer after pump failure is not a normal '
       'selector state and is outside this overlay.')
    ev('lm7_pump_branches', 'lm7-aoh-v1', 775, '3-105', 'Table 3-1, 4CB117 and 4CB141',
       'Each primary glycol pump is supplied from CDR DC through its own breaker '
       'and GLYCOL PUMP switch. AUTO TRNFR is a relay-control branch, not a pump load.')
    ev('lm7_ags_states', 'lm7-aoh-v1', 757, '3-87', 'Table 3-1, 12S17 AGS STATUS',
       'OFF removes AGS operating power but retains ASA heater supply. STANDBY '
       'applies full ASA power and AEA warmup. OPERATE applies full ASA and AEA power. '
       'AEA warmup watts and thermostat duty are not established.')
    ev('lm7_stab_branches', 'lm7-aoh-v1', 804, '3-134',
       'Table 3-1, 4CB28, 4CB79, 4CB82 and 4CB230',
       'LMP DC feeds AEA, ASA, ATCA power supply and AGS ATCA selection/bias branch. '
       'AEA has another CDR feed; ASA breaker also acts as its on/off supply.')
    ev('lm7_stab_cdr_branches', 'lm7-aoh-v1', 772, '3-102',
       'Table 3-1, 4CB238 and 4CB81',
       'CDR DC provides AEA main supply and ATCA PGNS selection/bias supply. '
       'The table does not establish redundant AEA feed sharing.')
    ev('lm7_deca_branch', 'lm7-aoh-v1', 773, '3-103', 'Table 3-1, 4CB69 and 4CB80',
       'DECA PWR applies CDR DC to DECA for engine-on function and trim-fail circuit. '
       'ENG CONT supplies engine-related control functions; its operating draw '
       'is not proven constant by closing its breaker.')
    ev('lm7_suit_delta_p_supply', 'lm7-aoh-v1', 807, '3-137', 'Table 3-1, 4CB120',
       'SUIT FAN DP supplies LMP DC to the suit fan differential-pressure sensor. '
       'Its electrical supply is not gated by the selected fan motor switch.')
    ev('lm7_rcs_instrument_supply', 'lm7-aoh-v1', 802, '3-132', 'Table 3-1, 4CB50, 4CB103 and 4CB121',
       '4CB50 supplies LMP DC to RCS TEMP/PRESS indicators and talkbacks. 4CB103 '
       'supplies LMP DC to main-propulsion temperature/pressure indicators and '
       'talkbacks. 4CB121 supplies LMP DC to the RCS propellant-quantity device. '
       'LM-8 Table 5-III assigns 4CB121 to CDR; that transfer is withheld.')
    ev('lm7_coas_gate', 'lm7-aoh-v1', 766, '3-96', 'Table 3-1, 16S14 COAS',
       'FWD or OVHD energizes the corresponding COAS connector from CDR DC through '
       'the FLIGHT DISPLAYS COAS breaker. OFF removes connector power. '
       'Brightness dependence is not quantified by the LM-8 maximum/nominal branch entry.')
    ev('lm7_rcs_heater_elements', 'lm7-aoh-v1', 360, '2.4-14', 'Section 2.4.3.4.2, Heaters',
       'Thirty-two heaters serve sixteen TCAs: two per TCA, one on each redundant '
       'bank. Each element is 17.5 W at 24 V. Four elements per quad/bank imply '
       '70 W at 24 V. Primary thermostat setpoint is 140 +/- 8 F, redundant '
       '147 +/- 7 F, with a 2 F deadband. Supply is described as 28 V DC.',
       elementsPerQuadBank=4, elementRatedW=17.5, elementRatedV=24,
       quadBankRatedW=70.0, primaryThermostatF=140, primaryThermostatToleranceF=8,
       redundantThermostatF=147, redundantThermostatToleranceF=7, deadbandF=2)
    ev('lm7_rcs_heater_gate', 'lm7-aoh-v1', 740, '3-70', 'Table 3-1, 11S4 through 11S7',
       'Bank 1 provides automatic heater control without override. Bank 2 AUTO '
       'uses temperature control, OFF interrupts power, and MAN bypasses temperature '
       'control to hold 28 V on its heaters. Breaker closure is not thermostat demand.')

    proxy = ('LM-8 BASIC branch input watts transferred to LM-7 as an explicit '
             'research proxy. LM-7 equality, flight initial conditions, warmup, '
             'voltage dependence and unlisted duty cycles are unverified. ')

    def load(ident, label, ref, watts, page, requirements=None, extra='', evidence_ids=()):
        breaker_id = by_ref[ref]
        loads.append(dict(id='flight_proxy_' + ident, label=label,
                          busId=breakers[breaker_id]['busId'], breakerIds=[breaker_id],
                          switchRequirements=requirements or [], powerW=watts,
                          sourceId='lm8-systems-handbook',
                          evidenceIds=[f'lm8_branch_table_{page}', *evidence_ids],
                          qualification=proxy + extra,
                          sourceReferenceDesignation=ref, sourcePdfPage=page,
                          vehicleApplicability='LM-8 value / LM-7 transfer assumption',
                          independentFlightValidation=False))

    for number, ref in [(1, '4CB138'), (2, '4CB119')]:
        load(f'suit_fan_{number}', f'Suit fan {number} (LM-8 proxy)', ref, 163.0, 65,
             [req('p2_suit_fan', str(number))],
             'Normal selected-fan operation; no fan failure or automatic transfer modeled.',
             ['lm7_ecs_selectors'])
    for number, ref in [(1, '4CB117'), (2, '4CB141')]:
        load(f'glycol_pump_{number}', f'Primary glycol pump {number} (LM-8 proxy)',
             ref, 30.5, 65, [req('p2_glycol_selector', f'PUMP {number}')],
             'Normal selected primary-pump operation; no failed-pump automatic transfer.',
             ['lm7_ecs_selectors', 'lm7_pump_branches'])
    load('asa_electronics', 'ASA operating electronics (LM-8 proxy)', '4CB79', 41.1, 64,
         [req('p6_ags_status', 'STANDBY', 'OPERATE')],
         'Only the ELECT row is included. The separate 253 W thermostat-controlled '
         'heater row is never included automatically.', ['lm7_ags_states', 'lm7_stab_branches'])
    for side, ref, other_ref in [('lmp', '4CB28', '4CB238'), ('cdr', '4CB238', '4CB28')]:
        load('aea_' + side, f'AEA single {side.upper()} feed (LM-8 proxy)', ref, 47.0,
             63 if side == 'lmp' else 66,
             [req('p6_ags_status', 'OPERATE'), req(by_ref[other_ref], 'PULLED')],
             'Conservative single-feed configuration only: other AEA breaker must '
             'be PULLED. Both feeds closed withholds this load because sharing '
             'is unresolved; it must not be read as a zero-power prediction. '
             'Standby warmup is withheld. No separate assumed DEDA draw is added.',
             ['lm7_ags_states', 'lm7_stab_branches', 'lm7_stab_cdr_branches'])
    for mode, watts in [('PGNS', 55.0), ('AGS', 65.0)]:
        load('atca_' + mode.lower(), f'ATCA {mode} mode (LM-8 proxy)', '4CB82', watts, 64,
             [req('p1_guid_cont', mode)],
             'The source mode distinction is selected by GUID CONT. This is the '
             'branch total; internal 800 Hz RGA/controller power is not added again. '
             'Failure/dead bias-supply mode consumption is not established.',
             ['lm7_stab_branches', 'lm7_stab_cdr_branches'])
    load('deca', 'DECA power (LM-8 proxy)', '4CB69', 10.6, 64,
         extra='Closed branch represents the nominal equipment input; engine-on '
               'versus trim-fail decomposition is unavailable.', evidence_ids=['lm7_deca_branch'])
    # These named rows represent equipment continuously supplied by their branch.
    # Multi-bus aggregate entries, transient actuator rows and variable light rows
    # are intentionally withheld below rather than split or held at their peaks.
    for ident, label, ref, watts, page in [
        ('co2_sensor', 'CO2 sensor', '4CB84', 1.0, 64),
        ('ecs_display', 'ECS display', '4CB140', 4.9, 65),
        ('signal_conditioner_1', 'Signal conditioner 1', '4CB131', 12.6, 65),
        ('mission_timer', 'Mission timer', '4CB159', 2.5, 65),
        ('des_eca_cdr', 'Descent ECA CDR supply', '4CB10', 10.0, 63),
        ('des_eca_lmp', 'Descent ECA LMP supply', '4CB11', 10.0, 63),
        ('asc_eca_cdr', 'Ascent ECA CDR supply', '4CB15', 5.0, 63),
        ('asc_eca_lmp', 'Ascent ECA LMP supply', '4CB14', 5.0, 63),
    ]:
        load(ident, label + ' (LM-8 proxy)', ref, watts, page,
             extra='Nominal continuously supplied branch model; missing component '
                   'failure or sub-mode behavior remains outside this overlay.')
    for ident, label, ref, watts, page, gate_evidence in [
        ('suit_fan_delta_p', 'Suit fan differential-pressure sensor', '4CB120', 3.6, 65,
         'lm7_suit_delta_p_supply'),
        ('rcs_temp_pressure_display', 'RCS temperature/pressure display and flags', '4CB50', 2.12, 64,
         'lm7_rcs_instrument_supply'),
        ('main_prop_temp_pressure_display', 'Main propulsion temperature/pressure display and flags',
         '4CB103', 3.05, 64, 'lm7_rcs_instrument_supply'),
    ]:
        load(ident, label + ' (LM-8 proxy)', ref, watts, page,
             extra='Nominal continuously supplied instrumentation branch. '
                   'The LM-7 table establishes its direct LMP DC breaker supply; '
                   'no inferred fan or engine activity gate is added.',
             evidence_ids=[gate_evidence])

    def heater(ident, label, ref, watts, page, requirements, **extra):
        breaker_id = by_ref[ref]
        heaters.append(dict(id='flight_proxy_' + ident, label=label,
                            busId=breakers[breaker_id]['busId'], breakerIds=[breaker_id],
                            switchRequirements=requirements, powerW=watts,
                            sourceId='lm8-systems-handbook',
                            evidenceIds=[f'lm8_branch_table_{page}',
                                         *extra.pop('evidenceIds', [])],
                            qualification=proxy + 'ON input only; a separate explicit '
                            'demand fraction or measured thermal state is required. '
                            'Included in the optional overlay only as a duty-controlled '
                            'load; consumers must provide an explicit demand fraction.',
                            nominalVoltageV=28.0, demandFractionRange=[0.0, 1.0],
                            demandIsKnown=False, dutyControlled=True, **extra))

    for bank in [1, 2]:
        for quad in range(1, 5):
            ref = f'4CB{217 + quad if bank == 1 else 221 + quad}'
            requirements = [] if bank == 1 else [req(f'p3_rcs_sys_a_b_2_quad_{quad}', 'AUTO', 'MAN')]
            heater(f'rcs_heater_bank{bank}_quad{quad}', f'RCS bank {bank} quad {quad}',
                   ref, 95.5, 66, requirements, thermalBank=bank, quad=quad,
                   manualDemandControl=None if bank == 1 else f'p3_rcs_sys_a_b_2_quad_{quad}',
                   fullDemandPositions=[] if bank == 1 else ['MAN'],
                   evidenceIds=['lm7_rcs_heater_elements', 'lm7_rcs_heater_gate'],
                   lm7ElementCalculation=dict(ratedW=70.0, ratedV=24.0,
                       resistiveInferenceAt28VW=70.0 * (28.0 / 24.0) ** 2,
                       qualification='Resistance/temperature dependence is unmeasured; '
                       'this calculation corroborates but does not replace LM-8 table95.5W.'))
    heater('asa_heater', 'ASA thermostatic heater', '4CB79', 253.0, 64, [],
           evidenceIds=['lm7_ags_states'],
           qualificationNote='AGS STATUS OFF retains ASA heater supply; do not gate '
           'heater availability on OPERATE. Heater power is thermostat-dependent.')
    heater('imu_standby_heater', 'IMU standby heat', '4CB161', 109.0, 65, [],
           qualificationNote='Closed IMU STBY supply does not establish continuous '
           '109 W thermal demand or flown temperature history.')

    evidence_by_id = {e['id']: e for e in evidence}
    for item in loads + heaters:
        assert item['powerW'] > 0 and 'currentA' not in item
        assert all(e in evidence_by_id for e in item['evidenceIds'])
        for ident in item['breakerIds']:
            assert ident in breakers and controls[ident]['type'] == 'breaker'
            assert breakers[ident]['busId'] == item['busId']
        for r in item['switchRequirements']:
            assert set(r['allowedPositions']) <= set(controls[r['controlId']]['positions'])
    assert len({e['id'] for e in loads + heaters}) == len(loads + heaters)
    return dict(schemaVersion=1,
        title='Optional LM-8 input-power proxies for LM-7 flight-validation research',
        status='PARTIAL / CROSS-VEHICLE PROXY / NOT INDEPENDENT FLIGHT VALIDATION',
        inventorySha256=sha(inventory_path), electricalDefinitionSha256=sha(electrical_path),
        sources=[
            dict(id='lm8-systems-handbook', title='LM-8 Systems Handbook',
                 path=str(LM8_PATH), url='https://www.ibiblio.org/apollo/Documents/HSI-208818.pdf',
                 revision='15 September 1970, LM-8 BASIC', sha256=lm8_sha256,
                 applicability='LM-8; every transferred LM-7 watt value is a declared proxy'),
            dict(id='lm7-aoh-v1', title='Apollo Operations Handbook, LM7 and Subsequent, Vol1',
                 path=str(LM7_PATH),
                 url='https://apollojournals.org/afj/ap13fj/pdf-hr/a13-lm-aoh-v1-lm7-subs-300ppi.pdf',
                 revision='1 February 1970', sha256=lm7_sha256,
                 applicability='LM-7 switch/supply functions and heater element requirements')],
        modelBoundary=[
            'Optional overlay only. The normal twenty-load LM-7 catalog is unchanged.',
            'No input watts or allocations are chosen to reproduce 25 A, 12 A or a reserve endpoint.',
            'Cross-vehicle transfer error and missing-power error have no established numeric bound.',
            'Values are nominal branch inputs; constant-power representation is an approximation.',
            'Heater availability and demand are separate. Candidates require explicit duty assumptions.',
            'LM-7 values take precedence where sources overlap; conflicting LM-8 comms/audio/EPS-display values are withheld.',
            'Unmodeled inverter losses and transient solenoid loads are not backfilled as residual watts.',
            'Single-feed AEA constraints prevent duplicate debit; dual-feed sharing remains unresolved.'],
        evidence=evidence, runtimeLoads=loads + heaters, heaterCandidates=heaters,
        uncertainDutyLoadIds=[h['id'] for h in heaters],
        excludedModes=[
            dict(id='rcs_quantity_bus_conflict', referenceDesignation='4CB121',
                 sourcePdfPage=65, publishedW=1.06, sourceBus='CDR_DC',
                 lm7GatePdfPage=802, lm7GateBus='LMP_DC',
                 reason='LM-8 input-power row assigns CDR while the LM-7 control '
                 'table and modeled breaker assign LMP. Withheld pending cross-vehicle '
                 'circuit adjudication; no silent bus transfer.'),
            dict(id='aea_dual_feed_and_warmup', reason='Both AEA feeds closed has no known sharing; standby/warmup watts unavailable.'),
            dict(id='ags_ac', sourcePdfPage=66, publishedW=3.45,
                 reason='The AC input mode gate and partial-supply response require circuit review; not a switch-only draw.'),
            dict(id='atca_bias', sourcePdfPages=[64, 66], publishedW=2.0,
                 reason='PGNS/AGS selector and mode bias paths do not establish a constant branch operating law.'),
            dict(id='rcs_thrusters', sourcePdfPages=[63, 64], publishedPerTcaW=112.0,
                 reason='Actual jet commands and dwell times required; closed TCA breaker is not firing.'),
            dict(id='engine_control', sourcePdfPage=64, publishedW=10.5, publishedA=0.28,
                 reason='Watts and amp columns disagree at28V; function/state consumption unresolved.'),
            dict(id='engine_arm_and_actuators', sourcePdfPages=[63, 64, 66],
                 reason='Momentary, solenoid or engine-state duty not established.'),
            dict(id='coas_and_lighting', sourcePdfPage=66, coasW=8.4,
                 reason='COAS local rheostat/connector occupancy and light brightness/duty unquantified; no full-bright current assumed.'),
            dict(id='multi_bus_instrumentation', sourcePdfPages=[63, 64, 65],
                 entries=['SIG CONDR2 10.36W', 'CWEA11.48W', 'PCMTE11W', 'SIG SENSOR14W mated'],
                 reason='Table describes CDR AND LMP aggregate; no invented per-bus split.'),
            dict(id='pgs_computer_and_imu_operate', sourcePdfPage=65,
                 reason='Power mode, standby and heater overlap unresolved; manual MCC kept LGC and IMU operate off.'),
            dict(id='lm8_document_discrepancies', sourcePdfPage=65,
                 entries=['EVENT TIMER/SE FDAI6.52W vs2.33A', 'ECS DISP4.9W vs1.77A'],
                 reason='Use printed watts only when included; never silently correct printed amp values.'),
        ],
        uncertainty=dict(
            numericalTableResolution='As printed:0.1W for most power rows; no calibration accuracy inferred.',
            crossVehicleTransferTolerance=None, thermalDutyKnown=False,
            currentObservationTolerancePredeclared=False,
            interpretation='Decimal resolution is not an accuracy bound or historical acceptance tolerance.'),
        validation=dict(runtimeLoadCount=len(loads) + len(heaters),
                        fixedNominalLoadCount=len(loads), heaterCandidateCount=len(heaters),
                        allStableControlIdsValid=True, allSupplyPathsOnDeclaredBus=True,
                        reviewedPrimarySourceHashesVerified=True,
                        noBreakerRatingUsedAsDraw=True, noResidualOrHistoricalFit=True,
                        completeVehicleLoadCoverage=False, independentFlightValidationPassed=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', type=Path, default=ROOT / 'reference/controls.json')
    parser.add_argument('--electrical', type=Path, default=ROOT / 'reference/electrical.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'reference/electrical-flight-loads.json')
    args = parser.parse_args()
    data = build(args.inventory, args.electrical)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(output=str(args.output), **data['validation'])))


if __name__ == '__main__':
    main()
