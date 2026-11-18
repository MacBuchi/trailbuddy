// Gruppenfahrt (#519) — durch die echte Oberfläche: der Knopf „Live" in
// der Fahrt, Buddys auf der Karte (genau nur in der Nähe mit Live, grob nur
// für Homies) und der Schalter „Homie" je Buddy. Die Koordinaten sind
// erfunden (A7).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/nearby/nearby_core.dart';
import 'package:trailbuddy/features/nearby/nearby_host.dart';
import 'package:trailbuddy/features/nearby/nearby_providers.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_nearby.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

const _lat = 40.0, _lon = 10.0;

void main() {
  late FakeBackend backend;
  late FakeUser me, anni, ben;
  late FakeNearbyRepository nearby;

  final near = NearbyCell.of(_lat + 2 / 111.2, _lon).encode();
  final far = NearbyCell.of(_lat + 30 / 111.2, _lon).encode();
  final farHome = encodeNearbyHome((lat: _lat - 20 / 111.2, lon: _lon));
  // Start 3 km zurück — der erste Kilometer ist vorbei.
  RecordedRide ride(DateTime at) => (
        startedAt: at,
        points: [RidePoint(lat: _lat - 3 / 111.2, lng: _lon, at: at, accuracyM: 5)],
        marks: const <RideMark>[],
      );

  setUp(() {
    backend = FakeBackend();
    me = backend.addUser(username: 'testrail');
    anni = backend.addUser(username: 'anni');
    ben = backend.addUser(username: 'ben');
    backend.addFriendship(me.id, anni.id);
    backend.addFriendship(me.id, ben.id);
    backend.signInAs(me.id);
    nearby = FakeNearbyRepository(backend);
  });

  Future<void> pump(WidgetTester tester, {RecordedRide? riding}) async {
    await pumpApp(tester, backend,
        settings: FakeSettings(buddiesNearby: true, nearbyHome: farHome),
        nearby: nearby,
        position: fakePosition(_lat, _lon),
        extraOverrides: [
          nearbyBackgroundNoticeProvider.overrideWithValue(({required title, required body, required id}) async {}),
          nearbySpeakProvider.overrideWithValue((text, _) async {}),
          if (riding != null) rideProvider.overrideWith(() => _Riding(riding)),
        ]);
    await settle(tester);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(NearbyHost)));

  testWidgets('Live in der Fahrt: Anni in der Nähe mit Live steht genau auf der Karte, bis Live aus ist',
      (tester) async {
    nearby.setCell(anni.id, near, live: true);
    nearby.setPosition(anni.id, _lat + 2 / 111.2, _lon);
    await pump(tester, riding: ride(DateTime(2026, 9, 28, 11)));
    expect(find.byKey(const ValueKey('live-share-button')), findsOneWidget);
    expect(nearby.sharedLive.last, isFalse, reason: 'ab Werk aus');
    expect(find.byKey(ValueKey('buddy-live-${anni.id}')), findsNothing, reason: 'ohne eigenes Live nichts Genaues');

    await tester.tap(find.byKey(const ValueKey('live-share-button')));
    await settle(tester);
    expect(find.byKey(const ValueKey('live-share-note')), findsOneWidget);
    expect(nearby.sharedLive.last, isTrue);
    expect(nearby.pairs, {anni.id});
    expect(nearby.liveSent, isNotEmpty, reason: 'meine genaue Position geht an Anni');
    expect(find.byKey(ValueKey('buddy-live-${anni.id}')), findsOneWidget);
    expect(find.text('A'), findsWidgets, reason: 'eine Scheibe mit dem Anfangsbuchstaben');

    await tapMapAt(tester, const LatLng(_lat + 2 / 111.2, _lon));
    await settle(tester);
    expect(find.text('anni — genaue Position, live'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-share-button')));
    await settle(tester);
    expect(nearby.pairs, isEmpty);
    expect(find.byKey(ValueKey('buddy-live-${anni.id}')), findsNothing);
  });

  testWidgets('Live endet mit der Fahrt — die nächste beginnt aus', (tester) async {
    await pump(tester, riding: ride(DateTime(2026, 9, 28, 11)));
    final c = containerOf(tester);
    c.read(liveShareProvider.notifier).set(true);
    expect(c.read(liveShareProvider), isTrue);
    (c.read(rideProvider.notifier) as _Riding).replace(ride(DateTime(2026, 9, 29, 9)));
    await settle(tester);
    expect(c.read(liveShareProvider), isFalse);
    (c.read(rideProvider.notifier) as _Riding).replace(null);
    await settle(tester);
    c.read(liveShareProvider.notifier).set(true);
    expect(c.read(liveShareProvider), isFalse, reason: 'ohne Fahrt gibt es kein Live');
    expect(find.byKey(const ValueKey('live-share-button')), findsNothing);
  });

  testWidgets('ohne Fahrt kein Knopf „Live"', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('live-share-button')), findsNothing);
  });

  testWidgets('Homie: Annis Zelle steht grob auf der Karte, Bens nicht', (tester) async {
    nearby.homieBy[anni.id] = {me.id};
    nearby.setCell(anni.id, far);
    nearby.setCell(ben.id, far);
    await pump(tester);
    expect(find.byKey(ValueKey('buddy-cell-${anni.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('buddy-cell-${ben.id}')), findsNothing, reason: 'Ben hat mich nicht gewählt');
    expect(find.byKey(ValueKey('buddy-live-${anni.id}')), findsNothing, reason: 'grob, nie genau');

    final cell = NearbyCell.tryParse(far)!;
    await tapMapAt(tester, LatLng(cell.centerLat, cell.centerLon));
    await settle(tester);
    expect(find.text('anni ist gerade irgendwo in diesem Quadrat (~5 km) — grob, nicht live'), findsOneWidget);
  });

  testWidgets('Homie, der mich ausgeschlossen hat: nichts', (tester) async {
    nearby.homieBy[anni.id] = {me.id};
    nearby.hiddenBy[anni.id] = {me.id};
    nearby.setCell(anni.id, far);
    await pump(tester);
    expect(find.byKey(ValueKey('buddy-cell-${anni.id}')), findsNothing);
  });

  testWidgets('je Buddy: „Homie" schreibt die Wahl, „sieht mich" aus sperrt sie', (tester) async {
    await pump(tester);
    await openTab(tester, 'Buddys');
    await tester.tap(find.byKey(ValueKey('nearby-buddy-${anni.id}')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nearby-buddy-homie')));
    await settle(tester);
    expect(nearby.prefs[anni.id]?.homie, isTrue);
    expect(nearby.homieBy[me.id], {anni.id});

    await tester.tap(find.byKey(const ValueKey('nearby-buddy-sees-me')));
    await settle(tester);
    final homie = tester.widget<SwitchListTile>(find.byKey(const ValueKey('nearby-buddy-homie')));
    expect(homie.value, isFalse, reason: 'wer mich nicht sieht, ist kein Homie');
    expect(homie.onChanged, isNull);

    await tester.tap(find.byKey(const ValueKey('nearby-buddy-sees-me')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nearby-buddy-homie')));
    await settle(tester);
    expect(nearby.prefs, isEmpty, reason: 'alles auf der Vorgabe: keine Zeile');
  });
}

class _Riding extends RideNotifier {
  _Riding(this.ride);

  final RecordedRide ride;

  @override
  RecordedRide? build() => ride;

  void replace(RecordedRide? next) => state = next;
}
