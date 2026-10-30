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
// - **Wheelies werden zur Laufzeit erkannt** (`wheelie_detector.dart`) und
//   als Banner gemeldet (`wheelie_notify.dart`); Ereignis und Antwort sind
//   eigene Zeilen derselben Datei (`e`, `l`, `m`, siehe [kSensorLogHeader]).
// - **Die Zeit ist die des Ereignisses** (`sensors_plus`: Systemstart +
//   Zeitstempel des Sensors, in µs), nicht die der Ankunft im Isolate —
//   der Kanal liefert in Schüben.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'ride_store.dart' show rideIdFor;
import 'ride_task_handler.dart';
import 'wheelie_detector.dart';
import 'wheelie_notify.dart';

/// Schalter der Brücke: Rohdaten mitschreiben (nur Dev-App).
const kRideDataSensorLog = 'ride_sensor_log';

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
const kSensorLogHeader = '# trailbuddy sensor log v1\n'
    '# a,t_us,x,y,z = accelerometer incl. gravity (m/s^2)\n'
    '# w,t_us,x,y,z = gyroscope (rad/s)\n'
    '# g,t_us,lat,lng,accuracy_m,speed_mps,alt_m = GPS fix\n'
    '# e,start_us,duration_s,length_m,max_tilt_deg = wheelie detected in the app\n'
    '# l,t_us,start_us,1|0 = answer to the wheelie at start_us (1 = "Stimmt")\n'
    '# m,t_us = "Wheelie verpasst" pressed\n';

String sensorLine(String kind, DateTime at, List<double> values) =>
    '$kind,${at.microsecondsSinceEpoch},${values.map(_num).join(',')}\n';

String wheelieEventLine(WheelieEvent e) => 'e,${e.startUs},'
    '${(e.duration.inMicroseconds / 1e6).toStringAsFixed(2)},'
    '${e.lengthM.toStringAsFixed(1)},${e.maxTiltDeg.toStringAsFixed(1)}\n';

String wheelieAnswerLine(DateTime at, {required int startUs, required bool yes}) =>
    'l,${at.microsecondsSinceEpoch},$startUs,${yes ? 1 : 0}\n';

String wheelieMissedLine(DateTime at) => 'm,${at.microsecondsSinceEpoch}\n';

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
      WheelieNotices? notices})
      : _sources = sources ?? SensorSources.platform,
        _notices = notices ?? WheelieNotices.platform;

  final File file;
  final SensorSources _sources;

  /// Fragt beim Schreiben, ob noch gemessen werden soll; `false` beendet.
  final Future<bool> Function()? stillWanted;

  final Duration flushEvery;

  final WheelieNotices _notices;
  final _wheelies = WheelieDetector();

  final _buffer = StringBuffer();
  final _subscriptions = <StreamSubscription<List<double>>>[];
  Timer? _timer;
  Future<void> _writing = Future.value();
  bool _stopped = false;

  bool get running => _timer != null;

  Future<void> start() async {
    await file.parent.create(recursive: true);
    if (!await file.exists() || await file.length() == 0) {
      await file.writeAsString(kSensorLogHeader, flush: true);
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

    listen('a', _sources.accel, _onAccel);
    listen('w', _sources.gyro);
    listen('g', _sources.gps, (v) => _wheelies.addSpeed(v[4]));
    _timer = Timer.periodic(flushEvery, (_) => _onTimer());
    await _notices.showMissed(file: file.path);
  }

  void _onAccel(List<double> v) {
    final event = _wheelies.addAccel(v[0].toInt(), v[1], v[2], v[3]);
    if (event == null) return;
    _buffer.write(wheelieEventLine(event));
    // Nicht abgewartet: Das Banner darf den Strom nicht aufhalten.
    unawaited(_notices.wheelie(event, file: file.path));
  }

  Future<void> _onTimer() async {
    final wanted = stillWanted;
    if (wanted != null && !await wanted()) {
      await stop();
      return;
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
    await flush();
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
