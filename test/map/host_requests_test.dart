// Anfragen an den Kartenhost zählen (#596 H7, docs/konzept-traffic.md).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trailbuddy/features/map/host_requests.dart';
import 'package:trailbuddy/features/map/map_providers.dart';
import 'package:trailbuddy/features/profile/dev_screen.dart'
    show DevScreen, kDevHostRefresh;

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  group('hostRequestKindOfPath', () {
    const base = '/trailbuddy';
    final cases = {
      '$base/dach-20261101.pmtiles': HostRequestKind.map,
      '$base/alpen/map-20261101.pmtiles': HostRequestKind.map,
      '$base/alpen/overview-20261101.pmtiles': HostRequestKind.map,
      '$base/ways-20261103.pmtiles': HostRequestKind.ways,
      '$base/heights-20261001.pmtiles': HostRequestKind.heights,
      '$base/dach.json': HostRequestKind.manifest,
      '$base/pois.json': HostRequestKind.manifest,
      '$base/regions.json': HostRequestKind.manifest,
      '$base/alpen/ways.json': HostRequestKind.manifest,
      '$base/pois-20261120/481_77.water.json': HostRequestKind.pois,
      '$base/pois-20261120/481_77.bikeService.json': HostRequestKind.pois,
      '$base/pois-20261120/-3_-12.places.json': HostRequestKind.pois,
      '$base/pois-20261120/names/sch.json': HostRequestKind.names,
      '$base/pois-20261120/bundle.tsv.gz': HostRequestKind.other,
    };
    for (final MapEntry(key: path, value: kind) in cases.entries) {
      test('$path ⇒ ${kind.name}', () {
        expect(hostRequestKindOfPath(path), kind);
      });
    }

    test('nur der Kartenhost zählt', () {
      expect(
        hostRequestKindOf(Uri.parse('$kMapTilesBase/dach.json')),
        HostRequestKind.manifest,
      );
      expect(
        hostRequestKindOf(Uri.parse('https://example.org/trailbuddy/x.json')),
        isNull,
      );
    });
  });

  test('der Client zählt Anfragen an den Host, sonst nichts', () async {
    final counter = HostRequestCounter.instance..reset();
    final client = HostCountingClient(
      MockClient((_) async => http.Response('{}', 200)),
    );
    await client.get(Uri.parse('$kMapTilesBase/dach.json'));
    await client.get(Uri.parse('$kMapTilesBase/dach.json'));
    await client.get(Uri.parse('$kMapTilesBase/pois-1/1_2.water.json'));
    await client.get(Uri.parse('https://api.github.com/repos'));
    expect(counter.counts, {
      HostRequestKind.manifest: 2,
      HostRequestKind.pois: 1,
    });
    counter.reset();
    expect(counter.counts, isEmpty);
  });

  test('Dart und native Zählung landen je Art zusammen', () {
    expect(
      mergeHostCounts(
        {HostRequestKind.manifest: 3},
        {
          '/trailbuddy/dach-20261101.pmtiles': 40,
          '/trailbuddy/ways-20261103.pmtiles': 7,
          '/trailbuddy/dach.json': 1,
        },
      ),
      {
        HostRequestKind.manifest: 4,
        HostRequestKind.map: 40,
        HostRequestKind.ways: 7,
      },
    );
  });

  // Jeder Abruf beim Host geht über hostClient/hostGet/openHostPmTiles —
  // sonst zählt der Zähler zu wenig, und die Grundlinie lügt.
  test('niemand in lib/ fragt das Netz an der Zählung vorbei', () {
    const allowed = {
      // Die Zählung selbst.
      'lib/features/map/host_requests.dart',
      // Andere Hosts: GitHub (Update, offizielle Trails), Supabase.
      'lib/core/update_check.dart',
      'lib/data/auth_repository.dart',
      'lib/features/update/update_installer.dart',
      'lib/features/official/official_trails_source.dart',
    };
    final pattern = RegExp(
      r'http\s*\.\s*(Client\s*\(\s*\)|get\s*\(|head\s*\(|read\s*\(|readBytes\s*\()'
      r'|PmTilesArchive\s*\.\s*fromUri\b(?!\s*\([^)]*client:)',
    );
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (allowed.contains(path) || path.startsWith('lib/l10n/')) continue;
      final code = f
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (pattern.hasMatch(code)) offenders.add(path);
    }
    expect(offenders, isEmpty);
  });

  group('Profil → Entwicklung', () {
    testWidgets('fehlt in der echten App', (tester) async {
      final backend = FakeBackend();
      final me = backend.addUser(username: 'testrail');
      backend.signInAs(me.id);
      await pumpApp(tester, backend);
      await openTab(tester, 'Profil');
      // Bis ganz unten, sonst baut die Liste die letzten Zeilen nicht.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile-footer')),
        200,
      );
      expect(find.byKey(const ValueKey('profile-about')), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-dev')), findsNothing);
    });

    testWidgets('zeigt die Zählung je Art und setzt sie zurück', (
      tester,
    ) async {
      final backend = FakeBackend();
      final me = backend.addUser(username: 'testrail');
      backend.signInAs(me.id);
      var counts = {HostRequestKind.map: 120, HostRequestKind.manifest: 4};
      var resets = 0;
      await pumpApp(
        tester,
        backend,
        extraOverrides: [
          devToolsVisibleProvider.overrideWithValue(true),
          hostRequestsProvider.overrideWithValue((
            read: () async => (counts: counts, since: DateTime(2026, 11, 20)),
            reset: () async {
              resets++;
              counts = {};
            },
          )),
        ],
      );
      await openTab(tester, 'Profil');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile-dev')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('profile-dev')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      String shown(String key) =>
          (tester.widget(find.byKey(ValueKey('dev-host-$key'))) as Text).data!;
      expect(shown('map'), '120');
      expect(shown('manifest'), '4');
      expect(shown('ways'), '0');
      expect(shown('total'), '124');
      expect(find.text('Seit 00:00:00'), findsOneWidget);

      // Die Seite liest jede Sekunde neu.
      counts = {HostRequestKind.map: 121, HostRequestKind.manifest: 4};
      await tester.pump(kDevHostRefresh);
      expect(shown('map'), '121');

      await tester.tap(find.byKey(const ValueKey('dev-host-reset')));
      await tester.pump();
      expect(resets, 1);
      expect(shown('total'), '0');

      // Weg von der Seite: der Takt endet mit ihr.
      Navigator.of(tester.element(find.byType(DevScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(kDevHostRefresh * 3);
      expect(find.byType(DevScreen), findsNothing);
    });
  });
}
