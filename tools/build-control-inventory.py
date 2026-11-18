"""Build the explicitly scoped, visually transcribed LM-7 panel inventory.

Source coordinates are pixels in reference/extracts/panel-*.png (AOH Fig.3-2).
This is a transcription script, not automatic inference from cockpit artwork.
"""
import argparse
import collections
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=ROOT/'reference/controls.json',
    help='Write an explicit staged snapshot without replacing the active inventory.')
parser.add_argument('--expansion', type=Path, default=ROOT/'reference/offpanel-controls.json',
    help='Use a staged off-panel/mechanism expansion without replacing the active data.')
args = parser.parse_args()
CROPS = json.loads((ROOT / 'reference/extracts/panel-crops.json').read_text())
CONTROLS = []

def add(panel, label, kind, x, y, positions=None, key=None, notes=None):
    panel = str(panel)
    image_size = CROPS['panels'][panel]['pixelSize']
    if positions is None:
        positions = {'pushbutton':['RELEASED','PRESSED'], 'breaker':['PULLED','PUSHED'],
                     'indicator':['OFF','ON'], 'meter':['UNPOWERED','POWERED'],
                     'display':['UNPOWERED','POWERED'], 'thumbwheel':['MIN','MID','MAX']}[kind]
    slug_input = key or label
    if slug_input.endswith(' +'): slug_input = slug_input[:-1] + 'plus'
    if slug_input.endswith(' -'): slug_input = slug_input[:-1] + 'minus'
    slug = re.sub('[^a-z0-9]+', '_', slug_input.lower()).strip('_')
    CONTROLS.append(dict(id=f'p{panel}_{slug}', panel=panel, label=label, type=kind,
        positions=positions, default=positions[0], interactive=kind not in ['indicator','meter','display'],
        layout=dict(u=round(x/image_size[0],5),v=round(1-y/image_size[1],5)),
        source=dict(document='lm7-aoh-v1',figure='3-2',printedPage='3-157/3-158',pdfPage=827),
        confidence='diagram_transcribed', provisional=True,
        notes=notes or 'Placard and location transcribed from Fig.3-2. Default is a sandbox state, not a flight-checklist initial condition.'))

def toggle(panel,label,x,y,positions=('ON','OFF'),**kw): add(panel,label,'toggle',x,y,list(positions),**kw)
def rotary(panel,label,x,y,positions,**kw): add(panel,label,'rotary',x,y,list(positions),**kw)
def button(panel,label,x,y,**kw): add(panel,label,'pushbutton',x,y,**kw)
def indicator(panel,label,x,y,**kw): add(panel,label,'indicator',x,y,**kw)
def meter(panel,label,x,y,**kw): add(panel,label,'meter',x,y,**kw)
def display(panel,label,x,y,**kw): add(panel,label,'display',x,y,**kw)
def tb(panel,label,x,y): add(panel,label,'indicator',x,y,['BARBER_POLE','GRAY'])

# Panel 1: commander flight instruments, guidance, propulsion and abort controls.
toggle(1,'X-POINTER SCALE',373,746,['HI MULT','LO MULT'])
toggle(1,'RATE/ERR MON',45,958,['RNDZ RADAR','LDG RDR/CMPTR'])
toggle(1,'ATTITUDE MON',45,1058,['PGNS','AGS'])
toggle(1,'GUID CONT',761,860,['PGNS','AGS'])
toggle(1,'MODE SEL',762,958,['LDG RADAR','PGNS','AGS'])
toggle(1,'RNG/ALT MON',762,1058,['RNG/RNG RT','ALT/ALT RT'])
toggle(1,'SHFT/TRUN',140,1195,['+/-50 DEG','+/-5 DEG'])
toggle(1,'RATE SCALE',231,1200,['25 DEG/SEC','5 DEG/SEC'])
toggle(1,'ACA PROP',323,1204,['ENABLE','DISABLE'])
toggle(1,'THR CONT',230,1312,['AUTO','MAN'],key='throt_cont')
toggle(1,'MAN THROT',323,1314,['CDR','SE'])
toggle(1,'ENG ARM',181,1407,['ASC','OFF','DES'])
toggle(1,'ATT/TRANSL',263,1400,['4 JETS','2 JETS'])
toggle(1,'BAL CPL',325,1406,['ON','OFF'])
toggle(1,'ASCENT He REG 1',403,1257,['OPEN','CLOSE'])
toggle(1,'ASCENT He REG 2',493,1257,['OPEN','CLOSE'])
toggle(1,'DESCENT He REG 1',402,1410,['OPEN','CLOSE'])
toggle(1,'DESCENT He REG 2',493,1410,['OPEN','CLOSE'])
toggle(1,'PRPLNT QTY MON',546,1282,['DES 1','OFF','DES 2'])
toggle(1,'PRPLNT TEMP/PRESS MON',550,1397,['ASC','DES 1','DES 2'])
rotary(1,'HELIUM MON',686,1314,['DES SUCRIT PRESS','DES AMB PRESS','OFF','ASC TEMP 1','ASC TEMP 2','ASC PRESS 1','ASC PRESS 2'])
button(1,'ABORT',641,1167)
button(1,'ABORT STAGE',751,1168,notes='Guarded pushbutton; guard geometry and interlock not yet independently inventoried.')
button(1,'MASTER ALARM',47,868)
for label,x,y in [('ASCENT He REG 1',404,1197),('ASCENT He REG 2',492,1197),('DESCENT He REG 1',404,1352),('DESCENT He REG 2',492,1352)]:tb(1,label+' TALKBACK',x,y)
for label,x,y in [('MISSION TIMER',135,451),('EVENT TIMER',362,451),('OXIDIZER QUANTITY',530,409),('FUEL QUANTITY',530,473),('HELIUM',707,458)]:display(1,label,x,y)
for label,x,y in [('X-POINTER',120,694),('THRUST',514,681),('TEMP',623,681),('PRESS',742,681),('FDAI',271,980),('RANGE/ALT',503,952),('RANGE RATE/ALT RATE',574,952),('T/W',685,958)]:meter(1,label,x,y)
indicator(1,'LUNAR CONTACT',372,633)
warning1=[('CES AC',399,191),('ASC PRESS',317,219),('CES DC',399,219),('DES REG',317,247),('AGS',399,247),('DES QTY',317,274),('LGC',399,274),('ISS',399,301),('RCS TCA',506,191),('CABIN',592,191),('RCS A REG',506,219),('SUIT/FAN',592,219),('RCS B REG',506,247),('DC BUS',506,274)]
for label,x,y in warning1:indicator(1,label+' WARNING',x,y)

