// Die Trail-zuerst-Runde pur (#158 Schritt 5): ein kleines Wegenetz mit
// zwei Trails, Budgets, Pflicht, zweite Abfahrt, offenes Ende und die
// Gründe für alles, was nicht hineinpasst.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_result.dart' show kRouteDirectBudget;
import 'package:trailbuddy/features/routing/route_vias.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart' show haversineM;

/// Meter → Grad über DIESELBE Projektion wie der Graph.
List<LatLng> _m(List<(double, double)> xy, {double lat0 = 47.5, double lon0 = 11.5}) {
  final proj = FlatProjection(lat0);
  final o = proj.xy(LatLng(lat0, lon0));
  return [for (final (x, y) in xy) proj.latLng(math.Point(o.x + x, o.y + y))];
}

WayLine _way(List<(double, double)> xy, {WayClass cls = WayClass.forstweg}) =>
    WayLine(cls: cls, oneway: false, points: _m(xy));

/// Ein Quadrat aus Forstwegen, 1 km Kante: der Start unten links (0,0),
/// die „Gipfel" oben. Höhen von Hand: nach oben 100 hm Anstieg, nach
/// unten 100 hm Abstieg, waagerecht flach.
RoadGraph _square() {
  final g = buildRoadGraph([
    _way([(0, 0), (0, 1000)]),
    _way([(0, 1000), (1000, 1000)]),
    _way([(1000, 1000), (1000, 0)]),
    _way([(1000, 0), (0, 0)]),
  ], lat0: 47.5).graph;
  for (final e in g.edges) {
    final a = g.nodes[e.a], b = g.nodes[e.b];
    final dy = b.y - a.y;
    if (dy.abs() > 1) {
      e.gain = dy > 0 ? 100 : 0;
      e.loss = dy > 0 ? 0 : 100;
    }
    e.hasHeights = true;
  }
  return g;
}

/// Ein Trail von [from] nach [to], 10 m neben den Wegen angeschlossen.
PoolTrail _trail(String id, (double, double) from, (double, double) to,
        {int? grade = 2, int? rating, bool mandatory = false, double lossM = 100}) =>
    PoolTrail(
      id: id,
      name: id,
      points: _m([from, ((from.$1 + to.$1) / 2, (from.$2 + to.$2) / 2), to]),
      lengthM: 1000,
      grade: grade,
      rating: rating,
      lossM: lossM,
      mandatory: mandatory,
    );

const _bio = RiderProfile.bio;
const _big = LoopBudget(timeS: 3 * 3600, climbM: 800, hikingM: 2000);

