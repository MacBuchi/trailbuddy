// Die freie Fahrt (Konzept 2, #484): die Uhr hat keine Linie, das Handy
// sucht den Trail in Reichweite und schickt ihn. `nearestTrailLine` ist die
// Entscheidung, die Tests darunter prüfen die Maschinerie.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trailbuddy/core/connectivity.dart' show noConnectivityProvider;
import 'package:trailbuddy/core/settings.dart' show settingsProvider;
import 'package:trailbuddy/data/providers.dart' show currentUserIdProvider;
import 'package:trailbuddy/features/trails/trail_geometry.dart' show RecordingSource;
import 'package:trailbuddy/features/trails/trail_providers.dart' show trailRepositoryProvider, trailsProvider;
import 'package:trailbuddy/features/garmin/garmin_bridge.dart' show garminBridgeProvider;
import 'package:trailbuddy/features/garmin/watch_branches.dart' show WatchBranch;
import 'package:trailbuddy/features/garmin/watch_free.dart';
import 'package:trailbuddy/features/garmin/watch_providers.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart' show areaHeightReaderProvider;
import 'package:trailbuddy/features/offline_areas/height_tiles.dart' show HeightReader, MemoryHeightSource;
import 'package:trailbuddy/models/trail.dart';
import '../fakes/fake_garmin.dart';
import '../fakes/fake_heights.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart' show FakeTrailRepository;

LatLng at(double lat, double lon) => LatLng(lat, lon);

Trail trail(String id, List<LatLng> pts, {String name = 'Trail'}) => Trail(
      id: id,
      myId: 'me',
      details: [TrailDetails(trailId: id, userId: 'me', name: name)],
      recordings: [
        TrailRecording(
          id: 'rec-$id',
          trailId: id,
          userId: 'me',
          source: RecordingSource.import,
          recordedAt: null,
          reversed: false,
          quality: 0.9,
          createdAt: DateTime(2026, 1, 1),
          points: pts,
          lengthM: lineLengthM(pts),
          ele: List<double>.filled(pts.length, 600),
        ),
      ],
    );

/// Eine gerade Linie von [from] nach [to] mit [n] Punkten.
List<LatLng> line(LatLng from, LatLng to, int n) => [
      for (var i = 0; i < n; i++)
        LatLng(from.latitude + (to.latitude - from.latitude) * i / (n - 1),
            from.longitude + (to.longitude - from.longitude) * i / (n - 1)),
    ];

List<Map<String, Object>> partsOf(FakeGarminBridge bridge, String type) =>
    [for (final batch in bridge.sent) ...batch.where((m) => m['t'] == type)];

/// Warten, bis Routenstücke draußen sind (Höhen und Abzweigungen rechnen).
Future<void> waitRoutes(FakeGarminBridge bridge, {int atLeast = 1}) async {
  for (var i = 0; i < 300 && partsOf(bridge, 'r').length < atLeast; i++) {
    await Future(() {});
  }
}

/// Eine Linie muss da sein — sonst ist der Fall falsch gebaut.
NearestLine lineFor(List<Trail> trails, LatLng at) {
  final found = nearestTrailLine(trails, at);
  if (found == null) throw StateError('keine Linie in Reichweite');
  return found;
}

