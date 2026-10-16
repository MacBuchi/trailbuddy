// Der Planer als Modus der Karte (seit 0.74.0, Betreiber: „zum Planen
// links ein Menü in der Art wie rechts, mit Planer-Optionen"). Der Zustand
// lebt HIER, nicht in einem Blatt: Leiste (`loop_tool_rail.dart`), Karte
// (Hervorhebung, Start-Nadel, Tipp auf einen Trail) und Ergebnis-Blatt
// (`loop_planner_sheet.dart`) lesen dieselbe Wahrheit.
//
// Vier Dinge, die man wissen muss:
// - **Die Auswahl macht der Nutzer.** Ein Tipp auf einen Trail der Karte
//   wählt ihn an, ein zweiter ab; die Liste (mit einstellbarem Radius) und
//   das gezeichnete Gebiet sind zwei weitere Wege zu DERSELBEN Menge. Der
//   Radius begrenzt nur die Liste — was angetippt ist, gehört dazu.
// - **Uphill-Trails und Verbinder sind nicht wählbar**: Sie sind der Weg
//   bergauf, die Runde nutzt sie von selbst (#185, `trail_overlay.dart`).
// - **Der Start ist der Standort, solange keiner getippt ist** — der Fix
//   kommt erst beim Rechnen (oder beim Öffnen der Liste), nie beim
//   Öffnen des Planers.
// - **Das Ziel ist ein Tipp wie der Start** (#331): nur im Modus
//   [LoopEndMode.target], nur für die Sitzung; ohne Ziel rechnet der
//   Planer nicht ([LoopBlocker.noTarget]).
// - **Zwischenpunkte vorab** (#331 Schritt 4): Tipps wie Start und Ziel,
//   oder ein Ort; die Fahrt muss durch sie, die Reihenfolge wählt der
//   Planer. Nur für die Sitzung.
// - **Rechnen geht nie still schief**: Jeder Ausgang hat eine Phase oder
//   einen Grund ([LoopBlocker]), ein Fehler wird gemeldet.
import 'dart:async';

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../core/settings.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import '../map/position_provider.dart';
import '../offline_areas/area_draw.dart' show AreaDrawTool;
import '../profile/profile_providers.dart';
import '../trails/trail_providers.dart';
import 'loop_plan_runner.dart';
import 'loop_planner.dart';
import 'planning_graph.dart';
import 'ride_calibrator.dart';
import 'road_graph.dart';
import 'route_profile.dart';
import 'route_via_providers.dart';
import 'route_vias.dart';
import 'trail_overlay.dart';

enum LoopPhase { idle, locating, loading, computing, result }

enum LoopBlocker { noPosition, noTarget, noArea, noTrails, failed }

class LoopSession {
  const LoopSession({
    this.open = false,
    this.start,
    this.pickingStart = false,
    this.target,
    this.pickingTarget = false,
    this.waypoints = const [],
    this.pickingWaypoint = false,
    this.drawTool,
    this.selected = const {},
    this.mandatory = const {},
    required this.prefs,
    required this.profile,
    this.phase = LoopPhase.idle,
    this.blocker,
    this.plan,
    this.planStart,
    this.planEnd = LoopEndMode.loop,
    this.coverage,
    this.tuned = false,
  });

  /// Der Planer-Modus ist an: Leiste links, Tipps wählen Trails.
  final bool open;

  /// Der getippte Start; null heißt der eigene Standort.
  final LatLng? start;

  /// Der nächste Tipp auf die Karte ist der Start.
  final bool pickingStart;

  /// Das getippte Ziel (#331) — zählt nur im Modus [LoopEndMode.target].
  final LatLng? target;

  /// Der nächste Tipp auf die Karte ist das Ziel.
  final bool pickingTarget;

  /// Vorab gesetzte Zwischenpunkte (#331 Schritt 4), in der Folge des
  /// Setzens — gefahren in der, die der Planer wählt.
  final List<LatLng> waypoints;

  /// Der nächste Tipp auf die Karte ist ein Zwischenpunkt.
  final bool pickingWaypoint;

  /// Wartet auf einen Tipp: Start, Ziel oder Zwischenpunkt.
  bool get picking => pickingStart || pickingTarget || pickingWaypoint;

  /// Ein Gebiet wird gezeichnet: dazu ([AreaDrawTool.add]) oder weg.
  final AreaDrawTool? drawTool;

