import 'dart:math' as math;

/// Entfernung in Kilometern, eben gerechnet.
///
/// Reicht für alles, was die App vergleicht: Über die paar Dutzend
/// Kilometer zwischen zwei Trails liegt der Fehler gegenüber der
/// Kugelformel weit unter einem Prozent — und auf den wenigen Metern
/// zwischen zwei Punkten einer Aufzeichnung ist die Erdkrümmung ohnehin
/// kein Thema. Der `cos`-Faktor auf die Länge ist der Teil, der wirklich
/// zählt; ohne ihn läge man in Deutschland um rund ein Drittel daneben.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const kmPerDegree = 111.2;
  final dy = (lat1 - lat2) * kmPerDegree;
  final dx =
      (lon1 - lon2) * kmPerDegree * math.cos((lat1 + lat2) / 2 * math.pi / 180);
  return math.sqrt(dx * dx + dy * dy);
}

/// Dieselbe Rechnung in Metern — der Maßstab, in dem Punkte einer
/// Aufzeichnung verglichen werden.
double distanceMeters(double lat1, double lon1, double lat2, double lon2) =>
    distanceKm(lat1, lon1, lat2, lon2) * 1000;

/// Kurswinkel von Punkt 1 nach Punkt 2 in Grad — 0 ist Norden, im
/// Uhrzeigersinn.
///
/// Dieselbe ebene Näherung wie [distanceKm] und aus demselben Grund. Der
/// `cos`-Faktor auf die Länge ist auch hier Pflicht — ohne ihn zeigte
/// „östlich" in Deutschland um rund ein Drittel daneben, und eine
/// Himmelsrichtung, die falsch ist, ist schlimmer als keine.
double bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
  const kmPerDegree = 111.2;
  final dy = (lat2 - lat1) * kmPerDegree;
  final dx =
      (lon2 - lon1) * kmPerDegree * math.cos((lat1 + lat2) / 2 * math.pi / 180);
  final degrees = math.atan2(dx, dy) * 180 / math.pi;
  return (degrees + 360) % 360;
}

/// Die Himmelsrichtung als deutsches Adverb: „nordöstlich".
///
/// ACHT Richtungen und nicht sechzehn: „nordnordöstlich" behauptet eine
/// Auflösung, die ein GPS-Kurswinkel mit ±5 m Streuung nicht hat. Jeder
/// Sektor ist 45° breit, Norden liegt mittig darin — deshalb der halbe
/// Sektor Versatz vor dem Abrunden.
String compassPoint(double bearingDeg) {
  const names = [
    'nördlich',
    'nordöstlich',
    'östlich',
    'südöstlich',
    'südlich',
    'südwestlich',
    'westlich',
    'nordwestlich',
  ];
  final normalized = (bearingDeg % 360 + 360) % 360;
  return names[(((normalized + 22.5) % 360) ~/ 45).toInt()];
}

/// Meter in der Schreibweise, die die App benutzt: „14 m", ab einem
/// Kilometer „1,2 km".
///
/// EIN Helfer statt `${x.round()} m` an fünf Stellen — die Schreibweise
/// (Komma, Leerzeichen vor der Einheit) soll überall dieselbe sein.
String formatMeters(double meters) {
  if (meters.abs() >= 1000) {
    final km = (meters / 100).round() / 10;
    return '${km.toString().replaceAll('.', ',')} km';
  }
  return '${meters.round()} m';
}
