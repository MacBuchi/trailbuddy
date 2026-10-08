import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'errors.dart';
import 'screen_awake.dart';

ScreenAwake createScreenAwake() => _WebScreenAwake();

/// Screen Wake Lock: Der Browser gibt die Sperre selbst frei, sobald der
/// Tab verdeckt ist — beim Zurückkommen wird sie neu geholt, solange sie
/// gewünscht ist.
class _WebScreenAwake implements ScreenAwake {
  web.WakeLockSentinel? _sentinel;
  bool _wanted = false;
  JSFunction? _onVisible;

  @override
  bool get supported => web.window.navigator.has('wakeLock');

  @override
  Future<void> keepOn(bool on) async {
    if (!supported) return;
    _wanted = on;
    if (on) {
      _onVisible ??= ((web.Event _) {
        if (_wanted && web.document.visibilityState == 'visible') _request();
      }).toJS;
      web.document.addEventListener('visibilitychange', _onVisible);
      await _request();
    } else {
      if (_onVisible != null) web.document.removeEventListener('visibilitychange', _onVisible);
      final s = _sentinel;
      _sentinel = null;
      try {
        await s?.release().toDart;
      } catch (e, st) {
        logError('Bildschirm freigeben', e, st);
      }
    }
  }

  Future<void> _request() async {
    try {
      _sentinel = await web.window.navigator.wakeLock.request('screen').toDart;
    } catch (_) {
      // Abgelehnt (Akku sparen, Tab nicht vorne): Der Bildschirm geht aus
      // wie immer — kein Fehlerbericht für eine Entscheidung des Browsers.
    }
  }
}
