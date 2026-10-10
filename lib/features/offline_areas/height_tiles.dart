// Höhenkacheln (docs/konzept-routing.md 2.6, Weg B; Schritt 2 aus
// Abschnitt 5): je z13-Kachel ein 49 × 49-Raster aus Höhen in ganzen
// Metern, abgetastet aus dem Copernicus-DEM GLO-90, gebaut von
// `tool/height_tiles.py` + `height-data.yml` als EIN PMTiles-Archiv auf
// dem eigenen Host. Ein gespeicherter Bereich holt seine Kacheln daraus
// wie die Kartenkacheln (Range-Anfragen, derselbe Leser) und legt sie als
// zweites Archiv neben sich ab. Hier steht der Leser: das Kachelformat,
// die bilineare Ablesung, die Hysterese für Anstieg und Abstieg.
//
// Warum ein Raster je Kachel und nicht PilzBuddys Höhengitter: gemessen
// (docs/routing-messung.md, M3). Entlang der offiziellen Trails Tirols
// traf das 250-m-Gitter mit 20-m-Stufen den Abstieg der Quelle mit 42 %
// Medianfehler, das DEM direkt mit 5 % — Stufen werden entlang einer
// Linie zu Treppen, die keine Hysterese wegbekommt.
//
// Das Format, Byte für Byte der Spiegel des Werkzeugs (dessen Self-Test
// und `test/offline_areas/height_tiles_test.dart` prüfen dasselbe
// Muster gegen dieselben Konstanten):
//   - [kHeightGrid] × [kHeightGrid] Proben je Kachel, zeilenweise, Zeile 0
//     im Norden, bei den Kachelbrüchen i/48 — die RÄNDER eingeschlossen,
//     Nachbarkacheln teilen sich also ihre Randzeile, und eine bilineare
//     Ablesung ist über die Kachelgrenze stetig.
//   - int16 Meter, Little-Endian, als Differenz zum Vorgänger in
//     Lesereihenfolge (der erste Wert absolut, Überlauf erlaubt), dann
//     gzip — das ist die Kachelkompression, die der Archiv-Header nennt.
//   - [kHeightNoData] steht für „keine Höhe" (kein DEM dort); eine Kachel
//     nur aus NODATA fehlt im Archiv.
//
// Der Anstieg einer Linie wird nicht an ihren Enden gelesen, sondern
// alle [kClimbSampleM] Meter entlang abgetastet und mit einer Hysterese
// von [kClimbHysteresisM] zu Anstieg/Abstieg summiert — die 3 m der
// Trail-Höhen (`kElevationThresholdM`) gelten für aufgezeichnete Höhen,
// nicht für ein 90-m-Gitter. Dieselbe Abtastung und Hysterese wie
// `climb_along` im Werkzeug.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipEncoder;
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';

import '../../core/line_geometry.dart';

/// Die Formatnummer, die Manifest und Archiv-Metadaten nennen; eine
/// andere heißt „kein Leser dafür", nicht „irgendwie lesen".
const kHeightsFormat = 1;

/// Proben je Achse und Kachel.
const kHeightGrid = 49;

/// Der Zoom der Höhenkacheln — der der Formen ([kAreaShapeZoom]), eine
/// Höhenkachel je Kartenkachel des Bereichs.
const kHeightTileZoom = 13;

/// „Keine Höhe" in einer Kachel.
const kHeightNoData = -32768;

/// Abtastschritt entlang einer Linie und Hysterese der Summierung.
const kClimbSampleM = 50.0;
const kClimbHysteresisM = 10.0;

/// Die Namensnennung des DEM, auf der Lizenzseite und in den Archiven.
const kHeightsAttribution =
    'Copernicus DEM GLO-90: © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH '
    '2014-2018, provided under COPERNICUS by the European Union and ESA; all rights reserved';

const _samples = kHeightGrid * kHeightGrid;

/// Die Metadaten, die ein Höhenarchiv auf dem Gerät trägt — dieselben
/// Schlüssel wie das Archiv des Hosts (`archive_metadata` im Werkzeug).
Map<String, dynamic> heightsMetadata(String name, String? build) => {
      'name': name,
      'format': kHeightsFormat,
      'grid': kHeightGrid,
      'zoom': kHeightTileZoom,
      'nodata': kHeightNoData,
      'unit': 'm',
      'build': ?build,
      'source': 'Copernicus DEM GLO-90',
      'attribution': kHeightsAttribution,
    };

