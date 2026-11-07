// Verbinder mit der ganzen Linie und Lücken mit Preis (#492, Betreiber
// 2026-11-07): „nicht nur Start- und Endpunkte, sondern die gesamte
// Linie", und „die Verbindungen bevorzugen, bei denen keine Lücke
// überbrückt werden muss" — ein Trail-Ende hing bis 0.162.x am nächsten
// Knoten in 30 m, auch wenn der Transferweg 2 m daneben lag.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_search.dart';
import 'package:trailbuddy/features/routing/trail_overlay.dart';

const _lat0 = 47.5;

List<LatLng> _m(List<(double, double)> xy) {
  final proj = FlatProjection(_lat0);
  final o = proj.xy(const LatLng(_lat0, 11.5));
  return [for (final (x, y) in xy) proj.latLng(math.Point(o.x + x, o.y + y))];
}

LatLng _p(double x, double y) => _m([(x, y)]).single;

WayLine _way(List<(double, double)> xy, {WayClass cls = WayClass.forstweg}) =>
    WayLine(cls: cls, oneway: false, points: _m(xy));

GraphTrail _connector(List<(double, double)> xy, {TrailRole role = TrailRole.connector}) =>
    GraphTrail(id: 'v', name: 'Transfer', points: _m(xy), role: role);

RoadGraph _flat(List<WayLine> ways) {
  final g = buildRoadGraph(ways, lat0: _lat0).graph;
  for (final e in g.edges) {
    e.hasHeights = true;
  }
  return g;
}

const _bio = RiderProfile.bio;

/// Der günstigste Weg von [from] nach [to], mit Summe.
PathSummary _route(RoadGraph g, int from, int to) {
  final r = shortestPath(g, from, to, _bio)!;
  return summarizePath(g, r.edges, from, _bio);
}

void main() {
  test('eine Lücke im Weg darunter: der Verbinder führt trotzdem hinauf', () {
    // Der Pfad unter dem Transfer hat eine Lücke von 150 m (y 400–550) —
    // 85 % der Linie liegen an ihm, bis 0.162.x kam deshalb keine eigene
    // Kante dazu, und über die Lücke führte nichts.
    final g = _flat([
      _way([(0, 0), (0, 400)], cls: WayClass.wanderweg),
      _way([(0, 550), (0, 1000)], cls: WayClass.wanderweg),
      _way([(0, 0), (3000, 0)]),
      _way([(3000, 0), (3000, 1000)]),
      _way([(3000, 1000), (0, 1000)]),
    ]);
    applyTrails(g, [_connector([(3, 0), (3, 500), (3, 1000)])]);
    final bottom = g.attach(_p(0, 0))!, top = g.attach(_p(0, 1000))!;
    final up = _route(g, bottom, top);
    expect(up.trailUpM, greaterThan(900), reason: 'über den Transfer, nicht den Umweg');
    expect(up.lengthM, lessThan(1100));
  });

  test('eine Kreuzung mitten im Verlauf: dort steigt die Route ein', () {
    // Der Transfer steht nicht in der Karte; seine Enden liegen weit weg
    // von jedem Weg. Nur eine Straße quert ihn in der Mitte.
    final g = _flat([_way([(-1000, 500), (1000, 500)], cls: WayClass.nebenstrasse)]);
    applyTrails(g, [_connector([(0, 0), (0, 500), (0, 1000)])]);
    final west = g.attach(_p(-1000, 500))!;
    final top = g.attach(_p(0, 1000))!;
    final r = _route(g, west, top);
    expect(r.trailUpM, closeTo(500, 10), reason: 'ab der Kreuzung auf dem Transfer');
    expect(r.lengthM, closeTo(1500, 10));
  });

  test('ein Trail-Ende 2 m neben dem Transfer nimmt ihn, nicht den Knoten 25 m daneben', () {
    // Forstweg nach Süden ab (25, 0) — sein Endknoten liegt 25 m vom
    // Trail-Ende E (0, 0). Der Transfer läuft 2 m an E vorbei (mittendrin,
    // ohne Knoten dort) und endet am Forstweg unten.
    final g = _flat([_way([(25, 0), (25, -1000)])]);
    applyTrails(g, [_connector([(2, 300), (2, 0), (2, -990), (20, -1000)])]);
    final e = g.anchor(_p(0, 0))!;
    expect(e.meters, closeTo(2, 0.1), reason: 'die kürzeste Lücke');
    final down = g.attach(_p(25, -1000))!;
    final r = _route(g, e.node, down);
    expect(r.trailUpM, greaterThan(950), reason: 'über den Transfer');
    // Gegen die alte Regel: der nächste KNOTEN in 30 m wäre der Forstweg.
    expect(g.nearestNode(g.proj.xy(_p(0, 0)), kGraphAttachM, exclude: e.node), isNotNull);
  });

  test('derselbe Punkt zweimal: derselbe Knoten, keine neuen Lücken', () {
    final g = _flat([_way([(25, 0), (25, -1000)]), _way([(-1000, 10), (1000, 10)])]);
    final a = g.anchor(_p(0, 0))!;
    final rev = g.revision;
    final b = g.anchor(_p(0, 0))!;
    expect(b.node, a.node);
    expect(g.revision, rev);
    expect([for (final ei in g.adj[a.node]) g.edges[ei].gap], everyElement(isTrue));
    expect(g.adj[a.node], hasLength(2), reason: 'je Weg in 30 m eine Lücke');
  });

  test('eine Lücke kostet: geschoben in der Zeit, über 5 m mit Aufschlag', () {
    expect(gapTimeS(3), closeTo(3, 1e-9));
    expect(gapCostS(3), closeTo(3, 1e-9), reason: 'GPS-Unschärfe ohne Aufschlag');
    expect(gapCostS(25), closeTo(25 + 20 * kGapCostPerM, 1e-9));
    final g = _flat([_way([(0, 0), (1000, 0)])]);
    final n = g.anchor(_p(500, 25))!.node;
    final gap = g.edges[g.adj[n].single];
    expect(gap.gap, isTrue);
    expect(gap.hiking, isFalse);
    expect(edgeCostFrom(g, gap.index, n, _bio).cost, closeTo(gapCostS(25), 1e-6));
    final s = summarizePath(g, [gap.index], n, _bio);
    expect(s.timeS, closeTo(25, 1e-6));
    expect(s.hikingM, 0);
  });

  test('ein Uphill-Trail mit eigener Linie bleibt gegen seine Richtung gesperrt', () {
    final g = _flat([_way([(-1000, 500), (1000, 500)], cls: WayClass.nebenstrasse)]);
    applyTrails(g, [_connector([(0, 0), (0, 500), (0, 1000)], role: TrailRole.uphill)]);
    final west = g.attach(_p(-1000, 500))!, top = g.attach(_p(0, 1000))!;
    expect(shortestPath(g, west, top, _bio), isNotNull, reason: 'hinauf');
    expect(shortestPath(g, top, west, _bio), isNull, reason: 'hinunter gesperrt');
  });
}
