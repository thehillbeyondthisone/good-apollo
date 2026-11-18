// Reproducible, deliberately qualified component predictions. Observed currents
// and reserves occur only in comparison records, never in a load or duty input.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.resolve(__dirname, '..');
const bytes = p => fs.readFileSync(path.join(root, p));
const read = p => JSON.parse(bytes(p).toString('utf8').replace(/^\uFEFF/, ''));
const hash = p => crypto.createHash('sha256').update(bytes(p)).digest('hex');
const seconds = value => value.split(':').reduce((total, part) => total * 60 + Number(part), 0);
const inventory = read('reference/controls.json');
const electrical = read('reference/electrical.json');
const sequence = read('reference/electrical-powerdown-sequence.json');
const overlay = read('reference/electrical-flight-loads.json');
if (overlay.inventorySha256 !== hash('reference/controls.json') ||
    overlay.electricalDefinitionSha256 !== hash('reference/electrical.json') ||
    overlay.validation.reviewedPrimarySourceHashesVerified !== true)
  throw new Error('Regenerate and review the optional load overlay against current source references.');
const controlsById = new Map(inventory.controls.map(c => [c.id, c]));
const modelSources = ['lm7_design', 'lm8_load_table', 'deep_powerdown_commands'];
const journal = 'https://apollojournals.org/afj/ap13fj/';
const sources = [];
function source(id, role, title, url, locator, qualification) {
  sources.push({id, role, title, url, locator, qualification});
}
source('lm7_design', 'model_input', 'LM-7 and subsequent Operations Handbook, Volume I',
  journal + 'pdf-hr/a13-lm-aoh-v1-lm7-subs-300ppi.pdf',
  'Equipment input-power ledger; EPS Figure 2.5-2; control tables; RCS heater section 2.4.3.4.2',
  'Original LM-7 input watts take precedence over LM-8 values. Protective breaker ratings are not operating loads.');
source('lm8_load_table', 'model_input', 'LM-8 Systems Handbook, HSI-208818',
  'https://www.ibiblio.org/apollo/Documents/HSI-208818.pdf', 'Table 5-III, PDF 63-66, printed 5-7 through 5-10',
  'Explicit cross-vehicle design-power proxy. Its application to LM-7 is an assumption, not established vehicle-specific telemetry. See electrical-flight-loads.json receipts and exclusions.');
source('deep_powerdown_commands', 'model_input', 'Apollo 13 air-to-ground power-down commands',
  journal + '13day4-leaving-moon.html', '079:49:52 through 082:28; machine-readable 13-event guide',
  'Commands/readbacks constrain a partial state. Individual grouped breaker execution times and omitted baseline states remain unknown.');
source('mcc_commands', 'model_input', 'Apollo 13 manual midcourse configuration calls',
  journal + '19day5-themanualcoursecorrection.html',
  '104:32:41 heaters; 104:58:11 AGS activation; 105:17:07 gimbal OFF; 105:17:58 engine arm DES; 105:43:59 power-down; 105:52:40 amplifier breaker',
  'Uses crew and CapCom configuration calls only. The later PAO current report is reserved for comparison. Exact unsaid breaker motion times are not inferred.');
source('battery_switch_commands', 'model_input', 'Apollo 13 Battery 2 isolation and restoration calls',
  journal + '17day5-thumpandsnowflakes.html', '099:52:13-099:55:08 and 101:02:47-101:05:49',
  'Manual contactor/cross-tie commands are replayed. The false warning does not invent an automatic disconnection or a signed transient current.');
source('late_source_commands', 'model_input', 'Mission Operations Report, TELMU',
  journal + 'pdf-hr/a13-mission-ops-report.pdf', 'Appendix G, G-5/G-6, PDF 239/240',
  'Battery 6 online 111:57, Battery 5 online 133:30, Battery 3 removal 139:16; normal rather than backup ascent feed selection remains an explicit assumption.');
