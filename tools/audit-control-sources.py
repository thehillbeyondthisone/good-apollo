"""Reproduce reviewed AOH control corrections and the explicit audit denominator.

This is a human transcription ledger, not an OCR completeness certificate.
Run after build-control-inventory.py to refresh the inventory-dependent report.
"""
from pathlib import Path
import argparse
import collections
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
PATCHES = {}
VISUAL_PAGES = {22, 24, 25, 26, 691, 692, 694, 695, 696, 697, 698, 699,
                708, 720, 729, 734, 735, 737, 738, 739, 740, 751, 752, 753,
                757, 759, 760, 761, 762, 787, 788, 790, 791, 795}
VISUAL_PAGES.update(range(767, 779))
VISUAL_PAGES.update(range(801, 811))
VISUAL_PAGES.update([745,746,747,748,749,758])
VISUAL_PAGES.update([683,684,685,686,687,688,689,703,704,705,706,707,
                     723,724,725,763,764,765,766,779,780,781,782,783,784,785,786,789])
VISUAL_PAGES.update([690,693,698,699,700,701,726,727,728,730,731,732,733,
                     736,741,742,743,754,755,792,793,794,796,797,798,799])
VISUAL_PAGES.update(range(708,723))


def add(cid, designation, page, visual=False, **patch):
    row = PATCHES.setdefault(cid, {})
    row.update(patch)
    row['referenceDesignation'] = designation
    row['source'] = dict(tablePdfPage=page, tablePrintedPage=f'3-{page - 670}',
                         table='Controls and Displays',
                         detailAudit='visual_table' if visual else 'index_or_table_ocr_link')
    row['confidence'] = 'diagram_and_table_crosschecked' if visual else 'diagram_with_detailed_source_link'


# Table 3-1 points to the detailed rows. A link alone does not certify states.
index_links = {
 'p1_x_pointer_scale': ('9S17',687), 'p1_rate_err_mon':('9S2',689),
 'p1_attitude_mon':('9S3',690), 'p1_mode_sel':('9S9',692),
 'p1_rng_alt_mon':('9S4',692), 'p1_shft_trun':('9S8',693),
 'p1_rate_scale':('9S29',693), 'p1_aca_prop':('1S25',688),
 'p1_att_transl':('1S6',695), 'p1_bal_cpl':('1S9',695),
 'p1_prplnt_qty_mon':('10S8',699), 'p1_prplnt_temp_press_mon':('10S1',700),
 'p1_helium_mon':('10S6',700), 'p1_master_alarm':('6S2',689),
 'p1_mission_timer':('9M12',686), 'p1_event_timer':('9M11',686),
 'p1_oxidizer_quantity':('10M5A',688), 'p1_fuel_quantity':('10M5B',688),
 'p1_helium':('10M1',688), 'p1_x_pointer':('9M2',686),
 'p1_thrust':('9M7',687), 'p1_temp':('10M4',689), 'p1_press':('10M3',689),
 'p1_fdai':('9M1',690), 'p1_range_alt':('9M9',691),
 'p1_range_rate_alt_rate':('9M9',691), 'p1_t_w':('9M4',691),
 'p1_lunar_contact':('1DS1',686),
 'p2_aca_prop':('1S26',722), 'p2_temp_press_mon':('8S19',720),
 'p2_rate_err_mon':('9S7',726), 'p2_attitude_mon':('9S10',726),
 'p2_glycol_selector':('7S3',727), 'p2_glycol_component_caution':('7DS3',727),
 'p2_suit_fan':('7S1',727), 'p2_suit_fan_component_caution':('7DS1',727),
 'p2_o2_h2o_qty_mon':('7S2',728), 'p2_co2_component_caution':('7DS6',728),
 'p2_h2o_sep_component_caution':('7DS7',728), 'p2_master_alarm':('6S3',723),
 'p2_part_press_co2':('7M1',723), 'p2_fdai':('9M6',725), 'p2_x_pointer':('9M3',725),
 'p3_radar_test':('17S6',730), 'p3_test_monitor':('17S8',730),
 'p3_slew_rate':('17S2',731), 'p3_slew':('17S1',732),
 'p3_rendezvous_radar':('17S3',732), 'p3_radar_signal_strength':('17M1',730),
 'p3_rendezvous_radar_no_track':('17DS1',730), 'p3_dead_band':('11S8',733),
 'p3_gyro_test_axis':('11S7',733), 'p3_gyro_test_rate':('11S1',733),
 'p3_pgns_mode_control':('11S24',735), 'p3_ags_mode_control':('11S25',736),
 'p3_imu_cage':('3S1',738), 'p3_htr_cont_temp':('18M1',738),
 'p3_temp_monitor':('18S10',738), 'p3_event_timer_cont':('9S12',739),
 'p3_side_panels':('16S9',741), 'p3_flood_ovhd_fwd':('16S8',741),
 'p3_flood_ovhd_fwd_brightness':('16R4',741), 'p3_lamp_tone_test':('16S10',741),
 'p3_exterior_ltg':('16S17',742), 'p3_x_pointer_scale':('9S18',743),
 'p3_lunar_contact':('1DS2',742),
 'p5_x_transl':('1S12',751), 'p5_mission_timer_cont':('9S19',751),
 'p5_anun_override':('16S4',753), 'p5_num_override':('16S5',753),
 'p5_integral_override':('16S3',754), 'p5_side_panels':('16S1',754),
 'p5_flood_ovhd_fwd':('16R1',754), 'p5_anun_num':('16R2',755),
 'p5_integral':('16R3',755),
 'p6_ags_status':('12S17',757), 'p6_deda_address':('12M1',757),
 'p6_deda_data':('12M2',757), 'p6_deda_opr_err':('12DS1',757),
 'p8_stage_seq_relays_sys_a':('2DS1',762), 'p8_stage_seq_relays_sys_b':('2DS2',763),
 'p8_stage_relay':('2S8',763),
 'p12_updata_link':('13S16',779), 'p12_modulate':('13S5',782),
 'p12_s_band_xmtr_rcvr':('13S3',782), 'p12_pwr_ampl':('13S2',782),
 'p12_functions_voice':('13S6',783), 'p12_functions_pcm':('13S1',783),
 'p12_functions_range':('13S4',784), 'p12_vhf_a_xmtr':('13S7',784),
 'p12_vhf_a_rcvr':('13S10',784), 'p12_vhf_b_xmtr':('13S12',785),
 'p12_vhf_b_rcvr':('13S15',785), 'p12_telemetry_biomed':('13S9',785),
 'p12_telemetry_pcm':('13S13',786), 'p12_recorder':('13S11',786),
 'p12_track_mode':('14S3',786), 'p12_recorder_tape_talkback':('13FL1',786),
 'p12_pitch':('14M3',787), 'p12_yaw':('14M4',787),
 'p12_signal_strength':('14M1',787),
 'p14_volts':('4M2',789), 'p14_amps':('4M3',789),
 'p14_bat_fault':('4DS1',789), 'p14_ed_volts':('4S17',789),
 'p14_inverter':('4S14',790), 'p14_power_temp_mon':('4S15',789),
}
for cid, (ref, page) in index_links.items():
    add(cid, ref, page, page in VISUAL_PAGES)

