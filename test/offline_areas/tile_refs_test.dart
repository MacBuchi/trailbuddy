// Das Alter je Kachel (#229 Schritt 4, Konzept 8.2): veraltet ist eine
// LIEGENDE Kachel, die eine Form deckt und aus einem älteren Bau stammt.
// Was fehlt, ist nicht veraltet — das holt „Fortsetzen".
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/offline_areas/tile_refs.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';

void main() {
  final index = {
    1: const StoredTileInfo(10, '20260901'),
    2: const StoredTileInfo(20, '20261001'),
    3: const StoredTileInfo(30, '20261101'),
    4: const StoredTileInfo(40, '20260901'),
  };

  test('nur liegende, gedeckte Kacheln älterer Bauten, mit ihren Bytes', () {
    final s = staleTiles(index, {1, 2, 3, 5}, '20261001');
    expect(s.ids, [1], reason: '4 deckt keine Form mehr, 5 liegt nicht, 2 und 3 sind nicht älter');
    expect(s.bytes, 10);
  });

  test('ohne Bau des Hosts ist nichts veraltet', () {
    expect(staleTiles(index, {1, 2, 3, 4}, null).ids, isEmpty);
  });

  test('sortiert, damit die Blöcke zusammenhängend bleiben', () {
    expect(staleTiles(index, {4, 1, 2}, '20261201').ids, [1, 2, 4]);
  });
}
