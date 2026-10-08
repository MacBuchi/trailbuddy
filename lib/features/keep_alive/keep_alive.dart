// Der EINE Foreground-Service der App, geteilt zwischen Fahrt (#28) und
// Bereichs-Download (Konzept-Schritt 3) — PilzBuddys Koordinator
// (#264/#338/#342), hierher portiert, sobald es den zweiten Verbraucher
// gab. Zwei `stop()` auf einem Service sind die Falle: Das Ende des
// Downloads beendete sonst die Fahrt mitten im Wald.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'keep_alive_stub.dart' if (dart.library.io) 'keep_alive_service.dart';

/// Welchen Zweck ein Melder dem System gegenüber angibt. Android 14
/// verlangt, dass ein Foreground-Service seinen Typ nennt, und prüft je
/// Typ die passende Berechtigung: Ein Download ist `dataSync`, eine
/// Fahrt `location` — und wer beides gleichzeitig tut, braucht beides.
enum KeepAliveType { dataSync, location }

/// Ein Knopf in der Dauerbenachrichtigung („Navigation beenden", #232).
/// Gedrückt wird er im Service-Isolate (`TaskHandler.onNotificationButtonPressed`).
typedef KeepAliveButton = ({String id, String text});

/// Hält den App-Prozess wach, solange ein Bereich lädt oder eine Fahrt
/// aufzeichnet. Ohne das friert Android den Prozess ein, sobald der
/// Nutzer in eine andere App wechselt: Der Download läuft im
/// Main-Isolate, ein „cached" Prozess wird ab Android 12 eingefroren.
/// Die Fahrt misst dagegen IM Service-Isolate, weil das das Wegwischen
/// der App überlebt; sie braucht den Takt (`setRepeat`).
abstract class KeepAlive {
  /// Startet den Service. Läuft er schon, werden nur Titel, Text und
  /// Knöpfe erneuert — die Typen bleiben dann, wie sie waren (siehe
  /// Koordinator).
  Future<void> start(String title, String text, Set<KeepAliveType> types,
      {List<KeepAliveButton> buttons = const []});

  /// Neuer Titel und Text; [buttons] ersetzt die Knöpfe (leer = keine).
  Future<void> update(String title, String text, {List<KeepAliveButton> buttons = const []});

  /// Der Wiederhol-Takt des Service-Isolates; null heißt kein Takt (der
  /// Zustand für Downloads).
  Future<void> setRepeat(Duration? every);

  /// Beendet den Service. Muss auch nach Fehlern laufen.
  Future<void> stop();
}

/// Meldet den Main-Isolate als Empfänger für das Service-Isolate an —
/// **gehört in `main()`, vor `runApp`** (PilzBuddy #465): Ohne sie ist
/// die Rückrichtung stumm, und die Karte kennt von einer Fahrt nur den
/// ersten Punkt.
void initKeepAliveCommunication() => initKeepAliveCommunicationImpl();

/// Plattform-Implementierung: Foreground-Service auf Android, sonst
/// nichts. Tests überschreiben den Provider.
final keepAliveProvider = Provider<KeepAlive>((ref) => createKeepAlive());

/// Teilt den EINEN Service unter mehreren Verbrauchern auf. Gezählt
/// wird über Schlüssel, damit der Text sagen kann, was gerade läuft.
/// Keine Fehlerbehandlung: Die Implementierung darunter schluckt schon
/// alles — Fahrt und Download sind wichtiger als ihre Benachrichtigung.
class KeepAliveCoordinator {
  KeepAliveCoordinator(this._keepAlive);

  final KeepAlive _keepAlive;

  final _needs = <String,
      ({String title, String text, Set<KeepAliveType> types, List<KeepAliveButton> buttons})>{};
  final _repeats = <String, Duration>{};
  Set<KeepAliveType> _runningTypes = const {};

