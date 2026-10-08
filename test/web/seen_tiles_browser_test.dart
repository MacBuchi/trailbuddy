// Der Speicher gesehener Kacheln (#155) in einer ECHTEN IndexedDB —
// läuft nur mit `flutter test --platform chrome` (CI: Schritt „Web-Test
// auf dart2js"). Auf der VM ist `kIsWeb` falsch und jeder Web-Zweig
// ungeprüft; die Speicher-Fassung von idb_shim gibt Werte anders zurück
// als der Browser (PilzBuddy #385).
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:trailbuddy/features/map/seen_tiles.dart';

void main() {
  test('echte IndexedDB: Bytes und Index überstehen eine neue Sitzung, geräumt wird auch dort', () async {
    // Ein grüner Lauf allein bewiese nichts — fiele der Zugang still auf
    // den Speicher zurück, sähe er genauso aus.
    expect(idbFactoryBrowser.persistent, isTrue);

    final bytes = Uint8List.fromList(List.generate(500, (i) => i % 251));
    final store = IdbSeenTileStore(idbFactoryBrowser, capBytes: 1200);
    await store.write('t/13/1/1', SeenTile(bytes, gzip: true));
    await store.write('t/13/1/2', SeenTile(Uint8List(500), gzip: false));

    final again = IdbSeenTileStore(idbFactoryBrowser, capBytes: 1200);
    final back = await again.read('t/13/1/1');
    expect(back, isNotNull);
    expect(back!.bytes, bytes);
    expect(back.gzip, isTrue);
    expect(again.totalBytes, 1000);

    await again.write('t/13/1/3', SeenTile(Uint8List(500), gzip: false));
    expect(again.totalBytes, lessThanOrEqualTo(1080));
    expect(await IdbSeenTileStore(idbFactoryBrowser).read('t/13/1/1'), isNull,
        reason: 'die älteste ist auch in IndexedDB weg');
  });
}
