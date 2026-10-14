// Prüft den Service Worker der Web-App gegen einen echten Chrome (#387).
//
//     node tool/check_service_worker.mjs build/web
//
// **Warum als eigenes Werkzeug.** Der Worker ist die riskanteste Stelle
// der PWA: Er entscheidet, ob die App ohne Netz startet, und ein Fehler
// darin ist von außen unsichtbar — `flutter analyze` sieht die Datei
// nicht, `flutter test` startet keinen Browser, und ein kaputter Worker
// scheitert still. Textprüfungen auf `web/sw.js` fangen Tippfehler, aber
// keine falsche Entscheidung.
//
// **Der Offline-Fall wird NICHT emuliert.** Der Webserver wird wirklich
// abgeschaltet. Alles andere wäre eine Aussage über die Emulation.
//
// Ohne Abhängigkeiten: Node bringt seit 22 ein globales `WebSocket` mit,
// und damit lässt sich das DevTools-Protokoll direkt sprechen.
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {existsSync, readFileSync} from 'node:fs';
import {readFile, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, extname, normalize} from 'node:path';

const ROOT = process.argv[2] ?? 'build/web';
const PORT = 8796;
const CDP_PORT = 9333;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const TYPES = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
};

// Der Build trägt seinen Pfad im `<base href>` — die Seite muss unter
// genau dem ausgeliefert werden, sonst zeigt jede relative Adresse ins
// Leere. So prüft dasselbe Werkzeug Freigabe (/trailbuddy/) und Vorschau.
const index = await readFile(join(ROOT, 'index.html'), 'utf8');
const base = index.match(/<base href="([^"]*)"/)?.[1] || '/';

// Wie der Server antwortet — das Netz, das der Worker erlebt:
//   'up'      normal
//   'hang'    Verbindung steht, Antwort kommt nie: „Empfang ohne Daten",
//             im Wald der Normalfall und für den Start schlimmer als
//             „aus" (im Feld 2026-09-24 so gesehen: PWA startete nicht)
//   'partial' nur die Hülle antwortet, alles andere hängt — ein Update,
//             das bei schwachem Empfang ankommt, aber nie fertig wird
let mode = 'up';
// Ein neuer Deploy, ohne neu zu bauen: Die Bauversion steht nur in
// `flutter_bootstrap.js` (`sw.js?v=…`), und genau dort wird sie erhöht.
let deploy = 0;
// Das Nachfüllen des Workers hängen lassen — nur DAS, erkennbar an seiner
// Kennung. So wird ein Update sicher nicht fertig, ohne dass die Seite
// selbst hängt (dann aktivierte der Browser den neuen Worker nie).
let blockTopUp = false;
// Wie oft der Server dem NACHFÜLLEN „unverändert" (304) sagte — GitHub
// Pages schickt ETags, und genau davon lebt es. Gezählt wird nur, was
// die Kennung des Nachfüllens trägt; der Browser fragt beim normalen
// Laden ebenfalls mit ETag nach.
let notModified = 0;
// Wie oft das Nachfüllen eine Datei VOLL laden musste, obwohl sie sich
// nicht geändert hat. Die Zusage ist nicht „viele 304" (PilzBuddy prüfte
// >= 5 und hat viele Assets, die die Seite beim Start nicht lädt —
// TrailBuddy hat davon zwei), sondern: Nichts Unverändertes wird neu
// geladen. `flutter_bootstrap.js` ändert sich je Deploy und zählt nicht.
let topUpFull = 0;
const SHELL_PATHS = new Set([
  '/index.html', '/flutter_bootstrap.js', '/main.dart.js',
  '/manifest.json', '/favicon.svg', '/favicon.png', '/icons/Icon-192.png',
  '/sw.js',
]);

