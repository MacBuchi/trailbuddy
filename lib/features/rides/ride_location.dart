// Der Standort der Fahrt je Plattform (#644, Paket 3).
//
// **Android** fragt je Takt (5 s) einen einzelnen Fix ab; den Prozess hält
// der Vordergrunddienst am Leben, auch nach dem Wegwischen.
//
// **iOS** hat keinen solchen Dienst. `flutter_foreground_task` startet dort
// zwar eine zweite Engine im SELBEN Prozess und taktet sie mit einem
// Timer, hält den Prozess aber nicht wach — das tut nur ein laufender
// Standortstrom mit `allowsBackgroundLocationUpdates` (dafür
// `UIBackgroundModes: location` in `Info.plist`; `geolocator_apple` setzt
// das Merkmal nur, wenn der Eintrag da ist). Der Strom muss im Vordergrund
// beginnen: Mit „Beim Benutzen" erlaubt iOS ihn danach im Hintergrund und
// bei gesperrtem Bildschirm und zeigt dafür den blauen Standort-Hinweis
// (`showBackgroundLocationIndicator`) — die Offenlegung, wie auf Android
// die stehende Benachrichtigung. Deshalb hält die Engine des Dienstes auf
// iOS EINEN Strom ([HeldFix]), und der Takt liest dessen letzten Punkt.
//
// Wischt man die App weg, endet der Prozess samt Strom; iOS startet sie
// danach nicht wieder (das ginge nur mit „Immer" und Ortswechsel-Diensten,
// und das versprechen wir nicht). `RideNotifier.restore` zeigt beim
// nächsten Start die Lücke.
import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../core/platform_support.dart';

/// Wie die Fahrt den Standort abonniert. `geolocator_apple` hält je Engine
/// EINEN Strom: Wer ihn zuerst öffnet, bestimmt die Einstellungen — die
/// Fahrt und der Sensor-Logger nehmen deshalb dieselben.
LocationSettings rideLocationSettings({
  Duration interval = const Duration(seconds: 1),
}) {
  if (isIosApp) {
    return AppleSettings(
      accuracy: LocationAccuracy.best,
      activityType: ActivityType.fitness,
      // Hielte iOS den Strom an, wenn es Stillstand vermutet, käme er im
      // Hintergrund nicht von selbst wieder — die Fahrt wäre still zu Ende.
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    );
  }
  return AndroidSettings(
    accuracy: LocationAccuracy.best,
    intervalDuration: interval,
  );
}

/// So alt darf der letzte Punkt des Stroms höchstens sein, damit ein Takt
/// ihn noch nimmt — zwei Takte. Älter heißt: kein Empfang, und ein alter
/// Punkt mit neuer Zeile wäre eine erfundene Messung.
const kHeldFixMaxAge = Duration(seconds: 10);

/// Ein laufender Standortstrom, dessen letzten Punkt der Takt liest (iOS).
///
/// [start] im Vordergrund aufrufen (beim Start des Dienstes); [fix] startet
/// den Strom notfalls selbst, falls er abgerissen ist. Fehler des Stroms
/// (Berechtigung entzogen, kein Empfang) beenden ihn nicht; endet er doch,
/// öffnet der nächste [fix] einen neuen.
class HeldFix {
  HeldFix({
    Stream<Position> Function()? positions,
    DateTime Function()? now,
    this.maxAge = kHeldFixMaxAge,
  }) : _positions = positions ?? _platform,
       _now = now ?? DateTime.now;

  final Stream<Position> Function() _positions;
  final DateTime Function() _now;
  final Duration maxAge;

  StreamSubscription<Position>? _sub;
  Position? _last;
  DateTime? _taken;

  static Stream<Position> _platform() =>
      Geolocator.getPositionStream(locationSettings: rideLocationSettings());

  bool get running => _sub != null;

  void start() {
    if (_sub != null) return;
    try {
      _sub = _positions().listen(
        (p) => _last = p,
        onError: (Object _) {},
        onDone: () => _sub = null,
      );
    } catch (_) {
      // Ohne Kanal (Test) oder Berechtigung: Der nächste Takt versucht es.
      _sub = null;
    }
  }

  /// Der letzte Punkt, wenn er frisch und noch nicht genommen ist; sonst
  /// `null` (der Wald). Steht man still, schickt iOS seltener — derselbe
  /// Punkt zweimal wäre eine Zeile ohne Messung.
  Future<Position?> fix() async {
    start();
    final p = _last;
    if (p == null || p.timestamp == _taken) return null;
    if (_now().difference(p.timestamp) > maxAge) return null;
    _taken = p.timestamp;
    return p;
  }

  Future<void> stop() async {
    final sub = _sub;
    _sub = null;
    _last = null;
    _taken = null;
    await sub?.cancel();
  }
}
