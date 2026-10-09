// „Gesehenes bleibt liegen" im Browser (#155): der Speicher in IndexedDB
// (hier dieselbe Implementierung im Speicher), der Kachel-Lieferant davor
// und die Regel der Stile — gemerktes Manifest ohne Empfang, Übersicht
// darunter, Android unverändert.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipEncoder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/map/base_map_providers.dart';
import 'package:trailbuddy/features/map/map_view/flutter_map_view.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/map_regions.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/map/pmtiles_tile_provider.dart';
import 'package:trailbuddy/features/map/seen_tiles.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../fakes/fake_settings.dart';

const _manifest = MapManifest(file: 'dach-20261001.pmtiles', maxZoom: 13, bytes: 1, sourceBuild: '20261001');
const _ways = WaysManifest(file: 'ways-20261008.pmtiles', bytes: 1, build: '20261008');

final _tile = vmt.TileIdentity(13, 4321, 2876);
final _other = vmt.TileIdentity(13, 4322, 2876);
final _content = Uint8List.fromList(List.generate(300, (i) => i % 7));

// Der Schreiber legt Kacheln ab, wie sie kommen — gzip also vorher, wie
// in den Archiven des Hosts.
Uint8List _archive() => writePmTiles(
      tiles: [TileToWrite(_tile.z, _tile.x, _tile.y, Uint8List.fromList(GZipEncoder().encode(_content)!))],
      tileCompression: Compression.gzip,
      bounds: const TileBounds(west: 9.8, south: 47.8, east: 9.9, north: 47.9),
    );

SeenTile _bytes(int n) => SeenTile(Uint8List(n), gzip: false);

