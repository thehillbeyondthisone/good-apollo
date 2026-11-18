// Export reviewable comparison tables and per-battery time series from the
// executed model report. This script never changes model inputs.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p));
const report = JSON.parse(read('output/electrical-flight-validation.json'));
const sha = p => crypto.createHash('sha256').update(read(p)).digest('hex');
if (report.manifestSha256 !== sha('reference/electrical-flight-configurations.json'))
  throw new Error('Run flight-validation against the current manifest before exporting.');
const number = value => Number(value).toFixed(3);
const get = value => [Math.floor(value / 3600), Math.floor(value / 60) % 60, value % 60]
  .map((n, i) => String(n).padStart(i ? 2 : 3, '0')).join(':');
const lines = [
  '# Electrical current and battery-history comparison', '',
  'Full electrical flight validation remains OPEN. The figures below are component-model outputs with explicit LM-8 transfer, initial-state and thermal-duty assumptions. No unknown load or duty fraction was fitted to a recorded current or reserve.', '',
  '| Configuration | Predicted source A | Recorded A | Difference from reported midpoint A | Status |',
  '|---|---:|---:|---:|---|'
];
for (const row of report.currentComparisons) {
  const c = row.comparison;
  lines.push(`| ${row.configurationId} | ${number(c.prediction)} | ${c.observedMin === c.observedMax ? number(c.observedMin) : number(c.observedMin) + '-' + number(c.observedMax)} | ${number(c.differenceFromMidpoint)} | ${c.status} |`);
}
lines.push('', 'The thermal-open and continuous-demand cases are sensitivity experiments, not a confidence interval. Values between the extremes are not automatically valid predictions. Source table resolution does not establish an acceptance tolerance.', '',
  '| Battery replay | Source delivered Ah | Remaining total Ah | CM-export input Ah | Conservation error Ah |',
  '|---|---:|---:|---:|---:|');
for (const h of report.historyCases)
  lines.push(`| ${h.id} | ${number(h.sourceConsumedAh)} | ${number(h.totalRemainingAh)} | ${number(h.finalAccounting.cmExport.consumedAh)} | ${h.chargeConservationErrorAh.toExponential(2)} |`);
lines.push('', 'The conditional mission histories use a hypothetical proportional distribution of the reported 2179 Ah at 57:44. The late-start history is an incremental sandbox replay, not an absolute flight checkpoint. Continuous-demand cases can exhaust sources; zero remaining capacity does not reproduce the flown history.', '',
  '| History and target | GET | Model value | Recorded interval | Phase |',
  '|---|---|---:|---:|---|');
for (const h of report.historyCases) for (const s of h.samples.filter(s => s.comparison.observedMin !== null)) {
  const c = s.comparison;
  lines.push(`| ${h.id}: ${s.id} (${s.metric}) | ${get(s.getSeconds)} | ${number(c.prediction)} | ${c.observedMin === c.observedMax ? number(c.observedMin) : number(c.observedMin) + '-' + number(c.observedMax)} | ${s.eventPhase} |`);
}
lines.push('', 'Battery 3 is sampled before its commanded removal. Its delivered charge is cumulative only within the assumed history. The final 410 Ah total reserve is kept separate from the reported 189.6 Ah usable reserve.', '',
  'Inputs: `reference/electrical-flight-configurations.json` and `reference/electrical-flight-loads.json`. Full per-load contributions, skipped unmodeled commands, source receipts, qualification text and exact fingerprints are in `output/electrical-flight-validation.json`.', '',
  'Hourly and target-time per-battery model outputs are exported to `output/electrical-battery-history.csv`. They are predictions, not a telemetry tape.', '');
fs.writeFileSync(path.join(root, 'output/electrical-flight-summary.md'), lines.join('\n'));
const rows = [['history', 'sample', 'get', 'phase', 'battery', 'connected', 'voltage_V', 'current_A', 'remaining_Ah', 'delivered_since_epoch_Ah', 'delivered_since_epoch_Wh', 'source_current_A', 'source_delivered_since_epoch_Ah', 'cm_export_input_since_epoch_Ah']];
for (const h of report.historyCases) for (const s of h.samples) for (const b of s.batteries)
  rows.push([h.id, s.id, get(s.getSeconds), s.eventPhase, b.id, b.connected, b.voltageV,
    b.currentA, b.remainingAh, b.consumedAh, b.consumedWh, s.accounting.source.currentA,
    s.accounting.source.consumedAh, s.accounting.cmExport.consumedAh]);
const csv = value => /[",\r\n]/.test(String(value)) ? '"' + String(value).replaceAll('"', '""') + '"' : String(value);
fs.writeFileSync(path.join(root, 'output/electrical-battery-history.csv'), rows.map(row => row.map(csv).join(',')).join('\n') + '\n');
console.log(JSON.stringify({summary: 'output/electrical-flight-summary.md', historyRows: rows.length - 1,
  csv: 'output/electrical-battery-history.csv', flightValidationPassed: false}));
