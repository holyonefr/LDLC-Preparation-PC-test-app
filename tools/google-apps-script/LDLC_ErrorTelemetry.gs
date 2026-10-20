/*
 * LDLC PrepTool telemetry receiver and secured dashboard.
 *
 * Setup:
 * 1. Paste this file into Apps Script.
 * 2. Deploy as a web app.
 * 3. The backing Google Sheet must stay permanent. Keep SPREADSHEET_ID set
 *    to the existing Sheet ID and update the existing web app deployment.
 */

const CONFIG = {
  SPREADSHEET_ID: '1PtMhZC_7dQi7aw278XPQ1udmV9ol5hrD_G4mdSwXWA0',
  SPREADSHEET_PROPERTY_KEY: 'LDLC_SPREADSHEET_ID',
  SPREADSHEET_NAME: 'LDLC PrepTool - Suivi des erreurs',
  ERROR_SHEET_NAME: 'Erreurs',
  RUN_SHEET_NAME: 'Executions',
  SUMMARY_SHEET_NAME: 'Synthese',
  SHEET_LAYOUT_VERSION: '2026-09-30-v1',
  HIDDEN_RUN_HEADERS: ['EtapesTerminees'],
  INGEST_SECRET: 'LDLC-PrepTool-2026-ea2653c3d8f94cad9bbe4a2fa6fe8e18',
  DASHBOARD_PASSWORD: 'LDLC-Dashboard-2026-288d06206918450293ed29d54fefc801',
  WEB_APP_URL: 'https://script.google.com/macros/s/AKfycbwYe2r5-y8HeyfLjslbq7wI2BdFH0sj7TLJQSiUyeRdt_z7yytyTKsPQPPcT0HUcAci3g/exec',
  REQUIRE_GOOGLE_EMAIL: false,
  ALLOWED_DASHBOARD_EMAILS: [
    'personne1@example.com',
    'personne2@example.com'
  ],
  TIMEZONE: 'Europe/Paris'
};

const APPLICATION_SOURCE_PC = 'LDLC_PREPARATION_PC';
const APPLICATION_SOURCE_NUMERIKS = 'NUMERIKS_PREPARATION_PC';
const APPLICATION_SOURCE_ADDON = 'LDLC_PREPARATION_ADDON';

const ERROR_HEADERS = [
  'Horodatage',
  'RunId',
  'Outil',
  'ApplicationSource',
  'Version',
  'PC',
  'Utilisateur',
  'Domaine',
  'NumeroSerie',
  'Fabricant',
  'Modele',
  'OS',
  'VersionOS',
  'FuseauHoraire',
  'Etape',
  'TypeErreur',
  'Message',
  'Details',
  'Statut',
  'Gravite',
  'Tags',
  'ScriptPath',
  'RecuLe'
];

const RUN_HEADERS = [
  'Debut',
  'Fin',
  'RunId',
  'Outil',
  'ApplicationSource',
  'Version',
  'PC',
  'Utilisateur',
  'Domaine',
  'NumeroSerie',
  'Fabricant',
  'Modele',
  'OS',
  'VersionOS',
  'FuseauHoraire',
  'DureeSecondes',
  'Statut',
  'Erreurs',
  'Avertissements',
  'Critiques',
  'Evenements',
  'EtapeActuelle',
  'EtapesTerminees',
  'DernierMessage',
  'DerniereMaj',
  'DernierHeartbeat',
  'Progression',
  'Final',
  'ScriptPath',
  'RecuLe',
  'Sequence',
  'DetailsAvertissements',
  'InterventionTerminee',
  'CauseBlocage'
];

function doPost(e) {
  try {
    const body = parseJsonBody_(e);
    const apiKey = getAny_(body, ['apiKey', 'ingestSecret', 'secret', 'key']);
    if (!body || apiKey !== CONFIG.INGEST_SECRET) {
      return json_({ ok: false, error: 'unauthorized' });
    }

    const action = String(getAny_(body, ['action', 'Action', 'adminAction'], '') || '').toLowerCase();
    if (action === 'auditruns' || action === 'deduplicateruns') {
      const adminKey = getAny_(body, ['adminKey', 'dashboardKey', 'password']);
      if (adminKey !== CONFIG.DASHBOARD_PASSWORD ||
          (action === 'deduplicateruns' && body.confirm !== 'DEDUPLICATE_SAME_RUN_ID')) {
        return json_({ ok: false, error: 'unauthorized_maintenance' });
      }
      return json_(maintainRunRows_(action === 'deduplicateruns', body.includeRows === true));
    }
    if (['reset', 'resettelemetry', 'clear', 'cleartelemetry'].indexOf(action) >= 0) {
      const adminKey = getAny_(body, ['adminKey', 'dashboardKey', 'password']);
      const confirmation = String(getAny_(body, ['confirm', 'confirmation'], '') || '');
      if (adminKey !== CONFIG.DASHBOARD_PASSWORD || confirmation !== 'RESET_LDLC_TELEMETRY') {
        return json_({ ok: false, error: 'unauthorized_reset' });
      }

      const result = resetTelemetryData_();
      return json_({
        ok: true,
        action: 'resetTelemetry',
        deletedErrors: result.deletedErrors,
        deletedRuns: result.deletedRuns,
        spreadsheetId: result.spreadsheetId,
        spreadsheetUrl: result.spreadsheetUrl
      });
    }

    if (['deleterun', 'deleteexecution', 'delete'].indexOf(action) >= 0) {
      const adminKey = getAny_(body, ['adminKey', 'dashboardKey', 'password']);
      const runId = text_(getAny_(body, ['RunId', 'runId', 'executionId', 'idExecution']));
      if (adminKey !== CONFIG.DASHBOARD_PASSWORD || !runId) {
        return json_({ ok: false, error: 'unauthorized_delete' });
      }

      const result = deleteRunData_(runId);
      return json_({
        ok: true,
        action: 'deleteRun',
        runId: runId,
        deletedRuns: result.deletedRuns,
        deletedErrors: result.deletedErrors,
        spreadsheetId: result.spreadsheetId,
        spreadsheetUrl: result.spreadsheetUrl
      });
    }

    const submitted = getAny_(body, ['payloads', 'reports', 'items'], body);
    const payloads = Array.isArray(submitted) ? submitted : [submitted];
    const result = savePayloads_(payloads);
    return json_({ ok: true, payloads: payloads.length, errors: result.errors, runs: result.runs });
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message ? err.message : err) });
  }
}

function doGet(e) {
  const auth = authorizeDashboard_(e);
  if (!auth.ok) {
    return HtmlService.createHtmlOutput(renderLogin_(auth.reason))
      .setTitle('Dashboard Preparation PC - Connexion');
  }

  const action = String(e && e.parameter ? (e.parameter.action || e.parameter.Action || '') : '').toLowerCase();
  if (['deleterun', 'deleteexecution', 'delete'].indexOf(action) >= 0) {
    const runId = text_(e && e.parameter ? (e.parameter.runId || e.parameter.RunId || e.parameter.executionId || e.parameter.idExecution) : '');
    const confirmation = String(e && e.parameter ? (e.parameter.confirm || e.parameter.confirmation || '') : '');
    if (!runId || confirmation !== 'DELETE_RUN') {
      return json_({ ok: false, error: 'delete_confirmation_missing' });
    }

    const result = deleteRunData_(runId);
    if (e && e.parameter && e.parameter.format === 'json') {
      return json_({
        ok: true,
        action: 'deleteRun',
        runId: runId,
        deletedRuns: result.deletedRuns,
        deletedErrors: result.deletedErrors
      });
    }

    return HtmlService.createHtmlOutput(
      '<!doctype html><html><head><meta charset="UTF-8"></head><body>Suppression réussie.</body></html>'
    ).setTitle('Dashboard Preparation PC - Suppression');
  }

  if (e && e.parameter && e.parameter.format === 'json') {
    const data = getDashboardSnapshot();
    const book = getSpreadsheet_();
    data.spreadsheetId = book.getId();
    return json_(data);
  }

  const data = buildDashboardData_();
  data.dashboardDeleteKey = e && e.parameter ? String(e.parameter.key || '') : '';
  return HtmlService.createHtmlOutput(renderDashboard_(data, auth.email))
    .setTitle('Dashboard Preparation PC');
}

function savePayloads_(payloads) {
  const lock = LockService.getScriptLock();
  // Rendre la main avant le timeout HTTP du client; sa file durable retentera.
  lock.waitLock(5000);

  try {
    const book = getSpreadsheet_();
    const errorSheet = ensureSheet_(book, CONFIG.ERROR_SHEET_NAME, ERROR_HEADERS);
    const runSheet = ensureSheet_(book, CONFIG.RUN_SHEET_NAME, RUN_HEADERS);
    const receivedAt = new Date();
    const existingRunRowsById = rowsByKey_(runSheet, 'RunId');
    const errorRows = [];
    const runRows = [];

    payloads.forEach(function(payload, payloadIndex) {
      if (!payload || typeof payload !== 'object') {
        return;
      }

      const rawRun = getIncomingRun_(payload);
      const run = withLegacyRunDefaults_(rawRun, receivedAt, payloadIndex);
      const events = getIncomingEvents_(payload);
      const eventList = Array.isArray(events) ? events : [events];
      if (hasFields_(rawRun)) {
        const runId = text_(getAny_(run, ['RunId', 'executionId', 'idExecution']));
        const existingRun = runId ? existingRunRowsById[runId] : null;
        if (shouldApplyRun_(existingRun, run)) {
          const row = runToRow_(run, receivedAt, existingRun);
          runRows.push(row);
          // Les payloads d'un meme POST peuvent arriver final puis demarrage.
          existingRunRowsById[runId] = objectFromRow_(RUN_HEADERS, row);
        }
      }

      eventList.forEach(function(event) {
        const severity = normalizedKey_(getAny_(event, ['Severity', 'Gravite', 'priority', 'status']));
        const isRealError = severity.indexOf('error') >= 0 || severity.indexOf('erreur') >= 0 ||
          severity.indexOf('critical') >= 0 || severity.indexOf('critique') >= 0 ||
          severity.indexOf('echec') >= 0 || severity.indexOf('échec') >= 0;
        if (hasFields_(event) && isRealError) {
          errorRows.push(eventToRow_(event, run, receivedAt));
        }
      });
    });

    // Une preuve d'erreur reste valable meme si les metadonnees du payload sont
    // anciennes ou absentes. Compter les evenements uniques pendant leur lecture
    // de deduplication evite un second parcours Sheets et les doubles comptages.
    const eventEvidenceByRun = Object.create(null);
    errorRows.forEach(function(row) {
      const runId = text_(row[ERROR_HEADERS.indexOf('RunId')]);
      if (runId) eventEvidenceByRun[runId] = { errors: 0, criticals: 0, reason: '' };
    });
    appendRowsUniqueByKey_(errorSheet, errorRows, ERROR_HEADERS, ['RunId', 'Etape', 'TypeErreur', 'Gravite', 'Message'], function(row, headers) {
      const runId = text_(row[headers.indexOf('RunId')]);
      const evidence = eventEvidenceByRun[runId];
      if (!evidence) return;
      const severity = normalizedKey_(row[headers.indexOf('Gravite')] || row[headers.indexOf('Statut')]);
      if (/error|erreur|echec/.test(severity)) evidence.errors += 1;
      if (/critical|critique/.test(severity)) evidence.criticals += 1;
      if (!evidence.reason) {
        const step = text_(row[headers.indexOf('Etape')]);
        const message = text_(row[headers.indexOf('Message')]);
        if (message) evidence.reason = clip_((step ? step + ' : ' : '') + message, 10000);
      }
    });
    Object.keys(eventEvidenceByRun).forEach(function(runId) {
      const stored = existingRunRowsById[runId];
      if (!stored) return; // Sans run connu ou accepte, ne pas fabriquer de metadonnees.
      const evidence = eventEvidenceByRun[runId];
      const corrected = Object.assign({}, stored);
      corrected.Erreurs = Math.max(number_(stored.Erreurs), evidence.errors);
      corrected.Critiques = Math.max(number_(stored.Critiques), evidence.criticals);
      corrected.CauseBlocage = text_(stored.CauseBlocage) || evidence.reason;
      corrected.Statut = inferredRunStatus_(corrected);
      if (corrected.Erreurs === stored.Erreurs && corrected.Critiques === stored.Critiques &&
          corrected.CauseBlocage === stored.CauseBlocage && corrected.Statut === stored.Statut) return;
      // Copier la ligne conserve Final, Fin, Sequence, dates et toutes les
      // metadonnees recentes ; un evenement tardif ne rouvre jamais le workflow.
      const row = RUN_HEADERS.map(function(header) { return getAny_(corrected, [header], ''); });
      runRows.push(row);
      existingRunRowsById[runId] = corrected;
    });
    upsertRowsByKey_(runSheet, runRows, RUN_HEADERS, 'RunId');
    updateSummarySheet_(book);
    return { errors: errorRows.length, runs: runRows.length };
  } finally {
    lock.releaseLock();
  }
}

function resetTelemetryData_() {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);

  try {
    const book = getSpreadsheet_();
    const errorSheet = ensureSheet_(book, CONFIG.ERROR_SHEET_NAME, ERROR_HEADERS);
    const runSheet = ensureSheet_(book, CONFIG.RUN_SHEET_NAME, RUN_HEADERS);
    const deletedErrors = Math.max(errorSheet.getLastRow() - 1, 0);
    const deletedRuns = Math.max(runSheet.getLastRow() - 1, 0);

    resetDataSheet_(errorSheet, ERROR_HEADERS);
    resetDataSheet_(runSheet, RUN_HEADERS);
    updateSummarySheet_(book);

    return {
      deletedErrors: deletedErrors,
      deletedRuns: deletedRuns,
      spreadsheetId: book.getId(),
      spreadsheetUrl: book.getUrl()
    };
  } finally {
    lock.releaseLock();
  }
}

function deleteRunFromDashboard(runId, dashboardKey) {
  if (dashboardKey !== CONFIG.DASHBOARD_PASSWORD) {
    throw new Error('Suppression refusée : clé dashboard invalide.');
  }
  const cleanRunId = text_(runId);
  if (!cleanRunId) {
    throw new Error('Suppression impossible : RunId manquant.');
  }

  const result = deleteRunData_(cleanRunId);
  const snapshot = getDashboardSnapshot();
  snapshot.ok = true;
  snapshot.deleteResult = {
    runId: cleanRunId,
    deletedRuns: result.deletedRuns,
    deletedErrors: result.deletedErrors,
    message: 'Suppression réussie'
  };
  return snapshot;
}

function deleteRunData_(runId) {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);

  try {
    const book = getSpreadsheet_();
    const errorSheet = ensureSheet_(book, CONFIG.ERROR_SHEET_NAME, ERROR_HEADERS);
    const runSheet = ensureSheet_(book, CONFIG.RUN_SHEET_NAME, RUN_HEADERS);
    const deletedRuns = deleteRowsByColumnValue_(runSheet, 'RunId', runId);
    const deletedErrors = deleteRowsByColumnValue_(errorSheet, 'RunId', runId);
    updateSummarySheet_(book);
    return {
      deletedRuns: deletedRuns,
      deletedErrors: deletedErrors,
      spreadsheetId: book.getId(),
      spreadsheetUrl: book.getUrl()
    };
  } finally {
    lock.releaseLock();
  }
}

function resetDataSheet_(sheet, headers) {
  if (sheet.getMaxColumns() < headers.length) {
    sheet.insertColumnsAfter(sheet.getMaxColumns(), headers.length - sheet.getMaxColumns());
  }

  if (sheet.getMaxRows() < 2) {
    sheet.insertRowsAfter(sheet.getMaxRows(), 2 - sheet.getMaxRows());
  }

  if (sheet.getMaxRows() > 2) {
    sheet.deleteRows(3, sheet.getMaxRows() - 2);
  }

  clearSheetDataValidations_(sheet);
  sheet.clear();
  sheet.getRange(1, 1, 1, headers.length).setValues([headers])
    .setFontWeight('bold')
    .setBackground('#06286b')
    .setFontColor('#ffffff');
  sheet.setFrozenRows(1);
  sheet.autoResizeColumns(1, headers.length);
}

function getIncomingRun_(payload) {
  const nested = getAny_(payload, ['Run', 'Execution', 'ResultatExecution'], {});
  if (hasFields_(nested)) {
    return nested;
  }

  return looksLikeRun_(payload) ? payload : {};
}

function getIncomingEvents_(payload) {
  const nested = getAny_(payload, ['Events', 'Errors', 'Erreurs', 'Incidents'], []);
  if (Array.isArray(nested) && nested.length) {
    return nested;
  }
  if (hasFields_(nested)) {
    return [nested];
  }

  return looksLikeEvent_(payload) ? [payload] : [];
}

function looksLikeRun_(value) {
  return hasAny_(value, [
    'RunId', 'StartedAt', 'FinishedAt', 'DurationSeconds', 'ResultStatus',
    'ErrorCount', 'WarningCount', 'CriticalCount', 'ComputerName', 'ToolVersion',
    'version_logiciel', 'date_debut', 'date_fin', 'statut_global'
  ]);
}

function looksLikeEvent_(value) {
  return hasAny_(value, ['Message', 'Details', 'Severity', 'Type', 'Step', 'Etape', 'Gravite']);
}

function hasFields_(value) {
  return !!value && typeof value === 'object' && Object.keys(value).length > 0;
}

function hasAny_(value, keys) {
  if (!hasFields_(value)) {
    return false;
  }
  const marker = {};
  return getAny_(value, keys, marker) !== marker;
}

function withLegacyRunDefaults_(run, receivedAt, payloadIndex) {
  if (!hasFields_(run)) {
    return {};
  }

  const copy = {};
  Object.keys(run).forEach(function(key) { copy[key] = run[key]; });

  if (!text_(getAny_(copy, ['RunId', 'executionId', 'idExecution']))) {
    const started = text_(getAny_(copy, ['StartedAt', 'Debut', 'dateDebut', 'startTime']));
    const machine = text_(getAny_(copy, ['SerialNumber', 'NumeroSerie', 'serial'])) ||
      text_(getAny_(copy, ['ComputerName', 'PC', 'poste', 'hostname', 'machine']));
    // L'horodatage de debut immuable permet de reconnaitre un ancien renvoi.
    // Sans cette preuve, ne jamais fusionner deux executions d'un meme PC.
    if (machine && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3,7}(Z|[+-]\d{2}:\d{2})$/.test(started)) {
      const identity = JSON.stringify([payloadApplicationSource_(copy, {}), machine, started]);
      const digest = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, identity);
      copy.RunId = 'legacy-' + digest.map(function(b) { return ('0' + ((b + 256) % 256).toString(16)).slice(-2); }).join('');
      return copy;
    }
    let suffix = String(payloadIndex || 0);
    try {
      suffix = Utilities.getUuid();
    } catch (err) {
      // A deterministic fallback is enough for legacy payloads without an ID.
    }
    copy.RunId = 'legacy-' + receivedAt.getTime() + '-' + suffix;
  }

  return copy;
}

function eventToRow_(event, run, receivedAt) {
  return [
    dateValue_(receivedAt),
    text_(getAny_(event, ['RunId', 'executionId', 'idExecution'], getAny_(run, ['RunId', 'executionId', 'idExecution']))),
    text_(getAny_(event, ['Source', 'Outil', 'tool', 'application'], getAny_(run, ['Source', 'Outil', 'tool', 'application'], 'LDLCPreparationPC'))),
    payloadApplicationSource_(event, run),
    text_(getAny_(event, ['ToolVersion', 'Version', 'versionLogiciel', 'softwareVersion'], getAny_(run, ['ToolVersion', 'Version', 'versionLogiciel', 'softwareVersion'], 'legacy'))),
    text_(getAny_(event, ['ComputerName', 'PC', 'poste', 'hostname', 'machine'], getAny_(run, ['ComputerName', 'PC', 'poste', 'hostname', 'machine']))),
    text_(getAny_(event, ['UserName', 'Utilisateur', 'user'], getAny_(run, ['UserName', 'Utilisateur', 'user']))),
    text_(getAny_(event, ['UserDomain', 'Domaine', 'domain'], getAny_(run, ['UserDomain', 'Domaine', 'domain']))),
    text_(getAny_(event, ['SerialNumber', 'NumeroSerie', 'serial'], getAny_(run, ['SerialNumber', 'NumeroSerie', 'serial']))),
    text_(getAny_(event, ['Manufacturer', 'Fabricant'], getAny_(run, ['Manufacturer', 'Fabricant']))),
    text_(getAny_(event, ['Model', 'Modele'], getAny_(run, ['Model', 'Modele']))),
    text_(getAny_(event, ['OSCaption', 'OS', 'operatingSystem'], getAny_(run, ['OSCaption', 'OS', 'operatingSystem']))),
    text_(getAny_(event, ['OSVersion', 'VersionOS'], getAny_(run, ['OSVersion', 'VersionOS']))),
    text_(getAny_(event, ['TimeZone', 'FuseauHoraire'], getAny_(run, ['TimeZone', 'FuseauHoraire']))),
    text_(getAny_(event, ['Step', 'Etape', 'stage'])),
    text_(getAny_(event, ['Type', 'TypeErreur', 'category'])),
    clip_(text_(getAny_(event, ['Message', 'errorMessage', 'description'])), 2000),
    clip_(text_(getAny_(event, ['Details', 'detail', 'stackTrace'])), 10000),
    text_(getAny_(event, ['Status', 'Statut'], 'en_attente')),
    text_(getAny_(event, ['Severity', 'Gravite', 'priority'])),
    tags_(getAny_(event, ['Tags', 'labels'], [])),
    text_(getAny_(event, ['ScriptPath', 'script'], getAny_(run, ['ScriptPath', 'script']))),
    receivedAt
  ];
}

