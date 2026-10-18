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
// - **Eine Änderung rechnet nicht neu** (#356, D3, Konzept-Routing 10.4):
//   Jede Eingabe geht über `_edit` — Ergebnis weg, Generation hoch, und
//   lag schon etwas im Blatt, sagt es „Auswahl geändert"
//   ([LoopSession.changed]).
// - **Ohne gewählten Trail ist „Zum Ziel" die Route von A nach B**
//   (#356, Konzept-Routing 10.2): im Stil [LoopPrefs.style], gerechnet wie
//   die Runde (`route_result.dart`). Stil und Rad im Ergebnis rechnen
//   sofort ([setStyle], [switchProfile]).
// - **Zu heißt aufgeräumt** (Konzept-Routing 10.5): Auswahl, Start, Ziel
//   und Zwischenpunkte gehen mit; [LoopPlannerNotifier.close] gibt dafür
//   einen [LoopClosed] zurück, mit dem „Rückgängig" alles wiederholt.
// - **Alle Einstiege landen hier** (#356 PR 7, Konzept-Routing 10.3): Wer
//   mit einem fertigen Auftrag kommt („Zum Trailkopf", Navi-Symbol, „Route
//   bis hier", „Route hierher"), bekommt über [beginRoute] einen frischen
//   Planer mit Ziel; bis er etwas ändert, schließt das Ergebnis den ganzen
//   Planer ([LoopSession.quick]).
// - **Der Graph liegt im Runner, nicht hier** (#356 PR 8, Konzept-Routing
//   10.6): Der Controller sammelt nur die Eingabe (`planning_graph.dart`)
//   und merkt sich Rahmen, Start und Schalter, für die der Runner gebaut
//   hat; ein Rahmen über `kPlanMaxTiles` ist [LoopBlocker.tooLarge], und
//   Verbinder kommen nur in der Nähe der Anker in den Rahmen
//   ([kPlanConnectorMarginM]), nicht alle im Radius.
import 'dart:async';

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../core/settings.dart';
import '../../core/stall_watch.dart';
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
import 'route_profile.dart';
import 'route_result.dart';
import 'route_via_providers.dart';
import 'route_vias.dart';
import 'trail_overlay.dart';

/// [loading] liest Kacheln (kurz), [building] baut den Graphen im
/// Rechen-Isolate (am Pixel ~0,33 s je Kachel, #356), [computing] rechnet.
enum LoopPhase { idle, locating, loading, building, computing, result }

enum LoopBlocker { noPosition, noTarget, noArea, noTrails, failed, tooLarge }

/// So weit um Start, Ziel, Zwischenpunkte und gewählte Trails kommen
/// Uphill-Trails und Verbinder in den Rahmen des Graphen (#356 PR 8,
/// Konzept-Routing 10.6). Bis 0.131.0 zählten alle im Radius der Liste
/// (bis 30 km) — ein 60 × 60-km-Rahmen für eine Runde von 12 km.
const kPlanConnectorMarginM = 3000.0;

class LoopSession {
  const LoopSession({
    this.open = false,
    this.start,
    this.pickingStart = false,
    this.target,
    this.targetTrailId,
    this.pickingTarget = false,
    this.waypoints = const [],
    this.pickingWaypoint = false,
    this.drawTool,
    this.selected = const {},
    this.mandatory = const {},
    required this.prefs,
    required this.profile,
    this.phase = LoopPhase.idle,
    this.progress,
    this.blocker,
    this.plan,
    this.planStart,
    this.planEnd = LoopEndMode.loop,
    this.coverage,
    this.tuned = false,
    this.changed = false,
    this.planBare = false,
    this.funEmpty = false,
    this.quick = false,
  });

  /// Der Planer-Modus ist an: Leiste links, Tipps wählen Trails.
  final bool open;

  /// Der getippte Start; null heißt der eigene Standort.
  final LatLng? start;

  /// Der nächste Tipp auf die Karte ist der Start.
  final bool pickingStart;

  /// Das getippte Ziel (#331) — zählt nur im Modus [LoopEndMode.target].
  final LatLng? target;

