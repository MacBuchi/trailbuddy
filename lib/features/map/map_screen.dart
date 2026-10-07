import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/connectivity.dart';
import '../../core/geo.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/safety_note.dart';
import '../../models/trail.dart';
import '../coach/coach.dart';
import '../feedback/feedback_dialog.dart';
import '../help/map_tour.dart';
import '../help/tab_tours.dart' show startWelcomeTour;
import '../highlights/highlight_sheet.dart' show maybeShowHighlights;
import '../rides/ride_providers.dart';
import '../rides/ride_split_sheet.dart';
import '../rides/ride_task_handler.dart';
import '../rides/ride_track.dart';
import '../routing/loop_planner_controller.dart';
import '../routing/loop_planner_providers.dart';
import '../routing/loop_planner_sheet.dart';
import '../routing/loop_tool_rail.dart';
import '../routing/map_panel.dart';
import '../routing/trail_head_providers.dart';
import '../routing/trail_head_sheet.dart';
import '../trails/trail_navigation.dart' show formatCoordinates, navigateToPoint;
import '../official/official_trails.dart';
import '../official/official_trails_layer.dart';
import '../official/official_trails_source.dart';
import '../offline_areas/area_draw.dart';
import '../offline_areas/area_draw_overlay.dart';
import '../offline_areas/area_overlay.dart';
import '../offline_areas/area_plan.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../offline_areas/offline_tool_rail.dart';
import '../trails/grade_shield.dart' show trailColorOf, trailLineStyleOf;
import '../trails/outbox_providers.dart';
import '../trails/trail_list.dart';
import '../trails/trail_providers.dart';
import '../trails/trail_sheet.dart';
import '../update/update_banner.dart';
import 'map_buttons.dart';
import 'map_legend.dart';
import 'map_view/map_view.dart';
import 'poi.dart';
import 'line_smoothing.dart';
import 'poi_layer.dart';
import 'trail_badges.dart';
import 'trail_quick_card.dart';
import 'position_provider.dart';
import 'poi_source.dart';

