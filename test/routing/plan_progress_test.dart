// Der Ladebalken des Planers (#356): Der Melder rechnet Abschnitte
// ineinander, meldet monoton, höchstens einmal je Prozent und am Ende 1 —
// und tut nichts, solange niemand zuhört.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/routing/plan_progress.dart';

void main() {
  test('ohne Zuhörer ist jeder Aufruf still', () {
    expect(PlanProgress.active, isFalse);
    PlanProgress.report(0.5);
    expect(PlanProgress.part(0, 0.5, () => 7), 7);
  });

  test('Abschnitte rechnen ineinander, am Ende steht 1', () {
    final got = <double>[];
    PlanProgress.run(got.add, () {
      PlanProgress.part(0, 0.5, () {
        PlanProgress.report(0.5); // 0.25
        PlanProgress.part(0.5, 1, () => PlanProgress.report(0.5)); // 0.375
      });
      PlanProgress.part(0.5, 1, () => PlanProgress.steps(1, 4)); // 0.625
    });
    expect(got, [0.25, 0.375, 0.5, 0.625, 1.0]);
    expect(PlanProgress.active, isFalse, reason: 'nach dem Lauf hört keiner mehr zu');
  });

  test('höchstens einmal je Prozent, nie rückwärts', () {
    final got = <double>[];
    PlanProgress.run(got.add, () {
      for (var i = 0; i <= 1000; i++) {
        PlanProgress.steps(i, 1000);
      }
      PlanProgress.report(0.2);
    });
    expect(got.length, lessThanOrEqualTo(101));
    // Die abschließende 1 kommt immer, auch knapp über dem letzten Stand.
    for (var i = 1; i < got.length - 1; i++) {
      expect(got[i] - got[i - 1], greaterThanOrEqualTo(PlanProgress.step - 1e-9));
    }
    expect(got.last, 1.0);
    expect(got.last, greaterThan(got[got.length - 2]));
  });

  test('wirft die Rechnung, ist der Melder danach wieder still', () {
    final got = <double>[];
    expect(() => PlanProgress.run(got.add, () => throw StateError('kaputt')), throwsStateError);
    expect(PlanProgress.active, isFalse);
    PlanProgress.report(0.9);
    expect(got, isEmpty);
  });
}
