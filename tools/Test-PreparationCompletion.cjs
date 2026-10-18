const fs = require('fs');
const assert = require('assert/strict');
const { api, context, sheets, book, send, find, plain } = require('./Test-LDLCTelemetryIngestion.cjs');
const cases = [
  ['fin_normale', { Status:'success', CompletionConfirmed:true }, 'success', 'validated'],
  ['fermeture_apres_fin', { Status:'success', CompletionConfirmed:true }, 'success', 'validated'],
  ['erreur', { Status:'success', CompletionConfirmed:true, ErrorCount:1, BlockingReason:'Google Chrome : code 1603' }, 'error', 'blocked'],
  ['avertissement', { Status:'warning', CompletionConfirmed:true, WarningCount:1, WarningDetails:'Chrome navigateur par defaut non confirme' }, 'warning', 'blocked'],
  ['delai', { Status:'timeout', CompletionConfirmed:true, WarningCount:1, BlockingReason:'Windows Update : delai depasse, 2 mises a jour restantes' }, 'timeout', 'blocked'],
  ['fermeture_anticipee', { Status:'stopped', CompletionConfirmed:false, BlockingReason:'Intervention interrompue a 25%' }, 'stopped', 'blocked'],
  ['fin_non_confirmee', { Status:'success', CompletionConfirmed:false }, 'stopped', 'blocked'],
  ['fin_non_confirmee_numerique', { Status:'success', CompletionConfirmed:0 }, 'stopped', 'blocked'],
  ['fin_non_confirmee_texte', { Status:'success', CompletionConfirmed:'0' }, 'stopped', 'blocked']
];
const checks = [], rows = [];
function check(value, message) { checks.push({ message, passed:!!value }); }
for (const [name, fields, status, validation] of cases) {
  const id = 'completion-' + name;
  send({ RunId:id, Status:'running', IsFinal:false, Sequence:1 });
  send({ RunId:id, IsFinal:true, Sequence:2, CurrentStep:'Verification finale', ...fields });
  const stored = find(id);
  const run = api.dashboardRuns_([stored])[0];
  check(stored.Statut === status, name + ': statut ' + status);
  if ([false,0,'0'].includes(fields.CompletionConfirmed)) {
    check(stored.InterventionTerminee === 'non', name + ': preuve explicite dincompletude conservee');
  }
  check(run.validation?.state === validation, name + ': validation ' + validation);
  if (validation === 'blocked') check(!!run.validation?.reason, name + ': cause lisible');
  const stats = api.successRateStats_([run]);
  check(stats.success === (validation === 'validated' ? 1 : 0), name + ': aucun faux succes dans les statistiques');
  send({ RunId:id, Status:'running', IsFinal:false, Sequence:3 });
  check(find(id).Statut === status, name + ': un ancien demarrage ne remplace pas la fin');
  rows.push({ scenario:name, status:stored.Statut, validation:run.validation || null, successCount:stats.success });
}
// A heartbeat age, 100%, or an idle application is not completion evidence.
send({ RunId:'completion-stale', Status:'running', IsFinal:false, ProgressPercent:100, DurationSeconds:90000 });
const stale = api.dashboardRuns_([find('completion-stale')])[0];
check(stale.status === 'running' && stale.validation?.state === 'pending', 'Pas de validation par age ou progression seule');
// An event error cannot be hidden by inconsistent counters or a later success.
api.savePayloads_([{ Run:{ RunId:'completion-error-event', Status:'success', IsFinal:true, Sequence:1, CompletionConfirmed:true, ErrorCount:0 },
  Events:[{ RunId:'completion-error-event', Severity:'error', Message:'Installation : code 1603', Step:'Chrome' }] }]);