/// Die Karte: hinter der Fassade `map_view/` (MapLibre auf Android,
/// flutter_map im Web), darüber die Trails des eigenen Netzes als Linien.
/// Eigene grün, nur von Buddys belegte blau, gesperrte oder zerstörte in
/// Warnfarbe — die Farbe sagt, was ICH damit zu tun habe, nicht, wie gut
/// der Trail ist. Ein gelber Rand heißt: Ein Buddy hat in den letzten
/// Tagen einen Hinweis dazu geschrieben (#7). Auf Wunsch Orte aus
/// OpenStreetMap als Stecknadeln (#12); gestrichelt die offiziellen
/// Trails (#13), eine eigene Ebene aus Behördendaten. Und die eigene
/// Fahrt (#28): die laufende Spur, unter den Trails.
///
/// **Was ein Tipp trifft, entscheidet die Fassade**, nicht die
/// Zeichenreihenfolge: Linien zuerst (das Netz liegt über den
/// offiziellen Trails), dann die Nadeln. Die Fahrt und die eigene
/// Position sind Kulisse und melden nichts.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _dachCenter = LatLng(48.8, 10.5);
  static const _initialZoom = 6.0;

  final _controller =
      MapViewController(initialCenter: _dachCenter, initialZoom: _initialZoom);
  bool _fittedOnce = false;

  /// Das Scaffold der Karte: Die Routen-Blätter hängen sich als Persistent
  /// Bottom Sheet daran (`map_panel.dart`) — die Karte darüber bleibt
  /// bedienbar.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Der ausgewählte Trail (#178): leuchtet, unten steht seine
  /// Schnellkarte. Null: keiner.
  String? _selectedTrailId;

  /// Wo der lange Druck lag (#177), solange sein Menü offen ist.
  LatLng? _pressedPoint;

  /// Ein Fokus-Wunsch (`mapFocusTrailProvider`) auf einen Trail, der
  /// noch nicht in der Liste ist — etwa aus einer Push-Benachrichtigung
  /// beim Kaltstart, bevor die Trails geladen sind. Eingelöst, sobald er
  /// kommt; ein Wunsch auf einen Trail, den man nie sieht, verfällt.
  String? _pendingFocus;

  /// Die Kamera beim letzten Stillstand — daran hängen Orte und
  /// offizielle Trails (welche Zellen, welcher Ausschnitt).
  MapViewCamera? _camera;

  Timer? _loadDebounce;
  String? _requestedPois;
  String? _requestedOfficial;

  /// Die Szenen der Karten-Tour (#132) — abgemeldet in [dispose].
  final _coachScenes = <VoidCallback>[];

  /// Der Trail, dessen Schild und Blatt die Tour zeigt: der erste
  /// gezeichnete mit Schild, sonst der erste gezeichnete. Gesetzt bei
  /// jedem Aufbau, gelesen von der Szene [MapCoach.trailSheet].
  Trail? _coachTrail;

  /// Nachladen kurz verzögert, damit ein Wischen über die Karte nicht
  /// zehn Abfragen auslöst.
  static const _loadDelay = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    // Eine Fahrt, die der Prozess-Kill unterbrochen hat, läuft weiter
    // (#28): Der Service hat derweil in die Datei geschrieben.
    unawaited(ref.read(rideProvider.notifier).restore());
    // Was im Ausgangskorb liegt, geht beim Start raus (#30).
    unawaited(ref.read(trailsProvider.notifier).sendOutbox());
    // Die Rückrichtung vom Service-Isolate: jeder Messpunkt kommt auf
    // die Karte, solange die App lebt. Der Port dafür entsteht in
    // `main()` (`initRideCommunication`).
    FlutterForegroundTask.addTaskDataCallback(_onRideTick);
    _registerCoachScenes();
    // Ein Fokus-Wunsch, der VOR dem Aufbau gestellt wurde (Route
    // `/trail/<id>` aus einer Push): `ref.listen` sieht nur Änderungen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _takeFocusWish();
      unawaited(_firstStart());
    });
  }

  /// Was beim ersten Start über der Karte liegt: erst der
  /// Sicherheitshinweis (#131), dann — IM SELBEN Start — die
  /// Willkommensseite mit der Karten-Tour (#133). PilzBuddy legt einen
  /// Start dazwischen; der Betreiber will „Hinweis vor der ersten Tour",
  /// nicht „einen Start dazwischen" (Plan 3.3). Hier und nicht in der
  /// App-Hülle, weil die Karte nur angemeldet gebaut wird und hinter
  /// einer Update-Sperre gar nicht.
  ///
  /// Gemerkt wird der Hinweis VOR dem Zeigen: Der Dialog ist nicht
  /// wegtippbar, der einzige Ausgang ist „Verstanden"; stirbt die App mit
  /// offenem Dialog, kommt er nicht bei jedem Start wieder. Die Tour
  /// dagegen erst an ihrem Ende — „Nicht jetzt" ist kein Gesehen.
  Future<void> _firstStart() async {
    var shownNote = false;
    if (!ref.read(safetyNoteSeenProvider)) {
      shownNote = true;
      ref.read(safetyNoteSeenProvider.notifier).set(true);
      await showSafetyNoteDialog(context);
      if (!mounted) return;
    }
    // Läuft schon etwas (aus der Kurzanleitung gestartet), nicht
    // dazwischenfahren.
    var overlayShown = shownNote;
    if (!ref.read(mapTourSeenProvider) && !ref.read(coachProvider.notifier).busy) {
      startWelcomeTour(ref, GoRouter.of(context));
      overlayShown = true;
    }
    // Die Neuheiten (#135): gerechnet wird immer — eine frische Installation
    // merkt ihre Version schon jetzt —, gezeigt nur in einem ruhigen Start.
    await maybeShowHighlights(context, ref, mayShow: !overlayShown);
  }

  /// Die Szenen der Karten-Tour (#132): Das Skript sagt WAS geöffnet
  /// wird, hier steht WIE — und wie es wieder zugeht. Direkt geöffnet,
  /// nicht über [_closeTools], das bei einem Entwurf nachfragte; die Tour
  /// beginnt ihn leer und verwirft ihn wieder.
  void _registerCoachScenes() {
    final coach = ref.read(coachRegistryProvider);
    Future<VoidCallback> sheet(Future<void> Function() show) async {
      final navigator = Navigator.of(context);
      var open = true;
      unawaited(show().whenComplete(() => open = false));
      return () {
        if (open) navigator.pop();
      };
    }

    _coachScenes
      ..add(coach.registerScene(MapCoach.rail, () async {
        final wasOpen = ref.read(offlineOverlayProvider);
        if (!wasOpen) _openTools();
        return () {
          if (wasOpen || !mounted) return;
          ref.read(areaDraftProvider.notifier).discard();
          ref.read(offlineOverlayProvider.notifier).state = false;
        };
      }))
      ..add(coach.registerScene(MapCoach.layersSheet, () => sheet(() => showMapLayersSheet(context))))
      // Die Legende (#182): aufklappen, und zu, wenn sie zu war.
      ..add(coach.registerScene(MapCoach.legend, () async {
        final legend = ref.read(mapLegendOpenProvider.notifier);
        final wasOpen = ref.read(mapLegendOpenProvider);
        if (!wasOpen) legend.set(true);
        return () {
          if (!wasOpen && mounted) legend.set(false);
        };
      }))
      // Der Planer ist seit 0.74.0 ein Modus mit Leiste: Die Szene öffnet
      // ihn und schließt ihn wieder, wenn sie ihn geöffnet hat.
      ..add(coach.registerScene(MapCoach.loopRail, () async {
        final wasOpen = ref.read(loopPlannerProvider).open;
        if (!wasOpen) await _openLoopPlanner();
        return () {
          if (!wasOpen && mounted) ref.read(loopPlannerProvider.notifier).close();
        };
      }))
      ..add(coach.registerScene(MapCoach.trailSheet, () async {
        final trail = _coachTrail;
        // Ohne Trail nichts zu öffnen — der Schritt fällt über `unless`
        // ohnehin weg; ein leerer Schließer hält die Kette trotzdem.
        if (trail == null) return () {};
        return sheet(() => showTrailSheet(context, ref.read(trailByIdProvider(trail.id)) ?? trail));
      }));
  }

  void _takeFocusWish() {
    final id = ref.read(mapFocusTrailProvider);
    if (id == null) return;
    ref.read(mapFocusTrailProvider.notifier).state = null;
    if (!_focusOn(id)) _pendingFocus = id;
  }

  /// Die Werkzeugleiste „Offline-Karten" öffnen (seit 0.27.0): abdunkeln, was
  /// nicht gespeichert ist, und einen leeren Entwurf beginnen.
  void _openTools() {
    ref.read(areaDraftProvider.notifier).start();
    ref.read(offlineOverlayProvider.notifier).state = true;
  }

  /// Schließen — über X, Knopf „Offline-Karten" oder Zurück. Steht etwas im
  /// Entwurf, wird gefragt; „Weiter bearbeiten" lässt alles offen.
  Future<void> _closeTools() async {
    final draft = ref.read(areaDraftProvider.notifier);
    if (draft.hasChanges && !await confirmDiscardDraft(context)) return;
    if (!mounted) return;
    draft.discard();
    ref.read(offlineOverlayProvider.notifier).state = false;
  }

  /// Der „Schnappschuss": die Kacheln des Ausschnitts in den Entwurf.
  void _addViewport() {
    final camera = _camera;
    if (camera == null) return;
    final b = camera.bounds;
    final keys = tilesInBounds(AreaBounds(south: b.south, west: b.west, north: b.north, east: b.east));
    if (keys == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Der Ausschnitt ist zu groß — erst näher heranzoomen.')));
      return;
    }
    ref.read(areaDraftProvider.notifier).addAll(keys);
  }

  /// Die Kacheln entlang der eigenen Trails in den Entwurf.
  void _addTrails() {
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    final along = AreaShape.alongLines([for (final t in trails) t.points]);
    if (along != null) ref.read(areaDraftProvider.notifier).addAll(along.keys);
  }

  /// Speichern: der Dialog misst, fragt und führt aus; danach ist der
  /// Entwurf leer, die Leiste bleibt offen und zeigt den neuen Bestand.
  Future<void> _saveDraft(AreaDraft draft) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showSaveDraftDialog(context, draft);
    if (!saved || !mounted) return;
    ref.read(areaDraftProvider.notifier).clear();
    final area = draft.adds.isEmpty ? null : ref.read(areaDownloadProvider).result;
    messenger.showSnackBar(SnackBar(
        content: Text(area == null
            ? 'Änderungen gespeichert.'
            : '„${area.name}" gespeichert: ${formatBytes(area.bytes)}.')));
  }

  /// Ein fertiger Strich (Stufe C): seine Kacheln in den Entwurf — oder,
  /// wenn er zu groß war, ein Satz statt einer Rechnung, die hängt.
  void _onStroke(Set<int>? keys) {
    final draft = ref.read(areaDraftProvider.notifier);
    if (keys == null) {
      draft.disarm();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Zu groß gezeichnet — erst näher heranzoomen.')));
      return;
    }
    draft.applyStroke(keys);
  }

  /// Auf den Trail zoomen, wenn er da ist. `false`, wenn nicht.
  ///
  /// Direkt aus der Liste, nicht über `trailByIdProvider`: Im Listener
  /// von `trailsProvider` ist die Familie noch nicht nachgezogen und
  /// antwortete mit dem alten Stand (gemessen: null, obwohl die Liste
  /// den Trail trug).
  bool _focusOn(String id) {
    final t = ref.read(trailsProvider).valueOrNull?.where((x) => x.id == id).firstOrNull;
    if (t == null) return false;
    // Blendet der Filter (#66) genau diesen Trail aus, fällt er — sonst
    // führte eine Push-Meldung auf eine leere Stelle. Und die App sagt es.
    final filter = ref.read(trailListFilterProvider);
    if (!passesTrailFilter(t, filter,
        seenNotes: ref.read(seenNotesProvider), snoozed: ref.read(stillValidSnoozesProvider))) {
      ref.read(trailListFilterProvider.notifier).state = const TrailListFilter();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          key: ValueKey('filter-reset-for-focus'),
          content: Text('Filter zurückgesetzt, damit der Trail zu sehen ist.')));
    }
    _fittedOnce = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitTo([t]);
    });
    return true;
  }

  void _onRideTick(Object data) {
    final point = decodeRideTick(data);
    if (point == null) return;
    ref.read(rideProvider.notifier).acceptTick(point);
    unawaited(ref.read(rideProvider.notifier).stopIfExpired());
  }

  @override
  void dispose() {
    for (final unregister in _coachScenes) {
      unregister();
    }
    FlutterForegroundTask.removeTaskDataCallback(_onRideTick);
    _loadDebounce?.cancel();
    super.dispose();
  }

  /// Geglättete Punkte je Trail, einmal gerechnet: Die Karte baut bei
  /// jeder Kamerabewegung neu, die Trails ändern sich nur mit dem Laden.
  static final _smoothCache = Expando<List<LatLng>>('smoothed');
  // An der PUNKTLISTE, nicht am Trail: Ein Trail-Objekt entsteht neu,
  // sobald sich ein Stern ändert, seine Linie nicht. Dieselbe geglättete
  // Liste heißt für MapLibre „nichts zu übertragen" (`MapLibreLineCache`).
  List<LatLng> _smoothed(Trail t) => _smoothCache[t.points] ??= chaikinSmooth(t.points);

  /// Die Linie trägt die Schwierigkeit (seit 0.42.0), nicht mehr die
  /// Beziehung; eine Meldung liegt als Leuchtrand darum ([_borderOf]).
  Color _colorOf(Trail t) => trailColorOf(t, AppColors.mapGrades);

  /// Der Rand um die Linie sagt den Zustand: gemeldet orange (die
  /// Warnung schlägt den Hinweis — meist kommt beides zusammen, und die
  /// Liste nennt beide Wörter), neuer Hinweis eines Buddys gelb, sonst
  /// der weiße Saum.
  (Color, double) _borderOf(Trail t, Set<String> seenNotes) {
    const c = AppColors.mapLines;
    if (t.status.warns) return (c.warning, 4);
    if (t.hasFreshNote(seen: seenNotes)) return (c.note, 4);
    return (c.halo!, c.haloBorderWidth);
  }

  void _onCameraIdle(MapViewCamera camera) {
    if (!mounted) return;
    setState(() => _camera = camera);
  }

  /// Orte und offizielle Trails für den Ausschnitt nachladen — je
  /// Ausschnitt EIN Versuch: Ohne Netz änderte sonst jede Antwort den
  /// Zustand, der Neuaufbau fragte wieder — alle halbe Sekunde.
  void _scheduleLoads({
    required List<PoiCell>? cells,
    required Set<PoiGroup> groups,
    required ({double s, double w, double n, double e})? officialView,
  }) {
    final poiKey = cells == null
        ? null
        : '${cells.join(';')}|${groups.map((g) => g.name).join(',')}';
    final officialKey = officialView == null
        ? null
        : '${officialView.s},${officialView.w},${officialView.n},${officialView.e}';
    final poisDue = poiKey != null && poiKey != _requestedPois;
    final officialDue = officialKey != null && officialKey != _requestedOfficial;
    if (poiKey == null) _requestedPois = null;
    if (officialKey == null) _requestedOfficial = null;
    if (!poisDue && !officialDue) return;
    if (poisDue) _requestedPois = poiKey;
    if (officialDue) _requestedOfficial = officialKey;
    _loadDebounce?.cancel();
    _loadDebounce = Timer(_loadDelay, () {
      if (!mounted) return;
      if (poisDue) {
        unawaited(ref.read(poiControllerProvider.notifier).ensure(cells!, groups));
      }
      if (officialDue) {
        unawaited(ref.read(officialTrailsControllerProvider.notifier).ensure(officialView!));
      }
    });
  }

  /// Ein Tipp ins Leere: Wartet der Planer auf seinen Start, ist der Tipp
  /// der Start; sonst hebt er die Auswahl eines Trails auf (#178).
  void _onMapTap(MapTap tap) {
    if (_takeLoopStart(tap)) return;
    if (_selectedTrailId != null) setState(() => _selectedTrailId = null);
  }

  bool _takeLoopStart(MapTap tap) {
    final session = ref.read(loopPlannerProvider);
    if (!session.open || !session.pickingStart) return false;
    ref.read(loopPlannerProvider.notifier).takeStart(tap.point);
    return true;
  }

  /// Der Planer als Modus (seit 0.74.0): Leiste links, Tipps wählen
  /// Trails. Die Leiste „Offline-Karten" geht dafür zu — zwei Leisten links passen
  /// nicht nebeneinander.
  Future<void> _openLoopPlanner({LatLng? start}) async {
    if (ref.read(offlineOverlayProvider)) {
      await _closeTools();
      if (!mounted || ref.read(offlineOverlayProvider)) return;
    }
    setState(() => _selectedTrailId = null);
    ref.read(loopPlannerProvider.notifier).open(start: start);
  }

  /// Schließen: Ergebnis-Blatt zu, Modus aus — die Auswahl bleibt für die
  /// Sitzung.
  void _closeLoopPlanner() {
    if (_loopPanelOpen) closeMapPanel();
    ref.read(loopPlannerProvider.notifier).close();
  }

  Future<void> _computeLoop() async {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold == null) return;
    if (_loopPanelOpen) {
      unawaited(ref.read(loopPlannerProvider.notifier).compute());
      return;
    }
    _loopPanelOpen = true;
    await showLoopResultPanel(scaffold);
    _loopPanelOpen = false;
  }

  bool _loopPanelOpen = false;

  void _onHit(Object hit, MapTap tap) {
    // Auch ein Tipp auf eine Linie ist ein Punkt, solange der Planer
    // seinen Start sucht — ein Trailkopf ist ein guter Start.
    if (_takeLoopStart(tap)) return;
    switch (hit) {
      case final Trail t:
        // Im Planer wählt ein Tipp den Trail an oder ab (#178).
        if (ref.read(loopPlannerProvider).open) {
          final result = ref.read(loopPlannerProvider.notifier).toggle(t);
          if (result == LoopToggle.connector || result == LoopToggle.pending) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(SnackBar(
                  key: const ValueKey('loop-not-pickable'),
                  content: Text(result == LoopToggle.connector
                      ? '„${t.displayName}" ist ein Uphill-Trail oder Verbinder — die Runde nutzt ihn von selbst bergauf.'
                      : '„${t.displayName}" wartet noch auf Übertragung.')));
          }
          return;
        }
        // Sonst: auswählen — er leuchtet, unten die Schnellkarte; ein
        // zweiter Tipp auf DENSELBEN Trail öffnet gleich das Blatt.
        if (_selectedTrailId == t.id) {
          _openSelected();
        } else {
          setState(() => _selectedTrailId = t.id);
        }
      case final OfficialTrail o:
        showOfficialTrailSheet(context, o);
      case final Poi p:
        showPoiSheet(context, p);
    }
  }

  /// „Meine Position": die einzige Stelle, die nach der Berechtigung
  /// fragt (`positionFixProvider`). Danach läuft der Punkt mit.
  Future<void> _locateMe() async {
    final messenger = ScaffoldMessenger.of(context);
    final fix = await ref.read(positionFixProvider)();
    if (!mounted) return;
    if (fix == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Position nicht verfügbar — Standort ist aus '
              'oder für TrailBuddy nicht erlaubt.')));
      return;
    }
    _fittedOnce = true;
    final zoom = _controller.zoom;
    _controller.move(LatLng(fix.latitude, fix.longitude), zoom < 14 ? 15 : zoom);
    ref.invalidate(positionStreamProvider);
  }

  void _fitTo(List<Trail> trails) => _fitPoints([for (final t in trails) ...t.points]);

  /// Einpassen — in die Fläche ÜBER einem offenen Routen-Blatt
  /// (`mapPanelInsetProvider`), sonst läge, was gezeigt werden soll,
  /// darunter (Feldbericht 0.73.0).
  ///
  /// Höchstens 55 % der Höhe gelten als verdeckt: Ist das Blatt ganz
  /// aufgezogen, passt die Karte lieber hinter den Rand ein als in einen
  /// Streifen, der die Runde auf Länderzoom zeigt.
  void _fitPoints(List<LatLng> pts) {
    final inset = ref.read(mapPanelInsetProvider);
    final cap = MediaQuery.sizeOf(context).height * 0.55;
    _controller.fit(pts, padding: 40, maxZoom: 15, bottomInset: inset < cap ? inset : cap);
  }

  /// Fahrt aufzeichnen oder beenden (#28). Beim Beenden ist die Fahrt
  /// gespeichert, BEVOR das Blatt aufgeht — wer es wegwischt, behält.
  Future<void> _toggleRide() async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(rideProvider.notifier);
    if (!notifier.isRunning) {
      final result = await notifier.start();
      if (!mounted) return;
      final text = switch (result) {
        RideStartResult.started =>
          'Fahrt läuft — der Weg wird aufgezeichnet, auch wenn das Telefon '
              'in der Tasche steckt.',
        RideStartResult.noPermission =>
          'Ohne Standortberechtigung lässt sich keine Fahrt aufzeichnen.',
        RideStartResult.noService => 'Der Standortdienst ist ausgeschaltet.',
        RideStartResult.failed => 'Die Fahrt ließ sich nicht starten.',
      };
      messenger.showSnackBar(SnackBar(content: Text(text)));
      return;
    }
    final ride = await notifier.stop();
    if (!mounted) return;
    if (ride == null) return;
    if (ride.points.length < 2) {
      // Nichts gemessen: nichts zu behalten, und ein leeres Blatt wäre
      // eine Frage ohne Gegenstand.
      await ref.read(ridesProvider.notifier).delete(ride.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Fahrt beendet — es kam kein Standort zustande, '
              'nichts gespeichert.')));
      return;
    }
    _fittedOnce = true;
    _fitPoints([for (final p in ride.points) LatLng(p.lat, p.lng)]);
    final discard = await showRideSplitSheet(context, SplitRequest.fromRide(ride), offerDiscard: true);
    if (!mounted || !discard) return;
    await ref.read(ridesProvider.notifier).delete(ride.id);
  }

  /// „Trail beginnt" / „Trail endet" (#105): eine Marke in der laufenden
  /// Fahrt. Die Leiste sagt, was gesetzt wurde — mit Handschuh auf dem
  /// Trail sieht man den Rand am Knopf nicht immer.
  Future<void> _toggleMark() async {
    final messenger = ScaffoldMessenger.of(context);
    final mark = await ref.read(rideProvider.notifier).toggleMark();
    if (!mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text(switch (mark?.kind) {
        RideMarkKind.start => 'Trail beginnt — markiert. Am Ende noch einmal tippen.',
        RideMarkKind.end => 'Trail endet — markiert. Das Stück steht nach der Fahrt im Zerlege-Blatt.',
        null => 'Die Marke ließ sich nicht speichern.',
      })));
  }

  /// Das große Blatt des ausgewählten Trails (#178: der zweite Schritt).
  void _openSelected() {
    final id = _selectedTrailId;
    if (id == null) return;
    final trail = ref.read(trailByIdProvider(id));
    if (trail == null) return;
    unawaited(showTrailSheet(context, trail));
  }

  /// „Zum Trailkopf" (#158 Schritt 4) und das Navi-Symbol (#176): das
  /// Blatt über der Karte; der Trail kommt frisch aus der Liste, der Wunsch
  /// trägt nur die Kennung.
  void _openTrailHead(TrailHeadRequest request) {
    final trail = ref.read(trailByIdProvider(request.trailId));
    final scaffold = _scaffoldKey.currentState;
    if (trail == null || scaffold == null) return;
    setState(() => _selectedTrailId = null);
    unawaited(showTrailHeadSheet(scaffold, trail, mode: request.mode));
  }

  /// Langer Druck (#177): eine Nadel am Punkt und ein kleines Menü —
  /// Route ab hier (der Planer mit diesem Start), Route bis hier (der Weg
  /// vom Standort), oder die Navi-App.
  Future<void> _onLongPress(MapTap tap) async {
    if (_takeLoopStart(tap)) return;
    final box = context.findRenderObject() as RenderBox?;
    final at = box?.localToGlobal(tap.screenPoint) ?? tap.screenPoint;
    setState(() {
      _pressedPoint = tap.point;
      _selectedTrailId = null;
    });
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(
          key: ValueKey('map-menu-from'),
          value: 'from',
          child: ListTile(leading: Icon(Icons.trip_origin), title: Text('Route ab hier')),
        ),
        PopupMenuItem(
          key: ValueKey('map-menu-to'),
          value: 'to',
          child: ListTile(leading: Icon(Icons.place_outlined), title: Text('Route bis hier')),
        ),
        PopupMenuItem(
          key: ValueKey('map-menu-external'),
          value: 'external',
          child: ListTile(leading: Icon(Icons.directions_outlined), title: Text('Mit der Navi-App hierher')),
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _pressedPoint = null);
    final scaffold = _scaffoldKey.currentState;
    switch (choice) {
      case 'from':
        await _openLoopPlanner(start: tap.point);
      case 'to':
        if (scaffold == null) return;
        await showRouteSheet(scaffold,
            RouteTarget(point: tap.point, title: formatCoordinates(tap.point.latitude, tap.point.longitude)));
      case 'external':
        await navigateToPoint(context, tap.point);
    }
  }

  /// „Fahrt zerlegen" aus „Meine Fahrten" oder dem GPX-Import (#29):
  /// die Spur einpassen, das Blatt öffnen.
  void _openSplit(SplitRequest request) {
    _fittedOnce = true;
    _fitPoints([for (final p in request.track.points) LatLng(p.lat, p.lon)]);
    unawaited(showRideSplitSheet(context, request));
  }

  @override
  Widget build(BuildContext context) {
    final trailsAsync = ref.watch(trailsProvider);
    final trails = trailsAsync.valueOrNull ?? const <Trail>[];
    final seenNotes = ref.watch(seenNotesProvider);
    final snoozed = ref.watch(stillValidSnoozesProvider);
    // Derselbe Filter wie in der Liste (#66, seit 0.33.0). Er wirkt NUR
    // auf das, was gezeichnet und getroffen wird — „Entlang meiner
    // Trails", Einpassen und Fokus rechnen weiter mit allen.
    final trailFilter = ref.watch(trailListFilterProvider);
    final shownTrails = trailFilter.isActive
        ? [
            for (final t in trails)
              if (passesTrailFilter(t, trailFilter, seenNotes: seenNotes, snoozed: snoozed)) t
          ]
        : trails;
    _coachTrail = shownTrails.where(hasTrailBadge).firstOrNull ?? shownTrails.firstOrNull;
    final groups = ref.watch(poiGroupsProvider);
    final hidden = ref.watch(poiHiddenKindsProvider);
    final poiState = ref.watch(poiControllerProvider);
    final poiUnavailable = groups.isNotEmpty && poiState.unavailable;
    final officialOn = ref.watch(officialTrailsEnabledProvider);
    final position = ref.watch(positionStreamProvider).valueOrNull;
    final official = ref.watch(officialTrailsControllerProvider);
    final ride = ref.watch(rideProvider);
    final focusRide = ref.watch(mapFocusRideProvider);
    final splitPreview = ref.watch(rideSplitPreviewProvider);
    final trailHeadPreview = ref.watch(trailHeadPreviewProvider);
    final loop = ref.watch(loopPlannerProvider);
    final loopPicking = loop.open && loop.pickingStart;
    final loopPlan = loop.open ? loop.plan : null;
    final panelInset = ref.watch(mapPanelInsetProvider);
    // Der ausgewählte Trail (#178) — weg, wenn er nicht mehr gezeigt wird
    // (Filter, gelöscht).
    final selected = _selectedTrailId == null
        ? null
        : trails.where((t) => t.id == _selectedTrailId).firstOrNull;
    final canRecord = ref.watch(rideRecordingAvailableProvider);
    final cachedAt = ref.watch(trailsCachedAtProvider);

    // Einmal auf das Netz zoomen, sobald es da ist; danach nie wieder
    // von selbst — wer die Karte verschoben hat, will nicht zurückgeholt
    // werden.
    ref.listen(trailsProvider, (_, next) {
      final list = next.valueOrNull;
      // Während einer Fahrt fragt der Dienst zu unbestätigten Meldungen
      // (#116); seine Liste folgt dem, was die App gerade sieht.
      if (list != null) unawaited(ref.read(rideProvider.notifier).syncConfirmTargets());
      // Ein wartender Fokus-Wunsch geht vor dem Einpassen auf das Netz.
      final pending = _pendingFocus;
      if (pending != null && list != null && _focusOn(pending)) {
        _pendingFocus = null;
      }
      if (!_fittedOnce && list != null && list.isNotEmpty) {
        _fittedOnce = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitTo(list);
        });
      }
    });
    ref.listen(mapFocusTrailProvider, (_, id) {
      if (id == null) return;
      _takeFocusWish();
    });
    // „Zum Trailkopf" (#158 Schritt 4): Das Trail-Blatt stellt den Wunsch,
    // die Karte rechnet und zeigt — die Vorschau gehört hierher. Nach dem
    // Bild, nicht im Listener: Der Wunsch kommt aus einem Blatt, das
    // gerade schließt, und der Reiter wechselt im selben Zug.
    ref.listen(trailHeadRequestProvider, (_, request) {
      if (request == null) return;
      ref.read(trailHeadRequestProvider.notifier).state = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openTrailHead(request);
      });
    });
    // Ein Routen-Blatt bittet ums Einpassen — wenn es soweit ist, also
    // nach dem Einklappen (`map_panel.dart`); eingepasst wird darüber.
    ref.listen(mapFitRequestProvider, (_, points) {
      if (points == null) return;
      ref.read(mapFitRequestProvider.notifier).state = null;
      if (points.isEmpty) return;
      _fittedOnce = true;
      _fitPoints(points);
    });
    // Verbindung zurück ⇒ Ausgangskorb losschicken (#30). Genau hier
    // und nicht am App-Resume: Wer aus dem Wald nach Hause kommt, ohne
    // die App zu schließen, hat kein Resume — aber einen Netzwechsel.
    // Steht danach noch die Kopie (#183: Start ohne Empfang), holt die
    // Karte den frischen Stand — sonst bliebe „Trails vom …" stehen, bis
    // jemand von Hand neu lädt.
    ref.listen<bool>(noConnectivityProvider, (previous, next) {
      if (previous == true && next == false) {
        unawaited(() async {
          await ref.read(trailsProvider.notifier).sendOutbox();
          if (mounted && ref.read(trailsCachedAtProvider) != null) ref.invalidate(trailsProvider);
        }());
      }
    });
    ref.listen(mapFocusRideProvider, (_, r) {
      if (r == null) return;
      _fittedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitPoints([for (final p in r.points) LatLng(p.lat, p.lng)]);
      });
    });
    ref.listen(mapSplitRequestProvider, (_, request) {
      if (request == null) return;
      ref.read(mapSplitRequestProvider.notifier).state = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSplit(request);
      });
    });
    // „Auf der Karte zeigen" aus „Meine Bereiche" (Konzept-Schritt 3).
    ref.listen(mapFocusAreaProvider, (_, area) {
      if (area == null) return;
      _fittedOnce = true;
      final b = area.bounds;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitPoints([LatLng(b.south, b.west), LatLng(b.north, b.east)]);
      });
      ref.read(mapFocusAreaProvider.notifier).state = null;
    });

    // Was der Ausschnitt braucht — und was davon fehlt, wird nachgeladen.
    final camera = _camera;
    final cells = poiCellsFor(camera, groups);
    final officialView = officialViewFor(camera, official, enabled: officialOn);
    _scheduleLoads(cells: cells, groups: groups, officialView: officialView);

    // Offline-Karten: Solange die Werkzeugleiste offen ist, liegt die
    // Abdunkelung unter allem — gespeicherte Kacheln sind die Löcher.
    // Beobachtet werden die Bereiche nur dann; sonst kostet jeder
    // Kamera-Stillstand eine Rechnung, die niemand sieht.
    final overlayOn = ref.watch(offlineOverlayProvider);
    final overlayAreas =
        overlayOn ? ref.watch(storedAreasProvider).valueOrNull ?? const <StoredArea>[] : null;
    // Um den Bestand ein durchgehender Rand in der Textfarbe des Modus
    // (Design Turn 2: dunkel hell, hell #131A16).
    final coverage = overlayAreas != null && camera != null
        ? offlineCoverage(overlayAreas, camera.bounds, outlineColor: AppPalette.of(context).text)
        : null;
    final mask = coverage?.mask;
    // Offene Änderungen über der Abdunkelung — Schraffur in der
    // Gegenhelligkeit ihres Grunds und ein gestrichelter Rand: „kommt
    // dazu" hell auf dunkel, „fällt weg" dunkel auf hell und gespiegelt;
    // nur mit Werkzeugleiste.
    final toolsOpen = overlayOn;
    final draft = overlayOn ? ref.watch(areaDraftProvider) : null;
    final drawTool = draft?.tool;
    final pending = draft != null && camera != null ? draftLayers(draft, camera) : null;

    final layers = MapViewLayers(
      polygons: [
        ?mask,
        ...?pending?.polygons,
      ],
      circles: [
        if (position != null && position.accuracy > 0)
          MapViewCircle(
            center: LatLng(position.latitude, position.longitude),
            radiusM: position.accuracy,
            fillColor: AppColors.mapLines.ride.withValues(alpha: 0.12),
            borderColor: AppColors.mapLines.ride.withValues(alpha: 0.35),
            borderWidth: 1,
          ),
      ],
      polylines: [
        // Ganz unten der Rand des Bestands und die Schraffur offener
        // Änderungen (ohne Kennung, ein Tipp geht hindurch); dann die
        // offiziellen Trails, darüber die Fahrt, oben das Netz — ein Tipp
        // trifft zuerst das Netz.
        ...?coverage?.outline,
        ...?pending?.lines,
        if (officialOn && camera != null && camera.zoom >= kOfficialMinZoom)
          ...officialPolylines(official),
        // Während das Zerlege-Blatt offen ist, zeichnet es die Fahrt
        // selbst — in Abschnitten, mit den Griffen.
        if (splitPreview.isNotEmpty)
          ...splitPreview
        else if (focusRide != null)
          _ridePolyline(focusRide.points),
        // Der Weg zum Trailkopf (#158 Schritt 4), solange sein Blatt offen
        // ist — über der Fahrt, unter dem Netz.
        ...trailHeadPreview,
        // Die geplante Runde (#158 Schritt 5), solange ihr Blatt offen ist.
        // Im Planer: die gewählten Trails leuchten — liegt eine Runde auf
        // der Karte, zeigt sie, was dabei ist.
        if (loop.open && loopPlan == null) ...loopSelectionLines(trails, loop),
        if (loopPlan != null) ...loopPreviewLines(loopPlan),
        // Der ausgewählte Trail leuchtet (#178) — unter dem Netz, die
        // Linie selbst behält ihre Farbe. Deckendes Lime mit dunkler
        // Kontur (#195): Jeder Trail trägt schon einen weißen Saum, und
        // Lime allein hebt sich vom hellen Kartengrund kaum ab.
        if (selected != null && selected.points.length >= 2)
          MapViewPolyline(
            points: _smoothed(selected),
            color: AppColors.brand,
            width: kSelectionGlowWidth,
            borderColor: AppColors.onBrand.withValues(alpha: 0.7),
            borderWidth: kSelectionGlowBorder,
          ),
        if (ride != null && ride.points.length >= 2) _ridePolyline(ride.points),
        for (final t in shownTrails)
          MapViewPolyline(
            // Geglättet für das Bild (`line_smoothing.dart`) — gerechnet
            // wird überall sonst mit den Originalpunkten.
            points: _smoothed(t),
            // Der Name fließt entlang der Linie (ab Zoom 14).
            label: t.pending ? null : t.displayName,
            // Farbe = Schwierigkeit, Linienart = Zustand, Saum ab S4
            // gestrichelt (`trailLineStyleOf`, Rework E9) — schwarz allein
            // unterschiede S3 nicht von S5. Wartend (#30) gestrichelt und
            // blass.
            color: _colorOf(t).withValues(alpha: _colorOf(t).a * trailLineStyleOf(t).opacity),
            width: 4,
            dash: trailLineStyleOf(t).dash,
            borderColor: _borderOf(t, seenNotes).$1,
            borderWidth: _borderOf(t, seenNotes).$2,
            borderDash: trailLineStyleOf(t).haloDash,
            hitValue: t,
          ),
      ],
      markers: [
        if (camera != null && cells != null)
          ...poiMarkers(poiState, camera, cells, groups, hidden),
        // Anfang, Richtung und Ende (#96) und das Schild am Trailanfang
        // (Design 4c) — über den Orten, weil sie zum Netz gehören; das
        // Schild zuoberst, es ist das Antippbare.
        ...trailEndMarkers(shownTrails, camera, coachTrailId: _coachTrail?.id),
        ...trailBadgeMarkers(shownTrails, camera, coachTrailId: _coachTrail?.id),
        // Der getippte Start des Planers.
        if (loop.open && loop.start != null)
          MapViewMarker(
            key: const ValueKey('loop-start-pin'),
            point: loop.start!,
            width: 32,
            height: 32,
            alignment: Alignment.topCenter,
            child: const LoopStartFlag(),
          ),
        // Die Nadel des langen Drucks (#177), solange sein Menü offen ist.
        if (_pressedPoint != null)
          MapViewMarker(
            key: const ValueKey('map-press-pin'),
            point: _pressedPoint!,
            width: 36,
            height: 36,
            alignment: Alignment.topCenter,
            child: const Icon(Icons.location_on, size: 36, color: AppColors.brand),
          ),
        if (position != null)
          MapViewMarker(
            key: const ValueKey('my-position'),
            point: LatLng(position.latitude, position.longitude),
            // Während einer Fahrt pulst ein Ring um den Punkt (1r); die
            // Fläche wächst mit, damit er nicht beschnitten wird.
            width: ride != null ? kRidePulseExtent : 22,
            height: ride != null ? kRidePulseExtent : 22,
            child: _PositionDot(pulsing: ride != null),
          ),
      ],
    );

    return PopScope(
      // Offen gilt: Zurück schließt die Werkzeugleiste (mit Rückfrage),
      // statt die App zu verlassen; wartet der Planer auf einen Tipp,
      // bricht Zurück das Tippen ab.
      canPop: !toolsOpen && !loop.open && selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (loop.open) {
          // Stufenweise: erst Start-Tipp oder Zeichnen abbrechen, dann
          // den Planer schließen (ein Ergebnis-Blatt nimmt Zurück selbst).
          final notifier = ref.read(loopPlannerProvider.notifier);
          if (loop.pickingStart) {
            notifier.cancelStartPick();
          } else if (loop.drawTool != null) {
            notifier.disarmDraw();
          } else {
            _closeLoopPlanner();
          }
          return;
        }
        if (selected != null) {
          setState(() => _selectedTrailId = null);
          return;
        }
        unawaited(_closeTools());
      },
      child: Scaffold(
      key: _scaffoldKey,
      // Die Tastatur ÜBERLAGERT die Karte, sie schiebt sie nicht — wie in
      // der Hülle (`router.dart`) und in PilzBuddy (#397). Dieser Body
      // hat kein einziges Textfeld; die Felder stecken in Dialogen und
      // Blättern ÜBER der Karte („Mein Beitrag", Zerlege-Blatt). Ab Werk
      // schrumpfte der Scaffold trotzdem um die Tastatur, und zwar Bild
      // für Bild ihrer Animation: Die native Fläche von MapLibre wurde
      // dabei bei jedem Bild neu bemessen — unnötige Arbeit, gefunden beim
      // Feldbericht 2026-10-02 (Hänger beim Eintragen der Details). Der
      // größere Teil lag beim Speichern (CLAUDE.md, „Speichern ohne
      // Neuladen des Netzes"); die Wirkung dieser Zeile hält
      // `keyboard_inset_flow_test` fest.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          MapView(
            config: MapViewConfig(
              initialCenter: _dachCenter,
              initialZoom: _initialZoom,
              // OSM liefert Kacheln nur bis Zoom 19; unten reicht 3.
              minZoom: 3,
              maxZoom: 19,
              backgroundColor: AppColors.mapBackground,
              // Die Quellen der offiziellen Trails, solange die Ebene an
              // ist und eine ihrer Regionen geladen.
              bottomLeftInset: toolsOpen || loop.open ? kRailWidth + 8 : 0,
              attributions: [
                if (officialOn)
                  for (final src in official.loadedSources)
                    '${src.attribution} (${src.license})',
              ],
              onHit: _onHit,
              onTap: _onMapTap,
              onLongPress: _onLongPress,
              onCameraIdle: _onCameraIdle,
            ),
            controller: _controller,
            layers: layers,
          ),
          // Solange ein Werkzeug auf seinen Strich wartet, liegt die
          // Zeichenfläche über der Karte und hält sie fest.
          if (drawTool != null && camera != null)
            Positioned.fill(
              child: AreaDrawOverlay(camera: camera, tool: drawTool, onStroke: _onStroke),
            ),
          // Der Planer zeichnet ein Gebiet: Trails darin dazu oder weg.
          if (loop.open && loop.drawTool != null && camera != null)
            Positioned.fill(
              child: AreaDrawOverlay(
                key: const ValueKey('loop-draw'),
                camera: camera,
                tool: loop.drawTool!,
                hint: loop.drawTool == AreaDrawTool.add
                    ? 'Gebiet umfahren — die Trails darin kommen dazu'
                    : 'Gebiet umfahren — die Trails darin fallen weg',
                onRing: (ring) {
                  final n = ref.read(loopPlannerProvider.notifier).applyRing(ring);
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(SnackBar(
                        content: Text(n == 0
                            ? 'In dem Gebiet liegt kein wählbarer Trail.'
                            : '$n ${n == 1 ? 'Trail' : 'Trails'} ${loop.drawTool == AreaDrawTool.add ? 'dazu' : 'weg'}.')));
                },
              ),
            ),
          if (trailsAsync.isLoading && trails.isEmpty)
            const CenteredTrailLoader(),
          // Solange ein Werkzeug scharf ist, gehört der Platz oben der
          // Zeile, was der nächste Strich tut.
          if (trailsAsync.hasValue && trails.isEmpty && drawTool == null)
            const _EmptyHint(),
          // Die Banner oben untereinander, nicht übereinander: Update,
          // Ausgangskorb und — solange einer gilt — der Trail-Filter.
          // Rechts halten sie IMMER Platz für die Glühbirne frei (#180),
          // auch ohne Banner — sonst spränge nichts, aber ein Banner
          // läge unter ihr.
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(right: kBannerRightInset),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const UpdateBanner(),
                  const _OutboxBanner(),
                  // Im Planer, solange nichts gewählt ist: wie es geht.
                  if (loop.open && !loopPicking && loop.drawTool == null && loop.selected.isEmpty)
                    const Card(
                      key: ValueKey('loop-hint'),
                      margin: EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.alt_route),
                        title: Text('Tippe die Trails an, die in die Runde sollen — '
                            'oder nimm Liste oder Gebiet links.'),
                      ),
                    ),
                  // Der Planer wartet auf seinen Start (#158 Schritt 5).
                  if (loopPicking)
                    Card(
                      key: const ValueKey('loop-pick-banner'),
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.touch_app_outlined),
                        title: const Text('Tippe auf die Karte, wo die Runde beginnt.'),
                        trailing: TextButton(
                          key: const ValueKey('loop-pick-cancel'),
                          onPressed: () => ref.read(loopPlannerProvider.notifier).cancelStartPick(),
                          child: const Text('Abbrechen'),
                        ),
                      ),
                    ),
                  if (trailFilter.isActive)
                    _TrailFilterBanner(
                        filter: trailFilter, shown: shownTrails.length, total: trails.length),
                ],
              ),
              ),
            ),
          ),
          // Die Glühbirne (#180, Betreiber 2026-10-02): oben rechts, abgesetzt
          // von den Knöpfen unten — melden kann man immer, also steht sie
          // immer da, neben den Bannern.
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: CoachAnchor(
                  id: MapCoach.feedback,
                  child: MapRoundButton(
                    key: const ValueKey('feedback-button'),
                    tooltip: 'Idee oder Fehler melden',
                    icon: Icons.lightbulb_outline,
                    onPressed: () => showFeedbackFlow(context, ref),
                  ),
                ),
              ),
            ),
          ),
          if (ride != null || focusRide != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 72, 16, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (ride != null) _RideStatusCard(ride),
                      if (focusRide != null) _FocusRideCard(focusRide),
                    ],
                  ),
                ),
              ),
            ),
          // Die Werkzeugleiste „Offline-Karten" (seit 0.27.0) links, mittig:
          // unten liegen Maßstab und Quellenhinweis, oben die Banner —
          // beide bleiben frei. Scrollt, wenn der Schirm zu kurz ist.
          if (toolsOpen)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 56, 0, 64),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    child: CoachAnchor(
                      id: MapCoach.rail,
                      child: OfflineToolRail(
                      onSnapshot: _addViewport,
                      onTrails: trails.isEmpty ? null : _addTrails,
                      onManage: () => context.go('/profile/areas'),
                      onSave: _saveDraft,
                      onClose: _closeTools,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Die Leiste des Planers (seit 0.74.0) — derselbe Platz wie die
          // Leiste „Offline-Karten"; beide sind nie zugleich offen.
          if (loop.open)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 56, 0, 64),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    child: CoachAnchor(
                      id: MapCoach.loopRail,
                      child: LoopToolRail(
                        onParams: () => showLoopParamsSheet(context),
                        onList: () => showLoopListSheet(context, ref),
                        onCompute: _computeLoop,
                        onClose: _closeLoopPlanner,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Die Legende (#182): links am Rand, zu eine schmale Lasche. Eine
          // offene Leiste hat den Platz; solange ein Werkzeug zeichnet,
          // gehört die Karte dem Strich.
          if (!toolsOpen && !loop.open && drawTool == null)
            const SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 56, 0, 64),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CoachAnchor(id: MapCoach.legend, child: MapLegend()),
                ),
              ),
            ),
          // Die Schnellkarte des ausgewählten Trails (#178): unten links,
          // neben der Knopfspalte; ein offenes Routen-Blatt geht vor.
          if (selected != null && panelInset == 0)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 76, 12),
                  child: TrailQuickCard(
                    trail: selected,
                    onOpen: _openSelected,
                    onClose: () => setState(() => _selectedTrailId = null),
                  ),
                ),
              ),
            ),
          // Die Knöpfe rechts (seit 0.27.0; vorher links, wo jetzt die
          // Werkzeugleiste und — auf beiden Engines — Maßstab und
          // Quellenhinweis stehen). Die Glühbirne steht seit 0.75.0 oben
          // rechts (#180).
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (officialOn && official.unavailable)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Text('Offizielle Trails gerade nicht erreichbar'),
                        ),
                      ),
                    // Ohne Empfang kommt das Netz aus der Kopie (#32). Das
                    // gehört gesagt, sonst hält man den Stand für aktuell.
                    if (cachedAt != null)
                      Card(
                        key: const ValueKey('cached-notice'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text(ref.watch(trailsAwaitNetworkProvider)
                              ? 'Trails vom ${formatCachedAt(cachedAt)} — das Netz antwortet noch'
                              : 'Kein Empfang — Trails vom ${formatCachedAt(cachedAt)}'),
                        ),
                      ),
                    if (poiUnavailable)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Text('Orte gerade nicht erreichbar'),
                        ),
                      ),
                    // Von oben nach unten (seit 0.75.0, #190): Kartenebenen,
                    // Offline-Karten, Runde, Position — und unten, am Daumen,
                    // die Aufnahme.
                    const SizedBox(height: 4),
                    // Die Knopfspalte als EIN Anker (#132): Die Tour spart
                    // sie ganz aus und legt den Ring auf den gemeinten Knopf.
                    // Mit dem fünften Knopf (0.72.0) passt sie auf einem
                    // kleinen Telefon QUER (360 px hoch) nicht mehr: Dort
                    // skaliert sie herunter, statt unten abgeschnitten zu
                    // werden — hochkant bleiben es 44 px (`map_shell_test`).
                    // `Flexible` gibt der FittedBox die Höhe, die übrig ist;
                    // ohne sie bekäme sie „unendlich" und skalierte nie.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomRight,
                        child: CoachAnchor(
                      id: MapCoach.buttons,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Kartenebenen (#190): EIN Blatt, direkt — welche
                          // Trails, offizielle Trails, Orte. Es liegt über
                          // jeder Leiste und ändert an ihr nichts.
                          CoachAnchor(
                            id: MapCoach.layers,
                            child: MapRoundButton(
                              key: const ValueKey('layers-button'),
                              tooltip: 'Kartenebenen',
                              icon: Icons.layers_outlined,
                              onPressed: () => showMapLayersSheet(context),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Offline-Karten: die Leiste links mit den
                          // Werkzeugen für Bereiche. Öffnet und schließt sie —
                          // dasselbe wie ihr X und die Zurück-Taste. Offen:
                          // Rand in der Marke, die Leiste gehört zu diesem Knopf.
                          CoachAnchor(
                            id: MapCoach.offline,
                            child: MapRoundButton(
                              key: const ValueKey('offline-button'),
                              tooltip: 'Offline-Karten',
                              icon: Icons.download_for_offline_outlined,
                              active: toolsOpen,
                              onPressed: toolsOpen
                                  ? _closeTools
                                  : () {
                                      if (loop.open) _closeLoopPlanner();
                                      _openTools();
                                    },
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Der Rundenplaner (#158 Schritt 5): eigener Knopf,
                          // nicht die Glühbirne (Entscheidung 8.7).
                          CoachAnchor(
                            id: MapCoach.loop,
                            child: MapRoundButton(
                              key: const ValueKey('loop-button'),
                              tooltip: 'Runde planen',
                              icon: Icons.alt_route,
                              // Öffnet und schließt den Planer — wie der
                              // Knopf „Offline-Karten" seine Leiste.
                              active: loop.open,
                              onPressed: () => loop.open ? _closeLoopPlanner() : unawaited(_openLoopPlanner()),
                            ),
                          ),
                          const SizedBox(height: 10),
                          CoachAnchor(
                            id: MapCoach.locate,
                            child: MapRoundButton(
                              key: const ValueKey('locate-button'),
                              tooltip: 'Meine Position',
                              icon: Icons.my_location,
                              onPressed: _locateMe,
                            ),
                          ),
                          // Die Marke über der Aufnahme, nur während einer
                          // Fahrt (#105, E12): Fahne für „beginnt",
                          // Zielflagge für „endet"; läuft ein markierter
                          // Trail, Rand in der Marke.
                          if (canRecord && ride != null) ...[
                            const SizedBox(height: 14),
                            MapRoundButton(
                              key: const ValueKey('ride-mark-button'),
                              tooltip: markedTrailOpen(ride.marks) ? 'Trail endet' : 'Trail beginnt',
                              icon: markedTrailOpen(ride.marks) ? Icons.sports_score : Icons.flag_outlined,
                              active: markedTrailOpen(ride.marks),
                              onPressed: _toggleMark,
                            ),
                          ],
                          if (canRecord) ...[
                            const SizedBox(height: 14),
                            CoachAnchor(
                              id: MapCoach.record,
                              child: RecordButton(
                                key: const ValueKey('ride-button'),
                                recording: ride != null,
                                onPressed: _toggleRide,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// „2 warten auf Übertragung" — antippen schickt sie los (#30). Steht
/// unter dem Update-Banner, damit sich beide nicht überdecken.
class _OutboxBanner extends ConsumerWidget {
  const _OutboxBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingJobCountProvider);
    final failed = ref.watch(failedJobCountProvider);
    if (count == 0) return const SizedBox.shrink();
    final waiting = count - failed;
    final text = [
      if (waiting > 0) '$waiting ${waiting == 1 ? 'wartet' : 'warten'} auf Übertragung',
      if (failed > 0) '$failed abgelehnt',
    ].join(' · ');
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Card(
          key: const ValueKey('outbox-banner'),
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ListTile(
            dense: true,
            leading: Icon(failed > 0 ? Icons.error_outline : Icons.schedule),
            title: Text(text),
            subtitle: Text(failed > 0 && waiting == 0
                ? 'Entscheiden in der Trail-Liste'
                : 'Antippen zum Senden — sonst beim nächsten Netz'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final r = await ref.read(trailsProvider.notifier).sendOutbox();
              messenger.showSnackBar(SnackBar(
                  content: Text(r.sent > 0
                      ? '${r.sent} übertragen'
                      : 'Noch kein Netz — bleibt im Ausgangskorb.')));
            },
          ),
        ),
      ),
    );
  }
}

/// Ein aktiver Trail-Filter meldet sich auf der Karte (#66; PilzBuddy
/// #154): Eine Karte, die still ausblendet, sieht aus, als fehlten
/// Trails. Das X setzt ihn zurück — für Liste und Karte.
class _TrailFilterBanner extends ConsumerWidget {
  const _TrailFilterBanner({required this.filter, required this.shown, required this.total});

  final TrailListFilter filter;
  final int shown;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        key: const ValueKey('map-filter-banner'),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.filter_alt_outlined),
          title: Text('Gefiltert: ${filter.describe()}'),
          subtitle: Text('$shown von $total ${total == 1 ? 'Trail' : 'Trails'}'),
          trailing: IconButton(
            key: const ValueKey('map-filter-reset'),
            tooltip: 'Filter zurücksetzen',
            icon: const Icon(Icons.close),
            onPressed: () => ref.read(trailListFilterProvider.notifier).state = const TrailListFilter(),
          ),
        ),
      );
}

/// „28.9., 10:12" — Tag und Uhrzeit des zwischengespeicherten Stands.
String formatCachedAt(DateTime at) {
  final l = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day}.${l.month}., ${two(l.hour)}:${two(l.minute)}';
}

/// Die Fahrt: Kulisse ohne Kennung — ein Tipp gilt weiter dem Trail.
MapViewPolyline _ridePolyline(List<RidePoint> points) => MapViewPolyline(
      points: [for (final p in thinnedRide(points)) LatLng(p.lat, p.lng)],
      color: AppColors.mapLines.ride.withValues(alpha: 0.75),
      width: 4,
      borderColor: AppColors.mapLines.halo,
      borderWidth: AppColors.mapLines.haloBorderWidth,
    );

/// „Fahrt läuft · 1,2 km · 12 min" — die Rückmeldung, dass aufgezeichnet
/// wird, auch wenn die Linie noch kurz ist.
class _RideStatusCard extends StatelessWidget {
  const _RideStatusCard(this.ride);

  final RecordedRide ride;

  @override
  Widget build(BuildContext context) {
    final length = rideLengthM(ride.points);
    final duration = DateTime.now().toUtc().difference(ride.startedAt);
    return Card(
      key: const ValueKey('ride-status'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fiber_manual_record, size: 14, color: AppColors.mapLines.warning),
            const SizedBox(width: 8),
            Text('Fahrt läuft · ${formatMeters(length)} · ${rideDurationLabel(duration)}'),
          ],
        ),
      ),
    );
  }
}

