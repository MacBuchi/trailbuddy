// Regionen des Kartenhosts (#220): Der Index ist streng, DACH kommt aus
// dem Binary, und jede Ebene wählt ihre Region nach der Lage — Karte und
// Wege beider Engines, Orte, Höhen, gespeicherte Bereiche.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/keep_alive/keep_alive.dart';
import 'package:trailbuddy/features/map/map_providers.dart';
import 'package:trailbuddy/features/map/map_regions.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_style_provider.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/poi_source.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/official/official_trails_source.dart';
import 'package:trailbuddy/features/routing/online_fill.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_official_trails.dart';
import '../fakes/fake_settings.dart';

/// Der Index, wie `tool/regions.py index` ihn heute schreibt.
Map<String, dynamic> _index({Map<String, dynamic> ca = const {}}) => {
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
          ...ca,
        },
      ],
    };

final _ca = parseRegionIndex(_index()).single;

const _dachMap = MapManifest(file: 'dach-20261001.pmtiles', maxZoom: 13, bytes: 1, sourceBuild: '20261001');
const _caMapJson = {'file': 'map-20261008.pmtiles', 'maxzoom': 13, 'bytes': 1, 'source_build': '20261008', 'region': 'ca'};
const _caWaysJson = {'file': 'ways-20261017.pmtiles', 'format': kWaysFormat, 'zoom': kWaysZoom, 'bytes': 1, 'build': '20261017'};

/// Squamish (British Columbia), ein Ort im Rahmen von Kanada.
const _caLat = 49.70, _caLng = -123.15;

