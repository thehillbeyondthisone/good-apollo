"""Transcribe the source-backed additions to the original LM-7 panel snapshot.

The states below were read from complete AOH pages, not inferred from OCR.
Coordinates and panel dimensions are provisional interaction-study placements.
Run before build-control-inventory.py to regenerate the expansion dataset.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=ROOT/'reference/offpanel-controls.json')
args = parser.parse_args()
CONTROLS = []
PANELS = []


def panel(key, label, width, height, x, y, z, rx, rz, pdf=827, figure='3-2'):
    PANELS.append(dict(id=key, label=label, width_m=width, height_m=height,
        dimensionsProvisional=True, layoutProvisional=True,
        placement=dict(x=x, y=y, z=z, rotateXDeg=rx, rotateZDeg=rz),
        source=dict(document='lm7-aoh-v1', figure=figure, pdfPage=pdf),
        notes='Functional grouping is sourced; dimensions, coordinates and reach are provisional.'))


def add(key, group, label, kind, states, pdf, printed, ref=None, uv=(.5, .5), **extra):
    source = dict(document='lm7-aoh-v1', pdfPage=pdf, printedPage=printed,
                  tablePdfPage=pdf, tablePrintedPage=printed)
    item = dict(id=key, panel=group, label=label, type=kind, positions=states,
        default=states[0], interactive=kind not in ['indicator', 'meter', 'display'],
        layout=dict(u=uv[0], v=uv[1]), source=source,
        confidence='visually_read_detailed_table', provisional=True,
        geometryProvisional=True,
        notes='Control states and function sourced; interaction-study placement and sandbox initial state are not a flown configuration.')
    if ref:
        item['referenceDesignation'] = ref
    item.update(extra)
    CONTROLS.append(item)
    return item


def axis(key, group, label, pdf, printed, ref, uv, physical_axis, low=-1, high=1,
         unit='normalized', momentary=True, **extra):
    states = ['NEGATIVE', 'CENTER', 'POSITIVE'] if momentary else ['MIN', 'MID', 'MAX']
    return add(key, group, label, 'axis', states, pdf, printed, ref, uv,
        default='CENTER' if momentary else 'MIN', momentary=momentary,
        axis=dict(min=low, max=high, unit=unit, axis=physical_axis), **extra)


def guard(key, group, label, protected, pdf, printed, uv, **extra):
    return add(key, group, label, 'guard', ['CLOSED', 'OPEN'], pdf, printed, None, uv,
        protectedControlId=protected,
        notes='Independent mechanical action. CLOSED/OPEN are sandbox status names; source nomenclature and motion are retained in mechanism metadata.', **extra)


# Missing controls on numbered panels. PDF 751, printed 3-81.
add('p5_stop', '5', 'ENGINE STOP', 'pushbutton', ['RELEASED', 'PRESSED'],
    751, '3-81', '1S3', (.28, .88), momentary=False,
    mechanism=dict(latching='push_push', guardId='p5_stop_guard'))
add('p5_des_rate', '5', 'DES RATE', 'toggle', ['+1 FPS', 'CENTER', '-1 FPS'],
    751, '3-81', '1S5', (.04, .82), default='CENTER', momentary=True,
    springReturn=True, mechanism=dict(springReturn=True, returnPosition='CENTER'))
guard('p5_stop_guard', '5', 'ENGINE STOP COVER', 'p5_stop', 827, '3-157/3-158',
    (.28, .97), source=dict(document='lm7-aoh-v1', pdfPage=827, printedPage='3-157/3-158', figure='3-2'),
    confidence='diagram_transcribed', mechanism=dict(action='hinged cover', interlockFidelity='sandbox blocking; geometry from figure'))
guard('p6_stop_guard', '6', 'ENGINE STOP COVER', 'p6_stop', 827, '3-157/3-158',
    (.10, .98), source=dict(document='lm7-aoh-v1', pdfPage=827, printedPage='3-157/3-158', figure='3-2'),
    confidence='diagram_transcribed', mechanism=dict(action='hinged cover', interlockFidelity='sandbox blocking; geometry from figure'))
guard('p8_stage_guard', '8', 'STAGE GUARD', 'p8_stage', 827, '3-157/3-158',
    (.42, .09), source=dict(document='lm7-aoh-v1', pdfPage=827, printedPage='3-157/3-158', figure='3-2'),
    confidence='diagram_transcribed', mechanism=dict(action='hinged guard', interlockFidelity='sandbox blocking; geometry from figure'))

# Instrument power-failure lamps are separate source-index entries, rather than
# hidden states of the compound meter assembly. Placements are diagram-relative
# offsets near the matching instrument, not independently measured coordinates.
_active = {c['id']: c for c in json.loads((ROOT / 'reference/controls.json').read_text(encoding='utf-8-sig'))['controls']}
for key, instrument, label, page, ref in [
    ('p1_x_pointer_power_failure','p1_x_pointer','X-POINTER POWER FAILURE',686,'16DS91'),
    ('p1_thrust_power_failure','p1_thrust','THRUST POWER FAILURE',688,'16DS92'),
    ('p1_press_power_failure','p1_press','PRESS POWER FAILURE',689,'16DS90'),
    ('p2_rcs_press_power_failure','p2_reaction_control_press','RCS PRESS POWER FAILURE',707,'16DS96'),
    ('p2_rcs_quantity_power_failure','p2_reaction_control_quantity','RCS QUANTITY POWER FAILURE',707,'16DS98'),
    ('p2_ecs_press_power_failure','p2_ecs_press','ECS PRESS POWER FAILURE',723,'16DS93'),
    ('p2_ecs_quantity_power_failure','p2_o2_h2o_quantity','ECS QUANTITY POWER FAILURE',724,'16DS94'),
    ('p2_glycol_power_failure','p2_glycol','GLYCOL POWER FAILURE',724,'16DS95'),
    ('p2_x_pointer_power_failure','p2_x_pointer','X-POINTER POWER FAILURE',725,'16DS97'),
]:
    owner = _active[instrument]
    uv=(min(.97,owner['layout']['u']+.042),min(.97,owner['layout']['v']+.028))
    add(key,owner['panel'],label,'indicator',['OFF','ON'],page,f'3-{page-670}',ref,uv,
        outputRole='instrument_power_failure',instrumentId=instrument,color='red',
        notes='Detailed source row: red lamp goes on when power to its instrument is interrupted. Indicator is inventoried separately; downstream equipment-power/failure wiring remains a scoped simulation concern.')

# AOT. Detailed table PDF 819-820, printed 3-149/150.
panel('AOT', 'Alignment optical telescope', .26, .30, 0, .95, 1.94, 90, 0)
axis('aot_eyepiece_adjust', 'AOT', 'EYEPIECE ADJUST', 819, '3-149', '3H3', (.76, .78),
     'focus', 0, 1, momentary=False,
     notes='Moves eyepiece toward/away from observer; normalized travel, physical travel not established.')
for key, name, ref, uv in [('mark_x', 'MARK X', '3S23', (.18, .52)),
                         ('mark_y', 'MARK Y', '3S25', (.82, .52)),
                         ('reject', 'REJECT', '3S24', (.82, .30))]:
    add('aot_' + key, 'AOT', name, 'pushbutton', ['RELEASED', 'PRESSED'], 819,
        '3-149', ref, uv, momentary=True)
axis('aot_reticle_illumination', 'AOT', 'RETICLE ILLUMINATION', 819, '3-149', '3R1',
     (.18, .30), 'brightness', 0, 1, momentary=False)
axis('aot_reticle', 'AOT', 'RETICLE ROTATION', 819, '3-149', '3H1', (.5, .34),
     'reticle', 0, 360, 'degrees', False,
     notes='Reticle rotation is sourced; wrap, gearing and exact control travel remain unvalidated.')
add('aot_azimuth', 'AOT', 'AZIMUTH', 'rotary', ['LR', 'L', 'F', 'R', 'RR', 'CL'],
    819, '3-149/3-150', '3H2', (.5, .75), source=dict(document='lm7-aoh-v1',
        pdfPage=819, pdfPages=[819, 820], printedPage='3-149/3-150', tablePdfPage=819))
add('aot_indicator', 'AOT', 'RETICLE ANGLE', 'display', ['UNPOWERED', 'POWERED'],
    820, '3-150', '3M7', (.5, .12), notes='Five-place reticle angle display; tenths of a degree in rightmost digit. Optical model is not coupled.')

# ORDEAL. PDF 821-823, printed 3-151-153/154. Placards also read on Fig.3-2.
panel('ORDEAL', 'ORDEAL', .31, .15, -1.04, -.28, 1.02, 70, 58)
for n, ref, uv in [(1, '9S23', (.12, .73)), (2, '9S24', (.31, .73))]:
    add(f'ordeal_fdai_{n}', 'ORDEAL', f'FDAI {n}', 'toggle', ['ORB RATE', 'INRTL'],
        821 if n == 1 else 822, '3-151/3-152' if n == 1 else '3-152', ref, uv)
add('ordeal_earth_lunar', 'ORDEAL', 'EARTH-LUNAR', 'toggle', ['EARTH', 'PWR OFF', 'LUNAR'],
    822, '3-152', '9S25', (.51, .73), default='PWR OFF')
axis('ordeal_alt_set', 'ORDEAL', 'ALT SET', 822, '3-152', '9R1', (.81, .51),
    'altitude', 10, 310, 'nautical_miles', False)
add('ordeal_lighting', 'ORDEAL', 'LIGHTING', 'toggle', ['BRT', 'OFF', 'DIM'],
    822, '3-152', '9S26', (.12, .25), default='OFF')
add('ordeal_mode', 'ORDEAL', 'MODE', 'toggle', ['OPR/SLOW', 'HOLD/FAST'],
    823, '3-153/3-154', '9S27', (.31, .25))
add('ordeal_slew', 'ORDEAL', 'SLEW', 'toggle', ['UP', 'CENTER', 'DOWN'],
    823, '3-153/3-154', '9S28', (.51, .25), default='CENTER',
    mechanism=dict(centerPlacardSource='Fig.3-2', springReturnUnconfirmed=True),
    notes='UP and DOWN functions from detailed table; unlabelled neutral position visible in Fig.3-2. Spring-return behavior is not asserted by the inspected table.')

# Both crew hand controllers. Vehicle axes follow the explicit AOH descriptions.
for crew, x, aca_ref, ttca_ref, select_ref, friction_ref, ptt_ref in [
    ('cdr', -.43, '1A1', '1X1', '1H1', '1H3', '15AS10'),
    ('lmp', .70, '1A2', '1X2', '1H2', '1H4', '15BS10')]:
    group = 'ACA_' + crew.upper()
    panel(group, crew.upper() + ' attitude controller', .16, .22, x, .35, .88, 40, 0)
    for name, vehicle_axis, uv in [('YAW', 'LM-X rotation', (.5, .78)),
                                 ('PITCH', 'LM-Y rotation', (.20, .46)),
                                 ('ROLL', 'LM-Z rotation', (.80, .46))]:
        axis(f'aca_{crew}_{name.lower()}', group, name, 820, '3-150', aca_ref, uv, vehicle_axis)
    add(f'aca_{crew}_ptt', group, 'PUSH TO TALK', 'pushbutton', ['RELEASED', 'PRESSED'],
        820, '3-150', ptt_ref, (.5, .16), momentary=True)
    group = 'TTCA_' + crew.upper()
    panel(group, crew.upper() + ' thrust/translation controller', .21, .24,
          x - .25, .35, .88, 40, 0)
    for name, uv in [('X', (.50, .80)), ('Y', (.19, .57)), ('Z', (.81, .57))]:
        axis(f'ttca_{crew}_translation_{name.lower()}', group, 'TRANSLATION ' + name,
             820, '3-150/3-151', ttca_ref, uv, 'LM-' + name + ' translation',
             notes='Three-axis controller. X translation is available with JETS selected; Y and Z translation are available in either lever position. Physical controller stop angles and transfer curve remain unvalidated.')
    add(f'ttca_{crew}_select', group, 'THROTTLE/JETS', 'toggle', ['JETS', 'THROTTLE'],
        821, '3-151', select_ref, (.18, .20))
    axis(f'ttca_{crew}_throttle', group, 'THROTTLE', 820, '3-150/3-151', ttca_ref,
         (.50, .37), 'throttle', 10, 92.5, 'percent_thrust', False,
         notes='Same physical LM-X tee-handle travel as X translation, selected by THROTTLE/JETS. Separate input node exposes both functions for this interaction study; engine coupling is absent.')
    axis(f'ttca_{crew}_friction', group, 'THROTTLE FRICTION', 821, '3-151', friction_ref,
         (.81, .20), 'friction', 0, 1, momentary=False,
         notes='Sourced control varies tee-handle force. The AOH quotes ranges of force, not a unique knob-position transfer; no physical haptic force is simulated.')

# Utility light controls and the separate radar gyro selector.
panel('UTIL', 'Utility lights', .28, .10, 0, .96, 2.02, 90, 0)
for crew, ref, uv in [('cdr', '16S19', (.25, .5)), ('lmp', '16S20', (.75, .5))]:
    add('util_' + crew, 'UTIL', crew.upper() + ' UTILITY LIGHTS', 'rotary',
        ['OFF', 'DIM', 'BRIGHT'], 823, '3-153/3-154', ref, uv)
panel('RR_GYRO', 'Rendezvous radar gyro selector', .07, .13, -.19, .95, 1.93, 90, 0)
add('rr_gyro_sel', 'RR_GYRO', 'RR GYRO SEL', 'toggle', ['PRIM', 'AUTO', 'SEC'],
    823, '3-153/3-154', '17S9', (.5, .5), default='AUTO')

# Aft ECS controls. All named rows on PDF811-818 are represented; multiple
# physical instances are separate IDs. The layout follows functional clusters
# from Fig.3-1 but does not claim measured LM-7 locations.
panel('ECS', 'Aft ECS valves and canisters', .78, .70, .57, -1.03, 1.13, -90, 0, 825, '3-1')
ecs = [
 ('suit_gas_diverter', 'SUIT GAS DIVERTER', ['PUSH-CABIN', 'PULL-EGRESS'], 811, '3-141', '7H8'),
 ('cabin_repress', 'CABIN REPRESS', ['MANUAL', 'AUTO', 'CLOSE'], 811, '3-141', '7H3'),
 ('plss_fill', 'PLSS FILL', ['OPEN', 'CLOSE'], 811, '3-141', '7H4'),
 ('press_reg_a', 'PRESS REG A', ['DIRECT O2', 'CABIN', 'EGRESS', 'CLOSE'], 812, '3-142', '7H1'),
 ('press_reg_b', 'PRESS REG B', ['DIRECT O2', 'CABIN', 'EGRESS', 'CLOSE'], 812, '3-142', '7H2'),
 ('des_o2', 'DES O2', ['OPEN', 'CLOSE'], 812, '3-142', '7H15'),
 ('asc_o2_1', '#1 ASC O2', ['OPEN', 'CLOSE'], 812, '3-142', '7H21'),
 ('asc_o2_2', '#2 ASC O2', ['OPEN', 'CLOSE'], 812, '3-142', '7H5'),
 ('suit_isol_cdr', 'CDR SUIT ISOL', ['SUIT DISC', 'SUIT FLOW', 'ACTUATOR OVRD'], 813, '3-143', '7H6'),
 ('suit_isol_lmp', 'LMP SUIT ISOL', ['SUIT DISC', 'SUIT FLOW', 'ACTUATOR OVRD'], 813, '3-143', '7H7'),
 ('sec_evap_flow', 'SEC EVAP FLOW', ['OPEN', 'CLOSE'], 813, '3-143', '7H18'),
 ('pri_evap_flow_2', 'PRI EVAP FLOW #2', ['OPEN', 'CLOSE'], 813, '3-143', '7H16'),
 ('water_tank_select', 'WATER TANK SELECT', ['DES', 'ASC', 'SEC'], 813, '3-143/3-144', '7H14'),
 ('asc_h2o', 'ASC H2O', ['OPEN', 'CLOSE'], 814, '3-144', '7H13'),
 ('des_h2o', 'DES H2O', ['OPEN', 'CLOSE'], 814, '3-144', '7H26'),
 ('cabin_gas_return', 'CABIN GAS RETURN', ['OPEN', 'AUTO', 'EGRESS'], 815, '3-145', '7H17'),
 ('co2_canister_sel', 'CO2 CANISTER SEL', ['PRIM', 'SEC'], 815, '3-145', '7H19'),
 ('suit_circuit_relief', 'SUIT CIRCUIT RELIEF', ['OPEN', 'AUTO', 'CLOSE'], 816, '3-146', '7H9'),
 ('water_sep_sel', 'WATER SEP SEL', ['PUSH: SEP 1', 'PUSH: SEP 2'], 817, '3-147', '7H10'),
 ('pri_evap_flow_1', 'PRI EVAP FLOW #1', ['OPEN', 'CLOSE'], 818, '3-148', None),
 ('primary_co2_cover', 'PRIMARY CO2 CANISTER', ['CLOSE', 'OPEN'], 816, '3-146', None),
 ('secondary_co2_cover', 'SECONDARY CO2 CANISTER', ['CLOSE', 'OPEN'], 816, '3-146', None),
]
for n, (key, label, states, pdf, printed, ref) in enumerate(ecs):
    col, row = n % 5, n // 5
    item = add('ecs_' + key, 'ECS', label, 'valve', states, pdf, printed, ref,
               (.10 + .20 * col, .90 - .17 * row))
    if key in ['suit_isol_cdr', 'suit_isol_lmp']:
        item.pop('referenceDesignation')
        item['referenceDesignationCandidates'] = ['7H6', '7H7']
        item['notes'] += ' Detailed table lists reference-designation pair 7H6/7H7 without assigning the crew side; per-side designation remains unadjudicated.'
axis('ecs_suit_temp', 'ECS', 'SUIT TEMP', 815, '3-145', '7H22', (.5, .06),
     'temperature_valve', 0, 1, momentary=False,
     notes='Continuous modulating faucet: DECR COLD to INCR HOT. Normalized travel; no ECS heat-flow coupling.')
axis('ecs_liquid_garment_cooling', 'ECS', 'LIQUID GARMENT COOLING', 818, '3-148', None,
     (.70, .06), 'temperature_valve', 0, 1, momentary=False,
     notes='Control endpoints COLD and HOT; normalized travel without thermal coupling.')
for which, ref, uv in [('primary', '7H23', (.12, .06)), ('secondary', '7H24', (.30, .06))]:
    add('ecs_' + which + '_co2_vent', 'ECS', which.upper() + ' CO2 CANISTER VENT',
        'pushbutton', ['RELEASED', 'PRESSED'], 816, '3-146', ref, uv, momentary=True)
guard('ecs_water_tank_safety_trigger', 'ECS', 'WATER TANK SAFETY TRIGGER',
    'ecs_water_tank_select', 814, '3-144', (.5, .48),
    mechanism=dict(action='lift safety trigger before selecting SEC'))

# Cabin hatches and relief/dump levers are separate mechanisms. The physical
# pressure constraint is recorded; this interaction-only scope has no pressure
# simulation and must never claim a validated pressure interlock.
for which, group, x, y, z, rx, valve_ref, hatch_pdf, hatch_printed, figure in [
    ('forward', 'HATCH_FWD', 0, 1.065, .44, 90, '7H11', 25, '1-9/1-10', '1-8'),
    ('overhead', 'HATCH_OVHD', 0, -.15, 2.055, 180, '7H20', 29, '1-13/1-14', '1-12')]:
    panel(group, which.title() + ' hatch controls', .50, .34, x, y, z, rx, 0,
          hatch_pdf + 1, figure)
    latch = 'hatch_' + which + '_latch'
    door = 'hatch_' + which + '_door'
    add(latch, group, 'HATCH LATCH', 'rotary', ['LATCHED', 'UNLATCHED'], hatch_pdf,
        hatch_printed, None, (.15, .65),
        mechanism=dict(action='cam latch' if which == 'forward' else '90 degree interior turn counterclockwise to open',
            requiredCabinCondition='depressurized', pressureInterlockImplemented=False))
    add(door, group, 'HATCH DOOR', 'rotary', ['CLOSED', 'OPEN'], hatch_pdf + 1,
        hatch_printed, None, (.5, .55),
        mechanism=dict(action='inward swing', requiredControlPosition=dict(id=latch, position='UNLATCHED'),
            requiredCabinCondition='depressurized', pressureInterlockImplemented=False),
        notes='Mechanical swing is an interaction study. No cabin-pressure force or pressure interlock is simulated.')
    add('hatch_' + which + '_relief_dump', group, 'CABIN RELIEF AND DUMP', 'valve',
        ['DUMP', 'AUTO', 'CLOSE'], 817, '3-147/3-148', None, (.81, .65),
        referenceDesignationCandidates=['7H11', '7H20'],
        default='AUTO', mechanism=dict(guardId='hatch_' + which + '_relief_trigger'),
        source=dict(document='lm7-aoh-v1', pdfPage=817, pdfPages=[817, 818], printedPage='3-147/3-148',
                    tablePdfPage=817, figure=figure))
    guard('hatch_' + which + '_relief_trigger', group, 'RELIEF VALVE UNLOCK TRIGGER',
        'hatch_' + which + '_relief_dump', 817, '3-147', (.81, .35),
        momentary=True, mechanism=dict(action='squeeze release trigger; spring release on hand release'))
    add('hatch_' + which + '_external_dump', group, 'EXTERNAL PULL TO DUMP', 'toggle',
        ['IN', 'OUT'], 817, '3-147', None, (.5, .15), momentary=True,
        referenceDesignationCandidates=['7H11', '7H20'],
        springReturn=True, mechanism=dict(returnPosition='IN', outsideCabin=True),
        notes='Exterior-side lever inventoried separately. Proxy is shown on the hatch study surface for inspection; not physically reachable from the pressurized cabin.')
add('hatch_forward_emergency_lockpin', 'HATCH_FWD', 'EMERGENCY RELEASE LOCKPIN',
    'toggle', ['INSERTED', 'WITHDRAWN'], 25, '1-9/1-10', None, (.15, .20),
    mechanism=dict(action='withdraw lockpin to release cam latch in emergency'),
    source=dict(document='lm7-aoh-v1', pdfPage=25, pdfPages=[25, 26], printedPage='1-9/1-10', figure='1-8'))

# Cabin support/portable mechanisms: the follow-up ledger identifies 15 manual
# functions and 20 object/retention-state abstractions, not 35 new panel switches.
# Keep software states distinct from spacecraft placards and unknown linkages.
FOLLOWUP_PATH = ROOT/'reference/cabin-mechanism-followup.json'
FOLLOWUP = json.loads(FOLLOWUP_PATH.read_text(encoding='utf-8'))
MECHANISM_GROUPS = {g['id']: g for g in FOLLOWUP['mechanismGroups']}
MECHANISM_LAYOUT = json.loads((ROOT/'assets/mechanism-layout.json').read_text(encoding='utf-8'))['controls']
logical_groups = [
    ('WINDOWS', 'Window shades', .42, .28, 0, .98, 1.60, 90, 0),
    ('CREW_CDR', 'Commander support and restraint', .32, .40, -.74, .08, .78, 60, 35),
    ('CREW_LMP', 'Pilot support and restraint', .32, .40, .74, .08, .78, 60, -35),
    ('COAS', 'Crewman optical alignment sight', .30, .28, -.72, .96, 1.60, 90, 0),
    ('CABIN_LIGHTS', 'Portable lights and flood reflectors', .55, .24, 0, .78, 1.98, 180, 0),
    ('CREW_TOOLS', 'Water dispenser and emergency tool', .36, .30, .98, -.65, .80, 90, -90),
    ('TUNNEL', 'LM docking drogue', .44, .26, 0, -.45, 1.90, 180, 0),
]
for group_id, label, width, height, x, y, z, rx, rz in logical_groups:
    panel(group_id, label, width, height, x, y, z, rx, rz, 664, '2.11-16')
    PANELS[-1].update(renderPanel=False, renderPlacards=False,
        notes='Logical assembly group only. Object anchors and display-proxy articulation are in assets/mechanism-layout.json; no panel board or invented spacecraft placards.')

candidate_rows = [(c, 'manual_cabin_input') for c in FOLLOWUP['implementationCandidates']['cabinInputs']]
candidate_rows += [(c, 'movable_object_state') for c in FOLLOWUP['implementationCandidates']['movableObjectAndRetentionStates']]
candidate_ids = [c['candidateId'] for c, _ in candidate_rows]
assert len(candidate_rows) == 35 and len(set(candidate_ids)) == 35
group_counters = collections.Counter()
for candidate, role in candidate_rows:
    ident = candidate['candidateId']
    family = candidate['group']
    evidence_group = MECHANISM_GROUPS[family]
    if ident.startswith('shade_'): group = 'WINDOWS'
    elif ident.startswith('coas_'): group = 'COAS'
    elif ident.startswith('utility_') or ident.startswith('flood_overhead_'): group = 'CABIN_LIGHTS'
    elif ident.startswith('water_dispenser_') or ident.startswith('tool_b_'): group = 'CREW_TOOLS'
    elif ident.startswith('drogue_'): group = 'TUNNEL'
    elif ident.startswith('hatch_forward_'): group = 'HATCH_FWD'
    else: group = 'CREW_CDR' if '_cdr' in ident else 'CREW_LMP'
    slot = group_counters[group]; group_counters[group] += 1
    uv = (.14 + .24 * (slot % 4), .82 - .28 * (slot // 4))
    evidence = [dict(document='lm7-aoh-v1', **entry) for entry in evidence_group['evidence']]
    primary = evidence[0]
    assembly_proxy = candidate['kind'] in ['assembly_proxy', 'maintenance_assembly_proxy']
    category = 'candidate_assembly_proxy' if assembly_proxy else (
        'visual_figure' if candidate['kind'] in ['ptt_switch', 'mount_lock', 'snap_on_filter', 'portable_pose', 'electrical_connector', 'clamp', 'fabric_object']
        else 'visual_functional_description')
    source = dict(document='lm7-aoh-v1', pdfPage=primary['pdfPage'], printedPage=primary['printedPage'],
        detailAudit=category, mechanismGroup=family, ledger='reference/cabin-mechanism-followup.json',
        candidateId=ident)
    states = candidate.get('states', ['MIN', 'MID', 'MAX'])
    kind = 'axis' if candidate['kind'] in ['continuous_knob', 'reflector_rotation'] else (
        'pushbutton' if candidate['kind'] in ['ptt_switch', 'trigger'] else 'mechanism')
    default = 'ADJUST_2' if candidate['kind'] == 'detented_armrest' else states[0]
    if ident in ['coas_barrel_lock', 'tool_b_head_lock']: default = 'SECURED'
    if ident == 'coas_filter': default = 'REMOVED'
    physical_instance_known = not assembly_proxy and candidate['kind'] != 'adjustment_pin'
    mechanism = dict(kind=candidate['kind'], namedActuatorId=ident+'__actuator',
        assemblyProxy=assembly_proxy, individualActuatorCountEstablished=physical_instance_known,
        physicalTravelEstablished=False, articulation=dict(proxy=True,
            layoutReference='assets/mechanism-layout.json#'+ident,
            kind=MECHANISM_LAYOUT[ident].get('motion', {}).get('kind', 'button_travel'),
            qualification='Display motion is a prototype proxy; not recovered mechanical dimensions or stops.'),
        sourceRelationship=candidate['relationship'], geometryNotEstablished=evidence_group.get('notEstablished', []))
    item = add(ident, group, ident.replace('_', ' ').upper(), kind, states, primary['pdfPage'],
        primary['printedPage'], None, uv, source=source, sourceEvidence=evidence,
        confidence=category, default=default, momentary=kind=='pushbutton', mechanism=mechanism,
        inventoryRole=role, mechanismGroup=family, stateLabelsArePlacards=False,
        renderPlacards=False, countingUnit='functional operation or object state; not an additional numbered-panel switch',
        softwareStateAbstraction=role=='movable_object_state' or candidate['kind'] in ['reflector_rotation', 'ptt_switch'],
        notes=candidate['relationship']+' State names are software inspection labels, not recovered placards. Physical placement and motion are explicit prototype proxies.')
    if kind == 'axis':
        item['axis'] = dict(min=0, max=1, unit='normalized_software_travel',
            axis='brightness' if candidate['kind']=='continuous_knob' else 'reflector_aim', physicalRangeKnown=False)
    if candidate['kind'] == 'detented_armrest':
        item['detentRelease'] = dict(gesture='grip', exceptFromPositions=['STOWED_UP'],
            basis='source_functional_description', explanation='Downward force leaves stow; latch release selects other detented positions. No separate button count is inferred.')
        item['mechanism']['wrap'] = False
    if candidate['kind'] == 'ratchet_lock':
        item['mechanism'].update(payoutAllowedPositions=['UNLOCKED'], reelingInAllowedPositions=['UNLOCKED','LOCKED'],
            forceModelImplemented=False, sourcedApproximateDownwardForceLbf=30)
    if assembly_proxy:
        item['softwareStateAbstraction'] = True
        item['mechanism']['individualActuatorCountEstablished'] = False
        item['mechanism']['doNotInferIndividualPinOrHandleCount'] = True
    if 'dimensions' in evidence_group: item['sourcedAssemblyDimensions'] = evidence_group['dimensions']

followup_controls = {c['id']: c for c in CONTROLS if c['id'] in candidate_ids}
def require(control_id, positions, basis, applies=None):
    rule = dict(controlId=control_id, allowedPositions=positions, basis=basis)
    if applies: rule['appliesToPositions'] = applies
    return rule
followup_controls['coas_mount']['motionRequires'] = [require('coas_barrel_lock', ['RELEASED'], 'declared_mechanical_inference')]
for component in ['coas_illumination', 'coas_barrel_lock', 'coas_cap', 'coas_filter']:
    followup_controls[component]['parentAssemblyId'] = 'coas_mount'
coas = followup_controls['coas_illumination']
coas['powerSelectorId'] = 'p8_coas'
coas['powerSelectorMap'] = dict(LEFT_WINDOW='FWD', DOCKING_WINDOW='OVHD')
coas['emissionRequires'] = [dict(breakerId='p11_cb_r02_c15', basis='source_circuit'),
    require('coas_cap', ['REMOVED'], 'source_use_procedure'),
    require('coas_mount', ['LEFT_WINDOW','DOCKING_WINDOW'], 'source_mount_positions'),
    require('p8_coas', ['FWD','OVHD'], 'source_power_selection')]
coas['emissionRelationship'] = 'Reticle requires power selector corresponding to mount, removed cap and nonzero intensity; shades obscure external view, not electrical reticle emission.'
coas['viewObscurationMap'] = dict(LEFT_WINDOW='shade_cdr', DOCKING_WINDOW='shade_docking')
for crew in ['cdr', 'lmp']:
    lamp = followup_controls[f'utility_{crew}_lamp']
    clamp_id = f'utility_{crew}_clamp'
    lamp['motionRequires'] = [require(clamp_id, ['RELEASED'], 'declared_mechanical_inference', ['STOWED','FREE']),
        require(clamp_id, ['SECURED'], 'software_definition_of_clamped_state', ['CLAMPED'])]
    lamp['powerSelectorId'] = f'util_{crew}'
    lamp['emissionRequires'] = [dict(breakerId='p11_cb_r03_c18', basis='source_circuit'),
        require(f'utility_{crew}_plug', ['CONNECTED'], 'source_electrical_connection'),
        require(f'util_{crew}', ['DIM','BRIGHT'], 'source_selector_states')]
    followup_controls[clamp_id]['parentAssemblyId'] = f'utility_{crew}_lamp'
    reflector = followup_controls[f'flood_overhead_{crew}_aim']
    reflector['powerSelectorId'] = 'p3_flood_ovhd_fwd'
    reflector['emissionRequires'] = [dict(breakerId='p16_cb_r02_c01', basis='source_circuit'),
        require('p3_flood_ovhd_fwd', ['OVHD/FWD','ALL'], 'source_lighting_route')]
    reflector['dimmerId'] = 'p5_flood_ovhd_fwd'
    ptt = followup_controls[f'umbilical_{crew}_ptt']
    ptt['commandAliasId'] = f'aca_{crew}_ptt'
    ptt['commandAliasBasis'] = 'Functional PTT interpretation; electrical contact wiring and flight communications not yet simulated.'
    ptt['crewRole'] = crew
followup_controls['water_dispenser_trigger']['parentAssemblyId'] = 'water_dispenser_pose'
followup_controls['water_dispenser_cap']['parentAssemblyId'] = 'water_dispenser_pose'
followup_controls['water_dispenser_trigger']['flowRequires'] = [
    require('water_dispenser_cap', ['REMOVED'], 'source_use_procedure_not_mechanical_trigger_lock'),
    dict(anyOf=[require('ecs_des_h2o', ['OPEN'], 'source_feed_path'),
                require('ecs_asc_h2o', ['OPEN'], 'source_feed_path')], basis='source_alternative_water_feeds')]
followup_controls['water_dispenser_trigger']['flowModel'] = 'Logical availability only; no flow rate, pressure, temperature or consumable depletion is claimed.'
followup_controls['drogue_pose']['motionRequires'] = [require('drogue_retention', ['RELEASED'], 'source_release_before_removal')]
followup_controls['drogue_retention']['motionRequires'] = [require('drogue_pose', ['IN_TUNNEL'], 'software_retained_mount_consistency', ['SECURED'])]
followup_controls['drogue_retention']['parentAssemblyId'] = 'drogue_pose'
followup_controls['hatch_forward_hinge_pin_set']['mechanism']['permitsFutureHatchRemoval'] = True
followup_controls['hatch_forward_hinge_pin_set']['notes'] += ' Existing door remains CLOSED/OPEN; detached-door removal awaits a sourced linkage implementation.'
followup_controls['hatch_forward_antibacterial_filter']['parentAssemblyId'] = 'hatch_forward_door'

# Selected Apollo 13 as-launched identities corroborate assembly counts. They do
# not certify generic handbook pose/closure geometry or in-flight arrangement.
mission_evidence = {
    'portable_utility_lights':dict(pdfPage=56, printedPage='52', item='O3006'),
    'water_dispenser':dict(pdfPage=49, printedPage='45', item='B1010'),
    'emergency_tool_b':dict(pdfPage=49, printedPage='45', item='B1011'),
    'hammocks':dict(pdfPage=58, printedPage='54', items=['O3049','O3050']),
}
for item in followup_controls.values():
    if item['mechanismGroup'] in mission_evidence:
        item['sourceEvidence'].append(dict(document='as13-stowage-final', **mission_evidence[item['mechanismGroup']]))
    item['placementSourceQualification'] = 'Handbook group location plus prototype display anchors; exact LM-7 object coordinates not established.'

PATCHES = {
    'p6_stop': dict(momentary=False, mechanism=dict(latching='push_push', guardId='p6_stop_guard'),
                    source=dict(tablePdfPage=757, tablePrintedPage='3-87'), referenceDesignation='1S4'),
    'p8_stage': dict(mechanism=dict(guardId='p8_stage_guard', leverLock=True, springReturn=True, returnPosition='SAFE'),
                     momentary=True),
    'ecs_water_tank_select': dict(mechanism=dict(guardId='ecs_water_tank_safety_trigger', guardedPositions=['SEC']),
        source=dict(pdfPage=813, pdfPages=[813, 814], printedPage='3-143/3-144', tablePdfPage=813)),
}

OUTPUT = dict(schemaVersion=1, title='LM-7 source-audited off-panel and missing-panel additions',
    sourceDocument='D:/apollo-ref/lm-systems/a13-lm-aoh-v1-lm7-subs-300ppi.pdf',
    reviewedPdfPages=[24, 25, 26, 29, 30, 686, 688, 689, 707, 723, 724, 725, 751, 757, 762] + list(range(811, 824)) + [825, 827],
    sourceMethod='Complete rendered pages visually read; detailed-table states and figure geometry retained separately.',
    geometryStatus='Provisional normalized layouts and dimensions; all additions need physical headset reach/readability testing.',
    completeVehicleDenominatorKnown=False,
    limitations=[
        'Source tables establish the listed control functions; they do not establish measured cabin coordinates.',
        'Controller axes are independent inspectable input nodes; the real shared TTCA handle and cross-axis coupling remain a presentation simplification.',
        'Exact controller stop angles, nonlinear response, friction force, and optical transfer functions remain unvalidated.',
        'Hatch pressure forces, emergency separation, and ECS fluid/thermal behavior are not simulated.',
        'Protective STOP covers and STAGE guard are visually transcribed; their blocking interaction is a declared sandbox rule.',
        'Complete instrument sub-elements, window shades, stowage latches, and utility light aiming have not been fully inventoried.',
    ], panels=PANELS, controls=CONTROLS, patches=PATCHES,
    cabinMechanismImplementation=dict(candidateSource='reference/cabin-mechanism-followup.json',
        candidateIds=candidate_ids, manualCabinInputs=15, movableObjectStates=20,
        implementedCandidateCount=35, wholeVehicleDenominatorEstablished=False,
        note='All listed candidate functions have definitions; assembly proxies and object-state abstractions do not establish unknown physical actuator counts.'),
    supplementarySources=[dict(id='as13-stowage-final', title=FOLLOWUP['sources']['as13_stowage']['title'],
        url=FOLLOWUP['sources']['as13_stowage']['url'],path=FOLLOWUP['sources']['as13_stowage']['localReviewCopy'],
        coverDate=FOLLOWUP['sources']['as13_stowage']['coverDate'])])
output = args.output
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(OUTPUT, indent=2) + '\n', encoding='utf-8')
print(json.dumps(dict(entries=len(CONTROLS), interactive=sum(c['interactive'] for c in CONTROLS),
    groups=len(PANELS), perPanel=dict(collections.Counter(c['panel'] for c in CONTROLS)),
    sha256=hashlib.sha256(output.read_bytes()).hexdigest()), indent=2))