  final Set<String> selected;

  /// Muss dabei sein (Stern in der Liste).
  final Set<String> mandatory;
  final LoopPrefs prefs;
  final RiderProfile profile;
  final LoopPhase phase;
  final LoopBlocker? blocker;
  final LoopPlan? plan;

  /// Wo die gerechnete Runde wirklich beginnt (Standort oder Tipp).
  final LatLng? planStart;

  /// Wie die gezeigte Planung endet — „Runde" heißt sie nur bei
  /// [LoopEndMode.loop], auch wenn der Regler inzwischen anders steht.
  final LoopEndMode planEnd;

  /// Der geladene Graph, aus dem das Blatt seinen Satz über die Kacheln
  /// macht (`planningCoverageNote` — Teil, online nachgeladen). Der Satz
  /// selbst entsteht erst im Blatt, in dessen Sprache (#209).
  final PlanningGraph? coverage;

  /// Die Runde ist von Hand getunt (#234): feste Folge, Teilstücke durch
  /// Zwischenpunkte. „Zurücksetzen" rechnet wieder frei.
  final bool tuned;

  bool get busy => phase == LoopPhase.locating || phase == LoopPhase.loading || phase == LoopPhase.computing;

  LoopSession copyWith({
    bool? open,
    LatLng? start,
    bool clearStart = false,
    bool? pickingStart,
    LatLng? target,
    bool? pickingTarget,
    List<LatLng>? waypoints,
    bool? pickingWaypoint,
    AreaDrawTool? drawTool,
    bool clearDrawTool = false,
    Set<String>? selected,
    Set<String>? mandatory,
    LoopPrefs? prefs,
    RiderProfile? profile,
    LoopPhase? phase,
    LoopBlocker? blocker,
    bool clearBlocker = false,
    LoopPlan? plan,
    bool clearPlan = false,
    LatLng? planStart,
    LoopEndMode? planEnd,
    PlanningGraph? coverage,
    bool? tuned,
  }) =>
      LoopSession(
        open: open ?? this.open,
        start: clearStart ? null : (start ?? this.start),
        pickingStart: pickingStart ?? this.pickingStart,
        target: target ?? this.target,
        pickingTarget: pickingTarget ?? this.pickingTarget,
        waypoints: waypoints ?? this.waypoints,
        pickingWaypoint: pickingWaypoint ?? this.pickingWaypoint,
        drawTool: clearDrawTool ? null : (drawTool ?? this.drawTool),
        selected: selected ?? this.selected,
        mandatory: mandatory ?? this.mandatory,
        prefs: prefs ?? this.prefs,
        profile: profile ?? this.profile,
        phase: phase ?? this.phase,
        blocker: clearBlocker ? null : (blocker ?? this.blocker),
        plan: clearPlan ? null : (plan ?? this.plan),
        planStart: clearPlan ? null : (planStart ?? this.planStart),
        planEnd: planEnd ?? this.planEnd,
        coverage: coverage ?? this.coverage,
        tuned: clearPlan ? (tuned ?? false) : (tuned ?? this.tuned),
      );
}

/// Wofür ein Punkt ohne Tipp in den Planer kommt (#331): Ort oder
/// Trailkopf.
enum LoopPlaceRole { start, waypoint, target }

/// Ein Tipp auf einen vorab gesetzten Zwischenpunkt (#331 Schritt 4) —
/// die Karte nimmt ihn weg.
class LoopWaypointHit {
  const LoopWaypointHit(this.index);

  final int index;
}

/// Was ein Tipp auf einen Trail im Planer getan hat — die Karte sagt es,
/// wenn er nicht wählbar ist.
enum LoopToggle { selected, deselected, connector, pending }

class LoopPlannerNotifier extends Notifier<LoopSession> {
  RoadGraph? _graph;
  LatLng? _graphStart;

  /// Der Rahmen, für den [_graph] geladen ist. Ein Trail darin liegt schon
  /// auf dem Graphen, seine Enden sind angeheftet — ihn dazuzuwählen
  /// braucht kein neues Laden, und der Rechen-Isolate behält den Graphen
  /// samt seinen Suchen (#188).
  LatBox? _graphBox;
  bool _graphOnline = false;

