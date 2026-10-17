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
//
// Seit #356 PR 8 in zwei Hälften: [readRoadTiles] liest nur BYTES (das
// darf der UI-Isolate, er hat den Kachelspeicher und das Netz),
// [buildRoadGraphFrom] dekodiert und baut — rein, synchron, und deshalb
// im Rechen-Isolate des Planers (`graph_input.dart`). [loadRoadGraph] ist
// beides hintereinander, im aufrufenden Isolate — seit PR 9 nur noch für
// die Tests; die Kalibrierung liest mit [readRoadTiles] die Kacheln
// eines Korridors ([tilesAlong]) und baut im Isolate.
// Eine Grenze VOR dem Lesen ([kPlanMaxTiles]): Ein Rahmen über so viele
// Kacheln öffnet kein Archiv und sagt „zu groß" (Konzept-Routing 10.6).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' show ProviderException, TileIdentity;

import '../../core/line_geometry.dart';
import '../../core/stall_watch.dart';
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

/// Über so viele z13-Kacheln rechnet der Planer nicht (#356 PR 8,
/// Konzept-Routing 10.6): Der Rahmen wird VOR dem Lesen gezählt, und
/// darüber sagt das Blatt „Gebiet zu groß" mit dem Rat (Radius kleiner,
/// weit entfernte Trails abwählen), ohne eine Kachel geöffnet zu haben.
/// Bei 47° N ist eine Kachel rund 3,3 × 3,3 km; 300 Kacheln sind
/// ~55 × 55 km, ein 30-km-Radius mit Trails an beiden Rändern.
///
/// VORLÄUFIG: Der Wert soll aus der Messung am Pixel kommen (Szenarien 2
/// und 4 in `docs/routing-messung.md` — die Kachelzahl, bei der der Bau
/// noch unter 5 s bleibt); bis dahin steht hier die Zahl vom Rechner.
const kPlanMaxTiles = 300;

/// Holt eine Kachel vom Host, die kein Bereich hat: die entpackten Bytes,
/// null, wenn der Host sie nicht hat (außerhalb DACH). Wirft bei einem
/// Netzfehler — danach fragt der Lader nicht weiter.
typedef OnlineTileFetcher = Future<Uint8List?> Function(TileXYZ tile);

/// Die Bytes einer Kachel, wie sie der Bau dekodiert (Wege oder
/// Wege-Archiv) — sendbar an einen Isolate.
typedef RoadTileBytes = ({TileXYZ tile, Uint8List bytes});

/// Was [readRoadTiles] gelesen hat: nur Bytes und Zahlen, nichts
/// Dekodiertes — das macht [buildRoadGraphFrom], wo auch immer.
class RoadTilesRead {
  const RoadTilesRead({
    required this.tilesNeeded,
    required this.roads,
    this.ways = const [],
    this.tilesOnline = 0,
    this.onlineCapped = false,
    this.onlineBroken = false,
    this.tooLarge = false,
  });

  /// Alle Kacheln des Rahmens (mit Rand).
  final int tilesNeeded;

  /// Die gefundenen Wege-Kacheln, aus den Bereichen und vom Host.
  final List<RoadTileBytes> roads;

  /// Die Kacheln des Wege-Archivs (#213) dazu — Lücken erlaubt.
  final List<RoadTileBytes> ways;

  /// Davon vom Host nachgeladen (#187) — in [tilesFound] mitgezählt.
  final int tilesOnline;

  /// Es fehlten mehr Kacheln, als eine Planung online holt.
  final bool onlineCapped;

  /// Das Nachladen brach ab (Netz weg, Frist um).
  final bool onlineBroken;

  /// Über [kPlanMaxTiles]: nichts gelesen.
  final bool tooLarge;

  int get tilesFound => roads.length;

  RoadCoverage get coverage => tilesFound == 0
      ? RoadCoverage.none
      : tilesFound < tilesNeeded
          ? RoadCoverage.partial
          : RoadCoverage.complete;

  /// Die gefundenen Kacheln als Höhenkacheln (gleicher Zoom, gleiche
  /// Nummern) — für [HeightTiles.read].
  Iterable<({int x, int y})> get heightTiles => [for (final r in roads) (x: r.tile.x, y: r.tile.y)];
}

/// Der Rahmen in Grad, mit [marginM] Metern Rand — EINE Rechnung für
/// Lader und Zähler.
AreaBounds roadGraphBounds(LatBox box, double marginM) {
  final dLat = marginM / 111320.0;
  return AreaBounds(
    south: box.s - dLat,
    west: box.w - dLat * 2,
    north: box.n + dLat,
    east: box.e + dLat * 2,
  );
}

