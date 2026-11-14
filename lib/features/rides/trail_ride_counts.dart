// Wie oft ich einen Trail gefahren bin (#516 Schritt 5, Konzept-Routing
// 12.4) — pur. Die Vorliebe des Planers rechnet damit.
//
// Quelle sind die Fahrten auf dem Gerät (A3: sie verlassen es nie). Je
// Fahrt wird EINMAL gerechnet, welche Trails sie befährt — nach derselben
// Regel wie „bekannt" im Zerlege-Blatt (`knownTrailSectionsOf`) —, und das
// Ergebnis liegt als kleine Datei neben den Fahrten (`rides/`, kein
// Backup). Eine Planung liest nur diese Datei und rechnet höchstens die
// Fahrten nach, die seit dem letzten Mal dazukamen; gelöschte fallen
// heraus. Kein Feld in der Datenbank, nichts für Buddys.
import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../models/trail.dart';
import 'ride_split.dart' show knownTrailSectionsOf;
import 'ride_track.dart';

/// Die Fassung der Datei. Wer die Regel ändert, nach der eine Fahrt einen
/// Trail befährt, zählt hoch — dann rechnet das Gerät alles neu.
const kTrailRideCountsVersion = 1;

/// Je Fahrt (Kennung) die Kennungen der Trails, die sie befährt.
class TrailRideCounts {
  const TrailRideCounts(this.byRide);

  static const empty = TrailRideCounts({});

  final Map<String, List<String>> byRide;

  /// Unlesbar oder eine andere Fassung ⇒ leer; es wird neu gerechnet.
  factory TrailRideCounts.parse(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['v'] != kTrailRideCountsVersion) return empty;
      final rides = json['rides'];
      if (rides is! Map) return empty;
      return TrailRideCounts({
        for (final e in rides.entries)
          if (e.key is String && e.value is List) e.key as String: [for (final id in e.value as List) if (id is String) id],
      });
    } catch (_) {
      return empty;
    }
  }

  String encode() => jsonEncode({'v': kTrailRideCountsVersion, 'rides': byRide});

  /// In wie vielen Fahrten [t] vorkommt — er selbst oder ein Duplikat,
  /// das bei mir unter ihm steht ([Trail.answersTo]); jede Fahrt einmal.
  int of(Trail t) {
    var n = 0;
    for (final ids in byRide.values) {
      if (ids.any(t.answersTo)) n++;
    }
    return n;
  }

  /// [of] für alle [trails] auf einmal, nur die mit mindestens einer Fahrt.
  Map<String, int> countsFor(Iterable<Trail> trails) => {
        for (final t in trails)
          if (of(t) case final n when n > 0) t.id: n,
      };
}

/// Zählt nur gefahrene Fahrten: keine geplanten (ohne Zeiten, nie
/// gefahren) und keine mit weniger als zwei Punkten.
bool countsAsRidden(Ride r) => !r.planned && r.points.length >= 2;

/// Die Trails, die [ride] befährt (dieselbe Regel wie das Zerlege-Blatt).
List<String> trailsRiddenBy(Ride ride, List<Trail> trails) {
  final latLng = [for (final p in ride.points) LatLng(p.lat, p.lng)];
  return [for (final s in knownTrailSectionsOf(latLng, trails)) s.trail.id];
}

/// Der neue Stand: [old] ohne die Fahrten, die es nicht mehr gibt, plus
/// die neuen aus [rides], gerechnet gegen [trails]. [between] läuft
/// zwischen zwei Fahrten (im UI-Isolate: ein Bild Luft). Null, wenn sich
/// nichts geändert hat.
Future<TrailRideCounts?> updateTrailRideCounts(
  TrailRideCounts old, {
  required List<Ride> rides,
  required List<Trail> trails,
  Future<void> Function()? between,
}) async {
  final ridden = [for (final r in rides) if (countsAsRidden(r)) r];
  final ids = {for (final r in ridden) r.id};
  final next = <String, List<String>>{
    for (final e in old.byRide.entries)
      if (ids.contains(e.key)) e.key: e.value,
  };
  var changed = next.length != old.byRide.length;
  for (final r in ridden) {
    if (next.containsKey(r.id)) continue;
    next[r.id] = trailsRiddenBy(r, trails);
    changed = true;
    if (between != null) await between();
  }
  return changed ? TrailRideCounts(next) : null;
}
