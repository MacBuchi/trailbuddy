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
import '../rides/ride_providers.dart' show trailRideCountsProvider;
import '../rides/trail_ride_counts.dart';
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
import 'trail_head_route.dart' show kTrailHeadMarginM;
import 'trail_overlay.dart';

/// [loading] liest Kacheln (kurz), [building] baut den Graphen im
/// Rechen-Isolate (am Pixel ~0,33 s je Kachel, #356), [computing] rechnet.
enum LoopPhase { idle, locating, loading, building, computing, result }

enum LoopBlocker { noPosition, noTarget, noArea, noTrails, noTrailsInReach, failed, tooLarge }

/// So weit um Start, Ziel, Zwischenpunkte und gewählte Trails kommen
/// Uphill-Trails und Verbinder in den Rahmen des Graphen (#356 PR 8,
/// Konzept-Routing 10.6). Bis 0.131.0 zählten alle im Radius der Liste
/// (bis 30 km) — ein 60 × 60-km-Rahmen für eine Runde von 12 km.
const kPlanConnectorMarginM = 3000.0;

/// So weit darf der Start neben dem gebauten Rahmen liegen, ohne dass der
/// Graph neu gebaut wird (#370). Der Lader liest den Rahmen plus
/// [kTrailHeadMarginM] (500 m); die Hälfte davon lässt dem Start noch
/// Wege um sich. Bis 0.132.1 baute jeder neue Fix des Standorts neu —
/// er lag Meter neben dem alten, und am Pixel kostete das 12–44 s.
const kPlanStartSlackM = kTrailHeadMarginM / 2;

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
    this.entry = false,
    this.targetMine = false,
    this.suggestReachM,
  });

  /// Die gezeigte Planung ist ein Vorschlag (#516 Schritt 4,
  /// Konzept-Routing 12.4): der Pool aus diesem Umkreis um den Start,
  /// die Höhenmeter aus [LoopPrefs.suggestBudget]. Null für alles, was
  /// aus einer Auswahl gerechnet ist.
  final double? suggestReachM;

  /// Das Budget, mit dem die gezeigte Planung gerechnet ist — Skalen,
  /// „ca." und „Kürzer als …" im Blatt lesen es.
  LoopBudget get planBudget => suggestReachM != null ? prefs.suggestBudget : prefs.budget;

  /// Der Planer-Modus ist an: Leiste links, Tipps wählen Trails.
  final bool open;

  /// Das Einstiegsblatt steht (#516, Konzept-Routing 12.3): Der
  /// Planer-Knopf fragt erst nach der Absicht; Kopf, Leiste und
  /// Auswahlzeile der Bearbeitung kommen danach.
  final bool entry;

  /// Das Ziel ist der eigene Standort, beim Wählen genommen (der Weg
  /// zurück zu sich, Konzept-Routing 12.3) — der Kopf sagt dann „Mein
  /// Standort" statt „Auf der Karte gesetzt".
  final bool targetMine;

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
    bool? entry,
    bool? targetMine,
    double? suggestReachM,
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
        entry: entry ?? this.entry,
        targetMine: targetMine ?? this.targetMine,
        suggestReachM: clearPlan ? suggestReachM : (suggestReachM ?? this.suggestReachM),
      );
}

/// Was [LoopPlannerNotifier.close] weggeräumt hat — „Rückgängig" holt es
/// mit [LoopPlannerNotifier.restore] zurück (Konzept-Routing 10.5: eine
/// Meldung statt einer Rückfrage). Samt Rahmen des Graphen: Der Runner
/// ist mit dem Schließen weg, der nächste baut aus denselben Bytes
/// denselben Graphen.
class LoopClosed {
  const LoopClosed._(this.session, this._graphBox, this._graphOnline, this._planRequest, this._vias);

  final LoopSession session;
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

  /// Die Gewichte der laufenden Rechnung ([loopPreferenceWeight]), je
  /// Trail-Kennung; fehlt eine, wiegt der Trail 1.
  Map<String, double> _weights = const {};

