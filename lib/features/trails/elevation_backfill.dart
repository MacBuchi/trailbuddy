import 'package:latlong2/latlong.dart';

import '../../models/trail.dart';
import 'gpx.dart';
import 'trail_geometry.dart';

/// Höhen nachtragen (Issue #16): Wer eine Datei noch einmal wählt, deren
/// Spur schon als eigene Aufzeichnung auf dem Server liegt, soll keine
/// zweite anlegen — und fehlen der alten die Höhen, bekommt sie sie aus
/// der Datei.
///
/// **Warum Punkte suchen statt neu vereinfachen.** Jeder gespeicherte
/// Punkt ist ein Originalpunkt der Datei (die Vereinfachung wählt aus,
/// sie rechnet nichts Neues). Neu vereinfachen ergäbe dagegen seit 0.3.0
/// eine ANDERE Linie, weil die Vereinfachung seitdem die Höhe mitrechnet.
/// Also werden die gespeicherten Punkte der Reihe nach in der Datei
/// gesucht; fehlt einer, ist es nicht dieselbe Datei. `attach_elevation`
/// prüft dasselbe noch einmal auf dem Server.

/// Toleranz beim Wiederfinden: `st_asgeojson` rundet auf neun Stellen,
/// GPX-Dateien schreiben höchstens acht — 1e-7° (≈ 1 cm) ist also
/// reichlich und trotzdem weit unter jeder echten Abweichung.
const double _tolDeg = 1e-7;

String _key(double lat, double lon) =>
    '${(lat * 1e6).round()},${(lon * 1e6).round()}';

bool _same(TrackPoint p, LatLng v) =>
    (p.lat - v.latitude).abs() <= _tolDeg &&
    (p.lon - v.longitude).abs() <= _tolDeg;

/// Die Punkte der [raw]-Spur, die der Reihe nach auf den [stored] Punkten
/// liegen — oder null, wenn auch nur einer fehlt.
///
/// Anfang und Ende müssen die der Datei sein (die Vereinfachung behält
/// beide): Sonst hielte ein eigenes Teilstück eine längere Datei, die es
/// enthält, für „schon beigesteuert".
List<TrackPoint>? storedLineInTrack(List<LatLng> stored, List<TrackPoint> raw) {
  if (stored.length < 2 || raw.length < 2) return null;
  if (!_same(raw.first, stored.first) || !_same(raw.last, stored.last)) {
    return null;
  }
  final out = <TrackPoint>[];
  var j = 0;
  for (final v in stored) {
    while (j < raw.length && !_same(raw[j], v)) {
      j++;
    }
    if (j == raw.length) return null;
    out.add(raw[j]);
    j++;
  }
  return out;
}

/// Was aus einer Datei-Spur wird, die es schon als eigene Aufzeichnung
/// gibt.
class ExistingRecording {
  const ExistingRecording(this.recording, this.points);

  final TrailRecording recording;

  /// Die Originalpunkte der gespeicherten Linie, aus der Datei.
  final List<TrackPoint> points;

  /// Höhen dieser Punkte, wenn die Datei für jeden eine hat.
  List<double>? get eles => trackElevations(points);

  /// Der Server hat keine Höhen, die Datei schon: nachtragen.
  bool get canBackfill => recording.ele == null && eles != null;
}

/// Sucht unter den eigenen Aufzeichnungen die, deren Linie aus [track]
/// stammt. Vorfilter über Anfangs- und Endpunkt (auf ~10 cm gerastert),
/// damit ein Zip mit dreihundert Dateien gegen hundert Aufzeichnungen
/// nicht jede Paarung ganz durchläuft.
ExistingRecording? findOwnRecording(
  GpxTrack track,
  Iterable<TrailRecording> own,
) {
  final raw = track.points;
  final keys = {for (final p in raw) _key(p.lat, p.lon)};
  for (final r in own) {
    if (r.points.length < 2) continue;
    final a = r.points.first, b = r.points.last;
    if (!keys.contains(_key(a.latitude, a.longitude)) ||
        !keys.contains(_key(b.latitude, b.longitude))) {
      continue;
    }
    final pts = storedLineInTrack(r.points, raw);
    if (pts != null) return ExistingRecording(r, pts);
  }
  return null;
}
