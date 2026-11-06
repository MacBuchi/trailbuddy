// Den Bildschirm anlassen, solange die Folgeansicht der Navigation vorne
// ist (#232, Konzept-Routing 9.4): Android über `FLAG_KEEP_SCREEN_ON` am
// Fenster (ein Methodenkanal in `MainActivity`, kein Paket), im Web über
// die Screen-Wake-Lock-API, wo der Browser sie hat. Das Flag gilt nur,
// solange das Fenster sichtbar ist — im Hintergrund geht der Bildschirm
// aus wie immer.
//
// Dieselbe Bauweise wie `push_web_bridge.dart`: Der Web-Weg ist die
// Vorgabe, `dart.library.io` wählt den Kanal.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screen_awake_web.dart' if (dart.library.io) 'screen_awake_io.dart';

abstract interface class ScreenAwake {
  /// Gibt es den Weg auf dieser Plattform? Sonst fehlt der Schalter.
  bool get supported;

  /// An oder aus. Ein Fehler ist kein Fehlerfall: Dann geht der
  /// Bildschirm eben aus wie immer.
  Future<void> keepOn(bool on);
}

/// Tests ersetzen ihn — im Harness gibt es weder Kanal noch Browser.
final screenAwakeProvider = Provider<ScreenAwake>((ref) => createScreenAwake());

/// Wer den Bildschirm gerade anlassen will (#445): die Folgeansicht der
/// Navigation und die laufende Fahrt. Der Bildschirm bleibt an, solange
/// EINER es will — sonst schaltete das Ende der Navigation den Bildschirm
/// einer Fahrt aus, die weiterläuft.
class ScreenHolds {
  ScreenHolds(this._screen);

  final ScreenAwake _screen;
  final _holders = <Object>{};
  // Ab Werk hält niemand den Bildschirm — ein „aus“ ohne „an“ davor
  // geht nicht hinaus.
  var _sent = false;

  bool get supported => _screen.supported;

  /// [who] will den Bildschirm an ([on]) oder gibt ihn frei.
  void set(Object who, bool on) {
    on ? _holders.add(who) : _holders.remove(who);
    final want = _holders.isNotEmpty;
    if (want == _sent) return;
    _sent = want;
    unawaited(_screen.keepOn(want));
  }
}

final screenHoldsProvider = Provider<ScreenHolds>((ref) => ScreenHolds(ref.watch(screenAwakeProvider)));
