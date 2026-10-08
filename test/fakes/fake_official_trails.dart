import 'dart:convert';

import 'package:trailbuddy/features/official/official_trails_source.dart';

/// Der Daten-Branch aus dem Speicher — kein Netz in Tests. Merkt sich
/// jede Anfrage, damit Tests zählen können, WANN gefragt wird.
class FakeOfficialTrailsSource implements OfficialTrailsSource {
  FakeOfficialTrailsSource([Map<String, String>? files]) : files = files ?? {};

  /// Leer: Es gibt keine Regionen (so startet jeder andere Test).
  final Map<String, String> files;
  final asked = <String>[];

  /// Gesetzt: Jede Anfrage scheitert damit (Funkloch).
  Object? failWith;

  @override
  Future<String> fetch(String file) async {
    asked.add(file);
    final f = failWith;
    if (f != null) throw f;
    return files[file] ??
        (file == 'index.json'
            ? jsonEncode({'version': 1, 'regions': [], 'sources': {}})
            : throw const OfficialTrailsUnavailable(404));
  }
}

/// Der Gerätespeicher im Speicher; ein Test, der den Neustart nachstellt,
/// gibt dieselbe Instanz an den zweiten Start weiter.
class MemoryOfficialTrailsCache implements OfficialTrailsCache {
  final files = <String, String>{};

  @override
  Future<String?> read(String name) async => files[name];

  @override
  Future<void> write(String name, String body) async => files[name] = body;
}

/// Eine kleine Region mit ausgedachten Koordinaten (nahe dem Ort, an dem
/// `seedTrail` seine Trails anlegt, damit die Karte dort hinzoomt).
String fakeIndex({String updated = '2026-09-01'}) => jsonEncode({
      'version': 1,
      'regions': [
        {
          'id': 'testland',
          'file': 'testland.geojson',
          'bbox': [8.9, 47.9, 9.1, 48.1],
          'count': 2,
          'updated': updated,
          'sources': ['testland'],
        },
      ],
      'sources': {
        'testland': {
          'name': 'Land Testland – Singletrails',
          'attribution': 'Land Testland',
          'license': 'CC0 1.0',
          'url': 'https://example.org/trails',
        },
      },
    });

/// Ein offizieller Trail genau auf der Linie, die `seedTrail` mit den
/// Vorgaben anlegt (Länge 9,0 von Breite 48,0 bis 48,009) — für „Auch
/// ausgeschildert als …".
Map<String, Object> fakeOnRoots({String status = 'closed', String? updated}) => {
      'type': 'Feature',
      'id': 'testland:3',
      'geometry': {
        'type': 'MultiLineString',
        'coordinates': [
          [[9.00003, 48.0], [9.00003, 48.0045], [9.00003, 48.009]],
        ],
      },
      'properties': {
        'name': 'Wurzelpfad',
        'kind': 'trail',
        'difficulty': 'leicht',
        'status': status,
        'sections': [{'variant': false, 'closed': status == 'closed'}],
        'source': 'testland',
        'updated': ?updated,
      },
    };

String fakeRegion({String name = 'Flowline', List<Map<String, Object>> extra = const []}) =>
    jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'id': 'testland:1',
          'geometry': {
            'type': 'MultiLineString',
            'coordinates': [
              [[9.002, 48.003], [9.004, 48.003]],
              [[9.002, 48.006], [9.004, 48.006]],
            ],
          },
          'properties': {
            'name': name,
            'kind': 'trail',
            'difficulty': 'mittelschwierig',
            'level': 'medium',
            'status': 'partly_closed',
            'sections': [
              {'variant': false, 'closed': false},
              {'variant': true, 'closed': true},
            ],
            'length_m': 1234,
            'up_m': 10,
            'down_m': 180,
            'description': 'Ein ausgedachter Trail für Tests.',
            'source': 'testland',
            'updated': '2026-05-19',
          },
        },
        {
          'type': 'Feature',
          'id': 'testland:2',
          'geometry': {'type': 'Point', 'coordinates': [9.0, 48.0]},
          'properties': {'name': 'Kaputt', 'source': 'testland'},
        },
        ...extra,
      ],
    });
