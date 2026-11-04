// Route und Bestwerte an die Uhr (docs/konzept-garmin.md, Abschnitte 2,
// 3 und 9.2). Die Karte ruft [WatchSync.follow] beim Start der
// Navigation mit dem Schalter „Auf der Uhr zeigen"; ab da folgt die Uhr
// der Navigation, bis sie endet (Betreiber 2026-11-04): Das Handy stößt
// die Uhr-App an (`openApplication`), sendet, sobald sie läuft, und jede
// neue Route der Navigation geht von selbst hinterher. Startet die
// Uhr-App (oder verbindet die Uhr neu), meldet sie sich mit der Kennung
// ihrer Route (`hi`); weicht die ab, geht die aktuelle. „Auf der Uhr"
// gilt erst mit ihrem „gespeichert" — Garmin Connect meldet `SUCCESS`
// auch, wenn die Uhr-App zu ist und die Nachricht verwirft. Nach dem
// „gespeichert" geht jeder neue Bestwert der Erkennung (#36) hinterher,
// bis die Fahrt endet. Nichts davon wird gespeichert (A3).
//
// Die Abzweigungen (`br`) rechnet ein eigener Rechen-Isolate auf dem
// Graphen des Korridors unter der Linie ([loadWatchBranches]): Beim Start
// der Navigation liegt kein Wegegraph im Speicher, und eine Fahrt aus
// „Meine Fahrten" hatte nie einen.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors.dart';
import '../../core/line_geometry.dart' show LatBox;
import '../../core/settings.dart';
import '../../core/stall_watch.dart';
import '../profile/profile_providers.dart' show riderProfileProvider;
import '../rides/airtime_live.dart';
import '../rides/ride_providers.dart' show rideProvider;
import '../routing/nav_providers.dart' show navigationProvider;
import '../routing/loop_plan_runner.dart' show loopPlanRunnerFactoryProvider;
import '../routing/loop_planner.dart' show LoopPrefs;
import '../routing/nav_sections.dart';
import '../routing/planning_graph.dart' show loadPlanningGraph;
import '../routing/road_graph_loader.dart' show tilesAlong;
import '../trails/terrain_heights.dart';
import 'garmin_bridge.dart';
import 'watch_branches.dart';
import 'watch_route.dart';

/// So lange wartet das Senden auf die Höhen; danach geht die Route ohne.
const kWatchHeightsWait = Duration(seconds: 5);

/// So lange wartet das Senden auf die Abzweigungen (Kacheln lesen,
/// Graph bauen); danach geht die Route ohne Stummel. Startwert bis zur
/// Messung am Gerät (8.2).
const kWatchBranchesWait = Duration(seconds: 15);

/// So lange wartet das Handy nach dem Senden auf „gespeichert"; danach
/// sagt die Leiste, die Uhr habe nicht geantwortet. Eine spätere Antwort
/// (oder ein `hi`) zählt trotzdem.
const kWatchAckWait = Duration(seconds: 15);

/// Der Korridor um die Linie, dessen Kacheln der Graph der Abzweigungen
/// liest — ein Stummel ist 40 m lang, der Rest ist Luft für den Rand.
const kWatchBranchCorridorM = 100.0;

/// Die Stummel entlang einer Linie — die Naht für Tests.
final watchBranchesLoaderProvider =
    Provider<Future<List<WatchBranch>> Function(List<LatLng> line)>((ref) => (line) => loadWatchBranches(ref, line));

/// Liest die Kacheln unter [line] (wie der Planer: Bereiche, vorgebackene
/// Stücke, mit Empfang und Schalter vom Host), baut den Graphen in einem
/// eigenen Rechen-Isolate und rechnet dort die Stummel. Ohne Kachel keine.
Future<List<WatchBranch>> loadWatchBranches(Ref ref, List<LatLng> line) async {
  if (line.length < 2) return const [];
  final profile = ref.read(riderProfileProvider);
  final prefs = LoopPrefs.parse(ref.read(settingsProvider).loopPlannerPrefs, profile);
  final loaded = await StallWatch.time('watch.graph', () => loadPlanningGraph(ref, LatBox.of(line),
      fillOnline: prefs.fillOnline, only: tilesAlong(line, kWatchBranchCorridorM)));
  final input = loaded.input;
  if (input == null) return const [];
  final runner = ref.read(loopPlanRunnerFactoryProvider)();
  try {
    final report = await runner.build(input);
    unawaited(loaded.keep(report)); // neu gebackene Stücke (#380)
    return await StallWatch.time('watch.branches', () => runner.run(WatchBranchesJob(line)));
  } finally {
    runner.dispose();
  }
}

