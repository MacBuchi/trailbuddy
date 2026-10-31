// Rohdaten der Sensoren während einer Fahrt (#36, Konzept Airtime 8.1 und
// 9, Schritte 1+2): ein Mess-Werkzeug, KEINE Erkennung. Nur in der
// Dev-App einschaltbar (`sensorLogAvailableProvider`), nur während einer
// Aufzeichnung, nur im Isolate des Dienstes — dieselbe Regel wie die
// Fahrt (`ride_task_handler.dart`): Das Main-Isolate stirbt beim
// Wegwischen, der Dienst nicht.
//
// Drei Dinge, die man wissen muss:
// - **Die Datei bleibt auf dem Gerät** (`rides/sensors/<Fahrt-ID>.csv`,
//   mit `rides/` vom Backup ausgeschlossen). Sie trägt Koordinaten wie die
//   Fahrt selbst; heraus kommt sie nur über „Sensordaten teilen" an den
//   Rechner des Betreibers, nie ins Repo (A7).
// - **Gesammelt wird im Speicher, geschrieben je [kSensorFlushInterval]**:
//   100 Hz je Sensor einzeln anzuhängen wären 200 Schreibvorgänge je
//   Sekunde. Der Zeitgeber prüft dabei die Brücke — endet die Fahrt, ohne
//   dass ein Takt kommt (der Dienst läuft für einen Download weiter),
//   hört der Logger trotzdem auf.
// - **Wheelies und Sprünge erkennt die Fusion zur Laufzeit**
//   (`sensor_fusion.dart`, seit 0.144.0; vorher die Rohregel) und meldet
//   sie als Banner (`wheelie_notify.dart`); Ereignis und Antwort sind
//   eigene Zeilen derselben Datei (`e`, `j`, `l`, `k`, `m`, `n`, siehe
//   [kSensorLogHeader]). Die Halterung, die sie lernt, liegt für die
//   nächste Fahrt in `rides/sensors/mount.json` und steht im Kopf der
//   Datei — so rechnet das Werkzeug von derselben aus.
// - **Die Zeit ist die des Ereignisses** (`sensors_plus`: Systemstart +
//   Zeitstempel des Sensors, in µs), nicht die der Ankunft im Isolate —
//   der Kanal liefert in Schüben.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'ride_store.dart' show rideIdFor;
import 'ride_task_handler.dart';
import 'sensor_fusion.dart';
import 'wheelie_notify.dart';

/// Schalter der Brücke: Rohdaten mitschreiben (nur Dev-App).
const kRideDataSensorLog = 'ride_sensor_log';

/// Messbereich der Sensoren, `<m/s²>,<rad/s>` — gelesen im Main-Isolate
/// beim Start der Fahrt (der Kanal hängt an der Activity), geschrieben in
/// den Kopf der Datei: Ein Sprung, der am Anschlag landet, misst zu wenig.
const kRideDataSensorRange = 'ride_sensor_range';

/// Der Name steht auch in `MainActivity.kt`; `android_manifest_test` hält
/// beide zusammen.
const kSensorChannel = 'de.mcbuchi.trailbuddy/sensors';

/// Der Messbereich für [kRideDataSensorRange], `<m/s²>,<rad/s>`; leer ohne
/// Kanal (Web, Test) oder ohne Sensor. Wirft nie.
Future<String> readSensorRange() async {
  try {
    final r = await const MethodChannel(kSensorChannel).invokeMapMethod<String, Object?>('range');
    final a = r?['accel'], g = r?['gyro'];
    return a is num && g is num ? '$a,$g' : '';
  } catch (_) {
    return '';
  }
}

/// Die Halterung der letzten Fahrt, in `rides/sensors/`.
const kSensorMountFile = 'mount.json';

/// So oft schreibt der Logger die Halterung auch mitten in der Fahrt —
/// endet der Dienst ohne `stop`, ist sie trotzdem da.
const kSensorMountSaveEvery = Duration(seconds: 60);