void main() {
  group('nächste Linie', () {
    // Ein Trail von 48.000 nach 48.010 (≈ 1,1 km), einer von 48.020 nach
    // 48.030 (≈ 1,1 km). Die Uhr steht bei 48.004.
    final near = trail('nah', line(at(48.000, 9.000), at(48.010, 9.000), 11));
    final far = trail('fern', line(at(48.020, 9.000), at(48.030, 9.000), 11));

    test('der nächste in Reichweite, der andere nicht', () {
      final found = lineFor([far, near], at(48.004, 9.0005));
      expect(found.trail.id, 'nah');
      expect(found.distanceM, lessThan(kWatchFreeRadiusM));
    });

    test('liegt nichts in Reichweite, bleibt die Uhr frei', () {
      expect(nearestTrailLine([near, far], at(48.015, 9.020)), isNull);
      expect(nearestTrailLine(const [], at(48.0, 9.0)), isNull);
    });

    test('die Linie fängt dort an, wo die Uhr steht', () {
      final found = lineFor([near], at(48.005, 9.000));
      expect(found.points.first.latitude, closeTo(48.005, 1e-6));
      expect(found.points.last.latitude, closeTo(48.010, 1e-6));
      expect(found.lengthM, closeTo(556, 5));
    });

    test('weitergeht es in die längere Richtung', () {
      // Die Uhr sitzt am Ende der Linie: der Rest nach vorne ist 111 m,
      // zurück 1,1 km. Sie bekommt die lange Seite, rückwärts.
      final found = lineFor([near], at(48.010, 9.000));
      expect(found.points.first.latitude, closeTo(48.010, 1e-6));
      expect(found.points.last.latitude, closeTo(48.000, 1e-6));
      expect(found.lengthM, greaterThan(1000));
    });

    test('ein Stummel ist kein Trail', () {
      // Nur 100 m Linie, die Uhr direkt daneben: zu kurz für eine Fahrt.
      final stub = trail('stummel', line(at(48.004, 9.000), at(48.005, 9.000), 3));
      expect(nearestTrailLine([stub], at(48.004, 9.000)), isNull);
    });

    test('der nächste gewinnt, auch wenn der andere länger ist', () {
      final short = trail('kurz', line(at(48.004, 9.000), at(48.008, 9.000), 5));
      final long = trail('lang', line(at(48.009, 9.000), at(48.020, 9.000), 12));
      expect(nearestTrailLine([long, short], at(48.005, 9.0002))?.trail.id, 'kurz');
    });

    test('die Abschnitte decken genau die Linie', () {
      final found = lineFor([near], at(48.005, 9.000));
      final sec = freeSections(found.trail, found.points).trails.single;
      expect(sec.trailId, 'nah');
      expect(sec.startM, 0);
      expect(sec.endM, closeTo(found.lengthM, 1e-9));
    });
  });

  group('die Uhr bekommt sie', () {
    late FakeGarminBridge bridge;

    ProviderContainer make(List<Trail> trails) {
      final c = ProviderContainer(overrides: [
        garminBridgeProvider.overrideWithValue(bridge),
        trailRepositoryProvider.overrideWithValue(
            FakeTrailRepository(myId: () => 'me')
              ..recordings.addAll([for (final t in trails) ...t.recordings])
              ..details.addAll([for (final t in trails) ...t.details])),
        settingsProvider.overrideWithValue(FakeSettings()),
        currentUserIdProvider.overrideWithValue('me'),
        areaHeightReaderProvider.overrideWith((ref) async =>
            HeightReader([MemoryHeightSource(slopeHeightTiles())])),
        noConnectivityProvider.overrideWithValue(true),
        watchBranchesLoaderProvider.overrideWithValue((line) async => const <WatchBranch>[]),
      ]);
      addTearDown(c.dispose);
      // Die Uhr redet, sobald die App läuft — auch ohne Navigation.
      c.read(watchSyncProvider);
      return c;
    }

    setUp(() => bridge = FakeGarminBridge.connected());

    test('ohne Linie in der Uhr: die nächste in Reichweite geht raus', () async {
      final c = make([trail('nah', line(at(48.000, 9.000), at(48.010, 9.000), 11))]);
      await c.read(trailsProvider.future);
      bridge.answer({'t': 'hi', 'v': 2, 'ver': '1.3.0'});
      bridge.answer({'t': 'g', 'la': 4800500, 'lo': 900010});
      await waitRoutes(bridge);
      final route = partsOf(bridge, 'r');
      expect(route, isNotEmpty);
      // Die Linie fängt am nächstliegenden Punkt des Trails an.
      expect(route.first['o'], [4800500, 900000]);
      expect(route.first['sec'], isNotEmpty);
    });

    test('hat die Uhr schon eine Linie, bleibt sie in Ruhe', () async {
      final c = make([trail('nah', line(at(48.000, 9.000), at(48.010, 9.000), 11))]);
      await c.read(trailsProvider.future);
      bridge.answer({'t': 'hi', 'id': 'alt-1', 'v': 2, 'ver': '1.3.0'});
      bridge.answer({'t': 'g', 'la': 4800500, 'lo': 900010});
      await Future(() {});
      expect(partsOf(bridge, 'r'), isEmpty);
    });

    test('liegt nichts in Reichweite, geht nichts raus', () async {
      final c = make([trail('fern', line(at(48.020, 9.000), at(48.030, 9.000), 11))]);
      await c.read(trailsProvider.future);
      bridge.answer({'t': 'hi', 'v': 2, 'ver': '1.3.0'});
      bridge.answer({'t': 'g', 'la': 4800500, 'lo': 900010});
      await Future(() {});
      expect(partsOf(bridge, 'r'), isEmpty);
    });

    test('die Linie geht nur einmal, nicht bei jedem Stand', () async {
      final c = make([trail('nah', line(at(48.000, 9.000), at(48.010, 9.000), 11))]);
      await c.read(trailsProvider.future);
      bridge.answer({'t': 'hi', 'v': 2, 'ver': '1.3.0'});
      bridge.answer({'t': 'g', 'la': 4800500, 'lo': 900010});
      await waitRoutes(bridge);
      bridge.answer({'t': 'g', 'la': 4800501, 'lo': 900010});
      await Future(() {});
      expect(partsOf(bridge, 'r').length, 1);
    });

    test('driftet die Uhr an einen anderen Trail, geht der', () async {
      final c = make([
        trail('nah', line(at(48.000, 9.000), at(48.010, 9.000), 11)),
        trail('neu', line(at(48.020, 9.000), at(48.030, 9.000), 11)),
      ]);
      await c.read(trailsProvider.future);
      bridge.answer({'t': 'hi', 'v': 2, 'ver': '1.3.0'});
      bridge.answer({'t': 'g', 'la': 4800500, 'lo': 900010});
      await waitRoutes(bridge);
      bridge.answer({'t': 'd', 'la': 4802200, 'lo': 900010, 'off': 500});
      await waitRoutes(bridge, atLeast: 2);
      final route = partsOf(bridge, 'r');
      expect(route.length, greaterThan(1));
      expect(route.last['id'], isNot(route.first['id']));
      expect(route.last['o'], [4802200, 900000]);
    });
  });
}