  /// Die Vorliebe je Trail (Konzept-Routing 12.4): die EIGENE Bewertung und
  /// wie oft er in Fahrten auf dem Gerät vorkommt. Ohne Zähler (Web, ein
  /// Fehler) zählen nur die Sterne — nie ein Grund, nicht zu rechnen.
  Future<Map<String, double>> _preferenceWeights(List<Trail> trails) async {
    var counts = TrailRideCounts.empty;
    try {
      counts = await ref.read(trailRideCountsProvider.future);
    } catch (e, s) {
      logError('Planer: Fahrten je Trail lesen', e, s);
    }
    return {
      for (final t in trails)
        if (loopPreferenceWeight(ownRating: t.myDetails?.rating, rides: counts.of(t)) case final w when w != 1)
          t.id: w,
    };
  }

  /// Den Modus öffnen; [start] aus „Start hier". [entry] vom
  /// Planer-Knopf (#516): ein frischer Planer beginnt mit dem
  /// Einstiegsblatt — ein schon offener bleibt, wie er ist.
  void open({LatLng? start, bool entry = false}) {
    final fresh = !state.open;
    // Schon offen und ohne neuen Start: Der getippte bleibt stehen.
    state = state.copyWith(
        open: true,
        pickingStart: false,
        pickingTarget: false,
        pickingWaypoint: false,
        clearDrawTool: true,
        entry: entry && fresh && start == null ? true : null);
    if (start != null) takeStart(start);
  }

  /// „Runde" oder „Route" im Einstieg — gemerkt für das nächste Öffnen.
  void setIntent({required bool route}) {
    if (route == state.prefs.intentRoute) return;
    setPrefs(state.prefs.copyWith(intentRoute: route));
  }

  /// Das Einstiegsblatt verlassen, in die Bearbeitung oder zum Rechnen:
  /// Die Absicht wird zum Ende der Fahrt — „Route" heißt Ziel, „Runde"
  /// zurück zum Start (ein gemerktes „Ende am letzten Trail" bleibt, das
  /// stellt nur die Bearbeitung). Kam das Ziel von außen („Ziel hier",
  /// „Als Ziel" bei offenem Einstieg), bleibt es eine Route.
  void leaveEntry() {
    if (!state.entry) return;
    final endMode = state.prefs.endMode;
    final mode = state.prefs.intentRoute || (endMode == LoopEndMode.target && state.target != null)
        ? LoopEndMode.target
        : endMode == LoopEndMode.lastTrail
            ? LoopEndMode.lastTrail
            : LoopEndMode.loop;
    if (mode != state.prefs.endMode) setPrefs(state.prefs.copyWith(endMode: mode));
    state = state.copyWith(entry: false, pickingStart: false, pickingTarget: false, pickingWaypoint: false);
  }

  /// Im Einstieg „Route" gewählt, und alles liegt bereit: ein Ziel, und
  /// kein Start, der erst noch getippt werden muss (Ziel am Standort
  /// braucht einen Start auf der Karte). Dann rechnet die Karte gleich.
  bool get entryRouteReady {
    final s = state;
    return s.entry && s.prefs.intentRoute && s.target != null && !s.picking && !(s.targetMine && s.start == null);
  }

  /// Das Ziel am eigenen Standort ([p] ist der Fix) — der Start muss dann
  /// woanders liegen: Steht er auf dem Standort, wartet der Planer auf
  /// einen Tipp für ihn (Konzept-Routing 12.3).
  void takeTargetMine(LatLng p) {
    _edit(state.copyWith(target: p, clearTargetTrail: true, pickingTarget: false, targetMine: true));
    if (state.start == null) armStartPick();
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
        quick: quick,
        entry: false);
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
    // Ein Trail angetippt statt einer Antwort: Das ist „Selbst
    // zusammenstellen" (#516).
    leaveEntry();
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

  /// „Rückgängig" nach einem Tipp auf der Karte (#375): die Auswahl samt
  /// Sternen von vorher — ein abgewählter Pflicht-Trail kommt mit Stern
  /// zurück.
  void restoreSelection(Set<String> selected, Set<String> mandatory) =>
      _edit(state.copyWith(selected: {...selected}, mandatory: {...mandatory}));

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

