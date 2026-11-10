// „Route umplanen" und „Route verlassen" (#464, Konzept-Routing 9.3a):
// wohin das neue Stück führt (nächster Trailkopf voraus, sonst das Ziel,
// dann 1 km voraus), wie die neue Route zusammengesetzt wird (Trails
// rücken mit), dass Umkehren teuer, aber möglich ist — und im Controller,
// dass der Knopf ab der Schwelle steht, die neue Route die alte ersetzt
// und die Navigation weit daneben von selbst endet, erst nachdem man auf
// der Route war.
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/geo.dart' as geo;
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge.dart' show GarminBridge, garminBridgeProvider;
import 'package:trailbuddy/features/garmin/watch_providers.dart' show watchSyncProvider;
import 'package:trailbuddy/features/garmin/watch_route.dart' show kWatchProtocol;
import 'package:trailbuddy/features/keep_alive/keep_alive.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';
import 'package:trailbuddy/features/rides/road_index.dart' show RoadCoverage;
import 'package:trailbuddy/features/routing/graph_input.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner.dart';
import 'package:trailbuddy/features/routing/nav_providers.dart';
import 'package:trailbuddy/features/routing/nav_replan.dart';
import 'package:trailbuddy/features/routing/nav_service.dart';
import 'package:trailbuddy/features/routing/planning_graph.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_progress.dart';

import '../fakes/fake_garmin.dart';
import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';
import '../fakes/graph_tiles.dart';

const _lat0 = 47.5, _lon0 = 11.5;
final _proj = FlatProjection(_lat0);
final _o = _proj.xy(const LatLng(_lat0, _lon0));

LatLng _m(double x, double y) => _proj.latLng(math.Point(_o.x + x, _o.y + y));

WayLine _way(List<(double, double)> xy) =>
    WayLine(cls: WayClass.forstweg, oneway: false, points: [for (final (x, y) in xy) _m(x, y)]);

double _dist(LatLng a, LatLng b) => geo.distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude);

const _trail = NavTrailSection(startM: 3000, endM: 4000, trailId: 't', name: 'Talweg', grade: 2);

//! Eine Standmeldung der Uhr (#500): ihr Stand in 1e-5-Grad und der Abstand
//! zur Linie, wie `NavTracker.driftM` sie schickt.
Map<String, Object> _drift(double x, double y, double off) => {
  't': 'd',
  'la': (_m(x, y).latitude * 1e5).round(),
  'lo': (_m(x, y).longitude * 1e5).round(),
  'off': off,
};