/// 100 Hz (Konzept 3): reicht für Flugphasen ab 150 ms und bleibt unter
/// den 200 Hz, ab denen Android `HIGH_SAMPLING_RATE_SENSORS` verlangt.
const kSensorSamplingPeriod = Duration(milliseconds: 10);

/// GPS einmal je Sekunde — der Takt der Fahrt (5 s) ist für „≥ 10 km/h in
/// den 3 s vor dem Absprung" zu grob.
const kSensorGpsInterval = Duration(seconds: 1);

const kSensorFlushInterval = Duration(seconds: 2);

/// Unterordner von `rides/`.
const kSensorDirName = 'sensors';

/// Die erste Zeile jeder Datei: sagt dem Werkzeug
/// (`tool/airtime_measure.py`), was die Spalten heißen.
const kSensorLogHeader = '# trailbuddy sensor log v2\n'
    '# a,t_us,x,y,z = accelerometer incl. gravity (m/s^2)\n'
    '# w,t_us,x,y,z = gyroscope (rad/s)\n'
    '# g,t_us,lat,lng,accuracy_m,speed_mps,alt_m = GPS fix\n'
    '# e,start_us,duration_s,length_m,max_tilt_deg = wheelie detected in the app (fused pitch against the way)\n'
    '# j,start_us,duration_s,landing_g,1|0 = jump detected in the app (1 = plausible)\n'
    '# l,t_us,start_us,1|0 = answer to the wheelie at start_us (1 = "Stimmt")\n'
    '# k,t_us,start_us,1|0 = answer to the jump at start_us (1 = "Stimmt")\n'
    '# m,t_us = "Wheelie verpasst" pressed; n,t_us = "Sprung verpasst" pressed\n'
    '# mount up_xyz forward_xyz = the mount the fusion started from (the last ride), if any\n'
    '# range accel_mps2 gyro_rads = the sensors\' maximum range, if known\n';

/// Der Kopf einer neuen Datei: [kSensorLogHeader], dann die Werte, mit
/// denen diese Fahrt beginnt.
String sensorLogHead({FusionMount? mount, String? range}) {
  final b = StringBuffer(kSensorLogHeader);
  if (mount != null) {
    final (ux, uy, uz) = mount.up;
    final (fx, fy, fz) = mount.forward;
    b.writeln('# mount,${[ux, uy, uz, fx, fy, fz].map((v) => v.toStringAsFixed(6)).join(',')}');
  }
  final r = range?.split(',').map(double.tryParse).toList();
  if (r != null && r.length == 2 && r.every((v) => v != null && v.isFinite)) {
    b.writeln('# range,${r.map((v) => v!.toStringAsFixed(3)).join(',')}');
  }
  return b.toString();
}

String sensorLine(String kind, DateTime at, List<double> values) =>
    '$kind,${at.microsecondsSinceEpoch},${values.map(_num).join(',')}\n';

String wheelieEventLine(WheelieEvent e) => 'e,${e.startUs},'
    '${(e.duration.inMicroseconds / 1e6).toStringAsFixed(2)},'
    '${e.lengthM.toStringAsFixed(1)},${e.maxTiltDeg.toStringAsFixed(1)}\n';

String wheelieAnswerLine(DateTime at, {required int startUs, required bool yes}) =>
    'l,${at.microsecondsSinceEpoch},$startUs,${yes ? 1 : 0}\n';

String wheelieMissedLine(DateTime at) => 'm,${at.microsecondsSinceEpoch}\n';

String jumpEventLine(JumpEvent e) => 'j,${e.startUs},'
    '${(e.duration.inMicroseconds / 1e6).toStringAsFixed(3)},'
    '${e.landingG.toStringAsFixed(2)},${e.plausible ? 1 : 0}\n';

String jumpAnswerLine(DateTime at, {required int startUs, required bool yes}) =>
    'k,${at.microsecondsSinceEpoch},$startUs,${yes ? 1 : 0}\n';

String jumpMissedLine(DateTime at) => 'n,${at.microsecondsSinceEpoch}\n';

/// Kurz genug für 30 MB je Stunde, genau genug für 0,01 m/s².
String _num(double v) => v.isFinite ? v.toStringAsFixed(4) : '';

