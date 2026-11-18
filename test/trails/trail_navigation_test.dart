// Die Übergabe an die Navi-App (#151), pur: der URI mit der Koordinate
// ZWEIMAL, die Beschriftung ohne Klammern und gekürzt, der Rückfall in
// die Zwischenablage. Die Breiten sind einstellig: Der Private-Info-
// Wächter hält zweistellige Paare mit vielen Nachkommastellen für echte
// Orte, und ein echter Ort gehört nicht ins Repo.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/trail_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('der URI trägt die Koordinate zweimal, mit Titel in Klammern', () {
    expect(
      geoUriFor(lat: 7.12345678, lng: 11.1, label: 'Hexentanz').toString(),
      'geo:7.123457,11.100000?q=7.123457,11.100000(Hexentanz)',
    );
    expect(
      geoUriFor(lat: 7.0, lng: 11.0).toString(),
      'geo:7.000000,11.000000?q=7.000000,11.000000',
    );
  });

  test('Klammern im Namen zerlegen den URI nicht, Überlänge wird gekürzt', () {
    final uri = geoUriFor(lat: 7, lng: 11, label: 'Hang (oben)\n  Variante');
    expect(uri.toString(), endsWith('(Hang%20oben%20Variante)'));
    final long = geoUriFor(lat: 7, lng: 11, label: 'x' * 80).toString();
    expect(long, endsWith('${'x' * kMaxLabelLength}%E2%80%A6)'));
    expect(
      geoUriFor(lat: 7, lng: 11, label: '  ').toString(),
      endsWith('q=7.000000,11.000000'),
    );
  });

  test('formatCoordinates schreibt den Punkt, nie das Komma', () {
    expect(formatCoordinates(7.5, 11.25), '7.500000, 11.250000');
  });

  test('ohne Empfänger landet die Koordinate in der Zwischenablage', () async {
    final clipboard = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    expect(
      await openInNavigationApp(lat: 7, lng: 11, launch: (_) async => true),
      NavigationOutcome.opened,
    );
    expect(clipboard, isEmpty);
    expect(
      await openInNavigationApp(lat: 7, lng: 11, launch: (_) async => false),
      NavigationOutcome.copiedNoApp,
    );
    // Je nach Android-Fassung eine Ausnahme statt `false` — dasselbe.
    expect(
      await openInNavigationApp(
        lat: 7,
        lng: 11,
        launch: (_) async => throw StateError('kein geo'),
      ),
      NavigationOutcome.copiedNoApp,
    );
    expect(clipboard, ['7.000000, 11.000000', '7.000000, 11.000000']);
  });
}
