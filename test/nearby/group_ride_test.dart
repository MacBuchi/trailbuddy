// Gruppenfahrt (#519) — was die Karte zeigt, wer einen Paarkanal bekommt
// und die Steuerung durch die Engine, ohne Oberfläche. Die Koordinaten sind
// erfunden (A7).
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/nearby/nearby_core.dart';
import 'package:trailbuddy/features/nearby/nearby_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_nearby.dart';

double north(double lat, double km) => lat + km / 111.2;

void main() {
  const lat = 40.0, lon = 10.0;
  final mine = NearbyCell.of(lat, lon);
  final nearCell = NearbyCell.of(north(lat, 2), lon);
  final farCell = NearbyCell.of(north(lat, 30), lon);
  final now = DateTime.utc(2026, 11, 18, 12);

  test('Paarkanal: sortiert, also genau einer je Paar', () {
    expect(livePairTopic('b', 'a'), 'live:a:b');
    expect(livePairTopic('a', 'b'), 'live:a:b');
  });

  test('Zellgrenzen: der Mittelpunkt liegt im Quadrat', () {
    expect(mine.south, lessThan(mine.centerLat));
    expect(mine.north, greaterThan(mine.centerLat));
    expect(mine.west, lessThan(mine.centerLon));
    expect(mine.east, greaterThan(mine.centerLon));
    expect(NearbyCell.of(mine.centerLat, mine.centerLon), mine);
  });

  group('livePairsFor — wer meine genaue Position bekommt', () {
    BuddySighting s(
      String id,
      NearbyCell cell, {
      bool live = true,
      bool present = true,
    }) => BuddySighting(
      buddyId: id,
      cell: cell,
      cellPresent: present,
      live: live,
    );

    test('nur mit Live auf beiden Seiten und nur in der Nähe', () {
      final all = [
        s('nah-live', nearCell),
        s('nah-ohne', nearCell, live: false),
        s('fern-live', farCell),
        s('weg', nearCell, present: false),
      ];
      expect(livePairsFor(mine: mine, myLive: true, sightings: all), {
        'nah-live',
      });
      expect(
        livePairsFor(mine: mine, myLive: false, sightings: all),
        isEmpty,
        reason: 'ich habe Live aus',
      );
      expect(
        livePairsFor(mine: null, myLive: true, sightings: all),
        isEmpty,
        reason: 'ich teile gerade nicht',
      );
    });
  });

  group('buddyMapEntries — was die Karte zeigt', () {
    test('genau und frisch; alt mit „vor …"; ganz alt weg', () {
      final fresh = BuddySighting(
        buddyId: 'a',
        position: (lat: lat, lon: lon),
        positionAt: now,
        positionPresent: true,
      );
      final old = BuddySighting(
        buddyId: 'b',
        position: (lat: lat, lon: lon),
        positionAt: now.subtract(const Duration(minutes: 4)),
        positionPresent: true,
      );
      final gone = BuddySighting(
        buddyId: 'c',
        position: (lat: lat, lon: lon),
        positionAt: now.subtract(const Duration(minutes: 16)),
      );
      final out = buddyMapEntries(
        [fresh, old, gone],
        homieOwners: const {},
        now: now,
      );
      expect(out.map((e) => e.buddyId), ['a', 'b']);
      expect(out[0].kind, BuddyMapKind.live);
      expect(out[0].seenAgo, isNull);
      expect(out[1].seenAgo, const Duration(minutes: 4));
    });

    test('die Zelle nur für Homies — alle anderen sehen nichts', () {
      final a = BuddySighting(
        buddyId: 'homie',
        cell: farCell,
        cellPresent: true,
      );
      final b = BuddySighting(
        buddyId: 'buddy',
        cell: farCell,
        cellPresent: true,
      );
      final out = buddyMapEntries([a, b], homieOwners: {'homie'}, now: now);
      expect(out.map((e) => e.buddyId), ['homie']);
      expect(out.single.kind, BuddyMapKind.cell);
      expect(out.single.cell, farCell);
      expect(out.single.point, (
        lat: farCell.centerLat,
        lon: farCell.centerLon,
      ));
    });

    test('eine herausgenommene Zelle bleibt 15 min mit „vor …"', () {
      BuddySighting gone(int min) => BuddySighting(
        buddyId: 'h',
        cell: farCell,
        cellGoneAt: now.subtract(Duration(minutes: min)),
      );
      expect(
        buddyMapEntries([gone(3)], homieOwners: {'h'}, now: now).single.seenAgo,
        const Duration(minutes: 3),
      );
      expect(
        buddyMapEntries([gone(16)], homieOwners: {'h'}, now: now),
        isEmpty,
      );
    });

    test('genau schlägt grob', () {
      final s = BuddySighting(
        buddyId: 'h',
        cell: nearCell,
        cellPresent: true,
        position: (lat: lat, lon: lon),
        positionAt: now,
        positionPresent: true,
      );
      expect(
        buddyMapEntries([s], homieOwners: {'h'}, now: now).single.kind,
        BuddyMapKind.live,
      );
    });
  });

  group('Engine', () {
    late FakeBackend backend;
    late FakeUser me, anni, ben;
    late FakeNearbyRepository repo;
    late NearbyEngine engine;
    late List<List<BuddySighting>> seen;
    var clock = now;

    setUp(() {
      backend = FakeBackend();
      me = backend.addUser(username: 'ich');
      anni = backend.addUser(username: 'anni');
      ben = backend.addUser(username: 'ben');
      backend.addFriendship(me.id, anni.id);
      backend.addFriendship(me.id, ben.id);
      backend.signInAs(me.id);
      repo = FakeNearbyRepository(backend);
      seen = [];
      clock = now;
      engine = NearbyEngine(
        repo,
        onNotice: (_) {},
        onSightings: seen.add,
        clock: () => clock,
      );
    });

    tearDown(() => engine.close());

    Future<void> sync({
      bool live = true,
      NearbyCell? at,
      ({double lat, double lon})? pos,
    }) async {
      final cell = at ?? mine;
      await engine.sync(
        mine: cell,
        buddies: {anni.id, ben.id},
        muted: const {},
        session: 's1',
        live: live,
        position: pos ?? (lat: lat, lon: lon),
      );
      await pumpEventQueue();
    }

    test(
      'Live an: Zelle trägt „l", Paarkanal nur mit dem nahen Buddy mit Live',
      () async {
        repo.setCell(anni.id, nearCell.encode(), live: true);
        repo.setCell(ben.id, farCell.encode(), live: true);
        await sync();
        expect(repo.sharedLive.last, isTrue);
        expect(repo.pairs, {
          anni.id,
        }, reason: 'Ben ist fern — er bekommt nichts Genaues');
        expect(repo.liveSent, isNotEmpty);
      },
    );

    test(
      'der Buddy hat Live aus: kein Paarkanal, nichts Genaues hinaus',
      () async {
        repo.setCell(anni.id, nearCell.encode());
        await sync();
        expect(repo.pairs, isEmpty);
        expect(repo.liveSent, isEmpty);
      },
    );

    test(
      'ich habe Live aus: nichts Genaues, auch wenn der Buddy es anhat',
      () async {
        repo.setCell(anni.id, nearCell.encode(), live: true);
        await sync(live: false);
        expect(repo.sharedLive.last, isFalse);
        expect(repo.pairs, isEmpty);
        expect(repo.liveSent, isEmpty);
      },
    );

    test(
      '„sieht mich" aus, in jeder Richtung: der Server lässt kein Paar zu',
      () async {
        repo.hiddenBy[me.id] = {anni.id};
        repo.setCell(anni.id, nearCell.encode(), live: true);
        await sync();
        expect(repo.pairs, isEmpty);
      },
    );

    test(
      'seine genaue Position kommt an; geht er aus der Nähe, verschwindet sie',
      () async {
        repo.setCell(anni.id, nearCell.encode(), live: true);
        repo.setPosition(anni.id, north(lat, 2), lon, at: now);
        await sync();
        final s = seen.last.singleWhere((s) => s.buddyId == anni.id);
        expect(s.position, isNotNull);
        expect(s.positionPresent, isTrue);
        expect(
          buddyMapEntries(
            seen.last,
            homieOwners: const {},
            now: now,
          ).single.kind,
          BuddyMapKind.live,
        );

        repo.setCell(anni.id, farCell.encode(), live: true);
        await pumpEventQueue();
        expect(repo.pairs, isEmpty);
        expect(
          seen.last.singleWhere((s) => s.buddyId == anni.id).position,
          isNull,
          reason: 'aus der Nähe heißt: auch die letzte genaue Position fällt',
        );
      },
    );

    test(
      'die genaue Position geht gedrosselt hinaus: alle 15 s oder nach 40 m',
      () async {
        repo.setCell(anni.id, nearCell.encode(), live: true);
        await sync();
        final n = repo.liveSent.length;
        await sync(pos: (lat: north(lat, 0.01), lon: lon)); // 10 m
        expect(repo.liveSent.length, n, reason: '10 m nach 0 s: nichts');
        await sync(pos: (lat: north(lat, 0.06), lon: lon)); // 60 m
        expect(repo.liveSent.length, n + 1);
        clock = clock.add(const Duration(seconds: 16));
        await sync(pos: (lat: north(lat, 0.06), lon: lon));
        expect(repo.liveSent.length, n + 2);
      },
    );

    test('Teilen aus: nichts bleibt im Speicher', () async {
      repo.setCell(anni.id, nearCell.encode(), live: true);
      await sync();
      expect(seen.last, isNotEmpty);
      await engine.sync(
        mine: null,
        buddies: {anni.id},
        muted: const {},
        session: 's1',
      );
      await pumpEventQueue();
      expect(seen.last, isEmpty);
      expect(repo.pairs, isEmpty);
    });

    test(
      'nimmt der Buddy die Zelle heraus, merkt die Engine, seit wann',
      () async {
        repo.setCell(ben.id, farCell.encode());
        await sync();
        clock = now.add(const Duration(minutes: 1));
        repo.setCell(ben.id, null);
        await pumpEventQueue();
        final s = seen.last.singleWhere((s) => s.buddyId == ben.id);
        expect(s.cellPresent, isFalse);
        expect(s.cellGoneAt, clock);
      },
    );
  });
}
