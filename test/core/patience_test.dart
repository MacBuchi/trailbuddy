// Die Frist ohne Rest (#183): Nach [patience] kommt null, ein schnelles
// Ergebnis kommt durch, ein Fehler auch.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/patience.dart';

void main() {
  const patience = Duration(milliseconds: 50);

  test('schnell: der Wert', () async {
    expect(await withinOrNull(Future.value(7), patience), 7);
  });

  test(
    'langsam: null nach der Frist, das Future läuft unbehelligt weiter',
    () async {
      final slow = Completer<int>();
      final watch = Stopwatch()..start();
      expect(await withinOrNull(slow.future, patience), isNull);
      expect(watch.elapsed, greaterThanOrEqualTo(patience));
      slow.complete(3);
      expect(await slow.future, 3);
    },
  );

  test('ein Fehler innerhalb der Frist kommt durch', () async {
    expect(
      withinOrNull<int>(Future.error(StateError('kaputt')), patience),
      throwsA(isA<StateError>()),
    );
  });
}
