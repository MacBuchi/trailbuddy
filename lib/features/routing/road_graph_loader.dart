// Der Wegegraph aus den gespeicherten Bereichen (Konzept-Routing 2.7):
// alle z13-Kacheln, die ein Rahmen berührt, aus den Bereichen, die sie
// tragen — derselbe Weg wie `loadRoads` für das Zerlege-Blatt, mit
// derselben Ehrlichkeit: `partial` heißt „nicht planbar", nicht „ein
// halber Plan". Danach die Höhen je Kante aus den Höhenkacheln der
// Bereiche (`HeightReader`); Kanten ohne Höhe bleiben flach und werden
// gezählt.
//
// Seit 0.78.0 (#187) kann der Aufrufer eine LETZTE Quelle mitgeben: das
// Online-Archiv des Kartenhosts. Gefragt wird es nur nach Kacheln, die
// kein Bereich hat, die nächsten zur Mitte zuerst, höchstens
// [kOnlineFillMaxTiles] je Planung — jede Kachel ist eine Range-Anfrage
// und damit eine R2-Class-B-Operation (#55).
import 'dart:typed_data';

import 'package:vector_map_tiles/vector_map_tiles.dart' show ProviderException, TileIdentity;

import '../../core/line_geometry.dart';
import '../map/pmtiles_tile_provider.dart';
import '../offline_areas/area_plan.dart';
import '../offline_areas/area_store.dart';
import '../offline_areas/height_tiles.dart';
import '../rides/road_index.dart' show RoadCoverage, distinctSources;
import 'road_graph.dart';

typedef RoadGraphLoadResult = ({
  RoadGraph? graph,
  RoadCoverage coverage,
  int tilesNeeded,
  int tilesFound,
  int joins,
  int crossings,
  int edgesWithoutHeights,
  int tilesOnline,
  bool onlineCapped,
  bool onlineBroken,
});

/// Höchstens so viele z13-Kacheln holt eine Planung vom Host (#187), je
/// Kachel dazu höchstens ihre Höhenkachel und ihre Wege-Kachel (#213) —
/// also höchstens dreimal so viele Range-Anfragen. 75 Kacheln sind bei 47° N rund 25 × 25 km, mehr
/// als der Rahmen einer Runde mit 12 km Reichweite meist braucht.
const kOnlineFillMaxTiles = 75;

/// Holt eine Kachel vom Host, die kein Bereich hat: die entpackten Bytes,
/// null, wenn der Host sie nicht hat (außerhalb DACH). Wirft bei einem
/// Netzfehler — danach fragt der Lader nicht weiter.
typedef OnlineTileFetcher = Future<Uint8List?> Function(TileXYZ tile);

