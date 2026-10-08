import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'errors.dart';
import 'picture_in_picture.dart';

/// Der Name steht auch in `MainActivity.kt`; `android_manifest_test` hält
/// beide zusammen.
const kPipChannel = 'de.mcbuchi.trailbuddy/pip';

PictureInPicture createPictureInPicture() => _AndroidPictureInPicture();

class _AndroidPictureInPicture implements PictureInPicture {
  static const _channel = MethodChannel(kPipChannel);

  bool get _supported => Platform.isAndroid;

  @override
  Future<void> allow(bool on) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('allow', {'on': on});
    } catch (e, s) {
      // Ohne Fenster bleibt die Benachrichtigung — kein Grund zum Abbruch.
      logError('Bild-im-Bild erlauben', e, s);
    }
  }

  @override
  void listen({required void Function(bool inPip) onMode, required VoidCallback onStop}) {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'changed':
          onMode((call.arguments as Map?)?['inPip'] == true);
        case 'stop':
          onStop();
      }
    });
  }
}
