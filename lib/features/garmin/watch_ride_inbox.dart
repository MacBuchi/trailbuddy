// Die Fahrten der Uhr kommen an (#484, docs/konzept-garmin.md 2a): Die
// Uhr-App zeichnet selbst auf und hält jede Fahrt, bis das Handy sie
// quittiert. Hier wird gelauscht, zusammengesetzt, abgelegt und erst dann
// quittiert — scheitert das Ablegen, bleibt die Fahrt auf der Uhr und
// kommt beim nächsten Mal wieder.
//
// Gelauscht wird ab dem Start der App, sobald einmal eine Uhr mit unserer
// App gefunden wurde (`Settings.watchSeen`, Betreiber 2026-11-07); die Uhr
// wird dabei nicht geöffnet (Konzept 2, „Kein Anstoßen beim Start").
import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../profile/profile_providers.dart' show riderProfileProvider;
import '../rides/ride_providers.dart' show ridesProvider, WatchRideSave;
import 'garmin_bridge.dart';
import 'watch_ride.dart';
import 'watch_route.dart' show watchHelloOf;

/// So lange wartet eine halbe Fahrt auf ihre übrigen Nachrichten; danach
/// fängt sie von vorn an (die Uhr schickt sie beim nächsten Mal ganz).
const kWatchRidePartWait = Duration(minutes: 2);

/// Zählt die Fahrten der Uhr, die in dieser Sitzung abgelegt wurden — die
/// Hülle zeigt bei jeder neuen eine Leiste (`WatchRideListener`).
class WatchRideInbox extends Notifier<int> {
  StreamSubscription<Object?>? _messages;
  final _incoming = <String, _Incoming>{};
  final _saving = <String>{};

  /// Die Uhr der Fristen (Test).
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  @override
  int build() {
    ref.onDispose(() {
      _messages?.cancel();
    });
    return 0;
  }

  /// Lauschen, wenn schon einmal eine Uhr da war. Beim Start der App.
  Future<void> startIfKnown() async {
    if (!ref.read(settingsProvider).watchSeen) return;
    await start();
  }

  /// Eine Uhr ist gefunden (Startblatt) oder bekannt: auf ihre Nachrichten
  /// hören. Gefragt wird die Uhr nicht — ihre App meldet sich bei jedem
  /// Start mit „hallo" samt den wartenden Fahrten, und beim Beenden schickt
  /// sie selbst. Ohne Navigation mit „Auf der Uhr zeigen" geht so nichts
  /// an die Uhr außer `wq` und `wk`.
  Future<void> start() async {
    final bridge = ref.read(garminBridgeProvider);
    if (!bridge.supported || _messages != null) return;
    _messages = bridge.messages.listen((m) => unawaited(_onMessage(m)));
    await bridge.listen();
  }

  Future<void> _onMessage(Object? message) async {
    final hello = watchHelloOf(message);
    if (hello.hello) {
      if (hello.rides.isNotEmpty) await ref.read(garminBridgeProvider).send([watchRidePull]);
      return;
    }
    final part = watchRidePartOf(message);
    if (part == null) return;
    final t = now();
    _incoming.removeWhere((_, i) => t.difference(i.touched) > kWatchRidePartWait);
    var inc = _incoming[part.id];
    if (inc == null || inc.n != part.n) inc = _incoming[part.id] = _Incoming(part.n);
    inc.parts[part.p] = part.chunks;
    inc.touched = t;
    if (inc.parts.length < inc.n) return;
    _incoming.remove(part.id);
    if (!_saving.add(part.id)) return;
    try {
      await _save(part.id, [for (var p = 0; p < inc.n; p++) ...inc.parts[p]!]);
    } finally {
      _saving.remove(part.id);
    }
  }

  Future<void> _save(String id, List<List<int>> chunks) async {
    final bridge = ref.read(garminBridgeProvider);
    final points = decodeWatchRide(chunks);
    if (points == null || points.length < 2) {
      // Unlesbar wird sie auch beim nächsten Mal nicht: quittieren, sonst
      // käme sie bei jedem Start wieder und belegte die Uhr für immer.
      logError('Fahrt der Uhr unlesbar', StateError('${chunks.length} Stücke'), StackTrace.current);
      await bridge.send([watchRideAckOf(id)]);
      return;
    }
    final profile = ref.read(riderProfileProvider).name;
    final result = await ref.read(ridesProvider.notifier).saveFromWatch(points, profile: profile);
    if (result == WatchRideSave.failed) return;
    await bridge.send([watchRideAckOf(id)]);
    if (result == WatchRideSave.saved) state = state + 1;
  }
}

class _Incoming {
  _Incoming(this.n);

  final int n;
  final parts = <int, List<List<int>>>{};
  DateTime touched = DateTime.fromMillisecondsSinceEpoch(0);
}

final watchRideInboxProvider = NotifierProvider<WatchRideInbox, int>(WatchRideInbox.new);