/// Die Quellen — im Test gegen Strom-Controller getauscht.
class SensorSources {
  const SensorSources({required this.accel, required this.gyro, required this.gps});

  final Stream<List<double>> Function() accel;
  final Stream<List<double>> Function() gyro;
  final Stream<List<double>> Function() gps;

  static final platform = SensorSources(
    accel: () => accelerometerEventStream(samplingPeriod: kSensorSamplingPeriod)
        .map((e) => [e.timestamp.microsecondsSinceEpoch.toDouble(), e.x, e.y, e.z]),
    gyro: () => gyroscopeEventStream(samplingPeriod: kSensorSamplingPeriod)
        .map((e) => [e.timestamp.microsecondsSinceEpoch.toDouble(), e.x, e.y, e.z]),
    gps: () => Geolocator.getPositionStream(
            locationSettings: AndroidSettings(
                accuracy: LocationAccuracy.best, intervalDuration: kSensorGpsInterval))
        .map((p) => [
              p.timestamp.microsecondsSinceEpoch.toDouble(),
              p.latitude,
              p.longitude,
              p.accuracy,
              p.speed,
              p.altitude,
            ]),
  );
}

/// Schreibt die Rohdaten EINER Fahrt in EINE Datei.
class SensorLogger {
  SensorLogger(
      {required this.file,
      SensorSources? sources,
      this.stillWanted,
      this.flushEvery = kSensorFlushInterval,
      this.range,
      WheelieNotices? notices})
      : _sources = sources ?? SensorSources.platform,
        _notices = notices ?? WheelieNotices.platform;

  final File file;
  final SensorSources _sources;

  /// Messbereich aus der Brücke ([kRideDataSensorRange]).
  final String? range;

  /// Fragt beim Schreiben, ob noch gemessen werden soll; `false` beendet.
  final Future<bool> Function()? stillWanted;

  final Duration flushEvery;

  final WheelieNotices _notices;
  SensorFusion _fusion = SensorFusion();
  final _sinceMountSaved = Stopwatch();

  File get _mountFile => File('${file.parent.path}/$kSensorMountFile');

  final _buffer = StringBuffer();
  final _subscriptions = <StreamSubscription<List<double>>>[];
  Timer? _timer;
  Future<void> _writing = Future.value();
  bool _stopped = false;

  bool get running => _timer != null;

  Future<void> start() async {
    await file.parent.create(recursive: true);
    final carried = await _readMount();
    _fusion = SensorFusion(carried: carried);
    if (!await file.exists() || await file.length() == 0) {
      await file.writeAsString(sensorLogHead(mount: carried, range: range), flush: true);
    }
    void listen(String kind, Stream<List<double>> Function() source,
        [void Function(List<double> v)? also]) {
      // Fehlt ein Sensor (`NO_SENSOR`), schreiben die anderen weiter.
      _subscriptions.add(source().listen((v) {
        _buffer.write(sensorLine(
            kind, DateTime.fromMicrosecondsSinceEpoch(v.first.toInt(), isUtc: true), v.sublist(1)));
        also?.call(v);
      }, onError: (Object _) {}));
    }

    listen('a', _sources.accel, (v) => _onEvents(_fusion.addAccel(v[0].toInt(), v[1], v[2], v[3])));
    listen('w', _sources.gyro, (v) => _onEvents(_fusion.addGyro(v[0].toInt(), v[1], v[2], v[3])));
    listen('g', _sources.gps, (v) => _onEvents(_fusion.addGps(v[0].toInt(), v[4])));
    _timer = Timer.periodic(flushEvery, (_) => _onTimer());
    _sinceMountSaved.start();
    await _notices.showMissed(file: file.path);
  }

  void _onEvents(List<FusionEvent> events) {
    for (final event in events) {
      // Nicht abgewartet: Das Banner darf den Strom nicht aufhalten.
      switch (event) {
        case WheelieEvent():
          _buffer.write(wheelieEventLine(event));
          unawaited(_notices.wheelie(event, file: file.path));
        case JumpEvent():
          _buffer.write(jumpEventLine(event));
          unawaited(_notices.jump(event, file: file.path));
      }
    }
  }