check(find('completion-error-event').Statut === 'error', 'Une erreur detaillee impose le blocage malgre ErrorCount=0');
send({ RunId:'completion-error-event', Status:'success', IsFinal:true, Sequence:2, CompletionConfirmed:true, ErrorCount:0 });
check(find('completion-error-event').Statut === 'error', 'Une fin ulterieure nefface pas une erreur connue du meme RunId');
// Delayed evidence is independent from the sequence/finality of run metadata.
const lateModes = ['stale-run', 'event-only', 'events-only'];
const errorRows = id => api.readObjects_(sheets.get('Erreurs')).filter(row => row.RunId === id);
const stableMetadata = row => {
  const copy = plain(row);
  for (const field of ['Statut', 'Erreurs', 'Critiques', 'CauseBlocage']) delete copy[field];
  return copy;
};
for (const mode of lateModes) {
  const id = 'completion-late-' + mode;
  send({ RunId:id, Status:'success', IsFinal:true, Sequence:5, CompletionConfirmed:true,
    ComputerName:'CURRENT-PC', ToolVersion:'2.6.6', CurrentStep:'Verification finale',
    LastMessage:'Verification finale confirmee', CompletedSteps:'Applications;GPU;Windows Update',
    ProgressPercent:100, DurationSeconds:600, ErrorCount:0, CriticalCount:0 });
  const original = stableMetadata(find(id));
  const event = { RunId:id, Severity:'error', Step:'Chrome', Type:'Installation', Message:'Installation : code 1603' };
  const payload = mode === 'stale-run'
    ? { Run:{ RunId:id, Status:'running', IsFinal:false, Sequence:1, ComputerName:'STALE-PC',
        ToolVersion:'old', CurrentStep:'Initialisation', LastMessage:'Execution demarree' }, Events:[event,event] }
    : mode === 'event-only' ? event : { Events:[event,event] };
  api.savePayloads_([payload]);
  const blocked = api.dashboardRuns_([find(id)])[0];
  check(find(id).Statut === 'error' && blocked.validation?.state === 'blocked', mode + ': erreur tardive bloquante');
  check(find(id).Erreurs === 1 && errorRows(id).length === 1, mode + ': evenement unique compte une seule fois');
  check(blocked.validation?.reason?.includes('Chrome') && blocked.validation?.reason?.includes('1603'), mode + ': cause exacte de levenement');
  check(JSON.stringify(stableMetadata(find(id))) === JSON.stringify(original), mode + ': fin, dates, sequence et metadonnees recentes conservees');
  const afterFirst = plain(find(id));
  api.savePayloads_([payload,payload]);
  check(JSON.stringify(plain(find(id))) === JSON.stringify(afterFirst) && errorRows(id).length === 1, mode + ': renvois idempotents sans nouvelle date');
  const critical = { ...event, Severity:'critical', Message:'Echec critique confirme' };
  api.savePayloads_([{ Events:[event,critical,critical] }]);
  check(find(id).Erreurs === 1 && find(id).Critiques === 1 && errorRows(id).length === 2, mode + ': erreur critique tardive unique');
  const second = { ...event, Step:'GPU', Message:'Pilote indisponible' };
  api.savePayloads_([{ Events:[second,second] }]);
  check(find(id).Erreurs === 2 && find(id).Critiques === 1 && errorRows(id).length === 3, mode + ': total des preuves distinctes entre POSTs');
  send({ RunId:id, Status:'success', IsFinal:true, Sequence:6, CompletionConfirmed:true, ErrorCount:0, CriticalCount:0 });
  check(find(id).Statut === 'error' && find(id).Erreurs === 2 && find(id).Critiques === 1, mode + ': succes suivant nefface pas les preuves');
  rows.push({ scenario:mode, status:find(id).Statut, validation:blocked.validation, errors:find(id).Erreurs, criticals:find(id).Critiques });
}
// An explicit event RunId is never attributed to a different wrapper run.
for (const id of ['completion-envelope','completion-event-target']) {
  send({ RunId:id, Status:'success', IsFinal:true, Sequence:4, CompletionConfirmed:true, ErrorCount:0 });
}
const unrelated = plain(find('completion-envelope'));
api.savePayloads_([{ Run:{ RunId:'completion-envelope', Status:'success', IsFinal:true, Sequence:4 },
  Events:[{ RunId:'completion-event-target', Severity:'error', Step:'Chrome', Message:'Echec cible uniquement' }] }]);
check(JSON.stringify(plain(find('completion-envelope'))) === JSON.stringify(unrelated), 'RunId explicite : aucune contamination du run enveloppe');
check(find('completion-event-target').Statut === 'error' && find('completion-event-target').Erreurs === 1, 'RunId explicite : blocage du run exact');
const runCountBeforeUnlinked = api.readObjects_(sheets.get('Executions')).length;
const beforeUnlinked = plain(find('completion-envelope'));
api.savePayloads_([{ Events:[{ Severity:'error', Step:'Chrome', Message:'Erreur sans RunId' }] }]);
check(api.readObjects_(sheets.get('Executions')).length === runCountBeforeUnlinked, 'RunId absent : aucune intervention inventee');
check(JSON.stringify(plain(find('completion-envelope'))) === JSON.stringify(beforeUnlinked), 'RunId absent : aucun rapprochement implicite');
send({ RunId:'completion-active-event', Status:'running', IsFinal:false, Sequence:2, CurrentStep:'Applications' });
api.savePayloads_([{ Events:[{ RunId:'completion-active-event', Severity:'error', Step:'Chrome', Message:'Erreur pendant traitement' }] }]);
check(find('completion-active-event').Statut === 'running' && find('completion-active-event').Final === 'non' && find('completion-active-event').Fin === '', 'Erreur seule : ne termine pas une intervention active');
check(find('completion-active-event').Erreurs === 1 && api.dashboardRuns_([find('completion-active-event')])[0].validation?.state === 'pending', 'Intervention active : preuve conservee sans validation');
// Repeat the actual summary updater: presentation should not rebuild each POST.
context.realUpdateSummary(book);
const summary = sheets.get('Synthese') || [...sheets.values()].find(s => /synth/i.test(s.name));
assert(summary, 'Summary sheet was actually created');
const before = { ...summary.calls };
context.realUpdateSummary(book);
check((summary.calls.clear || 0) === 0, 'Synthese : aucune destruction complete de feuille pendant le POST');
check((summary.calls.breakApart || 0) === (before.breakApart || 0), 'Synthese : aucune nouvelle fusion/mise en forme au deuxieme envoi');
rows.push({ scenario:'synthese_repetee', clearCalls:summary.calls.clear || 0, repeatedBreakApart:(summary.calls.breakApart || 0)-(before.breakApart || 0) });
if (process.env.PREPARATION_COMPLETION_REPORT) fs.writeFileSync(process.env.PREPARATION_COMPLETION_REPORT, JSON.stringify({ rows, checks }, null, 2));
const failed = checks.filter(c => !c.passed);
failed.forEach(c => console.error('ECHEC : ' + c.message));
assert.equal(failed.length, 0, `${failed.length}/${checks.length} checks failed`);
console.log(`OK Apps Script completion: ${cases.length + lateModes.length + 4} scenarios, ${checks.length} checks, actual ingestion and summary updater; no Google requests.`);
