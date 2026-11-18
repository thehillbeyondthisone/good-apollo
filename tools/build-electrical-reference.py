"""Create the first EPS wiring/data scope without changing the frozen control inventory."""
import hashlib,json
from pathlib import Path
R=Path(__file__).resolve().parents[1]
inv=json.loads((R/'reference/controls.json').read_text())
controls={c['id']:c for c in inv['controls']}
def cb(p,r,c): return f'p{p}_cb_r{r:02}_c{c:02}'
ratings11=[
 [2,2,2,2,2,2,2,2,5,5,5,5,2,2,2,2,2,2,2],
 [5,10,10,10,10,5,5,5,2,2,2,2,2,2,2,2,2,2,2],
 [5,5,7.5,5,2,2,3,10,2,7.5,2,2,10,2,20,2,2,2,2],
 [7.5,7.5,7.5,7.5,20,5,5,5,2,2,5,5,5,2,2,2,10,7.5,5,20,5],
 [100,100,30,100,50,5,2,5,2,30,3]]
ratings16=[
 [2,2,5,5,5,10,10,10,10,5,2,3,5,2,2,5],
 [5,20,2,2,2,2,2,10,2,20,7.5,7.5,2,2,2,2,2,5],
 [2,2,5,2,5,5,2,5,2,2,5,5,2,2,20,2,2,2],
 [7.5,7.5,7.5,7.5,2,2,2,2,3,30,2,5,2,5,50,100,30,100,100]]
breakers=[]
for panel,rows in [(11,ratings11),(16,ratings16)]:
 for row,ratings in enumerate(rows,1):
  for col,rating in enumerate(ratings,1):
   ident=cb(panel,row,col);c=controls[ident];label=c['label']
   bus='CDR_DC' if panel==11 else 'LMP_DC'
   if label.startswith('AC BUS A '):bus='AC_A'
   if label.startswith('AC BUS B '):bus='AC_B'
   role='branch'
   if 'BAT FEED TIE' in label:role='battery_feeder'
   elif 'CROSS TIE' in label:role='bus_tie'
   elif 'BUS TIE INV' in label:role='ac_feeder'
   elif 'XLUNAR BUS TIE' in label:role='return_tie'
   breakers.append(dict(controlId=ident,label=label,busId=bus,role=role,ratedCurrentA=rating,
       currentKnown=False,source=dict(document='lm7-aoh-v1',figure='2.5-2',pdfPages=[381,382,383],printedPages=['2.5-5','2.5-6','2.5-6A/2.5-6B']),
       limitation='Rated amperage is not equipment operating draw. Trip is an instantaneous surrogate, not a sourced thermal time-current curve.'))
# Correct positional transcription errors exposed by the complete table audit.
# Each of these ratings agrees between the visually reviewed detailed table and
# the identified breaker on Fig.2.5-2 (PDF381-383). Keep genuine disagreements.
confirmed_rating_corrections={
 cb(11,3,10):2, cb(11,3,11):7.5,
 cb(11,4,18):15, cb(11,4,19):7.5, cb(11,4,20):5, cb(11,4,21):20,
 cb(16,2,6):10, cb(16,2,8):20, cb(16,2,9):7.5, cb(16,2,10):7.5,
 cb(16,2,11):2, cb(16,2,12):3, cb(16,2,13):10,
 cb(16,3,8):2, cb(16,4,6):5, cb(16,4,9):2}
for breaker in breakers:
 ident=breaker['controlId']
 if ident in confirmed_rating_corrections:
  corrected=confirmed_rating_corrections[ident]
  assert controls[ident]['electricalTable']['ratedCurrentA']==corrected,ident
  breaker['ratedCurrentA']=corrected
  breaker['ratingAdjudication']=dict(status='CORRECTED_TRANSCRIPTION',
      referenceDesignation=controls[ident]['referenceDesignation'],
      tablePdfPage=controls[ident]['source']['tablePdfPage'],schematicPdfPages=[381,382,383],
      explanation='Detailed table and visually identified schematic breaker agree; previous positional rating transcription corrected.')
 if ident==cb(16,1,12):
  breaker['ratingSourceConflict']=dict(status='OPEN',schematicRatedCurrentA=3,
      detailedTableRatedCurrentA=2,tablePdfPage=802,schematicPdfPages=[381,382,383],
      selectedSource='Fig.2.5-2 schematic retained pending revision/circuit adjudication')
