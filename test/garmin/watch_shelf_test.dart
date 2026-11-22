// Die Ablage auf der Uhr (#515): was das Handy schickt, wann, und was es
// sich merkt. Die Seite der Uhr prüft der Ablaufkern (`CoreTests.mc`,
// `shelf*`). Alles erfunden: eine Linie nach Osten um 47,5/11.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge.dart';
import 'package:trailbuddy/features/garmin/watch_branches.dart'
    show WatchBranch;
import 'package:trailbuddy/features/garmin/watch_providers.dart'
    show watchBranchesLoaderProvider;
import 'package:trailbuddy/features/garmin/watch_route.dart';
import 'package:trailbuddy/features/garmin/watch_shelf.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/routing/nav_sections.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_garmin.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

const _lat = 47.5;

/// Eine geknickte Linie nach Osten, damit das Vereinfachen Punkte lässt.
List<LatLng> _line(double dy) => [
  for (var i = 0; i <= 8; i++)
    LatLng(_lat + (i.isEven ? 0 : dy), 11 + i * 0.002),
];

WatchRoute _route(double dy) => watchRouteOf(_line(dy), NavSections.none)!;

WatchShelfEntry _entry(WatchRoute r, String name) =>
    WatchShelfEntry(id: r.id, name: name, lengthM: 1200, climbM: 80);

Map<String, Object> _hello({
  String ver = '1.9.0',
  List<WatchShelfEntry> sh = const [],
}) => {
  't': 'hi',
  'v': kWatchProtocol,
  'ver': ver,
  if (sh.isNotEmpty) 'sh': [for (final e in sh) e.toJson()],
};

Map<String, Object> _shelf(List<WatchShelfEntry> l, {String? id}) => {
  't': kWatchShelf,
  'l': [for (final e in l) e.toJson()],
  'id': ?id,
};

