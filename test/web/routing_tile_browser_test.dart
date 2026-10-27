// Vorgebackene Routing-Kacheln (#380) unter dart2js — läuft nur mit
// `flutter test --platform chrome` (CI: Schritt „Web-Test auf dart2js").
// Im Web sind Bitoperationen 32 Bit: Schreiber und Leser der Varints
// rechnen deshalb mit Multiplikation, und Backen, Packen (gzip),
// Lesen und Zusammensetzen müssen dort denselben Graphen ergeben wie auf
// der VM. Die Zahlen unten sind auf der VM gerechnet.
@TestOn('browser')
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_search.dart';
import 'package:trailbuddy/features/routing/routing_tile.dart';

import '../fakes/graph_tiles.dart';

void main() {
  test('backen, packen, lesen und zusammensetzen wie auf der VM', () {
    final (tiles, nodes, edges, points, gainCm, cost) = routingTileFingerprint();
    expect((tiles, nodes, edges, points), (_vm.$1, _vm.$2, _vm.$3, _vm.$4));
    // Höhen und Kosten rechnen über sin/log in JavaScript — genau bis auf
    // die letzte Stelle ist dort nicht versprochen.
    expect(gainCm, closeTo(_vm.$5, 5));
    expect(cost, closeTo(_vm.$6, 0.01));
  });
}

/// Ein Gitter 6 × 6 km über mehrere Kacheln westlich von Greenwich (der
/// Kachelrand liegt bei negativen Längen), mit Knicken (innere Punkte in
/// Pixeln), Höhen und einer Straße quer hindurch (Kreuzungen).
(int, int, int, int, int, double) routingTileFingerprint() {
  const lat0 = 51.4, lon0 = -0.05;
  final proj = FlatProjection(lat0);
  final o = proj.xy(const LatLng(lat0, lon0));
  LatLng at(double x, double y) => proj.latLng(math.Point(o.x + x, o.y + y));
  final lines = [
    for (var i = 0; i <= 10; i++) ...[
      WayLine(cls: WayClass.forstweg, oneway: false, points: [at(i * 600.0 - 3000, -3000), at(i * 600.0 - 2970, 310), at(i * 600.0 - 3000, 3000)]),
      WayLine(cls: WayClass.wanderweg, oneway: false, points: [at(-3000, i * 600.0 - 3000), at(290, i * 600.0 - 2980), at(3000, i * 600.0 - 3000)]),
    ],
    WayLine(cls: WayClass.nebenstrasse, oneway: false, points: [at(-2900, -2810), at(2890, 2900)]),
  ];
  final roads = roadTilesOf(lines);
  final heights = heightTilesOf([for (final r in roads) r.tile], (p) => 40 + 30 * math.sin(proj.xy(p).x / 400));
  final pieces = bakeTiles(roads: roads, heights: heights);
  final g = stitchPieces([for (final p in pieces) unpackPiece(p.bytes)!], lat0).graph;
  final s = g.nearestNode(proj.xy(at(-3000, -3000)), 5)!, t = g.nearestNode(proj.xy(at(3000, 3000)), 5)!;
  final cost = dijkstra(g, s, RiderProfile.bio, target: t).costTo(t)!;
  final gainCm = g.edges.fold<int>(0, (a, e) => a + (e.gain * 100).round());
  final points = g.edges.fold<int>(0, (a, e) => a + e.points.length);
  return (roads.length, g.nodes.length, g.edges.length, points, gainCm, (cost * 1000).roundToDouble() / 1000);
}

/// Auf der VM gerechnet (`routingTileFingerprint` aus einem VM-Test).
const _vm = (9, 206, 304, 630, 136696, 6227.709);
