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
// Seit #380 (Konzept-Routing 11) setzt der Bau den Graphen aus
// vorgebackenen Stücken zusammen ([GraphInput.bake]): Was der UI-Isolate
// frisch im Kachelspeicher fand, kommt als [GraphInput.pieces], die
// übrigen Kacheln backt [buildGraphFrom] hier ([bakeTiles]) und gibt die
// neuen Stücke im Bericht zurück ([GraphReport.baked]) — der UI-Isolate
// legt sie in den Speicher. Die zweite Planung in denselben Kacheln setzt
// nur noch zusammen.
//
// Rein: keine Widgets, kein Riverpod, kein `dart:isolate` — im Browser
// baut dieselbe Funktion an Ort und Stelle (`InlineLoopPlanRunner`).
import '../../core/stall_watch.dart';
import '../offline_areas/height_tiles.dart';
import 'loop_planner.dart' show LoopSearchCache;
import 'plan_progress.dart';
import 'road_graph.dart';
import 'road_graph_loader.dart' show RoadTileBytes, buildRoadGraphFrom;
import 'routing_tile.dart';
import 'trail_overlay.dart';

/// Alles, was der Bau braucht — sendbar an einen Isolate.
class GraphInput {
  const GraphInput({
    required this.roads,
    this.ways = const [],
    this.heights,
    this.trails = const [],
    required this.lat0,
    this.pieces = const [],
    this.bake = false,
  });

  /// Die Wege-Kacheln (Ebene `roads`), Bytes wie im Archiv — mit [bake]
  /// nur die, für die es noch kein Stück gibt.
  final List<RoadTileBytes> roads;

  /// Vorgebackene Stücke (#380), gepackt wie im Kachelspeicher.
  final List<RoutingPiece> pieces;

  /// Aus Stücken zusammensetzen: [roads] werden je Kachel gebacken und
  /// mit [pieces] zusammengesetzt (`routing_tile.dart`). Ohne baut es den
  /// Graphen wie bis 0.135 in einem Stück — die Kalibrierung, die nur
  /// Klassen braucht und keine Höhen liest, und die Messungen.
  final bool bake;

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
      pieces.fold<int>(0, (s, p) => s + p.bytes.length) +
      ways.fold<int>(0, (s, w) => s + w.bytes.length) +
      (heights?.length ?? 0) * kHeightGrid * kHeightGrid * 2;
}

/// Nur backen, ohne Graph (#380 Weg C): die Kacheln eines gespeicherten
/// Bereichs im Hintergrund, Block für Block — sendbar wie [GraphInput].
class BakeInput {
  const BakeInput({required this.roads, this.ways = const [], this.heights});

  /// Die zu backenden Wege-Kacheln.
  final List<RoadTileBytes> roads;

  /// Das Wege-Archiv um sie herum (3 × 3) — Lücken erlaubt.
  final List<RoadTileBytes> ways;

  /// Die Höhen der zu backenden Kacheln; null: flach.
  final HeightTiles? heights;
}

/// Backt die Stücke für [input] — dieselben wie im Bau ([buildGraphFrom]).
List<RoutingPiece> bakeFrom(BakeInput input) => StallWatch.mark(
    'graph.bake', () => bakeTiles(roads: input.roads, ways: input.ways, heights: input.heights));

/// Eine Rechnung auf dem Graphen drüben (#356 PR 9): hinüber gehen nur
/// ihre Eingaben, zurück kommt [R] — beides muss sendbar sein (keine
/// Closures, keine Provider). [runOn] läuft im Isolate, mit dem
/// Suchspeicher des Runners. Die Runde (`LoopRequest`), „Zurück zur
/// Route" (`TrailHeadJob`) und das Einordnen einer Fahrt (`CalibJob`)
/// sind welche.
abstract interface class GraphJob<R> {
  R runOn(RoadGraph g, LoopSearchCache cache);
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
    this.baked = const [],
    this.stitched = 0,
    this.broken = const [],
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

  /// Die Stücke, die dieser Bau gebacken hat (#380), gepackt — der
  /// UI-Isolate legt sie in den Kachelspeicher.
  final List<RoutingPiece> baked;

  /// Aus so vielen Stücken (vorhandenen und gebackenen) zusammengesetzt.
  final int stitched;

  /// Die vorhandenen Stücke, die sich nicht lesen ließen (`x`, `y`) — sie
  /// fehlen im Graphen; der UI-Isolate nimmt sie aus dem Speicher, damit
  /// die nächste Planung sie neu backt.
  final List<(int, int)> broken;
}

/// Der Graph samt Bericht — was [buildGraphFrom] liefert, wo es läuft.
typedef BuiltGraph = ({RoadGraph graph, GraphReport report});

/// Baut den Graphen des Planers aus [input]: dekodieren, bauen, Höhen,
/// Güte ([buildRoadGraphFrom]), dann die Trails auflegen ([applyTrails])
/// und die Enden jeder Abfahrt anheften — dieselben Punkte, die
/// `planLoop` anheftet (#188), seit #394 wie dort bis [kGraphSnapM]: So
/// teilt ein später dazugewählter Trail aus dem Rahmen keine Kante mehr,
/// und der Suchspeicher bleibt gültig.
/// Wirft bei einem kaputten Eingang — der Aufrufer meldet und sagt
/// „keine Wege" (ein halb belegter Graph plante Abfahrten bergauf).
BuiltGraph buildGraphFrom(GraphInput input, {String builtIn = ''}) {
  var baked = const <RoutingPiece>[];
  final broken = <(int, int)>[];
  final ({RoadGraph graph, int joins, int crossings, int edgesWithoutHeights}) built;
  if (!input.bake) {
    built = PlanProgress.part(
        0,
        0.96,
        () => StallWatch.mark('graph.build',
            () => buildRoadGraphFrom(roads: input.roads, ways: input.ways, heights: input.heights, lat0: input.lat0)));
  } else {
    // Den Balken teilen nach Arbeit: Backen kostet je Kachel etwa so viel
    // wie der Bau von heute, Zusammensetzen ein Zehntel (Konzept-Routing
    // 11.3).
    final work = input.roads.length + 0.1 * input.pieces.length;
    final bakeTo = work == 0 ? 0.0 : 0.96 * input.roads.length / work;
    baked = PlanProgress.part(
        0,
        bakeTo,
        () => StallWatch.mark(
            'graph.bake', () => bakeTiles(roads: input.roads, ways: input.ways, heights: input.heights)));
    final stitched = PlanProgress.part(bakeTo, 0.96, () => StallWatch.mark('graph.stitch', () {
          final decoded = <DecodedPiece>[];
          for (final p in [...input.pieces, ...baked]) {
            final d = unpackPiece(p.bytes);
            if (d == null) {
              broken.add((p.x, p.y));
            } else {
              decoded.add(d);
            }
          }
          return stitchPieces(decoded, input.lat0);
        }));
    final g = stitched.graph;
    built = (
      graph: g,
      joins: stitched.joins,
      crossings: 0,
      edgesWithoutHeights: g.edgesWithoutHeights,
    );
  }
  final graph = built.graph;
  final overlay =
      PlanProgress.part(0.96, 0.99, () => StallWatch.mark('graph.trails', () => applyTrails(graph, input.trails)));
  StallWatch.mark('graph.attach', () {
    for (final t in input.trails) {
      if (t.role != TrailRole.downhill) continue;
      graph.snap(t.points.first);
      graph.snap(t.points.last);
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
      baked: baked,
      stitched: input.bake ? input.pieces.length + baked.length - broken.length : 0,
      broken: broken,
    ),
  );
}
