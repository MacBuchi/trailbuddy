// Das Profil (Design 1l, seit 0.41.0): Kopf mit Zahlen, darunter Zeilen
// mit ihrem aktuellen Wert, jede führt auf ihre Seite.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('Kopf zählt eigene Trails, Buddys und Fahrten; Zeilen zeigen ihren Wert',
      (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    final jan = backend.addUser(username: 'jan');
    final mira = backend.addUser(username: 'mira');
    backend.signInAs(me.id);
    backend.addFriendship(me.id, jan.id);
    // Eine offene Anfrage ist (noch) kein Buddy.
    backend.addFriendship(mira.id, me.id, status: 'pending');
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.seedTrail(me.id, name: 'Meiner');
    trails.seedTrail(me.id, name: 'Auch meiner', lat: 48.1);
    // Nur von Jan: sichtbar, aber nicht meiner.
    trails.seedTrail(jan.id, name: 'Von Jan', lat: 48.2);
    await pumpApp(tester, backend, trails: trails, settings: FakeSettings(appearance: 'dark'));
    await openTab(tester, 'Profil');

    expect(find.text('TESTRAIL'), findsOneWidget);
    expect(findLabel('testrail'), findsOneWidget, reason: 'der Bildschirmleser liest den Namen, wie er geschrieben ist');
    expect((tester.widget(find.byKey(const ValueKey('profile-stats'))) as Text).data,
        '2 Trails · 1 Buddy · 0 Fahrten');

    Finder value(String id, String text) =>
        find.descendant(of: find.byKey(ValueKey('profile-$id')), matching: find.text(text));
    expect(value('notifications', 'Aus'), findsOneWidget);
    expect(value('rider', 'Bio-Bike'), findsOneWidget, reason: 'Vorgabe Bio-Bike');
    expect(value('navigation', 'Umplanen ab 100 m · Ende ab 500 m'), findsOneWidget,
        reason: 'Vorgaben von #464');
    // Mit der Zeile „Navigation" (0.157.0) liegt das Erscheinungsbild unter
    // dem Rand der faulen Liste.
    await scrollTo(tester, find.byKey(const ValueKey('profile-appearance')));
    expect(value('appearance', 'Dunkel'), findsOneWidget);
    // Mit der Zeile „Fahrerprofil" (0.70.0) liegt das Konto unter dem Rand
    // der faulen Liste — erst hinscrollen, sonst ist die Zeile nicht gebaut.
    await scrollTo(tester, find.byKey(const ValueKey('profile-account')));
    expect(value('account', 'Name, E-Mail, Passwort, Geräte'), findsOneWidget);
    // Konto löschen liegt nicht mehr auf der ersten Seite.
    expect(find.text('Konto löschen'), findsNothing);

    await openProfilePage(tester, 'account');
    expect(find.text('Benutzername ändern'), findsOneWidget);
    expect(find.text('testrail'), findsOneWidget);
    await scrollTo(tester, find.text('Konto löschen'));
    expect(find.text('Konto löschen'), findsOneWidget);
  });
}
