// Nachrichten zwischen Buddys (#34, Vorlage PilzBuddy #564) — durch die
// echte Oberfläche.
//
// Die teuren Fälle: eine Nachricht an jemanden, der nicht angefragt hat;
// eine vierte vor der Freundschaft; ein Verlauf, der das Entfernen
// überlebt; und ein Text, der beim Scheitern verloren geht.
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
  late FakeUser bert;

  setUp(() {
    backend = FakeBackend();
    me = backend.addUser(username: 'testrail');
    bert = backend.addUser(username: 'bert');
    backend.signInAs(me.id);
  });

  void seedMessage(String from, String to, String body,
      {DateTime? at, bool read = false, Duration? age}) {
    final created = at ?? DateTime.now().subtract(age ?? Duration.zero);
    backend.messages.add(BuddyMessage(
      id: 'seed-${backend.messages.length}',
      senderId: from,
      recipientId: to,
      body: body,
      createdAt: created,
      expiresAt: created.add(const Duration(days: kMessageDays)),
      readAt: read ? created : null,
    ));
  }

  Future<void> openConversation(WidgetTester tester, String otherId) async {
    await openTab(tester, 'Buddys');
    // `ensureVisible` statt `scrollUntilVisible`: Der Reiter hat mehrere
    // Scrollables (das Suchfeld bringt ein eigenes mit).
    await tester.ensureVisible(find.byKey(messageButtonKey(otherId)));
    await settle(tester);
    await tester.tap(find.byKey(messageButtonKey(otherId)));
    await settle(tester, frames: 12);
  }

  Future<void> write(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(kMessageFieldKey), text);
    await tester.tap(find.byKey(kMessageSendKey));
    await settle(tester, frames: 12);
  }

  testWidgets('unter Buddys: schreiben, Text geht hinaus, Feld leert sich',
      (tester) async {
    backend.addFriendship(me.id, bert.id);
    await pumpApp(tester, backend);
    await openConversation(tester, bert.id);

    expect(find.text(kMessagesNote), findsOneWidget);
    expect(find.byKey(kMessageLimitKey), findsNothing,
        reason: 'Buddys haben kein Limit');
    await write(tester, '  Morgen Hangweg?  ');

    final sent = backend.messages.single;
    expect(sent.body, 'Morgen Hangweg?');
    expect(sent.recipientId, bert.id);
    expect(find.text('Morgen Hangweg?'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byKey(kMessageFieldKey)).controller!.text,
        isEmpty);
  });

  testWidgets('der Verlauf liest sich von oben nach unten: neueste unten, '
      'direkt über dem Feld', (tester) async {
    backend.addFriendship(me.id, bert.id);
    seedMessage(bert.id, me.id, 'Erste', age: const Duration(hours: 3));
    seedMessage(me.id, bert.id, 'Zweite', age: const Duration(hours: 2));
    seedMessage(bert.id, me.id, 'Dritte', age: const Duration(hours: 1));
    await pumpApp(tester, backend);
    await openConversation(tester, bert.id);

    final y = [
      for (final t in ['Erste', 'Zweite', 'Dritte'])
        tester.getTopLeft(find.text(t)).dy,
    ];
    expect(y[0], lessThan(y[1]));
    expect(y[1], lessThan(y[2]));
    expect(y[2], lessThan(tester.getTopLeft(find.byKey(kMessageFieldKey)).dy));

    // Auch eine frisch geschriebene landet unten.
    await write(tester, 'Vierte');
    expect(tester.getTopLeft(find.text('Vierte')).dy,
        greaterThan(tester.getTopLeft(find.text('Dritte')).dy));
  });

  testWidgets('Ungelesenes: Punkt am Reiter und am Buddy — Öffnen liest',
      (tester) async {
    backend.addFriendship(me.id, bert.id);
    seedMessage(bert.id, me.id, 'Hangweg ist frei!');
    await pumpApp(tester, backend);

    expect(find.byKey(const Key('buddys-unread-badge')), findsWidgets);
    await openTab(tester, 'Buddys');
    expect(find.byTooltip('1 ungelesen'), findsOneWidget);

    await tester.tap(find.byKey(messageButtonKey(bert.id)));
    await settle(tester, frames: 16);
    expect(find.text('Hangweg ist frei!'), findsOneWidget);
    expect(backend.messages.single.readAt, isNotNull);
    expect(find.byKey(const Key('buddys-unread-badge')), findsNothing);
  });

  testWidgets('bewirkt „gelesen" nichts, fragt der Verlauf nicht endlos '
      'nach', (tester) async {
    // In der Gegenprobe gefunden: Ohne Sperre markierte der Bildschirm
    // bei jeder neuen Liste erneut, und jede Markierung lud die Liste
    // neu. Setzt der Server `read_at` nicht, lief das ohne Ende.
    backend.addFriendship(me.id, bert.id);
    seedMessage(bert.id, me.id, 'hallo');
    backend.markReadIgnored = true;
    await pumpApp(tester, backend);
    await openConversation(tester, bert.id);
    await settle(tester, frames: 30);

    expect(backend.markReadCalls, 1);
  });

  testWidgets('offene Anfrage: drei Nachrichten, dann ist das Feld zu',
      (tester) async {
    backend.addFriendship(me.id, bert.id, status: 'pending');
    await pumpApp(tester, backend);
    await openConversation(tester, bert.id);

    expect(find.text('Noch 3 Nachrichten, bis bert die Anfrage annimmt.'),
        findsOneWidget);
    await write(tester, 'Hallo, ich bin Anna vom Bikepark');
    await write(tester, 'Wir sind letzten Herbst zusammen gefahren');
    expect(find.text('Noch 1 Nachricht, bis bert die Anfrage annimmt.'),
        findsOneWidget);
    await write(tester, 'Nimmst du an?');

    expect(backend.messages, hasLength(3));
    expect(find.textContaining('Deine 3 Nachrichten sind geschrieben'),
        findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(kMessageFieldKey)).enabled,
        isFalse);
    expect(tester.widget<IconButton>(find.byKey(kMessageSendKey)).onPressed,
        isNull);
  });

  testWidgets('Anfrage an mich: erst fragen, dann annehmen', (tester) async {
    backend.addFriendship(bert.id, me.id, status: 'pending');
    seedMessage(bert.id, me.id, 'Hi, ich bin Bert vom Stammtisch');
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    expect(find.text('ANFRAGEN AN DICH · 1'), findsOneWidget);
    expect(find.byKey(messageButtonKey(bert.id)), findsOneWidget);
    await tester.tap(find.byKey(messageButtonKey(bert.id)));
    await settle(tester, frames: 12);
    expect(find.text('Hi, ich bin Bert vom Stammtisch'), findsOneWidget);
    expect(find.text('Noch 3 Nachrichten, bevor du die Anfrage annimmst.'),
        findsOneWidget);
    await write(tester, 'Welcher Stammtisch?');
    expect(backend.messages.last.recipientId, bert.id);
  });

  testWidgets('Buddy entfernen löscht den Verlauf für beide, und der '
      'Dialog sagt es', (tester) async {
    backend.addFriendship(me.id, bert.id);
    // Ungelesen: Der Punkt am Reiter muss mit dem Verlauf verschwinden —
    // sonst zeigte die App nach dem Entfernen eine Liste, die es nicht
    // mehr gibt.
    seedMessage(bert.id, me.id, 'eins');
    seedMessage(me.id, bert.id, 'zwei');
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');
    expect(find.byKey(const Key('buddys-unread-badge')), findsWidgets);

    await tester.tap(find.byTooltip('Buddy entfernen'));
    await settle(tester);
    expect(find.textContaining('eure Nachrichten werden für beide gelöscht'),
        findsOneWidget);
    await tester.tap(find.text('Entfernen'));
    await settle(tester, frames: 12);

    expect(backend.messages, isEmpty);
    expect(find.byKey(messageButtonKey(bert.id)), findsNothing);
    expect(find.byKey(const Key('buddys-unread-badge')), findsNothing);
  });

  testWidgets('ohne Empfang: nicht gesendet, der Text bleibt im Feld',
      (tester) async {
    backend.addFriendship(me.id, bert.id);
    await pumpApp(tester, backend);
    await openConversation(tester, bert.id);

    backend.offline = true;
    await write(tester, 'kommt das an?');
    expect(backend.messages, isEmpty);
    expect(find.textContaining('Nicht gesendet'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byKey(kMessageFieldKey)).controller!.text,
        'kommt das an?');
    await drainSnackbars(tester);
  });

  testWidgets('eigene Nachricht zurücknehmen — fremde nicht', (tester) async {
    backend.addFriendship(me.id, bert.id);
    seedMessage(bert.id, me.id, 'von bert', read: true);
    seedMessage(me.id, bert.id, 'von mir');
    await pumpApp(tester, backend);
    await openConversation(tester, bert.id);

    await tester.longPress(find.text('von bert'));
    await settle(tester);
    expect(find.text('Nachricht zurücknehmen?'), findsNothing);

    await tester.longPress(find.text('von mir'));
    await settle(tester);
    await tester.tap(find.text('Zurücknehmen'));
    await settle(tester, frames: 12);
    expect([for (final m in backend.messages) m.body], ['von bert']);
    expect(find.text('von mir'), findsNothing);
  });

  testWidgets('nach 30 Tagen weg; fremde Verläufe nie zu sehen',
      (tester) async {
    final carl = backend.addUser(username: 'carl');
    backend.addFriendship(me.id, bert.id);
    backend.addFriendship(bert.id, carl.id);
    seedMessage(bert.id, me.id, 'uralt', read: true, age: const Duration(days: 31));
    seedMessage(bert.id, me.id, 'frisch', read: true);
    seedMessage(bert.id, carl.id, 'nur für carl');
    // Ein ZWEITER eigener Verlauf: Den liefert die Datenbank mit aus,
    // und nur die App trennt ihn vom Verlauf mit Bert.
    backend.addFriendship(me.id, carl.id);
    seedMessage(carl.id, me.id, 'von carl an mich', read: true);
    await pumpApp(tester, backend);
    await openConversation(tester, bert.id);

    expect(find.text('frisch'), findsOneWidget);
    expect(find.text('uralt'), findsNothing);
    expect(find.text('nur für carl'), findsNothing);
    expect(find.text('von carl an mich'), findsNothing,
        reason: 'ein anderer Verlauf, nicht dieser');
  });
}