  /// Ist das Ziel der Kopf eines Trails („Zum Trailkopf"), dessen Kennung:
  /// Die Fahrt heißt nach ihm, die Navigation kennt ihn als Trail hinter
  /// dem Ende, und der spaßige Umweg nimmt ihn nicht mit.
  final String? targetTrailId;

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

  /// Der Fortschritt der laufenden Phase, 0…1 — der Ladebalken (#356,
  /// Betreiber 2026-10-18: mit Balken darf es länger dauern). Null, solange
  /// die Phase nichts meldet; jeder Wechsel der Phase setzt ihn zurück.
  final double? progress;
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

  /// Eine Eingabe hat sich geändert, nachdem schon gerechnet war oder
  /// wurde (D3): Das Blatt sagt „Auswahl geändert" und bietet „Neu
  /// rechnen" an — es rechnet nicht von selbst.
  final bool changed;

  /// Die gezeigte Planung ist eine Route ohne gewählten Trail (#356) —
  /// das Blatt zeigt dazu den Stil.
  final bool planBare;

  /// Spaßig gewählt, aber kein Trail passte in den Umweg: gezeigt ist der
  /// direkte Weg, und das Blatt sagt es.
  final bool funEmpty;

  /// Über einen Einstieg mit fertigem Auftrag geöffnet und seither nichts
  /// geändert (Konzept-Routing 10.4 „Schnell zu"): Zurück oder X am
  /// Ergebnis schließen den ganzen Planer, nicht nur das Blatt. Stil und
  /// Rad im Ergebnis zählen nicht als Änderung.
  final bool quick;

  bool get busy =>
      phase == LoopPhase.locating ||
      phase == LoopPhase.loading ||
      phase == LoopPhase.building ||
      phase == LoopPhase.computing;

  LoopSession copyWith({
    bool? open,
    LatLng? start,
    bool clearStart = false,
    bool? pickingStart,
    LatLng? target,
    String? targetTrailId,
    bool clearTargetTrail = false,
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
    double? progress,
    LoopBlocker? blocker,
    bool clearBlocker = false,
    LoopPlan? plan,
    bool clearPlan = false,
    LatLng? planStart,
    LoopEndMode? planEnd,
    PlanningGraph? coverage,
    bool? tuned,
    bool? changed,
    bool? planBare,
    bool? funEmpty,
    bool? quick,
  }) =>
      LoopSession(
        open: open ?? this.open,
        start: clearStart ? null : (start ?? this.start),
        pickingStart: pickingStart ?? this.pickingStart,
        target: target ?? this.target,
        targetTrailId: clearTargetTrail ? null : (targetTrailId ?? this.targetTrailId),
        pickingTarget: pickingTarget ?? this.pickingTarget,
        waypoints: waypoints ?? this.waypoints,
        pickingWaypoint: pickingWaypoint ?? this.pickingWaypoint,
        drawTool: clearDrawTool ? null : (drawTool ?? this.drawTool),
        selected: selected ?? this.selected,
        mandatory: mandatory ?? this.mandatory,
        prefs: prefs ?? this.prefs,
        profile: profile ?? this.profile,
        phase: phase ?? this.phase,
        progress: progress ?? (phase != null && phase != this.phase ? null : this.progress),
        blocker: clearBlocker ? null : (blocker ?? this.blocker),
        plan: clearPlan ? null : (plan ?? this.plan),
        planStart: clearPlan ? null : (planStart ?? this.planStart),
        planEnd: planEnd ?? this.planEnd,
        coverage: coverage ?? this.coverage,
        tuned: clearPlan ? (tuned ?? false) : (tuned ?? this.tuned),
        changed: changed ?? this.changed,
        planBare: clearPlan ? (planBare ?? false) : (planBare ?? this.planBare),
        funEmpty: clearPlan ? (funEmpty ?? false) : (funEmpty ?? this.funEmpty),
        quick: quick ?? this.quick,
      );
}

/// Was [LoopPlannerNotifier.close] weggeräumt hat — „Rückgängig" holt es
/// mit [LoopPlannerNotifier.restore] zurück (Konzept-Routing 10.5: eine
/// Meldung statt einer Rückfrage). Samt Rahmen des Graphen: Der Runner
/// ist mit dem Schließen weg, der nächste baut aus denselben Bytes
/// denselben Graphen.
class LoopClosed {
  const LoopClosed._(this.session, this._graphStart, this._graphBox, this._graphOnline, this._planRequest, this._vias);

