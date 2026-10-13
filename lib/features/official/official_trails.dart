import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/l10n.dart';

/// Offizielle Trails (#13, `docs/konzept-offizielle-trails.md`): Linien
/// einer Behörde, gebaut von `official-trails.yml` auf den Branch
/// `official-trails-data`. Eine getrennte Ebene — keine Aufzeichnung,
/// kein Beitrag, kein Abgleich. Hier stehen nur das Format und sein
/// Lesen; geladen wird in `official_trails_source.dart`.

/// Ab dieser Zoomstufe lädt und zeichnet die Karte die Ebene. Darunter
/// wären die Linien Striche ohne Aussage, und schon der Start (DACH auf
/// Zoom 6) holte sonst jede Region.
const kOfficialMinZoom = 8.0;

/// Eine Quelle, wie `index.json` sie nennt — Wortlaut der Quellenangabe
/// und Lizenz stehen dort, nicht im Code.
@immutable
class OfficialSource {
  const OfficialSource({
    required this.id,
    required this.name,
    required this.attribution,
    required this.license,
    this.licenseUrl,
    this.url,
  });

  final String id;
  final String name;

  /// Die Quellenangabe, z. B. „Land Tirol".
  final String attribution;
  final String license;
  final String? licenseUrl;

  /// Die Seite der Quelle — der Link im Blatt.
  final String? url;

  factory OfficialSource.fromJson(String id, Map<String, dynamic> j) =>
      OfficialSource(
        id: id,
        name: j['name'] as String,
        attribution: j['attribution'] as String,
        license: j['license'] as String,
        licenseUrl: j['license_url'] as String?,
        url: j['url'] as String?,
      );
}

/// Eine Region: eine Datei mit Rahmen und Stand.
@immutable
class OfficialRegion {
  const OfficialRegion({
    required this.id,
    required this.file,
    required this.updated,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.sourceIds,
  });

  final String id;
  final String file;

  /// Stand der Quelle (`YYYY-MM-DD`). Ändert er sich, holt die App die
  /// Datei neu; sonst reicht die gemerkte.
  final String updated;
  final double south, west, north, east;
  final List<String> sourceIds;

  /// Berührt der Rahmen den Ausschnitt?
  bool touches(double s, double w, double n, double e) =>
      south <= n && north >= s && west <= e && east >= w;

  /// Nur schlichte Dateinamen: Der Name wird auf dem Gerät zum Pfad, und
  /// ein `../` aus einer kaputten oder fremden Datei hat dort nichts zu
  /// suchen.
  static final _safeFile = RegExp(r'^[a-z0-9_-]+\.geojson$');

  factory OfficialRegion.fromJson(Map<String, dynamic> j) {
    final file = j['file'] as String;
    if (!_safeFile.hasMatch(file)) {
      throw FormatException('Regionsdatei mit ungültigem Namen: $file');
    }
    final bbox = [for (final v in j['bbox'] as List) (v as num).toDouble()];
    if (bbox.length != 4) throw const FormatException('Rahmen braucht vier Zahlen');
    return OfficialRegion(
      id: j['id'] as String,
      file: file,
      updated: j['updated'] as String,
      west: bbox[0],
      south: bbox[1],
      east: bbox[2],
      north: bbox[3],
      sourceIds: [for (final s in j['sources'] as List) s as String],
    );
  }
}

/// `index.json`: welche Regionen es gibt und woher sie kommen.
@immutable
class OfficialIndex {
  const OfficialIndex({required this.regions, required this.sources});

  final List<OfficialRegion> regions;
  final Map<String, OfficialSource> sources;

  /// Die Formatversion, die diese App liest. Eine neuere lässt die Ebene
  /// leer, statt Felder falsch zu deuten.
  static const supportedVersion = 1;

  factory OfficialIndex.parse(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final version = j['version'];
    if (version != supportedVersion) {
      throw FormatException('Index in Version $version, gelesen wird $supportedVersion');
    }
    return OfficialIndex(
      regions: [
        for (final r in j['regions'] as List)
          OfficialRegion.fromJson(r as Map<String, dynamic>),
      ],
      sources: {
        for (final e in (j['sources'] as Map<String, dynamic>).entries)
          e.key: OfficialSource.fromJson(e.key, e.value as Map<String, dynamic>),
      },
    );
  }
}

