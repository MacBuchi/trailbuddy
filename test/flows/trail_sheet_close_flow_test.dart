// Das Trail-Blatt lässt sich schließen (#215): mit dem X im Kopf, mit der
// Zurück-Taste und durch Ziehen nach unten — auch auf dem Inhalt, nicht
// nur am Griff. Aus der Karte (Schnellkarte) und aus der Liste.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.seedTrail(anna.id, name: 'Hexentanz', grade: 2);
  });

  final title = find.byKey(const ValueKey('trail-sheet-title'));

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> openFromMap(WidgetTester tester) async {
    await phone(tester);
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);
    await tapMapAt(tester, const LatLng(48.0005, 9.0));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('trail-quick-open')));
    await settle(tester);
    expect(title, findsOneWidget);
  }

  Future<void> openFromList(WidgetTester tester) async {
    await phone(tester);
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text('Hexentanz'));
    await settle(tester);
    expect(title, findsOneWidget);
  }

  Future<bool> back(WidgetTester tester) async {
    final handled = await tester.binding.handlePopRoute();
    await settle(tester);
    return handled;
  }

  testWidgets('Karte: das X im Kopf schließt das Blatt', (tester) async {
    await openFromMap(tester);
    await tester.tap(find.byKey(const ValueKey('trail-sheet-close')));
    await settle(tester);
    expect(title, findsNothing);
  });

  testWidgets('Karte: Zurück schließt das Blatt, dann die Auswahl', (tester) async {
    await openFromMap(tester);
    expect(await back(tester), isTrue);
    expect(title, findsNothing);
    expect(find.byKey(const ValueKey('trail-quick-card')), findsOneWidget, reason: 'erst das Blatt');
    expect(await back(tester), isTrue);
    expect(find.byKey(const ValueKey('trail-quick-card')), findsNothing);
  });

  testWidgets('Karte: nach unten ziehen auf dem Inhalt schließt das Blatt', (tester) async {
    await openFromMap(tester);
    await tester.fling(title, const Offset(0, 600), 2000);
    await settle(tester, frames: 30);
    expect(title, findsNothing);
  });

  testWidgets('Liste: X, Zurück und Ziehen schließen das Blatt', (tester) async {
    await openFromList(tester);
    await tester.tap(find.byKey(const ValueKey('trail-sheet-close')));
    await settle(tester);
    expect(title, findsNothing);

    await tester.tap(find.text('Hexentanz'));
    await settle(tester);
    expect(await back(tester), isTrue);
    expect(title, findsNothing);
    expect(find.text('Hexentanz'), findsOneWidget, reason: 'die Liste bleibt');

    await tester.tap(find.text('Hexentanz'));
    await settle(tester);
    await tester.fling(title, const Offset(0, 600), 2000);
    await settle(tester, frames: 30);
    expect(title, findsNothing);
  });
}
