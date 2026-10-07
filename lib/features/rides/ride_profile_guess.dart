// Mit welchem Rad gefahren? (#227) Ein Vorschlag aus der Steigrate, wenn
// Fahrten aus GPX-Dateien kommen: Wer zwanzig alte Fahrten übernimmt, hat
// oft Bio- und E-Bike gemischt, und eine falsch eingeordnete Fahrt lernt
// dem falschen Profil eine falsche Steigrate bei (`ride_calibrator.dart`).
//
// Gemessen wird wie bei der Kalibrierung — dieselben Aufstiege
// (`ascentSections`, ab 100 Hm am Stück, über fünf Minuten, Rate in der
// plausiblen Spanne) —, aber OHNE Wegegraph: Der Vorschlag soll auch ohne
// gespeicherten Bereich gehen, und er lernt nichts, er belegt nur vor.
// Verglichen wird der Median der Raten mit einer Bezugsrate je Profil,
// √(Forstweg · Pfad) aus den gelernten oder den Vorgabewerten; die Grenze
// liegt im geometrischen Mittel der beiden.
//
// **Im Zweifel kein Vorschlag**: kein Aufstieg, keine Höhen oder ein
// Median in [kProfileGuessBand] um die Grenze ⇒ `null`, und es gilt, was
// der Nutzer gewählt hat. Ein geratener Vorschlag, der wie eine Messung
// aussieht, wäre schlimmer als keiner.
//
// Rein: keine Widgets, kein Riverpod, keine Platte.
import 'dart:math' as math;

import '../routing/ride_calibration.dart';
import '../routing/route_profile.dart';
import 'ride_track.dart';

/// So nah (als Anteil) an der Grenze zwischen den Profilen gibt es keinen
/// Vorschlag.
const kProfileGuessBand = 0.10;

/// Die Bezugsrate eines Profils in Hm/h: das geometrische Mittel aus
/// Forstweg und Pfad — eine Fahrt ohne Wegegraph mischt beides.
double profileClimbRate(RiderParams p) => math.sqrt(p.climbTrackMPerH * p.climbPathMPerH);

/// Der Median der Steigraten (Hm/h) aller Aufstiege der Spur, oder null.
double? rideClimbRate(List<RidePoint> pts) {
  if (pts.length < kCalibWindow) return null;
  final ele = [for (final p in pts) p.altM];
  if (ele.any((e) => e == null)) return null;
  final rates = <double>[];
  for (final s in ascentSections(ele.cast<double>())) {
    final secs = pts[s.top].at.difference(pts[s.start].at).inSeconds.toDouble();
    if (secs <= kCalibMinSectionS) continue;
    final rate = s.gainM / (secs / 3600);
    if (rate < kCalibClimbRange.$1 || rate > kCalibClimbRange.$2) continue;
    rates.add(rate);
  }
  if (rates.isEmpty) return null;
  rates.sort();
  final m = rates.length ~/ 2;
  return rates.length.isOdd ? rates[m] : (rates[m - 1] + rates[m]) / 2;
}

/// Bio oder E-Bike nach der Steigrate, oder null (siehe oben). [bio] und
/// [ebike] sind die Profile, mit denen die Planer rechnen — gelernt, wo
/// gelernt ist; so verschiebt sich die Grenze mit dem Fahrer.
RiderProfile? guessRideProfile(List<RidePoint> pts,
    {RiderParams bio = RiderProfile.bio, RiderParams ebike = RiderProfile.ebike}) {
  final rate = rideClimbRate(pts);
  if (rate == null) return null;
  final b = profileClimbRate(bio), e = profileClimbRate(ebike);
  // Hat das Lernen die Profile vertauscht (Bio schneller als E), trägt die
  // Steigrate keine Unterscheidung mehr.
  if (!(e > b)) return null;
  final border = math.sqrt(b * e);
  if ((rate - border).abs() <= border * kProfileGuessBand) return null;
  return rate > border ? RiderProfile.ebike : RiderProfile.bio;
}
