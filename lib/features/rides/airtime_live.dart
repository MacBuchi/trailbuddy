// Die Live-Ansicht der Erkennung in der offenen App (#36, Betreiber
// 2026-10-31: „eine Art Mini-Animation, wo man in Echtzeit sehen kann, was
// das Modell denkt"): sammelt, was der Dienst schickt
// (`airtime_message.dart`), spielt die Takte nach ihrer Zeit ab und hält
// die Ereignisse, die noch eine Antwort brauchen.
//
// Zwei Dinge, die man wissen muss:
// - **Die Fusion rechnet in Schüben** — je GPS-Punkt eine Sekunde, 1,5 s
//   hinter der Uhr. Abgespielt wird deshalb mit einem Verzug [lagUs], der
//   den ältesten Takt jedes Schubs noch erreicht; so läuft die Animation
//   gleichmäßig statt einmal je Sekunde zehn Bilder auf einmal.
// - **Eine Antwort hier ist dieselbe wie im Banner** (`answerAirtimeInApp`):
//   dieselbe Zeile in den Rohdaten, das Banner geht weg.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'airtime_message.dart';
import 'ride_providers.dart';
import 'sensor_fusion.dart';
import 'wheelie_notify.dart';

/// Höchstens so viele offene Fragen; ältere fallen weg (das Banner hat
/// sie noch).
const kAirtimePendingMax = 5;

/// Zuschlag auf den gemessenen Verzug, damit ein Schub, der etwas später
/// kommt, die Animation nicht anhält.
const kAirtimeLagMarginUs = 200000;

class AirtimeLiveState {
  const AirtimeLiveState({
    this.file,
    this.ticks = const [],
    this.lagUs = 0,
    this.pending = const [],
    this.collapsed = false,
  });

  /// Die Rohdaten der laufenden Fahrt; `null`, bis der erste Schub da ist.
  final String? file;

  /// Nach der Zeit, die letzte Sekunde vor dem Abspielpunkt und alles
  /// danach.
  final List<FusionLive> ticks;
  final int lagUs;

  /// Älteste zuerst.
  final List<FusionEvent> pending;

  /// Zum Knopf verkleinert — gilt bis zur nächsten Fahrt.
  final bool collapsed;

  bool get active => file != null;

  /// Der Takt, der zur Uhrzeit [nowUs] zu sehen ist; `null` vor dem ersten.
  FusionLive? tickAt(int nowUs) {
    final at = nowUs - lagUs;
    FusionLive? shown;
    for (final t in ticks) {
      if (t.tUs > at) break;
      shown = t;
    }
    return shown ?? (ticks.isEmpty ? null : ticks.first);
  }

  AirtimeLiveState copyWith(
          {List<FusionLive>? ticks, int? lagUs, List<FusionEvent>? pending, bool? collapsed}) =>
      AirtimeLiveState(
          file: file,
          ticks: ticks ?? this.ticks,
          lagUs: lagUs ?? this.lagUs,
          pending: pending ?? this.pending,
          collapsed: collapsed ?? this.collapsed);
}

/// Die Uhr der Ansicht in µs seit 1970 — dieselbe Achse wie die Zeiten der
/// Sensoren. Tests drehen sie selbst.
final airtimeClockProvider = Provider<int Function()>((ref) => () => DateTime.now().microsecondsSinceEpoch);

typedef AirtimeAnswer = Future<void> Function(
    {required String actionId, required String file, int? startUs, int? notificationId});

/// Schreibt eine Antwort in die Rohdaten. Tests sammeln sie.
final airtimeAnswerProvider = Provider<AirtimeAnswer>((ref) => answerAirtimeInApp);

class AirtimeLiveNotifier extends Notifier<AirtimeLiveState> {
  @override
  AirtimeLiveState build() {
    // Fahrt zu Ende: Die Ansicht geht mit, die nächste beginnt leer.
    ref.listen(rideProvider, (previous, next) {
      if (next == null) state = const AirtimeLiveState();
    });
    return const AirtimeLiveState();
  }

  /// `true`, wenn [data] eine Nachricht der Erkennung war.
  bool accept(Object? data) {
    final message = decodeAirtimeMessage(data);
    if (message == null) return data is String && data.startsWith(kAirtimeMessagePrefix);
    var current = state;
    if (current.file != message.file) current = AirtimeLiveState(file: message.file);
    switch (message) {
      case AirtimeLiveMessage(:final ticks):
        if (ticks.isEmpty) break;
        final now = ref.read(airtimeClockProvider)();
        // Der älteste Takt des Schubs muss noch drankommen; wird der
        // Verzug kleiner, gleitet er hinterher statt zu springen.
        final need = now - ticks.first.tUs + kAirtimeLagMarginUs;
        final lag = current.lagUs == 0 || need > current.lagUs
            ? need
            : current.lagUs - ((current.lagUs - need) ~/ 10);
        final keepFrom = now - lag - 1000000;
        final all = [...current.ticks.where((t) => t.tUs >= keepFrom), ...ticks];
        current = current.copyWith(ticks: all, lagUs: lag);
      case AirtimeEventMessage(:final event):
        final pending = [...current.pending, event];
        current = current.copyWith(
            pending: pending.sublist(math.max(0, pending.length - kAirtimePendingMax)));
    }
    state = current;
    return true;
  }

  void setCollapsed(bool value) => state = state.copyWith(collapsed: value);

  /// „Stimmt" ([yes]) oder „War keiner" zum ältesten offenen Ereignis.
  Future<void> answer(FusionEvent event, {required bool yes}) async {
    final file = state.file;
    state = state.copyWith(pending: [...state.pending.where((e) => !identical(e, event))]);
    if (file == null) return;
    final (actionId, id) = switch (event) {
      WheelieEvent() => (yes ? kWheelieYes : kWheelieNo, wheelieNotificationId(event.startUs)),
      JumpEvent() => (yes ? kJumpYes : kJumpNo, jumpNotificationId(event.startUs)),
      StoppieEvent() => (yes ? kStoppieYes : kStoppieNo, stoppieNotificationId(event.startUs)),
    };
    await ref.read(airtimeAnswerProvider)(
        actionId: actionId, file: file, startUs: event.startUs, notificationId: id);
  }

  /// „… verpasst" — [actionId] ist [kWheelieMissed], [kJumpMissed] oder
  /// [kStoppieMissed].
  Future<void> missed(String actionId) async {
    final file = state.file;
    if (file == null) return;
    await ref.read(airtimeAnswerProvider)(actionId: actionId, file: file);
  }
}

final airtimeLiveProvider = NotifierProvider<AirtimeLiveNotifier, AirtimeLiveState>(AirtimeLiveNotifier.new);
