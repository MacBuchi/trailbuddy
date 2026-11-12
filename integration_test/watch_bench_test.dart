// Der Kettenstand (S5, docs/konzept-garmin.md 12.3, #527): die echte
// Brücke (Dart → GarminBridge.kt → Companion-SDK über adb) gegen die echte
// Uhr-App im Connect-IQ-Simulator. Das Handy ist der Android-Emulator.
//
// Nicht von Hand starten: `tool/garmin_bench.sh chain` hält die Reihenfolge
// ein (erst dieser Treiber bis „BENCH sdk-up", dann im Simulator „adb
// Connection → Start", dann die Uhr-App aus `garmin_build.sh --bench`).
//
// Die Uhr nimmt im Bench-Bau Ereignisse über den Kanal (`_k` Taste, `_f`
// Fixe, `_t` Zeitsprung, `_x` gewollter Bruch) und meldet ihren Stand mit
// `_s` — `TrailBuddyApp.mc`, Abschnitt „Der Kettenstand". Was hier das
// Handy tut (Route schicken, `wk`), tut in der App `watch_providers.dart`
// bzw. `watch_ride_inbox.dart`; der Treiber prüft die Kette, nicht diese.
//
// Jede Zeile `BENCH step <Name> OK|FEHLT` liest das Skript. Die Routen
// sind erfunden und liegen am Äquator (A7).
//
// Das Uhr-Protokoll (#510): Die Fahrt muss ihren Ring (`ev`) heil über die
// Brücke bringen; danach startet die Uhr-App neu (Zeile `BENCH relaunch`,
// das Skript startet `monkeydo` noch einmal) — nach einem sauberen Ende
// ohne Ring im „hallo", nach einem echten Absturz (`_z`) mit, und nach
// einer Antwort des Handys wieder ohne.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge_io.dart';
import 'package:trailbuddy/features/garmin/watch_events.dart';
import 'package:trailbuddy/features/garmin/watch_ride.dart';
import 'package:trailbuddy/features/garmin/watch_route.dart';
import 'package:trailbuddy/features/routing/nav_sections.dart';

/// So oft die Runde „Route in Stücken → ok" (der Versuch: 20 von 20).
const _rounds = int.fromEnvironment('ROUNDS', defaultValue: 5);

/// So lange wartet ein Schritt auf die Antwort der Uhr.
const _wait = Duration(seconds: int.fromEnvironment('STEP_WAIT', defaultValue: 30));

/// So lange hat das Skript nach „sdk-up", um den Simulator zu verbinden und
/// die Uhr-App zu laden.
const _linkWait = Duration(seconds: int.fromEnvironment('LINK_WAIT', defaultValue: 40));

/// Der gewollte Bruch: Die Uhr sendet nie `ok` — die Kette muss rot werden.
const _breakOk = bool.fromEnvironment('BREAK_OK');

/// Eine erfundene Linie im Zickzack (sonst vereinfacht `watchRouteOf` sie
/// auf zwei Punkte), [n] Punkte, je rund 25 m.
List<LatLng> _line(int seed, int n) => [
      for (var i = 0; i < n; i++)
        LatLng(0.001 * seed + 0.0002 * i, 0.0001 * i + (i.isEven ? 0.0001 : 0)),
    ];