function runToRow_(run, receivedAt, existingRun) {
  function field(keys, fallback) {
    return getAny_(run, keys, getAny_(existingRun || {}, keys, fallback));
  }
  const finalRun = isFinalRun_(run);
  const completionConfirmed = field(['CompletionConfirmed', 'InterventionTerminee']);
  const suppliedDuration = getAny_(run, ['DurationSeconds', 'DureeSecondes', 'duration', 'duree']);
  const hasDuration = suppliedDuration !== undefined && suppliedDuration !== '' &&
    Number.isFinite(Number(suppliedDuration)) && Number(suppliedDuration) >= 0 && Number(suppliedDuration) < 30 * 86400;
  const initialAt = finalRun && hasDuration ? new Date(receivedAt.getTime() - Math.round(Number(suppliedDuration)) * 1000) : receivedAt;
  const startedAt = validDate_(getAny_(existingRun || {}, ['Debut', 'StartedAt', 'dateDebut', 'startTime'])) || initialAt;
  const existingFinishedAt = validDate_(getAny_(existingRun || {}, ['Fin', 'FinishedAt', 'dateFin', 'endTime']));
  const finishedAt = finalRun ? (existingFinishedAt || receivedAt) : null;
  const lastUpdateAt = receivedAt;
  const heartbeatAt = receivedAt;
  const durationEnd = finishedAt || lastUpdateAt;
  const serverDurationSeconds = finalRun && hasDuration ? Math.round(Number(suppliedDuration)) : elapsedSeconds_(startedAt, durationEnd);

  const row = [
    dateValue_(startedAt),
    dateValue_(finishedAt),
    text_(getAny_(run, ['RunId', 'executionId', 'idExecution'])),
    text_(field(['Source', 'Outil', 'tool', 'application'], 'LDLCPreparationPC')),
    payloadApplicationSource_(run, existingRun || {}),
    text_(field(['ToolVersion', 'Version', 'versionLogiciel', 'softwareVersion'], 'legacy')),
    text_(field(['ComputerName', 'PC', 'poste', 'hostname', 'machine'])),
    text_(field(['UserName', 'Utilisateur', 'user'])),
    text_(field(['UserDomain', 'Domaine', 'domain'])),
    text_(field(['SerialNumber', 'NumeroSerie', 'serial'])),
    text_(field(['Manufacturer', 'Fabricant'])),
    text_(field(['Model', 'Modele'])),
    text_(field(['OSCaption', 'OS', 'operatingSystem'])),
    text_(field(['OSVersion', 'VersionOS'])),
    text_(field(['TimeZone', 'FuseauHoraire'])),
    serverDurationSeconds,
    text_(field(['Status', 'Statut', 'ResultStatus', 'statutGlobal', 'result'])),
    Math.max(number_(field(['ErrorCount', 'Erreurs', 'errorsCount', 'nombreErreurs'])), number_(getAny_(existingRun, ['Erreurs', 'ErrorCount']))),
    Math.max(number_(field(['WarningCount', 'Avertissements', 'warningsCount', 'nombreAvertissements'])), number_(getAny_(existingRun, ['Avertissements', 'WarningCount']))),
    Math.max(number_(field(['CriticalCount', 'Critiques', 'criticalsCount', 'nombreCritiques'])), number_(getAny_(existingRun, ['Critiques', 'CriticalCount']))),
    number_(field(['EventCount', 'Evenements', 'eventsCount', 'nombreEvenements'])),
    text_(field(['CurrentStep', 'EtapeActuelle', 'currentStep', 'etapeCourante'])),
    text_(field(['CompletedSteps', 'EtapesTerminees', 'completedSteps', 'etapesTerminees'])),
    clip_(text_(field(['LastMessage', 'DernierMessage', 'lastMessage', 'message'])), 2000),
    dateValue_(lastUpdateAt),
    dateValue_(heartbeatAt),
    Math.max(0, Math.min(100, number_(field(['ProgressPercent', 'Progression', 'progress', 'percent'])))),
    booleanText_(finalRun),
    text_(field(['ScriptPath', 'script'])),
    receivedAt,
    number_(field(['Sequence', 'sequence', 'updateSequence'])),
    clip_(text_(field(['WarningDetails', 'DetailsAvertissements'])), 10000),
    completionConfirmed == null ? '' : completionConfirmed === 0 ? 'non' : booleanText_(completionConfirmed),
    clip_(text_(field(['BlockingReason', 'CauseBlocage'])), 10000)
  ];
  row[RUN_HEADERS.indexOf('Statut')] = inferredRunStatus_(objectFromRow_(RUN_HEADERS, row));
  return row;
}

function objectFromRow_(headers, row) {
  const value = {};
  headers.forEach(function(header, index) { value[header] = row[index]; });
  return value;
}

function shouldApplyRun_(existing, incoming) {
  if (!existing) return true;
  const wasFinal = isFinalRun_(existing);
  const nowFinal = isFinalRun_(incoming);
  if (wasFinal && !nowFinal) return false;
  if (!wasFinal && nowFinal) return true;
  const oldSequence = number_(getAny_(existing, ['Sequence', 'updateSequence']));
  const newSequence = number_(getAny_(incoming, ['Sequence', 'updateSequence']));
  if (oldSequence > 0 && newSequence > 0) return newSequence > oldSequence;
  // Un ancien exe renvoie son rapport final identique si l'acquittement a ete perdu.
  if (wasFinal) return false;
  return true;
}

function inferredRunStatus_(run) {
  const supplied = text_(getAny_(run, ['Status', 'Statut', 'status', 'ResultStatus', 'statutGlobal', 'result']));
  const suppliedKey = normalizedKey_(supplied);
  const currentStepKey = normalizedKey_(getAny_(run, ['EtapeActuelle', 'CurrentStep', 'currentStep', 'etapeCourante']));
  const lastMessageKey = normalizedKey_(getAny_(run, ['DernierMessage', 'LastMessage', 'lastMessage', 'message']));
  const finalMarker = normalizedKey_(getAny_(run, ['Final', 'IsFinal', 'isFinal', 'final']));
  const hasFinishedAt = !!validDate_(getAny_(run, ['Fin', 'FinishedAt', 'dateFin', 'endTime']));
  const isInitialPlaceholder = !hasFinishedAt && ['oui', 'yes', 'true', '1', 'final'].indexOf(finalMarker) < 0 &&
    currentStepKey === 'initialisation' && lastMessageKey.indexOf('executiondemarree') >= 0;
  const errors = number_(getAny_(run, ['ErrorCount', 'Erreurs', 'errors', 'errorsCount', 'nombreErreurs']));
  const warnings = number_(getAny_(run, ['WarningCount', 'Avertissements', 'warnings', 'warningsCount', 'nombreAvertissements']));
  const criticals = number_(getAny_(run, ['CriticalCount', 'Critiques', 'criticals', 'criticalsCount', 'nombreCritiques']));

  const explicitlyFinal = ['oui', 'yes', 'true', '1', 'final'].indexOf(finalMarker) >= 0 || hasFinishedAt;
  const explicitlyRunning = ['non', 'no', 'false', '0'].indexOf(finalMarker) >= 0;
  if (!explicitlyFinal && (explicitlyRunning || ['running', 'encours', 'inprogress'].indexOf(suppliedKey) >= 0 || isInitialPlaceholder)) {
    return 'running';
  }
  if (['stopped', 'interrompu', 'cancelled', 'annule', 'annulee'].indexOf(suppliedKey) >= 0) return 'stopped';
  if (/timeout|bloque|delai/.test(suppliedKey)) return 'timeout';



  if (errors > 0 || criticals > 0 || errorStatusKey_(suppliedKey)) {
    return 'error';
  }
  const completed = getAny_(run, ['CompletionConfirmed', 'InterventionTerminee']);
  if (completed === false || completed === 0 || ['non', 'no', 'false', '0'].indexOf(normalizedKey_(completed)) >= 0) {
    return explicitlyFinal ? 'stopped' : 'running';
  }
  if (warnings > 0 || warningStatusKey_(suppliedKey)) {
    return 'warning';
  }
  if (!suppliedKey) {
    // Compatibilite avec les anciennes executions qui ne transportaient pas
    // de statut final mais representaient un traitement termine sans erreur.
    return 'success';
  }
  if (['running', 'encours', 'inprogress'].indexOf(suppliedKey) >= 0) {
    return explicitlyFinal ? 'success' : 'running';
  }
  if (isInitialPlaceholder && (suppliedKey.indexOf('bloque') >= 0 || suppliedKey.indexOf('delai') >= 0 || suppliedKey.indexOf('timeout') >= 0)) {
    return 'running';
  }
  if (suppliedKey.indexOf('bloque') >= 0 || suppliedKey.indexOf('delai') >= 0 || suppliedKey.indexOf('timeout') >= 0) {
    return 'timeout';
  }
  if (['stopped', 'interrompu', 'cancelled', 'annule', 'annulee'].indexOf(suppliedKey) >= 0) {
    return 'stopped';
  }
  if (successStatusKey_(suppliedKey)) {
    return 'success';
  }
  return supplied;
}

function buildDashboardData_() {
  const book = getSpreadsheet_();
  const errorSheet = ensureSheet_(book, CONFIG.ERROR_SHEET_NAME, ERROR_HEADERS);
  const runSheet = ensureSheet_(book, CONFIG.RUN_SHEET_NAME, RUN_HEADERS);
  const errors = readObjects_(errorSheet);
  const runs = readObjects_(runSheet);
  const now = new Date();
  const dashboardRunRows = dashboardRuns_(runs);
  const dashboardErrorRows = dashboardErrors_(errors);

  return {
    generatedAt: formatDateTime_(now),
    generatedIso: now.toISOString(),
    generatedDateKey: periodKey_(now, 'day'),
    spreadsheetUrl: book.getUrl(),
    dashboardUrl: dashboardUrl_(),
    sheetLayout: {
      hiddenRunHeaders: hiddenHeaders_(runSheet, RUN_HEADERS)
    },
    errors: groupDashboardErrors_(dashboardErrorRows, dashboardRunRows),
    rawErrors: dashboardErrorRows,
    runs: dashboardRunRows
  };
}

function getDashboardSnapshot() {
  const data = buildDashboardData_();
  data.ok = true;
  return data;
}

function dashboardErrors_(errors) {
  return errors
    .filter(function(err) {
      const severity = normalizedKey_(getAny_(err, ['Gravite', 'Severity', 'priority']));
      const status = normalizedKey_(getAny_(err, ['Statut', 'Status']));
      return (
        severity.indexOf('crit') >= 0 ||
        severity.indexOf('error') >= 0 ||
        severity.indexOf('erreur') >= 0 ||
        severity.indexOf('echec') >= 0 ||
        status.indexOf('crit') >= 0 ||
        status.indexOf('error') >= 0 ||
        status.indexOf('erreur') >= 0 ||
        status.indexOf('echec') >= 0
      );
    })
    .slice()
    .sort(function(a, b) {
      return asDate_(getAny_(b, ['Horodatage', 'Timestamp', 'date', 'createdAt'])) -
        asDate_(getAny_(a, ['Horodatage', 'Timestamp', 'date', 'createdAt']));
    })
    .map(function(err) {
      const received = asDate_(getAny_(err, ['RecuLe', 'ReceivedAt', 'receivedAt']));
      const date = trustedServerDate_(asDate_(getAny_(err, ['Horodatage', 'Timestamp', 'date', 'createdAt'])), received);
      const tool = text_(getAny_(err, ['Outil', 'Source', 'tool', 'application']));
      return {
        dateIso: toIso_(date),
        dateKey: date && !isNaN(date.getTime()) ? periodKey_(date, 'day') : '',
        date: formatDateTime_(date),
        runId: text_(getAny_(err, ['RunId', 'executionId', 'idExecution'])),
        applicationSource: payloadApplicationSource_(err, {}),
        tool: tool,
        pc: text_(getAny_(err, ['PC', 'ComputerName', 'poste', 'hostname', 'machine'])),
        step: text_(getAny_(err, ['Etape', 'Step', 'stage'])),
        category: text_(getAny_(err, ['TypeErreur', 'Type', 'category'], 'non renseigne')),
        status: text_(getAny_(err, ['Statut', 'Status'], 'en attente')),
        priority: text_(getAny_(err, ['Gravite', 'Severity', 'priority'], 'haute')),
        message: text_(getAny_(err, ['Message', 'errorMessage', 'description'])),
        details: text_(getAny_(err, ['Details', 'detail', 'stackTrace'])),
        tags: text_(getAny_(err, ['Tags', 'labels'])),
        scriptPath: text_(getAny_(err, ['ScriptPath', 'script']))
      };
    });
}

function groupDashboardErrors_(errors, runs) {
  const runsById = {};
  (runs || []).forEach(function(run) {
    if (run && run.runId) {
      runsById[run.runId] = run;
    }
  });

  const groups = {};
  (errors || []).forEach(function(err) {
    const runId = text_(err.runId);
    const fallbackDate = err.dateIso ? err.dateIso.substring(0, 16) : '';
    const key = runId || ['legacy', err.applicationSource || '', err.pc || '', fallbackDate].join('|');
    if (!groups[key]) {
      const run = runId ? runsById[runId] : null;
      groups[key] = {
        dateIso: run && run.startedIso ? run.startedIso : err.dateIso,
        dateKey: run && run.dateKey ? run.dateKey : err.dateKey,
        date: run && run.startedIso ? formatDateTime_(new Date(run.startedIso)) : err.date,
        runId: runId,
        applicationSource: err.applicationSource,
        tool: err.tool,
        pc: err.pc,
        category: '',
        status: run && run.status ? run.status : '',
        priority: '',
        message: '',
        step: '',
        details: '',
        tags: '',
        scriptPath: err.scriptPath,
        issueCount: 0,
        warningCount: 0,
        criticalCount: 0,
        steps: [],
        categories: [],
        issues: []
      };
    }

    const group = groups[key];
    group.issueCount++;
    group.issues.push(err);

    if (err.step && group.steps.indexOf(err.step) < 0) group.steps.push(err.step);
    if (err.category && group.categories.indexOf(err.category) < 0) group.categories.push(err.category);

    const severity = normalizedKey_(err.priority || err.status);
    if (severity.indexOf('crit') >= 0 || severity.indexOf('error') >= 0 || severity.indexOf('erreur') >= 0 || severity.indexOf('echec') >= 0) {
      group.criticalCount++;
    } else {
      group.warningCount++;
    }

    if (!group.dateIso || (err.dateIso && err.dateIso > group.dateIso)) {
      group.dateIso = err.dateIso;
      group.dateKey = err.dateKey;
      group.date = err.date;
    }
  });

  return Object.keys(groups).map(function(key) {
    const group = groups[key];
    group.issues.sort(function(a, b) { return String(b.dateIso || '').localeCompare(String(a.dateIso || '')); });
    const first = group.issues[0] || {};
    group.category = group.categories.slice(0, 4).join(', ') || first.category || 'non renseigne';
    group.step = group.steps.slice(0, 4).join(', ') || first.step || '';
    group.priority = group.criticalCount > 0 ? 'critique' : 'warning';
    group.status = group.status || (group.criticalCount > 0 ? 'critique' : 'en_attente');
    group.message = group.issueCount + ' probleme' + (group.issueCount > 1 ? 's' : '') + ' detecte' + (group.issueCount > 1 ? 's' : '') + ' pendant cette execution';
    group.details = group.issues.map(function(issue) {
      return [issue.date, issue.step, issue.category, issue.message].filter(Boolean).join(' - ');
    }).join('\n');
    return group;
  }).sort(function(a, b) {
    return String(b.dateIso || '').localeCompare(String(a.dateIso || ''));
  });
}

function dashboardRuns_(runs) {
  const mappedRuns = runs.map(function(run) {
    const received = asDate_(getAny_(run, ['RecuLe', 'ReceivedAt', 'receivedAt']));
    const finishedRaw = asDate_(getAny_(run, ['Fin', 'FinishedAt', 'dateFin', 'endTime']));
    const started = trustedServerDate_(asDate_(getAny_(run, ['Debut', 'StartedAt', 'dateDebut', 'startTime'])), received);
    const finished = validDate_(finishedRaw) ? trustedServerDate_(finishedRaw, received) : new Date(NaN);
    const updated = trustedServerDate_(asDate_(getAny_(run, ['DerniereMaj', 'LastUpdatedAt', 'lastUpdatedAt', 'updatedAt'])), received);
    const heartbeat = trustedServerDate_(asDate_(getAny_(run, ['DernierHeartbeat', 'LastHeartbeatAt', 'lastHeartbeatAt', 'heartbeatAt'])), received);
    const isFinal = isFinalRun_(run);
    const tool = text_(getAny_(run, ['Outil', 'Source', 'tool', 'application']));
    const status = displayRunStatus_(run, heartbeat, isFinal);
    const heartbeatAgeMinutes = heartbeat && !isNaN(heartbeat.getTime())
      ? Math.max(0, Math.floor((new Date().getTime() - heartbeat.getTime()) / 60000))
      : null;
    const isStale = !isFinal && heartbeatAgeMinutes !== null && heartbeatAgeMinutes > 15;
    const primaryDate = validDate_(finished) || validDate_(started) || validDate_(updated) || validDate_(received);
    return {
      startedIso: toIso_(started),
      finishedIso: toIso_(finished),
      updatedIso: toIso_(updated),
      heartbeatIso: toIso_(heartbeat),
      receivedIso: toIso_(received),
      dateKey: primaryDate ? periodKey_(primaryDate, 'day') : '',
      runId: text_(getAny_(run, ['RunId', 'executionId', 'idExecution'])),
      applicationSource: payloadApplicationSource_(run, {}),
      tool: tool,
      version: text_(getAny_(run, ['Version', 'ToolVersion', 'versionLogiciel', 'softwareVersion'], 'legacy')),
      pc: text_(getAny_(run, ['PC', 'ComputerName', 'poste', 'hostname', 'machine'])),
      user: text_(getAny_(run, ['Utilisateur', 'UserName', 'user'])),
      status: status,
      isFinal: isFinal,
      isStale: isStale,
      heartbeatAgeMinutes: heartbeatAgeMinutes,
      currentStep: text_(getAny_(run, ['EtapeActuelle', 'CurrentStep', 'currentStep', 'etapeCourante'])),
      completedSteps: text_(getAny_(run, ['EtapesTerminees', 'CompletedSteps', 'completedSteps', 'etapesTerminees'])),
      lastMessage: text_(getAny_(run, ['DernierMessage', 'LastMessage', 'lastMessage', 'message'])),
      warningDetails: text_(getAny_(run, ['DetailsAvertissements', 'WarningDetails'])),
      validation: runValidation_(run),
      progress: number_(getAny_(run, ['Progression', 'ProgressPercent', 'progress', 'percent'])),
      durationSeconds: number_(getAny_(run, ['DureeSecondes', 'DurationSeconds', 'duration', 'duree'])),
      errors: number_(getAny_(run, ['Erreurs', 'ErrorCount', 'errorsCount', 'nombreErreurs'])),
      warnings: number_(getAny_(run, ['Avertissements', 'WarningCount', 'warningsCount', 'nombreAvertissements'])),
      criticals: number_(getAny_(run, ['Critiques', 'CriticalCount', 'criticalsCount', 'nombreCritiques'])),
      events: number_(getAny_(run, ['Evenements', 'EventCount', 'eventsCount', 'nombreEvenements']))
    };
  });

  return deduplicateDashboardRuns_(mappedRuns);
}

function deduplicateDashboardRuns_(runs) {
  const grouped = {};
  const result = [];
  (runs || []).forEach(function(run) {
    const key = text_(run && run.runId);
    if (!key) {
      result.push(run);
      return;
    }
    if (!grouped[key]) {
      grouped[key] = run;
      result.push(run);
      return;
    }
    const current = grouped[key];
    const preferred = preferredDashboardRun_(current, run);
    if (preferred !== current) {
      grouped[key] = preferred;
      const index = result.indexOf(current);
      if (index >= 0) {
        result[index] = preferred;
      }
    }
  });
  return result;
}

function preferredDashboardRun_(current, candidate) {
  if (dashboardRunScore_(candidate) > dashboardRunScore_(current)) {
    return candidate;
  }
  return current;
}