const handler = async (req, res) => {
  try {
    let path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (!path.startsWith(base)) throw new Error('außerhalb');
    path = '/' + path.slice(base.length);
    if (path.endsWith('/')) path += 'index.html';
    if (mode === 'hang' || (mode === 'partial' && !SHELL_PATHS.has(path)) ||
        (blockTopUp && req.headers['x-trailbuddy-topup'])) {
      return; // nie antworten; `stopServer` räumt die Verbindung ab
    }
    const file = join(ROOT, normalize(path));
    let body = await readFile(file);
    if (deploy && path === '/flutter_bootstrap.js') {
      body = Buffer.from(body.toString('utf8').replace(
          /sw\.js\?v=' \+ "?(\d+)"?/,
          (_, v) => `sw.js?v=' + ${BigInt(v) + BigInt(deploy)}`));
    }
    const etag = `"${createHash('sha1').update(body).digest('hex')}"`;
    if (req.headers['if-none-match'] === etag) {
      if (req.headers['x-trailbuddy-topup']) notModified++;
      res.writeHead(304, {etag}).end();
      return;
    }
    if (req.headers['x-trailbuddy-topup'] && path !== '/flutter_bootstrap.js') topUpFull++;
    res.writeHead(200, {
      'content-type': TYPES[extname(file)] ?? 'application/octet-stream',
      etag,
    });
    res.end(body);
  } catch (_) {
    res.writeHead(404).end('nicht da');
  }
};

let server;
const startServer = async () => {
  server = createServer(handler);
  await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
};
const stopServer = async () => {
  server.closeAllConnections();
  await new Promise((r) => server.close(r));
};

function chromeBinary() {
  if (process.env.CHROME_EXECUTABLE) return process.env.CHROME_EXECUTABLE;
  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/opt/google/chrome/chrome',
    '/usr/bin/chromium-browser',
    '/usr/bin/chromium',
  ];
  const found = candidates.find(existsSync);
  if (!found) {
    throw new Error('Kein Chrome gefunden. Gesucht in:\n  ' +
        candidates.join('\n  ') +
        '\nAbhilfe: CHROME_EXECUTABLE setzen.');
  }
  return found;
}

// Was Chrome nebenbei erzählt.
//
// **Warum das hier steht.** Bis dahin verschluckte [waitFor] jede
// Ausnahme („Während einer Navigation antwortet die Seite kurz nicht"),
// und ein Fehlschlag hinterließ genau eine Zeile: „Zeitlimit: die App
// rendert OHNE Server". Damit sehen zwei völlig verschiedene Lagen
// identisch aus — eine startnotwendige Datei fehlt im Cache, oder die
// Umgebung hing. Ohne Unterschied bleibt nur, den Lauf zu wiederholen,
// bis er grün ist, und dann prüft der Check nichts mehr.
//
// Gesammelt wird fortlaufend und ausgegeben NUR im Fehlerfall — ein
// grüner Lauf soll so knapp bleiben, wie er ist.
const trace = {console: [], exceptions: [], failed: [], urls: new Map()};

/// Mehr als das braucht niemand, und ein Lauf soll nicht am Mitschreiben
/// volllaufen.
const TRACE_MAX = 300;

function remember(list, text) {
  list.push({at: Date.now(), text});
  if (list.length > TRACE_MAX) list.shift();
}

function watchEvents(ws) {
  ws.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    switch (message.method) {
      case 'Runtime.consoleAPICalled': {
        const text = (message.params.args ?? [])
            .map((arg) => arg.value ?? arg.description ?? arg.type)
            .join(' ');
        remember(trace.console, `${message.params.type}: ${text}`);
        break;
      }
      case 'Runtime.exceptionThrown': {
        const details = message.params.exceptionDetails;
        remember(trace.exceptions,
            details.exception?.description ?? details.text);
        break;
      }
      // Die Zuordnung id → URL kommt aus der Anfrage; `loadingFailed`
      // trägt nur die id.
      case 'Network.requestWillBeSent':
        trace.urls.set(message.params.requestId, message.params.request.url);
        if (trace.urls.size > TRACE_MAX * 4) {
          trace.urls.delete(trace.urls.keys().next().value);
        }
        break;
      case 'Network.loadingFailed': {
        const where = trace.urls.get(message.params.requestId) ??
            `(Anfrage ${message.params.requestId})`;
        remember(trace.failed, `${where} — ${message.params.errorText}`);
        break;
      }
    }
  });
}

/// Alles, was seit [mark] hereinkam — als fertiger Textblock.
function traceSince(mark, lastError) {
  const block = (title, list, limit = 15) => {
    const lines = list.filter((e) => e.at >= mark).map((e) => e.text);
    return lines.length
        ? `--- ${title} (${lines.length}) ---\n  ${lines.slice(-limit).join('\n  ')}\n`
        : `--- ${title}: nichts ---\n`;
  };
  return block('fehlgeschlagene Anfragen', trace.failed) +
      block('Ausnahmen der Seite', trace.exceptions) +
      block('Konsole', trace.console) +
      (lastError ? `--- zuletzt beim Auswerten: ${lastError.message}\n` : '');
}

