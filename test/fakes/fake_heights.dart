// Höhenkacheln für Tests (#186): ein Hang um 48° N / 9° O, nach Süden
// gleichmäßig steigend — 5 m je Probenzeile (~68 m), also ~73 m auf den
// 0,009° der Trails aus `seedTrail` und `gpx()` (nach Norden bergab).
// Dieselben Werte im Speicher (Bereiche) und als Archiv (Host), über
// geteilte Ränder stetig.
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart' show tileAt;
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';

final _origin = tileAt(48.0, 9.0, kHeightTileZoom);

List<int> _values(int y) => [
  for (var r = 0; r < kHeightGrid; r++)
    for (var c = 0; c < kHeightGrid; c++)
      1000 + 5 * ((y - _origin.y + 1) * (kHeightGrid - 1) + r),
];

/// Die Kacheln um den Ursprung, je 3 × 3.
Map<({int x, int y}), HeightTile> slopeHeightTiles() => {
  for (var dx = -1; dx <= 1; dx++)
    for (var dy = -1; dy <= 1; dy++)
      (x: _origin.x + dx, y: _origin.y + dy): HeightTile(
        Int16List.fromList(_values(_origin.y + dy)),
      ),
};

/// Dieselben Kacheln als Höhenarchiv, wie es der Host liefert.
Uint8List slopeHeightsArchive() => writePmTiles(
  tiles: [
    for (final e in slopeHeightTiles().entries)
      TileToWrite(
        kHeightTileZoom,
        e.key.x,
        e.key.y,
        encodeHeightTile(e.value.values),
      ),
  ],
  tileCompression: Compression.gzip,
  bounds: const TileBounds(west: 8.9, south: 47.9, east: 9.1, north: 48.1),
  metadata: heightsMetadata('Test', '20261001'),
);

/// Die Höhe des Hangs an [p] — was das Modell dort liest.
Future<double> slopeHeightAt(LatLng p) async =>
    (await HeightReader([MemoryHeightSource(slopeHeightTiles())]).heightAt(p))!;