function dashboardRunScore_(run) {
  const status = normalizedKey_(run && run.status);
  let score = 0;
  if (run && run.isFinal) score += 1000000000000000;
  if (status.indexOf('success') >= 0 || status.indexOf('reussi') >= 0 || status.indexOf('termine') >= 0 ||
      status.indexOf('echec') >= 0 || status.indexOf('erreur') >= 0 || status.indexOf('interrompu') >= 0 ||
      status.indexOf('bloque') >= 0 || status.indexOf('delai') >= 0 || status.indexOf('timeout') >= 0) {
    score += 1000000000000;
  }
  const dates = [run && run.finishedIso, run && run.updatedIso, run && run.heartbeatIso, run && run.receivedIso, run && run.startedIso]
    .map(function(value) {
      const date = asDate_(value);
      return date && !isNaN(date.getTime()) ? date.getTime() : 0;
    });
  return score + Math.max.apply(null, dates.concat([0]));
}

function isFinalRun_(run) {
  const value = getAny_(run, ['Final', 'IsFinal', 'isFinal', 'final']);
  if (value === true) return true;
  const finished = validDate_(getAny_(run, ['Fin', 'FinishedAt', 'dateFin', 'endTime']));
  if (finished) return true;
  if (value === false) return false;
  const normalized = normalizedKey_(value);
  if (['oui', 'yes', 'true', '1', 'final'].indexOf(normalized) >= 0) {
    return true;
  }
  if (['non', 'no', 'false', '0'].indexOf(normalized) >= 0) return false;

  const status = normalizedKey_(inferredRunStatus_(run));
  if (successStatusKey_(status) || warningStatusKey_(status) || errorStatusKey_(status) ||
      ['stopped', 'interrompu', 'cancelled', 'annule', 'annulee'].indexOf(status) >= 0 ||
      status.indexOf('bloque') >= 0 || status.indexOf('delai') >= 0 || status.indexOf('timeout') >= 0) {
    return true;
  }

  return false;
}

function displayRunStatus_(run, heartbeat, isFinal) {
  // Un heartbeat ancien peut venir d'une absence de reseau ou d'un PC eteint.
  // Il ne prouve pas un blocage. Seul le worker principal peut envoyer timeout.
  [heartbeat, isFinal];
  return inferredRunStatus_(run);
}

function runValidation_(run) {
  const status = normalizedKey_(inferredRunStatus_(run));
  if (!isFinalRun_(run)) return { state: 'pending', reason: 'Intervention en cours : fin non confirmee.' };
  if (status === 'success') return { state: 'validated', reason: '' };
  const step = text_(getAny_(run, ['EtapeActuelle', 'CurrentStep']));
  const detail = text_(getAny_(run, ['CauseBlocage', 'BlockingReason'])) ||
    text_(getAny_(run, ['DetailsAvertissements', 'WarningDetails'])) ||
    text_(getAny_(run, ['DernierMessage', 'LastMessage']));
  const fallback = /timeout|bloque|delai/.test(status) ? 'Delai depasse' :
    status === 'stopped' ? 'Intervention incomplete ou interrompue' : 'Erreur ou verification non confirmee';
  return { state: 'blocked', reason: detail || fallback + (step ? ' : ' + step : '') + '.' };
}

function trustedServerDate_(primaryDate, receivedDate) {
  const primary = validDate_(primaryDate);
  const received = validDate_(receivedDate);
  if (!received) {
    return primary || new Date(NaN);
  }
  if (!primary) {
    return received;
  }
  const maxTrustedDriftMs = 2 * 24 * 60 * 60 * 1000;
  return Math.abs(primary.getTime() - received.getTime()) > maxTrustedDriftMs ? received : primary;
}

function toIso_(date) {
  return date && !isNaN(date.getTime()) ? date.toISOString() : '';
}

function renderDashboard_(data, email) {
  data.email = '';
  return '<!doctype html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<title>Dashboard Preparation PC</title><meta http-equiv="Cache-Control" content="no-store">' +
    '<base target="_top">' +
    '<style>' + dashboardCss_() + '</style></head><body>' +
    '<div class="app-shell">' +
    '<aside class="sidebar">' +
    '<nav class="side-nav">' +
    applicationNavGroup_(APPLICATION_SOURCE_PC, 'All In App LDLC', true) +
    applicationNavGroup_(APPLICATION_SOURCE_NUMERIKS, 'All In App Numerik&apos;s', false) +
    applicationNavGroup_(APPLICATION_SOURCE_ADDON, 'Pr&eacute;paration ADDON', false) +
    '</nav></aside>' +
    '<main class="workspace">' +
    '<header class="hero-header"><div class="hero-line top" aria-hidden="true"></div><div class="hero-line bottom" aria-hidden="true"></div><div class="hero-dots left" aria-hidden="true"></div><div class="hero-dots right" aria-hidden="true"></div><div class="hero-circuit left" aria-hidden="true"></div><div class="hero-radar" aria-hidden="true"></div>' +
    '<div class="hero-title"><h1 id="pageTitle">Dashboard Preparation PC</h1><div class="title-rule" aria-hidden="true"><span></span></div><p id="pageSubtitle">Erreurs et ex&eacute;cutions</p></div>' +
    '<div class="account-block"><span class="system-pill"><i></i>Google Sheet actif</span><span class="updated">Derniere mise a jour : <b id="updatedAt"></b></span><button class="icon-button" id="refreshButton" title="Actualiser">' + iconSvg_('refresh') + '</button></div></header>' +
    '<nav class="mobile-application-tabs" aria-label="Type de preparation">' +
    '<button class="application-tab active" type="button" data-application="' + APPLICATION_SOURCE_PC + '">All In App LDLC</button>' +
    '<button class="application-tab" type="button" data-application="' + APPLICATION_SOURCE_NUMERIKS + '">All In App Numerik&apos;s</button>' +
    '<button class="application-tab" type="button" data-application="' + APPLICATION_SOURCE_ADDON + '">Pr&eacute;paration ADDON</button>' +
    '</nav>' +
    '<nav class="mobile-nav" aria-label="Navigation du tableau de bord">' +
    navItem_('grid', 'Vue d&apos;ensemble', 'overview', true) +
    navItem_('alert', 'Erreurs', 'errors', false) +
    navItem_('trend', 'Executions', 'executions', false) +
    navItem_('file', 'Rapports', 'reports', false) +
    navItem_('settings', 'Parametres', 'settings', false) +
    '</nav>' +
    '<section class="filters"><div class="period-tabs">' +
    '<button class="period active" data-period="today">Aujourd&apos;hui</button>' +
    '<button class="period" data-period="7">7 derniers jours</button>' +
    '<button class="period" data-period="30">30 derniers jours</button>' +
    '<button class="period" data-period="all">Toute la periode</button>' +
    '</div><label class="date-filter"><input type="date" id="dateFilter"><span>' + iconSvg_('calendar') + '</span></label></section>' +
    '<section class="view-panel active" data-view-panel="overview">' +
    '<section class="dashboard-grid top-grid"><div class="kpi-row" id="kpiRow"></div><aside class="side-summary" id="sideSummary"></aside></section>' +
    '<section class="chart-grid">' +
    chartCard_('Evolution des erreurs', 'lineChart') +
    chartCard_('Repartition des erreurs par categorie', 'categoryChart') +
    chartCard_('Reussites vs Erreurs', 'successChart') +
    '<article class="panel top-errors"><h2>Top des erreurs</h2><div id="topErrors"></div></article>' +
    '</section>' +
    '<section class="panel recent-panel"><div class="panel-head"><h2>Erreurs recentes</h2><div class="table-actions"><label class="search-box"><input id="searchInput" type="search" placeholder="Rechercher une execution..."><span>' + iconSvg_('search') + '</span></label><select id="categoryFilter"><option value="">Toutes categories</option></select><select id="statusFilter"><option value="">Tous statuts</option></select><button class="icon-button" id="downloadButton" title="Exporter CSV">' + iconSvg_('download') + '</button></div></div><div class="table-wrap"><table><thead><tr><th>Date et heure</th><th>Rubrique</th><th>All In App</th><th>Poste</th><th>Statut</th><th>Problemes</th><th>Etapes concernees</th><th>Resume</th><th>Details</th></tr></thead><tbody id="recentRows"></tbody></table></div><p class="table-foot" id="tableFoot"></p></section>' +
    '<section class="metric-strip" id="metricStrip"></section>' +
    '</section>' +
    '<section class="view-panel" data-view-panel="errors"><section class="panel focus-panel"><div class="panel-head"><div><h2>Centre de traitement des erreurs</h2><p class="panel-subtitle">Executions regroupees par poste, statut et problemes detectes.</p></div><button class="icon-button" id="errorsDownloadButton" title="Exporter les erreurs">' + iconSvg_('download') + '</button></div><div class="focus-grid" id="errorBoard"></div><div class="table-wrap view-table"><table><thead><tr><th>Date et heure</th><th>Rubrique</th><th>All In App</th><th>Poste</th><th>Statut</th><th>Problemes</th><th>Categories</th><th>Etapes concernees</th><th>Details</th></tr></thead><tbody id="errorsRows"></tbody></table></div></section></section>' +
    '<section class="view-panel" data-view-panel="executions"><section class="panel focus-panel"><div class="panel-head"><div><h2>Suivi des executions</h2><p class="panel-subtitle">Historique des lancements, reussites, echecs et durees.</p></div><button class="icon-button" id="runsDownloadButton" title="Exporter les executions">' + iconSvg_('download') + '</button></div><div class="focus-grid" id="runsBoard"></div><div class="table-wrap view-table"><table><thead><tr><th>Debut</th><th>Fin</th><th>Statut</th><th>Temps total</th><th>Etape actuelle</th><th>Derniere maj</th><th>Erreurs</th><th>All In App</th><th>Poste</th><th>Version</th><th>Details</th><th>Action</th></tr></thead><tbody id="runsRows"></tbody></table></div></section></section>' +
    '<section class="view-panel" data-view-panel="reports"><section class="panel focus-panel"><div class="panel-head"><div><h2>Rapports</h2><p class="panel-subtitle">Synthese exploitable de la periode selectionnee.</p></div><div class="table-actions"><button class="icon-button" id="reportErrorsCsv" title="Exporter les erreurs">' + iconSvg_('download') + '</button><button class="icon-button" id="reportRunsCsv" title="Exporter les executions">' + iconSvg_('file') + '</button></div></div><div class="report-grid" id="reportsBoard"></div></section></section>' +
    '<section class="view-panel" data-view-panel="settings"><section class="panel focus-panel"><div class="panel-head"><div><h2>Parametres</h2><p class="panel-subtitle">Connexion permanente au Google Sheet et acces par lien securise.</p></div><button class="icon-button" id="settingsRefreshButton" title="Actualiser">' + iconSvg_('refresh') + '</button></div><div class="report-grid" id="settingsBoard"></div></section></section>' +
    '</main></div>' +
    '<div class="dashboard-toast" id="dashboardToast" role="status" aria-live="polite"></div>' +
    '<script>window.LDLC_DASHBOARD_DATA=' + safeJson_(data) + ';</script><script>' + dashboardScript_() + '</script>' +
    '</body></html>';
}

function renderLogin_(reason) {
  return '<!doctype html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<base target="_top">' +
    '<style>' + dashboardCss_() + '</style></head><body><main class="login">' +
    '<form method="get"><h1>Dashboard Preparation PC</h1><p>Acces au tableau de bord securise.</p>' +
    '<input type="password" name="key" placeholder="Mot de passe" autofocus>' +
    '<button type="submit">Connexion</button>' +
    (reason ? '<small>' + esc_(reason) + '</small>' : '') +
    '</form></main></body></html>';
}

function applicationNavGroup_(application, label, expanded) {
  return '<section class="nav-group' + (expanded ? ' open' : '') + '" data-application-group="' + esc_(application) + '">' +
    '<button class="nav-group-toggle' + (expanded ? ' active' : '') + '" type="button" data-toggle-application="' + esc_(application) + '" aria-expanded="' + (expanded ? 'true' : 'false') + '">' +
    '<span class="nav-group-icon">' + iconSvg_(application === APPLICATION_SOURCE_ADDON ? 'trend' : 'grid') + '</span><span>' + label + '</span><i class="nav-chevron">&#8964;</i></button>' +
    '<div class="nav-submenu">' +
    navItem_('grid', 'Vue d&apos;ensemble', 'overview', expanded, application) +
    navItem_('alert', 'Erreurs', 'errors', false, application) +
    navItem_('trend', 'Executions', 'executions', false, application) +
    navItem_('file', 'Rapports', 'reports', false, application) +
    navItem_('settings', 'Parametres', 'settings', false, application) +
    '</div></section>';
}

function navItem_(icon, label, view, active, application) {
  const appAttribute = application ? ' data-application="' + esc_(application) + '"' : '';
  return '<button class="nav-item' + (active ? ' active' : '') + '" type="button" data-view="' + esc_(view) + '"' + appAttribute + (active ? ' aria-current="page"' : '') + '>' + iconSvg_(icon) + '<span>' + label + '</span></button>';
}

function chartCard_(title, canvasId) {
  const isLine = canvasId === 'lineChart';
  const canvasClass = isLine ? 'line-canvas' : 'donut-canvas';
  const width = isLine ? 520 : 220;
  const height = isLine ? 220 : 220;
  return '<article class="panel chart-card"><h2>' + esc_(title) + '</h2><div class="chart-body"><canvas class="' + canvasClass + '" id="' + esc_(canvasId) + '" width="' + width + '" height="' + height + '"></canvas><div class="legend" id="' + esc_(canvasId) + 'Legend"></div></div></article>';
}

function iconSvg_(name) {
  const icons = {
    grid: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="6" height="6" rx="1"></rect><rect x="14" y="4" width="6" height="6" rx="1"></rect><rect x="4" y="14" width="6" height="6" rx="1"></rect><rect x="14" y="14" width="6" height="6" rx="1"></rect></svg>',
    alert: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 2 21h20L12 3Z"></path><path d="M12 9v5"></path><path d="M12 17h.01"></path></svg>',
    trend: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 19V5"></path><path d="M4 19h16"></path><path d="m7 15 4-4 3 3 5-7"></path></svg>',
    file: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 3h9l4 4v14H6z"></path><path d="M15 3v5h5"></path><path d="M9 13h6"></path><path d="M9 17h6"></path></svg>',
    settings: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a8 8 0 0 0 .1-2l2-1.5-2-3.4-2.4 1a7 7 0 0 0-1.7-1L15 5h-4l-.4 3.1a7 7 0 0 0-1.7 1l-2.4-1-2 3.4 2 1.5a8 8 0 0 0 .1 2l-2.1 1.5 2 3.4 2.5-1a7 7 0 0 0 1.6.9L11 23h4l.4-3.2a7 7 0 0 0 1.6-.9l2.5 1 2-3.4L19.4 15Z"></path></svg>',
    refresh: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 12a8 8 0 1 1-2.3-5.7"></path><path d="M20 4v6h-6"></path></svg>',
    calendar: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="5" width="16" height="15" rx="2"></rect><path d="M8 3v4M16 3v4M4 10h16"></path></svg>',
    search: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"></circle><path d="m16 16 4 4"></path></svg>',
    download: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12"></path><path d="m7 10 5 5 5-5"></path><path d="M5 21h14"></path></svg>'
  };
  return icons[name] || icons.grid;
}

