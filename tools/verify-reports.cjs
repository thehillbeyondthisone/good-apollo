// Validate recorded evidence, source/asset agreement and native hashes.
// This consolidates completed tests; it does not rerun the simulations.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.resolve(root, p));
const json = p => JSON.parse(read(p).toString('utf8').replace(/^\uFEFF/, ''));
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const assert = (ok, why) => { if (!ok) throw new Error(why); };

const reportPaths = [
  'output/electrical-core-tests.json', 'reference/interaction-coverage.json',
  'reference/systems-integration.json', 'reference/agc-integration.json',
  'reference/agc-stepped-test.json', 'reference/agc-native-integration.json',
  'reference/checkpoint-integration.json', 'reference/default-backend.json',
  'reference/audio-lifecycle.json', 'reference/xr-input-tests.json',
  'reference/xr-target-tests.json', 'reference/cabin-batching-tests.json',
  'reference/interaction-batched.json',
  'reference/mechanism-runtime-tests.json', 'reference/xr-action-map-tests.json',
  'reference/cabin-mechanisms-integration.json',
  'output/equipment-load-tests.json', 'reference/equipment-load-integration.json',
  'reference/caution-warning-tests.json', 'reference/caution-warning-integration.json',
  'output/electrical-accounting-tests.json', 'output/electrical-sequence-tests.json',
  'reference/powerdown-integration.json',
  'output/electrical-history-tests.json', 'output/electrical-flight-tests.json',
];
const reports = reportPaths.map(file => {
  const data = json(file);
  assert((data.result || data.status) === 'PASS', `Evidence is not passing: ${file}`);
  assert(!data.failures || data.failures.length === 0, `Failures recorded: ${file}`);
  if (Array.isArray(data.checks)) assert(data.checks.every(c => c.passed === true), `A native check failed: ${file}`);
  return {file, checks: Array.isArray(data.checks) ? data.checks.length : data.checks, sha256: hash(read(file))};
});