source('initial_capacity', 'model_input', 'Apollo 13 Mission Report initial electrical capacity',
  'https://apollojournals.org/alsj/a13/A13_MissionReport.pdf', 'Section 7.2.5, printed 7-6/7-7',
  'Reported 2179 Ah at LM power-up. Exact epoch and individual battery distribution are not established. Proportional allocation is conditional.');
source('charger_input_scenario', 'model_input', 'TELMU charger input and crew charging sequence',
  journal + '21day5-batterycharge.html', 'TELMU G-6 about 8 A; charge/pause/changeover calls recorded in electrical-flight-audit.json',
  'Nominal 8 A is a scenario input during selected documented windows, never a reconstructed waveform or CM charge-restoration model. Other CM demand remains unknown.');
source('final_powerup_commands', 'model_input', 'Apollo 13 late LM reactivation calls',
  journal + '25day6-thelastcoursecorrection.html', '133:22:08 authorization; reactivation about 133:29',
  'Grouped modeled guidance reactivation at the reported start is an assumed schedule; exact per-switch execution history is absent.');
source('obs_coast', 'validation_observation', 'Mission Operations Report electrical hourly summary',
  'https://apollojournals.org/alsj/a13/A13_MissionOpReport.pdf', 'Printed III-32, 096:00 GET',
  'Reported present draw 11.8 A. Resolution alone is not a calibration, timing or total model-uncertainty allowance.');
source('obs_mcc', 'validation_observation', 'Contemporaneous PAO manual midcourse current report',
  journal + '19day5-themanualcoursecorrection.html', 'PAO 106:02-106:03, retrospective during-burn current',
  'Around 25 A during the burn; no calibrated tolerance or complete current-versus-time trace is provided. Not used to select equipment watts or duties.');
source('obs_post_mcc', 'validation_observation', 'Contemporaneous PAO post-midcourse current report',
  journal + '19day5-themanualcoursecorrection.html', 'PAO 106:02-106:03, present powered-down current',
  'Reported 10-12 A after completed power-down. No extra acceptance allowance has been established.');
source('obs_charge', 'validation_observation', 'Mission Operations Report charge-period hourly summary',
  'https://apollojournals.org/alsj/a13/A13_MissionOpReport.pdf', 'Printed III-36, 114:00 GET',
  'Reported total source current 19.2 A; not an LM-equipment-only current to which export can be added.');
source('obs_bat3', 'validation_observation', 'TELMU Battery 3 withdrawal history',
  journal + 'pdf-hr/a13-mission-ops-report.pdf', 'Appendix G-6, PDF 240, 139:16 GET',
  'Reported 394 Ah delivered and less than 1 A immediately before removal. Model current is sampled before the forced disconnection; initial per-battery history remains unknown.');
source('obs_total_reserve', 'validation_observation', 'Apollo 13 Mission Report total reserve endpoint',
  'https://apollojournals.org/alsj/a13/A13_MissionReport.pdf', 'Section 7.2.5, printed 7-7/7-8, LM undocking',
  '410 Ah total remaining. Distinct from 189.6 Ah usable reserve. No acceptance band or source-ledger boundary is inferred.');

// Retain the exact operating gates in the reviewed overlay. Extra evidence
// metadata stays in its source ledger; the runtime manifest is schema-strict.
const loadKeys = ['id', 'label', 'busId', 'breakerIds', 'switchRequirements', 'powerW', 'currentA', 'sourceId', 'qualification'];
const additionalEquipmentLoads = overlay.runtimeLoads.map(row => Object.fromEntries(
  loadKeys.filter(k => row[k] !== undefined).map(k => [k, row[k]])));
