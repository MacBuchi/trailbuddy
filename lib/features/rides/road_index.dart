// Die Wege-Ebene für das Zerlege-Blatt (#29, Konzept Offline-Karten
// 3.5): Fahr- und Forststraßen aus den gespeicherten Kacheln, als Gitter
// für „liegt dieser Punkt an einer Straße?". Ein Fahrtabschnitt, der zu
// mehr als 70 % weiter als 15 m von all dem entfernt liegt, ist
// Singletrail oder Wiese — die eine Zutat der Kandidaten-Heuristik, die
// nicht aus der Fahrt selbst kommt.
//
// Gelesen wird NUR aus gespeicherten Bereichen, nie vom Host: Das Blatt
// geht nach der Fahrt auf, oft im Funkloch, und ein Bereich bis Zoom 13
// trägt die Wege vollständig (Messung in Konzept 7). Liegt keiner für
// die Fahrt vor, kennt die App die Wege nicht, sagt das, und bietet nur
// an, was ohne sie geht (Betreiber, 2026-09-28: keine Gefälle-allein-
// Regel als Zwischenlösung).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' show TileIdentity, ProviderException;
import 'package:vector_tile/vector_tile.dart';

import '../../core/line_geometry.dart';
import '../map/pmtiles_tile_provider.dart';
import '../offline_areas/area_plan.dart';
import '../offline_areas/area_store.dart';

/// Die Zoomstufe, aus der die Wege gelesen werden. Forstwege stehen ab
/// z12 in den Kacheln, Pfade und Fußwege ab z13 — darunter fehlten die
/// Wege, an denen sich ein Trail gerade NICHT messen soll. Ein Bereich
/// mit weniger Zoom zählt für die Wege nicht.
const kRoadTileZoom = 13;

/// So nah an einer Straße heißt „auf der Straße" — derselbe Korridor wie
/// beim Abgleich, aus demselben Grund: Ein GPS-Punkt liegt so weit neben
/// dem Weg, den er meint.
const kRoadCorridorM = kMatchCorridorM;

/// Was eine Straße ist: alle Fahrstraßen der Protomaps-Ebene `roads`
/// (`highway`, `major_road`, `medium_road`, `minor_road` — Letztere
/// tragen auch `service`) plus `other` (Zufahrten, Rennstrecken) und
/// von den Pfaden nur der Forstweg (`kind == path` mit
/// `kind_detail == track`). Fußwege, Pfade, Steige, Radwege bleiben
/// draußen — die SIND die Kandidaten. Schienen und Fähren ebenso: Wer
/// neben einem Gleis fährt, fährt keinen Forstweg.
const kRoadKinds = {'highway', 'major_road', 'medium_road', 'minor_road', 'other'};

bool isRoadFeature({required String? kind, required String? kindDetail}) =>
    kind != null && (kRoadKinds.contains(kind) || (kind == 'path' && kindDetail == 'track'));

/// Die Straßen einer Kachel als Linien in Grad. Eine Kachel, die sich
/// nicht lesen lässt, liefert keine Linien — der Aufrufer zählt sie als
/// fehlend, nicht als straßenfrei.
List<List<LatLng>> roadLinesFromTile(Uint8List mvt, {required int z, required int x, required int y}) {
  final VectorTile tile;
  try {
    tile = VectorTile.fromBytes(bytes: mvt);
  } catch (_) {
    return const [];
  }
  final n = 1 << z;
  final out = <List<LatLng>>[];
  for (final layer in tile.layers) {
    if (layer.name != 'roads') continue;
    final extent = layer.extent.toDouble();
    for (final f in layer.features) {
      if (f.type != VectorTileGeomType.LINESTRING) continue;
      final props = f.decodeProperties();
      if (!isRoadFeature(
          kind: props['kind']?.dartStringValue, kindDetail: props['kind_detail']?.dartStringValue)) {
        continue;
      }
      for (final line in f.decodeLineString()) {
        if (line.length < 2) continue;
        out.add([
          for (final p in line) _tileToLatLng(x + p[0] / extent, y + p[1] / extent, n),
        ]);
      }
    }
  }
  return out;
}