/// Liest die Bytes aller z13-Kacheln, die [box] (mit [marginM] Rand)
/// berührt, aus [areas] — und, wo keiner sie hat, über [fetchOnline] vom
/// Host (die nächsten zur Mitte zuerst, höchstens [maxOnline]). Dazu die
/// Kacheln des Wege-Archivs über [openWays] und [fetchWaysOnline] (nur
/// für die nachgeladenen). Dekodiert NICHTS.
///
/// Mehr als [maxTiles] Kacheln im Rahmen: [RoadTilesRead.tooLarge], ohne
/// ein Archiv geöffnet zu haben. Null heißt keine Grenze.
///
/// Mit [only] werden aus dem Rahmen nur diese Kacheln gelesen (#356 PR 9,
/// die Kalibrierung: der Korridor einer Fahrt, [tilesAlong]) — die
/// Zählung und die Grenze gelten dann für sie.
Future<RoadTilesRead> readRoadTiles({
  required List<StoredArea> areas,
  required LatBox box,
  required Future<ClosableVectorTileProvider?> Function(StoredArea area) open,
  double marginM = 0,
  OnlineTileFetcher? fetchOnline,
  int maxOnline = kOnlineFillMaxTiles,
  Future<ClosableVectorTileProvider?> Function(StoredArea area)? openWays,
  OnlineTileFetcher? fetchWaysOnline,
  String Function(StoredArea area)? sourceKey,
  int? maxTiles,
  Set<(int, int)>? only,
}) async {
  final bounds = roadGraphBounds(box, marginM);
  final tiles = [
    for (final t in tilesCovering(bounds, minZoom: kRoadGraphZoom, maxZoom: kRoadGraphZoom))
      if (only == null || only.contains((t.x, t.y))) t,
  ];
  if (maxTiles != null && tiles.length > maxTiles) {
    return RoadTilesRead(tilesNeeded: tiles.length, roads: const [], tooLarge: true);
  }
  // Seit #229 haben alle Bereiche einer Region EINE Quelle ([sourceKey]).
  final inBox = [
    for (final a in areas)
      if (a.maxZoom >= kRoadGraphZoom && a.bounds.intersects(bounds)) a,
  ];
  final candidates = distinctSources(inBox, sourceKey);
  if ((candidates.isEmpty && fetchOnline == null) || tiles.isEmpty) {
    return RoadTilesRead(tilesNeeded: tiles.length, roads: const []);
  }
  final opened = <ClosableVectorTileProvider>[];
  final roads = <RoadTileBytes>[];
  final missing = <TileXYZ>[];
  final fromHost = <TileXYZ>[];
  var online = 0;
  var capped = false;
  var broken = false;
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
          roads.add((tile: t, bytes: bytes));
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
      roads.add((tile: t, bytes: bytes));
      online++;
      fromHost.add(t);
    }
  }
  final ways = roads.isEmpty || (openWays == null && fetchWaysOnline == null)
      ? const <RoadTileBytes>[]
      : await _wayTiles(
          tiles: tiles,
          areas: distinctSources([
            for (final a in inBox)
              if (a.hasWays) a,
          ], sourceKey),
          openWays: openWays,
          fromHost: fromHost,
          fetchWaysOnline: fetchWaysOnline,
        );
  return RoadTilesRead(
    tilesNeeded: tiles.length,
    roads: roads,
    ways: ways,
    tilesOnline: online,
    onlineCapped: capped,
    onlineBroken: broken,
  );
}

/// Was [buildRoadGraphFrom] gebaut hat.
typedef RoadGraphBuilt = ({RoadGraph graph, int joins, int crossings, int edgesWithoutHeights});

