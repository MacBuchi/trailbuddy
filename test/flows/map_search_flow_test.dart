// Die Suche auf der Karte (#576, Stufe 1) durch die echte Oberfläche:
// Lupe → Feld; ein Trail wird eingepasst und leuchtet, ein Ort und ein
// Startpunkt kommen in die Mitte und öffnen ihr Blatt; Orte aller
// Gruppen um die Kartenmitte, auch wenn die Gruppe auf der Karte aus ist;
// ohne Netz sagt die Suche es; X und Zurück schließen. Stufe 2: Ortsnamen
// aus dem Index des Hosts (hier `FakePlaceSource`). Alle Koordinaten
// sind erfunden (A7).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_search.dart';
import 'package:trailbuddy/features/map/place.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/poi_source.dart';
import 'package:trailbuddy/models/start_point.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_pois.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late String annaId;
  late FakeTrailRepository trails;
  late FakePoiSource pois;
  late FakePlaceSource places;
  late String hirschId;

  const here = LatLng(47.5, 10.5);
  const fountain = LatLng(47.52, 10.51);
  const shop = LatLng(47.48, 10.49);

  setUp(() {
    places = FakePlaceSource([
      const Place(
        id: 'node/40',
        kind: PlaceKind.peak,
        name: 'Grünstein',
        ele: 2042,
        position: LatLng(47.9, 10.9),
      ),
      const Place(
        id: 'node/41',
        kind: PlaceKind.hut,
        name: 'Grünsteinhütte',
        position: LatLng(47.88, 10.88),
      ),
    ]);
    backend = FakeBackend();
    annaId = backend.addUser(username: 'anna').id;
    backend.signInAs(annaId);
    trails = FakeTrailRepository(
      myId: () => backend.currentUserId ?? '',
      areFriends: backend.areFriends,
    );
    hirschId = trails.seedTrail(
      annaId,
      name: 'Hirschsprung',
      lat: 47.45,
      lon: 10.45,
    );
    trails.seedTrail(annaId, name: 'Roots', lat: 47.55, lon: 10.55);
    trails.startPoints.add(
      StartPoint(
        clientId: 's1',
        userId: annaId,
        name: 'Parkplatz Talboden',
        lat: 47.51,
        lon: 10.52,
        createdAt: DateTime.utc(2026, 11, 19),
      ),
    );
    pois = FakePoiSource([
      const Poi(id: 'node/1', kind: PoiKind.drinkingWater, position: fountain),
      const Poi(
        id: 'node/2',
        kind: PoiKind.bikeShop,
        position: shop,
        name: 'Radl Huber',
      ),
    ]);
  });

  Future<void> start(WidgetTester tester) async {
    await pumpApp(tester, backend, trails: trails, pois: pois, places: places);
    await settle(tester, frames: 20);
    fakeMap(tester).move(here, 13);
    await settle(tester, frames: 20);
  }

  Future<void> openAndType(WidgetTester tester, String text) async {
    await tester.tap(find.byKey(const ValueKey('search-button')));
    await settle(tester);
    expect(find.byKey(const ValueKey('map-search')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('map-search-field')),
      text,
    );
    await settle(tester);
  }

  testWidgets('ein Trail: eingepasst, er leuchtet, die Schnellkarte steht', (
    tester,
  ) async {
    await start(tester);
    await openAndType(tester, 'hirsch');
    expect(find.byKey(ValueKey('map-search-trail-$hirschId')), findsOneWidget);
    expect(find.text('Roots'), findsNothing);

    await tester.tap(find.byKey(ValueKey('map-search-trail-$hirschId')));
    await settle(tester, frames: 20);
    expect(find.byKey(const ValueKey('map-search')), findsNothing);
    expect(find.byKey(const ValueKey('trail-quick-card')), findsOneWidget);
    expect(
      fakeMap(tester).center.latitude,
      closeTo(47.4545, 0.01),
      reason: 'die Karte steht auf dem Trail, nicht mehr in der Mitte',
    );
  });

  testWidgets(
    'Orte aller Gruppen um die Mitte — der Radladen, obwohl „Rad-Service" aus ist',
    (tester) async {
      await start(tester);
      expect(
        pois.groupsAsked.expand((g) => g),
        isNot(contains(PoiGroup.bikeService)),
        reason: 'ab Werk zeigt die Karte nur „Wasser"',
      );
      await openAndType(tester, 'radladen');
      expect(pois.groupsAsked.last, PoiGroup.values.toSet());
      expect(
        pois.cellsAsked.last.toSet(),
        mapSearchPoiCells(here).toSet(),
        reason: 'die Zelle der Mitte und ihre Nachbarn, sonst nichts',
      );
      expect(
        find.byKey(const ValueKey('map-search-poi-node/2')),
        findsOneWidget,
      );
      expect(find.text('Radl Huber'), findsOneWidget);

      // „Trinkwasser" ohne Namen — über die Art.
      await tester.enterText(
        find.byKey(const ValueKey('map-search-field')),
        'trinkwasser',
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('map-search-poi-node/1')));
      await settle(tester, frames: 20);
      expect(find.byKey(const ValueKey('map-search')), findsNothing);
      expect(fakeMap(tester).center.latitude, closeTo(fountain.latitude, 1e-6));
      expect(fakeMap(tester).zoom, greaterThanOrEqualTo(kMapSearchFlyZoom));
      expect(
        find.byKey(const ValueKey('poi-route')),
        findsOneWidget,
        reason: 'das Blatt des Ortes ist offen',
      );
    },
  );

  testWidgets('ein Startpunkt: in die Mitte, sein Blatt geht auf', (
    tester,
  ) async {
    await start(tester);
    await openAndType(tester, 'talbod');
    await tester.tap(find.text('Parkplatz Talboden'));
    await settle(tester, frames: 20);
    expect(fakeMap(tester).center.latitude, closeTo(47.51, 1e-6));
    expect(find.byKey(const ValueKey('start-point-as-start')), findsOneWidget);
  });

  testWidgets('Tippfehler: „Meintest du …?" über dem geratenen Treffer', (
    tester,
  ) async {
    await start(tester);
    await openAndType(tester, 'Hirschsbrung');
    expect(find.byKey(const ValueKey('map-search-guess')), findsOneWidget);
    expect(find.byKey(ValueKey('map-search-trail-$hirschId')), findsOneWidget);
  });

  testWidgets('ohne Netz: die Suche sagt, dass Orte fehlen; Trails gehen', (
    tester,
  ) async {
    pois.failWith = const PoiUnavailable(503);
    await start(tester);
    pois.failWith = const PoiUnavailable(503);
    await openAndType(tester, 'hirsch');
    expect(
      find.byKey(const ValueKey('map-search-pois-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('map-search-trail-$hirschId')), findsOneWidget);
  });

  testWidgets('X und Zurück schließen; nichts gefunden sagt, wo gesucht wird', (
    tester,
  ) async {
    await start(tester);
    await openAndType(tester, 'zzzz');
    expect(find.byKey(const ValueKey('map-search-nothing')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-search-close')));
    await settle(tester);
    expect(find.byKey(const ValueKey('map-search')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('search-button')));
    await settle(tester);
    expect(find.byKey(const ValueKey('map-search')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byKey(const ValueKey('map-search')), findsNothing);
  });

  testWidgets(
    'Ortsnamen (#576 Stufe 2): ein Gipfel weit weg, hin; die Hütte öffnet ihr Blatt',
    (tester) async {
      await start(tester);
      await openAndType(tester, 'Grünstein');
      expect(places.queries.last, 'Grünstein');
      expect(
        find.byKey(const ValueKey('map-search-place-node/40')),
        findsOneWidget,
      );
      expect(find.text('Gipfel · 2042 m'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('map-search-place-node/40')));
      await settle(tester, frames: 20);
      expect(find.byKey(const ValueKey('map-search')), findsNothing);
      expect(fakeMap(tester).center.latitude, closeTo(47.9, 1e-6));
      expect(
        fakeMap(tester).zoom,
        greaterThanOrEqualTo(PlaceKind.peak.flyZoom),
      );

      await openAndType(tester, 'grunsteinhutte');
      await tester.tap(find.byKey(const ValueKey('map-search-place-node/41')));
      await settle(tester, frames: 20);
      expect(fakeMap(tester).center.latitude, closeTo(47.88, 1e-6));
      expect(
        find.byKey(const ValueKey('poi-route')),
        findsOneWidget,
        reason: 'eine Hütte ist ein Ort der Karte — ihr Blatt ist offen',
      );
    },
  );

  testWidgets('Ortsnamen ohne Netz: die Suche sagt, woher sie kommen', (
    tester,
  ) async {
    places.offline = true;
    await start(tester);
    await openAndType(tester, 'Grünstein');
    expect(
      find.byKey(const ValueKey('map-search-places-offline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('map-search-place-node/40')),
      findsOneWidget,
    );
  });
}
