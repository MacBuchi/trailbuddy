// Die Bereiche in der App: wie mehrere Bereiche zu EINER Kachelquelle der
// flutter_map-Engine werden — seit 0.106.0 (#229) über den Kachelspeicher
// ihrer Region, in den die Liste beim ersten Lesen den Altbestand
// übernimmt.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/map/map_regions.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../fakes/fake_settings.dart';

const _manifest = MapManifest(file: 'dach-20260928.pmtiles', maxZoom: 13, bytes: 1, sourceBuild: '20260928');

Uint8List _archive(AreaBounds b, String tag) => writePmTiles(
      tiles: [
        for (final t in tilesCovering(b, maxZoom: 9))
          TileToWrite(t.z, t.x, t.y, Uint8List.fromList(utf8.encode('$tag ${t.z}/${t.x}/${t.y}'))),
      ],
      tileCompression: Compression.none,
      bounds: TileBounds(west: b.west, south: b.south, east: b.east, north: b.north),
    );

StoredArea _area(String id, AreaBounds b) => StoredArea(
      id: id,
      name: id,
      bounds: b,
      minZoom: 8,
      maxZoom: 9,
      build: '20260928',
      tiles: 1,
      bytes: 1,
      savedAt: DateTime.utc(2026, 9, 28),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer make({required bool noConnectivity, MapManifest? manifest = _manifest, AreaStore? store}) {
    final c = ProviderContainer(overrides: [
      noConnectivityProvider.overrideWithValue(noConnectivity),
      regionsLoaderProvider.overrideWithValue(() async => null),
      mapManifestLoaderProvider.overrideWithValue(() async => manifest),
      areaStoreProvider.overrideWithValue(store ?? MemoryAreaStore()),
      tileStoreProvider.overrideWithValue(MemoryTileStore()),
      settingsProvider.overrideWithValue(FakeSettings()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('zwei Bereiche werden EINE Kachelquelle: der erste, der die Kachel hat, liefert', () async {
    const west = AreaBounds(south: 47.9, west: 11.0, north: 48.0, east: 11.2);
    const east = AreaBounds(south: 47.9, west: 12.0, north: 48.0, east: 12.2);
    final store = MemoryAreaStore();
    await store.putArchive('w', _archive(west, 'west'));
    await store.putArchive('e', _archive(east, 'east'));
    await store.saveIndex([_area('w', west), _area('e', east)]);

    final c = make(noConnectivity: true, store: store);
    // Die Liste übernimmt beide Archive in den Speicher der Region.
    final areas = await c.read(storedAreasProvider.future);
    expect(areas.every((a) => !a.legacy), isTrue);
    expect(store.archives, isEmpty, reason: 'der Altbestand ist nach der Übernahme weg');
    // Der Stil kommt aus dem Asset — das der Test-Runner nicht liefert;
    // die Kachelquelle selbst braucht ihn nicht.
    final opened = [
      for (final a in areas)
        (minZoom: a.minZoom, maxZoom: a.maxZoom, provider: (await c.read(areaArchiveOpenerProvider)(store, a))!),
    ];
    final multi = MultiAreaTileProvider(opened);
    expect(multi.minimumZoom, kAreaMinZoom);
    expect(multi.maximumZoom, 9);

    final inWest = tileAt(47.95, 11.1, 9);
    final inEast = tileAt(47.95, 12.1, 9);
    expect(utf8.decode(await multi.provide(TileIdentity(9, inWest.x, inWest.y))), startsWith('west'));
    expect(utf8.decode(await multi.provide(TileIdentity(9, inEast.x, inEast.y))), startsWith('east'));
    final nowhere = tileAt(50, 8, 9);
    await expectLater(multi.provide(TileIdentity(9, nowhere.x, nowhere.y)), throwsA(isA<ProviderException>()));
    await expectLater(multi.provide(TileIdentity(12, 0, 0)), throwsA(isA<ProviderException>()),
        reason: 'über dem Zoom der Bereiche');
    await multi.close();
  });

  test('die Wege der Bereiche (#212): EINE Quelle nur bei Zoom 13, nur aus Bereichen mit Wegen, aus mit dem Schalter', () async {
    const west = AreaBounds(south: 47.9, west: 11.0, north: 48.0, east: 11.2);
    final store = MemoryAreaStore();
    final inWest = tileAt(47.95, 11.1, kWaysZoom);
    await store.putWays(
        'w',
        writePmTiles(
          tiles: [TileToWrite(kWaysZoom, inWest.x, inWest.y, Uint8List.fromList(utf8.encode('weg')))],
          tileCompression: Compression.none,
          bounds: TileBounds(west: west.west, south: west.south, east: west.east, north: west.north),
        ));
    final withWays = StoredArea.fromJson({..._area('w', west).toJson(), 'way_tiles': 1, 'way_bytes': 1});
    await store.saveIndex([withWays, _area('plain', west)]);

    final c = make(noConnectivity: true, store: store);
    await c.read(storedAreasProvider.future);
    final style = await c.read(areaWaysStyleProvider.future);
    expect(style, isNotNull);
    final multi = style!.tileProviders.tileProviderBySource[kWaysSourceId]!;
    expect([multi.minimumZoom, multi.maximumZoom], [kWaysZoom, kWaysZoom]);
    expect(utf8.decode(await multi.provide(TileIdentity(kWaysZoom, inWest.x, inWest.y))), 'weg');
    await expectLater(multi.provide(TileIdentity(kWaysZoom, inWest.x + 1, inWest.y)), throwsA(isA<ProviderException>()));

    final off = ProviderContainer(overrides: [
      noConnectivityProvider.overrideWithValue(true),
      areaStoreProvider.overrideWithValue(store),
      tileStoreProvider.overrideWithValue(MemoryTileStore()),
      settingsProvider.overrideWithValue(FakeSettings(wayLayerEnabled: false)),
    ]);
    addTearDown(off.dispose);
    expect(await off.read(areaWaysStyleProvider.future), isNull);
  });

  test('ohne Bereiche keine Schicht; ein Bereich ohne Kacheln liefert „fehlt" statt einer Kachel', () async {
    final c = make(noConnectivity: true);
    expect(await c.read(areaMapStyleProvider.future), isNull);

    final store = MemoryAreaStore();
    await store.saveIndex([_area('ghost', const AreaBounds(south: 47, west: 11, north: 48, east: 12))]);
    final c2 = make(noConnectivity: true, store: store);
    final ghost = (await c2.read(storedAreasProvider.future)).single;
    expect(ghost.legacy, isFalse, reason: 'ohne Archiv gibt es nichts zu übernehmen — der Eintrag bleibt');
    final source = (await c2.read(areaArchiveOpenerProvider)(store, ghost))!;
    final t = tileAt(47.5, 11.5, 9);
    await expectLater(source.provide(TileIdentity(9, t.x, t.y)), throwsA(isA<ProviderException>()));
  });
}
