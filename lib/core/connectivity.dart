import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Der Transportweg, wie `connectivity_plus` ihn meldet. In Tests
/// überschrieben — ohne Kanal gäbe es sonst keinen Strom.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>(
    (ref) => Connectivity().onConnectivityChanged);

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
