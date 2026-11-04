import 'garmin_bridge.dart';

GarminBridge createGarminBridge() => const _NoWatch();

/// Im Browser keine Uhr (Konzept-Garmin 3, A9).
class _NoWatch implements GarminBridge {
  const _NoWatch();

  @override
  bool get supported => false;

  @override
  Future<WatchStatus> status() async => WatchStatus.none;

  @override
  Future<WatchSendResult> send(List<Map<String, Object>> messages) async =>
      const WatchSendResult('NOT_SUPPORTED', 0);

  @override
  Stream<Object?> get messages => const Stream.empty();
}
