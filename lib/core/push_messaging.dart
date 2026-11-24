// Die Plattformseite der Push-Benachrichtigungen (#34; PilzBuddy #277 als
// Muster): Firebase starten, ein Token holen, auf das Antippen einer
// Meldung hören.
//
// **Push ist ein Nebenfeature.** Jeder Fehlerpfad endet hier in `null` =
// kein Token = keine Registrierung. Ein fehlendes, kaputtes oder
// abgelaufenes Firebase-Projekt darf die App nicht am Starten hindern —
// dieselbe Linie wie beim Update-Check und bei der Onlinekarte: Optionale
// Wege dürfen still degradieren, der Kernpfad nicht.
//
// Die Berechtigung wird NICHT beim Start erfragt. Sie kommt erst, wenn
// jemand im Profil den Schalter umlegt — ein Systemdialog beim ersten
// Start, bevor die Karte auch nur zu sehen war, ist die zuverlässigste
// Art, ein „Nein für immer" zu bekommen (dieselbe Regel wie beim
// Standort, `position_provider.dart`).
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'errors.dart';
import 'platform_support.dart';
import 'push_config.dart';
import 'push_web_bridge.dart';

/// Firebase starten — auf Android OHNE Optionen.
///
/// Das Google-Services-Gradle-Plugin startet die Standard-App nativ aus
/// `google-services.json`, bevor Dart überhaupt läuft. Ein zweites
/// `initializeApp` mit Optionen quittiert das mit `[core/duplicate-app]`
/// — folgenlos, aber es verdeckt die echten Meldungen. Im Web gibt es
/// diesen Vorlauf nicht, dort sind die Optionen Pflicht — und fehlen sie
/// noch (`push_config.dart`), gibt es keine App und kein Token.
Future<void> _ensureFirebase() async {
  if (Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp(options: kIsWeb ? pushFirebaseOptions : null);
}

/// Fehlt diesem Build die Firebase-Konfiguration? Dann ist ein Scheitern
/// beim Start kein Fehler des Geräts, sondern des Builds — „noch nicht
/// eingerichtet" statt eines Eintrags im Wochendigest.
///
/// Zwei Formen, beide gesehen: `[core/…]` aus dem Dart-Teil von
/// firebase_core, und — ohne `google-services.json` auf Android — die
/// `PlatformException` „Failed to load FirebaseOptions from resource"
/// aus dem nativen Teil (`optionsFromResource`). Die zweite kam bis
/// 0.36.x als Fehlerbericht an (Wochendigest #62).
bool isMissingFirebaseConfig(Object error) =>
    (error is FirebaseException && error.plugin == 'core') ||
    (error is PlatformException &&
        (error.message ?? '').contains('Failed to load FirebaseOptions'));

/// Wo der Web-Push-Worker liegt — RELATIV, und das ist der ganze Punkt.
///
/// Ohne Angabe sucht das FCM-SDK `/firebase-messaging-sw.js` am
/// **Origin-Root**. Unsere Web-App liegt unter `/trailbuddy/`, dort steht
/// also nichts — 404, und `getToken` scheitert dauerhaft und STILL. Ein
/// absoluter Pfad MIT Präfix wäre eine weitere Stelle, die mit
/// `--base-href` synchron bleiben müsste. Relativ löst der Browser gegen
/// das `<base href>` auf, das Flutter beim Bauen ohnehin setzt.
///
/// Das Unterverzeichnis ist ebenfalls Absicht — die Begründung steht in
/// der Datei selbst: Der Offline-Worker `sw.js` hat den Basis-Scope, und
/// zwei Worker im selben Scope verdrängen sich.
const webServiceWorkerPath = 'push/firebase-messaging-sw.js';

/// Was beim Holen eines Tokens herauskam.
///
/// **Ein nacktes `null` genügt hier nicht.** Wer ablehnt, wer kein Netz
/// hat und wer einen Build ohne Firebase-Konfiguration benutzt, bekommen
/// sonst denselben Satz — und die Berechtigungs-Erklärung ist im
/// Funkloch schlicht falsch: Sie schickt jemanden in die
/// Android-Einstellungen, wo alles in Ordnung ist.
/// Gibt es Push auf dieser Plattform? Web und Android. Auf dem iPhone
/// noch nicht (#644): ohne APNs-Schlüssel und `GoogleService-Info.plist`
/// kein Token, und `push_devices` kennt die Plattform nicht. Der Schalter
/// im Profil sagt dann „nicht eingerichtet" (`unavailable`).
bool get pushPlatformSupported => kIsWeb || isAndroidApp;

typedef PushTokenResult = ({String? token, bool denied, bool unavailable});

/// Das FCM-Token dieses Geräts.
///
/// Fragt dabei die Systemberechtigung ab. `denied` sagt, ob die Absage
/// von der Nutzerin kam; `unavailable`, dass dieser Build gar kein
/// Firebase hat (Web ohne Konfiguration, Android ohne
/// `google-services.json`). Alles andere (kein Netz, keine
/// Play-Dienste, Zeitüberschreitung) liefert beides `false`.
Future<PushTokenResult> requestPushToken() async {
  if (!pushPlatformSupported || (kIsWeb && !pushWebConfigured)) {
    return (token: null, denied: false, unavailable: true);
  }
  try {
    await _ensureFirebase();
  } catch (e, stackTrace) {
    // Ohne google-services.json hat Android keine Standard-App; das ist
    // kein Fehler dieses Geräts, sondern dieses Builds — und kein Fund
    // für den Wochendigest.
    if (isMissingFirebaseConfig(e)) {
      return (token: null, denied: false, unavailable: true);
    }
    logError('Firebase starten', e, stackTrace);
    return (token: null, denied: false, unavailable: false);
  }
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return (token: null, denied: true, unavailable: false);
    }
    // Mit Frist: `getToken` scheitert nicht immer, es bleibt auch mal
    // stehen — etwa wenn die Registrierung bei FCM nicht durchkommt. Ohne
    // die Frist hinge der Schalter im Profil an einem Vorgang, der nie
    // endet. Ein Timeout landet unten im catch und wird zu „kein Token".
    final token = await messaging
        .getToken(
          vapidKey: kIsWeb ? pushWebVapidKey : null,
          serviceWorkerScriptPath: kIsWeb ? webServiceWorkerPath : null,
        )
        .timeout(const Duration(seconds: 15));
    return (token: token, denied: false, unavailable: false);
  } catch (e, stackTrace) {
    // Gemeldet, aber nicht geworfen: Dass Push nicht geht, ist eine
    // Information — dass die App deshalb stehen bleibt, wäre ein Fehler.
    logError('Push-Token holen', e, stackTrace);
    return (token: null, denied: false, unavailable: false);
  }
}

