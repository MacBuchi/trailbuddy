// Messung, kein Test (#188, „Plan duration"): Wie lange rechnet der
// Rundenplaner bei großer Auswahl? Er läuft im UI-Isolate; das Konzept
// verlangt < 5 s auf dem Telefon, und ab einer spürbaren Pause gehört er
// in ein Isolate.
//
// Läuft NICHT in CI (kein `_test.dart`), sondern von Hand:
//   flutter test test/routing/perf_loop_planner_measure.dart
// Die Zahlen gehören nach docs/routing-messung.md. Je Zeile: Dauer an Ort
// und Stelle (= so lange steht die Oberfläche), dann im Rechen-Isolate
// (`loop_plan_runner.dart`) die erste Rechnung (Graph geht hinüber), eine
// zweite auf demselben Graphen und eine dritte mit einem Trail weniger —
// beide seit 0.80.2 aus den gemerkten Suchen (`LoopSearchCache`) —, je
// Dauer / längste Pause des UI-Takts, alles in ms. Die Rechenzeit auf dem Rechner (JIT) ist eine
// untere Grenze; das Telefon ist langsamer.
//
// Das Netz ist erfunden, aber so groß wie der dichteste Tirol-Rahmen
// (M1/M5: 24 722 Wegstücke auf 20 km): ein Gitter über 25 × 25 km mit
// 200 m Maschenweite, Forstweg/Wanderweg/Nebenstraße im Wechsel, Höhen aus
// einer glatten Hügelfläche (bis ~1 200 hm Spanne, Rampen über 15 %). Die
// Trails steigen das Gitter hinab (immer zum tiefsten Nachbarn), 1–2 km,
// gestreut über 12 km um den Start — der Pool des Planers.
//
// Seit #356 mit Kreuzungsteilung wie in der App: Eine dritte Schar
// Nebenstraßen liegt eine halbe Masche versetzt, ihre Kreuzungen teilen
// keinen Scheitel und gehen durch `findCrossings` (bis dahin baute das
// Skript mit `splitCrossings: false`, #354 war so nie gemessen). Die Zeit
// des Baus ist eine JIT-Zahl; der AOT-Fall aus #354 zeigt sich nur auf dem
// Gerät (Stall-Wächter, `lib/core/stall_watch.dart`).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner_io.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/trail_overlay.dart';

const _lat0 = 47.3, _lon0 = 11.4;
const _sizeM = 25000.0, _stepM = 200.0;

double _height(double x, double y) =>
    900 + 450 * math.sin(x / 2600) * math.cos(y / 3400) + 180 * math.sin((x + 2 * y) / 1300);

/// Dauer und längste Pause des UI-Takts (alle 4 ms ein Timer) — die
/// Pause ist, was man sieht: so lange steht Karte und Kreisel.
Future<({T result, Duration total, Duration stall})> _watch<T>(Future<T> Function() f) async {
  final clock = Stopwatch()..start();
  var last = Duration.zero, stall = Duration.zero;
  void tick() {
    final now = clock.elapsed;
    if (now - last > stall) stall = now - last;
    last = now;
  }

  final timer = Timer.periodic(const Duration(milliseconds: 4), (_) => tick());
  await Future<void>.delayed(Duration.zero);
  final result = await f();
  tick();
  timer.cancel();
  return (result: result, total: clock.elapsed, stall: stall);
}

