// Service Worker für Web-Push (#34; PilzBuddy #277/1.203.0 als Vorlage).
//
// **Warum in einem Unterverzeichnis.** Im Basis-Scope (`/trailbuddy/`)
// liegt der Offline-Start der Web-App (`sw.js`). Service-Worker-
// Registrierungen sind über ihren SCOPE eindeutig: Ein zweiter Worker mit
// demselben Scope ersetzt den ersten. Läge diese Datei neben der
// index.html, verlöre die Web-App beim ersten Einschalten der
// Benachrichtigungen still ihren Offline-Start. Aus `web/push/` heraus
// bekommt sie den Scope `/trailbuddy/push/` und kommt der anderen nicht
// in die Quere; Push-Ereignisse gehen an die Registrierung, nicht an die
// kontrollierten Seiten. Der Dateiname ist der, den das FCM-SDK
// erwartet; ein Firebase-SDK steckt NICHT darin.
//
// **Ohne Firebase-SDK.** Der Browser liefert die Meldung selbst; zum
// Empfangen braucht es kein SDK, das Abo legt die SEITE an (`getToken`).
// Das SDK entschied in PilzBuddy falsch: Es zeigte nichts an, sobald
// IRGENDEIN Fenster der Domain sichtbar war — auch die Vorschau neben der
// Freigabe (beide liegen auf macbuchi.github.io) —, und der Tipp folgte
// einem festen Link, der aus der Vorschau heraus die Freigabe öffnete.
//
// Hier gilt: **Ist ein Fenster DIESER App im Fokus, bekommt es die
// Meldung als Leiste, sonst zeigt der Browser sie an.** Beide Seiten der
// Übergabe gehören uns (`push_web_bridge_web.dart`), es hängt also an
// keinem internen Format von Firebase. `tool/check_push_worker.mjs` prüft
// alle Wege im echten Chrome.
//
// **Keine Platzhalter des Flutter-Builds in dieser Datei** — sie liegt
// nicht im Build-Lauf von `flutter_bootstrap.js`, aber wer sie dorthin
// kopiert, soll es nicht über einen Kommentar lernen.

/// Die App, zu der dieser Worker gehört: eine Ebene über `push/`.
/// `/trailbuddy/` oder `/trailbuddy-preview/` — daraus folgt alles andere.
const APP_BASE = new URL('../', self.registration.scope).href;

/// Die Kennung unserer Übergabe an die Seite. Die Gegenstelle prüft sie;
/// Nachrichten ohne sie (etwa die des Offline-Workers `sw.js`) bleiben
/// liegen.
const BRIDGE = 'trailbuddy-push';

/// Wohin ein Tipp führt. Die App nutzt die Hash-Strategie (Flutters
/// Vorgabe, kein `usePathUrlStrategy`), der Pfad steht also hinter `#`.
/// Welche Pfade sie befolgt, entscheidet sie selbst (`pushRouteOf`).
function appUrl(route) {
  return typeof route === 'string' && route.startsWith('/')
      ? `${APP_BASE}#${route}`
      : APP_BASE;
}

/// Die Fenster dieser App — NICHT die der Nachbar-App auf derselben
/// Domain. `/trailbuddy/` ist kein Präfix von `/trailbuddy-preview/`, der
/// Schrägstrich am Ende trennt beide.
async function appWindows() {
  const all = await self.clients.matchAll(
      {type: 'window', includeUncontrolled: true});
  return all.filter((c) => c.url.startsWith(APP_BASE));
}

/// Die FCM-Nutzlast, wie der Browser sie liefert:
/// `{notification: {title, body}, data: {...}, from, fcmMessageId, …}`.
function payloadOf(event) {
  try {
    return event.data ? event.data.json() : null;
  } catch (_) {
    return null; // kein JSON — nicht von uns
  }
}

async function onPush(payload) {
  const notification = payload.notification ?? {};
  const data = payload.data ?? {};
  const focused = (await appWindows()).find((c) => c.focused);
  if (focused) {
    focused.postMessage({type: BRIDGE, kind: 'message', notification, data});
    return;
  }
  await self.registration.showNotification(notification.title ?? 'TrailBuddy', {
    body: notification.body ?? '',
    icon: `${APP_BASE}icons/Icon-192.png`,
    data,
  });
}

async function onTap(data) {
  const windows = await appWindows();
  if (windows.length > 0) {
    const target = windows.find((c) => c.focused) ?? windows[0];
    try {
      await target.focus();
    } catch (_) {
      // Fokus geht nur aus einem Klick heraus; die Übergabe gilt trotzdem.
    }
    target.postMessage({type: BRIDGE, kind: 'tap', data});
    return;
  }
  await self.clients.openWindow(appUrl(data.route));
}

self.addEventListener('push', (event) => {
  const payload = payloadOf(event);
  if (!payload) return;
  event.waitUntil(onPush(payload));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(onTap(event.notification.data ?? {}));
});

// Sofort übernehmen: Ein neuer Stand dieser Datei soll nicht warten, bis
// jede alte Seite zu ist — sonst entschiede bis dahin der alte Worker.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