/// Eine entpackte Höhenkachel.
class HeightTile {
  const HeightTile(this.values);

  /// Zeilenweise, Zeile 0 im Norden, Spalte 0 im Westen.
  final Int16List values;

  /// Aus den ENTPACKTEN Bytes einer Kachel (das Paket entpackt nach der
  /// Kompression im Archiv-Header, `Tile.bytes()`); wirft
  /// [FormatException], wenn es nicht genau eine Kachel ist.
  factory HeightTile.decode(List<int> raw) {
    if (raw.length != _samples * 2) {
      throw FormatException('Höhenkachel: ${raw.length} Byte statt ${_samples * 2}');
    }
    final data = ByteData.sublistView(Uint8List.fromList(raw));
    final out = Int16List(_samples);
    var prev = 0;
    for (var i = 0; i < _samples; i++) {
      final d = data.getInt16(2 * i, Endian.little);
      prev = ((prev + d + 32768) & 0xFFFF) - 32768;
      out[i] = prev;
    }
    return HeightTile(out);
  }

  int valueAt(int col, int row) => values[row * kHeightGrid + col];

  /// Die Höhe bei den Kachelbrüchen [fx] (0 West … 1 Ost) und [fy]
  /// (0 Nord … 1 Süd), bilinear zwischen den vier nächsten Proben; null,
  /// sobald eine davon NODATA ist.
  double? at(double fx, double fy) {
    final gx = fx.clamp(0.0, 1.0) * (kHeightGrid - 1);
    final gy = fy.clamp(0.0, 1.0) * (kHeightGrid - 1);
    final c0 = math.min(gx.floor(), kHeightGrid - 2);
    final r0 = math.min(gy.floor(), kHeightGrid - 2);
    final tc = gx - c0, tr = gy - r0;
    final v00 = valueAt(c0, r0), v01 = valueAt(c0 + 1, r0);
    final v10 = valueAt(c0, r0 + 1), v11 = valueAt(c0 + 1, r0 + 1);
    if (v00 == kHeightNoData || v01 == kHeightNoData || v10 == kHeightNoData || v11 == kHeightNoData) {
      return null;
    }
    final a = v00 * (1 - tc) + v01 * tc;
    final b = v10 * (1 - tc) + v11 * tc;
    return a * (1 - tr) + b * tr;
  }

  bool get isEmpty => values.every((v) => v == kHeightNoData);
}

/// Die Kachelbytes, wie sie im Archiv liegen (Delta, dann gzip — die
/// Kachelkompression des Headers) — für Tests und Fixtures, mit
/// denselben Regeln wie `encode_tile` im Werkzeug.
Uint8List encodeHeightTile(List<int> values) =>
    Uint8List.fromList(GZipEncoder().encode(heightTileDeltas(values), level: 9)!);

/// Die rohen Delta-Bytes einer Kachel (vor gzip): was [HeightTile.decode]
/// liest, und was der Test gegen die Konstanten des Werkzeugs hält.
Uint8List heightTileDeltas(List<int> values) {
  if (values.length != _samples) {
    throw ArgumentError('${values.length} Werte, erwartet $_samples');
  }
  final raw = Uint8List(_samples * 2);
  final data = ByteData.sublistView(raw);
  var prev = 0;
  for (var i = 0; i < _samples; i++) {
    final v = values[i];
    if (v < -32768 || v > 32767) throw ArgumentError('Höhe $v außerhalb int16');
    data.setUint16(2 * i, (v - prev) & 0xFFFF, Endian.little);
    prev = v;
  }
  return raw;
}

/// Die Breite, an der Web-Mercator endet — eine Konstante mit Namen, damit
/// der Privat-Wächter sie nicht für ein Koordinatenpaar hält.
const _maxMercatorLat = 85.05112878;

/// Welche z13-Kachel ein Punkt trifft, und wo darin (Brüche 0…1).
({int x, int y, double fx, double fy}) heightTileOf(LatLng p, {int zoom = kHeightTileZoom}) {
  final n = 1 << zoom;
  final xf = (p.longitude + 180) / 360 * n;
  final lat = p.latitude.clamp(-_maxMercatorLat, _maxMercatorLat) * math.pi / 180;
  final yf = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n;
  final x = xf.floor().clamp(0, n - 1);
  final y = yf.floor().clamp(0, n - 1);
  return (x: x, y: y, fx: (xf - x).clamp(0.0, 1.0), fy: (yf - y).clamp(0.0, 1.0));
}

