// Der Service Worker der Web-App (#387, Stufe 4 von vier).
//
// Ohne ihn passiert beim Start ohne Netz gar nichts: Der Browser bekommt
// keine `index.html`, also keine App — und damit laufen auch die drei
// Stufen davor ins Leere (Übersichtskarte #383, Spots in IndexedDB #385,
// Ausgangskorb #386). Erst hier ergeben sie zusammen etwas.
//
// **Die tragende Entscheidung: immer zuerst das Netz, der Cache nur als
// Rückfall.** Ein Service Worker, dessen Cache gewinnt, nagelt Nutzer auf
// einen alten Stand — und umgeht damit genau die kontrollierte
// Beförderung, auf der das Release-Modell dieses Projekts beruht. Bei
// `network-first` kann das nicht passieren. Dazu ein harter Grund:
// Flutters Web-Ausgaben tragen KEINE Inhalts-Prüfsummen (`main.dart.js`
// heißt immer gleich), ein `cache-first` lieferte also stillschweigend
// die alte App.
//
// Der Preis ist ehrlich: Diese Datei macht die PWA **nicht schneller**,
// nur startfähig. Genau das war der Auftrag.
//
// **Wenn dieser Worker je kaputt ist**, gibt es drei Wege hinaus:
//   1. Jeder Fehler unten fällt auf ein nacktes `fetch` durch.
//   2. `postMessage({type: 'unregister'})` räumt Registrierung und Cache.
//   3. Der eigentliche: Ein Build ohne die Registrierung in
//      `flutter_bootstrap.js` plus ein `sw.js`, das sich selbst abmeldet,
//      erreicht jeden Online-Nutzer beim nächsten Laden — eben WEIL die
//      Navigation netzwerkzuerst läuft.
'use strict';

// Je Build eine neue Nummer (aus der eigenen URL) und damit ein neuer
// Cache. Ohne `?v=` — etwa beim Aufruf von Hand — bleibt es bei „dev".
const VERSION = new URL(self.location.href).searchParams.get('v') || 'dev';
const CACHE = 'trailbuddy-' + VERSION;

// Nur die Hülle, und nur was der Start ohne Netz zwingend braucht.
// CanvasKit steht bewusst NICHT hier: Welche Variante geholt wird
// (`canvaskit/` oder `canvaskit/chromium/`), entscheidet der Browser —
// die kommt über den Laufzeit-Cache dazu.
const SHELL = [
  './',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'favicon.svg',
  'favicon.png',
  'icons/Icon-192.png',
];

// Schwacher Empfang ist im Wald der Normalfall, und „langsam" ist für den
// Start schlimmer als „aus": Ohne Grenze hinge die App am hängenden Netz,
// statt die Kopie zu nehmen.
//
// **Die Grenze gilt für JEDE Datei, die eine Kopie hat** (seit 1.204.2).
// Bis dahin nur für die Seite selbst: Sie kam nach 3 s aus dem Cache,
// `main.dart.js` und CanvasKit warteten dann ohne Grenze auf ein Netz,
// das nie antwortete — Verbindung da, Daten nicht. Im Feld am
// 2026-09-24 genau so gesehen („quasi kein Empfang", PWA blieb leer).
// Ohne Kopie wird weiter gewartet: Dann ist das Netz die einzige Chance.
const NAVIGATION_TIMEOUT_MS = 3000;
const SUBRESOURCE_TIMEOUT_MS = 4000;

// Die App lädt ihre Dateien nacheinander (Seite, Lader, `main.dart.js`,
// CanvasKit, Assets …); mit 4 s je Stück stünde man bei totem Netz eine
// halbe Minute vor einer leeren Seite. Hat gerade eine Anfrage die Grenze
// gerissen, bekommen die folgenden nur noch diese kurze Frist — bis
// wieder etwas aus dem Netz ankommt.
const DEAD_NETWORK_TIMEOUT_MS = 300;
const DEAD_NETWORK_MEMORY_MS = 30000;
let lastTimeoutAt = 0;

// Merker „dieser Cache ist vollständig" — als Eintrag im Cache selbst,
// damit er mit ihm lebt und stirbt.
const COMPLETE = new URL('__trailbuddy_cache_complete__', self.registration.scope).href;

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // Einzeln und fehlertolerant: `cache.addAll` verwirft ALLES, wenn
    // eine einzige Datei fehlt — eine umbenannte Grafik legte damit den
    // ganzen Offline-Start still.
    await Promise.allSettled(SHELL.map((path) => cache.add(path)));
    await self.skipWaiting();
  })());
});

