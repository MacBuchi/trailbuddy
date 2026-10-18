// Wo die Runde gerechnet wird (#188, „Plan duration"). Gemessen
// (`test/routing/perf_loop_planner_measure.dart`, docs/routing-messung.md):
// Auf einem Netz in der Größe des dichtesten Tirol-Rahmens rechnet
// `planLoop` auf dem Rechner 0,3 s mit 12 Trails und 2,2 s mit 60 — im
// UI-Isolate heißt das eine stehende Karte und ein stehender Kreisel,
// auf dem Telefon länger. Drei Dinge, die man wissen muss:
// - **Ein DAUERHAFTER Rechen-Isolate, nicht `Isolate.run` je Rechnung.**
//   Bis 0.131.0 ging der fertige Graph EINMAL hinüber — und allein das
//   Senden kopierte ihn im UI-Isolate (1,8 s bei 62 600 Kanten). Seit
//   #356 PR 8 geht nur die Eingabe hinüber ([GraphInput]: Kachel-Bytes,
//   Höhenraster, Trails), der Isolate BAUT den Graphen ([build]) und
//   behält ihn; jede Rechnung schickt nur Start, Budget, Profil und
//   Trails ([plan]).
// - **Der Graph lebt drüben.** Der UI-Isolate hat keinen. Wer etwas auf
//   einem Graphen rechnen will, schickt eine [GraphJob] — die Runde
//   ([LoopRequest]), „Zurück zur Route" (`TrailHeadJob`) und das
//   Einordnen einer Fahrt für die Kalibrierung (`CalibJob`, #356 PR 9) —
//   und bekommt nur das Ergebnis zurück.
// - **Im Browser und im Test rechnet er an Ort und Stelle**
//   ([InlineLoopPlanRunner]): Das Web hat keine Isolate, und ein
//   Widget-Test läuft in einer Zone mit falscher Uhr, in der ein echter
//   Isolate nie antwortet. Der Harness hängt deshalb die Inline-Fassung
//   ein; `loop_plan_runner_test.dart` fährt die echte.
// - **Bau und Runde melden ihren Fortschritt** (#356, Ladebalken):
//   `onProgress` bekommt Anteile 0…1 aus [PlanProgress] drüben, höchstens
//   einen je Prozent. Die übrigen Aufträge melden nichts.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'graph_input.dart';
import 'loop_plan_runner_web.dart' if (dart.library.io) 'loop_plan_runner_io.dart';
import 'loop_planner.dart';
import 'plan_progress.dart';
import 'road_graph.dart';
import 'route_profile.dart';

/// Eine Runde oder Route ohne den Graphen — das, was je Rechnung hinübergeht.
class LoopRequest implements GraphJob<LoopPlan> {
  const LoopRequest({
    required this.start,
    required this.profile,
    required this.budget,
    required this.pool,
    this.returnToStart = true,
    this.end,
    this.searchBudget = kLoopSearchBudget,
    this.tune,
    this.waypoints = const [],
    this.bare = false,
  });

  final LatLng start;
  final RiderParams profile;
  final LoopBudget budget;
  final List<PoolTrail> pool;
  final bool returnToStart;

  /// Das getippte Ziel (#331); null heißt Runde oder Ende am letzten Trail.
  final LatLng? end;
  final Duration searchBudget;

  /// Von Hand getunt (#234): feste Folge, Teilstücke durch Zwischenpunkte.
  final LoopTune? tune;

  /// Vorab gesetzte Zwischenpunkte (#331 Schritt 4).
  final List<LatLng> waypoints;

  /// Eine Route ohne Trail ist auch ein Ergebnis (#356, A → B).
  final bool bare;

  /// Dieselbe Rechnung mit fester Folge — das Tunen (#234) braucht genau
  /// die Eingaben der gezeigten Planung, nicht die, die jetzt eingestellt
  /// sind.
  LoopRequest withTune(LoopTune tune) => LoopRequest(
      start: start,
      profile: profile,
      budget: budget,
      pool: pool,
      returnToStart: returnToStart,
      end: end,
      searchBudget: searchBudget,
      tune: tune,
      waypoints: waypoints,
      bare: bare);

  LoopPlan planOn(RoadGraph g, {LoopSearchCache? cache}) => planLoop(g,
      start: start,
      profile: profile,
      budget: budget,
      pool: pool,
      returnToStart: returnToStart,
      end: end,
      searchBudget: searchBudget,
      cache: cache,
      tune: tune,
      waypoints: waypoints,
      bare: bare);

  @override
  LoopPlan runOn(RoadGraph g, LoopSearchCache cache) => planOn(g, cache: cache);
}

abstract interface class LoopPlanRunner {
  /// Baut den Graphen aus [input] und behält ihn — der vorige ist damit
  /// weg, samt gemerkten Suchen. Wirft, wenn der Bau scheitert.
  /// [onProgress] bekommt den Fortschritt (0…1).
  Future<GraphReport> build(GraphInput input, {void Function(double value)? onProgress});

  /// Ein Graph liegt bereit. Falsch vor dem ersten [build] und nachdem
  /// der Isolate verloren ging — dann baut der Aufrufer neu.
  bool get hasGraph;

  /// Rechnet [request] auf dem gebauten Graphen — [run] für die Runde,
  /// mit Fortschritt an [onProgress].
  Future<LoopPlan> plan(LoopRequest request, {void Function(double value)? onProgress});

  /// Rechnet [job] auf dem gebauten Graphen, drüben. Ohne Graph ein
  /// [StateError].
  Future<R> run<R>(GraphJob<R> job);

  /// Gibt den Isolate und seinen Graphen frei.
  void dispose();
}

/// Rechnet an Ort und Stelle — im Browser und im Test.
class InlineLoopPlanRunner implements LoopPlanRunner {
  RoadGraph? _graph;
  var _cache = LoopSearchCache();

  @override
  Future<GraphReport> build(GraphInput input, {void Function(double value)? onProgress}) async {
    BuiltGraph go() => buildGraphFrom(input, builtIn: 'inline');
    final built = onProgress == null ? go() : PlanProgress.run(onProgress, go);
    _graph = built.graph;
    _cache = LoopSearchCache();
    return built.report;
  }

  @override
  bool get hasGraph => _graph != null;

  @override
  Future<LoopPlan> plan(LoopRequest request, {void Function(double value)? onProgress}) async {
    if (onProgress == null) return run(request);
    final g = _graph;
    if (g == null) throw StateError('kein Graph gebaut');
    return PlanProgress.run(onProgress, () => request.runOn(g, _cache));
  }

  @override
  Future<R> run<R>(GraphJob<R> job) async {
    final g = _graph;
    if (g == null) throw StateError('kein Graph gebaut');
    return job.runOn(g, _cache);
  }

  @override
  void dispose() {
    _graph = null;
  }
}

/// Der Runner für den Planer: auf dem Telefon ein Rechen-Isolate, im
/// Browser an Ort und Stelle. Eine Fabrik, weil der Controller ihn mit
/// dem Modus anlegt und beim Schließen freigibt.
final loopPlanRunnerFactoryProvider = Provider<LoopPlanRunner Function()>((ref) => createLoopPlanRunner);
