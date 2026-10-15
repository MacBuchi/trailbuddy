import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Der Transportweg, wie `connectivity_plus` ihn meldet. In Tests
/// überschrieben — ohne Kanal gäbe es sonst keinen Strom.
///
/// Erst der jetzige Stand, dann die Wechsel: Im Browser meldet
/// `onConnectivityChanged` NUR Wechsel (`online`/`offline` am Fenster),
/// keinen Anfang. Ohne den Stand blieb ein Start ohne Empfang
/// „unbekannt" = verbunden, und die Rückkehr des Netzes war kein Wechsel
/// von „kein Netz" — der Ausgangskorb ging erst beim nächsten Start raus,
/// und „Kein Empfang — Trails vom …" blieb stehen (gefunden im
/// Browser-Check von 0.102.0, #153). Android liefert den Anfang selbst;
/// dort kommt er so höchstens doppelt, und das ist kein Wechsel.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  final connectivity = Connectivity();
  return startingWith(connectivity.checkConnectivity(), connectivity.onConnectivityChanged);
});

/// [changes], vorneweg [current] — es sei denn, ein Wechsel war schneller:
/// Dann ist [current] schon überholt und fällt weg. Gehört wird ab dem
/// ersten Hörer, damit zwischen Abfrage und Abo kein Wechsel verloren
/// geht. Scheitert die Abfrage, gibt es keinen Anfang (unbekannt gilt
/// als verbunden, siehe [noConnectivityProvider]).
Stream<T> startingWith<T>(Future<T> current, Stream<T> changes) {
  late final StreamController<T> out;
  StreamSubscription<T>? sub;
  var changed = false;
  out = StreamController<T>(
    onListen: () {
      sub = changes.listen((v) {
        changed = true;
        out.add(v);
      }, onError: out.addError, onDone: out.close);
      current.then((v) {
        if (!changed && !out.isClosed) out.add(v);
      }, onError: (Object _) {});
    },
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () => sub?.cancel(),
  );
  return out.stream;
}

/// Kein Empfang? Der eine Wechsel, an dem der Ausgangskorb (#30) hängt:
/// von „kein Netz" zurück auf irgendetwas. Bewusst NICHT am App-Resume —
/// wer aus dem Wald nach Hause kommt, ohne die App zu schließen, hat
/// kein Resume, aber sehr wohl einen Netzwechsel. Unbekannt gilt als
/// verbunden: ein Banner „offline" beim Aufbau, das gleich wieder
/// verschwindet, wäre schlimmer als eines einen Frame später.
final noConnectivityProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityProvider).valueOrNull;
  if (results == null) return false;
  return results.isEmpty || results.every((r) => r == ConnectivityResult.none);
});

/// Mobilfunk und kein WLAN/LAN? Für die Warnung vor großen Downloads
/// (Konzept Offline-Karten 8.2: „bei Mobilfunk mit Warnung"). Der
/// Transportweg ist nicht die Rechnung — ein Hotspot heißt hier WLAN —,
/// aber er ist, was `connectivity_plus` weiß. Unbekannt heißt: keine
/// Warnung.
final onMobileDataProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityProvider).valueOrNull ?? const [];
  return results.contains(ConnectivityResult.mobile) &&
      !results.any((r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
});
