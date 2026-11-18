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

  /// Die Ränder der Zelle — für das Quadrat auf der Karte (#519, Homies).
  double get south => row * kNearbyCellDeg;
  double get north => (row + 1) * kNearbyCellDeg;
  double get west => col * _width(row);
  double get east => (col + 1) * _width(row);

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

// ---------------------------------------------------------------------------
// Gruppenfahrt (#519, E4; docs/konzept-geraete.md 6.3)
// ---------------------------------------------------------------------------

/// Der Paarkanal zweier Buddys: die Kennungen sortiert, also genau einer
/// je Paar (Patch 032, `app_internal.may_live`).
String livePairTopic(String a, String b) =>
    a.compareTo(b) < 0 ? 'live:$a:$b' : 'live:$b:$a';

/// So lange gilt eine genaue Position als frisch; danach „zuletzt vor …"
/// (A8: ohne Netz ehrlich, kein Punkt, der stillsteht).
const kLiveFreshFor = Duration(minutes: 2);

/// So lange bleibt die letzte genaue Position stehen, nachdem nichts mehr
/// kam; danach verschwindet sie. Nur im Speicher, nie gespeichert.
const kLiveKeepFor = Duration(minutes: 15);

/// So lange bleibt die Zelle eines Homies stehen, nachdem er sie
/// herausgenommen hat (oder die Verbindung riss).
const kCellKeepFor = Duration(minutes: 15);

/// Was ich gerade von EINEM Buddy weiß.
class BuddySighting {
  const BuddySighting({
    required this.buddyId,
    this.cell,
    this.cellPresent = false,
    this.cellGoneAt,
    this.live = false,
    this.position,
    this.positionAt,
    this.positionPresent = false,
  });

  final String buddyId;

  /// Seine grobe Zelle (Patch 031) — alle direkten Buddys empfangen sie.
  final NearbyCell? cell;

  /// Liegt die Zelle noch im Kanal? Nein: [cellGoneAt] sagt, seit wann.
  final bool cellPresent;
  final DateTime? cellGoneAt;

  /// Hat er „Live mit Buddys" in dieser Fahrt an?
  final bool live;

  /// Seine genaue Position aus dem Paarkanal — nur in der Nähe, nur wenn
  /// beide Live anhaben.
  final NearbyPoint? position;

  /// Wann er sie gesetzt hat (seine Uhr, nie in der Zukunft).
  final DateTime? positionAt;
  final bool positionPresent;

  BuddySighting copyWith({
    NearbyCell? Function()? cell,
    bool? cellPresent,
    DateTime? Function()? cellGoneAt,
    bool? live,
    NearbyPoint? Function()? position,
    DateTime? Function()? positionAt,
    bool? positionPresent,
  }) =>
      BuddySighting(
        buddyId: buddyId,
        cell: cell != null ? cell() : this.cell,
        cellPresent: cellPresent ?? this.cellPresent,
        cellGoneAt: cellGoneAt != null ? cellGoneAt() : this.cellGoneAt,
        live: live ?? this.live,
        position: position != null ? position() : this.position,
        positionAt: positionAt != null ? positionAt() : this.positionAt,
        positionPresent: positionPresent ?? this.positionPresent,
      );
}

/// Wie ein Buddy auf der Karte steht.
enum BuddyMapKind {
  /// Genau, aus dem Paarkanal.
  live,

  /// Grob: das Quadrat seiner Zelle — nur für Homies.
  cell,
}

/// Ein Eintrag der Karte: [point] ist die genaue Position oder der
/// Mittelpunkt der Zelle; [seenAgo] null heißt frisch.
typedef BuddyMapEntry = ({
  String buddyId,
  BuddyMapKind kind,
  NearbyPoint point,
  NearbyCell? cell,
  Duration? seenAgo,
});

/// Was die Karte zeigt (6.1, E4): genau, wenn eine Position aus dem
/// Paarkanal da ist und nicht älter als [kLiveKeepFor]; sonst die Zelle —
/// aber NUR, wenn der Buddy mich als Homie gewählt hat ([homieOwners]).
/// Alle anderen: nichts. Rein, damit Test und Karte dieselbe Antwort
/// bekommen.
List<BuddyMapEntry> buddyMapEntries(
  Iterable<BuddySighting> sightings, {
  required Set<String> homieOwners,
  required DateTime now,
}) {
  final out = <BuddyMapEntry>[];
  for (final s in sightings) {
    final pos = s.position;
    final at = s.positionAt;
    if (pos != null && at != null) {
      final age = now.difference(at);
      if (age < kLiveKeepFor) {
        final fresh = s.positionPresent && age < kLiveFreshFor;
        out.add((
          buddyId: s.buddyId,
          kind: BuddyMapKind.live,
          point: pos,
          cell: null,
          seenAgo: fresh ? null : (age.isNegative ? Duration.zero : age),
        ));
        continue;
      }
    }
    final cell = s.cell;
    if (cell == null || !homieOwners.contains(s.buddyId)) continue;
    Duration? ago;
    if (!s.cellPresent) {
      final gone = s.cellGoneAt;
      if (gone == null) continue;
      ago = now.difference(gone);
      if (ago >= kCellKeepFor) continue;
      if (ago.isNegative) ago = Duration.zero;
    }
    out.add((
      buddyId: s.buddyId,
      kind: BuddyMapKind.cell,
      point: (lat: cell.centerLat, lon: cell.centerLon),
      cell: cell,
      seenAgo: ago,
    ));
  }
  return out;
}

/// Mit wem soll ich gerade einen Paarkanal haben? Nur, wenn ICH Live
/// anhabe und teile ([mine] nicht null), und nur mit Buddys, die Live auch
/// anhaben und in derselben oder einer Nachbarzelle sind. Das ist die
/// einzige Stelle, die entscheidet, wer meine genaue Position bekommt.
Set<String> livePairsFor({
  required NearbyCell? mine,
  required bool myLive,
  required Iterable<BuddySighting> sightings,
}) {
  if (mine == null || !myLive) return const {};
  return {
    for (final s in sightings)
      if (s.live && s.cellPresent && s.cell != null && mine.isNearTo(s.cell!)) s.buddyId,
  };
}
