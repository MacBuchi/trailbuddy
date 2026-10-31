// Der Zustand der Navigation (#232, Konzept-Routing 9): welche Linie,
// wo man auf ihr ist, ob die Karte dreht. Die Folgeansicht und die Karte
// lesen dieselbe Wahrheit; gerechnet wird in `route_progress.dart`.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../core/settings.dart';
import '../../core/stall_watch.dart';
import '../../models/trail.dart';
import '../profile/profile_providers.dart';
import '../trails/trail_providers.dart' show trailsProvider;
import '../trails/terrain_heights.dart';
import 'loop_plan_runner.dart';
import 'loop_planner.dart' show LoopPrefs;
import 'nav_notice.dart' show NavRouteData;
import 'nav_service.dart';
import 'planning_graph.dart';
import 'ride_calibrator.dart';
import 'route_profile.dart' show RiderParamsPrefs, RiderProfile, RoutePrefs;
import 'route_progress.dart';
import 'trail_head_route.dart';

export 'route_progress.dart' show kNavArrivedLinger, kNavTrailDoneLinger;

/// Was navigiert werden soll — gestellt von einem Ergebnis-Blatt oder aus
/// „Meine Fahrten", eingelöst von der Karte (Muster
/// `trailHeadRequestProvider`): Die Karte fragt nach Aufzeichnen und
/// Bildschirm, holt den Standort und startet.
class NavRequest {
  const NavRequest(
      {required this.points,
      required this.title,
      this.startAlongM = 0,
      this.sections,
      this.fromPlanner = false,
      this.profile,
      this.routePrefs});

  /// Die Linie in Fahrtrichtung, wie sie die Karte zeichnet.
  final List<LatLng> points;
  final String title;

  /// Wo der Stand anfängt — „zuletzt navigiert" geht dort weiter.
  final double startAlongM;

  /// Die Trails auf der Linie (9.9). Null heißt: die Karte leitet sie aus
  /// dem Netz ab (eine Fahrt kennt ihre Trails nicht).
  final NavSections? sections;

  /// Aus einem Ergebnis des Planers: Nach dem Ende der Navigation steht
  /// es wieder da (Konzept-Routing 10.5); aus „Meine Fahrten" oder
  /// „zuletzt navigiert" die normale Karte.
  final bool fromPlanner;

  /// Rad und Stil, mit denen die Route gerechnet wurde (#356 PR 9,
  /// Konzept-Routing 10.6): „Zurück zur Route" rechnet damit. Null (eine
  /// Fahrt aus „Meine Fahrten", die Wiederaufnahme nach einem Neustart):
  /// das aktuelle Profil und die gemerkten Vorlieben.
  final RiderProfile? profile;
  final RoutePrefs? routePrefs;
}

final navRequestProvider = StateProvider<NavRequest?>((ref) => null);

