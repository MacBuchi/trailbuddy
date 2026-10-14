// Der Vordergrund-Zuhörer (#34; PilzBuddy #277).
//
// Android zeigt eine `notification`-Nutzlast nur an, solange die App
// NICHT vorne ist — im Vordergrund landet sie ausschließlich in
// `onMessage`. Diese SnackBar ist also die einzige Anzeige, die es dann
// gibt, und was sie verdeckt, sieht niemand.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/push_messaging.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/core/widgets/push_listener.dart';

import 'fakes/fake_settings.dart';

void main() {
  late StreamController<RemoteMessage> incoming;

  setUp(() => incoming = StreamController<RemoteMessage>.broadcast());
  tearDown(() => incoming.close());

  Future<ScaffoldMessengerState> pumpListener(WidgetTester tester) async {
    late ScaffoldMessengerState messenger;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pushMessageListenerProvider.overrideWithValue(() => incoming.stream),
        // Ohne Token gleicht PushListener keine Sprache ab (#209).
        settingsProvider.overrideWithValue(FakeSettings()),
      ],
      child: MaterialApp(
        builder: (context, child) =>
            PushListener(child: child ?? const SizedBox.shrink()),
        home: Builder(builder: (context) {
          messenger = ScaffoldMessenger.of(context);
          return const Scaffold(body: SizedBox.shrink());
        }),
      ),
    ));
    await tester.pump(); // erster Frame — erst danach hängt der Zuhörer
    return messenger;
  }

  RemoteMessage messageWith(String? body, {String? title = 'TrailBuddy'}) =>
      RemoteMessage(
          notification: RemoteNotification(title: title, body: body));

  testWidgets('eine eintreffende Meldung erscheint als SnackBar',
      (tester) async {
    await pumpListener(tester);
    incoming.add(messageWith('Neuer Hinweis von einem Buddy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Neuer Hinweis von einem Buddy'), findsOneWidget);
  });

  testWidgets('sie verdrängt eine stehende Rückmeldung', (tester) async {
    // Der Fall vom Pixel: Der Testknopf zeigt „Testnachricht ist
    // unterwegs.", und weil `showSnackBar` sich hinten anstellt, stand
    // die vier Sekunden lang VOR der Meldung, die sie ankündigte.
    final messenger = await pumpListener(tester);
    messenger.showSnackBar(const SnackBar(
        content: Text('Testnachricht ist unterwegs.'),
        duration: Duration(seconds: 4)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Testnachricht ist unterwegs.'), findsOneWidget);

    incoming.add(messageWith('Test — so sieht eine Benachrichtigung aus.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Test — so sieht eine Benachrichtigung aus.'),
        findsOneWidget);
    expect(find.text('Testnachricht ist unterwegs.'), findsNothing,
        reason: 'die Quittung darf die Meldung nicht überdauern');
  });

  testWidgets('Titel UND Rumpf stehen da', (tester) async {
    // Der Titel trägt die Aussage und der Rumpf nur die Ergänzung.
    // Zeigte die App nur den Rumpf, stünde dort „An 2 Trails" ohne jeden
    // Zusammenhang.
    await pumpListener(tester);
    incoming.add(messageWith('An 2 Trails',
        title: '2 neue Hinweise von deinen Buddys'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('2 neue Hinweise von deinen Buddys'), findsOneWidget);
    expect(find.text('An 2 Trails'), findsOneWidget);
  });

  testWidgets('ohne Titel steht der Rumpf für sich', (tester) async {
    // Ältere oder fremde Nutzlast: kein Titel, aber ein Rumpf. Dann darf
    // nichts wegfallen und nichts leer dastehen.
    await pumpListener(tester);
    incoming.add(messageWith('Ein Buddy meldet einen Trail als gesperrt', title: null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ein Buddy meldet einen Trail als gesperrt'), findsOneWidget);
  });

  testWidgets('ohne Text passiert nichts', (tester) async {
    // Eine reine Daten-Nachricht hat keine `notification` — dann gibt es
    // auch nichts anzuzeigen, und eine leere SnackBar wäre Lärm.
    await pumpListener(tester);
    incoming.add(messageWith(null));
    incoming.add(const RemoteMessage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SnackBar), findsNothing);
  });
}
