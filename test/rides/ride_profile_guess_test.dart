// Mit welchem Rad gefahren? (#227) Der Vorschlag aus der Steigrate beim
// GPX-Import: klar Bio, klar E-Bike, und im Zweifel GAR KEINER — ein
// geratener Vorschlag lernte dem falschen Profil eine falsche Steigrate bei.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_profile_guess.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/routing/ride_calibration.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 28, 9);

  /// Ein Aufstieg über [gainM] mit [rateMPerH], alle 10 s ein Punkt, dann
  /// 60 m hinab (beendet den Abschnitt).
  List<RidePoint> climb(double rateMPerH, {double gainM = 300, bool withAlt = true}) {
    final secs = gainM / rateMPerH * 3600;
    final n = (secs / 10).round();
    return [
      for (var i = 0; i <= n + 30; i++)
        RidePoint(
          lat: 47 + i / 10000,
          lng: 11,
          at: t0.add(Duration(seconds: 10 * i)),
          accuracyM: 0,
          altM: !withAlt ? null : (i <= n ? 800 + gainM * i / n : 800 + gainM - 2.0 * (i - n)),
        ),
    ];
  }

  test('die Grenze liegt zwischen den Bezugsraten der Vorgaben', () {
    expect(profileClimbRate(RiderProfile.bio), closeTo(396.9, 0.1));
    expect(profileClimbRate(RiderProfile.ebike), closeTo(743.3, 0.1));
  });

  test('die Steigrate einer Spur ist der Median ihrer Aufstiege', () {
    expect(rideClimbRate(climb(400)), closeTo(400, 20));
  });

  test('klar Bio, klar E-Bike', () {
    expect(guessRideProfile(climb(380)), RiderProfile.bio);
    expect(guessRideProfile(climb(760)), RiderProfile.ebike);
  });

  test('im Zweifel kein Vorschlag: nahe der Grenze, kein Aufstieg, keine Höhen', () {
    // Grenze √(396,9 · 743,3) ≈ 543 Hm/h, ±10 %.
    expect(guessRideProfile(climb(545)), isNull);
    expect(guessRideProfile(climb(400, gainM: 60)), isNull, reason: 'unter 100 Hm am Stück');
    expect(guessRideProfile(climb(760, withAlt: false)), isNull);
    expect(guessRideProfile(const []), isNull);
  });

  test('gelernte Werte verschieben die Grenze', () {
    // 620 Hm/h ist nach den Vorgaben E-Bike — für einen schnellen
    // Bio-Fahrer (700/600 gelernt) aber Bio.
    expect(guessRideProfile(climb(620)), RiderProfile.ebike);
    const fastBio = CalibratedRider(
        RiderProfile.bio, RiderCalibration(climbTrackMPerH: 700, climbPathMPerH: 600, sections: 5));
    expect(guessRideProfile(climb(620), bio: fastBio), RiderProfile.bio);
    // Gelernt schneller als das E-Bike: die Rate unterscheidet nichts mehr.
    const fasterBio = CalibratedRider(
        RiderProfile.bio, RiderCalibration(climbTrackMPerH: 900, climbPathMPerH: 800, sections: 5));
    expect(guessRideProfile(climb(380), bio: fasterBio), isNull);
  });

  test('Raten außerhalb der plausiblen Spanne zählen nicht', () {
    expect(kCalibClimbRange.$2, lessThan(2000));
    expect(guessRideProfile(climb(2000)), isNull);
  });
}
