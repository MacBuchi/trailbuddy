// Messung, kein Test (#378): Wie viel Heap hält EIN gebauter Wegegraph,
// und welche Klassen? Nach GC gelesen über den VM-Service — der RSS des
// Prozesses schwankt um ±100 MB und taugt dafür nicht.
//
// Läuft NICHT in CI (kein `_test.dart`), sondern von Hand und nur mit
// VM-Service:
//   flutter test --enable-vmservice test/routing/perf_graph_memory_measure.dart
// Die Zahlen gehören nach docs/routing-messung.md („#378"). Das Netz ist
// dasselbe Gitter wie in `perf_loop_planner_measure.dart` (25 × 25 km,
// 200 m Maschenweite, versetzte Nebenstraßen mit Kreuzungsteilung), als
// z13-Kacheln kodiert und gebaut wie im Rechen-Isolate.
import 'dart:developer' as dev;
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/routing/graph_input.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
// Kommt mit flutter_test (über leak_tracker); für ein Mess-Skript von
// Hand keine eigene Abhängigkeit.
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service_io.dart';

import '../fakes/graph_tiles.dart';

const _lat0 = 47.3, _lon0 = 11.4;
const _sizeM = 25000.0, _stepM = 200.0;

void main() {
  test('Heap eines Wegegraphen', () async {
    final proj = FlatProjection(_lat0);
    final o = proj.xy(const LatLng(_lat0, _lon0));
    LatLng at(double x, double y) => proj.latLng(math.Point(o.x + x, o.y + y));
    final n = (_sizeM / _stepM).round() + 1;
    const classes = [WayClass.forstweg, WayClass.wanderweg, WayClass.forstweg, WayClass.nebenstrasse];
    final lines = [
      for (var i = 0; i < n; i++) ...[
        WayLine(
            cls: classes[i % classes.length],
            oneway: false,
            points: [for (var j = 0; j < n; j++) at(i * _stepM, j * _stepM)]),
        WayLine(
            cls: classes[(i + 1) % classes.length],
            oneway: false,
            points: [for (var j = 0; j < n; j++) at(j * _stepM, i * _stepM)]),
        if (i + 1 < n)
          WayLine(
              cls: WayClass.nebenstrasse,
              oneway: false,
              points: [for (var j = 0; j < n - 1; j++) at(j * _stepM + _stepM / 2, i * _stepM + _stepM / 2)]),
      ],
    ];
    final roads = roadTilesOf(lines);
    final input = GraphInput(
        roads: roads, heights: heightTilesOf([for (final r in roads) r.tile], (_) => 900), trails: const [], lat0: _lat0);
    buildGraphFrom(input); // Code warm, Felder der Bibliotheken angelegt

    final info = await dev.Service.controlWebServer(enable: true);
    final uri = info.serverWebSocketUri;
    if (uri == null) fail('Kein VM-Service — mit --enable-vmservice starten.');
    final svc = await vmServiceConnectUri(uri.toString());
    final iso = dev.Service.getIsolateId(Isolate.current)!;
    Future<(int, Map<String, (int, int)>)> profile() async {
      final p = await svc.getAllocationProfile(iso, gc: true);
      return (
        p.memoryUsage!.heapUsage!,
        {
          for (final m in p.members!)
            '${m.classRef!.library?.uri?.split('/').last}:${m.classRef!.name}': (m.bytesCurrent ?? 0, m.instancesCurrent ?? 0)
        },
      );
    }

    final (h0, p0) = await profile();
    final g = buildGraphFrom(input).graph;
    final (h1, p1) = await profile();
    String mb(int b) => (b / (1 << 20)).toStringAsFixed(1);
    // ignore: avoid_print
    print('Graph: ${g.nodes.length} Knoten, ${g.edges.length} Kanten, '
        '${g.edges.fold<int>(0, (s, e) => s + e.points.length)} Linienpunkte — Heap +${mb(h1 - h0)} MB');
    final diff = [
      for (final e in p1.entries) (e.key, e.value.$1 - (p0[e.key]?.$1 ?? 0), e.value.$2 - (p0[e.key]?.$2 ?? 0)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    for (final (cls, bytes, count) in diff.take(10)) {
      // ignore: avoid_print
      print('| $cls | ${mb(bytes)} MB | $count |');
    }
    // Fingerabdruck des Graphen (#378): Ein Umbau des Speichers muss ihn
    // halten — dieselben Knoten, Kanten, Linien, Längen und Höhen.
    final edgeHash = _fnv([
      for (final e in g.edges)
        '${e.a} ${e.b} ${e.cls.index} ${e.length} ${e.gain} ${e.loss} ${e.steepWUp} ${e.carry} '
            '${[for (final p in e.points) '${p.latitude},${p.longitude}'].join(';')}',
    ].join('|'));
    final adjHash = _fnv([for (var n = 0; n < g.nodes.length; n++) g.adj[n].join(',')].join('|'));
    // ignore: avoid_print
    print('Fingerabdruck: ${edgeHash.toRadixString(16)} ${adjHash.toRadixString(16)}');
    expect(g.edges, isNotEmpty);
    await svc.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// FNV-1a über den Text — `Object.hash` ist je Prozess anders geseedet.
int _fnv(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h;
}
