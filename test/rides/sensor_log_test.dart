// Die Rohdaten der Sensoren (#36, Messplan 8.1): der Logger im Isolate des
// Dienstes, ohne Plattform — die Quellen sind Strom-Controller, die
// Brücke eine Map.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_confirm_notify.dart';
import 'package:trailbuddy/features/rides/ride_store.dart';
import 'package:trailbuddy/features/rides/ride_task_handler.dart';
import 'package:trailbuddy/features/rides/airtime_message.dart';
import 'package:trailbuddy/features/rides/sensor_fusion.dart';
import 'package:trailbuddy/features/rides/sensor_log.dart';
import 'package:trailbuddy/features/rides/wheelie_notify.dart';

class FakeWheelieNotices implements WheelieNotices {
  final shown = <(FusionEvent, String)>[];
  final calls = <String>[];

  @override
  Future<void> wheelie(WheelieEvent event, {required String file}) async {
    shown.add((event, file));
    calls.add('wheelie');
  }

  @override
  Future<void> jump(JumpEvent event, {required String file}) async {
    shown.add((event, file));
    calls.add('jump');
  }

  @override
  Future<void> stoppie(StoppieEvent event, {required String file}) async {
    shown.add((event, file));
    calls.add('stoppie');
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
  late List<Object> toApp;
  final started = DateTime.utc(2026, 10, 30, 9, 15, 3, 250);
  const every = Duration(milliseconds: 20);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sensors_');
    accel = StreamController<List<double>>.broadcast();
    gyro = StreamController<List<double>>.broadcast();
    gps = StreamController<List<double>>.broadcast();
    sources = SensorSources(accel: () => accel.stream, gyro: () => gyro.stream, gps: () => gps.stream);
    notices = FakeWheelieNotices();
    toApp = [];
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
      sensorLogTick(sources: sources, read: read, flushEvery: every, notices: notices, toApp: toApp.add);
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
    expect(lines.first, '# trailbuddy sensor log v3');
    expect(lines.where((l) => l.startsWith('# mount,') || l.startsWith('# range,')), isEmpty,
        reason: 'ohne Halterung der letzten Fahrt und ohne Messbereich keine Zeile');
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

  test('Wheelie, Sprung und Stoppie in den Strömen: Zeilen e, j und s, je ein Banner, die Halterung für die nächste Fahrt',
      () async {
    // Die Halterung der letzten Fahrt: Telefon flach, oben = z, vorn = x.
    final mountFile = File('${dir.path}/rides/sensors/$kSensorMountFile');
    await mountFile.parent.create(recursive: true);
    await mountFile.writeAsString(
        jsonEncode(const FusionMount(up: (0.0, 0.0, 1.0), forward: (1.0, 0.0, 0.0)).toJson()));
    bridge[kRideDataSensorRange] = '78.453,34.907';
    await tick();
    expect(notices.calls, ['showMissed ${logFile().path}']);
    const g = 9.80665;
    final us = t.toInt();
    // 40 s mit 5 m/s; Front hoch um 25° von 20 bis 23 s (der Kreisel dreht
    // mit), frei fallend 30,0–30,5 s und Landung mit 3 g; Stoppie: ab 35 s
    // bremsen mit 2,5 m/s² bis 1 m/s, die Front 18° unten von 35,3 bis
    // 36,6 s, dann wieder antreten.
    double ramp(double s, double t0, double t1) => math.max(0.0, math.min(1.0, math.min((s - t0) / 0.3, (t1 - s) / 0.3)));
    double pitch(double s) => math.pi / 180 * (25 * ramp(s, 20, 23) - 18 * ramp(s, 35.3, 36.6));
    double speed(double s) => s < 35
        ? 5.0
        : s < 36.6
            ? 5 - 2.5 * (s - 35)
            : math.min(5.0, 1 + 2 * (s - 36.6));
    for (var i = 0; i < 4000; i++) {
      final s = i / 100;
      final at = us + i * 10000.0;
      if (i % 100 == 0) gps.add([at, 7.1, 9.2, 4.0, speed(s), 800.0]);
      final p = pitch(s);
      final dv = (speed(s + 0.005) - speed(s - 0.005)) / 0.01;
      var f = [g * math.sin(p) + dv * math.cos(p), 0.0, g * math.cos(p) - dv * math.sin(p)];
      if (s >= 30 && s < 30.5) f = [0.0, 0.0, 0.0];
      if (s >= 30.5 && s < 30.55) f = [0.0, 0.0, 3 * g];
      accel.add([at, ...f]);
      gyro.add([at + 2000, 0.0, -(pitch(s + 0.005) - pitch(s - 0.005)) / 0.01, 0.0]);
      if (i % 500 == 0) await Future<void>.delayed(Duration.zero);
    }
    await wait();
    await stopSensorLog();

    expect(notices.calls, ['showMissed ${logFile().path}', 'wheelie', 'jump', 'stoppie', 'cancelMissed']);
    final wheelie = notices.shown[0].$1 as WheelieEvent;
    final jump = notices.shown[1].$1 as JumpEvent;
    expect(notices.shown.map((e) => e.$2), everyElement(logFile().path));
    expect((wheelie.startUs - us) / 1e6, closeTo(20.2, 0.2));
    expect(wheelie.duration.inMilliseconds / 1000, closeTo(2.8, 0.3));
    expect(wheelie.maxTiltDeg, closeTo(25, 2));
    expect((jump.startUs - us) / 1e6, closeTo(30.0, 0.05));
    expect(jump.landingG, closeTo(3, 0.1));
    expect(jump.plausible, isTrue);
    final stoppie = notices.shown[2].$1 as StoppieEvent;
    expect((stoppie.startUs - us) / 1e6, closeTo(35.4, 0.3));
    expect(stoppie.maxTiltDeg, greaterThan(12));
    expect(stoppie.decel, greaterThan(kFusionStoppieDecel));

    final lines = (await logFile().readAsString()).split('\n');
    expect(lines.first, '# trailbuddy sensor log v3');
    expect(lines, contains('# mount,0.000000,0.000000,1.000000,1.000000,0.000000,0.000000'));
    expect(lines, contains('# range,78.453,34.907'));
    expect(lines.where((l) => l.startsWith('e,')), [wheelieEventLine(wheelie).trim()]);
    expect(lines.where((l) => l.startsWith('j,')), [jumpEventLine(jump).trim()]);
    expect(jumpEventLine(jump), matches(RegExp(r'^j,\d+,0\.\d{3},3\.\d\d,1\n$')));
    expect(lines.where((l) => l.startsWith('s,')), [stoppieEventLine(stoppie).trim()]);
    expect(stoppieEventLine(stoppie), matches(RegExp(r'^s,\d+,\d\.\d\d,\d+\.\d,\d\.\d\d,\d\.\d\d\n$')));

    // Die offene App bekommt dieselben drei Ereignisse und die Takte dazu.
    final messages = toApp.map(decodeAirtimeMessage).toList();
    expect(messages, everyElement(isNotNull));
    expect(messages.map((m) => m!.file), everyElement(logFile().path));
    final sent = [for (final m in messages.whereType<AirtimeEventMessage>()) m.event];
    expect(sent.map((e) => '${e.runtimeType} ${e.startUs}'),
        [wheelie, jump, stoppie].map((e) => '${e.runtimeType} ${e.startUs}'));
    final ticks = [for (final m in messages.whereType<AirtimeLiveMessage>()) ...m.ticks];
    expect(ticks.length, closeTo(400, 30), reason: '40 s mit 10 Hz');
    final up = ticks.firstWhere((l) => l.tUs >= us + 22000000);
    expect(up.phase, FusionPhase.wheelie);
    expect(up.pitchDeg, closeTo(25, 2));

    final saved = FusionMount.fromJson(jsonDecode(await mountFile.readAsString()))!;
    expect(saved.up.$3, closeTo(1, 1e-3), reason: 'die gelernte Halterung liegt für die nächste Fahrt bereit');
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
    expect(await handleWheelieResponse(actionId: kJumpYes, payload: payload, now: at), isTrue);
    expect(await handleWheelieResponse(actionId: kJumpNo, payload: payload, now: at), isTrue);
    expect(
        await handleWheelieResponse(
            actionId: kJumpMissed,
            payload: encodeWheeliePayload(file: file.path),
            now: at,
            confirmMissed: noted),
        isTrue);
    expect(confirmed, 2);
    expect(await handleWheelieResponse(actionId: kStoppieYes, payload: payload, now: at), isTrue);
    expect(await handleWheelieResponse(actionId: kStoppieNo, payload: payload, now: at), isTrue);
    expect(
        await handleWheelieResponse(
            actionId: kStoppieMissed,
            payload: encodeWheeliePayload(file: file.path),
            now: at,
            confirmMissed: noted),
        isTrue);
    expect(confirmed, 3);
    expect(data, ['l,$us,$start,1', 'l,$us,$start,0', 'm,$us']);
    final all = (await file.readAsString()).split('\n').where((l) => l.isNotEmpty && !l.startsWith('#'));
    expect(all.skip(3), ['k,$us,$start,1', 'k,$us,$start,0', 'n,$us', 'p,$us,$start,1', 'p,$us,$start,0', 'q,$us']);

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
