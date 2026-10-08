// Den Bildschirm anlassen, solange die Folgeansicht der Navigation vorne
// ist (#232, Konzept-Routing 9.4): Android über `FLAG_KEEP_SCREEN_ON` am
// Fenster (ein Methodenkanal in `MainActivity`, kein Paket), im Web über
// die Screen-Wake-Lock-API, wo der Browser sie hat. Das Flag gilt nur,
// solange das Fenster sichtbar ist — im Hintergrund geht der Bildschirm
// aus wie immer.
//
// Dieselbe Bauweise wie `push_web_bridge.dart`: Der Web-Weg ist die
// Vorgabe, `dart.library.io` wählt den Kanal.
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