class _StepFailed implements Exception {
  _StepFailed(this.step);
  final String step;
  @override
  String toString() => 'Schritt „$step" fehlt';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kettenstand: Handy und Uhr über die echte Brücke', (tester) async {
    await tester.runAsync(() async {
      final bridge = createGarminBridge();
      final inbox = <Map<Object?, Object?>>[];
      final sub = bridge.messages.listen((m) {
        if (m is! Map) return;
        // Nur die Art, nie Inhalt (Koordinaten der Fahrt).
        debugPrint('BENCH receive ${m['t']}');
        inbox.add(m);
      });

      Future<Map<Object?, Object?>?> waitFor(bool Function(Map<Object?, Object?> m) test,
          [Duration limit = _wait]) async {
        final end = DateTime.now().add(limit);
        while (DateTime.now().isBefore(end)) {
          for (final m in inbox) {
            if (test(m)) {
              inbox.remove(m);
              return m;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        return null;
      }

      Future<void> send(Map<String, Object> m) async {
        final r = await bridge.send([m]);
        if (!r.ok) debugPrint('BENCH send ${m['t']} ${r.status}');
      }

      Future<T> step<T>(String name, Future<T?> Function() run) async {
        final t0 = DateTime.now();
        final v = await run();
        final ms = DateTime.now().difference(t0).inMilliseconds;
        if (v == null || v == false) {
          debugPrint('BENCH step $name FEHLT ${ms}ms');
          throw _StepFailed(name);
        }
        debugPrint('BENCH step $name OK ${ms}ms');
        return v;
      }

      /// Den Stand der Uhr erfragen, bis [test] passt.
      Future<Map<Object?, Object?>?> stateUntil(bool Function(Map<Object?, Object?> s) test) async {
        final end = DateTime.now().add(_wait);
        while (DateTime.now().isBefore(end)) {
          inbox.removeWhere((m) => m['t'] == '_s');
          await send({'t': '_s'});
          final s = await waitFor((m) => m['t'] == '_s', const Duration(seconds: 5));
          if (s != null && test(s)) return s;
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        return null;
      }

      /// Die Uhr-App neu starten lassen (das Skript sieht die Zeile) und
      /// auf ihr „hallo" warten.
      Future<Map<Object?, Object?>?> relaunched() async {
        inbox.clear();
        debugPrint('BENCH relaunch');
        // Der Simulator startet ganz neu (gut 25 s) und verbindet sich wieder.
        final end = DateTime.now().add(_linkWait * 3);
        while (DateTime.now().isBefore(end)) {
          final hi = await waitFor((m) => m['t'] == 'hi', const Duration(seconds: 3));
          if (hi != null) return hi;
          await bridge.status();
          await send({'t': 'q'});
        }
        return null;
      }

      bool hasEvent(List<int> ev, int kind, int detail) =>
          ev.any((v) => unpackWatchEvent(v).kind == kind && unpackWatchEvent(v).detail == detail);

      /// Eine Route in Stücken an die Uhr; true, wenn sie `ok` sagt.
      Future<bool> route(WatchRoute r) async {
        final sent = await bridge.send(r.parts());
        if (!sent.ok) return false;
        return await waitFor((m) => m['t'] == 'ok' && m['id'] == r.id) != null;
      }

      try {
        // Erst lauscht das SDK, dann verbindet sich der Simulator (12.3).
        final first = await bridge.status();
        debugPrint('BENCH sdk-up connect=${first.connect} device=${first.device}');
        final hello = await step('hallo', () async {
          final end = DateTime.now().add(_linkWait);
          while (DateTime.now().isBefore(end)) {
            await bridge.status();
            await send({'t': 'q'});
            final hi = await waitFor((m) => m['t'] == 'hi', const Duration(seconds: 3));
            if (hi != null) return hi;
          }
          return null;
        });
        debugPrint('BENCH hallo v=${hello['v']} ver=${hello['ver']}');

        if (_breakOk) await send({'t': '_x', 'drop': 'ok'});

        // Route in Stücken → ok, mehrmals hintereinander.
        WatchRoute? last;
        final times = <int>[];
        for (var r = 1; r <= _rounds; r++) {
          final wr = watchRouteOf(_line(r, 1200), NavSections.none)!;
          final t0 = DateTime.now();
          await step('Route in Stücken → ok ($r/$_rounds, ${wr.parts().length} Stücke)', () => route(wr));
          times.add(DateTime.now().difference(t0).inMilliseconds);
          last = wr;
        }
        times.sort();
        debugPrint('BENCH route median ${times[times.length ~/ 2]}ms max ${times.last}ms');
        final a = last!;

        // Die Frage nach der neuen Linie läuft ab, die Uhr nimmt sie.
        await step('letzte Route geladen', () async {
          await send({'t': '_t', 'ms': 9000});
          return stateUntil((s) => s['id'] == a.id && s['ready'] == true && s['ask'] == false);
        });

        // START an der Uhr → das Handy hört `rs`.
        inbox.clear();
        await send({'t': '_k', 'k': 'start'});
        await step('START → rs', () => waitFor((m) => m['t'] == kWatchRecordStart));
        await step('Aufzeichnung läuft', () => stateUntil((s) => s['rec'] == 1));

        // Fixe entlang der Linie, damit die Fahrt Punkte hat.
        final pts = _line(_rounds, 1200);
        Map<String, Object> fixes(int from, int to) => {
              't': '_f',
              'la': [for (var i = from; i < to; i++) (pts[i].latitude * 1e5).round()],
              'lo': [for (var i = from; i < to; i++) (pts[i].longitude * 1e5).round()],
              'dt': 5,
              'sp': 6,
            };
        await send(fixes(0, 20));
        await step('Fixe verarbeitet', () => stateUntil((s) => s['fx'] == 0));

        // Pause und weiter.
        inbox.clear();
        await send({'t': '_k', 'k': 'start'});
        await step('Pause → rp', () => waitFor((m) => m['t'] == kWatchRecordPause));
        await step('Menü der Pause', () => stateUntil((s) => s['menu'] == 'pause' && s['rec'] == 2));
        await send({'t': '_k', 'k': 'resume'});
        await step('Weiter → rr', () => waitFor((m) => m['t'] == kWatchRecordResume));
        // Weit über RideLog.MIN_POINTS (24): Mit 40 Fixen kamen mal 24, mal
        // 23 Punkte an, und die Uhr verwarf die Fahrt als zu kurz (#510).
        await send(fixes(20, 60));
        await step('Fixe verarbeitet', () => stateUntil((s) => s['fx'] == 0));

        // Abkommen: weit neben der Linie meldet die Uhr ihren Stand (`d`).
        inbox.clear();
        await send({
          't': '_f',
          'la': [(pts[60].latitude * 1e5).round() + 5000],
          'lo': [(pts[60].longitude * 1e5).round()],
          'dt': 5,
          'sp': 6,
        });
        await step('abseits → d', () => waitFor((m) => m['t'] == 'd'));

        // Umplanen: Eine neue Linie während der Fahrt — die Uhr fragt …
        final b = watchRouteOf(_line(_rounds + 50, 600), NavSections.none)!;
        await step('neue Linie → ok', () => route(b));
        await step('Frage steht', () => stateUntil((s) => s['ask'] == true && s['pend'] == b.id));
        // … und nimmt sie, wenn niemand antwortet.
        await step('nach der Frist genommen', () async {
          await send({'t': '_t', 'ms': 9000});
          return stateUntil((s) => s['id'] == b.id && s['ready'] == true && s['rec'] == 1);
        });

        // Speichern: Ende ans Handy, dann die Fahrt in Nachrichten, `wk`.
        inbox.clear();
        await send({'t': '_k', 'k': 'start'});
        await step('Pause vor dem Speichern', () => stateUntil((s) => s['menu'] == 'pause'));
        await send({'t': '_k', 'k': 'save'});
        await step('Speichern → re', () => waitFor((m) => m['t'] == kWatchRecordEnd && m['k'] == true));
        List<int>? rideEvents;
        final ride = await step('Fahrt hinüber', () async {
          final parts = <int, List<List<int>>>{};
          String? id;
          final end = DateTime.now().add(_wait * 2);
          while (DateTime.now().isBefore(end)) {
            final m = await waitFor((m) => m['t'] == kWatchRide, const Duration(seconds: 2));
            final part = watchRidePartOf(m);
            if (part == null) continue;
            id = part.id;
            parts[part.p] = part.chunks;
            if (part.p == 0) rideEvents = watchEventsOf(m!['ev']);
            if (parts.length == part.n) {
              final points = decodeWatchRide([for (var p = 0; p < part.n; p++) ...parts[p]!]);
              return points == null ? null : (id: id, points: points.length);
            }
          }
          return null;
        });
        debugPrint('BENCH Fahrt ${ride.points} Punkte');
        // #510: Der Ring kam mit, heil über Kotlin und das SDK — mit START
        // am Anfang und „Speichern" am Ende.
        final ev = await step('Protokoll mit der Fahrt', () async {
          final ev = rideEvents;
          if (ev == null) return null;
          final last = unpackWatchEvent(ev.last);
          debugPrint('BENCH Protokoll ${ev.length} Ereignisse, zuletzt ${last.kind}.${last.detail}');
          return hasEvent(ev, 1, 0) && hasEvent(ev, 2, 1) && hasEvent(ev, 9, 1) ? ev : null;
        });
        debugPrint('BENCH Protokoll ${encodeWatchEvents(ev).length} Zeichen im Feedback');
        // Der nächste Start behält den Speicher (sonst wischt der Bench-Bau).
        await send({'t': '_r'});
        await send(watchRideAckOf(ride.id));
        // Die Uhr löscht sie mit `wk` und geht zu: kein neues `w` mehr.
        await step('wk angenommen', () async {
          final again = await waitFor((m) => m['t'] == kWatchRide, const Duration(seconds: 8));
          return again == null;
        });
        // Sauber zu: Beim nächsten Start kein Absturz-Ring.
        final clean = await step('Neustart nach sauberem Ende', relaunched);
        await step('hallo ohne Protokoll', () async => clean['ev'] == null);

        // Ein echter Absturz nach START (gespeichert wird bei jeder Taste).
        await send({'t': '_t', 'ms': 9000});
        await step('Route nach Neustart', () => stateUntil((s) => s['ready'] == true && s['wait'] == 0));
        inbox.clear();
        await send({'t': '_k', 'k': 'start'});
        await step('START → rs (vor dem Absturz)', () => waitFor((m) => m['t'] == kWatchRecordStart));
        await send({'t': '_z'});
        final crashed = await step('Neustart nach Absturz', relaunched);
        await step('hallo mit Protokoll', () async {
          final ev = watchEventsOf(crashed['ev']);
          if (ev == null) return null;
          debugPrint('BENCH Absturz-Protokoll ${ev.length} Ereignisse');
          return hasEvent(ev, 1, 0) ? ev : null;
        });
        // Das Handy antwortet (die Route ist aktuell): Der Ring ist angekommen.
        await send({'t': 'k'});
        await Future<void>.delayed(const Duration(seconds: 2));
        inbox.clear();
        await send({'t': 'q'});
        await step('nach der Antwort ohne Protokoll', () async {
          final hi = await waitFor((m) => m['t'] == 'hi');
          return hi != null && hi['ev'] == null;
        });
        debugPrint('BENCH result grün');
      } on _StepFailed catch (e) {
        debugPrint('BENCH result rot: ${e.step}');
        fail(e.toString());
      } finally {
        await sub.cancel();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 20)));
}
