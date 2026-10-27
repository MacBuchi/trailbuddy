// „Passwort vergessen" — vom Anfordern des Codes bis zum neuen Passwort,
// komplette App gegen das In-Memory-Backend (siehe test/fakes/).
//
// Der Reset läuft absichtlich über den Zahlencode aus der Mail und nicht
// über deren Link: Der Link ist an das Gerät gebunden, das ihn angefordert
// hat (PKCE-Verifier im lokalen Speicher), und stirbt daher, wenn die Mail
// woanders geöffnet wird. Siehe AuthRepository.sendPasswordResetCode.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trailbuddy/core/errors.dart';
import 'package:trailbuddy/core/widgets/form_notice.dart';
import 'package:trailbuddy/features/map/map_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

/// Erst ins Bild holen, dann tippen: Der Reset-Modus zeigt vier Felder und
/// einen Hinweis, damit rutscht der Knopf im kleinen Test-Viewport unter den
/// sichtbaren Rand — ein Tap daneben warnt nur, statt zu scheitern, und der
/// Test liefe stumm ins Leere.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

/// Bringt den Login-Screen in den Code-Modus: E-Mail eintragen, Code
/// anfordern. Die Vorbedingung der meisten Tests hier.
Future<void> _requestCode(WidgetTester tester, String email) async {
  await _tap(tester, find.text('Passwort vergessen?'));
  await tester.enterText(find.widgetWithText(TextField, 'E-Mail'), email);
  await _tap(tester, find.text('Code anfordern'));
}

