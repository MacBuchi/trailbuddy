// Meldungen für Buddys (Issue #7, seit #433 ein Eintrag aus Status, Text
// und Foto): „Baum liegt quer". Schreiben darf, wer den Trail sieht;
// sehen die direkten Buddys, die ihn auch sehen; den Text entfernen, wer
// ihn sieht („erledigt"). Ein neuer Text eines Buddys hebt den Trail in
// der Liste hervor, bis man ihn im Blatt gesehen hat.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId, bobId, carlaId;
  late String roots, bobsFlow;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    final carla = backend.addUser(username: 'carla');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    annaId = anna.id;
    bobId = bob.id;
    carlaId = carla.id;
    trails = FakeTrailRepository(
        myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames[bob.id] = 'bob';
    trails.usernames[carla.id] = 'carla';
    roots = trails.seedTrail(bob.id, name: 'Roots');
    trails.seedTrail(anna.id, trailId: roots);
    bobsFlow = trails.seedTrail(bob.id, name: 'Bobs Flow', lat: 48.1);
  });

  Future<void> openList(WidgetTester tester) async {
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
  }

  Future<void> openTrail(WidgetTester tester, String name) async {
    await openList(tester);
    await tester.tap(find.text(name));
    await settle(tester);
  }

  /// „Melden" unten im Blatt, wahlweise mit Status und Text.
  Future<void> report(WidgetTester tester, {String? status, String? text}) async {
    await tester.ensureVisible(find.byKey(const ValueKey('trail-report')));
    await tester.tap(find.byKey(const ValueKey('trail-report')));
    await settle(tester);
    if (status != null) {
      await tester.tap(find.byKey(ValueKey('report-status-$status')));
      await settle(tester);
    }
    if (text != null) {
      await tester.enterText(find.byKey(const ValueKey('report-note')), text);
      await settle(tester);
    }
    await tester.tap(find.byKey(const ValueKey('report-submit')));
    await settle(tester, frames: 20);
  }

  testWidgets('neuer Hinweis eines Buddys: hervorgehoben, bis man ihn gesehen hat',
      (tester) async {
    trails.seedNote(bobId, bobsFlow, 'Baum liegt quer nach der zweiten Kehre',
        at: DateTime.now().subtract(const Duration(days: 1)));
    trails.seedNote(bobId, roots, 'Alter Hinweis',
        at: DateTime.now().subtract(const Duration(days: 30)));
    final settings = FakeSettings();
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);

    // Seit 0.38.0 (Design 1j) das Wort in Versalien und ein gelber
    // Rahmen um die Karte statt Symbol und getönter Zeile.
    expect(find.textContaining('NEUE MELDUNG'), findsOneWidget,
        reason: 'nur Bobs Flow — der Hinweis zu Roots ist älter als 7 Tage');
    Card card(String name) =>
        tester.widget<Card>(find.ancestor(of: find.text(name), matching: find.byType(Card)));
    expect((card('Bobs Flow').shape! as RoundedRectangleBorder).side.color,
        AppColors.light.map.note);
    expect((card('Roots').shape! as RoundedRectangleBorder).side.color,
        isNot(AppColors.light.map.note));
    // Und der Rand atmet (Design 1t) — nur um die Karte mit dem Hinweis.
    final glow = find.byKey(const ValueKey('breathing-glow'));
    expect(glow, findsOneWidget);
    expect(find.descendant(of: glow, matching: find.text('Bobs Flow')), findsOneWidget);

    await tester.tap(find.text('Bobs Flow'));
    await settle(tester);
    expect(find.text('Baum liegt quer nach der zweiten Kehre'), findsOneWidget);
    expect(find.text('bob · gestern'), findsOneWidget);
    expect(find.byTooltip('Text löschen'), findsNothing);
    expect(find.byTooltip('Erledigt — Text entfernen'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect(find.textContaining('NEUE MELDUNG'), findsNothing,
        reason: 'im Blatt gesehen — nicht mehr hervorgehoben');
    expect(glow, findsNothing, reason: 'nur solange ungesehen');
    expect(settings.seenNoteIds, hasLength(1));

    // Und nach einem Neustart auch nicht.
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    expect(find.text('Bobs Flow'), findsOneWidget);
    expect(find.textContaining('NEUE MELDUNG'), findsNothing);
  });

  testWidgets('wer den Trail nur über einen Buddy sieht, darf schreiben und erledigen',
      (tester) async {
    trails.seedNote(bobId, bobsFlow, 'Baum liegt quer');
    await openTrail(tester, 'Bobs Flow');

    await report(tester, text: 'Umfahrung links');
    expect(trails.notes.where((n) => n.userId == annaId).single.trailId, bobsFlow);

    await tester.ensureVisible(find.byTooltip('Erledigt — Text entfernen'));
    await tester.tap(find.byTooltip('Erledigt — Text entfernen'));
    await settle(tester);
    expect(find.textContaining('auch für bob'), findsOneWidget);
    await tester.tap(find.text('Entfernen'));
    await settle(tester, frames: 20);
    expect(trails.notes.map((n) => n.body), ['Umfahrung links']);
    expect(find.text('Baum liegt quer'), findsNothing);
  });

  testWidgets('Text allein melden und wieder löschen', (tester) async {
    await openTrail(tester, 'Roots');
    expect(find.textContaining('Noch keine.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('trail-report')));
    await tester.tap(find.byKey(const ValueKey('trail-report')));
    await settle(tester);
    expect(find.text('Deine Buddys sehen Text und Foto, 90 Tage lang.'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-confirmation')), findsNothing,
        reason: 'Text allein gibt es nichts zu bestätigen');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('report-submit'))).onPressed, isNull,
        reason: 'weder Status noch Text');
    await tester.enterText(find.byKey(const ValueKey('report-note')), '  Neuer Drop am Ende ');
    await settle(tester);
    // Feldbericht 2026-10-02 (Hänger beim Hinweis schreiben): nachgelesen
    // werden die Hinweise, nicht jede Linie des Netzes.
    final fetches = trails.recordingFetches;
    await tester.tap(find.byKey(const ValueKey('report-submit')));
    await settle(tester, frames: 20);
    expect(trails.recordingFetches, fetches, reason: 'ein Text ändert keine Linie');
    expect(trails.reports, isEmpty, reason: 'ohne Status keine Meldung');

    final note = trails.notes.single;
    expect(note.userId, annaId);
    expect(note.trailId, roots);
    expect(note.body, 'Neuer Drop am Ende');
    expect(note.reportId, isNull);
    expect(find.text('Neuer Drop am Ende'), findsOneWidget);
    expect(find.text('Du · heute'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Text löschen'));
    await tester.tap(find.byTooltip('Text löschen'));
    await settle(tester);
    // Im Dialog — „Löschen" steht seit 0.46.0 auch im Blatt (Beitrag).
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Löschen')));
    await settle(tester, frames: 20);
    expect(trails.notes, isEmpty);
    expect(find.text('Neuer Drop am Ende'), findsNothing);
  });

  testWidgets('Hinweise von Nicht-Buddys und zu privaten Beiträgen bleiben unsichtbar',
      (tester) async {
    trails.seedTrail(carlaId, trailId: roots);
    trails.seedNote(carlaId, roots, 'Carlas Hinweis');
    trails.seedNote(bobId, roots, 'Bobs Hinweis');
    trails.seedNote(bobId, bobsFlow, 'Bobs Hinweis zum Flow');
    // Bob hat seinen Beitrag zu Roots auf privat gestellt: Anna sieht den
    // Trail weiter (sie hat ihn selbst belegt), Bobs Hinweis dazu nicht.
    final i = trails.details.indexWhere((d) => d.userId == bobId && d.trailId == roots);
    trails.details[i] = trails.details[i].copyWith(visibility: TrailVisibility.private);

    // Mit Bobs Beitrag ist auch sein Name weg.
    await openTrail(tester, 'Trail ohne Namen');
    expect(find.text('Bobs Hinweis'), findsNothing);
    expect(find.text('Carlas Hinweis'), findsNothing);
    expect(find.textContaining('Noch keine.'), findsOneWidget);

    // Gegenprobe: Bobs geteilter Trail zeigt seinen Hinweis.
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await tester.tap(find.text('Bobs Flow'));
    await settle(tester);
    expect(find.text('Bobs Hinweis zum Flow'), findsOneWidget);
  });

  testWidgets('Status und Text: ein Aufruf, eine Zeile im Blatt', (tester) async {
    await openTrail(tester, 'Roots');
    await tester.ensureVisible(find.byKey(const ValueKey('trail-report')));
    await tester.tap(find.byKey(const ValueKey('trail-report')));
    await settle(tester);
    expect(find.byKey(const ValueKey('report-condition-3')), findsNothing,
        reason: 'der Zustand steht an seiner Kachel, nicht im Dialog');
    await tester.tap(find.byKey(const ValueKey('report-status-closed')));
    await settle(tester);
    expect(find.text('Deine Buddys sehen die Meldung; Text und Foto 90 Tage lang.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('report-note')), 'Forst sperrt bis Oktober');
    final fetches = trails.recordingFetches;
    final calls = trails.reportCalls;
    await tester.tap(find.byKey(const ValueKey('report-submit')));
    await settle(tester, frames: 20);
    // Feldbericht 2026-10-02 (Hänger beim Melden): nachgelesen werden
    // Meldungen und Texte, nicht jede Linie des Netzes.
    expect(trails.recordingFetches, fetches, reason: 'eine Meldung ändert keine Linie');
    expect(trails.reportCalls, calls + 1, reason: 'Meldung und Text in EINEM Aufruf');

    final r = trails.reports.singleWhere((r) => r.userId == annaId && r.trailId == roots);
    expect(r.status, TrailStatus.closed);
    expect(r.confirmed, isTrue, reason: 'Anna hat Roots selbst belegt');
    final note = trails.notes.single;
    expect(note.body, 'Forst sperrt bis Oktober');
    expect(note.reportId, r.id, reason: 'der Text gehört zu seiner Meldung');
    // EINE Zeile: Statuswort und Text im selben Eintrag.
    final row = find.byKey(ValueKey('note-${note.id}'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Gesperrt')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Forst sperrt bis Oktober')), findsOneWidget);
    expect(find.byKey(ValueKey('report-${r.id}')), findsNothing, reason: 'keine zweite Zeile');
  });

  testWidgets('erledigt neben einer Sperre: fragt nach „wieder offen"', (tester) async {
    final closed = trails.seedReport(bobId, bobsFlow, status: TrailStatus.closed);
    trails.seedNote(bobId, bobsFlow, 'Baum liegt quer', reportId: closed);
    final other = trails.seedReport(bobId, roots, status: TrailStatus.closed);
    trails.seedNote(bobId, roots, 'Forstarbeiten', reportId: other);
    await openTrail(tester, 'Bobs Flow');

    // Nein: nur der Text geht, die Sperre bleibt.
    await tester.ensureVisible(find.byTooltip('Erledigt — Text entfernen'));
    await tester.tap(find.byTooltip('Erledigt — Text entfernen'));
    await settle(tester);
    expect(find.textContaining('Ist der Trail wieder offen?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resolve-text-only')));
    await settle(tester, frames: 20);
    expect(trails.notes.where((n) => n.trailId == bobsFlow), isEmpty);
    expect(trails.reports.where((r) => r.trailId == bobsFlow).map((r) => r.status), [TrailStatus.closed]);
    expect(find.text('Gesperrt'), findsOneWidget, reason: 'die Meldung steht ohne Text da');

    // Ja: Text weg UND „wieder offen" gemeldet. Anna hat Roots belegt,
    // also bestätigt — die Warnung ist weg.
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await tester.tap(find.text('Roots'));
    await settle(tester);
    await tester.ensureVisible(find.byTooltip('Erledigt — Text entfernen'));
    await tester.tap(find.byTooltip('Erledigt — Text entfernen'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('resolve-reopen')));
    await settle(tester, frames: 20);
    expect(trails.notes.where((n) => n.trailId == roots), isEmpty);
    final open = trails.reports.singleWhere((r) => r.userId == annaId && r.trailId == roots);
    expect(open.status, TrailStatus.open);
    expect(open.confirmed, isTrue);
    expect(find.text('Text entfernt, als wieder offen gemeldet'), findsOneWidget);
  });

  testWidgets('erledigt ohne Warnung: keine Rückfrage nach „wieder offen"', (tester) async {
    trails.seedNote(bobId, bobsFlow, 'Neuer Drop');
    await openTrail(tester, 'Bobs Flow');
    await tester.ensureVisible(find.byTooltip('Erledigt — Text entfernen'));
    await tester.tap(find.byTooltip('Erledigt — Text entfernen'));
    await settle(tester);
    expect(find.textContaining('wieder offen'), findsNothing);
    expect(find.byKey(const ValueKey('resolve-confirm')), findsOneWidget);
  });

  testWidgets('Text allein geht ohne Netz in den Ausgangskorb', (tester) async {
    await openTrail(tester, 'Roots');
    trails.failNextReport = const SocketException('offline');
    await report(tester, text: 'Kehre ausgewaschen');
    expect(trails.notes, isEmpty, reason: 'noch nicht beim Server');
    expect(find.text('Kehre ausgewaschen'), findsOneWidget, reason: 'wartend im Blatt');
    expect(find.textContaining('wartet auf Übertragung'), findsOneWidget);
  });
}