// **Der alte Cache geht erst, wenn der neue alles hat** (seit 1.204.2).
// Bis dahin löschte das Aktivieren jeden früheren Cache sofort — und im
// neuen lag nur die Hülle. CanvasKit, Schriften und Assets kamen erst,
// wenn die neue Version einmal ganz mit Netz lief; wer nach einem Deploy
// kurz online war, hatte danach KEINEN Offline-Start mehr. Mit einem
// Deploy je Merge (Vorschau) war das der Normalfall.
//
// Jetzt bleibt genau EIN früherer Cache stehen — der vollständige, wenn
// es einen gibt. Solange er da ist, kommt jeder Rückfall zuerst aus ihm
// (`cachedCopy`): Ohne Netz startet dann der ALTE Stand, und zwar ganz,
// statt einer Mischung aus neuer Hülle und alten Assets. `topUp` füllt
// den neuen nach und räumt den alten erst danach ab.
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // Was bleibt, entscheidet der MERKER, nicht die Reihenfolge von
    // `caches.keys()`. PilzBuddys Fassung las die Reihenfolge als
    // Anlegereihenfolge — und Chromium liefert sie nicht immer so:
    // Beim Bau dieses Workers stand der neue Cache in zwei von drei
    // Läufen VOR dem alten (Chromium 1194 lokal, google-chrome auf dem
    // Runner), `previousCaches()` war dann leer, der neue Cache hielt
    // sich für vollständig, und der alte blieb für immer stehen.
    // Vollständige frühere Caches bleiben, bis `topUp` sie umgelegt hat;
    // unvollständige Reste älterer Stände gehen — ohne Merker startete
    // aus ihnen ohnehin nichts.
    for (const name of await otherCaches()) {
      if (!(await caches.match(COMPLETE, {cacheName: name}))) {
        await caches.delete(name);
      }
    }
    await self.clients.claim();
  })());
  // Nicht in `waitUntil`: Solange das Aktivieren läuft, stehen die
  // Anfragen der Seite. Bricht der Browser den Lauf ab, holt ihn das
  // nächste Vorwärmen nach.
  queue(topUp);
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  // Nur Lesezugriffe: Ein POST an Supabase hat hier nichts verloren.
  if (request.method !== 'GET') return;
  // Teilanfragen bleiben unangetastet — eine 206 lässt sich nicht in den
  // Cache legen, `cache.put` wirft dabei.
  if (request.headers.has('range')) return;
  // Fremde Ziele (Supabase, DWD, GitHub) nie anfassen: Deren Antworten
  // sind entweder persönlich oder riesig, und ihr Ausfall ist eine
  // Aussage, die die App selbst behandeln muss.
  if (new URL(request.url).origin !== self.location.origin) return;

  event.respondWith(networkFirst(request, request.mode === 'navigate'));
});

async function networkFirst(request, isNavigation) {
  // Der Netz-Versuch legt bei Erfolg selbst ab. Wichtig für den Fall
  // „Zeitlimit gerissen": Die Antwort kommt vielleicht später doch, und
  // dann soll sie wenigstens im Cache landen.
  const fromNetwork = fetchAndCache(request);
  fromNetwork.catch(() => {}); // verliert es das Rennen, fragt keiner mehr
  const cached = await cachedCopy(request, isNavigation);
  // Keine Kopie: Das Netz ist die einzige Chance, also ohne Grenze —
  // und scheitert es, dann wie ohne Worker.
  if (!cached) return fromNetwork;
  const deadNetwork = Date.now() - lastTimeoutAt < DEAD_NETWORK_MEMORY_MS;
  try {
    return await Promise.race([
      fromNetwork,
      rejectAfter(deadNetwork
          ? DEAD_NETWORK_TIMEOUT_MS
          : isNavigation ? NAVIGATION_TIMEOUT_MS : SUBRESOURCE_TIMEOUT_MS),
    ]);
  } catch (_) {
    lastTimeoutAt = Date.now();
    return cached;
  }
}

/// Die Kopie für den Rückfall. Solange ein früherer Cache steht, ist der
/// neue unvollständig — dann zuerst der frühere, damit ein Start ohne
/// Netz aus EINEM Stand kommt.
async function cachedCopy(request, isNavigation) {
  const names = [...(await previousCaches()), CACHE];
  for (const name of names) {
    // `caches.match(…, {cacheName})` statt `caches.open(name).match(…)`:
    // `open` LEGT AN, was es nicht findet. Löscht `topUp` gerade den alten
    // Cache, während hier eine Anfrage nachschlägt, entstand aus dem
    // eben gelöschten Namen ein leerer Cache ohne Merker — ein Zombie,
    // der weder Rückfall noch Nachfüllen je wieder loswurde (beim Bau in
    // einem von drei Läufen gesehen). `match` mit Namen liest nur.
    const hit = await caches.match(request, {cacheName: name}) ??
        // Eine Navigation darf auch dann noch gelingen, wenn genau diese
        // Adresse nie im Cache lag — die App ist eine einzige Seite.
        (isNavigation ? await caches.match('./', {cacheName: name}) : undefined);
    if (hit) return hit;
  }
  return null;
}

