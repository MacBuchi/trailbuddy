// Fahrten aus GPX-Dateien übernehmen (#188): Wer vor TrailBuddy mit einer
// anderen App aufgezeichnet hat, legt diese Fahrten in „Meine Fahrten" ab
// — mit dem Profil, mit dem er sie gefahren ist. Dann lernt das
// Fahrerprofil aus ihnen (`ride_calibrator.dart`), sie lassen sich
// zerlegen und wieder exportieren wie jede eigene Aufzeichnung.
//
// Rein: Spur rein, Punkte raus. Kein Netz, keine Platte.
import 'ride_track.dart';
import '../trails/gpx.dart';

/// Die Punkte einer Datei als Fahrt: nur Punkte mit Zeit (ohne Zeit gibt
/// es keine Geschwindigkeit und keine Steigrate), mit der Höhe der Datei.
/// Eine Streuung kennt die Datei nicht; 0 steht dort wie bei der
/// geplanten Fahrt und wird für übernommene Fahrten nie gelesen.
List<RidePoint> ridePointsOf(GpxTrack track) => [
      for (final p in track.points)
        if (p.time case final at?)
          RidePoint(lat: p.lat, lng: p.lon, at: at.toUtc(), accuracyM: 0, altM: p.ele),
    ];

/// Liegt diese Fahrt schon auf dem Gerät? Dieselbe Startsekunde wie eine
/// gemessene Fahrt — auch eine eigene Aufzeichnung, die als GPX
/// exportiert und wieder gewählt wurde (ihr erster Punkt ist derselbe).
bool rideOnDevice(List<RidePoint> points, List<Ride> rides) {
  if (points.isEmpty) return false;
  final first = points.first.at;
  return rides.any((r) =>
      !r.planned &&
      r.points.isNotEmpty &&
      r.points.first.at.difference(first).inMilliseconds.abs() < 1000);
}

/// Hat das Handy für die Zeit von [points] schon eine eigene Fahrt (#484,
/// Betreiber 2026-11-07: „Uhr nimmt immer auf, Handy prüft")? Eine
/// gemessene Fahrt — Aufzeichnung oder übernommene Datei, keine geplante
/// —, die mindestens [share] der Zeitspanne deckt. Dann ist die Spur der
/// Uhr doppelt und wird nicht abgelegt.
bool rideOverlaps(List<RidePoint> points, List<Ride> rides, {double share = 0.5}) {
  if (points.length < 2) return false;
  final a = points.first.at, b = points.last.at;
  final span = b.difference(a).inMilliseconds;
  if (span <= 0) return false;
  for (final r in rides) {
    if (r.planned || r.points.length < 2) continue;
    final ra = r.points.first.at, rb = r.points.last.at;
    final from = ra.isAfter(a) ? ra : a;
    final to = rb.isBefore(b) ? rb : b;
    final overlap = to.difference(from).inMilliseconds;
    if (overlap >= share * span) return true;
  }
  return false;
}