for (const load of additionalEquipmentLoads) load.sourceId = {
  'lm8-systems-handbook': 'lm8_load_table', 'lm7-aoh-v1': 'lm7_design'
}[load.sourceId] || load.sourceId;
for (const load of additionalEquipmentLoads) {
  if (!sources.some(s => s.id === load.sourceId && s.role === 'model_input'))
    throw new Error('Unregistered overlay source ' + load.sourceId);
}
const thermalIds = overlay.uncertainDutyLoadIds;
if (!Array.isArray(thermalIds) || !thermalIds.length) throw new Error('Missing explicit thermostat uncertainty scope');
const duty = value => Object.fromEntries(thermalIds.map(id => [id, value]));
const seed = electrical.presets.find(p => p.id === 'sourced_equipment_checkout');
const activation = {...seed.controls};
// Explicit engineering hypotheses, not source-confirmed flown detents.
Object.assign(activation, {p2_suit_fan: '1', p2_glycol_selector: 'PUMP 1', p6_ags_status: 'OPERATE', p1_guid_cont: 'PGNS',
  p11_cb_r03_c08: 'PULLED', p16_cb_r02_c06: 'PUSHED'});
const coast = {...activation};
for (const event of sequence.events) for (const action of event.actions) coast[action.controlId] = action.position;
// Do not let unspecified standby computer selection energize AEA through its
// alternative CDR supply. These explicit choices remain in the assumptions.
Object.assign(coast, {p6_ags_status: 'OFF', p11_cb_r03_c08: 'PULLED', p16_cb_r02_c06: 'PULLED',
  p12_s_band_xmtr_rcvr: 'PRIM', p12_track_mode: 'OFF', p12_vhf_a_rcvr: 'OFF',
  p12_vhf_b_rcvr: 'OFF', p12_updata_link: 'OFF', p12_telemetry_biomed: 'OFF', p2_suit_fan: '1'});
const heaterSelectors = inventory.controls.filter(c => /^p3_rcs_sys_a_b_2_quad_/.test(c.id));
if (heaterSelectors.length !== 4) throw new Error('Expected four quad heater selectors');
const heaters = state => Object.fromEntries(heaterSelectors.map(c => [c.id, state]));
Object.assign(coast, heaters('OFF'));
const mcc = {...coast, ...heaters('AUTO'), p6_ags_status: 'OPERATE', p1_guid_cont: 'AGS',
  p1_eng_arm: 'DES', p3_eng_gmbl: 'OFF',
  p14_inverter: '1', p11_cb_r05_c10: 'PUSHED', p11_cb_r01_c10: 'PUSHED', p11_cb_r01_c12: 'PUSHED',
  p11_cb_r01_c05: 'PUSHED', p16_cb_r02_c06: 'PUSHED', p16_cb_r02_c08: 'PUSHED',
  p16_cb_r02_c10: 'PUSHED', p16_cb_r02_c12: 'PUSHED', p11_cb_r03_c15: 'PUSHED',
  p11_cb_r03_c12: 'PUSHED', p11_cb_r02_c14: 'PUSHED', p11_cb_r02_c19: 'PUSHED',
  p11_cb_r01_c18: 'PULLED', p16_cb_r03_c05: 'PUSHED', p12_pwr_ampl: 'PRIM'};