# Panel 2: LMP instruments, RCS valve controls and ECS monitor selection.
for sys,xs in [('A',[68,148]),('B',[232,313])]:
    for i,x in enumerate(xs,1):
        toggle(2,f'SYSTEM {sys} ASC FEED {i}',x,715,['OPEN','CLOSE'])
        tb(2,f'SYSTEM {sys} ASC {"FUEL" if i==1 else "OXID"} TALKBACK',x,643)
    for quad,x,y,ty in [(1,xs[0],887,819),(4,xs[1],887,819),(2,xs[0],1047,970),(3,xs[1],1047,970)]:
        toggle(2,f'SYSTEM {sys} QUAD {quad} THRUSTER PAIR',x,y,['OPEN','CLOSE'])
        tb(2,f'SYSTEM {sys} QUAD {quad} TALKBACK',x,ty)
toggle(2,'CRSFD',67,1213,['OPEN','CLOSE']);tb(2,'CRSFD TALKBACK',67,1149)
for label,x in [('SYS A',208),('SYS B',305)]:
    toggle(2,'MAIN SOV '+label,x,1215,['OPEN','CLOSE']);tb(2,'MAIN SOV '+label+' TALKBACK',x,1149)
toggle(2,'ACA PROP',305,1323,['ENABLE','DISABLE'])
rotary(2,'TEMP/PRESS MON',81,1335,['He','PRPLNT','FUEL MANF','OXID MANF'])
toggle(2,'RATE/ERR MON',764,957,['RNDZ RADAR','LDG RDR/CMPTR']);toggle(2,'ATTITUDE MON',764,1061,['PGNS','AGS'])
rotary(2,'GLYCOL',435,1255,['INST (SEC)','PUMP 1','PUMP 2'],key='glycol_selector')
indicator(2,'GLYCOL COMPONENT CAUTION',542,1254)
rotary(2,'SUIT FAN',438,1397,['OFF','1','2'])
indicator(2,'SUIT FAN COMPONENT CAUTION',535,1397)
rotary(2,'O2/H2O QTY MON',653,1339,['C/W RESET','DES','ASC 1','ASC 2'])
indicator(2,'CO2 COMPONENT CAUTION',622,1424);indicator(2,'H2O SEP COMPONENT CAUTION',678,1424)
button(2,'MASTER ALARM',765,865)
for label,x,y in [('REACTION CONTROL TEMP',84,478),('REACTION CONTROL PRESS',202,478),('REACTION CONTROL QUANTITY',302,478),('ECS TEMP',442,478),('ECS PRESS',551,478),('PART PRESS CO2',704,477),('GLYCOL',433,702),('O2/H2O QUANTITY',544,702),('X-POINTER',707,698),('FDAI',548,978)]:meter(2,label,x,y)
caution2=[('ASC HI REG',426,191),('INVERTER',509,191),('ED RELAYS',597,191),('ECS',684,191),('ASC QTY',426,218),('BATTERY',509,218),('RCS',597,218),('O2 QTY',684,218),('ENG GMBL',426,245),('RNDZ RDR',509,245),('HEATER',597,245),('GLYCOL',684,245),('C/W PWR',597,272),('WATER QTY',684,272),('PRE AMPS',509,299),('S-BD RCVR',684,299)]
for label,x,y in caution2:indicator(2,label+' CAUTION',x,y)