/// Wie die App an ein Token kommt — die Test-Naht.
///
/// Im Widget-Test gibt es weder FCM noch Berechtigungsdialoge; das
/// Harness überschreibt diesen Provider, sonst hinge jeder Test, der das
/// Profil öffnet, an einer Plattform, die es dort nicht gibt.
final pushTokenProvider = Provider<Future<PushTokenResult> Function()>(
  (ref) => requestPushToken,
);

/// Auf das Antippen einer Meldung hören.
///
/// **Bewusst KEIN eigener `onBackgroundMessage`-Handler.** Er erzeugte in
/// PilzBuddys Nachbarprojekt eine zweite Benachrichtigung neben der, die
/// das System ohnehin anzeigt.
///
/// **Im Web über den eigenen Worker, nicht über Firebase.** Dort holt
/// sich `onMessageOpenedApp` die Firebase-App — die es erst gibt, wenn
/// jemand Push eingeschaltet hat; das warf bei jedem Seitenaufruf. Der
/// Worker reicht den Tipp selbst an ein offenes Fenster weiter
/// ([pushBridgeMessageOf]); ist keines offen, öffnet er die App gleich
/// am Ziel.
Stream<RemoteMessage> pushTaps() => kIsWeb
    ? _bridged('tap')
    : pushPlatformSupported
    ? FirebaseMessaging.onMessageOpenedApp
    : const Stream.empty();

/// Dieselbe Naht für das Antippen.
final pushTapListenerProvider = Provider<Stream<RemoteMessage> Function()>(
  (ref) => pushTaps,
);