LatLng _tileToLatLng(double tx, double ty, int n) {
  final lon = tx / n * 360 - 180;
  final latRad = math.atan(_sinh(math.pi * (1 - 2 * ty / n)));
  return LatLng(latRad * 180 / math.pi, lon);
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

/// Die Straßen um eine Fahrt, als Gitter in derselben Projektion wie die
/// Fahrt selbst — sonst wären „15 m" zwei verschiedene Längen.
class RoadIndex {
  RoadIndex(Iterable<List<LatLng>> lines, this.projection)
      : _grid = SegmentGrid([for (final l in lines) projection.line(l)], kRoadCorridorM);

  final FlatProjection projection;
  final SegmentGrid _grid;

  bool get isEmpty => _grid.isEmpty;

  bool nearRoad(math.Point<double> xy) => _grid.within(xy, kRoadCorridorM);
}

/// Je Quelle ([key]) der erste Bereich — ohne [key] alle.
List<StoredArea> distinctSources(List<StoredArea> areas, String Function(StoredArea area)? key) {
  if (key == null) return areas;
  final seen = <String>{};
  return [for (final a in areas) if (seen.add(key(a))) a];
}

/// Wie gut die gespeicherten Bereiche die Fahrt decken.
enum RoadCoverage {
  /// Jede Kachel der Fahrt liegt in einem Bereich: Die Wege sind bekannt.
  complete,

  /// Ein Teil fehlt: Die Wege sind NICHT bekannt — ein Kandidat, der
  /// halb im Bekannten liegt, wäre eine halbe Aussage.
  partial,

  /// Kein Bereich trägt eine Kachel der Fahrt.
  none,
}

typedef RoadLoadResult = ({RoadIndex? index, RoadCoverage coverage, int tilesNeeded, int tilesFound});

/// Liest die Straßen aller z13-Kacheln, die [box] (plus Korridor) berührt,
/// aus den Bereichen, die sie tragen. [open] liefert je Bereich die
/// Kachelquelle (die Naht der Bereichs-Provider); geschlossen wird hier.
/// [sourceKey] sagt, welche Bereiche DIESELBE Quelle haben (seit #229 die
/// Region: ein Kachelspeicher für alle ihre Bereiche) — die wird dann nur
/// einmal gefragt.
Future<RoadLoadResult> loadRoads({
  required List<StoredArea> areas,
  required LatBox box,
  required Future<ClosableVectorTileProvider?> Function(StoredArea area) open,
  required FlatProjection projection,
  String Function(StoredArea area)? sourceKey,
}) async {
  final margin = kRoadCorridorM / 111320.0;
  final bounds = AreaBounds(
    south: box.s - margin,
    west: box.w - margin * 2,
    north: box.n + margin,
    east: box.e + margin * 2,
  );
  final tiles = tilesCovering(bounds, minZoom: kRoadTileZoom, maxZoom: kRoadTileZoom);
  final candidates = distinctSources([
    for (final a in areas)
      if (a.maxZoom >= kRoadTileZoom && a.bounds.intersects(bounds)) a,
  ], sourceKey);
  if (candidates.isEmpty || tiles.isEmpty) {
    return (index: null, coverage: RoadCoverage.none, tilesNeeded: tiles.length, tilesFound: 0);
  }
  final opened = <ClosableVectorTileProvider>[];
  final lines = <List<LatLng>>[];
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
      for (final p in opened) {
        try {
          final bytes = await p.provide(TileIdentity(t.z, t.x, t.y));
          lines.addAll(roadLinesFromTile(bytes, z: t.z, x: t.x, y: t.y));
          found++;
          break;
        } on ProviderException {
          continue;
        }
      }
    }
  } finally {
    for (final p in opened) {
      await p.close();
    }
  }
  final coverage = found == 0
      ? RoadCoverage.none
      : found == tiles.length
          ? RoadCoverage.complete
          : RoadCoverage.partial;
  return (
    index: coverage == RoadCoverage.complete ? RoadIndex(lines, projection) : null,
    coverage: coverage,
    tilesNeeded: tiles.length,
    tilesFound: found,
  );
}