  /// Meldet einen Verbraucher an und startet den Service, falls er ruht.
  /// **Ändert sich dabei die Typmenge, wird der Service neu gestartet:**
  /// `updateService` kann die Typen nicht ändern, und ein als `dataSync`
  /// laufender Service liefert einer Fahrt im Hintergrund keine
  /// Standorte mehr. Die kurze Lücke kostet höchstens einen Fix.
  Future<void> start(
    String key,
    String text, {
    required String title,
    Set<KeepAliveType> types = const {KeepAliveType.dataSync},
    List<KeepAliveButton> buttons = const [],
  }) async {
    _needs[key] = (title: title, text: text, types: types, buttons: buttons);
    final wanted = _wantedTypes();
    if (_runningTypes.isNotEmpty && !_sameTypes(_runningTypes, wanted)) {
      await _keepAlive.stop();
      _runningTypes = const {};
    }
    final restarted = _runningTypes.isEmpty;
    _runningTypes = wanted;
    await _keepAlive.start(_title(), _combined(), wanted, buttons: _buttons());
    // Ein frischer Service kommt ohne Takt hoch; ein Melder, der ihn
    // schon gesetzt hatte, verlöre ihn sonst beim Neustart der Typen.
    if (restarted && _repeats.isNotEmpty) await _keepAlive.setRepeat(_repeat());
  }

  /// Neuer Text dieses Melders. Unbekannte Schlüssel und unveränderte
  /// Texte tun nichts — sonst ginge jeder Fortschritts-Tick über den
  /// Platform-Channel.
  Future<void> update(String key, String text) async {
    final need = _needs[key];
    if (need == null || need.text == text) return;
    _needs[key] = (title: need.title, text: text, types: need.types, buttons: need.buttons);
    await _keepAlive.update(_title(), _combined(), buttons: _buttons());
  }

  /// Meldet einen Verbraucher ab. Der Service endet erst, wenn der
  /// letzte gegangen ist.
  ///
  /// Bleiben Melder übrig, wird der Service über `start` erneuert, nicht
  /// über `update`: „Navigation beenden" in der Benachrichtigung (#232)
  /// beendet ihn drüben im Service-Isolate womöglich schon, und ein
  /// laufender Download stünde dann ohne Service da. `start` auf einem
  /// laufenden Service ist nur ein Update.
  Future<void> stop(String key) async {
    final hadRepeat = _repeats.remove(key) != null;
    if (_needs.remove(key) == null) return;
    if (_needs.isEmpty) {
      await _keepAlive.stop();
      _runningTypes = const {};
      return;
    }
    // Die Typen der Übrigen: Läuft der Dienst noch, bleibt es ein Update
    // (die Typen ändert das nicht); war er weg, startet er nur mit dem,
    // was noch gebraucht wird — `location` für einen Download wäre
    // gegenüber Play eine falsche Angabe.
    _runningTypes = _wantedTypes();
    await _keepAlive.start(_title(), _combined(), _runningTypes, buttons: _buttons());
    // Neu gestartet hätte er keinen Takt — den der übrigen Melder setzen.
    if (hadRepeat || _repeats.isNotEmpty) await _keepAlive.setRepeat(_repeat());
  }

  /// Der Takt des Service-Isolates, je Melder: Fahrt und Navigation
  /// (#232) messen beide darin. Es gilt der kürzeste; null meldet den
  /// eigenen ab — bis 0.95.0 gab es nur einen, und das Ende der Fahrt
  /// hätte der Navigation den Takt genommen.
  Future<void> setRepeat(String key, Duration? every) async {
    if (every == null) {
      _repeats.remove(key);
    } else {
      _repeats[key] = every;
    }
    await _keepAlive.setRepeat(_repeat());
  }

  Duration? _repeat() => _repeats.isEmpty
      ? null
      : _repeats.values.reduce((a, b) => a <= b ? a : b);

  bool get isEmpty => _needs.isEmpty;

  Set<KeepAliveType> _wantedTypes() => {for (final need in _needs.values) ...need.types};

  static bool _sameTypes(Set<KeepAliveType> a, Set<KeepAliveType> b) =>
      a.length == b.length && a.containsAll(b);

  /// Bei genau einem Melder sein eigener Titel, sonst ein neutraler —
  /// „Bereich wird gespeichert" über einer laufenden Fahrt wäre falsch.
  String _title() => _needs.length == 1 ? _needs.values.single.title : 'TrailBuddy arbeitet';

  String _combined() => [for (final need in _needs.values) need.text].join(' · ');

  List<KeepAliveButton> _buttons() => [
        for (final need in _needs.values) ...need.buttons,
      ];
}

/// Der Koordinator lebt so lange wie der ProviderScope — die gemeinsame
/// Buchführung aller Verbraucher.
final keepAliveCoordinatorProvider = Provider<KeepAliveCoordinator>(
    (ref) => KeepAliveCoordinator(ref.watch(keepAliveProvider)));
