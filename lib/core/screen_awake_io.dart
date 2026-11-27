import 'package:flutter/services.dart';

import 'errors.dart';
import 'screen_awake.dart';
import 'platform_support.dart';

/// Der Name steht auch in `MainActivity.kt` und `ScreenAwake.swift` (#644);
/// `android_manifest_test` und `ios_support_test` halten sie zusammen.
const kScreenChannel = 'de.mcbuchi.trailbuddy/screen';

ScreenAwake createScreenAwake() => _NativeScreenAwake();

class _NativeScreenAwake implements ScreenAwake {
  static const _channel = MethodChannel(kScreenChannel);

  @override
  bool get supported => hasAndroidChannels || hasIosChannels;

  @override
  Future<void> keepOn(bool on) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('keepOn', {'on': on});
    } catch (e, s) {
      logError('Bildschirm anlassen', e, s);
    }
  }
}
