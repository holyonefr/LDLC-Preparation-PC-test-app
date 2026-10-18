const fs = require('fs');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');
const assert = require('assert/strict');
const source = fs.readFileSync(process.env.PREPARATION_APPS_SCRIPT_SOURCE || path.join(__dirname, 'google-apps-script/LDLC_ErrorTelemetry.gs'), 'utf8');

// Values and row indices behave like Sheets; presentation calls are no-ops.
class Sheet {
  constructor(name) { this.name = name; this.data = []; this.rows = 100; this.cols = 40; this.calls = {}; }
  getName() { return this.name; }
  getSheetId() { return this.name === 'Executions' ? 1 : 2; }
  getMaxRows() { return this.rows; }
  getMaxColumns() { return this.cols; }
  getLastRow() { return this.data.length; }
  getLastColumn() { return Math.max(0, ...this.data.map(row => row.length)); }
  insertRowsAfter(index, count) { this.rows += count; }
  insertColumnsAfter(index, count) { this.cols += count; }
  getDataRange() { return this.getRange(1, 1, this.getLastRow(), this.getLastColumn()); }
  getRange(row, col, height = 1, width = 1) {
    assert(row + height - 1 <= this.rows && col + width - 1 <= this.cols, 'Grid capacity must be extended before writing');
    const sheet = this;
    const methods = {
      getValues() { return Array.from({ length: height }, (_, r) => Array.from({ length: width }, (_, c) => sheet.data[row + r - 1]?.[col + c - 1] ?? '')); },
      setValues(values) {
        assert.equal(values.length, height);
        values.forEach((valuesRow, r) => {
          assert.equal(valuesRow.length, width);
          const target = sheet.data[row + r - 1] ||= [];
          valuesRow.forEach((value, c) => { target[col + c - 1] = value; });
        });
        return proxy;
      }
    };
    const proxy = new Proxy(methods, { get: (target, key) => key in target ? target[key] : () => { sheet.calls[key] = (sheet.calls[key] || 0) + 1; return proxy; } });
    return proxy;
  }
  deleteRow(row) { this.data.splice(row - 1, 1); }
  clear() { this.calls.clear = (this.calls.clear || 0) + 1; this.data = []; }
  setFrozenRows() {}
  setRowHeight() {}
  setColumnWidth() {}
  setConditionalFormatRules() {}
  getFilter() { return true; }
  hideColumns() {}
  isColumnHiddenByUser() { return false; }
}
const sheets = new Map();
const properties = new Map();
let locked = false;
const chain = new Proxy({}, { get: (_, key) => key === 'build' ? () => ({}) : () => chain });
const book = {
  getId: () => 'test-book', getUrl: () => 'test-only',
  getSheetByName: name => sheets.get(name),
  insertSheet: name => { const sheet = new Sheet(name); sheets.set(name, sheet); return sheet; }
};
const context = vm.createContext({
  console, Date, JSON, Math, Object, Array, String, Number, RegExp, isNaN,
  SpreadsheetApp: { openById: () => book, newConditionalFormatRule: () => chain },
  PropertiesService: { getScriptProperties: () => ({ getProperty: key => properties.get(key), setProperty: (key, value) => properties.set(key, value) }) },
  LockService: { getScriptLock: () => ({ waitLock: () => { assert(!locked); locked = true; }, releaseLock: () => { assert(locked); locked = false; } }) },
  Utilities: {
    getUuid: () => crypto.randomUUID(), DigestAlgorithm: { SHA_256: 'sha256' },
    computeDigest: (algorithm, text) => [...crypto.createHash(algorithm).update(text).digest()],
    formatDate: date => new Date(date).toISOString().slice(0, 10)
  }
});
vm.runInContext(source + `
globalThis.realUpdateSummary = updateSummarySheet_;
updateSummarySheet_ = function() {};
globalThis.api = { savePayloads_, readObjects_, dashboardRuns_, successRateStats_, runState_,
  maintainRunRows_, dashboardScript_, withLegacyRunDefaults_ };
`, context);
const api = context.api;
const plain = value => JSON.parse(JSON.stringify(value));
const read = () => api.readObjects_(sheets.get('Executions'));
const find = id => read().find(row => row.RunId === id);
const send = (...runs) => api.savePayloads_(runs.map(Run => ({ Run })));
const start = id => ({ RunId: id, Status: 'running', IsFinal: false, ComputerName: 'SAME-PC', ToolVersion: '2.6.0', Sequence: 1, CurrentStep: 'Initialisation', LastMessage: 'Execution demarree' });
send(start('a'));
const began = find('a').Debut;
send({ RunId: 'a', Status: 'running', IsFinal: false, Sequence: 2, CurrentStep: 'Applications', ErrorCount: 1, DurationSeconds: 479 });
assert.equal(find('a').Statut, 'running', 'Errors before finalization must not finish the run');
assert.equal(find('a').Final, 'non');
assert.equal(find('a').Fin, '');
assert.equal(find('a').PC, 'SAME-PC', 'Sparse updates preserve metadata');
assert.equal(find('a').Debut.getTime(), began.getTime());
assert.equal(api.runState_(find('a')), 'info');
send({ RunId: 'a', Status: 'success', IsFinal: true, Sequence: 3, DurationSeconds: 479, ErrorCount: 1 });
assert.equal(find('a').Statut, 'error', 'A real collected error must remain an error');
assert.equal(find('a').DureeSecondes, 479);
assert(find('a').Fin instanceof Date);
send(start('a'));
assert.equal(find('a').Statut, 'error', 'Late startup must not replace terminal state');
assert.equal(read().length, 1);
send({ ...start('b'), Status: 'success', IsFinal: true, Sequence: 2 }, start('b'));
assert.equal(find('b').Statut, 'success', 'Final then old start in a single POST stays final');
send(start('c'), { ...start('c'), IsFinal: true, Status: 'warning', Sequence: 2, WarningCount: 1, WarningDetails: 'PDF non confirme' });
assert.equal(find('c').Statut, 'warning');
assert.equal(find('c').DetailsAvertissements, 'PDF non confirme');
send(start('d'), { RunId: 'd', IsFinal: false, Status: 'running', Sequence: 3, CurrentStep: 'GPU' }, { RunId: 'd', IsFinal: false, Status: 'running', Sequence: 2, CurrentStep: 'OLD' });
assert.equal(find('d').EtapeActuelle, 'GPU', 'Old sequence must not roll back progress');
send({ ...start('stopped'), IsFinal: true, Status: 'stopped', ErrorCount: 1 });
send({ ...start('timeout'), IsFinal: true, Status: 'timeout' });
send({ ...start('other-machine'), ComputerName: 'OTHER-PC' });
assert.equal(read().length, 7, 'Same PC and simultaneous PCs keep their separate RunIds');

