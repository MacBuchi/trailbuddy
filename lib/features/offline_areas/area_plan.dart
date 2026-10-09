// Die Planung eines Bereichs (Konzept 3.2), pur: welche Kacheln eine
// FORM von Zoom [kAreaMinZoom] bis zum Zoom des Archivs berührt, und
// welche Kachel-Ids das im Archiv sind. Die Größe kommt später aus dem
// Verzeichnis des Archivs (jede Kachel nennt dort ihre Bytes) — hier
// wird nur GEZÄHLT, nicht geschätzt.
//
// Zwei Formen ([AreaShape]): ein Rahmen ([RectShape], der Ausschnitt)
// und eine Kachelmenge ([TileSetShape], seit 0.24.0 die Form von „Um
// meine Trails"). Bis 0.23.0 war auch „Um meine Trails" ein Rahmen —
// EIN Rechteck um alle Trails plus Rand, und bei verstreuten Trails
// bestand das vor allem aus Land dazwischen: 40 779 Kacheln beim
// Betreiber, die Obergrenze sind 40 000. Ein Archiv braucht kein
// Rechteck; sein Rahmen im Header ist nur die Hülle.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart' show ZXY;

import '../map/poi.dart' show PoiCell, poiCellsCovering;

/// Unter Zoom 8 liegt die mitgelieferte Übersicht (Zoom 0–7), die hat
/// jedes Gerät. Ein Bereich beginnt darüber.
const kAreaMinZoom = 8;

/// Mehr Kacheln als das speichert die App nicht in EINEM Bereich: Bei
/// Zoom 13 sind das rund 1 000 km × 400 km, weit mehr als ein
/// Wochenende, und die Kachelliste selbst (Nachschlagen jeder Kachel im
/// Verzeichnis) würde spürbar. Wer mehr will, speichert zwei Bereiche.
const kAreaMaxTiles = 40000;

/// Der Rand um einen Rahmen aus Punkten ([AreaBounds.around]); bis
/// 0.23.0 der Rand von „Um meine Trails".
const kAreaTrailsMarginKm = 2.0;

/// Der Korridor entlang der Trails (seit 0.24.0): Eine Kachel gehört
/// dazu, wenn ein Trail ihr näher als so viele Kilometer kommt
/// (Betreiber, 2026-09-28: 1 km statt der 2 km des Rechtecks — gezählt
/// wird ohnehin je Kachel, und die ist bei Zoom 13 rund 3 km breit).
const kAreaTrailsCorridorKm = 1.0;

/// Der Zoom, in dem eine [TileSetShape] ihre Kacheln merkt — fest, damit
/// die Form nicht vom Zoom des Hosts abhängt: Ein höherer Zoom des
/// Archivs sind die Kinder dieser Kacheln, ein niedrigerer die Eltern.
const kAreaShapeZoom = 13;

/// Ein Rahmen in Grad, Süden/Westen/Norden/Osten.
class AreaBounds {
  const AreaBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  /// Um die Punkte, mit [marginKm] Rand. Null ohne Punkte.
  static AreaBounds? around(Iterable<LatLng> points, {double marginKm = kAreaTrailsMarginKm}) {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    var any = false;
    for (final p in points) {
      any = true;
      s = math.min(s, p.latitude);
      n = math.max(n, p.latitude);
      w = math.min(w, p.longitude);
      e = math.max(e, p.longitude);
    }
    if (!any) return null;
    final dLat = marginKm / 111.0;
    final midLat = (s + n) / 2;
    final dLon = marginKm / (111.0 * math.max(0.2, math.cos(midLat * math.pi / 180)));
    return AreaBounds(
      south: math.max(-85.0, s - dLat),
      west: math.max(-180.0, w - dLon),
      north: math.min(85.0, n + dLat),
      east: math.min(180.0, e + dLon),
    );
  }

  bool contains(LatLng p) =>
      p.latitude >= south && p.latitude <= north && p.longitude >= west && p.longitude <= east;

  /// Berührt der Rahmen [other]?
  bool intersects(AreaBounds other) =>
      other.west <= east && other.east >= west && other.south <= north && other.north >= south;

  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);

  Map<String, dynamic> toJson() => {'s': south, 'w': west, 'n': north, 'e': east};

  factory AreaBounds.fromJson(Map<String, dynamic> j) => AreaBounds(
        south: (j['s'] as num).toDouble(),
        west: (j['w'] as num).toDouble(),
        north: (j['n'] as num).toDouble(),
        east: (j['e'] as num).toDouble(),
      );
}