# Panel 3: radar, stabilization/control, event timer and lighting.
toggle(3,'ENG GMBL',94,88,['ENABLE','OFF'])
toggle(3,'DES ENG CMD OVRD',81,195,['ON','OFF'])
toggle(3,'LDG ANT',176,87,['AUTO','DES','HOVER'])
toggle(3,'RADAR TEST',180,196,['RNDZ','OFF','LDG'])
rotary(3,'TEST/MONITOR',148,336,['LDG RADAR ALT XMTR','LDG RADAR VEL XMTR','LDG RADAR PWR','RNDZ RADAR AGC','RNDZ RADAR XMTR PWR','RNDZ RADAR SHAFT ERR','RNDZ RADAR TRUN ERR'])
toggle(3,'SLEW RATE',300,247,['HI','LO'])
add(3,'SLEW','joystick',299,339,['CENTER','UP','RIGHT','DOWN','LEFT'])
rotary(3,'RENDEZVOUS RADAR',445,333,['AUTO TRACK','SLEW','LGC'])
meter(3,'RADAR SIGNAL STRENGTH',302,129);indicator(3,'RENDEZVOUS RADAR NO TRACK',445,183)
toggle(3,'DEAD BAND',604,88,['MAX','MIN'])
toggle(3,'GYRO TEST AXIS',711,88,['ROLL','PITCH','YAW'])
toggle(3,'GYRO TEST RATE',824,88,['POS RT','OFF','NEG RT'])
for axis,x in [('ROLL',604),('PITCH',711),('YAW',820)]:toggle(3,axis+' MODE CONT',x,199,['MODE CONT','PULSE','DIR'])
toggle(3,'PGNS MODE CONTROL',604,326,['AUTO','ATT HOLD','OFF'])
toggle(3,'AGS MODE CONTROL',714,326,['AUTO','ATT HOLD','OFF'])
toggle(3,'IMU CAGE',825,326,['ON','OFF'])
meter(3,'HTR CONT TEMP',970,138)
rotary(3,'TEMP MONITOR',970,337,['RNDZ','LDG','QUAD 1','QUAD 2','QUAD 3','QUAD 4','S-BAND'])
toggle(3,'EVENT TIMER RESET/COUNT',1045,90,['RESET','COUNT DOWN'])
toggle(3,'EVENT TIMER CONT',1121,90,['START','STOP'])
toggle(3,'EVENT TIMER SLEW CONT MIN',1183,90,['TENS','UNITS'])
toggle(3,'EVENT TIMER SLEW CONT SEC',1252,90,['TENS','UNITS'])
for quad,x,y in [(1,1114,215),(4,1184,215),(2,1114,324),(3,1184,324)]:toggle(3,f'RCS SYS A/B-2 QUAD {quad}',x,y,['AUTO','OFF','MAN'])
toggle(3,'SIDE PANELS',1326,90,['ON','OFF'])
toggle(3,'FLOOD OVHD/FWD',1328,168,['OVHD/FWD','OFF','ALL'])
rotary(3,'FLOOD OVHD/FWD BRIGHTNESS',1450,168,['DIM','MID','BRIGHT'])
rotary(3,'LAMP/TONE TEST',1393,332,['OFF','ALARM/TONE','C/W 1','ENG PB-C/W 2','C/W 3','C/W 4','COMPN T'])
toggle(3,'EXTERIOR LTG',1557,334,['DOCK','OFF','TRACK'])
toggle(3,'X-POINTER SCALE',1584,203,['HI MULT','LO MULT'])
indicator(3,'LUNAR CONTACT',1582,90)

# Panel 4: DSKY and four enable switches. Each key is a distinct inventory node.
for side,x in [('CDR',81),('LMP',651)]:
    toggle(4,side+' ACA/4 JET',x,128,['ENABLE','DISABLE'])
    toggle(4,side+' TTCA/TRANSL',x,317,['ENABLE','DISABLE'])
for label,x,y in [('VERB',207,333),('NOUN',207,388),('+',264,307),('-',264,360),('0',264,414),('7',316,307),('4',316,360),('1',316,414),('8',370,307),('5',370,360),('2',370,414),('9',423,307),('6',423,360),('3',423,414),('CLR',477,307),('PRO',477,360),('KEY REL',477,414),('ENTR',531,333),('RSET',531,388)]:button(4,'DSKY '+label,x,y)
for label,x,y in [('UPLINK ACTY',250,40),('TEMP',316,40),('NO ATT',250,69),('GIMBAL LOCK',316,69),('STBY',250,97),('PROG',316,97),('KEY REL',250,126),('RESTART',316,126),('OPR ERR',250,155),('TRACKER',316,155),('ALT',316,186),('VEL',316,215),('COMPTR ACTY',426,45)]:indicator(4,'DSKY '+label+' LIGHT',x,y)
for label,x,y in [('PROG',502,49),('VERB',427,98),('NOUN',502,98),('R1',462,143),('R2',462,192),('R3',462,243)]:display(4,'DSKY '+label+' DISPLAY',x,y)

