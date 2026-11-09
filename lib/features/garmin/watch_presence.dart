// Der Stand der Uhr auf dem Handy (#499, docs/konzept-garmin.md 2): ist sie
// verbunden, und nimmt sie auf? Die Uhr sagt es selbst — START, Pause,
// Weiter, Ende (`rs`, `rp`, `rr`, `re` in `watch_ride.dart`), und jedes
// „hallo" zeigt: sie ist da. Gelauscht wird, ohne die Uhr anzustoßen
// (Konzept 2, „Kein Anstoßen beim Start"); auf Plattformen ohne Uhr (A9)
// fragt niemand.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'garmin_bridge.dart';
import 'watch_route.dart' show watchFixOf;
import 'watch_ride.dart' show WatchRecordEvent, watchRecordOf;

/// Die Aufzeichnung an der Uhr, so wie das Handy sie kennt.
enum WatchRecord {
  idle,

  /// START gedrückt, noch nicht gespeichert.
  running,

  /// START nochmal: die Pause mit ihrem Menü.
  paused,
}

/// Ab dem Abstand melden Uhr und Handy verschiedene Orte (#500). Uhr am
/// Handgelenk, Handy in der Tasche — darunter liegen sie immer beieinander.
const kWatchFixApartM = 200.0;

/// Was das Handy über die Uhr weiß. [connected] kommt von Garmin Connect
/// oder von einer Nachricht der Uhr — ein Abbruch meldet das SDK nicht.
/// [watchFix] ist der erste eigene GPS-Fix der Uhr (#500), null, wenn sie
/// ihn noch nicht gemeldet hat oder eine alte Uhr-App ihn nicht mitschickt.
class WatchPresence {
  const WatchPresence({this.connected = false, this.record = WatchRecord.idle, this.watchFix});

  static const none = WatchPresence();

  final bool connected;
  final WatchRecord record;
  final LatLng? watchFix;

  bool get recording => record != WatchRecord.idle;

  /// Ein Uhr-Symbol steht nur, wenn etwas zu sagen ist.
  bool get shows => connected || recording;
}

class WatchPresenceNotifier extends Notifier<WatchPresence> {
  StreamSubscription<Object?>? _messages;
  StreamSubscription<void>? _connected;

  @override
  WatchPresence build() {
    ref.onDispose(() {
      _messages?.cancel();
      _connected?.cancel();
    });
    final bridge = ref.read(garminBridgeProvider);
    if (!bridge.supported) return WatchPresence.none;
    // Mitlesen, nicht anstoßen: die Uhr meldet sich selbst, wenn ihre App
    // läuft. Dieselbe Leitung wie das Fahrten-Postfach (`watch_ride_inbox`).
    _messages = bridge.messages.listen(_onMessage);
    _connected = bridge.connected.listen((_) => _note(true, state.record));
    // Die erste Frage startet das SDK; eine Antwort ist ein Fund.
    unawaited(bridge.status().then((s) {
      if (s.canShow) _note(true, state.record);
    }));
    return WatchPresence.none;
  }

  void _onMessage(Object? message) {
    // Jede Nachricht der Uhr heißt: sie ist verbunden.
    final fix = watchFixOf(message);
    if (fix != null) {
      state = WatchPresence(connected: true, record: state.record, watchFix: fix);
      return;
    }
    final record = watchRecordOf(message);
    if (record == null) {
      _note(true, state.record);
      return;
    }
    final next = switch (record.event) {
      WatchRecordEvent.start => WatchRecord.running,
      WatchRecordEvent.pause => WatchRecord.paused,
      WatchRecordEvent.resume => WatchRecord.running,
      WatchRecordEvent.trail => state.record,
      WatchRecordEvent.end => WatchRecord.idle,
    };
    _note(true, next);
  }

  void _note(bool connected, WatchRecord record) {
    if (!connected && record == WatchRecord.idle) return;
    state = WatchPresence(
        connected: connected || state.connected, record: record, watchFix: state.watchFix);
  }
}

final watchPresenceProvider = NotifierProvider<WatchPresenceNotifier, WatchPresence>(WatchPresenceNotifier.new);
