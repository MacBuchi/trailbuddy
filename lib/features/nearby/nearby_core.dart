// Buddy in der Nähe (#526, E8; docs/konzept-geraete.md 6.1) — der reine
// Kern ohne Netz und ohne Widgets: Zelle, Nachbarschaft, wann gemeldet
// wird und dass jeder Buddy je Fahrt nur einmal kommt.
//
// **Eine Zelle, nie eine Position.** Hinaus geht nur `"<zeile>:<spalte>"`
// eines Rasters von rund 5 km. In der Nähe heißt: dieselbe oder eine
// Nachbarzelle (Mittelpunkte höchstens [kNearbyNearMeters] auseinander) —
// zwei Fahrer 200 m auseinander in verschiedenen Zellen sind damit
// weiter „in der Nähe", zwei 12 km auseinander nicht.
import 'dart:math' as math;

import '../../core/geo.dart';

/// Kantenlänge der Zelle in Grad Breite — rund 5 km (Betreiber 2026-11-11:
/// „5 km Umkreis?").
const kNearbyCellDeg = 0.045;

/// Mittelpunkte höchstens so weit auseinander ⇒ in der Nähe. Deckt die
/// acht Nachbarn ab (Kante 5 km, Ecke 7,1 km), die übernächste nicht.
const kNearbyNearMeters = 7600.0;

/// Um „Zuhause" und um den Start einer Aufzeichnung meldet sich die App
/// nie (A3: nicht ab der Haustür; Betreiber 2026-11-18: 1 km).
const kNearbyQuietMeters = 1000.0;

/// Eine Zelle des Rasters. Die Spaltenbreite hängt von der Zeile ab, damit
/// jede Zelle ungefähr quadratisch ist — deshalb vergleicht [isNearTo]
/// Mittelpunkte und nicht Indizes.
class NearbyCell {
  const NearbyCell(this.row, this.col);

  final int row;
  final int col;

  factory NearbyCell.of(double lat, double lon) {
    final row = (lat / kNearbyCellDeg).floor();
    final col = (lon / _width(row)).floor();
    return NearbyCell(row, col);
  }

  /// `"12:34"` zurück in eine Zelle; alles andere ist null — eine fremde
  /// Nutzlast darf nie werfen.
  static NearbyCell? tryParse(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final row = int.tryParse(parts[0]);
    final col = int.tryParse(parts[1]);
    if (row == null || col == null) return null;
    if (row.abs() > 90 / kNearbyCellDeg + 1) return null;
    return NearbyCell(row, col);
  }

  static double _width(int row) {
    final centerLat = (row + 0.5) * kNearbyCellDeg;
    final c = math.cos(centerLat * math.pi / 180).abs();
    return kNearbyCellDeg / math.max(c, 0.01);
  }

  double get centerLat => (row + 0.5) * kNearbyCellDeg;

  double get centerLon => (col + 0.5) * _width(row);

  bool isNearTo(NearbyCell other) =>
      distanceMeters(centerLat, centerLon, other.centerLat, other.centerLon) <=
      kNearbyNearMeters;

  String encode() => '$row:$col';

  @override
  bool operator ==(Object other) => other is NearbyCell && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'NearbyCell(${encode()})';
}

/// Warum gerade NICHT geteilt wird — für die Zeile im Profil und die Tests.
enum NearbyPause {
  /// Schalter „Buddys unterwegs" aus (oder nie beantwortet).
  off,

  /// Keine Position (Standort aus, keine Berechtigung, noch kein Fix).
  noPosition,

  /// Im Umkreis von „Zuhause".
  home,

  /// Aufzeichnung läuft, aber noch keinen Kilometer vom Start.
  nearStart,

  /// Ohne Aufzeichnung nur im Vordergrund (6.1: kein eigener Dienst).
  background,

  /// Ohne Aufzeichnung nur, wenn „Zuhause" gesetzt ist — sonst wüsste die
  /// App nicht, wo die Haustür liegt.
  noHome,
}

/// Eine Stelle auf dem Gerät (Zuhause, Start, Position).
typedef NearbyPoint = ({double lat, double lon});

NearbyPoint? parseNearbyHome(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0]);
  final lon = double.tryParse(parts[1]);
  if (lat == null || lon == null) return null;
  return (lat: lat, lon: lon);
}

String encodeNearbyHome(NearbyPoint p) =>
    '${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}';

double _dist(NearbyPoint a, NearbyPoint b) => distanceMeters(a.lat, a.lon, b.lat, b.lon);

/// Darf jetzt geteilt (und gehört) werden? null heißt ja; sonst der Grund,
/// warum nicht. Die Reihenfolge ist die Reihenfolge der Antwort im Profil.
NearbyPause? nearbyPause({
  required bool? enabled,
  required NearbyPoint? position,
  required NearbyPoint? home,
  required NearbyPoint? rideStart,
  required bool foreground,
}) {
  if (enabled != true) return NearbyPause.off;
  if (position == null) return NearbyPause.noPosition;
  if (home != null && _dist(position, home) < kNearbyQuietMeters) return NearbyPause.home;
  if (rideStart != null) {
    return _dist(position, rideStart) < kNearbyQuietMeters ? NearbyPause.nearStart : null;
  }
  if (!foreground) return NearbyPause.background;
  if (home == null) return NearbyPause.noHome;
  return null;
}

/// Wen habe ich in dieser Fahrt schon gemeldet? Eine Fahrt ist eine
/// Aufzeichnung; ohne Aufzeichnung die Sitzung der App. Ein neuer
/// [session]-Schlüssel leert die Liste.
class NearbyNoticeLog {
  Object? _session;
  final _told = <String>{};

  /// true, wenn [buddyId] in [session] zum ersten Mal kommt — und merkt es.
  bool firstTime(String buddyId, Object? session) {
    if (session != _session) {
      _session = session;
      _told.clear();
    }
    return _told.add(buddyId);
  }
}
