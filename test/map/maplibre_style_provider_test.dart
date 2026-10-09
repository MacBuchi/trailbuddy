// Der Style-Provider ist die I/O-Schicht über dem puren Composer: Welche
// Quellen er wann zusammensetzt, ist die Regel „Online-Karte vom Host,
// sobald das Manifest da ist; die Übersicht darunter ohne Empfang oder
// ohne Manifest; die gespeicherten Bereiche immer zuoberst (#82)" —
// dieselbe wie in der flutter_map-Engine.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_style_provider.dart';
import 'package:trailbuddy/features/map/map_regions.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';
import 'package:trailbuddy/features/offline_areas/tile_store_io.dart';
import 'package:trailbuddy/features/official/official_trails_source.dart';

import '../fakes/fake_official_trails.dart';
import '../fakes/fake_settings.dart';

/// I/O-Fake: liefert feste Pfade und Header-Zoombereiche, merkt sich, für
/// welche Dateien der Header gelesen wurde.
class _FakeIo extends MapLibreStyleIo {
  final readHeaders = <String>[];
  bool failOverview = false;

  @override
  Future<String> loadBaseStyle() async => jsonEncode({
        'version': 8,
        'sources': {},
        'layers': [
          {'id': 'earth', 'type': 'fill', 'source': 'protomaps', 'source-layer': 'earth'},
        ],
      });

  @override
  Future<String> materializeOverview() async {
    if (failOverview) throw StateError('Asset kaputt');
    return '/fake/offline_maps/overview_dach.pmtiles';
  }

  @override
  Future<String> materializeGlyphs() async => 'file:///fake/map_glyphs/{fontstack}/{range}.pbf';

  @override
  Future<({int min, int max})> readZoomRange(String path) async {
    readHeaders.add(path);
    return (min: 0, max: 7);
  }
}

const _manifest = MapManifest(
  file: 'dach-20260928.pmtiles',
  maxZoom: 13,
  bytes: 2900000000,
  sourceBuild: '20260928',
);