# Panel 5: manual engine start, +X translation, mission timer and lighting.
button(5,'START',224,260);button(5,'+X TRANSL',197,441)
toggle(5,'MISSION TIMER CONT',396,185,['START','STOP','RESET'])
for label,x in [('HOURS',516),('MIN',610),('SEC',705)]:toggle(5,'MISSION TIMER SLEW CONT '+label,x,185,['TENS','UNITS'])
for label,x in [('ANUN OVERRIDE',494),('NUM OVERRIDE',571),('INTEGRAL OVERRIDE',645),('SIDE PANELS',719)]:toggle(5,label,x,331,['ON','OFF'])
for label,x in [('FLOOD OVHD/FWD',337),('ANUN/NUM',544),('INTEGRAL',717)]:rotary(5,label,x,452,['DIM','MID','BRIGHT'])

# Panel 6: DEDA and engine stop. Key layout transcribed from the foldout.
button(6,'STOP',60,70)
toggle(6,'AGS STATUS',210,513,['OPERATE','STANDBY','OFF'])
for label,x,y in [('+',326,255),('-',326,308),('7',382,255),('8',438,255),('9',494,255),('4',382,308),('5',438,308),('6',494,308),('1',382,362),('2',438,362),('3',494,362),('0',326,362),('CLR',552,255),('READ OUT',552,308),('ENTR',552,362),('HOLD',439,414)]:button(6,'DEDA '+label,x,y)
display(6,'DEDA ADDRESS',495,154);display(6,'DEDA DATA',487,206);indicator(6,'DEDA OPR ERR',382,207)

# Circuit breakers: visually audited sockets and full placarded group/names.
cbx11=[64,128,193,254,386,452,517,579,649,712,776,843,905,968,1030,1093,1157,1228,1295]
cb11=[
 (210,cbx11,['AC BUS B SE WIND HTR','AC BUS B He/PQGS PROPUL DISP','AC BUS B S-BD ANT','AC BUS B ORDEAL','AC BUS B AGS','AC BUS B AOT LAMP','AC BUS B SE FDAI','AC BUS B NUM LTG','AC BUS B BUS TIE INV 2','AC BUS B BUS TIE INV 1','AC BUS A BUS TIE INV 2','AC BUS A BUS TIE INV 1','AC BUS A AC BUS VOLT','AC BUS A CDR WIND HTR','AC BUS A TAPE RCDR','AC BUS A AOT LAMP','AC BUS A RNDZ RDR','AC BUS A DECA GMBL','AC BUS A INTGL LTG']),
 (426,cbx11,['RCS SYS A MAIN SOV','RCS SYS A QUAD 4 TCA','RCS SYS A QUAD 3 TCA','RCS SYS A QUAD 2 TCA','RCS SYS A QUAD 1 TCA','RCS SYS A ISOL VLV','RCS SYS A ASC FEED 2','RCS SYS A ASC FEED 1','FLIGHT DISPLAYS THRUST','FLIGHT DISPLAYS MISSION TIMER','FLIGHT DISPLAYS CDR X-PNTR','FLIGHT DISPLAYS RNG/RNG RT ALT/ALT RT','FLIGHT DISPLAYS GASTA','FLIGHT DISPLAYS CDR FDAI','FLIGHT DISPLAYS COAS','FLIGHT DISPLAYS ORDEAL','AC BUS A RNG/RNG RT ALT/ALT RT','AC BUS A GASTA','AC BUS A CDR FDAI']),
 (644,cbx11,['DES He REG-VENT','HEATERS RNDZ RDR STBY','HEATERS RNDZ RDR OPR','HEATERS LDG RDR','HEATERS DOCK WINDOW','HEATERS AOT','INST SIG CONDR 1','STAB/CONT AEA','STAB/CONT ABORT STAGE','STAB/CONT ATCA PGNS','STAB/CONT AELD','STAB/CONT ENG CONT','STAB/CONT ATT DIR CONT','STAB/CONT ENG START OVRD','STAB/CONT DECA PWR','ED LDG GEAR FLAG','ED LOGIC PWR A','LTG UTIL','LTG ANUN/DOCK/COMPN T']),
 (876,cbx11+[1360,1420],['HEATERS RCS SYS A/B-1 QUAD 4','HEATERS RCS SYS A/B-1 QUAD 3','HEATERS RCS SYS A/B-1 QUAD 2','HEATERS RCS SYS A/B-1 QUAD 1','ECS SUIT FAN 1','ECS CABIN FAN 1','ECS GLYCOL PUMP 2','ECS GLYCOL PUMP 1','ECS GLYCOL PUMP AUTO TRNFR','COMM UP DATA LINK','COMM SEC S-BD XMTR/RCVR','COMM SEC S-BD PWR AMPL','COMM VHF B XMTR','COMM VHF A RCVR','COMM CDR AUDIO','PGNS SIG STR DISP','PGNS LDG RDR','PGNS RNDZ RDR','PGNS LGC/DSKY','PGNS IMU STBY','PGNS IMU OPR']),
 (1125,[64,128,193,254,386,452,517,579,649,712,776],['EPS BAT FEED TIE 1','EPS BAT FEED TIE 2','EPS CROSS TIE BAL LOADS','EPS CROSS TIE BUS','EPS XLUNAR BUS TIE','EPS DES ECA CONT','EPS DES ECA','EPS ASC ECA CONT','EPS ASC ECA','EPS INV 1','EPS DC BUS VOLT'])]