void main() {
  // Trail A: von der oberen linken Ecke diagonal zur unteren rechten.
  // Trail B: von der oberen rechten Ecke hinunter zur unteren rechten.
  final a = _trail('A', (10, 990), (990, 10));
  final b = _trail('B', (1010, 990), (1010, 10));
  final start = _m([(5, 0)]).single;

  test('LoopPrefs: das Ende der Fahrt (#331) — alter Schalter gelesen, Ziel als r=2 geschrieben, als Runde gelesen',
      () {
    LoopEndMode read(String? raw) => LoopPrefs.parse(raw, RiderProfile.bio).endMode;
    expect(read(null), LoopEndMode.loop);
    expect(read('h=3.0;r=1'), LoopEndMode.loop);
    expect(read('h=3.0;r=0'), LoopEndMode.lastTrail);
    // #356: Das Ziel gilt nur für die Sitzung — ohne es aufzugehen hieße
    // „Kein Ziel gesetzt" vor der ersten Rechnung.
    expect(read('h=3.0;r=2'), LoopEndMode.loop);
    expect(read('h=3.0;r=x'), LoopEndMode.loop);
    for (final m in [LoopEndMode.loop, LoopEndMode.lastTrail]) {
      final prefs = LoopPrefs.defaults(RiderProfile.bio).copyWith(endMode: m);
      expect(read(prefs.encode()), m, reason: '$m hin und zurück');
    }
    expect(LoopPrefs.defaults(RiderProfile.bio).copyWith(endMode: LoopEndMode.target).encode(), contains('r=2'));
    expect(LoopPrefs.defaults(RiderProfile.bio).copyWith(endMode: LoopEndMode.lastTrail).encode(), contains('r=0'),
        reason: 'ältere Apps lesen „letzter Trail" weiter als 0');
  });

  test('LoopPrefs: der Stil der Route (#356) hin und zurück, ab Werk direkt', () {
    RouteMode read(String? raw) => LoopPrefs.parse(raw, RiderProfile.bio).style;
    expect(read(null), RouteMode.direct);
    expect(read('h=3.0;r=1'), RouteMode.direct, reason: 'vor 0.129.0 gemerkt');
    for (final m in RouteMode.values) {
      expect(read(LoopPrefs.defaults(RiderProfile.bio).copyWith(style: m).encode()), m);
    }
  });

  test('LoopPrefs: „Bergauf bequem" (#356 PR 7b) hin und zurück, ab Werk aus; planRoute je Ziel', () {
    final d = LoopPrefs.defaults(RiderProfile.bio);
    expect(d.easyUp, isFalse);
    expect(LoopPrefs.parse('h=3.0;r=1;y=e', RiderProfile.bio).easyUp, isFalse, reason: 'vor 0.131.0 gemerkt');
    expect(LoopPrefs.parse(d.copyWith(easyUp: true).encode(), RiderProfile.bio).easyUp, isTrue);
    expect(d.copyWith(easyUp: true).planRoute.easy, isTrue, reason: 'Runde');
    expect(d.copyWith(easyUp: true, endMode: LoopEndMode.lastTrail).planRoute.easy, isTrue);
    expect(d.copyWith(easyUp: true, endMode: LoopEndMode.target).planRoute.easy, isFalse,
        reason: 'zu einem Ziel entscheidet der Stil');
    expect(d.copyWith(endMode: LoopEndMode.target, style: RouteMode.easy).planRoute.easy, isTrue);
    expect(d.copyWith(style: RouteMode.easy).planRoute.easy, isFalse, reason: 'die Runde hat keinen Stil');
  });

  group('die Route ohne Trail (#356, bare)', () {
    // Von unten links nach oben rechts — zwei gleich lange Wege um das
    // Quadrat.
    final to = _m([(1000, 1000)]).single;

    test('ohne Trail ein Ergebnis: Linie vom Start zum Ziel, 2 km, ohne Halt', () {
      final plan = planLoop(_square(),
          start: start, profile: _bio, budget: _big, pool: const [], returnToStart: false, end: to, bare: true);
      expect(plan.outcome, LoopOutcome.ok);
      expect(plan.isEmpty, isTrue);
      expect(plan.summary!.lengthM, closeTo(2000, 2));
      expect(plan.summary!.trailM, 0);
      expect(haversineM(plan.points.first.latitude, plan.points.first.longitude, start.latitude, start.longitude), lessThan(1));
      expect(haversineM(plan.points.last.latitude, plan.points.last.longitude, to.latitude, to.longitude), lessThan(1));
    });

    test('ohne bare bleibt es „nichts zu fahren" — eine Runde braucht einen Trail', () {
      final plan = planLoop(_square(),
          start: start, profile: _bio, budget: _big, pool: const [], returnToStart: false, end: to);
      expect(plan.outcome, LoopOutcome.empty);
    });

    test('mit Zwischenpunkt und getunt (#234): durch den Punkt, auch ohne Trail', () {
      final via = _m([(1000, 0)]).single;
      final free = planLoop(_square(),
          start: start, profile: _bio, budget: _big, pool: const [], returnToStart: false, end: to, waypoints: [via], bare: true);
      expect(free.outcome, LoopOutcome.ok);
      expect(free.points.any((p) => haversineM(p.latitude, p.longitude, via.latitude, via.longitude) < 1), isTrue);
      final tuned = planLoop(_square(),
          start: start,
          profile: _bio,
          budget: _big,
          pool: const [],
          returnToStart: false,
          end: to,
          tune: LoopTune(order: const [], vias: RouteVias({0: [via]})),
          bare: true);
      expect(tuned.outcome, LoopOutcome.ok);
      expect(tuned.points.any((p) => haversineM(p.latitude, p.longitude, via.latitude, via.longitude) < 1), isTrue);
    });
  });

  test('beide Trails bergab, verbunden durch Aufstiege, zurück zum Start', () {
    final plan = planLoop(_square(), start: start, profile: _bio, budget: _big, pool: [a, b],
        searchBudget: const Duration(milliseconds: 50));
    expect(plan.outcome, LoopOutcome.ok);
    expect(plan.stops.map((s) => s.trail.id), unorderedEquals(['A', 'B']));
    final s = plan.summary!;
    expect(s.trailM, closeTo(2000, 0.5));
    expect(s.trailLossM, 200);
    expect(s.gainM, closeTo(200, 0.5), reason: 'zweimal 100 hm hinauf');
    expect(s.wastedLossM, 0, reason: 'bergab nur auf Trails');
    expect(s.hikingM, 0);
    expect(s.heightsComplete, isTrue);
    expect(s.timeS, greaterThan(0));
    // Linie: beginnt und endet am Start, trägt beide Trails.
    expect(plan.points.first, start);
    expect(plan.points.last, start);
    expect(plan.sections.where((x) => x.isTrail), hasLength(2));
    expect(plan.sections.where((x) => !x.isTrail && x.cls == WayClass.forstweg), isNotEmpty);
    expect(plan.excluded, isEmpty);
    expect(plan.sections.map((x) => x.lengthM).fold(0.0, (p, q) => p + q), closeTo(s.lengthM, 0.5));
  });

  test('knappes Zeitbudget: nur ein Trail, der andere mit Grund „Budget"', () {
    // Ein Trail: 1 km Aufstieg (~13 min + 100 hm ≈ 13 min) + Abfahrt +
    // Rückweg: knapp unter einer Stunde. Zwei passen nicht.
    final plan = planLoop(_square(), start: start, profile: _bio,
        budget: const LoopBudget(timeS: 55 * 60, climbM: 800, hikingM: 2000),
        pool: [a, b], searchBudget: const Duration(milliseconds: 50));
    expect(plan.outcome, LoopOutcome.ok);
    expect(plan.stops, hasLength(1));
    expect(plan.excluded.values.single, LoopExclusion.budget);
    expect(plan.summary!.timeS, lessThanOrEqualTo(55 * 60 * 0.9));
  });

  test('Höhenbudget und Wanderweg-Budget greifen', () {
    final climb = planLoop(_square(), start: start, profile: _bio,
        budget: const LoopBudget(timeS: 3 * 3600, climbM: 150, hikingM: 2000),
        pool: [a, b], searchBudget: const Duration(milliseconds: 50));
    expect(climb.stops, hasLength(1), reason: '200 hm für beide, 150 erlaubt');
    // Der Weg nach oben als Wanderweg: mit „kein Wanderweg" bleibt nur,
    // was ohne ihn erreichbar ist — hier nichts.
    final g = buildRoadGraph([
      _way([(0, 0), (0, 1000)], cls: WayClass.wanderweg),
      _way([(0, 1000), (1000, 1000)]),
      _way([(1000, 1000), (1000, 0)]),
      _way([(1000, 0), (0, 0)]),
    ], lat0: 47.5).graph;
    final hiking = planLoop(g, start: start, profile: _bio,
        budget: const LoopBudget(timeS: 3 * 3600, climbM: 800, hikingM: 0),
        pool: [a], searchBudget: const Duration(milliseconds: 50));
    // A beginnt oben links — der billigste Weg dorthin ist der Wanderweg;
    // ohne ihn geht es über drei Seiten des Quadrats (flach), und genau
    // die nimmt die Runde, statt A auszulassen.
    expect(hiking.stops, hasLength(1));
    expect(hiking.summary!.hikingM, 0);
    expect(hiking.summary!.mix[WayClass.wanderweg], isNull);
    expect(hiking.summary!.mix[WayClass.forstweg], closeTo(4000, 0.5), reason: '3 km hin, 1 km zurück');
    // Mit 2 km Wanderweg erlaubt nimmt sie ihn.
    final allowed = planLoop(g, start: start, profile: _bio,
        budget: const LoopBudget(timeS: 3 * 3600, climbM: 800, hikingM: 2000),
        pool: [a], searchBudget: const Duration(milliseconds: 50));
    expect(allowed.summary!.hikingM, closeTo(1000, 0.5));
  });

  test('Pflicht-Trail kommt hinein, auch wenn er je Minute weniger bringt', () {
    // C ist kurz und weit: 200 m an der rechten Seite, von der oberen Ecke
    // hinunter. Mit 40 Minuten nähme greedy nur A (1 km Trail für 28 min);
    // als Pflicht steht C zuerst, und A passt dann nicht mehr.
    final c = PoolTrail(
        id: 'C', name: 'C', points: _m([(1010, 990), (1010, 800)]), lengthM: 200, grade: 1, lossM: 20);
    final free = planLoop(_square(), start: start, profile: _bio,
        budget: const LoopBudget(timeS: 40 * 60, climbM: 800, hikingM: 2000),
        pool: [a, b, c], searchBudget: const Duration(milliseconds: 50));
    expect(free.stops.map((s) => s.trail.id), ['A']);
    final must = planLoop(_square(), start: start, profile: _bio,
        budget: const LoopBudget(timeS: 40 * 60, climbM: 800, hikingM: 2000),
        pool: [a, b, PoolTrail(id: 'C', name: 'C', points: c.points, lengthM: 200, grade: 1, lossM: 20, mandatory: true)],
        searchBudget: const Duration(milliseconds: 50));
    expect(must.stops.map((s) => s.trail.id), contains('C'));
    expect(must.stops.map((s) => s.trail.id), isNot(contains('A')));
    expect(must.excluded['A'], LoopExclusion.budget);
  });

  test('zweite Abfahrt nur mit 4 oder 5 Sternen', () {
    final plain = planLoop(_square(), start: start, profile: _bio, budget: _big,
        pool: [_trail('A', (10, 990), (990, 10), rating: 3)],
        searchBudget: const Duration(milliseconds: 50));
    expect(plain.stops, hasLength(1));
    final loved = planLoop(_square(), start: start, profile: _bio, budget: _big,
        pool: [_trail('A', (10, 990), (990, 10), rating: 5)],
        searchBudget: const Duration(milliseconds: 50));
    expect(loved.stops.map((s) => s.secondPass), [false, true]);
    expect(loved.summary!.trailM, closeTo(1300, 0.5), reason: '100 % + 30 %');
    expect(loved.sections.where((s) => s.isTrail).length, 2);
  });

  test('offenes Ende: die Runde endet am letzten Trail', () {
    final plan = planLoop(_square(), start: start, profile: _bio, budget: _big, pool: [a, b],
        returnToStart: false, searchBudget: const Duration(milliseconds: 50));
    expect(plan.stops, hasLength(2));
    expect(plan.points.last, isNot(start));
    expect(plan.summary!.gainM, closeTo(200, 0.5));
  });

  test('die Gründe: zu weit (vom Aufrufer), kein Weg, nicht erreichbar, Start ohne Weg', () {
    final far = _trail('F', (5000, 5000), (6000, 5000));
    final island = buildRoadGraph([
      _way([(0, 0), (0, 1000)]),
      _way([(3000, 0), (3000, 1000)]),
    ], lat0: 47.5).graph;
    final onIsland = _trail('I', (3010, 990), (3010, 10));
    final plan = planLoop(island, start: start, profile: _bio, budget: _big,
        pool: [far, onIsland, _trail('N', (10, 990), (10, 10))],
        excluded: {'F': LoopExclusion.tooFar}, searchBudget: const Duration(milliseconds: 50));
    expect(plan.excluded['F'], LoopExclusion.tooFar);
    expect(plan.excluded['I'], LoopExclusion.unreachable);
    expect(plan.stops.single.trail.id, 'N');

    final off = planLoop(_square(), start: start, profile: _bio, budget: _big,
        pool: [_trail('X', (10, 990), (500, 500))], searchBudget: const Duration(milliseconds: 50));
    expect(off.outcome, LoopOutcome.empty);
    expect(off.excluded['X'], LoopExclusion.offNetwork);

    final nowhere = planLoop(_square(), start: _m([(500, 500)]).single, profile: _bio, budget: _big,
        pool: [a], searchBudget: const Duration(milliseconds: 50));
    expect(nowhere.outcome, LoopOutcome.startOffNetwork);
  });

  group('gesetzte Punkte springen auf den nächsten Weg (#374)', () {
    LoopPlan plan({required LatLng from, LatLng? end, List<LatLng> waypoints = const []}) => planLoop(_square(),
        start: from,
        profile: _bio,
        budget: _big,
        pool: [a],
        returnToStart: end == null,
        end: end,
        waypoints: waypoints,
        searchBudget: const Duration(milliseconds: 50));
    double dist(LatLng p, LatLng q) => haversineM(p.latitude, p.longitude, q.latitude, q.longitude);

    test('ein Start 120 m neben dem Weg plant, die Linie beginnt am Weg', () {
      final r = plan(from: _m([(120, 500)]).single);
      expect(r.outcome, LoopOutcome.ok);
      final s = r.snaps.single;
      expect(s.role, SnapRole.start);
      expect(s.meters, closeTo(120, 1));
      expect(dist(s.at, _m([(0, 500)]).single), lessThan(1));
      expect(r.points.first, s.at);
      expect(r.points.last, s.at, reason: 'die Runde endet, wo sie beginnt');
    });

    test('in 30 m bleibt es still wie bisher', () {
      final r = plan(from: _m([(25, 500)]).single);
      expect(r.outcome, LoopOutcome.ok);
      expect(r.snaps, isEmpty);
    });

    test('über 200 m bleibt es beim Fehler', () {
      expect(kGraphSnapM, 200);
      expect(plan(from: _m([(250, 500)]).single).outcome, LoopOutcome.startOffNetwork);
    });

    test('Ziel und Zwischenpunkt springen auch, je mit ihrem Abstand', () {
      final r = plan(from: start, end: _m([(1150, 500)]).single, waypoints: [
        _m([(500, 900)]).single,
        _m([(500, 1080)]).single,
      ]);
      expect(r.outcome, LoopOutcome.ok);
      expect({for (final s in r.snaps) (s.role, s.index): s.meters.round()},
          {(SnapRole.end, 0): 150, (SnapRole.waypoint, 0): 100, (SnapRole.waypoint, 1): 80});
      expect(r.points.last, r.snaps.firstWhere((s) => s.role == SnapRole.end).at);
    });
  });

  group('Trail-Enden springen auf den nächsten Weg (#394)', () {
    // Trail A mit dem Kopf 120 m innen neben der oberen Kante, das Ende
    // wie bisher 10 m neben der unteren rechten Ecke.
    final inWood = _trail('W', (500, 880), (990, 10));

    test('ein Trailkopf 120 m im Wald fährt mit, und das Blatt erfährt es', () {
      final r = planLoop(_square(), start: start, profile: _bio, budget: _big, pool: [inWood],
          searchBudget: const Duration(milliseconds: 50));
      expect(r.outcome, LoopOutcome.ok);
      expect(r.stops.single.trail.id, 'W');
      final s = r.snaps.single;
      expect(s.role, SnapRole.trailStart);
      expect(s.trailId, 'W');
      expect(s.meters, closeTo(120, 1));
      expect(r.excluded, isEmpty);
    });

    test('ein Trail, der nicht mitfährt, bringt keinen Satz', () {
      // Angeheftet (gesprungen) wird W, ins Budget von 20 min passt er nicht.
      final r = planLoop(_square(), start: start, profile: _bio,
          budget: const LoopBudget(timeS: 1200, climbM: 800, hikingM: 2000), pool: [inWood],
          searchBudget: const Duration(milliseconds: 50));
      expect(r.excluded['W'], LoopExclusion.budget);
      expect(r.snaps, isEmpty);
    });

    test('beim Laden angeheftet, teilt die Planung keine Kante mehr (Suchspeicher bleibt gültig)', () {
      final g = _square();
      // Was `buildGraphFrom` mit jeder Abfahrt im Rahmen tut.
      g.snap(inWood.start);
      g.snap(inWood.end);
      final rev = g.revision;
      final r = planLoop(g, start: start, profile: _bio, budget: _big, pool: [inWood],
          searchBudget: const Duration(milliseconds: 50));
      expect(r.stops, hasLength(1));
      expect(g.revision, rev);
    });
  });

  test('nur Zwischenpunkte, kein Trail, kein Ziel (#395): eine Runde durch die Punkte', () {
    final via = _m([(1000, 1000)]).single;
    final r = planLoop(_square(), start: start, profile: _bio, budget: kRouteDirectBudget, pool: const [],
        waypoints: [via], bare: true);
    expect(r.outcome, LoopOutcome.ok);
    expect(r.isEmpty, isTrue);
    expect(r.summary!.lengthM, closeTo(4000, 20), reason: 'einmal um das Quadrat');
    expect(r.points.any((p) => haversineM(p.latitude, p.longitude, via.latitude, via.longitude) < 1), isTrue);
    expect(r.points.last, r.points.first);
  });

  test('das Budget: 10 % Reserve auf die Zeit', () {
    expect(const LoopBudget(timeS: 3600, climbM: 1, hikingM: 1).plannedTimeS, closeTo(3240, 1e-9));
  });

  group('Suchen über die Rechnung hinaus (#188)', () {
    // Alles, woran man ein anderes Ergebnis erkennen würde.
    String sig(LoopPlan p) => [
          p.outcome,
          p.stops.map((s) => '${s.trail.id}${s.secondPass ? '²' : ''}').join(','),
          p.summary?.trailM,
          p.summary?.timeS,
          p.summary?.gainM,
          p.summary?.hikingM,
          p.points.length,
          p.excluded,
        ].join(' | ');

    LoopPlan plan(RoadGraph g, List<PoolTrail> pool,
            {LoopSearchCache? cache, LatLng? from, RiderParams profile = _bio, LoopBudget budget = _big}) =>
        planLoop(g,
            start: from ?? start,
            profile: profile,
            budget: budget,
            pool: pool,
            cache: cache,
            searchBudget: const Duration(milliseconds: 50));

    test('dieselbe Rechnung noch einmal: keine neue Suche, dasselbe Ergebnis', () {
      final g = _square(), cache = LoopSearchCache();
      final first = plan(g, [a, b], cache: cache);
      final ran = cache.searchesRun;
      expect(ran, greaterThan(0));
      final again = plan(g, [a, b], cache: cache);
      expect(cache.searchesRun, ran);
      expect(sig(again), sig(first));
    });

    test('abwählen, Höhenbudget, Pflicht: alles aus dem Speicher — und wie ohne gerechnet', () {
      // Zum Vergleich ein zweiter Graph, der dieselbe Folge OHNE Speicher
      // rechnet: Er ist dann im selben Stand (dieselben Teilungen).
      final g = _square(), fresh = _square(), cache = LoopSearchCache();
      expect(sig(plan(g, [a, b], cache: cache)), sig(plan(fresh, [a, b])));
      final ran = cache.searchesRun;
      final steps = <(List<PoolTrail>, LoopBudget)>[
        ([a], _big),
        ([a, b], const LoopBudget(timeS: 3 * 3600, climbM: 150, hikingM: 2000)),
        ([a, _trail('B', (1010, 990), (1010, 10), mandatory: true)], _big),
      ];
      for (final (pool, budget) in steps) {
        expect(sig(plan(g, pool, cache: cache, budget: budget)), sig(plan(fresh, pool, budget: budget)));
      }
      expect(cache.searchesRun, ran);
    });

    test('anderes Profil oder anderes Zeitbudget: neu gesucht', () {
      final g = _square(), cache = LoopSearchCache();
      plan(g, [a, b], cache: cache);
      var ran = cache.searchesRun;
      plan(g, [a, b], cache: cache, profile: RiderProfile.ebike);
      expect(cache.searchesRun, greaterThan(ran), reason: 'die Kosten hängen am Profil');
      ran = cache.searchesRun;
      plan(g, [a, b], cache: cache, profile: RiderProfile.ebike, budget: const LoopBudget(timeS: 2 * 3600, climbM: 800, hikingM: 2000));
      expect(cache.searchesRun, greaterThan(ran), reason: 'das Zeitbudget ist die Grenze der Suche');
    });

    test('teilt das Anheften eine Kante, gilt nichts Gemerktes mehr', () {
      final g = _square(), fresh = _square(), cache = LoopSearchCache();
      plan(g, [a, b], cache: cache);
      plan(fresh, [a, b]);
      final revision = g.revision;
      // Ein Start mitten auf dem unteren Weg: neuer Knoten, geteilte Kante.
      final mid = _m([(500, 0)]).single;
      final moved = plan(g, [a, b], cache: cache, from: mid);
      expect(g.revision, greaterThan(revision));
      expect(moved.outcome, LoopOutcome.ok);
      expect(sig(moved), sig(plan(fresh, [a, b], from: mid)));
    });
  });

  group('Zwischenpunkte vorab (#331 Schritt 4)', () {
    final corner = _m([(1000, 1000)]).single;
    double nearest(List<LatLng> line, LatLng p) => line.map((q) => haversineM(q.latitude, q.longitude, p.latitude, p.longitude)).reduce(math.min);
    LoopPlan plan(List<PoolTrail> pool, {List<LatLng> waypoints = const [], LoopBudget budget = _big, LoopTune? tune}) =>
        planLoop(_square(),
            start: start,
            profile: _bio,
            budget: budget,
            pool: pool,
            waypoints: waypoints,
            tune: tune,
            searchBudget: const Duration(milliseconds: 50));

    test('die Fahrt führt durch den Punkt, er ist kein Trail und kein Grund', () {
      final free = plan([a]);
      final via = plan([a], waypoints: [corner]);
      expect(via.outcome, LoopOutcome.ok);
      expect(nearest(free.points, corner), greaterThan(500), reason: 'frei geht es nicht dort vorbei');
      expect(nearest(via.points, corner), lessThan(1));
      expect(via.stops.map((s) => s.trail.id), ['A']);
      expect(via.order, contains('${kLoopWaypointPrefix}0'));
      expect(via.excluded.keys.where((k) => k.startsWith(kLoopWaypointPrefix)), isEmpty);
      expect(via.summary!.trailM, closeTo(1000, 0.5), reason: 'der Punkt bringt keine Trail-Meter');
      expect(via.summary!.lengthM, greaterThan(free.summary!.lengthM + 500));
      // Der Halt teilt die Fahrt: drei Teilstücke statt zwei.
      expect({for (final s in via.sections) if (!s.isTrail) s.leg}, hasLength(3));
    });

    test('auch ohne Runde und zum Ziel', () {
      for (final (rts, end) in [(false, null), (false, _m([(0, 1000)]).single)]) {
        final r = planLoop(_square(),
            start: start,
            profile: _bio,
            budget: _big,
            pool: [a],
            returnToStart: rts,
            end: end,
            waypoints: [corner],
            searchBudget: const Duration(milliseconds: 50));
        expect(r.outcome, LoopOutcome.ok, reason: 'Ende $end');
        expect(nearest(r.points, corner), lessThan(1), reason: 'Ende $end');
      }
    });

    test('ein Punkt abseits jedes Wegs: viaFailed, kein Grund mit seiner Kennung', () {
      final r = plan([a], waypoints: [_m([(500, 500)]).single]);
      expect(r.outcome, LoopOutcome.viaFailed);
      expect(r.excluded.keys.where((k) => k.startsWith(kLoopWaypointPrefix)), isEmpty);
    });

    test('der Punkt geht vor dem Budget — dann bleibt für den Trail keins', () {
      final tight = LoopBudget(timeS: plan([a]).summary!.timeS / (1 - kLoopTimeReserve) + 60, climbM: 800, hikingM: 2000);
      expect(plan([a], budget: tight).stops, hasLength(1), reason: 'ohne Punkt passt A');
      final r = plan([a], budget: tight, waypoints: [corner]);
      expect(r.outcome, LoopOutcome.empty);
      expect(r.excluded, {'A': LoopExclusion.budget});
    });

    test('getunt bleibt der Punkt in der Folge', () {
      final via = plan([a], waypoints: [corner]);
      final tuned = plan([a], waypoints: [corner], tune: LoopTune.of(via, RouteVias.none));
      expect(tuned.outcome, LoopOutcome.ok);
      expect(tuned.order, via.order);
      expect(nearest(tuned.points, corner), lessThan(1));
      expect(tuned.summary!.lengthM, closeTo(via.summary!.lengthM, 1));
    });
  });
}
