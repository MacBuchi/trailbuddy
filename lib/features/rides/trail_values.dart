// Trail-Werte in der App (#36, Konzept Airtime 9 Schritt 5): was die
// Erkennung (`sensor_fusion.dart`) auf einem Stück der Fahrt gefunden hat —
// Airtime, Max G, Wheelies und Stoppies (Stoppies seit dem Betreiber
// 2026-10-31, experimentell). Alles bleibt auf dem Gerät; geteilt wird
// erst mit Schritt 6.
//
// Drei Dinge, die man wissen muss:
// - **Die Quelle ist eine kleine Datei je Fahrt**, `rides/sensors/<id>.events.csv`,
//   mit denselben Zeilen wie die Rohdaten (`e`, `j`, `s` und die Antworten
//   `l`, `k`, `p`) — die Rohdaten selbst sind ~30 MB je Stunde und taugen
//   nicht zum Lesen je Blatt. Der Logger schreibt sie im Dienst, die
//   Antwort aus Banner oder Fenster hängt dort ebenfalls an.
// - **„War keiner" zählt nicht**, die letzte Antwort gilt (wie im
//   Werkzeug). Unbeantwortet zählt — die meisten Ereignisse beantwortet
//   niemand.
// - **Ein Sprung zählt nur plausibel** (Tempo davor und danach, Spitze
//   unter 8 g, Rad aufrecht; Konzept 2); Max G ist die Spitze dieser
//   Landungen, über 40 ms gemittelt.
import '../../l10n/l10n.dart';
import 'sensor_fusion.dart';

/// Die Ereignisse einer Fahrt und die Antworten darauf.
class AirtimeLog {
  const AirtimeLog({this.events = const [], this.rejected = const {}});

  static const empty = AirtimeLog();

  final List<FusionEvent> events;

  /// Mit „War keiner" beantwortet: [airtimeEventKey].
  final Set<String> rejected;

  /// Was zählt.
  Iterable<FusionEvent> get kept => events.where((e) => !rejected.contains(airtimeEventKey(e)));

  bool get isEmpty => events.isEmpty;

  /// Mit [event] dazu; dasselbe Ereignis zweimal bleibt eines.
  AirtimeLog withEvent(FusionEvent event) {
    final key = airtimeEventKey(event);
    if (events.any((e) => airtimeEventKey(e) == key)) return this;
    return AirtimeLog(events: [...events, event], rejected: rejected);
  }

  /// Eine Antwort; „Stimmt" nach „War keiner" nimmt es zurück.
  AirtimeLog withAnswer(FusionEvent event, {required bool yes}) {
    final key = airtimeEventKey(event);
    return AirtimeLog(
        events: events, rejected: yes ? ({...rejected}..remove(key)) : {...rejected, key});
  }

  /// Zusammen mit [other] (Datei und Kanal): Ereignisse beider, die
  /// Antworten von [other] zuletzt.
  AirtimeLog merge(AirtimeLog other) {
    var out = this;
    for (final e in other.events) {
      out = out.withEvent(e);
    }
    return AirtimeLog(events: out.events, rejected: {...rejected, ...other.rejected});
  }
}

/// Art und Beginn — so findet eine Antwort ihr Ereignis.
String airtimeEventKey(FusionEvent e) => '${_kind(e)}${e.startUs}';

String _kind(FusionEvent e) => switch (e) {
      WheelieEvent() => 'w',
      JumpEvent() => 'j',
      StoppieEvent() => 's',
    };

/// Liest die Zeilen der Ereignis-Datei. Unlesbare Zeilen fallen einzeln
/// weg — die letzte kann nach einem Prozess-Kill halb sein.
AirtimeLog parseAirtimeLog(String text) {
  final events = <FusionEvent>[];
  final seen = <String>{};
  final answers = <String, bool>{};
  for (final line in text.split('\n')) {
    final f = line.trim().split(',');
    if (f.length < 2) continue;
    try {
      double n(int i) => double.parse(f[i]);
      int us(int i) => int.parse(f[i]);
      Duration d(int i) => Duration(microseconds: (n(i) * 1e6).round());
      final FusionEvent? event = switch (f.first) {
        'e' when f.length >= 5 => WheelieEvent(startUs: us(1), duration: d(2), lengthM: n(3), maxTiltDeg: n(4)),
        'j' when f.length >= 5 => JumpEvent(
            startUs: us(1), duration: d(2), landingG: n(3), upright: true, plausible: f[4] == '1'),
        's' when f.length >= 6 =>
          StoppieEvent(startUs: us(1), duration: d(2), maxTiltDeg: n(3), decel: n(4), landingG: n(5)),
        _ => null,
      };
      if (event != null) {
        if (seen.add(airtimeEventKey(event))) events.add(event);
        continue;
      }
      final kind = switch (f.first) { 'l' => 'w', 'k' => 'j', 'p' => 's', _ => null };
      if (kind != null && f.length >= 4) answers['$kind${us(2)}'] = f[3] == '1';
    } catch (_) {
      continue;
    }
  }
  return AirtimeLog(events: events, rejected: {
    for (final e in answers.entries)
      if (!e.value) e.key,
  });
}