/// Eine gespeicherte Fahrt auf der Karte, bis sie weggetippt wird.
class _FocusRideCard extends ConsumerWidget {
  const _FocusRideCard(this.ride);

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        key: const ValueKey('focus-ride'),
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Fahrt · ${formatMeters(ride.lengthM)} · '
                  '${rideDurationLabel(ride.duration)}'),
              IconButton(
                tooltip: 'Fahrt ausblenden',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => ref.read(mapFocusRideProvider.notifier).state = null,
              ),
            ],
          ),
        ),
      );
}

/// Leuchten um den ausgewählten Trail (#178, #195): 16 px Lime unter der
/// Linie (4 px plus weißer Saum, zusammen 8) — also 4 px Lime je Seite —
/// und 2 px dunkle Kontur je Seite außen.
const kSelectionGlowWidth = 16.0;
const kSelectionGlowBorder = 2.0;

/// Größe der Markerfläche, solange der Ring pulst: Punkt 22 px, Ring bis
/// zum 3,2-Fachen (Design 1r).
const kRidePulseExtent = 22.0 * kRidePulseScale;
const kRidePulseScale = 3.2;

class _PositionDot extends StatelessWidget {
  const _PositionDot({this.pulsing = false});

  /// Eine Fahrt läuft: der Ring um den Punkt pulst (Design 1r).
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final dot = SizedBox.square(
      dimension: 22,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.mapLines.ride,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
        ),
      ),
    );
    return Semantics(
      label: pulsing ? 'Deine Position, Fahrt läuft' : 'Deine Position',
      child: pulsing
          ? Stack(alignment: Alignment.center, children: [const RidePulse(), dot])
          : dot,
    );
  }
}

