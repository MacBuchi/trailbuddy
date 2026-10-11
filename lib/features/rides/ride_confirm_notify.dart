// Die lokale Frage während der Fahrt (#116) — gezeigt aus dem
// Service-Isolate, beantwortet über die Knöpfe der Benachrichtigung.
//
// **Warum `flutter_local_notifications` und nicht die Dauerbenachrichtigung
// der Fahrt.** Deren Kanal (`ride_recording`) ist leise: Android zeigt
// eine Änderung dort nicht als Banner, und wer mit dem Telefon in der
// Tasche fährt, sähe die Frage nie. Der Kanal der Meldungen
// (`trailbuddy_meldungen`, IMPORTANCE_HIGH, angelegt in
// `MainActivity.onCreate`) zeigt ein Banner — genau der wird benutzt.
// Das Paket läuft im Service-Isolate, weil `flutter_foreground_task` dort
// eine eigene `FlutterEngine` mit allen Plugins startet.
//
// **Wo eine Antwort landet.** Knöpfe OHNE Oberfläche („Stimmt", „Trail
// ist frei") laufen in einem eigenen Hintergrund-Isolate des Pakets
// ([rideConfirmBackgroundResponse]); „Ändern…" und der Tipp auf die
// Benachrichtigung öffnen die App und kommen im Main-Isolate an
// ([rideConfirmTapsProvider]). Beide Wege schreiben dieselbe Zeile in
// die Fahrt-Datei ([handleConfirmResponse]) — die Datei ist die eine
// Wahrheit, gesendet wird beim Beenden der Fahrt.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../l10n/l10n.dart';
import 'ride_confirm.dart';
import 'ride_store.dart';

/// Der Kanal der Meldungen — derselbe wie für Push (`strings.xml`,
/// `MainActivity.kt`); der Manifest-Test hält die Namen zusammen.
const kConfirmChannelId = 'trailbuddy_meldungen';
const kConfirmChannelName = 'Meldungen';

/// Das Symbol, nur Alphakanal (wie bei Push und Fahrt).
const kConfirmNotificationIcon = 'ic_notification';

/// Was die Benachrichtigung zur Antwort mitträgt: wo die Fahrt liegt, zu
/// welchem Konto und welcher Fahrt sie gehört, und welcher Trail.
typedef ConfirmPayload = ({String dir, String uid, DateTime rideStartedAt, String trailId});

String encodeConfirmPayload(ConfirmPayload p) => jsonEncode({
      'dir': p.dir,
      'uid': p.uid,
      'ride': p.rideStartedAt.toUtc().toIso8601String(),
      'trail': p.trailId,
    });

ConfirmPayload? decodeConfirmPayload(String? text) {
  if (text == null) return null;
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) return null;
    final dir = json['dir'], uid = json['uid'], trail = json['trail'];
    final ride = DateTime.tryParse(json['ride'] as String? ?? '');
    if (dir is! String || uid is! String || trail is! String || ride == null) return null;
    return (dir: dir, uid: uid, rideStartedAt: ride.toUtc(), trailId: trail);
  } catch (_) {
    return null;
  }
}

/// Eine feste Kennung je Trail, damit eine zweite Frage zum selben Trail
/// (neue Fahrt) die alte ersetzt statt sich daneben zu stellen. FNV-1a —
/// `String.hashCode` ist über Isolate-Grenzen nicht zugesichert.
int confirmNotificationId(String trailId) {
  var h = 0x811c9dc5;
  for (final c in trailId.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

/// Schreibt die Antwort (wenn es eine ist) in die Fahrt und gibt den
/// Trail zurück, zu dem gefragt wurde. Wirft nie.
Future<String?> handleConfirmResponse({
  required String? actionId,
  required String? payload,
  DateTime? now,
  RideStore Function(String dir)? storeFor,
}) async {
  try {
    final p = decodeConfirmPayload(payload);
    if (p == null) return null;
    final choice = ConfirmChoice.fromId(actionId);
    if (choice != null) {
      final store = (storeFor ?? _storeFor)(p.dir);
      await store.appendConfirmEvent(
        ConfirmAnswered(trailId: p.trailId, at: (now ?? DateTime.now()).toUtc(), choice: choice),
        rideStartedAt: p.rideStartedAt,
      );
    }
    return p.trailId;
  } catch (_) {
    return null;
  }
}

RideStore _storeFor(String dir) => FileRideStore(baseDir: Directory(dir));

/// Die Knöpfe ohne Oberfläche. Läuft in einem Isolate, das das Paket
/// eigens dafür startet — darum top-level und `vm:entry-point`.
@pragma('vm:entry-point')
void rideConfirmBackgroundResponse(NotificationResponse response) {
  unawaited(handleConfirmResponse(actionId: response.actionId, payload: response.payload));
}

final _plugin = FlutterLocalNotificationsPlugin();
Future<bool?>? _initialized;

Future<void> _init({DidReceiveNotificationResponseCallback? onResponse}) async {
  await (_initialized ??= _plugin.initialize(
    settings: const InitializationSettings(
        android: AndroidInitializationSettings(kConfirmNotificationIcon)),
    onDidReceiveNotificationResponse: onResponse,
    onDidReceiveBackgroundNotificationResponse: rideConfirmBackgroundResponse,
  ));
}

/// Zeigt die Frage. Aufgerufen im Service-Isolate; wirft nie — ohne
/// Benachrichtigung fragt das Zerlege-Blatt am Ende.
Future<void> showConfirmNotice(ConfirmTarget target, {required String payload}) async {
  try {
    await _init();
    // Kein BuildContext im Service-Isolate: die Sprache der App, fest
    // Deutsch bis #209 sie freigibt (`appLocaleProvider`). Welche Sprache
    // die Benachrichtigung dann spricht, entscheidet die Stufe der Fahrten.
    final notice = confirmNoticeOf(lookupAppLocalizations(const Locale('de')), target);
    await _plugin.show(
      id: confirmNotificationId(target.trailId),
      title: notice.title,
      body: notice.body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          kConfirmChannelId,
          kConfirmChannelName,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.recommendation,
          styleInformation: BigTextStyleInformation(notice.body),
          actions: [
            for (final (choice, label) in notice.actions)
              AndroidNotificationAction(
                choice.id,
                label,
                cancelNotification: true,
                // „Ändern…" braucht die App; die anderen beiden
                // antworten, ohne sie zu öffnen — die Hand ist am Lenker.
                showsUserInterface: choice == ConfirmChoice.change,
              ),
          ],
        ),
      ),
    );
  } catch (_) {
    // Kein Kanal, keine Berechtigung, kein Plugin: Das Zerlege-Blatt
    // fragt am Ende noch einmal. Ein Bericht je Trail wäre Lärm.
  }
}

/// Die Trails, zu denen eine Frage in der App angetippt wurde (Tipp auf
/// die Benachrichtigung oder „Ändern…") — auch der Tipp, der die App
/// erst gestartet hat. Nur Android; im Test überschrieben.
final rideConfirmTapsProvider = Provider<Stream<String> Function()>((ref) => _platformTaps);

Stream<String> _platformTaps() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return const Stream.empty();
  final controller = StreamController<String>();
  Future<void> forward(NotificationResponse r) async {
    final trail = await handleConfirmResponse(actionId: r.actionId, payload: r.payload);
    if (trail != null && !controller.isClosed) controller.add(trail);
  }

  () async {
    try {
      await _init(onResponse: forward);
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) await forward(response);
    } catch (e, stackTrace) {
      logError('Fahrt: Antworten auf Fragen verdrahten', e, stackTrace);
    }
  }();
  return controller.stream;
}
