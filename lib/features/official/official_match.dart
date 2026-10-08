import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/line_geometry.dart';
import 'official_trails.dart';

/// „Auch ausgeschildert als …" (#13, Schritt 4): Deckt ein Trail des
/// Netzes eine offizielle Linie? Gerechnet auf dem Gerät mit der Deckung
/// des Abgleichs — Korridor und Anteil wie `contribute_recording` und
/// `tool/trail_match.py` (`DEFAULT_D`, `DEFAULT_COV`, `STEP`); ändern sich
/// die Schwellen dort, ändern sie sich hier im selben PR. Die Rechnung
/// selbst (Projektion, Abtastung, Gitter) liegt in `core/line_geometry.dart`,
/// geteilt mit dem Zerlege-Blatt (#29).
///
/// Bewusst OHNE Fréchet: Es wird nichts verschmolzen, nur ein Satz im
/// Blatt gezeigt, und beide Linien sieht der Nutzer auf der Karte. Über
/// Netzgrenzen geht nichts (Konzept 12) — die offiziellen Linien sind
/// öffentlich, der Trail ist einer, den der Nutzer ohnehin sieht.
const kOfficialCorridorM = kMatchCorridorM;
const kOfficialCoverage = kMatchCoverage;
const kOfficialSampleStepM = kMatchSampleStepM;

/// Ab so viel gedeckter Länge liegt ein gesperrter Abschnitt AUF dem Trail
/// (#41) — die Mindestlänge eines Trails im Abgleich (Patch 017). Ein
/// Queren deckt im 15-m-Korridor höchstens rund 30 m; ein kurzer
/// gesperrter Abschnitt zählt trotzdem, wenn ihn der Trail zu 0,8 deckt.
const kOfficialClosedMinM = 50.0;

enum OfficialOverlap {
  /// Beide decken einander: derselbe Trail.
  same,

  /// Der Trail des Netzes liegt auf einem Stück des offiziellen.
  partOf,

  /// Der offizielle liegt ganz auf dem (längeren) Trail des Netzes.
  contains,
}

/// [onClosed]: Ein gesperrter Abschnitt des offiziellen Trails liegt auf
/// der Linie (#41). Bei „teilweise gesperrt" ist das die eigentliche
/// Frage — die gesperrte Variante kann auch woanders liegen.
typedef OfficialMatch = ({OfficialTrail trail, OfficialOverlap overlap, bool onClosed});

/// Die offiziellen Trails, die [line] deckt, „derselbe" zuerst.
///
/// Die Hauptroute zählt für die Rückrichtung, Varianten nicht: Wer die
/// Hauptroute fährt, fährt den ausgeschilderten Trail, auch wenn er die
/// Varianten auslässt. Für die Hinrichtung zählt jeder Teil — wer eine
/// Variante fährt, ist trotzdem auf dem offiziellen Trail.
List<OfficialMatch> matchOfficial(List<LatLng> line, Iterable<OfficialTrail> candidates) {
  if (line.length < 2) return const [];
  final proj = FlatProjection.around(line);
  final lineBox = LatBox.of(line);
  final lineXy = [for (final p in line) proj.xy(p)];
  final lineSamples = resampleXy(lineXy, kOfficialSampleStepM);
  SegmentGrid? lineGrid;

  final out = <OfficialMatch>[];
  for (final t in candidates) {
    final all = [for (final s in t.sections) ...s.points];
    if (!lineBox.near(LatBox.of(all), kOfficialCorridorM)) continue;
    final sectionsXy = [
      for (final s in t.sections) [for (final p in s.points) proj.xy(p)],
    ];
    final there = SegmentGrid(sectionsXy, kOfficialCorridorM);
    final ab = coverageWithin(lineSamples, there, kOfficialCorridorM);
    final main = [
      for (var i = 0; i < t.sections.length; i++)
        if (!t.sections[i].variant) sectionsXy[i],
    ];
    lineGrid ??= SegmentGrid([lineXy], kOfficialCorridorM);
    final mainSamples = [
      for (final s in main.isEmpty ? sectionsXy : main)
        ...resampleXy(s, kOfficialSampleStepM),
    ];
    final ba = coverageWithin(mainSamples, lineGrid, kOfficialCorridorM);
    final overlap = switch ((ab >= kOfficialCoverage, ba >= kOfficialCoverage)) {
      (true, true) => OfficialOverlap.same,
      (true, false) => OfficialOverlap.partOf,
      (false, true) => OfficialOverlap.contains,
      _ => null,
    };
    if (overlap == null) continue;
    var onClosed = false;
    for (var i = 0; i < t.sections.length && !onClosed; i++) {
      if (!t.sections[i].closed) continue;
      final samples = resampleXy(sectionsXy[i], kOfficialSampleStepM);
      final share = coverageWithin(samples, lineGrid, kOfficialCorridorM);
      onClosed = share >= kOfficialCoverage ||
          share * _lengthXy(sectionsXy[i]) >= kOfficialClosedMinM;
    }
    out.add((trail: t, overlap: overlap, onClosed: onClosed));
  }
  out.sort((a, b) => a.overlap.index.compareTo(b.overlap.index));
  return out;
}

double _lengthXy(List<math.Point<double>> xy) {
  var m = 0.0;
  for (var i = 1; i < xy.length; i++) {
    m += xy[i].distanceTo(xy[i - 1]);
  }
  return m;
}
