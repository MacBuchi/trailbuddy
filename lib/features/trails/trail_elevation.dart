import 'package:latlong2/latlong.dart';

import '../offline_areas/height_tiles.dart' show hysteresisClimb, kClimbHysteresisM, kClimbSampleM;
import 'trail_geometry.dart' as geo;

/// Das Höhenprofil eines Trails, in TRAIL-Richtung (Konzept 4.3): Eine
/// Aufzeichnung, die gegen die Richtung gefahren wurde, wird umgedreht —
/// sonst stünde an einem Downhill „↑ 420 Hm", weil ein Buddy ihn
/// hochgeschoben hat.
///
/// Alles hier ist aus Punkten und Höhen GERECHNET, nichts gespeichert:
/// Jeder, der dieselbe Aufzeichnung sieht, bekommt dieselben Zahlen
/// (Konzept 3, „Länge, Höhenmeter, mittleres Gefälle").
class ElevationProfile {
  ElevationProfile._(this.distM, this.eleM, {this.fromTerrain = false})
      : assert(distM.length == eleM.length && distM.length >= 2);

  /// Null, wenn Höhen fehlen, nicht zur Linie passen oder die Linie
  /// keine Länge hat — lieber kein Profil als ein erfundenes.
  static ElevationProfile? of(List<LatLng> points, List<double>? ele,
      {bool reversed = false}) {
    if (ele == null || ele.length != points.length || points.length < 2) {
      return null;
    }
    final pts = reversed ? points.reversed.toList() : points;
    final e = reversed ? ele.reversed.toList() : List.of(ele);
    final dist = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      dist.add(dist.last +
          geo.haversineM(pts[i - 1].latitude, pts[i - 1].longitude,
              pts[i].latitude, pts[i].longitude));
    }
    if (dist.last <= 0) return null;
    return ElevationProfile._(dist, e);
  }

  /// Aus dem Geländemodell (#186): Höhen der Höhenkacheln an Proben alle
  /// [kClimbSampleM] Meter entlang der Linie in Trail-Richtung. Anstieg
  /// und Abstieg mit derselben Abtastung und Hysterese wie gemessen (M3,
  /// `climb_along` im Werkzeug) — nicht mit den 3 m aufgezeichneter
  /// Höhen. Ein steilstes Stück gibt es nicht: Ein 90-m-Raster kennt
  /// keine 50 m.
  static ElevationProfile? terrain(List<LatLng> samples, List<double> ele) {
    final p = of(samples, ele);
    if (p == null) return null;
    return ElevationProfile._(p.distM, p.eleM, fromTerrain: true);
  }

  /// Distanz ab Start in Metern, je Punkt.
  final List<double> distM;

  /// Höhe in Metern, je Punkt.
  final List<double> eleM;

  /// Gelesen aus den Höhenkacheln, nicht aufgezeichnet (#186): nur für die
  /// Anzeige, nie gespeichert — und das Blatt sagt es.
  final bool fromTerrain;

  double get lengthM => distM.last;

  /// Die Höhe [alongM] Meter ab Start, zwischen zwei Punkten linear;
  /// außerhalb auf Start oder Ziel geklemmt.
  double eleAt(double alongM) {
    if (alongM <= 0) return eleM.first;
    if (alongM >= lengthM) return eleM.last;
    var lo = 0, hi = distM.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (distM[mid] <= alongM) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final seg = distM[hi] - distM[lo];
    final t = seg <= 0 ? 0.0 : (alongM - distM[lo]) / seg;
    return eleM[lo] + (eleM[hi] - eleM[lo]) * t;
  }
  double get startM => eleM.first;
  double get endM => eleM.last;
  double get minM => eleM.reduce((a, b) => a < b ? a : b);
  double get maxM => eleM.reduce((a, b) => a > b ? a : b);

  late final ({double gain, double loss}) _gl = fromTerrain
      ? (() {
          final (gain, loss) = hysteresisClimb(eleM, kClimbHysteresisM);
          return (gain: gain, loss: loss);
        })()
      : geo.gainLoss(eleM, geo.kElevationThresholdM);

  /// Höhenmeter bergauf (mit Hysterese, [geo.kElevationThresholdM]).
  double get gainM => _gl.gain;

  /// Höhenmeter bergab.
  double get lossM => _gl.loss;

  /// Mittleres Gefälle in Prozent von Start bis Ziel; positiv heißt
  /// bergab. Nettowert, deshalb unabhängig von jeder Schwelle.
  double get meanDescentPct => (startM - endM) / lengthM * 100;

  /// Steilstes Stück über [geo.kSteepestWindowM]; null bei kürzeren
  /// Trails.
  late final double? steepestDescentPct =
      fromTerrain ? null : geo.steepestDescentPct(distM, eleM);
}