/// Was die Uhr weiß — gefragt, wenn das Startblatt der Navigation
/// aufgeht. Auf einer Plattform ohne Uhr (Web, Test) fragt niemand.
final watchStatusProvider = FutureProvider.autoDispose<WatchStatus>((ref) async {
  final bridge = ref.watch(garminBridgeProvider);
  if (!bridge.supported) return WatchStatus.none;
  return bridge.status();
});

enum WatchSyncPhase {
  idle,

  /// Höhen und Abzweigungen werden gerechnet, oder die Stücke gehen.
  sending,

  /// Die Uhr fragt „TrailBuddy öffnen?" — die Route geht mit ihrem `hi`.
  prompted,

  /// Gesendet, „gespeichert" steht aus.
  sent,

  /// Die Uhr hat die Route bestätigt.
  stored,

  /// Gesendet, aber in [kWatchAckWait] kein „gespeichert".
  unconfirmed,
  failed,
}

class WatchSyncState {
  const WatchSyncState({this.phase = WatchSyncPhase.idle, this.routeId, this.parts = 0, this.error});

  final WatchSyncPhase phase;
  final String? routeId;

  /// In so vielen Stücken ging die Route (Messung 8.2).
  final int parts;

  /// Der Fehler des SDK beim Senden, oder null.
  final String? error;
}

class WatchSync extends Notifier<WatchSyncState> {
  StreamSubscription<Object?>? _answers;
  StreamSubscription<void>? _reconnects;
  Map<String, Object>? _lastBests;
  bool _bests = false;

  /// Folgt die Uhr der Navigation ([follow])?
  bool _follow = false;

  /// Die Linie der Navigation, für die zuletzt gerechnet wurde.
  List<LatLng>? _line;

  /// Die Route, die auf die Uhr gehört, fertig in Stücken rechenbar; null,
  /// solange gerechnet wird.
  WatchRoute? _route;

  /// Ein `hi`, das kam, während noch gerechnet wurde.
  ({bool hello, String? id})? _early;

  /// Zählt jede neue Route; eine Rechnung für eine alte fällt weg.
  int _gen = 0;
  bool _pushing = false;
  Timer? _ackTimer;

  @override
  WatchSyncState build() {
    ref.onDispose(() {
      _answers?.cancel();
      _reconnects?.cancel();
      _ackTimer?.cancel();
    });
    // Jeder neue Bestwert geht hinterher, solange eine Route auf der Uhr
    // ist; die Fahrt zu Ende heißt: nichts mehr.
    ref.listen(airtimeLiveProvider.select((s) => s.log), (_, log) {
      if (!_bests) return;
      final bests = watchBestsOf(log);
      if (bests == null || _same(bests, _lastBests)) return;
      _lastBests = bests;
      unawaited(ref.read(garminBridgeProvider).send([bests]));
    });
    ref.listen(rideProvider, (previous, next) {
      if (previous != null && next == null) _bests = false;
    });
    // Jede neue Linie der Navigation geht hinterher; das Ende der
    // Navigation beendet das Folgen.
    ref.listen(navigationProvider, (_, next) {
      if (next == null) {
        _release();
      } else if (_follow && !identical(next.route.points, _line)) {
        unawaited(_show(next.route.points, next.sections));
      }
    });
    return const WatchSyncState();
  }

  /// Vor dem Start einer Navigation: Soll die Uhr ihr folgen? An heißt:
  /// Die Route dieser (und jeder folgenden) Navigation geht an die Uhr; aus
  /// lässt die Uhr in Ruhe, auch wenn sie der vorigen folgte.
  void follow(bool on) {
    if (!on) {
      _release();
      return;
    }
    _follow = true;
    final bridge = ref.read(garminBridgeProvider);
    _answers ??= bridge.messages.listen(_onAnswer);
    _reconnects ??= bridge.connected.listen((_) => _onReconnect());
  }

  void _release() {
    _follow = false;
    _gen++;
    _line = null;
    _route = null;
    _early = null;
    _ackTimer?.cancel();
    if (state.phase != WatchSyncPhase.idle) state = const WatchSyncState();
  }

