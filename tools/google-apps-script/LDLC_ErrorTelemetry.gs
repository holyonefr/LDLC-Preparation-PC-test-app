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
/* Preparation dashboard: matte slate, no luminous effects or graphic wallpaper. */
:root{color-scheme:dark;--blue:#8daed5;--blue2:#7899bf;--red:#e28a90;--red2:#e28a90;--green:#7fc5a0;--orange:#d9b47a;--text:#e4e8ee;--muted:#b5bfcc;--line:#465263;--panel:#252e3a;--bg:#1b222c;--shadow:none;--shadow-strong:none}
*{box-sizing:border-box;min-width:0}
html{min-width:0;background:var(--bg)}
body{margin:0;min-height:100vh;background:linear-gradient(145deg,#222b37,#1b222c 70%);color:var(--text);font-family:"Trebuchet MS",Verdana,sans-serif;font-size:14px;line-height:1.45;overflow-x:hidden}
button,input,select{font:inherit;color:inherit}
button{cursor:pointer}
button:focus-visible,input:focus-visible,select:focus-visible,summary:focus-visible{outline:2px solid var(--blue);outline-offset:3px}
svg{width:22px;height:22px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
.app-shell{width:min(100%,1800px);min-height:100vh;margin:0 auto;display:grid;grid-template-columns:264px minmax(0,1fr);gap:24px;padding:24px}
.sidebar{display:flex;flex-direction:column}
.side-nav{position:sticky;top:24px;height:calc(100vh - 48px);min-height:620px;display:flex;flex-direction:column;gap:20px;padding:18px 12px;border:1px solid var(--line);border-radius:10px;background:linear-gradient(180deg,#28323f,#222b37);overflow:auto}
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
.hero-header{position:relative;min-height:190px;margin-bottom:24px;padding:36px 24px 58px;display:grid;place-items:center;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:linear-gradient(120deg,#303c4b 0%,#293442 50%,#252f3b 100%)}
.hero-header:before{content:"";position:absolute;top:-110px;right:-70px;width:400px;height:320px;transform:rotate(-24deg);border:1px solid rgba(172,188,210,.08);background:rgba(172,188,210,.015);pointer-events:none}
.hero-line,.hero-dots,.hero-circuit,.hero-radar,.title-rule,.system-pill{display:none}
.hero-title{position:relative;z-index:1;width:100%;text-align:center}
.hero-title h1{margin:0;font-family:Bahnschrift,"Trebuchet MS",sans-serif;font-size:clamp(30px,3vw,44px);line-height:1.2;font-weight:600;letter-spacing:.01em;text-shadow:none}
.hero-title p{margin:10px 0 0;font-size:13px;color:var(--muted);letter-spacing:.02em}
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
.card-icon{width:38px;height:38px;display:grid;place-items:center;border-radius:8px;background:#263342;color:var(--blue);margin-bottom:20px}
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
.mini-track{height:3px;background:#303843;border-radius:3px;overflow:hidden;margin-top:9px}
.mini-track i{display:block;height:100%;background:var(--red)}
.recent-panel{margin-top:24px}
.panel-head{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:18px}
.panel-head h2{margin:0;font-size:18px}
.table-actions{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.search-box{flex:1 1 220px;max-width:292px;height:40px;display:flex;align-items:center;gap:10px;padding:0 12px;background:#222b37;border:1px solid var(--line);border-radius:6px}
.search-box svg{width:18px;height:18px;color:var(--muted)}
.search-box input{width:100%;border:0;outline:0;background:transparent;font-size:13px}
.search-box input::placeholder{color:var(--muted)}
select{height:40px;min-width:150px;max-width:100%;padding:0 12px;border:1px solid var(--line);border-radius:6px;background:#222b37;font-size:13px}
.table-wrap{overflow:auto;border:1px solid var(--line);border-radius:6px;background:#222b37}
table{width:100%;border-collapse:collapse;min-width:900px;table-layout:fixed}
th,td{padding:13px 12px;border-bottom:1px solid var(--line);text-align:left;vertical-align:middle;font-size:12px;overflow-wrap:anywhere}
th{position:sticky;top:0;z-index:1;background:#313d4c;color:#c6cfdb;font-weight:500}
td{color:#c3cbd6}
tbody tr:hover{background:#2e3b4b}
.pill{display:inline-flex;align-items:center;justify-content:center;min-height:26px;max-width:100%;padding:4px 9px;border:1px solid transparent;border-radius:5px;font-size:11px;font-weight:500;line-height:1.3;text-align:center;white-space:normal;overflow-wrap:anywhere;vertical-align:middle}
.pill.wait{background:#332e29;border-color:#5b4b37;color:var(--orange)}
.pill.crit{background:#34282f;border-color:#62434b;color:var(--red)}
.pill.ok{background:#24332e;border-color:#3c5b4e;color:var(--green)}
.pill.info{background:#263342;border-color:#425670;color:var(--blue)}
.application-badge{display:inline-block;padding:4px 8px;border:1px solid #425670;border-radius:5px;background:#263342;color:#b3c8e2;font-size:11px;font-weight:500;line-height:1.4}
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
.issue-details summary{list-style:none;display:inline-flex;align-items:center;min-height:32px;max-width:100%;padding:4px 10px;border:1px solid #425670;border-radius:5px;color:#c6d7ec;background:#263342;font-size:12px;cursor:pointer;white-space:normal;overflow-wrap:anywhere}
.issue-details summary::-webkit-details-marker{display:none}
.issue-details[open] summary{background:#3b4d63}
.issue-details .toggle-open{display:none}
.issue-details[open] .toggle-open{display:inline}
.issue-details[open] .toggle-closed{display:none}
.issue-list{display:grid;gap:10px;margin-top:12px;width:min(680px,100%);min-width:0;max-width:100%}
.run-issue-list{width:min(760px,100%)}
.issue-item{min-width:0;max-width:100%;padding:10px 12px;border:1px solid var(--line);border-radius:6px;background:#222b37;white-space:normal;overflow-wrap:anywhere}
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
.dashboard-toast{position:fixed;right:22px;bottom:22px;z-index:80;max-width:min(420px,calc(100vw - 44px));padding:14px 16px;border:1px solid #425670;border-radius:8px;background:#222d3b;color:var(--text);font-weight:500;line-height:1.5;opacity:0;transform:translateY(8px);pointer-events:none;transition:opacity .15s ease,transform .15s ease}
.dashboard-toast.visible{opacity:1;transform:translateY(0)}
.dashboard-toast.success{border-color:#3c5b4e;background:#24332e}
.dashboard-toast.error{border-color:#62434b;background:#34282f}
.login{min-height:100vh;display:grid;place-items:center;background:linear-gradient(145deg,#222b37,#1b222c)}
.login form{width:min(410px,calc(100vw - 40px));padding:30px;background:var(--panel);border:1px solid var(--line);border-radius:8px}
.login h1{font-family:Bahnschrift,"Trebuchet MS",sans-serif;font-size:30px;font-weight:600;line-height:1.2}
.login p{color:var(--muted);font-size:13px}
.login input,.login button{width:100%;height:42px;margin-top:12px;padding:0 12px;border:1px solid var(--line);border-radius:6px;background:#222b37}
.login button{background:#3b4d63;border-color:#4c617d}
@media(max-width:1650px){.dashboard-grid{grid-template-columns:1fr}.side-summary{grid-template-columns:repeat(2,minmax(0,1fr))}.chart-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:1180px){.app-shell{grid-template-columns:1fr;padding:18px}.sidebar{display:none}.mobile-application-tabs,.mobile-nav{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;margin-bottom:12px}.mobile-nav{grid-template-columns:repeat(5,minmax(0,1fr));margin-bottom:22px}.mobile-nav .nav-item{border-color:var(--line);justify-content:center;background:var(--panel)}.mobile-nav .nav-item.active{background:#3b4d63;border-color:#455974}.hero-title h1{font-size:36px}.hero-header{min-height:178px}.filters{grid-template-columns:1fr}.date-filter{width:min(240px,100%)}.period-tabs{grid-template-columns:repeat(4,minmax(0,1fr))}.kpi-row{grid-template-columns:repeat(2,minmax(0,1fr))}.panel-head{align-items:flex-start;flex-direction:column}.table-actions{width:100%}.search-box{max-width:none}.table-actions select{flex:1 1 150px}}
@media(max-width:760px){.app-shell{padding:10px;gap:12px}.hero-header{min-height:165px;padding:28px 14px 62px}.hero-title h1{font-size:30px;letter-spacing:0}.hero-title p{font-size:12px}.account-block{right:14px;left:14px;justify-content:center;font-size:11px}.mobile-application-tabs,.mobile-nav{grid-template-columns:repeat(2,minmax(0,1fr))}.application-tab{font-size:12px;padding:8px}.mobile-nav .nav-item{font-size:12px;gap:8px;justify-content:flex-start}.period-tabs{grid-template-columns:repeat(2,minmax(0,1fr))}.date-filter{width:100%}.card{min-height:190px;padding:18px}.card b{font-size:32px}.card span{font-size:12px}.side-summary,.chart-grid{grid-template-columns:1fr}.panel{padding:18px}.chart-card,.top-errors{min-height:260px}.focus-grid,.report-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.table-wrap{overflow:visible;border:0;background:transparent}.table-wrap table{min-width:0}.table-wrap thead{display:none}.table-wrap tbody,.table-wrap tr,.table-wrap td{display:block;width:100%}.table-wrap tr{margin-bottom:12px;border:1px solid var(--line);border-radius:6px;background:#222b37;overflow:hidden}.table-wrap td{display:grid;grid-template-columns:108px minmax(0,1fr);gap:12px;padding:11px 12px;border-bottom:1px solid var(--line)}.table-wrap td:last-child{border-bottom:0}.table-wrap td:before{content:attr(data-label);font-weight:500;color:var(--muted)}.empty-row td{display:block;text-align:center}.empty-row td:before{content:""}.pill{white-space:normal}}
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