/// Ein Trail des Netzes nach Kennung, aus dem geladenen Stand — für die
/// Abschnitte (9.9: Charakter, Zustand, Hinweis). Null, wenn er nicht
/// (mehr) im Netz liegt; dann gelten die Werte des Planers.
Trail? Function(String id) trailByIdOf(WidgetRef ref) {
  final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
  return (id) => trails.where((t) => t.id == id).firstOrNull;
}

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
    this.sections = const NavSections.empty(),
    this.state,
    this.climbDistM,
    this.climbEleM,
    this.north = false,
    this.rejoin = NavRejoin.none,
    this.rejoinLine,
    this.trailDone,
    this.profile,
    this.routePrefs,
  });

  final NavRoute route;
  final String title;

  /// Rad und Stil der Route (`NavRequest`), für „Zurück zur Route".
  final RiderProfile? profile;
  final RoutePrefs? routePrefs;

  /// Die Trails auf der Linie (9.9).
  final NavSections sections;

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

  /// Die Bilanz des Trails, der gerade zu Ende gefahren ist (9.9) — das
  /// Blatt „Trail geschafft" steht, solange sie da ist.
  final NavTrailDone? trailDone;

  double get remainingM => state?.remainingM ?? route.lengthM;
  double? get remainingClimbM => climbAfter(climbDistM, climbEleM, state?.alongM ?? 0);

  /// Wohin oben zeigt.
  double get bearingDeg => north ? 0 : (state?.headingDeg ?? route.bearingAt(0));

  /// Der Abschnitt, in dem man ist (9.9) — vor dem ersten Fix die Anfahrt
  /// ab Start.
  NavPhase get phase => navPhaseOf(
        state ??
            NavState(
              alongM: 0,
              remainingM: route.lengthM,
              offM: 0,
              offRoute: false,
              arrived: false,
              headingDeg: 0,
              position: route.points.first,
              rejoin: route.points.first,
            ),
        sections,
        routeLengthM: route.lengthM,
        climbDistM: climbDistM,
        climbEleM: climbEleM,
      );

  NavSession copyWith({NavState? state, List<double>? climbDistM, List<double>? climbEleM, bool? north}) =>
      NavSession(
        route: route,
        title: title,
        sections: sections,
        state: state ?? this.state,
        climbDistM: climbDistM ?? this.climbDistM,
        climbEleM: climbEleM ?? this.climbEleM,
        north: north ?? this.north,
        rejoin: rejoin,
        rejoinLine: rejoinLine,
        trailDone: trailDone,
        profile: profile,
        routePrefs: routePrefs,
      );

  /// Ein neuer Stand von „Zurück zur Route" — das Stück nur bei [NavRejoin.shown].
  NavSession withRejoin(NavRejoin rejoin, [List<LatLng>? line]) => NavSession(
        route: route,
        title: title,
        sections: sections,
        state: state,
        climbDistM: climbDistM,
        climbEleM: climbEleM,
        north: north,
        rejoin: rejoin,
        rejoinLine: rejoin == NavRejoin.shown ? line : null,
        trailDone: trailDone,
        profile: profile,
        routePrefs: routePrefs,
      );

  /// Mit oder ohne Bilanz am Trail-Ende.
  NavSession withTrailDone(NavTrailDone? done) => NavSession(
        route: route,
        title: title,
        sections: sections,
        state: state,
        climbDistM: climbDistM,
        climbEleM: climbEleM,
        north: north,
        rejoin: rejoin,
        rejoinLine: rejoinLine,
        trailDone: done,
        profile: profile,
        routePrefs: routePrefs,
      );
}

class NavController extends Notifier<NavSession?> {
  NavTracker? _tracker;
  NavTrailWatch? _trails;
  Timer? _linger;
  Timer? _doneLinger;
  double _startAlongM = 0;

  /// Der Rechen-Isolate für „Zurück zur Route" (#356 PR 9) und der Rahmen
  /// des Graphen, den er hält: Ein zweiter Tipp im selben Rahmen baut
  /// nicht neu. Weg mit dem Ende der Navigation.
  LoopPlanRunner? _rejoinRunner;
  LatBox? _rejoinBox;

  /// Dienst und Brücke (9.5) in einer Kette: Beenden und sofort wieder
  /// Starten („zuletzt navigiert") löschte sonst die frische Datei.
  Future<void> _service = Future.value();

  void _queue(Future<void> Function() job) {
    _service = _service.then((_) => job()).catchError((Object e, StackTrace s) {
      logError('Navigation: Dienst', e, s);
    });
  }

  @override
  NavSession? build() {
    ref.onDispose(() {
      _linger?.cancel();
      _doneLinger?.cancel();
      _dropRejoinGraph();
    });
    return null;
  }

  bool get isRunning => state != null;

  /// Startet die Navigation auf [points] ab [startAlongM]; false, wenn die
  /// Linie keine Länge hat. Eine laufende wird ersetzt.
  bool start(List<LatLng> points, String title,
      {double startAlongM = 0, NavSections? sections, RiderProfile? profile, RoutePrefs? routePrefs}) {
    final route = NavRoute.of(points);
    if (route == null) return false;
    _linger?.cancel();
    _doneLinger?.cancel();
    _dropRejoinGraph();
    _tracker = NavTracker(route, startAlongM: startAlongM);
    _trails = NavTrailWatch();
    _startAlongM = startAlongM;
    final session = NavSession(
        route: route,
        title: title,
        sections: sections ?? const NavSections.empty(),
        profile: profile,
        routePrefs: routePrefs);
    state = session;
    final bridge = ref.read(navServiceBridgeProvider);
    final keepAlive = ref.read(navKeepAliveProvider);
    _queue(() async {
      await bridge.arm(NavRouteData(
          points: route.points, title: title, startAlongM: startAlongM, sections: session.sections));
      await keepAlive.start();
    });
    unawaited(_loadClimb(session));
    return true;
  }

