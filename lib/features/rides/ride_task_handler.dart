// Die Fahrt im Isolate des Foreground-Service (#28; PilzBuddy #342).
//
// **Warum hier und nicht im Main-Isolate.** Wischt der Nutzer die App
// aus der Übersicht, stirbt der Flutter-Prozess samt allen Dart-Timern —
// der Service läuft sichtbar weiter, und aufgezeichnet würde trotzdem
// nichts. PilzBuddy hat genau das im Feld gesehen (2026-08-27).
// `flutter_foreground_task` startet für den Service ein EIGENES
// Flutter-Isolate, das das Wegwischen überlebt. Was hier steht, läuft
// dort — und nur dort.
//
// **Was in diesem Isolate NICHT gilt:** kein Riverpod, keine Widgets,
// kein `logError` mit Sink. Alles, was gebraucht wird, kommt über die
// Brücke (`FlutterForegroundTask.saveData`, also SharedPreferences —
// lesbar in beiden Isolaten) oder aus der Datei.
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../routing/nav_notice.dart';
import 'ride_confirm.dart';
import 'ride_confirm_notify.dart';
import 'ride_store.dart';
import 'ride_track.dart';

/// Schlüssel der Brücke zwischen den Isolaten. Bewusst flache Werte:
/// `saveData` nimmt nur int, double, String und bool an.
const kRideDataDir = 'ride_dir';
const kRideDataUid = 'ride_uid';
const kRideDataActive = 'ride_active';

/// Beginn der laufenden Fahrt (ISO-8601, UTC) — trägt die Frage an einen
/// Trail (#116) in ihrer Benachrichtigung mit, damit eine späte Antwort
/// nicht in einer anderen Fahrt landet.
const kRideDataStartedAt = 'ride_started_at';

/// Ein gemessener Punkt als Zeichenkette an den Main-Isolate —
/// `sendDataToMain` trägt nur einfache Werte.
String encodeRideTick(RidePoint point) =>
    '${point.lat};${point.lng};${point.at.toUtc().toIso8601String()};'
    '${point.accuracyM};${point.altM ?? ''}';

RidePoint? decodeRideTick(Object? data) {
  if (data is! String) return null;
  final parts = data.split(';');
  if (parts.length != 5) return null;
  final lat = double.tryParse(parts[0]);
  final lng = double.tryParse(parts[1]);
  final at = DateTime.tryParse(parts[2]);
  final accuracy = double.tryParse(parts[3]);
  if (lat == null || lng == null || at == null || accuracy == null) return null;
  return RidePoint(
      lat: lat,
      lng: lng,
      at: at.toUtc(),
      accuracyM: accuracy,
      altM: double.tryParse(parts[4]));
}

/// Ein Takt der Aufzeichnung: messen, anhängen, melden.
///
/// Gibt zurück, was gemessen wurde — `null`, wenn keine Fahrt läuft oder
/// kein Fix zustande kam. **Wirft nie**: Eine Ausnahme in diesem Isolate
/// hat niemanden, der sie fängt, und beendete die Aufzeichnung für den
/// Rest der Fahrt.
Future<RidePoint?> recordRideTick({
  Future<Position?> Function()? fix,
  RideStore Function(String dir)? storeFor,
  ConfirmNotify? notify,
}) async {
  try {
    final active = await FlutterForegroundTask.getData<bool>(key: kRideDataActive);
    if (active != true) return null;
    final dir = await FlutterForegroundTask.getData<String>(key: kRideDataDir);
    if (dir == null) return null;

    final position = await (fix ?? _fix)();
    if (position == null) return null;
    final point = RidePoint(
      lat: position.latitude,
      lng: position.longitude,
      at: position.timestamp.toUtc(),
      accuracyM: position.accuracy,
      altM: position.altitude,
    );

    final store = (storeFor ?? _storeFor)(dir);
    await store.appendPoint(point);
    // Damit die Karte mitläuft, solange jemand hinsieht. Ist die App weg,
    // geht das ins Leere — und genau dann trägt die Datei allein.
    FlutterForegroundTask.sendDataToMain(encodeRideTick(point));
    await _confirmTick(point, store: store, dir: dir, notify: notify ?? _notify);
    return point;
  } catch (_) {
    return null;
  }
}

RideStore _storeFor(String dir) => FileRideStore(baseDir: Directory(dir));

/// Zeigt die Frage zu einem Trail; die Naht für den Test.
typedef ConfirmNotify = Future<void> Function(ConfirmTarget target, {required String payload});

Future<void> _notify(ConfirmTarget target, {required String payload}) =>
    showConfirmNotice(target, payload: payload);

/// Der Wächter der laufenden Fahrt — einer je Fahrt, im Speicher dieses
/// Isolates. Stirbt das Isolate, liest der nächste die gestellten Fragen
/// aus der Datei; nur der vorige Punkt ist dann weg (ein Takt später
/// geht es weiter).
RideConfirmWatcher? _watcher;