/// Baut den Graphen für [box] (in Grad, mit einem Rand von
/// [marginM] Metern) aus [areas]. [open] liefert je Bereich die
/// Kachelquelle, [heights] die Höhen — null heißt: alle Kanten flach.
/// Mit [requireComplete] false kommt auch bei `partial` ein Graph aus
/// den gefundenen Kacheln — für die Kalibrierung (Schritt 6), die eine
/// Fahrt nur EINORDNET (welche Wegklasse liegt unter dem Aufstieg) und
/// nichts plant; ein Abschnitt in einer fehlenden Kachel ist dann
/// „abseits" und zählt nicht. Seit 0.74.0 plant auch die Planung so
/// (`planning_graph.dart`) und sagt es.
///
/// [fetchOnline] ist die letzte Quelle für Kacheln, die kein Bereich hat
/// (#187): die nächsten zur Mitte von [box] zuerst, höchstens
/// [maxOnline]; wirft sie, bleibt es bei dem, was schon da ist.
///
/// Seit #213 bekommen Forstwege und Wanderwege ihre Güte aus dem
/// Wege-Archiv ([addWayQuality]): [openWays] öffnet das Archiv eines
/// Bereichs (null ohne), [fetchWaysOnline] ist wieder die letzte Quelle,
/// gefragt nur für Kacheln, die schon online nachgeladen wurden — ohne
/// beides bleibt jede Güte unbekannt und kostet, was sie immer kostete.
/// Das Archiv hat Lücken (nur Kacheln mit getaggten Wegen): Eine fehlende
/// Kachel heißt „nichts bekannt", nicht „Fehler".
Future<RoadGraphLoadResult> loadRoadGraph({
  required List<StoredArea> areas,
  required LatBox box,
  required Future<ClosableVectorTileProvider?> Function(StoredArea area) open,
  HeightReader? heights,
  double marginM = 0,
  bool requireComplete = true,
  OnlineTileFetcher? fetchOnline,
  int maxOnline = kOnlineFillMaxTiles,
  Future<ClosableVectorTileProvider?> Function(StoredArea area)? openWays,
  OnlineTileFetcher? fetchWaysOnline,
  String Function(StoredArea area)? sourceKey,
}) async {
  final dLat = marginM / 111320.0;
  final bounds = AreaBounds(
    south: box.s - dLat,
    west: box.w - dLat * 2,
    north: box.n + dLat,
    east: box.e + dLat * 2,
  );
  final tiles = tilesCovering(bounds, minZoom: kRoadGraphZoom, maxZoom: kRoadGraphZoom);
  // Seit #229 haben alle Bereiche einer Region EINE Quelle ([sourceKey]).
  final inBox = [
    for (final a in areas)
      if (a.maxZoom >= kRoadGraphZoom && a.bounds.intersects(bounds)) a,
  ];
  final candidates = distinctSources(inBox, sourceKey);
  var online = 0;
  var capped = false;
  var broken = false;
  RoadGraphLoadResult none(RoadCoverage c, int found) => (
        graph: null,
        coverage: c,
        tilesNeeded: tiles.length,
        tilesFound: found,
        joins: 0,
        crossings: 0,
        edgesWithoutHeights: 0,
        tilesOnline: online,
        onlineCapped: capped,
        onlineBroken: broken,
      );
  if ((candidates.isEmpty && fetchOnline == null) || tiles.isEmpty) return none(RoadCoverage.none, 0);
  final opened = <ClosableVectorTileProvider>[];
  final lines = <WayLine>[];
  final missing = <TileXYZ>[];
  final fromHost = <TileXYZ>[];
  var found = 0;
  try {
    for (final a in candidates) {
      try {
        final p = await open(a);
        if (p != null) opened.add(p);
      } catch (_) {
        // Ein Bereich, der nicht aufgeht, trägt keine Kacheln bei; die
        // Zählung unten sagt dann „nicht gedeckt".
      }
    }
    for (final t in tiles) {
      var hit = false;
      for (final p in opened) {
        try {
          final bytes = await p.provide(TileIdentity(t.z, t.x, t.y));
          lines.addAll(wayLinesFromTile(bytes, z: t.z, x: t.x, y: t.y));
          found++;
          hit = true;
          break;
        } on ProviderException {
          continue;
        }
      }
      if (!hit) missing.add(t);
    }
  } finally {
    for (final p in opened) {
      await p.close();
    }
  }
  if (fetchOnline != null && missing.isNotEmpty) {
    missing.sort((a, b) => _distanceToCenter(a, box).compareTo(_distanceToCenter(b, box)));
    capped = missing.length > maxOnline;
    for (final t in missing.take(maxOnline)) {
      final Uint8List? bytes;
      try {
        bytes = await fetchOnline(t);
      } catch (_) {
        // Netz weg oder Host stumm: Was schon da ist, reicht für einen
        // Plan, und das Blatt sagt, über wie viele Kacheln.
        broken = true;
        break;
      }
      if (bytes == null) continue;
      lines.addAll(wayLinesFromTile(bytes, z: t.z, x: t.x, y: t.y));
      found++;
      online++;
      fromHost.add(t);
    }
  }
  if (found == 0) return none(RoadCoverage.none, 0);
  final partial = found < tiles.length;
  if (partial && requireComplete) return none(RoadCoverage.partial, found);
  final build = buildRoadGraph(lines, lat0: (box.s + box.n) / 2);
  if (heights != null) await addClimbs(build.graph, heights);
  if (openWays != null || fetchWaysOnline != null) {
    final grades = await _wayGrades(
      tiles: tiles,
      areas: distinctSources([
        for (final a in inBox)
          if (a.hasWays) a,
      ], sourceKey),
      openWays: openWays,
      fromHost: fromHost,
      fetchWaysOnline: fetchWaysOnline,
    );
    addWayQuality(build.graph, grades);
  }
  return (
    graph: build.graph,
    coverage: partial ? RoadCoverage.partial : RoadCoverage.complete,
    tilesNeeded: tiles.length,
    tilesFound: found,
    joins: build.joins,
    crossings: build.crossings,
    edgesWithoutHeights: heights == null ? build.graph.edges.length : build.graph.edgesWithoutHeights,
    tilesOnline: online,
    onlineCapped: capped,
    onlineBroken: broken,
  );
}

/// Die Linien des Wege-Archivs über [tiles]: aus den Bereichen, die es
/// tragen, für die vom Host nachgeladenen Kacheln ([fromHost]) vom Host.
/// Ein Fehler kostet nur die Güte, nie den Graphen.
Future<List<WayGradeLine>> _wayGrades({
  required List<TileXYZ> tiles,
  required List<StoredArea> areas,
  required Future<ClosableVectorTileProvider?> Function(StoredArea area)? openWays,
  required List<TileXYZ> fromHost,
  required OnlineTileFetcher? fetchWaysOnline,
}) async {
  final out = <WayGradeLine>[];
  final opened = <ClosableVectorTileProvider>[];
  try {
    if (openWays != null) {
      for (final a in areas) {
        try {
          final p = await openWays(a);
          if (p != null) opened.add(p);
        } catch (_) {
          // Ein Wege-Archiv, das nicht aufgeht: Güte dort unbekannt.
        }
      }
    }
    if (opened.isNotEmpty) {
      for (final t in tiles) {
        for (final p in opened) {
          try {
            final bytes = await p.provide(TileIdentity(t.z, t.x, t.y));
            out.addAll(wayGradeLinesFromTile(bytes, z: t.z, x: t.x, y: t.y));
            break;
          } on ProviderException {
            continue;
          }
        }
      }
    }
  } finally {
    for (final p in opened) {
      await p.close();
    }
  }
  if (fetchWaysOnline != null) {
    for (final t in fromHost) {
      try {
        final bytes = await fetchWaysOnline(t);
        if (bytes != null) out.addAll(wayGradeLinesFromTile(bytes, z: t.z, x: t.x, y: t.y));
      } catch (_) {
        break; // Netz weg: Was da ist, reicht; der Rest bleibt unbekannt.
      }
    }
  }
  return out;
}

/// Abstand zur Kachel in der Mitte des Rahmens, in Kachelbreiten zum
/// Quadrat — genug, um die nächsten zuerst zu holen.
int _distanceToCenter(TileXYZ t, LatBox box) {
  final c = tileAt((box.s + box.n) / 2, (box.w + box.e) / 2, t.z);
  final dx = t.x - c.x, dy = t.y - c.y;
  return dx * dx + dy * dy;
}
