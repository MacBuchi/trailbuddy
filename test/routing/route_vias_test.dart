// Zwischenpunkte pur (#234): Reihenfolge im Teilstück, Weg durch die
// Punkte bei „Zum Trailkopf", die getunte Runde mit fester Folge und der
// Teilstück-Index an den Verbindungen.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_vias.dart';
import 'package:trailbuddy/features/routing/trail_head_route.dart';

/// Meter → Grad über DIESELBE Projektion wie der Graph.
List<LatLng> _m(List<(double, double)> xy, {double lat0 = 47.5, double lon0 = 11.5}) {
  final proj = FlatProjection(lat0);
  final o = proj.xy(LatLng(lat0, lon0));
  return [for (final (x, y) in xy) proj.latLng(math.Point(o.x + x, o.y + y))];
}

LatLng _p(double x, double y) => _m([(x, y)]).single;

/// Ein Quadrat aus Forstwegen, 1 km Kante, flach.
RoadGraph _square() => buildRoadGraph([
      for (final w in [
        [(0.0, 0.0), (0.0, 1000.0)],
        [(0.0, 1000.0), (1000.0, 1000.0)],
        [(1000.0, 1000.0), (1000.0, 0.0)],
        [(1000.0, 0.0), (0.0, 0.0)],
      ])
        WayLine(cls: WayClass.forstweg, oneway: false, points: _m(w)),
    ], lat0: 47.5)
        .graph;

PoolTrail _trail(String id, (double, double) from, (double, double) to) => PoolTrail(
      id: id,
      name: id,
      points: _m([from, ((from.$1 + to.$1) / 2, (from.$2 + to.$2) / 2), to]),
      lengthM: 1000,
      grade: 2,
      lossM: 100,
    );

const _bio = RiderProfile.bio;
const _big = LoopBudget(timeS: 3 * 3600, climbM: 800, hikingM: 2000);

void main() {
  group('RouteVias', () {
    final line = _m([(0, 0), (100, 0), (200, 0), (300, 0), (400, 0)]);

    test('ein neuer Punkt kommt dorthin, wo er auf der Linie liegt', () {
      var (v, r) = RouteVias.none.insert(0, _p(300, 5), line);
      expect(r, (leg: 0, index: 0));
      (v, r) = v.insert(0, _p(100, 5), line);
      expect(r, (leg: 0, index: 0), reason: 'vor dem bei 300 m');
      (v, r) = v.insert(0, _p(390, 5), line);
      expect(r, (leg: 0, index: 2));
      expect(v.of(0), [_p(100, 5), _p(300, 5), _p(390, 5)]);
      expect(v.count, 3);
    });

    test('verschieben, entfernen, Gleichheit nach Inhalt', () {
      final (v, r) = RouteVias.none.insert(2, _p(200, 0), line);
      final moved = v.move(r, _p(250, 0));
      expect(moved.of(2), [_p(250, 0)]);
      expect(moved.remove(r).isEmpty, isTrue);
      expect(moved.remove(r), RouteVias.none);
      expect(RouteVias({2: [_p(250, 0)]}), moved);
      expect(moved == v, isFalse);
    });
  });

  group('Zum Trailkopf durch Zwischenpunkte', () {
    final from = _p(0, 5), head = _p(5, 1000);

    test('ohne Punkt die linke Kante, mit Punkt rechts herum', () {
      final direct = planTrailHeadRoute(_square(), from, head, _bio);
      expect(direct.route!.summary.lengthM, closeTo(1000, 1));
      final via = planTrailHeadRoute(_square(), from, head, _bio, via: [_p(1005, 500)]);
      expect(via.outcome, TrailHeadOutcome.ok);
      expect(via.route!.summary.lengthM, closeTo(3000, 1), reason: 'unten, rechts, oben');
      expect(via.route!.points.first, from);
      expect(via.route!.points.last, head);
    });

    test('ein Punkt abseits jedes Wegs', () {
      expect(planTrailHeadRoute(_square(), from, head, _bio, via: [_p(500, 500)]).outcome,
          TrailHeadOutcome.viaOffNetwork);
    });
  });

  group('Die getunte Runde', () {
    // A: oben links diagonal nach unten rechts; B: rechts hinunter.
    final a = _trail('A', (10, 990), (990, 10));
    final b = _trail('B', (1010, 990), (1010, 10));
    final start = _p(5, 0);

    test('Verbindungen tragen ihr Teilstück', () {
      final plan = planLoop(_square(), start: start, profile: _bio, budget: _big, pool: [a],
          searchBudget: const Duration(milliseconds: 50));
      final legs = {for (final s in plan.sections) if (!s.isTrail) s.leg};
      expect(legs, {0, 1}, reason: 'Start → A, A → Start');
      expect(plan.sections.where((s) => s.isTrail).every((s) => s.leg == null), isTrue);
    });

    test('ein Punkt im ersten Teilstück legt den Aufstieg rechts herum', () {
      final free = planLoop(_square(), start: start, profile: _bio, budget: _big, pool: [a],
          searchBudget: const Duration(milliseconds: 50));
      final tuned = planLoop(_square(),
          start: start,
          profile: _bio,
          budget: _big,
          pool: [a],
          tune: LoopTune.of(free, RouteVias({0: [_p(1005, 500)]})));
      expect(tuned.outcome, LoopOutcome.ok);
      final leg0 = tuned.sections.where((s) => s.leg == 0).fold(0.0, (m, s) => m + s.lengthM);
      expect(leg0, closeTo(3000, 1));
      expect(tuned.summary!.lengthM - free.summary!.lengthM, closeTo(2000, 1));
    });

    test('die Folge steht fest, auch wenn sie schlechter ist', () {
      final tuned = planLoop(_square(),
          start: start, profile: _bio, budget: _big, pool: [a, b], tune: const LoopTune(order: ['B', 'A']));
      expect(tuned.stops.map((s) => s.trail.id), ['B', 'A']);
    });

    test('ein Punkt abseits jedes Wegs: viaFailed', () {
      final tuned = planLoop(_square(),
          start: start,
          profile: _bio,
          budget: _big,
          pool: [a],
          tune: LoopTune(order: const ['A'], vias: RouteVias({0: [_p(500, 500)]})));
      expect(tuned.outcome, LoopOutcome.viaFailed);
    });
  });
}