  Future<void> _loadClimb(NavSession session) async {
    try {
      final profile = await ref.read(terrainHeightsProvider).profile(session.route.points);
      // Inzwischen beendet oder eine andere Navigation: nichts mehr tun.
      if (profile == null || !identical(state?.route, session.route)) return;
      state = state!.copyWith(climbDistM: profile.distM, climbEleM: profile.eleM);
      // Der Dienst rechnet die Höhenmeter für die Benachrichtigung selbst;
      // dieselbe Linie behält dort ihren Stand.
      final bridge = ref.read(navServiceBridgeProvider);
      _queue(() => bridge.arm(NavRouteData(
          points: session.route.points,
          title: session.title,
          startAlongM: _startAlongM,
          sections: session.sections,
          climbDistM: profile.distM,
          climbEleM: profile.eleM)));
    } catch (_) {
      // Ohne Höhen zeigt die Leiste nur km — das Lesen meldet seine
      // Fehler selbst (`TerrainHeights`).
    }
  }

  /// Ein Fix der eigenen Position. [headingDeg]/[speedMps] wie vom GPS,
  /// [at] seine Zeit (ohne: jetzt).
  void onFix(LatLng p, {double? headingDeg, double? speedMps, DateTime? at}) {
    final tracker = _tracker;
    final session = state;
    if (tracker == null || session == null) return;
    final wasArrived = session.state?.arrived ?? false;
    final next = tracker.update(p, headingDeg: headingDeg, speedMps: speedMps);
    // Wieder auf der Linie: Das Stück zurück und sein Satz fallen weg.
    final back = !next.offRoute && session.rejoin != NavRejoin.none;
    var updated = (back ? session.withRejoin(NavRejoin.none) : session).copyWith(state: next);
    final done = _trails?.update(next, session.sections, at ?? DateTime.now(),
        speedMps: speedMps, climbDistM: session.climbDistM, climbEleM: session.climbEleM);
    if (done != null) {
      updated = updated.withTrailDone(done);
      _doneLinger?.cancel();
      _doneLinger = Timer(kNavTrailDoneLinger, dismissTrailDone);
    }
    state = updated;
    if (next.arrived && !wasArrived) {
      // Angekommen, kurz wieder weg, wieder angekommen: nur EIN Timer —
      // der erste beendete sonst eine Navigation, die er nicht kennt.
      _linger?.cancel();
      _linger = Timer(kNavArrivedLinger, stop);
    }
  }