  final LoopSession session;
  final LatLng? _graphStart;
  final LatBox? _graphBox;
  final bool _graphOnline;
  final LoopRequest? _planRequest;
  final RouteVias _vias;

  /// Ein Ergebnis lag im Blatt — die Karte öffnet es wieder.
  bool get hasResult => session.plan != null;
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
  LatLng? _graphStart;

  /// Der Rahmen, für den der Runner seinen Graphen gebaut hat. Ein Trail
  /// darin liegt schon auf dem Graphen, seine Enden sind angeheftet — ihn
  /// dazuzuwählen braucht kein neues Laden, und der Rechen-Isolate
  /// behält den Graphen samt seinen Suchen (#188).
  LatBox? _graphBox;
  bool _graphOnline = false;

  /// Baut und rechnet (#188, #356 PR 8: auf dem Telefon im Rechen-Isolate,
  /// der den Graphen hält); lebt mit dem Modus und wird beim Schließen
  /// freigegeben.
  LoopPlanRunner? _runner;

  /// Der Runner hat den Graphen für [_graphBox]. Falsch nach dem
  /// Schließen (der Runner ist weg) oder wenn der Isolate verloren ging.
  bool get _hasGraph => _graphBox != null && (_runner?.hasGraph ?? false);

  /// Steigt beim Schließen des Planers oder des Ergebnisses: Was danach
  /// ankommt, gehört zu einer Rechnung, die niemand mehr sehen will.
  int _generation = 0;

