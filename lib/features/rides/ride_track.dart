// Die Fahrt (#28, Konzept 5.1): der aufgezeichnete Weg von Start bis
// Ziel — Haustür bis Haustür. Sie ist ein Bewegungsprofil und verlässt
// das Gerät nie von selbst (Konzept 10, Entscheidung 4; die Sicherung
// ist der GPX-Export von Hand, #150); beigesteuert werden nur
// Ausschnitte, die einen Trail belegen (Zerlege-Blatt, #29).
//
// Alles hier ist rein: Punkte rein, Zahlen raus. Kein Netz, keine
// Platte, keine Provider. Der Baustein ist die Pilztour aus PilzBuddy
// (#338/#342 dort), ohne die Leergang-Logik.
import '../trails/trail_geometry.dart' show haversineM;
import 'ride_confirm.dart' show ConfirmEvent;

/// Ein gemessener Punkt der Fahrt.
class RidePoint {
  const RidePoint({
    required this.lat,
    required this.lng,
    required this.at,
    required this.accuracyM,
    this.altM,
  });

  final double lat;
  final double lng;
  final DateTime at;

  /// Der Streuradius, den das Gerät zu diesem Fix meldet. Mitgeführt,
  /// weil das Zerlege-Blatt (#29) unscharfe Stücke anders behandeln
  /// soll als scharfe — ein 15-m-Korridor gegen einen ±40-m-Fix ist
  /// Rauschen im Gewand einer Messung.
  final double accuracyM;

  /// Die Höhe, die das GPS meldet — ROH mitgeschrieben, nirgends
  /// angezeigt. GPS-Höhen rauschen um Dutzende Meter; ob sie als
  /// Höhenquelle taugen, wird gemessen, bevor eine Zahl daraus wird
  /// (#28: „file elevations stay the source until measured"). Ohne die
  /// Rohdaten gäbe es nichts zu messen.
  final double? altM;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'at': at.toUtc().toIso8601String(),
        'acc': accuracyM,
        if (altM != null) 'alt': altM,
      };

  static RidePoint? fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (lat == null || lng == null || at == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return RidePoint(
      lat: lat,
      lng: lng,
      at: at.toUtc(),
      // Fehlende Genauigkeit heißt „unbrauchbar", nicht „perfekt".
      accuracyM: (json['acc'] as num?)?.toDouble() ?? double.infinity,
      altM: (json['alt'] as num?)?.toDouble(),
    );
  }
}

/// Eine Marke während der Aufnahme (#105, Rework 5.2 und E12): „Trail
/// beginnt" oder „Trail endet", gesetzt per Knopf — wer auf dem Trail
/// steht, weiß genau, wo er anfängt. Die Marke trägt NUR die Zeit: Den
/// Ort sagt die Spur, und das Zerlege-Blatt nimmt den Punkt, der ihr
/// zeitlich am nächsten liegt. Ein eigener Fix beim Tippen wäre eine
/// zweite Messung derselben Stelle, die der Takt ohnehin macht.
enum RideMarkKind { start, end }

class RideMark {
  const RideMark({required this.kind, required this.at});

  final RideMarkKind kind;
  final DateTime at;

  /// Steht als eigene Zeile in der Fahrt-Datei, erkennbar am Schlüssel —
  /// `RidePoint.fromJson` ließe sie ohnehin liegen (keine Koordinate).
  static bool isMark(Map<String, dynamic> json) => json.containsKey('mark');

  Map<String, dynamic> toJson() => {'mark': kind.name, 'at': at.toUtc().toIso8601String()};

  static RideMark? fromJson(Map<String, dynamic> json) {
    final kind = switch (json['mark']) {
      'start' => RideMarkKind.start,
      'end' => RideMarkKind.end,
      _ => null,
    };
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (kind == null || at == null) return null;
    return RideMark(kind: kind, at: at.toUtc());
  }
}

/// Läuft gerade ein markierter Trail? Die letzte Marke ist ein Beginn.
/// Dieselbe Regel für den Knopf (was der nächste Tipp setzt, ob er einen
/// Rand trägt) und das Zerlege-Blatt (offene Marke bis zum Ende).
bool markedTrailOpen(List<RideMark> marks) =>
    marks.isNotEmpty && marks.last.kind == RideMarkKind.start;

/// Die laufende Fahrt: wann sie begann, was seither gemessen und was
/// markiert wurde.
typedef RecordedRide = ({DateTime startedAt, List<RidePoint> points, List<RideMark> marks});