# Correct neutral positions and physical mechanism behavior from complete rows.
for cid, ref, page in [
 ('p1_ascent_he_reg_1','10S3',696), ('p1_ascent_he_reg_2','10S4',696),
 ('p1_descent_he_reg_1','10S5',697), ('p1_descent_he_reg_2','10S7',698)]:
    add(cid, ref, page, True, positions=['OPEN','CENTER','CLOSE'], default='CENTER',
        mechanism=dict(springReturn=True),
        notes='AOH table: spring-loaded to center. Center removes coil excitation; the valve retains its last command. Sandbox default, not flown configuration.')
for cid, ref, page in [('p1_guid_cont','9S6',691),('p1_eng_arm','1S1',695)]:
    add(cid, ref, page, True, mechanism=dict(leverLock=True),
        notes='AOH describes a center (lock) handle position. Electrical detents remain as declared; unlocking is separate from selection, not an invented electrical OFF reset.')
for cid, ref, page in [('p1_throt_cont','1S11',694), ('p1_man_throt','1S10',694)]:
    add(cid, ref, page, True)
for cid, ref, page in [('p1_abort','1S13',698),('p1_abort_stage','1S14',699),
                       ('p5_stop','1S3',751),('p6_stop','1S4',757)]:
    add(cid, ref, page, True, momentary=False, latched=True,
        notes='AOH: pushbutton remains pressed and resets when pressed a second time. Mechanical latch only; downstream subsystem behavior remains separately scoped.')
add('p5_start','1S2',751,True,momentary=False,latched=True,
    mechanism=dict(resetBy=['p5_stop','p6_stop']),
    notes='AOH: START remains pressed/illuminated; either engine STOP interrupts override and extinguishes START. Downstream engine coupling is not implemented.')

# All RCS command switches have a neutral coil-off center, distinct from valve state.
for system, basepage in [('a',708),('b',714)]:
    for feed, offset, ref in [(1,0,'8S8' if system=='a' else '8S10'),
                               (2,1,'8S22' if system=='a' else '8S23')]:
        cid=f'p2_system_{system}_asc_feed_{feed}'
        add(cid,ref,basepage+offset,basepage+offset in VISUAL_PAGES,
            positions=[f'ASC FEED {feed}','CENTER','CLOSE'],default='CENTER',
            mechanism=dict(springReturn=True,leverLock=True),
            notes='Table gives ASC FEED/CENTER/CLOSE; center removes solenoid excitation and leaves valves in last commanded state.')
    refs={'a':['8S11','8S12','8S15','8S16'],'b':['8S13','8S14','8S17','8S18']}[system]
    for quad,ref in enumerate(refs,1):
        add(f'p2_system_{system}_quad_{quad}_thruster_pair',ref,basepage+1+quad,False,
            positions=['OPEN','CENTER','CLOSE'],default='CENTER',
            mechanism=dict(springReturn=True,leverLock=True))
for cid,ref,page in [('p2_crsfd','8S20',720),('p2_main_sov_sys_a','8S7',721),('p2_main_sov_sys_b','8S9',722)]:
    add(cid,ref,page,page in VISUAL_PAGES,positions=['OPEN','CENTER','CLOSE'],
        default='CENTER',mechanism=dict(springReturn=True,leverLock=True))
add('p3_event_timer_reset_count','9S11',739,True,positions=['RESET','UP','DOWN'],default='UP')
for cid,ref,page in [('p3_event_timer_slew_cont_min','9S13',739),
                      ('p3_event_timer_slew_cont_sec','9S14',740),
                      ('p5_mission_timer_slew_cont_hours','9S22',752),
                      ('p5_mission_timer_slew_cont_min','9S21',752),
                      ('p5_mission_timer_slew_cont_sec','9S20',753)]:
    add(cid,ref,page,True,positions=['TENS','CENTER','UNITS'],default='CENTER',
        mechanism=dict(springReturn=True),
        notes='AOH: center disables slewing; TENS/UNITS operate only while held. Sandbox released default CENTER.')