void main() {
  (ProviderContainer, _FakeIo) make({
    required bool noConnectivity,
    MapManifest? manifest = _manifest,
    bool officialOn = false,
    FakeOfficialTrailsSource? official,
    AreaStore? areaStore,
    TileStore? tileStore,
    WaysManifest? ways,
    FakeSettings? settings,
  }) {
    final io = _FakeIo();
    final container = ProviderContainer(overrides: [
      maplibreStyleIoProvider.overrideWithValue(io),
      areaStoreProvider.overrideWithValue(areaStore ?? MemoryAreaStore()),
      tileStoreProvider.overrideWithValue(tileStore ?? MemoryTileStore()),
      noConnectivityProvider.overrideWithValue(noConnectivity),
      regionsLoaderProvider.overrideWithValue(() async => null),
      mapManifestLoaderProvider.overrideWithValue(() async => manifest),
      settingsProvider.overrideWithValue(settings ?? FakeSettings(officialTrailsEnabled: officialOn)),
      waysManifestLoaderProvider.overrideWithValue(() async => ways),
      officialTrailsSourceProvider.overrideWithValue(official ?? FakeOfficialTrailsSource()),
      officialTrailsCacheProvider.overrideWithValue(MemoryOfficialTrailsCache()),
    ]);
    addTearDown(container.dispose);
    return (container, io);
  }

  Future<Map<String, dynamic>> styleOf(ProviderContainer c) async =>
      jsonDecode((await c.read(maplibreStyleProvider.future))!) as Map<String, dynamic>;

  List<String> sourceIds(Map<String, dynamic> style) =>
      (style['sources'] as Map<String, dynamic>).keys.toList();

  test('online mit Manifest: nur die Online-Karte, kein Archiv-Header gelesen', () async {
    final (container, io) = make(noConnectivity: false);
    final style = await styleOf(container);
    expect(sourceIds(style), ['online']);
    final online = (style['sources'] as Map)['online'] as Map;
    expect(online['url'], 'pmtiles://https://tiles.mcbuchi.de/trailbuddy/dach-20260928.pmtiles');
    expect(online['maxzoom'], 13, reason: 'aus dem Manifest, nicht aus einer Range-Anfrage');
    expect(io.readHeaders, isEmpty);
    expect(style['glyphs'], 'file:///fake/map_glyphs/{fontstack}/{range}.pbf');
  });

  test('ohne Empfang: die Übersicht allein — das Manifest wird gar nicht erst geholt', () async {
    var asked = 0;
    final io = _FakeIo();
    final container = ProviderContainer(overrides: [
      maplibreStyleIoProvider.overrideWithValue(io),
      areaStoreProvider.overrideWithValue(MemoryAreaStore()),
      noConnectivityProvider.overrideWithValue(true),
      regionsLoaderProvider.overrideWithValue(() async => null),
      mapManifestLoaderProvider.overrideWithValue(() async {
        asked++;
        return _manifest;
      }),
      settingsProvider.overrideWithValue(FakeSettings()),
      waysManifestLoaderProvider.overrideWithValue(() async => null),
      officialTrailsSourceProvider.overrideWithValue(FakeOfficialTrailsSource()),
      officialTrailsCacheProvider.overrideWithValue(MemoryOfficialTrailsCache()),
    ]);
    addTearDown(container.dispose);
    final style = await styleOf(container);
    expect(sourceIds(style), ['overview']);
    expect(asked, 0, reason: 'ein Funkloch ist kein Grund für einen Fehlversuch');
    expect(io.readHeaders, ['/fake/offline_maps/overview_dach.pmtiles']);
    final ids = (style['layers'] as List).map((l) => (l as Map)['id']).toList();
    expect(ids, ['hintergrund', 'overview/earth']);
  });

  test('online ohne Manifest (Host weg): die Übersicht ist die Karte', () async {
    final (container, _) = make(noConnectivity: false, manifest: null);
    expect(sourceIds(await styleOf(container)), ['overview']);
  });

  test('ein Manifest, das nicht kommt, hält die Karte nicht auf (#183) — kommt es spät, '
      'wechselt der Stil', () async {
    final late = Completer<MapManifest?>();
    final io = _FakeIo();
    final container = ProviderContainer(overrides: [
      maplibreStyleIoProvider.overrideWithValue(io),
      areaStoreProvider.overrideWithValue(MemoryAreaStore()),
      noConnectivityProvider.overrideWithValue(false),
      regionsLoaderProvider.overrideWithValue(() async => null),
      mapManifestLoaderProvider.overrideWithValue(() => late.future),
      settingsProvider.overrideWithValue(FakeSettings()),
      waysManifestLoaderProvider.overrideWithValue(() async => null),
      officialTrailsSourceProvider.overrideWithValue(FakeOfficialTrailsSource()),
      officialTrailsCacheProvider.overrideWithValue(MemoryOfficialTrailsCache()),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(maplibreStyleProvider, (_, _) {});
    addTearDown(sub.close);
    final watch = Stopwatch()..start();
    expect(sourceIds(await styleOf(container)), ['overview']);
    expect(watch.elapsed, lessThan(kMapManifestPatience + const Duration(seconds: 1)),
        reason: 'die Übersicht nach der Frist, nicht nach dem Abbruch des Abrufs');
    late.complete(_manifest);
    await Future<void>.delayed(Duration.zero);
    expect(sourceIds(await styleOf(container)), ['online']);
  });

  test('I/O-Fehler ⇒ null statt Wurf (die Engine fällt auf flutter_map zurück)', () async {
    final (container, io) = make(noConnectivity: true);
    io.failOverview = true;
    expect(await container.read(maplibreStyleProvider.future), isNull);
  });

  test('die Quellen der offiziellen Trails stehen im Style, sobald eine Region geladen ist',
      () async {
    final source = FakeOfficialTrailsSource({
      'index.json': fakeIndex(),
      'testland.geojson': fakeRegion(),
    });
    final (container, _) = make(noConnectivity: false, officialOn: true, official: source);
    var style = await styleOf(container);
    expect(((style['sources'] as Map)['online'] as Map)['attribution'],
        '© OpenStreetMap contributors · Protomaps');

    await container
        .read(officialTrailsControllerProvider.notifier)
        .ensure((s: 47.9, w: 8.9, n: 48.1, e: 9.1));
    style = await styleOf(container);
    expect(((style['sources'] as Map)['online'] as Map)['attribution'],
        '© OpenStreetMap contributors · Protomaps · Land Testland (CC0 1.0)');
  });

  /// Ein Bereich als Verweis (#229) und seine Kacheln im MBTiles-Speicher
  /// — die Datei, deren Pfad MapLibre als `mbtiles://` bekommt.
  Future<(MemoryAreaStore, SqliteTileStore)> storeWithArea({bool withWays = false}) async {
    final dir = await Directory.systemTemp.createTemp('tiles');
    final tiles = SqliteTileStore(baseDir: dir);
    addTearDown(() async {
      tiles.close();
      await dir.delete(recursive: true);
    });
    await tiles.put('dach', TileLayer.map, [StoreTile(13, 4380, 2860, Uint8List.fromList([1, 2, 3]), '20260928')]);
    if (withWays) {
      await tiles.put('dach', TileLayer.ways, [StoreTile(13, 4380, 2860, Uint8List.fromList([4, 5]), '20261101')]);
    }
    final store = MemoryAreaStore();
    await store.saveIndex([
      StoredArea(
        id: 'a1',
        name: 'Isartrails',
        bounds: const AreaBounds(south: 47.9, west: 11.6, north: 47.95, east: 11.7),
        minZoom: 8,
        maxZoom: 13,
        build: '20260928',
        tiles: 42,
        bytes: 3,
        savedAt: DateTime.utc(2026, 9, 28),
        wayTiles: withWays ? 1 : 0,
        wayBytes: withWays ? 2 : 0,
        waysBuild: withWays ? '20261101' : null,
        format: kStoredAreaFormat,
      ),
    ]);
    return (store, tiles);
  }

  group('gespeicherte Bereiche (Konzept-Schritt 3)', () {
    test('ohne Empfang liegt der Speicher der Region als mbtiles://-Quelle über der Übersicht (#229)', () async {
      final (store, tiles) = await storeWithArea();
      final (c, _) = make(noConnectivity: true, areaStore: store, tileStore: tiles);
      final style = await styleOf(c);
      expect(sourceIds(style), ['overview', 'area-dach'], reason: 'EINE Quelle je Region, nicht je Bereich');
      final area = (style['sources'] as Map)['area-dach'] as Map;
      expect(area['url'], allOf(startsWith('mbtiles:///'), endsWith('/dach/map.mbtiles')));
      expect(area['minzoom'], 8);
      expect(area['maxzoom'], 13);
      // Und die Ebenen des Basis-Styles gibt es für die Quelle noch einmal.
      expect((style['layers'] as List).any((l) => (l as Map)['id'] == 'area-dach/earth'), isTrue);
    });

    test('zwei Bereiche einer Region bleiben EINE Quelle', () async {
      final (store, tiles) = await storeWithArea();
      final one = (await store.list()).single;
      await store.saveIndex([one, StoredArea.fromJson({...one.toJson(), 'id': 'a2'})]);
      final (c, _) = make(noConnectivity: true, areaStore: store, tileStore: tiles);
      expect(sourceIds(await styleOf(c)), ['overview', 'area-dach']);
    });

    test('mit Empfang liegen sie ÜBER der Online-Karte (#82)', () async {
      // Bis 0.36.x nur ['online']: Bei schwachem Empfang meldet das
      // Telefon ein Netz, die Online-Kacheln kommen nie — und die
      // gespeicherten wurden gar nicht gefragt.
      final (store, tiles) = await storeWithArea();
      final (c, _) = make(noConnectivity: false, areaStore: store, tileStore: tiles);
      final style = await styleOf(c);
      expect(sourceIds(style), ['online', 'area-dach'], reason: 'Reihenfolge = Schichtung');
      final ids = (style['layers'] as List).map((l) => (l as Map)['id']).toList();
      expect(ids.indexOf('area-dach/earth'), greaterThan(ids.indexOf('online/earth')),
          reason: 'die deckende Fläche des Bereichs liegt über der Online-Karte');
    });

    test('ohne Manifest (Host weg): Übersicht, dann der Bereich', () async {
      final (store, tiles) = await storeWithArea();
      final (c, _) = make(noConnectivity: false, manifest: null, areaStore: store, tileStore: tiles);
      expect(sourceIds(await styleOf(c)), ['overview', 'area-dach']);
    });

    test('ohne Pfad (Browser) keine Quelle — der Canvas-Renderer liest den Speicher', () async {
      final (store, _) = await storeWithArea();
      final memory = MemoryTileStore();
      await memory.put('dach', TileLayer.map, [StoreTile(13, 4380, 2860, Uint8List.fromList([1]), 'b')]);
      final (c, _) = make(noConnectivity: true, areaStore: store, tileStore: memory);
      expect(sourceIds(await styleOf(c)), ['overview']);
    });
  });

  group('Wege (#212)', () {
    const ways = WaysManifest(file: 'ways-20261101.pmtiles', bytes: 92300000, build: '20261101');

    test('über allen Kartenquellen, auch über den Bereichen, mit eigenen Ebenen', () async {
      final (store, tiles) = await storeWithArea();
      final (c, _) = make(noConnectivity: false, areaStore: store, tileStore: tiles, ways: ways);
      final style = await styleOf(c);
      expect(sourceIds(style), ['online', 'area-dach', kWaysSourceId]);
      final src = (style['sources'] as Map)[kWaysSourceId] as Map;
      expect(src['url'], 'pmtiles://https://tiles.mcbuchi.de/trailbuddy/ways-20261101.pmtiles');
      expect([src['minzoom'], src['maxzoom']], [kWaysZoom, kWaysZoom]);
      expect(src.containsKey('attribution'), isFalse, reason: 'OSM steht schon an der Karte');
      final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
      final ids = layers.map((l) => l['id']).toList();
      final firstWay = ids.indexWhere((id) => (id as String).startsWith('$kWaysSourceId/'));
      expect(firstWay, greaterThan(ids.indexOf('area-dach/earth')),
          reason: 'die deckende Fläche eines Bereichs deckte die Wege sonst zu');
      expect(ids.sublist(firstWay), [for (final l in wayStyleLayers(kWaysSourceId, dashes: true)) l['id']],
          reason: 'MapLibre bekommt die Fassung MIT Strich');
    });

    test('Schalter aus: kein Abruf, keine Quelle', () async {
      var asked = 0;
      final container = ProviderContainer(overrides: [
        maplibreStyleIoProvider.overrideWithValue(_FakeIo()),
        areaStoreProvider.overrideWithValue(MemoryAreaStore()),
        noConnectivityProvider.overrideWithValue(false),
        regionsLoaderProvider.overrideWithValue(() async => null),
        mapManifestLoaderProvider.overrideWithValue(() async => _manifest),
        settingsProvider.overrideWithValue(FakeSettings(wayLayerEnabled: false)),
        waysManifestLoaderProvider.overrideWithValue(() async {
          asked++;
          return ways;
        }),
        officialTrailsSourceProvider.overrideWithValue(FakeOfficialTrailsSource()),
        officialTrailsCacheProvider.overrideWithValue(MemoryOfficialTrailsCache()),
      ]);
      addTearDown(container.dispose);
      expect(sourceIds(await styleOf(container)), ['online']);
      expect(asked, 0, reason: 'aus heißt: keine Anfrage');
    });

    test('ein spätes Wege-Manifest hält die Karte nicht auf und baut den Stil neu', () async {
      final late = Completer<WaysManifest?>();
      final container = ProviderContainer(overrides: [
        maplibreStyleIoProvider.overrideWithValue(_FakeIo()),
        areaStoreProvider.overrideWithValue(MemoryAreaStore()),
        noConnectivityProvider.overrideWithValue(false),
        regionsLoaderProvider.overrideWithValue(() async => null),
        mapManifestLoaderProvider.overrideWithValue(() async => _manifest),
        settingsProvider.overrideWithValue(FakeSettings()),
        waysManifestLoaderProvider.overrideWithValue(() => late.future),
        officialTrailsSourceProvider.overrideWithValue(FakeOfficialTrailsSource()),
        officialTrailsCacheProvider.overrideWithValue(MemoryOfficialTrailsCache()),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(maplibreStyleProvider, (_, _) {});
      addTearDown(sub.close);
      final watch = Stopwatch()..start();
      expect(sourceIds(await styleOf(container)), ['online']);
      expect(watch.elapsed, lessThan(kMapManifestPatience + const Duration(seconds: 1)));
      late.complete(ways);
      await Future<void>.delayed(Duration.zero);
      expect(sourceIds(await styleOf(container)), ['online', kWaysSourceId]);
    });

    test('ohne Empfang: kein Abruf', () async {
      final (c, _) = make(noConnectivity: true, ways: ways);
      expect(sourceIds(await styleOf(c)), ['overview']);
    });

    group('aus gespeicherten Bereichen (#212, PR 3)', () {
      const areaWays = '$kWaysSourceId-area-dach';

      test('ohne Empfang: die Wege der Region als mbtiles://-Quelle über dem Bereich', () async {
        final (store, tiles) = await storeWithArea(withWays: true);
        final (c, _) = make(noConnectivity: true, areaStore: store, tileStore: tiles, ways: ways);
        final style = await styleOf(c);
        expect(sourceIds(style), ['overview', 'area-dach', areaWays]);
        final src = (style['sources'] as Map)[areaWays] as Map;
        expect(src['url'], allOf(startsWith('mbtiles:///'), endsWith('/dach/ways.mbtiles')));
        expect([src['minzoom'], src['maxzoom']], [kWaysZoom, kWaysZoom]);
        final ids = (style['layers'] as List).map((l) => (l as Map)['id']).toList();
        expect(ids.indexWhere((id) => (id as String).startsWith('$areaWays/')), greaterThan(ids.indexOf('area-dach/earth')));
        expect(ids.where((id) => (id as String).startsWith('$areaWays/')),
            [for (final l in wayStyleLayers(areaWays, dashes: true)) l['id']]);
      });

      test('mit Empfang: über den Wegen vom Host', () async {
        final (store, tiles) = await storeWithArea(withWays: true);
        final (c, _) = make(noConnectivity: false, areaStore: store, tileStore: tiles, ways: ways);
        expect(sourceIds(await styleOf(c)), ['online', 'area-dach', kWaysSourceId, areaWays]);
      });

      test('Schalter aus: auch die Wege der Bereiche nicht', () async {
        final (store, tiles) = await storeWithArea(withWays: true);
        final (c, _) = make(
            noConnectivity: true,
            manifest: null,
            areaStore: store,
            tileStore: tiles,
            settings: FakeSettings(wayLayerEnabled: false));
        expect(sourceIds(await styleOf(c)), ['overview', 'area-dach']);
      });
    });
  });

  group('Gesehenes bleibt liegen (#155)', () {
    const ways = WaysManifest(file: 'ways-20261101.pmtiles', bytes: 92300000, build: '20261101');
    String url(Map<String, dynamic> style, String id) => ((style['sources'] as Map)[id] as Map)['url'] as String;

    test('mit Empfang wird das Manifest von Karte und Wegen gemerkt', () async {
      final settings = FakeSettings();
      final (c, _) = make(noConnectivity: false, ways: ways, settings: settings);
      await styleOf(c);
      await Future<void>.delayed(Duration.zero);
      expect(MapManifest.fromJson(jsonDecode(settings.seenMapManifest!) as Map<String, dynamic>).file,
          'dach-20260928.pmtiles');
      expect(WaysManifest.fromJson(jsonDecode(settings.seenWaysManifest!) as Map<String, dynamic>).file,
          'ways-20261101.pmtiles');
    });

    test('ohne Empfang nennt der Stil die gemerkten Archive, über der Übersicht — '
        'MapLibre liest sie aus seinem Zwischenspeicher', () async {
      final settings = FakeSettings(
        seenMapManifest: jsonEncode(_manifest.toJson()),
        seenWaysManifest: jsonEncode(ways.toJson()),
      );
      final (c, _) = make(noConnectivity: true, settings: settings);
      final style = await styleOf(c);
      expect(sourceIds(style), ['overview', 'online', kWaysSourceId],
          reason: 'die Übersicht darunter: wo nichts gemerkt ist, scheint sie durch');
      expect(url(style, 'online'), 'pmtiles://https://tiles.mcbuchi.de/trailbuddy/dach-20260928.pmtiles');
      expect(url(style, kWaysSourceId), 'pmtiles://https://tiles.mcbuchi.de/trailbuddy/ways-20261101.pmtiles');
    });

    test('Host weg (ein Balken ohne Daten): ebenso', () async {
      final settings = FakeSettings(seenMapManifest: jsonEncode(_manifest.toJson()));
      final (c, _) = make(noConnectivity: false, manifest: null, settings: settings);
      expect(sourceIds(await styleOf(c)), ['overview', 'online']);
    });

    test('ein frisches Manifest gilt vor dem gemerkten, ohne Übersicht', () async {
      final settings = FakeSettings(seenMapManifest: jsonEncode(const MapManifest(
              file: 'dach-20260801.pmtiles', maxZoom: 13, bytes: 1, sourceBuild: '20260801')
          .toJson()));
      final (c, _) = make(noConnectivity: false, settings: settings);
      final style = await styleOf(c);
      expect(sourceIds(style), ['online']);
      expect(url(style, 'online'), endsWith('/dach-20260928.pmtiles'));
      await Future<void>.delayed(Duration.zero);
      expect(settings.seenMapManifest, contains('dach-20260928.pmtiles'));
    });

    test('Wege-Schalter aus: auch keine gemerkten Wege', () async {
      final settings = FakeSettings(
        wayLayerEnabled: false,
        seenMapManifest: jsonEncode(_manifest.toJson()),
        seenWaysManifest: jsonEncode(ways.toJson()),
      );
      final (c, _) = make(noConnectivity: true, settings: settings);
      expect(sourceIds(await styleOf(c)), ['overview', 'online']);
    });

    test('Gemerktes, das nicht mehr passt (fremdes Wege-Format, Unsinn), heißt still keins', () async {
      final settings = FakeSettings(
        seenMapManifest: '{kaputt',
        seenWaysManifest: jsonEncode({...ways.toJson(), 'format': kWaysFormat + 1}),
      );
      final (c, _) = make(noConnectivity: true, settings: settings);
      expect(sourceIds(await styleOf(c)), ['overview']);
    });
  });
}
