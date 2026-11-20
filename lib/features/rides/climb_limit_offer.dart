// Die Limits wachsen mit dem, was man gefahren ist — auf Nachfrage (#516
// Schritt 6, Konzept-Routing 12.5a). Nach einer AUFGEZEICHNETEN Fahrt,
// deren Anstieg das Höhenmeter-Limit oder deren Länge das Distanz-Limit
// ihres Rads um mindestens einen Schritt übertrifft, schlägt die App EINE
// Zeile vor: anheben oder nicht — beide Limits in derselben Frage, wenn
// beide übertroffen sind (Betreiber, 2026-11-20). Sagt die Steigrate
// deutlich „E-Bike", während die Fahrt als Bio lief, ist DAS die eine
// Frage.
//
// - **Nur nach oben, nur mit Ja**: Hier wird nichts gestellt, nur
//   vorgeschlagen ([climbLimitOfferFor]) und eine Antwort angewandt
//   ([LoopPrefs.withClimb], [LoopPrefs.withDeclined]).
// - **Höchstens eine Frage je Fahrt, und selten**: Ein „Nein" gilt, bis
//   eine Fahrt den abgelehnten Wert um einen weiteren Schritt übertrifft.
// - **Nicht gefragt** wird nach geplanten, aus GPX übernommenen und von der
//   Uhr gekommenen Fahrten (Betreiber, 2026-11-14: Uhr-Fahrten erst
//   einmal nicht), nach Fahrten ohne Rad im Kopf (vor 0.70.0) und ohne
//   Höhen.
//
// Rein: keine Widgets, kein Riverpod, keine Platte.
import 'dart:math' as math;

import '../offline_areas/height_tiles.dart'
    show hysteresisClimb, kClimbHysteresisM;
import '../routing/loop_planner.dart' show LoopPrefs;
import '../routing/route_profile.dart';
import 'ride_profile_guess.dart';
import 'ride_split.dart' show kSplitSmoothWindow, smoothElevation;
import 'ride_track.dart';

/// Ein Schritt des Limits (der Schritt des Reglers): gefragt wird erst ab
/// einem ganzen Schritt über dem Limit, angehoben auf ganze Schritte.
const kClimbLimitStepM = LoopPrefs.climbStep;

/// Ein Schritt des Distanz-Limits, ebenso.
const kDistLimitStepKm = LoopPrefs.distStepKm;

/// Der Anstieg einer Spur in Höhenmetern, gemessen wie im Zerlege-Blatt:
/// GPS-Höhe im gleitenden Median, dann die Hysterese der Trail-Höhen. Null
/// ohne Höhen.
double? rideClimbM(List<RidePoint> pts) {
  if (pts.length < 2 || pts.any((p) => p.altM == null)) return null;
  final smooth = smoothElevation([
    for (final p in pts) p.altM!,
  ], kSplitSmoothWindow);
  return hysteresisClimb(smooth, kClimbHysteresisM).$1;
}

/// Der Vorschlag nach einer Fahrt.
class ClimbLimitOffer {
  const ClimbLimitOffer({
    required this.rideId,
    required this.bike,
    required this.climbM,
    required this.toM,
    this.askEbike = false,
    this.distKm = 0,
    this.toKm,
  });

  final String rideId;

  /// Das Rad im Kopf der Fahrt.
  final RiderProfile bike;

  /// Der Anstieg der Fahrt, auf einen Schritt abgerundet.
  final double climbM;

  /// Das neue Höhenmeter-Limit fürs [bike]: [climbM], höchstens das Ende
  /// des Reglers; null, wenn die Fahrt es nicht übertraf.
  final double? toM;

  /// Als Bio aufgezeichnet, die Steigrate sagt deutlich E-Bike: Die eine
  /// Frage ist dann „War es eins?" (12.5a). Nur mit [toM].
  final bool askEbike;

  /// Die Länge der Fahrt in km, auf einen Schritt abgerundet.
  final double distKm;

