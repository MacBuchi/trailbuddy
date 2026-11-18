// Die Rückrichtung vom Service-Isolate zur Karte (#28; PilzBuddy #465).
//
// Der Service meldet jeden Takt per `sendDataToMain`, die Karte hört mit
// `addTaskDataCallback`. Dazwischen liegt ein benannter Port, den
// ausschließlich `initCommunicationPort` anlegt — das Paket ruft ihn nie
// von selbst. Fehlt er, geht die Meldung still verloren: kein Fehler,
// keine Spur, nur eine Karte, die einen einzigen Punkt kennt. Geprüft
// wird deshalb dreierlei: dass der Weg trägt, dass er OHNE Port nicht
// trägt, und dass `main()` ihn anlegt.
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_task_handler.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'dart:io';

const _portName = 'flutter_foreground_task/isolateComPort';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final point = RidePoint(
    lat: 47.26,
    lng: 11.39,
    at: DateTime.utc(2026, 9, 28, 10, 1),
    accuracyM: 5,
    altM: 700,
  );

  tearDown(() {
    for (final callback in [...FlutterForegroundTask.dataCallbacks]) {
      FlutterForegroundTask.removeTaskDataCallback(callback);
    }
    IsolateNameServer.removePortNameMapping(_portName);
  });

  test(
    'ein gemeldeter Punkt erreicht die Karte, wenn der Port steht',
    () async {
      FlutterForegroundTask.initCommunicationPort();
      final seen = <RidePoint>[];
      FlutterForegroundTask.addTaskDataCallback((data) {
        final decoded = decodeRideTick(data);
        if (decoded != null) seen.add(decoded);
      });
      FlutterForegroundTask.sendDataToMain(encodeRideTick(point));
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));
      expect(seen.single.lat, point.lat);
      expect(seen.single.altM, 700);
    },
  );

  test('ohne angelegten Port geht die Meldung still verloren', () async {
    final seen = <Object>[];
    FlutterForegroundTask.addTaskDataCallback(seen.add);
    FlutterForegroundTask.sendDataToMain(encodeRideTick(point));
    await Future<void>.delayed(Duration.zero);
    expect(
      seen,
      isEmpty,
      reason: 'genau diese Stille trug den Fehler in PilzBuddy',
    );
  });

  test('main() legt den Port an, vor runApp', () {
    final main = File('lib/main.dart').readAsStringSync();
    final init = main.indexOf('initRideCommunication();');
    expect(init, greaterThan(0));
    expect(init, lessThan(main.indexOf('runApp(')));
  });
}
