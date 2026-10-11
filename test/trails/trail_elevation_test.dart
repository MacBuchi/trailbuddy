// Höhenmeter, Gefälle und Profil (Issue #14). Die Vektoren der Hysterese
// stehen wortgleich in tool/elevation_measure.py (VECTORS) — Werkzeug und
// App müssen dieselbe Zahl sagen, sonst misst das Werkzeug eine Regel, die
// die App nicht hat.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/elevation_profile_chart.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/trail_elevation.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/features/trails/trail_sheet.dart';

import '../fakes/l10n_de.dart';

const _vectors = <(List<double>, double, double, double)>[
  ([100, 101, 100, 101, 100, 90], 0, 2, 12),
  ([100, 101, 100, 101, 100, 90], 2, 0, 10),
  ([100, 98, 104, 95, 96, 80], 3, 4, 24),
  ([100, 104, 108, 104, 100], 5, 8, 8),
  ([100, 102, 104], 5, 4, 0),
];

/// [n] Punkte nach Norden, 10 m Abstand.
List<LatLng> north(int n) =>
    [for (var i = 0; i < n; i++) LatLng(48.0 + i * 10 / 111195.0, 9.0)];

void main() {
  test('Hysterese: dieselben Vektoren wie tool/elevation_measure.py', () {
    for (final (ele, h, gain, loss) in _vectors) {
      final got = gainLoss(ele, h);
      expect((got.gain, got.loss), (gain, loss), reason: '$ele bei $h m');
      expect(got.loss - got.gain, closeTo(ele.first - ele.last, 1e-9),
          reason: 'das Nettogefälle hängt nie an der Schwelle');
    }
  });

  test('Rauschen auf einem Downhill zählt nicht als Anstieg', () {
    // ±2,4 m Zickzack auf ~80 m Gefälle: jede Welle steigt 2,8 m, knapp
    // unter der Schwelle — roh rund 55 m „bergauf", mit der Schwelle
    // keiner. (Endet auf einem Tal, sonst bucht der Rest am Ende die
    // letzte halbe Welle als Anstieg.)
    final ele = [for (var i = 0; i < 40; i++) 600 - i * 2.0 + (i.isEven ? 2.4 : -2.4)];
    expect(gainLoss(ele, 0).gain, greaterThan(20));
    expect(gainLoss(ele, kElevationThresholdM).gain, 0);
  });

  test('Höhen nur, wenn jeder Punkt eine plausible hat', () {
    expect(trackElevations(const [TrackPoint(48, 9, ele: 500), TrackPoint(48.1, 9, ele: 490)]),
        [500, 490]);
    expect(trackElevations(const [TrackPoint(48, 9, ele: 500), TrackPoint(48.1, 9)]), isNull);
    // Manche Geräte schreiben „keine Höhe" als −32768 — dann lieber ohne
    // Höhen beisteuern als an der RPC scheitern.
    expect(trackElevations(const [TrackPoint(48, 9, ele: 500), TrackPoint(48.1, 9, ele: -32768)]),
        isNull);
  });

  test('Vereinfachung behält eine Welle auf gerader Linie', () {
    // Wie im Selbsttest des Werkzeugs: 100 m gerade, 10 m bergab, in der
    // Mitte 15 m über der Geraden.
    final pts = [
      for (var i = 0; i <= 10; i++)
        TrackPoint(48.0 + i * 10 / 111195.0, 9.0, ele: i == 5 ? 110 : 100.0 - i),
    ];
    final flat = simplify(pts.map((p) => TrackPoint(p.lat, p.lon)).toList());
    expect(flat.length, 2, reason: 'ohne Höhen zählt nur die Geometrie');
    final kept = simplify(pts);
    expect(kept.map((p) => pts.indexOf(p)), [0, 4, 5, 6, 10],
        reason: 'dieselben Indizes wie simplify_3d im Werkzeug');
    expect(gainLoss(trackElevations(kept)!, 3).gain, greaterThanOrEqualTo(13));
  });

  test('Profil in Trail-Richtung: umgedreht tauschen Anstieg und Abstieg', () {
    final pts = north(21);
    final ele = [for (var i = 0; i <= 20; i++) 500.0 + i * 5]; // 100 m bergauf
    final up = ElevationProfile.of(pts, ele)!;
    expect(up.gainM, 100);
    expect(up.lossM, 0);
    expect(up.meanDescentPct, closeTo(-50, 0.5));
    final down = ElevationProfile.of(pts, ele, reversed: true)!;
    expect(down.gainM, 0);
    expect(down.lossM, 100);
    expect(down.startM, 600);
    expect(down.meanDescentPct, closeTo(50, 0.5));
    expect(down.steepestDescentPct, closeTo(50, 0.5));
    expect(down.lengthM, closeTo(200, 1));
  });

  test('kein Profil ohne passende Höhen', () {
    expect(ElevationProfile.of(north(3), null), isNull);
    expect(ElevationProfile.of(north(3), [1, 2]), isNull);
    expect(ElevationProfile.of([const LatLng(48, 9), const LatLng(48, 9)], [1, 2]), isNull);
  });

  test('steilstes Stück erst ab 50 m', () {
    expect(steepestDescentPct([0, 50, 100, 150], [100, 95, 80, 78], windowM: 100), 20);
    expect(steepestDescentPct([0, 30], [100, 90]), isNull);
  });

  test('Anzeige: bergab zuerst, eben statt Null mit Vorzeichen', () {
    expect(formatElevation(l10nDe, (gain: 35.4, loss: 419.6)), '↓ 420 Hm · ↑ 35 Hm');
    expect(formatMeanGrade(l10nDe, 14.2), 'Ø 14 % Gefälle');
    expect(formatMeanGrade(l10nDe, -3.4), 'Ø 3 % Steigung');
    expect(formatMeanGrade(l10nDe, 0.3), 'Ø eben');
  });

  test('flacher Verbinder wird nicht zur Steilwand gestreckt', () {
    final p = ElevationProfile.of(north(3), [500, 502, 504])!;
    final pts = ElevationProfilePainter(p,
            line: Colors.green, fill: Colors.green, grid: Colors.grey)
        .pointsFor(const Size(200, 100));
    expect(pts.first.dx, 0);
    expect(pts.last.dx, closeTo(200, 1e-6));
    // 4 m Spanne auf mindestens 20 m gestreckt: 20 % der Höhe, mittig.
    expect(pts.first.dy - pts.last.dy, closeTo(20, 1e-6));
    expect(pts[1].dy, closeTo(50, 1e-6));
  });
}
