// Die Rohdaten der Sensoren (#36, Messplan 8.1): der Logger im Isolate des
// Dienstes, ohne Plattform — die Quellen sind Strom-Controller, die
// Brücke eine Map.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_confirm_notify.dart';
import 'package:trailbuddy/features/rides/ride_store.dart';
import 'package:trailbuddy/features/rides/ride_task_handler.dart';
import 'package:trailbuddy/features/rides/sensor_log.dart';
import 'package:trailbuddy/features/rides/wheelie_detector.dart';
import 'package:trailbuddy/features/rides/wheelie_notify.dart';

class FakeWheelieNotices implements WheelieNotices {
  final shown = <(WheelieEvent, String)>[];
  final calls = <String>[];

  @override
  Future<void> wheelie(WheelieEvent event, {required String file}) async {
    shown.add((event, file));
    calls.add('wheelie');
  }

  @override
  Future<void> showMissed({required String file}) async => calls.add('showMissed $file');

  @override
  Future<void> cancelMissed() async => calls.add('cancelMissed');
}

void main() {
  late Directory dir;
  late StreamController<List<double>> accel, gyro, gps;
  late SensorSources sources;
  late Map<String, Object?> bridge;
  late FakeWheelieNotices notices;
  final started = DateTime.utc(2026, 10, 30, 9, 15, 3, 250);
  const every = Duration(milliseconds: 20);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sensors_');
    accel = StreamController<List<double>>.broadcast();
    gyro = StreamController<List<double>>.broadcast();
    gps = StreamController<List<double>>.broadcast();
    sources = SensorSources(accel: () => accel.stream, gyro: () => gyro.stream, gps: () => gps.stream);
    notices = FakeWheelieNotices();
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
  Future<void> tick() =>
      sensorLogTick(sources: sources, read: read, flushEvery: every, notices: notices);
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

  test('ein Wheelie in den Strömen: Zeile e in der Datei, ein Banner, Knopf „verpasst" solange es läuft',
      () async {
    await tick();
    expect(notices.calls, ['showMissed ${logFile().path}']);
    const g = 9.80665;
    final us = t.toInt();
    for (var i = 0; i < 3000; i++) {
      if (i % 100 == 0) gps.add([us + i * 10000.0, 7.1, 9.2, 4.0, 5.0, 800.0]);
      final deg = i >= 2000 && i < 2300 ? 25.0 : 0.0;
      final a = deg * math.pi / 180;
      accel.add([us + i * 10000.0, 0, g * math.sin(a), g * math.cos(a)]);
      if (i % 500 == 0) await Future<void>.delayed(Duration.zero);
    }
    await wait();
    expect(notices.shown, hasLength(1));
    final (event, file) = notices.shown.single;
    expect(file, logFile().path);
    expect((event.startUs - us) / 1e6, closeTo(20.2, 0.3));
    final lines = (await logFile().readAsString()).split('\n');
    expect(lines.where((l) => l.startsWith('e,')), [wheelieEventLine(event).trim()]);
    expect(lines.first, '# trailbuddy sensor log v1');
    expect(kSensorLogHeader, contains('# e,start_us,duration_s'));

    await stopSensorLog();
    expect(notices.calls.last, 'cancelMissed');
  });

  test('die Antwort im Banner: l mit 1 oder 0, „verpasst": m — die Frage an den Trail bleibt unberührt',
      () async {
    final file = logFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(kSensorLogHeader);
    final at = DateTime.utc(2026, 10, 30, 9, 30);
    const start = 1761816600000000;
    final payload = encodeWheeliePayload(file: file.path, startUs: start);
    var confirmed = 0;
    Future<void> noted() async => confirmed++;

    expect(await handleWheelieResponse(actionId: kWheelieYes, payload: payload, now: at), isTrue);
    expect(await handleWheelieResponse(actionId: kWheelieNo, payload: payload, now: at), isTrue);
    expect(
        await handleWheelieResponse(
            actionId: kWheelieMissed,
            payload: encodeWheeliePayload(file: file.path),
            now: at,
            confirmMissed: noted),
        isTrue);
    expect(confirmed, 1, reason: 'die stehende Benachrichtigung zeigt, dass der Tipp ankam');
    expect(await handleWheelieResponse(actionId: null, payload: payload, now: at), isTrue,
        reason: 'Tipp auf das Banner: kein Trail, keine Zeile');

    final us = at.microsecondsSinceEpoch;
    final data = (await file.readAsString()).split('\n').where((l) => l.isNotEmpty && !l.startsWith('#'));
    expect(data, ['l,$us,$start,1', 'l,$us,$start,0', 'm,$us']);

    const trailPayload = '{"dir":"/x","uid":"u","ride":"2026-10-30T09:00:00.000Z","trail":"t"}';
    expect(await handleWheelieResponse(actionId: 'confirm_yes', payload: trailPayload), isFalse);
    expect(await handleWheelieResponse(actionId: null, payload: trailPayload), isFalse);
  });

  test('der EINE Hintergrund-Empfänger des Pakets reicht die Wheelie-Knöpfe weiter', () async {
    final file = logFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(kSensorLogHeader);
    rideConfirmBackgroundResponse(NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: kWheelieNo,
        payload: encodeWheeliePayload(file: file.path, startUs: 42)));
    await wait();
    expect(await file.readAsString(), matches(RegExp(r'\nl,\d+,42,0\n$')));
  });
}