  /// Rechnet die Runde (#188: auf dem Telefon im Rechen-Isolate); lebt mit
  /// dem Modus und wird beim Schließen freigegeben.
  LoopPlanRunner? _runner;

  /// Steigt beim Schließen des Planers oder des Ergebnisses: Was danach
  /// ankommt, gehört zu einer Rechnung, die niemand mehr sehen will.
  int _generation = 0;

  /// Das Ziel, mit dem [LoopSession.plan] gerechnet ist — ein neuer Tipp
  /// räumt den Plan, das Tunen braucht trotzdem DIESES.
  LatLng? _planTarget;

  /// Die vorab gesetzten Zwischenpunkte, mit denen [LoopSession.plan]
  /// gerechnet ist — das Tunen braucht DIESE, wie beim Ziel.
  List<LatLng> _planWaypoints = const [];

  /// Die Zwischenpunkte, mit denen [LoopSession.plan] gerechnet ist.
  RouteVias _vias = RouteVias.none;
  int _tuneSeq = 0;

  @override
  LoopSession build() {
    ref.onDispose(() => _runner?.dispose());
    // Die Karte ändert die Punkte, hier wird gerechnet (#234).
    ref.listen(routeViaProvider, (_, next) {
      if (next == null || next.owner != ViaOwner.loop || next.vias == _vias) return;
      unawaited(_retune(next.vias));
    });
    final profile = ref.read(riderProfileProvider);
    return LoopSession(prefs: LoopPrefs.parse(ref.read(settingsProvider).loopPlannerPrefs, profile), profile: profile);
  }

  List<Trail> get _trails => ref.read(trailsProvider).valueOrNull ?? const <Trail>[];

  /// Den Modus öffnen; [start] aus „Route ab hier".
  void open({LatLng? start}) {
    // Ohne neuen Start bleibt ein früher getippter stehen.
    state = state.copyWith(
        open: true, start: start, pickingStart: false, pickingTarget: false, pickingWaypoint: false, clearDrawTool: true);
  }

  /// Den Modus schließen. Die Auswahl bleibt für die Sitzung — wer
  /// wiederkommt, findet seine Trails noch angewählt.
  void close() {
    ref.read(routeViaProvider.notifier).end(ViaOwner.loop);
    _generation++;
    _runner?.dispose();
    _runner = null;
    state = state.copyWith(
      open: false,
      pickingStart: false,
      pickingTarget: false,
      pickingWaypoint: false,
      clearDrawTool: true,
      clearPlan: true,
      clearBlocker: true,
      phase: LoopPhase.idle,
    );
  }

  LoopToggle toggle(Trail t) {
    if (t.pending) return LoopToggle.pending;
    if (trailRoleOf(t) != TrailRole.downhill) return LoopToggle.connector;
    final selected = {...state.selected};
    final mandatory = {...state.mandatory};
    final on = selected.add(t.id);
    if (!on) {
      selected.remove(t.id);
      mandatory.remove(t.id);
    }
    state = state.copyWith(selected: selected, mandatory: mandatory, clearPlan: true, clearBlocker: true);
    return on ? LoopToggle.selected : LoopToggle.deselected;
  }

  void setSelected(Iterable<String> ids, bool on) {
    final selected = {...state.selected};
    final mandatory = {...state.mandatory};
    for (final id in ids) {
      if (on) {
        selected.add(id);
      } else {
        selected.remove(id);
        mandatory.remove(id);
      }
    }
    state = state.copyWith(selected: selected, mandatory: mandatory, clearPlan: true, clearBlocker: true);
  }

  void clearSelection() =>
      state = state.copyWith(selected: const {}, mandatory: const {}, clearPlan: true, clearBlocker: true);

  void toggleMandatory(String id) {
    final mandatory = {...state.mandatory};
    final selected = {...state.selected};
    if (!mandatory.remove(id)) {
      mandatory.add(id);
      selected.add(id);
    }
    state = state.copyWith(selected: selected, mandatory: mandatory, clearPlan: true);
  }

  /// Ein gezeichnetes Gebiet: was es fasst, kommt dazu bzw. fällt weg
  /// (nur wählbare Trails — Abfahrten).
  int applyRing(List<LatLng> ring) {
    final tool = state.drawTool ?? AreaDrawTool.add;
    final hits = trailsInRing(
        _trails.where((t) => !t.pending && trailRoleOf(t) == TrailRole.downhill), ring);
    setSelected(hits, tool == AreaDrawTool.add);
    state = state.copyWith(clearDrawTool: true);
    return hits.length;
  }

