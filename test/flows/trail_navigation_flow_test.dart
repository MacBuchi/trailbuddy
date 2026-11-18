// Der Weg vom Trail-Blatt in die Navi-App (#151), durch die echte
// Oberfläche. Gemockt wird der Kanal von url_launcher, nicht die eigene
// Funktion: So steht in der Erwartung der URI, der das Gerät wirklich
// verlässt (PilzBuddy #367).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/trail_navigation.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late List<String> launched;
  late List<String> clipboard;

  void mockLauncher({required bool handled}) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_launcherChannel, (call) async {
      launched.add((call.arguments as Map)['url'] as String);
      return handled;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  }

  setUp(() {
    launched = [];
    clipboard = [];
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(
      myId: () => backend.currentUserId ?? '',
      areFriends: backend.areFriends,
    );
    // Gegen die Trail-Richtung aufgenommen: Der Trailkopf ist das Ende
    // der gespeicherten Linie (lat + 0.009). Einstellige Breite, weil der
    // Private-Info-Wächter zweistellige Paare mit sechs Nachkommastellen
    // für echte Orte hält.
    trails.seedTrail(
      anna.id,
      name: 'Hexentanz (Nord)',
      grade: 2,
      reversed: true,
      lat: 7.0,
    );
    trails.seedTrail(anna.id, lat: 8.5);
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_launcherChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> openSheet(WidgetTester tester, String name) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text(name));
    await settle(tester);
  }

  Future<void> tapNavigate(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('trail-navigate'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settle(tester);
  }

  testWidgets('„Anfahrt" übergibt den Trailkopf in Trail-Richtung samt Namen', (
    tester,
  ) async {
    await openSheet(tester, 'Hexentanz (Nord)');
    mockLauncher(handled: true);
    await tapNavigate(tester);
    expect(launched, [
      'geo:7.009000,9.000000?q=7.009000,9.000000(Hexentanz%20Nord)',
    ]);
    expect(clipboard, isEmpty);
    // Der App-Wähler steht im Vordergrund — eine SnackBar dahinter wäre
    // für niemanden.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('ohne Navi-App: Zwischenablage, und die App sagt es', (
    tester,
  ) async {
    await openSheet(tester, 'Hexentanz (Nord)');
    mockLauncher(handled: false);
    await tapNavigate(tester);
    expect(launched, hasLength(1));
    expect(clipboard, ['7.009000, 9.000000']);
    expect(find.textContaining('Keine Navi-App gefunden'), findsOneWidget);
  });

  testWidgets('der Platzhalter „Trail ohne Namen" wird nicht übergeben', (
    tester,
  ) async {
    await openSheet(tester, 'Trail ohne Namen');
    mockLauncher(handled: true);
    await tapNavigate(tester);
    expect(launched, ['geo:8.500000,9.000000?q=8.500000,9.000000']);
    expect(kGeoScheme, 'geo');
  });
}