function safeJson_(obj) {
  return JSON.stringify(obj)
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

function dashboardUrl_() {
  const baseUrl = CONFIG.WEB_APP_URL || ScriptApp.getService().getUrl() || '';
  if (!baseUrl) {
    return '';
  }
  const separator = baseUrl.indexOf('?') === -1 ? '?' : '&';
  return baseUrl + separator + 'key=' + encodeURIComponent(CONFIG.DASHBOARD_PASSWORD || '');
}

function dashboardCss_() {
  return `
@font-face{font-family:"Outfit";src:url(data:font/woff2;base64,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) format("woff2");font-style:normal;font-weight:100 900;font-display:swap}
/* Brighter slate. Outfit is embedded under SIL OFL 1.1; see fonts/OFL.txt. */
:root{color-scheme:dark;--blue:#8daed5;--blue2:#7899bf;--red:#e28a90;--red2:#e28a90;--green:#7fc5a0;--orange:#d9b47a;--text:#f2f6fc;--muted:#c1cee0;--line:#4a5d76;--panel:#2b394b;--bg:#202b3a;--shadow:none;--shadow-strong:none}
*{box-sizing:border-box;min-width:0}
html{min-width:0;background:var(--bg)}
body{margin:0;min-height:100vh;background:linear-gradient(145deg,#334a65,#2b394b 70%);color:var(--text);font-family:"Trebuchet MS",Verdana,sans-serif;font-size:14px;line-height:1.45;overflow-x:hidden}
button,input,select{font:inherit;color:inherit}
button{cursor:pointer}
button:focus-visible,input:focus-visible,select:focus-visible,summary:focus-visible{outline:2px solid var(--blue);outline-offset:3px}
svg{width:22px;height:22px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
.app-shell{width:min(100%,1800px);min-height:100vh;margin:0 auto;display:grid;grid-template-columns:264px minmax(0,1fr);gap:24px;padding:24px}
.sidebar{display:flex;flex-direction:column}
.side-nav{position:sticky;top:24px;height:calc(100vh - 48px);min-height:620px;display:flex;flex-direction:column;gap:20px;padding:18px 12px;border:1px solid var(--line);border-radius:10px;background:linear-gradient(180deg,#28323f,#334a65);overflow:auto}
.nav-group{display:grid;gap:8px}
.nav-group-toggle{width:100%;min-height:56px;border:1px solid transparent;border-radius:6px;background:transparent;color:var(--muted);display:grid;grid-template-columns:24px minmax(0,1fr) 14px;align-items:center;gap:10px;padding:10px 12px;text-align:left;font-weight:600}
.nav-group-toggle:hover{background:#313d4c;color:var(--text)}
.nav-group-toggle.active{border-color:#414e60;background:#354456;color:var(--text)}
.nav-group-icon{display:grid;place-items:center;color:var(--blue)}
.nav-group-icon svg{width:21px;height:21px}
.nav-group[data-application-group="NUMERIKS_PREPARATION_PC"] .nav-group-icon{color:#9bc5b7}
.nav-chevron{font-style:normal;transition:transform .15s ease}
.nav-group.open .nav-chevron{transform:rotate(180deg)}
.nav-submenu{display:none;gap:4px;padding-left:8px}
.nav-group.open .nav-submenu{display:grid}
.nav-item{width:100%;min-height:44px;display:flex;align-items:center;gap:12px;padding:10px 12px;border:1px solid transparent;border-radius:6px;background:transparent;color:var(--muted);font-weight:500;text-align:left;transition:background .15s ease,color .15s ease}
.nav-item svg{flex:0 0 auto;width:20px;height:20px}
.nav-item:hover{background:#303c4b;color:var(--text)}
.nav-item.active{background:#3b4d63;border-color:#455974;color:#e4ecf6}
.nav-item[data-view="errors"] svg{color:var(--red)}
.nav-item[data-view="executions"] svg{color:var(--green)}
.workspace{min-width:0;max-width:100%}
.view-panel{display:none}
.view-panel.active{display:block}
.hero-header{position:relative;min-height:190px;margin-bottom:24px;padding:36px 24px 58px;display:grid;place-items:center;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:linear-gradient(120deg,#3a526f 0%,#324860 50%,#2a3c53 100%)}
.hero-header:before{content:"";position:absolute;top:-110px;right:-70px;width:400px;height:320px;transform:rotate(-24deg);border:1px solid rgba(172,188,210,.08);background:rgba(172,188,210,.015);pointer-events:none}
.hero-line,.hero-dots,.hero-circuit,.hero-radar,.title-rule,.system-pill{display:none}
.hero-title{position:relative;z-index:1;width:100%;text-align:center}
.hero-title h1{margin:0;font-family:"Outfit","Segoe UI Variable Display","Segoe UI",sans-serif;font-size:clamp(30px,3vw,44px);line-height:1.2;font-weight:650;letter-spacing:-.025em;color:#f5f9ff;text-shadow:none}
.hero-title p{margin:12px 0 0;display:inline-flex;align-items:center;justify-content:center;gap:8px;max-width:100%;padding:6px 13px;border:1px solid rgba(176,208,247,.24);border-radius:999px;background:rgba(18,32,49,.20);font-family:"Outfit","Segoe UI",sans-serif;font-size:14px;line-height:1.35;font-weight:450;color:#d8e5f7;letter-spacing:.015em}
.hero-title p:before{content:"";flex:0 0 auto;width:6px;height:6px;border-radius:50%;background:#a6ceff}
.account-block{position:absolute;bottom:14px;right:20px;left:20px;display:flex;justify-content:flex-end;align-items:center;gap:12px;color:var(--muted);font-size:12px}
.updated{overflow:hidden;text-overflow:ellipsis}
.updated b{font-weight:400;color:#c0c8d3}
.icon-button{flex:0 0 auto;width:36px;height:36px;border:1px solid var(--line);border-radius:6px;background:#313d4c;display:grid;place-items:center;color:#cbd4df}
.icon-button:hover{background:#3b495b;border-color:#526178}
.mobile-application-tabs,.mobile-nav{display:none}
.application-tab{min-height:44px;border:1px solid var(--line);border-radius:6px;background:var(--panel);font-weight:500}
.application-tab.active{background:#3b4d63;border-color:#455974}
.filters{display:grid;grid-template-columns:minmax(0,1fr) 240px;align-items:center;gap:16px;margin-bottom:22px}
.tool-tabs{display:none}
.period-tabs{display:grid;grid-template-columns:repeat(4,minmax(0,132px));gap:8px}
.period{height:44px;width:100%;border:1px solid var(--line);border-radius:6px;background:#293442;color:#bdc6d2;font-size:13px;font-weight:500;line-height:1.2;padding:0 10px}
.period:hover{background:#354456}
.period.active{background:#3b4d63;border-color:#4c617d;color:#e3ebf6}
.date-filter{height:44px;display:flex;align-items:center;gap:10px;padding:0 12px;border:1px solid var(--line);border-radius:6px;background:var(--panel)}
.date-filter input{width:100%;border:0;outline:0;background:transparent;font-size:13px}
.date-filter svg{width:18px;height:18px;color:var(--muted)}
.dashboard-grid{display:grid;grid-template-columns:minmax(0,1fr) 300px;gap:18px}
.kpi-row{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}
.card,.panel,.summary-card,.mini-card{background:var(--panel);border:1px solid var(--line);border-radius:8px;box-shadow:none}
.card{position:relative;min-height:210px;padding:22px;display:flex;flex-direction:column;justify-content:space-between;overflow-wrap:anywhere}
.card:before{content:"";position:absolute;left:0;top:22px;bottom:22px;width:2px;background:var(--blue)}
.card.red:before{background:var(--red)}
.card.orange:before{background:var(--orange)}
.card.green:before{background:var(--green)}
.card-icon{width:38px;height:38px;display:grid;place-items:center;border-radius:8px;background:#354d69;color:var(--blue);margin-bottom:20px}
.card-icon svg{width:23px;height:23px}
.card.red .card-icon{background:#34282f;color:var(--red)}
.card.orange .card-icon{background:#332e29;color:var(--orange)}
.card.green .card-icon{background:#24332e;color:var(--green)}
.card b{display:block;font-size:36px;line-height:1.15;font-weight:500;font-variant-numeric:tabular-nums;letter-spacing:-.03em;margin-bottom:6px}
.card span{display:block;font-size:13px;color:#c2cad5}
.trend{font-size:12px;margin-top:18px;color:var(--muted)}
.card.red .trend{color:var(--red)}
.card.orange .trend{color:var(--orange)}
.card.green .trend{color:var(--green)}
.card.blue .trend{color:var(--blue)}
.side-summary{display:grid;gap:14px}
.summary-card{padding:18px 20px}
.summary-card h3{margin:0 0 12px;font-size:14px;font-weight:600}
.summary-card strong{display:block;font-size:13px;line-height:1.5;font-weight:400;overflow-wrap:anywhere}
.summary-card small{display:block;margin-top:8px;font-size:12px;color:var(--red)}
.summary-line{display:flex;align-items:flex-start;gap:10px}
.summary-line svg{flex:0 0 auto;color:var(--red);width:18px;height:18px;margin-top:3px}
.chart-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr)) 300px;gap:18px;margin-top:22px}
.panel{min-width:0;max-width:100%;padding:22px;overflow-wrap:anywhere}
.panel h2{margin:0 0 18px;font-size:16px;font-weight:600;letter-spacing:0}
.chart-card,.top-errors{min-height:280px}
.chart-body{height:210px;display:grid;grid-template-columns:minmax(0,1fr) minmax(100px,136px);gap:16px;align-items:center}
.chart-card:first-child .chart-body{grid-template-columns:1fr}
canvas{display:block}
.line-canvas{width:100%;height:190px}
.donut-canvas{width:min(170px,100%);height:auto;aspect-ratio:1/1;justify-self:center}
.legend{display:grid;gap:14px;font-size:12px}
.legend-item{display:grid;grid-template-columns:10px minmax(0,1fr);gap:8px;align-items:start}
.swatch{width:10px;height:10px;border-radius:2px;margin-top:3px}
.legend-item small{display:block;margin-top:4px;color:var(--muted)}
.top-errors ol{margin:0;padding:0;list-style:none;display:grid;gap:18px}
.top-error{display:grid;grid-template-columns:18px minmax(0,1fr) 26px;gap:10px;font-size:12px;align-items:start}
.top-error span{color:var(--muted)}
.top-error b{display:block;font-weight:400;line-height:1.5;overflow-wrap:anywhere}
.top-error strong{font-weight:500;text-align:right}
.mini-track{height:3px;background:#475b75;border-radius:3px;overflow:hidden;margin-top:9px}
.mini-track i{display:block;height:100%;background:var(--red)}
.recent-panel{margin-top:24px}
.panel-head{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:18px}
.panel-head h2{margin:0;font-size:18px}
.table-actions{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.search-box{flex:1 1 220px;max-width:292px;height:40px;display:flex;align-items:center;gap:10px;padding:0 12px;background:#334a65;border:1px solid var(--line);border-radius:6px}
.search-box svg{width:18px;height:18px;color:var(--muted)}
.search-box input{width:100%;border:0;outline:0;background:transparent;font-size:13px}
.search-box input::placeholder{color:var(--muted)}
select{height:40px;min-width:150px;max-width:100%;padding:0 12px;border:1px solid var(--line);border-radius:6px;background:#334a65;font-size:13px}
.table-wrap{overflow:auto;border:1px solid var(--line);border-radius:6px;background:#334a65}
table{width:100%;border-collapse:collapse;min-width:900px;table-layout:fixed}
th,td{padding:13px 12px;border-bottom:1px solid var(--line);text-align:left;vertical-align:middle;font-size:12px;overflow-wrap:anywhere}
th{position:sticky;top:0;z-index:1;background:#313d4c;color:#c6cfdb;font-weight:500}
td{color:#c3cbd6}
tbody tr:hover{background:#2e3b4b}
.pill{display:inline-flex;align-items:center;justify-content:center;min-height:26px;max-width:100%;padding:4px 9px;border:1px solid transparent;border-radius:5px;font-size:11px;font-weight:500;line-height:1.3;text-align:center;white-space:normal;overflow-wrap:anywhere;vertical-align:middle}
.pill.wait{background:#332e29;border-color:#5b4b37;color:var(--orange)}
.pill.crit{background:#34282f;border-color:#62434b;color:var(--red)}
.pill.ok{background:#24332e;border-color:#3c5b4e;color:var(--green)}
.pill.info{background:#354d69;border-color:#425670;color:var(--blue)}
.application-badge{display:inline-block;padding:4px 8px;border:1px solid #425670;border-radius:5px;background:#354d69;color:#b3c8e2;font-size:11px;font-weight:500;line-height:1.4}
.application-badge.numeriks{border-color:#405e54;background:#24332e;color:#b0cfbf}
.row-menu{font-size:0;color:var(--muted);text-align:right}
.row-menu:before{content:"\\22EE";font-size:18px}
.empty-row td{text-align:center;color:var(--muted);height:88px}
.table-foot,.panel-subtitle{font-size:12px;color:var(--muted)}
.empty{color:var(--muted);font-size:12px}
.table-foot{margin:14px 2px 0}
.metric-strip{display:none}
.focus-grid,.report-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:14px;margin-bottom:22px}
.mini-card{min-height:110px;padding:18px}
.mini-card small{display:block;color:var(--muted);font-size:11px;font-weight:500;text-transform:uppercase;letter-spacing:.07em}
.mini-card strong{display:block;margin:7px 0;font-size:27px;font-weight:500;font-variant-numeric:tabular-nums}
.mini-card span{display:block;font-size:12px;color:var(--muted)}
.mini-card.danger strong{color:var(--red)}
.mini-card.good strong{color:var(--green)}
.mini-card.warn strong{color:var(--orange)}
.settings-list{display:grid;gap:16px;font-size:13px;line-height:1.6}
.settings-list b{display:block;font-weight:500}
.settings-link{display:inline-block;margin-top:6px;color:var(--blue);overflow-wrap:anywhere;text-decoration:none}
.settings-link:hover{text-decoration:underline}
.issue-details{min-width:0;max-width:100%}
.issue-details summary{list-style:none;display:inline-flex;align-items:center;min-height:32px;max-width:100%;padding:4px 10px;border:1px solid #425670;border-radius:5px;color:#c6d7ec;background:#354d69;font-size:12px;cursor:pointer;white-space:normal;overflow-wrap:anywhere}
.issue-details summary::-webkit-details-marker{display:none}
.issue-details[open] summary{background:#3b4d63}
.issue-details .toggle-open{display:none}
.issue-details[open] .toggle-open{display:inline}
.issue-details[open] .toggle-closed{display:none}
.issue-list{display:grid;gap:10px;margin-top:12px;width:min(680px,100%);min-width:0;max-width:100%}
.run-issue-list{width:min(760px,100%)}
.issue-item{min-width:0;max-width:100%;padding:10px 12px;border:1px solid var(--line);border-radius:6px;background:#334a65;white-space:normal;overflow-wrap:anywhere}
.issue-item b{display:block;font-size:12px;font-weight:500;line-height:1.5}
.issue-item span{display:block;margin-top:4px;color:var(--muted);font-size:11px;line-height:1.5}
#runsRows>tr>td[data-label="Details"]>.issue-list{margin-top:0}
.run-detail-card b{color:#c6d7ec}
.run-detail-card .run-detail-excerpt{display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;max-height:33px;overflow:hidden;margin:6px 0;color:var(--muted)}
.run-detail-button{padding:0;border:0;background:transparent;color:var(--blue);font:inherit;font-size:11px;text-align:left;text-decoration:underline;cursor:pointer}
.run-detail-dialog{width:min(660px,calc(100vw - 32px));max-height:80vh;padding:22px;border:1px solid var(--line);border-radius:8px;background:#293442;color:var(--text);overflow:auto}
.run-detail-dialog::backdrop{background:rgba(0,0,0,.6)}
.run-detail-dialog form{float:right;margin:0 0 12px 16px}
.run-detail-dialog h3{margin:0 0 18px;font-size:18px}
.run-detail-dialog h4{margin:18px 0 6px;font-size:13px;color:#c6d7ec}
.run-detail-dialog p{margin:0;white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px;line-height:1.6}
@media(min-width:761px){.view-table:has(#runsRows) table{min-width:1220px;table-layout:auto}.view-table:has(#runsRows) th{white-space:nowrap;overflow-wrap:normal}.view-table:has(#runsRows) th:nth-child(11){width:230px}.view-table:has(#runsRows) th:nth-child(12){width:72px}#runsRows td[data-label="Statut"] .pill{white-space:nowrap;overflow-wrap:normal}}
.delete-run-button{width:32px;height:32px;border:1px solid #62434b;border-radius:5px;background:#34282f;color:var(--red);font-size:18px;line-height:1}
.delete-run-button:hover{background:#493038}
.delete-run-button:disabled{opacity:.5;cursor:wait}
.dashboard-toast{position:fixed;right:22px;bottom:22px;z-index:80;max-width:min(420px,calc(100vw - 44px));padding:14px 16px;border:1px solid #425670;border-radius:8px;background:#344b66;color:var(--text);font-weight:500;line-height:1.5;opacity:0;transform:translateY(8px);pointer-events:none;transition:opacity .15s ease,transform .15s ease}
.dashboard-toast.visible{opacity:1;transform:translateY(0)}
.dashboard-toast.success{border-color:#3c5b4e;background:#24332e}
.dashboard-toast.error{border-color:#62434b;background:#34282f}
.login{min-height:100vh;display:grid;place-items:center;background:linear-gradient(145deg,#334a65,#2b394b)}
.login form{width:min(410px,calc(100vw - 40px));padding:30px;background:var(--panel);border:1px solid var(--line);border-radius:8px}
.login h1{font-family:Bahnschrift,"Trebuchet MS",sans-serif;font-size:30px;font-weight:600;line-height:1.2}
.login p{color:var(--muted);font-size:13px}
.login input,.login button{width:100%;height:42px;margin-top:12px;padding:0 12px;border:1px solid var(--line);border-radius:6px;background:#334a65}
.login button{background:#3b4d63;border-color:#4c617d}
@media(max-width:1650px){.dashboard-grid{grid-template-columns:1fr}.side-summary{grid-template-columns:repeat(2,minmax(0,1fr))}.chart-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:1180px){.app-shell{grid-template-columns:1fr;padding:18px}.sidebar{display:none}.mobile-application-tabs,.mobile-nav{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;margin-bottom:12px}.mobile-nav{grid-template-columns:repeat(5,minmax(0,1fr));margin-bottom:22px}.mobile-nav .nav-item{border-color:var(--line);justify-content:center;background:var(--panel)}.mobile-nav .nav-item.active{background:#3b4d63;border-color:#455974}.hero-title h1{font-size:36px}.hero-header{min-height:178px}.filters{grid-template-columns:1fr}.date-filter{width:min(240px,100%)}.period-tabs{grid-template-columns:repeat(4,minmax(0,1fr))}.kpi-row{grid-template-columns:repeat(2,minmax(0,1fr))}.panel-head{align-items:flex-start;flex-direction:column}.table-actions{width:100%}.search-box{max-width:none}.table-actions select{flex:1 1 150px}}
@media(max-width:760px){.app-shell{padding:10px;gap:12px}.hero-header{min-height:165px;padding:28px 14px 62px}.hero-title h1{font-size:30px;letter-spacing:0}.hero-title p{font-size:12px}.account-block{right:14px;left:14px;justify-content:center;font-size:11px}.mobile-application-tabs,.mobile-nav{grid-template-columns:repeat(2,minmax(0,1fr))}.application-tab{font-size:12px;padding:8px}.mobile-nav .nav-item{font-size:12px;gap:8px;justify-content:flex-start}.period-tabs{grid-template-columns:repeat(2,minmax(0,1fr))}.date-filter{width:100%}.card{min-height:190px;padding:18px}.card b{font-size:32px}.card span{font-size:12px}.side-summary,.chart-grid{grid-template-columns:1fr}.panel{padding:18px}.chart-card,.top-errors{min-height:260px}.focus-grid,.report-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.table-wrap{overflow:visible;border:0;background:transparent}.table-wrap table{min-width:0}.table-wrap thead{display:none}.table-wrap tbody,.table-wrap tr,.table-wrap td{display:block;width:100%}.table-wrap tr{margin-bottom:12px;border:1px solid var(--line);border-radius:6px;background:#334a65;overflow:hidden}.table-wrap td{display:grid;grid-template-columns:108px minmax(0,1fr);gap:12px;padding:11px 12px;border-bottom:1px solid var(--line)}.table-wrap td:last-child{border-bottom:0}.table-wrap td:before{content:attr(data-label);font-weight:500;color:var(--muted)}.empty-row td{display:block;text-align:center}.empty-row td:before{content:""}.pill{white-space:normal}}
@media(prefers-reduced-motion:reduce){*,*:before,*:after{transition:none!important}}
`;
}

function dashboardScript_() {
  return `
(function(){
  var data = window.LDLC_DASHBOARD_DATA || { errors: [], runs: [], generatedIso: new Date().toISOString() };
  var dashboardDeleteKey = data.dashboardDeleteKey || '';
  var state = { period: 'today', search: '', category: '', status: '', view: 'overview', application: 'LDLC_PREPARATION_PC' };
  var refreshInProgress = false;
  var viewMeta = {
    overview: { title: 'Vue d ensemble', subtitle: 'Erreurs et executions' },
    errors: { title: 'Erreurs', subtitle: 'Traitement, priorite et historique des incidents' },
    executions: { title: 'Executions', subtitle: 'Suivi des lancements et du taux de reussite' },
    reports: { title: 'Rapports', subtitle: 'Synthese de la periode selectionnee' },
    settings: { title: 'Parametres', subtitle: 'Connexion permanente et acces securise par lien' }
  };
  var colors = ['#e28a90','#d9b47a','#8daed5','#7fc5a0','#a3acb8','#b49fc6','#9bc5b7','#c4b399'];
  var icons = {
    alert:'<svg viewBox="0 0 24 24"><path d="M12 3 2 21h20L12 3Z"></path><path d="M12 9v5"></path><path d="M12 17h.01"></path></svg>',
    calendar:'<svg viewBox="0 0 24 24"><rect x="4" y="5" width="16" height="15" rx="2"></rect><path d="M8 3v4M16 3v4M4 10h16"></path></svg>',
    check:'<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"></circle><path d="m8 12 3 3 5-6"></path></svg>',
    target:'<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"></circle><circle cx="12" cy="12" r="3"></circle><path d="M12 2v4M22 12h-4"></path></svg>',
    fail:'<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"></circle><path d="M9 9l6 6M15 9l-6 6"></path></svg>',
    clock:'<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"></circle><path d="M12 7v5l3 2"></path></svg>',
    trend:'<svg viewBox="0 0 24 24"><path d="M4 19V5"></path><path d="M4 19h16"></path><path d="m7 15 4-4 3 3 5-7"></path></svg>'
  };

  function $(id){ return document.getElementById(id); }
  function parseDate(value){ var d = value ? new Date(value) : null; return d && !isNaN(d.getTime()) ? d : null; }
  function pad(n){ return String(n).padStart(2,'0'); }
  function dayKey(d){ return d.getFullYear() + '-' + pad(d.getMonth()+1) + '-' + pad(d.getDate()); }
  function dateKeyFor(iso){ var d = parseDate(iso); return d ? dayKey(d) : ''; }
  function dayLabel(d){ return pad(d.getDate()) + '/' + pad(d.getMonth()+1); }
  function fullDate(d){ return pad(d.getDate()) + '/' + pad(d.getMonth()+1) + '/' + d.getFullYear(); }
  function esc(value){ return String(value == null ? '' : value).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
  function normalized(value){ return String(value || '').toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g,''); }
  function toolKey(value){
    var compact = normalized(value).replace(/[^a-z0-9]+/g,'');
    if (!compact) return 'unknown';
    if (compact.indexOf('addonsport') >= 0 || (compact.indexOf('addon') >= 0 && compact.indexOf('sport') >= 0)) return 'addon-sport';
    if (compact.indexOf('ldlcpreparationpc') >= 0 || compact.indexOf('preparationpc') >= 0 || compact.indexOf('preptool') >= 0) return 'prep-tool';
    return compact;
  }
  function toolLabel(value){
    var key = toolKey(value);
    if (key === 'addon-sport') return 'Pr\\u00e9paration Addon Sport';
    if (key === 'prep-tool') return 'Pr\\u00e9paration PC';
    if (key === 'unknown') return 'Rubrique non renseignee';
    return String(value || key);
  }
  function applicationKey(value, fallbackTool){
    var compact = normalized(value).replace(/[^a-z0-9]+/g,'');
    if (compact.indexOf('addon') >= 0) return 'LDLC_PREPARATION_ADDON';
    if (compact.indexOf('numerik') >= 0 || normalized(fallbackTool).indexOf('numerik') >= 0) return 'NUMERIKS_PREPARATION_PC';
    if (compact.indexOf('preparationpc') >= 0 || compact.indexOf('preptool') >= 0 || compact === 'pc') return 'LDLC_PREPARATION_PC';
    return toolKey(fallbackTool) === 'addon-sport' ? 'LDLC_PREPARATION_ADDON' : 'LDLC_PREPARATION_PC';
  }
  function applicationLabel(value){
    var key = applicationKey(value);
    if (key === 'LDLC_PREPARATION_ADDON') return 'Pr\\u00e9paration ADDON';
    return key === 'NUMERIKS_PREPARATION_PC' ? "All In App Numerik's" : 'All In App LDLC';
  }
  function applicationBadge(row){
    var key = applicationKey(row && row.applicationSource, row && row.tool);
    return '<span class="application-badge ' + (key === 'NUMERIKS_PREPARATION_PC' ? 'numeriks' : 'ldlc') + '">' + esc(applicationLabel(key)) + '</span>';
  }
  function matchesApplication(row){
    return applicationKey(row && row.applicationSource, row && row.tool) === state.application;
  }
  function runStatusValue(run){
    return normalized(run && (run.status || run.Statut || run.Status || run.ResultStatus || run.statutGlobal || run.result));
  }
  function errorStatusKey(status){
    status = String(status || '');
    return status.indexOf('failed') >= 0 || status.indexOf('failure') >= 0 ||
      status.indexOf('echec') >= 0 || status.indexOf('error') >= 0 ||
      status.indexOf('erreur') >= 0 || status.indexOf('critical') >= 0 ||
      status.indexOf('critique') >= 0;
  }
  function warningStatusKey(status){
    status = String(status || '');
    return status.indexOf('warning') >= 0 || status.indexOf('warn') >= 0 ||
      status.indexOf('avertissement') >= 0 || status.indexOf('partial') >= 0 ||
      status.indexOf('partiel') >= 0 || status.indexOf('partielle') >= 0;
  }
  function successStatusKey(status){
    if (errorStatusKey(status) || warningStatusKey(status)) return false;
    return !status || status.indexOf('termine') >= 0 || status.indexOf('termin') >= 0 ||
      status.indexOf('success') >= 0 || status.indexOf('succes') >= 0 || status.indexOf('succe') >= 0 || status.indexOf('succ') >= 0 ||
      status.indexOf('reussi') >= 0 || status.indexOf('completed') >= 0 ||
      status.indexOf('complete') >= 0 || status.indexOf('finished') >= 0 ||
      ['ok','done','termineavecsucces'].indexOf(status) >= 0;
  }
  function countBy(rows, getter){
    var map = {};
    rows.forEach(function(row){ var key = getter(row) || 'non renseigne'; map[key] = (map[key] || 0) + 1; });
    return Object.keys(map).map(function(key){ return { label:key, count:map[key] }; }).sort(function(a,b){ return b.count - a.count || String(a.label).localeCompare(String(b.label)); });
  }
  function runState(run){
    var status = runStatusValue(run);
    if (['running','encours','inprogress','stopped','interrompu','cancelled','annule','annulee'].indexOf(status.replace(/[^a-z0-9]/g,'')) >= 0) return 'info';
    if (status.indexOf('bloque') >= 0 || status.indexOf('delai') >= 0 || status.indexOf('timeout') >= 0) return 'info';
    if (Number(run && (run.errors || run.Erreurs || run.ErrorCount) || 0) > 0 ||
        Number(run && (run.criticals || run.Critiques || run.CriticalCount) || 0) > 0 ||
        errorStatusKey(status)) return 'error';
    if (Number(run && (run.warnings || run.Avertissements || run.WarningCount) || 0) > 0 ||
        warningStatusKey(status)) return 'warning';
    if (['running','encours','inprogress','stopped','interrompu','cancelled','annule','annulee'].indexOf(status) >= 0) return 'info';
    if (status.indexOf('bloque') >= 0 || status.indexOf('delai') >= 0 || status.indexOf('timeout') >= 0) return 'info';
    if (successStatusKey(status)) return 'success';
    return 'info';
  }
  function isSuccess(run){ return runState(run) === 'success'; }
  function isWarning(run){ return runState(run) === 'warning'; }
  function isFailed(run){ return runState(run) === 'error'; }
  function isInterrupted(run){
    var status = runStatusValue(run);
    return status.indexOf('interrompu') >= 0 || status.indexOf('stopped') >= 0 ||
      status.indexOf('cancel') >= 0 || status.indexOf('annul') >= 0;
  }
  function runRank(run){
    var state = runState(run);
    var score = 0;
    if (run && run.isFinal) score += 1000000000000000;
    if (state !== 'info' || isInterrupted(run)) score += 1000000000000;
    var dates = [run && run.finishedIso, run && run.updatedIso, run && run.heartbeatIso, run && run.receivedIso, run && run.startedIso].map(function(value){
      var date = parseDate(value);
      return date ? date.getTime() : 0;
    });
    return score + Math.max.apply(null, dates.concat([0]));
  }
  function dedupeRuns(rows){
    var grouped = {};
    var result = [];
    (rows || []).forEach(function(run){
      var key = runDedupeKey(run);
      if (!key) {
        result.push(run);
        return;
      }
      if (!grouped[key]) {
        grouped[key] = run;
        result.push(run);
        return;
      }
      if (runRank(run) > runRank(grouped[key])) {
        var index = result.indexOf(grouped[key]);
        grouped[key] = run;
        if (index >= 0) result[index] = run;
      }
    });
    return result;
  }
  function successStats(runs){
    var stats = { success:0, failed:0, warning:0, interrupted:0, timeout:0, running:0, eligible:0, rate:0, errorRate:0 };
    (runs || []).forEach(function(run){
      var state = runState(run);
      if (isInterrupted(run)) stats.interrupted += 1;
      else if (/timeout|bloque|delai/.test(runStatusValue(run))) stats.timeout += 1;
      else if (state === 'success') stats.success += 1;
      else if (state === 'error') stats.failed += 1;
      else if (state === 'warning') {
        stats.warning += 1;
      }
      else stats.running += 1;
    });
    stats.eligible = stats.success + stats.failed + stats.warning;
    stats.rate = stats.eligible ? Math.round(stats.success / stats.eligible * 100) : 0;
    stats.errorRate = stats.eligible ? Math.round(stats.failed / stats.eligible * 100) : 0;
    return stats;
  }
  function durationLabel(seconds){
    seconds = Math.max(0, Number(seconds || 0));
    var minutes = Math.floor(seconds / 60);
    var rest = Math.round(seconds % 60);
    if (minutes >= 60) return Math.floor(minutes / 60) + 'h ' + pad(minutes % 60) + 'm';
    if (minutes > 0) return minutes + 'm ' + pad(rest) + 's';
    return rest + 's';
  }
  function runDurationSeconds(run){
    var seconds = Number(run && run.durationSeconds || 0);
    if (seconds > 0) return seconds;
    var start = parseDate(run && run.startedIso);
    var end = parseDate(run && (run.finishedIso || run.updatedIso || run.receivedIso));
    if (start && end && end.getTime() >= start.getTime()) {
      return Math.round((end.getTime() - start.getTime()) / 1000);
    }
    return 0;
  }
  function runDurationLabel(run){
    var seconds = runDurationSeconds(run);
    return seconds > 0 ? durationLabel(seconds) : '-';
  }
  function statusClass(value){
    var v = normalized(value);
    if (v.indexOf('attente') >= 0 || v.indexOf('pending') >= 0 || v.indexOf('warn') >= 0 || v.indexOf('avert') >= 0 || v.indexOf('partial') >= 0 || v.indexOf('partiel') >= 0) return 'wait';
    if (v.indexOf('crit') >= 0 || v.indexOf('fail') >= 0 || v.indexOf('echec') >= 0 || v.indexOf('error') >= 0 || v.indexOf('erreur') >= 0) return 'crit';
    if (v.indexOf('corr') >= 0 || v.indexOf('success') >= 0 || v.indexOf('ok') >= 0 || v.indexOf('reussi') >= 0 || v.indexOf('completed') >= 0 || v.indexOf('complete') >= 0 || v.indexOf('done') >= 0 || v.indexOf('finish') >= 0 || v.indexOf('termine') >= 0 || v.indexOf('succes') >= 0) return 'ok';
    if (v.indexOf('bloque') >= 0 || v.indexOf('delai') >= 0 || v.indexOf('timeout') >= 0 || v.indexOf('stop') >= 0 || v.indexOf('interrompu') >= 0 || v.indexOf('annul') >= 0 || v.indexOf('cancel') >= 0) return 'info';
    return 'info';
  }
  function priorityClass(value){
    var v = normalized(value);
    return v.indexOf('crit') >= 0 || v.indexOf('haut') >= 0 || v.indexOf('high') >= 0 || v.indexOf('critical') >= 0 ? 'crit' : 'info';
  }
  function pill(value, kind){
    var cls = kind === 'priority' ? priorityClass(value) : statusClass(value);
    return '<span class="pill ' + cls + '">' + esc(value || (kind === 'priority' ? 'Haute' : 'en attente')) + '</span>';
  }
  function issueCountLabel(count){
    count = Number(count || 0);
    return count + ' erreur' + (count > 1 ? 's' : '');
  }
  function issueListHtml(issues, extraClass){
    return '<div class="issue-list ' + esc(extraClass || '') + '">' + issues.map(function(issue){
      return '<article class="issue-item"><b>' + esc(issue.message || '(message vide)') + '</b><span>' + esc([issue.date, issue.step, issue.category, issue.status || issue.priority].filter(Boolean).join(' - ')) + '</span></article>';
    }).join('') + '</div>';
  }
  function expandableIssueDetailsHtml(issues, extraClass){
    var count = issues.length;
    if (!count) return '<span class="empty">Aucun detail</span>';
    if (count === 1) return issueListHtml(issues, extraClass);
    return '<details class="issue-details"><summary><span class="toggle-closed">+</span><span class="toggle-open">-</span> ' + esc(issueCountLabel(count)) + '</summary>' + issueListHtml(issues, extraClass) + '</details>';
  }
  function issueDetailsHtml(row){
    var issues = row && row.issues && row.issues.length ? row.issues : [];
    return expandableIssueDetailsHtml(issues, '');
  }
  function errorsByRunId(){
    var map = {};
    (data.errors || []).forEach(function(group){
      var id = String(group && group.runId || '').trim();
      if (id) map[id] = group.issues && group.issues.length ? group.issues : [];
    });
    return map;
  }
  function runIssueDetailsHtml(run){
    run = run || {};
    var id = String(run.runId || '').trim();
    var issues = id ? errorsByRunId()[id] || [] : [];
    var validation = run.validation || {};
    var content = '';
    function detail(label, value){
      return value ? '<h4>' + esc(label) + '</h4><p>' + esc(value) + '</p>' : '';
    }
    if (validation.state === 'blocked') content += detail('Validation bloquee', validation.reason);
    content += detail('Avertissements', run.warningDetails);
    content += detail('Dernier message', run.lastMessage);
    issues.forEach(function(issue){
      content += detail([issue.date, issue.step, issue.category].filter(Boolean).join(' - ') || 'Erreur', issue.message);
    });
    if (!content) return '<span class="empty">-</span>';
    var counts = [];
    var errors = Number(run.errors || issues.length || 0), warnings = Number(run.warnings || 0);
    if (errors) counts.push(errors + ' erreur' + (errors > 1 ? 's' : ''));
    if (warnings) counts.push(warnings + ' avertissement' + (warnings > 1 ? 's' : ''));
    var title = counts.join(' / ') || (validation.state === 'blocked' ? 'Validation bloquee' : 'Compte rendu');
    var excerpt = String(validation.reason || (issues[0] && issues[0].message) || run.warningDetails || run.lastMessage || '').replace(/\\s+/g, ' ').trim();
    if (excerpt.length > 160) excerpt = excerpt.slice(0, 157) + '...';
    return '<article class="issue-item run-detail-card"><b>' + esc(title) + '</b><span class="run-detail-excerpt">' + esc(excerpt) + '</span><button type="button" class="run-detail-button" data-show-run-details>Voir les détails</button><div hidden class="run-detail-full">' + content + '</div></article>';
  }
  function deleteRunButtonHtml(run){
    var id = String(run && run.runId || '').trim();
    if (!id) return '<span class="empty">-</span>';
    return '<button class="delete-run-button" type="button" title="Supprimer cette ex\\u00e9cution" aria-label="Supprimer cette ex\\u00e9cution" data-delete-run="' + esc(id) + '">X</button>';
  }
  function showDashboardMessage(type, message){
    var toast = $('dashboardToast');
    if (!toast) {
      if (type === 'error') alert(message);
      return;
    }
    toast.className = 'dashboard-toast visible ' + (type || 'info');
    toast.textContent = message;
    clearTimeout(showDashboardMessage.timer);
    showDashboardMessage.timer = setTimeout(function(){
      toast.className = 'dashboard-toast';
    }, 6500);
  }
  function setDeleteButtonLoading(button, loading){
    if (!button) return;
    if (loading) {
      button.dataset.originalText = button.textContent || 'X';
      button.disabled = true;
      button.textContent = '...';
    } else {
      button.disabled = false;
      button.textContent = button.dataset.originalText || 'X';
    }
  }
  function dashboardBaseUrl(){
    var url = String(data.dashboardUrl || window.location.href || '');
    return url.split('?')[0];
  }
  function deleteRunViaDirectRequest(runId, button, reason){
    if (!dashboardDeleteKey) {
      setDeleteButtonLoading(button, false);
      showDashboardMessage('error', 'Suppression impossible : clé dashboard absente. Recharge le lien complet du tableau.');
      return;
    }
    setDeleteButtonLoading(button, true);
    showDashboardMessage('info', reason || 'Suppression directe en cours...');
    var iframe = document.createElement('iframe');
    var done = false;
    iframe.style.display = 'none';
    iframe.onload = function(){
      if (done) return;
      done = true;
      setDeleteButtonLoading(button, false);
      showDashboardMessage('success', 'Suppression demandée. Actualisation du tableau...');
      setTimeout(function(){ location.reload(); }, 1200);
    };
    iframe.onerror = function(){
      if (done) return;
      done = true;
      setDeleteButtonLoading(button, false);
      showDashboardMessage('error', 'Suppression directe impossible : réponse du serveur non reçue.');
    };
    setTimeout(function(){
      if (done) return;
      done = true;
      setDeleteButtonLoading(button, false);
      showDashboardMessage('error', 'Suppression directe trop longue. Recharge le tableau puis réessaie.');
    }, 20000);
    iframe.src = dashboardBaseUrl() +
      '?key=' + encodeURIComponent(dashboardDeleteKey) +
      '&action=deleteRun' +
      '&confirm=DELETE_RUN' +
      '&runId=' + encodeURIComponent(runId) +
      '&ts=' + Date.now();
    document.body.appendChild(iframe);
  }
  function deleteRun(runId, button){
    runId = String(runId || '').trim();
    if (!runId) return;
    if (!confirm('Voulez-vous vraiment supprimer cette ex\\u00e9cution et ses erreurs associ\\u00e9es ?')) return;
    if (!window.google || !google.script || !google.script.run) {
      deleteRunViaDirectRequest(runId, button, 'Service Google Apps Script indisponible, tentative directe...');
      return;
    }
    setDeleteButtonLoading(button, true);
    showDashboardMessage('info', 'Suppression en cours pour ' + runId + '...');
    var completed = false;
    var timeout = setTimeout(function(){
      if (completed) return;
      completed = true;
      deleteRunViaDirectRequest(runId, button, 'Suppression trop longue, tentative directe...');
    }, 45000);
    google.script.run
      .withSuccessHandler(function(snapshot){
        if (completed) return;
        completed = true;
        clearTimeout(timeout);
        setDeleteButtonLoading(button, false);
        if (snapshot && snapshot.ok !== false) {
          var result = snapshot.deleteResult || {};
          snapshot.dashboardDeleteKey = dashboardDeleteKey;
          data = snapshot;
          render();
          showDashboardMessage('success', 'Suppression réussie : ' + Number(result.deletedRuns || 0) + ' exécution(s) et ' + Number(result.deletedErrors || 0) + ' erreur(s) supprimée(s).');
          return;
        }
        showDashboardMessage('error', 'Suppression refusée par le serveur : ' + (snapshot && snapshot.error ? snapshot.error : 'réponse invalide.'));
      })
      .withFailureHandler(function(error){
        if (completed) return;
        completed = true;
        clearTimeout(timeout);
        deleteRunViaDirectRequest(runId, button, 'Suppression Apps Script impossible, tentative directe...');
      })
      .deleteRunFromDashboard(runId, dashboardDeleteKey);
  }
  function runPill(run){
    var stateToClass = { success:'ok', warning:'wait', error:'crit', info:'info' };
    var stateToLabel = { success:'Valid\\u00e9', warning:'\\u00c0 v\\u00e9rifier', error:'\\u00c9chec', info:'Information' };
    var state = runState(run);
    var status = runStatusValue(run);
    var label = state === 'success' || state === 'warning' || state === 'error' ? stateToLabel[state] : stateToLabel.info;
    if (state === 'info') {
      if (['running','encours','inprogress'].indexOf(status) >= 0) {
        var age = Number(run && run.heartbeatAgeMinutes);
        label = run && run.isStale && isFinite(age)
          ? 'En cours - sans nouvelle depuis ' + age + ' min'
          : 'En cours';
      } else if (status.indexOf('timeout') >= 0 || status.indexOf('bloque') >= 0 || status.indexOf('delai') >= 0) {
        label = 'D\\u00e9lai d\\u00e9pass\\u00e9';
      } else if (status.indexOf('stop') >= 0 || status.indexOf('interrompu') >= 0 || status.indexOf('annul') >= 0) {
        label = 'Interrompu';
      }
    }
    return '<span class="pill ' + stateToClass[state] + '">' + esc(label) + '</span>';
  }
  function miniCard(label, value, detail, kind){
    return '<article class="mini-card ' + (kind || '') + '"><small>' + esc(label) + '</small><strong>' + esc(value) + '</strong><span>' + esc(detail || '') + '</span></article>';
  }
  function selectedDate(){
    var input = $('dateFilter');
    var generated = parseDate(data.generatedIso) || new Date();
    return input && input.value ? new Date(input.value + 'T12:00:00') : generated;
  }
  function selectedDateKey(){
    var input = $('dateFilter');
    return input && input.value ? input.value : (data.generatedDateKey || dayKey(selectedDate()));
  }
  function periodWindow(offset){
    var base = selectedDate();
    var end = new Date(base.getFullYear(), base.getMonth(), base.getDate() + 1);
    var start = new Date(base.getFullYear(), base.getMonth(), base.getDate());
    if (state.period === '7') start.setDate(start.getDate() - 6);
    if (state.period === '30') start.setDate(start.getDate() - 29);
    if (state.period === 'all') return { start:null, end:null, days:null };
    var days = Math.round((end - start) / 86400000);
    if (offset) { start = new Date(start.getTime() - days * 86400000); end = new Date(end.getTime() - days * 86400000); }
    return { start:start, end:end, days:days };
  }
  function inWindow(iso, win){
    var d = parseDate(iso);
    if (!d) return false;
    if (!win.start || !win.end) return true;
    return d >= win.start && d < win.end;
  }
  function runDate(run){ return run.finishedIso || run.startedIso || run.receivedIso; }
  function runDedupeKey(run){
    var id = String(run && run.runId || '').trim();
    if (id) return 'id:' + id;
    // Sans RunId, aucune preuve que deux lignes representent le meme lancement.
    return '';
  }
  function allRawErrors(){ return data.rawErrors && data.rawErrors.length ? data.rawErrors : data.errors; }
  function currentErrors(){ var w = periodWindow(false); return data.errors.filter(function(e){ return matchesApplication(e) && inWindow(e.dateIso, w); }); }
  function previousErrors(){ var w = periodWindow(true); return w.start ? data.errors.filter(function(e){ return matchesApplication(e) && inWindow(e.dateIso, w); }) : []; }
  function currentRawErrors(){ var w = periodWindow(false); return allRawErrors().filter(function(e){ return matchesApplication(e) && inWindow(e.dateIso, w); }); }
  function previousRawErrors(){ var w = periodWindow(true); return w.start ? allRawErrors().filter(function(e){ return matchesApplication(e) && inWindow(e.dateIso, w); }) : []; }
  function currentRuns(){ var w = periodWindow(false); return dedupeRuns(data.runs.filter(function(r){ return matchesApplication(r) && inWindow(runDate(r), w); })); }
  function previousRuns(){ var w = periodWindow(true); return w.start ? dedupeRuns(data.runs.filter(function(r){ return matchesApplication(r) && inWindow(runDate(r), w); })) : []; }
  function selectedDayErrors(){
    var key = selectedDateKey();
    return data.errors.filter(function(e){ return matchesApplication(e) && (e.dateKey || dateKeyFor(e.dateIso)) === key; });
  }
  function selectedDayRawErrors(){
    var key = selectedDateKey();
    return allRawErrors().filter(function(e){ return matchesApplication(e) && (e.dateKey || dateKeyFor(e.dateIso)) === key; });
  }
  function selectedDayRuns(){
    var key = selectedDateKey();
    return dedupeRuns(data.runs.filter(function(run){ return matchesApplication(run) && (run.dateKey || dateKeyFor(runDate(run))) === key; }));
  }
  function periodLabel(){
    if (state.period === 'today') return 'Aujourd\\'hui';
    if (state.period === '7') return '7 derniers jours';
    if (state.period === '30') return '30 derniers jours';
    return 'Toute la periode';
  }
  function kpiCard(kind, icon, value, label, note){
    return '<article class="card ' + kind + '"><div class="card-icon">' + icons[icon] + '</div><div><b>' + esc(value) + '</b><span>' + esc(label) + '</span><div class="trend">' + esc(note || periodLabel()) + '</div></div></article>';
  }
  function renderKpis(errors, runs, prevErrors, prevRuns, rawErrors){
    rawErrors = rawErrors || errors;
    var stats = successStats(runs);
    $('kpiRow').innerHTML =
      kpiCard('red','alert',errors.length,'Executions avec problemes',rawErrors.length + ' probleme(s) detaille(s)') +
      kpiCard('blue','check',selectedDayRuns().length,'Executions aujourd\\'hui',periodLabel()) +
      kpiCard('green','target',stats.rate + '%','Taux de reussite',stats.success + ' reussite(s) terminee(s)') +
      kpiCard('red','fail',stats.errorRate + '%','Taux d\\'erreur',stats.failed + ' echec(s), ' + stats.interrupted + ' interrompue(s)');
  }
  function renderSideSummary(errors){
    var top = countBy(errors, function(e){ return e.message || '(message vide)'; })[0];
    var recent = errors.slice().sort(function(a,b){ return (parseDate(b.dateIso) || 0) - (parseDate(a.dateIso) || 0); })[0];
    $('sideSummary').innerHTML =
      '<article class="summary-card"><h3>Erreur la plus frequente</h3><strong>' + esc(top ? top.label : 'Aucune erreur') + '</strong><small>' + (top ? top.count + ' occurrence' + (top.count > 1 ? 's' : '') : '0 occurrence') + '</small></article>' +
      '<article class="summary-card"><h3>Derniere erreur detectee</h3><div class="summary-line">' + icons.clock + '<div><strong>' + esc(recent ? recent.date : 'Aucune') + '</strong><small>' + esc(recent ? recent.message : 'Aucune erreur sur la periode') + '</small></div></div></article>';
  }
  function lineSeries(errors){
    var win = periodWindow(false);
    var days = win.days || 7;
    if (state.period === 'all') days = 7;
    var end = selectedDate();
    var labels = [];
    var values = [];
    for (var i = days - 1; i >= 0; i--) {
      var d = new Date(end.getFullYear(), end.getMonth(), end.getDate() - i);
      var key = dayKey(d);
      labels.push(dayLabel(d));
      values.push(errors.filter(function(e){ var ed = parseDate(e.dateIso); return ed && dayKey(ed) === key; }).length);
    }
    return { labels:labels, values:values };
  }
  function drawLineChart(canvas, series){
    var ctx = canvas.getContext('2d'), w = canvas.width, h = canvas.height;
    ctx.clearRect(0,0,w,h);
    var padL = 42, padR = 18, padT = 18, padB = 34;
    var max = Math.max.apply(null, series.values.concat([1]));
    ctx.strokeStyle = 'rgba(163,172,184,.14)'; ctx.lineWidth = 1;
    for (var y=0;y<5;y++){ var yy = padT + y * (h-padT-padB)/4; ctx.beginPath(); ctx.moveTo(padL,yy); ctx.lineTo(w-padR,yy); ctx.stroke(); }
    for (var x=0;x<series.labels.length;x++){ var xx = padL + x * (w-padL-padR)/Math.max(1,series.labels.length-1); ctx.beginPath(); ctx.moveTo(xx,padT); ctx.lineTo(xx,h-padB); ctx.stroke(); }
    ctx.beginPath();
    series.values.forEach(function(v,i){ var x = padL + i * (w-padL-padR)/Math.max(1,series.values.length-1); var y = h-padB - (v/max)*(h-padT-padB); if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y); });
    ctx.strokeStyle = '#e28a90'; ctx.lineWidth = 2; ctx.stroke();
    ctx.lineTo(w-padR,h-padB); ctx.lineTo(padL,h-padB); ctx.closePath(); ctx.fillStyle = 'rgba(226,138,144,.08)'; ctx.fill();
    ctx.fillStyle = '#a3acb8'; ctx.font = '12px Trebuchet MS';
    series.labels.forEach(function(label,i){ var x = padL + i * (w-padL-padR)/Math.max(1,series.labels.length-1); ctx.fillText(label, x-13, h-10); });
    ctx.fillStyle = '#e28a90';
    series.values.forEach(function(v,i){ var x = padL + i * (w-padL-padR)/Math.max(1,series.values.length-1); var y = h-padB - (v/max)*(h-padT-padB); ctx.beginPath(); ctx.arc(x,y,4,0,Math.PI*2); ctx.fill(); });
  }
  function drawDonut(canvas, items, legendId, palette){
    var ctx = canvas.getContext('2d'), w = canvas.width, h = canvas.height, cx = w/2, cy = h/2, r = Math.min(w,h)*.34, total = items.reduce(function(s,i){ return s+i.count; },0);
    palette = palette && palette.length ? palette : colors;
    ctx.clearRect(0,0,w,h);
    if(!total){ ctx.beginPath(); ctx.arc(cx,cy,r,0,Math.PI*2); ctx.lineWidth=28; ctx.strokeStyle='rgba(163,172,184,.18)'; ctx.stroke(); $(legendId).innerHTML='<span class="empty">Aucune donnee</span>'; return; }
    var start = -Math.PI/2;
    items.forEach(function(item,idx){ var angle = item.count/total*Math.PI*2; ctx.beginPath(); ctx.arc(cx,cy,r,start,start+angle); ctx.lineWidth=30; ctx.strokeStyle=palette[idx%palette.length]; ctx.stroke(); start += angle; });
    $(legendId).innerHTML = items.map(function(item,idx){ var pct = Math.round(item.count/total*100); return '<div class="legend-item"><i class="swatch" style="background:' + palette[idx%palette.length] + '"></i><span>' + esc(item.label) + '<small>' + item.count + ' (' + pct + '%)</small></span></div>'; }).join('');
  }
  function renderCharts(errors, runs, rawErrors){
    rawErrors = rawErrors || errors;
    drawLineChart($('lineChart'), lineSeries(errors));
    drawDonut($('categoryChart'), countBy(rawErrors,function(e){return e.category;}).slice(0,5), 'categoryChartLegend');
    var stats = successStats(runs);
    drawDonut($('successChart'), [{label:'Reussites',count:stats.success},{label:'Erreurs',count:stats.failed}], 'successChartLegend', ['#7fc5a0','#e28a90']);
  }
  function renderTopErrors(errors){
    var items = countBy(errors,function(e){ return e.message || '(message vide)'; }).slice(0,5);
    if(!items.length){ $('topErrors').innerHTML = '<p class="empty">Aucune erreur sur la periode.</p>'; return; }
    var max = items[0].count || 1;
    $('topErrors').innerHTML = '<ol>' + items.map(function(item,idx){ var pct = Math.round(item.count/max*100); return '<li class="top-error"><span>' + (idx+1) + '.</span><div><b title="' + esc(item.label) + '">' + esc(item.label) + '</b><div class="mini-track"><i style="width:' + pct + '%"></i></div></div><strong>' + item.count + '</strong></li>'; }).join('') + '</ol>';
  }
  function fillSelect(select, values, allLabel){
    var current = select.value;
    select.innerHTML = '<option value="">' + allLabel + '</option>' + values.map(function(v){ return '<option value="' + esc(v) + '">' + esc(v) + '</option>'; }).join('');
    select.value = values.indexOf(current) >= 0 ? current : '';
  }
  function filteredTableRows(errors){
    var q = normalized(state.search);
    return errors.filter(function(e){
      var hay = normalized([e.date,toolLabel(e.tool),e.category,e.message,e.step,e.status,e.priority,e.pc,e.details,e.runId].join(' '));
      return (!q || hay.indexOf(q) >= 0) && (!state.category || e.category === state.category) && (!state.status || e.status === state.status);
    });
  }
  function renderTable(errors){
    var categories = countBy(errors,function(e){return e.category;}).map(function(i){return i.label;});
    var statuses = countBy(errors,function(e){return e.status;}).map(function(i){return i.label;});
    fillSelect($('categoryFilter'), categories, 'Toutes categories');
    fillSelect($('statusFilter'), statuses, 'Tous statuts');
    state.category = $('categoryFilter').value;
    state.status = $('statusFilter').value;
    var rows = filteredTableRows(errors);
    var html = rows.slice(0,100).map(function(e){
      return '<tr><td data-label="Date et heure">' + esc(e.date) + '</td><td data-label="Rubrique">' + esc(toolLabel(e.tool)) + '</td><td data-label="All In App">' + applicationBadge(e) + '</td><td data-label="Poste">' + esc(e.pc || '-') + '</td><td data-label="Statut">' + pill(e.status, 'status') + '</td><td data-label="Problemes">' + esc(e.issueCount || 1) + '</td><td data-label="Etapes concernees">' + esc(e.step || '-') + '</td><td data-label="Resume">' + esc(e.message) + '</td><td data-label="Details" class="row-menu">' + issueDetailsHtml(e) + '</td></tr>';
    }).join('');
    $('recentRows').innerHTML = html || '<tr class="empty-row"><td colspan="9">Aucune erreur ne correspond aux filtres.</td></tr>';
    $('tableFoot').textContent = 'Affichage de ' + (rows.length ? 1 : 0) + ' a ' + Math.min(100, rows.length) + ' sur ' + rows.length + ' execution' + (rows.length > 1 ? 's' : '') + ' avec probleme';
  }
  function renderStrip(errors, runs){
    var selected = fullDate(selectedDate());
    var stats = successStats(runs);
    $('metricStrip').innerHTML =
      metric('calendar','Preparation active', applicationLabel(state.application)) +
      metric('calendar','Periode selectionnee', selected) +
      metric('alert','Total des erreurs', errors.length, 'red') +
      metric('fail','Executions', runs.length) +
      metric('alert','Avec avertissements', stats.warning, 'orange') +
      metric('fail','En echec', stats.failed, 'red') +
      metric('trend','Taux de reussite', stats.rate + '%', 'green');
  }
  function metric(icon,label,value,color){ return '<div class="metric"><span class="mini-icon ' + (color||'') + '">' + icons[icon] + '</span><div><small>' + esc(label) + '</small><strong>' + esc(value) + '</strong></div></div>'; }
  function renderErrorsView(errors){
    var waiting = errors.filter(function(e){ return normalized(e.status).indexOf('attente') >= 0 || normalized(e.status).indexOf('pending') >= 0; }).length;
    var critical = errors.filter(function(e){ return priorityClass(e.priority) === 'crit' || statusClass(e.status) === 'crit'; }).length;
    var pcs = countBy(errors, function(e){ return e.pc || 'PC non renseigne'; });
    var categories = countBy(errors, function(e){ return e.category; });
    $('errorBoard').innerHTML =
      miniCard('Erreurs ouvertes', errors.length, 'Sur la periode selectionnee', errors.length ? 'danger' : 'good') +
      miniCard('Critiques', critical, 'A traiter en priorite', critical ? 'danger' : 'good') +
      miniCard('En attente', waiting, 'Statut non corrige', waiting ? 'warn' : 'good') +
      miniCard('Postes touches', pcs.length, pcs[0] ? 'Principal : ' + pcs[0].label : 'Aucun poste');
    var rows = errors.slice().sort(function(a,b){ return (parseDate(b.dateIso) || 0) - (parseDate(a.dateIso) || 0); });
    $('errorsRows').innerHTML = rows.slice(0,150).map(function(e){
      return '<tr><td data-label="Date et heure">' + esc(e.date) + '</td><td data-label="Rubrique">' + esc(toolLabel(e.tool)) + '</td><td data-label="All In App">' + applicationBadge(e) + '</td><td data-label="Poste">' + esc(e.pc || '-') + '</td><td data-label="Statut">' + pill(e.status, 'status') + '</td><td data-label="Problemes">' + esc(e.issueCount || 1) + '</td><td data-label="Categories">' + esc(e.category) + '</td><td data-label="Etapes concernees">' + esc(e.step || '-') + '</td><td data-label="Details">' + issueDetailsHtml(e) + '</td></tr>';
    }).join('') || '<tr class="empty-row"><td colspan="9">Aucune erreur sur cette periode.</td></tr>';
  }
  function renderRunsView(runs){
    var stats = successStats(runs);
    var warnings = runs.reduce(function(sum, run){ return sum + Number(run.warnings || 0); }, 0);
    var finishedRuns = runs.filter(function(run){ return isSuccess(run) || isWarning(run) || isFailed(run); });
    var avg = finishedRuns.length ? Math.round(finishedRuns.reduce(function(sum, run){ return sum + Number(run.durationSeconds || 0); }, 0) / finishedRuns.length) : 0;
    $('runsBoard').innerHTML =
      miniCard('Executions', runs.length, 'Lancements sur la periode') +
      miniCard('En cours', stats.running, stats.running ? 'Preparation active ou recente' : 'Aucune execution active') +
      miniCard('Interrompues', stats.interrupted, stats.interrupted ? 'Arret detecte sans doublon' : 'Aucune interruption', stats.interrupted ? 'warn' : 'good') +
      miniCard('Delais depasses', stats.timeout, 'Arret confirme par le logiciel', stats.timeout ? 'warn' : 'good') +
      miniCard('Reussites', stats.success, stats.eligible ? stats.rate + '% des terminees' : 'Aucune execution terminee', 'good') +
      miniCard('Avec avertissement', stats.warning, 'Validation bloquee : controle requis', stats.warning ? 'warn' : 'good') +
      miniCard('Echecs', stats.failed, stats.failed ? 'Avec erreur(s) reelle(s)' : 'Aucun echec', stats.failed ? 'danger' : 'good') +
      miniCard('Duree moyenne', durationLabel(avg), warnings + ' avertissement' + (warnings > 1 ? 's' : ''));
    var rows = runs.slice().sort(function(a,b){ return (parseDate(runDate(b)) || 0) - (parseDate(runDate(a)) || 0); });
    $('runsRows').innerHTML = rows.slice(0,150).map(function(run){
      return '<tr><td data-label="Debut">' + esc(run.startedIso ? formatIsoForTable(run.startedIso) : '-') + '</td><td data-label="Fin">' + esc(run.finishedIso ? formatIsoForTable(run.finishedIso) : '-') + '</td><td data-label="Statut">' + runPill(run) + '</td><td data-label="Temps total">' + esc(runDurationLabel(run)) + '</td><td data-label="Etape actuelle">' + esc(run.currentStep || '-') + '</td><td data-label="Derniere maj">' + esc(run.updatedIso ? formatIsoForTable(run.updatedIso) : '-') + '</td><td data-label="Erreurs">' + esc(run.errors) + '</td><td data-label="All In App">' + applicationBadge(run) + '</td><td data-label="Poste">' + esc(run.pc || '-') + '</td><td data-label="Version">' + esc(run.version || '-') + '</td><td data-label="Details">' + runIssueDetailsHtml(run) + '</td><td data-label="Action">' + deleteRunButtonHtml(run) + '</td></tr>';
    }).join('') || '<tr class="empty-row"><td colspan="12">Aucune execution sur cette periode.</td></tr>';
  }
  function formatIsoForTable(iso){
    var d = parseDate(iso);
    return d ? fullDate(d) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds()) : '';
  }
  function renderReportsView(errors, runs){
    var topError = countBy(errors, function(e){ return e.message || '(message vide)'; })[0];
    var topCategory = countBy(errors, function(e){ return e.category; })[0];
    var stats = successStats(runs);
    $('reportsBoard').innerHTML =
      miniCard('Preparation analysee', applicationLabel(state.application), 'Donnees isolees du tableau') +
      miniCard('Periode analysee', state.period === 'all' ? 'Toute la periode' : fullDate(selectedDate()), 'Filtre actif du tableau') +
      miniCard('Total erreurs', errors.length, topCategory ? 'Categorie dominante : ' + topCategory.label : 'Aucune categorie', errors.length ? 'danger' : 'good') +
      miniCard('Taux de reussite', stats.rate + '%', stats.success + ' reussite(s), ' + stats.failed + ' echec(s), ' + stats.interrupted + ' interrompue(s)', stats.rate >= 80 ? 'good' : 'warn') +
      miniCard('Erreur recurrente', topError ? topError.count + 'x' : '0', topError ? topError.label : 'Aucune erreur');
  }
  function renderSettingsView(errors, runs){
    $('settingsBoard').innerHTML =
      miniCard('Connexion Google Sheet', 'Active', 'Les erreurs sont centralisees dans le Sheet permanent.', 'good') +
      miniCard('Acces dashboard', 'Lien securise', 'La page reste masquee sans la cle dans le lien.') +
      miniCard('Synchronisation', data.generatedAt || '-', errors.length + ' erreur(s), ' + runs.length + ' execution(s) chargee(s) pour ' + applicationLabel(state.application)) +
      '<article class="mini-card"><small>Base de suivi</small><strong>Google Sheet</strong><span>Historique conserve apres les mises a jour.</span><a class="settings-link" href="' + esc(data.spreadsheetUrl || '#') + '" target="_blank" rel="noopener">Ouvrir le Sheet</a></article>' +
      '<article class="mini-card"><small>Lien permanent</small><strong>Tableau HTML</strong><span>Utiliser ce lien, pas l adresse temporaire googleusercontent.</span><a class="settings-link" href="' + esc(data.dashboardUrl || '#') + '" target="_blank" rel="noopener">Ouvrir le dashboard</a></article>';
  }
  function renderViewPanels(){
    var meta = viewMeta[state.view] || viewMeta.overview;
    $('pageTitle').textContent = 'Dashboard Preparation PC';
    $('pageSubtitle').textContent = applicationLabel(state.application) + ' - Erreurs et ex\\u00e9cutions';
    document.title = 'Dashboard Preparation PC - ' + meta.title;
    document.querySelectorAll('[data-view-panel]').forEach(function(panel){
      panel.classList.toggle('active', panel.getAttribute('data-view-panel') === state.view);
    });
    document.querySelectorAll('.nav-item').forEach(function(btn){
      var application = btn.getAttribute('data-application');
      var active = btn.getAttribute('data-view') === state.view && (!application || application === state.application);
      btn.classList.toggle('active', active);
      if (active) btn.setAttribute('aria-current', 'page'); else btn.removeAttribute('aria-current');
    });
    document.querySelectorAll('[data-application-group]').forEach(function(group){
      var active = group.getAttribute('data-application-group') === state.application;
      group.classList.toggle('open', active);
      var toggle = group.querySelector('.nav-group-toggle');
      if (toggle) {
        toggle.classList.toggle('active', active);
        toggle.setAttribute('aria-expanded', active ? 'true' : 'false');
      }
    });
    document.querySelectorAll('.application-tab').forEach(function(btn){
      btn.classList.toggle('active', btn.getAttribute('data-application') === state.application);
    });
  }
  function render(){
    var errors = currentErrors(), rawErrors = currentRawErrors(), runs = currentRuns(), prevE = previousErrors(), prevR = previousRuns(), prevRaw = previousRawErrors();
    $('updatedAt').textContent = data.generatedAt || '';
    renderKpis(errors, runs, prevE, prevR, rawErrors, prevRaw);
    renderSideSummary(rawErrors);
    renderCharts(errors, runs, rawErrors);
    renderTopErrors(rawErrors);
    renderTable(errors);
    renderStrip(errors, runs);
    renderErrorsView(errors);
    renderRunsView(runs);
    renderReportsView(errors, runs);
    renderSettingsView(errors, runs);
    renderViewPanels();
  }
  function refreshDashboardData(){
    if (refreshInProgress || !window.google || !google.script || !google.script.run) return;
    refreshInProgress = true;
    google.script.run
      .withSuccessHandler(function(snapshot){
        refreshInProgress = false;
        if (snapshot && snapshot.ok !== false) {
          snapshot.dashboardDeleteKey = dashboardDeleteKey;
          data = snapshot;
          render();
        }
      })
      .withFailureHandler(function(){
        refreshInProgress = false;
      })
      .getDashboardSnapshot();
  }
  function downloadCsv(){
    var rows = filteredTableRows(currentErrors());
    var cols = ['Date','RunId','Rubrique','PC','Statut','Priorite','Problemes','Categories','Etapes','Resume','Details','All In App'];
    var csv = [cols.join(';')].concat(rows.map(function(e){ return [e.date,e.runId,toolLabel(e.tool),e.pc,e.status,e.priority,e.issueCount,e.category,e.step,e.message,e.details,applicationLabel(e.applicationSource)].map(function(v){ return '"' + String(v || '').replace(/"/g,'""') + '"'; }).join(';'); })).join('\\r\\n');
    var blob = new Blob([csv], { type:'text/csv;charset=utf-8;' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url; a.download = 'ldlc-erreurs-' + (state.application === 'LDLC_PREPARATION_ADDON' ? 'addon' : state.application === 'NUMERIKS_PREPARATION_PC' ? 'numeriks' : 'ldlc') + '.csv'; a.click();
    URL.revokeObjectURL(url);
  }
  function downloadRunsCsv(){
    var rows = currentRuns();
    var cols = ['Debut','Fin','Statut','TempsTotal','EtapeActuelle','DernierMessage','DerniereMaj','DureeSecondes','Erreurs','Avertissements','Critiques','Evenements','PC','Version','All In App'];
    var csv = [cols.join(';')].concat(rows.map(function(run){ return [run.startedIso,run.finishedIso,run.status,runDurationLabel(run),run.currentStep,run.lastMessage,run.updatedIso,runDurationSeconds(run),run.errors,run.warnings,run.criticals,run.events,run.pc,run.version,applicationLabel(run.applicationSource)].map(function(v){ return '"' + String(v || '').replace(/"/g,'""') + '"'; }).join(';'); })).join('\\r\\n');
    var blob = new Blob([csv], { type:'text/csv;charset=utf-8;' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url; a.download = 'ldlc-executions-' + (state.application === 'LDLC_PREPARATION_ADDON' ? 'addon' : state.application === 'NUMERIKS_PREPARATION_PC' ? 'numeriks' : 'ldlc') + '.csv'; a.click();
    URL.revokeObjectURL(url);
  }
  document.addEventListener('DOMContentLoaded', function(){
    var generated = parseDate(data.generatedIso) || new Date();
    $('dateFilter').value = data.generatedDateKey || dayKey(generated);
    document.querySelectorAll('.period').forEach(function(btn){ btn.addEventListener('click', function(){ document.querySelectorAll('.period').forEach(function(b){b.classList.remove('active');}); btn.classList.add('active'); state.period = btn.getAttribute('data-period'); render(); }); });
    $('dateFilter').addEventListener('change', render);
    $('searchInput').addEventListener('input', function(e){ state.search = e.target.value; renderTable(currentErrors()); });
    $('categoryFilter').addEventListener('change', function(e){ state.category = e.target.value; renderTable(currentErrors()); });
    $('statusFilter').addEventListener('change', function(e){ state.status = e.target.value; renderTable(currentErrors()); });
    $('downloadButton').addEventListener('click', downloadCsv);
    $('errorsDownloadButton').addEventListener('click', downloadCsv);
    $('runsDownloadButton').addEventListener('click', downloadRunsCsv);
    $('reportErrorsCsv').addEventListener('click', downloadCsv);
    $('reportRunsCsv').addEventListener('click', downloadRunsCsv);
    $('settingsRefreshButton').addEventListener('click', function(){ location.reload(); });
    $('refreshButton').addEventListener('click', function(){ location.reload(); });
    document.querySelectorAll('.nav-item').forEach(function(btn){ btn.addEventListener('click', function(){ state.view = btn.getAttribute('data-view') || 'overview'; state.application = btn.getAttribute('data-application') || state.application; render(); }); });
    document.querySelectorAll('[data-toggle-application]').forEach(function(btn){ btn.addEventListener('click', function(){ state.application = btn.getAttribute('data-toggle-application') || 'LDLC_PREPARATION_PC'; render(); }); });
    document.querySelectorAll('.application-tab').forEach(function(btn){ btn.addEventListener('click', function(){ state.application = btn.getAttribute('data-application') || 'LDLC_PREPARATION_PC'; render(); }); });
    document.addEventListener('click', function(event){
      var detailButton = event.target && event.target.closest ? event.target.closest('[data-show-run-details]') : null;
      if (detailButton) {
        var dialog = $('runDetailDialog');
        if (!dialog) {
          dialog = document.createElement('dialog');
          dialog.id = 'runDetailDialog';
          dialog.className = 'run-detail-dialog';
          dialog.setAttribute('aria-labelledby', 'runDetailTitle');
          dialog.innerHTML = '<form method="dialog"><button type="submit" class="icon-button">Fermer</button></form><h3 id="runDetailTitle">Détails de l’exécution</h3><div class="run-detail-body"></div>';
          document.body.appendChild(dialog);
        }
        dialog.querySelector('.run-detail-body').innerHTML = detailButton.nextElementSibling.innerHTML;
        dialog.showModal();
        return;
      }
      var button = event.target && event.target.closest ? event.target.closest('[data-delete-run]') : null;
      if (!button) return;
      deleteRun(button.getAttribute('data-delete-run'), button);
    });
    render();
    setInterval(refreshDashboardData, 5000);
  });
})();
`;
}

function parseJsonBody_(e) {
  if (!e || !e.postData || !e.postData.contents) {
    return null;
  }
  return JSON.parse(e.postData.contents);
}

function authorizeDashboard_(e) {
  const password = e && e.parameter ? String(e.parameter.key || '') : '';
  if (CONFIG.DASHBOARD_PASSWORD && password !== CONFIG.DASHBOARD_PASSWORD) {
    return { ok: false, reason: password ? 'Mot de passe incorrect.' : '' };
  }

  const email = getActiveEmail_();
  const allowed = (CONFIG.ALLOWED_DASHBOARD_EMAILS || [])
    .map(function(value) { return String(value || '').toLowerCase().trim(); })
    .filter(Boolean);

  if (CONFIG.REQUIRE_GOOGLE_EMAIL && allowed.length && email && allowed.indexOf(email.toLowerCase()) === -1) {
    return { ok: false, reason: 'Compte Google non autorise: ' + email };
  }

  if (CONFIG.REQUIRE_GOOGLE_EMAIL && allowed.length && !email) {
    return { ok: false, reason: 'Compte Google requis pour ce tableau de bord.' };
  }

  return { ok: true, email: email };
}

function getActiveEmail_() {
  try {
    return Session.getActiveUser().getEmail() || '';
  } catch (err) {
    return '';
  }
}

function getSpreadsheet_() {
  if (CONFIG.SPREADSHEET_ID && CONFIG.SPREADSHEET_ID !== 'PASTE_GOOGLE_SHEET_ID_HERE') {
    return SpreadsheetApp.openById(CONFIG.SPREADSHEET_ID);
  }

  const properties = PropertiesService.getScriptProperties();
  const storedId = properties.getProperty(CONFIG.SPREADSHEET_PROPERTY_KEY);
  if (storedId) {
    try {
      return SpreadsheetApp.openById(storedId);
    } catch (err) {
      properties.deleteProperty(CONFIG.SPREADSHEET_PROPERTY_KEY);
    }
  }

  throw new Error('Aucun Google Sheet permanent configure. Renseigne CONFIG.SPREADSHEET_ID avec le Sheet LDLC existant avant de deployer.');
}

function clearSheetDataValidations_(sheet) {
  try {
    const rows = Math.max(sheet.getMaxRows(), 1);
    const columns = Math.max(sheet.getMaxColumns(), 1);
    sheet.getRange(1, 1, rows, columns).clearDataValidations();
  } catch (err) {
    // Stale validations from older layouts must not reject telemetry writes.
  }
}

function ensureSheet_(book, name, headers) {
  let sheet = book.getSheetByName(name);
  if (!sheet) {
    sheet = book.insertSheet(name);
  }

  const headerWidth = Math.max(headers.length, Math.max(1, sheet.getLastColumn()));
  ensureGridCapacity_(sheet, 2, headerWidth);
  const firstRow = sheet.getRange(1, 1, 1, headerWidth).getValues()[0];
  const hasHeaders = firstRow.some(function(cell) { return String(cell || '').trim(); });
  if (!hasHeaders) {
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    sheet.setFrozenRows(1);
  } else {
    const existingHeaders = firstRow.map(function(cell) { return String(cell || '').trim(); });
    const missingHeaders = headers.filter(function(header) {
      return existingHeaders.indexOf(header) === -1;
    });
    if (missingHeaders.length) {
      const lastUsedHeader = existingHeaders.reduce(function(last, header, index) {
        return header ? index : last;
      }, -1);
      ensureGridCapacity_(sheet, 2, lastUsedHeader + 1 + missingHeaders.length);
      sheet.getRange(1, lastUsedHeader + 2, 1, missingHeaders.length).setValues([missingHeaders]);
    }
  }
  const layoutKey = 'LDLC_LAYOUT_' + sheet.getSheetId();
  const signature = CONFIG.SHEET_LAYOUT_VERSION + ':' + sheet.getLastColumn() + ':' + sheet.getMaxRows();
  const properties = PropertiesService.getScriptProperties();
  if (properties.getProperty(layoutKey) !== signature) {
    clearSheetDataValidations_(sheet);
    applySheetStyle_(sheet, headers, name);
    properties.setProperty(layoutKey, signature);
  } else {
    applyHiddenColumns_(sheet, sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].map(String), name);
  }
  return sheet;
}