/// Der Ring um den Positionspunkt, solange eine Fahrt läuft (Design 1r):
/// wächst in 1,6 s vom Punkt auf das 3,2-Fache und blendet von 0,7 aus.
/// Bei reduzierter Bewegung steht nur ein ruhiger Ring da — die Aussage
/// „es wird aufgezeichnet" bleibt.
class RidePulse extends StatefulWidget {
  const RidePulse({super.key});

  static const period = Duration(milliseconds: 1600);

  @override
  State<RidePulse> createState() => _RidePulseState();
}

class _RidePulseState extends State<RidePulse> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: RidePulse.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _controller
        ..stop()
        ..value = 0.35;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox.square(
          key: const ValueKey('ride-pulse'),
          dimension: kRidePulseExtent,
          child: CustomPaint(painter: _PulsePainter(_controller)),
        ),
      );
}

/// Radius und Deckkraft des Rings bei [t] (0…1), `ease-out` wie im
/// Entwurf. Pur, damit der Test ohne Pixel prüfen kann.
({double scale, double opacity}) ridePulseAt(double t) {
  final e = Curves.easeOut.transform(t.clamp(0, 1));
  return (scale: 1 + (kRidePulseScale - 1) * e, opacity: 0.7 * (1 - e));
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final r = ridePulseAt(animation.value);
    canvas.drawCircle(size.center(Offset.zero), 11 * r.scale,
        Paint()..color = AppColors.mapLines.ride.withValues(alpha: r.opacity));
  }

  @override
  bool shouldRepaint(_PulsePainter old) => false;
}

/// Der leere Kartenzustand (#131): sagt, wie Trails hierher kommen, und
/// führt auf Tipp in die Kurzanleitung. Er verschwindet mit dem ersten
/// Trail von selbst — das Verschwinden IST die Rückmeldung.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: CoachAnchor(
          id: MapCoach.empty,
          child: Card(
          key: const ValueKey('map-empty-hint'),
          margin: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/profile/help'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Noch keine Trails. Importiere deine GPX-Dateien im Profil '
                      'oder verbinde dich mit Buddys — du siehst, was sie gefahren sind.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.help_outline, color: AppPalette.of(context).accentText,
                      semanticLabel: 'Kurzanleitung'),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
