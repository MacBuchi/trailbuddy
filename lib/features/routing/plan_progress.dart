// Der Ladebalken des Planers (#356, Betreiber 2026-10-18: „Wenn es einen
// Ladebalken gibt, ist eine längere Berechnungsdauer ok"). Gemessen am
// Pixel baut der Graph ~0,33 s je Kachel und rechnet eine Runde mit
// vielen Trails über eine Minute (docs/routing-messung.md) — ohne
// Fortschritt sieht das aus wie ein Hänger.
//
// Wie der Stall-Wächter ein statischer Melder JE ISOLATE: Bau und Suche
// sind reine Funktionen tief unten (`road_graph.dart`, `loop_planner.dart`),
// eine Rückmeldung durch jede Signatur wäre viel Naht für eine Zahl. Nur
// wer [PlanProgress.run] ruft (der Rechen-Isolate des Planers, im Browser
// der Inline-Runner), bekommt Meldungen; sonst ist jeder Aufruf ein
// Vergleich mit null.
//
// Rein: kein Flutter, kein `dart:isolate` — der Bau läuft auch im Browser.

/// Meldet den Fortschritt einer Rechnung als Anteil 0…1.
abstract final class PlanProgress {
  static void Function(double value)? _sink;
  static double _from = 0, _to = 1, _last = -1;

  /// Unter dieser Änderung meldet er nichts — ein Prozent, damit das
  /// Senden zwischen den Isolates nie selbst zur Last wird.
  static const step = 0.01;

  /// Es hört jemand zu — für Schleifen, die nur dann zählen sollen.
  static bool get active => _sink != null;

  /// Rechnet [f] und schickt den Fortschritt an [sink], monoton und in
  /// Schritten von mindestens [step]; am Ende einmal 1.
  static T run<T>(void Function(double value) sink, T Function() f) {
    final saved = (_sink, _from, _to, _last);
    _sink = sink;
    _from = 0;
    _to = 1;
    _last = -1;
    try {
      final r = f();
      _send(1);
      return r;
    } finally {
      _sink = saved.$1;
      _from = saved.$2;
      _to = saved.$3;
      _last = saved.$4;
    }
  }

  /// [f] ist der Abschnitt [from]…[to] des laufenden Abschnitts; was
  /// [f] meldet, gilt darin.
  static T part<T>(double from, double to, T Function() f) {
    if (_sink == null) return f();
    final a = _from, b = _to;
    _from = a + (b - a) * from;
    _to = a + (b - a) * to;
    try {
      return f();
    } finally {
      _send(_to);
      _from = a;
      _to = b;
    }
  }

  /// Im laufenden Abschnitt ist der Anteil [fraction] geschafft.
  static void report(double fraction) {
    if (_sink == null) return;
    _send(_from + (_to - _from) * fraction.clamp(0.0, 1.0));
  }

  /// Im laufenden Abschnitt sind [done] von [total] Schritten geschafft.
  static void steps(int done, int total) {
    if (_sink == null || total <= 0) return;
    report(done / total);
  }

  static void _send(double v) {
    final sink = _sink;
    if (sink == null || v < _last + step && v < 1) return;
    if (v <= _last) return;
    _last = v;
    sink(v);
  }
}
