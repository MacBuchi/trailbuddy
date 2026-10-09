// Die Online-Karte (#31, Schritt 2): Manifest vom Host, Archiv per Range —
// und die Regel, wann gar nicht erst gefragt wird.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/features/map/map_providers.dart';
import 'package:trailbuddy/features/map/map_regions.dart';
import 'package:trailbuddy/features/map/online_map.dart';

void main() {
  test('Manifest: Datei, Zoom, Stand — und der Archivpfad unter dem Host', () {
    final m = MapManifest.fromJson({
      'format': 1,
      'file': 'dach-20260928.pmtiles',
      'bytes': 2900000000,
      'maxzoom': 13,
      'source_build': '20260928',
    });
    expect(m.maxZoom, 13);
    expect(m.sourceBuild, '20260928');
    expect(m.archiveUri.toString(), '$kMapTilesBase/dach-20260928.pmtiles');
    expect(kMapTilesBase, startsWith('https://tiles.mcbuchi.de/'));
  });

  test('ein Dateiname, der kein Archivname ist, wird abgelehnt (er wird zu einem Pfad)', () {
    expect(
        () => MapManifest.fromJson({
              'file': '../secret.pmtiles',
              'bytes': 1,
              'maxzoom': 13,
              'source_build': 'x',
            }),
        throwsFormatException);
  });

  test('Höhen-Manifest: Datei und Bau — und ein fremdes Format wird abgelehnt', () {
    final good = {'format': 1, 'file': 'heights-20261001.pmtiles', 'bytes': 240000000, 'zoom': 13, 'grid': 49, 'build': '20261001'};
    final m = HeightsManifest.fromJson(good);
    expect(m.build, '20261001');
    expect(m.archiveUri.toString(), '$kMapTilesBase/heights-20261001.pmtiles');
    expect(kHeightsManifestUrl, '$kMapTilesBase/heights.json');
    expect(() => HeightsManifest.fromJson({...good, 'file': '../x.pmtiles'}), throwsFormatException);
    expect(() => HeightsManifest.fromJson({...good, 'format': 2}), throwsFormatException);
    expect(() => HeightsManifest.fromJson({...good, 'grid': 33}), throwsFormatException);
    expect(() => HeightsManifest.fromJson({...good, 'zoom': 12}), throwsFormatException);
  });

  test('das Höhen-Manifest: ohne Empfang nicht geholt, ein fremdes Format heißt null', () async {
    var asked = 0;
    ProviderContainer make(bool offline, {bool bad = false}) {
      final c = ProviderContainer(overrides: [
        noConnectivityProvider.overrideWithValue(offline),
        heightsManifestLoaderProvider.overrideWithValue(() async {
          asked++;
          if (bad) throw const FormatException('fremd');
          return const HeightsManifest(file: 'heights-20261001.pmtiles', bytes: 1, build: '20261001');
        }),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    expect(await make(true).read(heightsManifestProvider.future), isNull);
    expect(asked, 0);
    expect((await make(false).read(heightsManifestProvider.future))?.build, '20261001');
    expect(await make(false, bad: true).read(heightsManifestProvider.future), isNull);
    expect(asked, 2);
  });

  test('ohne Empfang wird das Manifest nicht geholt; mit Empfang schon', () async {
    var asked = 0;
    ProviderContainer make(bool offline) {
      final c = ProviderContainer(overrides: [
        noConnectivityProvider.overrideWithValue(offline),
        regionsLoaderProvider.overrideWithValue(() async => null),
        mapManifestLoaderProvider.overrideWithValue(() async {
          asked++;
          return const MapManifest(
              file: 'dach-20260928.pmtiles', maxZoom: 13, bytes: 1, sourceBuild: '20260928');
        }),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    expect(await make(true).read(mapManifestProvider.future), isNull);
    expect(asked, 0);
    expect((await make(false).read(mapManifestProvider.future))?.file, 'dach-20260928.pmtiles');
    expect(asked, 1);
  });

  test('ein kaputtes Manifest oder ein toter Host heißt null, nie ein Wurf', () async {
    final c = ProviderContainer(overrides: [
      noConnectivityProvider.overrideWithValue(false),
      regionsLoaderProvider.overrideWithValue(() async => null),
      mapManifestLoaderProvider.overrideWithValue(() async => throw const FormatException('x')),
    ]);
    addTearDown(c.dispose);
    expect(await c.read(mapManifestProvider.future), isNull);
    expect(await c.read(onlineMapStyleProvider.future), isNull,
        reason: 'ohne Manifest keine Online-Karte — die Übersicht bleibt');
  });
}
