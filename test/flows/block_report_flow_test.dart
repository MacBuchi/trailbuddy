// Blockieren und Melden (#584, Patch 033) — durch die echte Oberfläche
// gegen den Fake, der die Regeln der Datenbank spiegelt.
//
// Die teuren Fälle: ein Blockierter, der weiter anfragen kann; eine
// Meldung, deren Text der Client erfindet; und eine Sperre, die man nicht
// wieder loswird.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/message_repository.dart';
import 'package:trailbuddy/features/friends/conversation_screen.dart';
import 'package:trailbuddy/features/friends/friends_screen.dart';
import 'package:trailbuddy/models/buddy_message.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeUser me;
  late FakeUser lilli;

  setUp(() {
    backend = FakeBackend();
    me = backend.addUser(username: 'testrail');
    lilli = backend.addUser(username: 'lilli92');
    backend.signInAs(me.id);
  });

  Future<void> openMenu(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.byTooltip('Mehr zu $name'));
    await settle(tester);
    await tester.tap(find.byTooltip('Mehr zu $name'));
    await settle(tester);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Buddy finden'),
      query,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
  }

  testWidgets('Blockieren an der Buddy-Zeile beendet die Verbindung und '
      'sagt, wo man freigibt', (tester) async {
    backend.addFriendship(me.id, lilli.id);
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    await openMenu(tester, 'lilli92');
    await tester.tap(find.text('Blockieren'));
    await settle(tester);
    expect(find.text('lilli92 blockieren?'), findsOneWidget);
    expect(find.textContaining('„Blockierte Nutzer“'), findsOneWidget);
    // Abbrechen: nichts passiert.
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(backend.friendships, hasLength(1));
    expect(backend.blocks, isEmpty);

    await openMenu(tester, 'lilli92');
    await tester.tap(find.text('Blockieren'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Blockieren'));
    await settle(tester, frames: 12);

    expect(backend.friendships, isEmpty);
    expect(backend.blocks.single.blocker, me.id);
    expect(backend.blocks.single.blocked, lilli.id);
    expect(find.text('lilli92 ist blockiert.'), findsOneWidget);
    expect(find.textContaining('Noch keine Buddys verbunden'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Wer blockiert ist, fragt ins Leere — und erfährt es nicht', (
    tester,
  ) async {
    backend.blocks.add((blocker: me.id, blocked: lilli.id, at: DateTime.now()));
    backend.signInAs(lilli.id);
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    await search(tester, 'testrail');
    await tester.tap(find.text('Anfragen'));
    await settle(tester);

    // Dieselbe Leiste wie bei jeder Anfrage — kein Fehler, kein Hinweis.
    expect(find.text('Anfrage an testrail gesendet.'), findsOneWidget);
    expect(backend.friendships, isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('Wer selbst blockiert hat, bekommt beim Anfragen den Weg zum '
      'Freigeben', (tester) async {
    backend.blocks.add((blocker: me.id, blocked: lilli.id, at: DateTime.now()));
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    await search(tester, 'lilli');
    await tester.tap(find.text('Anfragen'));
    await settle(tester);

    expect(find.textContaining('Du hast lilli92 blockiert.'), findsOneWidget);
    expect(backend.friendships, isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('Im Profil steht, wen ich blockiert habe, und Freigeben hebt '
      'die Sperre auf', (tester) async {
    await pumpApp(tester, backend);
    await openTab(tester, 'Profil');
    // Ohne Sperre keine Zeile — sie stünde direkt über „Konto".
    await scrollTo(tester, find.byKey(const ValueKey('profile-account')));
    expect(find.byKey(const ValueKey('profile-blocked')), findsNothing);
    await tester.pumpWidget(const SizedBox());

    backend.blocks.add((blocker: me.id, blocked: lilli.id, at: DateTime.now()));
    // Eine fremde Sperre gehört nicht in meine Liste.
    final other = backend.addUser(username: 'fremd');
    backend.blocks.add((blocker: other.id, blocked: me.id, at: DateTime.now()));
    await pumpApp(tester, backend);
    await openTab(tester, 'Profil');

    final row = find.byKey(const ValueKey('profile-blocked'));
    await scrollTo(tester, row);
    expect(find.text('1 Person'), findsOneWidget);
    await tester.tap(row);
    await settle(tester, frames: 12);

    expect(find.text('lilli92'), findsOneWidget);
    expect(find.text('fremd'), findsNothing);
    await tester.tap(find.text('Freigeben'));
    await settle(tester, frames: 12);

    expect(backend.blocks.where((b) => b.blocker == me.id), isEmpty);
    expect(backend.blocks, hasLength(1), reason: 'die fremde Sperre bleibt');
    expect(find.text('lilli92 ist freigegeben.'), findsOneWidget);
    expect(find.textContaining('Du hast niemanden blockiert'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Eine fremde Anfrage lässt sich melden — erst mit Grund', (
    tester,
  ) async {
    backend.addFriendship(lilli.id, me.id, status: 'pending');
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    await openMenu(tester, 'lilli92');
    await tester.tap(find.text('Melden'));
    await settle(tester);
    expect(find.text('lilli92 melden'), findsOneWidget);
    expect(find.textContaining('nur an den Betreiber'), findsOneWidget);

    final send = find.byKey(const Key('report-send'));
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.tap(find.text('Spam oder Werbung'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('report-note')),
      '  will Geld  ',
    );
    await tester.tap(send);
    await settle(tester, frames: 12);

    final report = backend.contentReports.single;
    expect(report['reporter_id'], me.id);
    expect(report['reported_id'], lilli.id);
    expect(report['kind'], 'user');
    expect(report['reason'], 'spam');
    expect(report['note'], 'will Geld');
    expect(
      find.text('Danke — die Meldung ist beim Betreiber.'),
      findsOneWidget,
    );
    // Ohne „Auch blockieren" bleibt die Anfrage stehen.
    expect(backend.friendships, hasLength(1));
    expect(backend.blocks, isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('Eine fremde Nachricht melden und blockieren schließt den '
      'Verlauf; der Text kommt aus der Nachricht', (tester) async {
    backend.addFriendship(me.id, lilli.id);
    final now = DateTime.now();
    backend.messages.add(
      BuddyMessage(
        id: 'm1',
        senderId: lilli.id,
        recipientId: me.id,
        body: 'du Pfeife',
        createdAt: now,
        expiresAt: now.add(const Duration(days: kMessageDays)),
        readAt: now,
      ),
    );
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');
    await tester.ensureVisible(find.byKey(messageButtonKey(lilli.id)));
    await settle(tester);
    await tester.tap(find.byKey(messageButtonKey(lilli.id)));
    await settle(tester, frames: 12);

    await tester.longPress(find.text('du Pfeife'));
    await settle(tester);
    expect(find.text('Nachricht von lilli92 melden'), findsOneWidget);
    await tester.tap(find.text('Belästigung oder Beleidigung'));
    await tester.tap(find.text('Auch blockieren'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('report-send')));
    await settle(tester, frames: 16);

    final report = backend.contentReports.single;
    expect(report['kind'], 'message');
    expect(report['message_id'], 'm1');
    expect(report['excerpt'], 'du Pfeife');
    expect(report['reason'], 'abuse');
    expect(backend.blocks.single.blocked, lilli.id);
    expect(backend.friendships, isEmpty);
    expect(backend.messages, isEmpty, reason: 'der Verlauf geht mit');
    expect(find.byType(ConversationScreen), findsNothing);
    expect(
      find.text('Danke — gemeldet, und lilli92 ist blockiert.'),
      findsOneWidget,
    );
    await drainSnackbars(tester);
  });
}
