// „Zum Trailkopf" pur (#158 Schritt 4): Anschluss von Standort und
// Trailkopf, die Abschnitte je Wegklasse, die Linie von Standort bis
// Kopf, die drei Fehlfälle, die Zeit-Wörter und die GPX-Spur.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/trail_head_route.dart';

import '../fakes/l10n_de.dart';

/// Meter → Grad über DIESELBE Projektion wie der Graph.
List<LatLng> _m(List<(double, double)> xy, {double lat0 = 47.5, double lon0 = 11.5}) {
  final proj = FlatProjection(lat0);
  final o = proj.xy(LatLng(lat0, lon0));
  return [for (final (x, y) in xy) proj.latLng(math.Point(o.x + x, o.y + y))];
}

WayLine _way(List<(double, double)> xy, {WayClass cls = WayClass.forstweg}) =>
    WayLine(cls: cls, oneway: false, points: _m(xy));

void main() {
  const bio = RiderProfile.bio;

  test('Forstweg, dann Wanderweg: zwei Abschnitte, Linie von Standort bis Kopf', () {
    final g = buildRoadGraph([
      _way([(0, 0), (500, 0), (1000, 0)]),
      _way([(1000, 0), (1000, 300)], cls: WayClass.wanderweg),
    ], lat0: 47.5).graph;
    // Standort 5 m neben dem Anfang, Trailkopf 10 m neben dem Ende.
    final from = _m([(0, 5)]).single, head = _m([(1010, 300)]).single;
    final plan = planTrailHeadRoute(g, from, head, bio);
    expect(plan.outcome, TrailHeadOutcome.ok);
    final r = plan.route!;
    expect(r.sections.map((s) => s.cls), [WayClass.forstweg, WayClass.wanderweg]);
    expect(r.sections[0].lengthM, closeTo(1000, 0.5));
    expect(r.sections[1].lengthM, closeTo(300, 0.5));
    expect(r.summary.hikingM, closeTo(300, 0.5));
    expect(r.summary.lengthM, closeTo(1300, 0.5), reason: 'die Verbinder zählen nicht');
    expect(r.points.first, from);
    expect(r.points.last, head);
    expect(r.points.length, r.sections.fold(0, (n, s) => n + s.points.length) - 1 + 2,
        reason: 'gemeinsame Knoten einmal, dazu Standort und Kopf');
    expect(r.profile, bio);
  });

  test('Standort oder Trailkopf ohne Weg in 30 m, oder keine Verbindung', () {
    final g = buildRoadGraph([_way([(0, 0), (500, 0)]), _way([(900, 0), (1400, 0)])], lat0: 47.5).graph;
    expect(planTrailHeadRoute(g, _m([(250, 100)]).single, _m([(500, 0)]).single, bio).outcome,
        TrailHeadOutcome.startOffNetwork);
    expect(planTrailHeadRoute(g, _m([(250, 0)]).single, _m([(700, 0)]).single, bio).outcome,
        TrailHeadOutcome.headOffNetwork);
    expect(planTrailHeadRoute(g, _m([(250, 0)]).single, _m([(1200, 0)]).single, bio).outcome,
        TrailHeadOutcome.noPath);
  });

  test('Standort und Kopf am selben Knoten: eine Linie ohne Strecke', () {
    final g = buildRoadGraph([_way([(0, 0), (500, 0)])], lat0: 47.5).graph;
    final plan = planTrailHeadRoute(g, _m([(2, 0)]).single, _m([(0, 3)]).single, bio);
    expect(plan.outcome, TrailHeadOutcome.ok);
    expect(plan.route!.summary.lengthM, 0);
    expect(plan.route!.sections, isEmpty);
    expect(plan.route!.points, hasLength(3));
  });

  test('das Profil ändert die Zeit, nicht den Weg', () {
    final g = buildRoadGraph([_way([(0, 0), (2000, 0)])], lat0: 47.5).graph;
    for (final e in g.edges) {
      e
        ..gain = 200
        ..hasHeights = true;
    }
    final from = _m([(0, 0)]).single, head = _m([(2000, 0)]).single;
    final b = planTrailHeadRoute(g, from, head, RiderProfile.bio).route!;
    final e = planTrailHeadRoute(g, from, head, RiderProfile.ebike).route!;
    expect(e.summary.timeS, lessThan(b.summary.timeS));
    expect(e.summary.lengthM, b.summary.lengthM);
    expect(b.summary.heightsComplete, isTrue);
  });

  test('Zeit-Wörter: auf fünf Minuten gerundet', () {
    expect(routeTimeLabel(l10nDe, 100), 'unter 5 min');
    expect(routeTimeLabel(l10nDe, 44 * 60.0), '45 min');
    expect(routeTimeLabel(l10nDe, 3600), '1 h');
    expect(routeTimeLabel(l10nDe, 4800), '1 h 20 min');
    expect(routeTimeLabel(l10nDe, 4680), '1 h 20 min', reason: '78 min → 80');
  });

  test('GPX: die ganze Linie, Name nennt den Trail, keine Höhen', () {
    final g = buildRoadGraph([_way([(0, 0), (500, 0)])], lat0: 47.5).graph;
    final r = planTrailHeadRoute(g, _m([(0, 4)]).single, _m([(500, 4)]).single, bio).route!;
    final t = trailHeadToGpx(l10nDe, r, trailName: 'Hexentanz');
    expect(t.name, 'Zum Trailkopf: Hexentanz');
    expect(t.points, hasLength(r.points.length));
    expect(t.points.first.lat, r.points.first.latitude);
    expect(t.points.every((p) => p.ele == null && p.time == null), isTrue);
    expect(t.link, isNull);
  });
}
