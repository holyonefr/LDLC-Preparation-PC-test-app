const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const sourcePath = path.join(root, 'tools', 'google-apps-script', 'LDLC_ErrorTelemetry.gs');
const source = fs.readFileSync(sourcePath, 'utf8');
const exportsSource = `
globalThis.__ldlc = {
  CONFIG, APPLICATION_SOURCE_PC, APPLICATION_SOURCE_NUMERIKS, APPLICATION_SOURCE_ADDON, ERROR_HEADERS, RUN_HEADERS, getIncomingRun_, getIncomingEvents_,
  withLegacyRunDefaults_, runToRow_, eventToRow_, inferredRunStatus_,
  runState_, successRateStats_, applicationSource_, payloadApplicationSource_, buildToolSummary_, dashboardRuns_, deduplicateDashboardRuns_,
  dashboardErrors_, groupDashboardErrors_, displayRunStatus_, dashboardScript_, renderDashboard_, applyHiddenColumns_
};`;

const context = vm.createContext({
  console,
  Date,
  JSON,
  Math,
  Object,
  Array,
  String,
  Number,
  RegExp,
  isNaN,
  Utilities: {
    getUuid: () => 'compat-test-uuid',
    formatDate: (date, timezone, pattern) => {
      const pad = (value) => String(value).padStart(2, '0');
      const d = new Date(date);
      const tokens = {
        yyyy: String(d.getUTCFullYear()),
        MM: pad(d.getUTCMonth() + 1),
        dd: pad(d.getUTCDate()),
        HH: pad(d.getUTCHours()),
        mm: pad(d.getUTCMinutes()),
        ss: pad(d.getUTCSeconds()),
        ww: '23'
      };
      return String(pattern || '').replace(/yyyy|MM|dd|HH|mm|ss|ww/g, (token) => tokens[token] || token);
    }
  }
});

vm.runInContext(source + exportsSource, context, { filename: sourcePath });
const api = context.__ldlc;

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function rowObject(headers, row) {
  return Object.fromEntries(headers.map((header, index) => [header, row[index]]));
}

const receivedAt = new Date('2026-06-04T08:00:00.000Z');
const currentPayload = {
  Run: {
    RunId: 'current-run',
    Source: 'LDLCPreparationPC',
    ApplicationSource: 'LDLC_PREPARATION_PC',
    ToolVersion: '2.0',
    StartedAt: '2026-06-04T07:59:00.000Z',
    FinishedAt: '2026-06-04T08:00:00.000Z',
    Status: 'success',
    ComputerName: 'CURRENT-PC',
    ErrorCount: 0,
    WarningCount: 0,
    CriticalCount: 0,
    EventCount: 0
  },
  Events: []
};

const legacyPayload = {
  execution: {
    id_execution: 'legacy-run',
    outil: 'LDLCPreparationPC',
    version_logiciel: '1.8',
    date_debut: '2026-06-04T07:50:00.000Z',
    date_fin: '2026-06-04T07:55:00.000Z',
    statut_global: 'erreur',
    poste: 'LEGACY-PC',
    nombre_erreurs: 1,
    nombre_avertissements: 0
  },
  erreurs: [{
    id_execution: 'legacy-run',
    horodatage: '2026-06-04T07:54:00.000Z',
    etape: 'Ancienne etape',
    type_erreur: 'Erreur technique',
    message: 'Erreur ancienne compatible',
    gravite: 'critical',
    statut: 'erreur'
  }]
};

const addonPayload = {
  Run: {
    RunId: 'addon-current-run',
    Source: 'Preparation Addon Sport',
    application_source: 'LDLC_PREPARATION_ADDON',
    ToolVersion: '2.0',
    StartedAt: '2026-06-04T07:58:00.000Z',
    FinishedAt: '2026-06-04T08:00:00.000Z',
    Status: 'error',
    ComputerName: 'ADDON-PC',
    ErrorCount: 1
  },
  Events: [{
    RunId: 'addon-current-run',
    Source: 'Preparation Addon Sport',
    application_source: 'LDLC_PREPARATION_ADDON',
    Timestamp: '2026-06-04T07:59:30.000Z',
    Type: 'Erreur technique',
    Message: 'Erreur ADDON isolee',
    Status: 'error'
  }]
};

const legacyAddonPayload = {
  execution: {
    id_execution: 'legacy-addon-run',
    outil: 'Preparation Addon Sport',
    version_logiciel: '1.9',
    date_debut: '2026-06-04T07:45:00.000Z',
    date_fin: '2026-06-04T07:49:00.000Z',
    statut_global: 'success',
    poste: 'LEGACY-ADDON-PC'
  }
};

