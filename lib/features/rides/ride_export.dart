// Eine Fahrt als GPX (#150, Konzept 10.4: „Sicherung ist der
// GPX-Export"). Pur: Fahrt rein, Spur raus.
//
// Die ganze Fahrt, Haustür bis Haustür, mit der ROHEN GPS-Höhe als
// `<ele>` und der Zeit je Punkt — das ist die Sicherung, nichts wird
// gestutzt. NICHT hinein gehen die Fragen und Antworten der Fahrt
// (`ConfirmEvent`: Trailnamen und -kennungen) und die Marken: Eine
// Fahrt in einer fremden App ist eine Linie, kein Protokoll.
import '../trails/gpx.dart';
import 'ride_track.dart';

/// „Fahrt 2026-10-01 10:00" — der Name im Dokument, aus der Ortszeit
/// des Starts; ohne `intl`, damit die Datei pur bleibt. Eine geplante
/// Fahrt (#158 Schritt 5) trägt ihren eigenen Namen.
String rideExportName(Ride ride) {
  if (ride.planned && ride.name != null) return ride.name!;
  final d = ride.startedAt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Fahrt ${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Der Dateiname: die Kennung der Fahrt ist schon ein Zeitstempel.
String rideExportFileName(Ride ride) =>
    'trailbuddy-fahrt-${ride.id.toLowerCase()}.gpx';

/// Eine geplante Fahrt geht OHNE Zeiten hinaus: Ihre Punkte tragen nur
/// den Zeitpunkt des Speicherns, und eine Spur mit lauter gleichen Zeiten
/// läse jede App als Stillstand. Ohne Zeiten ist sie, was sie ist — eine
/// geplante Route (Konzept 5.2).
GpxTrack rideToGpx(Ride ride) => GpxTrack(
  name: rideExportName(ride),
  points: [
    for (final p in ride.points)
      TrackPoint(p.lat, p.lng, ele: p.altM, time: ride.planned ? null : p.at),
  ],
);
