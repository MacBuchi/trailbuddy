// Ein Wegenetz in Grad als z13-Kacheln, wie das Archiv sie trägt — die
// Eingabe für den Rechen-Isolate des Planers (#356 PR 8, `GraphInput`):
// Der Bau dekodiert drüben, also brauchen Runner-Test und Messskript
// echte Kachel-Bytes statt fertiger `WayLine`s. Kodiert mit `mvtTile`
// (`fake_tiles.dart`), geschnitten je Kachel mit demselben `clipToTile`,
// das der Bau beim Lesen anwendet; die Höhen als 49 × 49-Raster je
// Kachel aus einer Funktion.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart' show RoadTileBytes;
import 'package:trailbuddy/features/routing/route_profile.dart';

import 'fake_tiles.dart';

const _z = kRoadGraphZoom;
const _n = 1 << _z;

/// Kachelkoordinaten (Spalte, Zeile mit Bruch) eines Punkts bei z13.
math.Point<double> _tileXy(LatLng p) {
  final xf = (p.longitude + 180) / 360 * _n;
  final lat = p.latitude * math.pi / 180;
  final yf = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * _n;
  return math.Point(xf, yf);
}

/// Der Punkt zu Kachelkoordinaten — die Umkehrung von [_tileXy].
LatLng tileLatLng(double xf, double yf) {
  final lon = xf / _n * 360 - 180;
  final lat = math.atan(_sinh(math.pi * (1 - 2 * yf / _n))) * 180 / math.pi;
  return LatLng(lat, lon);
}

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

/// Wie Protomaps eine Klasse schreibt (`kind`, `kind_detail`) — die
/// Umkehrung von `classifyWay`.
(String, String?) _kindOf(WayClass cls) => switch (cls) {
      WayClass.bundesstrasse => ('major_road', 'primary'),
      WayClass.hauptstrasse => ('major_road', 'secondary'),
      WayClass.landstrasse => ('medium_road', null),
      WayClass.nebenstrasse => ('minor_road', 'residential'),
      WayClass.zufahrt => ('minor_road', 'service'),
      WayClass.forstweg => ('path', 'track'),
      WayClass.radweg => ('path', 'cycleway'),
      WayClass.wanderweg => ('path', 'path'),
      WayClass.fussweg => ('path', 'footway'),
      WayClass.stufen => ('path', 'steps'),
    };

/// Kodiert [lines] als z13-Kacheln über ihrem Rahmen: je Kachel die
/// Stücke, die in ihr liegen, in Kachel-Pixeln.
List<RoadTileBytes> roadTilesOf(List<WayLine> lines) {
  final box = LatBox.of([for (final l in lines) ...l.points]);
  final tiles = tilesCovering(
    AreaBounds(south: box.s, west: box.w, north: box.n, east: box.e),
    minZoom: _z,
    maxZoom: _z,
  );
  final out = <RoadTileBytes>[];
  for (final t in tiles) {
    final roads = <RoadLine>[];
    for (final l in lines) {
      final px = [
        for (final p in l.points)
          () {
            final xy = _tileXy(p);
            return math.Point((xy.x - t.x) * kTileExtent, (xy.y - t.y) * kTileExtent);
          }(),
      ];
      final (kind, detail) = _kindOf(l.cls);
      for (final piece in clipToTile(px, kTileExtent.toDouble())) {
        roads.add(road(
          [for (final p in piece) (p.x.round(), p.y.round())],
          kind,
          kindDetail: detail,
          extra: {
            if (l.oneway) 'oneway': true,
            if (l.level > 0) 'is_bridge': true,
            if (l.level < 0) 'is_tunnel': true,
          },
        ));
      }
    }
    if (roads.isNotEmpty) out.add((tile: t, bytes: mvtTile(roads)));
  }
  return out;
}

/// Höhenkacheln über [tiles] aus [height] (Meter am Punkt), abgetastet
/// bei den Kachelbrüchen i/48 wie das Werkzeug.
HeightTiles heightTilesOf(Iterable<TileXYZ> tiles, double Function(LatLng p) height) {
  final out = <int, HeightTile>{};
  for (final t in tiles) {
    final values = Int16List(kHeightGrid * kHeightGrid);
    for (var row = 0; row < kHeightGrid; row++) {
      for (var col = 0; col < kHeightGrid; col++) {
        final p = tileLatLng(t.x + col / (kHeightGrid - 1), t.y + row / (kHeightGrid - 1));
        values[row * kHeightGrid + col] = height(p).round();
      }
    }
    out[HeightTiles.keyOf(t.x, t.y)] = HeightTile(values);
  }
  return HeightTiles(out);
}