for row,(y,xs,labels) in enumerate(cb11,1):
    assert len(xs)==len(labels),(11,row,len(xs),len(labels))
    for col,(x,label) in enumerate(zip(xs,labels),1):add(11,label,'breaker',x,y,key=f'cb_r{row:02}_c{col:02}')

cb16=[
 (204,[110,173,238,299,365,429,498,561,625,695,758,821,887,952,1014,1136],['FLT DISP EVENT TIMER/SE FDAI','FLT DISP SE X-PNTR','RCS SYS B ASC FEED 1','RCS SYS B ASC FEED 2','RCS SYS B ISOL VLV','RCS SYS B QUAD 1 TCA','RCS SYS B QUAD 2 TCA','RCS SYS B QUAD 3 TCA','RCS SYS B QUAD 4 TCA','RCS SYS B CRSFD','RCS SYS B TEMP/PRESS DISP-FLAGS','RCS SYS B PQGS DISP','RCS SYS B MAIN SOV','DISP/ENG OVRD LOGIC','PQGS','ASC He REG']),
 (422,[110,173,238,299,365,429,498,561,625,695,758,821,887,952,1014,1136,1200,1267],['LTG FLOOD','LTG TRACK','LTG ANUN/DOCK/COMPN T','LTG MASTER ALARM','ED LOGIC PWR B','STAB/CONT AEA','STAB/CONT ENG ARM','STAB/CONT ASA','STAB/CONT AELD','STAB/CONT ATCA','STAB/CONT ABORT STAGE','STAB/CONT ATCA AGS','STAB/CONT DES ENG OVRD','INST CWEA','INST SIG SENSOR','INST PCM/TE','INST SIG CONDR 2','ECS SUIT FLOW CONT']),
 (642,[110,173,238,299,365,429,498,561,625,695,758,887,952,1014,1136,1200,1267,1330],['COMM DISP','COMM SE AUDIO','COMM VHF A XMTR','COMM VHF B RCVR','COMM PRIM S-BD PWR AMPL','COMM PRIM S-BD XMTR/RCVR','COMM S-BD ANT','COMM PMP','COMM TV','ECS DISP','ECS GLYCOL PUMP SEC','ECS LCG PUMP','ECS CABIN FAN CONT','ECS CABIN REPRESS','ECS SUIT FAN 2','ECS SUIT FAN AP','ECS DIVERT VLV','ECS CO2 SENSOR']),
 (873,[102,166,232,294,361,425,490,556,619,685,749,813,878,941,1003,1136,1200,1267,1330],['HEATERS RCS SYS A/B-2 QUAD 1','HEATERS RCS SYS A/B-2 QUAD 2','HEATERS RCS SYS A/B-2 QUAD 3','HEATERS RCS SYS A/B-2 QUAD 4','HEATERS DISP','HEATERS S-BD ANT','CAMR SEQ','EPS DISP','EPS DC BUS VOLT','EPS INV 2','EPS ASC ECA','EPS ASC ECA CONT','EPS DES ECA','EPS DES ECA CONT','EPS XLUNAR BUS TIE','EPS CROSS TIE BUS','EPS CROSS TIE BAL LOADS','EPS BAT FEED TIE 1','EPS BAT FEED TIE 2'])]
for row,(y,xs,labels) in enumerate(cb16,1):
    assert len(xs)==len(labels),(16,row,len(xs),len(labels))
    for col,(x,label) in enumerate(zip(xs,labels),1):add(16,label,'breaker',x,y,key=f'cb_r{row:02}_c{col:02}')

# Panel 8: descent vents, explosive devices and commander's audio.
for label,x in [('FUEL VENT',582),('OXID VENT',670)]:
    toggle(8,'DES PROPULSION '+label,x,155,['OPEN','CLOSE'])
    tb(8,'DES PROPULSION '+label+' TALKBACK',x,79)
