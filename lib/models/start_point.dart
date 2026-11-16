// Ein gemerkter Startpunkt (#543, `docs/konzept-startpunkte.md`, Patch
// 030): ein benannter Punkt, den jemand bewusst anlegt — ein Parkplatz,
// der Eingang eines Trailcenters. Name, Lage, Sichtbarkeit, mehr nicht.
//
// Die App kennt einen Punkt unter seiner `client_id`, nicht unter der
// Server-Kennung: Sie entsteht auf dem Gerät, bevor der Punkt den Server
// je gesehen hat, und so treffen Umbenennen und Löschen aus dem
// Ausgangskorb auch einen Punkt, der ohne Netz angelegt wurde. Eindeutig
// ist sie nur je Konto — [key] nimmt deshalb den Besitzer dazu.
import 'package:latlong2/latlong.dart';

import 'trail.dart' show TrailVisibility;

/// Wie lang ein Name sein darf — derselbe Check wie in der Datenbank.
const kStartPointNameMaxLength = 60;

/// Höchstens so viele Punkte je Konto (Trigger `start_points_limit`,
/// Konzept 9.2).
const kStartPointMax = 100;

class StartPoint {
  const StartPoint({
    required this.clientId,
    required this.userId,
    required this.name,
    required this.lat,
    required this.lon,
    this.visibility = TrailVisibility.buddies,
    required this.createdAt,
    this.updatedAt,
    this.username,
    this.pending = false,
    this.sending = false,
  });

  final String clientId;
  final String userId;
  final String name;
  final double lat;
  final double lon;
  final TrailVisibility visibility;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Aus dem Embed `owner:profiles(username)` — für den Buddy-Namen.
  final String? username;

  /// Wartet im Ausgangskorb (ohne Netz angelegt oder geändert).
  final bool pending;

  /// Gerade unterwegs (#183), immer mit [pending].
  final bool sending;

  /// Eindeutig über alle sichtbaren Punkte.
  String get key => '$userId/$clientId';

  bool get shared => visibility == TrailVisibility.buddies;

  LatLng get position => LatLng(lat, lon);

  bool isMine(String myId) => userId == myId;

  StartPoint copyWith({
    String? name,
    double? lat,
    double? lon,
    TrailVisibility? visibility,
    bool? pending,
    bool? sending,
  }) =>
      StartPoint(
        clientId: clientId,
        userId: userId,
        name: name ?? this.name,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        visibility: visibility ?? this.visibility,
        createdAt: createdAt,
        updatedAt: updatedAt,
        username: username,
        pending: pending ?? this.pending,
        sending: sending ?? this.sending,
      );

  /// Liest eine Zeile wie vom Netz — oder `null`, wenn sie nicht taugt
  /// (eine Kopie, die ein späterer Stand anders geschrieben hat).
  static StartPoint? fromJson(Map<String, dynamic> json) {
    final clientId = json['client_id'] as String?;
    final userId = json['user_id'] as String?;
    final name = (json['name'] as String?)?.trim();
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    if (clientId == null || userId == null || name == null || name.isEmpty ||
        lat == null || lon == null || createdAt == null) {
      return null;
    }
    final owner = json['owner'];
    return StartPoint(
      clientId: clientId,
      userId: userId,
      name: name,
      lat: lat,
      lon: lon,
      visibility: TrailVisibility.fromDb(json['visibility'] as String?),
      createdAt: createdAt.toLocal(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '')?.toLocal(),
      username: owner is Map<String, dynamic> ? owner['username'] as String? : null,
    );
  }

  /// Die Zeile, wie sie in die Kopie auf dem Gerät geht — die Hälfte zu
  /// [fromJson].
  Map<String, dynamic> toRow() => {
        'client_id': clientId,
        'user_id': userId,
        'name': name,
        'lat': lat,
        'lon': lon,
        'visibility': visibility.db,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt?.toUtc().toIso8601String(),
        'owner': username == null ? null : {'username': username},
      };

  /// Was an den Server geht: nur die Spalten, die der Besitzer setzt.
  Map<String, dynamic> toWriteRow() => {
        'client_id': clientId,
        'user_id': userId,
        'name': name,
        'lat': lat,
        'lon': lon,
        'visibility': visibility.db,
      };
}

/// Kürzt einen Namen auf das, was die Datenbank annimmt — `''` heißt:
/// so nicht speicherbar. Gezählt in Codepunkten wie `char_length`, damit
/// ein Emoji am Ende nicht halbiert wird.
String clampStartPointName(String raw) {
  final t = raw.trim();
  if (t.runes.length <= kStartPointNameMaxLength) return t;
  return String.fromCharCodes(t.runes.take(kStartPointNameMaxLength)).trimRight();
}
