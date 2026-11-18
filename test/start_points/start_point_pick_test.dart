// Die Liste „Gemerkt" und die Vorbelegung vor Ort (#543 Schritt 3,
// Konzept Startpunkte 5.1 und 9) — pur. Erfundene Lagen (A7).
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/routing/start_point_pick.dart';
import 'package:trailbuddy/models/start_point.dart';

void main() {
  StartPoint p(String owner, String id, String name, double lat, double lon) =>
      StartPoint(
        clientId: id,
        userId: owner,
        name: name,
        lat: lat,
        lon: lon,
        createdAt: DateTime.utc(2026, 11, 17),
      );

  const from = LatLng(47.5, 10.5);
  final near = p('me', 'a', 'Nah', 47.501, 10.5); // ~111 m
  final far = p('me', 'b', 'Fern', 47.53, 10.5); // ~3,3 km
  final mid = p('ben', 'c', 'Mitte', 47.51, 10.5); // ~1,1 km
  // Ein fremder Punkt 10 m neben dem eigenen: die 30-m-Regel.
  final shadow = p('ben', 'd', 'Schatten', 47.50109, 10.5);

  test('nach Abstand, die 30-m-Regel wie auf der Karte', () {
    final c = startPointChoices([far, mid, near, shadow], 'me', from: from);
    expect(c.map((x) => x.point.name), ['Nah', 'Mitte', 'Fern']);
    expect(c.first.distanceM, closeTo(111, 2));
  });

  test('der zuletzt gewählte oben', () {
    final c = startPointChoices(
      [far, mid, near],
      'me',
      from: from,
      lastKey: far.key,
    );
    expect(c.map((x) => x.point.name), ['Fern', 'Nah', 'Mitte']);
  });

  test('ohne Ursprung nach Namen, ohne Abstand', () {
    final c = startPointChoices([near, far, mid], 'me');
    expect(c.map((x) => x.point.name), ['Fern', 'Mitte', 'Nah']);
    expect(c.every((x) => x.distanceM == null), isTrue);
  });

  test('vorbelegt nur bis 300 m, der nächste gewinnt', () {
    expect(nearbyStartPoint([far, mid], 'me', from), isNull);
    expect(nearbyStartPoint([far, near, mid], 'me', from), same(near));
    final edge = p('me', 'e', 'Rand', 47.5026, 10.5); // ~289 m
    final over = p('me', 'f', 'Drüber', 47.5028, 10.5); // ~311 m
    expect(nearbyStartPoint([edge], 'me', from), same(edge));
    expect(nearbyStartPoint([over], 'me', from), isNull);
  });
}
