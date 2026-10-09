import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Orte auf der Karte (Issue #12): Einkehr, Wasser, Rad-Service und
/// Sonstiges aus OpenStreetMap — seit 0.18.0 als fertige Dateien je
/// Rasterzelle und Gruppe auf dem eigenen Kartenhost (`tiles.mcbuchi.de`,
/// gebaut von `poi-data.yml` aus `tool/poi_extract.py`), vorher live von
/// der Overpass-API.
///
/// Reine Daten und reine Funktionen — Manifest und Zellendatei lesen,
/// Raster rechnen. Das Netz steckt in `poi_source.dart`, die Anzeige in
/// `poi_layer.dart`. Die Arten und ihre Regeln stehen ZWEIMAL: hier für
/// die App und in `tool/pois/kinds.json` für das Werkzeug, das die
/// Dateien baut; `test/map/poi_test.dart` hält beide zusammen.

/// Die Gruppen, die man im Filter an- und ausschaltet.
enum PoiGroup {
  food('Einkehr', 'Biergarten, Café, Hütte, Gasthaus', Color(0xFF8D5524)),
  water('Wasser', 'Trinkwasser, Wasserstellen, Quellen', Color(0xFF0277BD)),
  bikeService('Rad-Service', 'Reparaturstation, Radladen, E-Bike-Laden',
      Color(0xFF455A64)),
  other('Sonstiges', 'Unterstand, Toilette, Aussichtspunkt, Parkplatz',
      Color(0xFF6D4C9F));

  const PoiGroup(this.label, this.examples, this.color);

  final String label;
  final String examples;

  /// Die Farbe der Stecknadel. Bewusst keine der Trail-Farben (Grün,
  /// Blau, Orange): Die sagen auf dieser Karte, was ICH mit einem Trail
  /// zu tun habe, und ein Ort soll nie wie ein Trail aussehen.
  final Color color;

  /// Beim ersten Start: nur Wasser (Entscheidung des Betreibers) — das,
  /// was man unterwegs am ehesten sucht, ohne die Karte in der Stadt mit
  /// Gasthäusern zu fluten.
  static const initial = {PoiGroup.water};
}

/// Was ein Ort ist. Die Reihenfolge zählt: Ein Objekt mit mehreren
/// passenden Merkmalen bekommt die ERSTE passende Art. Deshalb steht der
/// Biergarten vorn: Ein Gasthaus mit Biergarten zeigt den Krug, nicht
/// das Besteck.
enum PoiKind {
  // In OSM gibt es beides: den eigenständigen Biergarten und das Gasthaus
  // (seltener die Kneipe) mit `biergarten=yes` — in München 54 zu 8.
  biergarten(PoiGroup.food, 'Biergarten', Icons.sports_bar, [
    {'amenity': 'biergarten'},
    {'biergarten': 'yes'},
    {'beer_garden': 'yes'},
  ]),
  // Kein Material-Symbol für ein Kuchenstück — `PoiGlyph` zeichnet es.
  cafe(PoiGroup.food, 'Café', null, [
    {'amenity': 'cafe'},
  ]),
  pub(PoiGroup.food, 'Kneipe', Icons.sports_bar, [
    {'amenity': 'pub'},
  ]),
  restaurant(PoiGroup.food, 'Gasthaus', Icons.restaurant, [
    {'amenity': 'restaurant'},
  ]),
  hut(PoiGroup.food, 'Hütte', Icons.cabin, [
    {'tourism': 'alpine_hut'},
  ]),
  drinkingWater(PoiGroup.water, 'Trinkwasser', Icons.water_drop, [
    {'amenity': 'drinking_water'},
  ]),
  waterPoint(PoiGroup.water, 'Wasserstelle', Icons.water_drop, [
    {'amenity': 'water_point'},
  ]),
  spring(PoiGroup.water, 'Quelle', Icons.local_drink, [
    {'natural': 'spring'},
  ]),
  repairStation(PoiGroup.bikeService, 'Reparaturstation', Icons.build, [
    {'amenity': 'bicycle_repair_station'},
  ]),
  bikeShop(PoiGroup.bikeService, 'Radladen', Icons.pedal_bike, [
    {'shop': 'bicycle'},
  ]),
  // Ladesäulen gibt es an jedem Supermarkt — hier nur die fürs Rad.
  eBikeCharging(PoiGroup.bikeService, 'E-Bike-Ladestation',
      Icons.electric_bike, [
    {'amenity': 'charging_station', 'bicycle': 'yes'},
  ]),
  shelter(PoiGroup.other, 'Unterstand', Icons.roofing, [
    {'amenity': 'shelter'},
  ]),
  toilets(PoiGroup.other, 'Toilette', Icons.wc, [
    {'amenity': 'toilets'},
  ]),
  viewpoint(PoiGroup.other, 'Aussichtspunkt', Icons.landscape, [
    {'tourism': 'viewpoint'},
  ]),
  // Private Parkplätze (Firmen, Anwohner) helfen niemandem.
  parking(PoiGroup.other, 'Parkplatz', Icons.local_parking, [
    {'amenity': 'parking'},
  ], excludeAccess: true);

  const PoiKind(this.group, this.label, this.icon, this.rules,
      {this.excludeAccess = false});

  final PoiGroup group;
  final String label;

  /// Das Symbol in der Nadel; null heißt gezeichnet (`PoiGlyph`).
  final IconData? icon;

  /// Jede Regel ist eine Menge Merkmale, die ALLE passen müssen; eine
  /// passende Regel genügt.
  final List<Map<String, String>> rules;
  final bool excludeAccess;

  bool matches(Map<String, String> tags) {
    if (excludeAccess && _closedAccess.contains(tags['access'])) return false;
    return rules.any((r) => r.entries.every((e) => tags[e.key] == e.value));
  }

  static PoiKind? of(Map<String, String> tags) {
    for (final k in values) {
      if (k.matches(tags)) return k;
    }
    return null;
  }

  /// Die Art aus ihrem Namen in einer Zellendatei — null für einen Namen,
  /// den diese App-Version nicht kennt (eine neuere Datei darf eine
  /// ältere App nicht brechen; die Art fällt dann still weg).
  static PoiKind? byName(String? name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

const _closedAccess = {'private', 'no'};

/// Ein Ort, so weit die Anzeige ihn braucht.
class Poi {
  const Poi({
    required this.id,
    required this.kind,
    required this.position,
    this.name,
    this.openingHours,
    this.drinkable,
  });

  /// `node/123`, `way/456` — zugleich der Pfad auf openstreetmap.org.
  final String id;
  final PoiKind kind;
  final LatLng position;
  final String? name;
  final String? openingHours;

  /// `drinking_water=yes/no` aus OSM, sonst null. Eine Quelle ist nicht
  /// von selbst Trinkwasser — das Blatt sagt es dazu.
  final bool? drinkable;

  PoiGroup get group => kind.group;
}

/// Unterhalb dieser Zoomstufe fragt die Karte nicht an und zeigt nichts:
/// Ein Ausschnitt über halb Bayern wäre eine Abfrage über zehntausende
/// Orte, und lesbar wären sie ohnehin nicht.
const kPoiMinZoom = 12.0;

/// Höchstens so viele Rasterzellen in einer Abfrage. Ein Tablet quer auf
/// Zoom 12 braucht etwa neun; mehr heißt, es wird gerade herausgezoomt.
const kPoiMaxCells = 16;

// Das Raster, in dem geladen und gemerkt wird: 0,1° × 0,15°, in
// Mitteleuropa etwa 11 × 11 km. Fest statt am Ausschnitt ausgerichtet,
// damit Verschieben nicht jedes Mal neu fragt.
const _cellLat = 0.1;
const _cellLon = 0.15;

/// Eine Rasterzelle, als `"zeile,spalte"`.
typedef PoiCell = String;

PoiCell poiCellOf(LatLng p) =>
    '${(p.latitude / _cellLat).floor()},${(p.longitude / _cellLon).floor()}';

/// Alle Zellen, die das Rechteck berühren (Süden, Westen, Norden, Osten).
List<PoiCell> poiCellsCovering(double s, double w, double n, double e) {
  final r0 = (s / _cellLat).floor(), r1 = (n / _cellLat).floor();
  final c0 = (w / _cellLon).floor(), c1 = (e / _cellLon).floor();
  return [
    for (var r = r0; r <= r1; r++)
      for (var c = c0; c <= c1; c++) '$r,$c',
  ];
}

/// Der Rahmen um eine Menge Zellen: (Süden, Westen, Norden, Osten).
({double s, double w, double n, double e}) poiCellsBounds(
    Iterable<PoiCell> cells) {
  var r0 = 1 << 30, r1 = -(1 << 30), c0 = 1 << 30, c1 = -(1 << 30);
  for (final cell in cells) {
    final parts = cell.split(',');
    final r = int.parse(parts[0]), c = int.parse(parts[1]);
    r0 = math.min(r0, r);
    r1 = math.max(r1, r);
    c0 = math.min(c0, c);
    c1 = math.max(c1, c);
  }
  return (
    s: r0 * _cellLat,
    w: c0 * _cellLon,
    n: (r1 + 1) * _cellLat,
    e: (c1 + 1) * _cellLon,
  );
}

/// Der Dateiname einer Zelle je Gruppe unter dem Präfix des Baus:
/// `<zeile>_<spalte>.<gruppe>.json` — das Komma des Zellenschlüssels
/// taugt nicht für eine URL. Dieselbe Regel in `tool/poi_extract.py`
/// (`cell_file`).
String poiCellFileName(PoiCell cell, PoiGroup group) =>
    '${cell.replaceAll(',', '_')}.${group.name}.json';

/// Das Manifest `pois.json` des Kartenhosts: welcher Bau gerade gilt und
/// welche Zellen je Gruppe überhaupt eine Datei haben. Eine Zelle, die
/// hier nicht steht, ist leer — die App fragt dann gar nicht erst.
class PoiManifest {
  const PoiManifest({required this.build, required this.prefix, required this.cells, this.dir = ''});

  /// `JJJJMMTT` des Baus.
  final String build;

  /// Der Ordner unter dem Kartenhost, `pois-<build>`.
  final String prefix;

  final Map<PoiGroup, Set<PoiCell>> cells;

  /// Der Ordner der Region (#220): leer für DACH, sonst `<id>/`; das
  /// Präfix ist relativ dazu.
  final String dir;

  /// Der Ordner des Baus unter dem Kartenhost, `[<id>/]pois-<build>`.
  String get folder => '$dir$prefix';

  bool has(PoiCell cell, PoiGroup group) => cells[group]?.contains(cell) ?? false;

  /// Liest das Manifest; wirft bei allem, was nicht passt. Das Präfix
  /// wird geprüft, weil es zu einem Pfad wird. Gruppen, die diese
  /// App-Version nicht kennt, fallen still weg.
  factory PoiManifest.fromJson(Map<String, dynamic> j, {String dir = ''}) {
    if (dir.isNotEmpty && !RegExp(r'^[a-z]{2,8}/$').hasMatch(dir)) {
      throw FormatException('Unerwarteter Regionsordner: $dir');
    }
    if (j['format'] != 1) throw FormatException('Orte-Manifest: Format ${j['format']}');
    final prefix = j['prefix'] as String;
    if (!RegExp(r'^pois-\d{8}$').hasMatch(prefix)) {
      throw FormatException('Unerwartetes Orte-Präfix: $prefix');
    }
    final raw = j['cells'] as Map<String, dynamic>;
    return PoiManifest(
      build: j['build'] as String,
      prefix: prefix,
      dir: dir,
      cells: {
        for (final g in PoiGroup.values)
          g: {for (final c in (raw[g.name] as List? ?? const [])) c as String},
      },
    );
  }
}

/// Liest eine Zellendatei (`pois-<build>/<zeile>_<spalte>.<gruppe>.json`).
/// Was keiner bekannten Art zugeordnet ist oder keine Lage hat, fällt
/// still heraus; die Art selbst hat schon das Werkzeug entschieden.
List<Poi> parsePoiFile(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  if (json['format'] != 1) throw FormatException('Orte-Datei: Format ${json['format']}');
  final out = <Poi>[];
  for (final el in (json['pois'] as List? ?? const [])) {
    if (el is! Map<String, dynamic>) continue;
    final kind = PoiKind.byName(el['kind'] as String?);
    final lat = el['lat'] as num?;
    final lng = el['lng'] as num?;
    final id = el['id'] as String?;
    if (kind == null || lat == null || lng == null || id == null) continue;
    final water = el['water'];
    out.add(Poi(
      id: id,
      kind: kind,
      position: LatLng(lat.toDouble(), lng.toDouble()),
      name: el['name'] as String?,
      openingHours: el['hours'] as String?,
      drinkable: water == 'yes' ? true : (water == 'no' ? false : null),
    ));
  }
  return out;
}
