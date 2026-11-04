import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../../core/errors.dart';
import 'garmin_bridge.dart';

/// Der Name steht auch in `GarminBridge.kt`; `android_manifest_test` hält
/// beide zusammen.
const kGarminChannel = 'de.mcbuchi.trailbuddy/garmin';

GarminBridge createGarminBridge() => _AndroidGarminBridge();

class _AndroidGarminBridge implements GarminBridge {
  static const _channel = MethodChannel(kGarminChannel);

  final _messages = StreamController<Object?>.broadcast();
  bool _listening = false;

  @override
  bool get supported => Platform.isAndroid;

  void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'message') _messages.add(call.arguments);
    });
  }

  @override
  Future<WatchStatus> status() async {
    if (!supported) return WatchStatus.none;
    _listen();
    try {
      final raw = await _channel.invokeMethod<Object?>(
          'status', {'appId': kWatchAppId, 'tethered': kGarminTethered});
      return WatchStatus.fromChannel(raw);
    } catch (e, s) {
      logError('Garmin-Status', e, s);
      return WatchStatus.none;
    }
  }

  @override
  Future<WatchSendResult> send(List<Map<String, Object>> messages) async {
    if (!supported) return const WatchSendResult('NOT_SUPPORTED', 0);
    try {
      final raw = await _channel.invokeMethod<Object?>('send', {'messages': messages});
      return WatchSendResult.fromChannel(raw);
    } catch (e, s) {
      logError('Route an die Uhr', e, s);
      return const WatchSendResult('FAILURE_UNKNOWN', 0);
    }
  }

  @override
  Stream<Object?> get messages => _messages.stream;
}