toggle(8,'DES PRPLNT ISOL VLV',791,110,['SAFE','FIRE'])
toggle(8,'MASTER ARM',1056,110,['OFF','ON'])
toggle(8,'DES VENT',1141,110,['SAFE','FIRE'])
toggle(8,'ASC He SEL',1224,110,['TANK 1','BOTH','TANK 2'])
tb(8,'LDG GEAR DEPLOY TALKBACK',975,155)
toggle(8,'LDG GEAR DEPLOY',975,231,['SAFE','FIRE'])
for label,x in [('RCS',1057),('DES START',1141),('ASCENT',1223)]:toggle(8,'He PRESS '+label,x,231,['SAFE','FIRE'])
toggle(8,'STAGE',974,347,['SAFE','FIRE'])
for label,x in [('SYS A',1057),('SYS B',1141)]:indicator(8,'STAGE SEQ RELAYS '+label,x,348)
toggle(8,'STAGE RELAY',1222,348,['OFF','RESET'])
for label,x,y,positions in [
    ('S-BAND T/R',1455,70,['T/R','OFF','RCV']),('ICS T/R',1571,70,['T/R','OFF','RCV']),
    ('RELAY',1708,70,['RELAY ON','RELAY OFF']),('MODE',1708,163,['VOX','ICS/PTT','PTT']),
    ('AUDIO CONT',1798,163,['NORM','BU']),('VHF A',1455,267,['T/R','OFF','RCV']),
    ('VHF B',1571,267,['T/R','OFF','RCV']),('COAS',1838,367,['OVHD','OFF','FWD'])]:toggle(8,label,x,y,positions)
for label,x,y in [('S-BAND RCV VOLUME',1455,162),('ICS RCV VOLUME',1571,162),('VOX SENS',1708,262),('VHF A VOLUME',1455,370),('VHF B VOLUME',1571,370),('MASTER VOL',1708,370)]:add(8,label,'thumbwheel',x,y)

# Panel 12: LMP audio, communications modes and antenna controls.
for label,x,y,positions in [
    ('AUDIO CONT',163,163,['NORM','BU']),('UPDATA LINK',120,343,['VOICE-BU','OFF','DATA']),
    ('S-BAND T/R',266,70,['T/R','OFF','RCV']),('ICS T/R',382,70,['T/R','OFF','RCV']),
    ('RELAY',492,70,['RELAY ON','RELAY OFF']),('MODE',492,154,['VOX','ICS/PTT','PTT']),
    ('VHF A AUDIO',266,267,['T/R','OFF','RCV']),('VHF B AUDIO',382,267,['T/R','OFF','RCV']),
    ('MODULATE',581,105,['PM','FM']),('S-BAND XMTR/RCVR',663,105,['PRIM','OFF','SEC']),
    ('PWR AMPL',765,105,['PRIM','OFF','SEC']),('FUNCTIONS VOICE',865,105,['VOICE','OFF','DN VOICE BU']),
    ('FUNCTIONS PCM',972,105,['PCM','OFF','KEY']),('FUNCTIONS RANGE',1069,105,['OFF/RESET','TV/CWEA ENABLE']),
    ('VHF A XMTR',682,241,['VOICE/RNG','OFF','VOICE']),('VHF A RCVR',768,241,['ON','OFF']),
    ('VHF B XMTR',846,241,['VOICE','OFF','DATA']),('VHF B RCVR',928,241,['ON','OFF']),
    ('TELEMETRY BIOMED',999,241,['LEFT','OFF','RIGHT']),('TELEMETRY PCM',1077,241,['HI','LO']),
    ('RECORDER',1077,369,['ON','OFF']),('TRACK MODE',1167,234,['AUTO','OFF','SLEW'])]:toggle(12,label,x,y,positions)
for label,x,y in [('S-BAND RCV VOLUME',266,162),('ICS RCV VOLUME',382,162),('VOX SENS',492,263),('VHF A VOLUME',266,369),('VHF B VOLUME',382,369),('MASTER VOL',492,369),('SQUELCH VHF A',768,369),('SQUELCH VHF B',918,369)]:add(12,label,'thumbwheel',x,y)
tb(12,'RECORDER TAPE TALKBACK',999,369)
for label,x,y in [('PITCH',1209,103),('YAW',1354,103),('SIGNAL STRENGTH',1285,247)]:meter(12,label,x,y)
rotary(12,'ANTENNA VHF',1518,135,['AFT','PLSS TEST','FWD','EVA'])
rotary(12,'ANTENNA S-BAND',1518,331,['FWD','AFT','SLEW','LUNAR STAY'])
rotary(12,'ANTENNA PITCH',1209,353,['-75','0','90','255'],notes='Analog control represented by sampled values for the interaction sandbox; continuous range and rate pending table audit.')
rotary(12,'ANTENNA YAW',1368,353,['-75','0','75'],notes='Analog control represented by sampled values for the interaction sandbox; continuous range and rate pending table audit.')