  /// Das neue Distanz-Limit fürs [bike]; null, wenn die Fahrt es nicht
  /// übertraf.
  final double? toKm;

  /// Für `Settings.climbLimitPending` — wer das Blatt schließt, ohne zu
  /// antworten, findet dieselbe Zeile einmal im Einstieg des Planers. Bis
  /// 0.194 fünf Felder (nur Höhenmeter), seither sieben.
  String encode() =>
      '$rideId|${bike.name}|$climbM|${toM ?? ''}|${askEbike ? 1 : 0}'
      '|$distKm|${toKm ?? ''}';

  static ClimbLimitOffer? parse(String? raw) {
    final f = raw?.split('|');
    if (f == null || (f.length != 5 && f.length != 7)) return null;
    final climb = double.tryParse(f[2]), to = double.tryParse(f[3]);
    final dist = f.length == 7 ? double.tryParse(f[5]) : 0.0;
    final toKm = f.length == 7 ? double.tryParse(f[6]) : null;
    if (f[0].isEmpty || climb == null || dist == null) return null;
    if (to == null && toKm == null) return null;
    final bike = RiderProfile.values.where((p) => p.name == f[1]).firstOrNull;
    if (bike == null) return null;
    return ClimbLimitOffer(
      rideId: f[0],
      bike: bike,
      climbM: climb,
      toM: to,
      askEbike: to != null && f[4] == '1',
      distKm: dist,
      toKm: toKm,
    );
  }
}

/// Lohnt eine Frage für [bike] bei [climbM] (abgerundet)? Über dem Limit um
/// einen Schritt, über einem „Nein" ebenso, und das Limit kann noch steigen.
bool climbLimitExceeded(LoopPrefs prefs, RiderProfile bike, double climbM) {
  final limit = prefs.climbOf(bike);
  if (limit >= LoopPrefs.maxClimb) return false;
  if (climbM < limit + kClimbLimitStepM) return false;
  final declined = prefs.declinedOf(bike);
  return declined == null || climbM >= declined + kClimbLimitStepM;
}

/// Dasselbe für das Distanz-Limit, mit [distKm] (abgerundet).
bool distLimitExceeded(LoopPrefs prefs, RiderProfile bike, double distKm) {
  final limit = prefs.distOf(bike);
  if (limit >= LoopPrefs.maxDistKm) return false;
  if (distKm < limit + kDistLimitStepKm) return false;
  final declined = prefs.declinedDistOf(bike);
  return declined == null || distKm >= declined + kDistLimitStepKm;
}

/// Lohnt die Frage [offer] noch, nach den Limits in [prefs]? (Die gemerkte
/// Frage im Einstieg — das Limit kann inzwischen darüber stehen.)
bool limitOfferStands(LoopPrefs prefs, ClimbLimitOffer offer) =>
    (offer.toM != null &&
        climbLimitExceeded(prefs, offer.bike, offer.climbM)) ||
    (offer.toKm != null && distLimitExceeded(prefs, offer.bike, offer.distKm));

/// Der Vorschlag nach [ride], oder null. [bio] und [ebike] sind die
/// Profile, mit denen geplant wird (gelernt, wo gelernt ist) — dieselben
/// wie beim Vorschlag des Rads im Import (`guessRideProfile`, #227).
ClimbLimitOffer? climbLimitOfferFor(
  Ride ride,
  LoopPrefs prefs, {
  RiderParams bio = RiderProfile.bio,
  RiderParams ebike = RiderProfile.ebike,
}) {
  if (ride.planned || ride.imported || ride.fromWatch) return null;
  final bike = RiderProfile.values
      .where((p) => p.name == ride.profile)
      .firstOrNull;
  if (bike == null) return null;
  // Ohne Höhen fragt nur die Distanz.
  final raw = rideClimbM(ride.points);
  final climb = raw == null
      ? 0.0
      : (raw / kClimbLimitStepM).floorToDouble() * kClimbLimitStepM;
  final dist =
      (ride.lengthM / 1000 / kDistLimitStepKm).floorToDouble() *
      kDistLimitStepKm;
  final overClimb = raw != null && climbLimitExceeded(prefs, bike, climb);
  final overDist = distLimitExceeded(prefs, bike, dist);
  if (!overClimb && !overDist) return null;
  final askEbike =
      overClimb &&
      bike == RiderProfile.bio &&
      guessRideProfile(ride.points, bio: bio, ebike: ebike) ==
          RiderProfile.ebike;
  return ClimbLimitOffer(
    rideId: ride.id,
    bike: bike,
    climbM: climb,
    toM: overClimb ? math.min(climb, LoopPrefs.maxClimb) : null,
    askEbike: askEbike,
    distKm: dist,
    toKm: overDist ? math.min(dist, LoopPrefs.maxDistKm) : null,
  );
}

