// Ortsnamen für die Kartensuche (#576 Stufe 2): Arten und Faltung gleich
// mit dem Werkzeug (`tool/pois/places.json`), der Schlüssel der
// Namensdatei, das Manifest, die Suche über vier Abschnitte und die
// Quelle — Host, Zwischenspeicher, Rückfall auf gespeicherte Bereiche.
// Alle Koordinaten sind erfunden (A7).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/search_text.dart';
import 'package:trailbuddy/features/map/map_providers.dart';
import 'package:trailbuddy/features/map/map_regions.dart';
import 'package:trailbuddy/features/map/map_search.dart';
import 'package:trailbuddy/features/map/place.dart';
import 'package:trailbuddy/features/map/place_source.dart';
import 'package:trailbuddy/features/map/poi.dart';

void main() {
  final spec =
      jsonDecode(File('tool/pois/places.json').readAsStringSync())
          as Map<String, dynamic>;

  group('gleich mit dem Werkzeug', () {
    test('Arten in derselben Reihenfolge', () {
      expect(
        [for (final k in PlaceKind.values) k.name],
        [for (final k in spec['kinds'] as List) (k as Map)['kind']],
      );
    });

    test('Faltung und Wörter wie in Python', () {
      for (final c in spec['fold_cases'] as List) {
        expect(foldSearchText(c[0] as String), c[1], reason: '${c[0]}');
      }
      for (final c in spec['word_cases'] as List) {
        expect(placeNameWords(c[0] as String), c[1], reason: '${c[0]}');
      }
    });
  });

  group('Schlüssel der Namensdatei', () {
    test('das längste Wort, der längste Anfang im Index (4, 3, 2)', () {
      expect(placeNameKey('Bad Tölz', {'ba', 'to'}), 'to');
      expect(placeNameKey('Bernau', {'be', 'ber'}), 'ber');
      expect(placeNameKey('Bernau', {'be'}), 'be');
      expect(placeNameKey('Schwarzach', {'sc', 'sch', 'schw'}), 'schw');
      expect(placeNameKey('Sch', {'sc', 'sch', 'schw'}), 'sch');
      expect(placeNameKey('Be', {'be', 'ber'}), 'be');
      expect(placeNameKey('Xyz', {'be'}), isNull, reason: 'nicht im Index');
      expect(placeNameKey('a', {'be'}), isNull, reason: 'zu kurz');
      expect(longestPlaceWord('  -  '), isNull);
    });
  });

  group('Manifest', () {
    Map<String, dynamic> manifest(Object? places) => {
      'format': 1,
      'build': '20261119',
      'prefix': 'pois-20261119',
      'cells': <String, dynamic>{},
      'places': ?places,
    };

    test('Zellen und Schlüssel; was zur Adresse würde, wird geprüft', () {
      final m = PoiManifest.fromJson(
        manifest({
          'cells': ['476,73', 'x,1'],
          'names': ['ho', 'ber', 'schw', '../a', 'abcde', 'Ab'],
        }),
      );
      expect(m.placeCells, {'476,73'});
      expect(m.placeNames, {'ho', 'ber', 'schw'});
    });

    test('ein Bau ohne Ortsnamen liest wie vorher', () {
      final m = PoiManifest.fromJson(manifest(null));
      expect(m.placeCells, isEmpty);
      expect(m.placeNames, isEmpty);
    });
  });

  test('parsePlaceFile: Art, Höhe, deutscher Name; Unbekanntes fällt weg', () {
    final places = parsePlaceFile(
      jsonEncode({
        'format': 1,
        'places': [
          {
            'id': 'node/21',
            'kind': 'peak',
            'name': 'Hörnle',
            'lat': 47.62,
            'lng': 11.01,
            'ele': 1548,
          },
          {
            'id': 'node/20',
            'kind': 'village',
            'name': 'Merano',
            'alt': 'Meran',
            'lat': 46.67,
            'lng': 11.16,
          },
          {'id': 'node/9', 'kind': 'volcano', 'name': 'X', 'lat': 1, 'lng': 1},
          {'id': 'node/8', 'kind': 'peak', 'lat': 1, 'lng': 1},
        ],
      }),
    );
    expect(places.map((p) => p.id), ['node/21', 'node/20']);
    expect(places[0].ele, 1548);
    expect(places[1].alt, 'Meran');
    expect(() => parsePlaceFile('{"format":2}'), throwsFormatException);
  });

  group('Suche über vier Abschnitte', () {
    const center = LatLng(47.6, 11.0);
    const hut = Place(
      id: 'node/24',
      kind: PlaceKind.hut,
      name: 'Hörnle-Hütte',
      position: LatLng(47.61, 11.0),
    );
    const peak = Place(
      id: 'node/21',
      kind: PlaceKind.peak,
      name: 'Hörnle',
      position: LatLng(47.62, 11.01),
    );
    const far = Place(
      id: 'node/30',
      kind: PlaceKind.village,
      name: 'Hörnleberg',
      position: LatLng(48.5, 11.0),
    );
    const merano = Place(
      id: 'node/20',
      kind: PlaceKind.town,
      name: 'Merano',
      alt: 'Meran',
      position: LatLng(46.67, 11.16),
    );

    MapSearchResult search(String q, {List<Poi> pois = const []}) =>
        mapSearchOf(
          query: q,
          center: center,
          trails: const [],
          startPoints: const [],
          pois: pois,
          places: const [far, peak, hut, merano],
          kindLabel: (k) => k.name,
        );

    test('nächste zuerst, auch über den deutschen Namen', () {
      expect(search('hornle').places, [hut, peak, far]);
      expect(search('Meran').places, [merano]);
    });

    test('eine Hütte, die schon unter den Orten steht, nur dort', () {
      final r = search('hornle', pois: [hut.asPoi!]);
      expect(r.pois.map((p) => p.id), ['node/24']);
      expect(r.places, [peak, far]);
    });

    test('geraten wird erst, wenn auch kein Ortsname passt', () {
      final r = search('Hornel');
      expect(r.isGuess, isTrue);
      expect(r.places, containsAll([peak, hut]));
    });
  });

  group('HostPlaceSource', () {
    const center = LatLng(47.6, 11.0);
    final manifest = {
      'format': 1,
      'build': '20261119',
      'prefix': 'pois-20261119',
      'cells': <String, dynamic>{},
      'places': {
        'cells': ['476,73'],
        'names': ['ho', 'me'],
      },
    };
    final ho = {
      'format': 1,
      'key': 'ho',
      'places': [
        {
          'id': 'node/21',
          'kind': 'peak',
          'name': 'Hörnle',
          'lat': 47.62,
          'lng': 11.01,
        },
      ],
    };
    final cell = jsonEncode({
      'format': 1,
      'cell': '476,73',
      'places': [
        {
          'id': 'node/24',
          'kind': 'hut',
          'name': 'Hörnle-Hütte',
          'lat': 47.61,
          'lng': 11.0,
        },
        {
          'id': 'node/25',
          'kind': 'peak',
          'name': 'Zwiesel',
          'lat': 47.6,
          'lng': 11.02,
        },
      ],
    });

    HostPlaceSource source(
      http.Client client, {
      List<String> stored = const [],
    }) => HostPlaceSource(
      client: client,
      regions: () async => const [kDachRegion],
      storedNames: () async => stored,
      readLocal: (n) async => n == '476_73.places.json' ? cell : null,
    );

    test(
      'eine Namensdatei, nur der Schlüssel in der Adresse; gemerkt',
      () async {
        final asked = <String>[];
        final s = source(
          MockClient((req) async {
            asked.add(req.url.toString());
            if (req.url.toString() == kPoiManifestUrl) {
              return http.Response(jsonEncode(manifest), 200);
            }
            return http.Response(jsonEncode(ho), 200);
          }),
        );
        final r = await s.lookup('Hörnle', center);
        expect(r.offline, isFalse);
        expect(r.places.map((p) => p.id), ['node/21']);
        await s.lookup('Hörnlegrat', center);
        expect(asked, [
          kPoiManifestUrl,
          '$kMapTilesBase/pois-20261119/names/ho.json',
        ], reason: 'derselbe Schlüssel fragt nicht noch einmal');
        expect(await s.lookup('Xaver', center), kNoPlaces);
        expect(asked, hasLength(2), reason: '„xa" nennt der Index nicht');
      },
    );

    test('ohne Netz: die Ortsnamen der gespeicherten Bereiche', () async {
      final s = source(
        MockClient((req) async => throw const SocketException('offline')),
        stored: ['476_73.places.json'],
      );
      final r = await s.lookup('Hörnle', center);
      expect(r.offline, isTrue);
      expect(r.places.map((p) => p.id), [
        'node/24',
      ], reason: 'nur, was mit „ho" beginnt — der Zwiesel nicht');
    });

    test('ein Bau ohne Ortsnamen: was liegt, ohne Hinweis', () async {
      final s = source(
        MockClient(
          (req) async =>
              http.Response(jsonEncode({...manifest}..remove('places')), 200),
        ),
        stored: ['476_73.places.json'],
      );
      final r = await s.lookup('Zwiesel', center);
      expect(r.offline, isFalse);
      expect(r.places.map((p) => p.id), ['node/25']);
    });
  });
}
