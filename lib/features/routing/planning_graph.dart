// Der Graph für eine Planung — EIN Weg für den Rundenplaner und den Weg zu
// einem Trail oder Punkt: Bereiche, Höhen, Wege aus den Kacheln, darauf
// die Trails des Netzes (Richtung, Verbinder; `trail_overlay.dart`).
//
// **Gerechnet wird über die Kacheln, die da sind** (seit 0.74.0). Bis
// 0.73.0 verlangte die Planung, dass das GANZE Rechteck um Start und Trails
// gespeichert ist — bei einem Bereich „Entlang meiner Trails" (Kacheln nur
// in 1 km um die Trails) war das praktisch nie der Fall, und das Blatt sagte
// „nur zum Teil gedeckt", obwohl jeder Weg dazwischen bekannt war
// (Feldbericht: „teils hat es nicht funktioniert ohne sichtbaren Grund").
// Jetzt plant die Suche über die gefundenen Kacheln; ein Weg außerhalb kann
// kürzer sein, und das Blatt sagt das ([PlanningGraph.partial]). Ohne eine
// einzige Kachel gibt es weiter keinen Plan.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../models/trail.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../offline_areas/height_tiles.dart';
import '../rides/road_index.dart' show RoadCoverage;
import '../trails/trail_providers.dart';
import 'loop_planner.dart' show graphTrailsOf;
import 'online_fill.dart';
import 'road_graph.dart';
import 'road_graph_loader.dart';
import 'trail_head_route.dart' show kTrailHeadMarginM;
import 'trail_overlay.dart';

class PlanningGraph {
  const PlanningGraph({
    required this.graph,
    required this.coverage,
    required this.tilesFound,
    required this.tilesNeeded,
    this.tilesOnline = 0,
    this.onlineCapped = false,
    this.onlineBroken = false,
  });

  /// Null: keine einzige Kachel im Rahmen — kein Plan.
  final RoadGraph? graph;
  final RoadCoverage coverage;
  final int tilesFound;
  final int tilesNeeded;

  /// Davon vom Host nachgeladen (#187) — in [tilesFound] mitgezählt.
  final int tilesOnline;

  /// Es fehlten mehr Kacheln, als eine Planung online holt.
  final bool onlineCapped;

  /// Das Nachladen brach ab (Netz weg, Frist um).
  final bool onlineBroken;

  /// Geplant über einen Teil der Kacheln: Ein Weg außerhalb kann kürzer
  /// sein, und das Blatt sagt es.
  bool get partial => graph != null && coverage == RoadCoverage.partial;
}

/// Lädt den Graphen für den Rahmen um [points] (plus [kTrailHeadMarginM])
/// und legt die sichtbaren Trails darauf. Wirft nie: Ein Fehler beim Lesen
/// wird gemeldet und ergibt „keine Kachel".
///
/// [fillOnline] erlaubt das Nachladen fehlender Kacheln vom Host — nur,
/// wenn das Gerät Empfang meldet.
Future<PlanningGraph> loadPlanningGraph(Ref ref, LatBox box, {bool fillOnline = true}) async {
  List<StoredArea> areas;
  try {
    areas = await ref.read(storedAreasProvider.future);
  } catch (_) {
    areas = const [];
  }
  HeightReader? heights;
  try {
    heights = await ref.read(areaHeightReaderProvider.future);
  } catch (e, s) {
    // Ohne Höhen rechnet die Suche flach und sagt es; der Weg steht trotzdem.
    logError('Höhen für die Planung öffnen', e, s);
  }
  final store = ref.read(areaStoreProvider);
  final open = ref.read(areaArchiveOpenerProvider);
  final openWays = ref.read(areaWaysOpenerProvider);
  final online = fillOnline && !ref.read(noConnectivityProvider) ? ref.read(onlineFillFactoryProvider)() : null;
  if (online != null) {
    // Die Höhen der nachgeladenen Kacheln kommen als LETZTE Quelle dazu;
    // der Leser der Bereiche gehört seinem Provider und bleibt offen.
    heights = HeightReader([...?heights?.sources, online.heights]);
  }
  RoadGraphLoadResult roads;
  try {
    roads = await loadRoadGraph(
      areas: areas,
      box: box,
      open: (a) => open(store, a),
      heights: heights,
      marginM: kTrailHeadMarginM,
      requireComplete: false,
      fetchOnline: online?.fetch,
      openWays: (a) => openWays(store, a),
      fetchWaysOnline: online?.fetchWays,
    );
  } catch (e, s) {
    logError('Wege für die Planung lesen', e, s);
    return const PlanningGraph(graph: null, coverage: RoadCoverage.none, tilesFound: 0, tilesNeeded: 0);
  } finally {
    await online?.close();
  }
  final graph = roads.graph;
  if (graph != null) {
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    final near = [
      for (final t in trails)
        if (t.points.length >= 2 && LatBox.of(t.points).near(box, kTrailHeadMarginM)) t,
    ];
    final onGraph = graphTrailsOf(near);
    applyTrails(graph, onGraph);
    // Die Enden jeder Abfahrt gleich mit (#188): Wählt der Planer später
    // einen weiteren Trail aus diesem Rahmen, teilt sein Anheften keine
    // Kante mehr, und der Rechen-Isolate behält seine Suchen
    // (`LoopSearchCache`). Dieselben Punkte, die `planLoop` anheftet.
    for (final t in onGraph) {
      if (t.role != TrailRole.downhill) continue;
      graph.attach(t.points.first);
      graph.attach(t.points.last);
    }
  }
  return PlanningGraph(
    graph: graph,
    coverage: roads.coverage,
    tilesFound: roads.tilesFound,
    tilesNeeded: roads.tilesNeeded,
    tilesOnline: roads.tilesOnline,
    onlineCapped: roads.onlineCapped,
    onlineBroken: roads.onlineBroken,
  );
}

/// Der Satz unter dem Ergebnis, wenn nicht alles aus den Bereichen kam —
/// EINE Fassung für Runde und Weg. Null, wenn es nichts zu sagen gibt.
String? planningCoverageNote(PlanningGraph g, {required String what}) {
  if (g.graph == null) return null;
  final online = g.tilesOnline;
  final tiles = online == 1 ? '1 Kachel' : '$online Kacheln';
  if (!g.partial) {
    return online == 0 ? null : '$tiles online nachgeladen — ohne Empfang ginge $what so nicht.';
  }
  final head = 'Gerechnet über ${g.tilesFound} von ${g.tilesNeeded} Kacheln — nur dort kennt die App die Wege.';
  if (online == 0) return '$head Ein Weg außerhalb deiner Bereiche kann kürzer sein.';
  final rest = g.onlineCapped
      ? 'mehr als $kOnlineFillMaxTiles holt eine Planung nicht'
      : g.onlineBroken
          ? 'dann riss die Verbindung ab'
          : 'der Rest liegt außerhalb der Karte';
  return '$head $tiles davon online nachgeladen — $rest.';
}

/// Ein Provider, damit die Blätter [loadPlanningGraph] mit IHREM `ref`
/// rufen können (`WidgetRef` ist kein `Ref`) und Tests die Naht haben.
final planningGraphLoaderProvider = Provider<Future<PlanningGraph> Function(LatBox box, {bool fillOnline})>(
    (ref) => (box, {fillOnline = true}) => loadPlanningGraph(ref, box, fillOnline: fillOnline));
