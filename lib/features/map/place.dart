// Ortsnamen für die Suche auf der Karte (#576, Stufe 2): Ortschaften,
// Gipfel, Pässe und Hütten aus dem eigenen Index auf dem Kartenhost —
// gebaut von `tool/poi_extract.py` aus denselben Geofabrik-Auszügen wie
// die Orte (POIs), Arten in `tool/pois/places.json`. Kein Geocoder, kein
// fremder Dienst: Zum Host gehen nur die ersten zwei oder drei Buchstaben
// des getippten Worts, als Name der Datei.
//
// Zwei Formen derselben Einträge: je Rasterzelle `<z>_<s>.places.json`
// (kommt mit jedem gespeicherten Bereich mit — offline gesucht wird dort)
// und je Namensschlüssel `names/<schlüssel>.json` (online, eine Datei je
// Suche). Die Karte zeichnet sie nicht; ihre Namen stehen schon in der
// Grundkarte.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/search_text.dart';
import '../../l10n/l10n.dart';
import 'poi.dart';

/// Die Arten, in der Reihenfolge von `tool/pois/places.json`
/// (`test/map/place_test.dart` hält beide zusammen).
enum PlaceKind {
  city(Icons.location_city, 12),
  town(Icons.location_city, 13),
  village(Icons.holiday_village, 14),
  hamlet(Icons.cottage, 15),
  peak(Icons.terrain, 15),
  pass(Icons.swap_calls, 15),
  hut(Icons.cabin, 15);

  const PlaceKind(this.icon, this.flyZoom);

  final IconData icon;

  /// So nah fliegt die Karte heran (256er-Zoom): eine Stadt ganz, ein
  /// Gipfel mit seinen Wegen.
  final double flyZoom;

  String label(AppLocalizations l) => switch (this) {
    city => l.placeKindCity,
    town => l.placeKindTown,
    village => l.placeKindVillage,
    hamlet => l.placeKindHamlet,
    peak => l.placeKindPeak,
    pass => l.placeKindPass,
    hut => l.poiKindHut,
  };

  static PlaceKind? byName(String? name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

/// Ein Ortsname aus dem Index.
@immutable
class Place {
  const Place({
    required this.id,
    required this.kind,
    required this.name,
    required this.position,
    this.alt,
    this.ele,
  });

  /// `node/123` — derselbe Pfad wie bei den Orten (POIs).
  final String id;
  final PlaceKind kind;
  final String name;

  /// Der deutsche Name, wo er vom örtlichen abweicht (`name:de`).
  final String? alt;
  final LatLng position;

  /// Höhe in Metern (Gipfel, Pass, Hütte), sonst null.
  final int? ele;

  /// Eine Hütte ist auch ein Ort der Karte — der Treffer öffnet ihr
  /// Blatt wie ein Tipp auf das Symbol.
  Poi? get asPoi => kind == PlaceKind.hut
      ? Poi(id: id, kind: PoiKind.hut, position: position, name: name)
      : null;

  @override
  bool operator ==(Object other) => other is Place && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Die Texte eines Ortsnamens für die Suche: Name und deutscher Name.
List<String> placeSearchTexts(Place p) => [p.name, ?p.alt];

/// `<zeile>_<spalte>.places.json` — derselbe Ordner und dieselbe Form wie
/// [poiCellFileName], nur mit der Gruppe `places`.
String placeCellFileName(PoiCell cell) =>
    '${cell.replaceAll(',', '_')}.places.json';

/// Ist [name] eine Ortsnamen-Zelle (und keine Orte-Datei)?
bool isPlaceCellFileName(String name) => name.endsWith('.places.json');

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Die gefalteten Wörter von [text] mit mindestens zwei Zeichen — wie
/// `name_words` im Werkzeug, das die Namen danach ablegt.
List<String> placeNameWords(String text) => [
  for (final m in _word.allMatches(text))
    if (foldSearchText(m[0]!) case final w when w.length >= 2) w,
];

/// Die Datei, in der [query] nachsieht: das längste getippte Wort, erst
/// seine ersten drei Buchstaben (eine geteilte Datei), sonst zwei — nur,
/// wenn der Index sie nennt ([keys]). Null: nichts zu fragen.
String? placeNameKey(String query, Set<String> keys) {
  final word = longestPlaceWord(query);
  if (word == null) return null;
  if (word.length >= 3 && keys.contains(word.substring(0, 3))) {
    return word.substring(0, 3);
  }
  final two = word.substring(0, 2);
  return keys.contains(two) ? two : null;
}

/// Das längste Wort der Eingabe (gefaltet) — oder null unter zwei Zeichen.
String? longestPlaceWord(String query) {
  String? best;
  for (final w in placeNameWords(query)) {
    if (best == null || w.length > best.length) best = w;
  }
  return best;
}

/// Hat [p] ein Wort, das mit [prefix] beginnt? So filtert die Suche die
/// gespeicherten Zellen auf dieselben Einträge, die die Namensdatei des
/// Hosts hätte.
bool placeHasWordStarting(Place p, String prefix) => placeSearchTexts(
  p,
).any((t) => placeNameWords(t).any((w) => w.startsWith(prefix)));

/// Liest eine Zellen- oder Namensdatei. Wirft bei falschem Format;
/// Einträge mit unbekannter Art oder ohne Lage fallen still weg.
List<Place> parsePlaceFile(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  if (json['format'] != 1) {
    throw FormatException('Ortsnamen-Datei: Format ${json['format']}');
  }
  final out = <Place>[];
  for (final el in (json['places'] as List? ?? const [])) {
    if (el is! Map<String, dynamic>) continue;
    final kind = PlaceKind.byName(el['kind'] as String?);
    final lat = el['lat'] as num?;
    final lng = el['lng'] as num?;
    final id = el['id'] as String?;
    final name = el['name'] as String?;
    if (kind == null || lat == null || lng == null || id == null) continue;
    if (name == null || name.isEmpty) continue;
    out.add(
      Place(
        id: id,
        kind: kind,
        name: name,
        alt: el['alt'] as String?,
        position: LatLng(lat.toDouble(), lng.toDouble()),
        ele: (el['ele'] as num?)?.round(),
      ),
    );
  }
  return out;
}
