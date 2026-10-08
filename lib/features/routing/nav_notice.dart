// Die Navigation in der Dauerbenachrichtigung (#232 Schritt 2,
// Konzept-Routing 9.5). Was hier steht, läuft im Isolate des
// Foreground-Service — wie die Fahrt (`ride_task_handler.dart`), aus
// demselben Grund: Die App kann weggewischt sein, der Dienst nicht.
//
// Die App legt die Route als Datei ab (`rides/nav_route.json`, per
// `.part` + `rename`) und zählt in der Brücke eine Fassung hoch; der
// Dienst liest die Datei nur neu, wenn die Fassung sich ändert. Er rechnet
// mit derselben puren Funktion wie die Folgeansicht (`NavTracker`) aus
// seinen EIGENEN Fixen und schreibt die Leiste als Text in die
// Benachrichtigung. Kein Riverpod, kein `logError` mit Sink — wie drüben.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart' show formatMeters;
import '../rides/ride_service.dart' show kRideNoticeText, kRideNoticeTitle;
import '../rides/ride_store.dart' show FileRideStore;
import '../rides/ride_task_handler.dart' show kRideDataActive, kRideDataDir;
import 'route_progress.dart';

/// Schlüssel der Brücke (SharedPreferences, in beiden Isolaten lesbar).
const kNavDataActive = 'nav_active';

/// Fassung der Routen-Datei — jede neue Fassung liest der Dienst neu.
const kNavDataRev = 'nav_rev';

/// Der Stand, den der Dienst zuletzt gerechnet hat: Startet die App neu,
/// während er navigiert, geht die Folgeansicht dort weiter.
const kNavDataAlong = 'nav_along';

/// Der Knopf in der Benachrichtigung und die Nachrichten an die App.
const kNavStopButton = 'nav_stop';
const kNavStopButtonText = 'Navigation beenden';
const kNavMessageStop = 'nav:stop';
const kNavMessageOpen = 'nav:open';

const kNavRouteFileName = 'nav_route.json';

/// Titel und Text, solange die App den ersten Fix des Dienstes noch nicht
/// kennt.
const kNavNoticeWaiting = 'Navigation läuft — warte auf den Standort';

/// Die Routen-Datei unter [baseDir] (dem Pfad aus `kRideDataDir`).
File navRouteFile(String baseDir) => File('$baseDir/${FileRideStore.dirName}/$kNavRouteFileName');

/// Was der Dienst von der Navigation wissen muss: die Linie, wo der Stand
/// anfängt, und — sobald gelesen — das Höhenprofil für die Höhenmeter,
/// die noch kommen.
class NavRouteData {
  const NavRouteData({
    required this.points,
    required this.title,
    this.startAlongM = 0,
    this.climbDistM,
    this.climbEleM,
  });

  final List<LatLng> points;
  final String title;
  final double startAlongM;
  final List<double>? climbDistM;
  final List<double>? climbEleM;

  NavRouteData withStart(double alongM) => NavRouteData(
      points: points, title: title, startAlongM: alongM, climbDistM: climbDistM, climbEleM: climbEleM);

  String encode() => jsonEncode({
        'v': 1,
        'title': title,
        'start': startAlongM,
        'pts': [
          for (final p in points) [p.latitude, p.longitude],
        ],
        if (climbDistM != null && climbEleM != null) 'climb': {'d': climbDistM, 'e': climbEleM},
      });