/// Eine Kachel im Web-Mercator-Raster.
typedef TileXYZ = ({int z, int x, int y});

/// Die Breite, an der Web-Mercator endet — eine Konstante mit Namen, damit
/// der Privat-Wächter sie nicht für ein Koordinatenpaar hält.
const _maxMercatorLat = 85.05112878;

/// Spalte und Zeile der Kachel, in der [lon]/[lat] bei Zoom [z] liegt.
({int x, int y}) tileAt(double lat, double lon, int z) {
  final n = 1 << z;
  final x = ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
  final latRad = lat.clamp(-_maxMercatorLat, _maxMercatorLat) * math.pi / 180;
  final y = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n)
      .floor()
      .clamp(0, n - 1);
  return (x: x, y: y);
}

/// Alle Kacheln, die [bounds] von [minZoom] bis [maxZoom] berühren, nach
/// Zoom und Zeile — die Reihenfolge ist egal, der Schreiber sortiert.
List<TileXYZ> tilesCovering(AreaBounds bounds, {int minZoom = kAreaMinZoom, required int maxZoom}) {
  final out = <TileXYZ>[];
  for (var z = minZoom; z <= maxZoom; z++) {
    final nw = tileAt(bounds.north, bounds.west, z);
    final se = tileAt(bounds.south, bounds.east, z);
    for (var x = nw.x; x <= se.x; x++) {
      for (var y = nw.y; y <= se.y; y++) {
        out.add((z: z, x: x, y: y));
      }
    }
  }
  return out;
}

/// Wie viele Kacheln [tilesCovering] liefern würde — ohne die Liste zu
/// bauen (für die Obergrenze, bevor jemand 40 000 Einträge anlegt).
int countTilesCovering(AreaBounds bounds, {int minZoom = kAreaMinZoom, required int maxZoom}) {
  var count = 0;
  for (var z = minZoom; z <= maxZoom; z++) {
    final nw = tileAt(bounds.north, bounds.west, z);
    final se = tileAt(bounds.south, bounds.east, z);
    count += (se.x - nw.x + 1) * (se.y - nw.y + 1);
  }
  return count;
}

int tileIdOf(TileXYZ t) => ZXY(t.z, t.x, t.y).toTileId();

