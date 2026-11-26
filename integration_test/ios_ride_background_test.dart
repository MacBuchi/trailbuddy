// Fahrt im Hintergrund auf dem iOS-Simulator (#644, Paket 3). Kein
// CI-Test — er braucht das Testkonto und `tool/ios_ride_bench.sh`, das
// den Standort abspielt und die App in den Hintergrund schickt:
//
//   tool/ios_ride_bench.sh <udid>   (TB_MAIL, TB_PW aus der Umgebung)
//
// Ablauf: anmelden, Fahrt starten, `TB-BENCH ride-started` drucken; das
// Skript startet eine andere App (unsere geht in den Hintergrund) und
// holt unsere nach [_bgSeconds] zurück. Geprüft wird die Datei der Fahrt:
// Während die App hinten war, kamen Punkte im Takt (5 s) dazu. Gegenprobe:
// ohne `UIBackgroundModes: location` in Info.plist friert iOS den Prozess
// ein — im Fenster steht kein Punkt.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trailbuddy/features/rides/ride_store.dart';
import 'package:trailbuddy/main.dart' as app;

const _mail = String.fromEnvironment('TB_MAIL');
const _pw = String.fromEnvironment('TB_PW');
const _bgSeconds = int.fromEnvironment('TB_BG_SECONDS', defaultValue: 90);

class _Lifecycle with WidgetsBindingObserver {
  DateTime? hidden;
  DateTime? back;
  final seen = <String>[];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final now = DateTime.now().toUtc();
    seen.add('${state.name}@${now.toIso8601String().substring(11, 19)}');
    if (state == AppLifecycleState.paused) hidden ??= now;
    // Zurück heißt: nach `paused` wieder `inactive` oder `resumed` — im
    // Simulator kommt nach `simctl launch` oft nur `inactive`.
    if (hidden != null &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.resumed)) {
      back ??= now;
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'eine Fahrt zeichnet im Hintergrund weiter',
    skip: _mail.isEmpty || _pw.isEmpty,
    (tester) async {
      await app.main();

      Future<bool> waitUntil(bool Function() ok, {int seconds = 40}) async {
        for (var i = 0; i < seconds * 4; i++) {
          if (ok()) return true;
          await tester.pump(const Duration(milliseconds: 250));
        }
        return ok();
      }

      Future<bool> waitFor(Finder f, {int seconds = 40}) =>
          waitUntil(() => f.evaluate().isNotEmpty, seconds: seconds);

      // Angemeldet aus einem früheren Lauf? Dann gleich die Karte.
      final record = find.byTooltip('Fahrt aufzeichnen');
      final fields = find.byType(TextField);
      await waitUntil(
        () => record.evaluate().isNotEmpty || fields.evaluate().length >= 2,
      );
      if (record.evaluate().isEmpty) {
        await tester.enterText(fields.at(0), _mail);
        await tester.enterText(fields.at(1), _pw);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        final safety = find.text('Verstanden');
        if (await waitFor(safety, seconds: 20)) await tester.tap(safety.first);
      }
      // Läuft noch eine Fahrt aus einem abgebrochenen Lauf, erst beenden.
      final stop = find.byTooltip('Fahrt beenden');
      expect(
        await waitUntil(
          () => record.evaluate().isNotEmpty || stop.evaluate().isNotEmpty,
        ),
        isTrue,
        reason: 'kein Aufnahmeknopf',
      );
      if (stop.evaluate().isNotEmpty) {
        await tester.tap(stop.first);
        await waitFor(record);
      }

      // Beim ersten Start legen sich Tour und Hinweise über die Karte
      // (`lib/features/coach/`): wegklicken, bis nichts mehr davor liegt.
      for (var round = 0; round < 8; round++) {
        await tester.pump(const Duration(seconds: 1));
        final away = [
          'Überspringen',
          'Später',
          'Nicht jetzt',
          "Los geht's",
          'Verstanden',
        ].map(find.text).where((f) => f.evaluate().isNotEmpty);
        if (away.isEmpty) break;
        await tester.tap(away.first.first, warnIfMissed: false);
      }

      final uid = Supabase.instance.client.auth.currentUser!.id;
      final lifecycle = _Lifecycle();
      WidgetsBinding.instance.addObserver(lifecycle);
      addTearDown(() => WidgetsBinding.instance.removeObserver(lifecycle));

      await tester.tap(record.first);
      final started = await waitFor(stop, seconds: 20);
      final shown = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .join(' | ');
      expect(started, isTrue, reason: 'nicht gestartet; im Bild: $shown');
      // Ein paar Takte im Vordergrund, dann gibt das Skript die App ab.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      // ignore: avoid_print
      print('TB-BENCH ride-started');

      // Warten, bis das Skript uns wieder nach vorn geholt hat. Im
      // Hintergrund steht dieser Code; was zählt, schreibt der Dienst.
      final deadline = DateTime.now().add(
        const Duration(seconds: _bgSeconds + 120),
      );
      while (lifecycle.back == null && DateTime.now().isBefore(deadline)) {
        // Kein `pump`: Im Hintergrund zeichnet die App keine Bilder.
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      // ignore: avoid_print
      print('TB-BENCH lifecycle ${lifecycle.seen.join(' ')}');
      expect(lifecycle.hidden, isNotNull, reason: 'nie im Hintergrund');

      final ride = await FileRideStore().readActive(uid: uid);
      expect(ride, isNotNull);
      // Kam die App nicht zurück, reicht das Fenster bis jetzt: Dieser Code
      // lief dann im Hintergrund.
      final from = lifecycle.hidden!;
      final to = lifecycle.back ?? DateTime.now().toUtc();
      final inside = ride!.points
          .where((p) => p.at.isAfter(from) && p.at.isBefore(to))
          .toList();
      final window = to.difference(from);
      // Mit den Rändern: Ohne Punkt im Hintergrund wäre die Lücke vom
      // Wegschicken bis zum ersten Punkt danach das ganze Fenster.
      final times = [from, for (final p in inside) p.at, to];
      var maxGap = Duration.zero;
      for (var i = 1; i < times.length; i++) {
        final g = times[i].difference(times[i - 1]);
        if (g > maxGap) maxGap = g;
      }
      // ignore: avoid_print
      print(
        'TB-BENCH window=${window.inSeconds}s points=${inside.length} '
        'maxGap=${maxGap.inSeconds}s total=${ride.points.length}',
      );
      // Takt 5 s: mindestens 70 % der möglichen Punkte, keine Lücke über 20 s.
      expect(inside.length, greaterThanOrEqualTo(window.inSeconds * 0.7 ~/ 5));
      expect(maxGap, lessThanOrEqualTo(const Duration(seconds: 20)));

      await tester.tap(stop.first);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