void main() {
  final proj = FlatProjection(_lat0);
  final o = proj.xy(const LatLng(_lat0, _lon0));
  LatLng at(double x, double y) => proj.latLng(math.Point(o.x + x, o.y + y));
  final n = (_sizeM / _stepM).round() + 1;
  const classes = [WayClass.forstweg, WayClass.wanderweg, WayClass.forstweg, WayClass.nebenstrasse];

  var crossings = 0;
  ({RoadGraph g, Duration build}) graph() {
    final clock = Stopwatch()..start();
    final lines = <WayLine>[
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
    final build = buildRoadGraph(lines, lat0: _lat0);
    final g = build.graph;
    crossings = build.crossings;
    for (final e in g.edges) {
      final a = g.nodes[e.a], b = g.nodes[e.b];
      final ha = _height(a.x - o.x, a.y - o.y), hb = _height(b.x - o.x, b.y - o.y);
      final d = hb - ha;
      e.gain = math.max(0, d);
      e.loss = math.max(0, -d);
      final over = math.max(0.0, d.abs() - kSteepGrade * e.length);
      e.steepUp = d > 0 ? over : 0;
      e.steepDown = d < 0 ? over : 0;
      e.hasHeights = true;
    }
    return (g: g, build: clock.elapsed);
  }

  /// [count] Trails, die das Gitter hinabsteigen, ab zufälligen Knoten in
  /// 12 km um die Mitte.
  List<(List<(int, int)>, double)> trails(int count, math.Random rnd) {
    final out = <(List<(int, int)>, double)>[];
    final mid = n ~/ 2, reach = (12000 / _stepM).floor() - 10;
    while (out.length < count) {
      var i = mid + rnd.nextInt(2 * reach) - reach, j = mid + rnd.nextInt(2 * reach) - reach;
      final cells = <(int, int)>[(i, j)];
      final steps = 5 + rnd.nextInt(6);
      for (var k = 0; k < steps; k++) {
        (int, int)? best;
        var low = _height(i * _stepM, j * _stepM);
        for (final (di, dj) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final (a, b) = (i + di, j + dj);
          if (a < 0 || b < 0 || a >= n || b >= n || cells.contains((a, b))) continue;
          final h = _height(a * _stepM, b * _stepM);
          if (h < low) (low, best) = (h, (a, b));
        }
        if (best == null) break;
        (i, j) = best;
        cells.add(best);
      }
      if (cells.length < 6) continue;
      final first = cells.first, last = cells.last;
      final loss = _height(first.$1 * _stepM, first.$2 * _stepM) - _height(last.$1 * _stepM, last.$2 * _stepM);
      if (loss < 60) continue;
      out.add((cells, loss));
    }
    return out;
  }

  for (final (count, profile, budget) in [
    (12, RiderProfile.bio, const LoopBudget(timeS: 3 * 3600, climbM: 1000, hikingM: 2000)),
    (30, RiderProfile.bio, const LoopBudget(timeS: 3 * 3600, climbM: 1000, hikingM: 2000)),
    (40, RiderProfile.bio, const LoopBudget(timeS: 5 * 3600, climbM: 1600, hikingM: 3000)),
    (60, RiderProfile.ebike, const LoopBudget(timeS: 5 * 3600, climbM: 2500, hikingM: 3000)),
  ]) {
    test('$count Trails, ${profile.name}, ${budget.timeS ~/ 3600} h', () async {
      final built = graph();
      final g = built.g;
      final rnd = math.Random(188 + count);
      final chosen = trails(count, rnd);
      final pool = <PoolTrail>[];
      final overlay = <GraphTrail>[];
      for (final (k, (cells, loss)) in chosen.indexed) {
        final pts = [for (final (i, j) in cells) at(i * _stepM, j * _stepM)];
        final id = 't$k';
        overlay.add(GraphTrail(id: id, name: id, points: pts, role: TrailRole.downhill));
        pool.add(PoolTrail(
          id: id,
          name: id,
          points: pts,
          lengthM: (cells.length - 1) * _stepM,
          grade: rnd.nextInt(4),
          rating: 1 + rnd.nextInt(5),
          lossM: loss,
        ));
      }
      final clock = Stopwatch()..start();
      final applied = applyTrails(g, overlay);
      final overlayTime = clock.elapsed;
      final request = LoopRequest(
          start: at(_sizeM / 2 - 100 + 13, _sizeM / 2 - 100), profile: profile, budget: budget, pool: pool);

      // An Ort und Stelle: so rechnete der Planer bis 0.80.0.
      final inline = await _watch(() async => request.planOn(g));
      // Im Rechen-Isolate, auf einem frischen Graphen (der erste Lauf hat
      // den Start schon angeheftet): die erste Rechnung schickt den
      // Graphen, die zweite nur noch die Anfrage.
      final fresh = graph().g;
      applyTrails(fresh, overlay);
      final runner = IsolateLoopPlanRunner();
      final first = await _watch(() => runner.plan(fresh, request));
      final second = await _watch(() => runner.plan(fresh, request));
      final fewer = LoopRequest(
          start: request.start, profile: profile, budget: budget, pool: pool.sublist(1));
      final third = await _watch(() => runner.plan(fresh, fewer));
      runner.dispose();
      expect(second.result.stops.map((s) => s.trail.id), first.result.stops.map((s) => s.trail.id));
      expect(first.result.stops.map((s) => s.trail.id), inline.result.stops.map((s) => s.trail.id));

      final plan = inline.result;
      String ms(Duration d) => '${d.inMilliseconds}';
      // ignore: avoid_print
      print('| $count | ${profile.name} ${budget.timeS ~/ 3600} h / ${budget.climbM.round()} hm '
          '| ${g.edges.length} | $crossings | ${ms(built.build)} | ${ms(overlayTime)} (${applied.blocked} gesperrt) '
          '| ${ms(inline.total)} | ${ms(first.total)} / ${ms(first.stall)} '
          '| ${ms(second.total)} / ${ms(second.stall)} '
          '| ${ms(third.total)} / ${ms(third.stall)} '
          '| ${plan.stops.length} | ${plan.summary == null ? '–' : '${(plan.summary!.timeS / 60).round()} min'} |');
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