/// Der Rahmen einer Kachel (Umkehrung von [tileAt]).
AreaBounds tileBounds(int z, int x, int y) {
  final n = 1 << z;
  double lat(int row) =>
      math.atan(_sinh(math.pi * (1 - 2 * row / n))) * 180 / math.pi;
  return AreaBounds(
    south: lat(y + 1),
    west: x / n * 360 - 180,
    north: lat(y),
    east: (x + 1) / n * 360 - 180,
  );
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

/// Die Form eines Bereichs: Rahmen oder Kachelmenge. Beide sagen, welche
/// Kacheln je Zoom dazugehören, welche Orte-Zellen, und was ihre Hülle
/// ist (der Rahmen im Archiv-Header, „auf der Karte zeigen").
sealed class AreaShape {
  const AreaShape();

  AreaBounds get hull;

  List<TileXYZ> tiles({int minZoom = kAreaMinZoom, required int maxZoom});

  /// Wie viele Kacheln [tiles] liefern würde — für die Obergrenze, bevor
  /// jemand 40 000 Einträge anlegt.
  int countTiles({int minZoom = kAreaMinZoom, required int maxZoom});

  /// Die Orte-Zellen, die zum Bereich gehören.
  List<PoiCell> poiCells();

  /// Alle Kacheln der Form bei Zoom [z] als Schlüssel ([TileSetShape.keyOf])
  /// — der gespeicherte Bestand, gegen den ein Entwurf rechnet.
  Set<int> keysAt(int z);

  /// Die Kacheln bei Zoom [z], die [box] berühren — für die Hervorhebung
  /// auf der Karte, die nur den Ausschnitt braucht und nicht 40 000
  /// Kacheln.
  List<TileXYZ> tilesWithin(AreaBounds box, int z);

  Map<String, dynamic> toJson();

  static AreaShape fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'tiles' => TileSetShape(
            zoom: j['zoom'] as int,
            keys: {for (final k in j['keys'] as List) k as int},
          ),
        'region' => RegionShape(
            region: j['region'] as String,
            bounds: AreaBounds.fromJson(j['bounds'] as Map<String, dynamic>),
          ),
        _ => RectShape(AreaBounds.fromJson(j['bounds'] as Map<String, dynamic>)),
      };

  /// Die Kacheln entlang der Linien, [corridorKm] beiderseits — leer
  /// (null), wenn es keine Punkte gibt.
  ///
  /// Abgetastet je halben Korridor: Um jede Probe kommt das Quadrat mit
  /// dem Korridor als halber Seite dazu (ein Quadrat statt eines Kreises
  /// — an den Ecken eine Kachel zu viel ist die harmlose Richtung).
  static TileSetShape? alongLines(Iterable<List<LatLng>> lines,
      {double corridorKm = kAreaTrailsCorridorKm, int zoom = kAreaShapeZoom}) {
    final keys = <int>{};
    final dLat = corridorKm / 111.0;
    final stepM = corridorKm * 1000 / 2;
    void sample(LatLng p) {
      final dLon = corridorKm / (111.0 * math.max(0.2, math.cos(p.latitude * math.pi / 180)));
      final nw = tileAt(p.latitude + dLat, p.longitude - dLon, zoom);
      final se = tileAt(p.latitude - dLat, p.longitude + dLon, zoom);
      for (var x = nw.x; x <= se.x; x++) {
        for (var y = nw.y; y <= se.y; y++) {
          keys.add(TileSetShape.keyOf(x, y, zoom));
        }
      }
    }

    for (final line in lines) {
      if (line.isEmpty) continue;
      sample(line.first);
      for (var i = 1; i < line.length; i++) {
        final a = line[i - 1], b = line[i];
        final dy = (b.latitude - a.latitude) * 111320.0;
        final dx = (b.longitude - a.longitude) * 111320.0 * math.cos(a.latitude * math.pi / 180);
        final steps = (math.sqrt(dx * dx + dy * dy) / stepM).ceil().clamp(1, 1 << 20);
        for (var k = 1; k <= steps; k++) {
          final f = k / steps;
          sample(LatLng(a.latitude + (b.latitude - a.latitude) * f,
              a.longitude + (b.longitude - a.longitude) * f));
        }
      }
    }
    return keys.isEmpty ? null : TileSetShape(zoom: zoom, keys: keys);
  }
}

/// Ein Rahmen — der aktuelle Ausschnitt.
class RectShape extends AreaShape {
  const RectShape(this.bounds);

  final AreaBounds bounds;

  @override
  AreaBounds get hull => bounds;

  @override
  List<TileXYZ> tiles({int minZoom = kAreaMinZoom, required int maxZoom}) =>
      tilesCovering(bounds, minZoom: minZoom, maxZoom: maxZoom);

  @override
  int countTiles({int minZoom = kAreaMinZoom, required int maxZoom}) =>
      countTilesCovering(bounds, minZoom: minZoom, maxZoom: maxZoom);

  @override
  List<PoiCell> poiCells() => poiCellsCovering(bounds.south, bounds.west, bounds.north, bounds.east);

  @override
  List<TileXYZ> tilesWithin(AreaBounds box, int z) {
    if (!bounds.intersects(box)) return const [];
    final cut = AreaBounds(
      south: math.max(bounds.south, box.south),
      west: math.max(bounds.west, box.west),
      north: math.min(bounds.north, box.north),
      east: math.min(bounds.east, box.east),
    );
    return tilesCovering(cut, minZoom: z, maxZoom: z);
  }

  @override
  Set<int> keysAt(int z) => {
        for (final t in tilesCovering(bounds, minZoom: z, maxZoom: z)) TileSetShape.keyOf(t.x, t.y, z),
      };

  @override
  Map<String, dynamic> toJson() => {'type': 'rect', 'bounds': bounds.toJson()};
}

/// Die ganze Region (#229, Konzept 8.2): alle Kacheln, die das Archiv des
/// Hosts im Rahmen der Region nennt, Zoom 8 bis zum Zoom des Hosts. Nach
/// außen ein Rahmen wie [RectShape] — die Kacheln, die der Host nicht hat
/// (Meer, außerhalb der Umrisslinie), fallen beim Planen weg wie immer.
///
/// Drei Dinge sind anders, weil die Form Millionen Kacheln deckt (Kanada
/// bei Zoom 13 rund 930 000): Sie hat keine Obergrenze ([kAreaMaxTiles]
/// gilt für gezeichnete), Verweise und Alter rechnen für eine Region mit
/// ihr gegen den ganzen Index statt gegen ihre Kacheln
/// (`tile_refs.dart`), und Entwurf und Radierer lassen sie aus — sie ist
/// nur im Ganzen zu löschen. [keysAt] würde deshalb niemand rufen; es
/// rechnet trotzdem richtig.
class RegionShape extends RectShape {
  const RegionShape({required this.region, required AreaBounds bounds}) : super(bounds);

