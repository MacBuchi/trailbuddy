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
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors.dart';
import '../../core/line_geometry.dart' show LatBox;
import '../../core/settings.dart';
import '../../core/stall_watch.dart';
import '../../models/trail.dart';
import '../profile/profile_providers.dart' show riderProfileProvider;
import '../rides/airtime_live.dart';
import '../rides/ride_providers.dart' show rideProvider;
import '../routing/nav_providers.dart' show navigationProvider, navReplanOfferDistanceProvider;
import '../routing/loop_plan_runner.dart' show loopPlanRunnerFactoryProvider;
import '../routing/loop_planner.dart' show LoopPrefs;
import '../routing/nav_sections.dart';
import '../routing/planning_graph.dart' show loadPlanningGraph;
import '../routing/road_graph_loader.dart' show tilesAlong;
import '../trails/terrain_heights.dart';
import '../trails/trail_elevation.dart' show ElevationProfile;
import '../trails/trail_providers.dart' show trailsProvider;
import 'garmin_bridge.dart';
import 'watch_free.dart' show nearestTrailLine, freeSections;
import 'watch_ride_inbox.dart';
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

/// Wartet das Handy auf die Uhr („gefragt" oder ohne „gespeichert"),
/// fragt es nach so langen Pausen noch einmal `q` — ein verlorenes `hi`
/// holte sonst erst das nächste Wiederverbinden nach. Kein Abfragen im
/// Takt: drei Mal, dann wartet es still auf die Uhr.
const kWatchNudges = [Duration(seconds: 5), Duration(seconds: 15), Duration(seconds: 45)];

/// Bricht die Übertragung mittendrin ab (Garmin Connect, Bluetooth), gehen
/// nach dieser Pause die übrigen Stücke noch einmal — die Uhr hat die
/// angekommenen schon abgelegt. Höchstens [kWatchResumes] Mal.
const kWatchResumePause = Duration(seconds: 2);
const kWatchResumes = 2;

/// Fehler, nach denen die übrigen Stücke noch einmal gehen.
const _resumable = {'FAILURE_DURING_TRANSFER', 'FAILURE_TIMEOUT'};

/// Der Fehler im Zustand, wenn die Uhr die Route auch mit halb so vielen
/// Punkten nicht nehmen konnte (Speicher, Absturz).
const kWatchTooBig = 'WATCH_TOO_BIG';

/// Die Uhr-App spricht ein älteres Protokoll (oder keins): neu aufspielen.
const kWatchOutdatedWatch = 'WATCH_OUTDATED';

/// Die Uhr-App spricht ein neueres Protokoll: die App aktualisieren.
const kWatchOutdatedPhone = 'PHONE_OUTDATED';

/// So oft geht die Position des Handys an die Uhr, solange die Uhr kein
/// eigenes GPS meldet (Betreiber 2026-11-05) …
const kWatchPositionEvery = Duration(seconds: 10);