/// Die Caches FRÜHERER Builds: alle anderen mit Vollständig-Merker.
///
/// Nicht „alle anderen": Liegt der Cache eines NEUEREN Workers daneben,
/// der noch wartet (bei knappem Netz aktiviert der Browser ihn erst, wenn
/// dieser hier alle offenen Anfragen los ist), nähme der Rückfall sonst
/// Dateien aus beiden Ständen — und ohne Netz startete die Mischung nicht
/// (in PilzBuddy beim Bau gemessen). Ein wartender Worker hat seinen
/// Merker noch nicht; ein früherer, den `topUp` noch nicht umgelegt hat,
/// hat ihn. Auf die Reihenfolge von `caches.keys()` verlässt sich hier
/// nichts mehr (siehe `activate`).
async function otherCaches() {
  return (await caches.keys())
      .filter((n) => n.startsWith('trailbuddy-') && n !== CACHE);
}

async function previousCaches() {
  const complete = [];
  for (const name of await otherCaches()) {
    // Lesend, ohne `open` — siehe `cachedCopy`.
    if (await caches.match(COMPLETE, {cacheName: name})) complete.push(name);
  }
  return complete;
}

async function fetchAndCache(request) {
  const response = await fetch(request);
  lastTimeoutAt = 0; // das Netz antwortet wieder
  // Nur vollständige, erfolgreiche Antworten. Weiterleitungen und Fehler
  // als Kopie zu behalten hieße, sie später ohne Netz zu wiederholen.
  if (response.status === 200 && cacheable(request.url)) {
    const copy = response.clone();
    // Nur ablegen, solange der eigene Cache noch existiert. Ein Worker,
    // den ein neuer gerade abgelöst hat, beantwortet noch offene Anfragen
    // — sein Cache ist dann schon gelöscht, und `open` legte ihn als
    // leeren Zombie ohne Merker neu an (beim Bau in einem von drei
    // Läufen gesehen). Dasselbe Tor in `warm` und `topUp`.
    ownCacheExists()
        .then((exists) => exists && caches.open(CACHE).then((cache) => cache.put(request, copy)))
        .catch(() => {});
  }
  return response;
}

// Ein Vorwärmen nach dem anderen. Seit #427 meldet die Seite fortlaufend,
// was sie geholt hat, statt einmal eine fertige Liste zu schicken — es
// kommen also viele Nachrichten statt einer. Zwei gleichzeitige Läufe
// holten dieselbe Datei doppelt: Die Prüfung unten sieht nur, was schon
// ABGELEGT ist, nicht was gerade unterwegs ist.
let warming = Promise.resolve();

/// Hinten anstellen — Vorwärmen und Nachfüllen laufen nie gleichzeitig.
function queue(job) {
  warming = warming.then(job).catch(() => {});
  return warming;
}

/// Existiert der eigene Cache noch? `false`, sobald ein Nachfolger ihn
/// umgelegt und gelöscht hat — dann ist dieser Worker Geschichte.
function ownCacheExists() {
  return caches.has(CACHE);
}

async function warm(urls) {
  if (!(await ownCacheExists())) return;
  const cache = await caches.open(CACHE);
  for (const url of urls) {
    try {
      if (new URL(url).origin !== self.location.origin) continue;
      if (!cacheable(url)) continue;
      if (await cache.match(url)) continue;
      const response = await fetch(url);
      if (response.status === 200) await cache.put(url, response);
    } catch (_) {
      // Eine Datei, die sich nicht holen lässt, ist kein Grund
      // aufzuhören — die übrigen sind es wert.
    }
  }
}

/// Den neuen Cache mit allem füllen, was der frühere hatte — dann erst
/// den früheren löschen.
///
/// **Ohne alles neu zu laden:** Je Datei fragt der Worker mit dem ETag
/// der alten Kopie nach (`If-None-Match`). Antwortet der Server 304, ist
/// sie unverändert und wird einfach umgelegt — CanvasKit ändert sich nur
/// mit der Flutter-Version, die Karten-Assets fast nie, und über
/// Mobilfunk sollen ein paar Kilobyte Kopfzeilen reichen statt der
/// vollen Dateien. Was der Server nicht mehr kennt (404), gehört nicht
/// mehr zur App. Scheitert eine Anfrage, bleibt der alte Cache stehen,
/// und der nächste Lauf versucht es wieder.
/// Zombies wegräumen: leere Caches ohne Merker. Sie entstehen, wenn ein
/// abgelöster Worker nach dem Löschen seines Caches noch einmal `open`
/// ruft (`has` sagte eben noch ja) — das Fenster ist winzig und trotzdem
/// beim Bau in jedem dritten Lauf getroffen worden. Kennzeichen: kein
/// Merker UND keine Hülle. Der Cache eines gerade installierenden
/// Nachfolgers trägt die Hülle binnen Millisekunden (`install` legt sie
/// zuerst ab), ein Zombie nie. Nur lesend geprüft, damit die Prüfung
/// nicht selbst anlegt, was sie sucht.
async function sweepZombies() {
  for (const name of await otherCaches()) {
    if (await caches.match(COMPLETE, {cacheName: name})) continue;
    if (await caches.match('./', {cacheName: name})) continue;
    if (await caches.match('flutter_bootstrap.js', {cacheName: name})) continue;
    await caches.delete(name);
  }
}