void main() {
  group('Index', () {
    test('DACH im Binary hat den Rahmen aus tool/regions.json', () {
      final config = jsonDecode(File('tool/regions.json').readAsStringSync()) as Map<String, dynamic>;
      final dach = (config['regions'] as List).cast<Map<String, dynamic>>().firstWhere((r) => r['id'] == 'dach');
      final [w, s, e, n] = (dach['bbox'] as List).cast<num>();
      expect([kDachRegion.box.w, kDachRegion.box.s, kDachRegion.box.e, kDachRegion.box.n], [w, s, e, n]);
      // Und jede Region der Konfiguration ist eine, die der Leser annimmt.
      final ids = [for (final r in config['regions'] as List) r['id']];
      expect(ids.first, 'dach');
    });

    test('liest die Regionen außer DACH, mit Ordner und den Manifesten, die es gibt', () {
      final regions = parseRegionIndex(_index(ca: {'heights': null, 'pois': null}));
      expect(regions, hasLength(1), reason: 'DACH kommt aus dem Binary');
      final ca = regions.single;
      expect([ca.id, ca.name, ca.dir], ['ca', 'Kanada', 'ca/']);
      expect(ca.manifests.keys, unorderedEquals([RegionLayer.map, RegionLayer.ways, RegionLayer.overview]));
      expect(ca.manifestUri(RegionLayer.map).toString(), '$kMapTilesBase/ca/map.json');
      expect(ca.contains(const LatLng(_caLat, _caLng)), isTrue);
      expect(rememberedRegions(encodeRegions(regions)), regions, reason: 'merken und zurücklesen');
    });

    for (final (what, change) in [
      ('ein Pfad außerhalb des Ordners', {'map': 'ca/../dach.json'}),
      ('ein fremder Ordner', {'dir': 'dach/'}),
      ('ohne Karte', {'map': null}),
      ('ein Rahmen über DACH', {'bbox': [10.0, 50.0, 20.0, 60.0]}),
      ('ein verkehrter Rahmen', {'bbox': [-52.6, 41.6, -133.2, 55.0]}),
      ('eine Kennung mit Schrägstrich', {'id': 'c/a', 'dir': 'c/a/'}),
    ]) {
      test('lehnt den ganzen Index ab: $what', () {
        expect(() => parseRegionIndex(_index(ca: change)), throwsFormatException);
      });
    }

    test('lehnt ein fremdes Format und eine doppelte Kennung ab', () {
      expect(() => parseRegionIndex({..._index(), 'format': 2}), throwsFormatException);
      final twice = _index();
      (twice['regions'] as List).add((twice['regions'] as List).last);
      expect(() => parseRegionIndex(twice), throwsFormatException);
    });
  });

  group('mapRegionsProvider', () {
    ProviderContainer make(Future<String?> Function() load, {bool offline = false, FakeSettings? settings}) {
      final c = ProviderContainer(overrides: [
        regionsLoaderProvider.overrideWithValue(load),
        noConnectivityProvider.overrideWithValue(offline),
        settingsProvider.overrideWithValue(settings ?? FakeSettings()),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('ohne Index DACH allein — die App bis 0.103', () async {
      expect(await make(() async => null).read(mapRegionsProvider.future), [kDachRegion]);
    });

    test('mit Index DACH zuerst, dann die übrigen; der Index wird gemerkt', () async {
      final settings = FakeSettings();
      final regions = await make(() async => jsonEncode(_index()), settings: settings).read(mapRegionsProvider.future);
      expect(regions.map((r) => r.id), ['dach', 'ca']);
      expect(rememberedRegions(settings.seenRegions), [_ca]);
    });

    test('ohne Empfang oder bei Fehler der gemerkte, ohne Merker DACH allein', () async {
      final settings = FakeSettings(seenRegions: encodeRegions([_ca]));
      var asked = 0;
      Future<String?> load() async {
        asked++;
        throw http.ClientException('weg');
      }

      expect(await make(load, offline: true, settings: settings).read(mapRegionsProvider.future), [kDachRegion, _ca]);
      expect(asked, 0, reason: 'ohne Empfang wird nicht gefragt');
      expect(await make(load, settings: settings).read(mapRegionsProvider.future), [kDachRegion, _ca]);
      expect(await make(() async => '{"format": 9}').read(mapRegionsProvider.future), [kDachRegion]);
    });
  });

  group('Manifeste', () {
    test('Kanada: map-… im Ordner ca/, DACH: dach-… an der Wurzel — nie über Kreuz', () {
      final ca = MapManifest.fromJson(_caMapJson, dir: 'ca/');
      expect(ca.archiveUri.toString(), '$kMapTilesBase/ca/map-20261008.pmtiles');
      expect(MapManifest.fromJson(ca.toJson()).archiveUri, ca.archiveUri, reason: 'gemerkt mit Ordner');
      expect(_dachMap.toJson().containsKey('dir'), isFalse, reason: 'DACH merkt sich wie vor #220');
      expect(() => MapManifest.fromJson(_caMapJson), throwsFormatException);
      expect(() => MapManifest.fromJson(_dachMap.toJson(), dir: 'ca/'), throwsFormatException);
      expect(() => MapManifest.fromJson(_caMapJson, dir: '../'), throwsFormatException);
      expect(WaysManifest.fromJson(_caWaysJson, dir: 'ca/').archiveUri.toString(),
          '$kMapTilesBase/ca/ways-20261017.pmtiles');
      final pois = PoiManifest.fromJson({'format': 1, 'build': '20261016', 'prefix': 'pois-20261016', 'cells': <String, dynamic>{}},
          dir: 'ca/');
      expect(pois.folder, 'ca/pois-20261016');
    });
  });

  test('flutter_map: EINE Quelle, je Kachel das Archiv ihrer Region', () async {
    final dach = _Labelled('dach');
    final ca = _Labelled('ca');
    final source = RegionTileProvider([(box: kDachRegion.box, provider: dach), (box: _ca.box, provider: ca)]);
    final inCa = tileAt(_caLat, _caLng, 12);
    final inDach = tileAt(47.5, 11.0, 12);
    final atlantic = tileAt(45.0, -30.0, 12);
    expect(utf8.decode(await source.provide(TileIdentity(12, inCa.x, inCa.y))), 'ca');
    expect(utf8.decode(await source.provide(TileIdentity(12, inDach.x, inDach.y))), 'dach');
    await expectLater(source.provide(TileIdentity(12, atlantic.x, atlantic.y)), throwsA(isA<ProviderException>()));
    expect(dach.asked, 1, reason: 'Kanada fragt das DACH-Archiv nie');

    // Mit nur einer Region bleibt es ihr Archiv selbst.
    expect(regionSource([kDachRegion], [(region: kDachRegion, provider: dach)]), same(dach));
    expect(regionSource([kDachRegion, _ca], [(region: kDachRegion, provider: dach), (region: _ca, provider: null)]),
        isA<RegionTileProvider>());
  });

  test('MapLibre: je Region Karte und Wege als eigene Quelle mit Rahmen', () async {
    final c = ProviderContainer(overrides: [
      maplibreStyleIoProvider.overrideWithValue(_FakeIo()),
      areaStoreProvider.overrideWithValue(MemoryAreaStore()),
      noConnectivityProvider.overrideWithValue(false),
      regionsLoaderProvider.overrideWithValue(() async => jsonEncode(_index())),
      mapManifestLoaderProvider.overrideWithValue(() async => _dachMap),
      waysManifestLoaderProvider.overrideWithValue(() async => null),
      regionManifestLoaderProvider.overrideWithValue((uri) async => switch (uri.path) {
            '/trailbuddy/ca/map.json' => _caMapJson,
            '/trailbuddy/ca/ways.json' => _caWaysJson,
            _ => null,
          }),
      settingsProvider.overrideWithValue(FakeSettings(officialTrailsEnabled: false)),
      officialTrailsSourceProvider.overrideWithValue(FakeOfficialTrailsSource()),
      officialTrailsCacheProvider.overrideWithValue(MemoryOfficialTrailsCache()),
    ]);
    addTearDown(c.dispose);
    final style = jsonDecode((await c.read(maplibreStyleProvider.future))!) as Map<String, dynamic>;
    final sources = style['sources'] as Map<String, dynamic>;
    expect(sources.keys, ['online', 'online-ca', 'ways-region-ca']);
    expect(sources['online-ca']['url'], 'pmtiles://$kMapTilesBase/ca/map-20261008.pmtiles');
    expect(sources['online-ca']['bounds'], [-133.2, 41.6, -52.6, 55.0]);
    expect(sources['online']['bounds'], [5.5, 45.5, 17.5, 55.5]);
    expect(sources['ways-region-ca']['url'], 'pmtiles://$kMapTilesBase/ca/ways-20261017.pmtiles');
    expect([for (final l in style['layers'] as List) if (l['source'] == 'ways-region-ca') l['id']], isNotEmpty);
  });

  group('Orte nach Lage', () {
    test('eine Zelle in Kanada fragt ca/pois.json und den Ordner der Region, eine in DACH die Wurzel', () async {
      final asked = <String>[];
      final caCell = poiCellOf(const LatLng(_caLat, _caLng));
      const dachCell = '475,60';
      Map<String, dynamic> manifest(String cell) => {
            'format': 1,
            'build': '20261016',
            'prefix': 'pois-20261016',
            'cells': {
              'water': [cell],
            },
          };
      final source = HostPoiSource(
        client: MockClient((req) async {
          asked.add(req.url.path);
          return switch (req.url.path) {
            '/trailbuddy/pois.json' => http.Response(jsonEncode(manifest(dachCell)), 200),
            '/trailbuddy/ca/pois.json' => http.Response(jsonEncode(manifest(caCell)), 200),
            _ => http.Response(jsonEncode({'format': 1, 'pois': []}), 200),
          };
        }),
        regions: () async => [kDachRegion, _ca],
      );
      await source.fetch([caCell, dachCell, '0,0'], {PoiGroup.water});
      expect(asked, unorderedEquals([
        '/trailbuddy/ca/pois.json',
        '/trailbuddy/ca/pois-20261016/${poiCellFileName(caCell, PoiGroup.water)}',
        '/trailbuddy/pois.json',
        '/trailbuddy/pois-20261016/${poiCellFileName(dachCell, PoiGroup.water)}',
      ]), reason: 'die Zelle im Golf von Guinea gehört keiner Region und fragt nichts');
    });

    test('eine Region ohne Orte im Index fragt gar nicht', () async {
      var asked = 0;
      final noPois = parseRegionIndex(_index(ca: {'pois': null})).single;
      final source = HostPoiSource(
          client: MockClient((req) async {
            asked++;
            return http.Response('', 404);
          }),
          regions: () async => [kDachRegion, noPois]);
      expect(await source.fetch([poiCellOf(const LatLng(_caLat, _caLng))], {PoiGroup.water}), isEmpty);
      expect(asked, 0);
    });
  });

  test('Höhen nach Lage: je Kachel die Quelle ihrer Region, außerhalb keine', () async {
    final opened = <String>[];
    final heights = RegionHeights(
      regions: () async => [kDachRegion, _ca],
      open: (region) {
        opened.add(region.id);
        return _NoHeights();
      },
    );
    final inCa = tileAt(_caLat, _caLng, kHeightTileZoom);
    final inDach = tileAt(47.5, 11.0, kHeightTileZoom);
    final atlantic = tileAt(45.0, -30.0, kHeightTileZoom);
    await heights.tile(inCa.x, inCa.y);
    await heights.tile(inCa.x + 1, inCa.y);
    await heights.tile(atlantic.x, atlantic.y);
    expect(opened, ['ca'], reason: 'eine Quelle je Region, keine im Atlantik');
    await heights.tile(inDach.x, inDach.y);
    expect(opened, ['ca', 'dach']);
    await heights.close();
  });

  group('Bereiche', () {
    test('ein Eintrag von vor 0.104.0 ist DACH; die Region reist mit', () {
      final json = StoredArea(
        id: 'a',
        name: 'a',
        bounds: const AreaBounds(south: 49.6, west: -123.2, north: 49.7, east: -123.1),
        minZoom: 8,
        maxZoom: 13,
        build: '20261008',
        tiles: 1,
        bytes: 1,
        savedAt: DateTime.utc(2026, 10, 9),
        region: 'ca',
      ).toJson();
      expect(StoredArea.fromJson(json).region, 'ca');
      expect(StoredArea.fromJson({...json}..remove('region')).region, 'dach');
    });

    ProviderContainer make(List<Uri> opened) {
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
        regionsLoaderProvider.overrideWithValue(() async => jsonEncode(_index())),
        mapManifestLoaderProvider.overrideWithValue(() async => _dachMap),
        regionManifestLoaderProvider.overrideWithValue(
            (uri) async => uri.path == '/trailbuddy/ca/map.json' ? _caMapJson : null),
        areaPoiManifestLoaderProvider.overrideWithValue(() async => null),
        areaHeightsManifestLoaderProvider.overrideWithValue(() async => null),
        areaWaysManifestLoaderProvider.overrideWithValue(() async => null),
        areaSourceOpenerProvider.overrideWithValue((uri) {
          opened.add(uri);
          return PmTilesArchive.fromBytes(source);
        }),
        areaStoreProvider.overrideWithValue(MemoryAreaStore()),
        keepAliveProvider.overrideWithValue(FakeKeepAlive()),
        settingsProvider.overrideWithValue(FakeSettings()),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('in Kanada gegen das Archiv der Region gemessen und gespeichert', () async {
      final opened = <Uri>[];
      final c = make(opened);
      final notifier = c.read(areaDownloadProvider.notifier);
      final plan = await notifier.plan(
          const RectShape(AreaBounds(south: 49.695, west: -123.155, north: 49.705, east: -123.145)));
      expect(plan.region, 'ca');
      expect(plan.tiles, isNotEmpty);
      expect(opened.single.toString(), '$kMapTilesBase/ca/map-20261008.pmtiles');
      final area = await notifier.start(plan, name: 'Squamish');
      expect(area?.region, 'ca');
      expect(area?.build, '20261008');
    });

    test('außerhalb aller Regionen: ein Satz, kein Abruf', () async {
      final opened = <Uri>[];
      final c = make(opened);
      await expectLater(
          c.read(areaDownloadProvider.notifier).plan(
              const RectShape(AreaBounds(south: 44.9, west: -30.1, north: 45.0, east: -30.0))),
          throwsA(isA<OutsideRegions>().having((e) => e.message, 'Satz', contains('DACH, Kanada'))));
      expect(opened, isEmpty);
    });
  });
}

class _Labelled extends VectorTileProvider {
  _Labelled(this.label);
  final String label;
  int asked = 0;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    asked++;
    return Uint8List.fromList(utf8.encode(label));
  }

  @override
  int get minimumZoom => 0;

  @override
  int get maximumZoom => 13;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;
}

class _NoHeights implements HeightTileSource {
  @override
  Future<HeightTile?> tile(int x, int y) async => null;

  @override
  Future<void> close() async {}
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