/// Was wirklich im Cache liegt — die andere Hälfte der Antwort auf
/// „warum startet sie nicht".
async function cacheReport(send) {
  try {
    const cached = await evaluate(send, `(async () => {
      const out = {};
      for (const name of await caches.keys()) {
        out[name] = (await (await caches.open(name)).keys()).map((r) => r.url);
      }
      return out;
    })()`);
    return Object.entries(cached)
        .map(([name, urls]) =>
            `--- im Cache „${name}" (${urls.length}) ---\n  ${urls.join('\n  ')}\n`)
        .join('') || '--- Cache: leer ---\n';
  } catch (error) {
    return `--- Cache nicht lesbar: ${error.message}\n`;
  }
}

function rpc(ws) {
  let id = 0;
  const pending = new Map();
  ws.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const {resolve, reject} = pending.get(message.id);
      pending.delete(message.id);
      message.error ? reject(new Error(JSON.stringify(message.error)))
                    : resolve(message.result);
    }
  });
  return (method, params = {}) =>
      new Promise((resolve, reject) => {
        const mid = ++id;
        pending.set(mid, {resolve, reject});
        ws.send(JSON.stringify({id: mid, method, params}));
      });
}

async function evaluate(send, expression) {
  const result = await send(
      'Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
  return result.result.value;
}

async function waitFor(send, expression, what, timeoutMs = 60000) {
  const mark = Date.now();
  const deadline = mark + timeoutMs;
  // Während einer Navigation antwortet die Seite kurz nicht — deshalb
  // bricht eine Ausnahme das Warten weiterhin NICHT ab. Sie wird nur
  // nicht mehr weggeworfen: Steht am Ende ein Zeitlimit, ist die letzte
  // von ihnen oft schon die halbe Antwort.
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      if (await evaluate(send, expression)) return;
      lastError = null;
    } catch (error) {
      lastError = error;
    }
    await sleep(300);
  }
  throw new Error(`Zeitlimit: ${what}\n${traceSince(mark, lastError)}`);
}

const ok = [];
const fail = [];
const check = (condition, text) => (condition ? ok : fail).push(text);

const profile = await mkdtemp(join(tmpdir(), 'trailbuddy-sw-'));
const binary = chromeBinary();
console.log(`Chrome: ${binary}`);
const chrome = spawn(binary, [
  '--headless=new',
  '--no-first-run',
  '--no-default-browser-check',
  // Auf CI-Rechnern läuft alles als root und ohne die üblichen
  // Kernel-Namespaces; ohne diese beiden startet Chrome dort gar nicht.
  '--no-sandbox',
  '--disable-dev-shm-usage',
  // CanvasKit braucht WebGL. Ohne Grafikkarte rendert SwiftShader in
  // Software — langsam, aber es rendert; ohne den Schalter gar nicht.
  '--enable-unsafe-swiftshader',
  `--remote-debugging-port=${CDP_PORT}`,
  `--user-data-dir=${profile}`,
  'about:blank',
], {stdio: ['ignore', 'pipe', 'pipe']});

// Chromes eigene Meldungen aufheben, statt sie wegzuwerfen: Startet er
// nicht, ist DAS die Auskunft — beim ersten CI-Lauf stand stattdessen nur
// „antwortet nicht auf dem Debug-Port" da, und das sagt nichts.
let chromeLog = '';
chrome.stdout.on('data', (d) => { chromeLog += d; });
chrome.stderr.on('data', (d) => { chromeLog += d; });
chrome.on('error', (error) => { chromeLog += `spawn: ${error.message}\n`; });
chrome.on('exit', (code, signal) => {
  chromeLog += `Chrome beendet (code ${code}, signal ${signal})\n`;
});