batteries=[]
for i in range(1,7):
 if i<5:
  owner='se' if i<3 else 'cdr'
  p,r,cols=(16,4,[18,19]) if i<3 else (11,5,[1,2])
  batteries.append(dict(id=f'BAT{i}',stage='descent',capacityAh=400,nominalVoltageV=30,lowTapVoltageV=28,
    normalBusId='LMP_DC' if i<3 else 'CDR_DC',highControlId=f'p14_{owner}_bat_{i}_hi_voltage',lowControlId=f'p14_{owner}_bat_{i}_low_voltage',feedBreakerIds=[cb(p,r,c) for c in cols],
    source=dict(document='lm7-aoh-v1',pdfPage=397,printedPage='2.5-19')))
 else:
  normal='se' if i==5 else 'cdr';backup='cdr' if i==5 else 'se'
  batteries.append(dict(id=f'BAT{i}',stage='ascent',capacityAh=296,nominalVoltageV=30,lowTapVoltageV=30,
    normalBusId='LMP_DC' if i==5 else 'CDR_DC',backupBusId='CDR_DC' if i==5 else 'LMP_DC',normalControlId=f'p14_bat_{i}_normal_{normal}_feed',backupControlId=f'p14_bat_{i}_back_up_{backup}_feed',feedBreakerIds=[],
    source=dict(document='lm7-aoh-v1',pdfPages=[397,399],printedPages=['2.5-19','2.5-21'])))

gates=[]
def group(ids,breaker,extra=None):
 for ident in ids:
  gates.append(dict(controlId=ident,breakerIds=[breaker],switchRequirements=extra or []))
group([k for k in controls if k.startswith('p4_dsky_')],cb(11,4,19))
group([k for k in controls if k.startswith('p6_deda_')],cb(16,2,6),[dict(controlId='p6_ags_status',allowedPositions=['OPERATE'])])
group([k for k in controls if (k.startswith('p1_') and k.endswith('_warning')) or (k.startswith('p2_') and k.endswith('_caution'))],cb(16,2,14))
group(['p14_volts','p14_amps','p14_power_temp_mon'],cb(16,4,8))
group(['p1_mission_timer'],cb(11,2,10));group(['p1_event_timer'],cb(16,1,1))
group(['p1_fdai'],cb(11,2,14));group(['p2_fdai'],cb(16,1,1))
for panel,breaker in [(1,cb(11,2,11)),(2,cb(16,1,2))]:group([f'p{panel}_x_pointer'],breaker)
for g in gates:
 if g['controlId']=='p1_fdai':g['breakerIds'].append(cb(11,2,19))
 if g['controlId']=='p2_fdai':g['breakerIds'].append(cb(11,1,7))

