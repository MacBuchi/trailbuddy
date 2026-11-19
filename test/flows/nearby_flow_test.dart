// Buddy in der Nähe (#526) — durch die echte Oberfläche: die einmalige
// Frage, die Meldung vorne und hinten, die Schalter je Buddy und der
// Schalter im Profil. Die Koordinaten sind erfunden (A7).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trailbuddy/data/nearby_repository.dart';
import 'package:trailbuddy/features/nearby/nearby_core.dart';
import 'package:trailbuddy/features/nearby/nearby_host.dart';
import 'package:trailbuddy/features/nearby/nearby_providers.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_nearby.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

const _lat = 40.0, _lon = 10.0;

void main() {
  late FakeBackend backend;
  late FakeUser me, anni;
  late FakeNearbyRepository nearby;
  late List<String> background;
  late List<String> spoken;

  final near = NearbyCell.of(_lat + 2 / 111.2, _lon).encode();
  final far = NearbyCell.of(_lat + 30 / 111.2, _lon).encode();
  // „Zuhause" 20 km entfernt — ohne Aufzeichnung braucht es eins.
  final farHome = encodeNearbyHome((lat: _lat - 20 / 111.2, lon: _lon));

  setUp(() {
    backend = FakeBackend();
    me = backend.addUser(username: 'testrail');
    anni = backend.addUser(username: 'anni');
    backend.addFriendship(me.id, anni.id);
    backend.signInAs(me.id);
    nearby = FakeNearbyRepository(backend);
    background = [];
    spoken = [];
  });

  Future<FakeSettings> pump(
    WidgetTester tester, {
    bool? on = true,
    String? home,
    bool noHome = false,
    double lat = _lat,
    RecordedRide? ride,
    bool voice = false,
    Stream<Position?>? positions,
  }) async {
    final settings = FakeSettings(
      buddiesNearby: on,
      nearbyHome: noHome ? null : home ?? farHome,
      voiceCues: voice,
    );
    await pumpApp(
      tester,
      backend,
      settings: settings,
      nearby: nearby,
      position: fakePosition(lat, _lon),
      positionStream: positions,
      extraOverrides: [
        nearbyBackgroundNoticeProvider.overrideWithValue(
          ({required title, required body, required id}) async =>
              background.add(body),
        ),
        if (ride != null) rideProvider.overrideWith(() => _Riding(ride)),
        nearbySpeakProvider.overrideWithValue(
          (text, _) async => spoken.add(text),
        ),
      ],
    );
    await settle(tester);
    return settings;
  }

  testWidgets('ein Buddy in der Nähe: eine Leiste, und nur einmal', (
    tester,
  ) async {
    nearby.setCell(anni.id, near);
    await pump(tester);
    expect(
      nearby.cellsOf[me.id],
      NearbyCell.of(_lat, _lon).encode(),
      reason: 'meine Zelle liegt im Kanal — nie eine Position',
    );
    expect(
      find.text('anni ist auch gerade unterwegs — in der Nähe'),
      findsOneWidget,
    );
    expect(
      spoken,
      isEmpty,
      reason: 'ohne Fahrt (und ohne „Ansagen") keine Stimme',
    );

    // Anni verschwindet und kommt wieder: dieselbe Sitzung, keine zweite.
    nearby.setCell(anni.id, null);
    nearby.setCell(anni.id, near);
    await settle(tester, frames: 70);
    expect(find.byKey(const ValueKey('nearby-notice')), findsNothing);
  });

  testWidgets('fern oder stumm: keine Meldung', (tester) async {
    nearby.setCell(anni.id, far);
    await pump(tester);
    expect(find.byKey(const ValueKey('nearby-notice')), findsNothing);
  });

  testWidgets('im Umkreis von „Zuhause": nichts geteilt, nichts gehört', (
    tester,
  ) async {
    nearby.setCell(anni.id, near);
    await pump(tester, home: encodeNearbyHome((lat: _lat + 0.003, lon: _lon)));
    expect(nearby.cellsOf.containsKey(me.id), isFalse);
    expect(nearby.listening, isEmpty);
    expect(find.byKey(const ValueKey('nearby-notice')), findsNothing);
  });

  testWidgets('Schalter aus: nichts geteilt', (tester) async {
    nearby.setCell(anni.id, near);
    await pump(tester, on: false);
    expect(nearby.cellsOf.containsKey(me.id), isFalse);
    expect(find.byKey(const ValueKey('nearby-notice')), findsNothing);
  });

  testWidgets(
    'während einer Fahrt, App im Hintergrund: eine Benachrichtigung statt der Leiste',
    (tester) async {
      // Start 3 km zurück — der erste Kilometer ist vorbei.
      final ride = (
        startedAt: DateTime(2026, 9, 28, 11),
        points: [
          RidePoint(
            lat: _lat - 3 / 111.2,
            lng: _lon,
            at: DateTime(2026, 9, 28, 11),
            accuracyM: 5,
          ),
        ],
        marks: const <RideMark>[],
      );
      await pump(tester, noHome: true, ride: ride, voice: true);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NearbyHost)),
      );
      container.read(appForegroundProvider.notifier).set(false);
      await settle(tester);
      expect(
        nearby.cellsOf[me.id],
        isNotNull,
        reason: 'mit Fahrt teilt die App auch hinten, auch ohne „Zuhause"',
      );
      nearby.setCell(anni.id, near);
      await settle(tester);
      expect(background, ['anni ist auch gerade unterwegs — in der Nähe']);
      expect(spoken, [
        'anni ist auch gerade unterwegs — in der Nähe',
      ], reason: 'mit „Ansagen" auch übers Ohr');
      expect(find.byKey(const ValueKey('nearby-notice')), findsNothing);
    },
  );

  testWidgets('ohne Fahrt im Hintergrund: nichts geteilt', (tester) async {
    await pump(tester);
    expect(nearby.cellsOf[me.id], isNotNull);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NearbyHost)),
    );
    container.read(appForegroundProvider.notifier).set(false);
    await settle(tester);
    expect(nearby.cellsOf.containsKey(me.id), isFalse);
    nearby.setCell(anni.id, near);
    await settle(tester);
    expect(background, isEmpty);
  });

  testWidgets('erster Kilometer der Fahrt: nichts geteilt', (tester) async {
    final ride = (
      startedAt: DateTime(2026, 9, 28, 11),
      points: [
        RidePoint(
          lat: _lat - 0.4 / 111.2,
          lng: _lon,
          at: DateTime(2026, 9, 28, 11),
          accuracyM: 5,
        ),
      ],
      marks: const <RideMark>[],
    );
    nearby.setCell(anni.id, near);
    await pump(tester, noHome: true, ride: ride);
    expect(nearby.cellsOf.containsKey(me.id), isFalse);
    expect(find.byKey(const ValueKey('nearby-notice')), findsNothing);
  });

  testWidgets('die einmalige Frage: im Buddys-Reiter, „Ja" vorausgewählt', (
    tester,
  ) async {
    final settings = await pump(tester, on: null);
    expect(
      nearby.cellsOf.containsKey(me.id),
      isFalse,
      reason: 'vor der Antwort nichts',
    );
    await openTab(tester, 'Buddys');
    expect(find.byKey(const ValueKey('nearby-ask')), findsOneWidget);
    expect(find.text('Buddys unterwegs?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nearby-ask-yes')));
    await settle(tester);
    expect(settings.buddiesNearby, isTrue);
    expect(
      nearby.cellsOf[me.id],
      isNotNull,
      reason: 'ab der Antwort wird geteilt',
    );

    // Kein zweites Mal.
    await openTab(tester, 'Karte');
    await openTab(tester, 'Buddys');
    expect(find.byKey(const ValueKey('nearby-ask')), findsNothing);
  });

  testWidgets('„Nein" ist eine Antwort; danach nie wieder gefragt', (
    tester,
  ) async {
    final settings = await pump(tester, on: null);
    await openTab(tester, 'Buddys');
    await tester.tap(find.byKey(const ValueKey('nearby-ask-no')));
    await settle(tester);
    expect(settings.buddiesNearby, isFalse);
    expect(
      find.byKey(ValueKey('nearby-buddy-${anni.id}')),
      findsNothing,
      reason: 'ohne „Buddys unterwegs" keine Schalter je Buddy',
    );
  });

  testWidgets('je Buddy: „sieht mich" aus schließt ihn auf dem Server aus', (
    tester,
  ) async {
    await pump(tester);
    await openTab(tester, 'Buddys');
    await tester.tap(find.byKey(ValueKey('nearby-buddy-${anni.id}')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nearby-buddy-sees-me')));
    await settle(tester);
    expect(nearby.hiddenBy[me.id], {anni.id});
    expect(nearby.prefs[anni.id]?.hidden, isTrue);

    await tester.tap(find.byKey(const ValueKey('nearby-buddy-notify')));
    await settle(tester);
    expect(nearby.prefs[anni.id]?.muted, isTrue);

    // Zurück auf die Vorgabe löscht die Zeile.
    await tester.tap(find.byKey(const ValueKey('nearby-buddy-sees-me')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nearby-buddy-notify')));
    await settle(tester);
    expect(nearby.prefs, isEmpty);
  });

  testWidgets('stumm: Anni in der Nähe, aber keine Meldung', (tester) async {
    nearby.prefs[anni.id] = NearbyPref(buddyId: anni.id, muted: true);
    nearby.setCell(anni.id, near);
    await pump(tester);
    expect(find.byKey(const ValueKey('nearby-notice')), findsNothing);
  });

  testWidgets('Profil: Schalter, Zustand und „Zuhause"', (tester) async {
    final settings = await pump(tester, noHome: true);
    await openTab(tester, 'Profil');
    await tester.tap(find.text('Benachrichtigungen'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('nearby-home')),
      100,
    );
    expect(
      find.text('Ohne Aufzeichnung erst, wenn „Zuhause“ festgelegt ist'),
      findsOneWidget,
    );
    expect(nearby.cellsOf.containsKey(me.id), isFalse);

    await tester.tap(find.byKey(const ValueKey('nearby-home')));
    await settle(tester);
    expect(settings.nearbyHome, isNotNull);
    expect(
      find.text('Pausiert: im Umkreis von „Zuhause“'),
      findsOneWidget,
      reason: '„Zuhause" ist, wo man gerade steht',
    );

    await tester.tap(find.byKey(const ValueKey('nearby-switch')));
    await settle(tester);
    expect(settings.buddiesNearby, isFalse);
    expect(find.byKey(const ValueKey('nearby-home')), findsNothing);
  });

  // W47 (#566): Während einer Fahrt kommen Punkt und Fix im selben Frame.
  // Riverpod flushte `nearbyPauseProvider` (wartet wegen der Fahrt) und
  // baute dabei `nearbyPositionProvider` neu; der Host las die Pause
  // synchron im Listener, sie baute sich mitten im Flush neu und änderte
  // die Abhängigkeiten, über die Riverpod gerade lief —
  // `ConcurrentModificationError` im Build des ProviderScope.
  testWidgets('Fahrt und Fix im selben Frame: kein Fehler im Flush', (
    tester,
  ) async {
    final fixes = StreamController<Position?>.broadcast();
    addTearDown(fixes.close);
    final start = DateTime(2026, 9, 28, 11);
    RidePoint point(int i) => RidePoint(
      lat: _lat + i * 2 / 111.2,
      lng: _lon,
      at: start.add(Duration(minutes: i)),
      accuracyM: 5,
    );
    final ride = (
      startedAt: start,
      points: [point(-2)],
      marks: const <RideMark>[],
    );
    await pump(tester, noHome: true, ride: ride, positions: fixes.stream);
    fixes.add(fakePosition(_lat, _lon));
    await settle(tester);
    expect(nearby.cellsOf[me.id], NearbyCell.of(_lat, _lon).encode());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NearbyHost)),
    );
    final riding = container.read(rideProvider.notifier) as _Riding;
    for (var i = 1; i <= 4; i++) {
      riding.add(point(i));
      fixes.add(fakePosition(_lat + i * 2 / 111.2, _lon));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'Fix $i');
    }
    expect(
      nearby.cellsOf[me.id],
      NearbyCell.of(_lat + 8 / 111.2, _lon).encode(),
      reason: 'die Zelle wandert mit dem Fix',
    );
  });
}

class _Riding extends RideNotifier {
  _Riding(this.ride);

  final RecordedRide ride;

  @override
  RecordedRide? build() => ride;

  void add(RidePoint p) {
    final r = state!;
    state = (startedAt: r.startedAt, points: [...r.points, p], marks: r.marks);
  }
}