  /// Die Rechnung hinter [LoopSession.plan] — das Tunen (#234) rechnet
  /// mit IHREN Eingaben (Ziel, Zwischenpunkte, Pool, Stil, Rad), nicht mit
  /// denen, die inzwischen eingestellt sind.
  LoopRequest? _planRequest;

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
    // Das Fahrerprofil gilt sofort (10.4): Ein anderes Rad in den
    // Einstellungen erreicht den offenen Planer, nicht erst den nächsten.
    ref.listen(riderProfileProvider, (_, next) {
      if (next != state.profile) setProfile(next);
    });
    final profile = ref.read(riderProfileProvider);
    return LoopSession(prefs: LoopPrefs.parse(ref.read(settingsProvider).loopPlannerPrefs, profile), profile: profile);
  }

  List<Trail> get _trails => ref.read(trailsProvider).valueOrNull ?? const <Trail>[];

  /// Den Modus öffnen; [start] aus „Route ab hier".
  void open({LatLng? start}) {
    // Schon offen und ohne neuen Start: Der getippte bleibt stehen.
    state = state.copyWith(open: true, pickingStart: false, pickingTarget: false, pickingWaypoint: false, clearDrawTool: true);
    if (start != null) takeStart(start);
  }

  /// Den Modus schließen, aufgeräumt (Konzept-Routing 10.5): Auswahl,
  /// Start, Ziel, Zwischenpunkte und Ergebnis gehen weg, gemerkt bleiben
  /// die Regler. Gibt zurück, was „Rückgängig" wiederholt — null, wenn
  /// nichts gesetzt war.
  LoopClosed? close() {
    final s = state;
    final kept = s.selected.isNotEmpty || s.waypoints.isNotEmpty || s.start != null || s.target != null
        ? LoopClosed._(
            // Eine laufende Rechnung kommt nicht zurück, nur ihre Eingaben.
            s.busy ? s.copyWith(phase: LoopPhase.idle) : s,
            _graphStart,
            _graphBox,
            _graphOnline,
            _planRequest,
            _vias)
        : null;
    ref.read(routeViaProvider.notifier).end(ViaOwner.loop);
    _generation++;
    _runner?.dispose();
    _runner = null;
    state = LoopSession(prefs: s.prefs, profile: s.profile, coverage: s.coverage);
    return kept;
  }

  /// „Rückgängig" nach [close]: Auswahl und Ergebnis kommen zurück, wie
  /// sie waren — die Karte öffnet das Blatt dazu wieder.
  void restore(LoopClosed closed, {bool? quick}) {
    _generation++;
    _graphStart = closed._graphStart;
    _graphBox = closed._graphBox;
    _graphOnline = closed._graphOnline;
    _planRequest = closed._planRequest;
    _vias = closed._vias;
    final s = closed.session;
    // Die Regler gelten, wie sie JETZT stehen — das Ergebnis ist mit den
    // alten gerechnet und bleibt trotzdem stehen, bis man neu rechnet.
    state = s.copyWith(
        open: true,
        pickingStart: false,
        pickingTarget: false,
        pickingWaypoint: false,
        clearDrawTool: true,
        prefs: state.prefs,
        profile: state.profile,
        quick: quick);
    final plan = s.plan;
    if (plan != null && plan.outcome == LoopOutcome.ok) ref.read(routeViaProvider.notifier).begin(ViaOwner.loop, _vias);
  }

  /// Jede Eingabe ändert sich hierüber (#356, D3): Das Ergebnis ist weg,
  /// eine Rechnung, die vorher losgelaufen ist, schreibt nichts mehr, und
  /// lag schon etwas im Blatt, sagt es „Auswahl geändert". Bis 0.127.4
  /// blieb die Phase „Ergebnis" ohne Plan stehen, und das Blatt meldete
  /// „Die Runde ließ sich nicht rechnen — ein Fehler, der gemeldet ist".
  void _edit(LoopSession next) {
    final shown = state.changed || state.phase != LoopPhase.idle;
    _generation++;
    if (state.plan != null) ref.read(routeViaProvider.notifier).end(ViaOwner.loop);
    state = next.copyWith(clearPlan: true, clearBlocker: true, phase: LoopPhase.idle, changed: shown, quick: false);
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
    _edit(state.copyWith(selected: selected, mandatory: mandatory));
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
    _edit(state.copyWith(selected: selected, mandatory: mandatory));
  }

  void clearSelection() => _edit(state.copyWith(selected: const {}, mandatory: const {}));

  void toggleMandatory(String id) {
    final mandatory = {...state.mandatory};
    final selected = {...state.selected};
    if (!mandatory.remove(id)) {
      mandatory.add(id);
      selected.add(id);
    }
    _edit(state.copyWith(selected: selected, mandatory: mandatory));
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

  void takeStart(LatLng p) => _edit(state.copyWith(start: p, pickingStart: false));

  void armTargetPick() =>
      state = state.copyWith(pickingTarget: true, pickingStart: false, pickingWaypoint: false, clearDrawTool: true);

  void armWaypointPick() =>
      state = state.copyWith(pickingWaypoint: true, pickingStart: false, pickingTarget: false, clearDrawTool: true);

  void takeWaypoint(LatLng p) => setWaypoints([...state.waypoints, p]);

  /// Die Zwischenpunkte ersetzen — Entfernen, Leeren, Rückgängig.
  void setWaypoints(List<LatLng> waypoints) =>
      _edit(state.copyWith(waypoints: waypoints, pickingWaypoint: false));

  void removeWaypoint(int k) {
    if (k < 0 || k >= state.waypoints.length) return;
    setWaypoints([...state.waypoints]..removeAt(k));
  }

  void takeTarget(LatLng p) => _edit(state.copyWith(target: p, clearTargetTrail: true, pickingTarget: false));

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
    if (asTarget) state = state.copyWith(targetTrailId: t.id);
    if (!asTarget && !t.pending && trailRoleOf(t) == TrailRole.downhill) setSelected([t.id], true);
  }

  /// Ein Einstieg mit fertigem Auftrag (#356 PR 7, Konzept-Routing 10.3):
  /// ein frischer Planer mit dem Ziel [target], Start am Standort — die
  /// Karte rechnet gleich danach. Ein laufender Auftrag wird ersetzt (mit
  /// Auswahl fragt die Karte vorher). [style] wie über das Ergebnis
  /// gemerkt; ohne bleibt der gemerkte.
  void beginRoute(LatLng target, {String? trailId, RouteMode? style}) {
    if (state.open) close();
    final prefs = state.prefs.copyWith(endMode: LoopEndMode.target, style: style);
    if (prefs.encode() != state.prefs.encode()) _remember(prefs);
    state = LoopSession(
        open: true,
        prefs: prefs,
        profile: state.profile,
        coverage: state.coverage,
        target: target,
        targetTrailId: trailId,
        quick: true);
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

  void useMyPosition() => _edit(state.copyWith(clearStart: true));

  void setPrefs(LoopPrefs prefs) {
    // Ohne den Modus „Zum Ziel" wartet auch kein Tipp mehr aufs Ziel.
    _edit(state.copyWith(
      prefs: prefs,
      pickingTarget: prefs.endMode == LoopEndMode.target ? null : false,
    ));
    _remember(prefs);
  }

  void _remember(LoopPrefs prefs) {
    ref.read(settingsProvider).setLoopPlannerPrefs(prefs.encode()).catchError((Object e, StackTrace s) {
      logError('Planer-Regler merken', e, s);
    });
  }

  void setProfile(RiderProfile next) {
    var prefs = state.prefs;
    // Steht das Höhenbudget auf der Vorgabe des alten Profils, folgt es dem
    // neuen — wer es selbst gestellt hat, behält es.
    if (prefs.climbM == state.profile.budgetClimbM) prefs = prefs.copyWith(climbM: next.budgetClimbM);
    _edit(state.copyWith(profile: next, prefs: prefs));
  }

  /// Der Stil im Ergebnis einer Route (#356, D3): gemerkt und sofort
  /// gerechnet — anders als die übrigen Eingaben.
  Future<void> setStyle(RouteMode style) {
    final quick = state.quick;
    if (style != state.prefs.style) setPrefs(state.prefs.copyWith(style: style));
    state = state.copyWith(quick: quick);
    return compute();
  }

  /// Das Rad im Ergebnis (D3): sofort gerechnet.
  Future<void> switchProfile(RiderProfile next) {
    final quick = state.quick;
    if (next != state.profile) setProfile(next);
    state = state.copyWith(quick: quick);
    return compute();
  }

  /// Das Ergebnis weglegen (Blatt zu); Modus und Auswahl bleiben.
  void clearResult() {
    ref.read(routeViaProvider.notifier).end(ViaOwner.loop);
    // Eine Rechnung, die noch läuft, gehört zu diesem Ergebnis.
    _generation++;
    state = state.copyWith(clearPlan: true, clearBlocker: true, phase: LoopPhase.idle, changed: false);
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
    final endMode = state.prefs.endMode;
    final target = endMode == LoopEndMode.target ? state.target : null;
    if (endMode == LoopEndMode.target && target == null) {
      state = state.copyWith(phase: LoopPhase.result, blocker: LoopBlocker.noTarget, clearPlan: true, changed: false);
      return;
    }
    // Ohne Trail gibt es nur zu einem Ziel etwas zu fahren: die Route (#356).
    final bare = chosen.isEmpty;
    if (bare && target == null) {
      state = state.copyWith(phase: LoopPhase.result, blocker: LoopBlocker.noTrails, clearPlan: true, changed: false);
      return;
    }
    final waypoints = state.waypoints;
    state = state.copyWith(
        clearPlan: true,
        clearBlocker: true,
        changed: false,
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
      // Die Trails, die eine spaßige Route mitnehmen darf, gleich in den
      // Rahmen — ein Wechsel des Stils lädt dann nicht neu.
      // Den Ziel-Trail fährt man danach, nicht auf dem Weg dorthin.
      final fun = bare ? funPoolOf(_trails, start, target!, exceptId: state.targetTrailId) : const <Trail>[];
      if (!_hasGraph ||
          _graphStart != start ||
          (target != null && !_graphBox!.contains(LatBox.of([target]))) ||
          (waypoints.isNotEmpty && !_graphBox!.contains(LatBox.of(waypoints))) ||
          !chosen.every((t) => _graphBox!.contains(LatBox.of(t.directedPoints))) ||
          !fun.every((t) => _graphBox!.contains(LatBox.of(t.directedPoints))) ||
          _graphOnline != fillOnline) {
        final s0 = start;
        // Die Anker: Start, Ziel, Zwischenpunkte, die gewählten Trails und
        // die des Umwegs. Die Uphill-Trails und Verbinder in ihrer Nähe
        // gehören in den Rahmen — sie sind der Weg bergauf (#185); die
        // weiter draußen (bis 0.131.0: alle im Radius) nur den Rahmen groß.
        final anchors = LatBox.of([
          s0,
          ?target,
          ...waypoints,
          for (final t in chosen) ...t.directedPoints,
          for (final t in fun) ...t.directedPoints,
        ]);
        final connectors = [
          for (final t in _trails)
            if (!t.pending && t.points.length >= 2 && trailRoleOf(t) != TrailRole.downhill && !t.status.warns)
              if (LatBox.of(t.points).near(anchors, kPlanConnectorMarginM)) t,
        ];
        final box = LatBox.of([
          s0,
          ?target,
          ...waypoints,
          for (final t in chosen) ...t.directedPoints,
          for (final t in fun) ...t.directedPoints,
          for (final t in connectors) ...t.points,
        ]);
        final built = await _loadGraph(box, start: s0, fillOnline: fillOnline, generation: generation);
        if (built != null || generation != _generation) return;
      }
      state = state.copyWith(phase: LoopPhase.computing);
      // Ein Bild für den Kreisel, bevor die Rechnung den Takt belegt.
      await WidgetsBinding.instance.endOfFrame;
      final runner = _runner ??= ref.read(loopPlanRunnerFactoryProvider)();
      final from = start;
      final LoopPlan plan;
      final LoopRequest request;
      var funEmpty = false;
      if (bare) {
        (plan, request, funEmpty) = await _planRoute(runner, from, target!, waypoints, fun);
      } else {
        // Direkt zu einem Ziel nimmt nur die Pflicht-Trails mit, auf
        // kürzestem Weg und ohne Budget (#356 PR 7b, Konzept-Routing 10.2);
        // die übrige Auswahl bleibt für Bequem und Spaßig.
        final direct = target != null && state.prefs.style == RouteMode.direct;
        request = LoopRequest(
          start: from,
          // Mit den gelernten Werten des Profils (Schritt 6), wo es welche
          // gibt; im Stil Bequem oder mit „Bergauf bequem" dessen Kosten.
          profile: ref.read(calibratedRiderProvider(state.profile)).withPrefs(state.prefs.planRoute),
          budget: direct ? kRouteDirectBudget : state.prefs.budget,
          pool: [
            for (final t in chosen)
              if (!direct || state.mandatory.contains(t.id))
                poolTrailOf(serviceL10n(), t, mandatory: state.mandatory.contains(t.id)),
          ],
          returnToStart: endMode == LoopEndMode.loop,
          end: target,
          waypoints: waypoints,
          bare: direct,
        );
        plan = await StallWatch.time('plan.loop', () => runner.plan(request, onProgress: _progressFor(generation)));
      }
      if (generation != _generation) return;
      _planRequest = request;
      state = state.copyWith(
          phase: LoopPhase.result,
          plan: plan,
          planStart: start,
          planEnd: endMode,
          planBare: bare,
          funEmpty: funEmpty);
      if (plan.outcome == LoopOutcome.ok) ref.read(routeViaProvider.notifier).begin(ViaOwner.loop);
    } catch (e, s) {
      // Geschlossen, während er rechnete: kein Fehler, nur zu spät.
      if (generation != _generation) return;
      logError('Runde planen', e, s);
      state = state.copyWith(phase: LoopPhase.result, blocker: LoopBlocker.failed);
    }
  }

  /// Sammelt die Eingabe für [box] und lässt den Runner bauen (#356 PR 8).
  /// Null, wenn der Graph steht — sonst der Grund, als Phase gesetzt
  /// (außer [quiet]) und zurückgegeben. Was nach einer Änderung der
  /// Generation ankommt, setzt nichts mehr.
  Future<LoopBlocker?> _loadGraph(LatBox box,
      {required LatLng start, required bool fillOnline, required int generation, bool quiet = false}) async {
    if (!quiet) state = state.copyWith(phase: LoopPhase.loading);
    final loaded = await ref.read(planningGraphLoaderProvider)(box, fillOnline: fillOnline);
    if (generation != _generation) return LoopBlocker.failed;
    LoopBlocker? fail(LoopBlocker b) {
      if (!quiet) state = state.copyWith(phase: LoopPhase.result, blocker: b, coverage: loaded.summary);
      return b;
    }

    if (loaded.tooLarge) return fail(LoopBlocker.tooLarge);
    final input = loaded.input;
    if (input == null) return fail(LoopBlocker.noArea);
    final runner = _runner ??= ref.read(loopPlanRunnerFactoryProvider)();
    if (!quiet) state = state.copyWith(phase: LoopPhase.building);
    try {
      await StallWatch.time(
          'graph.build', () => runner.build(input, onProgress: quiet ? null : _progressFor(generation)));
    } catch (e, s) {
      if (generation != _generation) return LoopBlocker.failed;
      // Wirft nie weiter: Ein halb belegter Graph plante Abfahrten
      // bergauf, also lieber keiner.
      logError('Graph für die Planung bauen', e, s);
      return fail(LoopBlocker.noArea);
    }
    if (generation != _generation) return LoopBlocker.failed;
    _graphStart = start;
    _graphBox = box;
    _graphOnline = fillOnline;
    if (!quiet) state = state.copyWith(coverage: loaded.summary);
    return null;
  }

  /// Schreibt den Fortschritt der laufenden Phase in den Zustand — nur,
  /// solange die Rechnung noch die von [generation] ist.
  void Function(double value) _progressFor(int generation) => (value) {
        if (generation == _generation && state.busy) state = state.copyWith(progress: value);
      };

  /// Die Route ohne gewählten Trail (#356, `route_result.dart`): Direkt
  /// und Bequem in einer Rechnung, Spaßig in zwei — passt kein Trail in
  /// den Umweg, bleibt es beim direkten Weg ([LoopSession.funEmpty]).
  Future<(LoopPlan, LoopRequest, bool)> _planRoute(
      LoopPlanRunner runner, LatLng from, LatLng to, List<LatLng> waypoints, List<Trail> fun) async {
    final prefs = state.prefs;
    final rider = ref.read(calibratedRiderProvider(state.profile)).withPrefs(prefs.planRoute);
    final direct = LoopRequest(
        start: from,
        profile: rider,
        budget: kRouteDirectBudget,
        pool: const [],
        returnToStart: false,
        end: to,
        waypoints: waypoints,
        bare: true);
    final plan = await StallWatch.time('route.direct', () => runner.plan(direct));
    if (prefs.style != RouteMode.fun || plan.outcome != LoopOutcome.ok) return (plan, direct, false);
    final s = plan.summary!;
    final funRequest = LoopRequest(
        start: from,
        profile: rider,
        budget: funBudgetOf(timeS: s.timeS, gainM: s.gainM, hikingM: s.hikingM, hikingKm: prefs.hikingKm),
        pool: [for (final t in fun) poolTrailOf(serviceL10n(), t)],
        returnToStart: false,
        end: to,
        waypoints: waypoints,
        bare: true);
    final funPlan =
        await StallWatch.time('route.fun', () => runner.plan(funRequest, onProgress: _progressFor(_generation)));
    if (funPlan.outcome == LoopOutcome.ok && !funPlan.isEmpty) return (funPlan, funRequest, false);
    return (plan, direct, true);
  }

  /// Die Runde mit fester Folge durch [vias] neu (#234). Das Ergebnis
  /// bleibt stehen, bis das neue da ist — ein Zug am Punkt soll die Linie
  /// umlegen, nicht das Blatt leeren. Geht es nicht, kommen die alten
  /// Punkte zurück.
  Future<void> _retune(RouteVias vias) async {
    final plan = state.plan;
    final request = _planRequest;
    final box = _graphBox;
    if (plan == null || plan.outcome != LoopOutcome.ok || request == null || box == null || state.busy) {
      ref.read(routeViaProvider.notifier).reject(_vias);
      return;
    }
    final generation = _generation;
    final seq = ++_tuneSeq;
    try {
      // Nach „Rückgängig" (10.5) ist der Runner neu und ohne Graphen: aus
      // denselben Bytes derselbe Graph, die Punkte sind Koordinaten.
      if (!_hasGraph) {
        final start = _graphStart;
        final blocked = start == null
            ? LoopBlocker.noArea
            : await _loadGraph(box, start: start, fillOnline: _graphOnline, generation: generation, quiet: true);
        if (generation != _generation || seq != _tuneSeq) return;
        if (blocked != null) {
          ref.read(routeViaProvider.notifier).reject(_vias);
          return;
        }
      }
      final next = await _runner!.plan(request.withTune(LoopTune.of(plan, vias)));
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
