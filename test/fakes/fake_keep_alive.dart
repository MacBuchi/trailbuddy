import 'package:trailbuddy/features/keep_alive/keep_alive.dart';

/// Der Foreground-Service im Speicher: zählt Starts, merkt Texte, Typen
/// und Takt — damit Tests prüfen können, WANN der Service läuft, ohne
/// Plattform-Kanal.
class FakeKeepAlive implements KeepAlive {
  bool running = false;
  int starts = 0;
  final texts = <String>[];
  final titles = <String>[];
  Set<KeepAliveType> types = const {};
  Duration? repeat;
  List<KeepAliveButton> buttons = const [];

  @override
  Future<void> start(String title, String text, Set<KeepAliveType> types,
      {List<KeepAliveButton> buttons = const []}) async {
    if (!running) {
      starts++;
      this.types = types;
    }
    running = true;
    titles.add(title);
    texts.add(text);
    this.buttons = buttons;
  }

  @override
  Future<void> update(String title, String text, {List<KeepAliveButton> buttons = const []}) async {
    titles.add(title);
    texts.add(text);
    this.buttons = buttons;
  }

  @override
  Future<void> setRepeat(Duration? every) async => repeat = every;

  @override
  Future<void> stop() async {
    running = false;
    repeat = null;
  }
}