/// Eine abgeschlossene Fahrt auf dem Gerät. [id] ist der Dateiname ohne
/// Endung, abgeleitet aus dem Start — eindeutig genug, zwei Fahrten
/// beginnen nie in derselben Sekunde.
/// Die Quelle einer Fahrt von der Garmin-Uhr (Kopfzeile `source`, #484).
const kRideSourceWatch = 'watch';

class Ride {
  const Ride({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.points,
    this.events = const [],
    this.marks = const [],
    this.profile,
    this.planned = false,
    this.imported = false,
    this.name,
    this.source,
  });

  final String id;
  final DateTime startedAt;

  /// Eine GEPLANTE Fahrt (#158 Schritt 5, Konzept 5.2): die Linie einer
  /// gerechneten Runde oder des Wegs zum Trailkopf, abgelegt in „Meine
  /// Fahrten", damit sie als GPX an die Navi-App geht und auf der Karte
  /// liegt. Keine Messung: [startedAt] ist der Zeitpunkt des Speicherns,
  /// die Punkte tragen keine eigene Zeit und keine Höhe, [endedAt] ist
  /// Start plus geschätzte Dauer. Nicht zerlegbar — beigesteuert wird,
  /// was gefahren wurde, und das ist dann eine eigene Aufzeichnung.
  final bool planned;

  /// Eine aus einer GPX-Datei übernommene Fahrt (#188): gemessen, aber
  /// nicht von dieser App — Zeit und Höhe stammen aus der Datei, eine
  /// Streuung je Punkt gibt es nicht (gespeichert als 0, gelesen wird sie
  /// nicht: [SplitRequest.fromRide] lässt sie weg). Ihre Höhen sind
  /// DATEI-Höhen und gehen beim Zerlegen mit hinaus wie beim Import.
  final bool imported;

  /// Der Name einer geplanten Fahrt („Runde: Hexentanz, Steinbruch") oder
  /// der Spur einer übernommenen Datei.
  final String? name;

  /// Woher eine übernommene Fahrt kam: [kRideSourceWatch] für die eigene
  /// Garmin-Uhr (#484), sonst null (eine GPX-Datei).
  final String? source;

  /// Von der eigenen Uhr aufgezeichnet (#484)?
  bool get fromWatch => source == kRideSourceWatch;

  /// Das Fahrerprofil beim Start (`RiderProfile.name`, Konzept-Routing
  /// 2.1) — die Kalibrierung rechnet je Profil; Fahrten ohne (vor 0.70.0)
  /// lernen nichts. Hier nur ein Name: Die Fahrt kennt die Engine nicht.
  final String? profile;
  final DateTime endedAt;
  final List<RidePoint> points;

  /// Fragen und Antworten während der Fahrt (#116), in der Reihenfolge
  /// der Datei.
  final List<ConfirmEvent> events;

  /// Die Marken „Trail beginnt/endet" (#105), in der Reihenfolge der Datei.
  final List<RideMark> marks;

  Duration get duration => endedAt.difference(startedAt);
  double get lengthM => rideLengthM(points);
}

/// Die Länge einer Spur in Metern — Punkt zu Punkt, dieselbe Formel wie
/// bei den Trails.
double rideLengthM(List<RidePoint> points) {
  var sum = 0.0;
  for (var i = 1; i < points.length; i++) {
    sum += haversineM(points[i - 1].lat, points[i - 1].lng, points[i].lat,
        points[i].lng);
  }
  return sum;
}

/// Wie viele Punkte die Karte höchstens zeichnet.
///
/// Eine Dreistundenfahrt im 5-Sekunden-Takt sind über 2 000 Punkte. Die
/// Grenze greift nur in die ANZEIGE ein: Gespeichert und später zerlegt
/// wird mit allen Punkten.
const kRideTrackMaxDots = 500;

/// Jeder n-te Punkt, damit höchstens [max] übrig bleiben — und der
/// LETZTE ist immer dabei: Er ist die Stelle, an der man gerade steht;
/// fiele er weg, hinkte die Spur sichtbar hinterher.
List<RidePoint> thinnedRide(List<RidePoint> points, {int max = kRideTrackMaxDots}) {
  if (points.length <= max) return points;
  final step = (points.length / max).ceil();
  final kept = <RidePoint>[
    for (var i = 0; i < points.length; i += step) points[i],
  ];
  if (kept.last != points.last) kept.add(points.last);
  return kept;
}

/// „1 h 12 min" bzw. „12 min".
String rideDurationLabel(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  return '$hours h $minutes min';
}