async function topUp() {
  if (!(await ownCacheExists())) return;
  await sweepZombies();
  const previous = await previousCaches();
  const cache = await caches.open(CACHE);
  if (previous.length === 0) {
    if (!(await cache.match(COMPLETE))) await markComplete(cache);
    return;
  }
  let complete = true;
  for (const name of previous) {
    // Hier ist `open` in Ordnung: Der Name kommt aus `previousCaches()`
    // mit Merker, und nur DIESER Lauf löscht — die Warteschlange lässt
    // kein zweites Nachfüllen daneben laufen.
    const old = await caches.open(name);
    for (const request of await old.keys()) {
      if (request.url === COMPLETE || !cacheable(request.url)) continue;
      if (await cache.match(request)) continue;
      try {
        const copy = await old.match(request);
        const etag = copy?.headers.get('etag');
        const response = await fetch(request.url, {
          cache: 'no-store',
          // Die Kennung ist für die Prüfung im Browser
          // (`check_service_worker.mjs`): Nur SO lassen sich die 304 des
          // Nachfüllens von denen des Browsers unterscheiden, der beim
          // normalen Laden ebenfalls mit ETag nachfragt.
          headers: {
            'x-trailbuddy-topup': '1',
            ...(etag ? {'If-None-Match': etag} : {}),
          },
          signal: AbortSignal.timeout(30000),
        });
        if (response.status === 304 && copy) {
          await cache.put(request, copy);
        } else if (response.status === 200) {
          await cache.put(request, response);
        } else if (response.status !== 404 && response.status !== 410) {
          complete = false;
        }
      } catch (_) {
        complete = false; // kein Netz — der alte bleibt, nächster Lauf
      }
    }
  }
  if (!complete) return;
  await markComplete(cache);
  await Promise.all(previous.map((name) => caches.delete(name)));
  // Der abgelöste Worker kann JETZT noch einen Zombie anlegen — kurz
  // danach noch einmal nachsehen.
  setTimeout(() => queue(sweepZombies), 2000);
}

function markComplete(cache) {
  return cache.put(COMPLETE, new Response('1'));
}

/// Flutters Update-Abfrage hängt an `version.json` bei jedem Start einen
/// neuen `cachebuster` — jede davon wäre ein eigener Eintrag, der Cache
/// wüchse je Start um einen, und das Nachfüllen trüge sie alle mit. Ohne
/// Netz braucht sie ohnehin niemand.
function cacheable(url) {
  return !new URL(url).searchParams.has('cachebuster');
}

function rejectAfter(ms) {
  return new Promise((_, reject) =>
      setTimeout(() => reject(new Error('Zeitlimit')), ms));
}

self.addEventListener('message', (event) => {
  if (!event.data) return;
  // Was die Seite wirklich geholt hat — siehe `flutter_bootstrap.js`.
  // Beim ersten Laden gehen die ersten Anfragen raus, bevor dieser Worker
  // aktiv ist; er sieht sie nie. Ohne diesen Nachschlag läge nach dem
  // ersten Besuch nur die Hülle im Cache.
  if (event.data.type === 'warm' && Array.isArray(event.data.urls)) {
    const urls = event.data.urls;
    queue(() => warm(urls));
    // Nach jedem Vorwärmen nachfüllen: Die Seite läuft, also gibt es
    // gerade Netz — der beste Moment, den früheren Cache loszuwerden.
    event.waitUntil(queue(topUp));
    return;
  }
  // Die Notbremse. Aus der Konsole:
  //   navigator.serviceWorker.controller.postMessage({type: 'unregister'})
  if (event.data.type !== 'unregister') return;
  event.waitUntil((async () => {
    try {
      await self.registration.unregister();
    } catch (error) {
      console.warn('Abmelden fehlgeschlagen:', error);
    }
    const names = await caches.keys();
    await Promise.all(names.map((name) => caches.delete(name)));
    // Bewusst OHNE die Seite neu zu laden: Beim nächsten Laden meldet
    // `flutter_bootstrap.js` den Worker sofort wieder an, und dann wäre
    // von der Notbremse nichts mehr zu sehen — auch nicht für den, der
    // gerade prüft, ob sie wirkt. Wer aufgeräumt hat, lädt selbst neu.
  })());
});
