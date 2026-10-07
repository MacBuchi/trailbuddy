// Die Glühbirne: Idee oder Fehler an den Betreiber. Der Bot macht daraus
// ein ÖFFENTLICHES Issue (tool/feedback_bot.py) — deshalb zählt hier
// auch, dass der Dialog das vor dem Schreiben sagt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/feedback_repository.dart';
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

Future<void> openFeedback(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Idee oder Fehler melden'));
  await settle(tester);
}

Future<void> writeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await settle(tester);
  await tester.tap(find.text('Senden'));
  await settle(tester);
}

void main() {
  testWidgets('von der Karte: Fehler melden, mit Version, Hinweis auf öffentlich',
      (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
    await pumpApp(tester, backend, appVersion: '0.2.0');

    await tester.tap(find.byTooltip('Idee oder Fehler melden'));
    await settle(tester);
    expect(find.text('Wünsch dir was!'), findsOneWidget);
    expect(find.textContaining('öffentlicher Eintrag auf GitHub'), findsOneWidget);
    expect(find.textContaining('keine Trailnamen'), findsOneWidget);

    await tester.tap(find.text('Fehler'));
    await settle(tester);
    // Unter drei Zeichen ist „Senden" gar nicht erst aktiv.
    await tester.enterText(find.byType(TextField), 'ab');
    await settle(tester);
    expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Senden')).onPressed,
        isNull);

    await tester.enterText(find.byType(TextField), '  Import bleibt hängen  ');
    await settle(tester);
    await tester.tap(find.text('Senden'));
    await settle(tester);

    expect(backend.feedback, hasLength(1));
    final row = backend.feedback.single;
    expect(row['user_id'], backend.currentUserId);
    expect(row['type'], 'bug');
    expect(row['message'], 'Import bleibt hängen');
    expect(row['app_version'], '0.2.0');
    expect(row['client_id'], isA<String>(),
        reason: 'schon der erste Versuch trägt die Kennung (Patch 018)');
    expect(find.textContaining('Danke für die Meldung'), findsOneWidget);
  });

  testWidgets('aus dem Profil: Idee ohne Netz wartet im Ausgangskorb (#218)', (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
    final outbox = FakeOutbox();
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    await pumpApp(tester, backend, outbox: outbox, trails: trails, appVersion: '0.2.0');
    await openProfilePage(tester, 'about');
    // In die Mitte holen: am unteren Rand läge die Zeile unter der
    // Navigationsleiste, und der Tipp träfe die.
    final tile = find.text('Idee oder Fehler melden');
    await tester.scrollUntilVisible(tile, 200);
    await tester.runAsync(() => Scrollable.ensureVisible(tester.element(tile), alignment: 0.5));
    await settle(tester);
    await tester.tap(tile);
    await settle(tester);

    expect(find.text('Wünsch dir was!'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Höhenprofil wäre toll');
    await settle(tester);
    backend.offline = true;
    await tester.tap(find.text('Senden'));
    await settle(tester);

    expect(backend.feedback, isEmpty);
    expect(find.textContaining('Kein Empfang — wird gesendet'), findsOneWidget);
    final job = outbox.jobs.single as FeedbackJob;
    expect(job.type, FeedbackType.feature);
    expect(job.message, 'Höhenprofil wäre toll');
    expect(job.appVersion, '0.2.0', reason: 'die Version beim Schreiben');

    // Netz zurück: Die Wiedervorlage schickt es mit DERSELBEN Kennung, und
    // das Netz wird dafür nicht neu geladen — am Trail ändert sich nichts.
    backend.offline = false;
    final fetches = trails.recordingFetches;
    final r = await tester.runAsync(() => containerOf(tester).read(trailsProvider.notifier).sendOutbox());
    await settle(tester);
    expect(r!.sent, 1);
    expect(outbox.jobs, isEmpty);
    expect(backend.feedback.single['client_id'], job.id);
    expect(backend.feedback.single['message'], 'Höhenprofil wäre toll');
    expect(trails.recordingFetches, fetches, reason: 'ein Wunsch lädt das Netz nicht neu');
  });

  testWidgets('ohne Netz und ohne Korb (Web, volle Platte): der Netzfehler wie bisher',
      (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
    final outbox = FakeOutbox()..failOnAppend = true;
    await pumpApp(tester, backend, outbox: outbox);
    await openFeedback(tester);
    backend.offline = true;
    await writeAndSend(tester, 'Höhenprofil wäre toll');
    expect(backend.feedback, isEmpty);
    expect(outbox.jobs, isEmpty);
    expect(find.textContaining('Keine Verbindung'), findsOneWidget);
  });

  testWidgets('die Glühbirne zeigt Wartendes und Abgelehntes; verwerfen und erneut senden',
      (tester) async {
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    final at = DateTime.now().toUtc();
    final outbox = FakeOutbox()
      ..uid = anna.id
      ..jobs.addAll([
        FeedbackJob(
            id: 'fb-a', createdAt: at, type: FeedbackType.bug, message: 'erster', failure: 'Abgelehnt'),
        FeedbackJob(
            id: 'fb-b', createdAt: at, type: FeedbackType.feature, message: 'zweiter', failure: 'Abgelehnt'),
      ]);
    // Der Start schickt schon — Abgelehntes bleibt dabei liegen.
    await pumpApp(tester, backend, outbox: outbox);
    await settle(tester, frames: 12);
    expect(outbox.jobs, hasLength(2));
    expect(find.textContaining('Entscheiden bei der Glühbirne'), findsOneWidget);

    await openFeedback(tester);
    expect(find.byKey(const ValueKey('feedback-waiting-fb-a')), findsOneWidget);
    expect(find.textContaining('Nicht angenommen: Abgelehnt'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('feedback-discard-fb-a')));
    await settle(tester);
    expect(find.byKey(const ValueKey('feedback-waiting-fb-a')), findsNothing);
    expect(outbox.jobs.map((j) => j.id), ['fb-b']);

    await tester.tap(find.byKey(const ValueKey('feedback-retry-fb-b')));
    await settle(tester, frames: 12);
    expect(outbox.jobs, isEmpty);
    expect(backend.feedback.single['client_id'], 'fb-b');
    expect(find.byKey(const ValueKey('feedback-waiting-fb-b')), findsNothing);
  });

  testWidgets('Abbrechen schickt nichts', (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
    await pumpApp(tester, backend);
    await tester.tap(find.byTooltip('Idee oder Fehler melden'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'nur so');
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(backend.feedback, isEmpty);
    expect(find.text('Wünsch dir was!'), findsNothing);
  });
}
