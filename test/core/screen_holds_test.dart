// Der Bildschirm bleibt an, solange EINER ihn hält (#445): Endet die
// Navigation während einer Fahrt mit Bildschirm-Knopf, bleibt er an.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/screen_awake.dart';

class _Screen implements ScreenAwake {
  final calls = <bool>[];

  @override
  bool get supported => true;

  @override
  Future<void> keepOn(bool on) async => calls.add(on);
}

void main() {
  test('an, solange einer hält; jeder Wechsel einmal', () {
    final screen = _Screen();
    final holds = ScreenHolds(screen);
    holds.set(#ride, true);
    holds.set(#nav, true);
    holds.set(#nav, false);
    expect(screen.calls, [true], reason: 'die Fahrt hält ihn weiter');
    holds.set(#ride, false);
    expect(screen.calls, [true, false]);
    holds.set(#nav, false);
    expect(screen.calls, [true, false], reason: 'nichts Neues, kein Aufruf');
  });

  test('ein „aus" ohne „an" davor geht nicht hinaus', () {
    final screen = _Screen();
    ScreenHolds(screen).set(#ride, false);
    expect(screen.calls, isEmpty);
  });
}