/// Was eine Antwort bewirkt hat — für die Zeile danach und „Rückgängig".
class ClimbLimitAnswer {
  const ClimbLimitAnswer({
    required this.before,
    required this.after,
    this.raisedBike,
    this.movedToEbike = false,
  });

  /// Die Limits vor und nach der Antwort (Rückgängig stellt [before] her).
  final LoopPrefs before, after;

  /// Das Rad, dessen Limit stieg, oder null.
  final RiderProfile? raisedBike;

  /// „War ein E-Bike": Die Fahrt ist umgeordnet.
  final bool movedToEbike;
}

/// „Anheben" (oder „Nein, Bio-Bike" bei der E-Frage — die Antwort war die
/// Bestätigung, 12.5a): jedes übertroffene Limit fürs Rad auf seinen neuen
/// Wert ([ClimbLimitOffer.toM], [ClimbLimitOffer.toKm]), ein altes „Nein"
/// dazu ist erledigt.
ClimbLimitAnswer raiseClimbLimit(LoopPrefs prefs, ClimbLimitOffer offer) {
  var after = prefs;
  if (offer.toM case final m?) {
    after = after.withClimb(offer.bike, m).withDeclined(offer.bike, null);
  }
  if (offer.toKm case final km?) {
    after = after.withDist(offer.bike, km).withDeclinedDist(offer.bike, null);
  }
  return ClimbLimitAnswer(before: prefs, after: after, raisedBike: offer.bike);
}

/// „Nein": gemerkt, bis eine Fahrt den Wert um einen Schritt übertrifft —
/// je Limit, nach dem gefragt war.
ClimbLimitAnswer declineClimbLimit(LoopPrefs prefs, ClimbLimitOffer offer) {
  var after = prefs;
  if (offer.toM != null) after = after.withDeclined(offer.bike, offer.climbM);
  if (offer.toKm != null) {
    after = after.withDeclinedDist(offer.bike, offer.distKm);
  }
  return ClimbLimitAnswer(before: prefs, after: after);
}

/// „Ja, E-Bike": Die Fahrt wird umgeordnet (das macht der Aufrufer), und
/// verglichen wird mit den E-Limits — übertrifft sie eines, hebt das Ja es
/// an, ohne zweite Frage.
ClimbLimitAnswer ebikeClimbLimit(LoopPrefs prefs, ClimbLimitOffer offer) {
  const e = RiderProfile.ebike;
  final overClimb = climbLimitExceeded(prefs, e, offer.climbM);
  final overDist = distLimitExceeded(prefs, e, offer.distKm);
  if (!overClimb && !overDist) {
    return ClimbLimitAnswer(before: prefs, after: prefs, movedToEbike: true);
  }
  var after = prefs;
  if (overClimb) {
    after = after
        .withClimb(e, math.min(offer.climbM, LoopPrefs.maxClimb))
        .withDeclined(e, null);
  }
  if (overDist) {
    after = after
        .withDist(e, math.min(offer.distKm, LoopPrefs.maxDistKm))
        .withDeclinedDist(e, null);
  }
  return ClimbLimitAnswer(
    before: prefs,
    after: after,
    raisedBike: e,
    movedToEbike: true,
  );
}