const currentRun = api.withLegacyRunDefaults_(api.getIncomingRun_(currentPayload), receivedAt, 0);
const currentRow = rowObject(api.RUN_HEADERS, api.runToRow_(currentRun, receivedAt));
assert(currentRow.Version === '2.0', 'La version actuelle doit etre conservee.');
assert(currentRow.ApplicationSource === api.APPLICATION_SOURCE_PC, 'Le payload PC actuel doit rester dans Preparation PC.');
assert(currentRow.Statut === 'success', 'Une execution actuelle reussie doit rester success.');
assert(currentRow.Debut.getTime() === receivedAt.getTime(), 'Le debut doit utiliser l heure serveur, pas l heure client.');
assert(currentRow.Fin.getTime() === receivedAt.getTime(), 'La fin doit utiliser l heure serveur pour un run final.');
assert(currentRow.DerniereMaj.getTime() === receivedAt.getTime(), 'La derniere mise a jour doit utiliser l heure serveur.');
assert(api.runState_(currentRow) === 'success', 'Une execution reussie doit etre classee success.');

const explicitSuccessRow = {
  ...currentRow,
  RunId: 'explicit-success-run',
  Statut: 'Terminé avec succès',
  Avertissements: 0,
  Erreurs: 0,
  Critiques: 0
};
assert(api.runState_(explicitSuccessRow) === 'success', 'Le statut Terminé avec succès doit etre classe en success.');
assert(api.dashboardRuns_([explicitSuccessRow])[0].status === 'success', 'Le statut historique Terminé avec succès doit etre normalise en success dans le dashboard.');

const legacySuccessVariants = ['Terminé', 'Succès', 'success', 'Réussi'];
legacySuccessVariants.forEach((status) => {
  const row = {
    ...currentRow,
    RunId: `legacy-success-${status}`,
    Statut: status,
    Avertissements: 0,
    Erreurs: 0,
    Critiques: 0
  };
  assert(api.runState_(row) === 'success', `Le statut historique ${status} doit rester une reussite.`);
});

const explicitSuccessDashboardRun = {
  runId: 'explicit-success-dashboard-run',
  status: 'Termin\u00e9 avec succ\u00e8s',
  errors: 0,
  criticals: 0,
  warnings: 0,
  isFinal: true
};
assert(api.runState_(explicitSuccessDashboardRun) === 'success', 'Un run dashboard Termine avec succes doit etre classe en success.');
const explicitSuccessStats = api.successRateStats_([explicitSuccessDashboardRun]);
assert(explicitSuccessStats.success === 1, 'Un run dashboard Termine avec succes doit compter comme reussite.');
assert(explicitSuccessStats.rate === 100, 'Un run dashboard Termine avec succes doit produire 100% de reussite.');

const warningOnlyRow = {
  ...currentRow,
  RunId: 'warning-only-run',
  Statut: 'Terminé avec avertissement',
  Avertissements: 3,
  Erreurs: 0,
  Critiques: 0
};
assert(api.runState_(warningOnlyRow) === 'warning', 'Terminé avec avertissement ne doit pas etre classe en reussite.');
const warningOnlyStats = api.successRateStats_([warningOnlyRow]);
assert(warningOnlyStats.success === 0, 'Un avertissement non resolu ne doit pas valider une intervention.');
assert(warningOnlyStats.warning === 1, 'Terminé avec avertissement doit etre compte comme avertissement.');
assert(warningOnlyStats.rate === 0, 'Un avertissement non resolu seul ne doit pas produire une reussite.');

const legacyRun = api.withLegacyRunDefaults_(api.getIncomingRun_(legacyPayload), receivedAt, 0);
const legacyRow = rowObject(api.RUN_HEADERS, api.runToRow_(legacyRun, receivedAt));
const legacyEvents = api.getIncomingEvents_(legacyPayload);
const legacyErrorRow = rowObject(api.ERROR_HEADERS, api.eventToRow_(legacyEvents[0], legacyRun, receivedAt));
assert(legacyRow.RunId === 'legacy-run', 'L identifiant historique doit etre lu.');
assert(legacyRow.Version === '1.8', 'version_logiciel doit alimenter Version.');
assert(legacyRow.PC === 'LEGACY-PC', 'poste doit alimenter PC.');
assert(legacyRow.Statut === 'error', 'statut_global erreur doit etre normalise en error.');
assert(legacyRow.Erreurs === 1, 'nombre_erreurs doit alimenter Erreurs.');
assert(legacyRow.ApplicationSource === api.APPLICATION_SOURCE_PC, 'Un ancien payload sans source applicative doit rester classe PC.');
assert(legacyErrorRow.Message === 'Erreur ancienne compatible', 'Le message historique doit etre conserve.');
assert(legacyErrorRow.Etape === 'Ancienne etape', 'L etape historique doit etre conservee.');
assert(legacyErrorRow.Horodatage.getTime() === receivedAt.getTime(), 'Une erreur doit etre horodatee cote serveur, pas avec l horodatage client.');
assert(api.runState_(legacyRow) === 'error', 'Une ancienne execution en erreur doit etre classee error.');