const inventory = json('reference/controls.json');
const ids = inventory.controls.map(c => c.id);
assert(new Set(ids).size === ids.length, 'Duplicate control IDs');
const inventoryHash = hash(read('reference/controls.json'));
const cabin = json('assets/cabin-build.json');
assert(cabin.inventorySha256 === inventoryHash, 'Blender build uses an older inventory');
const layoutHash = hash(read('assets/mechanism-layout.json'));
assert(cabin.mechanismLayoutSha256 === layoutHash, 'Blender build uses an older mechanism layout');
assert(cabin.unmodeledControlIds.length === 0, 'Declared controls omitted by Blender');
const glb = read('assets/aquarius-cabin.glb');
assert(glb.readUInt32LE(0) === 0x46546c67 && glb.readUInt32LE(4) === 2, 'Invalid glTF binary');
const gltf = JSON.parse(glb.subarray(20, 20 + glb.readUInt32LE(12)).toString('utf8').trim());
for (const id of ids) assert(gltf.nodes.filter(n => n.name === id).length === 1, `Expected one glTF node for ${id}`);
const normalMapped = gltf.meshes.flatMap(mesh => mesh.primitives).filter(primitive => gltf.materials[primitive.material]?.normalTexture);
assert(normalMapped.length > 0 && normalMapped.every(({attributes}) => Object.hasOwn(attributes, 'TEXCOORD_0') && Object.hasOwn(attributes, 'TANGENT')), 'Normal-mapped cabin geometry requires UVs and tangents');
for (const panelId of ['1', '2', '3', '4', '11', '16']) {
  const material = gltf.materials.find(entry => entry.name === `AQ_artwork_${panelId}`);
  assert(material?.normalTexture && material.emissiveTexture, `Missing paint relief or legend backlight on panel ${panelId}`);
}
const eps = json('reference/electrical-provenance.json');
const electricalHash = hash(read('reference/electrical.json'));
assert(eps.frozenControlsSha256 === inventoryHash, 'Electrical inventory pin differs');
assert(eps.electricalDefinitionSha256 === electricalHash, 'Electrical data hash differs');
const electrical = json('reference/electrical.json');
assert(electrical.equipmentLoadEvidence.sha256 === hash(read('reference/electrical-load-evidence.json')), 'Equipment source ledger differs');
assert(electrical.equipmentLoads.length === json('reference/electrical-load-evidence.json').runtimeLoads.length, 'Equipment catalog count differs');
for (const file of ['output/equipment-load-tests.json','reference/equipment-load-integration.json','reference/caution-warning-tests.json','reference/caution-warning-integration.json','output/electrical-accounting-tests.json','output/electrical-sequence-tests.json','reference/powerdown-integration.json']) {
  const report = json(file);
  assert((report.electricalSha256 || report.electricalDefinitionSha256) === electricalHash, `Electrical fingerprint differs: ${file}`);
  assert((report.controlsSha256 || report.inventorySha256 || report.sourceInventorySha256) === inventoryHash, `Inventory fingerprint differs: ${file}`);
}
const powerdown = json('reference/electrical-powerdown-sequence.json');
const powerdownHash = hash(read('reference/electrical-powerdown-sequence.json'));
assert(powerdown.inventorySha256 === inventoryHash && powerdown.completeFlownConfiguration === false && powerdown.independentFlightValidationPassed === false, 'Power-down replay scope or inventory differs');
for (const file of ['output/electrical-sequence-tests.json','reference/powerdown-integration.json']) {
  assert(json(file).sequenceSha256 === powerdownHash, `Power-down sequence fingerprint differs: ${file}`);
}
const accounting = json('output/electrical-accounting-tests.json');
assert(accounting.saveSchemaVersion === 2 && accounting.historicalTransferBoundaryResolved === false && accounting.restoredCmChargeModeled === false, 'Accounting scope was promoted to historical charger validation');
const flightAudit = json('reference/electrical-flight-audit.json');
assert(flightAudit.reportedBudget.independentValidationPassed === false && flightAudit.profileAudit.scenarios.every(s => s.independentValidationPassed === false), 'Source aggregate scenarios were promoted to independent flight validation');
assert(flightAudit.heldOutTargets.componentModelEvaluated === true && flightAudit.heldOutTargets.fullVehicleComponentModelValidated === false && flightAudit.profileAudit.heldOutSpotChecks.acceptanceTolerance === null, 'Missing or overstated component research comparisons');
const flightManifest = json('reference/electrical-flight-configurations.json');
const flightLoads = json('reference/electrical-flight-loads.json');
const flightReport = json('output/electrical-flight-validation.json');
assert(flightLoads.inventorySha256 === inventoryHash && flightLoads.electricalDefinitionSha256 === electricalHash && flightLoads.validation.reviewedPrimarySourceHashesVerified === true, 'Optional flight loads have stale source/reference evidence');
assert(flightReport.manifestSha256 === hash(read('reference/electrical-flight-configurations.json')) && flightReport.inventorySha256 === inventoryHash && flightReport.electricalSha256 === electricalHash, 'Component prediction report uses stale inputs');
assert(json('output/electrical-flight-tests.json').manifestSha256 === flightReport.manifestSha256, 'Flight verification did not execute the current source cases');
assert(flightReport.independentFlightValidationPassed === false && flightReport.completeEquipmentLoadCoverage === false, 'Optional proxy predictions were promoted to full flight validation');
assert(flightReport.configurations.length === flightManifest.configurations.length && flightReport.currentComparisons.length === flightManifest.currentComparisons.length && flightReport.historyCases.length === flightManifest.historyCases.length, 'Component prediction report omits declared cases');
assert(flightManifest.additionalEquipmentLoads.length === flightLoads.runtimeLoads.length && flightReport.additionalEquipmentLoads.length === flightLoads.runtimeLoads.length, 'Optional equipment catalog count differs');
for (const row of flightLoads.runtimeLoads) {
  const input = flightManifest.additionalEquipmentLoads.find(l => l.id === row.id);
  assert(input && input.powerW === row.powerW && input.busId === row.busId && JSON.stringify(input.breakerIds) === JSON.stringify(row.breakerIds) && JSON.stringify(input.switchRequirements) === JSON.stringify(row.switchRequirements), `Proxy power or operating gate differs: ${row.id}`);
}
assert(flightReport.currentComparisons.every(c => c.comparison.withinTolerance === null), 'An unestablished current tolerance was silently accepted');
for (const h of flightReport.historyCases) {
  assert(Math.abs(h.chargeConservationErrorAh) < 1e-6 && Math.abs(h.accountingConservationErrorAh) < 1e-6 && Math.abs(h.accountingConservationErrorWh) < 1e-5, `History is not conserved: ${h.id}`);
  assert(h.samples.filter(s => s.id.startsWith('battery3_')).every(s => s.eventPhase === 'before_events'), 'Battery 3 comparison follows forced withdrawal');
}
const lgcIntegration = json('reference/powerdown-integration.json');
assert(lgcIntegration.lgcPowerCycleModeled === true && lgcIntegration.headsetTested === false, 'Missing offline LGC power-cycle evidence');
const audit = json('reference/control-source-audit.json');
assert(audit.inventorySha256 === inventoryHash, 'Source audit inventory fingerprint differs');
assert(audit.counts.declaredEntries === ids.length && audit.counts.pendingSourceEntries === 0, 'Declared controls lack a source basis');
const coverage = json('reference/interaction-coverage.json');
assert(coverage.inventoryEntries === ids.length && coverage.boundNodes === ids.length, 'Interaction evidence uses a different inventory');
const mechanisms = json('reference/cabin-mechanisms-integration.json');
assert(mechanisms.sourceInventorySha256 === inventoryHash && mechanisms.mechanismLayoutSha256 === layoutHash, 'Mechanism integration uses different inventory or geometry layout');
assert(mechanisms.boundNodes === ids.length && mechanisms.wholeSessionRestore === true, 'Mechanism integration coverage differs');
assert(json('reference/mechanism-runtime-tests.json').sourceInventorySha256 === inventoryHash, 'Mechanism state fixture uses an older inventory');
const native = json('reference/agc-stepped-build.json');
const nativeTest = json('reference/agc-stepped-test.json');
const workspaceBuild = path.join(root, '.cache/agc-power-cycle');
const nativeBuild = fs.existsSync(path.join(workspaceBuild, 'AquariusAgc.dll')) ? workspaceBuild : 'D:/apollo-ref/build/agc';
const dllPath = path.join(nativeBuild, 'AquariusAgc.dll');
assert(hash(fs.readFileSync(dllPath)) === native.dllSha256, 'Native DLL differs from tested build');
assert(native.cpuInstructionBytesUnchanged && native.cpuOriginalTextSha256 === native.cpuExposedTextSha256, 'CPU instruction preservation proof differs');
assert(nativeTest.build.dllSha256 === native.dllSha256 && nativeTest.powerRestartRetainsPhysicalErasable && nativeTest.powerRestartExecutesLm131r1Vector, 'Native restart and retention evidence differs');
const ropePath = path.join(nativeBuild, 'LM131R1/MAIN.agc.bin');
const ropeHash = hash(fs.readFileSync(ropePath));
assert(ropeHash === 'ae4f9e51ac9491c3da6462233936daeffc16277cd302c43a70b8459ebcd6cca5', 'Fixed rope hash differs');
const load = json('reference/lm131r1-prelaunch.json');
assert(load.approvedForLoading === false, 'Unresolved parameter load was unexpectedly approved');

