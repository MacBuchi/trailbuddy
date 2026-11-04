// Die Abzweigungen für die Uhr (#449, docs/konzept-garmin.md 1 und 2): je
// Kreuzung der Route ein Stummel des abgehenden Wegs, 40 m; die Kreuzung
// bleibt beim Vereinfachen stehen, die Stummel gehen mit dem Stück ihres
// Punkts.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/garmin/watch_branches.dart';
import 'package:trailbuddy/features/garmin/watch_route.dart';
import 'package:trailbuddy/features/routing/nav_sections.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

// Erfunden, am Äquator (nie echte Koordinaten im Repo); Meter über
// DIESELBE Projektion wie der Graph (test/CLAUDE.md der Routing-Tests).
final _proj = FlatProjection(0);
LatLng _m(double x, double y) => _proj.latLng(Point(x, y));

/// Ein Weg nach Norden (die Route), bei y = 500 ein Querweg nach Osten
/// und Westen, bei y = 800 ein Abzweig nach Nordosten, der erst 10 m
/// neben der Route läuft (folgt NICHT), bei y = 300 nur 5 m Kante (zu
/// kurz für eine Richtung). Dazu zwei Wege daneben, die nicht dazugehören.
RoadGraph _graph() {
  final g = RoadGraph(0);
  void edge(List<(double, double)> pts) {
    final ll = [for (final (x, y) in pts) _m(x, y)];
    g.addEdge(g.node(ll.first), g.node(ll.last), WayClass.forstweg, false, ll);
  }

  edge([(0, 0), (0, 300)]);
  edge([(0, 300), (0, 500)]);
  edge([(0, 500), (0, 800)]);
  edge([(0, 800), (0, 1000)]);
  edge([(0, 500), (200, 500)]);
  edge([(0, 500), (-30, 500)]);
  edge([(0, 800), (30, 830), (100, 900)]);
  edge([(0, 300), (5, 300)]);
  // Ein Weg 20 m daneben, der sich verzweigt: nicht die Route.
  edge([(20, 600), (20, 700)]);
  edge([(20, 700), (20, 750)]);
  edge([(20, 700), (60, 700)]);
  // Ein Knoten 7 m neben der Route, alle Kanten gehen weg: kein Teil der
  // Route, also keine Kreuzung DER Route.
  edge([(7, 650), (60, 650)]);
  edge([(7, 650), (60, 690)]);
  edge([(7, 650), (60, 610)]);
  return g;
}

final _line = [for (var y = 0.0; y <= 1000; y += 50) _m(0, y)];

void main() {
  test('je Kreuzung der Route ein Stummel je abgehender Kante, 40 m oder bis zum Ende der Kante', () {
    final br = watchBranchesOn(_graph(), _line);
    expect(br, hasLength(3), reason: 'Querweg zweimal, Nordost einmal — nicht die 5-m-Kante, nicht der Weg daneben');
    final ends = [for (final b in br) _proj.xy(b.end)];
    final ats = [for (final b in br) _proj.xy(b.at)];
    expect(br.map((b) => b.index), [10, 10, 16], reason: 'nach Punkt sortiert, der Punkt der Kreuzung');
    for (var k = 0; k < 2; k++) {
      expect(ats[k].y, closeTo(500, 0.01));
    }
    expect(ends.take(2).map((p) => p.x.round()).toSet(), {40, -30}, reason: 'Osten 40 m, Westen nur bis zum Ende der Kante');
    expect(ends[2].distanceTo(ats[2]), greaterThan(39));
    expect(ends[2].x, greaterThan(25), reason: 'Nordost: die Richtung des Wegs, nicht der Route');
  });

  test('eine GPS-Linie neben dem Knoten: der nächste Punkt, das Ende gegen die Kreuzung', () {
    final wobbly = [for (var y = 0.0; y <= 1000; y += 22) _m(3, y)];
    final br = watchBranchesOn(_graph(), wobbly);
    final cross = [for (final b in br) if ((_proj.xy(b.at).y - 500).abs() < 0.1) b];
    expect(cross, hasLength(2));
    expect(cross.first.index, 23, reason: 'y 506 liegt näher an 500 als 484');
    final route = watchRouteOf(wobbly, NavSections.none, branches: cross)!;
    final json = route.toJson();
    final b = json['br'] as List;
    expect(b.length, 6);
    // Ende gegen die Kreuzung, nicht gegen den Punkt: ±40 bzw. −30 m Ost.
    final dLons = {b[2], b[5]};
    expect(dLons, {(40 / 111194.93 * 1e5).round(), (-30 / 111194.93 * 1e5).round()});
    expect({b[1], b[4]}, {0});
  });

  test('ohne Graph in der Nähe: nichts', () {
    final far = [for (var y = 0.0; y <= 1000; y += 50) _m(5000, y)];
    expect(watchBranchesOn(_graph(), far), isEmpty);
  });

  test('die Kreuzung bleibt beim Vereinfachen stehen, die Nummer zeigt auf sie', () {
    // Eine Gerade: ohne festen Punkt blieben nur Anfang und Ende.
    final line = [for (var y = 0.0; y <= 1000; y += 10) _m(0, y)];
    expect(watchRouteOf(line, NavSections.none)!.pointCount, 2);
    final route = watchRouteOf(line, NavSections.none,
        branches: [(index: 50, at: _m(0, 500), end: _m(40, 500))])!;
    expect(route.pointCount, 3);
    expect(route.br, [1, 0, (40 / 111194.93 * 1e5).round()]);
  });

  test('die Stummel gehen mit dem Stück ihres Punkts und zählen in dessen Zahlen mit', () {
    final line = [for (var i = 0; i < 300; i++) _m(i.isEven ? 0 : 30, i * 30.0)];
    final branches = [
      for (var i = 10; i < 300; i += 7) (index: i, at: line[i], end: _proj.latLng(_proj.xy(line[i]) + const Point(-40, 0))),
    ];
    final route = watchRouteOf(line, NavSections.none, branches: branches)!;
    expect(route.br.length, branches.length * 3);
    final parts = route.parts(maxInts: 100);
    final br = <int>[];
    var offset = 0;
    for (final p in parts) {
      final pts = (p['pts'] as List).length ~/ 2;
      final own = (p['br'] as List?)?.cast<int>() ?? const <int>[];
      expect((p['pts'] as List).length + own.length, lessThanOrEqualTo(100));
      for (var k = 0; k < own.length; k += 3) {
        expect(own[k], inInclusiveRange(offset, offset + pts - 1), reason: 'der Punkt liegt in diesem Stück');
      }
      br.addAll(own);
      offset += pts;
    }
    expect(br, route.br);
    expect(route.toJson()['br'], route.br);
  });

  test('mehr als die Uhr nimmt: gleichmäßig ausgedünnt', () {
    final g = RoadGraph(0);
    final line = [for (var y = 0.0; y <= 40000; y += 50) _m(0, y)];
    for (var k = 0; k + 1 < line.length; k++) {
      g.addEdge(g.node(line[k]), g.node(line[k + 1]), WayClass.forstweg, false, [line[k], line[k + 1]]);
      final side = _m(40, k * 50.0);
      g.addEdge(g.node(line[k]), g.node(side), WayClass.forstweg, false, [line[k], side]);
    }
    final br = watchBranchesOn(g, line);
    expect(br, hasLength(kWatchMaxBranches));
    expect(br.first.index, lessThan(5));
    expect(br.last.index, greaterThan(line.length - 10));
  });
}