void main() {
  testWidgets('Passwort vergessen fragt nur die E-Mail ab', (tester) async {
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);

    await _tap(tester, find.text('Passwort vergessen?'));

    expect(find.byType(TextField), findsOneWidget,
        reason: 'Im Reset-Modus gibt es kein Passwortfeld — nur die E-Mail. '
            'Sonst tippt man dort das vergessene Passwort ein.');
    expect(find.text('Code anfordern'), findsOneWidget);
  });

  testWidgets('Unbekannte Adresse verrät nicht, dass es kein Konto gibt',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);

    await _requestCode(tester, 'gibtesnicht@example.org');

    // Dieselbe Meldung wie im Erfolgsfall, und die Anfrage ist trotzdem
    // vermerkt: Wer hier unterscheidet, baut ein Konto-Orakel.
    expect(
        find.textContaining('Wenn es zu gibtesnicht@example.org ein Konto gibt'),
        findsOneWidget);
    expect(backend.passwordResets, ['gibtesnicht@example.org']);
    expect(find.widgetWithText(TextField, 'Code aus der Mail'), findsOneWidget);
  });

  testWidgets('Falscher Code lässt niemanden in die App', (tester) async {
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testrail@example.org');

    await tester.enterText(
        find.widgetWithText(TextField, 'Code aus der Mail'), '000000');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
        'NeuerTrail#2026!');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
        'NeuerTrail#2026!');
    await _tap(tester, find.text('Neues Passwort speichern'));

    expect(find.textContaining('Code ist falsch oder abgelaufen'),
        findsOneWidget);
    expect(find.byType(MapScreen), findsNothing,
        reason: 'Ein falscher Code darf die Karte nicht öffnen.');
    expect(backend.currentUserId, isNull);
  });

  testWidgets('Zwei verschiedene Passwörter werden abgefangen',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testrail@example.org');

    await tester.enterText(find.widgetWithText(TextField, 'Code aus der Mail'),
        FakeBackend.resetCode);
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
        'NeuerTrail#2026!');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
        'Tippfehler#2026!');
    await _tap(tester, find.text('Neues Passwort speichern'));

    expect(find.textContaining('stimmen nicht überein'), findsOneWidget);
    expect(backend.currentUserId, isNull,
        reason: 'Der Code wurde gar nicht erst eingelöst.');
  });

  testWidgets('Zu kurzes Passwort wird abgefangen', (tester) async {
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testrail@example.org');

    await tester.enterText(find.widgetWithText(TextField, 'Code aus der Mail'),
        FakeBackend.resetCode);
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
        'kurz');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort wiederholen'), 'kurz');
    await _tap(tester, find.text('Neues Passwort speichern'));

    expect(find.textContaining('mindestens'), findsOneWidget);
    expect(backend.currentUserId, isNull);
  });

  testWidgets('Richtiger Code setzt das Passwort und führt in die App',
      (tester) async {
    final backend = FakeBackend()
      ..addUser(username: 'testrail', password: 'AlterTrail#2026!');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testrail@example.org');

    await tester.enterText(find.widgetWithText(TextField, 'Code aus der Mail'),
        FakeBackend.resetCode);
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
        'NeuerTrail#2026!');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
        'NeuerTrail#2026!');
    await _tap(tester, find.text('Neues Passwort speichern'));

    expect(find.byType(MapScreen), findsOneWidget,
        reason: 'Nach dem Ändern öffnet das userUpdated-Ereignis die App.');
    expect(backend.currentUserId, isNotNull);
    // Der Effekt, nicht nur der Aufruf: das Passwort ist wirklich neu.
    expect(backend.users.single.password, 'NeuerTrail#2026!');
  });

  testWidgets('Eine Recovery-Sitzung allein öffnet die App nicht',
      (tester) async {
    final backend = FakeBackend();
    final user = backend.addUser(username: 'testrail');
    await pumpApp(tester, backend);

    // Genau der Zustand direkt nach dem Einlösen des Codes: gültige
    // Sitzung, aber das neue Passwort ist noch nicht gesetzt. Reagierte
    // der Router darauf, läge die Karte mitten im Reset offen — und die
    // Nutzerin wäre angemeldet, ohne ihr Passwort zu kennen. Ohne den
    // Filter in lib/core/router.dart wird dieser Test rot.
    backend.setCurrentUser(user, AuthChangeEvent.passwordRecovery);
    await settle(tester);

    expect(find.byType(MapScreen), findsNothing);
    expect(find.text('Anmelden'), findsOneWidget,
        reason: 'Erst das geänderte Passwort (userUpdated) darf hereinlassen.');
  });

  testWidgets('Zurück zur Anmeldung stellt das Passwortfeld wieder her',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);

    await _tap(tester, find.text('Passwort vergessen?'));
    await _tap(tester, find.text('Zurück zur Anmeldung'));

    expect(find.widgetWithText(TextField, 'Passwort'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.text('Passwort vergessen?'), findsOneWidget);
  });

  // #399: Chrome lädt einen Tab im Hintergrund neu („Memory Saver"),
  // während man im Postfach den Code holt. Ein Neuladen ruft kein
  // `dispose` — nachgestellt mit dem Merker in frischen Einstellungen.
  testWidgets('Nach einem Neuladen steht die Code-Eingabe wieder da',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testrail');
    final before = FakeSettings();
    await pumpApp(tester, backend, settings: before);
    await _requestCode(tester, 'testrail@example.org');
    final remembered = before.pendingAuthCode;
    expect(remembered, isNotNull);
    expect(remembered, isNot(contains('Passwort')),
        reason: 'Gemerkt wird die Adresse, nie ein Passwort.');

    await tester.pumpWidget(const SizedBox());
    final after = FakeSettings(pendingAuthCode: remembered);
    await pumpApp(tester, backend, settings: after);

    expect(find.widgetWithText(TextField, 'Code aus der Mail'), findsOneWidget);
    expect(find.textContaining('testrail@example.org'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, 'Code aus der Mail'),
        FakeBackend.resetCode);
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
        'NeuerTrail#2026!');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
        'NeuerTrail#2026!');
    await _tap(tester, find.text('Neues Passwort speichern'));

    expect(find.byType(MapScreen), findsOneWidget,
        reason: 'Der Code aus der Zeit vor dem Neuladen gilt weiter.');
    expect(after.pendingAuthCode, isNull,
        reason: 'Angemeldet wartet niemand mehr auf einen Code.');
  });

  testWidgets('Zurück zur Anmeldung vergisst den wartenden Code',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testrail');
    final settings = FakeSettings();
    await pumpApp(tester, backend, settings: settings);
    await _requestCode(tester, 'testrail@example.org');
    expect(settings.pendingAuthCode, isNotNull);

    await _tap(tester, find.text('Zurück zur Anmeldung'));

    expect(settings.pendingAuthCode, isNull);
  });

  testWidgets('Ein bekannt unsicheres Passwort wird abgelehnt',
      (tester) async {
    // „zu kurz" wäre hier die falsche Erklärung, das Passwort ist lang
    // genug — der Server lehnt es als bekannt ab.
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testrail@example.org');

    await tester.enterText(find.widgetWithText(TextField, 'Code aus der Mail'),
        FakeBackend.resetCode);
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
        'passwort123');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
        'passwort123');
    await _tap(tester, find.text('Neues Passwort speichern'));

    expect(find.textContaining('zu unsicher'), findsOneWidget);
    expect(find.byType(MapScreen), findsNothing);
  });

  testWidgets('Der Code lässt sich erneut anfordern', (tester) async {
    // Ohne diesen Knopf ist eine im Spam gelandete Mail eine Sackgasse.
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testrail@example.org');

    // Gerade ist eine Mail rausgegangen — erst läuft die Wartezeit.
    expect(find.textContaining('Erneut senden in'), findsOneWidget);
    await passResendCooldown(tester);

    await _tap(tester, find.text('Code nicht angekommen? Erneut senden'));

    expect(backend.passwordResets,
        ['testrail@example.org', 'testrail@example.org']);
    expect(find.textContaining('ein neuer Code'), findsOneWidget);
  });

  testWidgets('Auch das erneute Anfordern verrät kein Konto', (tester) async {
    // Dieselbe Meldung wie bei einer bekannten Adresse — sonst wäre der
    // zweite Tap das Orakel, das der erste vermeidet.
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'gibtesnicht@example.org');
    await passResendCooldown(tester);

    await _tap(tester, find.text('Code nicht angekommen? Erneut senden'));

    expect(
        find.textContaining('Wenn es zu gibtesnicht@example.org ein Konto gibt'),
        findsOneWidget);
    expect(backend.passwordResets.length, 2);
  });

  testWidgets('Ohne Adresse behauptet das Erneut-Senden keine Mail',
      (tester) async {
    // Das E-Mail-Feld steht auch im Code-Modus da und lässt sich leeren.
    // Ohne Prüfung fragte der zweite Weg trotzdem an, GoTrue antwortete
    // „Password recovery requires an email" (400), und die App meldete
    // unbeirrt „ein neuer Code ist unterwegs".
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testrail@example.org');
    await passResendCooldown(tester);

    await tester.enterText(find.widgetWithText(TextField, 'E-Mail'), '');
    await _tap(tester, find.text('Code nicht angekommen? Erneut senden'));

    expect(find.textContaining('gültige E-Mail-Adresse'), findsOneWidget);
    expect(find.textContaining('ein neuer Code'), findsNothing);
    expect(tester.widget<FormNotice>(find.byType(FormNotice)).tone,
        NoticeTone.error);
    expect(backend.passwordResets, ['testrail@example.org'],
        reason: 'Es darf keine zweite Anfrage rausgegangen sein.');
  });

  testWidgets('Ein abgelehnter Mailversand landet nicht im Fehlerbericht',
      (tester) async {
    // Das Mail-Limit ist die vorgesehene Antwort auf zu häufiges Fragen —
    // ein normaler Vorgang, der den Wochendigest anführt, verstopft ihn
    // für die echten Funde.
    final reported = <String>[];
    setErrorSink((context, _, _) => reported.add(context));
    addTearDown(() => setErrorSink(null));

    final backend = FakeBackend()
      ..addUser(username: 'testrail')
      ..passwordResetMailLimit = 0;
    await pumpApp(tester, backend);

    await _requestCode(tester, 'testrail@example.org');

    expect(reported, isEmpty);
    // Nach außen bleibt es bei der einen Auskunft: Eine sichtbare
    // Ablehnung wäre wieder ein Konto-Orakel.
    expect(
        find.textContaining('Wenn es zu testrail@example.org ein Konto gibt'),
        findsOneWidget);
  });

  testWidgets('Ein 504 aus dem Reset landet nicht im Fehlerbericht',
      (tester) async {
    // Ein 504 heißt, das Gateway hat nicht geantwortet — `looksOffline`
    // führt das überall sonst als fehlenden Empfang. Ein `logError` mit
    // eigenem Kontext meldet ALLES, der Pfad muss also selbst filtern.
    final reported = <String>[];
    setErrorSink((context, _, _) => reported.add(context));
    addTearDown(() => setErrorSink(null));

    final backend = FakeBackend()
      ..addUser(username: 'testrail')
      ..passwordResetTimesOut = true;
    await pumpApp(tester, backend);

    await _requestCode(tester, 'testrail@example.org');

    expect(reported, isEmpty);
    // Und nach außen bleibt es bei derselben einen Auskunft — eine
    // sichtbare Fehlermeldung wäre wieder ein Konto-Orakel.
    expect(
        find.textContaining('Wenn es zu testrail@example.org ein Konto gibt'),
        findsOneWidget);
  });

  testWidgets('Ein echter Auth-Fehler landet sehr wohl im Bericht',
      (tester) async {
    // Die Gegenrichtung. Ohne sie wäre der Filter auch dann grün, wenn
    // er alles schluckte — und dann sähe niemand mehr, wenn der Reset
    // wirklich kaputt ist.
    final reported = <String>[];
    setErrorSink((context, _, _) => reported.add(context));
    addTearDown(() => setErrorSink(null));

    final backend = FakeBackend()
      ..addUser(username: 'testrail')
      ..passwordResetFails = true;
    await pumpApp(tester, backend);

    await _requestCode(tester, 'testrail@example.org');

    expect(reported, contains('Passwort-Reset anfordern'));
  });

  group('Transparenz im Formular', () {
    testWidgets('Das Auge macht das Passwort sichtbar', (tester) async {
      final backend = FakeBackend()..addUser(username: 'testrail');
      await pumpApp(tester, backend);

      final field = find.widgetWithText(TextField, 'Passwort');
      expect(tester.widget<TextField>(field).obscureText, isTrue);

      await _tap(
          tester,
          find.descendant(
              of: field, matching: find.byIcon(Icons.visibility_outlined)));

      expect(tester.widget<TextField>(field).obscureText, isFalse,
          reason: 'Wer sein Passwort nicht sehen kann, tippt es blind falsch.');
    });

    testWidgets('Die Übereinstimmung wird schon beim Tippen angezeigt',
        (tester) async {
      final backend = FakeBackend()..addUser(username: 'testrail');
      await pumpApp(tester, backend);
      await _requestCode(tester, 'testrail@example.org');

      // Solange nichts wiederholt wurde, ist Schweigen richtig.
      expect(find.textContaining('stimmen'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
          'NeuerTrail#2026!');
      await tester.enterText(
          find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
          'NeuerTrail#202');
      await settle(tester);
      expect(find.text('Passwörter stimmen noch nicht überein'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
          'NeuerTrail#2026!');
      await settle(tester);

      expect(find.text('Passwörter stimmen überein'), findsOneWidget,
          reason: 'Ohne Live-Abgleich merkt man den Tippfehler erst beim '
              'Absenden.');
    });
  });
}
