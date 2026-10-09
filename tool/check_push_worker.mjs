// Prüft den Web-Push-Worker gegen einen echten Chrome (#34; PilzBuddy
// 1.203.0 als Vorlage).
//
//     node tool/check_push_worker.mjs
//
// **Warum überhaupt.** Der Worker entscheidet, ob eine Meldung im Browser
// erscheint, und ein Fehler darin ist von außen unsichtbar: FCM quittiert
// den Versand mit „ok", und dann passiert nichts (PilzBuddy, 2026-09-24:
// Nachrichten gingen nachweislich hinaus, in der Vorschau-PWA kam keine
// an). `flutter test` startet keinen Browser, und Textprüfungen fangen
// keine falsche Entscheidung.
//
// **Gesendet wird WIRKLICH.** `ServiceWorker.deliverPushMessage` legt eine
// Meldung so in den Worker, wie der Push-Dienst des Browsers es täte —
// dasselbe `push`-Ereignis, dieselbe Nutzlast wie von FCM. Nur FCM selbst
// fehlt.
//
// Aufgebaut wie auf GitHub Pages: ZWEI Apps auf einem Ursprung, die
// Vorschau (`/trailbuddy-preview/`) mit dem Worker und die Freigabe
// (`/trailbuddy/`) daneben. Die Nachbarschaft ist der Fall, an dem das
// Firebase-SDK scheiterte.
//
// Ohne Abhängigkeiten, wie `check_service_worker.mjs`; dient ohne Build,
// die Datei kommt direkt aus `web/push/`.
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {existsSync} from 'node:fs';
import {readFile, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const PORT = 8797;
const CDP_PORT = 9334;
const APP = '/trailbuddy-preview/';
const SIBLING = '/trailbuddy/';
const WORKER = 'push/firebase-messaging-sw.js';
const ORIGIN = `http://127.0.0.1:${PORT}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const PAGE = `<!doctype html><meta charset="utf-8"><title>t</title><script>
  window.__got = [];
  navigator.serviceWorker.addEventListener('message', (e) => __got.push(e.data));
</script>`;

const server = createServer(async (req, res) => {
  const path = new URL(req.url, ORIGIN).pathname;
  if (path === APP + WORKER) {
    res.writeHead(200, {'content-type': 'application/javascript'});
    res.end(await readFile(join('web', WORKER)));
  } else if (path === APP || path === SIBLING) {
    res.writeHead(200, {'content-type': 'text/html'});
    res.end(PAGE);
  } else {
    res.writeHead(404).end();
  }
});

function chromeBinary() {
  if (process.env.CHROME_EXECUTABLE) return process.env.CHROME_EXECUTABLE;
  const found = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/opt/google/chrome/chrome',
    '/usr/bin/chromium-browser',
    '/usr/bin/chromium',
  ].find(existsSync);
  if (!found) throw new Error('Kein Chrome gefunden — CHROME_EXECUTABLE setzen.');
  return found;
}

/// Ein Protokoll-Anschluss am BROWSER, mit Sitzungen je Ziel (flatten).
function connect(ws) {
  let id = 0;
  const pending = new Map();
  const listeners = [];
  ws.addEventListener('message', (event) => {
    const m = JSON.parse(event.data);
    if (m.id && pending.has(m.id)) {
      const {resolve, reject} = pending.get(m.id);
      pending.delete(m.id);
      m.error ? reject(new Error(JSON.stringify(m.error))) : resolve(m.result);
    } else if (m.method) {
      for (const l of listeners) l(m);
    }
  });
  const send = (method, params = {}, sessionId) =>
      new Promise((resolve, reject) => {
        const mid = ++id;
        pending.set(mid, {resolve, reject});
        ws.send(JSON.stringify({id: mid, method, params, sessionId}));
      });
  return {send, on: (l) => listeners.push(l)};
}

const ok = [];
const fail = [];
const check = (condition, text) => (condition ? ok : fail).push(text);

const profile = await mkdtemp(join(tmpdir(), 'trailbuddy-push-'));
const chrome = spawn(chromeBinary(), [
  '--headless=new',
  '--no-first-run',
  '--no-default-browser-check',
  '--no-sandbox',
  '--disable-dev-shm-usage',
  `--remote-debugging-port=${CDP_PORT}`,
  `--user-data-dir=${profile}`,
  'about:blank',
], {stdio: 'ignore'});

try {
  await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
  let version;
  for (let i = 0; i < 60 && !version; i++) {
    try {
      version = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/version`)).json();
    } catch (_) {
      await sleep(500);
    }
  }
  if (!version) throw new Error('Chrome antwortet nicht auf dem Debug-Port.');
  const ws = new WebSocket(version.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r));
  const {send, on} = connect(ws);

  const {targetInfos} = await send('Target.getTargets');
  const pageId = targetInfos.find((t) => t.type === 'page').targetId;
  const {sessionId: page} =
      await send('Target.attachToTarget', {targetId: pageId, flatten: true});
  const run = async (expression, session = page) => {
    const r = await send('Runtime.evaluate',
        {expression, awaitPromise: true, returnByValue: true}, session);
    if (r.exceptionDetails) {
      throw new Error(r.exceptionDetails.exception?.description ??
          r.exceptionDetails.text);
    }
    return r.result.value;
  };
  const waitFor = async (expression, what, session = page) => {
    for (let i = 0; i < 40; i++) {
      try {
        if (await run(expression, session)) return true;
      } catch (_) {
        // Während einer Navigation antwortet die Seite kurz nicht.
      }
      await sleep(250);
    }
    throw new Error(`Zeitlimit: ${what}`);
  };
  const navigate = async (path) => {
    await send('Page.navigate', {url: ORIGIN + path}, page);
    await waitFor(`location.pathname === '${path}' && Array.isArray(window.__got)`,
        `Seite ${path} geladen`);
  };

  const registrations = new Map();
  on((m) => {
    if (m.method === 'ServiceWorker.workerRegistrationUpdated') {
      for (const r of m.params.registrations) {
        registrations.set(r.scopeURL, r.registrationId);
      }
    }
  });
  await send('Page.enable', {}, page);
  await send('ServiceWorker.enable', {}, page);
  await send('Browser.grantPermissions',
      {origin: ORIGIN, permissions: ['notifications']});

  await navigate(APP);
  await run(`navigator.serviceWorker.register('${WORKER}')
      .then(() => navigator.serviceWorker.getRegistration('${WORKER}'))
      .then((r) => new Promise((ok) => {
        const w = r.installing ?? r.waiting ?? r.active;
        if (w.state === 'activated') return ok();
        w.addEventListener('statechange', () => w.state === 'activated' && ok());
      }))`);
  const scope = `${ORIGIN}${APP}push/`;
  for (let i = 0; i < 40 && !registrations.has(scope); i++) await sleep(250);
  const registrationId = registrations.get(scope);
  check(!!registrationId, `der Worker ist unter ${scope} angemeldet`);

  // So kommt eine Meldung aus `send-push` an (FCM-Webpush-Form).
  const push = (body) => send('ServiceWorker.deliverPushMessage', {
    origin: ORIGIN,
    registrationId,
    data: JSON.stringify({
      from: '000000000000',
      fcmMessageId: 'x',
      notification: {title: 'Neuer Hinweis von einem Buddy', body},
      data: {route: '/trail/abc'},
    }),
  }, page);
  const shown = `navigator.serviceWorker.getRegistration('${APP}${WORKER}')
      .then((r) => r.getNotifications())
      .then((ns) => ns.map((n) => ({title: n.title, body: n.body, data: n.data})))`;

  const {targetInfos: all} = await send('Target.getTargets');
  const workerTarget = all.find((t) =>
      t.type === 'service_worker' && t.url.endsWith(WORKER));
  const {sessionId: sw} = await send('Target.attachToTarget',
      {targetId: workerTarget.targetId, flatten: true});

  // **Gelesen wird erst, wenn `showNotification` fertig ist — und dann
  // einmal.** `getNotifications()` gleicht in Chrome den Speicher mit den
  // angezeigten Meldungen ab und LÖSCHT, was noch nicht angezeigt ist.
  // Fällt eine Abfrage in das Fenster zwischen Speichern und Anzeigen,
  // ist die Meldung weg, obwohl `showNotification` Erfolg meldet. Bis
  // 2026-10-09 wartete der Prüfer, indem er alle 250 ms abfragte, und
  // scheiterte so etwa jeden zwanzigsten Lauf (TrailBuddy #290). Gemessen:
  // dichtes Abfragen während des Zeigens verliert 16 von 40 Meldungen,
  // eine Abfrage nach dem Abschluss 0 von 80. Der Zähler ist Gerüst wie
  // der gestellte Fokus unten; was der Worker zeigt, bleibt seine Sache.
  await run(`self.__shown = 0;
    const show = self.registration.showNotification.bind(self.registration);
    self.registration.showNotification = (...a) =>
        show(...a).then((v) => { self.__shown++; return v; });
    true`, sw);
  const shownCount = () => run('self.__shown', sw);
  const shownWith = (body) => `${shown}.then((ns) => ns.find((n) => n.body === '${body}'))`;

  // 1 — App vorne: keine Systembenachrichtigung, die App bekommt sie.
  //
  // **Der Fokus ist hier das einzig Gestellte.** Ein kopfloser Chrome
  // meldet `WindowClient.focused` nie als wahr, auch nicht mit
  // Fokus-Emulation (die wirkt nur auf `document.hasFocus()` — gemessen).
  // Deshalb bekommt der Worker für diesen einen Fall die ECHTEN Fenster,
  // nur mit `focused: true`; Meldung, Übergabe und Empfang bleiben echt.
  // In echten Browsern ist die Fehlerrichtung ohnehin harmlos: Meldet ein
  // Browser keinen Fokus, erscheint die Systembenachrichtigung — lieber
  // eine zu viel als eine verschluckte.
  const focusAll = () => run(`self.__matchAll ??= self.clients.matchAll.bind(self.clients);
    self.clients.matchAll = async (o) => (await __matchAll(o)).map((c) => ({
      url: c.url, focused: true,
      postMessage: (m) => c.postMessage(m), focus: () => c.focus()}));
    true`, sw);
  const realFocus = () => run('self.clients.matchAll = __matchAll; true', sw);
  await focusAll();
  await push('Tippen zeigt den Trail');
  await waitFor('__got.length > 0', 'die fokussierte App bekommt die Meldung');
  const got = await run('__got[0]');
  check(got?.type === 'trailbuddy-push' && got?.kind === 'message' &&
      got?.notification?.body === 'Tippen zeigt den Trail' &&
      got?.data?.route === '/trail/abc',
      `fokussierte App bekommt die Meldung (${JSON.stringify(got)})`);
  await sleep(500);
  check((await shownCount()) === 0,
      'keine Systembenachrichtigung, solange die App im Fokus ist');
  await realFocus();

  // 1b — App offen, aber NICHT im Fokus (so meldet es der kopflose
  // Chrome von sich aus): Die Meldung erscheint im System.
  await run('__got.length = 0');
  await push('Tippen zeigt den Trail');
  await waitFor('self.__shown === 1',
      'App offen, aber nicht im Fokus: der Worker zeigt die Meldung', sw);
  check(!!(await run(shownWith('Tippen zeigt den Trail'))),
      'App offen, aber nicht im Fokus: die Meldung erscheint im System');
  check((await run('__got.length')) === 0,
      'eine unfokussierte App bekommt keine zweite Fassung als Leiste');

  // 2 — nur die NACHBAR-App ist offen und vorne. Genau hier schluckte das
  // Firebase-SDK die Meldung: „ein Fenster der Domain sichtbar".
  //
  // Mit gestelltem Fokus: Die Nachbar-App gilt als vorne, und genau dann
  // muss der Worker sie trotzdem übergehen — sonst prüfte dieser Fall die
  // Trennung der beiden Apps gar nicht.
  await navigate(SIBLING);
  await focusAll();
  await push('An 2 Trails');
  await waitFor('self.__shown === 2',
      'der Worker zeigt die Meldung, obwohl die Nachbar-App vorne ist', sw);
  const n = await run(shownWith('An 2 Trails'));
  check(n?.title === 'Neuer Hinweis von einem Buddy' && n?.body === 'An 2 Trails' &&
      n?.data?.route === '/trail/abc',
      `Systembenachrichtigung mit Titel, Text und Ziel (${JSON.stringify(n)})`);
  check((await run('__got.length')) === 0,
      'die Nachbar-App bekommt die Meldung NICHT');
  await realFocus();

  // 3 — der Tipp. Ausgelöst im Worker selbst, weil sich eine
  // Systembenachrichtigung nicht per Protokoll anklicken lässt; geprüft
  // wird dieselbe Funktion, die `notificationclick` aufruft.
  const url = await run(`appUrl('/trail/abc')`, sw);
  check(url === `${ORIGIN}${APP}#/trail/abc`,
      `der Tipp zielt auf die EIGENE App, Hash-Pfad (${url})`);
  check(await run(`appUrl(undefined) === APP_BASE && appUrl('https://x.test/') === APP_BASE`, sw),
      'ohne gültiges Ziel: die Startseite der App, nie eine fremde Adresse');

  await navigate(APP);
  await run(`onTap({route: '/trail/abc'})`, sw);
  await waitFor('__got.length > 0', 'die offene App bekommt den Tipp');
  const tap = await run('__got[0]');
  check(tap?.type === 'trailbuddy-push' && tap?.kind === 'tap' &&
      tap?.data?.route === '/trail/abc',
      `offene App bekommt den Tipp samt Ziel (${JSON.stringify(tap)})`);
} catch (error) {
  fail.push(`Abbruch: ${error.message}`);
} finally {
  chrome.kill();
  server.close();
  await rm(profile, {recursive: true, force: true}).catch(() => {});
}

for (const line of ok) console.log(`  ✓ ${line}`);
for (const line of fail) console.log(`  ✗ ${line}`);
if (fail.length) {
  console.log(`\n${fail.length} von ${ok.length + fail.length} Prüfungen gescheitert.`);
  process.exit(1);
}
console.log(`\nAlle ${ok.length} Prüfungen bestanden.`);