void main() {
  group('pur', () {
    test(
      'jedes Stück trägt `sh`, nur das erste Name, Länge, bergauf und `rp`',
      () {
        final r = _route(0.0005);
        final parts = watchShelfParts(
          r,
          _entry(r, 'Hausrunde'),
          replace: 'alt',
        );
        expect(parts, hasLength(r.parts().length));
        expect(
          parts.every((p) => p['sh'] == 1 && p['t'] == kWatchRoutePart),
          isTrue,
        );
        expect(parts.first, containsPair('nm', 'Hausrunde'));
        expect(parts.first, containsPair('len', 1200));
        expect(parts.first, containsPair('hm', 80));
        expect(parts.first, containsPair('rp', 'alt'));
        expect(
          watchShelfParts(r, _entry(r, 'x')).first.containsKey('rp'),
          isFalse,
        );
      },
    );

    test(
      'die Ablage aus „hallo" und aus der Antwort; Unlesbares fällt weg',
      () {
        final r = _route(0.0005);
        final hi = watchShelfOf(_hello(sh: [_entry(r, 'A')]))!;
        expect(hi.entries.single.name, 'A');
        expect(hi.id, isNull);
        expect(watchShelfOf(_hello())!.entries, isEmpty);
        final sh = watchShelfOf({
          't': 'sh',
          'id': 'z',
          'l': [
            ['z', 'Z', 10, 2],
            ['kaputt'],
          ],
        })!;
        expect(sh.id, 'z');
        expect(sh.entries.single.id, 'z');
        expect(watchShelfOf({'t': 'ok', 'id': 'z'}), isNull);
      },
    );

    test(
      'Handy und Uhr nennen dieselbe Größe der Ablage und dieselbe Fassung',
      () {
        final mc = File('garmin/source/PhoneRoute.mc').readAsStringSync();
        expect(
          RegExp(r'const SHELF_MAX = (\d+);').firstMatch(mc)?.group(1),
          '$kWatchShelfMax',
        );
        expect(
          watchKnowsShelf(File('garmin/VERSION').readAsStringSync().trim()),
          isTrue,
          reason: 'die Uhr-App dieses Stands kennt die Ablage',
        );
      },
    );

    test('erst ab Uhr-App 1.9.0', () {
      expect(watchKnowsShelf('1.9.0'), isTrue);
      expect(watchKnowsShelf('1.9.0-dev'), isTrue);
      expect(watchKnowsShelf('1.10.0'), isTrue);
      expect(watchKnowsShelf('1.8.0'), isFalse);
      expect(watchKnowsShelf(null), isFalse);
    });

    test('der Merker liest sich zurück, Unlesbares heißt leer', () {
      final r = _route(0.0005);
      final s = WatchShelfState(
        entries: [_entry(_route(0.001), 'Alt')],
        jobs: [
          WatchShelfJob.put(
            _entry(r, 'Neu'),
            watchShelfParts(r, _entry(r, 'Neu')),
          ),
          const WatchShelfJob.drop('weg'),
        ],
      );
      final back = WatchShelfState.parse(s.encode());
      expect(back.entries.single.name, 'Alt');
      expect(back.jobs, hasLength(2));
      expect(back.jobs.first.parts!.first['nm'], 'Neu');
      expect(back.jobs.last.dropId, 'weg');
      expect(WatchShelfState.parse('{kaputt').jobs, isEmpty);
    });
  });

  group('Notifier', () {
    late FakeGarminBridge bridge;
    late MemoryWatchShelfStore store;

    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          garminBridgeProvider.overrideWithValue(bridge),
          watchShelfStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      c.read(watchShelfProvider);
      return c;
    }

    List<Map<String, Object>> shelfSent() => [
      for (final batch in bridge.sent)
        ...batch.where((m) => m['sh'] == 1 || m['t'] == kWatchShelfDrop),
    ];

    setUp(() {
      bridge = FakeGarminBridge.connected()..openResult = WatchOpen.prompted;
      store = MemoryWatchShelfStore();
    });

    test(
      '515.1 handy: ohne offene Uhr-App wartet der Auftrag, gemerkt; das „hallo" schickt ihn, erst `sh` nimmt ihn',
      () async {
        final c = container();
        final r = _route(0.0005);
        final put = await c
            .read(watchShelfProvider.notifier)
            .put(_entry(r, 'Hausrunde'), r);
        expect(put, WatchShelfPut.waiting);
        expect(bridge.opens, 1);
        expect(shelfSent(), isEmpty);
        expect(store.value, contains('Hausrunde'));
        expect(c.read(watchShelfProvider).shown.single.name, 'Hausrunde');

        bridge.answer(_hello());
        await pumpEventQueue();
        expect(shelfSent(), hasLength(r.parts().length));
        expect(c.read(watchShelfProvider).sendingId, r.id);
        // Nur `ok` oder SUCCESS zählt nicht — die Uhr muss die Ablage nennen.
        bridge.answer({'t': 'ok', 'id': r.id});
        await pumpEventQueue();
        expect(c.read(watchShelfProvider).jobs, hasLength(1));
        bridge.answer(_shelf([_entry(r, 'Hausrunde')], id: r.id));
        await pumpEventQueue();
        final s = c.read(watchShelfProvider);
        expect(s.jobs, isEmpty);
        expect(s.entries.single.id, r.id);
        expect(store.value, isNot(contains('parts')));
      },
    );

    test('515.5 handy: ein Auftrag übersteht den Neustart der App', () async {
      final r = _route(0.0005);
      var c = container();
      await c.read(watchShelfProvider.notifier).put(_entry(r, 'Hausrunde'), r);
      c.dispose();
      c = container();
      await pumpEventQueue();
      expect(c.read(watchShelfProvider).pending.single.name, 'Hausrunde');
      bridge.answer(_hello());
      await pumpEventQueue();
      expect(shelfSent(), hasLength(r.parts().length));
    });

    test(
      'läuft die Uhr-App schon, fragt das Handy nach ihrem „hallo"',
      () async {
        bridge.openResult = WatchOpen.running;
        final c = container();
        final r = _route(0.0005);
        await c.read(watchShelfProvider.notifier).put(_entry(r, 'A'), r);
        await pumpEventQueue();
        expect(bridge.queries, 1);
        expect(shelfSent(), isEmpty);
        bridge.answer(_hello());
        await pumpEventQueue();
        expect(shelfSent(), hasLength(r.parts().length));
      },
    );

    test(
      'eine Uhr-App vor 1.9.0 bekommt nichts — sie nähme es als Navigation',
      () async {
        final c = container();
        final r = _route(0.0005);
        await c.read(watchShelfProvider.notifier).put(_entry(r, 'A'), r);
        bridge.answer(_hello(ver: '1.8.0'));
        await pumpEventQueue();
        expect(shelfSent(), isEmpty);
        expect(c.read(watchShelfProvider).failure, WatchShelfFailure.outdated);
        expect(c.read(watchShelfProvider).jobs, hasLength(1));
      },
    );

    test(
      '637.1 handy: unklarer Öffnungsstatus, erneutes Hallo und verlorenes sh',
      () async {
        bridge.openResult = WatchOpen.unknown;
        final gate = bridge.sendGate = Completer<void>();
        final c = container();
        final r = _route(0.0005);
        final entry = _entry(r, 'A');
        await c.read(watchShelfProvider.notifier).put(entry, r);
        await pumpEventQueue();
        expect(bridge.queries, 1);

        bridge.answer(_hello(ver: '1.10.0'));
        await pumpEventQueue();
        final sent = shelfSent().length;
        expect(sent, r.parts().length);
        bridge.answer(_hello(ver: '1.10.0'));
        await pumpEventQueue();
        expect(shelfSent(), hasLength(sent));

        gate.complete();
        await pumpEventQueue();
        bridge.answer(_hello(ver: '1.10.0', sh: [entry]));
        await pumpEventQueue();
        expect(c.read(watchShelfProvider).jobs, isEmpty);
        expect(c.read(watchShelfProvider).entries.single.id, r.id);
        expect(shelfSent(), hasLength(sent));
      },
    );

    test(
      '637.2 handy: Hallo nach Versand an geschlossene Uhr versucht erneut',
      () async {
        final c = container();
        final r = _route(0.0005);
        final entry = _entry(r, 'A');
        bridge.answer(_hello(ver: '1.10.0'));
        await pumpEventQueue();
        await c.read(watchShelfProvider.notifier).put(entry, r);
        await pumpEventQueue();
        // Das SDK meldete SUCCESS, aber die bis jetzt geschlossene Uhr nahm nichts.
        expect(shelfSent(), hasLength(r.parts().length));
        bridge.answer(_hello(ver: '1.10.0'));
        await pumpEventQueue();
        expect(shelfSent(), hasLength(2 * r.parts().length));
        bridge.answer(_shelf([entry], id: r.id));
        await pumpEventQueue();
        expect(c.read(watchShelfProvider).entries.single.id, r.id);
      },
    );

    test(
      '515.2 handy: voll heißt Fehler und der Auftrag geht weg; schon da heißt nichts senden',
      () async {
        final c = container();
        final r = _route(0.0005);
        bridge.answer(_hello(sh: [_entry(r, 'Da')]));
        await pumpEventQueue();
        expect(
          await c.read(watchShelfProvider.notifier).put(_entry(r, 'Da'), r),
          WatchShelfPut.already,
        );
        final n = _route(0.001);
        expect(
          await c.read(watchShelfProvider.notifier).put(_entry(n, 'Neu'), n),
          WatchShelfPut.sending,
        );
        await pumpEventQueue();
        expect(shelfSent(), isNotEmpty);
        bridge.answer({'t': 'x', 'id': n.id, 'c': kWatchErrFull});
        await pumpEventQueue();
        final s = c.read(watchShelfProvider);
        expect(s.jobs, isEmpty);
        expect(s.failure, WatchShelfFailure.full);
        expect(s.failed, 'Neu');
      },
    );

    test(
      'ersetzt eine, die selbst erst kommt: die fällt weg, kein `rp`',
      () async {
        final c = container();
        final a = _route(0.0005), b = _route(0.001);
        await c.read(watchShelfProvider.notifier).put(_entry(a, 'A'), a);
        await c
            .read(watchShelfProvider.notifier)
            .put(_entry(b, 'B'), b, replace: a.id);
        final jobs = c.read(watchShelfProvider).jobs;
        expect(jobs.single.id, b.id);
        expect(jobs.single.replace, isNull);
      },
    );

    test(
      '515.4 handy: Entfernen geht als `sd`; die Antwort ohne die Route nimmt den Auftrag',
      () async {
        final c = container();
        final r = _route(0.0005);
        bridge.answer(_hello(sh: [_entry(r, 'A')]));
        await pumpEventQueue();
        await c.read(watchShelfProvider.notifier).remove(r.id);
        expect(c.read(watchShelfProvider).shown, isEmpty);
        await pumpEventQueue();
        expect(shelfSent().single, {'t': kWatchShelfDrop, 'id': r.id});
        bridge.answer(_shelf(const []));
        await pumpEventQueue();
        final s = c.read(watchShelfProvider);
        expect(s.jobs, isEmpty);
        expect(s.entries, isEmpty);
        expect(store.value, isNull);
      },
    );

    test(
      'eine Route, die erst kommt, nimmt Entfernen einfach zurück',
      () async {
        final c = container();
        final r = _route(0.0005);
        await c.read(watchShelfProvider.notifier).put(_entry(r, 'A'), r);
        await c.read(watchShelfProvider.notifier).remove(r.id);
        expect(c.read(watchShelfProvider).jobs, isEmpty);
        bridge.answer(_hello());
        await pumpEventQueue();
        expect(shelfSent(), isEmpty);
      },
    );

    test('Entfernen beim Senden wartet trotz Hallo bis zum Ablegen', () async {
      final gate = bridge.sendGate = Completer<void>();
      final c = container();
      final shelf = c.read(watchShelfProvider.notifier);
      final r = _route(0.0005);
      final entry = _entry(r, 'A');
      bridge.answer(_hello());
      await pumpEventQueue();
      await shelf.put(entry, r);
      await pumpEventQueue();
      await shelf.remove(r.id);
      bridge.answer(_hello());
      await pumpEventQueue();
      expect(c.read(watchShelfProvider).removing, {r.id});
      expect(shelfSent().last['t'], kWatchRoutePart);
      gate.complete();
      await pumpEventQueue();
      bridge.answer(_shelf([entry], id: r.id));
      await pumpEventQueue();
      expect(shelfSent().last, watchShelfDropOf(r.id));
      bridge.answer(_shelf(const []));
      await pumpEventQueue();
      expect(c.read(watchShelfProvider).jobs, isEmpty);
    });
  });

  group('in der App', () {
    testWidgets(
      '515.1 handy: „Auf die Uhr legen" in „Meine Fahrten", voll fragt, die Seite zeigt es',
      (tester) async {
        final backend = FakeBackend();
        final anna = backend.addUser(username: 'anna');
        backend.signInAs(anna.id);
        final store = FakeRideStore()..uid = anna.id;
        final t0 = DateTime.utc(2026, 10, 8, 9);
        store.rides.add(
          Ride(
            id: '20261008T090000Z',
            startedAt: t0,
            endedAt: t0.add(const Duration(hours: 1)),
            points: [
              for (final p in _line(0.0007))
                RidePoint(
                  lat: p.latitude,
                  lng: p.longitude,
                  at: t0,
                  accuracyM: 0,
                ),
            ],
            planned: true,
            name: 'Hausrunde',
          ),
        );
        final bridge = FakeGarminBridge.connected()
          ..openResult = WatchOpen.prompted;
        final settings = FakeSettings(watchSeen: true);
        await pumpApp(
          tester,
          backend,
          rideStore: store,
          garmin: bridge,
          settings: settings,
          extraOverrides: [
            watchBranchesLoaderProvider.overrideWithValue(
              (_) async => const <WatchBranch>[],
            ),
          ],
        );
        // Auf der Uhr liegen schon drei.
        bridge.answer(
          _hello(
            sh: [
              for (final (i, d) in [0.0002, 0.0003, 0.0004].indexed)
                _entry(_route(d), 'Alt $i'),
            ],
          ),
        );
        await settle(tester);
        await openProfilePage(tester, 'rides');
        await tester.tap(
          find.byKey(const ValueKey('ride-menu-20261008T090000Z')),
        );
        await settle(tester);
        await tester.tap(
          find.byKey(const ValueKey('ride-watch-20261008T090000Z')),
        );
        await settle(tester);
        expect(
          find.byKey(const ValueKey('watch-shelf-replace')),
          findsOneWidget,
        );
        final old = _route(0.0003).id;
        await tester.tap(find.byKey(ValueKey('watch-shelf-replace-$old')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await settle(tester);
        expect(
          find.textContaining('„Hausrunde“ geht auf die Uhr'),
          findsOneWidget,
        );
        final parts = [
          for (final b in bridge.sent) ...b.where((m) => m['sh'] == 1),
        ];
        expect(parts.first['rp'], old);
        expect(parts.first['nm'], 'Hausrunde');

        // Die Seite „Uhr" im Profil zeigt, was kommt.
        // Ein Tipp auf den Reiter führt zurück an den Anfang des Profils.
        await openProfilePage(tester, 'watch');
        expect(find.text('Hausrunde'), findsOneWidget);
        expect(find.text('Alt 1'), findsNothing, reason: 'ersetzt');
        expect(find.text('Alt 0'), findsOneWidget);
      },
    );
  });
}
