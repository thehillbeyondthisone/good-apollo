// Source-qualified, deliberately partial switching replay. No current targets.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.resolve(__dirname, '..');
const inventoryBytes = fs.readFileSync(path.join(root, 'reference/controls.json'));
const controls = new Map(JSON.parse(inventoryBytes).controls.map(c => [c.id, c]));
const action = (controlId, position) => ({controlId, position});
const cb = (panel, row, column, closed = false) => action(`p${panel}_cb_r${String(row).padStart(2,'0')}_c${String(column).padStart(2,'0')}`, closed ? 'PUSHED' : 'PULLED');
const events = [];
function event(id,get,evidenceKind,title,actions=[],sourceGets=[get],qualification='') {
  const [h,m,s]=get.split(':').map(Number);
  events.push({id,get,getSeconds:h*3600+m*60+s,evidenceKind,title,actions,sourceGets,qualification});
}
event('hold_for_ptc','079:37:48','instruction_only','Hold deep powerdown for PTC',[],['079:37:48'],'Marker only; retain guidance during PTC setup.');
event('amplifier_branch','079:50:10','crew_intent_readback','Remove amplifier branch; retain PRIMARY',[cb(16,3,5),action('p12_pwr_ampl','PRIM')],['079:49:52','079:50:10'],'Readback expresses immediate intent; exact contact motion is unrecorded.');
event('lighting_selectors','079:51:00','crew_state_report','Lighting selectors off',[action('p3_flood_ovhd_fwd','OFF'),action('p3_exterior_ltg','OFF')]);
event('inverter_selector','079:51:28','crew_state_report','Inverter selector off',[action('p14_inverter','OFF')],['079:51:24','079:51:28']);
event('vhf_receiver','079:53:55','crew_execution_report','VHF receiver removed',[cb(11,4,14)],['079:53:41','079:53:55']);
event('inverter_branch','079:54:23','crew_intent_report','Inverter 1 branch removed',[cb(11,5,10)],['079:54:23'],'Immediate intent; exact opening time unrecorded.');
event('atca_pgns','082:03:11','crew_execution_report','TCA and ATCA PGNS branches removed',[...[2,3,4,5].map(c=>cb(11,2,c)),cb(11,3,10)],['082:02:48','082:02:54','082:03:04','082:03:11'],'TCA changes reported at82:02:54; grouped with ATCA completion at the later label.');
event('final_readup','082:06:30','readup_only','Read final configuration; retain IMU standby',[],['082:05:36','082:06:30'],'Future-tense readback is not switch execution.');
const final = [
  ...[1,2,3,4].map(c=>cb(11,4,c)),cb(11,4,9,true),cb(11,4,14),cb(11,4,15),cb(11,4,19),cb(11,4,20,true),cb(11,4,21),cb(11,5,8),
  ...[6,7,8,9].map(c=>cb(16,1,c)),cb(16,1,12),
  ...[1,2,3,4].map(c=>cb(16,2,c,true)),...[5,6,7,8,9,10,11,12,13].map(c=>cb(16,2,c)),...[14,15,16,17,18].map(c=>cb(16,2,c,true)),
  cb(16,3,1),cb(16,3,2,true),cb(16,3,3),cb(16,3,4),cb(16,3,5),cb(16,3,6,true),cb(16,3,7),cb(16,3,8,true),cb(16,3,9),cb(16,3,10),cb(16,3,11),cb(16,3,12),cb(16,3,13),...[14,15,16,17,18].map(c=>cb(16,3,c,true)),
  ...[1,2,3,4].map(c=>cb(16,4,c,true)),cb(16,4,5),cb(16,4,6,true),cb(16,4,7),cb(16,4,8),cb(16,4,9,true),cb(16,4,10),cb(16,4,11,true),cb(16,4,12),...[13,14,15].map(c=>cb(16,4,c,true)),cb(16,4,16),...[17,18,19].map(c=>cb(16,4,c,true))
];
event('final_execution','082:16:37','execution_start_grouped','Execute reviewed final branch changes',final,['082:02:48','082:05:36','082:06:30','082:07:05','082:08:24','082:08:50','082:09:38','082:10:08','082:10:16','082:11:12','082:11:54','082:12:46','082:16:37'],'Grouped at execution start for guided review; individual action order/times are unknown. Only explicitly identified commands included; baseline checklist-only branches omitted.');
event('sealed_heater','082:23:19','crew_acknowledgement','Keep four heater branches closed',[1,2,3,4].map(c=>cb(16,4,c,true)),['082:22:43','082:23:06','082:23:19'],'Quad 1 branch reported sealed closed; replay never opens it.');
event('heater_selectors','082:24:11','crew_execution_report','RCS heater selectors off',[1,2,3,4].map(n=>action(`p3_rcs_sys_a_b_2_quad_${n}`,'OFF')),['082:13:51','082:24:11'],'Crew says panel 4; prior explicit instruction identifies panel 3, matching inventory. Branch closure alone does not energize heaters.');
event('lighting_branches','082:25:03','crew_execution_report','TRACK and FLOOD branches removed',[cb(16,2,1),cb(16,2,2)],['082:24:53','082:25:03']);
event('low_power_summary','082:30:00','approximate_summary_only','TELMU low-power state reached',[],['TELMU G-5'],'Approximate achieved-state anchor; no 12.5 A target is imposed.');
const seen = new Set();
for (const e of events) {
  if(seen.has(e.id)) throw Error('Duplicate event'); seen.add(e.id);
  const ids=new Set();
  for(const a of e.actions) {
    if(ids.has(a.controlId)) throw Error('Duplicate action'); ids.add(a.controlId);
    if(!controls.get(a.controlId)?.positions.includes(a.position)) throw Error(`Invalid ${a.controlId}/${a.position}`);
  }
}
const data={schemaVersion:1,id:'apollo13_partial_flown_powerdown',title:'Apollo 13 source-confirmed powerdown',
  initialPreset:'sourced_equipment_checkout',inventorySha256:crypto.createHash('sha256').update(inventoryBytes).digest('hex'),
  qualification:'Guided partial switching history from a sandbox equipment checkout. GET labels do not advance simulation time. Unknown demand excluded. The stepped CPU responds to the modeled LGC/DSKY branch; no flown guidance state is initialized.',
  completeFlownConfiguration:false,independentFlightValidationPassed:false,
  sources:{transcript:{url:'https://apollojournals.org/afj/ap13fj/13day4-leaving-moon.html',kind:'Contemporaneous air-to-ground transcript; sourceGets identify utterances, not guaranteed switch-motion times.'},telmu:{url:'https://apollojournals.org/afj/ap13fj/pdf-hr/a13-mission-ops-report.pdf',pdfPage:239,printedPage:'G-5'}},
  limitations:['No mission-state, padload, attitude or per-battery history initialization.','Unspecified baseline checklist states retain sandbox values.','Unquantified equipment and heater currents remain unknown; no reserve fit.','Final branch group executes at82:16:37 for review; actual individual execution times are unknown.','Further headset testing deferred by user.'],events};
fs.writeFileSync(path.join(root,'reference/electrical-powerdown-sequence.json'),JSON.stringify(data,null,2)+'\n');
console.log(JSON.stringify({events:events.length,actions:events.reduce((s,e)=>s+e.actions.length,0),completeFlownConfiguration:false,independentFlightValidationPassed:false}));