/// Woher Höhenkacheln kommen: die Archive der Bereiche, im Test ein
/// Speicher.
abstract interface class HeightTileSource {
  /// Die Kachel [x]/[y] bei [kHeightTileZoom], null wenn die Quelle sie
  /// nicht hat.
  Future<HeightTile?> tile(int x, int y);

  Future<void> close();
}

/// Ein Höhenarchiv (vom Host oder das eines Bereichs), Kacheln einmal
/// entpackt und gemerkt.
class ArchiveHeightSource implements HeightTileSource {
  ArchiveHeightSource(this._archive);

  final PmTilesArchive _archive;
  final _cache = <int, HeightTile?>{};

  @override
  Future<HeightTile?> tile(int x, int y) async {
    final id = ZXY(kHeightTileZoom, x, y).toTileId();
    if (_cache.containsKey(id)) return _cache[id];
    HeightTile? out;
    if (await _archive.lookup(id) != null) {
      try {
        out = HeightTile.decode((await _archive.tile(id)).bytes());
      } on FormatException {
        // Eine Kachel, die sich nicht lesen lässt, ist keine Kachel —
        // der Abnehmer sagt dann „keine Höhen", statt eine Zahl zu
        // erfinden.
        out = null;
      }
    }
    return _cache[id] = out;
  }

  @override
  Future<void> close() => _archive.close();
}

/// Höhenkacheln aus dem Speicher — für Tests.
class MemoryHeightSource implements HeightTileSource {
  MemoryHeightSource(this.tiles);

  final Map<({int x, int y}), HeightTile> tiles;

  @override
  Future<HeightTile?> tile(int x, int y) async => tiles[(x: x, y: y)];

  @override
  Future<void> close() async {}
}

/// Liest Höhen über mehrere Quellen (die erste, die die Kachel hat,
/// liefert) und rechnet Anstieg/Abstieg entlang einer Linie.
class HeightReader {
  HeightReader(this.sources);

  final List<HeightTileSource> sources;
  final _found = <int, HeightTile?>{};

  Future<HeightTile?> tileAt(int x, int y) async {
    final key = (x << kHeightTileZoom) | y;
    if (_found.containsKey(key)) return _found[key];
    for (final s in sources) {
      final t = await s.tile(x, y);
      if (t != null) return _found[key] = t;
    }
    return _found[key] = null;
  }

  /// Die Höhe am Punkt, null ohne Kachel oder auf NODATA. Ein Punkt
  /// GENAU auf einer Kachelkante gehört rechnerisch einer der beiden
  /// Kacheln — welcher, entscheidet das letzte Bit des Rundlaufs Grad →
  /// Meter → Grad. Fehlt die, liest die Nachbarkachel an ihrem Rand: Die
  /// Ränder sind geteilt, es ist dieselbe Zahl. Ohne diese Regel war ein
  /// Weg am Rand des einzigen Bereichs „ohne Höhe".
  Future<double?> heightAt(LatLng p) async {
    final t = heightTileOf(p);
    final tile = await tileAt(t.x, t.y);
    if (tile != null) return tile.at(t.fx, t.fy);
    const eps = 1e-9;
    final xs = [(t.x, t.fx), if (t.fx <= eps) (t.x - 1, 1.0), if (t.fx >= 1 - eps) (t.x + 1, 0.0)];
    final ys = [(t.y, t.fy), if (t.fy <= eps) (t.y - 1, 1.0), if (t.fy >= 1 - eps) (t.y + 1, 0.0)];
    for (final (x, fx) in xs) {
      for (final (y, fy) in ys) {
        if (x == t.x && y == t.y) continue;
        final edge = await tileAt(x, y);
        if (edge != null) return edge.at(fx, fy);
      }
    }
    return null;
  }