const addonRun = api.withLegacyRunDefaults_(api.getIncomingRun_(addonPayload), receivedAt, 0);
const addonRow = rowObject(api.RUN_HEADERS, api.runToRow_(addonRun, receivedAt));
const addonEvent = api.getIncomingEvents_(addonPayload)[0];
const addonErrorRow = rowObject(api.ERROR_HEADERS, api.eventToRow_(addonEvent, addonRun, receivedAt));
assert(addonRow.ApplicationSource === api.APPLICATION_SOURCE_ADDON, 'Le payload ADDON actuel doit rester dans Preparation ADDON.');
assert(addonErrorRow.ApplicationSource === api.APPLICATION_SOURCE_ADDON, 'Une erreur ADDON doit rester dans Preparation ADDON.');

const legacyAddonRun = api.withLegacyRunDefaults_(api.getIncomingRun_(legacyAddonPayload), receivedAt, 0);
const legacyAddonRow = rowObject(api.RUN_HEADERS, api.runToRow_(legacyAddonRun, receivedAt));
assert(legacyAddonRow.ApplicationSource === api.APPLICATION_SOURCE_ADDON, 'Une ancienne version ADDON doit etre reconnue par son nom historique.');

const missingOptionalFields = api.runToRow_({ ComputerName: 'OLD-PC' }, receivedAt);
const defaultRow = rowObject(api.RUN_HEADERS, missingOptionalFields);
assert(defaultRow.Version === 'legacy', 'Une version absente doit recevoir la valeur legacy.');
assert(defaultRow.Statut === 'success', 'Un ancien run sans statut ni erreur doit rester visible comme reussite.');
assert(defaultRow.ApplicationSource === api.APPLICATION_SOURCE_PC, 'Un ancien run minimal doit rester classe PC.');

const classifiedRuns = api.dashboardRuns_([currentRow, legacyRow, addonRow, legacyAddonRow]);
assert(classifiedRuns.filter((run) => run.applicationSource === api.APPLICATION_SOURCE_PC).length === 2, 'Les executions PC doivent rester isolees.');
assert(classifiedRuns.filter((run) => run.applicationSource === api.APPLICATION_SOURCE_ADDON).length === 2, 'Les executions ADDON doivent rester isolees.');

const numeriksRun = { ...currentPayload.Run, RunId: 'numeriks-run', Source: 'NumeriksPreparationPC', Edition: 'NUMERIKS', ApplicationSource: 'NUMERIKS_PREPARATION_PC', UserName: '' };
const numeriksRow = rowObject(api.RUN_HEADERS, api.runToRow_(numeriksRun, receivedAt));
assert(numeriksRow.ApplicationSource === api.APPLICATION_SOURCE_NUMERIKS, 'Numeriks doit etre conserve lors de l ingestion.');
const oldNumeriks = { ...currentRow, RunId: 'old-numeriks', ScriptPath: "D:\\Preparation\\Numerik'sPreparationPC.exe" };
assert(api.dashboardRuns_([oldNumeriks])[0].applicationSource === api.APPLICATION_SOURCE_NUMERIKS, 'Un ancien Numeriks peut etre reconnu par son chemin, sans changer la ligne historique.');
assert(api.payloadApplicationSource_({ application_source: 'Numeriks', Source: 'legacy' }, {}) === api.APPLICATION_SOURCE_NUMERIKS, 'Alias ancien Numeriks.');
assert(api.payloadApplicationSource_({ ApplicationSource: api.APPLICATION_SOURCE_ADDON, ScriptPath: oldNumeriks.ScriptPath }, {}) === api.APPLICATION_SOURCE_ADDON, 'ADDON ne doit jamais etre confondu avec Numeriks.');
const editionSummary = api.buildToolSummary_([], [currentRow, numeriksRow, oldNumeriks, addonRow]);
assert(editionSummary.find(row => row.key === api.APPLICATION_SOURCE_PC).runs === 1, 'Statistiques LDLC separees.');
assert(editionSummary.find(row => row.key === api.APPLICATION_SOURCE_NUMERIKS).runs === 2, 'Statistiques Numeriks separees.');
assert(editionSummary.find(row => row.key === api.APPLICATION_SOURCE_ADDON).runs === 1, 'Statistiques ADDON conservees.');