function ensureGridCapacity_(sheet, rows, columns) {
  if (rows > sheet.getMaxRows()) sheet.insertRowsAfter(sheet.getMaxRows(), rows - sheet.getMaxRows());
  if (columns > sheet.getMaxColumns()) sheet.insertColumnsAfter(sheet.getMaxColumns(), columns - sheet.getMaxColumns());
}

function applySheetStyle_(sheet, headers, name) {
  const lastRow = Math.max(sheet.getLastRow(), 2);
  const width = Math.max(headers.length, sheet.getLastColumn());
  const activeHeaders = sheet.getRange(1, 1, 1, width).getValues()[0].map(function(value) {
    return String(value || '').trim();
  });
  const allRange = sheet.getRange(1, 1, lastRow, width);
  allRange.setFontFamily('Arial').setFontSize(10).setVerticalAlignment('middle');

  sheet.setFrozenRows(1);
  sheet.setRowHeight(1, 38);
  sheet.getRange(1, 1, 1, width)
    .setBackground('#06286b')
    .setFontColor('#ffffff')
    .setFontWeight('bold')
    .setHorizontalAlignment('center')
    .setWrap(true);

  const sizes = {
    Horodatage: 165,
    Debut: 165,
    Fin: 165,
    RecuLe: 165,
    RunId: 230,
    Outil: 150,
    ApplicationSource: 210,
    Version: 90,
    PC: 150,
    Utilisateur: 150,
    Domaine: 120,
    NumeroSerie: 160,
    Fabricant: 150,
    Modele: 180,
    OS: 260,
    VersionOS: 130,
    FuseauHoraire: 135,
    Etape: 190,
    TypeErreur: 150,
    Message: 420,
    Details: 560,
    Statut: 135,
    Gravite: 110,
    Tags: 180,
    ScriptPath: 420,
    DureeSecondes: 120,
    Erreurs: 95,
    Avertissements: 125,
    Critiques: 95,
    Evenements: 110,
    EtapeActuelle: 220,
    EtapesTerminees: 320,
    DernierMessage: 360,
    DerniereMaj: 165,
    DernierHeartbeat: 165,
    Progression: 105,
    Final: 70
  };

  activeHeaders.forEach(function(header, index) {
    sheet.setColumnWidth(index + 1, sizes[header] || 130);
  });

  // Les colonnes de version et les identifiants ne sont jamais des dates.
  const dateHeaders = ['Horodatage', 'Debut', 'Fin', 'DerniereMaj', 'DernierHeartbeat', 'RecuLe'];
  const numericHeaders = ['DureeSecondes', 'Erreurs', 'Avertissements', 'Critiques', 'Evenements', 'Progression', 'Sequence'];
  activeHeaders.forEach(function(header, index) {
    if (headers.indexOf(header) < 0 || dateHeaders.indexOf(header) >= 0) return;
    sheet.getRange(2, index + 1, Math.max(sheet.getMaxRows() - 1, 1), 1)
      .setNumberFormat(numericHeaders.indexOf(header) >= 0 ? '0' : '@');
  });

  ['Horodatage', 'Debut', 'Fin', 'DerniereMaj', 'DernierHeartbeat', 'RecuLe'].forEach(function(header) {
    const column = activeHeaders.indexOf(header) + 1;
    if (column > 0) {
      sheet.getRange(2, column, Math.max(sheet.getMaxRows() - 1, 1), 1)
        .setNumberFormat('yyyy-mm-dd hh:mm:ss');
    }
  });

  ['Message', 'Details', 'ScriptPath', 'OS', 'EtapeActuelle', 'EtapesTerminees', 'DernierMessage'].forEach(function(header) {
    const column = activeHeaders.indexOf(header) + 1;
    if (column > 0) {
      sheet.getRange(2, column, Math.max(sheet.getMaxRows() - 1, 1), 1).setWrap(true);
    }
  });

  applyHiddenColumns_(sheet, activeHeaders, name);

  try {
    if (!sheet.getFilter()) {
      sheet.getRange(1, 1, Math.max(sheet.getLastRow(), 2), width).createFilter();
    }
  } catch (err) {
    // Existing protected or empty filters can safely be ignored.
  }

  applyConditionalRules_(sheet, activeHeaders, name);
}

