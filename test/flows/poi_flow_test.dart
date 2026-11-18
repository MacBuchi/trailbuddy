// Orte auf der Karte (#12): Stecknadeln ab Zoom 12, Vorgabe „Wasser",
// Filter gemerkt, und keine Abfrage, wenn nichts eingeschaltet ist.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/poi_source.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_pois.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late FakePoiSource pois;
  late FakeSettings settings;

  const water = Poi(
    id: 'node/1',
    kind: PoiKind.drinkingWater,
    position: LatLng(48.004, 9.001),
    name: 'Brunnen am Hang',
    drinkable: true,
  );
  const cafe = Poi(
    id: 'node/2',
    kind: PoiKind.cafe,
    position: LatLng(48.006, 8.999),
    name: 'Hüttencafé',
    openingHours: 'Sa-Su 10:00-18:00',
  );

  final waterPin = find.byKey(const ValueKey('poi-node/1'));
  final cafePin = find.byKey(const ValueKey('poi-node/2'));

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(
      myId: () => backend.currentUserId ?? '',
      areFriends: backend.areFriends,
    );
    pois = FakePoiSource([water, cafe]);
    settings = FakeSettings();
  });

  /// Das Blatt ist halb so hoch wie der Schirm; die Ebenen stehen oben,
  /// die Orte darunter — erst hinscrollen.
  Future<void> tapInSheet(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await settle(tester, frames: 3);
    await tester.tap(f);
  }

  Future<void> start(WidgetTester tester, {bool withTrail = true}) async {
    // Ein Trail, damit die Karte von selbst auf Zoom 15 geht.
    if (withTrail) trails.seedTrail(backend.currentUserId!, name: 'Roots');
    await pumpApp(
      tester,
      backend,
      trails: trails,
      pois: pois,
      settings: settings,
    );
    await settle(tester, frames: 20);
  }

  testWidgets('Vorgabe: Trinkwasser als Nadel, Tipp zeigt, was es ist', (
    tester,
  ) async {
    await start(tester);
    expect(waterPin, findsOneWidget);
    expect(cafePin, findsNothing);
    expect(pois.groupsAsked.single, {PoiGroup.water});

    await tester.tap(waterPin);
    await settle(tester);
    expect(find.text('Brunnen am Hang'), findsOneWidget);
    expect(find.text('Trinkwasser laut OpenStreetMap.'), findsOneWidget);
    expect(find.text('Auf OpenStreetMap ansehen'), findsOneWidget);
  });

  testWidgets('Filter: Einkehr an, Wasser aus — und gemerkt', (tester) async {
    await start(tester);
    // Seit 0.75.0 (#190) öffnet der Knopf das Blatt direkt.
    await tester.tap(find.byTooltip('Kartenebenen'));
    await settle(tester);
    await tapInSheet(tester, find.byKey(const ValueKey('poi-group-food')));
    await tapInSheet(tester, find.byKey(const ValueKey('poi-group-water')));
    await settle(tester);
    expect(settings.poiGroups, ['food']);
    await tester.tapAt(const Offset(400, 20)); // Blatt schließen
    await settle(tester, frames: 20);

    expect(cafePin, findsOneWidget);
    expect(waterPin, findsNothing);
    // Nachgefragt wurde nur, was fehlte.
    expect(pois.groupsAsked.last, {PoiGroup.food});

    await tester.tap(cafePin);
    await settle(tester);
    expect(find.text('Öffnungszeiten: Sa-Su 10:00-18:00'), findsOneWidget);
  });

  testWidgets('Detailfilter: eine Art ausblenden, ohne neu zu fragen', (
    tester,
  ) async {
    settings.poiGroups = const ['food', 'water'];
    await start(tester);
    expect(waterPin, findsOneWidget);
    expect(cafePin, findsOneWidget);
    final asked = pois.calls.length;

    // Seit 0.75.0 (#190) öffnet der Knopf das Blatt direkt.
    await tester.tap(find.byTooltip('Kartenebenen'));
    await settle(tester);
    // Die Arten stehen unter ihrer Gruppe; Sonstiges ist aus, also ohne.
    expect(find.byKey(const ValueKey('poi-kind-biergarten')), findsOneWidget);
    expect(find.byKey(const ValueKey('poi-kind-parking')), findsNothing);
    await tapInSheet(tester, find.byKey(const ValueKey('poi-kind-cafe')));
    await settle(tester);
    expect(settings.poiHiddenKinds, ['cafe']);
    await tester.tapAt(const Offset(400, 20));
    await settle(tester, frames: 20);

    expect(cafePin, findsNothing);
    expect(waterPin, findsOneWidget);
    expect(pois.calls.length, asked, reason: 'ausblenden fragt nicht neu');
  });

  testWidgets('alles aus: keine einzige Abfrage', (tester) async {
    settings.poiGroups = const [];
    await start(tester);
    expect(pois.calls, isEmpty);
    expect(waterPin, findsNothing);
  });

  testWidgets('weit herausgezoomt: keine Abfrage', (tester) async {
    await start(tester, withTrail: false);
    expect(pois.calls, isEmpty);
  });

  testWidgets('Orte-Host nicht erreichbar: die Karte sagt es', (tester) async {
    pois.failWith = const PoiUnavailable(504);
    await start(tester);
    expect(find.text('Orte gerade nicht erreichbar'), findsOneWidget);
  });
}
