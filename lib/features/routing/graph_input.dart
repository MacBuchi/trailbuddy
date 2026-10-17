// Der Graph des Planers wird im Rechen-Isolate GEBAUT, nicht nur
// gerechnet (#356 PR 8, Konzept-Routing 10.6). Bis 0.131.0 baute ihn der
// UI-Isolate — auf Android seit Flutter 3.29 der Haupt-Thread — und
// schickte ihn dann hinüber: 36 s in `findCrossings` waren ein ANR
// (#354), und allein das Senden stand 1,8 s bei 62 600 Kanten
// (docs/routing-messung.md, #356).
//
// Die Naht ist [GraphInput]: nur Bytes und schlichte Werte, die der
// UI-Isolate aus Kachelspeicher, Netz und Trail-Liste gesammelt hat —
// nichts Dekodiertes, kein Leser, kein Provider. [buildGraphFrom] macht
// daraus den Graphen: dekodieren, bauen (Zuschnitt, tote Enden,
// Kreuzungen), Steigungen, Güte, Trails auflegen, Enden anheften. Ein
// Test prüft strukturell, dass kein Weg vom Bau zurück in den UI-Isolate
// führt (`test/routing/graph_isolation_test.dart`).
//
// Rein: keine Widgets, kein Riverpod, kein `dart:isolate` — im Browser
// baut dieselbe Funktion an Ort und Stelle (`InlineLoopPlanRunner`).
import '../../core/stall_watch.dart';
import '../offline_areas/height_tiles.dart';
import 'road_graph.dart';
import 'road_graph_loader.dart' show RoadTileBytes, buildRoadGraphFrom;
import 'trail_overlay.dart';

/// Alles, was der Bau braucht — sendbar an einen Isolate.
class GraphInput {
  const GraphInput({
    required this.roads,
    this.ways = const [],
    this.heights,
    this.trails = const [],
    required this.lat0,
  });

  /// Die Wege-Kacheln (Ebene `roads`), Bytes wie im Archiv.
  final List<RoadTileBytes> roads;

  /// Die Kacheln des Wege-Archivs (#213) — Lücken erlaubt.
  final List<RoadTileBytes> ways;

  /// Die Höhenkacheln des Rahmens, vorab gelesen; null: alle Kanten flach.
  final HeightTiles? heights;

  /// Die Trails des Netzes im Rahmen, in Trail-Richtung (`graphTrailsOf`).
  final List<GraphTrail> trails;

  /// Die Breite, um die der Graph eben gerechnet wird.
  final double lat0;

  /// Ungefähr so viele Bytes gehen hinüber — für Messung und Log.
  int get bytes =>
      roads.fold<int>(0, (s, r) => s + r.bytes.length) +
      ways.fold<int>(0, (s, w) => s + w.bytes.length) +
      (heights?.length ?? 0) * kHeightGrid * kHeightGrid * 2;
}

/// Was der Bau gemacht hat — die Zahlen, die der UI-Isolate zurückbekommt
/// (der Graph selbst bleibt drüben).
class GraphReport {
  const GraphReport({
    required this.nodes,
    required this.edges,
    required this.joins,
    required this.crossings,
    required this.edgesWithoutHeights,
    required this.edgesOnTrails,
    required this.blocked,
    required this.addedEdges,
    required this.builtIn,
  });

  final int nodes;
  final int edges;
  final int joins;
  final int crossings;
  final int edgesWithoutHeights;
  final int edgesOnTrails;
  final int blocked;
  final int addedEdges;

  /// Der Name des Isolates, in dem gebaut wurde — der Runner setzt ihn,
  /// der Test vergleicht ihn mit dem eigenen.
  final String builtIn;
}

/// Der Graph samt Bericht — was [buildGraphFrom] liefert, wo es läuft.
typedef BuiltGraph = ({RoadGraph graph, GraphReport report});

/// Baut den Graphen des Planers aus [input]: dekodieren, bauen, Höhen,
/// Güte ([buildRoadGraphFrom]), dann die Trails auflegen ([applyTrails])
/// und die Enden jeder Abfahrt anheften — dieselben Punkte, die
/// `planLoop` anheftet (#188): So teilt ein später dazugewählter Trail
/// aus dem Rahmen keine Kante mehr, und der Suchspeicher bleibt gültig.
/// Wirft bei einem kaputten Eingang — der Aufrufer meldet und sagt
/// „keine Wege" (ein halb belegter Graph plante Abfahrten bergauf).
BuiltGraph buildGraphFrom(GraphInput input, {String builtIn = ''}) {
  final built = StallWatch.mark(
      'graph.build', () => buildRoadGraphFrom(roads: input.roads, ways: input.ways, heights: input.heights, lat0: input.lat0));
  final graph = built.graph;
  final overlay = StallWatch.mark('graph.trails', () => applyTrails(graph, input.trails));
  StallWatch.mark('graph.attach', () {
    for (final t in input.trails) {
      if (t.role != TrailRole.downhill) continue;
      graph.attach(t.points.first);
      graph.attach(t.points.last);
    }
  });
  return (
    graph: graph,
    report: GraphReport(
      nodes: graph.nodes.length,
      edges: graph.edges.length,
      joins: built.joins,
      crossings: built.crossings,
      edgesWithoutHeights: built.edgesWithoutHeights,
      edgesOnTrails: overlay.edgesOnTrails,
      blocked: overlay.blocked,
      addedEdges: overlay.addedEdges,
      builtIn: builtIn,
    ),
  );
}
