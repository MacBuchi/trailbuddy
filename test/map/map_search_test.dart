// Die Suche auf der Karte (#576), pur: Teiltreffer über drei Abschnitte,
// der Tippfehler-Ausgleich nur, wenn KEIN Abschnitt einen Teiltreffer
// hat, die Art eines Ortes als Suchtext, die nächsten zuerst, und die
// Zellen um die Mitte. Alle Koordinaten sind erfunden (A7).
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_search.dart';
import 'package:trailbuddy/features/map/place.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/start_point.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/l10n_de.dart';

/// Ein Trail mit einer Linie aus [points] und einem eigenen Beitrag.
Trail trailFrom(String name, List<LatLng> points) => Trail(
  id: name,
  myId: 'me',
  recordings: [
    TrailRecording(
      id: 'rec-$name',
      trailId: name,
      userId: 'me',
      source: RecordingSource.import,
      recordedAt: null,
      reversed: false,
      quality: 0.5,
      createdAt: DateTime(2026, 9, 1),
      points: points,
      lengthM: 1000,
    ),
  ],
  details: [TrailDetails(trailId: name, userId: 'me', name: name)],
);

/// Ein kurzer Trail, der bei [at] beginnt.
Trail trailAt(String name, LatLng at) =>
    trailFrom(name, [at, LatLng(at.latitude + 0.005, at.longitude)]);

