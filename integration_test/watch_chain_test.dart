// Kettenstand (docs/konzept-garmin.md 12.3, #527) — Versuch: die echte
// Brücke gegen den Connect-IQ-Simulator, das Handy ist der Android-Emulator.
// Dev-App mit `--dart-define=GARMIN_TETHERED=true`, vorher
// `adb forward tcp:7381 tcp:7381` und im Simulator „adb Connection → Start".
//
// Gezählt wird, wie oft die Runde „Route in Stücken → ok" gelingt. Die
// Routen sind erfunden und liegen am Äquator (A7).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge_io.dart';
import 'package:trailbuddy/features/garmin/watch_route.dart';
import 'package:trailbuddy/features/routing/nav_sections.dart';

const _rounds = int.fromEnvironment('ROUNDS', defaultValue: 20);
const _ackWait = Duration(seconds: int.fromEnvironment('ACK_WAIT', defaultValue: 60));

List<LatLng> _route(int round) => [
      for (var i = 0; i < 60; i++) LatLng(0.0005 * round + 0.0002 * i, 0.0003 * i + (i.isEven ? 0.0001 : 0)),
    ];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kette: Route in Stücken, die Uhr antwortet ok', (tester) async {
    await tester.runAsync(() async {
      final bridge = createGarminBridge();
      final inbox = <Object?>[];
      final sub = bridge.messages.listen((m) {
        debugPrint('BENCH receive $m');
        inbox.add(m);
      });

      Future<Map?> waitFor(bool Function(Map m) test, Duration limit) async {
        final end = DateTime.now().add(limit);
        while (DateTime.now().isBefore(end)) {
          for (final m in inbox) {
            if (m is Map && test(m)) return m;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        return null;
      }

      // Erst lauscht das SDK, dann verbindet sich der Simulator (Konzept 3):
      // nach dem ersten `status` klickt das Skript „adb Connection → Start".
      final first = await bridge.status();
      debugPrint('BENCH sdk-up connect=${first.connect} device=${first.device} app=${first.app}');
      await Future<void>.delayed(const Duration(seconds: int.fromEnvironment('LINK_WAIT', defaultValue: 25)));
      final status = await bridge.status();
      debugPrint('BENCH status connect=${status.connect} device=${status.device} app=${status.app}');
      final open = await bridge.open();
      debugPrint('BENCH open $open');

      final q = await bridge.send([
        {'t': 'q'}
      ]);
      debugPrint('BENCH q ${q.status}');
      final hi = await waitFor((m) => m['t'] == 'hi', const Duration(seconds: 30));
      debugPrint('BENCH hello ${hi == null ? "keine Antwort" : "v=${hi['v']}"}');

      var good = 0;
      final times = <int>[];
      for (var r = 1; r <= _rounds; r++) {
        final route = watchRouteOf(_route(r), NavSections.none);
        if (route == null) fail('keine Route');
        inbox.clear();
        final t0 = DateTime.now();
        final sent = await bridge.send(route.parts());
        final ok = sent.ok ? await waitFor((m) => m['t'] == 'ok' && m['id'] == route.id, _ackWait) : null;
        final ms = DateTime.now().difference(t0).inMilliseconds;
        if (ok != null) {
          good++;
          times.add(ms);
        }
        debugPrint('BENCH round $r send=${sent.status} ${ok != null ? "ok" : "KEIN ok"} ${ms}ms');
      }
      times.sort();
      debugPrint('BENCH result $good/$_rounds'
          '${times.isEmpty ? "" : " median ${times[times.length ~/ 2]}ms max ${times.last}ms"}');
      await sub.cancel();
      expect(good, greaterThanOrEqualTo((_rounds * 0.95).floor()), reason: 'die Kette trägt nicht');
    });
  }, timeout: const Timeout(Duration(minutes: 40)));
}