const duplicateStartRow = {
  ...currentRow,
  RunId: 'dedupe-run',
  Statut: 'En cours',
  Fin: '',
  DerniereMaj: '2026-06-04T08:10:00.000Z',
  DernierHeartbeat: '2026-06-04T08:10:00.000Z',
  Progression: 35,
  Final: 'non'
};
const duplicateFinalRow = {
  ...duplicateStartRow,
  Statut: 'success',
  Fin: '2026-06-04T08:15:00.000Z',
  DerniereMaj: '2026-06-04T08:15:00.000Z',
  DernierHeartbeat: '2026-06-04T08:15:00.000Z',
  Progression: 100,
  Final: 'oui'
};
const freshHeartbeatIso = new Date().toISOString();
const stillRunningRow = {
  ...currentRow,
  RunId: 'running-rate-test',
  Statut: 'En cours',
  Fin: '',
  DerniereMaj: freshHeartbeatIso,
  DernierHeartbeat: freshHeartbeatIso,
  Progression: 15,
  Final: 'non'
};
const interruptedRow = {
  ...currentRow,
  RunId: 'interrupted-rate-test',
  Statut: 'Interrompu',
  Fin: '2026-06-04T08:17:00.000Z',
  Erreurs: 0,
  Critiques: 0,
  Avertissements: 0,
  DerniereMaj: '2026-06-04T08:17:00.000Z',
  DernierHeartbeat: '2026-06-04T08:17:00.000Z',
  Progression: 45,
  Final: 'oui'
};
const dedupedRuns = api.dashboardRuns_([duplicateStartRow, duplicateFinalRow, duplicateStartRow]);
assert(dedupedRuns.length === 1, 'Un meme RunId ne doit apparaitre qu une seule fois dans le dashboard.');
assert(dedupedRuns[0].status === 'success', 'La ligne finale doit remplacer la ligne En cours du meme RunId.');
assert(api.runState_(dedupedRuns[0]) === 'success', 'La ligne dedupliquee doit rester classee en reussite.');

const serverStart = new Date('2026-06-04T08:00:00.000Z');
const serverEnd = new Date('2026-06-04T08:15:00.000Z');
const serverStartRow = rowObject(api.RUN_HEADERS, api.runToRow_({
  RunId: 'server-time-run',
  Status: 'En cours',
  IsFinal: false,
  StartedAt: '1999-01-01T00:00:00.000Z',
  LastUpdatedAt: '1999-01-01T00:10:00.000Z',
  LastHeartbeatAt: '1999-01-01T00:10:00.000Z'
}, serverStart));
const serverFinalRow = rowObject(api.RUN_HEADERS, api.runToRow_({
  RunId: 'server-time-run',
  Status: 'success',
  IsFinal: true,
  StartedAt: '1999-01-01T00:00:00.000Z',
  FinishedAt: '1999-01-01T00:45:00.000Z'
}, serverEnd, serverStartRow));
assert(serverStartRow.Debut.getTime() === serverStart.getTime(), 'Le premier POST serveur doit definir le debut.');
assert(serverFinalRow.Debut.getTime() === serverStart.getTime(), 'La mise a jour finale doit conserver le debut serveur initial.');
assert(serverFinalRow.Fin.getTime() === serverEnd.getTime(), 'La fin doit etre l heure serveur de reception finale.');
assert(serverFinalRow.DureeSecondes === 900, 'La duree doit etre calculee avec les heures serveur.');

const rateRuns = api.dashboardRuns_([duplicateStartRow, duplicateFinalRow, stillRunningRow, interruptedRow]);
const rateStats = api.successRateStats_(rateRuns);
assert(rateRuns.length === 3, 'Les doublons RunId ne doivent pas gonfler le nombre d executions.');
assert(rateStats.success === 1, 'La reussite finale doit etre comptee une seule fois.');
assert(rateStats.running === 1, 'Une execution En cours doit rester visible sans entrer dans le taux.');
assert(rateStats.interrupted === 1, 'Une execution interrompue doit etre comptee separement.');
assert(rateStats.eligible === 1, 'Seules les executions terminees reussite/echec doivent entrer dans le taux.');
assert(rateStats.rate === 100, 'Une seule execution terminee reussie doit produire 100% de reussite.');

const noisyPayload = {
  Run: {
    RunId: 'same-run',
    Source: 'LDLCPreparationPC',
    ApplicationSource: 'LDLC_PREPARATION_PC',
    StartedAt: '2026-06-04T08:10:00.000Z',
    Status: 'Termine avec avertissement',
    ComputerName: 'NOISY-PC'
  },
  Events: [
    {
      RunId: 'same-run',
      Timestamp: '2026-06-04T08:11:00.000Z',
      Step: 'Applications par defaut',
      Type: 'Default Apps',
      Message: 'Fenetre Parametres introuvable',
      Status: 'warning'
    },
    {
      RunId: 'same-run',
      Timestamp: '2026-06-04T08:12:00.000Z',
      Step: 'Applications par defaut',
      Type: 'Default Apps',
      Message: 'Fenetre Parametres non active',
      Status: 'warning'
    }
  ]
};
const noisyRun = api.withLegacyRunDefaults_(api.getIncomingRun_(noisyPayload), receivedAt, noisyPayload.Events.length);
const noisyRow = rowObject(api.RUN_HEADERS, api.runToRow_(noisyRun, receivedAt));
const noisyErrorRows = api.getIncomingEvents_(noisyPayload).map((event) => rowObject(api.ERROR_HEADERS, api.eventToRow_(event, noisyRun, receivedAt)));
const groupedErrors = api.groupDashboardErrors_(api.dashboardErrors_(noisyErrorRows), api.dashboardRuns_([noisyRow]));
assert(groupedErrors.length === 0, 'Les avertissements seuls ne doivent plus apparaitre comme alertes dashboard.');

