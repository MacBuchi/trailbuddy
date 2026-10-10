// Die Höhenkacheln (Konzept-Routing 2.6, Weg B): das Kachelformat Byte
// für Byte gegen die Konstanten des Werkzeugs (`tool/height_tiles.py`,
// dasselbe Fixture-Raster), die bilineare Ablesung über Kachelgrenzen
// hinweg, NODATA, die Hysterese mit den Testvektoren des Werkzeugs, und
// der Anstieg entlang einer Linie aus einem Archiv des eigenen Schreibers.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';

/// `fixture_grid()` im Werkzeug — Zeile für Zeile dieselben Werte.
List<int> _fixture() {
  final values = <int>[];
  for (var j = 0; j < kHeightGrid; j++) {
    for (var i = 0; i < kHeightGrid; i++) {
      values.add(1000 + 7 * i - 3 * j + (i * j) % 5);
    }
  }
  values[20 * kHeightGrid + 10] = kHeightNoData;
  values[0] = -120;
  values[kHeightGrid * kHeightGrid - 1] = 4810;
  return values;
}

int _fnv1a(List<int> bytes) {
  var h = 0x811C9DC5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Eine Kachel aus einer Höhenfunktion über (fx, fy) — wie das Werkzeug
/// sie aus dem DEM abtastet, nur ohne DEM.
HeightTile _tileFrom(double Function(double fx, double fy) fn) {
  final values = Int16List(kHeightGrid * kHeightGrid);
  for (var j = 0; j < kHeightGrid; j++) {
    for (var i = 0; i < kHeightGrid; i++) {
      values[j * kHeightGrid + i] = (fn(i / (kHeightGrid - 1), j / (kHeightGrid - 1)) + 0.5).floor();
    }
  }
  return HeightTile(values);
}

void main() {
  test('das Fixture-Raster ergibt dieselben Delta-Bytes und denselben FNV wie das Werkzeug', () {
    final deltas = heightTileDeltas(_fixture());
    expect(deltas.length, 4802);
    expect(deltas.sublist(0, 8), [0x88, 0xff, 0x67, 0x04, 0x07, 0x00, 0x07, 0x00]);
    expect(_fnv1a(deltas), 0x20E77837);
    // Rundlauf, mit NODATA und den Extremen.
    final back = HeightTile.decode(deltas);
    expect(back.values, _fixture());
    expect(back.valueAt(10, 20), kHeightNoData);
    expect(back.valueAt(0, 0), -120);
    expect(back.valueAt(kHeightGrid - 1, kHeightGrid - 1), 4810);
    expect(encodeHeightTile(_fixture()).length, lessThan(4802 ~/ 3), reason: 'Delta + gzip');
  });

  test('überlaufende Differenzen kommen zurück, falsche Längen werden abgelehnt', () {
    final extremes = [
      for (var i = 0; i < kHeightGrid * kHeightGrid; i++) [kHeightNoData, 32767, -32767, 0][i % 4],
    ];
    expect(HeightTile.decode(heightTileDeltas(extremes)).values, extremes);
    expect(() => encodeHeightTile([1, 2, 3]), throwsArgumentError);
    expect(() => HeightTile.decode(heightTileDeltas(extremes).sublist(0, 20)), throwsFormatException);
    expect(() => HeightTile.decode(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  test('bilinear: eine Ebene wird zwischen den Proben genau getroffen, NODATA macht null', () {
    final plane = _tileFrom((fx, fy) => 1000 + 480 * fx + 240 * fy);
    expect(plane.at(0, 0), 1000);
    expect(plane.at(1, 1), 1720);
    expect(plane.at(0.5, 0.25), closeTo(1300, 0.6), reason: 'Rundung auf ganze Meter je Probe');
    expect(plane.at(1 / 96, 0), closeTo(1005, 0.6), reason: 'zwischen Spalte 0 und 1');
    // Außerhalb wird geklemmt, nicht geraten.
    expect(plane.at(1.5, -1), plane.at(1, 0));
    final holed = Int16List.fromList(plane.values)..[0] = kHeightNoData;
    final tile = HeightTile(holed);
    expect(tile.at(0.001, 0.001), isNull, reason: 'eine der vier Proben ist NODATA');
    expect(tile.at(0.5, 0.5), isNotNull);
    expect(tile.isEmpty, isFalse);
    expect(HeightTile(Int16List(kHeightGrid * kHeightGrid)..fillRange(0, kHeightGrid * kHeightGrid, kHeightNoData)).isEmpty,
        isTrue);
  });

  test('heightTileOf: die z13-Kachel samt Bruch, und ein Punkt auf der Kante gehört beiden', () {
    const p = LatLng(47.26, 11.4);
    final t = heightTileOf(p);
    final expected = tileAt(p.latitude, p.longitude, kHeightTileZoom);
    expect((t.x, t.y), (expected.x, expected.y));
    expect(t.fx, inInclusiveRange(0, 1));
    expect(t.fy, inInclusiveRange(0, 1));
    // Die Westkante der Nachbarkachel ist die Ostkante dieser.
    final west = tileBounds(kHeightTileZoom, t.x + 1, t.y).west;
    final edge = heightTileOf(LatLng(p.latitude, west));
    expect(edge.x, t.x + 1);
    expect(edge.fx, closeTo(0, 1e-9));
  });

  test('die Hysterese: die Testvektoren des Werkzeugs', () {
    expect(hysteresisClimb([100, 105, 100, 105, 100, 150, 140, 200], 10), (110.0, 10.0));
    expect(hysteresisClimb([200, 100], 10), (0.0, 100.0));
    expect(hysteresisClimb([100, 200, 100], 10), (100.0, 100.0));
    expect(hysteresisClimb([100], 10), (0.0, 0.0));
    expect(hysteresisClimb([100, 104, 108, 112], 10), (12.0, 0.0), reason: 'ein Anstieg aus kleinen Schritten zählt');
  });

  test('edgeClimb: die Hysterese plus der Rest bis zum Ende — die Testvektoren des Werkzeugs', () {
    expect(edgeClimb([100, 104, 108], 10), (8.0, 0.0), reason: 'eine Kante unter der Schwelle behält ihren Anstieg');
    expect(edgeClimb([100, 130, 125], 10), (30.0, 5.0), reason: 'der Rest nach der letzten Wende zählt');
    expect(edgeClimb([100, 105, 100, 105, 100, 150, 140, 200], 10), (110.0, 10.0), reason: 'Zacken fallen weiter weg');
    expect(edgeClimb([100], 10), (0.0, 0.0));
    var sum = 0.0;
    for (var i = 0; i < 25; i++) {
      sum += edgeClimb([100.0 + 4 * i, 104.0 + 4 * i], 10).$1;
    }
    expect(sum, 100.0, reason: '25 kurze Kanten zu 4 m steigen 100 m, nicht 0');
  });

  test('samplesAlong: alle 50 m, erster und letzter Punkt, in Metern gerechnet', () {
    final line = [const LatLng(47.0, 11.0), LatLng(47.0, 11.0 + 1000 / (111320 * math.cos(47 * math.pi / 180)))];
    final samples = samplesAlong(line, 50);
    expect(samples.length, 21);
    expect(samples.first.latitude, closeTo(line.first.latitude, 1e-9));
    expect(samples.first.longitude, closeTo(line.first.longitude, 1e-9));
    expect(samples.last.longitude, closeTo(line.last.longitude, 1e-9));
    expect(samples[10].latitude, closeTo(47.0, 1e-9));
  });

  group('der Leser über Archive', () {
    // Zwei Nachbarkacheln (z13) aus EINER Ebene in Metern über der
    // Kachelbreite, damit die Kante stetig ist: Höhe = 500 + 300 je Kachel
    // nach Osten.
    final origin = tileAt(47.5, 11.5, kHeightTileZoom);
    double planeAt(int x, double fx, double fy) => 500 + 300 * (x - origin.x + fx) + 100 * fy;
    Uint8List archiveOf(List<({int x, int y})> tiles) => writePmTiles(
          tiles: [
            for (final t in tiles)
              TileToWrite(kHeightTileZoom, t.x, t.y,
                  encodeHeightTile(_tileFrom((fx, fy) => planeAt(t.x, fx, fy)).values)),
          ],
          tileCompression: Compression.gzip,
          bounds: const TileBounds(west: 11, south: 47, east: 12, north: 48),
          metadata: heightsMetadata('Test', '20261001'),
        );

    test('Höhen über die Kachelgrenze, null ohne Kachel, die erste Quelle gewinnt', () async {
      final a = await PmTilesArchive.fromBytes(archiveOf([(x: origin.x, y: origin.y)]));
      final b = await PmTilesArchive.fromBytes(archiveOf([(x: origin.x + 1, y: origin.y)]));
      final reader = HeightReader([ArchiveHeightSource(a), ArchiveHeightSource(b)]);
      addTearDown(reader.close);
      final left = tileBounds(kHeightTileZoom, origin.x, origin.y);
      final right = tileBounds(kHeightTileZoom, origin.x + 1, origin.y);
      final midLat = (left.north + left.south) / 2;
      // Westkante 500, Ostkante der linken = Westkante der rechten = 800.
      expect(await reader.heightAt(LatLng(left.north, left.west)), closeTo(500, 0.6));
      final atEdge = await reader.heightAt(LatLng(midLat, right.west));
      expect(atEdge, closeTo(800 + 50, 1.5));
      final justLeft = await reader.heightAt(LatLng(midLat, right.west - 1e-7));
      expect(justLeft, closeTo(atEdge!, 0.1), reason: 'stetig über die Kante');
      expect(await reader.heightAt(LatLng(midLat, right.east + 0.01)), isNull);
      expect(await reader.tileAt(origin.x + 5, origin.y), isNull);
      expect(await reader.tileAt(origin.x, origin.y), isNotNull);
    });

    test('climbAlong: eine Linie bergauf über zwei Kacheln, und null, sobald eine Probe fehlt', () async {
      final both = await PmTilesArchive.fromBytes(
          archiveOf([(x: origin.x, y: origin.y), (x: origin.x + 1, y: origin.y)]));
      final reader = HeightReader([ArchiveHeightSource(both)]);
      addTearDown(reader.close);
      final left = tileBounds(kHeightTileZoom, origin.x, origin.y);
      final right = tileBounds(kHeightTileZoom, origin.x + 1, origin.y);
      final lat = (left.north + left.south) / 2;
      // Von der Westkante der linken bis zur Ostkante der rechten: +600 m.
      final climb = await reader.climbAlong([LatLng(lat, left.west), LatLng(lat, right.east)]);
      expect(climb, isNotNull);
      expect(climb!.gain, closeTo(600, 3));
      expect(climb.loss, closeTo(0, 1));
      // Und zurück: nur Abstieg.
      final back = await reader.climbAlong([LatLng(lat, right.east), LatLng(lat, left.west)]);
      expect(back!.loss, closeTo(600, 3));
      expect(back.gain, closeTo(0, 1));
      // Ein Stück ohne Kachel: keine Zahl.
      expect(await reader.climbAlong([LatLng(lat, left.west), LatLng(lat, right.east + 0.05)]), isNull);
      expect(await reader.climbAlong([LatLng(lat, left.west)]), (gain: 0.0, loss: 0.0));
    });

    test('eine Kachel, die sich nicht entpacken lässt, ist keine Kachel', () async {
      final broken = await PmTilesArchive.fromBytes(writePmTiles(
        tiles: [TileToWrite(kHeightTileZoom, origin.x, origin.y, Uint8List.fromList([1, 2, 3]))],
        tileCompression: Compression.none,
        bounds: const TileBounds(west: 11, south: 47, east: 12, north: 48),
      ));
      final source = ArchiveHeightSource(broken);
      addTearDown(source.close);
      expect(await source.tile(origin.x, origin.y), isNull);
    });
  });
}
