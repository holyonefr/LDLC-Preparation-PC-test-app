const fs = require('fs');
const path = require('path');

const playwrightCandidates = [
  process.env.LDLC_PLAYWRIGHT_PACKAGE,
  'playwright'
].filter(Boolean);

let playwright;
for (const candidate of playwrightCandidates) {
  try {
    playwright = require(candidate);
    break;
  } catch (err) {
    // Try the next bundled runtime location.
  }
}

if (!playwright) {
  throw new Error('Playwright introuvable dans les runtimes Codex.');
}

const { chromium } = playwright;

const projectId = '19Sn2qzKl3XwTV8Gxq1RLELhJcg5Uy-iXk_YglKJlggyduRai_xZL9WhP';
const projectUrlCandidates = [
  process.env.LDLC_APPS_SCRIPT_PROJECT_URL,
  `https://script.google.com/home/projects/${projectId}/edit`,
  `https://script.google.com/u/0/home/projects/${projectId}/edit`,
  `https://script.google.com/u/1/home/projects/${projectId}/edit`
].filter(Boolean);
const webAppUrl = 'https://script.google.com/macros/s/AKfycbwYe2r5-y8HeyfLjslbq7wI2BdFH0sj7TLJQSiUyeRdt_z7yytyTKsPQPPcT0HUcAci3g/exec';
const dashboardKey = 'LDLC-Dashboard-2026-288d06206918450293ed29d54fefc801';
const sourcePath = path.resolve(__dirname, 'google-apps-script', 'LDLC_ErrorTelemetry.gs');
const profileDir = process.env.LDLC_CHROME_PROFILE ||
  path.join(process.env.TEMP || process.env.TMP || process.cwd(), 'LDLCChromeProfileCodex');

async function findMonacoFrame(page) {
  for (let i = 0; i < 60; i += 1) {
    for (const frame of page.frames()) {
      const modelCount = await frame.evaluate(() => {
        if (typeof monaco === 'undefined' || !monaco.editor || !monaco.editor.getModels) {
          return 0;
        }
        return monaco.editor.getModels().length;
      }).catch(() => 0);
      if (modelCount > 0) {
        return frame;
      }
    }
    await page.waitForTimeout(1000);
  }
  throw new Error('Editeur Monaco Apps Script introuvable.');
}

async function clickFirst(page, candidates, timeout = 15000) {
  let lastError;
  for (const candidate of candidates) {
    try {
      const locator = candidate();
      await locator.click({ timeout });
      return;
    } catch (err) {
      lastError = err;
    }
  }
  throw lastError || new Error('Aucun selecteur valide.');
}

async function openProjectEditor(page) {
  let lastUrl = '';
  let lastTitle = '';

  for (const candidate of projectUrlCandidates) {
    await page.goto(candidate, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.waitForTimeout(8000);

    lastUrl = page.url();
    lastTitle = await page.title();
    console.log('PROJECT_URL=' + lastUrl);
    console.log('PROJECT_TITLE=' + lastTitle);

    if (lastUrl.includes('accounts.google.com')) {
      throw new Error('Le profil Chrome temporaire n est pas connecte au compte Google.');
    }

    if (!lastUrl.includes('developers.google.com')) {
      return;
    }
  }

  throw new Error('Impossible d ouvrir l editeur Apps Script. Derniere URL=' + lastUrl + ' Title=' + lastTitle);
}

async function main() {
  const source = fs.readFileSync(sourcePath, 'utf8');
  const context = await chromium.launchPersistentContext(profileDir, {
    executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: false,
    viewport: { width: 1600, height: 980 },
    args: [
      '--no-first-run',
      '--disable-session-crashed-bubble',
      '--disable-infobars'
    ]
  });

  const page = context.pages()[0] || await context.newPage();
  page.setDefaultTimeout(30000);
  await openProjectEditor(page);

  const frame = await findMonacoFrame(page);
  await frame.evaluate((text) => {
    const model = monaco.editor.getModels()[0];
    model.setValue(text);
  }, source);
  await page.keyboard.press('Control+S');
  await page.waitForTimeout(6000);

  await clickFirst(page, [
    () => page.getByRole('button', { name: /D\u00e9ployer|Deployer|Deploy/i }),
    () => page.getByText(/D\u00e9ployer|Deployer|Deploy/i)
  ]);
  await page.waitForTimeout(1000);
  await clickFirst(page, [
    () => page.getByRole('menuitem', { name: /G\u00e9rer les d\u00e9ploiements|Manage deployments/i }),
    () => page.getByText(/G\u00e9rer les d\u00e9ploiements|Manage deployments/i)
  ]);
  await page.waitForTimeout(3000);

  const dialog = page.getByRole('dialog', { name: /G\u00e9rer les d\u00e9ploiements|Manage deployments/i });
  await dialog.getByRole('button', { name: /Modifier|Edit/i }).click({ timeout: 30000 });
  await page.waitForTimeout(1200);
  await dialog.getByRole('combobox').first().click({ timeout: 30000 });
  await page.waitForTimeout(800);
  await page.getByRole('option', { name: /Nouvelle version|New version/i }).click({ timeout: 30000 });
  await page.waitForTimeout(800);
  await dialog.getByRole('button', { name: /D\u00e9ployer|Deployer|Deploy/i }).click({ timeout: 30000 });
  await page.waitForTimeout(8000);

  const deployed = await page.getByText(/Mise \u00e0 jour du d\u00e9ploiement effectu\u00e9e|Deployment updated/i).isVisible().catch(() => false);
  if (!deployed) {
    throw new Error('La confirmation de deploiement Apps Script n est pas visible.');
  }

  const dashboardPage = await context.newPage();
  await dashboardPage.goto(webAppUrl + '?key=' + encodeURIComponent(dashboardKey), { waitUntil: 'domcontentloaded', timeout: 90000 });
  await dashboardPage.waitForTimeout(6000);
  const title = await dashboardPage.title();
  const bodyText = await dashboardPage.locator('body').innerText({ timeout: 30000 });
  if (!title.includes('LDLC PrepTool') || (!bodyText.includes('Erreurs et executions') && !bodyText.includes('Erreurs et ex\u00e9cutions'))) {
    throw new Error('Le dashboard HTML ne semble pas charge correctement. Title=' + title);
  }

  console.log('DEPLOYED_OK=true');
  console.log('DASHBOARD_TITLE=' + title);
  console.log('DASHBOARD_URL=' + webAppUrl + '?key=' + encodeURIComponent(dashboardKey));

  await context.close();
}

main().catch(async (err) => {
  console.error(err && err.stack ? err.stack : String(err));
  process.exit(1);
});
