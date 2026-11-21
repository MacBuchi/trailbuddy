// Texte der Kacheln und Sätze im Ergebnis des Planers (15l9, #516): Zahl
// und Einheit brechen nie auseinander, die Zeit der Kachel ist knapp.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/routing/loop_planner_sheet.dart';

import '../fakes/l10n_de.dart';

void main() {
  test('keepUnits: geschütztes Leerzeichen zwischen Zahl und Einheit', () {
    expect(
      keepUnits('Forstweg 6,9 km · 120 hm · 2 h 30 min · 300 m'),
      'Forstweg 6,9 km · 120 hm · 2 h 30 min · 300 m',
    );
    expect(keepUnits('8 Trails'), '8 Trails', reason: 'keine Einheit');
    expect(keepUnits('3 mal'), '3 mal', reason: 'nur ganze Einheiten');
  });

  test('routeTimeCompact: 1:55 h statt 1 h 55 min, auf 5 min gerundet', () {
    expect(routeTimeCompact(l10nDe, 115 * 60), '1:55 h');
    expect(routeTimeCompact(l10nDe, 64 * 60), '1:05 h');
    expect(routeTimeCompact(l10nDe, 2 * 3600), '2 h');
    expect(routeTimeCompact(l10nDe, 45 * 60), '45 min');
  });
}
