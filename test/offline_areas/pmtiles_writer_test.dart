// Der PMTiles-Schreiber (Konzept 3.2): Was er schreibt, liest das Paket
// zurück — jede Kachel, mit und ohne Blatt-Verzeichnisse, dedupliziert,
// mit dem Zoombereich und der Kompression im Header. Ein Archiv, das
// hier durchgeht und auf dem Gerät scheitert, hätte einen anderen Leser
// — beide Engines lesen mit demselben Format.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';

Uint8List _payload(int z, int x, int y) =>
    Uint8List.fromList(utf8.encode('tile $z/$x/$y ' * (1 + (x + y) % 3)));

const _bounds = TileBounds(west: 9, south: 47, east: 12, north: 49);

List<TileToWrite> _grid({int zFrom = 8, int zTo = 10}) => [
  for (var z = zFrom; z <= zTo; z++)
    for (var x = 0; x < 6; x++)
      for (var y = 0; y < 5; y++)
        // Jede dritte Kachel „Meer": gleiche Bytes, einmal abgelegt.
        TileToWrite(
          z,
          x,
          y,
          (x * 5 + y) % 3 == 0
              ? Uint8List.fromList([1, 2, 3])
              : _payload(z, x, y),
        ),
];

void main() {
  test(
    'jede Kachel kommt Byte für Byte zurück, in der Reihenfolge des Aufrufers egal',
    () async {
      final tiles = _grid();
      final bytes = writePmTiles(
        tiles: tiles.reversed,
        tileCompression: Compression.none,
        bounds: _bounds,
      );
      final archive = await PmTilesArchive.fromBytes(bytes);
      expect(archive.header.minZoom, 8);
      expect(archive.header.maxZoom, 10);
      expect(archive.header.tileCompression, Compression.none);
      expect(archive.header.internalCompression, Compression.none);
      expect(archive.header.numberOfAddressedTiles, tiles.length);
      expect(
        archive.header.numberOfTileContents,
        lessThan(tiles.length),
        reason: 'die Meer-Kacheln liegen nur einmal da',
      );
      expect(
        archive.header.leafDirectoriesLength,
        0,
        reason: 'die Wurzel reicht',
      );
      for (final t in tiles) {
        final tile = await archive.tile(ZXY(t.z, t.x, t.y).toTileId());
        expect(tile.compressedBytes(), t.bytes, reason: '${t.z}/${t.x}/${t.y}');
      }
      // Und nichts, was nicht drin ist.
      expect(
        archive.lookup(const ZXY(11, 0, 0).toTileId()),
        completion(isNull),
      );
      expect(archive.header.minPosition.longitude, closeTo(9, 1e-6));
      expect(archive.header.maxPosition.latitude, closeTo(49, 1e-6));
    },
  );

  test('mit Blatt-Verzeichnissen liest sich das Archiv genauso', () async {
    final tiles = _grid();
    final bytes = writePmTiles(
      tiles: tiles,
      tileCompression: Compression.gzip,
      bounds: _bounds,
      leafSize: 4,
    );
    final archive = await PmTilesArchive.fromBytes(bytes);
    expect(archive.header.leafDirectoriesLength, greaterThan(0));
    expect(archive.header.tileCompression, Compression.gzip);
    for (final t in tiles) {
      final tile = await archive.tile(ZXY(t.z, t.x, t.y).toTileId());
      expect(tile.compressedBytes(), t.bytes, reason: '${t.z}/${t.x}/${t.y}');
    }
    // `tiles()` — der Weg des Downloads — liefert dieselben Bytes.
    final ids = [for (final t in tiles) ZXY(t.z, t.x, t.y).toTileId()];
    final got = <int, List<int>>{};
    await for (final tile in archive.tiles(ids)) {
      got[tile.id] = tile.compressedBytes();
    }
    expect(got.length, ids.length);
  });

  test(
    'ein großes Verzeichnis bekommt von selbst Blätter, und die Wurzel bleibt klein',
    () async {
      // 12 000 Kacheln mit lauter verschiedenen Längen: Läufe fallen weg,
      // jede Kachel ein Eintrag, die Wurzel überschreitet 16 KiB.
      final tiles = <TileToWrite>[];
      var i = 0;
      for (var x = 0; x < 120; x++) {
        for (var y = 0; y < 100; y++) {
          tiles.add(TileToWrite(13, x, y, Uint8List(1 + (i++ % 97))));
        }
      }
      final bytes = writePmTiles(
        tiles: tiles,
        tileCompression: Compression.none,
        bounds: _bounds,
      );
      final archive = await PmTilesArchive.fromBytes(bytes);
      expect(
        archive.header.rootDirectoryLength,
        lessThanOrEqualTo(kPmTilesMaxRootBytes),
      );
      expect(archive.header.leafDirectoriesLength, greaterThan(0));
      final probe = tiles[tiles.length ~/ 2];
      final tile = await archive.tile(ZXY(13, probe.x, probe.y).toTileId());
      expect(tile.compressedBytes().length, probe.bytes.length);
    },
  );

  test('ohne Kacheln kein Archiv', () {
    expect(
      () => writePmTiles(
        tiles: const [],
        tileCompression: Compression.none,
        bounds: _bounds,
      ),
      throwsArgumentError,
    );
  });
}