const realErrorPayload = {
  Run: {
    RunId: 'real-error-run',
    Source: 'LDLCPreparationPC',
    ApplicationSource: 'LDLC_PREPARATION_PC',
    StartedAt: '2026-06-04T08:20:00.000Z',
    Status: 'Échec',
    ComputerName: 'ERROR-PC'
  },
  Events: [
    {
      RunId: 'real-error-run',
      Timestamp: '2026-06-04T08:21:00.000Z',
      Step: 'Windows Update',
      Type: 'Windows Update',
      Message: 'Impossible de lancer Windows Update en arriere-plan.',
      Status: 'erreur',
      Severity: 'error'
    }
  ]
};
const realErrorRun = api.withLegacyRunDefaults_(api.getIncomingRun_(realErrorPayload), receivedAt, realErrorPayload.Events.length);
const realErrorRow = rowObject(api.RUN_HEADERS, api.runToRow_(realErrorRun, receivedAt));
const realErrorRows = api.getIncomingEvents_(realErrorPayload).map((event) => rowObject(api.ERROR_HEADERS, api.eventToRow_(event, realErrorRun, receivedAt)));
const groupedRealErrors = api.groupDashboardErrors_(api.dashboardErrors_(realErrorRows), api.dashboardRuns_([realErrorRow]));
assert(groupedRealErrors.length === 1, 'Une vraie erreur doit rester visible dans le dashboard.');
assert(groupedRealErrors[0].issueCount === 1, 'Une vraie erreur doit compter un probleme.');

const livePayload = {
  Run: {
    RunId: 'live-run',
    Source: 'LDLCPreparationPC',
    ApplicationSource: 'LDLC_PREPARATION_PC',
    StartedAt: '2026-06-04T09:00:00.000Z',
    Status: 'En cours',
    ComputerName: 'LIVE-PC',
    CurrentStep: 'Windows Update',
    CompletedSteps: 'Initialisation | Applications',
    LastMessage: 'Recherche Windows Update en cours',
    LastUpdatedAt: new Date().toISOString(),
    LastHeartbeatAt: new Date().toISOString(),
    ProgressPercent: 42,
    IsFinal: false
  }
};
const stalePayload = {
  Run: {
    RunId: 'stale-run',
    Source: 'LDLCPreparationPC',
    ApplicationSource: 'LDLC_PREPARATION_PC',
    StartedAt: '2026-06-04T09:00:00.000Z',
    Status: 'En cours',
    ComputerName: 'STALE-PC',
    CurrentStep: 'Windows Update',
    LastMessage: 'Installation Windows Update en cours',
    LastUpdatedAt: '2020-01-01T00:00:00.000Z',
    LastHeartbeatAt: '2020-01-01T00:00:00.000Z',
    ProgressPercent: 90,
    IsFinal: false
  }
};
const liveReceivedAt = new Date();
const liveRun = api.withLegacyRunDefaults_(api.getIncomingRun_(livePayload), liveReceivedAt, 0);
const liveRow = rowObject(api.RUN_HEADERS, api.runToRow_(liveRun, liveReceivedAt));
const staleRun = api.withLegacyRunDefaults_(api.getIncomingRun_(stalePayload), receivedAt, 0);
const staleRow = rowObject(api.RUN_HEADERS, api.runToRow_(staleRun, new Date('2020-01-01T00:00:00.000Z')));
const liveDashboardRun = api.dashboardRuns_([liveRow]).find((run) => run.runId === 'live-run');
const staleDashboardRun = api.dashboardRuns_([staleRow]).find((run) => run.runId === 'stale-run');
assert(liveRow.EtapeActuelle === 'Windows Update', 'L etape actuelle doit etre ecrite dans la ligne Sheet.');
assert(liveRow.EtapesTerminees === 'Initialisation | Applications', 'Les etapes terminees doivent etre ecrites dans la ligne Sheet.');
assert(liveRow.DernierMessage === 'Recherche Windows Update en cours', 'Le dernier message doit etre ecrit dans la ligne Sheet.');
assert(liveRow.Progression === 42, 'La progression doit etre ecrite dans la ligne Sheet.');
assert(liveRow.Final === 'non', 'Une execution non finale doit etre marquee non finale.');
assert(liveRow.Fin === '', 'Une execution non finale ne doit pas avoir de date de fin.');
assert(liveDashboardRun && liveDashboardRun.status === 'running', 'Une execution non finale recente doit apparaitre en cours.');
assert(staleDashboardRun && staleDashboardRun.status === 'running', 'Une execution non finale sans heartbeat recent doit rester en cours.');
assert(staleDashboardRun && staleDashboardRun.isStale === true, 'Une execution non finale sans heartbeat recent doit etre marquee sans nouvelle.');
assert(api.runState_(staleDashboardRun) === 'info', 'Une execution bloquee sans erreur reelle doit rester informative.');
assert(api.runState_(interruptedRow) === 'info', 'Une execution interrompue sans erreur reelle ne doit pas etre une alerte.');

