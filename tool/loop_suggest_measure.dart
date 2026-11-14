// Messung, kein Test (#516, Konzept-Routing 12.8): Was kostet „Runde
// vorschlagen", wenn der Pool ALLES im Umkreis ist — je Zeitstufe der
// Umkreis aus 12.4 (1 h → 5 km, 2 h → 8 km, 3 h → 12 km, darüber 15 km)?
// Kacheln des Rahmens gegen `kPlanMaxTiles`, Zusammensetzen aus
// gebackenen Stücken, Rechenzeit gegen die Budgets aus 10.7, und was der
// Vorschlag ist (Trails, Zeit, Anteil).
//
// Öffentliche Daten: die offiziellen Trails Tirols (Branch
// `official-trails-data`, `tirol.geojson`) und die Kacheln um Innsbruck
// vom eigenen Host:
//   python3 tool/routing_tiles.py sample --out DIR/tiles --frame innsbruck --size 13
//   TB_TILES_DIR=DIR/tiles/innsbruck TB_TRAILS=DIR/tirol.geojson \
//     flutter test tool/loop_suggest_measure.dart
// Die Zahlen gehören nach docs/routing-messung.md („#516"). Liegt unter
// tool/, nicht test/: Es geht nie ins Binary (Version Guard).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/routing/graph_input.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/routing_tile.dart';
import 'package:trailbuddy/features/routing/trail_head_route.dart' show kTrailHeadMarginM;
import 'package:trailbuddy/features/routing/trail_overlay.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart' show haversineM;

double _dist(LatLng a, LatLng b) => haversineM(a.latitude, a.longitude, b.latitude, b.longitude);

const _z = 13;

/// Öffentliche Ortsmitte (dieselbe wie `tool/routing_tiles.py`).
const _start = LatLng(47.27, 11.40);

/// Zeitstufen und Umkreis aus Konzept-Routing 12.4.
const _steps = [(1.0, 5000.0), (1.5, 6500.0), (2.0, 8000.0), (3.0, 12000.0), (4.0, 15000.0), (5.0, 15000.0)];