//! Das „hallo“ der Uhr-App, wie sie es beim Start sendet.
Map<String, Object> _hello(String ver) => {'t': 'hi', 'v': kWatchProtocol, 'ver': ver};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('wohin das neue Stück führt', () {
    final route = NavRoute.of([_m(0, 0), _m(0, 6000)])!;

    test('zum nächsten Trailkopf voraus, dann 1 km voraus', () {
      final t = replanTargetsOf(route, NavSections([_trail]), 500);
      expect(t, hasLength(2));
      expect(t[0], 3000);
      expect(t[1], closeTo(1500, 1e-9));
    });

    test('ohne Trail voraus zum Ziel; der Trail dahinter zählt nicht', () {
      expect(replanTargetsOf(route, NavSections([_trail]), 3500).first, route.lengthM);
      expect(replanTargetsOf(route, const NavSections.empty(), 0).first, route.lengthM);
    });

    test('nie hinter den Kopf: liegt er näher als 1 km, gibt es keinen zweiten Versuch', () {
      expect(replanTargetsOf(route, NavSections([_trail]), 2500), [3000]);
    });
  });

  test('die neue Route: das Stück, dann der Rest ab dem Kopf — die Trails rücken mit', () {
    final route = NavRoute.of([_m(0, 0), _m(0, 6000)])!;
    const second = NavTrailSection(
        startM: 5000,
        endM: 5500,
        trailId: 'u',
        name: 'Ufer',
        approachWays: [(cls: WayClass.forstweg, lengthM: 1000)]);
    final earlier = const NavTrailSection(startM: 200, endM: 400, trailId: 'e', name: 'Erster');
    final sections = NavSections([earlier, _trail.shifted(0), second]);
    // 400 m östlich, dann nach Norden zum Kopf bei 3000 m: 400 + 2000 m.
    final line = [_m(400, 1000), _m(400, 3000), _m(0, 3000)];
    final next = spliceReplan(route, sections, line, 3000);
    final newRoute = NavRoute.of(next.points)!;
    expect(next.points.first, _m(400, 1000));
    expect(newRoute.lengthM, closeTo(2400 + 3000, 1));
    // Der Kopf steht einmal, nicht doppelt.
    expect(next.points.where((p) => _dist(p, _m(0, 3000)) < 0.01), hasLength(1));
    expect([for (final t in next.sections.trails) t.trailId], ['t', 'u'], reason: 'der Trail dahinter fällt weg');
    expect(next.sections.trails[0].startM, closeTo(2400, 1));
    expect(next.sections.trails[0].endM, closeTo(3400, 1));
    expect(next.sections.trails[1].startM, closeTo(4400, 1));
    expect(next.sections.trails[1].approachWays, hasLength(1), reason: 'die Anfahrt zum zweiten Trail blieb');
    expect(next.sections.trails[0].approachWays, isEmpty, reason: 'die Anfahrt zum ersten ist das neue Stück');
  });

  group('Umkehren ist teuer, aber möglich', () {
    // Ein Weg west–ost; der Standort bei (0, 0) mit Kurs Osten, das Ziel
    // 300 m westlich, also hinter einem. Nach vorn eine Schleife zurück.
    RoadGraph graph({required double loopY, required double loopX}) => buildRoadGraph([
          _way([(-1000, 0), (-300, 0)]),
          _way([(-300, 0), (loopX, 0)]),
          _way([(loopX, 0), (1000, 0)]),
          _way([(loopX, 0), (loopX, loopY), (-300, loopY), (-300, 0)]),
        ], lat0: _lat0).graph;

    test('die lange Schleife nach vorn verliert: umkehren', () {
      final g = graph(loopX: 500, loopY: 300);
      final plan = planReplanRoute(g, _m(0, 0), 90, _m(-300, 0), RiderProfile.bio);
      expect(plan.outcome, ReplanOutcome.ok);
      expect(plan.turnedBack, isTrue);
      expect(NavRoute.of(plan.points!)!.lengthM, closeTo(300, 5));
    });

    test('ist die Schleife nur wenig länger, geht es in Fahrtrichtung weiter', () {
      final g = graph(loopX: 100, loopY: 50);
      final plan = planReplanRoute(g, _m(0, 0), 90, _m(-300, 0), RiderProfile.bio);
      expect(plan.turnedBack, isFalse);
      expect(NavRoute.of(plan.points!)!.lengthM, closeTo(100 + 50 + 400 + 50, 5));
      expect(plan.points!.any((p) => p.longitude > _m(50, 0).longitude), isTrue, reason: 'erst nach Osten');
    });

    test('ohne Kurs gibt es kein „zurück": der kürzeste Weg', () {
      final g = graph(loopX: 100, loopY: 50);
      final plan = planReplanRoute(g, _m(0, 0), null, _m(-300, 0), RiderProfile.bio);
      expect(NavRoute.of(plan.points!)!.lengthM, closeTo(300, 5));
    });

    test('der Standort an keinem Weg', () {
      final g = graph(loopX: 100, loopY: 50);
      expect(planReplanRoute(g, _m(0, 500), 90, _m(-300, 0), RiderProfile.bio).outcome,
          ReplanOutcome.startOffNetwork);
    });
  });

  group('im Controller', () {
    late FakeSettings settings;
    late List<Object> jobs;

    // Die Route nach Norden auf x = 0, ein Trail ab 1500 m; ein Weg
    // parallel auf x = 300, verbunden bei 0 und 1500 m.
    ProviderContainer container({PlanningGraph? graph, GarminBridge? bridge}) {
      jobs = [];
      final input = GraphInput(
        roads: roadTilesOf([
          _way([(0, 0), (0, 1500), (0, 2500)]),
          _way([(300, 0), (300, 1500), (300, 2500)]),
          _way([(0, 0), (300, 0)]),
          _way([(300, 1500), (0, 1500)]),
        ]),
        lat0: _lat0,
      );
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWithValue(settings),
        navServiceBridgeProvider.overrideWithValue(FakeNavServiceBridge()),
        keepAliveProvider.overrideWithValue(FakeKeepAlive()),
        areaStoreProvider.overrideWithValue(MemoryAreaStore()),
        tileStoreProvider.overrideWithValue(MemoryTileStore()),
        connectivityProvider.overrideWith((ref) => Stream.value(const [ConnectivityResult.none])),
        loopPlanRunnerFactoryProvider.overrideWithValue(() => _JobSpy(jobs)),
        planningGraphLoaderProvider.overrideWithValue((box, {fillOnline = true}) async =>
            graph ?? PlanningGraph(input: input, coverage: RoadCoverage.complete, tilesFound: 1, tilesNeeded: 1)),
        if (bridge != null) garminBridgeProvider.overrideWithValue(bridge),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    setUp(() => settings = FakeSettings());

    final route = [_m(0, 0), _m(0, 1500), _m(0, 2500)];
    final sections = NavSections([
      const NavTrailSection(startM: 1500, endM: 2500, trailId: 't', name: 'Talweg', grade: 2),
    ]);

    test('ab 100 m steht der Knopf; die neue Route führt zum Kopf und ersetzt die alte', () async {
      final c = container();
      final nav = c.read(navigationProvider.notifier);
      nav.start(route, 'Hausrunde', sections: sections);
      nav.onFix(_m(0, 100), headingDeg: 0, speedMps: 5);
      // 60 m daneben: abseits, aber noch kein Umplanen.
      nav.onFix(_m(60, 300), headingDeg: 0, speedMps: 5);
      nav.onFix(_m(60, 320), headingDeg: 0, speedMps: 5);
      expect(c.read(navigationProvider)!.state!.offRoute, isTrue);
      expect(c.read(navigationProvider)!.replanOffer, isFalse);
      // Auf dem Weg daneben, nach Norden.
      nav.onFix(_m(300, 700), headingDeg: 0, speedMps: 5);
      expect(c.read(navigationProvider)!.replanOffer, isTrue);
      // Zurück unter die Schwelle: Der Knopf bleibt, bis man auf der Linie ist.
      nav.onFix(_m(80, 720), headingDeg: 0, speedMps: 5);
      expect(c.read(navigationProvider)!.replanOffer, isTrue);
      nav.onFix(_m(300, 800), headingDeg: 0, speedMps: 5);

      final old = c.read(navigationProvider)!.route;
      await nav.replan();
      final session = c.read(navigationProvider)!;
      expect(session.route, isNot(same(old)));
      expect(session.title, 'Hausrunde');
      expect(session.route.points.first, _m(300, 800));
      // 700 m nach Norden, 300 m nach Westen, dann der Trail.
      expect(session.route.lengthM, closeTo(1000 + 1000, 2));
      expect(session.sections.trails.single.startM, closeTo(1000, 2));
      expect(session.replan, NavReplan.none);
      expect(session.replanOffer, isFalse);
      expect(session.state!.offRoute, isFalse, reason: 'man steht am Anfang der neuen Linie');
      final job = jobs.single as ReplanJob;
      expect(job.courseDeg, 0, reason: 'der GPS-Kurs geht mit');
      expect(_dist(job.target, _m(0, 1500)), lessThan(1), reason: 'der Kopf des nächsten Trails');

      // „Zuletzt navigiert" nimmt die neue Route.
      nav.stop();
      expect(c.read(lastNavProvider)!.points.first, _m(300, 800));
    });

    test('die Schwelle kommt aus den Einstellungen', () async {
      settings.navReplanOfferM = 500;
      final c = container();
      final nav = c.read(navigationProvider.notifier);
      nav.start(route, 'Test', sections: sections);
      nav.onFix(_m(0, 100));
      nav.onFix(_m(300, 700));
      nav.onFix(_m(300, 800));
      expect(c.read(navigationProvider)!.state!.offRoute, isTrue);
      expect(c.read(navigationProvider)!.replanOffer, isFalse);
    });

    test('ohne Kacheln: ein Satz, die alte Route bleibt', () async {
      final c = container(graph: PlanningGraph.none);
      final nav = c.read(navigationProvider.notifier);
      nav.start(route, 'Test', sections: sections);
      final old = c.read(navigationProvider)!.route;
      nav.onFix(_m(0, 100));
      nav.onFix(_m(300, 700));
      nav.onFix(_m(300, 800));
      await nav.replan();
      expect(c.read(navigationProvider)!.replan, NavReplan.noArea);
      expect(c.read(navigationProvider)!.route, same(old));
      // Wieder auf der Linie: Der Satz fällt weg.
      nav.onFix(_m(0, 900));
      expect(c.read(navigationProvider)!.replan, NavReplan.none);
    });

    test('weit daneben endet die Navigation — erst, nachdem man auf der Route war', () async {
      final c = container();
      final nav = c.read(navigationProvider.notifier);
      nav.start(route, 'Test', sections: sections);
      // Der Start liegt 700 m neben der Route: Man fährt erst hin.
      nav.onFix(_m(700, 0));
      nav.onFix(_m(700, 10));
      nav.onFix(_m(700, 20));
      expect(c.read(navigationProvider), isNotNull);
      nav.onFix(_m(0, 100));
      // Ein Ausreißer zählt nicht.
      nav.onFix(_m(700, 200));
      expect(c.read(navigationProvider), isNotNull);
      nav.onFix(_m(0, 220));
      nav.onFix(_m(700, 300));
      nav.onFix(_m(700, 320));
      expect(c.read(navigationProvider), isNull);
      expect(c.read(navLeftProvider), closeTo(700, 5));
      expect(c.read(lastNavProvider), isNotNull, reason: '„Weiter navigieren" holt sie zurück');
    });

    test('„nie": die Navigation bleibt', () async {
      settings.navLeaveM = 0;
      final c = container();
      final nav = c.read(navigationProvider.notifier);
      nav.start(route, 'Test', sections: sections);
      nav.onFix(_m(0, 100));
      for (var i = 0; i < 5; i++) {
        nav.onFix(_m(5000, 300.0 + i));
      }
      expect(c.read(navigationProvider), isNotNull);
      expect(c.read(navLeftProvider), isNull);
    });

    // #501 (Konzept 2, was der Alarm auslöst): Die Uhr meldet ihren Stand,
    // das Handy rechnet die Linie ab ihr um — erst die Uhr-App ab 1.3.0, die
    // vorher fragt, ob sie die neue Linie nimmt.
    test('die Uhr meldet ihren Stand, das Handy rechnet ab ihr um', () async {
      final watch = FakeGarminBridge.connected()..autoStore = true;
      final c = container(bridge: watch);
      c.read(watchSyncProvider.notifier).follow(true);
      final nav = c.read(navigationProvider.notifier);
      nav.start(route, 'Hausrunde', sections: sections);
      nav.onFix(_m(0, 100), headingDeg: 0, speedMps: 5);
      await Future<void>.delayed(Duration.zero);
      final old = c.read(navigationProvider)!.route;
      final la = (_m(300, 700).latitude * 1e5).round(), lo = (_m(300, 700).longitude * 1e5).round();
      final at = LatLng(la / 1e5, lo / 1e5);
      // Eine alte Uhr-App kennt die Frage nicht: sie bleibt in Ruhe.
      watch.answer(const {'t': 'hi', 'v': kWatchProtocol, 'ver': '1.2.0'});
      watch.answer({'t': 'd', 'la': la, 'lo': lo, 'off': 300});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(navigationProvider)!.route, same(old));
      // Ab 1.3.0: 300 m daneben, über der Schwelle von 100 m.
      watch.answer(const {'t': 'hi', 'v': kWatchProtocol, 'ver': '1.3.0-dev'});
      watch.answer({'t': 'd', 'la': la, 'lo': lo, 'off': 60});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(navigationProvider)!.route, same(old), reason: 'unter der Schwelle bleibt die Linie');
      watch.answer({'t': 'd', 'la': la, 'lo': lo, 'off': 300});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final next = c.read(navigationProvider)!.route;
      expect(next, isNot(same(old)));
      expect(next.points.first, at, reason: 'die neue Linie beginnt am Stand der Uhr');
      expect(next.lengthM, closeTo(2100, 2), reason: '1100 m hin, dann der Trail');
    });

    // #501 (Konzept 2): Was die Standmeldung der Uhr auslöst — und was nicht.
    test('501.6 meldet sich die Uhr nicht vorher, bleibt die Linie', () async {
      final watch = FakeGarminBridge.connected()..autoStore = true;
      final c = container(bridge: watch);
      c.read(watchSyncProvider.notifier).follow(true);
      final nav = c.read(navigationProvider.notifier);
      nav.start(route, 'Hausrunde', sections: sections);
      nav.onFix(_m(0, 100), headingDeg: 0, speedMps: 5);
      await Future<void>.delayed(Duration.zero);
      final old = c.read(navigationProvider)!.route;
      watch.answer(_drift(300, 700, 300));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(navigationProvider)!.route, same(old),
          reason: 'ohne hallo kennt das Handy die Fassung der Uhr-App nicht');
    });

    test('501.7 endet die Navigation, folgt aus der Meldung nichts', () async {
      final watch = FakeGarminBridge.connected()..autoStore = true;
      final c = container(bridge: watch);
      c.read(watchSyncProvider.notifier).follow(true);
      final nav = c.read(navigationProvider.notifier);
      nav.start(route, 'Hausrunde', sections: sections);
      nav.onFix(_m(0, 100), headingDeg: 0, speedMps: 5);
      watch.answer(_hello('1.3.0-dev'));
      await Future<void>.delayed(Duration.zero);
      nav.stop();
      watch.answer(_drift(300, 700, 300));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(navigationProvider), isNull,
          reason: 'ohne laufende Navigation rechnet niemand um');
    });

    test('501.8 Schalter aus: die Meldung der Uhr bleibt folgenlos', () async {
      final watch = FakeGarminBridge.connected()..autoStore = true;
      final c = container(bridge: watch);
      c.read(watchSyncProvider.notifier).follow(false);
      final nav = c.read(navigationProvider.notifier);
      nav.start(route, 'Hausrunde', sections: sections);
      nav.onFix(_m(0, 100), headingDeg: 0, speedMps: 5);
      await Future<void>.delayed(Duration.zero);
      final old = c.read(navigationProvider)!.route;
      watch.answer(_hello('1.3.0-dev'));
      watch.answer(_drift(300, 700, 300));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(navigationProvider)!.route, same(old), reason: 'der Schalter steht auf aus');
      expect(watch.sent, isEmpty, reason: 'auch die Linie geht nicht hin');
    });

    test('501.9 zwei Meldungen zugleich, eine neue Linie', () async {
      final watch = FakeGarminBridge.connected()..autoStore = true;
      final c = container(bridge: watch);
      c.read(watchSyncProvider.notifier).follow(true);
      final nav = c.read(navigationProvider.notifier);
      nav.start(route, 'Hausrunde', sections: sections);
      nav.onFix(_m(0, 100), headingDeg: 0, speedMps: 5);
      watch.answer(_hello('1.3.0-dev'));
      await Future<void>.delayed(Duration.zero);
      int heads() {
        var n = 0;
        for (final msgs in watch.sent) {
          for (final m in msgs) {
            if (m['t'] == 'r' && m['p'] == 0) n++;
          }
        }
        return n;
      }
      final before = heads();
      watch.answer(_drift(300, 700, 300));
      watch.answer(_drift(320, 720, 320));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(heads() - before, 1, reason: 'während das Handy rechnet, löst die zweite nichts an');
    });
  });

  test('der Stand verlässt die Route erst nach zwei Fixen und erst nach dem Ankommen', () {
    NavState s(double off) => NavState(
        alongM: 0,
        remainingM: 0,
        offM: off,
        offRoute: off > kNavOffRouteM,
        arrived: false,
        headingDeg: 0,
        position: _m(0, 0),
        rejoin: _m(0, 0));
    final w = NavLeaveWatch(500);
    expect(w.update(s(900)), isFalse);
    expect(w.update(s(900)), isFalse, reason: 'noch nie auf der Route');
    expect(w.update(s(10)), isFalse);
    expect(w.update(s(600)), isFalse);
    expect(w.update(s(600)), isTrue);
    expect(NavLeaveWatch(0).update(s(10)), isFalse);
  });
}

/// Rechnet an Ort und Stelle und merkt sich jede Aufgabe.
class _JobSpy extends InlineLoopPlanRunner {
  _JobSpy(this.jobs);

  final List<Object> jobs;

  @override
  Future<R> run<R>(GraphJob<R> job) {
    jobs.add(job);
    return super.run(job);
  }
}
