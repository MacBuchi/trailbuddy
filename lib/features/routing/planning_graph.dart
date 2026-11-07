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
//
// **Vorgebackene Stücke** (#380, `routing_pieces.dart`): Vor dem Lesen
// sucht der Lader frische Stücke im Kachelspeicher; deren Kacheln liest er
// nicht, die übrigen backt der Rechen-Isolate, und [PlanningGraph.keep]
// legt die neuen Stücke nach dem Bau ab.
//
// **Was online kam, bleibt** (#478, `kept_tiles.dart`): Nach dem Lesen
// legt der Lader die vom Host geholten Kacheln in den Kachelspeicher der
// Region („Unterwegs geladen"); ihre Stücke backen dorthin. VOR dem Lesen
// holt er behaltene Kacheln aus einem älteren Bau neu, die im Rahmen
// liegen — nur mit Empfang, nur sie, und innerhalb derselben Grenze
// [kOnlineFillMaxTiles]. Eine Zeile `graph.online` nennt die Anfragen je
// Planung (Messung für Schritt 2 des Issues).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../core/stall_watch.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import '../official/official_trails_source.dart';
import '../offline_areas/area_plan.dart' show TileSetShape, kAreaShapeZoom;
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../offline_areas/height_tiles.dart';
import '../offline_areas/kept_tiles.dart';
import '../offline_areas/tile_store.dart';
import '../rides/road_index.dart' show RoadCoverage;
import '../trails/trail_providers.dart';
import 'graph_input.dart';
import 'loop_planner.dart' show graphTrailsOf;
import 'online_fill.dart';
import 'road_graph.dart' show kRoadGraphZoom;
import 'road_graph_loader.dart';
import 'routing_pieces.dart';
import 'routing_tile.dart' show RoutingPiece, pieceBuild;
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
    PieceLookup? pieces,
  }) : _pieces = pieces;

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

  final PieceLookup? _pieces;

  /// Legt die Stücke ab, die der Bau aus [input] gebacken hat (#380) —
  /// nach `LoopPlanRunner.build` zu rufen. Wirft nie.
  Future<void> keep(GraphReport report) async => _pieces?.keep(report);

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
///
/// Mit [only] nur diese Kacheln des Rahmens (der Korridor einer Linie,
/// [tilesAlong]) — die Abzweigungen für die Uhr (#449); Grenze und
/// Zählung gelten dann für sie.
Future<PlanningGraph> loadPlanningGraph(Ref ref, LatBox box,
    {bool fillOnline = true, int? maxTiles = kPlanMaxTiles, Set<(int, int)>? only}) async {
  List<StoredArea> areas;
  try {
    areas = await ref.read(storedAreasProvider.future);
  } catch (_) {
    areas = const [];
  }
  final store = ref.read(areaStoreProvider);
  final tileStore = ref.read(tileStoreProvider);
  // Die Halter „Unterwegs geladen" wie sie JETZT liegen: Die Liste des
  // Providers wird nicht nach jeder Planung neu gelesen (das baute den
  // Kartenstil neu), der Index schon geschrieben.
  try {
    final kept = [for (final a in await store.list()) if (a.kept) a];
    areas = [for (final a in areas) if (!a.kept) a, ...kept];
  } catch (_) {
    // Dann eben der Stand des Providers.
  }
  HeightReader? heights;
  try {
    heights = await ref.read(areaHeightReaderProvider.future);
  } catch (e, s) {
    // Ohne Höhen rechnet die Suche flach und sagt es; der Weg steht trotzdem.
    logError('Höhen für die Planung öffnen', e, s);
  }
  final session = ref.read(routingPieceSessionProvider);
  // Frische Stücke im Kachelspeicher (#380) — nur in einem Rahmen, den
  // der Lader auch liest.
  final frame = [
    for (final t in roadGraphTiles(box, kTrailHeadMarginM))
      if (only == null || only.contains((t.x, t.y))) t,
  ];
  final tooLarge = maxTiles != null && frame.length > maxTiles;
  final online =
      fillOnline && !tooLarge && !ref.read(noConnectivityProvider) ? ref.read(onlineFillFactoryProvider)(box) : null;
  // Wohin Geholtes gehört (#478) — null ohne Manifest oder ohne Naht.
  ({String region, KeptBuilds builds})? keep;
  if (online?.keep case final target?) {
    try {
      keep = await target().timeout(kOnlineFillTimeout);
    } catch (e, s) {
      if (!looksOffline(e)) logError('Ziel für online geholte Kacheln', e, s);
    }
  }
  // Behaltene Kacheln aus einem älteren Bau: genau diese neu (#478).
  var refreshed = 0;
  if (online != null && keep != null) {
    final stale = await staleKeptTiles(
        tiles: tileStore,
        areas: areas,
        region: keep.region,
        frame: frame,
        mapBuild: keep.builds.map,
        max: kOnlineFillMaxTiles);
    for (final t in stale) {
      try {
        if (await online.fetch(t, fresh: true) == null) continue;
        refreshed++;
        await online.fetchWays(t);
      } catch (_) {
        break; // Netz weg: Die alte Kachel gilt.
      }
    }
    if (refreshed > 0) {
      await _keep(ref, keep, online.takeKept(), const [], pieces: null);
      try {
        final kept = [for (final a in await store.list()) if (a.kept) a];
        areas = [for (final a in areas) if (!a.kept) a, ...kept];
      } catch (_) {
        // Der alte Stand trägt; die Kachel liest der Lader trotzdem.
      }
    }
  }
  final regions = <String>{
    for (final a in areas)
      if (a.maxZoom >= kRoadGraphZoom && a.bounds.intersects(roadGraphBounds(box, kTrailHeadMarginM))) a.region,
  };
  final pieces = tooLarge || regions.isEmpty
      ? PieceLookup.none(session)
      : await StallWatch.time('graph.pieces', () => findPieces(tileStore, regions, frame, session));
  final open = ref.read(areaArchiveOpenerProvider);
  final openWays = ref.read(areaWaysOpenerProvider);
  if (online != null) {
    // Die Höhen der nachgeladenen Kacheln kommen als LETZTE Quelle dazu;
    // der Leser der Bereiche gehört seinem Provider und bleibt offen.
    heights = HeightReader([...?heights?.sources, online.heights]);
  }
  RoadTilesRead read;
  HeightTiles? tiles;
  ({List<RoadTileBytes> roads, List<RoutingPiece> pieces})? split;
  try {
    read = await StallWatch.time('graph.load', () => readRoadTiles(
      areas: areas,
      box: box,
      open: (a) => open(store, a),
      marginM: kTrailHeadMarginM,
      fetchOnline: online == null ? null : (t) => online.fetch(t),
      maxOnline: kOnlineFillMaxTiles - refreshed,
      openWays: (a) => openWays(store, a),
      fetchWaysOnline: online?.fetchWays,
      sourceKey: (a) => a.region,
      maxTiles: maxTiles,
      only: only,
      covered: pieces.fresh.keys.toSet(),
    ));
    StallWatch.info('graph.tiles', '${read.tilesFound}/${read.tilesNeeded}');
    // Was online ergänzt war und in dieser Sitzung schon ein Stück hat,
    // wird nicht noch einmal gebacken.
    split = pieces.split(read.roads);
    // Die Höhen der zu backenden Kacheln gleich mit — drüben gibt es
    // weder den Kachelspeicher noch das Netz.
    final bake = split.roads;
    if (bake.isNotEmpty && heights != null) {
      final h = heights;
      tiles = await StallWatch.time(
          'graph.heights', () => HeightTiles.read(h, [for (final r in bake) (x: r.tile.x, y: r.tile.y)]));
    }
    if (online != null) {
      final fetched = online.takeKept();
      StallWatch.info('graph.online',
          'roads=${online.roadRequests} heights=${online.heightRequests} ways=${online.wayRequests} refreshed=$refreshed');
      if (keep != null) {
        await _keep(ref, keep, fetched, [for (final t in frame) TileSetShape.keyOf(t.x, t.y, kAreaShapeZoom)],
            pieces: pieces);
      }
    } else if (!tooLarge) {
      // Ohne Empfang zählt die Nutzung trotzdem: Was man fährt, bleibt.
      final region = areas.where((a) => a.kept && a.bounds.intersects(roadGraphBounds(box, kTrailHeadMarginM)));
      for (final holder in region) {
        await _keep(ref, (region: holder.region, builds: (map: holder.build, heights: null, ways: null)), const [],
            [for (final t in frame) TileSetShape.keyOf(t.x, t.y, kAreaShapeZoom)],
            pieces: null);
      }
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
      roads: split.roads,
      ways: read.ways,
      heights: tiles,
      trails: graphTrailsOf(serviceL10n(), near),
      closures: await officialClosuresIn(ref, box),
      lat0: (box.s + box.n) / 2,
      pieces: [...pieces.fresh.values, ...split.pieces],
      bake: true,
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
    pieces: input == null ? null : pieces,
  );
}

/// Legt [fetched] in den Halter von [target] und merkt [used] als gebraucht
/// (#478); die Stücke der geholten Kacheln gehören danach in den Speicher
/// ([PieceLookup.adopt]). Wirft nie: Ein Fehler lässt die Kacheln bei der
/// Sitzung, wie bis 0.158.
Future<void> _keep(Ref ref, ({String region, KeptBuilds builds}) target, List<KeptFetch> fetched, List<int> used,
    {required PieceLookup? pieces}) async {
  final tiles = ref.read(tileStoreProvider);
  try {
    final r = await keepOnlineTiles(
      areas: ref.read(areaStoreProvider),
      tiles: tiles,
      region: target.region,
      builds: target.builds,
      fetched: fetched,
      used: used,
    );
    pieces?.adopt(tiles, {
      for (final f in fetched)
        (f.x, f.y): (
          region: target.region,
          build: pieceBuild(
            map: target.builds.map,
            heights: f.heights == null ? null : target.builds.heights,
            ways: f.ways == null ? null : target.builds.ways,
          ),
        ),
    });
    if (fetched.isNotEmpty || r.evicted > 0) {
      StallWatch.info('graph.kept', 'kept=${fetched.length} evicted=${r.evicted}');
    }
    // Neu in der Region: Karte und Höhen kennen sie erst nach dem Neulesen.
    if (r.relist) await ref.read(storedAreasProvider.notifier).refresh();
  } catch (e, s) {
    logError('Online geholte Kacheln behalten', e, s);
  }
}

/// Die gesperrten Abschnitte der offiziellen Quelle (#41) in [box] — für
/// [GraphInput.closures] (#434). Nur bei eingeschalteter Ebene: aus heißt
/// keine Anfrage, also auch keine Sperren. Fehlt eine Region auf dem Gerät
/// und kommt sie nicht in [kOfficialClosuresWait], plant der Planer ohne
/// sie — wie die Karte, die sie dann auch nicht zeigt.
Future<List<List<LatLng>>> officialClosuresIn(Ref ref, LatBox box) async {
  if (!ref.read(officialTrailsEnabledProvider)) return const [];
  try {
    await ref
        .read(officialTrailsControllerProvider.notifier)
        .ensure((s: box.s, w: box.w, n: box.n, e: box.e))
        .timeout(kOfficialClosuresWait);
  } catch (e, s) {
    logError('Offizielle Sperren für die Planung', e, s);
  }
  return [
    for (final t in ref.read(officialTrailsControllerProvider).trails)
      for (final sec in t.sections)
        if (sec.closed && LatBox.of(sec.points).near(box, kTrailHeadMarginM)) sec.points,
  ];
}

/// So lange wartet die Planung auf die offiziellen Regionen ihres Rahmens.
const kOfficialClosuresWait = Duration(seconds: 5);

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