/// Der amtliche Status. Er kommt von der Quelle und wird als deren
/// Aussage gezeigt, nie als Meldung eines Buddys (Konzept 4).
enum OfficialStatus {
  open,

  /// Ein Teil (meist eine Variante) ist gesperrt, die Hauptroute nicht.
  partlyClosed,
  closed;

  static OfficialStatus parse(Object? raw) => switch (raw) {
        'closed' => closed,
        'partly_closed' => partlyClosed,
        _ => open,
      };
}

/// Ein Teil der Linie: die Hauptroute oder eine Variante, je mit eigenem
/// Status.
@immutable
class OfficialSection {
  const OfficialSection({required this.points, this.variant = false, this.closed = false});

  final List<LatLng> points;
  final bool variant;
  final bool closed;
}

/// Ein offizieller Trail. Kein S-Grad: [difficulty] ist der Wortlaut der
/// Quelle (Konzept 5.2).
@immutable
class OfficialTrail {
  const OfficialTrail({
    required this.id,
    required this.name,
    required this.sourceId,
    required this.sections,
    this.description,
    this.difficulty,
    this.status = OfficialStatus.open,
    this.lengthM,
    this.upM,
    this.downM,
    this.updated,
  });

  /// `quelle:originalkennung`, stabil über Läufe.
  final String id;
  final String name;
  final String sourceId;
  final List<OfficialSection> sections;
  final String? description;
  final String? difficulty;
  final OfficialStatus status;
  final double? lengthM;
  final double? upM;
  final double? downM;

  /// Stand dieses Trails in der Quelle (`YYYY-MM-DD`).
  final String? updated;

  static OfficialTrail fromFeature(Map<String, dynamic> f) {
    final p = f['properties'] as Map<String, dynamic>;
    final g = f['geometry'] as Map<String, dynamic>;
    final lines = switch (g['type']) {
      'MultiLineString' => g['coordinates'] as List,
      'LineString' => [g['coordinates']],
      final t => throw FormatException('Geometrie $t'),
    };
    final meta = (p['sections'] as List?) ?? const [];
    final sections = <OfficialSection>[];
    for (var i = 0; i < lines.length; i++) {
      final m = i < meta.length ? meta[i] as Map<String, dynamic> : const {};
      final points = [
        for (final c in lines[i] as List)
          LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      if (points.length < 2) continue;
      sections.add(OfficialSection(
        points: points,
        variant: m['variant'] == true,
        closed: m['closed'] == true,
      ));
    }
    if (sections.isEmpty) throw const FormatException('Trail ohne Linie');
    String? text(String key) {
      final v = (p[key] as String?)?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    return OfficialTrail(
      id: (f['id'] ?? p['id']) as String,
      name: text('name') ?? 'Ohne Namen',
      sourceId: p['source'] as String,
      sections: sections,
      description: text('description'),
      difficulty: text('difficulty'),
      status: OfficialStatus.parse(p['status']),
      lengthM: (p['length_m'] as num?)?.toDouble(),
      upM: (p['up_m'] as num?)?.toDouble(),
      downM: (p['down_m'] as num?)?.toDouble(),
      updated: text('updated'),
    );
  }
}

/// Eine Regionsdatei lesen. Ein einzelnes kaputtes Feature fällt weg,
/// statt die Region zu leeren; ist gar nichts lesbar, ist die Datei kaputt.
List<OfficialTrail> parseOfficialRegion(String body) {
  final j = jsonDecode(body) as Map<String, dynamic>;
  final features = j['features'] as List;
  final trails = <OfficialTrail>[];
  for (final f in features) {
    try {
      trails.add(OfficialTrail.fromFeature(f as Map<String, dynamic>));
    } on Object catch (_) {
      // Bewusst still: Die Pipeline prüft das Format, ein Ausreißer soll
      // die übrigen Trails der Region nicht mitnehmen.
    }
  }
  if (features.isNotEmpty && trails.isEmpty) {
    throw const FormatException('Keines der Features lesbar');
  }
  return trails;
}

/// „19.05.2026" aus „2026-05-19" (Muster `officialDatePattern` der
/// Sprache); Unlesbares bleibt, wie es ist.
String formatIsoDate(AppLocalizations l, String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (m == null) return iso;
  final date = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return DateFormat(l.officialDatePattern, l.localeName).format(date);
}