  /// Die Route an die Uhr: vereinfacht, mit Höhen, falls sie in
  /// [kWatchHeightsWait] kommen, und den Abzweigungen, falls sie in
  /// [kWatchBranchesWait] kommen (beides zugleich). Derweil stößt das
  /// Handy die Uhr-App an; läuft sie, gehen die Stücke, sonst warten sie
  /// auf ihr `hi`.
  Future<void> _show(List<LatLng> points, NavSections sections) async {
    final gen = ++_gen;
    _line = points;
    _route = null;
    _early = null;
    _ackTimer?.cancel();
    final bridge = ref.read(garminBridgeProvider);
    state = const WatchSyncState(phase: WatchSyncPhase.sending);
    // Die Frage auf der Uhr gleich: Bis jemand bestätigt, ist die Route
    // gerechnet.
    final opening = bridge.open();
    final branchesSoon = ref
        .read(watchBranchesLoaderProvider)(points)
        .timeout(kWatchBranchesWait, onTimeout: () => const <WatchBranch>[])
        .catchError((Object e, StackTrace s) {
      logError('Abzweigungen für die Uhr', e, s);
      return const <WatchBranch>[];
    });
    final heights = await ref
        .read(terrainHeightsProvider)
        .profile(points)
        .timeout(kWatchHeightsWait, onTimeout: () => null)
        .catchError((Object e, StackTrace s) {
      logError('Höhen für die Uhr', e, s);
      return null;
    });
    final branches = await branchesSoon;
    final open = await opening;
    if (gen != _gen) return;
    final route = watchRouteOf(points, sections, heights: heights, branches: branches);
    if (route == null) {
      state = const WatchSyncState(phase: WatchSyncPhase.failed, error: 'EMPTY');
      return;
    }
    _route = route;
    if (open == WatchOpen.notInstalled) {
      state = WatchSyncState(phase: WatchSyncPhase.failed, routeId: route.id, error: 'APP_IS_NOT_INSTALLED');
      return;
    }
    final early = _early;
    _early = null;
    if (early != null) return _onHello(early.id);
    if (open == WatchOpen.prompted) {
      state = WatchSyncState(phase: WatchSyncPhase.prompted, routeId: route.id);
      return;
    }
    await _push();
  }

  /// Die Stücke der Route an die Uhr; danach wartet das Handy auf
  /// „gespeichert", höchstens [kWatchAckWait].
  Future<void> _push() async {
    final route = _route;
    if (route == null || _pushing) return;
    final gen = _gen;
    final parts = route.parts();
    _pushing = true;
    state = WatchSyncState(phase: WatchSyncPhase.sending, routeId: route.id, parts: parts.length);
    final WatchSendResult result;
    try {
      result = await ref.read(garminBridgeProvider).send(parts);
    } finally {
      _pushing = false;
    }
    if (gen != _gen) return;
    // „Gespeichert" kann vor dem Ende von `send` kommen.
    if (state.phase == WatchSyncPhase.stored && state.routeId == route.id) return;
    if (!result.ok) {
      state = WatchSyncState(
          phase: WatchSyncPhase.failed, routeId: route.id, parts: parts.length, error: result.status);
      return;
    }
    state = WatchSyncState(phase: WatchSyncPhase.sent, routeId: route.id, parts: parts.length);
    _ackTimer?.cancel();
    _ackTimer = Timer(kWatchAckWait, () {
      if (gen == _gen && state.phase == WatchSyncPhase.sent) {
        state = WatchSyncState(phase: WatchSyncPhase.unconfirmed, routeId: route.id, parts: parts.length);
      }
    });
  }

  void _onAnswer(Object? message) {
    final hello = watchHelloOf(message);
    if (hello.hello) return _onHello(hello.id);
    final id = watchStoredId(message);
    // Nur die Bestätigung der Route, die gerade auf die Uhr gehört.
    if (id == null || !_follow || id != _route?.id) return;
    _stored(id);
  }

  /// Die Uhr-App meldet sich: Hat sie die Route schon, gilt sie als
  /// gespeichert; sonst geht die aktuelle.
  void _onHello(String? id) {
    if (!_follow) return;
    final route = _route;
    if (route == null) {
      _early = (hello: true, id: id);
      return;
    }
    if (id == route.id) return _stored(id!);
    unawaited(_push());
  }

  /// Die Uhr ist wieder da: Läuft ihre App, sagt ihr `hi`, ob die Route
  /// noch stimmt — kein Abfragen im Takt.
  void _onReconnect() {
    if (!_follow || _route == null || _pushing) return;
    unawaited(ref.read(garminBridgeProvider).send([watchQuery]));
  }

  void _stored(String id) {
    _ackTimer?.cancel();
    state = WatchSyncState(phase: WatchSyncPhase.stored, routeId: id, parts: state.parts);
    // Die Bestwerte gehen erst jetzt: Vorher verwarf eine geschlossene
    // Uhr-App sie. Startete die Uhr-App neu, hat sie sie vergessen.
    _bests = true;
    _lastBests = null;
    final bests = watchBestsOf(ref.read(airtimeLiveProvider).log);
    if (bests != null) {
      _lastBests = bests;
      unawaited(ref.read(garminBridgeProvider).send([bests]));
    }
  }

  static bool _same(Map<String, Object> a, Map<String, Object>? b) {
    if (b == null || a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}

final watchSyncProvider = NotifierProvider<WatchSync, WatchSyncState>(WatchSync.new);
