// Bewertung, Meldung und Zustand im Blatt (#101, Rework Abschnitt 9):
// Sterne nur mit eigenem Beleg, melden darf jeder, der den Trail sieht —
// bestätigt nur, wer gefahren oder vor Ort ist; zum Server geht nur das
// Ja/Nein, nie die Position. Seit #433 steht der Zustand an seiner Kachel,
// nicht mehr im Dialog „Melden".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/features/trails/rating_stars.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId;
  late String bobId;
  late String shared;
  late String bobsFlow;

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
    trails.usernames[bob.id] = 'bob';
    // Roots: Bob und Anna sind ihn gefahren, Bob gibt 5 Sterne.
    shared = trails.seedTrail(bob.id, name: 'Roots', rating: 5);
    trails.seedTrail(anna.id, trailId: shared);
    // Bobs Flow (48,1° N): nur Bob ist ihn gefahren.
    bobsFlow = trails.seedTrail(bob.id, name: 'Bobs Flow', lat: 48.1);
  });

  Future<void> openTrail(WidgetTester tester, String name,
      {FakePositionFix? positionFix, FakeOutbox? outbox}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend, trails: trails, positionFix: positionFix, outbox: outbox);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text(name));
    await settle(tester);
  }

  Future<void> openReport(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('trail-report')));
    await tester.tap(find.byKey(const ValueKey('trail-report')));
    await settle(tester);
  }

  Future<void> openCondition(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('metric-condition')));
    await tester.tap(find.byKey(const ValueKey('metric-condition')));
    await settle(tester);
    expect(find.byKey(const ValueKey('condition-sheet')), findsOneWidget);
  }

  testWidgets('Sterne: blass, bis ich bewerte; Median des Netzes, der höhere', (tester) async {
    await openTrail(tester, 'Roots');
    expect(findLabel('Bewertung 5 von 5 Sternen, 1 Stimme'), findsOneWidget);
    final own = find.byKey(const ValueKey('own-rating-4'));
    await tester.ensureVisible(own);
    await tester.tap(own);
    await settle(tester, frames: 20);

    expect(trails.details.singleWhere((d) => d.userId == annaId).rating, 4);
    expect(findLabel('Bewertung 5 von 5 Sternen, 2 Stimmen'), findsOneWidget,
        reason: '4 und 5: bei Gleichstand der höhere');

    // Ein Tipp zeigt, wer was vergeben hat.
    await tester.ensureVisible(find.byKey(const ValueKey('metric-rating')));
    await tester.tap(find.byKey(const ValueKey('metric-rating')));
    await settle(tester);
    expect(find.text('Du'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
  });

  testWidgets('Liste: Sterne in der Zeile, blass beim eigenen unbewerteten Trail', (tester) async {
    await openTrail(tester, 'Roots');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    final stars = find.byKey(const ValueKey('row-rating'));
    expect(stars, findsNWidgets(1), reason: 'nur Roots trägt eine Bewertung, Bobs Flow keine');
    expect(tester.widget<RatingStars>(stars).faded, isTrue,
        reason: 'Bob hat bewertet, ich noch nicht — das IST „Bewertung offen"');
  });

  testWidgets('ein Buddy-Trail, den ich nicht gefahren bin: keine eigenen Sterne', (tester) async {
    await openTrail(tester, 'Bobs Flow');
    expect(find.text('Deine Bewertung'), findsNothing);
    expect(find.byKey(const ValueKey('trail-report')), findsOneWidget,
        reason: 'melden darf, wer den Trail sieht');
  });

  testWidgets('von zu Hause gemeldet: zu bestätigen, verblasst, keine Warnung auf Karte und Liste',
      (tester) async {
    await openTrail(tester, 'Bobs Flow');
    await openReport(tester);
    await tester.tap(find.byKey(const ValueKey('report-status-closed')));
    await settle(tester);
    expect(find.textContaining('Nicht gefahren'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report-submit')));
    await settle(tester, frames: 20);

    final r = trails.reports.single;
    expect(r.userId, annaId);
    expect(r.status, TrailStatus.closed);
    expect(r.confirmed, isFalse);
    expect(find.byKey(const ValueKey('status-chip-unconfirmed')), findsOneWidget);
    expect(find.byKey(const ValueKey('status-chip')), findsNothing);
    expect(find.textContaining('Du · heute · zu bestätigen'), findsOneWidget);

    // Die Liste warnt nur bei einer bestätigten Meldung; die unbestätigte
    // steht gedämpft mit Fragezeichen da.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.textContaining('GESPERRT?'), findsOneWidget);
    expect(find.textContaining(RegExp(r'GESPERRT(?!\?)')), findsNothing);
  });

  testWidgets('vor Ort (≤ 200 m): bestätigt, Zustand in der Kachel, die Position bleibt hier',
      (tester) async {
    // 48,105° N liegt auf Bobs Linie, 0,0005° O sind ~37 m daneben.
    final fix = FakePositionFix(fakePosition(48.105, 9.0005));
    await openTrail(tester, 'Bobs Flow', positionFix: fix);
    expect(find.text('—'), findsWidgets, reason: 'noch kein Zustand');
    await openCondition(tester);
    expect(fix.calls, 0, reason: 'nach der Position wird erst auf Tipp gefragt');
    await tester.ensureVisible(find.byKey(const ValueKey('report-on-site')));
    await tester.tap(find.byKey(const ValueKey('report-on-site')));
    await settle(tester);
    expect(fix.calls, 1);
    expect(find.textContaining('Vor Ort'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report-condition-2')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('condition-submit')));
    await settle(tester, frames: 20);

    final r = trails.reports.single;
    expect(r.kind, ReportKind.condition);
    expect(r.condition, 2);
    expect(r.confirmed, isTrue);
    expect(findLabel('Zustand: Abgerockt, heute'), findsOneWidget);
  });

  testWidgets('zu weit weg: bleibt zu bestätigen und sagt es', (tester) async {
    await openTrail(tester, 'Bobs Flow', positionFix: FakePositionFix(fakePosition(48.2, 9.0)));
    await openReport(tester);
    await tester.tap(find.byKey(const ValueKey('report-status-changed')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('report-on-site')));
    await tester.tap(find.byKey(const ValueKey('report-on-site')));
    await settle(tester);
    expect(find.textContaining('entfernt'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report-submit')));
    await settle(tester, frames: 20);
    expect(trails.reports.single.confirmed, isFalse);
  });

  testWidgets('selbst gefahren: bestätigt ohne Position', (tester) async {
    final fix = FakePositionFix();
    await openTrail(tester, 'Roots', positionFix: fix);
    await openReport(tester);
    await tester.tap(find.byKey(const ValueKey('report-status-destroyed')));
    await settle(tester);
    expect(find.textContaining('Du bist ihn gefahren'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-on-site')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('report-submit')));
    await settle(tester, frames: 20);
    expect(trails.reports.single.confirmed, isTrue);
    expect(fix.calls, 0);
    expect(find.byKey(const ValueKey('status-chip')), findsOneWidget);
  });

  testWidgets('der Verlauf nennt den Buddy und das Alter', (tester) async {
    trails.seedReport(bobId, bobsFlow,
        status: TrailStatus.closed, at: DateTime.now().subtract(const Duration(days: 3)));
    trails.seedReport(bobId, bobsFlow,
        condition: 3, at: DateTime.now().subtract(const Duration(days: 120)));
    await openTrail(tester, 'Bobs Flow');
    expect(find.textContaining('bob · vor 3 Tagen'), findsOneWidget);
    expect(find.textContaining('gemeldet vor 3 Tagen'), findsOneWidget);
    // Älter als 90 Tage, aber der jüngste bestätigte Zustand: steht da.
    expect(findLabel('Zustand: Ausgefahren, vor 4 Monaten'), findsOneWidget);
  });

  testWidgets('ohne Netz: wartet im Korb, mit der Zeit des Meldens', (tester) async {
    final outbox = FakeOutbox();
    trails.failNextReport = const SocketException('offline');
    await openTrail(tester, 'Roots', outbox: outbox);
    await openCondition(tester);
    await tester.tap(find.byKey(const ValueKey('report-condition-4')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('condition-submit')));
    await settle(tester, frames: 20);

    final job = outbox.jobs.single as ReportJob;
    expect(job.trailId, shared);
    expect(job.condition, 4);
    expect(job.onSite, isFalse);
    expect(trails.reports, isEmpty);
    // Der wartende Zustand steht im Blatt des Zustands, mit „wartet".
    await openCondition(tester);
    expect(find.textContaining('wartet auf Übertragung'), findsOneWidget);
  });

  testWidgets('Zustand 1 oder 2: die Rückmeldung bietet an, etwas dazu zu schreiben', (tester) async {
    await openTrail(tester, 'Roots');
    await openCondition(tester);
    await tester.tap(find.byKey(const ValueKey('report-condition-1')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('condition-submit')));
    await settle(tester, frames: 20);
    expect(trails.reports.single.condition, 1);
    await tester.tap(find.text('Dazu schreiben'));
    await settle(tester);
    // „Melden" ohne Status, das Textfeld ist da.
    expect(find.byKey(const ValueKey('report-note')), findsOneWidget);
    for (final s in ['closed', 'destroyed', 'changed', 'open']) {
      expect(tester.widget<ChoiceChip>(find.byKey(ValueKey('report-status-$s'))).selected, isFalse);
    }
  });

  testWidgets('Zustand 3: keine Einladung zum Schreiben', (tester) async {
    await openTrail(tester, 'Roots');
    await openCondition(tester);
    await tester.tap(find.byKey(const ValueKey('report-condition-3')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('condition-submit')));
    await settle(tester, frames: 20);
    expect(find.text('Zustand gemeldet'), findsOneWidget);
    expect(find.text('Dazu schreiben'), findsNothing);
  });
}