  /// „Zurück zur Route" (9.3, Betreiber 2026-10-08: ein Knopf, kein
  /// automatisches Neurechnen): ein A* vom Standort zum Punkt der Linie
  /// [kNavRejoinTargetM] voraus — im Rechen-Isolate, auf einem Graphen aus
  /// denselben Bytes wie der Planer, mit Rad und Stil der Route (#356
  /// PR 9; ohne: aktuelles Profil, gemerkte Vorlieben). Das Profil ist
  /// das kalibrierte von jetzt, nicht das vom Planen.
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
      final RiderProfile profile = session.profile ?? ref.read(riderProfileProvider);
      final prefs = LoopPrefs.parse(ref.read(settingsProvider).loopPlannerPrefs, profile);
      final rider = ref.read(calibratedRiderProvider(profile)).withPrefs(session.routePrefs ?? prefs.route);
      final need = LatBox.of([from, target]);
      final runner = _rejoinRunner ??= ref.read(loopPlanRunnerFactoryProvider)();
      var ready = runner.hasGraph && (_rejoinBox?.contains(need) ?? false);
      if (!ready) {
        // Mit Rand, damit der nächste Tipp ein Stück weiter denselben
        // Graphen nimmt; der Lader legt seinen eigenen noch dazu.
        final box = _grow(need, kNavRejoinGraphMarginM);
        final loaded = await ref.read(planningGraphLoaderProvider)(box, fillOnline: prefs.fillOnline);
        final input = loaded.input;
        if (input != null) {
          final report = await StallWatch.time('graph.build', () => runner.build(input));
          unawaited(loaded.keep(report)); // die neu gebackenen Stücke (#380)
          _rejoinBox = box;
          ready = true;
        }
      }
      if (!ready) {
        result = NavRejoin.noArea;
      } else {
        final plan = await StallWatch.time('nav.rejoin', () => runner.run(TrailHeadJob(from, target, rider)));
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
      // Ein Isolate, der weg ist, baut beim nächsten Tipp neu.
      _dropRejoinGraph();
    }
    // Inzwischen beendet, ersetzt oder wieder auf der Linie: nichts tun.
    final after = state;
    if (after == null || !identical(after.route, session.route) || after.rejoin != NavRejoin.computing) return;
    state = after.withRejoin(result, line);
  }

  void _dropRejoinGraph() {
    _rejoinRunner?.dispose();
    _rejoinRunner = null;
    _rejoinBox = null;
  }

  static LatBox _grow(LatBox b, double marginM) {
    final dLat = marginM / 111320.0;
    final dLon = dLat / math.cos((b.s + b.n) / 2 * math.pi / 180);
    return LatBox(b.s - dLat, b.w - dLon, b.n + dLat, b.e + dLon);
  }

  /// Seit wann der laufende Trail gefahren wird; null abseits (#36: ab
  /// hier zählen die Trail-Werte der Folgeansicht).
  DateTime? get trailSince => _trails?.enteredAt;

  /// „Weiter" im Blatt „Trail geschafft" — oder die 20 s sind um.
  void dismissTrailDone() {
    _doneLinger?.cancel();
    _doneLinger = null;
    final session = state;
    if (session?.trailDone != null) state = session!.withTrailDone(null);
  }

  void toggleNorth() {
    final session = state;
    if (session != null) state = session.copyWith(north: !session.north);
  }

  /// Beenden fragt nicht (9.2). Eine Aufzeichnung läuft weiter; die
  /// Route bleibt als „zuletzt navigiert" — nach der Ankunft wieder ab
  /// Start, sonst ab dem letzten Stand. Auch der Weg für „Navigation
  /// beenden" in der Benachrichtigung (Nachricht vom Dienst).
  void stop() {
    final session = state;
    if (session != null) {
      final bridge = ref.read(navServiceBridgeProvider);
      final keepAlive = ref.read(navKeepAliveProvider);
      _queue(() async {
        // Erst die Brücke aus, dann der Melder: Der Dienst soll keinen
        // Takt mehr auf eine Route rechnen, die es nicht mehr gibt.
        await bridge.disarm();
        await keepAlive.stop();
      });
      final now = session.state;
      ref.read(lastNavProvider.notifier).state = NavRequest(
        points: session.route.points,
        title: session.title,
        startAlongM: now == null || now.arrived ? 0 : now.alongM,
        sections: session.sections,
      );
    }
    _linger?.cancel();
    _linger = null;
    _doneLinger?.cancel();
    _doneLinger = null;
    _dropRejoinGraph();
    _tracker = null;
    _trails = null;
    state = null;
  }
}

/// Rand um Standort und Zielpunkt, in dem der Graph für „Zurück zur Route"
/// gelesen wird: 2 km, damit ein zweiter Tipp wenig später denselben
/// Graphen nimmt (eine Handvoll Kacheln statt einer je Tipp).
const kNavRejoinGraphMarginM = 2000.0;
final navigationProvider = NotifierProvider<NavController, NavSession?>(NavController.new);

/// Bildschirm an in der Folgeansicht (9.4), gemerkt auf dem Gerät.
final navKeepScreenOnProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.navKeepScreenOn,
    write: (s, v) => s.setNavKeepScreenOn(v),
    label: 'Bildschirm-Schalter der Navigation merken',
  ),
);
