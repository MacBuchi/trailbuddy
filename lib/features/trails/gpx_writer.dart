// GPX schreiben (#150): die Gegenrichtung zu `gpx.dart`. Eine Spur als
// GPX 1.1 — ein `<trk>`, ein `<trkseg>`, `<ele>` und `<time>` nur, wo es
// sie gibt, `<link>` nur, wenn einer gesetzt ist. Neben dem Parser, weil
// er dessen `TrackPoint` nimmt (das Issue nannte `lib/core/`; ein
// Writer, der das Modell des Parsers braucht, gehört zu ihm).
//
// Was NICHT hineingeht, entscheidet der Aufrufer (`ride_export.dart`,
// `trail_export.dart`): keine Buddy-Namen, keine Hinweise, keine
// Fragen und Antworten einer Fahrt. Die Datei ist das, was der Nutzer
// weitergibt — eine Linie mit Namen.
import 'package:xml/xml.dart';

import 'gpx.dart';

/// Der Namensraum von GPX 1.1 — Text in der Datei, kein Netzziel.
const kGpxNamespace = 'http://www.topografix.com/GPX/1/1';

/// Der eigene Namensraum für `<extensions>` (#186) — eine URN, keine
/// Adresse: niemand ruft sie ab.
const kTrailBuddyGpxNamespace = 'urn:trailbuddy:gpx:1';

/// Schreibt eine Spur als GPX-1.1-Dokument. [points] werden mit sechs
/// Nachkommastellen geschrieben (~11 cm), Höhen mit einer, Zeiten in
/// UTC ohne Bruchteile — was `parseGpx` liest, kommt Feld für Feld
/// zurück (Rundlauf-Test).
///
/// [terrainHeights]: Die Höhen kommen aus dem Geländemodell, nicht aus
/// einer Aufzeichnung (#186). Die Spur trägt dann
/// `<extensions><tb:elevationSource>terrain</…>`, und `parseGpx` liest
/// diese Höhen nie wieder ein — andere Apps zeigen sie, unser Import
/// nimmt sie nicht als gemessen.
String writeGpx({
  required String name,
  required List<TrackPoint> points,
  String? link,
  String creator = 'TrailBuddy',
  bool terrainHeights = false,
}) {
  final b = XmlBuilder();
  b.processing('xml', 'version="1.0" encoding="UTF-8"');
  b.element(
    'gpx',
    nest: () {
      b.attribute('version', '1.1');
      b.attribute('creator', creator);
      b.attribute('xmlns', kGpxNamespace);
      if (terrainHeights) b.attribute('xmlns:tb', kTrailBuddyGpxNamespace);
      b.element(
        'metadata',
        nest: () {
          b.element('name', nest: name);
          if (link != null) {
            b.element('link', nest: () => b.attribute('href', link));
          }
        },
      );
      b.element(
        'trk',
        nest: () {
          b.element('name', nest: name);
          if (link != null) {
            b.element('link', nest: () => b.attribute('href', link));
          }
          if (terrainHeights) {
            b.element(
              'extensions',
              nest: () => b.element(
                'tb:$kElevationSourceTag',
                nest: kTerrainElevationSource,
              ),
            );
          }
          b.element(
            'trkseg',
            nest: () {
              for (final p in points) {
                b.element(
                  'trkpt',
                  nest: () {
                    b.attribute('lat', p.lat.toStringAsFixed(6));
                    b.attribute('lon', p.lon.toStringAsFixed(6));
                    if (p.ele case final ele?) {
                      b.element('ele', nest: ele.toStringAsFixed(1));
                    }
                    if (p.time case final time?) {
                      b.element(
                        'time',
                        nest: time.toUtc().toIso8601String().replaceFirst(
                          RegExp(r'\.\d+'),
                          '',
                        ),
                      );
                    }
                  },
                );
              }
            },
          );
        },
      );
    },
  );
  return b.buildDocument().toXmlString(pretty: true);
}

/// Ein Dateiname aus einem Trail- oder Fahrtnamen: `trailbuddy-<slug>.gpx`,
/// nur Kleinbuchstaben, Ziffern und Bindestriche — Umlaute aufgelöst,
/// damit die Datei auf jedem System heißt, wie sie heißt.
String gpxFileName(String name) {
  var slug = name.toLowerCase();
  const umlauts = {'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss'};
  umlauts.forEach((k, v) => slug = slug.replaceAll(k, v));
  slug = slug
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > 60) {
    slug = slug.substring(0, 60).replaceAll(RegExp(r'-+$'), '');
  }
  return 'trailbuddy-${slug.isEmpty ? 'trail' : slug}.gpx';
}
