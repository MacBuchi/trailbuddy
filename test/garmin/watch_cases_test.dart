// Die Fälle von #500 und #501 stehen an einer Stelle: docs/watch_cases.json.
// Dieser Test prüft, dass jeder Fall wirklich geprüft ist — auf der Uhr
// (Monkey-C-Unit-Test), im Simulator-Szenario (tool/garmin_scenario.sh) oder
// am Handy (Fake-Uhr in test/). Ein Fall ohne Prüfung macht die Tests rot,
// damit die Abdeckung nicht leise kleiner wird.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alle Fälle von #500 und #501 haben eine Prüfung', () async {
    final doc = jsonDecode(File('docs/watch_cases.json').readAsStringSync()) as Map<String, dynamic>;
    final faelle = (doc['faelle'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(faelle, isNotEmpty, reason: 'die Falldatei ist leer');

    final mc = File('garmin/source/Tests.mc').readAsStringSync();
    final uhrCode = File('garmin/source/TrailBuddyApp.mc').readAsStringSync() +
        File('garmin/source/NavTracker.mc').readAsStringSync();
    final script = File('tool/garmin_scenario.sh').readAsStringSync();

    final dartSrc = <String>[];
    await for (final e in Directory('test').list(recursive: true)) {
      if (e is File) dartSrc.add(e.readAsStringSync());
    }

    final ids = faelle.map((f) => f['id'] as String).toList();
    expect(ids.toSet().length, ids.length, reason: 'eine Fallkennung zweimal');

    for (final f in faelle) {
      final id = f['id'] as String;
      expect(f['erwartung'], isA<String>(), reason: '$id ohne Erwartung');
      final uhr = f['uhr'] as String?;
      final handy = f['handy'] as String?;
      final szen = (f['szenario'] as List<dynamic>?)?.cast<String>();
      expect(uhr != null || handy != null || (szen != null && szen.isNotEmpty), isTrue,
          reason: '$id hat keine Prüfung');
      if (uhr != null) {
        expect(mc, contains('function $uhr('), reason: '$id: der Unit-Test der Uhr fehlt');
      }
      if (handy != null) {
        expect(dartSrc.any((s) => s.contains(handy)), isTrue, reason: '$id: kein Test am Handy');
      }
      for (final s in szen ?? const <String>[]) {
        expect(script, contains(s), reason: '$id: das Szenario prüft es nicht');
      }
      for (final k in (f['konstant'] as List<dynamic>?)?.cast<String>() ?? const <String>[]) {
        expect(uhrCode, contains(k), reason: '$id: die Konstante $k steht nicht in der Uhr');
      }
    }
  });
}