  Future<FusionMount?> _readMount() async {
    try {
      return FusionMount.fromJson(jsonDecode(await _mountFile.readAsString()));
    } catch (_) {
      return null; // keine oder kaputte Datei: Die Fahrt lernt von vorn.
    }
  }

  /// Nur eine gelernte Halterung ersetzt die alte. Wirft nie.
  Future<void> _saveMount() async {
    final mount = _fusion.mount;
    if (mount == null) return;
    try {
      final part = File('${_mountFile.path}.part');
      await part.writeAsString(jsonEncode(mount.toJson()), flush: true);
      await part.rename(_mountFile.path);
    } catch (_) {
      // Dann beginnt die nächste Fahrt mit der vorigen oder von vorn.
    }
  }

  Future<void> _onTimer() async {
    final wanted = stillWanted;
    if (wanted != null && !await wanted()) {
      await stop();
      return;
    }
    if (_sinceMountSaved.elapsed >= kSensorMountSaveEvery) {
      _sinceMountSaved.reset();
      await _saveMount();
    }
    await flush();
  }

  /// Hängt an, was sich gesammelt hat. Wirft nie.
  Future<void> flush() => _writing = _writing.then((_) async {
        if (_buffer.isEmpty) return;
        final text = _buffer.toString();
        _buffer.clear();
        try {
          await file.writeAsString(text, mode: FileMode.append, flush: true);
        } catch (_) {
          // Platte voll oder Datei weg: Die Fahrt läuft weiter, die
          // Rohdaten sind ein Zusatz.
        }
      });

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    _onEvents(_fusion.finish());
    await flush();
    await _saveMount();
    await _notices.cancelMissed();
  }
}

/// Der Pfad der Rohdaten zu einer Fahrt unter dem App-Verzeichnis [base].
File sensorLogFile(String base, String rideId) =>
    File('$base/rides/$kSensorDirName/$rideId.csv');

/// Der laufende Logger dieses Isolates, höchstens einer.
SensorLogger? _logger;
String? _loggerRide;

@visibleForTesting
SensorLogger? get currentSensorLogger => _logger;

/// Je Takt des Dienstes: startet den Logger, wenn eine Fahrt mit Schalter
/// läuft und noch keiner schreibt; beendet ihn sonst. Wirft nie.
Future<void> sensorLogTick({
  SensorSources? sources,
  Future<T?> Function<T>(String key)? read,
  Duration flushEvery = kSensorFlushInterval,
  WheelieNotices? notices,
}) async {
  try {
    final get = read ?? _read;
    final ride = await _wantedRide(get);
    if (ride == null) {
      await stopSensorLog();
      return;
    }
    if (_logger != null && _loggerRide == ride.id) return;
    await stopSensorLog();
    final logger = SensorLogger(
      file: sensorLogFile(ride.dir, ride.id),
      sources: sources,
      stillWanted: () async => (await _wantedRide(get))?.id == ride.id,
      flushEvery: flushEvery,
      range: await get<String>(kRideDataSensorRange),
      notices: notices,
    );
    _logger = logger;
    _loggerRide = ride.id;
    await logger.start();
  } catch (_) {
    // Messwerkzeug: Ein Fehler hier darf die Fahrt nicht berühren.
  }
}

Future<void> stopSensorLog() async {
  final logger = _logger;
  _logger = null;
  _loggerRide = null;
  await logger?.stop();
}

Future<T?> _read<T>(String key) => FlutterForegroundTask.getData<T>(key: key);

Future<({String dir, String id})?> _wantedRide(Future<T?> Function<T>(String key) get) async {
  if (await get<bool>(kRideDataActive) != true) return null;
  if (await get<bool>(kRideDataSensorLog) != true) return null;
  final dir = await get<String>(kRideDataDir);
  final started = DateTime.tryParse(await get<String>(kRideDataStartedAt) ?? '');
  if (dir == null || started == null) return null;
  return (dir: dir, id: rideIdFor(started));
}
