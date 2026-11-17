// Buddy in der Nähe (#526) — Zelle, Bedingungen und die Steuerung, ohne
// Oberfläche. Die Koordinaten sind erfunden (A7).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/nearby/nearby_core.dart';
import 'package:trailbuddy/features/nearby/nearby_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_nearby.dart';

/// Rund [km] Kilometer nördlich (1° Breite ≈ 111,2 km).
double north(double lat, double km) => lat + km / 111.2;

void main() {
  group('Zelle', () {
    const lat = 40.0, lon = 10.0;

    test('nah: dieselbe Zelle und die Nachbarzelle, auch über die Grenze', () {
      final a = NearbyCell.of(lat, lon);
      expect(a.isNearTo(NearbyCell.of(north(lat, 0.2), lon)), isTrue);
      // Zwei Punkte 300 m auseinander, aber beiderseits einer Zeilengrenze.
      final edge = (a.row + 1) * kNearbyCellDeg;
      final below = NearbyCell.of(edge - 0.0013, lon);
      final above = NearbyCell.of(edge + 0.0013, lon);
      expect(below, isNot(above));
      expect(below.isNearTo(above), isTrue);
    });

    test('fern: die übernächste Zelle ist nicht mehr in der Nähe', () {
      final a = NearbyCell.of(lat, lon);
      expect(a.isNearTo(NearbyCell.of(north(lat, 12), lon)), isFalse);
      expect(a.isNearTo(NearbyCell(a.row, a.col + 2)), isFalse);
      expect(a.isNearTo(NearbyCell(a.row + 1, a.col + 1)), isTrue, reason: 'Ecke');
    });

    test('ungefähr quadratisch, auch weit im Norden', () {
      for (final la in [0.0, 47.0, 65.0]) {
        final c = NearbyCell.of(la, 10);
        final right = NearbyCell(c.row, c.col + 1);
        final km = (right.centerLon - c.centerLon) * 111.2 * _cosDeg(c.centerLat);
        expect(km, closeTo(5.0, 0.1), reason: 'Breite $la');
      }
    });

    test('hinaus geht nur "zeile:spalte"; Fremdes wirft nie', () {
      final c = NearbyCell.of(lat, lon);
      expect(c.encode(), matches(RegExp(r'^-?\d+:-?\d+$')));
      expect(NearbyCell.tryParse(c.encode()), c);
      for (final bad in [null, 3, '', '1', '1:2:3', 'a:b', '99999:1', {'c': '1:2'}]) {
        expect(NearbyCell.tryParse(bad), isNull, reason: '$bad');
      }
    });
  });

  group('Wann geteilt wird', () {
    const here = (lat: 40.0, lon: 10.0);
    final home = (lat: north(40.0, 0.5), lon: 10.0);
    final farHome = (lat: north(40.0, 30), lon: 10.0);
    final start = (lat: north(40.0, 0.6), lon: 10.0);
    final farStart = (lat: north(40.0, 3), lon: 10.0);

    NearbyPause? pause({
      bool? enabled = true,
      NearbyPoint? position = here,
      NearbyPoint? home,
      NearbyPoint? rideStart,
      bool foreground = true,
    }) =>
        nearbyPause(enabled: enabled, position: position, home: home, rideStart: rideStart, foreground: foreground);

    test('aus oder nie gefragt: nichts', () {
      expect(pause(enabled: false, home: farHome), NearbyPause.off);
      expect(pause(enabled: null, home: farHome), NearbyPause.off);
    });

    test('ohne Position: nichts', () {
      expect(pause(position: null, home: farHome), NearbyPause.noPosition);
    });

    test('nie im Umkreis von „Zuhause" — auch nicht mit Aufzeichnung', () {
      expect(pause(home: home), NearbyPause.home);
      expect(pause(home: home, rideStart: farStart), NearbyPause.home);
    });

    test('mit Aufzeichnung erst ab 1 km vom Start, auch im Hintergrund', () {
      expect(pause(rideStart: start), NearbyPause.nearStart);
      expect(pause(rideStart: farStart), isNull);
      expect(pause(rideStart: farStart, foreground: false), isNull);
      expect(pause(rideStart: farStart, home: farHome), isNull);
    });

    test('ohne Aufzeichnung nur vorne und nur mit „Zuhause"', () {
      expect(pause(home: farHome), isNull);
      expect(pause(home: farHome, foreground: false), NearbyPause.background);
      expect(pause(), NearbyPause.noHome);
    });

    test('„Zuhause" übersteht den Merker', () {
      final raw = encodeNearbyHome(home);
      final back = parseNearbyHome(raw)!;
      expect(back.lat, closeTo(home.lat, 1e-5));
      expect(parseNearbyHome('kaputt'), isNull);
      expect(parseNearbyHome(null), isNull);
    });
  });

  group('Steuerung', () {
    late FakeBackend backend;
    late FakeUser me, anni, ben, gina;
    late FakeNearbyRepository repo;
    late List<String> told;
    late NearbyEngine engine;
    final mine = NearbyCell.of(40.0, 10.0);
    final near = NearbyCell.of(north(40.0, 2), 10.0).encode();
    final far = NearbyCell.of(north(40.0, 30), 10.0).encode();

    setUp(() {
      backend = FakeBackend();
      me = backend.addUser(username: 'ich');
      anni = backend.addUser(username: 'anni');
      ben = backend.addUser(username: 'ben');
      gina = backend.addUser(username: 'gina');
      backend.addFriendship(me.id, anni.id);
      backend.addFriendship(me.id, ben.id);
      backend.signInAs(me.id);
      repo = FakeNearbyRepository(backend);
      told = [];
      engine = NearbyEngine(repo, onNotice: told.add);
    });

    tearDown(() => engine.close());

    Future<void> sync({NearbyCell? at, Set<String>? muted, Object session = 's1'}) async {
      await engine.sync(
        mine: at,
        buddies: {anni.id, ben.id, gina.id},
        muted: muted ?? const {},
        session: session,
      );
      await pumpEventQueue();
    }

    test('teilt nur die Zelle und nimmt sie wieder heraus', () async {
      await sync(at: mine);
      expect(repo.shared, [mine.encode()]);
      expect(repo.cellsOf[me.id], mine.encode());
      await sync();
      expect(repo.shared.last, isNull);
      expect(repo.cellsOf.containsKey(me.id), isFalse);
      expect(repo.listening, isEmpty, reason: 'wer nicht teilt, hört nicht zu');
    });

    test('ein Buddy in der Nähe: einmal je Fahrt, eine neue Fahrt meldet neu', () async {
      repo.setCell(anni.id, near);
      await sync(at: mine);
      expect(told, [anni.id]);
      repo.setCell(anni.id, null);
      repo.setCell(anni.id, near);
      await sync(at: mine);
      expect(told, [anni.id], reason: 'dieselbe Fahrt: nicht noch einmal');
      await sync(at: mine, session: 's2');
      expect(told, [anni.id, anni.id]);
    });

    test('fern, stumm oder kein Buddy: keine Meldung', () async {
      repo.setCell(anni.id, far);
      repo.setCell(ben.id, near);
      repo.setCell(gina.id, near);
      await sync(at: mine, muted: {ben.id});
      expect(told, isEmpty);
      expect(repo.listening, {anni.id, ben.id}, reason: 'Gina ist kein Buddy — ihr Kanal ist zu');
    });

    test('„sieht mich" aus: Anni hört mich nicht und ich sie trotzdem', () async {
      repo.hiddenBy[anni.id] = {me.id};
      repo.setCell(anni.id, near);
      await sync(at: mine);
      expect(repo.listening.contains(anni.id), isFalse);
      expect(told, isEmpty);
    });

    test('kommt der Buddy erst später in die Nähe, meldet es sich dann', () async {
      repo.setCell(anni.id, far);
      await sync(at: mine);
      expect(told, isEmpty);
      repo.setCell(anni.id, near);
      await pumpEventQueue();
      expect(told, [anni.id]);
    });

    test('Schalter je Buddy noch nicht geladen: erst melden, wenn sie da sind', () async {
      repo.setCell(anni.id, near);
      await engine.sync(mine: mine, buddies: {anni.id}, muted: null, session: 's1');
      await pumpEventQueue();
      expect(told, isEmpty);
      await sync(at: mine);
      expect(told, [anni.id]);
    });

    test('ohne Empfang: nichts geteilt, nichts gemeldet, später schon', () async {
      repo.offline = true;
      repo.setCell(anni.id, near);
      await sync(at: mine);
      expect(repo.cellsOf.containsKey(me.id), isFalse);
      expect(told, isEmpty);
      repo.offline = false;
      // Der nächste Abgleich kommt mit dem Takt; zuhören erst nach der Pause.
      await sync(at: mine);
      expect(repo.cellsOf[me.id], mine.encode());
    });
  });
}

double _cosDeg(double deg) => math.cos(deg * math.pi / 180);