# Panel 14: electrical power selection and battery contactor commands.
meter(14,'VOLTS',183,87);meter(14,'AMPS',183,216)
indicator(14,'BAT FAULT',366,127);indicator(14,'DC BUS FAULT',83,237)
toggle(14,'ED VOLTS',366,237,['BAT A','OFF','BAT B'])
toggle(14,'INVERTER',535,245,['2','1','OFF'])
rotary(14,'POWER/TEMP MON',535,128,['ED/OFF','BAT 1','BAT 2','BAT 3','BAT 4','BAT 5','BAT 6','CDR BUS','SE BUS','AC BUS'])
for battery,x in [(1,693),(2,765),(3,847),(4,916)]:
    owner='SE' if battery<3 else 'CDR'
    toggle(14,f'{owner} BAT {battery} HI VOLTAGE',x,154,['OFF/RESET','ON'])
    toggle(14,f'{owner} BAT {battery} LOW VOLTAGE',x,245,['OFF/RESET','ON'])
    tb(14,f'{owner} BAT {battery} TALKBACK',x,83)
toggle(14,'DES BATS',988,155,['DEAD FACE','CONNECT']);tb(14,'DES BATS TALKBACK',988,83)
for label,x in [('BAT 5 NORMAL SE FEED',1058),('BAT 5 BACK UP CDR FEED',1157),('BAT 6 NORMAL CDR FEED',1241),('BAT 6 BACK UP SE FEED',1319)]:
    toggle(14,label,x,182,['OFF/RESET','ON']);tb(14,label+' TALKBACK',x,120)
toggle(14,'UPLINK SQUELCH',1455,184,['ENABLE','OFF'])

# Detailed-table spot checks resolve ambiguous circular symbols in the artwork.
table_checks={
 'p2_glycol_selector':('7S3',727,'3-57'),
 'p2_glycol_component_caution':('7DS3',727,'3-57'),
 'p2_suit_fan':('7S1',727,'3-57'),
 'p2_suit_fan_component_caution':('7DS1',727,'3-57'),
 'p8_stage_seq_relays_sys_a':('2DS1',762,'3-92'),
 'p8_stage_seq_relays_sys_b':('2DS2',763,'3-93'),
 'p8_s_band_t_r':('15AS1',763,'3-93'),
 'p8_ics_t_r':('15AS3',764,'3-94'),
 'p8_relay':('15AS4',764,'3-94'),
 'p8_mode':('15AS6',764,'3-94'),
 'p8_audio_cont':('15AS5',765,'3-95'),
 'p8_vhf_a':('15AS2',765,'3-95'),
 'p12_updata_link':('13S16',779,'3-109'),
 'p12_s_band_t_r':('15BS1',779,'3-109'),
 'p12_ics_t_r':('15BS3',779,'3-109'),
 'p14_power_temp_mon':('4S15',790,'3-120')}
for c in CONTROLS:
    if c['id'] in table_checks:
        ref,pdf_page,printed_page=table_checks[c['id']]
        c['referenceDesignation']=ref
        c['source']['tablePdfPage']=pdf_page
        c['source']['tablePrintedPage']=printed_page
        c['confidence']='diagram_and_table_crosschecked'

# Versioned source audit additions and corrections. Keep old IDs stable while
# explicitly extending the inventory denominator beyond the original foldout.
def merge_patch(target, patch):
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge_patch(target[key], value)
        else:
            target[key] = value

expansion_path = args.expansion
expansion = json.loads(expansion_path.read_text(encoding='utf-8')) if expansion_path.exists() else {}
CONTROLS.extend(expansion.get('controls', []))
by_id = {c['id']: c for c in CONTROLS}
for control_id, patch in expansion.get('patches', {}).items():
    assert control_id in by_id, f'Unknown off-panel patch ID: {control_id}'
    merge_patch(by_id[control_id], patch)
detail_path = ROOT / 'reference/control-detail-overrides.json'
detail_audit = json.loads(detail_path.read_text(encoding='utf-8-sig')) if detail_path.exists() else {}
for control_id, patch in detail_audit.get('controls', {}).items():
    assert control_id in by_id, f'Unknown detailed-audit control ID: {control_id}'
    merge_patch(by_id[control_id], patch)

panels=[]
sizes={'1':(.42,.78),'2':(.42,.78),'3':(.84,.21),'4':(.32,.25),'5':(.40,.28),'6':(.32,.26),'8':(.75,.17),'11':(.60,.55),'12':(.75,.17),'14':(.75,.14),'16':(.60,.45)}
for k,crop in CROPS['panels'].items():
    panels.append(dict(id=k,label='Panel '+k,width_m=sizes[k][0],height_m=sizes[k][1],dimensionsProvisional=True,
        texture=crop['image'],source=dict(document='lm7-aoh-v1',figure='3-2',printedPage='3-157/3-158',pdfPage=827)))
