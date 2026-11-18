import 'dart:async';

/// Wartet höchstens [patience] auf [future] — danach `null`, ohne dass
/// [future] abgebrochen wird (#183). Die Uhr ist ein [Timer], der beim Sieg
/// von [future] abgebrochen wird: Ein `Future.delayed` liefe im Widget-Test
/// über das Testende hinaus. Ein Fehler von [future] innerhalb der Frist
/// kommt durch.
Future<T?> withinOrNull<T>(Future<T> future, Duration patience) {
  final done = Completer<T?>();
  final clock = Timer(patience, () {
    if (!done.isCompleted) done.complete(null);
  });
  future.then(
    (value) {
      clock.cancel();
      if (!done.isCompleted) done.complete(value);
    },
    onError: (Object error, StackTrace stackTrace) {
      clock.cancel();
      if (!done.isCompleted) done.completeError(error, stackTrace);
    },
  );
  return done.future;
}