const event = { RunId: 'a', Timestamp: '2026-09-24T13:22:00Z', Step: 'Apps', Type: 'Test', Severity: 'error', Message: 'Real failure' };
api.savePayloads_([{ Run: { RunId: 'a', Status: 'error', IsFinal: true, Sequence: 3 }, Events: [event, event] }]);
api.savePayloads_([{ Run: { RunId: 'a', Status: 'error', IsFinal: true, Sequence: 3 }, Events: [event] }]);
assert.equal(api.readObjects_(sheets.get('Erreurs')).length, 1, 'Repeated final POST must not repeat its error at a new receipt time');
api.savePayloads_([{ execution: { id_execution: 'legacy', statut_global: 'success', poste: 'OLD-PC' } }]);
assert.equal(find('legacy').Statut, 'success');
assert.equal(find('legacy').Version, 'legacy');
const legacyWithStart = { ComputerName: 'OLD-PC', StartedAt: '2026-09-24T13:20:45.938Z', Status: 'running' };
const legacyId = api.withLegacyRunDefaults_(legacyWithStart, new Date(), 0).RunId;
assert.equal(api.withLegacyRunDefaults_(legacyWithStart, new Date(), 1).RunId, legacyId);
assert.notEqual(api.withLegacyRunDefaults_({ ...legacyWithStart, StartedAt: '2026-09-24T14:20:45.938Z' }, new Date(), 1).RunId, legacyId);
send(legacyWithStart, { ...legacyWithStart, Status: 'success' });
assert.equal(find(legacyId).Statut, 'success');
send({ ComputerName: 'NO-ID' }, { ComputerName: 'NO-ID' });
assert.equal(read().filter(row => row.PC === 'NO-ID').length, 2, 'No PC-only deduplication');