const legacyFalseTimeoutRow = {
  ...staleRow,
  RunId: 'legacy-false-timeout-run',
  Statut: 'Bloqué ou délai dépassé',
  EtapeActuelle: 'Initialisation',
  DernierMessage: 'Execution demarree',
  Erreurs: 0,
  Avertissements: 0,
  Critiques: 0,
  Final: 'non',
  Fin: ''
};
const legacyFalseTimeoutDashboardRun = api.dashboardRuns_([legacyFalseTimeoutRow]).find((run) => run.runId === 'legacy-false-timeout-run');
assert(legacyFalseTimeoutDashboardRun && legacyFalseTimeoutDashboardRun.status === 'running', 'Une ancienne ligne Initialisation faussement bloquee doit redevenir en cours.');
assert(legacyFalseTimeoutDashboardRun && legacyFalseTimeoutDashboardRun.isFinal === false, 'Une ancienne ligne Initialisation faussement bloquee ne doit pas etre finale.');

const script = api.dashboardScript_();
const html = api.renderDashboard_({ errors: [], runs: [], generatedAt: '', generatedIso: receivedAt.toISOString() }, '');
// Exercise rendered cells: long messages stay available inside a closed disclosure.
const compactNodes = { runsRows: {}, runsBoard: {} };
const compactContext = vm.createContext({
  window: { LDLC_DASHBOARD_DATA: { errors: [], runs: [] } },
  document: { addEventListener() {}, getElementById: (id) => compactNodes[id] },
  console, Date, JSON, Math, Object, Array, String, Number, RegExp, isNaN
});
vm.runInContext(script.replace('})();', 'globalThis.compact = { renderRunsView, runIssueDetailsHtml };})();'), compactContext);
const compactRun = { runId: '', status: 'warning', errors: 1, warnings: 1, lastMessage: '<img onerror=bad>' + 'Long message '.repeat(1000), warningDetails: 'Warning retained', validation: { state: 'blocked', reason: 'Blocked retained' } };
compactContext.compact.renderRunsView([compactRun]);
const compactRow = compactNodes.runsRows.innerHTML;
assert((compactRow.match(/<td /g) || []).length === 12, 'Execution rows must contain twelve cells.');
assert(!html.includes('<th>Dernier message</th>') && !compactRow.includes('data-label="Dernier message"'), 'Last message must not have a table column.');
assert(compactRow.includes('<details class="issue-details">') && !compactRow.includes('<details class="issue-details" open'), 'Execution details must start collapsed.');
assert(compactRow.includes('&lt;img onerror=bad&gt;') && !compactRow.includes('<img'), 'Last message must remain escaped and accessible even without RunId.');
assert(compactRow.includes('Warning retained') && compactRow.includes('Blocked retained'), 'Blocking and warning reasons must remain accessible.');
compactContext.compact.renderRunsView([]);
assert(compactNodes.runsRows.innerHTML.includes('colspan="12"'), 'Empty executions row must span twelve columns.');
assert(script.includes("'DernierMessage'") && script.includes('run.lastMessage'), 'Last message must remain available to CSV export.');