/// Dekodiert [roads] und baut den Graphen (Zuschnitt, tote Enden,
/// Kreuzungen — [buildRoadGraph]), liest die Steigungen aus [heights]
/// (null: alle Kanten flach) und die Güte aus [ways] ([addWayQuality]).
/// Rein und synchron: läuft im Rechen-Isolate (#356 PR 8).
RoadGraphBuilt buildRoadGraphFrom({
  required List<RoadTileBytes> roads,
  List<RoadTileBytes> ways = const [],
  HeightTiles? heights,
  required double lat0,
}) {
  final lines = <WayLine>[];
  StallWatch.mark('graph.decode', () {
    for (final r in roads) {
      lines.addAll(wayLinesFromTile(r.bytes, z: r.tile.z, x: r.tile.x, y: r.tile.y));
    }
  });
  final build = buildRoadGraph(lines, lat0: lat0);
  if (heights != null) StallWatch.mark('graph.climbs', () => addClimbsFrom(build.graph, heights));
  if (ways.isNotEmpty) {
    final grades = <WayGradeLine>[];
    for (final w in ways) {
      grades.addAll(wayGradeLinesFromTile(w.bytes, z: w.tile.z, x: w.tile.x, y: w.tile.y));
    }
    StallWatch.mark('graph.wayQuality', () => addWayQuality(build.graph, grades));
  }
  return (
    graph: build.graph,
    joins: build.joins,
    crossings: build.crossings,
    edgesWithoutHeights: heights == null ? build.graph.edges.length : build.graph.edgesWithoutHeights,
  );
}

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
///
/// Seit #356 PR 8 [readRoadTiles] + [HeightTiles.read] + [buildRoadGraphFrom]
/// hintereinander, im AUFRUFENDEN Isolate — der Planer nimmt die Hälften
/// einzeln (`planning_graph.dart`), damit der Bau drüben läuft.
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
  final read = await readRoadTiles(
    areas: areas,
    box: box,
    open: open,
    marginM: marginM,
    fetchOnline: fetchOnline,
    maxOnline: maxOnline,
    openWays: openWays,
    fetchWaysOnline: fetchWaysOnline,
    sourceKey: sourceKey,
  );
  RoadGraphLoadResult none(RoadCoverage c) => (
        graph: null,
        coverage: c,
        tilesNeeded: read.tilesNeeded,
        tilesFound: read.tilesFound,
        joins: 0,
        crossings: 0,
        edgesWithoutHeights: 0,
        tilesOnline: read.tilesOnline,
        onlineCapped: read.onlineCapped,
        onlineBroken: read.onlineBroken,
      );
  if (read.tilesFound == 0) return none(RoadCoverage.none);
  if (read.coverage == RoadCoverage.partial && requireComplete) return none(RoadCoverage.partial);
  final tiles = heights == null ? null : await HeightTiles.read(heights, read.heightTiles);
  final built = buildRoadGraphFrom(roads: read.roads, ways: read.ways, heights: tiles, lat0: (box.s + box.n) / 2);
  return (
    graph: built.graph,
    coverage: read.coverage,
    tilesNeeded: read.tilesNeeded,
    tilesFound: read.tilesFound,
    joins: built.joins,
    crossings: built.crossings,
    edgesWithoutHeights: built.edgesWithoutHeights,
    tilesOnline: read.tilesOnline,
    onlineCapped: read.onlineCapped,
    onlineBroken: read.onlineBroken,
  );
}

/// Die Kacheln des Wege-Archivs über [tiles]: aus den Bereichen, die es
/// tragen, für die vom Host nachgeladenen Kacheln ([fromHost]) vom Host.
/// Ein Fehler kostet nur die Güte, nie den Graphen.
Future<List<RoadTileBytes>> _wayTiles({
  required List<TileXYZ> tiles,
  required List<StoredArea> areas,
  required Future<ClosableVectorTileProvider?> Function(StoredArea area)? openWays,
  required List<TileXYZ> fromHost,
  required OnlineTileFetcher? fetchWaysOnline,
}) async {
  final out = <RoadTileBytes>[];
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
            out.add((tile: t, bytes: await p.provide(TileIdentity(t.z, t.x, t.y))));
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
        if (bytes != null) out.add((tile: t, bytes: bytes));
      } catch (_) {
        break; // Netz weg: Was da ist, reicht; der Rest bleibt unbekannt.
      }
    }
  }
  return out;
}

/// Die z13-Kacheln, die eine Linie mit [marginM] Rand berührt — als
/// `(x, y)` für [readRoadTiles] `only` (#356 PR 9). Eine Fahrt von 40 km
/// quer durchs Tal spannt einen Rahmen von hundert Kacheln auf und fährt
/// durch zwanzig; die Kalibrierung ordnet nur ein, was unter der Linie
/// liegt. Zwischen zwei Punkten, die weiter als eine halbe Kachel
/// auseinanderliegen, wird die Strecke abgetastet (ein Loch im GPS
/// überspränge sonst eine Kachel).
Set<(int, int)> tilesAlong(List<LatLng> points, double marginM) {
  final out = <(int, int)>{};
  if (points.isEmpty) return out;
  final dLat = marginM / 111320.0;
  void add(LatLng p) {
    final dLon = dLat / math.cos(p.latitude * math.pi / 180);
    final a = tileAt(p.latitude + dLat, p.longitude - dLon, kRoadGraphZoom);
    final b = tileAt(p.latitude - dLat, p.longitude + dLon, kRoadGraphZoom);
    for (var x = a.x; x <= b.x; x++) {
      for (var y = a.y; y <= b.y; y++) {
        out.add((x, y));
      }
    }
  }

  // Eine halbe z13-Kachel in Grad Breite (am Äquator 360 / 8192 / 2).
  const halfTileDeg = 360.0 / (1 << kRoadGraphZoom) / 2;
  add(points.first);
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    final span = math.max((b.latitude - a.latitude).abs(), (b.longitude - a.longitude).abs());
    final steps = (span / halfTileDeg).ceil();
    for (var k = 1; k < steps; k++) {
      final t = k / steps;
      add(LatLng(a.latitude + t * (b.latitude - a.latitude), a.longitude + t * (b.longitude - a.longitude)));
    }
    add(b);
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