  /// Ein Werkzeug scharf machen; derselbe Knopf noch einmal entschärft.
  void armDraw(AreaDrawTool tool) => state = state.drawTool == tool
      ? state.copyWith(clearDrawTool: true)
      : state.copyWith(drawTool: tool, pickingStart: false, pickingTarget: false, pickingWaypoint: false);

  void disarmDraw() => state = state.copyWith(clearDrawTool: true);

  void armStartPick() =>
      state = state.copyWith(pickingStart: true, pickingTarget: false, pickingWaypoint: false, clearDrawTool: true);

  /// Bricht ab, worauf der Tipp gerade wartet — Start, Ziel oder
  /// Zwischenpunkt.
  void cancelStartPick() => state = state.copyWith(pickingStart: false, pickingTarget: false, pickingWaypoint: false);

  void takeStart(LatLng p) =>
      state = state.copyWith(start: p, pickingStart: false, clearPlan: true, clearBlocker: true);

  void armTargetPick() =>
      state = state.copyWith(pickingTarget: true, pickingStart: false, pickingWaypoint: false, clearDrawTool: true);

  void armWaypointPick() =>
      state = state.copyWith(pickingWaypoint: true, pickingStart: false, pickingTarget: false, clearDrawTool: true);

  void takeWaypoint(LatLng p) => setWaypoints([...state.waypoints, p]);

  /// Die Zwischenpunkte ersetzen — Entfernen, Leeren, Rückgängig.
  void setWaypoints(List<LatLng> waypoints) => state =
      state.copyWith(waypoints: waypoints, pickingWaypoint: false, clearPlan: true, clearBlocker: true);

  void removeWaypoint(int k) {
    if (k < 0 || k >= state.waypoints.length) return;
    setWaypoints([...state.waypoints]..removeAt(k));
  }

  void takeTarget(LatLng p) =>
      state = state.copyWith(target: p, pickingTarget: false, clearPlan: true, clearBlocker: true);

  /// Wohin der nächste Tipp geht: Start, Ziel oder Zwischenpunkt. Falsch,
  /// wenn der Planer auf keinen wartet.
  bool takePick(LatLng p) {
    if (!state.open) return false;
    if (state.pickingStart) {
      takeStart(p);
    } else if (state.pickingTarget) {
      takeTarget(p);
    } else if (state.pickingWaypoint) {
      takeWaypoint(p);
    } else {
      return false;
    }
    return true;
  }

  /// Der Trailkopf aus dem Trail-Blatt (#331 Schritt 2). Als Start kommt
  /// der Trail in die Auswahl, wenn er wählbar ist — wer an seinem Kopf
  /// losfährt, will ihn fahren; als Ziel schaltet er auf „Zum Ziel" und
  /// bleibt, wie er war (am Kopf endet die Fahrt, bevor er beginnt).
  void takeTrailHead(Trail t, {required bool asTarget}) {
    takePlace(t.start, asTarget ? LoopPlaceRole.target : LoopPlaceRole.start);
    if (!asTarget && !t.pending && trailRoleOf(t) == TrailRole.downhill) setSelected([t.id], true);
  }

  /// Ein Punkt als Start, Zwischenpunkt oder Ziel, ohne Tipp auf die
  /// Karte — ein Ort aus der Ebene „Orte" (#331 Schritte 3 und 4) oder ein
  /// Trailkopf. Als Ziel schaltet er auf „Zum Ziel" (gemerkt wie über die
  /// Parameter).
  void takePlace(LatLng p, LoopPlaceRole role) {
    switch (role) {
      case LoopPlaceRole.start:
        takeStart(p);
      case LoopPlaceRole.waypoint:
        takeWaypoint(p);
      case LoopPlaceRole.target:
        if (state.prefs.endMode != LoopEndMode.target) setPrefs(state.prefs.copyWith(endMode: LoopEndMode.target));
        takeTarget(p);
    }
  }

  void useMyPosition() => state = state.copyWith(clearStart: true, clearPlan: true, clearBlocker: true);