for axis,ref in [('roll','11S4'),('pitch','11S3'),('yaw','11S5')]:
    add(f'p3_{axis}_mode_cont',ref,734,True)
for quad in range(1,5):
    add(f'p3_rcs_sys_a_b_2_quad_{quad}',f'11S{quad+3}',740,True)

for cid,ref in [('p8_des_propulsion_fuel_vent','10S9'),('p8_des_propulsion_oxid_vent','10S10')]:
    add(cid,ref,759,True,positions=['OPEN','CENTER','CLOSE'],default='CENTER',
        notes='AOH: center retains valve position. This table does not explicitly specify spring return, so no spring-return claim is added.')
for cid,ref,page in [('p8_des_prplnt_isol_vlv','2S9',760),('p8_des_vent','2S6',760),
                      ('p8_ldg_gear_deploy','2S10',761),('p8_he_press_rcs','2S2',761),
                      ('p8_he_press_des_start','2S1',762),('p8_he_press_ascent','2S4',762),
                      ('p8_stage','2S5',762)]:
    add(cid,ref,page,True,mechanism=dict(springReturn=True,leverLock=True),default='SAFE',
        notes='AOH: switch locked in and spring-loaded to SAFE. FIRE is a held command, not a latched flight state.')
add('p8_master_arm','2S7',760,True,mechanism=dict(leverLock=True))
add('p8_asc_he_sel','2S3',761,True,mechanism=dict(leverLock=True))

# Correct command knob ranges. These differ from antenna/indicator travel limits.
for cid,ref,lo,hi,states in [
 ('p12_antenna_pitch','14B2',-75,225,['-75','0','90','225']),
 ('p12_antenna_yaw','14B1',-90,90,['-90','0','90'])]:
    add(cid,ref,787,True,positions=states,default='0',
        analog=dict(min=lo,max=hi,unit='deg',step=1,default=0),
        notes='Source-backed command-knob range, distinct from antenna mechanical/indicator limits. Clockwise approach specified by handbook. Sampled positions retained for compatible discrete interface; analog metadata states continuous domain.')
add('p12_antenna_vhf','14S6',787,True,mechanism=dict(leverLock=True),
    notes='Selector must be pulled out before rotation. Detailed table lists AFT/FWD/EVA; figure also depicts PLSS TEST. Revision/state discrepancy remains open; no unsupported state silently removed.')
add('p12_antenna_s_band','14S5',788,True,mechanism=dict(leverLock=True))

for battery in range(1,5):
    owner='se' if battery<3 else 'cdr'
    high_page={1:791,2:792,3:793,4:794}[battery]
    low_page={1:791,2:792,3:794,4:795}[battery]
    for tap,page,refnum in [('hi',high_page,battery),('low',low_page,battery+4)]:
        add(f'p14_{owner}_bat_{battery}_{tap}_voltage',f'4S{refnum}',page,page in VISUAL_PAGES,
            positions=['OFF/RESET','CENTER','ON'],default='CENTER',
            notes='AOH table includes CENTER: retain status of last initiated command. Handle position must not be conflated with latched ECA contactor state.')
    add(f'p14_{owner}_bat_{battery}_talkback',f'4FL{battery}',{1:792,2:793,3:794,4:795}[battery],battery==4,
        positions=['BARBER_POLE','GRAY','GRAY/LO'])
add('p14_des_bats','4S9',795,True,positions=['DEAD FACE','CENTER','CONNECT'],default='CENTER',
    mechanism=dict(springReturn=True,leverLock=True),
    notes='AOH: lever locked to center; momentary command sets latching relays. CENTER retains last command. DEADFACE source spelling normalized to existing DEAD FACE ID interface.')
for cid,ref,page in [('p14_bat_5_normal_se_feed','4S10',796),
                      ('p14_bat_5_back_up_cdr_feed','4S12',797),
                      ('p14_bat_6_normal_cdr_feed','4S11',798),
                      ('p14_bat_6_back_up_se_feed','4S13',798)]:
    add(cid,ref,page,False,positions=['OFF/RESET','CENTER','ON'],default='CENTER',
        mechanism=dict(springReturn=True),
        notes='AOH: spring-loaded CENTER retains latched ECA state; ON/OFF-RESET are momentary coil commands.')
add('p14_uplink_squelch','13S17',799,False,positions=['ENABLE','DISABLE'],default='DISABLE')

