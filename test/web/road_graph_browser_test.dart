// Der Wegegraph in typisierten Feldern (#378) unter dart2js — läuft nur
// mit `flutter test --platform chrome` (CI: Schritt „Web-Test auf
// dart2js"). Im Web sind Zahlen Doubles (genau bis 2^53) und Bitoperationen
// 32 Bit: Die Streuung der Gitterzellen, die Zellnummern und die
// Punktnummern des Segmentgitters müssen dort dieselben Kandidaten finden
// wie auf der VM. Die Zahlen unten sind auf der VM gerechnet.
@TestOn('browser')
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_search.dart';

void main() {
  test('Bau, Join, Kreuzungen, Anheften und Suche wie auf der VM', () {
    // Ein Gitter 2 × 2 km, 200 m Masche, westlich von Greenwich (negative
    // Zellkoordinaten); dazu eine versetzte Schar ohne gemeinsame
    // Scheitel (Kreuzungen) und tote Enden 1 m vor dem nächsten Weg.
    const lat0 = 47.3, lon0 = -0.2, step = 200.0;
    final proj = FlatProjection(lat0);
    final o = proj.xy(const LatLng(lat0, lon0));
    LatLng at(double x, double y) => proj.latLng(math.Point(o.x + x, o.y + y));
    const n = 11;
    final lines = [
      for (var i = 0; i < n; i++) ...[
        WayLine(cls: WayClass.forstweg, oneway: false, points: [for (var j = 0; j < n; j++) at(i * step, j * step)]),
        WayLine(cls: WayClass.wanderweg, oneway: false, points: [for (var j = 0; j < n; j++) at(j * step, i * step)]),
        if (i + 1 < n)
          WayLine(
              cls: WayClass.nebenstrasse,
              oneway: false,
              points: [for (var j = 0; j < n - 1; j++) at(j * step + step / 2, i * step + step / 2)]),
      ],
      WayLine(cls: WayClass.radweg, oneway: false, points: [at(-150, 300), at(-1, 300)]),
    ];
    final build = buildRoadGraph(lines, lat0: lat0);
    final g = build.graph;
    expect((g.nodes.length, g.edges.length, build.joins, build.crossings), _vm.counts);

    final head = g.attach(at(1000 + 7, 1000 + 55));
    expect(head, isNotNull);
    final path = shortestPath(g, g.attach(at(-150, 300))!, head!, RiderProfile.bio);
    expect(path, isNotNull);
    expect(path!.edges.length, _vm.pathEdges);
    expect(path.costS, closeTo(_vm.costS, 1e-6));
    expect(g.nearest(at(333, 444), 60)?.edge, _vm.nearestEdge);
  });
}

/// Auf der VM gerechnet (`flutter test` ohne `@TestOn`).
const _vm = (counts: (234, 413, 1, 90), pathEdges: 13, costS: 573.6, nearestEdge: 53);
