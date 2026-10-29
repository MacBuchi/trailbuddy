// Die Rohdaten der Sensoren (#36, Messplan 8.1): der Logger im Isolate des
// Dienstes, ohne Plattform — die Quellen sind Strom-Controller, die
// Brücke eine Map.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_store.dart';
import 'package:trailbuddy/features/rides/ride_task_handler.dart';
import 'package:trailbuddy/features/rides/sensor_log.dart';

void main() {
  late Directory dir;
  late StreamController<List<double>> accel, gyro, gps;
  late SensorSources sources;
  late Map<String, Object?> bridge;
  final started = DateTime.utc(2026, 10, 30, 9, 15, 3, 250);
  const every = Duration(milliseconds: 20);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sensors_');
    accel = StreamController<List<double>>.broadcast();
    gyro = StreamController<List<double>>.broadcast();
    gps = StreamController<List<double>>.broadcast();
    sources = SensorSources(accel: () => accel.stream, gyro: () => gyro.stream, gps: () => gps.stream);
    bridge = {
      kRideDataActive: true,
      kRideDataSensorLog: true,
      kRideDataDir: dir.path,
      kRideDataStartedAt: started.toIso8601String(),
    };
  });

  tearDown(() async {
    await stopSensorLog();
    await dir.delete(recursive: true);
  });

  Future<T?> read<T>(String key) async => bridge[key] as T?;
  Future<void> tick() => sensorLogTick(sources: sources, read: read, flushEvery: every);
  Future<void> wait() => Future<void>.delayed(every * 4);
  File logFile() => sensorLogFile(dir.path, '20261030T091503Z');
  final t = DateTime.utc(2026, 10, 30, 9, 16).microsecondsSinceEpoch.toDouble();

  test('Fahrt mit Schalter: Kopf, dann je Ereignis eine Zeile mit der Zeit des Sensors', () async {
    await tick();
    expect(currentSensorLogger?.running, isTrue);
    expect(logFile().path, endsWith('/rides/sensors/20261030T091503Z.csv'),
        reason: 'dieselbe Kennung wie die Fahrt, unter rides/ (Backup-Ausschluss)');
    accel.add([t, 0.1, 9.81, -0.25]);
    gyro.add([t + 10000, 0.01, -0.02, 0.5]);
    gps.add([t + 20000, 7.1, 9.2, 4.5, 6.25, 812.0]);
    await wait();

    final lines = (await logFile().readAsString()).split('\n');
    expect(lines.first, '# trailbuddy sensor log v1');
    final data = lines.where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
    expect(data, [
      'a,${t.toInt()},0.1000,9.8100,-0.2500',
      'w,${t.toInt() + 10000},0.0100,-0.0200,0.5000',
      'g,${t.toInt() + 20000},7.1000,9.2000,4.5000,6.2500,812.0000',
    ]);
  });

  test('ohne Schalter oder ohne Fahrt schreibt niemand', () async {
    bridge[kRideDataSensorLog] = false;
    await tick();
    expect(currentSensorLogger, isNull);
    bridge[kRideDataSensorLog] = true;
    bridge[kRideDataActive] = false;
    await tick();
    expect(currentSensorLogger, isNull);
    expect(await logFile().exists(), isFalse);
  });

  test('ein zweiter Takt startet keinen zweiten Logger', () async {
    await tick();
    final first = currentSensorLogger;
    await tick();
    expect(currentSensorLogger, same(first));
    expect(accel.hasListener, isTrue);
  });

  test('endet die Fahrt ohne Takt, hört der Logger beim nächsten Schreiben selbst auf', () async {
    await tick();
    final logger = currentSensorLogger!;
    accel.add([t, 0, 0, 9.81]);
    bridge[kRideDataActive] = false;
    await wait();
    expect(logger.running, isFalse);
    expect(accel.hasListener, isFalse, reason: 'der Sensor ist abgemeldet');
    expect(await logFile().readAsString(), contains('a,${t.toInt()},'),
        reason: 'was gesammelt war, steht noch in der Datei');
  });

  test('eine neue Fahrt schreibt in ihre eigene Datei', () async {
    await tick();
    final first = currentSensorLogger!;
    bridge[kRideDataStartedAt] = DateTime.utc(2026, 10, 30, 11).toIso8601String();
    await tick();
    expect(first.running, isFalse);
    expect(currentSensorLogger!.file.path, endsWith('20261030T110000Z.csv'));
  });

  test('Löschen der Fahrt nimmt die Rohdaten mit; der Pfad nur, wenn es sie gibt', () async {
    final store = FileRideStore(baseDir: dir);
    const id = '20261030T091503Z';
    expect(await store.sensorLogPath(id), isNull);
    await logFile().parent.create(recursive: true);
    await logFile().writeAsString(kSensorLogHeader);
    expect(await store.sensorLogPath(id), logFile().path);
    expect(await store.sensorLogPath('../x'), isNull);
    await store.delete(id);
    expect(await logFile().exists(), isFalse);
  });
}