void main() {
  const center = LatLng(47.0, 11.0);

  StartPoint point(String id, String name, LatLng at, {String? username}) =>
      StartPoint(
        clientId: id,
        userId: username == null ? 'me' : 'buddy',
        name: name,
        lat: at.latitude,
        lon: at.longitude,
        createdAt: DateTime.utc(2026, 11, 19),
        username: username,
      );

  Poi poi(String id, PoiKind kind, LatLng at, {String? name}) =>
      Poi(id: id, kind: kind, position: at, name: name);

  MapSearchResult search(
    String query, {
    List<Trail> trails = const [],
    List<StartPoint> startPoints = const [],
    List<Poi> pois = const [],
  }) => mapSearchOf(
    query: query,
    center: center,
    trails: trails,
    startPoints: startPoints,
    pois: pois,
    kindLabel: (k) => k.label(l10nDe),
  );

  test('leere Eingabe: nichts — die Suche ist kein Verzeichnis', () {
    final r = search(
      '  ',
      trails: [trailAt('Hirschsprung', center)],
      pois: [poi('node/1', PoiKind.drinkingWater, center)],
    );
    expect(r.trails, isEmpty);
    expect(r.pois, isEmpty);
    expect(r.isGuess, isFalse);
  });

  test('Teiltreffer in allen drei Abschnitten, Umlaute gefaltet', () {
    final r = search(
      'Rosskopf',
      trails: [trailAt('Roßkopf Süd', center), trailAt('Anderer', center)],
      startPoints: [point('a', 'Parkplatz Roßkopf', center)],
      pois: [poi('node/1', PoiKind.hut, center, name: 'Roßkopfhütte')],
    );
    expect(r.isGuess, isFalse);
    expect([for (final t in r.trails) t.name], ['Roßkopf Süd']);
    expect([for (final p in r.startPoints) p.name], ['Parkplatz Roßkopf']);
    expect([for (final p in r.pois) p.name], ['Roßkopfhütte']);
  });

  test('die Art eines Ortes findet ihn auch ohne Namen', () {
    final r = search(
      'trinkwasser',
      pois: [
        poi('node/1', PoiKind.drinkingWater, center),
        poi('node/2', PoiKind.bikeShop, center, name: 'Radl Huber'),
      ],
    );
    expect([for (final p in r.pois) p.id], ['node/1']);
  });

  test('ein fremder Startpunkt findet sich auch über den Buddy', () {
    final r = search(
      'anni',
      startPoints: [point('a', 'Talboden', center, username: 'anni')],
    );
    expect(r.startPoints, hasLength(1));
  });

  test(
    'Tippfehler nur, wenn NIRGENDS ein Teiltreffer ist — dann über alle Abschnitte',
    () {
      // „Rosskopg" trifft nichts wörtlich; der Roßkopf ist eine Änderung
      // entfernt, der Brunnen gar nicht.
      final guess = search(
        'Rosskopg',
        trails: [trailAt('Roßkopf', center)],
        pois: [poi('node/1', PoiKind.drinkingWater, center)],
      );
      expect(guess.isGuess, isTrue);
      expect(guess.trails, hasLength(1));
      expect(guess.pois, isEmpty);

      // Trifft ein Ort wörtlich, rät die Suche nicht beim Trail.
      final exact = search(
        'Rosskopg',
        trails: [trailAt('Roßkopf', center)],
        pois: [poi('node/1', PoiKind.hut, center, name: 'Rosskopg-Alm')],
      );
      expect(exact.isGuess, isFalse);
      expect(exact.trails, isEmpty);
      expect(exact.pois, hasLength(1));
    },
  );

  test('die nächsten zuerst, je Abschnitt gekappt', () {
    final far = poi('node/far', PoiKind.drinkingWater, const LatLng(47.1, 11));
    final near = poi(
      'node/near',
      PoiKind.drinkingWater,
      const LatLng(47.01, 11),
    );
    final r = search('wasser', pois: [far, near]);
    expect([for (final p in r.pois) p.id], ['node/near', 'node/far']);

    final many = search(
      'wasser',
      pois: [
        for (var i = 0; i < 30; i++)
          poi('node/$i', PoiKind.drinkingWater, LatLng(47 + i / 1000, 11)),
      ],
    );
    expect(many.pois, hasLength(kMapSearchMaxPois));
    expect(many.pois.first.id, 'node/0');
  });

  test('genau vor „beginnt mit" vor „ein Wort" vor dem Rest, dann nah '
      '(#596, Fund aus #576)', () {
    Place place(String id, String name, double lat) => Place(
      id: id,
      kind: PlaceKind.village,
      name: name,
      position: LatLng(lat, 11),
    );
    final r = mapSearchOf(
      query: 'Au',
      center: center,
      trails: const [],
      startPoints: const [],
      pois: const [],
      places: [
        place('n/1', 'Pfaffenau', 47.001),
        place('n/2', 'Bad Au', 47.002),
        place('n/3', 'Aurach', 47.003),
        place('n/4', 'Au', 47.2),
      ],
      kindLabel: (k) => k.label(l10nDe),
    );
    expect(
      [for (final p in r.places) p.name],
      ['Au', 'Aurach', 'Bad Au', 'Pfaffenau'],
    );
    expect(matchRank('au', ['Bad Au']), 2);
    expect(matchRank('grunstein', ['Grünstein']), 0);
  });

  test('ein langer Trail ist nah, wenn er durchs Bild läuft', () {
    // Beginnt 20 km weg, läuft aber an der Mitte vorbei.
    final through = trailFrom('Durchs Bild', [
      const LatLng(47.18, 11.0),
      const LatLng(47.0005, 11.0),
    ]);
    final beside = trailAt('Daneben', const LatLng(47.05, 11.0));
    final r = search('d', trails: [beside, through]);
    expect([for (final t in r.trails) t.name], ['Durchs Bild', 'Daneben']);
  });

  test('gesucht wird in der Zelle der Mitte und ihren acht Nachbarn', () {
    final cells = mapSearchPoiCells(center);
    expect(cells, hasLength(9));
    expect(cells, contains(poiCellOf(center)));
    expect(cells.length, lessThanOrEqualTo(kPoiMaxCells));
    // 20 km nördlich liegt außerhalb.
    expect(cells, isNot(contains(poiCellOf(const LatLng(47.2, 11.0)))));
  });
}
