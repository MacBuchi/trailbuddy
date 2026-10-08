// Der Zustand der Navigation (#232, Konzept-Routing 9): welche Linie,
// wo man auf ihr ist, ob die Karte dreht. Die Folgeansicht und die Karte
// lesen dieselbe Wahrheit; gerechnet wird in `route_progress.dart`.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../core/settings.dart';
import '../profile/profile_providers.dart';
import '../trails/terrain_heights.dart';
import 'loop_planner.dart' show LoopPrefs;
import 'planning_graph.dart';
import 'ride_calibrator.dart';
import 'route_profile.dart' show RiderParamsPrefs;
import 'route_progress.dart';
import 'trail_head_route.dart';

/// Nach „Angekommen" endet die Navigation von selbst (9.3).
const kNavArrivedLinger = Duration(minutes: 1);

/// Was navigiert werden soll — gestellt von einem Ergebnis-Blatt oder aus
/// „Meine Fahrten", eingelöst von der Karte (Muster
/// `trailHeadRequestProvider`): Die Karte fragt nach Aufzeichnen und
/// Bildschirm, holt den Standort und startet.
class NavRequest {
  const NavRequest({required this.points, required this.title, this.startAlongM = 0});

  /// Die Linie in Fahrtrichtung, wie sie die Karte zeichnet.
  final List<LatLng> points;
  final String title;

  /// Wo der Stand anfängt — „zuletzt navigiert" geht dort weiter.
  final double startAlongM;
}

final navRequestProvider = StateProvider<NavRequest?>((ref) => null);

/// „Zuletzt navigiert" oben in „Meine Fahrten" (9.2): Beenden fragt
/// nicht, also ist aus Versehen beendet mit einem Tipp wieder an. Nur im
/// Speicher — eine Route beginnt oft an der Haustür, und was in den
/// Einstellungen läge, ginge mit in die Sicherung des Geräts.
final lastNavProvider = StateProvider<NavRequest?>((ref) => null);

/// „Zurück zur Route" (9.3): wo die Rechnung steht.
enum NavRejoin {
  none,
  computing,

  /// Das Stück liegt gestrichelt vor der Route.
  shown,

  /// Keine Kachel um Standort und Ziel — kein Bereich, kein Empfang.
  noArea,

  /// Kein Weg auf den Kacheln, die da sind.
  noPath,
}

/// Eine laufende Navigation.
class NavSession {
  const NavSession({
    required this.route,
    required this.title,
    this.state,
    this.climbDistM,
    this.climbEleM,
    this.north = false,
    this.rejoin = NavRejoin.none,
    this.rejoinLine,
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

  /// „Zurück zur Route": der Stand der Rechnung und das Stück vom Standort
  /// auf die Linie. Fällt weg, sobald man wieder drauf ist.
  final NavRejoin rejoin;
  final List<LatLng>? rejoinLine;

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
        rejoin: rejoin,
        rejoinLine: rejoinLine,
      );

  /// Ein neuer Stand von „Zurück zur Route" — das Stück nur bei [NavRejoin.shown].
  NavSession withRejoin(NavRejoin rejoin, [List<LatLng>? line]) => NavSession(
        route: route,
        title: title,
        state: state,
        climbDistM: climbDistM,
        climbEleM: climbEleM,
        north: north,
        rejoin: rejoin,
        rejoinLine: rejoin == NavRejoin.shown ? line : null,
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

  /// Startet die Navigation auf [points] ab [startAlongM]; false, wenn die
  /// Linie keine Länge hat. Eine laufende wird ersetzt.
  bool start(List<LatLng> points, String title, {double startAlongM = 0}) {
    final route = NavRoute.of(points);
    if (route == null) return false;
    _linger?.cancel();
    _tracker = NavTracker(route, startAlongM: startAlongM);
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
    // Wieder auf der Linie: Das Stück zurück und sein Satz fallen weg.
    final back = !next.offRoute && session.rejoin != NavRejoin.none;
    state = (back ? session.withRejoin(NavRejoin.none) : session).copyWith(state: next);
    if (next.arrived && !wasArrived) {
      _linger = Timer(kNavArrivedLinger, stop);
    }
  }

  /// „Zurück zur Route" (9.3, Betreiber 2026-10-08: ein Knopf, kein
  /// automatisches Neurechnen): ein A* vom Standort zum Punkt der Linie
  /// [kNavRejoinTargetM] voraus, über denselben Graphen und dasselbe
  /// Profil wie die Planung.
  Future<void> rejoin() async {
    final session = state;
    final now = session?.state;
    if (session == null || now == null || session.rejoin == NavRejoin.computing) return;
    final from = now.position;
    final target = session.route.pointAt(now.alongM + kNavRejoinTargetM);
    state = session.withRejoin(NavRejoin.computing);
    var result = NavRejoin.noPath;
    List<LatLng>? line;
    try {
      final profile = ref.read(riderProfileProvider);
      final prefs = LoopPrefs.parse(ref.read(settingsProvider).loopPlannerPrefs, profile);
      final loaded =
          await ref.read(planningGraphLoaderProvider)(LatBox.of([from, target]), fillOnline: prefs.fillOnline);
      final graph = loaded.graph;
      if (graph == null) {
        result = NavRejoin.noArea;
      } else {
        final rider = ref.read(calibratedRiderProvider(profile)).withPrefs(prefs.route);
        final plan = planTrailHeadRoute(graph, from, target, rider);
        if (plan.route != null) {
          result = NavRejoin.shown;
          line = plan.route!.points;
        } else if (plan.outcome == TrailHeadOutcome.startOffNetwork) {
          // Der Standort liegt an keinem bekannten Weg: Das ist für den, der
          // dort steht, dasselbe wie kein Bereich.
          result = NavRejoin.noArea;
        }
      }
    } catch (e, s) {
      logError('Weg zurück zur Route', e, s);
    }
    // Inzwischen beendet, ersetzt oder wieder auf der Linie: nichts tun.
    final after = state;
    if (after == null || !identical(after.route, session.route) || after.rejoin != NavRejoin.computing) return;
    state = after.withRejoin(result, line);
  }

  void toggleNorth() {
    final session = state;
    if (session != null) state = session.copyWith(north: !session.north);
  }

  /// Beenden fragt nicht (9.2). Eine Aufzeichnung läuft weiter; die
  /// Route bleibt als „zuletzt navigiert" — nach der Ankunft wieder ab
  /// Start, sonst ab dem letzten Stand.
  void stop() {
    final session = state;
    if (session != null) {
      final now = session.state;
      ref.read(lastNavProvider.notifier).state = NavRequest(
        points: session.route.points,
        title: session.title,
        startAlongM: now == null || now.arrived ? 0 : now.alongM,
      );
    }
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