  /// Die Region des Hosts (`dach`, `ca`).
  final String region;

  @override
  Map<String, dynamic> toJson() => {'type': 'region', 'region': region, 'bounds': bounds.toJson()};
}

/// Eine Menge Kacheln bei [zoom] (Schlüssel aus [keyOf]) — die Form
/// entlang der Trails. Andere Zooms folgen daraus: Eltern darunter,
/// Kinder darüber.
class TileSetShape extends AreaShape {
  const TileSetShape({required this.zoom, required this.keys});

  final int zoom;
  final Set<int> keys;

  static int keyOf(int x, int y, int zoom) => (x << zoom) | y;

  ({int x, int y}) _xy(int key) => (x: key >> zoom, y: key & ((1 << zoom) - 1));

  /// Die Kacheln bei Zoom [z] — als Menge, weil Eltern mehrfach kommen.
  Set<int> _keysAt(int z) {
    if (z == zoom) return keys;
    if (z < zoom) {
      final d = zoom - z;
      return {for (final k in keys) TileSetShape.keyOf(_xy(k).x >> d, _xy(k).y >> d, z)};
    }
    final d = z - zoom;
    return {
      for (final k in keys)
        for (var dx = 0; dx < (1 << d); dx++)
          for (var dy = 0; dy < (1 << d); dy++)
            TileSetShape.keyOf((_xy(k).x << d) + dx, (_xy(k).y << d) + dy, z),
    };
  }

  @override
  List<TileXYZ> tiles({int minZoom = kAreaMinZoom, required int maxZoom}) => [
        for (var z = minZoom; z <= maxZoom; z++)
          for (final k in _keysAt(z)) (z: z, x: k >> z, y: k & ((1 << z) - 1)),
      ];

  @override
  int countTiles({int minZoom = kAreaMinZoom, required int maxZoom}) {
    var count = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      count += z > zoom ? keys.length << (2 * (z - zoom)) : _keysAt(z).length;
    }
    return count;
  }

  @override
  AreaBounds get hull {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final k in keys) {
      final b = tileBounds(zoom, _xy(k).x, _xy(k).y);
      s = math.min(s, b.south);
      n = math.max(n, b.north);
      w = math.min(w, b.west);
      e = math.max(e, b.east);
    }
    return AreaBounds(south: s, west: w, north: n, east: e);
  }

  @override
  List<PoiCell> poiCells() {
    final cells = <PoiCell>{};
    for (final k in keys) {
      final b = tileBounds(zoom, _xy(k).x, _xy(k).y);
      cells.addAll(poiCellsCovering(b.south, b.west, b.north, b.east));
    }
    return cells.toList()..sort();
  }

  @override
  List<TileXYZ> tilesWithin(AreaBounds box, int z) {
    final nw = tileAt(box.north, box.west, z);
    final se = tileAt(box.south, box.east, z);
    return [
      for (final k in _keysAt(z))
        if ((k >> z) >= nw.x && (k >> z) <= se.x && (k & ((1 << z) - 1)) >= nw.y && (k & ((1 << z) - 1)) <= se.y)
          (z: z, x: k >> z, y: k & ((1 << z) - 1)),
    ];
  }

  @override
  Set<int> keysAt(int z) => _keysAt(z);

  @override
  Map<String, dynamic> toJson() => {'type': 'tiles', 'zoom': zoom, 'keys': keys.toList()..sort()};
}

/// Lesbare Größe, wie sie das Blatt und die Liste zeigen.
String formatBytes(int bytes) {
  if (bytes < 1000 * 1000) return '${(bytes / 1000).round()} kB';
  if (bytes < 1000 * 1000 * 1000) return '${(bytes / 1e6).toStringAsFixed(1).replaceAll('.', ',')} MB';
  return '${(bytes / 1e9).toStringAsFixed(2).replaceAll('.', ',')} GB';
}