Future<void> _confirmTick(RidePoint point,
    {required RideStore store, required String dir, required ConfirmNotify notify}) async {
  try {
    final uid = await FlutterForegroundTask.getData<String>(key: kRideDataUid);
    final started = DateTime.tryParse(
        await FlutterForegroundTask.getData<String>(key: kRideDataStartedAt) ?? '');
    if (uid == null || started == null) return;
    final watcher = _watcher;
    final current = watcher != null &&
            watcher.uid == uid &&
            watcher.rideStartedAt.isAtSameMomentAs(started)
        ? watcher
        : _watcher = RideConfirmWatcher(uid: uid, rideStartedAt: started.toUtc(), dir: dir);
    await current.onPoint(point, store: store, notify: notify);
  } catch (_) {
    // Die Frage ist ein Zusatz; die Fahrt läuft weiter.
  }
}

/// Fragt je Trail und Fahrt höchstens einmal (#116). Die Ziele liest er
/// aus der Datei, die die App schreibt — neu nur, wenn sie sich ändert.
class RideConfirmWatcher {
  RideConfirmWatcher({required this.uid, required this.rideStartedAt, required this.dir});

  final String uid;
  final DateTime rideStartedAt;
  final String dir;

  RidePoint? _previous;
  Set<String>? _asked;
  List<ConfirmTarget> _targets = const [];
  Object? _version = const Object();

  Future<void> onPoint(RidePoint point,
      {required RideStore store, required ConfirmNotify notify}) async {
    final previous = _previous;
    _previous = point;
    final version = store is FileRideStore ? await store.confirmTargetsModified() : null;
    if (version != _version || store is! FileRideStore) {
      _version = version;
      _targets = await store.readConfirmTargets(uid: uid);
    }
    if (_targets.isEmpty) return;
    final asked = _asked ??= {
      for (final e in await store.activeConfirmEvents(uid: uid))
        if (e is ConfirmAsked) e.trailId,
    };
    final target =
        confirmPromptFor(targets: _targets, previous: previous, current: point, asked: asked);
    if (target == null) return;
    asked.add(target.trailId);
    // Erst ins Protokoll, dann fragen: Die Antwort braucht die Frage
    // (was bestätigt wird, steht dort), und ein Neustart des Isolates
    // soll nicht noch einmal fragen.
    await store.appendConfirmEvent(ConfirmAsked.of(target, at: point.at));
    await notify(target,
        payload: encodeConfirmPayload(
            (dir: dir, uid: uid, rideStartedAt: rideStartedAt, trailId: target.trailId)));
  }
}

Future<Position?> _fix() async {
  try {
    // KEIN `timeLimit` (PilzBuddy-Lehre): Es machte aus jedem langsamen
    // Hintergrund-Fix stillschweigend gar keinen.
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    );
  } catch (_) {
    // Kein Empfang zum Himmel: ein fehlender Fix ist kein Fehler,
    // sondern der Wald.
    return null;
  }
}

/// Ein Takt des Dienstes: Fahrt und Navigation (#232) teilen sich EINEN
/// Fix — zwei GPS-Abfragen je Takt kosteten Akku und lieferten zwei
/// leicht verschiedene Punkte. Gefragt wird erst, wenn eines von beiden
/// läuft. Wirft nie.
Future<void> serviceTick({Future<Position?> Function()? fix}) async {
  try {
    final recording = await FlutterForegroundTask.getData<bool>(key: kRideDataActive) == true;
    final navigating = await FlutterForegroundTask.getData<bool>(key: kNavDataActive) == true;
    if (!recording && !navigating) return;
    Future<Position?>? once;
    Future<Position?> shared() => once ??= (fix ?? _fix)();
    if (recording) await recordRideTick(fix: shared);
    if (navigating) await navTick(fix: shared, recording: recording);
  } catch (_) {
    // Der nächste Takt versucht es wieder.
  }
}

/// Der Task-Handler des Service: misst je Takt, solange die Brücke
/// „aktiv" sagt.
class RideTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Nicht abgewartet: `onRepeatEvent` ist synchron, der nächste Takt
    // kommt erst nach dem eingestellten Abstand.
    serviceTick();
  }

  /// „Navigation beenden" (#232) — auch wenn die App weggewischt ist.
  @override
  void onNotificationButtonPressed(String id) {
    if (id == kNavStopButton) stopNavFromService();
  }

  /// Der Tipp öffnet die App von selbst (Launch-Intent des Pakets); läuft
  /// sie noch, soll sie die Karte zeigen, nicht den letzten Reiter.
  @override
  void onNotificationPressed() => FlutterForegroundTask.sendDataToMain(kNavMessageOpen);

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
