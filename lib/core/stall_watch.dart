import 'dart:async';
import 'dart:developer' as developer;

/// Der Stall-Wächter (#356 PR 4, Konzept-Routing 10.7): misst auf dem
/// Gerät, wie lange der UI-Isolate steht — auf Android seit Flutter 3.29
/// der Haupt-Thread, ab 5 s ein ANR (#354).
///
/// Aus, solange nicht mit `--dart-define=STALL_WATCH=true` gebaut wird;
/// dann ist jeder Aufruf hier eine Konstante, die der Compiler wegwirft,
/// bis auf die Timeline-Marken (die gibt es im Release-Build ohnehin nicht).
/// Gebaut wird damit die Dev-App (`android/CLAUDE.md`); gelesen wird im
/// Logcat (`adb logcat -s flutter | grep TB-`):
///
/// - `TB-STALL gap 812 ms [graph.crossings 790]` — so lange kam der Takt
///   nicht dran, dahinter die Marken, die in die Lücke fielen.
/// - `TB-STALL graph.crossings 790 ms` — eine Marke allein über der
///   Schwelle, auch wenn sie in einem Isolate lief (dort steht keine
///   Oberfläche, aber die Rechnung ist trotzdem zu lang).
/// - `TB-TIME plan.loop 1840 ms` — Dauer eines ganzen Schritts mit
///   `await`, für die Budgets aus Konzept-Routing 10.7.
const kStallWatch = bool.fromEnvironment('STALL_WATCH');

/// Ab hier meldet der Wächter eine Lücke oder Marke. Die Hälfte des
/// Budgets „längster Block ≤ 200 ms", damit auch knappe Fälle auftauchen.
const kStallReportMs = 100;

/// So oft schaut der Takt nach (ein Bild bei 60 Hz).
const kStallTickMs = 16;

/// Eine Marke im Gedächtnis des Wächters, Zeiten in µs seit seinem Start.
typedef StallMark = ({String name, int startUs, int endUs});

/// Der rechnende Teil, ohne Timer und ohne Ausgabe — so lässt er sich im
/// Test mit einer erfundenen Uhr fahren.
class StallMonitor {
  StallMonitor({required this.log, this.reportMs = kStallReportMs, this.tickMs = kStallTickMs});

  final void Function(String line) log;
  final int reportMs;
  final int tickMs;

  final _marks = <StallMark>[];
  int? _lastTickUs;

  /// Eine Marke ist fertig. Über der Schwelle gleich gemeldet; behalten
  /// für die Zuordnung der nächsten Lücke.
  void mark(String name, int startUs, int endUs) {
    final ms = (endUs - startUs) ~/ 1000;
    if (ms >= reportMs) log('TB-STALL $name $ms ms');
    _marks.add((name: name, startUs: startUs, endUs: endUs));
    // Nur die Marken seit dem letzten Takt zählen für die Lücke; ein
    // Deckel hält das Gedächtnis klein, falls der Takt nie kommt (Isolate).
    if (_marks.length > 64) _marks.removeRange(0, _marks.length - 64);
  }

  /// Der Takt kam dran. Lag der letzte zu weit zurück, stand der Isolate.
  void tick(int nowUs) {
    final last = _lastTickUs;
    _lastTickUs = nowUs;
    if (last == null) return;
    final gapMs = (nowUs - last) ~/ 1000 - tickMs;
    if (gapMs >= reportMs) {
      final inside = [
        for (final m in _marks)
          if (m.endUs > last && m.startUs < nowUs) '${m.name} ${(m.endUs - m.startUs) ~/ 1000}',
      ];
      log('TB-STALL gap $gapMs ms${inside.isEmpty ? '' : ' [${inside.join(', ')}]'}');
    }
    _marks.removeWhere((m) => m.endUs <= nowUs);
  }

  /// Ein Schritt mit `await` ist fertig — immer gemeldet, er ist eine
  /// Zahl für die Budgets, kein Befund.
  void time(String name, int startUs, int endUs) => log('TB-TIME $name ${(endUs - startUs) ~/ 1000} ms');
}

/// Der Wächter dieses Isolates. Jeder Isolate hat seinen eigenen (Dart
/// teilt keine statischen Felder); der Takt läuft nur, wo [start] gerufen
/// wurde — im UI-Isolate aus `main`.
abstract final class StallWatch {
  static final _clock = Stopwatch()..start();
  static final _monitor = StallMonitor(log: (line) {
    // Logcat-Tag `flutter`; `print` statt `debugPrint`, das im Release
    // drosseln kann und hier kein Flutter braucht (auch im Isolate).
    // ignore: avoid_print
    print(line);
  });
  static Timer? _timer;

  /// Den Takt im UI-Isolate anwerfen. Ohne [kStallWatch] nichts.
  static void start() {
    if (!kStallWatch || _timer != null) return;
    _monitor.tick(_clock.elapsedMicroseconds);
    _timer = Timer.periodic(const Duration(milliseconds: kStallTickMs), (_) {
      _monitor.tick(_clock.elapsedMicroseconds);
    });
  }

  /// [f] als benannter Block: eine Timeline-Marke (sichtbar in DevTools
  /// eines Profile-Builds) und mit [kStallWatch] eine Zeile, wenn er zu
  /// lange dauert. Nur für Synchrones — wer `await`, nimmt [time].
  static T mark<T>(String name, T Function() f) {
    if (!kStallWatch) return developer.Timeline.timeSync(name, f);
    final start = _clock.elapsedMicroseconds;
    try {
      return developer.Timeline.timeSync(name, f);
    } finally {
      _monitor.mark(name, start, _clock.elapsedMicroseconds);
    }
  }

  /// [f] als benannter Schritt mit `await`; mit [kStallWatch] immer eine
  /// Zeile `TB-TIME`, auch wenn er wirft.
  static Future<T> time<T>(String name, Future<T> Function() f) async {
    if (!kStallWatch) return f();
    final start = _clock.elapsedMicroseconds;
    try {
      return await f();
    } finally {
      _monitor.time(name, start, _clock.elapsedMicroseconds);
    }
  }
}
