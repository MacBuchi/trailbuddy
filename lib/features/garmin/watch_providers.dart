// Route und Bestwerte an die Uhr (docs/konzept-garmin.md, Abschnitte 2,
// 3 und 9.2). Die Karte ruft [WatchSync.sendRoute] beim Start der
// Navigation, wenn „Auf der Uhr zeigen" an ist; ab da schickt der
// Controller jeden neuen Bestwert der Erkennung (#36) hinterher, bis die
// Fahrt endet. Nichts davon wird gespeichert (A3).
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

enum WatchSyncPhase { idle, sending, sent, stored, failed }

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
  Map<String, Object>? _lastBests;
  bool _bests = false;

  @override
  WatchSyncState build() {
    ref.onDispose(() => _answers?.cancel());
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
    return const WatchSyncState();
  }

  /// Die Route an die Uhr: vereinfacht, mit Höhen, falls sie in
  /// [kWatchHeightsWait] kommen, und den Abzweigungen, falls sie in
  /// [kWatchBranchesWait] kommen (beides zugleich), in Stücken. Kommt
  /// später „gespeichert" mit derselben Kennung zurück, steht
  /// [WatchSyncPhase.stored].
  Future<WatchSendResult> sendRoute(List<LatLng> points, NavSections sections) async {
    final bridge = ref.read(garminBridgeProvider);
    _answers ??= bridge.messages.listen(_onAnswer);
    state = const WatchSyncState(phase: WatchSyncPhase.sending);
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
    final route = watchRouteOf(points, sections, heights: heights, branches: branches);
    if (route == null) {
      state = const WatchSyncState(phase: WatchSyncPhase.failed, error: 'EMPTY');
      return const WatchSendResult('EMPTY', 0);
    }
    final parts = route.parts();
    final result = await bridge.send(parts);
    if (state.phase == WatchSyncPhase.stored && state.routeId == route.id) return result;
    state = WatchSyncState(
        phase: result.ok ? WatchSyncPhase.sent : WatchSyncPhase.failed,
        routeId: route.id,
        parts: parts.length,
        error: result.ok ? null : result.status);
    if (result.ok) {
      _bests = true;
      _lastBests = null;
      // Was die Erkennung schon hat, gleich mit.
      final bests = watchBestsOf(ref.read(airtimeLiveProvider).log);
      if (bests != null) {
        _lastBests = bests;
        unawaited(bridge.send([bests]));
      }
    }
    return result;
  }

  void _onAnswer(Object? message) {
    final id = watchStoredId(message);
    if (id == null) return;
    final now = state;
    // Die Antwort kann vor dem Ende von `send` kommen (das letzte Stück
    // ist bestätigt, die Kennung schon gesetzt oder gleich).
    state = WatchSyncState(phase: WatchSyncPhase.stored, routeId: id, parts: now.parts);
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
