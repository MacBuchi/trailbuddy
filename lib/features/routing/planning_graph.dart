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
//
// **Hier wird nichts gebaut** (#356 PR 8, Konzept-Routing 10.6): Der
// UI-Isolate sammelt nur Bytes — die Kacheln der Bereiche, online
// ergänzt, die Höhenkacheln dazu, die Trails im Rahmen — als
// [GraphInput]; dekodiert und gebaut wird im Rechen-Isolate des Planers
// (`graph_input.dart`, `loop_plan_runner.dart`), und der Graph bleibt
// dort. Vor dem ersten Lesen zählt der Lader den Rahmen: über
// [kPlanMaxTiles] ist er „zu groß" ([PlanningGraph.tooLarge]), ohne
// eine Kachel geöffnet zu haben.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../core/stall_watch.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../offline_areas/height_tiles.dart';
import '../rides/road_index.dart' show RoadCoverage;
import '../trails/trail_providers.dart';
import 'graph_input.dart';
import 'loop_planner.dart' show graphTrailsOf;
import 'online_fill.dart';
import 'road_graph_loader.dart';
import 'trail_head_route.dart' show kTrailHeadMarginM;

class PlanningGraph {
  const PlanningGraph({
    this.input,
    required this.coverage,
    required this.tilesFound,
    required this.tilesNeeded,
    this.tilesOnline = 0,
    this.onlineCapped = false,
    this.onlineBroken = false,
    this.tooLarge = false,
  });

  /// Keine Kachel im Rahmen — kein Plan.
  static const none = PlanningGraph(coverage: RoadCoverage.none, tilesFound: 0, tilesNeeded: 0);

  /// Die Eingabe für den Bau im Rechen-Isolate; null ohne Kachel, bei
  /// „zu groß" — und nach der Übergabe ([summary]), damit die Bytes nicht
  /// im Zustand des Planers liegen bleiben.
  final GraphInput? input;
  final RoadCoverage coverage;
  final int tilesFound;
  final int tilesNeeded;

  /// Davon vom Host nachgeladen (#187) — in [tilesFound] mitgezählt.
  final int tilesOnline;

  /// Es fehlten mehr Kacheln, als eine Planung online holt.
  final bool onlineCapped;

  /// Das Nachladen brach ab (Netz weg, Frist um).
  final bool onlineBroken;

  /// Der Rahmen übersteigt [kPlanMaxTiles]: nichts gelesen, kein Plan.
  final bool tooLarge;

  /// Es gibt einen Graphen zum Rechnen (mindestens eine Kachel).
  bool get usable => tilesFound > 0 && !tooLarge;

  /// Geplant über einen Teil der Kacheln: Ein Weg außerhalb kann kürzer
  /// sein, und das Blatt sagt es.
  bool get partial => usable && coverage == RoadCoverage.partial;

  /// Dasselbe ohne die Bytes — was der Planer nach der Übergabe behält.
  PlanningGraph get summary => input == null
      ? this
      : PlanningGraph(
          coverage: coverage,
          tilesFound: tilesFound,
          tilesNeeded: tilesNeeded,
          tilesOnline: tilesOnline,
          onlineCapped: onlineCapped,
          onlineBroken: onlineBroken,
          tooLarge: tooLarge,
        );
}

/// Sammelt die Eingabe für den Graphen im Rahmen um [points] (plus
/// [kTrailHeadMarginM]): Kacheln, Höhen, die sichtbaren Trails. Wirft
/// nie: Ein Fehler beim Lesen wird gemeldet und ergibt „keine Kachel".
/// Gebaut wird NICHT hier (`buildGraphFrom`).
///
/// [fillOnline] erlaubt das Nachladen fehlender Kacheln vom Host — nur,
/// wenn das Gerät Empfang meldet. [maxTiles] ist die Grenze vor dem
/// Lesen; null heißt keine.
Future<PlanningGraph> loadPlanningGraph(Ref ref, LatBox box,
    {bool fillOnline = true, int? maxTiles = kPlanMaxTiles}) async {
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
  final online = fillOnline && !ref.read(noConnectivityProvider) ? ref.read(onlineFillFactoryProvider)(box) : null;
  if (online != null) {
    // Die Höhen der nachgeladenen Kacheln kommen als LETZTE Quelle dazu;
    // der Leser der Bereiche gehört seinem Provider und bleibt offen.
    heights = HeightReader([...?heights?.sources, online.heights]);
  }
  RoadTilesRead read;
  HeightTiles? tiles;
  try {
    read = await StallWatch.time('graph.load', () => readRoadTiles(
      areas: areas,
      box: box,
      open: (a) => open(store, a),
      marginM: kTrailHeadMarginM,
      fetchOnline: online?.fetch,
      openWays: (a) => openWays(store, a),
      fetchWaysOnline: online?.fetchWays,
      sourceKey: (a) => a.region,
      maxTiles: maxTiles,
    ));
    StallWatch.info('graph.tiles', '${read.tilesFound}/${read.tilesNeeded}');
    // Die Höhen der gefundenen Kacheln gleich mit — drüben gibt es
    // weder den Kachelspeicher noch das Netz.
    if (read.tilesFound > 0 && heights != null) {
      final h = heights;
      tiles = await StallWatch.time('graph.heights', () => HeightTiles.read(h, read.heightTiles));
    }
  } catch (e, s) {
    logError('Wege für die Planung lesen', e, s);
    return PlanningGraph.none;
  } finally {
    await online?.close();
  }
  GraphInput? input;
  if (read.tilesFound > 0) {
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    final near = [
      for (final t in trails)
        if (t.points.length >= 2 && LatBox.of(t.points).near(box, kTrailHeadMarginM)) t,
    ];
    input = GraphInput(
      roads: read.roads,
      ways: read.ways,
      heights: tiles,
      trails: graphTrailsOf(serviceL10n(), near),
      lat0: (box.s + box.n) / 2,
    );
  }
  return PlanningGraph(
    input: input,
    coverage: read.coverage,
    tilesFound: read.tilesFound,
    tilesNeeded: read.tilesNeeded,
    tilesOnline: read.tilesOnline,
    onlineCapped: read.onlineCapped,
    onlineBroken: read.onlineBroken,
    tooLarge: read.tooLarge,
  );
}

/// Der Satz unter dem Ergebnis, wenn nicht alles aus den Bereichen kam —
/// EINE Fassung für Runde ([loop]) und Weg. Null, wenn es nichts zu sagen
/// gibt.
String? planningCoverageNote(AppLocalizations l, PlanningGraph g, {required bool loop}) {
  if (!g.usable) return null;
  final online = g.tilesOnline;
  if (!g.partial) {
    return online == 0 ? null : (loop ? l.routingCoverageOnlineLoop(online) : l.routingCoverageOnlineRoute(online));
  }
  final head = l.routingCoveragePartial(g.tilesFound, g.tilesNeeded);
  if (online == 0) return '$head ${l.routingCoverageOffline}';
  final rest = g.onlineCapped
      ? l.routingCoverageCapped(online, kOnlineFillMaxTiles)
      : g.onlineBroken
          ? l.routingCoverageBroken(online)
          : l.routingCoverageOutside(online);
  return '$head $rest';
}

/// Ein Provider, damit die Blätter [loadPlanningGraph] mit IHREM `ref`
/// rufen können (`WidgetRef` ist kein `Ref`) und Tests die Naht haben.
final planningGraphLoaderProvider = Provider<Future<PlanningGraph> Function(LatBox box, {bool fillOnline})>(
    (ref) => (box, {fillOnline = true}) => loadPlanningGraph(ref, box, fillOnline: fillOnline));