function applyHiddenColumns_(sheet, headers, name) {
  if (name !== CONFIG.RUN_SHEET_NAME) {
    return;
  }

  (CONFIG.HIDDEN_RUN_HEADERS || []).forEach(function(header) {
    const column = headers.indexOf(header) + 1;
    if (column > 0) {
      sheet.hideColumns(column);
    }
  });
}

function hiddenHeaders_(sheet, headers) {
  const actualHeaders = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].map(String);
  return actualHeaders.filter(function(header, index) {
    try {
      return sheet.isColumnHiddenByUser(index + 1);
    } catch (err) {
      return false;
    }
  });
}

function applyConditionalRules_(sheet, headers, name) {
  const rows = Math.max(sheet.getMaxRows() - 1, 1);
  const rules = [];
  const statusColumn = headers.indexOf('Statut') + 1;
  const severityColumn = headers.indexOf('Gravite') + 1;

  function addTextRule(column, text, bg, fg) {
    if (column <= 0) {
      return;
    }
    rules.push(SpreadsheetApp.newConditionalFormatRule()
      .whenTextContains(text)
      .setBackground(bg)
      .setFontColor(fg)
      .setRanges([sheet.getRange(2, column, rows, 1)])
      .build());
  }

  addTextRule(statusColumn, 'attente', '#fff3e8', '#c55300');
  addTextRule(statusColumn, 'pending', '#fff3e8', '#c55300');
  addTextRule(statusColumn, 'cours', '#e9f2ff', '#0957c3');
  addTextRule(statusColumn, 'running', '#e9f2ff', '#0957c3');
  addTextRule(statusColumn, 'inprogress', '#e9f2ff', '#0957c3');
  addTextRule(statusColumn, 'corrige', '#e9f8ee', '#0f7d3b');
  addTextRule(statusColumn, 'success', '#e9f8ee', '#0f7d3b');
  addTextRule(statusColumn, 'reussi', '#e9f8ee', '#0f7d3b');
  addTextRule(statusColumn, 'succes', '#e9f8ee', '#0f7d3b');
  addTextRule(statusColumn, 'succès', '#e9f8ee', '#0f7d3b');
  addTextRule(statusColumn, 'completed', '#e9f8ee', '#0f7d3b');
  addTextRule(statusColumn, 'termine', '#e9f8ee', '#0f7d3b');
  addTextRule(statusColumn, 'finished', '#e9f8ee', '#0f7d3b');
  addTextRule(statusColumn, 'warning', '#fff3e8', '#c55300');
  addTextRule(statusColumn, 'avertissement', '#fff3e8', '#c55300');
  addTextRule(statusColumn, 'partial', '#fff3e8', '#c55300');
  addTextRule(statusColumn, 'error', '#ffe9ed', '#d4001d');
  addTextRule(statusColumn, 'erreur', '#ffe9ed', '#d4001d');
  addTextRule(statusColumn, 'failed', '#ffe9ed', '#d4001d');
  addTextRule(statusColumn, 'echec', '#ffe9ed', '#d4001d');
  addTextRule(statusColumn, 'bloque', '#e9f2ff', '#0957c3');
  addTextRule(statusColumn, 'delai', '#e9f2ff', '#0957c3');
  addTextRule(statusColumn, 'timeout', '#e9f2ff', '#0957c3');
  addTextRule(statusColumn, 'interrompu', '#e9f2ff', '#0957c3');
  addTextRule(severityColumn, 'critical', '#ffe9ed', '#d4001d');
  addTextRule(severityColumn, 'critique', '#ffe9ed', '#d4001d');
  addTextRule(severityColumn, 'haute', '#fff3e8', '#c55300');
  addTextRule(severityColumn, 'high', '#fff3e8', '#c55300');

  if (rules.length) {
    sheet.setConditionalFormatRules(rules);
  }
}