/// Die Meldung, mit deren Tipp die App aus dem BEENDETEN Zustand
/// gestartet wurde. `onMessageOpenedApp` sieht nur den Fall „lief im
/// Hintergrund"; ohne diese Abfrage öffnete ein Tipp nach einem Neustart
/// nur die Karte, nie den Trail.
final pushInitialMessageProvider = Provider<Future<RemoteMessage?> Function()>(
  (ref) => initialPushMessage,
);

/// Die Startmeldung — oder `null`, auch wenn Push hier gar nicht geht.
///
/// **Erst Firebase starten, dann fragen** (PilzBuddy 1.201.0: ohne das
/// gut hundert Fehlerberichte an einem Tag, „[core/no-app]"). Ohne
/// Firebase (Gerät ohne Play-Dienste, Build ohne google-services.json)
/// gibt es schlicht keine Startmeldung — kein Fehler für den
/// Wochendigest, Push ist ein Nebenfeature.
///
/// **Im Web gar nicht.** Dort gibt es keine Startmeldung — ein Tipp auf
/// eine Web-Push öffnet die Seite selbst am Ziel —, und `initializeApp`
/// lädt im Browser das Firebase-SDK von `www.gstatic.com`: bei JEDEM
/// Seitenaufruf, auch für alle, die Push nie eingeschaltet haben. Auf
/// Android ist die Standard-App längst nativ gestartet, `_ensureFirebase`
/// lädt dort nichts nach.
Future<RemoteMessage?> initialPushMessage() async {
  if (kIsWeb || !pushPlatformSupported) return null;
  try {
    await _ensureFirebase();
  } catch (_) {
    // Kein Firebase ⇒ keine Startmeldung. Begründung oben.
    return null;
  }
  return FirebaseMessaging.instance.getInitialMessage();
}

/// Nachrichten, die eintreffen, **während die App im Vordergrund ist**.
///
/// Ohne diesen Zweig verschwinden sie spurlos: Android und der Service
/// Worker zeigen eine `notification`-Nutzlast nur an, solange die App
/// **nicht** vorne ist. Ist sie es, liefert FCM sie ausschließlich
/// hierher. Der Testknopf im Profil könnte sonst gar nicht
/// funktionieren — beim Tippen ist die App zwangsläufig vorne —, und
/// schlimmer: Auch ein echter Versand verpufft, wenn jemand die App
/// zufällig offen hat; der Versender verbucht ihn als zugestellt.
///
/// **Im Web kommt sie vom eigenen Worker** — und nur, wenn ein Fenster
/// DIESER App im Fokus ist; sonst zeigt der Browser sie an.
Stream<RemoteMessage> pushMessages() => kIsWeb
    ? _bridged('message')
    : pushPlatformSupported
    ? FirebaseMessaging.onMessage
    : const Stream.empty();

/// Die Kennung, mit der der Worker seine Nachrichten markiert — dieselbe
/// Zeichenkette wie `BRIDGE` in `web/push/firebase-messaging-sw.js`
/// (`test/push_service_worker_test.dart` hält beide zusammen).
const kPushBridgeType = 'trailbuddy-push';

Stream<RemoteMessage> _bridged(String kind) => serviceWorkerMessages()
    .map(pushBridgeMessageOf)
    .where((m) => m?.kind == kind)
    .map((m) => m!.message);

/// Deutet eine Nachricht des Web-Push-Workers — `null` für alles, was
/// nicht von ihm stammt oder nicht passt. Der Offline-Worker `sw.js`
/// schickt der Seite ebenfalls Nachrichten; die bleiben liegen.
({String kind, RemoteMessage message})? pushBridgeMessageOf(Object? raw) {
  if (raw is! Map || raw['type'] != kPushBridgeType) return null;
  final kind = raw['kind'];
  if (kind is! String) return null;
  final data = <String, dynamic>{
    for (final MapEntry(:key, :value)
        in (raw['data'] as Map? ?? const {}).entries)
      if (key is String && value is String) key: value,
  };
  final n = raw['notification'];
  return (
    kind: kind,
    message: RemoteMessage(
      data: data,
      notification: n is Map
          ? RemoteNotification(
              title: n['title'] as String?,
              body: n['body'] as String?,
            )
          : null,
    ),
  );
}

/// Dieselbe Naht für Vordergrund-Nachrichten.
final pushMessageListenerProvider = Provider<Stream<RemoteMessage> Function()>(
  (ref) => pushMessages,
);
