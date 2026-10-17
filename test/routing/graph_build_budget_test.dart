// Wacht über die Bauzeit des Wegegraphen (#356 PR 4) — RELATIV zur
// Maschine: Ein langsamer Runner darf nicht rot werden, ein Bau, der um
// Größenordnungen kippt, schon.
//
// Was dieser Test NICHT sieht: den Fall aus #354. Der verschachtelte
// Record-Schlüssel war nur im AOT-Build langsam (VM-Typprüfung); im
// JIT-Lauf der Tests baute derselbe Code gleich schnell (gemessen
// 2026-10-17: 497 statt 470 ms). Dafür gibt es den Stall-Wächter in der
// Dev-App (`lib/core/stall_watch.dart`). Hier fällt auf, was überall
// langsam ist — eine Suche ohne Gitter, eine Schleife über alle Paare.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

/// Rot erst, wenn der Bau mehr als [_maxRatio]-mal so lange braucht wie
/// die Vergleichsarbeit UND länger als [_maxBuild] — beides zusammen,
/// damit weder ein langsamer Runner noch ein schneller Rechner täuscht.
const _maxRatio = 15;
const _maxBuild = Duration(seconds: 20);

void main() {
  test('15 km Gitter mit 5 550 Kreuzungen baut in der Zeit', () {
    const lat0 = 47.3, lon0 = 11.4, step = 200.0, sizeM = 15000.0;
    final proj = FlatProjection(lat0);
    final o = proj.xy(const LatLng(lat0, lon0));
    LatLng at(double x, double y) => proj.latLng(math.Point(o.x + x, o.y + y));
    final n = (sizeM / step).round() + 1;
    // Die Querlinien liegen um eine halbe Masche versetzt: Keine Kreuzung
    // teilt einen Scheitel, jede muss `findCrossings` finden und teilen —
    // so wie bei Kacheln, deren Vereinfachung die Knoten weggenommen hat.
    final lines = <WayLine>[
      for (var i = 0; i < n; i++) ...[
        WayLine(cls: WayClass.forstweg, oneway: false, points: [for (var j = 0; j < n; j++) at(i * step, j * step)]),
        WayLine(
            cls: WayClass.nebenstrasse,
            oneway: false,
            points: [for (var j = 0; j < n - 1; j++) at(j * step + step / 2, i * step + step / 2)]),
      ],
    ];

    final ref = Stopwatch()..start();
    final seen = <(int, int, int, int)>{};
    for (var r = 0; r < 2000000; r++) {
      seen.add((r & 1023, r >> 10, r % 7, r ~/ 3));
    }
    ref.stop();

    final clock = Stopwatch()..start();
    final build = buildRoadGraph(lines, lat0: lat0);
    clock.stop();

    expect(build.crossings, 5550, reason: 'das Gitter prüft die Kreuzungsteilung nicht mehr');
    expect(seen, hasLength(2000000));
    final ratio = clock.elapsedMicroseconds / math.max(1, ref.elapsedMicroseconds);
    final tooSlow = ratio > _maxRatio && clock.elapsed > _maxBuild;
    expect(tooSlow, isFalse,
        reason: 'Bau ${clock.elapsedMilliseconds} ms, Vergleich ${ref.elapsedMilliseconds} ms '
            '(${ratio.toStringAsFixed(1)}-fach)');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
