// Push-Benachrichtigungen (#34): der Schalter im Profil, die
// Testnachricht, eine Meldung im Vordergrund und der Weg zum Trail.
//
// Nicht geprüft wird FCM selbst — das Harness reicht ein Token herein
// und liefert Meldungen über einen Strom. Geprüft wird, was die App
// daraus macht: Ob das Gerät wirklich eingetragen wird, ob der Schalter
// das ERGEBNIS zeigt (und nicht den Wunsch), und ob ein Tipp auf die
// Meldung den Trail auf der Karte findet — auch dann, wenn die Karte den
// Wunsch bekommt, bevor die Trails geladen sind.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/push_messaging.dart';
import 'package:trailbuddy/core/router.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

const kRootsId = '11111111-0000-0000-0000-000000000001';

void main() {
  late FakeBackend backend;
  late String annaId, bobId;
  late FakeTrailRepository trails;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    annaId = anna.id;
    bobId = bob.id;
    trails = FakeTrailRepository(
        myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
  });

  Future<void> scrollToSwitch(WidgetTester tester) async {
    await openProfilePage(tester, 'notifications');
    await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Benachrichtigungen'), 200,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);
  }

  testWidgets('Einschalten trägt das Gerät ein, Ausschalten wieder aus',
      (tester) async {
    final settings = FakeSettings();
    final push = FakePushRepository(backend);
    await pumpApp(tester, backend, trails: trails, settings: settings, push: push);
    await scrollToSwitch(tester);

    final tile = find.widgetWithText(SwitchListTile, 'Benachrichtigungen');
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.text('Testnachricht senden'), findsNothing,
        reason: 'ohne eingetragenes Gerät gibt es nichts zu testen');

    await tester.tap(tile);
    await settle(tester);
    expect(backend.pushDevices, {'test-token': annaId});
    expect(backend.pushLocales, {'test-token': 'de'},
        reason: 'die Meldungen kommen in der Sprache der App (Patch 027)');
    expect(settings.pushToken, 'test-token');
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    // Die Testnachricht geht an DIESES Token.
    await tester.tap(find.text('Testnachricht senden'));
    await settle(tester);
    expect(push.tests, ['test-token']);
    expect(find.text('Testnachricht ist unterwegs.'), findsOneWidget);
    await drainSnackbars(tester);

    await tester.tap(tile);
    await settle(tester);
    expect(backend.pushDevices, isEmpty);
    expect(settings.pushToken, isNull);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  });

  testWidgets('Wer die Berechtigung ablehnt, sieht den Schalter zurückspringen',
      (tester) async {
    await pumpApp(tester, backend, trails: trails, extraOverrides: [
      pushTokenProvider.overrideWithValue(
          () async => (token: null, denied: true, unavailable: false)),
    ]);
    await scrollToSwitch(tester);
    final tile = find.widgetWithText(SwitchListTile, 'Benachrichtigungen');
    await tester.tap(tile);
    await settle(tester);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(backend.pushDevices, isEmpty);
    expect(find.textContaining('nicht erlaubt'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Ein Build ohne Firebase sagt das, statt „hat nicht geklappt"',
      (tester) async {
    await pumpApp(tester, backend, trails: trails, extraOverrides: [
      pushTokenProvider.overrideWithValue(
          () async => (token: null, denied: false, unavailable: true)),
    ]);
    await scrollToSwitch(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Benachrichtigungen'));
    await settle(tester);
    expect(find.textContaining('noch nicht eingerichtet'), findsOneWidget);
    expect(backend.pushDevices, isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('Scheitert das Eintragen, bleibt der Schalter aus', (tester) async {
    final settings = FakeSettings();
    final push = FakePushRepository(backend)..failNextRegister = StateError('db down');
    await pumpApp(tester, backend, trails: trails, settings: settings, push: push);
    await scrollToSwitch(tester);
    final tile = find.widgetWithText(SwitchListTile, 'Benachrichtigungen');
    await tester.tap(tile);
    await settle(tester);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(settings.pushToken, isNull,
        reason: 'ein Token ohne Zeile in push_devices wäre eine Lüge');
    await drainSnackbars(tester);
  });

  testWidgets('Ein gemerktes Token heißt „an" — auch nach dem Neustart',
      (tester) async {
    await pumpApp(tester, backend, trails: trails,
        settings: FakeSettings(pushToken: 'alt'));
    await scrollToSwitch(tester);
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Benachrichtigungen'))
            .value,
        isTrue);
    expect(find.text('Testnachricht senden'), findsOneWidget);
  });

  testWidgets('Die Sprache der Meldungen folgt der App (#209)', (tester) async {
    // Eingetragen vor 0.119: Token da, Sprache nie geschrieben. Der Start
    // trägt sie einmal nach, danach nur noch bei einem Wechsel.
    backend.pushDevices['alt'] = annaId;
    final settings = FakeSettings(pushToken: 'alt');
    final push = FakePushRepository(backend);
    await pumpApp(tester, backend, trails: trails, settings: settings, push: push);
    expect(backend.pushLocales, {'alt': 'de'});
    expect(settings.pushLocale, 'de');

    // Der nächste Start schreibt nicht noch einmal (sonst bei JEDEM
    // Start eine Zeile ins Netz). SizedBox dazwischen: Kaltstart.
    backend.pushLocales.clear();
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, backend, trails: trails, settings: settings, push: push);
    expect(backend.pushLocales, isEmpty, reason: 'gleiche Sprache, nichts zu schreiben');

    await openProfilePage(tester, 'language');
    await tester.tap(find.text('English'));
    await settle(tester);
    expect(backend.pushLocales, {'alt': 'en'});
    expect(settings.pushLocale, 'en');
    expect(backend.pushDevices, {'alt': annaId}, reason: 'dieselbe Zeile, kein zweites Gerät');
  });

  testWidgets('Ohne Push schreibt der Sprachwechsel nichts', (tester) async {
    final settings = FakeSettings();
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await openProfilePage(tester, 'language');
    await tester.tap(find.text('English'));
    await settle(tester);
    expect(backend.pushDevices, isEmpty);
    expect(settings.pushLocale, isNull);
  });

  testWidgets('Eine Meldung im Vordergrund erscheint als Leiste, „Öffnen" zeigt den Trail',
      (tester) async {
    // Eine ECHTE Kennung: Die Erlaubnisliste nimmt nur UUIDs an.
    final roots = trails.seedTrail(bobId, name: 'Roots', lat: 48.5, lon: 9.5, trailId: kRootsId);
    trails.seedTrail(bobId, name: 'Weit weg', lat: 47.0, lon: 8.0);
    final incoming = StreamController<RemoteMessage>.broadcast();
    addTearDown(incoming.close);
    await pumpApp(tester, backend, trails: trails, pushMessages: incoming.stream);
    // Weg von der Karte: Die Leiste muss überall erscheinen.
    await openTab(tester, 'Profil');

    incoming.add(RemoteMessage(
      notification: const RemoteNotification(
          title: 'Ein Buddy meldet einen Trail als gesperrt',
          body: 'Tippen zeigt den Trail'),
      data: {'route': '/trail/$roots'},
    ));
    await settle(tester);
    expect(find.text('Ein Buddy meldet einen Trail als gesperrt'), findsOneWidget);
    expect(find.text('Tippen zeigt den Trail'), findsOneWidget);

    await tester.tap(find.text('Öffnen'));
    await settle(tester, frames: 12);
    // Zurück auf der Karte, und die Kamera steht auf DIESEM Trail.
    expect(find.byType(NavigationBar), findsOneWidget);
    final cam = fakeMap(tester).camera;
    expect(cam.center.latitude, closeTo(48.5, 0.01));
    expect(cam.center.longitude, closeTo(9.5, 0.01));
  });

  testWidgets('Ohne bekanntes Ziel gibt es keinen „Öffnen"-Knopf', (tester) async {
    final incoming = StreamController<RemoteMessage>.broadcast();
    addTearDown(incoming.close);
    await pumpApp(tester, backend, trails: trails, pushMessages: incoming.stream);
    incoming.add(const RemoteMessage(
      notification: RemoteNotification(title: 'TrailBuddy', body: 'Test — so sieht eine Benachrichtigung aus.'),
      data: {'route': 'https://example.org/'},
    ));
    await settle(tester);
    expect(find.text('Test — so sieht eine Benachrichtigung aus.'), findsOneWidget);
    expect(find.text('Öffnen'), findsNothing);
  });

  testWidgets('Der Fokus-Wunsch vor dem Laden der Trails wird eingelöst, sobald sie da sind',
      (tester) async {
    // Der Kaltstart aus einer Push (Route /trail/<id>, Web-Worker oder
    // Startmeldung): Die Karte bekommt den Wunsch, bevor sie den Trail
    // kennt — und darf ihn nicht verwerfen.
    final roots = trails.seedTrail(bobId, name: 'Roots', lat: 48.5, lon: 9.5, trailId: kRootsId);
    trails.seedTrail(bobId, name: 'Weit weg', lat: 47.0, lon: 8.0);
    final gate = Completer<void>();
    trails.fetchGate = gate.future;
    await pumpApp(tester, backend, trails: trails);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(NavigationBar)), listen: false);
    container.read(routerProvider).go('/trail/$roots');
    await settle(tester);
    expect(container.read(mapFocusTrailProvider), isNull,
        reason: 'die Karte hat den Wunsch übernommen (und wartet)');
    gate.complete();
    await settle(tester, frames: 12);
    final cam = fakeMap(tester).camera;
    expect(cam.center.latitude, closeTo(48.5, 0.01));
    expect(cam.center.longitude, closeTo(9.5, 0.01));
  });
}
