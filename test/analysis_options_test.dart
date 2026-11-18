// Der Wächter über `analysis_options.yaml`.
//
// **Warum eine Datei mit Regeln einen Test braucht:** Verschwindet dort
// eine Zeile — beim Auflösen eines Merge-Konflikts, beim Umschreiben der
// Kommentare, oder weil jemand einen hartnäckigen Fund loswerden will —
// dann meldet `flutter analyze` weiterhin „No issues found". Der Verlust
// sieht also genau aus wie Erfolg.
//
// Geprüft wird das Vorhandensein, NICHT die Wirkung: Ob eine Regel etwas
// findet, beantwortet `flutter analyze` selbst und besser.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final options = File('analysis_options.yaml').readAsStringSync();

  test('die Grundlage bleibt flutter_lints', () {
    expect(options, contains('include: package:flutter_lints/flutter.yaml'));
  });

  test('use_build_context_synchronously ist ein FEHLER, keine Warnung', () {
    // Die wichtigste Regel des Satzes: „`mounted`/`context.mounted` nach
    // jedem `await` prüfen". Unter flutter_lints allein ist das eine
    // Warnung — und eine Warnung blockiert `flutter analyze` nicht, die
    // Konvention hinge also wieder an der Aufmerksamkeit des Lesers.
    expect(options, contains('use_build_context_synchronously: error'));
  });

  test('die gesetzten Regeln stehen alle noch da', () {
    for (final rule in [
      'strict-casts: true',
      'strict-raw-types: true',
      'avoid_print: error',
      '- unawaited_futures',
      '- prefer_const_constructors',
      '- prefer_final_locals',
    ]) {
      expect(
        options,
        contains(rule),
        reason:
            '$rule fehlt in analysis_options.yaml — eine Regel '
            'verschwindet still, `flutter analyze` bleibt grün',
      );
    }
  });
}