void main() {
  group('IdbSeenTileStore', () {
    test('legt ab und liest zurück — auch in einer neuen Sitzung', () async {
      final factory = newIdbFactoryMemory();
      final store = IdbSeenTileStore(factory);
      expect(await store.read('a/13/1/1'), isNull);
      await store.write('a/13/1/1', SeenTile(Uint8List.fromList([1, 2, 3]), gzip: true));
      final back = await store.read('a/13/1/1');
      expect(back?.bytes, [1, 2, 3]);
      expect(back?.gzip, isTrue);

      final again = IdbSeenTileStore(factory);
      expect((await again.read('a/13/1/1'))?.bytes, [1, 2, 3],
          reason: 'der Index wird beim ersten Zugriff aus IndexedDB gelesen');
      expect(again.totalBytes, 3);
    });

    test('über der Grenze geht die am längsten nicht gebrauchte zuerst, bis 90 %', () async {
      var now = DateTime(2026, 10, 8, 8);
      final factory = newIdbFactoryMemory();
      final store = IdbSeenTileStore(factory, capBytes: 1000, now: () => now);
      for (final key in ['k1', 'k2', 'k3', 'k4']) {
        await store.write(key, _bytes(250));
        now = now.add(const Duration(hours: 2));
      }
      // k1 wieder gebraucht — länger als die Schwelle her, also aufgefrischt.
      expect(await store.read('k1'), isNotNull);
      now = now.add(const Duration(hours: 2));
      await store.write('k5', _bytes(250));
      // 1250 > 1000: geräumt bis 900, also zwei — die beiden ältesten
      // ungenutzten, nicht k1.
      expect(store.totalBytes, 750);
      expect(await store.read('k2'), isNull);
      expect(await store.read('k3'), isNull);
      for (final key in ['k1', 'k4', 'k5']) {
        expect(await store.read(key), isNotNull, reason: key);
      }

      final again = IdbSeenTileStore(factory, capBytes: 1000, now: () => now);
      expect(await again.read('k2'), isNull, reason: 'auch in IndexedDB weg, nicht nur im Index');
      expect(again.totalBytes, 750);
    });

    test('ein Speicher, der nicht aufgeht, ist leer und wirft nie', () async {
      final store = IdbSeenTileStore(_BrokenFactory());
      expect(await store.read('x'), isNull);
      await store.write('x', _bytes(10));
      expect(await store.read('x'), isNull);
    });
  });

  group('SeenTilesVectorTileProvider', () {
    test('erst der Host, dann der Speicher — komprimiert abgelegt, ausgepackt geliefert', () async {
      final store = IdbSeenTileStore(newIdbFactoryMemory());
      final online = await PmTilesVectorTileProvider.openBytes(_archive());
      final provider = SeenTilesVectorTileProvider(
          archive: _manifest.file, store: store, online: online, minZoom: 0, maxZoom: 13);
      expect(provider.seenOnly, isFalse);
      expect(await provider.provide(_tile), _content);
      // Abgelegt wird nebenher.
      await pumpEventQueue();
      final stored = await store.read('dach-20261001.pmtiles/13/4321/2876');
      expect(stored?.gzip, isTrue);
      expect(stored!.bytes, isNot(_content), reason: 'gzip, wie im Archiv');

      await online.close();
      final offline = SeenTilesVectorTileProvider(
          archive: _manifest.file, store: store, online: null, minZoom: 0, maxZoom: 13);
      expect(offline.seenOnly, isTrue);
      expect(await offline.provide(_tile), _content, reason: 'ohne Host aus dem Speicher');
      expect(() => offline.provide(_other), throwsA(isA<vmt.ProviderException>()),
          reason: 'nicht gesehen heißt „Kachel fehlt" — die Übersicht scheint durch');
    });

    test('der Speicher geht vor, auch mit Host (eine Range-Anfrage weniger, #55)', () async {
      final store = IdbSeenTileStore(newIdbFactoryMemory());
      await store.write('dach-20261001.pmtiles/13/4322/2876', SeenTile(Uint8List.fromList([9]), gzip: false));
      final online = await PmTilesVectorTileProvider.openBytes(_archive());
      addTearDown(online.close);
      final provider = SeenTilesVectorTileProvider(
          archive: _manifest.file, store: store, online: online, minZoom: 0, maxZoom: 13);
      expect(await provider.provide(_other), [9], reason: 'das Archiv hat diese Kachel nicht — sie kam aus dem Speicher');
    });

    test('ein anderer Bau hat andere Schlüssel', () async {
      final store = IdbSeenTileStore(newIdbFactoryMemory());
      final online = await PmTilesVectorTileProvider.openBytes(_archive());
      addTearDown(online.close);
      await SeenTilesVectorTileProvider(
              archive: _manifest.file, store: store, online: online, minZoom: 0, maxZoom: 13)
          .provide(_tile);
      await pumpEventQueue();
      final next = SeenTilesVectorTileProvider(
          archive: 'dach-20261101.pmtiles', store: store, online: null, minZoom: 0, maxZoom: 13);
      expect(() => next.provide(_tile), throwsA(isA<vmt.ProviderException>()));
    });
  });

  group('Stile der flutter_map-Engine', () {
    ProviderContainer make({
      required bool offline,
      SeenTileStore? store,
      Settings? settings,
      bool wayLayer = true,
    }) {
      final c = ProviderContainer(overrides: [
        noConnectivityProvider.overrideWithValue(offline),
        seenTileStoreProvider.overrideWithValue(store),
        settingsProvider.overrideWithValue(settings ?? FakeSettings(wayLayerEnabled: wayLayer)),
        regionsLoaderProvider.overrideWithValue(() async => null),
        mapManifestLoaderProvider.overrideWithValue(() async => _manifest),
        waysManifestLoaderProvider.overrideWithValue(() async => _ways),
        onlineArchiveOpenerProvider.overrideWithValue((_) => PmTilesVectorTileProvider.openBytes(_archive())),
        baseThemeWithoutBackgroundProvider.overrideWith((ref) async => vtr.ThemeReader().read({'version': 8, 'layers': []})),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    vmt.VectorTileProvider? providerOf(BaseMapStyle? style) => style?.tileProviders.tileProviderBySource.values.single;

    test('mit Empfang: Host plus Speicher, und das Manifest wird gemerkt', () async {
      final settings = FakeSettings();
      final c = make(offline: false, store: IdbSeenTileStore(newIdbFactoryMemory()), settings: settings);
      final map = providerOf(await c.read(onlineMapStyleProvider.future));
      expect(map, isA<SeenTilesVectorTileProvider>().having((p) => p.seenOnly, 'seenOnly', isFalse));
      final ways = providerOf(await c.read(onlineWaysStyleProvider.future));
      expect(ways, isA<SeenTilesVectorTileProvider>().having((p) => p.archive, 'archive', _ways.file));
      expect(jsonDecode(settings.seenMapManifest!)['file'], _manifest.file);
      expect(jsonDecode(settings.seenWaysManifest!)['file'], _ways.file);
    });

    test('ohne Empfang: das gemerkte Manifest, nur der Speicher', () async {
      final settings = FakeSettings(
        seenMapManifest: jsonEncode(_manifest.toJson()),
        seenWaysManifest: jsonEncode(_ways.toJson()),
      );
      final c = make(offline: true, store: IdbSeenTileStore(newIdbFactoryMemory()), settings: settings);
      final style = await c.read(onlineMapStyleProvider.future);
      expect(providerOf(style),
          isA<SeenTilesVectorTileProvider>()
              .having((p) => p.seenOnly, 'seenOnly', isTrue)
              .having((p) => p.archive, 'archive', _manifest.file));
      expect(seenOnlyProviders(style!.tileProviders), isTrue);
      expect(providerOf(await c.read(onlineWaysStyleProvider.future)),
          isA<SeenTilesVectorTileProvider>().having((p) => p.seenOnly, 'seenOnly', isTrue));
    });

    test('ohne Empfang und Ebene „Wege" aus: keine gemerkten Wege', () async {
      final settings = FakeSettings(wayLayerEnabled: false, seenWaysManifest: jsonEncode(_ways.toJson()));
      final c = make(offline: true, store: IdbSeenTileStore(newIdbFactoryMemory()), settings: settings);
      expect(await c.read(onlineWaysStyleProvider.future), isNull);
    });

    test('ohne Speicher (Android-Rückfall, Test-VM) bleibt alles, wie es war', () async {
      final settings = FakeSettings(seenMapManifest: jsonEncode(_manifest.toJson()));
      final offline = make(offline: true, settings: settings);
      expect(await offline.read(onlineMapStyleProvider.future), isNull);
      final online = make(offline: false, settings: settings);
      expect(providerOf(await online.read(onlineMapStyleProvider.future)), isA<PmTilesVectorTileProvider>());
    });
  });

  group('die Übersicht unter gesehenen Kacheln', () {
    BaseMapStyle style(vmt.VectorTileProvider provider) => BaseMapStyle(
          theme: vtr.ThemeReader().read({
            'version': 8,
            'sources': {
              'protomaps': {'type': 'vector'},
            },
            'layers': [
              {
                'id': 'earth',
                'type': 'fill',
                'source': 'protomaps',
                'source-layer': 'earth',
                'paint': {'fill-color': '#e2dfda'},
              },
            ],
          }),
          tileProviders: vmt.TileProviders({'protomaps': provider}),
        );

    for (final seenOnly in [true, false]) {
      testWidgets(seenOnly ? 'nur Gesehenes: Übersicht darunter' : 'frisch: keine Übersicht', (tester) async {
        final online = await tester.runAsync(() => PmTilesVectorTileProvider.openBytes(_archive()));
        final store = IdbSeenTileStore(newIdbFactoryMemory());
        final provider = SeenTilesVectorTileProvider(
            archive: _manifest.file, store: store, online: seenOnly ? null : online, minZoom: 0, maxZoom: 13);
        final base = style(provider);
        const config = MapViewConfig(
          initialCenter: LatLng(47.85, 9.85),
          initialZoom: 12,
          minZoom: 3,
          maxZoom: 19,
          backgroundColor: AppColors.mapBackground,
        );
        await tester.pumpWidget(ProviderScope(
          overrides: [
            noConnectivityProvider.overrideWithValue(false),
            onlineMapStyleProvider.overrideWith((ref) async => style(provider)),
            baseMapStyleProvider.overrideWith((ref) async => base),
            areaMapStyleProvider.overrideWith((ref) async => null),
            onlineWaysStyleProvider.overrideWith((ref) async => null),
            areaWaysStyleProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: FlutterMapView(
              config: config,
              controller: MapViewController(initialCenter: config.initialCenter, initialZoom: 12),
              layers: const MapViewLayers(),
            ),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(find.byKey(const ValueKey('base-map')), seenOnly ? findsOneWidget : findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 1));
        await tester.runAsync(() async => online!.close());
      });
    }
  });
}

/// Eine IndexedDB, die sich nicht öffnen lässt (privater Modus).
class _BrokenFactory implements IdbFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('kein IndexedDB');
}