void main() {
  final dir = Platform.environment['TB_TILES_DIR'], trailsPath = Platform.environment['TB_TRAILS'];
  test('Runde vorschlagen: alles im Umkreis', () {
    if (dir == null || trailsPath == null) {
      // ignore: avoid_print
      print('TB_TILES_DIR / TB_TRAILS fehlen — siehe Kopf der Datei.');
      return;
    }
    final meta = jsonDecode(File('$dir/frame.json').readAsStringSync()) as Map<String, dynamic>;
    final tiles = [for (final t in meta['tiles'] as List) ((t as List)[0] as int, t[1] as int)];
    Uint8List? bytes(String kind, (int, int) t, String ext) {
      final f = File('$dir/$kind/${t.$1}_${t.$2}.$ext');
      return f.existsSync() ? f.readAsBytesSync() : null;
    }

    final heights = HeightTiles({
      for (final t in tiles)
        if (bytes('heights', t, 'bin') case final b?) HeightTiles.keyOf(t.$1, t.$2): HeightTile.decode(b),
    });
    // Einmal backen, was der Workflow oder das Gerät vorab tut (#380).
    final bakeClock = Stopwatch()..start();
    final pieces = {
      for (final p in bakeTiles(
        roads: [
          for (final t in tiles)
            if (bytes('roads', t, 'mvt') case final b?) (tile: (z: _z, x: t.$1, y: t.$2), bytes: b),
        ],
        ways: [
          for (final t in tiles)
            if (bytes('ways', t, 'mvt') case final b?) (tile: (z: _z, x: t.$1, y: t.$2), bytes: b),
        ],
        heights: heights,
      ))
        (p.x, p.y): p,
    };
    // ignore: avoid_print
    print('Gebacken: ${pieces.length} Stücke in ${bakeClock.elapsedMilliseconds} ms');

    final all = _trails(trailsPath);
    // ignore: avoid_print
    print('| Zeit | Umkreis | Rad | Pool | Kacheln (Kreis) | Zusammensetzen | Kanten | Fenster / Limit | Rechnung | Trails | Schätzung | Trail-Anteil | Anstieg |');
    var warm = false;
    for (final profile in [RiderProfile.bio, RiderProfile.ebike]) {
      for (final (hours, reachM) in _steps) {
        final inReach = [
          for (final t in all)
            if (_dist(_start, t.points.first) <= reachM && _dist(_start, t.points.last) <= reachM) t,
        ];
        final box = LatBox.of([_start, for (final t in inReach) ...t.points]);
        final frame = roadGraphTiles(box, kTrailHeadMarginM);
        // Der schlimmste Fall: Trails rundum bis an den Umkreis.
        final dLat = reachM / 111320, dLon = dLat / math.cos(_start.latitude * math.pi / 180);
        final circle = roadGraphTiles(
            LatBox(_start.latitude - dLat, _start.longitude - dLon, _start.latitude + dLat, _start.longitude + dLon),
            kTrailHeadMarginM);
        final missing = frame.where((t) => !pieces.containsKey((t.x, t.y))).length;
        final input = GraphInput(
          roads: const [],
          pieces: [for (final t in frame) ?pieces[(t.x, t.y)]],
          bake: true,
          trails: [
            for (final t in inReach)
              GraphTrail(id: t.id, name: t.name, points: t.points, role: TrailRole.downhill),
          ],
          lat0: _start.latitude,
        );
        // Höhenmeter wie in 12.4: die Vorgabe (3 h) linear mit der Zeit,
        // auf die Spanne geklemmt.
        final climb = ((profile.budgetClimbM * hours / kBudgetHours / LoopPrefs.climbStep).round() *
                LoopPrefs.climbStep)
            .clamp(LoopPrefs.minClimb, LoopPrefs.maxClimb);
        if (!warm) {
          buildGraphFrom(input);
          warm = true;
        }
        final buildClock = Stopwatch()..start();
        final built = buildGraphFrom(input);
        final buildMs = buildClock.elapsedMilliseconds;
        for (final (label, windowS, climbM) in [
          ('0', 0.0, climb),
          ('¼', hours * 3600 / 4, climb),
          ('30', kLoopTimeWindowS, climb),
          ('30, frei', kLoopTimeWindowS, LoopPrefs.maxClimb),
        ]) {
          if (label == '¼' && hours >= 2) continue;
          final budget = LoopBudget(
              timeS: hours * 3600, climbM: climbM, hikingM: kBudgetHikingKm * 1000, windowS: windowS);
          final planClock = Stopwatch()..start();
          final plan = planLoop(built.graph, start: _start, profile: profile, budget: budget, pool: inReach);
          final planMs = planClock.elapsedMilliseconds;
          final s = plan.summary;
          final share = s == null || s.lengthM == 0 ? null : s.trailM / s.lengthM;
          String hm(double sec) => '${sec ~/ 3600} h ${((sec % 3600) / 60).round().toString().padLeft(2, '0')}';
          // ignore: avoid_print
          print('| ${hours.toStringAsFixed(1)} h | ${(reachM / 1000).round()} km | ${profile.name} '
              '| ${inReach.length} | ${frame.length} (${circle.length})${missing > 0 ? ' ($missing fehlen)' : ''} '
              '| $buildMs ms | ${built.report.edges} | $label / ${climbM.round()} | $planMs ms | ${plan.stops.length} '
              '| ${s == null ? '–' : hm(s.timeS)} | ${share == null ? '–' : '${(share * 100).round()} %'} '
              '| ${s == null ? '–' : '${s.gainM.round()} hm'} |');
        }
      }
    }
    // Zusammensetzen des ganzen Rahmens (13 × 13) — die Obergrenze hier.
    final whole = GraphInput(roads: const [], pieces: pieces.values.toList(), bake: true, lat0: _start.latitude);
    final wholeClock = Stopwatch()..start();
    final wholeGraph = buildGraphFrom(whole);
    // ignore: avoid_print
    print('Ganzer Rahmen: ${pieces.length} Kacheln, ${wholeGraph.report.edges} Kanten, '
        '${wholeClock.elapsedMilliseconds} ms');
  }, timeout: const Timeout(Duration(minutes: 30)));
}

/// Die offiziellen Trails als Pool: Punkte in Fahrtrichtung (die Quelle
/// nennt `down_m`), Grad aus `level`, ohne Sterne.
List<PoolTrail> _trails(String path) {
  final d = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  const grades = {'easy': 1, 'medium': 2, 'difficult': 3, 'expert': 4};
  final out = <PoolTrail>[];
  for (final (k, f) in (d['features'] as List).cast<Map<String, dynamic>>().indexed) {
    final p = f['properties'] as Map<String, dynamic>;
    final g = f['geometry'] as Map<String, dynamic>;
    final lines = g['type'] == 'LineString' ? [g['coordinates'] as List<dynamic>] : (g['coordinates'] as List).cast<List<dynamic>>();
    final pts = [
      for (final line in lines)
        for (final c in line) LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
    if (pts.length < 2) continue;
    out.add(PoolTrail(
      id: 'o$k',
      name: 'o$k',
      points: pts,
      lengthM: (p['length_m'] as num).toDouble(),
      grade: grades[p['level']],
      gainM: ((p['up_m'] as num?) ?? 0).toDouble(),
      lossM: math.max(0, ((p['down_m'] as num?) ?? 0).toDouble()),
    ));
  }
  return out;
}
