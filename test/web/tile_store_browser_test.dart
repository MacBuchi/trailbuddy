// Der Kachelspeicher der Bereiche (#229) in einer ECHTEN IndexedDB —
// läuft nur mit `flutter test --platform chrome` (CI: Schritt „Web-Test
// auf dart2js"). Auf der VM gibt die Speicher-Fassung von idb_shim Werte
// anders zurück als der Browser (PilzBuddy #385); hier kommen Bytes und
// Index so zurück, wie die Karte und „Meine Bereiche" sie lesen.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:pmtiles/pmtiles.dart' show ZXY;
import 'package:trailbuddy/features/offline_areas/tile_store.dart';
import 'package:trailbuddy/features/offline_areas/tile_store_idb.dart';

void main() {
  test('echte IndexedDB: Kacheln und Index überstehen eine neue Sitzung, Entfernen wirkt dort auch', () async {
    // Ein grüner Lauf allein bewiese nichts — fiele der Zugang still auf
    // den Speicher zurück, sähe er genauso aus.
    expect(idbFactoryBrowser.persistent, isTrue);

    final bytes = Uint8List.fromList(List.generate(300, (i) => i % 251));
    await IdbTileStore(idbFactoryBrowser).put('dach', TileLayer.map, [
      StoreTile(13, 4380, 2860, bytes, '20261001'),
      StoreTile(12, 2190, 1430, Uint8List(7), '20261001'),
    ]);

    final again = IdbTileStore(idbFactoryBrowser);
    expect(await again.read('dach', TileLayer.map, 13, 4380, 2860), bytes);
    final index = await again.index('dach', TileLayer.map);
    expect(index[const ZXY(13, 4380, 2860).toTileId()]!.bytes, 300);
    expect(index[const ZXY(13, 4380, 2860).toTileId()]!.build, '20261001');
    expect(await again.index('dach', TileLayer.ways), isEmpty, reason: 'Ebenen getrennt');

    await again.remove('dach', TileLayer.map, [const ZXY(13, 4380, 2860).toTileId()]);
    final after = IdbTileStore(idbFactoryBrowser);
    expect(await after.read('dach', TileLayer.map, 13, 4380, 2860), isNull);
    expect((await after.index('dach', TileLayer.map)).keys, [const ZXY(12, 2190, 1430).toTileId()]);
  });
}
