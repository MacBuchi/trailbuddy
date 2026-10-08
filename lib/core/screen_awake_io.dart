import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'errors.dart';
import 'screen_awake.dart';

/// Der Name steht auch in `MainActivity.kt`; `android_manifest_test` hält
/// beide zusammen.
const kScreenChannel = 'de.mcbuchi.trailbuddy/screen';

ScreenAwake createScreenAwake() => _AndroidScreenAwake();

class _AndroidScreenAwake implements ScreenAwake {
  static const _channel = MethodChannel(kScreenChannel);

  @override
  bool get supported => Platform.isAndroid;

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