panels.extend(expansion.get('panels', []))
counts=collections.Counter(c['panel'] for c in CONTROLS)
inventory=dict(schemaVersion=1,title='Aquarius LM-7 - expanded source-audited control inventory',
    coordinateSystem=dict(u='0 left to 1 right',v='0 bottom to 1 top',layoutUnits='normalized panel texture coordinates',worldFrame='Blender X right, Y forward, Z up; metres'),
    scope=dict(status='EXPANDED AUDIT - complete vehicle and measured-geometry gates remain open',auditedFigure='AOH Fig.3-2, PDF page827; Fig.3-1, PDF825; detailed tables and hatch descriptions',
        completeVehicleDenominatorKnown=False,trackedEntries=len(CONTROLS),trackedPerPanel=dict(sorted(counts.items(),key=lambda p:(0,int(p[0])) if p[0].isdigit() else (1,p[0]))),
        exclusions=[
            'Unplacarded or blank caution/warning and DSKY cells without an identified functional control',
            'Unmodeled individual instrument subscales, needles and any remaining unspecified failure indications; the nine source-named power-failure flags are included',
            'Engineering-complete dimensions, linkage geometry, forces, stops and individual stowage closure counts remain unestablished; all 76 handbook package rows have an audited disposition',
            'Wearable/EVA equipment, camera controls and CSM-side interface controls are outside the current cabin-defined inventory scope',
            'Full subsystem coupling and physical validation of the added mechanism proxies'],
        expansionSource='reference/offpanel-controls.json',detailAuditSource='reference/control-detail-overrides.json',
        cabinMechanismImplementation=expansion.get('cabinMechanismImplementation', {}),
        coverageMeaning='Coverage tests can prove binding of these entries only; the complete LM control count is not yet established.'),
    sources=[dict(id='lm7-aoh-v1',title='Apollo Operations Handbook LM 7 and Subsequent Volume1, LMA790-3-LM, 1 February1970',path='D:/apollo-ref/lm-systems/a13-lm-aoh-v1-lm7-subs-300ppi.pdf',url='https://apollojournals.org/afj/ap13fj/pdf-hr/a13-lm-aoh-v1-lm7-subs-300ppi.pdf',figures=['1-7','3-2'])],
    defaultsNote='All default states and sampled analog states are for the interaction sandbox, not Apollo13 activation or power-down conditions.',
    panels=panels,controls=CONTROLS)
inventory['sources'].extend(expansion.get('supplementarySources', []))
ids=[c['id'] for c in CONTROLS]
assert len(ids)==len(set(ids)), ['Duplicate control ID', [k for k,v in collections.Counter(ids).items() if v>1]]
panel_ids={str(p['id']) for p in panels}
def validate_conditions(conditions, owner_id, output_only=False):
    for condition in conditions:
        if 'anyOf' in condition:
            assert condition['anyOf'], f'Empty alternative condition: {owner_id}'
            validate_conditions(condition['anyOf'], owner_id, output_only)
            continue
        if 'breakerId' in condition:
            target=condition['breakerId']
            assert output_only and target in by_id and by_id[target]['type']=='breaker', f'Invalid output power condition: {owner_id}'
            continue
        target=condition.get('controlId')
        assert target in by_id, f'Unknown mechanism condition target: {owner_id}/{target}'
        assert condition.get('allowedPositions') and set(condition['allowedPositions']).issubset(by_id[target]['positions']), f'Invalid required states: {owner_id}/{target}'
        if condition.get('appliesToPositions'):
            assert set(condition['appliesToPositions']).issubset(by_id[owner_id]['positions']), f'Invalid conditional operation states: {owner_id}'
for c in CONTROLS:
    assert c['default'] in c['positions']
    assert all(0<=c['layout'][axis]<=1 for axis in ['u','v']),c
    assert str(c['panel']) in panel_ids, f"Unknown panel: {c['id']}"
    if c['type']=='axis':
        assert len(c['positions'])==3, f"Axis must define endpoint/center/endpoint: {c['id']}"
        assert c['axis']['min']<c['axis']['max'], f"Invalid physical axis range: {c['id']}"
    guard_id=c.get('mechanism',{}).get('guardId')
    if guard_id:
        assert guard_id in by_id and by_id[guard_id]['type']=='guard', f"Invalid guard: {c['id']}"
        assert by_id[guard_id]['protectedControlId']==c['id'], f"Guard must target protected control: {c['id']}"
    required=c.get('mechanism',{}).get('requiredControlPosition')
    if required:
        assert required['id'] in by_id and required['position'] in by_id[required['id']]['positions'], f"Invalid interlock target: {c['id']}"
    validate_conditions(c.get('motionRequires', []), c['id'])
    validate_conditions(c.get('flowRequires', []), c['id'], True)
    validate_conditions(c.get('emissionRequires', []), c['id'], True)
    if c.get('parentAssemblyId'):
        assert c['parentAssemblyId'] in by_id and c['parentAssemblyId']!=c['id'], f"Invalid assembly parent: {c['id']}"
    if c.get('detentRelease'):
        assert set(c['detentRelease'].get('exceptFromPositions',[])).issubset(c['positions']), f"Invalid detent release exemption: {c['id']}"
out=args.output;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(inventory,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(entries=len(CONTROLS),interactive=sum(c['interactive'] for c in CONTROLS),perPanel=dict(counts)),indent=2))
