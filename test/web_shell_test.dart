/// Die Web-Hülle: Startdatei, Service Worker, Manifest. Die Fallen sind
/// still (PilzBuddy #387): Ein Platzhalter in einem Kommentar macht die
/// Startdatei zu Syntaxmüll, eine falsche Farbe zwei Antworten auf eine
/// Frage.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
  final sw = File('web/sw.js').readAsStringSync();
  final index = File('web/index.html').readAsStringSync();
  final manifest = File('web/manifest.json').readAsStringSync();

  test('die drei Platzhalter stehen genau einmal und nie in einem Kommentar', () {
    for (final ph in ['{{flutter_js}}', '{{flutter_build_config}}',
        '{{flutter_service_worker_version}}']) {
      final lines = bootstrap.split('\n').where((l) => l.contains(ph)).toList();
      expect(lines, hasLength(1), reason: ph);
      expect(lines.single.trimLeft(), isNot(startsWith('//')), reason: ph);
    }
  });

  test('der Lader registriert UNSEREN Worker, nicht Flutters', () {
    // Nur der CODE zählt — der Kommentar erklärt gerade, warum die Zeile
    // fehlt.
    final code = bootstrap.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    expect(code, isNot(contains('serviceWorkerSettings')));
    expect(bootstrap, contains("register('sw.js?v='"));
    expect(bootstrap, contains("updateViaCache: 'none'"));
  });

  test('der Worker ist netzwerkzuerst und trägt den eigenen Namen', () {
    expect(sw, contains("const CACHE = 'trailbuddy-' + VERSION"));
    expect(sw, contains('__trailbuddy_cache_complete__'));
    expect(sw, isNot(contains('pilzbuddy')));
    expect(sw, contains('NAVIGATION_TIMEOUT_MS'));
  });

  test('index und Manifest sagen dieselbe Farbe und denselben Namen', () {
    final metaColor = RegExp(r'name="theme-color" content="(#[0-9A-Fa-f]{6})"')
        .firstMatch(index)!
        .group(1);
    final manifestColor = RegExp(r'"theme_color":\s*"(#[0-9A-Fa-f]{6})"')
        .firstMatch(manifest)!
        .group(1);
    expect(metaColor, manifestColor);
    // Der Grund des dunklen Modus — die Leisten der PWA und der Start-
    // bildschirm sollen nicht in der alten Farbe aufblitzen.
    expect(metaColor, '#0E1411');
    expect(manifest, contains('"background_color": "#0E1411"'));
    expect(index, contains('<title>TrailBuddy</title>'));
    expect(manifest, contains('"name": "TrailBuddy"'));
    expect(index, contains('name="viewport"'));
    expect(index, contains('flutter_bootstrap.js'));
  });

  test('die Rechtsseiten liegen neben der App', () {
    for (final f in [
      'datenschutz.html', 'impressum.html', 'konto-loeschen.html',
      'privacy.html', 'imprint.html', 'delete-account.html',
    ]) {
      expect(File('web/$f').existsSync(), isTrue, reason: f);
    }
  });
}
