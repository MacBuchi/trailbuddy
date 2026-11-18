// Der Takt im Service-Isolate (#28; PilzBuddy #342). Geprüft über die
// eingebauten Nähte (`fix`, `storeFor`), nicht gegen echtes GPS: Was
// zählt, sind die Regeln drumherum — schreibt er nur, wenn eine Fahrt
// läuft, und übersteht er einen Fehlschlag.
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailbuddy/features/rides/ride_task_handler.dart';

import '../fakes/fake_rides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime.utc(2026, 9, 28, 10);
  Position positionAt() => Position(
    latitude: 47.2,
    longitude: 11.4,
    timestamp: at,
    accuracy: 6,
    altitude: 812,
    altitudeAccuracy: 3,
    heading: 0,
    headingAccuracy: 0,
    speed: 4,
    speedAccuracy: 1,
  );

  /// Die Brücke liegt in SharedPreferences — `saveData`/`getData` lesen
  /// sie in BEIDEN Isolaten, deshalb ist sie hier mockbar.
  Future<void> bridge({required bool active, String dir = '/tmp/ride'}) async {
    SharedPreferences.setMockInitialValues({});
    if (dir.isNotEmpty) {
      await FlutterForegroundTask.saveData(key: kRideDataDir, value: dir);
    }
    await FlutterForegroundTask.saveData(key: kRideDataActive, value: active);
  }

  test('läuft eine Fahrt, wird gemessen und angehängt — samt Höhe', () async {
    await bridge(active: true);
    final store = FakeRideStore();
    await store.begin(uid: 'me', startedAt: at);
    final point = await recordRideTick(
      fix: () async => positionAt(),
      storeFor: (_) => store,
    );
    expect(point, isNotNull);
    expect(point!.accuracyM, 6);
    expect(point.altM, 812);
    expect(store.points, hasLength(1));
    expect(store.points.single.at, at);
  });

  test('ohne laufende Fahrt wird GPS gar nicht erst gefragt', () async {
    await bridge(active: false);
    final store = FakeRideStore();
    var asked = 0;
    final point = await recordRideTick(
      fix: () async {
        asked++;
        return positionAt();
      },
      storeFor: (_) => store,
    );
    expect(point, isNull);
    expect(store.points, isEmpty);
    expect(asked, 0);
  });

  test('ohne Pfad in der Brücke passiert nichts', () async {
    await bridge(active: true, dir: '');
    final store = FakeRideStore();
    expect(
      await recordRideTick(
        fix: () async => positionAt(),
        storeFor: (_) => store,
      ),
      isNull,
    );
    expect(store.points, isEmpty);
  });

  test('kein Fix ist kein Fehler, ein werfender Fix beendet nichts', () async {
    await bridge(active: true);
    final store = FakeRideStore();
    expect(
      await recordRideTick(fix: () async => null, storeFor: (_) => store),
      isNull,
    );
    expect(
      await recordRideTick(
        fix: () async => throw Exception('GPS weg'),
        storeFor: (_) => store,
      ),
      isNull,
    );
    expect(store.points, isEmpty);
  });
}