presets=[]
for name,total,description in [
 ('cold_dark',0,'All batteries disconnected; no energized buses.'),
 ('minimum_lifeboat_12a',12,'Aggregate calibration from Mission Report6.2 after second DPS burn; not a complete flown checklist configuration.'),
 ('initial_powerdown_30a',30,'Aggregate calibration from Mission Report6.2 initial powerdown; not a complete flown checklist configuration.'),
 ('late_profile_14_7a',14.7,'Late-mission planning-profile LM solid line126.5..136h; not measured telemetry.'),
 ('electrical_checkout',12,'Powered desktop checkout with branch energization and AC inverter; aggregate draw is a calibration scaffold.')]:
 states={b['controlId']:'PULLED' for b in breakers}
 for b in batteries:
  if b['stage']=='descent':states[b['highControlId']]='OFF/RESET';states[b['lowControlId']]='OFF/RESET'
  else:states[b['normalControlId']]='OFF/RESET';states[b['backupControlId']]='OFF/RESET'
 states['p14_des_bats']='CONNECT';states['p14_inverter']='OFF';states['p14_power_temp_mon']='BAT 1'
 states['p6_ags_status']='OPERATE'
 if total>0:
  for b in batteries[:4]:states[b['highControlId']]='ON'
  for k in [cb(11,5,1),cb(11,5,2),cb(16,4,18),cb(16,4,19),cb(11,5,3),cb(16,4,17),cb(16,4,8),cb(16,2,14),cb(16,2,3),cb(11,4,5),cb(11,4,8),cb(11,4,19),cb(11,4,20),cb(11,4,21),cb(16,2,6)]:states[k]='PUSHED'
 if name=='electrical_checkout':
  states.update({b['controlId']:'PUSHED' for b in breakers});states['p14_inverter']='1'
 presets.append(dict(id=name,description=description,aggregateCurrentA=total,initialTotalRemainingAh=2179 if total else None,controls=states))

data=dict(schemaVersion=1,title='First deterministic EPS scope - partial, aggregate calibrated',inventorySha256=hashlib.sha256((R/'reference/controls.json').read_bytes()).hexdigest(),fixedStepSeconds=.25,
    sources=[dict(id='lm7-aoh-v1',path='D:/apollo-ref/lm-systems/a13-lm-aoh-v1-lm7-subs-300ppi.pdf',pages=[377,379,380,381,382,383,397,399,789,790]),dict(id='mission-report',path='D:/apollo-ref/a13-mission-data/a13-mission-report-197007.pdf',pages=[45,62,63,64]),dict(id='fdlog-current-profile',path='D:/apollo-ref/a13-procedures/09-a13-fdlog-lm-current-profile.pdf',pages=[1,3])],
    modelNotes=['Battery capacities are sourced ratings at specified nominal operating conditions; no electrochemistry or temperature derating.', 'Ideal30V high-tap and28V low-tap outputs are a coarse voltage surrogate, not a discharge curve.', 'Equal connected-source sharing, ideal diodes and ideal inverter; wire resistance and conversion losses absent.', 'Every declared circuit breaker has a logical source bus and rated amperage. Individual operating draws remain unknown.', 'Two aggregate bus loads split total calibrated draw equally; this allocation is an explicit approximation and is not a set of component wattages.', 'Mission Report12A/30A presets are calibration cases, not independent flight validation.', 'Thermal breaker trip curve, detailed ECA protection, reverse current, thermal faults and full CWEA logic remain unmodelled.'],
    batteries=batteries,breakers=breakers,
    ties=[dict(id='balance_loads',breakerIds=[cb(11,5,3),cb(16,4,17)],busA='CDR_DC',busB='LMP_DC',ratedCurrentA=30),dict(id='emergency_cross_bus',breakerIds=[cb(11,5,4),cb(16,4,16)],busA='CDR_DC',busB='LMP_DC',ratedCurrentA=100)],
    inverters=[dict(id='INV1',inputBreakerId=cb(11,5,10),sourceBusId='CDR_DC',selection='1',acABreakerId=cb(11,1,12),acBBreakerId=cb(11,1,10)),dict(id='INV2',inputBreakerId=cb(16,4,10),sourceBusId='LMP_DC',selection='2',acABreakerId=cb(11,1,11),acBBreakerId=cb(11,1,9))],
    loads=[dict(id='aggregate_cdr',busId='CDR_DC',nominalShare=.5,currentModel='preset aggregate; unknown component decomposition'),dict(id='aggregate_lmp',busId='LMP_DC',nominalShare=.5,currentModel='preset aggregate; unknown component decomposition')],
    poweredControls=gates,presets=presets,
    observedConstraints=[dict(id='initial_powerdown',kind='reported operating aggregate',currentA=30,powerW=900,source='Mission Report6.2 PDF45 printed6-1'),dict(id='minimum_powerdown',kind='reported operating aggregate',currentA=12,powerW=360,source='Mission Report6.2 PDF45 printed6-1'),dict(id='remaining_at_undocking',kind='independent total-capacity endpoint',remainingAh=410,source='Mission Report7.2.5 PDF63 printed7-7',proposedToleranceAh=50,toleranceNote='Engineering review tolerance for coarse aggregate model; not a published NASA acceptance tolerance')],
    planningProfile=[dict(getHours=122,currentA=11.9),dict(getHours=126.5,currentA=14.7),dict(getHours=136,currentA=40.7),dict(getHours=142.75,currentA=0)],
    validationGate='OPEN - no full flown load timeline and no independent fullmission agreement demonstrated')
