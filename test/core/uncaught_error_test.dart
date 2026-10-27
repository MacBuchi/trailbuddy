import 'package:executor_lib/executor_lib.dart' show CancellationException;
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/errors.dart';

// #351: Nur ein abgebrochener Kachel-Auftrag gilt als behandelt — sonst
// warf der Browser ihn als „Uncaught Error" in die Konsole. Alles andere
// bleibt bei der Standardbehandlung.
void main() {
  final reported = <Object>[];
  setUp(() {
    reported.clear();
    setErrorSink((context, error, stack) => reported.add(error));
  });
  tearDown(() => setErrorSink(null));

  test('CancellationException ist behandelt und wird nicht gemeldet', () {
    expect(handleUncaughtError(CancellationException(), StackTrace.empty), isTrue);
    expect(reported, isEmpty);
  });

  test('ein echter Fehler wird gemeldet und nicht verschluckt', () {
    final error = StateError('kaputt');
    expect(handleUncaughtError(error, StackTrace.empty), isFalse);
    expect(reported, [error]);
  });

  test('ohne Sitzung wird weder gemeldet noch verschluckt', () {
    expect(handleUncaughtError(const NotSignedInException(), StackTrace.empty), isFalse);
    expect(reported, isEmpty);
  });
}