# Full visual row-by-row transcription of all 160 breaker entries. The table
# ratings are retained as evidence, independently of existing schematic ratings.
# Each token is reference-designation suffix : PDF page : table amperes.
CB_ROWS = {
 (11,1): '152:767:2 169:767:2 34:767:2 226:767:2 203:767:2 214:767:2 210:767:2 200:767:2 186:767:5 185:768:5 24:768:5 23:768:5 27:768:2 144:768:2 202:768:2 212:768:2 206:768:2 207:768:2 211:768:2',
 (11,2): '72:769:5 60:769:10 61:769:10 62:769:10 63:769:10 67:770:5 231:770:5 51:770:5 168:770:2 159:770:2 133:770:2 123:770:2 88:771:2 97:771:2 188:771:2 227:771:2 204:769:2 201:769:2 209:769:2',
 (11,3): '74:771:5 156:771:5 155:771:7.5 157:772:5 129:772:2 213:772:2 131:772:3 238:772:10 3:772:2 81:772:2 40:772:7.5 80:773:2 59:773:10 106:773:2 69:773:20 149:773:2 76:774:2 236:774:2 146:774:2',
 (11,4): '221:774:7.5 220:774:7.5 219:774:7.5 218:774:7.5 138:774:20 107:775:5 141:775:5 117:775:5 217:775:2 228:775:2 137:775:5 136:775:5 162:775:5 87:776:2 86:776:2 154:776:2 105:776:10 29:776:15 122:776:7.5 161:776:5 124:777:20',
 (11,5): '18:777:100 26:777:100 184:777:30 20:777:100 4:777:50 8:777:5 10:778:2 6:778:5 15:778:2 12:778:30 22:778:3',
 (16,1): '126:801:2 134:801:2 52:801:5 232:801:5 49:801:5 45:801:10 44:802:10 43:802:10 42:802:10 54:802:5 50:802:0 121:802:2 73:802:5 103:802:2 32:803:2 53:803:5',
 (16,2): '128:803:5 160:803:20 148:803:2 147:803:2 75:803:2 28:804:10 37:804:2 79:804:20 41:804:7.5 82:804:7.5 2:804:2 230:804:3 233:804:10 99:805:2 132:805:2 125:805:2 1:805:2 234:805:5',
 (16,3): '153:805:2 85:806:2 115:806:5 114:806:2 30:806:5 111:806:5 110:806:2 102:806:2 104:807:2 140:807:2 96:807:5 108:807:5 109:807:2 113:807:0 119:807:20 120:807:2 112:808:2 84:808:2',
 (16,4): '222:808:7.5 223:808:7.5 224:808:7.5 225:808:7.5 68:808:2 31:809:5 33:809:2 16:809:2 21:809:2 13:809:30 14:809:2 7:809:5 11:809:2 9:810:5 5:810:50 19:810:100 183:810:30 25:810:100 17:810:100',
}
for (panel,row), tokens in CB_ROWS.items():
    for col, token in enumerate(tokens.split(),1):
        ref,page,amps=token.split(':')
        cid=f'p{panel}_cb_r{row:02}_c{col:02}'
        patch=dict(electricalTable=dict(ratedCurrentA=float(amps) if float(amps)>0 else None,
                                       ratingNotPrinted=float(amps)==0,
                                       schematicPdfPages=[381,382,383],
                                       note='Table rating is evidence, not an equipment operating draw or a change to the EPS branch rating.'))
        add(cid,f'4CB{ref}',int(page),True,**patch)
assert sum(len(v.split()) for v in CB_ROWS.values())==160

# DSKY and DEDA are separately counted keys/displays, although some handbook
# rows group the numeric keys. Preserve that group distinction in designations.
for cid,ref in [('p4_cdr_aca_4_jet','1S21'),('p4_lmp_aca_4_jet','1S23'),
                ('p4_cdr_ttca_transl','1S20'),('p4_lmp_ttca_transl','1S22')]:
    add(cid,ref,745,True)
DSKY_LIGHTS={
 'uplink_acty':('3DS1',745),'temp':('3DS8',745),
 'no_att':('3DS5',746),'gimbal_lock':('3DS9',746),'stby':('3DS6',746),
 'prog':('3DS10',746),'key_rel':('3DS7',746),'restart':('3DS11',746),
 'opr_err':('3DS14',747),'tracker':('3DS12',747),'alt':('3DS209',747),
 'vel':('3DS204',747),'comptr_acty':('3DS15',748)}
for name,(ref,page) in DSKY_LIGHTS.items():
    add(f'p4_dsky_{name}_light',ref,page,True)
for name,ref in [('prog','3M1'),('verb','3M2'),('noun','3M3'),('r1','3M4'),('r2','3M5'),('r3','3M6')]:
    add(f'p4_dsky_{name}_display',ref,748,True)
for name,ref,page in [('verb','3S3',748),('noun','3S4',748),('clr','3S5',748),
                       ('pro','3S6',749),('key_rel','3S7',749),('entr','3S8',749),('rset','3S9',749),
                       ('plus','3S21',749),('minus','3S20',749)]:
    add(f'p4_dsky_{name}',ref,page,True,momentary=True)
for digit in range(10):
    add(f'p4_dsky_{digit}','3S10-3S19 (numeric-key group)',749,True,momentary=True)
for name,ref in [('clr','12S13'),('read_out','12S15'),('entr','12S14'),('hold','12S16')]:
    add(f'p6_deda_{name}',ref,758,True,momentary=True)
for name in ['plus','minus']+[str(n) for n in range(10)]:
    add(f'p6_deda_{name}','12S1-12S12 (keyboard group)',758,True,momentary=True)

for cid, ref, page in [
 ('p1_ascent_he_reg_1_talkback','10FL1',696),('p1_ascent_he_reg_2_talkback','10FL2',697),
 ('p1_descent_he_reg_1_talkback','10FL3',697),('p1_descent_he_reg_2_talkback','10FL4',698),
 ('p3_eng_gmbl','1S8',729),('p3_des_eng_cmd_ovrd','1S19',729),('p3_ldg_ant','17S5',729),
 ('p8_des_propulsion_fuel_vent_talkback','10FL5',759),
 ('p8_des_propulsion_oxid_vent_talkback','10FL6',760),('p8_ldg_gear_deploy_talkback','2FL1',761),
 ('p14_dc_bus_fault','4DS2',789),('p14_des_bats_talkback','4FL9',796),
 ('p14_bat_5_normal_se_feed_talkback','4FL5',797),
 ('p14_bat_5_back_up_cdr_feed_talkback','4FL7',797),
 ('p14_bat_6_normal_cdr_feed_talkback','4FL6',798),
 ('p14_bat_6_back_up_se_feed_talkback','4FL8',799),
 ('p5_des_rate','1S5',751)]:
    add(cid,ref,page,page in VISUAL_PAGES)

