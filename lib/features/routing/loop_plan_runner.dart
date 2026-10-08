// Wo die Runde gerechnet wird (#188, „Plan duration"). Gemessen
// (`test/routing/perf_loop_planner_measure.dart`, docs/routing-messung.md):
// Auf einem Netz in der Größe des dichtesten Tirol-Rahmens rechnet
// `planLoop` auf dem Rechner 0,3 s mit 12 Trails und 2,2 s mit 60 — im
// UI-Isolate heißt das eine stehende Karte und ein stehender Kreisel,
// auf dem Telefon länger. Drei Dinge, die man wissen muss:
// - **Ein DAUERHAFTER Rechen-Isolate, nicht `Isolate.run` je Rechnung.**
//   Das Senden kopiert den Graphen im UI-Isolate, und das allein kostete
//   0,3–0,6 s — fast so viel, wie es sparen sollte. Der Graph geht deshalb
//   EINMAL hinüber (mit dem Laden, wenn ohnehin der Kreisel läuft), jede
//   Rechnung schickt nur Start, Budget, Profil und Trails.
// - **Drüben wird der Graph verändert** (`attach` teilt Kanten), hier
//   nicht. Der Controller hält seinen Graphen nur, um ihn hinüberzugeben;
//   wer ihn hier für etwas anderes braucht, rechnet auf dem Stand vor der
//   Planung.
// - **Im Browser und im Test rechnet er an Ort und Stelle**
//   ([InlineLoopPlanRunner]): Das Web hat keine Isolate, und ein
//   Widget-Test läuft in einer Zone mit falscher Uhr, in der ein echter
//   Isolate nie antwortet. Der Harness hängt deshalb die Inline-Fassung
//   ein; `loop_plan_runner_test.dart` fährt die echte.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'loop_plan_runner_web.dart' if (dart.library.io) 'loop_plan_runner_io.dart';
import 'loop_planner.dart';
import 'road_graph.dart';
import 'route_profile.dart';

/// Eine Rechnung ohne den Graphen — das, was je Rechnung hinübergeht.
class LoopRequest {
  const LoopRequest({
    required this.start,
    required this.profile,
    required this.budget,
    required this.pool,
    this.returnToStart = true,
    this.searchBudget = kLoopSearchBudget,
    this.tune,
  });

  final LatLng start;
  final RiderParams profile;
  final LoopBudget budget;
  final List<PoolTrail> pool;
  final bool returnToStart;
  final Duration searchBudget;

  /// Von Hand getunt (#234): feste Folge, Teilstücke durch Zwischenpunkte.
  final LoopTune? tune;

  LoopPlan planOn(RoadGraph g, {LoopSearchCache? cache}) => planLoop(g,
      start: start,
      profile: profile,
      budget: budget,
      pool: pool,
      returnToStart: returnToStart,
      searchBudget: searchBudget,
      cache: cache,
      tune: tune);
}

abstract interface class LoopPlanRunner {
  /// Rechnet [request] auf [graph]. Derselbe Graph (identisch) wird nur
  /// einmal übergeben.
  Future<LoopPlan> plan(RoadGraph graph, LoopRequest request);

  /// Gibt den Isolate und seine Kopie des Graphen frei.
  void dispose();
}

/// Rechnet an Ort und Stelle — im Browser und im Test.
class InlineLoopPlanRunner implements LoopPlanRunner {
  final _cache = LoopSearchCache();

  @override
  Future<LoopPlan> plan(RoadGraph graph, LoopRequest request) async => request.planOn(graph, cache: _cache);

  @override
  void dispose() {}
}

/// Der Runner für den Planer: auf dem Telefon ein Rechen-Isolate, im
/// Browser an Ort und Stelle. Eine Fabrik, weil der Controller ihn mit
/// dem Modus anlegt und beim Schließen freigibt.
final loopPlanRunnerFactoryProvider = Provider<LoopPlanRunner Function()>((ref) => createLoopPlanRunner);