const sheet = sheets.get('Executions');
const before = sheet.data.length;
sheet.data.push([...sheet.data[1]]);
const audit = api.maintainRunRows_(false, true);
assert.equal(audit.duplicateGroups.length, 1);
assert.equal(sheet.data.length, before + 1, 'Dry run cannot delete anything');
const repair = api.maintainRunRows_(true, false);
assert.equal(repair.removed, 1);
assert.equal(sheet.data.length, before);
assert.equal(api.maintainRunRows_(true, false).removed, 0, 'Maintenance is idempotent');

// Exercise the actual client helpers, stopping before DOM initialization.
const script = api.dashboardScript_();
const helperStart = script.indexOf('  function $(id)');
const helperEnd = script.indexOf('  function durationLabel');
const client = vm.createContext({ Date, console, data: { errors: [] } });
vm.runInContext(script.slice(helperStart, helperEnd) + `
function runDedupeKey(run) { return run.runId ? 'id:' + run.runId : ''; }
globalThis.api = { runState, successStats, dedupeRuns };
`, client);
const displayed = plain(api.dashboardRuns_(read()));
assert.deepEqual(plain(client.api.successStats(displayed)), plain(api.successRateStats_(displayed)), 'Client and server counters must agree');
displayed.forEach(run => assert.equal(client.api.runState(run), api.runState_(run), run.runId));
assert.equal(client.api.dedupeRuns([{ pc: 'same' }, { pc: 'same' }]).length, 2);
const statuses = plain(api.successRateStats_(displayed));
assert.equal(statuses.failed, 1);
assert.equal(statuses.warning, 1);
assert.equal(statuses.interrupted, 1);
assert.equal(statuses.timeout, 1);
assert.equal(statuses.running, 2);
send({ RunId: 'final-running', Status: 'running', IsFinal: true, ErrorCount: 0 });
assert.equal(find('final-running').Statut, 'success', 'Explicit final evidence, not duration, allows completion');
assert.equal(find('final-running').Final, 'oui');
console.log('OK ingestion persistence, repeated/reordered POSTs, legacy, separate PCs/runs, errors, terminal states, dry-run cleanup, client/server parity');

send({ ...start('numeriks-edition'), Source: 'NumeriksPreparationPC', ApplicationSource: 'NUMERIKS_PREPARATION_PC', Edition: 'NUMERIKS', UserName: '' });
send({ RunId: 'numeriks-edition', Source: 'NumeriksPreparationPC', ApplicationSource: 'NUMERIKS_PREPARATION_PC', Edition: 'NUMERIKS', Status: 'success', IsFinal: true, Sequence: 2, ErrorCount: 0 });
assert.equal(find('numeriks-edition').ApplicationSource, 'NUMERIKS_PREPARATION_PC');
assert.equal(api.dashboardRuns_([find('numeriks-edition')])[0].applicationSource, 'NUMERIKS_PREPARATION_PC');
const brandHelpers = vm.createContext({ Date, console });
vm.runInContext(script.slice(helperStart, helperEnd) + 'globalThis.api = { applicationKey, applicationLabel, applicationBadge };', brandHelpers);
assert.equal(brandHelpers.api.applicationKey('NUMERIKS_PREPARATION_PC'), 'NUMERIKS_PREPARATION_PC');
assert.equal(brandHelpers.api.applicationLabel('NUMERIKS_PREPARATION_PC'), "All In App Numerik's");
assert.match(brandHelpers.api.applicationBadge({ applicationSource: 'NUMERIKS_PREPARATION_PC' }), /Numerik&#39;s/);
assert.equal(brandHelpers.api.applicationLabel('LDLC_PREPARATION_PC'), 'All In App LDLC');
console.log('OK LDLC/Numeriks persistent classification and client labels; ADDON preserved.');

module.exports = { api, context, sheets, book, send, find, plain };