assert(script.includes("['#7fc5a0','#e28a90']"), 'Le graphique succes/erreur doit utiliser un vert et un rouge sobres.');
assert(script.includes("function runPill(run)"), 'Les statuts d execution doivent utiliser la couleur issue du resultat complet.');
assert(script.includes("function dedupeRuns(rows)"), 'Le dashboard HTML doit dedupliquer les executions par RunId.');
assert(script.includes("function successStats(runs)"), 'Le dashboard HTML doit calculer le taux avec les executions terminees.');
assert(script.includes("function successStatusKey(status)"), 'Le dashboard HTML doit partager la detection des statuts de reussite.');
assert(script.includes("success:'Valid\\u00e9'"), 'Une preparation sans probleme doit etre affichee comme validee.');
assert(script.includes("function runDurationLabel(run)"), 'Le dashboard HTML doit afficher une duree totale lisible dans la vue executions.');
assert(html.includes('<th>Temps total</th>'), 'La vue executions doit afficher la colonne Temps total.');
assert(!html.includes('<th>Progression</th>'), 'La vue executions ne doit plus afficher Progression comme colonne visible.');
assert(!html.includes('<th>Etapes terminees</th>') && !html.includes('<th>Étapes terminées</th>'), 'Le dashboard ne doit pas afficher Etapes terminees.');
assert(html.includes('<th>Details</th>'), 'La vue executions doit contenir une colonne Details.');
assert(html.includes('<th>Action</th>'), 'La vue executions doit contenir une colonne Action.');
assert(!script.includes("kpiCard('orange','calendar',selectedDayRuns().length"), 'La carte orange Executions aujourd hui doit etre supprimee.');
assert(script.includes("kpiCard('blue','check',selectedDayRuns().length,'Executions aujourd\\'hui'"), 'La carte bleue doit compter les executions du jour.');
assert(script.includes('function runIssueDetailsHtml(run)'), 'La vue executions doit afficher les erreurs detaillees par RunId.');
assert(script.includes('<span class="toggle-closed">+</span><span class="toggle-open">-</span>'), 'Le detail des erreurs doit utiliser un bouton + puis -.');
assert(script.includes('function deleteRun(runId, button)'), 'La vue executions doit pouvoir supprimer une execution par RunId.');
assert(script.includes('.deleteRunFromDashboard(runId, dashboardDeleteKey)'), 'La suppression HTML doit appeler Apps Script avec la cle dashboard.');
assert(script.includes('function showDashboardMessage(type, message)'), 'La suppression doit afficher un retour visuel clair.');
assert(script.includes('setTimeout(function()') && script.includes('Suppression trop longue'), 'La suppression doit avoir un delai de securite anti-chargement infini.');
assert(script.includes('Suppression réussie'), 'La suppression doit afficher un message de succes.');
assert(script.includes('setDeleteButtonLoading(button, false)'), 'Le bouton supprimer doit etre reactive apres succes ou erreur.');
assert(script.includes('function deleteRunViaDirectRequest(runId, button, reason)'), 'La suppression doit avoir un fallback direct si google.script.run reste bloque.');
assert(script.includes('&action=deleteRun') && script.includes('&confirm=DELETE_RUN'), 'Le fallback direct doit cibler explicitement la suppression par RunId.');
assert(source.includes('generatedDateKey'), 'Le dashboard doit recevoir une cle de date serveur.');
assert(source.includes("periodKey_(now, 'day')"), 'La date du jour doit etre calculee cote Apps Script.');
assert(/\.kpi-row\{[^}]*grid-template-columns:repeat\(4,minmax\(0,1fr\)\)/.test(source), 'La ligne de KPI doit utiliser 4 colonnes sans trou.');
assert(source.includes('function deleteRunFromDashboard(runId, dashboardKey)'), 'Apps Script doit exposer une suppression protegee.');
assert(source.includes('snapshot.ok = true;'), 'Apps Script doit confirmer explicitement la suppression.');
assert(source.includes("confirmation !== 'DELETE_RUN'"), 'La suppression GET doit exiger une confirmation explicite.');
assert(source.includes("deleteRowsByColumnValue_(runSheet, 'RunId', runId)") && source.includes("deleteRowsByColumnValue_(errorSheet, 'RunId', runId)"), 'La suppression doit retirer execution et erreurs par RunId.');
assert(source.includes('Voulez-vous vraiment supprimer cette'), 'Le bouton supprimer doit demander une confirmation.');
assert(html.includes('<meta charset="UTF-8">'), 'Le dashboard doit declarer explicitement UTF-8.');
assert(html.includes('id="dashboardToast"'), 'Le dashboard doit inclure une zone de message visible.');
assert(script.includes("function warningStatusKey(status)"), 'Le dashboard HTML doit exclure les avertissements du taux de reussite.');
assert(script.includes('stats.warning += 1;') && !script.includes('stats.warning += 1;\n        stats.success += 1;'), 'Le dashboard ne doit pas compter un avertissement comme validation.');
assert(script.includes("function selectedDayRuns()"), 'La carte executions aujourd hui doit compter les executions, pas les erreurs.');
assert(!script.includes("Math.round(success / runs.length"), 'Le taux de reussite ne doit pas etre calcule sur toutes les executions, En cours inclus.');
assert(script.includes("application: 'LDLC_PREPARATION_PC'"), 'Le dashboard doit ouvrir Preparation PC par defaut.');
assert(script.includes('function matchesApplication(row)'), 'Les statistiques doivent filtrer la preparation active.');
assert(!script.includes("tool: 'all'"), 'Le dashboard ne doit plus ouvrir une vue melangeant PC et ADDON.');
assert(html.includes('data-application-group="LDLC_PREPARATION_PC"'), 'Le menu Preparation PC doit etre present.');
assert(html.includes('data-application-group="LDLC_PREPARATION_ADDON"'), 'Le menu Preparation ADDON doit etre present.');
assert((html.match(/data-application="LDLC_PREPARATION_PC"/g) || []).length >= 5, 'Le menu PC doit contenir ses sous-sections.');
assert((html.match(/data-application="LDLC_PREPARATION_ADDON"/g) || []).length >= 5, 'Le menu ADDON doit contenir ses sous-sections.');
assert(html.includes('Dashboard Preparation PC'), 'Le titre commun doit etre present.');
assert(html.includes('data-application-group="NUMERIKS_PREPARATION_PC"'), 'Le menu Numeriks doit etre present.');
assert(html.includes('<th>All In App</th><th>Poste</th>'), 'La marque doit etre affichee sans perdre le nom du poste.');
assert(source.includes('font-size:clamp(30px,3vw,44px)'), 'Titre desktop responsive.');
assert(source.includes('.hero-title h1{font-size:36px}'), 'Titre tablette lisible.');
assert(source.includes('.hero-title h1{font-size:30px;letter-spacing:0}'), 'Titre mobile lisible.');
assert(source.includes('text-shadow:none'), 'Le titre ne doit plus avoir de halo lumineux.');
assert(source.includes('.view-panel{display:none}') && source.includes('.view-panel.active{display:block}'), 'Une seule rubrique doit etre visible a la fois.');
assert(!source.includes('--circuit-bg') && !source.includes('--neon-blue'), 'Le fond circuit et les anciennes couches neon doivent etre retires.');
assert(source.includes('box-shadow:none') && source.includes('--green:#7fc5a0'), 'Le theme doit etre mat et conserver les couleurs semantiques.');
assert(source.includes('termineavecsucces'), 'Le dashboard doit reconnaitre Terminé avec succès comme reussite.');
assert(source.includes("status.indexOf('bloque') >= 0 || status.indexOf('delai') >= 0 || status.indexOf('timeout') >= 0) return 'info'"), 'Le dashboard ne doit plus classer bloque/delai/timeout en erreur sans erreurs reelles.');
assert(source.includes('duplicateRowsToDelete'), 'L upsert Sheet doit supprimer les anciennes lignes doublons du meme RunId.');
assert(source.includes('incomingByKey[key] = aligned'), 'L upsert Sheet doit garder le dernier etat recu pour un meme RunId.');
assert(source.includes("appendRowsUniqueByKey_(errorSheet, errorRows"), 'Les erreurs du meme RunId ne doivent pas etre ajoutees plusieurs fois lors d un renvoi.');
assert(source.includes('function appendRowsUniqueByKey_'), 'La fonction de deduplication des erreurs Sheet doit etre presente.');
assert(source.includes("HIDDEN_RUN_HEADERS: ['EtapesTerminees']"), 'EtapesTerminees doit rester une colonne technique masquee.');
assert(source.includes('function applyHiddenColumns_') && source.includes('sheet.hideColumns(column)'), 'Apps Script doit masquer automatiquement les colonnes techniques.');
assert(source.includes('applyHiddenColumns_(sheet, activeHeaders, name)'), 'Le masquage doit etre applique pendant la mise en forme de la feuille.');
assert(source.includes('hiddenRunHeaders: hiddenHeaders_(runSheet, RUN_HEADERS)'), 'Le JSON live doit permettre de verifier les colonnes masquees.');

