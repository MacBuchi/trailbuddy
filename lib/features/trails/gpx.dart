import 'package:xml/xml.dart';

import 'trail_link.dart';

/// Ein Punkt einer GPX-Spur. `ele` und `time` fehlen bei gezeichneten
/// Routen (Konzept 5.2: „geplant", nicht „gefahren").
class TrackPoint {
  const TrackPoint(this.lat, this.lon, {this.ele, this.time});

  final double lat;
  final double lon;
  final double? ele;
  final DateTime? time;
}

/// Eine Spur aus einer GPX-Datei: ein `<trk>` mit allen Segmenten
/// hintereinander (ein Segmentbruch ist eine Lücke, kein neuer Trail) —
/// oder ein `<rte>`, wenn die Datei nur eine Route trägt.
class GpxTrack {
  const GpxTrack({required this.name, required this.points, this.link, this.terrainHeights = false});

  final String name;
  final List<TrackPoint> points;

  /// Die Höhen der Punkte kommen aus dem Geländemodell (#186) — nur beim
  /// Export gesetzt; der Parser liest solche Höhen gar nicht erst ein.
  final bool terrainHeights;

  /// Der Link zur Quelle (#103): `<link href>` der Spur, sonst der aus
  /// `<metadata>` — schon durch [linkFromFile] gefiltert, also https, ohne
  /// Query, und nie der Hersteller des Geräts. Null, wenn keiner taugt.
  final String? link;
}

/// Das Element in `<extensions>` einer Spur, das sagt, woher ihre Höhen
/// kommen (#186), und der Wert für „aus dem Geländemodell".
const kElevationSourceTag = 'elevationSource';
const kTerrainElevationSource = 'terrain';

/// Trägt [parent] (`<trk>`/`<rte>`) die Marke „Höhen aus dem
/// Geländemodell"? Namensräume zählen nicht, wie überall hier.
bool _terrainMarked(XmlElement parent) => parent
    .findElements('extensions')
    .expand((e) => e.findElements(kElevationSourceTag, namespaceUri: '*'))
    .any((e) => e.innerText.trim() == kTerrainElevationSource);

class GpxFormatException implements Exception {
  const GpxFormatException(this.message);
  final String message;

  @override
  String toString() => 'GpxFormatException: $message';
}

/// Liest alle Spuren einer GPX-Datei. Namensräume werden ignoriert:
/// Locus, Komoot, Garmin und Strava schreiben alle GPX 1.1, aber mit
/// verschiedenen Präfixen und Erweiterungen; uns interessieren nur
/// `trkpt`/`rtept` mit `lat`, `lon`, `ele`, `time`.
///
/// Doppelte aufeinanderfolgende Punkte (Locus schreibt sie an Pausen)
/// fallen weg. Spuren mit weniger als zwei Punkten fallen weg.
///
/// Höhen einer Spur, die als „aus dem Geländemodell" markiert ist (unser
/// eigener Export, #186), werden NICHT gelesen: Sie sind nicht gemessen,
/// und ein Re-Import schriebe sie sonst als Aufzeichnung auf den Server
/// (Nachtragen, Beisteuern).
List<GpxTrack> parseGpx(String xml, {String fallbackName = 'Ohne Namen'}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    throw GpxFormatException('Kein gültiges XML: ${e.message}');
  }
  final root = doc.rootElement;
  if (root.name.local != 'gpx') {
    throw GpxFormatException('Keine GPX-Datei (Wurzel ist <${root.name.local}>).');
  }
  final fileLink = _link(root.getElement('metadata'));
  final tracks = <GpxTrack>[];
  for (final trk in root.findElements('trk')) {
    final points = <TrackPoint>[];
    final terrain = _terrainMarked(trk);
    for (final seg in trk.findElements('trkseg')) {
      _collect(seg.findElements('trkpt'), points, withEle: !terrain);
    }
    if (points.length >= 2) {
      tracks.add(GpxTrack(
          name: _name(trk) ?? fallbackName, points: points, link: _link(trk) ?? fileLink));
    }
  }
  for (final rte in root.findElements('rte')) {
    final points = <TrackPoint>[];
    _collect(rte.findElements('rtept'), points, withEle: !_terrainMarked(rte));
    if (points.length >= 2) {
      tracks.add(GpxTrack(
          name: _name(rte) ?? fallbackName, points: points, link: _link(rte) ?? fileLink));
    }
  }
  return tracks;
}

/// Der erste taugliche `<link href>` direkt unter [parent] (GPX 1.1; in
/// GPX 1.0 ist `<url>` ein Textelement).
String? _link(XmlElement? parent) {
  if (parent == null) return null;
  for (final el in parent.findElements('link')) {
    final link = linkFromFile(el.getAttribute('href'));
    if (link != null) return link;
  }
  return linkFromFile(parent.getElement('url')?.innerText);
}

String? _name(XmlElement parent) {
  final el = parent.getElement('name');
  final text = el?.innerText.trim();
  return (text == null || text.isEmpty) ? null : decodeTrackName(text);
}

final _percentEscape = RegExp(r'%[0-9A-Fa-f]{2}');

/// Manche Apps (Locus beim Export von Trailforks-Spuren) schreiben den
/// Namen URL-kodiert: „DREI%20EICHEN%20-%20…". Dekodiert wird nur, was
/// wie ein Escape aussieht und sich sauber dekodieren lässt — ein Name
/// wie „100 % Flow" bleibt, wie er ist.
String decodeTrackName(String name) {
  if (!_percentEscape.hasMatch(name)) return name;
  try {
    return Uri.decodeComponent(name).trim();
  } on ArgumentError {
    return name;
  } on FormatException {
    return name;
  }
}

void _collect(Iterable<XmlElement> elements, List<TrackPoint> into, {bool withEle = true}) {
  for (final p in elements) {
    final lat = double.tryParse(p.getAttribute('lat') ?? '');
    final lon = double.tryParse(p.getAttribute('lon') ?? '');
    if (lat == null || lon == null) continue;
    if (lat.abs() > 90 || lon.abs() > 180) continue;
    if (into.isNotEmpty &&
        (into.last.lat - lat).abs() < 1e-9 &&
        (into.last.lon - lon).abs() < 1e-9) {
      continue;
    }
    final ele = withEle ? double.tryParse(p.getElement('ele')?.innerText.trim() ?? '') : null;
    final timeText = p.getElement('time')?.innerText.trim();
    final time = timeText == null ? null : DateTime.tryParse(timeText);
    into.add(TrackPoint(lat, lon, ele: ele, time: time?.toUtc()));
  }
}
