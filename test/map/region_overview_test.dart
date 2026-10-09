// Die Übersicht einer Region als Download (#220 Schritt 4,
// `docs/konzept-regionen.md` §5): Sie kommt mit dem ersten Bereich der
// Region, nur wenn sie passt, liegt unter den Bereichen auf der Karte und
// geht mit dem letzten Bereich — „Meine Bereiche" zeigt sie als eigene
// Zeile.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/keep_alive/keep_alive.dart';
import 'package:trailbuddy/features/map/map_providers.dart';
import 'package:trailbuddy/features/map/map_regions.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_style_provider.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';
import 'package:trailbuddy/features/offline_areas/area_store_idb.dart';
import 'package:trailbuddy/features/offline_areas/area_store_io.dart';
import 'package:trailbuddy/features/offline_areas/areas_screen.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/offline_areas/region_overview.dart';
import 'package:trailbuddy/features/official/official_trails_source.dart';

import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_official_trails.dart';
import '../fakes/fake_settings.dart';

/// Der Index, wie `tool/regions.py index` ihn heute schreibt.
const _index = {
  'format': 1,
  'regions': [
    {
      'id': 'dach',
      'name': 'DACH',
      'bbox': [5.5, 45.5, 17.5, 55.5],
      'dir': '',
      'map': 'dach.json',
      'heights': 'heights.json',
      'ways': 'ways.json',
      'pois': 'pois.json',
      'overview': null,
    },
    {
      'id': 'ca',
      'name': 'Kanada',
      'bbox': [-133.2, 41.6, -52.6, 55.0],
      'dir': 'ca/',
      'map': 'ca/map.json',
      'heights': 'ca/heights.json',
      'ways': 'ca/ways.json',
      'pois': 'ca/pois.json',
      'overview': 'ca/overview.json',
    },
  ],
};

const _dachMap = MapManifest(file: 'dach-20261001.pmtiles', maxZoom: 13, bytes: 1, sourceBuild: '20261001');
const _caMapJson = {'file': 'map-20261008.pmtiles', 'maxzoom': 13, 'bytes': 1, 'source_build': '20261008', 'region': 'ca'};

/// Eine kleine Übersicht: je Zoom 0–7 die Kachel über Squamish.
final Uint8List _overview = writePmTiles(
  tiles: [
    for (final t in tilesCovering(const AreaBounds(south: 49.69, west: -123.16, north: 49.71, east: -123.14),
        maxZoom: 7, minZoom: 0))
      TileToWrite(t.z, t.x, t.y, Uint8List.fromList(utf8.encode('overview ${t.z}/${t.x}/${t.y}'))),
  ],
  tileCompression: Compression.none,
  bounds: const TileBounds(west: -141, south: 41.6, east: -52.6, north: 83),
);

Map<String, dynamic> _overviewJson({String build = '20261008', Uint8List? bytes, String? sha}) {
  final b = bytes ?? _overview;
  return {
    'file': 'overview-$build.pmtiles',
    'bytes': b.length,
    'sha256': sha ?? crypto.sha256.convert(b).toString(),
    'maxzoom': 7,
    'source_build': build,
    'format': 1,
    'region': 'ca',
  };
}

/// Zwei Bereiche in Squamish und ein Ausschnitt in DACH.
const _squamish = RectShape(AreaBounds(south: 49.695, west: -123.155, north: 49.705, east: -123.145));
const _squamish2 = RectShape(AreaBounds(south: 49.696, west: -123.154, north: 49.704, east: -123.146));

