// Das Limit aus Fahrten (#516 Schritt 6, Konzept-Routing 12.5a): ein Limit
// je Rad, eine Frage nur über dem Limit (und über einem „Nein") um einen
// Schritt, nie nach geplanten, übernommenen oder Uhr-Fahrten, und die
// E-Frage, wenn die Steigrate deutlich E-Bike sagt.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/climb_limit_offer.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 14, 9);
  const bio = RiderProfile.bio, ebike = RiderProfile.ebike;

  /// Ein Anstieg über [gainM] mit [rateMPerH], alle 10 s ein Punkt, dann
  /// 60 m hinab — dieselbe Spur wie im Test des Rad-Vorschlags.
  List<RidePoint> climb(double gainM, double rateMPerH, {bool withAlt = true}) {
    final n = (gainM / rateMPerH * 3600 / 10).round();
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

  Ride ride(List<RidePoint> pts,
          {String? profile = 'bio', bool planned = false, bool imported = false, String? source}) =>
      Ride(
        id: 'r1',
        startedAt: pts.first.at,
        endedAt: pts.last.at,
        points: pts,
        profile: profile,
        planned: planned,
        imported: imported,
        source: source,
      );

  group('ein Limit je Rad', () {
    test('Vorgaben je Rad, der Radwechsel holt das andere', () {
      final d = LoopPrefs.defaults(bio);
      expect(d.climbM, 800);
      expect(d.withBike(ebike).climbM, 1400);
      final set = d.copyWith(climbM: 1000);
      expect(set.climbBioM, 1000);
      expect(set.withBike(ebike).climbM, 1400, reason: 'das E-Bike behält seins');
      expect(set.withBike(ebike).withBike(bio).climbM, 1000);
    });

    test('ein altes c gilt fürs gewählte Rad, das andere beginnt mit der Vorgabe', () {
      final asBio = LoopPrefs.parse('h=3.0;c=1000.0;w=1.0;r=1', bio);
      expect((asBio.climbBioM, asBio.climbEbikeM), (1000, 1400));
      final asE = LoopPrefs.parse('h=3.0;c=1000.0;w=1.0;r=1', ebike);
      expect((asE.climbBioM, asE.climbEbikeM), (800, 1000));
    });

    test('kodiert und gelesen bleibt alles, auch ein Nein; c für ältere Apps', () {
      final p = LoopPrefs.defaults(bio)
          .withClimb(bio, 1100)
          .withClimb(ebike, 1600)
          .withDeclined(ebike, 1800)
          .withBike(ebike);
      final raw = p.encode();
      expect(raw, contains('c=1600.0'));
      final back = LoopPrefs.parse(raw, bio);
      expect((back.climbBioM, back.climbEbikeM), (1100, 1600));
      expect((back.declinedBioM, back.declinedEbikeM), (null, 1800));
      expect(back.climbM, 1100, reason: 'das Rad kommt aus dem Lesen');
      expect(back.withDeclined(ebike, null).declinedEbikeM, isNull);
    });

    test('Rückgängig nimmt nur Limits und Nein zurück', () {
      final before = LoopPrefs.defaults(bio);
      final after = before.withClimb(bio, 1200).withDeclined(ebike, 1500).copyWith(hours: 4);
      final undone = after.withLimitsOf(before);
      expect((undone.climbBioM, undone.declinedEbikeM, undone.hours), (800, null, 4));
    });
  });

  group('der Anstieg der Fahrt', () {
    test('gemessen über die geglättete GPS-Höhe, ohne Höhen nichts', () {
      expect(rideClimbM(climb(1150, 400)), closeTo(1150, 15));
      expect(rideClimbM(climb(1150, 400, withAlt: false)), isNull);
    });
  });

  group('die Frage', () {
    test('ab einem Schritt über dem Limit, abgerundet auf 100 hm', () {
      final prefs = LoopPrefs.defaults(bio);
      expect(climbLimitOfferFor(ride(climb(850, 400)), prefs), isNull, reason: 'nur 50 hm über 800');
      final offer = climbLimitOfferFor(ride(climb(1150, 400)), prefs)!;
      expect((offer.bike, offer.climbM, offer.toM, offer.askEbike), (bio, 1100, 1100, false));
    });

    test('das Rad der Fahrt zählt, nicht das gewählte', () {
      final prefs = LoopPrefs.defaults(bio);
      expect(climbLimitOfferFor(ride(climb(1150, 800), profile: 'ebike'), prefs), isNull,
          reason: 'unter dem E-Limit 1 400');
      final offer = climbLimitOfferFor(ride(climb(1550, 800), profile: 'ebike'), prefs)!;
      expect((offer.bike, offer.climbM), (ebike, 1500));
    });

    test('nie nach geplanten, übernommenen, Uhr-Fahrten und ohne Rad', () {
      final prefs = LoopPrefs.defaults(bio);
      final pts = climb(1150, 400);
      expect(climbLimitOfferFor(ride(pts, planned: true), prefs), isNull);
      expect(climbLimitOfferFor(ride(pts, imported: true), prefs), isNull);
      expect(climbLimitOfferFor(ride(pts, source: kRideSourceWatch), prefs), isNull);
      expect(climbLimitOfferFor(ride(pts, profile: null), prefs), isNull);
    });

    test('ein Nein gilt, bis eine Fahrt es um einen Schritt übertrifft', () {
      final prefs = declineClimbLimit(LoopPrefs.defaults(bio), climbLimitOfferFor(ride(climb(1150, 400)), LoopPrefs.defaults(bio))!).after;
      expect(prefs.declinedBioM, 1100);
      expect(climbLimitOfferFor(ride(climb(1150, 400)), prefs), isNull);
      expect(climbLimitOfferFor(ride(climb(1180, 400)), prefs), isNull, reason: 'noch 1 100');
      expect(climbLimitOfferFor(ride(climb(1250, 400)), prefs)!.climbM, 1200);
    });

    test('am Ende des Reglers keine Frage, darüber bis zum Ende', () {
      final top = LoopPrefs.defaults(bio).withClimb(bio, LoopPrefs.maxClimb);
      expect(climbLimitOfferFor(ride(climb(2900, 400)), top), isNull);
      final offer = climbLimitOfferFor(ride(climb(2950, 400)), LoopPrefs.defaults(bio))!;
      expect((offer.climbM, offer.toM), (2900, LoopPrefs.maxClimb));
    });

    test('als Bio gefahren, die Steigrate sagt E-Bike: die E-Frage', () {
      final prefs = LoopPrefs.defaults(bio);
      expect(climbLimitOfferFor(ride(climb(1150, 900)), prefs)!.askEbike, isTrue);
      expect(climbLimitOfferFor(ride(climb(1150, 380)), prefs)!.askEbike, isFalse);
      expect(climbLimitOfferFor(ride(climb(1550, 900), profile: 'ebike'), prefs)!.askEbike, isFalse);
    });

    test('kodiert für den Einstieg des Planers', () {
      const o = ClimbLimitOffer(rideId: 'x-1', bike: ebike, climbM: 1500, toM: 1500, askEbike: true);
      final back = ClimbLimitOffer.parse(o.encode())!;
      expect((back.rideId, back.bike, back.climbM, back.toM, back.askEbike), ('x-1', ebike, 1500, 1500, true));
      expect(ClimbLimitOffer.parse('kaputt'), isNull);
      expect(ClimbLimitOffer.parse(null), isNull);
    });
  });

  group('die Antworten', () {
    const offer = ClimbLimitOffer(rideId: 'r1', bike: bio, climbM: 1100, toM: 1100, askEbike: true);

    test('Anheben hebt das Limit des Rads und vergisst ein altes Nein', () {
      final prefs = LoopPrefs.defaults(bio).withDeclined(bio, 1000);
      final a = raiseClimbLimit(prefs, offer);
      expect((a.after.climbBioM, a.after.declinedBioM, a.after.climbEbikeM, a.raisedBike), (1100, null, 1400, bio));
    });

    test('Ja, E-Bike: unter dem E-Limit nur umgeordnet, darüber angehoben', () {
      final a = ebikeClimbLimit(LoopPrefs.defaults(bio), offer);
      expect((a.movedToEbike, a.raisedBike, a.after.climbEbikeM), (true, null, 1400));
      const big = ClimbLimitOffer(rideId: 'r1', bike: bio, climbM: 1600, toM: 1600, askEbike: true);
      final b = ebikeClimbLimit(LoopPrefs.defaults(bio), big);
      expect((b.movedToEbike, b.raisedBike, b.after.climbEbikeM, b.after.climbBioM), (true, ebike, 1600, 800));
    });
  });
}
