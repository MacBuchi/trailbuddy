// Manifeste des Kartenhosts höchstens einmal am Tag (#596 H4): gemerkt,
// geteilt, frisch nach „Aktualisieren", und die Lader der Ebenen gehen
// alle über dieselbe Stelle.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:trailbuddy/data/seen_host_files.dart';
import 'package:trailbuddy/features/map/host_manifests.dart';
import 'package:trailbuddy/features/map/map_providers.dart';
import 'package:trailbuddy/features/map/map_regions.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';

const _map = {
  'format': 1,
  'file': 'dach-20261101.pmtiles',
  'bytes': 2900000000,
  'maxzoom': 13,
  'source_build': '20261101',
};

const _heights = {
  'format': 1,
  'file': 'heights-20261001.pmtiles',
  'bytes': 240000000,
  'zoom': 13,
  'grid': 49,
  'build': '20261001',
};

/// Ein Host, der zählt; [body] je Pfad, sonst 404.
class _Host {
  _Host(this.body);
  final Map<String, Object> body;
  final asked = <String>[];
  Completer<void>? hold;

  Future<http.Response> get(Uri uri) async {
    asked.add(uri.path);
    await hold?.future;
    final b = body[uri.path.split('/').last];
    if (b == null) return http.Response('', 404);
    if (b is int) return http.Response('', b);
    return http.Response(jsonEncode(b), 200);
  }
}

MapManifest _parseMap(String t) =>
    MapManifest.fromJson(jsonDecode(t) as Map<String, dynamic>);

void main() {
  late DateTime now;
  late MemorySeenHostFiles seen;
  late _Host host;
  HostManifests manifests() =>
      HostManifests(seen: seen, get: host.get, now: () => now);
  final uri = Uri.parse(kMapManifestUrl);

  setUp(() {
    now = DateTime(2026, 11, 20, 8);
    seen = MemorySeenHostFiles(now: () => now);
    host = _Host({'dach.json': _map, 'heights.json': _heights});
  });

  test('ein gemerktes Manifest unter 24 h kostet keine Anfrage — '
      'auch nach einem Neustart (neue Instanz, dieselbe Ablage)', () async {
    expect((await manifests().load(uri, _parseMap))!.sourceBuild, '20261101');
    now = now.add(const Duration(hours: 23));
    expect((await manifests().load(uri, _parseMap))!.sourceBuild, '20261101');
    expect(host.asked, ['/trailbuddy/dach.json']);
    expect(seen.texts.keys, ['dach.json'], reason: 'Pfad unter dem Host');
  });

  test(
    'älter als 24 h: die App fragt wieder und merkt sich die Antwort',
    () async {
      await manifests().load(uri, _parseMap);
      now = now.add(const Duration(hours: 25));
      await manifests().load(uri, _parseMap);
      expect(host.asked, hasLength(2));
      now = now.add(const Duration(hours: 1));
      await manifests().load(uri, _parseMap);
      expect(host.asked, hasLength(2));
    },
  );

  test(
    '„Aktualisieren" (expire) fragt einmal frisch, danach gilt das neue',
    () async {
      final m = manifests();
      await m.load(uri, _parseMap);
      m.expire();
      now = now.add(const Duration(minutes: 1));
      await m.load(uri, _parseMap);
      await m.load(uri, _parseMap);
      expect(host.asked, hasLength(2));
    },
  );

  test('gleichzeitige Fragen teilen eine Anfrage', () async {
    host.hold = Completer();
    final m = manifests();
    final a = m.load(uri, _parseMap);
    final b = m.load(uri, _parseMap);
    await Future<void>.delayed(Duration.zero);
    host.hold!.complete();
    await Future.wait([a, b]);
    expect(host.asked, hasLength(1));
  });

  test(
    'ein gemerktes Manifest, das diese Fassung nicht liest, ist keins',
    () async {
      await seen.write('dach.json', '{"file": "../x"}');
      expect((await manifests().load(uri, _parseMap))!.sourceBuild, '20261101');
      expect(host.asked, hasLength(1));
    },
  );

  test(
    'eine kaputte Antwort wird nicht gemerkt; 404 ist null, 5xx wirft',
    () async {
      host.body['dach.json'] = {'file': 'kaputt'};
      await expectLater(manifests().load(uri, _parseMap), throwsA(anything));
      expect(seen.texts, isEmpty);

      host.body.remove('dach.json');
      expect(await manifests().load(uri, _parseMap), isNull);
      expect(seen.texts, isEmpty);

      host.body['dach.json'] = 503;
      await expectLater(
        manifests().load(uri, _parseMap),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test('remembered: jedes Alter, nie eine Anfrage', () async {
    expect(await manifests().remembered(uri, _parseMap), isNull);
    await manifests().load(uri, _parseMap);
    now = now.add(const Duration(days: 30));
    expect(
      (await manifests().remembered(uri, _parseMap))!.sourceBuild,
      '20261101',
    );
    expect(host.asked, hasLength(1));
  });

  test('Karte, Höhen, Wege, Regionen und die Lader der Bereiche gehen über '
      'dieselbe Stelle', () async {
    host.body['ways.json'] = 404;
    host.body['regions.json'] = {'format': 1, 'regions': <Object>[]};
    final c = ProviderContainer(
      overrides: [hostManifestsProvider.overrideWithValue(manifests())],
    );
    addTearDown(c.dispose);
    for (var i = 0; i < 2; i++) {
      await c.read(mapManifestLoaderProvider)();
      await c.read(heightsManifestLoaderProvider)();
      await c.read(areaHeightsManifestLoaderProvider)();
      await c.read(areaWaysManifestLoaderProvider)();
      await c.read(regionsLoaderProvider)();
      await c.read(regionManifestLoaderProvider)(
        Uri.parse('$kMapTilesBase/ca/heights.json'),
      );
    }
    expect(host.asked.toSet(), {
      '/trailbuddy/dach.json',
      '/trailbuddy/heights.json',
      '/trailbuddy/ways.json',
      '/trailbuddy/regions.json',
      '/trailbuddy/ca/heights.json',
    });
    // Gemerkt sind nur die, die es gibt: dach, heights, regions — und die
    // fehlenden (404) fragen jedes Mal.
    expect(
      host.asked.where((p) => p.endsWith('/dach.json')),
      hasLength(1),
      reason: 'Karte: einmal',
    );
    expect(
      host.asked.where((p) => p == '/trailbuddy/heights.json'),
      hasLength(1),
      reason: 'Höhen: Karte und Bereich teilen das gemerkte',
    );
    expect(host.asked.where((p) => p.endsWith('/regions.json')), hasLength(1));
    expect(
      () => fetchWaysManifest(manifests()),
      throwsA(isA<http.ClientException>()),
      reason: '404 bleibt für die Wege ein Fehler wie bisher',
    );
  });

  test('rememberedHeightsManifest liest das gemerkte der Region', () async {
    final m = manifests();
    expect(await rememberedHeightsManifest(m, kDachRegion), isNull);
    await fetchHeightsManifest(m);
    expect(
      (await rememberedHeightsManifest(m, kDachRegion))!.file,
      'heights-20261001.pmtiles',
    );
  });
}