void main() {
  group('Manifest', () {
    test('liest die Form vom Host, nur im Ordner einer Region', () {
      final m = OverviewManifest.fromJson(_overviewJson(), dir: 'ca/');
      expect(m.archiveUri.toString(), '$kMapTilesBase/ca/overview-20261008.pmtiles');
      expect(m.maxZoom, 7);
      expect(m.sourceBuild, '20261008');
      expect(() => OverviewManifest.fromJson(_overviewJson()), throwsFormatException,
          reason: 'DACH hat seine Übersicht im Binary');
      expect(() => OverviewManifest.fromJson({..._overviewJson(), 'file': '../x.pmtiles'}, dir: 'ca/'),
          throwsFormatException);
      expect(() => OverviewManifest.fromJson({..._overviewJson(), 'file': 'map-20261008.pmtiles'}, dir: 'ca/'),
          throwsFormatException);
      expect(() => OverviewManifest.fromJson(_overviewJson(sha: 'abc'), dir: 'ca/'), throwsFormatException);
    });

    test('die Datei muss zu Länge, Prüfsumme und Zoom passen', () async {
      final m = OverviewManifest.fromJson(_overviewJson(), dir: 'ca/');
      await checkOverview(m, _overview);
      final flipped = Uint8List.fromList(_overview)..[_overview.length - 1] ^= 1;
      await expectLater(checkOverview(m, flipped), throwsA(isA<OverviewMismatch>()));
      await expectLater(checkOverview(m, Uint8List.sublistView(_overview, 1)), throwsA(isA<OverviewMismatch>()));
      final wrongZoom = OverviewManifest.fromJson({..._overviewJson(), 'maxzoom': 8}, dir: 'ca/');
      await expectLater(checkOverview(wrongZoom, _overview), throwsA(isA<OverviewMismatch>()));
    });
  });

  group('mit dem ersten Bereich', () {
    late List<Uri> fetched;

    ProviderContainer make({Map<String, dynamic>? overview, AreaStore? store}) {
      fetched = [];
      const box = AreaBounds(south: 49.69, west: -123.16, north: 49.71, east: -123.14);
      final source = writePmTiles(
        tiles: [
          for (final t in tilesCovering(box, maxZoom: 13))
            TileToWrite(t.z, t.x, t.y, Uint8List.fromList(utf8.encode('${t.z}/${t.x}/${t.y}'))),
        ],
        tileCompression: Compression.none,
        bounds: TileBounds(west: box.west, south: box.south, east: box.east, north: box.north),
      );
      final c = ProviderContainer(overrides: [
        noConnectivityProvider.overrideWithValue(false),
        regionsLoaderProvider.overrideWithValue(() async => jsonEncode(_index)),
        mapManifestLoaderProvider.overrideWithValue(() async => _dachMap),
        regionManifestLoaderProvider.overrideWithValue((uri) async => switch (uri.path) {
              '/trailbuddy/ca/map.json' => _caMapJson,
              '/trailbuddy/ca/overview.json' => overview ?? _overviewJson(),
              _ => null,
            }),
        overviewFetcherProvider.overrideWithValue((uri, {onProgress, check}) async {
          fetched.add(uri);
          check?.call();
          onProgress?.call(_overview.length, _overview.length);
          return _overview;
        }),
        areaPoiManifestLoaderProvider.overrideWithValue(() async => null),
        areaHeightsManifestLoaderProvider.overrideWithValue(() async => null),
        areaWaysManifestLoaderProvider.overrideWithValue(() async => null),
        areaSourceOpenerProvider.overrideWithValue((uri) => PmTilesArchive.fromBytes(source)),
        areaStoreProvider.overrideWithValue(store ?? MemoryAreaStore()),
        tileStoreProvider.overrideWithValue(MemoryTileStore()),
        keepAliveProvider.overrideWithValue(FakeKeepAlive()),
        settingsProvider.overrideWithValue(FakeSettings()),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('kommt sie mit, samt Größe im Plan; der zweite Bereich holt sie nicht noch einmal', () async {
      final store = MemoryAreaStore();
      final c = make(store: store);
      final notifier = c.read(areaDownloadProvider.notifier);
      final plan = await notifier.plan(_squamish);
      expect(plan.overview?.file, 'overview-20261008.pmtiles');
      expect(plan.totalBytes, plan.bytes + _overview.length);
      expect(fetched, isEmpty, reason: 'gemessen wird am Manifest, geholt erst beim Speichern');

      await notifier.start(plan, name: 'Squamish');
      expect(fetched.single.toString(), '$kMapTilesBase/ca/overview-20261008.pmtiles');
      final stored = (await store.overviews()).single;
      expect((stored.region, stored.build, stored.bytes, stored.maxZoom), ('ca', '20261008', _overview.length, 7));
      expect(await store.readOverview('ca'), _overview);
      expect(await c.read(storedOverviewsProvider.future), hasLength(1));

      final second = await notifier.plan(_squamish2);
      expect(second.overview, isNull);
      expect(second.totalBytes, second.bytes);
    });

    test('ein neuerer Bau kommt mit dem nächsten Bereich', () async {
      final store = MemoryAreaStore();
      await store.putOverview(
          StoredOverview(region: 'ca', build: '20260915', bytes: 3, maxZoom: 7, savedAt: DateTime.utc(2026, 9, 15)),
          Uint8List.fromList([1, 2, 3]));
      final c = make(store: store);
      final plan = await c.read(areaDownloadProvider.notifier).plan(_squamish);
      expect(plan.overview?.sourceBuild, '20261008');
      await c.read(areaDownloadProvider.notifier).start(plan, name: 'Squamish');
      expect((await store.overviews()).single.build, '20261008');
    });

    test('eine Datei, die nicht passt, kostet nur die Übersicht', () async {
      final store = MemoryAreaStore();
      final c = make(store: store, overview: _overviewJson(sha: '0' * 64));
      final plan = await c.read(areaDownloadProvider.notifier).plan(_squamish);
      final area = await c.read(areaDownloadProvider.notifier).start(plan, name: 'Squamish');
      expect(area, isNotNull);
      expect(await store.list(), hasLength(1));
      expect(await store.overviews(), isEmpty);
      expect(await store.readOverview('ca'), isNull);
    });

    test('ein Bereich in DACH holt keine — die liegt im Binary', () async {
      final c = make();
      final plan = await c
          .read(areaDownloadProvider.notifier)
          .plan(const RectShape(AreaBounds(south: 47.90, west: 11.60, north: 47.91, east: 11.61)));
      expect(plan.region, 'dach');
      expect(plan.overview, isNull);
    });

    test('geht mit dem letzten Bereich der Region, nicht mit dem vorletzten', () async {
      final store = MemoryAreaStore();
      final c = make(store: store);
      final notifier = c.read(areaDownloadProvider.notifier);
      final a = await notifier.start(await notifier.plan(_squamish), name: 'A');
      final b = await notifier.start(await notifier.plan(_squamish2), name: 'B');
      await c.read(storedAreasProvider.notifier).delete(a!.id);
      expect(await store.overviews(), hasLength(1));
      await c.read(storedAreasProvider.notifier).delete(b!.id);
      expect(await store.overviews(), isEmpty);
      expect(await store.readOverview('ca'), isNull);
      expect(await c.read(storedOverviewsProvider.future), isEmpty);
    });

    test('von Hand gelöscht und allein wieder geholt — die Bereiche bleiben', () async {
      final store = MemoryAreaStore();
      final c = make(store: store);
      final notifier = c.read(areaDownloadProvider.notifier);
      await notifier.start(await notifier.plan(_squamish), name: 'A');
      await c.read(storedAreasProvider.notifier).deleteOverview('ca');
      expect(await store.overviews(), isEmpty);
      expect(await store.list(), hasLength(1));
      fetched.clear();
      final ca = (await c.read(mapRegionsProvider.future)).last;
      expect(await notifier.fetchOverview(ca), isTrue);
      expect(fetched, hasLength(1));
      expect((await store.overviews()).single.region, 'ca');
      expect(await c.read(storedOverviewsProvider.future), hasLength(1));
    });
  });

  group('Ablage', () {
    Future<void> roundTrip(AreaStore store) async {
      expect(await store.overviews(), isEmpty);
      final o = StoredOverview(region: 'ca', build: '20261008', bytes: 3, maxZoom: 7, savedAt: DateTime.utc(2026, 10, 9));
      await store.putOverview(o, Uint8List.fromList([1, 2, 3]));
      await store.putOverview(
          StoredOverview(region: 'ca', build: '20261108', bytes: 4, maxZoom: 7, savedAt: DateTime.utc(2026, 11, 9)),
          Uint8List.fromList([1, 2, 3, 4]));
      expect([for (final o in await store.overviews()) o.build], ['20261108'], reason: 'ersetzt, nicht daneben');
      expect(await store.readOverview('ca'), [1, 2, 3, 4]);
      // Ein Bereich mit allem Drum und Dran fasst sie nicht an.
      await store.putArchive('area-x', Uint8List.fromList([9]));
      await store.delete('area-x');
      expect(await store.readOverview('ca'), [1, 2, 3, 4]);
      await store.deleteOverview('ca');
      expect(await store.overviews(), isEmpty);
      expect(await store.readOverview('ca'), isNull);
      expect(await store.overviewPath('ca'), isNull);
    }

    test('Dateien (Android): neben den Bereichen, also im Backup-Ausschluss', () async {
      final dir = await Directory.systemTemp.createTemp('areas');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileAreaStore(baseDir: dir);
      await store.putOverview(
          StoredOverview(region: 'ca', build: '20261008', bytes: 3, maxZoom: 7, savedAt: DateTime.utc(2026, 10, 9)),
          Uint8List.fromList([1, 2, 3]));
      expect(await store.overviewPath('ca'), '${dir.path}/overview-ca.pmtiles');
      await store.deleteOverview('ca');
      await roundTrip(store);
    });

    test('IndexedDB (Browser)', () => roundTrip(IdbAreaStore(newIdbFactoryMemory())));

    test('Speicher (Test)', () => roundTrip(MemoryAreaStore()));

    test('eine Region im Index, die kein Dateiname sein kann, gilt nicht', () {
      expect(
          () => StoredOverview.fromJson({'region': '../x', 'build': '1', 'bytes': 1, 'max_zoom': 7, 'saved_at': '2026-10-09T00:00:00Z'}),
          throwsFormatException);
    });
  });

  group('auf der Karte (MapLibre)', () {
    Future<Map<String, dynamic>> style({required bool noConnectivity, required bool caFresh}) async {
      final dir = await Directory.systemTemp.createTemp('areas');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileAreaStore(baseDir: dir);
      await store.putOverview(
          StoredOverview(region: 'ca', build: '20261008', bytes: 3, maxZoom: 7, savedAt: DateTime.utc(2026, 10, 9)),
          Uint8List.fromList([1, 2, 3]));
      final c = ProviderContainer(overrides: [
        maplibreStyleIoProvider.overrideWithValue(_FakeIo()),
        areaStoreProvider.overrideWithValue(store),
        tileStoreProvider.overrideWithValue(MemoryTileStore()),
        noConnectivityProvider.overrideWithValue(noConnectivity),
        regionsLoaderProvider.overrideWithValue(() async => jsonEncode(_index)),
        mapManifestLoaderProvider.overrideWithValue(() async => _dachMap),
        waysManifestLoaderProvider.overrideWithValue(() async => null),
        regionManifestLoaderProvider.overrideWithValue(
            (uri) async => caFresh && uri.path == '/trailbuddy/ca/map.json' ? _caMapJson : null),
        settingsProvider.overrideWithValue(FakeSettings(officialTrailsEnabled: false)),
        officialTrailsSourceProvider.overrideWithValue(FakeOfficialTrailsSource()),
        officialTrailsCacheProvider.overrideWithValue(MemoryOfficialTrailsCache()),
      ]);
      addTearDown(c.dispose);
      return jsonDecode((await c.read(maplibreStyleProvider.future))!) as Map<String, dynamic>;
    }

    test('ohne Empfang über der DACH-Übersicht, unter allem anderen', () async {
      final s = await style(noConnectivity: true, caFresh: false);
      final sources = s['sources'] as Map<String, dynamic>;
      expect(sources.keys.take(2), ['overview', 'overview-ca']);
      expect(sources['overview-ca']['url'], startsWith('pmtiles://file://'));
      expect(sources['overview-ca']['url'], endsWith('/overview-ca.pmtiles'));
      expect(sources['overview-ca']['maxzoom'], 7);
    });

    test('mit frischer Karte der Region nicht — dort ist die Online-Karte die Karte', () async {
      final s = await style(noConnectivity: false, caFresh: true);
      expect((s['sources'] as Map).keys, isNot(contains('overview-ca')));
      final host = await style(noConnectivity: false, caFresh: false);
      expect((host['sources'] as Map).keys, contains('overview-ca'), reason: 'Host für Kanada weg: die Übersicht');
    });
  });

  group('Meine Bereiche', () {
    Future<MemoryAreaStore> pump(WidgetTester tester, {required bool withOverview, bool online = true}) async {
      final store = MemoryAreaStore();
      await store.saveIndex([
        StoredArea(
          id: 'a1',
          name: 'Squamish',
          bounds: _squamish.bounds,
          minZoom: 8,
          maxZoom: 13,
          build: '20261008',
          tiles: 10,
          bytes: 1000000,
          savedAt: DateTime.utc(2026, 10, 9),
          region: 'ca',
        ),
      ]);
      if (withOverview) {
        await store.putOverview(
            StoredOverview(
                region: 'ca', build: '20261008', bytes: _overview.length, maxZoom: 7, savedAt: DateTime.utc(2026, 10, 9)),
            _overview);
      }
      await tester.pumpWidget(ProviderScope(
        overrides: [
          noConnectivityProvider.overrideWithValue(!online),
          regionsLoaderProvider.overrideWithValue(() async => jsonEncode(_index)),
          mapManifestLoaderProvider.overrideWithValue(() async => _dachMap),
          regionManifestLoaderProvider.overrideWithValue((uri) async => switch (uri.path) {
                '/trailbuddy/ca/map.json' => _caMapJson,
                '/trailbuddy/ca/overview.json' => _overviewJson(),
                _ => null,
              }),
          overviewFetcherProvider.overrideWithValue((uri, {onProgress, check}) async => _overview),
          heightsManifestLoaderProvider.overrideWithValue(() async => null),
          areaWaysManifestLoaderProvider.overrideWithValue(() async => null),
          areaStoreProvider.overrideWithValue(store),
          tileStoreProvider.overrideWithValue(MemoryTileStore()),
          keepAliveProvider.overrideWithValue(FakeKeepAlive()),
          settingsProvider.overrideWithValue(FakeSettings()),
        ],
        child: const MaterialApp(home: AreasScreen()),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return store;
    }

    testWidgets('eine eigene Zeile mit Größe und Stand; Löschen nimmt nur sie', (tester) async {
      final store = await pump(tester, withOverview: true);
      final row = find.byKey(const ValueKey('overview-ca'));
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Übersicht Kanada')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('Stand 08.10.2026')), findsOneWidget);
      expect(find.byKey(const ValueKey('overview-fetch-ca')), findsNothing, reason: 'liegt schon, gleicher Stand');
      await tester.tap(find.byKey(const ValueKey('overview-delete-ca')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(await store.overviews(), isEmpty);
      expect(await store.list(), hasLength(1));
      expect(find.byKey(const ValueKey('overview-fetch-ca')), findsOneWidget, reason: 'zurückholen geht allein');
    });

    testWidgets('fehlt sie, holt der Knopf nur sie', (tester) async {
      final store = await pump(tester, withOverview: false);
      expect(find.textContaining('Nicht auf dem Gerät'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('overview-fetch-ca')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect((await store.overviews()).single.region, 'ca');
      expect(find.byKey(const ValueKey('overview-delete-ca')), findsOneWidget);
    });

    testWidgets('der letzte Bereich sagt, dass die Übersicht mitgeht', (tester) async {
      await pump(tester, withOverview: true);
      await tester.tap(find.byKey(const ValueKey('area-delete-a1')));
      await tester.pump();
      expect(find.textContaining('die Übersichtskarte der Region geht mit'), findsOneWidget);
    });
  });
}

class _FakeIo extends MapLibreStyleIo {
  @override
  Future<String> loadBaseStyle() async => jsonEncode({
        'version': 8,
        'sources': {},
        'layers': [
          {'id': 'earth', 'type': 'fill', 'source': 'protomaps', 'source-layer': 'earth'},
        ],
      });

  @override
  Future<String> materializeOverview() async => '/fake/offline_maps/overview_dach.pmtiles';

  @override
  Future<String> materializeGlyphs() async => 'file:///fake/map_glyphs/{fontstack}/{range}.pbf';

  @override
  Future<({int min, int max})> readZoomRange(String path) async => (min: 0, max: 7);
}
