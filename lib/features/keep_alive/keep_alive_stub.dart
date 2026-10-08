import 'keep_alive.dart';

/// Web: kein Prozess, den man wachhalten müsste, und kein Service-Isolate.
class _NoKeepAlive implements KeepAlive {
  const _NoKeepAlive();

  @override
  Future<void> start(String title, String text, Set<KeepAliveType> types,
      {List<KeepAliveButton> buttons = const []}) async {}

  @override
  Future<void> update(String title, String text, {List<KeepAliveButton> buttons = const []}) async {}

  @override
  Future<void> setRepeat(Duration? every) async {}

  @override
  Future<void> stop() async {}
}

KeepAlive createKeepAlive() => const _NoKeepAlive();

void initKeepAliveCommunicationImpl() {}