for name,ref,page in [
 ('ces_ac',6,683),('asc_press',2,683),('ces_dc',7,683),('des_reg',3,683),
 ('ags',8,684),('des_qty',4,683),('lgc',9,684),('iss',10,684),
 ('rcs_tca',11,684),('cabin',16,685),('rcs_a_reg',12,685),
 ('suit_fan',17,685),('rcs_b_reg',13,685),('dc_bus',14,685)]:
    add(f'p1_{name}_warning',f'6DS{ref}',page,True)
for name,ref,page in [
 ('asc_hi_reg',21,703),('inverter',26,703),('ed_relays',31,705),('ecs',36,706),
 ('asc_qty',22,703),('battery',27,704),('rcs',32,705),('o2_qty',37,706),
 ('eng_gmbl',23,703),('rndz_rdr',28,704),('heater',33,705),('glycol',38,706),
 ('c_w_pwr',34,705),('water_qty',39,706),('pre_amps',30,704),('s_bd_rcvr',40,707)]:
    add(f'p2_{name}_caution',f'6DS{ref}',page,True)
for system,refs,pages in [
 ('a',['8FL6','8FL18','8FL9','8FL10','8FL13','8FL14'],[708,709,710,711,712,713]),
 ('b',['8FL8','8FL19','8FL11','8FL12','8FL15','8FL16'],[714,715,716,717,718,719])]:
    names=['asc_fuel','asc_oxid','quad_1','quad_2','quad_3','quad_4']
    for name,ref,page in zip(names,refs,pages):
        add(f'p2_system_{system}_{name}_talkback',ref,page,page in VISUAL_PAGES)
for cid,ref,page in [('p2_crsfd_talkback','8FL17',720),
                      ('p2_main_sov_sys_a_talkback','8FL5',721),('p2_main_sov_sys_b_talkback','8FL7',722)]:
    add(cid,ref,page,page in VISUAL_PAGES)
for cid,ref,page,scales in [
 ('p2_reaction_control_temp','8M2',707,['SYS A','SYS B']),
 ('p2_reaction_control_press','8M1',707,['SYS A','SYS B']),
 ('p2_reaction_control_quantity','8M4',707,['SYS A','SYS B']),
 ('p2_ecs_temp','7M3A/7M3B',723,['CABIN degF','SUIT degF']),
 ('p2_ecs_press','7M2A/7M2B',723,['CABIN psia','SUIT psia']),
 ('p2_glycol','7M5A/7M5B',723,['PRESS','TEMP']),
 ('p2_o2_h2o_quantity','7M4A/7M4B',724,['O2','H2O'])]:
    add(cid,ref,page,True,instrumentAssembly=dict(subscales=scales,
        countMeaning='One physical instrument assembly; its multiple scales/needles are named here rather than counted as separate input controls.'))

# The two audio centers share control functions but have distinct designations.
for panel,prefix,base in [(8,'15A',763),(12,'15B',779)]:
    page_map={8:dict(s_band_t_r=763,s_band_rcv_volume=763,ics_t_r=764,ics_rcv_volume=764,
                    relay=764,mode=764,audio_cont=765,vox_sens=765,vhf_a=765,vhf_a_volume=765,
                    vhf_b=765,vhf_b_volume=766,master_vol=766),
              12:dict(s_band_t_r=779,s_band_rcv_volume=779,ics_t_r=779,ics_rcv_volume=780,
                     relay=780,mode=780,audio_cont=780,vox_sens=781,vhf_a_audio=781,vhf_a_volume=781,
                     vhf_b_audio=781,vhf_b_volume=782,master_vol=782)}[panel]
    suffixes=dict(s_band_t_r='S1',ics_t_r='S3',relay='S4',mode='S6',audio_cont='S5',
                  vhf_a='S2',vhf_a_audio='S2',vhf_b='S9',vhf_b_audio='S9',
                  s_band_rcv_volume='R14',ics_rcv_volume='R7',vox_sens='R8',
                  vhf_a_volume='R12',vhf_b_volume='R13',master_vol='R15')
    for name,page in page_map.items():
        patch={}
        if suffixes[name].startswith('R'):
            patch=dict(analog=dict(min=0,max=1,step=0.01,default=0,unit='normalized'),
                       notes='AOH specifies continuous adjustment without a calibrated numeric placard range. Runtime normalized0..1 is a UI parameter, not a recovered gain law.')
        add(f'p{panel}_{name}',prefix+suffixes[name],page,True,**patch)
add('p8_coas','16S14',766,True)
add('p12_squelch_vhf_a','13R10',784,True,
    analog=dict(min=0,max=1,step=0.01,default=0,unit='normalized'))
add('p12_squelch_vhf_b','13R15',785,True,
    analog=dict(min=0,max=1,step=0.01,default=0,unit='normalized'))
# Visual review resolves several mistaken OCR digits in the index/row links.
add('p12_s_band_xmtr_rcvr','13S8',782,True)
add('p12_functions_pcm','13S4',783,True)
add('p12_functions_range','13S1',784,True,
    positions=['RANGE','OFF/RESET','TV/CWEA ENABLE'],default='OFF/RESET')
add('p12_telemetry_biomed','13S3',785,True)
add('p1_aca_prop','1S25',693,True)
add('p3_dead_band','11S2',733,True)
add('p3_flood_ovhd_fwd','16S6',741,True)
add('p14_dc_bus_fault','4DS2',789,True,label='DC FEEDER FAULT',
    notes='Source table names DC FEEDER FAULT. Stable ID retained from the original DC BUS FAULT diagram transcription.')