  void takeTarget(LatLng p) =>
      _edit(state.copyWith(target: p, clearTargetTrail: true, pickingTarget: false, targetMine: false));

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
  /// gemerkt; ohne bleibt der gemerkte. Bei offenem Planer kommt es seit
  /// #516 nicht mehr hierher: Dort ist der Punkt das Ziel DIESER Planung
  /// (`takePlace`, `takeTrailHead`), also auch kein getippter Start, den
  /// ein Auftrag behalten müsste (#373).
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
    final quick = state.quick, reach = state.suggestReachM;
    if (style != state.prefs.style) setPrefs(state.prefs.copyWith(style: style));
    state = state.copyWith(quick: quick);
    return compute(suggestReachM: reach);
  }

  /// Das Rad im Ergebnis (D3): sofort gerechnet.
  Future<void> switchProfile(RiderProfile next) {
    final quick = state.quick, reach = state.suggestReachM;
    if (next != state.profile) setProfile(next);
    state = state.copyWith(quick: quick);
    // Ein Vorschlag bleibt ein Vorschlag: neu aus dem Umkreis, mit den
    // Höhenmetern des anderen Rads.
    return compute(suggestReachM: reach);
  }

  /// „Runde vorschlagen" im Einstieg (#516 Schritt 4, Konzept-Routing
  /// 12.4): der Pool aus dem Umkreis der Zeit.
  Future<void> suggest() => compute(suggestReachM: loopSuggestReachM(state.prefs.hours));

  /// „Weiter suchen" (Konzept-Routing 12.5): derselbe Vorschlag aus dem
  /// nächsten Umkreis. Ohne Vorschlag oder über dem letzten nichts.
  Future<void> suggestWider() async {
    final reach = state.suggestReachM;
    final next = reach == null ? null : loopSuggestNextReachM(reach);
    if (next != null) await compute(suggestReachM: next);
  }

  /// Der nächste Umkreis für „Weiter suchen", null ohne.
  double? get widerReachM {
    final reach = state.suggestReachM;
    return reach == null ? null : loopSuggestNextReachM(reach);
  }

  /// Das Ergebnis weglegen (Blatt zu); Modus und Auswahl bleiben.
  void clearResult() {
    ref.read(routeViaProvider.notifier).end(ViaOwner.loop);
    // Eine Rechnung, die noch läuft, gehört zu diesem Ergebnis.
    _generation++;
    state = state.copyWith(clearPlan: true, clearBlocker: true, phase: LoopPhase.idle, changed: false);
  }

  /// „Abbrechen" am Ladebalken (#372): Die laufende Arbeit endet, die
  /// Eingaben bleiben, und das Blatt sagt „Auswahl geändert" mit „Neu
  /// rechnen" (D3) — der Planer bleibt offen. Baut oder rechnet der
  /// Runner, geht er mit seinem Isolate weg (eine Suche lässt sich drüben
  /// nicht anhalten); seine wartenden Aufträge scheitern, die Generation
  /// verwirft sie, und die nächste Rechnung baut neu.
  void cancel() {
    if (!state.busy) return;
    _generation++;
    if (state.phase == LoopPhase.building || state.phase == LoopPhase.computing) {
      _runner?.dispose();
      _runner = null;
    }
    state = state.copyWith(phase: LoopPhase.idle, changed: true);
  }

  /// Der Mittelpunkt der Liste: getippter Start, sonst der Standort
  /// (`currentPositionProvider`). Null ohne beides.
  Future<LatLng?> listCenter() async {
    final s = state.start;
    if (s != null) return s;
    final fix = await ref.read(currentPositionProvider)();
    return fix == null ? null : LatLng(fix.latitude, fix.longitude);
  }

  /// Rechnen. Jeder Ausgang ist eine Phase oder ein Grund.
  ///
  /// Mit [suggestReachM] ist es der Vorschlag (#516 Schritt 4): Der Pool
  /// sind alle wählbaren Abfahrten mit beiden Enden in diesem Umkreis um
  /// den Start (`loopPoolOf`, wie „Alle wählen"), die Höhenmeter aus
  /// [LoopPrefs.suggestBudget]; danach sind die Trails des Vorschlags
  /// die Auswahl — „Bearbeiten" fängt dort an.
  Future<void> compute({double? suggestReachM}) async {
    if (state.busy) return;
    // Gerechnet wird in der Bearbeitung — auch, wenn der Einstieg gleich
    // rechnet (Route mit Ziel) oder ein Ziel von außen kam.
    leaveEntry();
    // Frei gerechnet: Die Punkte der alten Runde gelten nicht mehr.
    ref.read(routeViaProvider.notifier).end(ViaOwner.loop);
    _vias = RouteVias.none;
    final suggest = suggestReachM != null;
    var chosen = suggest
        ? const <Trail>[]
        : [
            for (final t in _trails)
              if (state.selected.contains(t.id) && !t.pending && t.points.length >= 2) t,
          ];
    // Ein Vorschlag ist eine Runde (oder endet am letzten Trail), nie eine
    // Route zu einem Ziel.
    final endMode =
        suggest && state.prefs.endMode == LoopEndMode.target ? LoopEndMode.loop : state.prefs.endMode;
    final target = endMode == LoopEndMode.target ? state.target : null;
    if (endMode == LoopEndMode.target && target == null) {
      state = state.copyWith(phase: LoopPhase.result, blocker: LoopBlocker.noTarget, clearPlan: true, changed: false);
      return;
    }
    // Ohne Trail gibt es zu einem Ziel die Route (#356), sonst durch die
    // Zwischenpunkte (#395): Runde zurück zum Start oder Ende am letzten
    // Punkt. Ohne beides ist nichts zu fahren.
    final waypoints = state.waypoints;
    final bare = !suggest && chosen.isEmpty && target != null;
    final pointsOnly = !suggest && chosen.isEmpty && target == null;
    if (pointsOnly && waypoints.isEmpty) {
      state = state.copyWith(phase: LoopPhase.result, blocker: LoopBlocker.noTrails, clearPlan: true, changed: false);
      return;
    }
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
        final fix = await ref.read(currentPositionProvider)();
        if (generation != _generation) return;
        if (fix == null) {
          state = state.copyWith(phase: LoopPhase.result, blocker: LoopBlocker.noPosition);
          return;
        }
        start = LatLng(fix.latitude, fix.longitude);
      }
      if (suggest) {
        chosen = loopPoolOf(_trails, start, reachM: suggestReachM).inReach;
        if (chosen.isEmpty) {
          state = state.copyWith(
              phase: LoopPhase.result, blocker: LoopBlocker.noTrailsInReach, suggestReachM: suggestReachM);
          return;
        }
      }
      final fillOnline = state.prefs.fillOnline;
      // Die Trails, die eine spaßige Route mitnehmen darf, gleich in den
      // Rahmen — ein Wechsel des Stils lädt dann nicht neu.
      // Den Ziel-Trail fährt man danach, nicht auf dem Weg dorthin.
      final fun = bare ? funPoolOf(_trails, start, target, exceptId: state.targetTrailId) : const <Trail>[];
      // Die Vorliebe (#516 Schritt 5): eigene Sterne und eigene Fahrten.
      _weights = await _preferenceWeights([...chosen, ...fun]);
      if (generation != _generation) return;
      // Der Start gehört nicht in den Schlüssel (#370): `planLoop` heftet
      // ihn bei jeder Rechnung an, und ein neuer Fix des Standorts liegt
      // Meter neben dem alten. Neu gebaut wird erst, wenn er den Rahmen
      // verlässt.
      if (!_hasGraph ||
          !_graphBox!.near(LatBox.of([start]), kPlanStartSlackM) ||
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
            if (!t.pending && t.points.length >= 2 && trailRoleOf(t) != TrailRole.downhill && !t.status.blocksRouting)
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
        final built = await _loadGraph(box, fillOnline: fillOnline, generation: generation);
        if (built != null || generation != _generation) return;
      }
      state = state.copyWith(phase: LoopPhase.computing);
      // Ein Bild für den Kreisel, bevor die Rechnung den Takt belegt.
      await WidgetsBinding.instance.endOfFrame;
      // Abgebrochen (#372), bevor die Rechnung losging.
      if (generation != _generation) return;
      final runner = _runner ??= ref.read(loopPlanRunnerFactoryProvider)();
      final from = start;
      final LoopPlan plan;
      final LoopRequest request;
      var funEmpty = false;
      if (bare) {
        (plan, request, funEmpty) = await _planRoute(runner, from, target, waypoints, fun);
      } else {
        // Direkt zu einem Ziel nimmt nur die Pflicht-Trails mit, auf
        // kürzestem Weg und ohne Budget (#356 PR 7b, Konzept-Routing 10.2);
        // die übrige Auswahl bleibt für Bequem und Spaßig.
        final direct = target != null && state.prefs.style == RouteMode.direct;
        // Nur Punkte: Der Planer wählt die Folge, ohne Budget — wie die
        // Route von A nach B.
        final free = direct || pointsOnly;
        request = LoopRequest(
          start: from,
          // Mit den gelernten Werten des Profils (Schritt 6), wo es welche
          // gibt; im Stil Bequem oder mit „Bergauf bequem" dessen Kosten.
          profile: ref.read(calibratedRiderProvider(state.profile)).withPrefs(state.prefs.planRoute),
          budget: free
              ? kRouteDirectBudget
              : suggest
                  ? state.prefs.suggestBudget
                  : state.prefs.budget,
          pool: [
            for (final t in chosen)
              if (!direct || state.mandatory.contains(t.id))
                poolTrailOf(serviceL10n(), t,
                    mandatory: state.mandatory.contains(t.id), weight: _weights[t.id] ?? 1),
          ],
          returnToStart: endMode == LoopEndMode.loop,
          end: target,
          waypoints: waypoints,
          bare: free,
        );
        plan = await StallWatch.time('plan.loop', () => runner.plan(request, onProgress: _progressFor(generation)));
      }
      if (generation != _generation) return;
      _planRequest = request;
      // Auf den Weg gesprungen (#374): Die Nadeln gehen mit, der Standort
      // nicht — der ist, wo man steht.
      LatLng? snapped(SnapRole role, [int k = 0]) =>
          plan.snaps.where((s) => s.role == role && s.index == k).firstOrNull?.at;
      state = state.copyWith(
          phase: LoopPhase.result,
          plan: plan,
          suggestReachM: suggestReachM,
          // Die Trails des Vorschlags sind die Auswahl, ohne „geändert".
          selected: suggest ? {for (final st in plan.stops) st.trail.id} : null,
          planStart: snapped(SnapRole.start) ?? start,
          planEnd: endMode,
          planBare: bare,
          funEmpty: funEmpty,
          start: state.start == null ? null : snapped(SnapRole.start),
          target: snapped(SnapRole.end),
          waypoints: plan.snaps.any((s) => s.role == SnapRole.waypoint)
              ? [for (var k = 0; k < waypoints.length; k++) snapped(SnapRole.waypoint, k) ?? waypoints[k]]
              : null);
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
      {required bool fillOnline, required int generation, bool quiet = false}) async {
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
      final report = await StallWatch.time(
          'graph.build', () => runner.build(input, onProgress: quiet ? null : _progressFor(generation)));
      // Die neu gebackenen Stücke in den Speicher (#380) — ohne darauf zu
      // warten: Gerechnet wird drüben, geschrieben hier.
      unawaited(loaded.keep(report));
    } catch (e, s) {
      if (generation != _generation) return LoopBlocker.failed;
      // Wirft nie weiter: Ein halb belegter Graph plante Abfahrten
      // bergauf, also lieber keiner.
      logError('Graph für die Planung bauen', e, s);
      return fail(LoopBlocker.noArea);
    }
    if (generation != _generation) return LoopBlocker.failed;
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
        pool: [for (final t in fun) poolTrailOf(serviceL10n(), t, weight: _weights[t.id] ?? 1)],
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
        final blocked = await _loadGraph(box, fillOnline: _graphOnline, generation: generation, quiet: true);
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
