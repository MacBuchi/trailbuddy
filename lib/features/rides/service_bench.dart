// Die Bank für Mitteilung und Stimme im Hintergrund (#644, Paket 3b):
// NUR mit `--dart-define=TB_SERVICE_BENCH=true` (tool/ios_ride_bench.sh
// --notice), sonst ist alles eine Konstante und fällt aus dem Build.
//
// Im Simulator gibt es keinen Trail unter der erfundenen Strecke und keine
// Hand für den Dialog des Systems. Deshalb zeigt der Dienst hier selbst alle
// [kServiceBenchEvery] Takte eine Frage an einen erfundenen Trail (mit der
// echten Fahrt im Payload, eine Antwort landet also in der Datei) und
// spricht einen Satz. Gefragt wird „vorläufig" (provisional): ohne Dialog,
// leise in der Mitteilungszentrale. Ob gezeigt und gesprochen wurde, sagen
// `getActiveNotifications` und die `TB-VOICE`-Zeilen im Systemprotokoll.
import 'dart:ui' show Locale;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trail.dart' show TrailStatus;
import '../routing/voice_service.dart' show speakVoice;
import 'ride_confirm.dart';
import 'ride_confirm_notify.dart';
import 'ride_task_handler.dart';

const kServiceBench = bool.fromEnvironment('TB_SERVICE_BENCH');

/// Alle so viele Takte (5 s) eine Frage und ein Satz.
const kServiceBenchEvery = 6;

/// Der erfundene Trail der Bank zum Takt [tick].
String serviceBenchTrailId(int tick) => 'bench-$tick';

int _ticks = 0;

/// Ein Takt der Fahrt im Dienst. Wirft nie.
Future<void> serviceBenchTick() async {
  if (!kServiceBench) return;
  try {
    _ticks++;
    if (_ticks % kServiceBenchEvery != 0) return;
    final dir = await FlutterForegroundTask.getData<String>(key: kRideDataDir);
    final uid = await FlutterForegroundTask.getData<String>(key: kRideDataUid);
    final started = DateTime.tryParse(
      await FlutterForegroundTask.getData<String>(key: kRideDataStartedAt) ??
          '',
    );
    if (dir == null || uid == null || started == null) return;
    final trail = serviceBenchTrailId(_ticks);
    // ignore: avoid_print
    print('TB-BENCH notice $trail');
    await showConfirmNotice(
      ConfirmTarget(
        trailId: trail,
        name: 'Bench $_ticks',
        line: const [LatLng(7, 11), LatLng(7.001, 11)],
        status: TrailStatus.closed,
      ),
      payload: encodeConfirmPayload((
        dir: dir,
        uid: uid,
        rideStartedAt: started.toUtc(),
        trailId: trail,
      )),
    );
    await speakVoice('TrailBuddy Bench $_ticks', const Locale('de'));
  } catch (_) {
    // Eine Bank, kein Teil der Fahrt.
  }
}