add('p3_test_monitor','17S8',730,True,
    positions=['LDG RADAR ALT XMTR','LDG RADAR VEL XMTR','RNDZ RADAR AGC',
               'RNDZ RADAR XMTR PWR','RNDZ RADAR SHAFT ERR','RNDZ RADAR TRUN ERR'],
    notes='Detailed table PDF730-731 has six selections. The original inferred LDG RADAR PWR state is removed; grouped LR/RR prefixes retained for clarity.')
add('p3_lamp_tone_test','16S10',741,True,
    positions=['OFF','ALARM/TONE','C/W 1','ENG PB-C/W 2','C/W 3','C/W 4','COMPN T','OFF'],
    default='OFF',mechanism=dict(wrap=False,offAtBothEnds=True),
    notes='AOH: OFF is present at each end of the switching sequence so either end can be selected without cycling through tests. Both physical detents retain the actual OFF placard; detent index must persist separately from label.')
for system in ['a','b']:
    for quad in range(1,5):
        cid=f'p2_system_{system}_quad_{quad}_talkback'
        PATCHES[cid]['positions']=['BARBER_POLE','GRAY','RED']
        PATCHES[cid]['notes']='AOH includes red TCA fault display in addition to gray/barber-pole valve status. Gray wording in the QUAD2 row differs from adjacent rows; subsystem semantics require reconciliation.'
for cid,ref,page in [('p3_flood_ovhd_fwd_brightness','16R4',741),
                      ('p5_flood_ovhd_fwd','16R1',754),('p5_anun_num','16R2',755),
                      ('p5_integral','16R3',755)]:
    add(cid,ref,page,True,analog=dict(min=0,max=1,step=0.01,default=0,unit='normalized'),
        notes='AOH specifies continuous DIM-to-BRIGHT adjustment. Normalized0..1 is a presentation parameter; photometry and the physical resistance/gain curve are not recovered.')

