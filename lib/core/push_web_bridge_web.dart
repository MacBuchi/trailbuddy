import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

StreamController<Object?>? _messages;

/// Alles, was ein Service Worker dieser Domain an die Seite schickt —
/// als Dart-Werte. EIN Zuhörer am Browser für alle Abnehmer; ausgesiebt
/// wird beim Deuten, nicht hier.
Stream<Object?> serviceWorkerMessages() {
  var controller = _messages;
  if (controller == null) {
    controller = _messages = StreamController<Object?>.broadcast();
    try {
      web.window.navigator.serviceWorker.addEventListener(
        'message',
        ((web.MessageEvent event) {
          controller!.add(event.data.dartify());
        }).toJS,
      );
      _refreshPushWorker();
    } catch (_) {
      // Kein `navigator.serviceWorker` (unsicherer Kontext, `file://`,
      // privater Modus mancher Browser) — dann gibt es auch keinen
      // Push-Worker, und der Strom bleibt leer.
    }
  }
  return controller.stream;
}

/// Den Push-Worker einmal je Start nach einer neuen Fassung sehen lassen.
///
/// Sein Scope (`push/`) wird nie angesteuert, und ein Token holt die App
/// nur beim Einschalten — von sich aus prüfte der Browser deshalb erst
/// nach einem Push-Ereignis und höchstens einmal am Tag. Kein Worker da
/// ⇒ nichts zu tun.
void _refreshPushWorker() {
  web.window.navigator.serviceWorker
      .getRegistration('push/')
      .toDart
      .then(
        (registration) => registration?.update(),
        onError: (Object _) {
          // Nur eine Auffrischung — scheitert sie, prüft der Browser später
          // selbst.
        },
      );
}