const summary = {
  schemaVersion: 1, checkedUtc: new Date().toISOString(),
  result: 'PASS', mode: 'Recorded-evidence and current-file verification',
  reportCount: reports.length, recordedChecks: reports.reduce((n,r) => n + r.checks, 0), reports,
  inventory: {entries: ids.length, interactive: inventory.controls.filter(c => c.interactive).length, sha256: inventoryHash, gltfNodesVerified: ids.length, glbSha256: hash(glb), mechanismLayoutSha256: layoutHash},
  cabinSurface: {normalMappedPrimitives: normalMapped.length, materialsWithNormalMaps: gltf.materials.filter(material => material.normalTexture).length},
  native: {dllSha256: native.dllSha256, ropeSha256: ropeHash, unchangedCpuInstructions: true, retainedErasablePowerRestart: true},
  electricalMilestone: {result: 'PASS - source loads, warning checkout, power-down replay, LGC restart and conserved export accounting', fullFlightGate: 'OPEN', definitionSha256: electricalHash, equipmentLoads: electrical.equipmentLoads.length, equipmentEvidenceSha256: hash(read('reference/electrical-load-evidence.json')), flightAuditSha256: hash(read('reference/electrical-flight-audit.json')), heldOutSpotChecks: flightAudit.profileAudit.heldOutSpotChecks.comparisons.length, componentPredictionReportSha256: hash(read('output/electrical-flight-validation.json')), optionalResearchLoads: flightLoads.runtimeLoads.length, currentConfigurations: flightReport.configurations.length, conditionalBatteryHistories: flightReport.historyCases.length, powerDownSequenceSha256: powerdownHash, powerDownEvents: powerdown.events.length, powerDownActions: powerdown.events.reduce((n,e) => n+e.actions.length,0), saveSchemaVersion: 2, oldElectricalCheckpointsCompatible: false},
  defaultBackend: json('reference/default-backend.json').defaultBackend,
  desktop: {historicalInventoryEntries: 495, currentBuildCertified: false, measurement: json('reference/desktop-performance.json')},
  cockpitSourceAudit: {file: 'reference/control-source-audit.json', sha256: hash(read('reference/control-source-audit.json')), counts: audit.counts, wholeVehicleGate: audit.result},
  headset: {result: 'DEFERRED_BY_USER', gatePassed: false, current620GeometryTested: false, operatorReview: 'output/xr-operator-review.json', note: 'Initial controls/readability accepted; later missing rays reported. Minimal Touch-only map passes software checks but sustained hardware reliability is unconfirmed. Further headset testing deferred by explicit user request.'},
  steamVrCompositor: fs.existsSync(path.join(root, 'output/steamvr-compositor.json')) ? {file: 'output/steamvr-compositor.json', sha256: hash(read('output/steamvr-compositor.json')), inventoryEntries: 585, inventorySha256: '2de418f4e1ff8057c478b0cc40f64f87f33364717ee43191eb8b72115a6c8fcb', currentBuildCertified: false, measurement: json('output/steamvr-compositor.json')} : null,
  openGates: ['Complete vehicle inventory/mechanisms', 'Full electrical flight-profile validation', 'Flown erasable memory initialization', 'Sensor/engine/trajectory/life-support coupling', 'LGC voltage transient and hardware restart timing', 'Physical headset and manual usability validation'],
};
fs.writeFileSync(path.join(root, 'reference/build-verification.json'), JSON.stringify(summary, null, 2)+'\n');
console.log(`PASS: ${reports.length} reports, ${summary.recordedChecks} recorded checks; ${ids.length} glTF IDs and native/rope hashes agree.`);