const url = `http://127.0.0.1:${PORT}${base}`;
let ws;
try {
  await startServer();

  // Chrome braucht einen Moment, bis das Protokoll offen ist.
  let targets;
  for (let attempt = 0; attempt < 60 && !targets; attempt++) {
    try {
      targets = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json();
    } catch (_) {
      await sleep(500);
    }
  }
  if (!targets) {
    throw new Error('Chrome antwortet nicht auf dem Debug-Port.\n' +
        `--- Ausgabe von Chrome ---\n${chromeLog.trim() || '(nichts)'}`);
  }

  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r));
  const send = rpc(ws);
  watchEvents(ws);
  await send('Page.enable');
  await send('Runtime.enable');
  // Nur fürs Protokoll: Ohne die Anfragen fehlt beim Zeitlimit genau
  // die Zeile, auf die es ankommt — WELCHE Datei nicht kam.
  await send('Network.enable');
  // Ein langsamer Runner zum Nachstellen: `CPU_SLOW=6 node …` drosselt
  // die Seite um diesen Faktor. Damit ließen sich beide Fehlschläge vom
  // 2026-10-01 lokal in jedem Lauf zeigen; ohne kam keiner.
  if (process.env.CPU_SLOW) {
    await send('Emulation.setCPUThrottlingRate', {rate: Number(process.env.CPU_SLOW)});
  }

  const APP = "!!document.querySelector('flutter-view, flt-glass-pane')";

  // 1 — der ERSTE Besuch. Frisch, damit gemessen wird, was ein neuer
  // Nutzer bekommt: Beim ersten Laden kontrolliert der Worker die Seite
  // noch nicht, der Cache entsteht erst durch das Vorwärmen.
  //
  // Frisch heißt: über das Protokoll geräumt, BEVOR die Seite je geladen
  // war. Bis 2026-10-01 lud hier ein Vorlauf die Seite, wartete 2 s und
  // räumte dann aus der Seite heraus ab. Auf einem langsamen Runner
  // installierte der Worker da noch: Sein Cache wurde gelöscht, die
  // Registrierung kam beim zweiten Laden mit derselben Skript-Adresse
  // zurück, und der Worker hielt sich danach für abgelöst
  // (`ownCacheExists`) — „0 im Cache", gefolgt von „startet ohne Server
  // nicht". Mit sechsfach gedrosselter CPU in jedem Lauf nachgestellt,
  // ohne den Vorlauf in keinem. Das Profil ist ohnehin neu
  // (`mkdtemp`); geräumt wird nur zur Sicherheit.
  await send('Storage.clearDataForOrigin', {
    origin: new URL(url).origin,
    storageTypes: 'service_workers,cache_storage',
  });
  await send('Page.navigate', {url: `${url}?frisch=1`});
  await waitFor(send, APP, 'die App rendert online');
  await waitFor(send, 'navigator.serviceWorker.controller !== null',
      'der Worker kontrolliert die Seite');

  const script = await evaluate(send, 'navigator.serviceWorker.controller.scriptURL');
  check(/\/sw\.js\?v=\d+$/.test(script), `der Worker läuft (${script})`);

  // CanvasKit vom CDN wäre offline tot — und schickte die IP jedes
  // Besuchers an Google, bevor irgendetwas eingeschaltet wurde.
  const fromCdn = await evaluate(send,
      "performance.getEntriesByType('resource').some(e => e.name.includes('flutter-canvaskit'))");
  check(fromCdn === false, `CanvasKit kommt aus dem eigenen Build (CDN: ${fromCdn})`);

  // Und kein UNERWARTETER fremder Ursprung beim Laden (#393).
  //
  // Bis 1.119.x holte Flutter im Browser seine Standardschrift bei jedem
  // Seitenaufruf von `fonts.gstatic.com` — vor der Anmeldung, vor jeder
  // Zustimmung, bei jedem Besucher. Aufgefallen ist das nur, weil dieser
  // Lauf ohnehin einen echten Chrome fährt; kein Dart-Test sieht so
  // etwas, und die Datenschutzerklärung hat es zwei Versionen lang
  // beschrieben statt verhindert.
  //
  // Supabase steht auf der Liste, weil die App schon VOR der Anmeldung
  // dorthin geht: `app_config` trägt die Mindestversion, und die wird
  // beim Start gelesen. Der Host kommt aus `supabase_config.dart` und
  // nicht als Literal — sonst zeigte diese Prüfung nach einem
  // Projektwechsel auf ein Ziel, das es nicht mehr gibt. Kommt ein
  // weiteres Ziel dazu, gehört es hier hinein UND in
  // `web/datenschutz.html` (und deren englische Fassung `privacy.html`).
  // TrailBuddy liest die URL aus `String.fromEnvironment` mit Vorgabe;
  // gebaut wird in CI ohne dart-define, also gilt die Vorgabe.
  const supabaseHost = new URL(
      readFileSync('lib/core/supabase_config.dart', 'utf8')
          .match(/'SUPABASE_URL',\s*defaultValue: '([^']+)'/)[1]).origin;
  const foreign = JSON.parse(await evaluate(send, `JSON.stringify(
      [...new Set(performance.getEntriesByType('resource')
          .map(e => new URL(e.name).origin)
          .filter(o => o !== location.origin))])`));
  const unexpected = foreign.filter((o) => o !== supabaseHost);
  check(unexpected.length === 0,
      `keine unerwarteten Ursprünge beim Laden (fremd: ${JSON.stringify(foreign)})`);

  await sleep(12000); // das Vorwärmen einholen lassen

  // Die Zusage ist nicht „viele Einträge", sondern: Was dieser Besuch
  // geholt hat, liegt danach auch im Cache.
  //
  // Bis 1.128.1 stand hier eine Untergrenze (>= 10). Die ist eine Aussage
  // über den LAUF, nicht über den Build — zwei Läufe desselben Commits
  // kamen auf 15 und 16 Einträge, und ausgerechnet der mit 16 startete
  // ohne Server nicht (#427). Mehr ist eben nicht vollständiger: Die
  // beiden Mengen stehen in keinem Teilmengen-Verhältnis. Gemessen wird
  // deshalb der Lauf gegen sich selbst; fehlt etwas, steht es beim Namen.
  const wanted = JSON.parse(await evaluate(send, `JSON.stringify(
      [...new Set(performance.getEntriesByType('resource')
          .filter(e => e.responseStatus === 200)
          .map(e => e.name)
          .filter(n => n.startsWith(location.origin))
          .filter(n => !new URL(n).searchParams.has('cachebuster')))])`));
  // Flutters Update-Abfrage legt der Worker bewusst NICHT ab (cacheable
  // in sw.js): je Start ein neuer cachebuster, ohne Netz nutzlos.
  // Was zwischen den beiden Abfragen dazukam, noch ablegen lassen: Der
  // Beobachter meldet es, der Worker holt es — beides braucht einen
  // Augenblick. Andersherum wäre die Reihenfolge falsch; ein Stück, das
  // NACH der Cache-Abfrage geholt wird, dürfte gar nicht erst in der
  // Soll-Liste stehen.
  await sleep(3000);
  const cached = JSON.parse(await evaluate(send, `(async () => {
    const out = {};
    for (const name of await caches.keys()) {
      out[name] = (await (await caches.open(name)).keys()).map(r => r.url);
    }
    return JSON.stringify(out);
  })()`));
  const names = Object.keys(cached);
  check(names.length === 1 && names[0].startsWith('trailbuddy-'),
      `genau ein Cache, benannt nach der Bauversion: ${JSON.stringify(names)}`);
  // Eine Untergrenze bleibt — aber auf der SOLL-Seite, und nur als
  // Beweis, dass überhaupt gemessen wurde. Ohne sie bliebe die Prüfung
  // darunter auch dann grün, wenn `responseStatus` einmal nichts mehr
  // liefert und die Liste leer durchläuft.
  check(wanted.length >= 8,
      `der Besuch hat wirklich etwas geholt (${wanted.length} eigene Dateien)`);
  const inCache = new Set(names.flatMap((name) => cached[name]));
  const missing = wanted.filter((url) => !inCache.has(url));
  check(missing.length === 0,
      `schon der erste Besuch legt jede geholte Datei ab ` +
      `(${wanted.length} geholt, ${inCache.size} im Cache` +
      (missing.length ? `) — es fehlen: ${missing.join(', ')}` : ')'));

  // 2 — der eigentliche Beweis: Server wirklich aus, dann neu laden.
  await stopServer();
  let reallyDown = false;
  try {
    await fetch(url, {signal: AbortSignal.timeout(2000)});
  } catch (_) {
    reallyDown = true;
  }
  check(reallyDown, 'der Webserver ist wirklich aus');

  await send('Page.navigate', {url});
  try {
    await waitFor(send, APP, 'die App rendert OHNE Server');
  } catch (error) {
    // Hier und nur hier lohnt der Cache-Auszug: Die Navigation selbst
    // gelingt immer (der Worker reicht die Hülle heraus), scheitern
    // können nur die Unterressourcen — und dann ist die Frage genau
    // „welche Datei fehlt", nicht „ob".
    throw new Error(`${error.message}${await cacheReport(send)}`);
  }
  check(true, 'die App startet ohne Server');

  // 3 — Empfang ohne Daten. Der Server nimmt Verbindungen an und
  // antwortet nie. Bis 1.204.1 wartete jede Datei außer der Seite selbst
  // ohne Grenze darauf, und die PWA blieb weiß.
  await startServer();
  mode = 'hang';
  const hangStart = Date.now();
  await send('Page.navigate', {url});
  try {
    await waitFor(send, APP, 'die App rendert bei Empfang ohne Daten', 30000);
    // Und zwar ZÜGIG: Mit der vollen Grenze je Datei käme bei rund zehn
    // Dateien nacheinander eine halbe Minute zusammen.
    const seconds = (Date.now() - hangStart) / 1000;
    check(seconds < 15,
        `die App startet bei Empfang ohne Daten aus dem Cache (${seconds.toFixed(1)} s)`);
  } catch (error) {
    fail.push(`bei Empfang ohne Daten: ${error.message.split('\n')[0]}`);
  }
  await stopServer();

  // 4 — ein Update kommt an, der neue Worker übernimmt, aber fertig wird
  // er nicht, und dann ist das Netz weg. Bis 1.204.1 löschte er beim
  // Aktivieren den alten, vollständigen Cache; im neuen lag nur die
  // Hülle, und ohne Netz startete nichts. Mit einem Deploy je Merge war
  // das der Normalfall.
  //
  // Das Update kommt bei normalem Netz; hängen bleibt nur das Nachfüllen.
  // Zwei Anläufe davor sind gescheitert: Hängt das ganze Netz, aktiviert
  // der Browser den neuen Worker nie (er wartet auf die offenen Anfragen
  // des alten). Wird es erst DANACH knapp, ist das Nachfüllen auf einem
  // schnellen Rechner schon fertig, und der Schritt prüft nichts — in CI
  // so passiert.
  const before = await evaluate(send, '(async () => (await caches.keys()))()');
  const oldScript = await evaluate(send, 'navigator.serviceWorker.controller.scriptURL');
  await startServer();
  mode = 'up';
  deploy = 1;
  blockTopUp = true;
  await send('Page.navigate', {url});
  // 120 s, nicht 30: Die ERSTE Update-Prüfung nach dem Installieren
  // schickt Chrome erst rund eine Minute später ab. Gemessen am
  // 2026-10-01 am Server: Die Seite ruft `register('sw.js?v=neu')` nach
  // 2 s, die Anfrage nach `sw.js` kommt nach 61 s — gedrosselt wie
  // ungedrosselt, gebündelt mit allen Update-Prüfungen der Navigationen
  // davor; jede spätere kommt sofort. Bis dahin fiel diese Minute in den
  // Vorlauf von Schritt 1 (der zweimal 60 s auf App und Worker wartete)
  // — je nach Tempo des Runners aber nicht ganz, und dann hierher. Die
  // 30 s waren also keine Aussage über unseren Worker, sondern darüber,
  // wo im Lauf die Minute gerade lag.
  try {
    await waitFor(send,
        `navigator.serviceWorker.controller?.scriptURL !== ${JSON.stringify(oldScript)}`,
        'der Worker des neuen Deploys übernimmt', 120000);
  } catch (error) {
    // Ganz ausgeben, nicht nur die erste Zeile: Die Anfragen darunter
    // sind die halbe Antwort, und abgeschnitten fehlten sie genau dann.
    fail.push(`neuer Deploy: ${error.message}`);
  }
  await sleep(3000);
  await stopServer();
  blockTopUp = false;
  await send('Page.navigate', {url});
  try {
    await waitFor(send, APP, 'die App rendert nach halbem Update OHNE Server', 30000);
    check(true, 'nach einem halben Update startet sie ohne Netz aus dem alten Stand');
  } catch (error) {
    fail.push(`nach halbem Update ohne Netz: ${error.message.split('\n')[0]}\n` +
        await cacheReport(send));
  }
  const afterUpdate = await evaluate(send, '(async () => (await caches.keys()))()');
  check(afterUpdate.length === 2,
      `der alte Cache steht noch, solange der neue unvollständig ist (${JSON.stringify(afterUpdate)})`);

  // 5 — wieder online füllt der neue Cache nach, und erst DANN geht der
  // alte. Ein alter Cache, der nie geht, wäre ein Speicherleck je Deploy.
  // Angestoßen wird das Nachfüllen hier von Hand, VOR dem Neuladen: Die
  // Seite holte sonst fast alles selbst, und gemessen wäre nur der Rest.
  await startServer();
  notModified = 0;
  topUpFull = 0;
  await evaluate(send,
      "navigator.serviceWorker.controller.postMessage({type: 'warm', urls: []})");
  // Länger als der 30-s-Timeout, den der Worker je Nachfüll-Anfrage hat:
  // Eine beim halben Update hängen gelassene Anfrage kann die Warteschlange
  // des Workers noch bis dahin blockieren, und erst danach läuft das
  // Nachfüllen für diesen Schritt.
  let caches2 = [];
  for (let i = 0; i < 80; i++) {
    await sleep(1000);
    caches2 = await evaluate(send, '(async () => (await caches.keys()))()');
    if (caches2.length === 1 && !before.includes(caches2[0])) break;
  }
  check(caches2.length === 1 && !before.includes(caches2[0]),
      `online räumt der neue Cache den alten ab (jetzt: ${JSON.stringify(caches2)})`);
  // Unverändertes (CanvasKit, Schriften) wird umgelegt, nicht neu geladen.
  // Null Anfragen sind erlaubt: Lädt die Seite beim Update selbst schon
  // alles, hat das Nachfüllen nichts mehr zu tun — und genau das ist bei
  // einer kleinen App mit zwölf Dateien der Normalfall.
  check(topUpFull === 0,
      `unverändertes wird umgelegt, nie voll geladen (${notModified}× 304, ${topUpFull}× voll geladen)`);
  await send('Page.navigate', {url});
  await waitFor(send, APP, 'wieder online nach dem Update');

  // 6 — die Notbremse. Eine, die man nie gezogen hat, zählt nicht.
  // Der Server läuft noch aus Schritt 5.
  await send('Page.navigate', {url});
  await waitFor(send, 'navigator.serviceWorker.controller !== null', 'wieder online');
  await sleep(12000);
  await evaluate(send,
      "navigator.serviceWorker.controller.postMessage({type: 'unregister'})");
  await sleep(3000);
  // Geprüft wird der CACHE. Die Registrierung bleibt laut Spezifikation
  // gelistet, solange diese Seite noch von ihr kontrolliert wird — sie
  // verschwindet beim Verlassen. Genau deshalb lädt die Notbremse nicht
  // selbst neu.
  const left = await evaluate(send, '(async () => (await caches.keys()).length)()');
  check(left === 0, `die Notbremse räumt den Cache (übrig: ${left})`);
} catch (error) {
  fail.push(`ABBRUCH: ${error.message}`);
} finally {
  // Aufräumen darf NIE über das Urteil entscheiden. Beim ersten Lauf in
  // CI tat es genau das: Chrome schrieb noch in sein Profil, als es
  // gelöscht wurde, `ENOTEMPTY` flog aus diesem Block und riss das
  // Skript mit — bevor auch nur eine Zeile Ergebnis gedruckt war. Der
  // Job stand auf rot, ohne dass jemand sagen konnte, welche Prüfung
  // gescheitert wäre.
  try { ws?.close(); } catch (_) { /* egal */ }
  chrome.kill('SIGKILL');
  try { await stopServer(); } catch (_) { /* schon zu */ }
  await sleep(500); // Chrome die Handles schließen lassen
  await rm(profile, {recursive: true, force: true, maxRetries: 5})
      .catch(() => { /* ein Rest im Temp-Verzeichnis ist kein Fehlschlag */ });
}

for (const line of ok) console.log('  OK   ' + line);
for (const line of fail) console.log('  FEHL ' + line);
console.log(fail.length ? '\nService Worker: FEHLGESCHLAGEN' : '\nService Worker: in Ordnung');
process.exit(fail.length ? 1 : 0);