const unknownLoads = [
  'LM-7 applicability of LM-8 branch design-power values is unconfirmed.',
  'Thermostat demand and thermal history; actual heater switching waveform.',
  'Unkeyed/keyed VHF and S-band ranging, internal instrumentation and lighting mode duty.',
  'RCS coil pulse durations, controller activity, valve transients and other omitted equipment.',
  'LGC/DSKY and IMU operating power, and its overlap with standby heating, are excluded even when activation/reactivation branches are powered.',
  'Inverter idle draw/conversion losses, wiring resistance and unequal source sharing.',
  'Exact initial flown branch/selector state, per-battery capacity and late full reactivation schedule.'
];
const assumptions = [
  'The named sourced-equipment sandbox supplies unspecified baseline states; this is a partial, source-constrained configuration, not a recovered flown checkpoint.',
  'Single suit fan 1 and pump selection are engineering hypotheses where omitted by replay; alternative AEA feed kept open to prevent an invented dual-feed split.',
  'Ideal 30 V high-tap sources and nominal design watts are retained. No historical current sets a residual load or a fitted duty fraction.',
  'Unknown thermal demand is exercised at fixed fractions 0 and 1. These are sensitivity cases, not a confidence interval or a recovered thermostat trace.'
];
const configurations = [];
function config(id, title, controls, thermal, sourceIds) {
  const c = {id, title, sourceIds, qualification: 'Conditional component subtotal with explicit thermal and LM-8 transfer assumptions; whole-vehicle current is not established.',
    initialPreset: seed.id, controls, additionalLoadDutyFractions: duty(thermal), assumptions,
    unknownLoads, complete: false};
  for (const [key, value] of Object.entries(controls)) {
    if (!controlsById.has(key) || !controlsById.get(key).positions.includes(value))
      throw new Error(`Unknown configuration command ${key}/${value}`);
  }
  configurations.push(c);
  return c;
}
for (const [suffix, fraction] of [['thermal_open', 0], ['thermal_demand', 1]]) {
  config('activation_' + suffix, 'Activation design-power hypothesis / ' + suffix, activation, fraction, modelSources);
  config('coast_' + suffix, 'Deep power-down / ' + suffix, coast, fraction, modelSources);
  config('manual_mcc_' + suffix, 'Manual midcourse burn configuration / ' + suffix, mcc, fraction, [...modelSources, 'mcc_commands']);
  config('post_mcc_' + suffix, 'Post-midcourse power-down / ' + suffix, coast, fraction, [...modelSources, 'mcc_commands']);
}
const currentComparisons = [];
for (const suffix of ['thermal_open', 'thermal_demand']) for (const [id, prefix, min, max, src] of [
  ['coast_96h', 'coast', 11.8, 11.8, 'obs_coast'],
  ['manual_mcc', 'manual_mcc', 25, 25, 'obs_mcc'],
  ['post_manual_mcc', 'post_mcc', 10, 12, 'obs_post_mcc']
]) currentComparisons.push({id: id + '_' + suffix, configurationId: prefix + '_' + suffix,
  observedMinA: min, observedMaxA: max, additionalToleranceA: null, sourceIds: [src],
  qualification: 'Observation excluded from load selection. Partial component subtotal and unestablished uncertainty prohibit a flight acceptance claim.'});

function event(get, controls, sourceIds, qualification, extra = {}) {
  return {getSeconds: seconds(get), controls, sourceIds, qualification, ...extra};
}
function sample(id, get, metric, sourceId, min, max, extra = {}) {
  return {id, getSeconds: seconds(get), metric, sourceIds: sourceId ? [sourceId] : [],
    observedMin: min, observedMax: max, tolerance: null,
    qualification: 'Conditional replay result. No tolerance is established; missing baseline/duty/switch history precludes historical acceptance.', ...extra};
}
const sharedEvents = [
  event('099:52:13', {p16_cb_r04_c17: 'PULLED'}, ['battery_switch_commands'], 'Crew-confirmed balance cross-tie opening.'),
  event('099:53:42', {p14_se_bat_2_hi_voltage: 'OFF/RESET', p14_se_bat_2_low_voltage: 'OFF/RESET'}, ['battery_switch_commands'], 'Manual Battery 2 removal; the false alarm does not command an automatic trip.'),
  event('099:55:08', {p16_cb_r04_c17: 'PUSHED'}, ['battery_switch_commands'], 'Crew-confirmed balance cross-tie closure.'),
  event('101:02:47', {p16_cb_r04_c17: 'PULLED', p14_se_bat_2_hi_voltage: 'ON'}, ['battery_switch_commands'], 'Battery 2 restoration; high tap is a hypothesis, not recovered voltage history.'),
  event('101:05:49', {p16_cb_r04_c17: 'PUSHED'}, ['battery_switch_commands'], 'Crew-confirmed balance cross-tie closure.'),
  event('104:32:41', {...heaters('AUTO'), p6_ags_status: 'STANDBY', p16_cb_r02_c08: 'PUSHED'}, ['mcc_commands'], 'Heaters reported on by this time; AUTO detent and grouped ASA warm-up start are hypotheses, not exact motion times.'),
  event('104:58:19', mcc, ['mcc_commands'], 'AGS activation acknowledged. Other burn-required branches are grouped here because individual times are absent; no all-interval 25 A load is imposed.'),
  event('105:43:59', {...coast, p16_cb_r03_c05: 'PUSHED'}, ['mcc_commands'], 'Source-authorized postburn power-down grouped at execution acknowledgment; amplifier branch retained until its separate call.'),
  event('105:52:40', {p16_cb_r03_c05: 'PULLED'}, ['mcc_commands'], 'Crew states primary amplifier breaker will be pulled; exact contact-motion time is not established.')
];
// A conservative nominal schedule through documented charge intervals; neither
// the amplitude nor the uncertain stops are reconstructed from endpoint fit.
const chargeEvents = [
  ['112:11:57', 8, 'First positive Battery A meter reading. Constant nominal input between readings is assumed.'],
  ['122:46:47', 0, 'Earliest documented departure to stop charging; exact interruption is within the source window.'],
  ['123:21:32', 8, 'Charging restart confirmed. Constant nominal input is an assumption.'],
  ['125:57:51', 0, 'Start of battery changeover; short unobserved charging gap is represented as zero.'],
  ['126:02:41', 8, 'First Battery B reading. Constant nominal input is an assumption.'],
  ['127:11:09', 0, 'Last positive reading; true shutdown is later within an unresolved window, so this truncates known demand.']
].map(([get, amps, note]) => event(get, {}, ['charger_input_scenario'], note,
  {cmExportSourceBusId: 'CDR_DC', cmExportDemandA: amps}));
