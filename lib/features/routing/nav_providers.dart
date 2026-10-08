// Der Zustand der Navigation (#232, Konzept-Routing 9): welche Linie,
// wo man auf ihr ist, ob die Karte dreht. Die Folgeansicht und die Karte
// lesen dieselbe Wahrheit; gerechnet wird in `route_progress.dart`.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/settings.dart';
import '../trails/terrain_heights.dart';
import 'route_progress.dart';

/// Nach „Angekommen" endet die Navigation von selbst (9.3).
const kNavArrivedLinger = Duration(minutes: 1);

/// Was navigiert werden soll — gestellt von einem Ergebnis-Blatt oder aus
/// „Meine Fahrten", eingelöst von der Karte (Muster
/// `trailHeadRequestProvider`): Die Karte fragt nach Aufzeichnen und
/// Bildschirm, holt den Standort und startet.
class NavRequest {
  const NavRequest({required this.points, required this.title});

  /// Die Linie in Fahrtrichtung, wie sie die Karte zeichnet.
  final List<LatLng> points;
  final String title;
}

final navRequestProvider = StateProvider<NavRequest?>((ref) => null);

/// Eine laufende Navigation.
class NavSession {
  const NavSession({
    required this.route,
    required this.title,
    this.state,
    this.climbDistM,
    this.climbEleM,
    this.north = false,
  });

  final NavRoute route;
  final String title;

  /// Der Stand nach dem letzten Fix; null bis zum ersten.
  final NavState? state;

  /// Das Profil entlang der Linie aus dem Geländemodell (Proben), für die
  /// Höhenmeter, die noch kommen. Null, solange gelesen wird oder wenn
  /// eine Kachel fehlt — dann zeigt die Leiste nur km.
  final List<double>? climbDistM;
  final List<double>? climbEleM;

  /// „Norden" (9.2): die Drehung für diese Navigation aus.
  final bool north;

  double get remainingM => state?.remainingM ?? route.lengthM;
  double? get remainingClimbM => climbAfter(climbDistM, climbEleM, state?.alongM ?? 0);

  /// Wohin oben zeigt.
  double get bearingDeg => north ? 0 : (state?.headingDeg ?? route.bearingAt(0));

  NavSession copyWith({NavState? state, List<double>? climbDistM, List<double>? climbEleM, bool? north}) =>
      NavSession(
        route: route,
        title: title,
        state: state ?? this.state,
        climbDistM: climbDistM ?? this.climbDistM,
        climbEleM: climbEleM ?? this.climbEleM,
        north: north ?? this.north,
      );
}

class NavController extends Notifier<NavSession?> {
  NavTracker? _tracker;
  Timer? _linger;

  @override
  NavSession? build() {
    ref.onDispose(() => _linger?.cancel());
    return null;
  }

  bool get isRunning => state != null;

  /// Startet die Navigation auf [points]; false, wenn die Linie keine
  /// Länge hat. Eine laufende wird ersetzt.
  bool start(List<LatLng> points, String title) {
    final route = NavRoute.of(points);
    if (route == null) return false;
    _linger?.cancel();
    _tracker = NavTracker(route);
    final session = NavSession(route: route, title: title);
    state = session;
    unawaited(_loadClimb(session));
    return true;
  }

  Future<void> _loadClimb(NavSession session) async {
    try {
      final profile = await ref.read(terrainHeightsProvider).profile(session.route.points);
      // Inzwischen beendet oder eine andere Navigation: nichts mehr tun.
      if (profile == null || !identical(state?.route, session.route)) return;
      state = state!.copyWith(climbDistM: profile.distM, climbEleM: profile.eleM);
    } catch (_) {
      // Ohne Höhen zeigt die Leiste nur km — das Lesen meldet seine
      // Fehler selbst (`TerrainHeights`).
    }
  }

  /// Ein Fix der eigenen Position. [headingDeg]/[speedMps] wie vom GPS.
  void onFix(LatLng p, {double? headingDeg, double? speedMps}) {
    final tracker = _tracker;
    final session = state;
    if (tracker == null || session == null) return;
    final wasArrived = session.state?.arrived ?? false;
    final next = tracker.update(p, headingDeg: headingDeg, speedMps: speedMps);
    state = session.copyWith(state: next);
    if (next.arrived && !wasArrived) {
      _linger = Timer(kNavArrivedLinger, stop);
    }
  }

  void toggleNorth() {
    final session = state;
    if (session != null) state = session.copyWith(north: !session.north);
  }

  /// Beenden fragt nicht (9.2). Eine Aufzeichnung läuft weiter.
  void stop() {
    _linger?.cancel();
    _linger = null;
    _tracker = null;
    state = null;
  }
}

final navigationProvider = NotifierProvider<NavController, NavSession?>(NavController.new);

/// Bildschirm an in der Folgeansicht (9.4), gemerkt auf dem Gerät.
final navKeepScreenOnProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.navKeepScreenOn,
    write: (s, v) => s.setNavKeepScreenOn(v),
    label: 'Bildschirm-Schalter der Navigation merken',
  ),
);
