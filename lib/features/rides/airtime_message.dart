// Was der Dienst der offenen App über die Erkennung sagt (#36, die
// Live-Ansicht): die Takte der Fusion ([FusionLive]) und die fertigen
// Ereignisse — über denselben Kanal wie die Punkte der Fahrt
// (`sendDataToMain`, nur einfache Werte, deshalb Text). Rein, ohne
// Plattform: Der Logger kodiert im Dienst, die Karte liest im
// Main-Isolate.
//
// Ist die App zu, verwirft `sendDataToMain` still — die Banner bleiben der
// Weg, die Ansicht ist ein Zusatz.
import 'dart:convert';

import 'sensor_fusion.dart';

/// Jede Nachricht der Erkennung beginnt so; alles andere ist ein Punkt
/// der Fahrt oder eine der Navigation.
const kAirtimeMessagePrefix = 'air:';
const _livePrefix = 'air:live:';
const _eventPrefix = 'air:event:';

/// Ein Schub Takte mit der Datei der Fahrt (für die Antworten).
String encodeAirtimeLive(String file, List<FusionLive> ticks) => _livePrefix +
    jsonEncode({
      'f': file,
      'v': [
        for (final t in ticks)
          [
            t.tUs,
            t.pitchDeg.isNaN ? null : _round(t.pitchDeg),
            _round(t.speedKmh),
            t.upKnown ? 1 : 0,
            t.phase.index,
            t.phaseStartUs,
            _round(t.peakDeg),
          ]
      ],
    });

/// Ein fertiges Ereignis, wie das Banner es zeigt.
String encodeAirtimeEvent(String file, FusionEvent event) => _eventPrefix +
    jsonEncode({
      'f': file,
      's': event.startUs,
      'd': event.duration.inMicroseconds,
      ...switch (event) {
        WheelieEvent() => {'k': 'w', 'm': _round(event.maxTiltDeg), 'l': _round(event.lengthM)},
        JumpEvent() => {'k': 'j', 'g': _round(event.landingG), 'p': event.plausible},
        StoppieEvent() =>
          {'k': 's', 'm': _round(event.maxTiltDeg), 'b': _round(event.decel), 'g': _round(event.landingG)},
      },
    });

double _round(double v) => (v * 10).roundToDouble() / 10;

sealed class AirtimeMessage {
  const AirtimeMessage(this.file);

  final String file;
}

class AirtimeLiveMessage extends AirtimeMessage {
  const AirtimeLiveMessage(super.file, this.ticks);

  final List<FusionLive> ticks;
}

class AirtimeEventMessage extends AirtimeMessage {
  const AirtimeEventMessage(super.file, this.event);

  final FusionEvent event;
}

/// `null` für alles, was keine Nachricht der Erkennung ist oder kaputt
/// ankommt. Wirft nie.
AirtimeMessage? decodeAirtimeMessage(Object? data) {
  if (data is! String || !data.startsWith(kAirtimeMessagePrefix)) return null;
  try {
    if (data.startsWith(_livePrefix)) {
      final json = jsonDecode(data.substring(_livePrefix.length)) as Map<String, dynamic>;
      final ticks = [
        for (final v in json['v'] as List)
          FusionLive(
            tUs: (v as List)[0] as int,
            pitchDeg: (v[1] as num?)?.toDouble() ?? double.nan,
            speedKmh: (v[2] as num).toDouble(),
            upKnown: v[3] == 1,
            phase: FusionPhase.values[v[4] as int],
            phaseStartUs: v[5] as int?,
            peakDeg: (v[6] as num).toDouble(),
          ),
      ];
      return AirtimeLiveMessage(json['f'] as String, ticks);
    }
    if (data.startsWith(_eventPrefix)) {
      final json = jsonDecode(data.substring(_eventPrefix.length)) as Map<String, dynamic>;
      final start = json['s'] as int;
      final duration = Duration(microseconds: json['d'] as int);
      double n(String key) => (json[key] as num).toDouble();
      final FusionEvent event = switch (json['k']) {
        'w' => WheelieEvent(startUs: start, duration: duration, lengthM: n('l'), maxTiltDeg: n('m')),
        'j' => JumpEvent(
            startUs: start,
            duration: duration,
            landingG: n('g'),
            upright: true,
            plausible: json['p'] == true),
        's' => StoppieEvent(
            startUs: start,
            duration: duration,
            maxTiltDeg: n('m'),
            decel: n('b'),
            landingG: (json['g'] as num?)?.toDouble() ?? 0),
        _ => throw const FormatException('Art'),
      };
      return AirtimeEventMessage(json['f'] as String, event);
    }
  } catch (_) {
    // Eine fremde oder kaputte Nachricht ist keine.
  }
  return null;
}