  /// Null bei allem, was nicht genau so aussieht — eine halbe Route zu
  /// navigieren wäre schlimmer als keine.
  static NavRouteData? decode(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic> || json['v'] != 1) return null;
      final pts = [
        for (final p in json['pts'] as List)
          LatLng((p as List)[0] as double, p[1] as double),
      ];
      if (pts.length < 2) return null;
      final climb = json['climb'];
      List<double>? nums(Object? list) =>
          list is List ? [for (final v in list) (v as num).toDouble()] : null;
      final d = climb is Map ? nums(climb['d']) : null;
      final e = climb is Map ? nums(climb['e']) : null;
      final paired = d != null && e != null && d.length == e.length;
      return NavRouteData(
        points: pts,
        title: json['title'] as String? ?? '',
        startAlongM: (json['start'] as num?)?.toDouble() ?? 0,
        climbDistM: paired ? d : null,
        climbEleM: paired ? e : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Die Leiste der Folgeansicht als eine Zeile: „Noch 12,4 km · 640 hm ·
/// auf der Route" (9.5). Höhenmeter nur, wenn das Profil gelesen ist.
String navNoticeText(NavState state, {double? climbM}) {
  if (state.arrived) return 'Angekommen';
  return [
    'Noch ${formatMeters(state.remainingM)}',
    if (climbM != null) '${climbM.round()} hm',
    state.offRoute ? '${formatMeters(state.offM)} neben der Route' : 'auf der Route',
  ].join(' · ');
}

/// Der Titel: Läuft die Aufzeichnung mit, sagt er es — sonst stünde die
/// Fahrt nirgends mehr in der Benachrichtigung.
String navNoticeTitle({required bool recording}) =>
    recording ? 'Navigation · Fahrt wird aufgezeichnet' : 'Navigation';

/// Der Stand der Navigation im Dienst — einer je Isolate. Stirbt das
/// Isolate, liest der nächste die Datei und fängt beim Stand der Datei an.
class NavNoticeWatcher {
  NavNoticeWatcher(this.baseDir);

  final String baseDir;

  int? _rev;
  NavRouteData? _data;
  NavTracker? _tracker;
  DateTime? _arrivedAt;

  /// Ein Fix. Null, wenn keine Route liegt (oder die Datei unlesbar ist).
  Future<NavState?> onFix(LatLng p,
      {required int rev, double? headingDeg, double? speedMps}) async {
    if (rev != _rev) {
      _rev = rev;
      final data = await _read();
      final same = data != null && _data != null && _samePoints(_data!.points, data.points);
      _data = data;
      if (data == null) {
        _tracker = null;
      } else if (!same) {
        // Eine neue Linie fängt neu an; dieselbe (nur das Höhenprofil kam
        // dazu) behält ihren Stand.
        final route = NavRoute.of(data.points);
        _tracker = route == null ? null : NavTracker(route, startAlongM: data.startAlongM);
        _arrivedAt = null;
      }
    }
    return _tracker?.update(p, headingDeg: headingDeg, speedMps: speedMps);
  }

  /// Höhenmeter bergauf ab [alongM]; null ohne Profil.
  double? climbAheadM(double alongM) => climbAfter(_data?.climbDistM, _data?.climbEleM, alongM);

  /// Seit wann angekommen — nach [kNavArrivedLinger] endet die Navigation
  /// auch ohne App (9.3).
  bool lingered(NavState state, DateTime now) {
    if (!state.arrived) return false;
    final since = _arrivedAt ??= now;
    return now.difference(since) >= kNavArrivedLinger;
  }

  Future<NavRouteData?> _read() async {
    try {
      final file = navRouteFile(baseDir);
      if (!await file.exists()) return null;
      return NavRouteData.decode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  static bool _samePoints(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Schreibt Titel und Text in die Benachrichtigung; die Naht für den Test.
typedef NavNoticeShow = Future<void> Function(String title, String text);

Future<void> _show(String title, String text) async {
  // Knöpfe bleiben, wie die App sie gesetzt hat (`null` = unverändert).
  await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
}

NavNoticeWatcher? _watcher;

/// Ein Takt der Navigation im Dienst: rechnen, Text setzen, Stand merken.
/// Gibt den Stand zurück; null, wenn keine Navigation läuft oder kein Fix
/// kam. **Wirft nie** — wie `recordRideTick`.
Future<NavState?> navTick({
  required Future<Position?> Function() fix,
  required bool recording,
  NavNoticeShow? show,
  Future<void> Function()? onLingered,
  DateTime Function()? now,
}) async {
  try {
    if (await FlutterForegroundTask.getData<bool>(key: kNavDataActive) != true) return null;
    final dir = await FlutterForegroundTask.getData<String>(key: kRideDataDir);
    if (dir == null) return null;
    final rev = await FlutterForegroundTask.getData<int>(key: kNavDataRev) ?? 0;
    final position = await fix();
    if (position == null) return null;
    final watcher = _watcher?.baseDir == dir ? _watcher! : _watcher = NavNoticeWatcher(dir);
    final state = await watcher.onFix(LatLng(position.latitude, position.longitude),
        rev: rev, headingDeg: position.heading, speedMps: position.speed);
    if (state == null) return null;
    await FlutterForegroundTask.saveData(key: kNavDataAlong, value: state.alongM);
    await (show ?? _show)(
        navNoticeTitle(recording: recording), navNoticeText(state, climbM: watcher.climbAheadM(state.alongM)));
    if (watcher.lingered(state, (now ?? DateTime.now)())) await (onLingered ?? stopNavFromService)();
    return state;
  } catch (_) {
    return null;
  }
}

/// Vergisst den Stand des Dienstes — für Tests, die mehrere Navigationen
/// im selben Isolate fahren.
void resetNavTick() => _watcher = null;

/// „Navigation beenden" in der Benachrichtigung — oder angekommen und die
/// Minute um. Drüben sagt es die App (falls sie lebt); hier endet die
/// Navigation sofort, auch ohne sie: Brücke aus, Datei weg, und ohne
/// laufende Fahrt der ganze Dienst. Läuft eine Fahrt, trägt die
/// Benachrichtigung wieder ihren Text und keinen Knopf. Wirft nie.
Future<void> stopNavFromService({
  Future<void> Function()? stopService,
  Future<void> Function(String title, String text)? showRide,
}) async {
  try {
    await FlutterForegroundTask.saveData(key: kNavDataActive, value: false);
    final dir = await FlutterForegroundTask.getData<String>(key: kRideDataDir);
    if (dir != null) {
      final file = navRouteFile(dir);
      if (await file.exists()) await file.delete();
    }
    _watcher = null;
    FlutterForegroundTask.sendDataToMain(kNavMessageStop);
    final recording = await FlutterForegroundTask.getData<bool>(key: kRideDataActive) == true;
    if (recording) {
      await (showRide ?? _showRide)(kRideNoticeTitle, kRideNoticeText);
    } else {
      await (stopService ?? _stopService)();
    }
  } catch (_) {
    // Im Dienst gibt es niemanden, der fängt; die App räumt beim nächsten
    // Start auf (`restore` verlangt einen laufenden Dienst).
  }
}

Future<void> _stopService() async {
  await FlutterForegroundTask.stopService();
}

Future<void> _showRide(String title, String text) async {
  await FlutterForegroundTask.updateService(
      notificationTitle: title, notificationText: text, notificationButtons: const []);
}