  void setPrefs(LoopPrefs prefs) {
    // Ohne den Modus „Zum Ziel" wartet auch kein Tipp mehr aufs Ziel.
    state = state.copyWith(
      prefs: prefs,
      clearPlan: true,
      pickingTarget: prefs.endMode == LoopEndMode.target ? null : false,
    );
    ref.read(settingsProvider).setLoopPlannerPrefs(prefs.encode()).catchError((Object e, StackTrace s) {
      logError('Planer-Regler merken', e, s);
    });
  }

  void setProfile(RiderProfile next) {
    var prefs = state.prefs;
    // Steht das Höhenbudget auf der Vorgabe des alten Profils, folgt es dem
    // neuen — wer es selbst gestellt hat, behält es.
    if (prefs.climbM == state.profile.budgetClimbM) prefs = prefs.copyWith(climbM: next.budgetClimbM);
    state = state.copyWith(profile: next, prefs: prefs, clearPlan: true);
  }

  /// Das Ergebnis weglegen (Blatt zu); Modus und Auswahl bleiben.
  void clearResult() {
    ref.read(routeViaProvider.notifier).end(ViaOwner.loop);
    // Eine Rechnung, die noch läuft, gehört zu diesem Ergebnis.
    _generation++;
    state = state.copyWith(clearPlan: true, clearBlocker: true, phase: LoopPhase.idle);
  }

  /// Der Mittelpunkt der Liste: getippter Start, sonst der Standort (mit
  /// Fix, wenn noch keiner läuft). Null ohne beides.
  Future<LatLng?> listCenter() async {
    final s = state.start;
    if (s != null) return s;
    final known = ref.read(positionStreamProvider).valueOrNull;
    if (known != null) return LatLng(known.latitude, known.longitude);
    final fix = await ref.read(positionFixProvider)();
    return fix == null ? null : LatLng(fix.latitude, fix.longitude);
  }

  /// Rechnen. Jeder Ausgang ist eine Phase oder ein Grund.
  Future<void> compute() async {
    if (state.busy) return;
    // Frei gerechnet: Die Punkte der alten Runde gelten nicht mehr.
    ref.read(routeViaProvider.notifier).end(ViaOwner.loop);
    _vias = RouteVias.none;
    final chosen = [
      for (final t in _trails)
        if (state.selected.contains(t.id) && !t.pending && t.points.length >= 2) t,
    ];
    if (chosen.isEmpty) {
      state = state.copyWith(phase: LoopPhase.result, blocker: LoopBlocker.noTrails, clearPlan: true);
      return;
    }
    final endMode = state.prefs.endMode;
    final target = endMode == LoopEndMode.target ? state.target : null;
    if (endMode == LoopEndMode.target && target == null) {
      state = state.copyWith(phase: LoopPhase.result, blocker: LoopBlocker.noTarget, clearPlan: true);
      return;
    }
    final waypoints = state.waypoints;
    state = state.copyWith(
        clearPlan: true,
        clearBlocker: true,
        clearDrawTool: true,
        pickingStart: false,
        pickingTarget: false,
        pickingWaypoint: false);
    final generation = _generation;
    try {
      var start = state.start;
      if (start == null) {
        state = state.copyWith(phase: LoopPhase.locating);
        final fix = await ref.read(positionFixProvider)();
        if (generation != _generation) return;
        if (fix == null) {
          state = state.copyWith(phase: LoopPhase.result, blocker: LoopBlocker.noPosition);
          return;
        }
        start = LatLng(fix.latitude, fix.longitude);
      }
      final fillOnline = state.prefs.fillOnline;
      if (_graph == null ||
          _graphStart != start ||
          (target != null && !_graphBox!.contains(LatBox.of([target]))) ||
          (waypoints.isNotEmpty && !_graphBox!.contains(LatBox.of(waypoints))) ||
          !chosen.every((t) => _graphBox!.contains(LatBox.of(t.directedPoints))) ||
          _graphOnline != fillOnline) {
        state = state.copyWith(phase: LoopPhase.loading);
        final s0 = start;
        // Die Uphill-Trails und Verbinder im Umkreis gehören in den Rahmen —
        // sie sind der Weg bergauf (#185).
        final connectors = loopPoolOf(_trails, s0, reachM: state.prefs.radiusKm * 1000).connectors;
        final box = LatBox.of([
          s0,
          ?target,
          ...waypoints,
          for (final t in chosen) ...t.directedPoints,
          for (final t in connectors) ...t.points,
        ]);
        final loaded = await ref.read(planningGraphLoaderProvider)(box, fillOnline: fillOnline);
        if (generation != _generation) return;
        if (loaded.graph == null) {
          state = state.copyWith(phase: LoopPhase.result, blocker: LoopBlocker.noArea);
          return;
        }
        _graph = loaded.graph;
        _graphStart = start;
        _graphBox = box;
        _graphOnline = fillOnline;
        state = state.copyWith(coverage: loaded);
      }
      state = state.copyWith(phase: LoopPhase.computing);
      // Ein Bild für den Kreisel, bevor die Rechnung den Takt belegt.
      await WidgetsBinding.instance.endOfFrame;
      final plan = await (_runner ??= ref.read(loopPlanRunnerFactoryProvider)()).plan(
        _graph!,
        LoopRequest(
          start: start,
          // Mit den gelernten Werten des Profils (Schritt 6), wo es welche gibt.
          profile: ref.read(calibratedRiderProvider(state.profile)).withPrefs(state.prefs.route),
          budget: state.prefs.budget,
          pool: [for (final t in chosen) poolTrailOf(serviceL10n(), t, mandatory: state.mandatory.contains(t.id))],
          returnToStart: endMode == LoopEndMode.loop,
          end: target,
          waypoints: waypoints,
        ),
      );
      if (generation != _generation) return;
      _planTarget = target;
      _planWaypoints = waypoints;
      state = state.copyWith(phase: LoopPhase.result, plan: plan, planStart: start, planEnd: endMode);
      if (plan.outcome == LoopOutcome.ok) ref.read(routeViaProvider.notifier).begin(ViaOwner.loop);
    } catch (e, s) {
      // Geschlossen, während er rechnete: kein Fehler, nur zu spät.
      if (generation != _generation) return;
      logError('Runde planen', e, s);
      state = state.copyWith(phase: LoopPhase.result, blocker: LoopBlocker.failed);
    }
  }

