import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/stall_watch.dart';

/// Der Stall-Wächter (#356 PR 4) mit erfundener Uhr: Was er meldet, ist
/// die Zahl, mit der die Abnahme am Gerät arbeitet.
void main() {
  late List<String> lines;
  late StallMonitor m;
  const ms = 1000; // µs je ms
  setUp(() {
    lines = [];
    m = StallMonitor(log: lines.add);
  });

  test('ein pünktlicher Takt meldet nichts', () {
    for (var t = 0; t <= 1000; t += kStallTickMs) {
      m.tick(t * ms);
    }
    expect(lines, isEmpty);
  });

  test('eine Lücke wird gemeldet, ohne den Takt selbst, mit den Marken darin', () {
    m.tick(0);
    m.tick(16 * ms);
    // Vor der Lücke: kurz, gehört nicht dazu (endete vor dem letzten Takt).
    m.mark('vorher', 2 * ms, 10 * ms);
    // In der Lücke: zwei Schritte, einer davon allein über der Schwelle.
    m.mark('graph.nodes', 20 * ms, 60 * ms);
    m.mark('graph.crossings', 60 * ms, 500 * ms);
    m.tick(516 * ms);
    expect(lines, [
      'TB-STALL graph.crossings 440 ms',
      'TB-STALL gap 484 ms [graph.nodes 40, graph.crossings 440]',
    ]);
  });

  test('knapp unter der Schwelle bleibt still, ab der Schwelle nicht', () {
    m.tick(0);
    m.tick((kStallTickMs + kStallReportMs - 1) * ms);
    expect(lines, isEmpty);
    m.tick((2 * kStallTickMs + 2 * kStallReportMs - 1) * ms);
    expect(lines, ['TB-STALL gap $kStallReportMs ms']);
  });

  test('eine Marke zählt nur für die Lücke, in die sie fiel', () {
    m.tick(0);
    m.mark('alt', 1 * ms, 5 * ms);
    m.tick(16 * ms);
    m.tick(300 * ms);
    expect(lines, ['TB-STALL gap 268 ms']);
  });

  test('ohne Takt (Isolate) bleibt das Gedächtnis gedeckelt, die Meldung kommt trotzdem', () {
    for (var i = 0; i < 500; i++) {
      m.mark('klein', i * ms, i * ms + 1);
    }
    m.mark('groß', 0, 150 * ms);
    expect(lines, ['TB-STALL groß 150 ms']);
  });

  test('ein Schritt mit await wird immer gemeldet', () {
    m.time('plan.loop', 5 * ms, 1845 * ms);
    m.time('route.direct', 0, 3 * ms);
    expect(lines, ['TB-TIME plan.loop 1840 ms', 'TB-TIME route.direct 3 ms']);
  });

  test('ohne Schalter gibt StallWatch nur durch, auch Fehler', () async {
    expect(kStallWatch, isFalse, reason: 'Tests bauen ohne --dart-define=STALL_WATCH');
    expect(StallWatch.mark('x', () => 42), 42);
    expect(await StallWatch.time('y', () async => 'ok'), 'ok');
    expect(() => StallWatch.mark<int>('z', () => throw StateError('kaputt')), throwsStateError);
  });
}