assert len(breakers)==160
for p in presets:
 for k,v in p['controls'].items():
  assert k in controls,(k,'missingcontrol')
  assert v in controls[k]['positions'],(k,v,controls[k]['positions'])
for g in gates:assert g['controlId'] in controls,g
load_evidence_path=R/'reference/electrical-load-evidence.json'
load_evidence=json.loads(load_evidence_path.read_text(encoding='utf-8'))
assert load_evidence['inventorySha256']==data['inventorySha256'],'Equipment evidence uses a different inventory'
equipment_loads=load_evidence['runtimeLoads']
assert len({l['id'] for l in equipment_loads})==len(equipment_loads)
breaker_by_id={b['controlId']:b for b in breakers}
for load in equipment_loads:
 assert load['powerW']>0 and load['sourceId'] and load['qualification'],load
 assert all(breaker_by_id[k]['busId']==load['busId'] for k in load['breakerIds']),load
 for requirement in load['switchRequirements']:
  assert all(v in controls[requirement['controlId']]['positions'] for v in requirement['allowedPositions']),load
equipment_states=dict(next(p for p in presets if p['id']=='electrical_checkout')['controls'])
equipment_states.update({'p12_s_band_xmtr_rcvr':'PRIM','p12_pwr_ampl':'PRIM','ordeal_earth_lunar':'PWR OFF'})
presets.append(dict(id='sourced_equipment_checkout',description='Partial source-valued equipment checkout. Known loads replace aggregate calibration; unknown equipment draw remains excluded. Not a flown configuration.',
 loadModel='sourced_components',aggregateCurrentA=0,initialTotalRemainingAh=2179,controls=equipment_states))
data['equipmentLoads']=equipment_loads
data['equipmentLoadEvidence']=dict(path='reference/electrical-load-evidence.json',sha256=hashlib.sha256(load_evidence_path.read_bytes()).hexdigest(),
 runtimeLoadCount=len(equipment_loads),completeVehicleLoadCoverage=False)
data['title']='Deterministic partial EPS - aggregate calibration and source-valued equipment modes'
data['modelNotes'].append('Sourced-component mode uses only published operating input watts with switch/branch gates. It never adds aggregate calibration; full vehicle load coverage remains incomplete.')
out=R/'reference/electrical.json';out.write_text(json.dumps(data,indent=2)+'\n')
provenance_path=R/'reference/electrical-provenance.json'
if provenance_path.exists():
 provenance=json.loads(provenance_path.read_text(encoding='utf-8'))
 provenance['electricalDefinitionSha256']=hashlib.sha256(out.read_bytes()).hexdigest()
 provenance['frozenControlsSha256']=data['inventorySha256']
 provenance['inventoryEntries']=len(inv['controls'])
 provenance['commandStateModel']='Physical CENTER detents retain separate ECA relay commands; explicit or sourced spring-return inputs restore released without erasing contactor state.'
 provenance_path.write_text(json.dumps(provenance,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(batteries=len(batteries),breakers=len(breakers),poweredControlMappings=len(gates),presets=len(presets))))