function updateSummarySheet_(book) {
  const sheet = book.getSheetByName(CONFIG.SUMMARY_SHEET_NAME) || book.insertSheet(CONFIG.SUMMARY_SHEET_NAME);
  const errors = readObjects_(ensureSheet_(book, CONFIG.ERROR_SHEET_NAME, ERROR_HEADERS));
  const runs = dashboardRuns_(readObjects_(ensureSheet_(book, CONFIG.RUN_SHEET_NAME, RUN_HEADERS)));
  const stats = successRateStats_(runs);
  const tools = buildToolSummary_(errors, runs);
  const topErrors = objectToSortedList_(errors.reduce(function(map, error) {
    const message = String(error.Message || '(message vide)');
    map[message] = (map[message] || 0) + 1;
    return map;
  }, {})).slice(0, 8);
  const topRow = 13 + Math.max(tools.length, 1);
  const rows = Math.max(40, topRow + topErrors.length);
  ensureGridCapacity_(sheet, rows, 5);
  const properties = PropertiesService.getScriptProperties();
  const layoutKey = 'LDLC_SUMMARY_LAYOUT_' + sheet.getSheetId();
  // La mise en forme/les fusions ne font pas partie du chemin de chaque POST.
  if (properties.getProperty(layoutKey) !== '2') {
    sheet.getRange(1, 1, rows, 5).breakApart();
    clearSheetDataValidations_(sheet);
    sheet.getRange(1, 1, 1, 5).merge().setBackground('#06286b').setFontColor('#ffffff').setFontWeight('bold').setFontSize(14);
    sheet.getRange(2, 1, 1, 5).merge().setFontColor('#63709a');
    sheet.getRange(4, 1, 6, 1).setFontWeight('bold').setBackground('#eef4ff');
    sheet.getRange(4, 2, 6, 1).setFontWeight('bold');
    sheet.getRange(11, 1, 1, 5).setBackground('#06286b').setFontColor('#ffffff').setFontWeight('bold');
    sheet.setFrozenRows(1);
    [520, 140, 180, 180, 140].forEach(function(width, index) { sheet.setColumnWidth(index + 1, width); });
    properties.setProperty(layoutKey, '2');
  }
  sheet.getRange(1, 1).setValue('LDLC PrepTool - Synthese du suivi');
  sheet.getRange(2, 1).setValue('Derniere mise a jour : ' + formatDateTime_(new Date()));
  sheet.getRange(4, 1, 6, 2).setValues([
    ['Erreurs totales', errors.length],
    ['Erreurs critiques / hautes', errors.filter(function(error) { return /critical|critique|haute|high/.test(String(error.Gravite || '').toLowerCase()); }).length],
    ['Executions', runs.length], ['Executions en echec', stats.failed],
    ['Executions validees', stats.success], ['Taux de reussite', stats.rate + '%']
  ]);
  const oldRows = number_(properties.getProperty(layoutKey + '_ROWS'));
  ensureGridCapacity_(sheet, Math.max(rows, oldRows), 5);
  sheet.getRange(11, 1, Math.max(rows, oldRows) - 10, 5).clearContent();
  sheet.getRange(11, 1, 1, 5).setValues([['Rubrique', 'Executions', 'Erreurs', 'Avertissements', 'Critiques']]);
  if (tools.length) sheet.getRange(12, 1, tools.length, 5).setValues(tools.map(function(tool) {
    return [tool.label, tool.runs, tool.errors, tool.warnings, tool.criticals];
  }));
  sheet.getRange(topRow, 1, 1, 2).setValues([['Top erreurs', 'Occurrences']]);
  if (topErrors.length) sheet.getRange(topRow + 1, 1, topErrors.length, 2).setValues(topErrors.map(function(error) { return [error.label, error.count]; }));
  properties.setProperty(layoutKey + '_ROWS', String(rows));
}

function appendRows_(sheet, rows, canonicalHeaders) {
  if (!rows || !rows.length) {
    return;
  }

  const actualHeaders = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].map(function(value) {
    return String(value || '').trim();
  });
  const canonicalIndexes = {};
  canonicalHeaders.forEach(function(header, index) {
    canonicalIndexes[normalizedKey_(header)] = index;
  });
  const alignedRows = rows.map(function(row) {
    return actualHeaders.map(function(header) {
      const index = canonicalIndexes[normalizedKey_(header)];
      return index === undefined ? '' : row[index];
    });
  });

  const firstRow = sheet.getLastRow() + 1;
  const oldCapacity = sheet.getMaxRows();
  ensureGridCapacity_(sheet, firstRow + alignedRows.length - 1, actualHeaders.length);
  if (sheet.getMaxRows() > oldCapacity) {
    // Extend the existing column formats before Sheets can coerce versions to dates.
    sheet.getRange(oldCapacity, 1, 1, actualHeaders.length).copyFormatToRange(
      sheet.getSheetId(), 1, actualHeaders.length, oldCapacity + 1, sheet.getMaxRows());
  }
  sheet.getRange(firstRow, 1, alignedRows.length, actualHeaders.length).setValues(alignedRows);
}