const lateEvents = [
  event('111:57:00', {p14_bat_6_normal_cdr_feed: 'ON'}, ['late_source_commands'], 'Battery 6 online per TELMU. Normal feed selection is assumed.'),
  ...chargeEvents,
  event('133:29:00', {...activation, ...heaters('OFF'), p14_bat_6_normal_cdr_feed: 'ON'}, ['final_powerup_commands'], 'Partial modeled reactivation grouped at reported start. This does not reconstruct every late switched load.'),
  event('133:30:00', {p14_bat_5_normal_se_feed: 'ON'}, ['late_source_commands'], 'Battery 5 online per TELMU. Normal feed selection is assumed.'),
  event('139:16:00', {p14_cdr_bat_3_hi_voltage: 'OFF/RESET', p14_cdr_bat_3_low_voltage: 'OFF/RESET'}, ['late_source_commands'], 'Prescribed Battery 3 removal occurs after pre-event current/cumulative-Ah samples.')
];
const qualifications = [
  ...assumptions,
  'Initial 2179 Ah is allocated by rated capacity. Individual remaining/delivered charge and exact capacity epoch are unknown; absolute battery comparisons are conditional.',
  'Equal connected-source sharing is an ideal solver approximation; the reported early CDR:LMP 4:1 split is not reconstructed.',
  'The nominal charger input schedule omits other CM loads and unresolved portions of the charge windows. Export is debited once at the LM source boundary.',
  'Thermal-open and continuous-demand cases are sensitivity cases. Ideal design power does not establish physical lower or upper bounds on mission consumption.',
  '410 Ah total reserve is not the 189.6 Ah usable reserve. No usable-reserve quantity is compared as total capacity.',
  'Activation/reactivation lack quantified LGC/IMU operating loads. Absolute mission endpoints expose an incomplete model, not a recovered battery-discharge history.'
];
const historyCases = [];
function predictionSamples(start, end) {
  const points = [];
  for (let at = Math.ceil(start / 3600) * 3600; at <= end; at += 3600)
    points.push({id: 'prediction_' + at, getSeconds: at, metric: 'totalConsumedAh', sourceIds: [],
      observedMin: null, observedMax: null, tolerance: null,
      qualification: 'Hourly model output only. Per-battery snapshots are conditional predictions, not measured telemetry.'});
  return points;
}
for (const suffix of ['thermal_open', 'thermal_demand']) {
  const earlyEvents = sequence.events.filter(e => e.actions.length).map(e =>
    event(e.get, Object.fromEntries(e.actions.map(a => [a.controlId, a.position])), ['deep_powerdown_commands'],
      e.qualification || 'Source-qualified partial guide command; grouped execution remains approximate.'));
  earlyEvents.push(event('082:30:00', coast, ['deep_powerdown_commands'], 'Source-constrained coast hypothesis applied at approximate completed deep-powerdown epoch.'));
  historyCases.push({id: 'conditional_mission_' + suffix, title: 'Conditional mission battery history / ' + suffix,
    initialConfigurationId: 'activation_' + suffix, startGetSeconds: seconds('057:44:00'), endGetSeconds: seconds('141:30:00'),
    sourceIds: ['initial_capacity', ...modelSources], events: [...earlyEvents, ...sharedEvents, ...lateEvents].sort((a,b) => a.getSeconds-b.getSeconds),
    samples: [
      ...predictionSamples(seconds('057:44:00'), seconds('141:30:00')),
      sample('coast_96h', '096:00:00', 'sourceCurrentA', 'obs_coast', 11.8, 11.8),
      sample('midcourse', '105:18:28', 'sourceCurrentA', 'obs_mcc', 25, 25),
      sample('post_midcourse', '106:03:00', 'sourceCurrentA', 'obs_post_mcc', 10, 12),
      sample('charging', '114:00:00', 'sourceCurrentA', 'obs_charge', 19.2, 19.2),
      sample('battery3_delivered_before_removal', '139:16:00', 'batteryConsumedAh', 'obs_bat3', 394, 394, {batteryId: 'BAT3', beforeEvents: true}),
      sample('battery3_current_before_removal', '139:16:00', 'batteryCurrentA', 'obs_bat3', 0, 1, {batteryId: 'BAT3', beforeEvents: true,
        qualification: 'Measured before forced disconnection. Source says less than 1 A; closed interval comparison is display-only with no acceptance tolerance.'}),
      sample('total_at_jettison', '141:30:00', 'totalRemainingAh', 'obs_total_reserve', 410, 410)
    ], qualifications});
}
historyCases.push({id: 'incremental_coast_to_midcourse', title: 'Incremental Battery 2 and midcourse replay from a sandbox charge state',
  initialConfigurationId: 'coast_thermal_demand', startGetSeconds: seconds('082:30:00'), endGetSeconds: seconds('106:03:00'),
  sourceIds: modelSources, events: sharedEvents,
  samples: [...predictionSamples(seconds('082:30:00'), seconds('106:03:00')),
    sample('incremental_midcourse', '105:18:28', 'sourceCurrentA', 'obs_mcc', 25, 25),
    sample('incremental_post_midcourse', '106:03:00', 'sourceCurrentA', 'obs_post_mcc', 10, 12)],
  qualifications: [...assumptions, 'Battery charge is a fresh sandbox allocation, not a recovered82:30 state. All consumed Ah/Wh are increments since82:30; no absolute394Ah/410Ah comparison is made.']});
const output = {schemaVersion: 1, title: 'Apollo 13 component-current and battery-history validation cases',
  qualification: 'Source-constrained hypotheses and held-out observations. Separate optional LM-8 design-power overlay, explicit thermostat sensitivity and conditional initial histories; full flight validation remains open.',
  inventorySha256: hash('reference/controls.json'), electricalSha256: hash('reference/electrical.json'),
  sources, additionalEquipmentLoads, uncertainDutyLoadIds: thermalIds, configurations, currentComparisons, historyCases};
fs.writeFileSync(path.join(root, 'reference/electrical-flight-configurations.json'), JSON.stringify(output, null, 2) + '\n');
console.log(JSON.stringify({configurations: configurations.length, comparisons: currentComparisons.length,
  histories: historyCases.length, optionalLoads: additionalEquipmentLoads.length,
  sha256: hash('reference/electrical-flight-configurations.json')}));
