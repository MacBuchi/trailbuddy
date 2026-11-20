// Orte auf der Karte (#12): Arten erkennen, Manifest und Zellendatei des
// Kartenhosts lesen, das Raster, die Quelle vom Host (nur genannte Zellen,
// Manifest einmal), und dass jede Zelle je Gruppe nur einmal gefragt wird.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/data/seen_host_files.dart';
import 'package:trailbuddy/features/map/map_providers.dart';
import 'package:trailbuddy/features/map/map_regions.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/poi_source.dart';

import '../fakes/fake_pois.dart';
import '../fakes/fake_settings.dart';

void main() {
  group('Arten', () {
    test('Café, Quelle, Schlüssel', () {
      expect(PoiKind.of({'amenity': 'cafe'}), PoiKind.cafe);
      expect(PoiKind.of({'natural': 'spring'}), PoiKind.spring);
      expect(
        PoiKind.of({'amenity': 'bicycle_repair_station'}),
        PoiKind.repairStation,
      );
      expect(PoiKind.of({'highway': 'track'}), isNull);
    });

    test(
      'Gasthaus mit Biergarten ist ein Biergarten (Krug, nicht Besteck)',
      () {
        expect(
          PoiKind.of({'amenity': 'restaurant', 'biergarten': 'yes'}),
          PoiKind.biergarten,
        );
        expect(
          PoiKind.of({'amenity': 'pub', 'beer_garden': 'yes'}),
          PoiKind.biergarten,
        );
        expect(PoiKind.of({'amenity': 'restaurant'}), PoiKind.restaurant);
        expect(PoiKind.biergarten.icon, Icons.sports_bar);
        expect(
          PoiKind.spring.icon,
          Icons.local_drink,
          reason: 'Wasserglas statt Wellen',
        );
        expect(
          PoiKind.cafe.icon,
          isNull,
          reason: 'das Kuchenstück ist gezeichnet',
        );
      },
    );

    test('Ladesäule nur fürs Rad, Parkplatz nur öffentlich', () {
      expect(PoiKind.of({'amenity': 'charging_station'}), isNull);
      expect(
        PoiKind.of({'amenity': 'charging_station', 'bicycle': 'yes'}),
        PoiKind.eBikeCharging,
      );
      expect(PoiKind.of({'amenity': 'parking'}), PoiKind.parking);
      expect(PoiKind.of({'amenity': 'parking', 'access': 'private'}), isNull);
    });

    test(
      'die Arten der App sind die des Werkzeugs — Reihenfolge, Regeln, Gruppe',
      () {
        // EINE Liste für zwei Leser: tool/poi_extract.py baut damit die
        // Dateien, die App zeigt damit. Laufen sie auseinander, sieht der
        // Nutzer Nadeln ohne Art oder Arten ohne Nadel.
        final json =
            jsonDecode(File('tool/pois/kinds.json').readAsStringSync())
                as Map<String, dynamic>;
        expect(json['format'], 1);
        expect(json['groups'], [for (final g in PoiGroup.values) g.name]);
        final kinds = (json['kinds'] as List).cast<Map<String, dynamic>>();
        expect(
          [for (final k in kinds) k['kind']],
          [for (final k in PoiKind.values) k.name],
          reason:
              'gleiche Arten in gleicher Reihenfolge — die erste passende gewinnt',
        );
        for (final (i, k) in kinds.indexed) {
          final dart = PoiKind.values[i];
          expect(k['group'], dart.group.name, reason: dart.name);
          expect(
            [
              for (final r in k['rules'] as List)
                (r as Map).cast<String, String>(),
            ],
            dart.rules,
            reason: '${dart.name}: Regeln',
          );
          final excluded =
              (k['exclude_access'] as List?)?.cast<String>() ?? const [];
          expect(
            excluded.isNotEmpty,
            dart.excludeAccess,
            reason: '${dart.name}: access',
          );
          if (excluded.isNotEmpty) expect(excluded, ['private', 'no']);
        }
        expect(PoiKind.byName('spring'), PoiKind.spring);
        expect(PoiKind.byName('teleporter'), isNull);
      },
    );
  });

  test('das Manifest: Präfix geprüft, Zellen je Gruppe, Unbekanntes egal', () {
    final m = PoiManifest.fromJson({
      'format': 1,
      'build': '20260928',
      'prefix': 'pois-20260928',
      'cells': {
        'water': ['475,60', '472,75'],
        'food': ['475,60'],
        'zeppelin': ['1,1'],
      },
    });
    expect(m.build, '20260928');
    expect(m.has('475,60', PoiGroup.water), isTrue);
    expect(m.has('472,75', PoiGroup.food), isFalse);
    expect(m.has('475,60', PoiGroup.other), isFalse);
    expect(
      () => PoiManifest.fromJson({
        'format': 1,
        'build': 'x',
        'prefix': '../etc',
        'cells': {},
      }),
      throwsFormatException,
      reason: 'das Präfix wird ein Pfad',
    );
    expect(
      () => PoiManifest.fromJson({
        'format': 2,
        'build': 'x',
        'prefix': 'pois-20260928',
        'cells': {},
      }),
      throwsFormatException,
    );
    expect(poiCellFileName('475,60', PoiGroup.water), '475_60.water.json');
    expect(
      poiCellFileName('-3,-12', PoiGroup.bikeService),
      '-3_-12.bikeService.json',
    );
  });

  test('die Zellendatei: Felder, Trinkwasser, unbekannte Art fällt weg', () {
    final pois = parsePoiFile('''
      {"format": 1, "build": "20260928", "cell": "475,60", "group": "water", "pois": [
        {"id": "node/1", "kind": "spring", "lat": 47.51, "lng": 9.01,
         "name": "Kalte Quelle", "water": "no"},
        {"id": "way/2", "kind": "biergarten", "lat": 47.52, "lng": 9.02,
         "hours": "Mo-Su 11:00-22:00"},
        {"id": "node/3", "kind": "teleporter", "lat": 47.53, "lng": 9.03},
        {"id": "node/4", "kind": "cafe"}
      ]}''');
    expect(pois.map((p) => p.id), ['node/1', 'way/2']);
    expect(pois[0].kind, PoiKind.spring);
    expect(pois[0].name, 'Kalte Quelle');
    expect(pois[0].drinkable, isFalse);
    expect(pois[1].position, const LatLng(47.52, 9.02));
    expect(pois[1].openingHours, 'Mo-Su 11:00-22:00');
    expect(pois[1].drinkable, isNull);
    expect(
      () => parsePoiFile('{"format": 7, "pois": []}'),
      throwsFormatException,
    );
  });

  group('Quelle vom Host', () {
    const manifest = {
      'format': 1,
      'build': '20260928',
      'prefix': 'pois-20260928',
      'cells': {
        'water': ['475,60'],
        'food': ['475,60', '475,61'],
      },
    };
    const spring = {
      'format': 1,
      'build': '20260928',
      'cell': '475,60',
      'group': 'water',
      'pois': [
        {'id': 'node/1', 'kind': 'spring', 'lat': 47.55, 'lng': 9.05},
      ],
    };

    test('Manifest einmal, dann nur die Zellen, die es nennt', () async {
      final asked = <String>[];
      final source = HostPoiSource(
        client: MockClient((req) async {
          asked.add(req.url.toString());
          if (req.url.toString() == kPoiManifestUrl) {
            return http.Response(jsonEncode(manifest), 200);
          }
          if (req.url.path.endsWith('475_60.water.json')) {
            return http.Response(jsonEncode(spring), 200);
          }
          if (req.url.path.endsWith('475_61.food.json')) {
            return http.Response('', 404);
          }
          return http.Response(jsonEncode({...spring, 'pois': []}), 200);
        }),
      );
      final pois = await source.fetch(
        ['475,60', '475,61', '476,60'],
        {PoiGroup.water, PoiGroup.food},
      );
      expect(pois.map((p) => p.id), ['node/1']);
      expect(asked, [
        kPoiManifestUrl,
        '$kMapTilesBase/pois-20260928/475_60.water.json',
        '$kMapTilesBase/pois-20260928/475_60.food.json',
        '$kMapTilesBase/pois-20260928/475_61.food.json',
      ], reason: '476,60 steht nicht im Manifest, 475,61 nicht unter Wasser');

      await source.fetch(['475,60'], {PoiGroup.water});
      expect(
        asked.where((u) => u == kPoiManifestUrl),
        hasLength(1),
        reason: 'das Manifest gilt für den App-Lauf',
      );
    });

    test(
      'kein Manifest (noch kein Bau, Host weg): nicht erreichbar, beim nächsten Mal wieder',
      () async {
        var manifestCalls = 0;
        final source = HostPoiSource(
          client: MockClient((req) async {
            if (req.url.toString() == kPoiManifestUrl) {
              manifestCalls++;
              if (manifestCalls == 1) return http.Response('', 404);
              return http.Response(jsonEncode(manifest), 200);
            }
            return http.Response(jsonEncode(spring), 200);
          }),
        );
        await expectLater(
          source.fetch(['475,60'], {PoiGroup.water}),
          throwsA(isA<PoiUnavailable>()),
        );
        final pois = await source.fetch(['475,60'], {PoiGroup.water});
        expect(pois, hasLength(1));
        expect(manifestCalls, 2);
      },
    );

    test(
      'gespeicherte Bereiche zuerst: lokale Zellen brauchen weder Manifest noch Netz',
      () async {
        var network = 0;
        final source = HostPoiSource(
          client: MockClient((req) async {
            network++;
            if (req.url.toString() == kPoiManifestUrl) {
              return http.Response(jsonEncode(manifest), 200);
            }
            return http.Response(jsonEncode({...spring, 'pois': []}), 200);
          }),
          readLocal: (name) async =>
              name == '475_60.water.json' ? jsonEncode(spring) : null,
        );
        final local = await source.fetch(['475,60'], {PoiGroup.water});
        expect(local.map((p) => p.id), ['node/1']);
        expect(network, 0, reason: 'alles lag im Bereich');
        // Fehlt eine Zelle lokal, geht nur die ans Netz.
        await source.fetch(['475,60'], {PoiGroup.water, PoiGroup.food});
        expect(network, 2, reason: 'Manifest und die eine Einkehr-Datei');
      },
    );

    test('eine Zellendatei mit 5xx: nicht erreichbar', () async {
      final source = HostPoiSource(
        client: MockClient((req) async {
          if (req.url.toString() == kPoiManifestUrl) {
            return http.Response(jsonEncode(manifest), 200);
          }
          return http.Response('', 503);
        }),
      );
      await expectLater(
        source.fetch(['475,60'], {PoiGroup.water}),
        throwsA(isA<PoiUnavailable>()),
      );
    });
  });

  test('Raster: Zellen um einen Rahmen und der Rahmen um Zellen', () {
    final cells = poiCellsCovering(47.55, 9.05, 47.65, 9.2);
    expect(cells, ['475,60', '475,61', '476,60', '476,61']);
    final b = poiCellsBounds(cells);
    expect(b.s, closeTo(47.5, 1e-9));
    expect(b.n, closeTo(47.7, 1e-9));
    expect(b.w, closeTo(9.0, 1e-9));
    expect(b.e, closeTo(9.3, 1e-9));
    expect(poiCellOf(const LatLng(47.55, 9.05)), '475,60');
  });

  group('Gesehenes (#596 H4)', () {
    const manifest = {
      'format': 1,
      'build': '20260928',
      'prefix': 'pois-20260928',
      'cells': {
        'water': ['475,60'],
      },
    };
    const spring = {
      'format': 1,
      'build': '20260928',
      'cell': '475,60',
      'group': 'water',
      'pois': [
        {'id': 'node/1', 'kind': 'spring', 'lat': 47.55, 'lng': 9.05},
      ],
    };

    MockClient host(List<String> asked, {bool offline = false}) =>
        MockClient((req) async {
          asked.add(req.url.toString());
          if (offline) throw const SocketException('offline');
          if (req.url.toString() == kPoiManifestUrl) {
            return http.Response(jsonEncode(manifest), 200);
          }
          return http.Response(jsonEncode(spring), 200);
        });

    test('eine Zelle kommt nach einem Neustart aus der Ablage, ohne Netz '
        'mit dem gemerkten Manifest', () async {
      final seen = MemorySeenHostFiles();
      final asked = <String>[];
      final first = HostPoiSource(client: host(asked), seen: seen);
      expect(
        (await first.fetch(['475,60'], {PoiGroup.water})).map((p) => p.id),
        ['node/1'],
      );
      expect(asked, hasLength(2));
      final later = HostPoiSource(
        client: host(asked, offline: true),
        seen: seen,
      );
      expect(
        (await later.fetch(['475,60'], {PoiGroup.water})).map((p) => p.id),
        ['node/1'],
      );
      expect(
        asked,
        hasLength(2),
        reason: 'Manifest jünger als 24 h, Zelle lag',
      );
    });

    test(
      'das Manifest höchstens einmal am Tag; ohne Netz gilt das alte',
      () async {
        var now = DateTime(2026, 11, 20, 8);
        final seen = MemorySeenHostFiles(now: () => now);
        final asked = <String>[];
        Future<PoiManifest?> load({bool offline = false}) => PoiManifests(
          client: host(asked, offline: offline),
          seen: seen,
          now: () => now,
        ).of(kDachRegion);
        await load();
        now = now.add(const Duration(hours: 23));
        await load();
        expect(asked, [kPoiManifestUrl], reason: 'nach 23 h noch gemerkt');
        now = now.add(const Duration(hours: 2));
        await load();
        expect(asked, [
          kPoiManifestUrl,
          kPoiManifestUrl,
        ], reason: 'nach 25 h neu');
        now = now.add(const Duration(days: 3));
        final old = await load(offline: true);
        expect(old?.folder, 'pois-20260928');
      },
    );

    test('dieselbe Zelle zugleich: eine Anfrage', () async {
      final asked = <String>[];
      final source = HostPoiSource(client: host(asked));
      await Future.wait([
        source.fetch(['475,60'], {PoiGroup.water}),
        source.fetch(['475,60'], {PoiGroup.water}),
      ]);
      expect(asked, [
        kPoiManifestUrl,
        '$kMapTilesBase/pois-20260928/475_60.water.json',
      ]);
    });
  });

  group('Nachladen', () {
    late FakePoiSource source;
    late ProviderContainer c;
    const spring = Poi(
      id: 'node/1',
      kind: PoiKind.spring,
      position: LatLng(47.55, 9.05),
    );
    const cafe = Poi(
      id: 'node/2',
      kind: PoiKind.cafe,
      position: LatLng(47.56, 9.06),
    );

    setUp(() {
      source = FakePoiSource([spring, cafe]);
      c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWithValue(FakeSettings()),
          poiSourceProvider.overrideWithValue(source),
        ],
      );
      addTearDown(c.dispose);
    });

    test('jede Zelle je Gruppe genau einmal', () async {
      final ctl = c.read(poiControllerProvider.notifier);
      await ctl.ensure(['475,60'], {PoiGroup.water});
      await ctl.ensure(['475,60'], {PoiGroup.water});
      expect(source.calls, hasLength(1));
      expect(source.cellsAsked.single, ['475,60']);
      expect(
        c.read(poiControllerProvider).inCells(['475,60'], {PoiGroup.water}),
        [spring],
      );

      // Eine neue Gruppe fragt nur sie nach.
      await ctl.ensure(['475,60'], {PoiGroup.water, PoiGroup.food});
      expect(source.calls, hasLength(2));
      expect(source.groupsAsked.last, {PoiGroup.food});
      expect(
        c
            .read(poiControllerProvider)
            .inCells(['475,60'], {PoiGroup.water, PoiGroup.food}),
        [spring, cafe],
      );
    });

    test('eine leere Zelle gilt als geladen', () async {
      final ctl = c.read(poiControllerProvider.notifier);
      await ctl.ensure(['0,0'], {PoiGroup.water});
      await ctl.ensure(['0,0'], {PoiGroup.water});
      expect(source.calls, hasLength(1));
    });

    test(
      'nicht erreichbar: sagt es und fragt beim nächsten Mal wieder',
      () async {
        final ctl = c.read(poiControllerProvider.notifier);
        source.failWith = const PoiUnavailable(503);
        await ctl.ensure(['475,60'], {PoiGroup.water});
        expect(c.read(poiControllerProvider).unavailable, isTrue);
        await ctl.ensure(['475,60'], {PoiGroup.water});
        expect(source.calls, hasLength(2));
        expect(c.read(poiControllerProvider).unavailable, isFalse);
      },
    );

    test('zu weit herausgezoomt: keine Abfrage', () async {
      final cells = poiCellsCovering(47, 8, 48, 10);
      expect(cells.length, greaterThan(kPoiMaxCells));
      await c.read(poiControllerProvider.notifier).ensure(cells, {
        PoiGroup.water,
      });
      expect(source.calls, isEmpty);
    });

    test('Filter: Vorgabe Wasser, gemerkt, leer heißt alles aus', () {
      final settings = FakeSettings();
      final c2 = ProviderContainer(
        overrides: [settingsProvider.overrideWithValue(settings)],
      );
      addTearDown(c2.dispose);
      expect(c2.read(poiGroupsProvider), {PoiGroup.water});
      c2.read(poiGroupsProvider.notifier).toggle(PoiGroup.water);
      expect(c2.read(poiGroupsProvider), isEmpty);
      expect(settings.poiGroups, isEmpty);

      final c3 = ProviderContainer(
        overrides: [
          settingsProvider.overrideWithValue(FakeSettings(poiGroups: const [])),
        ],
      );
      addTearDown(c3.dispose);
      expect(c3.read(poiGroupsProvider), isEmpty);
    });

    test('Detailfilter: vorgegeben alles sichtbar, Abwahl gemerkt', () {
      final settings = FakeSettings();
      final c2 = ProviderContainer(
        overrides: [settingsProvider.overrideWithValue(settings)],
      );
      addTearDown(c2.dispose);
      expect(c2.read(poiHiddenKindsProvider), isEmpty);
      c2.read(poiHiddenKindsProvider.notifier).toggle(PoiKind.spring);
      expect(c2.read(poiHiddenKindsProvider), {PoiKind.spring});
      expect(settings.poiHiddenKinds, ['spring']);
      c2.read(poiHiddenKindsProvider.notifier).toggle(PoiKind.spring);
      expect(settings.poiHiddenKinds, isEmpty);
    });
  });
}