# Upgrade only full pages actually viewed in this review; OCR pages remain explicit.
for patch in PATCHES.values():
    if patch['source']['tablePdfPage'] in VISUAL_PAGES:
        patch['source']['detailAudit']='visual_table'
        patch['confidence']='diagram_and_table_crosschecked'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory',type=Path,default=ROOT/'reference/controls.json',
                        help='Inventory to audit; staged snapshots may be audited without replacing the active one.')
    parser.add_argument('--report',type=Path,default=ROOT/'reference/control-source-audit.json')
    parser.add_argument('--skip-overrides',action='store_true',help='Read-only inventory audit; do not rewrite the correction ledger.')
    args=parser.parse_args()
    inventory_path=args.inventory.resolve()
    inventory=json.loads(inventory_path.read_text(encoding='utf-8-sig'))
    controls={c['id']:c for c in inventory['controls']}
    # p5_stop is a source-confirmed omission being added by the off-panel audit.
    unknown=sorted(set(PATCHES)-set(controls)-{'p5_stop'})
    if unknown:
        raise ValueError(f'Unknown audit IDs (do not silently lose corrections): {unknown}')
    override=dict(schemaVersion=1,document='lm7-aoh-v1',
                  reviewDate='2026-11-17',status='reviewed corrections; complete-vehicle gate remains open',
                  controls=PATCHES)
    if not args.skip_overrides:
        (ROOT/'reference/control-detail-overrides.json').write_text(json.dumps(override,indent=2)+'\n',encoding='utf-8')
    counts=collections.Counter(c['panel'] for c in controls.values())
    followup=json.loads((ROOT/'reference/cabin-mechanism-followup.json').read_text(encoding='utf-8'))
    for side,n in [('aft',31),('forward',45)]:
        rows=followup['stowageRowDispositions'][side]['rows']
        if [r['item'] for r in rows]!=list(range(1,n+1)):
            raise ValueError(f'Incomplete or reordered stowage row disposition: {side}')
        if any(r.get('disposition') not in followup['stowageRowDispositions']['dispositionKey'] for r in rows):
            raise ValueError(f'Unknown stowage row disposition: {side}')
    candidates={c['candidateId']:c for category in ['cabinInputs','movableObjectAndRetentionStates']
                for c in followup['implementationCandidates'][category]}
    if len(candidates)!=35:
        raise ValueError('The reviewed cabin mechanism snapshot must retain all 35 proposed IDs.')
    groups={g['id']:g for g in followup['mechanismGroups']}
    cabin_categories={'visual_functional_description','visual_figure','candidate_assembly_proxy'}
    # Table rows, functional descriptions, figures and assembly proxies are
    # distinct evidence classes. A source-backed object is not thereby a
    # tabled flight switch, nor are its software states recovered placards.
    evidence={}
    for cid,c in controls.items():
        if cid in PATCHES:
            evidence[cid]=PATCHES[cid]['source']['detailAudit']
        elif cid in candidates:
            kind=c.get('source',{}).get('detailAudit',c.get('confidence','pending'))
            evidence[cid]=kind if kind in cabin_categories else 'pending'
            if evidence[cid]!='pending':
                if c.get('stateLabelsArePlacards') is not False:
                    raise ValueError(f'Cabin software state labels need an explicit non-placard marker: {cid}')
                if c.get('source',{}).get('tablePdfPage'):
                    raise ValueError(f'Cabin mechanism must not be mislabeled as a detailed table row: {cid}')
        elif c.get('source',{}).get('tablePdfPage') and c.get('confidence')=='visually_read_detailed_table':
            evidence[cid]='visual_table'
        elif c.get('source',{}).get('figure') and c.get('confidence') in ['visually_read_detailed_table','diagram_transcribed']:
            evidence[cid]='visual_figure'
        else:
            evidence[cid]='pending'
    visual=collections.Counter(controls[cid]['panel'] for cid,kind in evidence.items()
                               if kind=='visual_table')
    linked=collections.Counter(controls[cid]['panel'] for cid,kind in evidence.items()
                               if kind in ['visual_table','index_or_table_ocr_link'])
    figure=collections.Counter(controls[cid]['panel'] for cid,kind in evidence.items() if kind=='visual_figure')
    functional=collections.Counter(controls[cid]['panel'] for cid,kind in evidence.items() if kind=='visual_functional_description')
    proxy=collections.Counter(controls[cid]['panel'] for cid,kind in evidence.items() if kind=='candidate_assembly_proxy')
    qualified=collections.Counter(controls[cid]['panel'] for cid,kind in evidence.items() if kind!='pending')
    category_counts=collections.Counter(evidence.values())
    per_control=[]
    for cid,kind in evidence.items():
        c=controls[cid]
        row=dict(controlId=cid,review=kind,
                 source=PATCHES[cid]['source'] if cid in PATCHES else c.get('source',{}))
        if cid in candidates:
            candidate=candidates[cid]
            row.update(inventoryRole=c.get('inventoryRole'),mechanismGroup=candidate['group'],
                sourceEvidence=c.get('sourceEvidence',groups[candidate['group']]['evidence']),
                stateLabelsArePlacards=False,
                stateBasis='Software abstraction of a described mechanism/object; labels are not recovered spacecraft placards.',
                contract=candidate.get('relationship'),
                limitations=groups[candidate['group']].get('notEstablished',[]))
            if kind=='candidate_assembly_proxy':
                row['stateBasis']='Assembly-level retention proxy; source does not establish the count or geometry of individual actuators.'
                row['individualActuatorCountEstablished']=False
        per_control.append(row)
    eps_path=ROOT/'reference/electrical.json'
    eps=json.loads(eps_path.read_text()) if eps_path.exists() else {'breakers':[]}
    eps_breakers={b['controlId']:b for b in eps['breakers']}
    conflicts=[]
    for cid,patch in PATCHES.items():
        amps=patch.get('electricalTable',{}).get('ratedCurrentA')
        if amps is not None and cid in eps_breakers and amps!=eps_breakers[cid]['ratedCurrentA']:
            conflicts.append(dict(controlId=cid,referenceDesignation=patch['referenceDesignation'],
                label=controls[cid]['label'],tableRatedCurrentA=amps,tablePdfPage=patch['source']['tablePdfPage'],
                currentSchematicRatedCurrentA=eps_breakers[cid]['ratedCurrentA'],schematicPdfPages=[381,382,383],
                resolution='OPEN - source editions/circuit identification need adjudication; EPS behavior not silently changed.'))
    report=dict(schemaVersion=1,checkedDate='2026-11-17',result='OPEN',
      inventoryFile=inventory_path.relative_to(ROOT).as_posix(),
      inventoryLifecycle='active' if inventory_path==ROOT/'reference/controls.json' else 'staged',
      declaredInventorySourceReview='PASS_SOURCE_QUALIFIED' if category_counts['pending']==0 else 'PARTIAL',
      knownInteriorMechanismReview='SOURCE_QUALIFIED_WITH_PROXY_LIMITS' if all(cid in controls for cid in candidates) else 'PARTIAL',
      physicalFollowup='DEFERRED_BY_EXPLICIT_USER_REQUEST; does not block automated development',
      inventorySha256=hashlib.sha256(inventory_path.read_bytes()).hexdigest(),
      completeVehicleDenominatorKnown=False,
      counts=dict(declaredEntries=len(controls),interactiveEntries=sum(c.get('interactive',False) for c in controls.values()),
                  outputEntries=sum(not c.get('interactive',False) for c in controls.values()),
                  newManualCabinInputFunctions=sum(c.get('inventoryRole')=='manual_cabin_input' for c in controls.values()),
                  newMovableObjectStates=sum(c.get('inventoryRole')=='movable_object_state' for c in controls.values()),
                  detailedSourceLinked=sum(linked.values()),
                  visuallyReviewedDetailRows=sum(visual.values()),figureMechanismEntries=sum(figure.values()),
                  functionalDescriptionEntries=sum(functional.values()),assemblyProxyEntries=sum(proxy.values()),
                  sourceQualifiedEntries=sum(qualified.values()),evidenceCategories=dict(sorted(category_counts.items())),
                  pendingSourceEntries=sum(kind=='pending' for kind in evidence.values()),
                  originalPanelEntriesReviewed=495,overrideEntries=len(PATCHES),
                  cabinMechanismCandidatesDefined=sum(cid in controls for cid in candidates),
                  stowageFigureRowsDispositioned=76),
      meaning='Counts refer to inventory entries, not unique source rows or independent physical controls. Table rows, functional descriptions, figures and assembly-level proxies are qualified separately. Source presence is not exact state/geometry certification. No complete-LM or headset pass is inferred.',
      evidenceDefinitions=dict(
        visual_table='Detailed Controls and Displays table row visually read; compound-key/instrument grouping remains explicit.',
        visual_functional_description='A visually reviewed functional description establishes mechanism and behavior; software states and provisional articulation remain qualified.',
        visual_figure='A visually reviewed figure or equipment list establishes the named physical article; motion/state abstractions are separately labeled.',
        candidate_assembly_proxy='Source-backed assembly represented by one retention proxy; individual actuator count, linkage and travel are not established.',
        index_or_table_ocr_link='Finding/link evidence only; does not establish a visually certified state audit.',
        pending='No accepted evidence classification present.'),
      panels=[dict(panel=p,declaredEntries=n,detailedSourceLinked=linked[p],
                   visuallyReviewedDetailRows=visual[p],
                   figureMechanismEntries=figure[p],
                   functionalDescriptionEntries=functional[p],assemblyProxyEntries=proxy[p],
                   sourceQualifiedEntries=qualified[p],
                   stateAudit='SOURCE_QUALIFIED_WITH_RECORDED_LIMITATIONS' if qualified[p]==n else 'PARTIAL',
                   unresolvedControlIds=[c['id'] for c in controls.values() if c['panel']==p and evidence[c['id']]=='pending'])
              for p,n in sorted(counts.items())],
      reviewedPdfPages=sorted(VISUAL_PAGES),
      reviewedPdfPagesMeaning='Original numbered-panel visual ledger only; off-panel and cabin mechanism evidence carries its own reviewed pages.',
      perControlEvidence=per_control,
      sourceConflicts=dict(outstandingMissionSourceConflicts=len(conflicts)+2,breakerRatings=conflicts,
        other=[dict(controlId='p12_antenna_vhf',kind='selector state',figurePdfPage=827,tablePdfPage=787,
                    issue='Figure depicts PLSS TEST; detailed table lists AFT/FWD/EVA. Figure state retained; revision reconciliation open.'),
               dict(controlId='p2_system_a_quad_2_talkback',kind='functional wording',tablePdfPage=711,
                    issue='Gray display row says isolation valves closed; neighboring quad gray rows say open. Three visual states inventoried; no flight-system behavior inferred from contradictory wording.')]),
      sourceTableReconciliation=dict(
        numberedPanelTables=dict(pdfPageRanges=[[683,701],[703,743],[745,749],[751,755],[757,758],[759,788],[789,799],[801,810]],
          originalEntriesLinked=495,originalEntriesWithoutLink=0,
          sourceConfirmedOmissionsAdded=['p5_stop','p5_des_rate','p1_x_pointer_power_failure','p1_thrust_power_failure',
            'p1_press_power_failure','p2_rcs_press_power_failure','p2_rcs_quantity_power_failure',
            'p2_ecs_press_power_failure','p2_ecs_quantity_power_failure','p2_glycol_power_failure','p2_x_pointer_power_failure'],
          compoundInstrumentPolicy='Each physical instrument is one inventory assembly; named subscales retain the detailed table components. Power-failure lamps have independent IDs.'),
        cabinMechanismFollowup=dict(source='reference/cabin-mechanism-followup.json',
          ledgerBaselineMeaning='The follow-up ledger inventoryStatus fields describe omissions in the historical 585-entry baseline; this report reconciles actual definitions in the selected inventory.',
          candidates=35,defined=sum(cid in controls for cid in candidates),
          absentCandidateIds=sorted(set(candidates)-set(controls)),
          aftStowageFigureRows=31,forwardStowageFigureRows=45,allRowsDispositioned=True,
          rowMeaning='Overlapping packages and arrangements, not independent control count.',
          statePolicy='New cabin state labels are software abstractions. Source descriptions, figure-only evidence and assembly proxies remain distinct.'),
        wholeVehicle='OPEN - original detailed tables and all 76 stowage figure rows reviewed; known cabin mechanisms source-qualified. Individual stowage closures, wearable/camera/CSM scope and measured geometry remain uncertified.'),
      geometry=dict(document='lm7-aoh-v1',review='visual_full_pages',
        crewCompartment=dict(pdfPage=22,printedPage='1-6',diameterIn=92,diameterM=2.3368,depthIn=42,depthM=1.0668,
                             flightStationSpacingIn=44,flightStationSpacingM=1.1176,deckIn=[36,55],deckM=[0.9144,1.397]),
        panelAttitudes=dict(pdfPage=24,printedPage='1-8',forwardPanelsCantDeg=10,
                            centerPanelsSlopeDownAftDeg=45,sidePanelsUpFromHorizontalDeg=15,
                            panel14UpFromHorizontalDeg=36.5,breakerRowTowardLineOfSightDeg=15),
        forwardHatch=dict(pdfPage=24,printedPage='1-8',approximatelySquareIn=32,approximatelySquareM=0.8128,inwardSwing=True),
        unknown=['individual panel width/height and 3D switch coordinates','crew standing-eye height and operational reach envelopes','precise pressure-shell cut-outs/flight-station floor relationship']),
      unresolved=[
        'All 495 original entries now have visually reviewed detailed table links; source disagreements remain explicit.',
        'All 160 breaker reference designations and table ratings reviewed; listed table/schematic rating conflicts remain open.',
        'Nine separate power-failure lamps added; compound instrument subscales remain explicitly named parts of physical assemblies.',
        'AOT/ORDEAL/ECS/hand-controller/hatch additions are source-linked; measured spatial placement remains provisional.',
        'Known shade/armrest/reel/COAS/utility/PTT/dispenser and retention definitions are source-qualified; check the follow-up candidate reconciliation for any still absent IDs.',
        'Every numbered aft/forward stowage row has a disposition. Unidentified individual closures, wearable/EVA controls, camera controls and CSM-side interfaces are excluded from the current cockpit snapshot; their wider scope remains OPEN.',
        'Drogue retention and forward hatch hinge-pin set are assembly proxies, not a certified count of individual release actuators.',
        'VHF antenna selector PLSS TEST is drawn in Fig3-2 but absent from the detailed selector table PDF787.',
        'Inventory mechanism metadata does not prove full electrical/mechanical subsystem coupling or human reach.',
        'Further physical headset tests are deferred by explicit user request; automated development continues. The observed 585-entry benchmark does not certify the 35 later mechanisms. Consult version-specific worn-headset evidence.'
      ])
    args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report['counts']))


if __name__=='__main__':
    main()