const hiddenExecutionColumns = [];
api.applyHiddenColumns_({ hideColumns: (column) => hiddenExecutionColumns.push(column) }, api.RUN_HEADERS, api.CONFIG.RUN_SHEET_NAME);
assert(hiddenExecutionColumns.length === 1, 'Une seule colonne technique doit etre masquee dans Executions.');
assert(hiddenExecutionColumns[0] === api.RUN_HEADERS.indexOf('EtapesTerminees') + 1, 'Le masquage doit cibler exactement EtapesTerminees.');
const hiddenErrorColumns = [];
api.applyHiddenColumns_({ hideColumns: (column) => hiddenErrorColumns.push(column) }, api.ERROR_HEADERS, api.CONFIG.ERROR_SHEET_NAME);
assert(hiddenErrorColumns.length === 0, 'Le masquage EtapesTerminees ne doit pas modifier la feuille Erreurs.');

assert(api.CONFIG.SPREADSHEET_ID === '1PtMhZC_7dQi7aw278XPQ1udmV9ol5hrD_G4mdSwXWA0', 'Le Sheet permanent a change.');
assert(api.CONFIG.WEB_APP_URL === 'https://script.google.com/macros/s/AKfycbwYe2r5-y8HeyfLjslbq7wI2BdFH0sj7TLJQSiUyeRdt_z7yytyTKsPQPPcT0HUcAci3g/exec', 'L URL web app permanente a change.');

console.log('OK current payload');
console.log('OK legacy payload');
console.log('OK current and legacy ADDON payloads');
console.log('OK isolated PC and ADDON menus and statistics');
console.log('OK optional defaults');
console.log('OK RunId dedupe and 100 percent success rate with running rows');
console.log('OK unique error rows on repeated payloads');
console.log('OK dashboard colors');
console.log('OK dashboard title sizes');
console.log('OK permanent links');