  /// Die Runde mit fester Folge durch [vias] neu (#234). Das Ergebnis
  /// bleibt stehen, bis das neue da ist — ein Zug am Punkt soll die Linie
  /// umlegen, nicht das Blatt leeren. Geht es nicht, kommen die alten
  /// Punkte zurück.
  Future<void> _retune(RouteVias vias) async {
    final plan = state.plan;
    final start = state.planStart;
    final graph = _graph;
    if (plan == null || plan.outcome != LoopOutcome.ok || start == null || graph == null || state.busy) {
      ref.read(routeViaProvider.notifier).reject(_vias);
      return;
    }
    final generation = _generation;
    final seq = ++_tuneSeq;
    try {
      final next = await (_runner ??= ref.read(loopPlanRunnerFactoryProvider)()).plan(
        graph,
        LoopRequest(
          start: start,
          profile: ref.read(calibratedRiderProvider(state.profile)).withPrefs(state.prefs.route),
          budget: state.prefs.budget,
          pool: [
            for (final t in _trails)
              if (state.selected.contains(t.id) && !t.pending && t.points.length >= 2)
                poolTrailOf(serviceL10n(), t, mandatory: state.mandatory.contains(t.id)),
          ],
          returnToStart: state.planEnd == LoopEndMode.loop,
          end: state.planEnd == LoopEndMode.target ? _planTarget : null,
          tune: LoopTune.of(plan, vias),
          waypoints: _planWaypoints,
        ),
      );
      // Ein späterer Zug hat schon eine neue Rechnung geschickt.
      if (generation != _generation || seq != _tuneSeq) return;
      if (next.outcome != LoopOutcome.ok) {
        ref.read(routeViaProvider.notifier).reject(_vias);
        return;
      }
      _vias = vias;
      state = state.copyWith(plan: next, tuned: true);
    } catch (e, s) {
      if (generation != _generation || seq != _tuneSeq) return;
      logError('Runde tunen', e, s);
      ref.read(routeViaProvider.notifier).reject(_vias);
    }
  }

  /// Zurück zur frei gerechneten Runde.
  Future<void> resetTuning() => compute();
}

final loopPlannerProvider = NotifierProvider<LoopPlannerNotifier, LoopSession>(LoopPlannerNotifier.new);
