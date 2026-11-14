// Das Limit wächst mit dem, was man gefahren ist — auf Nachfrage (#516
// Schritt 6, Konzept-Routing 12.5a). Nach einer AUFGEZEICHNETEN Fahrt,
// deren Anstieg das Höhenmeter-Limit ihres Rads um mindestens einen
// Schritt übertrifft, schlägt die App EINE Zeile vor: anheben oder nicht.
// Sagt die Steigrate deutlich „E-Bike", während die Fahrt als Bio lief,
// ist DAS die eine Frage.
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
import '../offline_areas/height_tiles.dart' show hysteresisClimb, kClimbHysteresisM;
import '../routing/loop_planner.dart' show LoopPrefs;
import '../routing/route_profile.dart';
import 'ride_profile_guess.dart';
import 'ride_split.dart' show kSplitSmoothWindow, smoothElevation;
import 'ride_track.dart';

/// Ein Schritt des Limits (der Schritt des Reglers): gefragt wird erst ab
/// einem ganzen Schritt über dem Limit, angehoben auf ganze Schritte.
const kClimbLimitStepM = LoopPrefs.climbStep;

/// Der Anstieg einer Spur in Höhenmetern, gemessen wie im Zerlege-Blatt:
/// GPS-Höhe im gleitenden Median, dann die Hysterese der Trail-Höhen. Null
/// ohne Höhen.
double? rideClimbM(List<RidePoint> pts) {
  if (pts.length < 2 || pts.any((p) => p.altM == null)) return null;
  final smooth = smoothElevation([for (final p in pts) p.altM!], kSplitSmoothWindow);
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
  });

  final String rideId;

  /// Das Rad im Kopf der Fahrt.
  final RiderProfile bike;

  /// Der Anstieg der Fahrt, auf einen Schritt abgerundet.
  final double climbM;

  /// Das neue Limit fürs [bike]: [climbM], höchstens das Ende des Reglers.
  final double toM;

  /// Als Bio aufgezeichnet, die Steigrate sagt deutlich E-Bike: Die eine
  /// Frage ist dann „War es eins?" (12.5a).
  final bool askEbike;

  /// Für `Settings.climbLimitPending` — wer das Blatt schließt, ohne zu
  /// antworten, findet dieselbe Zeile einmal im Einstieg des Planers.
  String encode() => '$rideId|${bike.name}|$climbM|$toM|${askEbike ? 1 : 0}';

  static ClimbLimitOffer? parse(String? raw) {
    final f = raw?.split('|');
    if (f == null || f.length != 5) return null;
    final climb = double.tryParse(f[2]), to = double.tryParse(f[3]);
    if (f[0].isEmpty || climb == null || to == null) return null;
    final bike = RiderProfile.values.where((p) => p.name == f[1]).firstOrNull;
    if (bike == null) return null;
    return ClimbLimitOffer(rideId: f[0], bike: bike, climbM: climb, toM: to, askEbike: f[4] == '1');
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

/// Der Vorschlag nach [ride], oder null. [bio] und [ebike] sind die
/// Profile, mit denen geplant wird (gelernt, wo gelernt ist) — dieselben
/// wie beim Vorschlag des Rads im Import (`guessRideProfile`, #227).
ClimbLimitOffer? climbLimitOfferFor(Ride ride, LoopPrefs prefs,
    {RiderParams bio = RiderProfile.bio, RiderParams ebike = RiderProfile.ebike}) {
  if (ride.planned || ride.imported || ride.fromWatch) return null;
  final bike = RiderProfile.values.where((p) => p.name == ride.profile).firstOrNull;
  if (bike == null) return null;
  final raw = rideClimbM(ride.points);
  if (raw == null) return null;
  final climb = (raw / kClimbLimitStepM).floorToDouble() * kClimbLimitStepM;
  if (!climbLimitExceeded(prefs, bike, climb)) return null;
  final askEbike = bike == RiderProfile.bio && guessRideProfile(ride.points, bio: bio, ebike: ebike) == RiderProfile.ebike;
  return ClimbLimitOffer(
    rideId: ride.id,
    bike: bike,
    climbM: climb,
    toM: climb > LoopPrefs.maxClimb ? LoopPrefs.maxClimb : climb,
    askEbike: askEbike,
  );
}

/// Was eine Antwort bewirkt hat — für die Zeile danach und „Rückgängig".
class ClimbLimitAnswer {
  const ClimbLimitAnswer({required this.before, required this.after, this.raisedBike, this.movedToEbike = false});

  /// Die Limits vor und nach der Antwort (Rückgängig stellt [before] her).
  final LoopPrefs before, after;

  /// Das Rad, dessen Limit stieg, oder null.
  final RiderProfile? raisedBike;

  /// „War ein E-Bike": Die Fahrt ist umgeordnet.
  final bool movedToEbike;
}

/// „Anheben" (oder „Nein, Bio-Bike" bei der E-Frage — die Antwort war die
/// Bestätigung, 12.5a): das Limit fürs Rad auf [ClimbLimitOffer.toM], ein
/// altes „Nein" ist erledigt.
ClimbLimitAnswer raiseClimbLimit(LoopPrefs prefs, ClimbLimitOffer offer) {
  final after = prefs.withClimb(offer.bike, offer.toM).withDeclined(offer.bike, null);
  return ClimbLimitAnswer(before: prefs, after: after, raisedBike: offer.bike);
}

/// „Nein": gemerkt, bis eine Fahrt den Wert um einen Schritt übertrifft.
ClimbLimitAnswer declineClimbLimit(LoopPrefs prefs, ClimbLimitOffer offer) =>
    ClimbLimitAnswer(before: prefs, after: prefs.withDeclined(offer.bike, offer.climbM));

/// „Ja, E-Bike": Die Fahrt wird umgeordnet (das macht der Aufrufer), und
/// verglichen wird mit dem E-Limit — übertrifft sie es, hebt das Ja es an,
/// ohne zweite Frage.
ClimbLimitAnswer ebikeClimbLimit(LoopPrefs prefs, ClimbLimitOffer offer) {
  const e = RiderProfile.ebike;
  if (!climbLimitExceeded(prefs, e, offer.climbM)) {
    return ClimbLimitAnswer(before: prefs, after: prefs, movedToEbike: true);
  }
  final to = offer.climbM > LoopPrefs.maxClimb ? LoopPrefs.maxClimb : offer.climbM;
  return ClimbLimitAnswer(
    before: prefs,
    after: prefs.withClimb(e, to).withDeclined(e, null),
    raisedBike: e,
    movedToEbike: true,
  );
}