  /// Anstieg und Abstieg entlang [line] — abgetastet alle [sampleM]
  /// Meter, mit Hysterese [hysteresisM]. Null, sobald eine Probe keine
  /// Höhe hat: ein halber Anstieg wäre eine erfundene Zahl.
  Future<({double gain, double loss})?> climbAlong(List<LatLng> line,
      {double sampleM = kClimbSampleM, double hysteresisM = kClimbHysteresisM}) async {
    if (line.length < 2) return (gain: 0.0, loss: 0.0);
    final profile = await profileAlong(line, sampleM: sampleM);
    if (profile == null) return null;
    final (gain, loss) = hysteresisClimb(profile.heights, hysteresisM);
    return (gain: gain, loss: loss);
  }

  /// Die Höhen alle [sampleM] Meter entlang [line] und die Abstände
  /// zwischen aufeinanderfolgenden Proben (Sehnen in der Ebene um den
  /// ersten Punkt) — `profile_along` im Werkzeug. Null, sobald eine Probe
  /// keine Höhe hat.
  Future<({List<double> heights, List<double> stepsM})?> profileAlong(List<LatLng> line,
      {double sampleM = kClimbSampleM}) async {
    if (line.length < 2) return (heights: <double>[], stepsM: <double>[]);
    final proj = FlatProjection(line.first.latitude);
    final xy = resampleXy(proj.line(line), sampleM);
    final heights = <double>[];
    for (final p in xy) {
      final h = await heightAt(proj.latLng(p));
      if (h == null) return null;
      heights.add(h);
    }
    return (heights: heights, stepsM: [for (var i = 1; i < xy.length; i++) xy[i - 1].distanceTo(xy[i])]);
  }

  Future<void> close() async {
    for (final s in sources) {
      await s.close();
    }
  }
}

/// Punkte alle [stepM] Meter entlang der Linie, erster und letzter
/// eingeschlossen — `climb_along` im Werkzeug: eben um die Breite des
/// ersten Punkts, [resampleXy], zurück nach Grad.
List<LatLng> samplesAlong(List<LatLng> line, double stepM) {
  if (line.length < 2) return [...line];
  final proj = FlatProjection(line.first.latitude);
  return [for (final p in resampleXy(proj.line(line), stepM)) proj.latLng(p)];
}

/// Anstieg und Abstieg EINER Kante: [hysteresisClimb], dazu der Rest bis
/// zur letzten Probe — so ist Anstieg minus Abstieg genau der
/// Höhenunterschied der Kante. Die Hysterese gilt für eine ganze Linie;
/// je Kante angewandt verschluckte sie jede Kante unter [threshold], und
/// eine Route aus kurzen Kanten zwischen Kreuzungen stieg „0 hm", während
/// ihr Profil daneben 150 hm zeigte. Spiegel von `edge_climb` im Werkzeug.
(double, double) edgeClimb(List<double> heights, double threshold) {
  final (gain, loss) = hysteresisClimb(heights, threshold);
  if (heights.length < 2) return (gain, loss);
  final rest = heights.last - heights.first - (gain - loss);
  return rest > 0 ? (gain + rest, loss) : (gain, loss - rest);
}

/// Summiert Anstiege und Abstiege und ignoriert Zacken unter
/// [threshold] — Spiegel von `hysteresis_climb` im Werkzeug, mit dessen
/// Testvektoren im Test.
(double, double) hysteresisClimb(List<double> heights, double threshold) {
  if (heights.length < 2) return (0.0, 0.0);
  var gain = 0.0, loss = 0.0;
  var ref = heights[0]; // letzter bestätigter Wendepunkt
  var extreme = ref; // Kandidat für den nächsten
  var direction = 0; // 0 unentschieden, 1 steigend, -1 fallend
  for (final h in heights.skip(1)) {
    if (direction == 0) {
      if (h - ref >= threshold) {
        direction = 1;
        extreme = h;
      } else if (ref - h >= threshold) {
        direction = -1;
        extreme = h;
      }
    } else if (direction == 1) {
      if (h > extreme) {
        extreme = h;
      } else if (extreme - h >= threshold) {
        gain += extreme - ref;
        ref = extreme;
        extreme = h;
        direction = -1;
      }
    } else {
      if (h < extreme) {
        extreme = h;
      } else if (h - extreme >= threshold) {
        loss += ref - extreme;
        ref = extreme;
        extreme = h;
        direction = 1;
      }
    }
  }
  if (direction == 1) {
    gain += extreme - ref;
  } else if (direction == -1) {
    loss += ref - extreme;
  }
  return (gain, loss);
}
