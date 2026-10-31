// Rechnet eine Rohdaten-Datei durch die Fusion der App
// (`lib/features/rides/sensor_fusion.dart`, #36 Schritt 4) und listet die
// Ereignisse wie `tool/airtime_measure.py --fused --list` (Mahony) — die
// Gegenprobe „Dart und Werkzeug finden dieselben Ereignisse". Die Datei
// bleibt auf dem Rechner des Betreibers; ausgegeben werden nur Zeiten ab
// Dateibeginn, Dauern und Zählungen.
//
//     dart run tool/fusion_replay.dart ride.csv
import 'dart:io';

import 'package:trailbuddy/features/rides/sensor_fusion.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/fusion_replay.dart ride.csv');
    exit(64);
  }
  final lines = await File(args.single).readAsLines();
  FusionMount? carried;
  int? origin;
  final rows = <(String, int, List<double>)>[];
  for (final line in lines) {
    if (line.startsWith('# mount,')) {
      final v = line.substring(8).split(',').map(double.tryParse).toList();
      if (v.length == 6 && !v.contains(null)) {
        carried = FusionMount(up: (v[0]!, v[1]!, v[2]!), forward: (v[3]!, v[4]!, v[5]!));
      }
      continue;
    }
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(',');
    final t = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (t == null) continue;
    origin ??= t;
    final values = [for (final p in parts.skip(2)) double.tryParse(p) ?? double.nan];
    rows.add((parts[0], t, values));
  }
  final fusion = SensorFusion(carried: carried, originUs: origin);
  // In der Reihenfolge der Datei, wie der Logger sie gefüttert hat — je
  // Sensor ist sie zeitlich geordnet, die Fusion mischt selbst.
  final events = <FusionEvent>[];
  for (final (kind, t, v) in rows) {
    switch (kind) {
      case 'a' when v.length == 3:
        events.addAll(fusion.addAccel(t, v[0], v[1], v[2]));
      case 'w' when v.length == 3:
        events.addAll(fusion.addGyro(t, v[0], v[1], v[2]));
      case 'g' when v.length == 5:
        events.addAll(fusion.addGps(t, v[3]));
    }
  }
  events.addAll(fusion.finish());

  String at(double? s) => s == null ? 'never' : '${s.toStringAsFixed(0)} s';
  double rel(int us) => (us - origin!) / 1e6;
  stdout.writeln('mount: ${fusion.mountCarried ? 'carried over, dropped at ${at(fusion.mountDroppedAt)}; ' : ''}'
      'up at ${at(fusion.upAt)}, forward at ${at(fusion.forwardAt)}, slips ${fusion.slips.length}'
      '${fusion.slips.isEmpty ? '' : ' (${fusion.slips.map(at).join(', ')})'}');
  stdout.writeln('wheelies at $kFusionWheelieTiltDeg deg / $kFusionWheelieMinS s against the way:');
  for (final e in events.whereType<WheelieEvent>()) {
    stdout.writeln('  t=${rel(e.startUs).toStringAsFixed(2).padLeft(8)}  '
        '${(e.duration.inMicroseconds / 1e6).toStringAsFixed(1)} s  ${e.lengthM.toStringAsFixed(1)} m  '
        '${e.maxTiltDeg.toStringAsFixed(0)} deg');
  }
  stdout.writeln('flights at $kFusionFlightG g / ${kFusionFlightMinMs.toStringAsFixed(0)} ms:');
  for (final e in events.whereType<JumpEvent>()) {
    stdout.writeln('  t=${rel(e.startUs).toStringAsFixed(2).padLeft(8)}  '
        '${(e.duration.inMicroseconds / 1e6).toStringAsFixed(2)} s  landing ${e.landingG.toStringAsFixed(1)} g'
        '  ${e.plausible ? 'plausible' : 'NOT plausible'}${e.upright ? '' : ', not upright'}');
  }
}