/// Was auf einem Stück zählt.
class TrailValues {
  const TrailValues({
    this.jumps = 0,
    this.airS = 0,
    this.longestJumpS = 0,
    this.maxG,
    this.wheelies = 0,
    this.longestWheelieM = 0,
    this.stoppies = 0,
    this.longestStoppieS = 0,
    this.steepestStoppieDeg = 0,
  });

  /// Plausible Sprünge, ihre Summe und der längste (s).
  final int jumps;
  final double airS;
  final double longestJumpS;

  /// Die härteste plausible Landung (g); null ohne Sprung.
  final double? maxG;

  final int wheelies;
  final double longestWheelieM;

  final int stoppies;
  final double longestStoppieS;
  final double steepestStoppieDeg;

  bool get isEmpty => jumps == 0 && wheelies == 0 && stoppies == 0;

  /// Die Ereignisse, die zwischen [fromUs] und [toUs] beginnen (beide
  /// eingeschlossen, µs seit 1970 — die Achse der Sensoren und der Fixe).
  static TrailValues of(Iterable<FusionEvent> events, {int? fromUs, int? toUs}) {
    var jumps = 0, wheelies = 0, stoppies = 0;
    var air = 0.0, longestJump = 0.0, longestWheelie = 0.0, longestStoppie = 0.0, steepest = 0.0;
    double? maxG;
    for (final e in events) {
      if (fromUs != null && e.startUs < fromUs) continue;
      if (toUs != null && e.startUs > toUs) continue;
      final s = e.duration.inMicroseconds / 1e6;
      switch (e) {
        case JumpEvent(:final plausible, :final landingG):
          if (!plausible) continue;
          jumps++;
          air += s;
          if (s > longestJump) longestJump = s;
          if (maxG == null || landingG > maxG) maxG = landingG;
        case WheelieEvent(:final lengthM):
          wheelies++;
          if (lengthM > longestWheelie) longestWheelie = lengthM;
        case StoppieEvent(:final maxTiltDeg):
          stoppies++;
          if (s > longestStoppie) longestStoppie = s;
          if (maxTiltDeg > steepest) steepest = maxTiltDeg;
      }
    }
    return TrailValues(
      jumps: jumps,
      airS: air,
      longestJumpS: longestJump,
      maxG: maxG,
      wheelies: wheelies,
      longestWheelieM: longestWheelie,
      stoppies: stoppies,
      longestStoppieS: longestStoppie,
      steepestStoppieDeg: steepest,
    );
  }
}

/// Eine Zahl in der Sprache der Oberfläche.
String airtimeNumber(AppLocalizations l, double v, int digits) {
  final text = v.toStringAsFixed(digits);
  return l.localeName.startsWith('de') ? text.replaceAll('.', ',') : text;
}

/// „Air 2,4 s (3) · 3,1 G · Wheelie 2 (7 m) · Stoppie 1" — nur, was es
/// gab; null, wenn nichts.
String? trailValuesLine(AppLocalizations l, TrailValues v) {
  if (v.isEmpty) return null;
  return [
    if (v.jumps > 0) l.airValuesAir(airtimeNumber(l, v.airS, 1), v.jumps),
    if (v.maxG case final g?) l.airValuesG(airtimeNumber(l, g, 1)),
    if (v.wheelies > 0) l.airValuesWheelie(v.wheelies, airtimeNumber(l, v.longestWheelieM, 0)),
    if (v.stoppies > 0) l.airValuesStoppie(v.stoppies),
  ].join(' · ');
}