/// … und höchstens so lange nach dem „gespeichert": Die Uhr navigiert
/// allein (A8), die Position des Handys ist nur ein Vorsprung beim Start.
const kWatchPositionFor = Duration(minutes: 3);

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
  final status = await bridge.status();
  // Eine Uhr mit unserer App: ab jetzt beim Start lauschen, und gleich
  // auch — sie hält vielleicht schon Fahrten (#484).
  if (status.canShow) {
    final settings = ref.read(settingsProvider);
    if (!settings.watchSeen) unawaited(settings.setWatchSeen(true));
    unawaited(ref.read(watchRideInboxProvider.notifier).start());
  }
  return status;
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

  /// Folgt die Uhr dem Handy ([follow])? An heißt: Diese Uhr bekommt Routen
  /// — die der Navigation, oder in der freien Fahrt die nächste Linie (#484).
  bool _follow = false;

  //! Die Route, die die Uhr hat (aus ihrem „hallo“). null, wenn sie keine
  //! hat — dann fragt sie nach einer (#484, freie Fahrt).
  String? _watchRouteId;

  /// Die Linie der Navigation, für die zuletzt gerechnet wurde.
  List<LatLng>? _line;

  /// Die Route, die auf die Uhr gehört, fertig in Stücken rechenbar; null,
  /// solange gerechnet wird.
  WatchRoute? _route;

  /// Woraus [_route] entstand — für eine kleinere, wenn die Uhr sie nicht
  /// nehmen kann ([_shrink]).
  ({List<LatLng> points, NavSections sections, ElevationProfile? heights, List<WatchBranch> branches})? _inputs;

  /// Diese Linie ging schon einmal mit halb so vielen Punkten.
  bool _shrunk = false;

  /// Ein `hi`, das kam, während noch gerechnet wurde.
  ({String? id, String? bad, String? ver})? _early;

  /// Die Uhr-App spricht eine andere Fassung — dann geht nichts hin, bis
  /// ein `hi` mit der passenden kommt.
  WatchOutdated? _outdated;

  /// Die Uhr hat eigenes GPS ([kWatchHasGps]); bis dahin geht die Position
  /// des Handys im Takt [kWatchPositionEvery].
  bool _gps = false;
  //! Der Stand, den die Uhr zuletzt meldete (#484, freie Fahrt).
  LatLng? _watchFix;
  //! Eine Linie für die freie Fahrt ging schon raus — nicht jede Nachricht
  //! der Uhr rechnet neu.
  bool _freeLine = false;
  //! Welcher Trail der Uhr in der freien Fahrt zuletzt ging — derselbe
  //! bleibt, auch wenn die Uhr weiter driftet.
  String? _freeTrailId;
  Timer? _positionTimer;
  int _positionTicks = 0;

  /// Die Route, deren Stücke gerade hinübergehen — ein „hallo" währenddessen
  /// (etwa auf das Nachfassen `q`) schickt sie nicht noch einmal (gemessen
  /// 2026-11-06: dieselbe Route zweimal, 13 s umsonst).
  String? _sendingId;

  /// Die Fassung der Uhr-App, wie sie ihr Hallo nennt. Unbekannt heißt alt:
  /// sie fragt nicht, bevor eine neue Linie kommt (#501).
  String? _watchVer;

  /// Eine Umplan-Rechnung für die Uhr läuft schon.
  bool _replanRunning = false;

  /// Jede Route, die in diesem Folgen an die Uhr ging: Nur deren
  /// „Navigation beendet" beendet die Navigation des Handys.
  final _sentIds = <String>{};

  /// Die Uhr hat die Navigation beendet — dann geht kein „beendet" zurück.
  bool _endedByWatch = false;

  /// Zählt jede neue Route; eine Rechnung für eine alte fällt weg.
  int _gen = 0;

  /// Es läuft eine Übertragung; eine weitere wartet in [_again] — zwei
  /// zugleich mischten ihre Stücke, und die Uhr finge bei jeder neuen
  /// Kennung von vorn an.
  bool _pushing = false;
  bool _again = false;
  Timer? _ackTimer;
  Timer? _nudgeTimer;

  /// Höhen und Abzweigungen, angestoßen, als das Startblatt die Uhr fand
  /// ([prepare]) — „Los" wartet dann nicht noch einmal von vorn.
  _Prepared? _prepared;

  /// Wie oft Höhen und Abzweigungen angestoßen wurden (Test).
  @visibleForTesting
  int loads = 0;

  @override
  WatchSyncState build() {
    ref.onDispose(() {
      _answers?.cancel();
      _reconnects?.cancel();
      _ackTimer?.cancel();
      _nudgeTimer?.cancel();
      _positionTimer?.cancel();
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
    // Die Uhr redet auch ohne Navigation: in der freien Fahrt fragt sie nach
    // einer Linie (#484), und das Handy antwortet mit dem Trail in Reichweite.
    _answers ??= ref.read(garminBridgeProvider).messages.listen(_onAnswer);
    // Jede neue Linie der Navigation geht hinterher; das Ende der
    // Navigation beendet das Folgen.
    ref.listen(navigationProvider, (_, next) {
      if (next == null) {
        _sendEnd();
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

  /// Das Startblatt hat eine Uhr gefunden: Höhen und Abzweigungen für
  /// [points] schon jetzt rechnen, solange gelesen wird. Ein Blatt ohne
  /// „Los" oder eine andere Linie verwirft das Ergebnis ([discardPrepared],
  /// [_show]); laufen lassen kostet nur die Rechnung, nichts geht hin.
  void prepare(List<LatLng> points) {
    if (points.length < 2) return;
    final ready = _prepared;
    if (ready != null && _sameLine(ready.line, points)) return;
    _prepared = _Prepared(points, _heightsOf(points), _branchesOf(points));
  }

  void discardPrepared() => _prepared = null;

  Future<ElevationProfile?> _heightsOf(List<LatLng> points) {
    loads++;
    return ref.read(terrainHeightsProvider).profile(points).catchError((Object e, StackTrace s) {
      logError('Höhen für die Uhr', e, s);
      return null;
    });
  }

  Future<List<WatchBranch>> _branchesOf(List<LatLng> points) =>
      ref.read(watchBranchesLoaderProvider)(points).catchError((Object e, StackTrace s) {
        logError('Abzweigungen für die Uhr', e, s);
        return const <WatchBranch>[];
      });

  /// Die Navigation endet auf dem Handy: Die Uhr-App schließt sich, wenn
  /// sie eine Route dieser Navigation zeigt ([kWatchEnd]).
  void _sendEnd() {
    final id = _route?.id ?? state.routeId;
    final byWatch = _endedByWatch;
    _endedByWatch = false;
    if (!_follow || byWatch || id == null) return;
    unawaited(ref.read(garminBridgeProvider).send([watchEndOf(id)]));
  }

  void _release() {
    _follow = false;
    _sendingId = null;
    _sentIds.clear();
    _gen++;
    _line = null;
    _route = null;
    _inputs = null;
    _early = null;
    _prepared = null;
    _again = false;
    _gps = false;
    _watchFix = null;
    _freeLine = false;
    _freeTrailId = null;
    _watchRouteId = null;
    _ackTimer?.cancel();
    _nudgeTimer?.cancel();
    _stopPositions();
    if (state.phase != WatchSyncPhase.idle) state = const WatchSyncState();
  }

  /// Die Route an die Uhr: vereinfacht, mit Höhen, falls sie in
  /// [kWatchHeightsWait] kommen, und den Abzweigungen, falls sie in
  /// [kWatchBranchesWait] kommen (beides zugleich; schon beim Startblatt
  /// angestoßen, wenn es dieselbe Linie war — [prepare]). Derweil stößt das
  /// Handy die Uhr-App an; läuft sie, gehen die Stücke, sonst warten sie
  /// auf ihr `hi`.
  Future<void> _show(List<LatLng> points, NavSections sections) async {
    final gen = ++_gen;
    _line = points;
    _route = null;
    _inputs = null;
    _shrunk = false;
    _early = null;
    _ackTimer?.cancel();
    _nudgeTimer?.cancel();
    final bridge = ref.read(garminBridgeProvider);
    state = const WatchSyncState(phase: WatchSyncPhase.sending);
    // Die Frage auf der Uhr gleich: Bis jemand bestätigt, ist die Route
    // gerechnet.
    final opening = bridge.open();
    // Vorbereitet gilt nur für dieselbe Linie, und nur einmal: Jede
    // spätere Route der Navigation rechnet selbst.
    final ready = _prepared;
    _prepared = null;
    final same = ready != null && _sameLine(ready.line, points);
    final branchesSoon = (same ? ready.branches : _branchesOf(points))
        .timeout(kWatchBranchesWait, onTimeout: () => const <WatchBranch>[]);
    final heights =
        await (same ? ready.heights : _heightsOf(points)).timeout(kWatchHeightsWait, onTimeout: () => null);
    final branches = await branchesSoon;
    final open = await opening;
    if (gen != _gen) return;
    final route = watchRouteOf(points, sections, heights: heights, branches: branches);
    if (route == null) {
      state = const WatchSyncState(phase: WatchSyncPhase.failed, error: 'EMPTY');
      return;
    }
    _route = route;
    _inputs = (points: points, sections: sections, heights: heights, branches: branches);
    if (open == WatchOpen.notInstalled) {
      state = WatchSyncState(phase: WatchSyncPhase.failed, routeId: route.id, error: 'APP_IS_NOT_INSTALLED');
      return;
    }
    if (_outdated != null) return _failedOutdated();
    final early = _early;
    _early = null;
    if (early != null) return _onHello(early.id, early.bad, kWatchProtocol, early.ver);
    if (open == WatchOpen.prompted) {
      state = WatchSyncState(phase: WatchSyncPhase.prompted, routeId: route.id);
      _nudge(0);
      return;
    }
    await _push();
  }

  /// Die Stücke der Route an die Uhr, eine Übertragung nach der anderen:
  /// Kommt währenddessen eine neue Route (oder ein `hi`, das eine andere
  /// will), geht danach die dann aktuelle.
  Future<void> _push() async {
    if (_pushing) {
      _again = true;
      return;
    }
    _pushing = true;
    try {
      do {
        _again = false;
        final route = _route;
        if (route == null || !_follow) return;
        if (_outdated != null) return _failedOutdated();
        _sendingId = route.id;
        try {
          await _pushOnce(route);
        } finally {
          _sendingId = null;
        }
      } while (_again);
    } finally {
      _pushing = false;
    }
  }

  /// Eine Übertragung; danach wartet das Handy auf „gespeichert",
  /// höchstens [kWatchAckWait].
  Future<void> _pushOnce(WatchRoute route) async {
    final gen = _gen;
    final parts = route.parts();
    _nudgeTimer?.cancel();
    state = WatchSyncState(phase: WatchSyncPhase.sending, routeId: route.id, parts: parts.length);
    final bridge = ref.read(garminBridgeProvider);
    // Erst die Ankündigung: Sie ist klein und gleich da, die Stücke
    // brauchen je ~15 s — eine startende Uhr zeigt so den Lader statt der
    // alten Route. Eine laufende übergeht sie. Das SDK sendet der Reihe
    // nach (GarminBridge.kt).
    unawaited(bridge.send([watchAnnounceOf(route.id, parts.length)]));
    _sentIds.add(route.id);
    var result = await bridge.send(parts);
    // Mittendrin abgebrochen: die übrigen Stücke noch einmal, die Uhr hat
    // die angekommenen schon abgelegt.
    var done = 0;
    for (var k = 0; k < kWatchResumes && !result.ok && _resumable.contains(result.status); k++) {
      done += result.sent;
      if (done >= parts.length) break;
      await Future<void>.delayed(kWatchResumePause);
      if (gen != _gen || _route?.id != route.id) return;
      final rest = await bridge.send(parts.sublist(done));
      result = WatchSendResult(rest.status, rest.ok ? parts.length - done : rest.sent);
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
        _nudge(0);
      }
    });
  }

  /// Nach [kWatchNudges] ein `q`, solange die Uhr nicht bestätigt hat.
  void _nudge(int step) {
    _nudgeTimer?.cancel();
    if (step >= kWatchNudges.length) return;
    final gen = _gen;
    _nudgeTimer = Timer(kWatchNudges[step], () {
      final waiting = state.phase == WatchSyncPhase.prompted || state.phase == WatchSyncPhase.unconfirmed;
      if (gen != _gen || !_follow || !waiting) return;
      if (!_pushing) unawaited(ref.read(garminBridgeProvider).send([watchQuery]));
      _nudge(step + 1);
    });
  }

  void _onAnswer(Object? message) {
    final hello = watchHelloOf(message);
    if (hello.hello) return _onHello(hello.id, hello.bad, hello.v, hello.ver);
    // #501 (Konzept 2, was der Alarm auslöst): Weicht die Uhr ab, rechnet
    // das Handy die Linie ab ihrem Stand neu und schickt sie; die Uhr fragt
    // kurz, ob sie sie nimmt.
    final drift = watchDriftOf(message);
    if (drift != null) {
      _replanForWatch(drift.at, drift.offM);
      return;
    }
    final ended = watchEndedId(message);
    if (ended != null) {
      // Auf der Uhr beendet: die Navigation des Handys auch — die
      // Aufzeichnung läuft weiter (NavController.stop).
      if (!_follow || !_sentIds.contains(ended)) return;
      _endedByWatch = true;
      ref.read(navigationProvider.notifier).stop();
      return;
    }
    if (watchHasGps(message)) {
      _gps = true;
      _watchFix = watchFixOf(message);
      _stopPositions();
      _offerFreeLine(_watchFix);
      return;
    }
    final error = watchErrorOf(message);
    if (error != null) {
      if (!_follow || error.id != _route?.id) return;
      if (error.code == kWatchErrVersion) {
        _outdated = watchOutdatedOf(error.v) ?? WatchOutdated.watch;
        return _failedOutdated();
      }
      return watchErrorWantsSmaller(error.code) ? _shrink() : _failed('WATCH_${error.code}');
    }
    final id = watchStoredId(message);
    // Nur die Bestätigung der Route, die gerade auf die Uhr gehört.
    if (id == null || !_follow || id != _route?.id) return;
    _stored(id);
  }

  /// Die Uhr-App meldet sich: Spricht sie eine andere Fassung, geht nichts
  /// hin, und die Leiste nennt die veraltete Seite. Hat sie die Route
  /// schon, gilt sie als gespeichert; sonst geht die aktuelle. Eine neu
  /// gestartete Uhr-App hat ihr GPS noch nicht.
  void _onHello(String? id, String? bad, int? v, String? ver) {
    if (!_follow) {
      // Keine Navigation auf dem Handy: Nur die Uhr ohne Linie bekommt eine —
      // die nächste in Reichweite (#484). Sonst bleibt sie in Ruhe.
      _watchRouteId = id;
      _watchVer = ver;
      if (id == null) _offerFreeLine(_watchFix);
      return;
    }
    _watchRouteId = id;
    _watchVer = ver;
    _outdated = watchOutdatedOf(v);
    _gps = false;
    final route = _route;
    if (_outdated != null) {
      _early = null;
      if (route != null) _failedOutdated();
      return;
    }
    final bridge = ref.read(garminBridgeProvider);
    if (route == null) {
      _early = (id: id, bad: bad, ver: ver);
      // Die Uhr wartet beim Start auf eine Antwort: Es kommt eine, nur
      // noch nicht fertig gerechnet.
      unawaited(bridge.send([watchAnnounceOf(null, 0)]));
      // Hat die Uhr gar keine Route und das Handy keine Navigation, fährt
      // sie frei: der nächste Trail in Reichweite geht an sie (#484).
      if (id == null) _offerFreeLine(_watchFix);
      return;
    }
    if (id == route.id) {
      unawaited(bridge.send([watchCurrentOf(id!)]));
      return _stored(id);
    }
    // Die Uhr-App stürzte mit dieser Route zweimal ab und hat sie
    // verworfen: Noch einmal dieselbe hieße noch ein Absturz.
    if (bad == route.id) return _shrink();
    // Sie geht gerade hinüber (das „hallo" kam auf das Nachfassen): nicht
    // noch einmal.
    if (_pushing && _sendingId == route.id) return;
    unawaited(_push());
  }

  /// Die Uhr hat keine Linie, das Handy keine Navigation: die nächste
  /// Trail-Linie in Reichweite geht an sie (#484, Konzept 2). Liegt nichts
  /// da, bleibt die Uhr bei ihrer eigenen Spur — und eine neue Linie bringt
  /// erst die Navigation oder die Driftmeldung der Uhr.
  void _offerFreeLine(LatLng? at) {
    if (at == null || _freeLine || _route != null || _pushing) return;
    if (_watchRouteId != null) return; // Die Uhr hat schon eine Linie.
    // Das Handy versorgt diese Uhr von nun an mit Linien.
    if (ref.read(navigationProvider) != null) return;
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    final found = nearestTrailLine(trails, at);
    if (found == null) return;
    _follow = true;
    _freeLine = true;
    _freeTrailId = found.trail.id;
    unawaited(_show(found.points, freeSections(found.trail, found.points)));
  }

  /// #501 (Konzept 2): Die Uhr meldet, dass sie neben ihrer Linie fährt. Das
  /// Handy rechnet sie ab ihrem Stand um (wie Route umplanen, #464) und
  /// schickt die neue Linie — die Uhr-App ab 1.3.0 fragt vorher, ob sie sie
  /// nimmt; eine ältere nähme sie still, und die ließ man bisher in Ruhe.
  /// Gerechnet wird erst ab der Schwelle der Seite Navigation im Profil.
  void _replanForWatch(LatLng at, double offM) {
    if (!_follow || !watchKnowsAsk(_watchVer) || _replanRunning) return;
    if (ref.read(navigationProvider) == null) {
      // Freiheit statt Navigation: die Uhr fährt ohne Ziel. Liegt neben
      // ihrer Linie ein anderer Trail, geht der an sie (#484).
      _watchFix = at;
      final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
      final found = nearestTrailLine(trails, at);
      if (found == null || found.trail.id == _freeTrailId) return;
      _freeTrailId = found.trail.id;
      unawaited(_show(found.points, freeSections(found.trail, found.points)));
      return;
    }
    if (offM < ref.read(navReplanOfferDistanceProvider)) return;
    _replanRunning = true;
    unawaited(ref.read(navigationProvider.notifier)
        .replan(from: at)
        .then((_) => _replanRunning = false));
  }

  /// Die Uhr kann die Route nicht nehmen (Speicher, Absturz): einmal mit
  /// halb so vielen Punkten neu rechnen und schicken, sonst aufgeben. Eine
  /// stärker vereinfachte Linie hat eine andere Kennung.
  void _shrink() {
    final route = _route, inputs = _inputs;
    if (route == null) return;
    if (_shrunk || inputs == null) return _failed(kWatchTooBig);
    _shrunk = true;
    final smaller = watchRouteOf(inputs.points, inputs.sections,
        heights: inputs.heights, branches: inputs.branches, maxPoints: math.max(2, route.pointCount ~/ 2));
    if (smaller == null || smaller.id == route.id) return _failed(kWatchTooBig);
    _route = smaller;
    unawaited(_push());
  }

  void _failedOutdated() =>
      _failed(_outdated == WatchOutdated.phone ? kWatchOutdatedPhone : kWatchOutdatedWatch);

  void _failed(String error) {
    _ackTimer?.cancel();
    _nudgeTimer?.cancel();
    state = WatchSyncState(phase: WatchSyncPhase.failed, routeId: _route?.id, parts: state.parts, error: error);
  }

  /// Die Uhr ist wieder da: Läuft ihre App, sagt ihr `hi`, ob die Route
  /// noch stimmt — kein Abfragen im Takt.
  void _onReconnect() {
    if (!_follow || _route == null || _pushing) return;
    unawaited(ref.read(garminBridgeProvider).send([watchQuery]));
  }

  void _stored(String id) {
    _ackTimer?.cancel();
    _nudgeTimer?.cancel();
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
    _startPositions();
  }

  /// Die Position des Handys an die Uhr, gleich und dann alle
  /// [kWatchPositionEvery], bis die Uhr eigenes GPS meldet, die
  /// Navigation endet oder [kWatchPositionFor] um ist. Läuft der Takt
  /// schon, bleibt er.
  void _startPositions() {
    if (_gps || _positionTimer != null) return;
    _positionTicks = 0;
    _sendPosition();
    _positionTimer = Timer.periodic(kWatchPositionEvery, (_) {
      _positionTicks++;
      if (_positionTicks * kWatchPositionEvery.inSeconds >= kWatchPositionFor.inSeconds) {
        _stopPositions();
        return;
      }
      _sendPosition();
    });
  }

  void _sendPosition() {
    if (!_follow || _gps || _pushing || state.phase != WatchSyncPhase.stored) return;
    final p = ref.read(navigationProvider)?.state?.position;
    if (p == null) return;
    unawaited(ref.read(garminBridgeProvider).send([watchPositionOf(p)]));
  }

  void _stopPositions() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  /// Die Navigation kopiert die Punkte (`NavRoute.of`): gleich heißt
  /// Punkt für Punkt gleich.
  static bool _sameLine(List<LatLng> a, List<LatLng> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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

class _Prepared {
  _Prepared(this.line, this.heights, this.branches);

  final List<LatLng> line;
  final Future<ElevationProfile?> heights;
  final Future<List<WatchBranch>> branches;
}