function appendRowsUniqueByKey_(sheet, rows, canonicalHeaders, keyHeaders, onUniqueRow) {
  if (!rows || !rows.length) {
    return;
  }

  const actualHeaders = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].map(function(value) {
    return String(value || '').trim();
  });
  const canonicalIndexes = {};
  canonicalHeaders.forEach(function(header, index) {
    canonicalIndexes[normalizedKey_(header)] = index;
  });
  const keyColumnIndexes = (keyHeaders || []).map(function(header) {
    return actualHeaders.findIndex(function(actualHeader) {
      return normalizedKey_(actualHeader) === normalizedKey_(header);
    });
  }).filter(function(index) { return index >= 0; });

  if (!keyColumnIndexes.length) {
    appendRows_(sheet, rows, canonicalHeaders);
    return;
  }

  function rowKey_(row) {
    const parts = keyColumnIndexes.map(function(index) {
      return text_(row[index]);
    });
    if (!parts.some(function(part) { return part !== ''; })) {
      return '';
    }
    return parts.join('|');
  }

  const existingKeys = {};
  const lastRow = sheet.getLastRow();
  if (lastRow >= 2) {
    const existingValues = sheet.getRange(2, 1, lastRow - 1, actualHeaders.length).getValues();
    existingValues.forEach(function(row) {
      const key = rowKey_(row);
      if (key && !existingKeys[key]) {
        existingKeys[key] = true;
        if (onUniqueRow) onUniqueRow(row, actualHeaders);
      }
    });
  }

  const alignedRows = [];
  rows.forEach(function(row) {
    const aligned = actualHeaders.map(function(header) {
      const index = canonicalIndexes[normalizedKey_(header)];
      return index === undefined ? '' : row[index];
    });
    const key = rowKey_(aligned);
    if (key && existingKeys[key]) {
      return;
    }
    if (key) {
      existingKeys[key] = true;
    }
    if (onUniqueRow) onUniqueRow(aligned, actualHeaders);
    alignedRows.push(aligned);
  });

  if (alignedRows.length) {
    ensureGridCapacity_(sheet, sheet.getLastRow() + alignedRows.length, actualHeaders.length);
    sheet.getRange(sheet.getLastRow() + 1, 1, alignedRows.length, actualHeaders.length).setValues(alignedRows);
  }
}

function rowsByKey_(sheet, keyHeader) {
  const rows = Object.create(null);
  readObjects_(sheet).forEach(function(row) {
    const key = text_(getAny_(row, [keyHeader]));
    if (key) {
      rows[key] = preferredStoredRun_(rows[key], row);
    }
  });
  return rows;
}

function maintainRunRows_(apply, includeRows) {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const book = getSpreadsheet_();
    const sheet = ensureSheet_(book, CONFIG.RUN_SHEET_NAME, RUN_HEADERS);
    const values = sheet.getDataRange().getValues();
    const headers = values[0].map(String);
    const groups = Object.create(null);
    values.slice(1).forEach(function(row, index) {
      const record = objectFromRow_(headers, row);
      const key = text_(getAny_(record, ['RunId']));
      if (!key) return;
      if (!groups[key]) groups[key] = [];
      groups[key].push({ row: index + 2, record: record });
    });
    const duplicates = [];
    Object.keys(groups).forEach(function(key) {
      const entries = groups[key];
      if (entries.length < 2) return;
      const preferred = entries.reduce(function(best, entry) { return preferredStoredRun_(best, entry.record); }, null);
      const keep = entries.find(function(entry) { return entry.record === preferred; });
      duplicates.push({ runId: key, keepRow: keep.row, removeRows: entries.filter(function(entry) { return entry !== keep; }).map(function(entry) { return entry.row; }) });
    });
    const removedRows = [].concat.apply([], duplicates.map(function(group) { return group.removeRows; }));
    if (apply) {
      removedRows.sort(function(a, b) { return b - a; }).forEach(function(row) { sheet.deleteRow(row); });
      if (removedRows.length) updateSummarySheet_(book);
    }
    return {
      ok: true, spreadsheetId: book.getId(), sheetId: sheet.getSheetId(),
      headers: headers, rowsBefore: values.length - 1, duplicateGroups: duplicates,
      removed: apply ? removedRows.length : 0,
      values: includeRows ? values : undefined
    };
  } finally { lock.releaseLock(); }
}

function preferredStoredRun_(current, candidate) {
  if (!current) return candidate;
  if (isFinalRun_(current) !== isFinalRun_(candidate)) return isFinalRun_(candidate) ? candidate : current;
  const a = number_(getAny_(current, ['Sequence', 'updateSequence']));
  const b = number_(getAny_(candidate, ['Sequence', 'updateSequence']));
  if (a && b && a !== b) return b > a ? candidate : current;
  const stamp = function(run) {
    const date = validDate_(getAny_(run, ['DerniereMaj', 'LastUpdatedAt', 'RecuLe', 'ReceivedAt']));
    return date ? date.getTime() : 0;
  };
  return stamp(candidate) >= stamp(current) ? candidate : current;
}

function deleteRowsByColumnValue_(sheet, columnHeader, value) {
  const target = text_(value);
  if (!target || sheet.getLastRow() < 2) {
    return 0;
  }

  const headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].map(function(header) {
    return String(header || '').trim();
  });
  const columnIndex = headers.findIndex(function(header) {
    return normalizedKey_(header) === normalizedKey_(columnHeader);
  });
  if (columnIndex < 0) {
    return 0;
  }

  const values = sheet.getRange(2, columnIndex + 1, sheet.getLastRow() - 1, 1).getValues();
  const rowsToDelete = [];
  values.forEach(function(row, index) {
    if (text_(row[0]) === target) {
      rowsToDelete.push(index + 2);
    }
  });
  rowsToDelete.sort(function(a, b) { return b - a; }).forEach(function(rowNumber) {
    sheet.deleteRow(rowNumber);
  });
  return rowsToDelete.length;
}

function upsertRowsByKey_(sheet, rows, canonicalHeaders, keyHeader) {
  if (!rows || !rows.length) {
    return;
  }

  const actualHeaders = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].map(function(value) {
    return String(value || '').trim();
  });
  const canonicalIndexes = {};
  canonicalHeaders.forEach(function(header, index) {
    canonicalIndexes[normalizedKey_(header)] = index;
  });

  const keyColumnIndex = actualHeaders.findIndex(function(header) {
    return normalizedKey_(header) === normalizedKey_(keyHeader);
  });
  if (keyColumnIndex < 0) {
    appendRows_(sheet, rows, canonicalHeaders);
    return;
  }

  const existingRows = {};
  const lastRow = sheet.getLastRow();
  if (lastRow >= 2) {
    const keyValues = sheet.getRange(2, keyColumnIndex + 1, lastRow - 1, 1).getValues();
    keyValues.forEach(function(row, index) {
      const key = text_(row[0]);
      if (key) {
        if (!existingRows[key]) {
          existingRows[key] = [];
        }
        existingRows[key].push(index + 2);
      }
    });
  }

  const incomingByKey = {};
  const incomingWithoutKey = [];
  rows.forEach(function(row) {
    const aligned = actualHeaders.map(function(header) {
      const index = canonicalIndexes[normalizedKey_(header)];
      return index === undefined ? '' : row[index];
    });
    const key = text_(aligned[keyColumnIndex]);
    if (key) {
      incomingByKey[key] = aligned;
    } else {
      incomingWithoutKey.push(aligned);
    }
  });

  const toAppend = [];
  const duplicateRowsToDelete = [];
  Object.keys(incomingByKey).forEach(function(key) {
    const aligned = incomingByKey[key];
    const existing = existingRows[key] || [];
    if (existing.length) {
      const keepRow = existing[existing.length - 1];
      const oldValues = sheet.getRange(keepRow, 1, 1, actualHeaders.length).getValues()[0];
      actualHeaders.forEach(function(header, index) {
        if (canonicalIndexes[normalizedKey_(header)] === undefined) aligned[index] = oldValues[index];
      });
      sheet.getRange(keepRow, 1, 1, actualHeaders.length).setValues([aligned]);
      existing.slice(0, -1).forEach(function(rowNumber) {
        duplicateRowsToDelete.push(rowNumber);
      });
    } else {
      toAppend.push(aligned);
    }
  });
  incomingWithoutKey.forEach(function(aligned) {
    toAppend.push(aligned);
  });

  if (toAppend.length) {
    ensureGridCapacity_(sheet, sheet.getLastRow() + toAppend.length, actualHeaders.length);
    sheet.getRange(sheet.getLastRow() + 1, 1, toAppend.length, actualHeaders.length).setValues(toAppend);
  }

  duplicateRowsToDelete.sort(function(a, b) { return b - a; }).forEach(function(rowNumber) {
    sheet.deleteRow(rowNumber);
  });
}

function readObjects_(sheet) {
  const values = sheet.getDataRange().getValues();
  if (values.length < 2) {
    return [];
  }
  const headers = values[0].map(String);
  return values.slice(1).filter(function(row) {
    return row.some(function(cell) { return cell !== '' && cell !== null; });
  }).map(function(row) {
    const obj = {};
    headers.forEach(function(header, index) {
      obj[header] = row[index];
    });
    return obj;
  });
}

function getAny_(obj, keys, fallback) {
  if (!obj) {
    return fallback;
  }
  for (let i = 0; i < keys.length; i++) {
    if (Object.prototype.hasOwnProperty.call(obj, keys[i])) {
      return obj[keys[i]];
    }
  }

  const normalized = {};
  Object.keys(obj).forEach(function(key) {
    const compact = normalizedKey_(key);
    if (!Object.prototype.hasOwnProperty.call(normalized, compact)) {
      normalized[compact] = obj[key];
    }
  });
  for (let i = 0; i < keys.length; i++) {
    const compact = normalizedKey_(keys[i]);
    if (Object.prototype.hasOwnProperty.call(normalized, compact)) {
      return normalized[compact];
    }
  }

  return fallback;
}

function normalizedKey_(value) {
  return String(value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '');
}

function errorStatusKey_(status) {
  status = String(status || '');
  return status.indexOf('failed') >= 0 ||
    status.indexOf('failure') >= 0 ||
    status.indexOf('echec') >= 0 ||
    status.indexOf('error') >= 0 ||
    status.indexOf('erreur') >= 0 ||
    status.indexOf('critical') >= 0 ||
    status.indexOf('critique') >= 0;
}

function warningStatusKey_(status) {
  status = String(status || '');
  return status.indexOf('warning') >= 0 ||
    status.indexOf('warn') >= 0 ||
    status.indexOf('avertissement') >= 0 ||
    status.indexOf('partial') >= 0 ||
    status.indexOf('partiel') >= 0 ||
    status.indexOf('partielle') >= 0;
}

function successStatusKey_(status) {
  if (errorStatusKey_(status) || warningStatusKey_(status)) {
    return false;
  }
  return !status ||
    status.indexOf('termine') >= 0 ||
    status.indexOf('termin') >= 0 ||
    status.indexOf('success') >= 0 ||
    status.indexOf('succes') >= 0 ||
    status.indexOf('succe') >= 0 ||
    status.indexOf('succ') >= 0 ||
    status.indexOf('reussi') >= 0 ||
    status.indexOf('completed') >= 0 ||
    status.indexOf('complete') >= 0 ||
    status.indexOf('finished') >= 0 ||
    ['ok', 'done', 'termineavecsucces'].indexOf(status) >= 0;
}

function runState_(run) {
  const status = normalizedKey_(inferredRunStatus_(run));
  if (['running', 'encours', 'inprogress', 'stopped', 'interrompu', 'cancelled', 'annule', 'annulee'].indexOf(status) >= 0 || /timeout|bloque|delai/.test(status)) return 'info';
  const errors = number_(getAny_(run, ['Erreurs', 'ErrorCount', 'errors', 'errorsCount', 'nombreErreurs']));
  const warnings = number_(getAny_(run, ['Avertissements', 'WarningCount', 'warnings', 'warningsCount', 'nombreAvertissements']));
  const criticals = number_(getAny_(run, ['Critiques', 'CriticalCount', 'criticals', 'criticalsCount', 'nombreCritiques']));

  if (errors > 0 || criticals > 0 || errorStatusKey_(status)) {
    return 'error';
  }
  if (warnings > 0 || warningStatusKey_(status)) {
    return 'warning';
  }
  if (['running', 'encours', 'inprogress'].indexOf(status) >= 0) {
    return 'info';
  }
  if (status.indexOf('bloque') >= 0 || status.indexOf('delai') >= 0 || status.indexOf('timeout') >= 0) {
    return 'info';
  }
  if (['stopped', 'interrompu', 'cancelled', 'annule', 'annulee'].indexOf(status) >= 0) {
    return 'info';
  }
  if (successStatusKey_(status)) {
    return 'success';
  }
  return 'info';
}

function successRateStats_(runs) {
  const stats = { success: 0, failed: 0, warning: 0, interrupted: 0, timeout: 0, running: 0, eligible: 0, rate: 0, errorRate: 0 };
  (runs || []).forEach(function(run) {
    const state = runState_(run);
    const status = normalizedKey_(getAny_(run, ['status', 'Statut', 'Status'], ''));
    if (status.indexOf('interrompu') >= 0 || status.indexOf('stopped') >= 0 || status.indexOf('cancel') >= 0 || status.indexOf('annul') >= 0) {
      stats.interrupted += 1;
    } else if (/timeout|bloque|delai/.test(status)) {
      stats.timeout += 1;
    } else if (state === 'success') {
      stats.success += 1;
    } else if (state === 'error') {
      stats.failed += 1;
    } else if (state === 'warning') {
      stats.warning += 1;
    } else {
      stats.running += 1;
    }
  });
  stats.eligible = stats.success + stats.failed + stats.warning;
  stats.rate = stats.eligible ? Math.round(stats.success / stats.eligible * 100) : 0;
  stats.errorRate = stats.eligible ? Math.round(stats.failed / stats.eligible * 100) : 0;
  return stats;
}

function dateValue_(value) {
  const date = asDate_(value);
  return date && !isNaN(date.getTime()) ? date : '';
}

function validDate_(value) {
  const date = asDate_(value);
  return date && !isNaN(date.getTime()) ? date : null;
}

function elapsedSeconds_(start, end) {
  const startDate = validDate_(start);
  const endDate = validDate_(end);
  if (!startDate || !endDate || endDate.getTime() < startDate.getTime()) {
    return 0;
  }
  return Math.round((endDate.getTime() - startDate.getTime()) / 1000);
}

function asDate_(value) {
  if (value instanceof Date) {
    return value;
  }
  if (!value) {
    return new Date(NaN);
  }
  return new Date(value);
}

function formatDateTime_(date) {
  if (!date || isNaN(date.getTime())) {
    return '';
  }
  return Utilities.formatDate(date, CONFIG.TIMEZONE || Session.getScriptTimeZone(), 'dd/MM/yyyy HH:mm:ss');
}

function periodKey_(date, period) {
  if (period === 'month') {
    return Utilities.formatDate(date, CONFIG.TIMEZONE, 'yyyy-MM');
  }
  if (period === 'week') {
    return Utilities.formatDate(date, CONFIG.TIMEZONE, 'yyyy') + '-S' + Utilities.formatDate(date, CONFIG.TIMEZONE, 'ww');
  }
  return Utilities.formatDate(date, CONFIG.TIMEZONE, 'yyyy-MM-dd');
}

function objectToSortedList_(obj) {
  return Object.keys(obj).map(function(key) {
    return { label: key, count: obj[key] };
  }).sort(function(a, b) {
    return b.count - a.count || String(a.label).localeCompare(String(b.label));
  });
}

function payloadApplicationSource_(primary, secondary) {
  const aliases = ['ApplicationSource', 'applicationSource', 'application_source', 'typePreparation', 'type_preparation'];
  const toolAliases = ['Source', 'Outil', 'tool', 'application'];
  const explicit = getAny_(primary, aliases, getAny_(secondary, aliases));
  const tool = getAny_(primary, toolAliases, getAny_(secondary, toolAliases));
  const hints = ['Edition', 'edition', 'Brand', 'brand', 'Marque', 'marque', 'ScriptPath'];
  const evidence = hints.map(function(key) {
    return text_(getAny_(primary, [key], getAny_(secondary, [key])));
  }).join(' ');
  return applicationSource_(explicit, tool, evidence);
}

function applicationSource_(value, fallbackTool, editionHint) {
  const compact = normalizedKey_(value);
  if (compact.indexOf('addon') >= 0) {
    return APPLICATION_SOURCE_ADDON;
  }
  // Older Numerik's builds sent the LDLC source; a named exe path is reliable evidence.
  if (compact.indexOf('numerik') >= 0 || normalizedKey_(fallbackTool).indexOf('numerik') >= 0 ||
      normalizedKey_(editionHint).indexOf('numerik') >= 0) {
    return APPLICATION_SOURCE_NUMERIKS;
  }
  if (compact.indexOf('preparationpc') >= 0 || compact.indexOf('preptool') >= 0 || compact === 'pc') {
    return APPLICATION_SOURCE_PC;
  }
  return toolKey_(fallbackTool) === 'addon-sport' ? APPLICATION_SOURCE_ADDON : APPLICATION_SOURCE_PC;
}

function applicationSourceLabel_(value) {
  const source = applicationSource_(value);
  if (source === APPLICATION_SOURCE_ADDON) return 'Preparation ADDON';
  return source === APPLICATION_SOURCE_NUMERIKS ? "All In App Numerik's" : 'All In App LDLC';
}

function toolKey_(value) {
  const compact = String(value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '');

  if (!compact) {
    return 'unknown';
  }
  if (compact.indexOf('addonsport') >= 0 || (compact.indexOf('addon') >= 0 && compact.indexOf('sport') >= 0)) {
    return 'addon-sport';
  }
  if (compact.indexOf('ldlcpreparationpc') >= 0 || compact.indexOf('preparationpc') >= 0 || compact.indexOf('preptool') >= 0) {
    return 'prep-tool';
  }
  return compact;
}

function toolLabel_(value) {
  const key = toolKey_(value);
  if (key === 'addon-sport') {
    return 'Preparation Addon Sport';
  }
  if (key === 'prep-tool') {
    return 'Preparation PC';
  }
  if (key === 'unknown') {
    return 'Rubrique non renseignee';
  }
  return String(value || key);
}

function ensureToolSummary_(map, key, label) {
  if (!map[key]) {
    map[key] = {
      key: key,
      label: label || toolLabel_(key),
      runs: 0,
      errors: 0,
      warnings: 0,
      criticals: 0
    };
  }
  return map[key];
}

function buildToolSummary_(errors, runs) {
  const map = {};
  ensureToolSummary_(map, APPLICATION_SOURCE_PC, 'All In App LDLC');
  ensureToolSummary_(map, APPLICATION_SOURCE_NUMERIKS, "All In App Numerik's");
  ensureToolSummary_(map, APPLICATION_SOURCE_ADDON, 'Preparation ADDON');

  runs.forEach(function(run) {
    const key = payloadApplicationSource_(run, {});
    const item = ensureToolSummary_(map, key, applicationSourceLabel_(key));
    item.runs += 1;
    item.warnings += number_(getAny_(run, ['Avertissements', 'warnings']));
    item.criticals += number_(getAny_(run, ['Critiques', 'criticals']));
  });

  errors.forEach(function(err) {
    const key = payloadApplicationSource_(err, {});
    const item = ensureToolSummary_(map, key, applicationSourceLabel_(key));
    const severity = String(err.Gravite || '').toLowerCase();
    item.errors += 1;
    if (severity.indexOf('critical') >= 0 || severity.indexOf('critique') >= 0 || severity.indexOf('haute') >= 0 || severity.indexOf('high') >= 0) {
      item.criticals += 1;
    }
  });

  const order = {};
  order[APPLICATION_SOURCE_PC] = 0;
  order[APPLICATION_SOURCE_NUMERIKS] = 1;
  order[APPLICATION_SOURCE_ADDON] = 2;
  return Object.keys(map).map(function(key) {
    return map[key];
  }).sort(function(a, b) {
    const ao = Object.prototype.hasOwnProperty.call(order, a.key) ? order[a.key] : 99;
    const bo = Object.prototype.hasOwnProperty.call(order, b.key) ? order[b.key] : 99;
    return ao - bo || String(a.label).localeCompare(String(b.label));
  });
}

function tags_(value) {
  if (Array.isArray(value)) {
    return value.join(', ');
  }
  return text_(value);
}

function text_(value) {
  if (value === null || value === undefined) {
    return '';
  }
  return String(value);
}

function number_(value) {
  const n = Number(value || 0);
  return isNaN(n) ? 0 : n;
}

function booleanText_(value) {
  if (value === true) return 'oui';
  if (value === false) return 'non';
  const normalized = normalizedKey_(value);
  if (!normalized) return '';
  return ['true', 'yes', 'oui', '1', 'final'].indexOf(normalized) >= 0 ? 'oui' : 'non';
}

function clip_(value, max) {
  const text = String(value || '');
  return text.length > max ? text.slice(0, max - 3) + '...' : text;
}

function esc_(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function json_(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function setupTelemetry() {
  const ss = getSpreadsheet_();
  ensureSheet_(ss, CONFIG.ERROR_SHEET_NAME, ERROR_HEADERS);
  ensureSheet_(ss, CONFIG.RUN_SHEET_NAME, RUN_HEADERS);
  updateSummarySheet_(ss);
  return {
    ok: true,
    spreadsheetId: ss.getId(),
    spreadsheetUrl: ss.getUrl(),
    webAppUrl: ScriptApp.getService().getUrl()
  };
}
