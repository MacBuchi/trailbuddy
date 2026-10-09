// Das Zerlege-Blatt (#29, Konzept 5.1): die Fahrt auf der Karte,
// zerlegt in bekannte Trails (vorangehakt, „wieder gefahren"),
// Kandidaten für neue Trails (Griffe, Name, S-Grad — oder verwerfen)
// und den Rest, der nicht angeboten wird. Ein Blatt für alle drei
// Wege: nach der Aufzeichnung, aus „Meine Fahrten", aus dem GPX-Import
// für Fahrten (Konzept 5.2, „geht durch dasselbe Blatt wie 5.1").
//
// Die Karte zeichnet dabei mit: Das Blatt legt seine Abschnitte in
// [rideSplitPreviewProvider], der Karten-Screen malt sie über die Fahrt
// — Griffe verschieben, und die Linie folgt. Gerechnet wird in
// `ride_split.dart`, hier steht nur, was der Nutzer sieht und wählt.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../models/trail.dart';
import '../coach/coach.dart';
import '../help/seen_tours.dart';
import '../help/split_tour.dart';
import '../map/map_view/map_view.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../trails/gpx.dart';
import '../trails/rating_stars.dart';
import '../trails/singletrail_scale.dart';
import '../trails/trail_geometry.dart';
import '../trails/trail_providers.dart';
import '../trails/trail_condition.dart';
import '../trails/trail_sheet.dart' show formatLength;
import '../trails/trail_takeover.dart';
import '../trails/trail_traits.dart';
import 'ride_confirm.dart';
import 'ride_split.dart';
import 'ride_track.dart';
import 'road_index.dart';
import 'split_confirm_row.dart';

/// Was zerlegt werden soll: die Spur, ihre Quelle, die Streuung je Punkt
/// (nur bei eigenen Aufzeichnungen).
class SplitRequest {
  const SplitRequest({
    required this.track,
    required this.source,
    this.accuracyM,
    this.rideId,
    this.marks = const [],
    this.rodeAt,
  });

  /// Aus einer eigenen Fahrt. Die GPS-Höhe geht als Höhe hinein — für die
  /// Gefälle-Suche taugt sie, ausgeliefert wird sie NICHT (#28: „file
  /// elevations stay the source until measured"); [stripElevation] gilt.
  /// Eine aus GPX übernommene Fahrt (#188) zählt wie die Datei, aus der
  /// sie kam: Quelle `import`, Datei-Höhen gehen mit, keine Streuung.
  factory SplitRequest.fromRide(Ride ride) => SplitRequest(
        track: GpxTrack(
          name: ride.imported ? (ride.name ?? 'Fahrt') : 'Fahrt',
          points: [
            for (final p in ride.points) TrackPoint(p.lat, p.lng, ele: p.altM, time: p.at),
          ],
        ),
        source: ride.imported ? RecordingSource.import : RecordingSource.app,
        accuracyM: ride.imported ? null : [for (final p in ride.points) p.accuracyM],
        rideId: ride.id,
        marks: ride.marks,
      );

  /// Aus einer GPX-Datei, die eine Fahrt ist (Konzept 5.2). [rodeAt] ist
  /// das Fahrdatum, das der Fahrer für eine Datei ohne Zeiten eingetragen
  /// hat (#120) — jedes beigesteuerte Stück trägt es.
  factory SplitRequest.fromGpx(GpxTrack track, {DateTime? rodeAt}) =>
      SplitRequest(track: track, source: sourceOf(track.points), rodeAt: rodeAt);

  final GpxTrack track;
  final RecordingSource source;
  final List<double?>? accuracyM;
  final String? rideId;

  /// Die Marken „Trail beginnt/endet" der Aufnahme (#105); eine Datei hat
  /// keine.
  final List<RideMark> marks;

  /// Eingetragenes Fahrdatum einer geplanten Datei (#120), sonst null.
  final DateTime? rodeAt;

  /// Höhen aus dem GPS werden nicht beigesteuert, Höhen aus der Datei schon.
  bool get stripElevation => source == RecordingSource.app;
}

/// Wunsch aus einer Liste an die Karte: diese Fahrt zerlegen. Die Karte
/// passt sie ein, öffnet das Blatt und setzt den Wunsch zurück.
final mapSplitRequestProvider = StateProvider<SplitRequest?>((ref) => null);

/// Was die Karte während des Blatts über die Fahrt zeichnet.
final rideSplitPreviewProvider = StateProvider<List<MapViewPolyline>>((ref) => const []);

/// Zeigt das Blatt; `true` heißt „Fahrt verwerfen" (nur nach einer
/// Aufzeichnung angeboten, [offerDiscard]).
Future<bool> showRideSplitSheet(
  BuildContext context,
  SplitRequest request, {
  bool offerDiscard = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final discard = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Die Karte soll sichtbar bleiben: Sie zeigt, was die Griffe tun.
    barrierColor: Colors.black12,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scroll) =>
          _RideSplitSheet(request: request, offerDiscard: offerDiscard, scroll: scroll),
    ),
  );
  // Die Vorschau gehört dem Blatt; ohne Blatt keine Vorschau. Hier und
  // nicht im `dispose` des Blatts: Dort ist `ref` schon tot, und ein
  // nachgereichter Frame träfe im Test einen abgebauten Container.
  container.read(rideSplitPreviewProvider.notifier).state = const [];
  return discard ?? false;
}

class _RideSplitSheet extends ConsumerStatefulWidget {
  const _RideSplitSheet({required this.request, required this.offerDiscard, required this.scroll});

  final SplitRequest request;
  final bool offerDiscard;
  final ScrollController scroll;

  @override
  ConsumerState<_RideSplitSheet> createState() => _RideSplitSheetState();
}

/// Ein Kandidat, wie er im Blatt steht: mit den Griffen, dem Namen, dem
/// Grad — und ob er noch dabei ist.
class _CandidateDraft {
  _CandidateDraft(this.section, String name, {int? start, int? end})
      : start = start ?? section.start,
        end = end ?? section.end,
        nameField = TextEditingController(text: name);

  final CandidateSection section;
  int start;
  int end;
  final TextEditingController nameField;
  int? grade;
  final traits = <TrailTrait>{};
  bool selected = true;
  bool discarded = false;
}

/// Ein bekannter Trail, den ich zum ersten Mal fahre (#102): die
/// Vorbelegung aus dem Netz, was ich daraus mache, und ob ich es bestätigt
/// habe — ohne Bestätigung wird das Stück nicht beigesteuert (E2).
class _TakeOverDraft {
  _TakeOverDraft(this.prefill)
      : nameField = TextEditingController(text: prefill.name),
        grade = prefill.grade,
        traits = {...prefill.traits},
        rating = prefill.rating,
        condition = prefill.condition;

  final TakeOver prefill;
  final TextEditingController nameField;
  int? grade;
  final Set<TrailTrait> traits;
  int? rating;
  int? condition;
  bool confirmed = false;

  /// Bestätigen geht erst mit Sternen: Wer ihn sich zu eigen macht,
  /// bewertet ihn (Rework Abschnitt 9, E2).
  bool get canConfirm => rating != null;
}

class _RideSplitSheetState extends ConsumerState<_RideSplitSheet> {
  static final _date = DateFormat('d. MMMM', 'de');

  RideSplit? _split;
  bool _loading = true;
  final _knownSelected = <int>{};
  final _drafts = <_CandidateDraft>[];

  /// Je bekannter Zeile ohne eigenen Beitrag die Übernahme (#102).
  final _takeOvers = <int, _TakeOverDraft>{};
  bool _busy = false;
  int _done = 0;

  /// „30. September" — der Tag der Fahrt, für die vorgeschlagenen Namen.
  String _dateLabel = '';

  /// Ob die Zerlege-Tour (#134) für dieses Blatt schon erwogen wurde —
  /// einmal je Blatt, sobald die Zerlegung steht.
  bool _tourConsidered = false;

  /// Die Zerlege-Tour (#134): einmal, und NUR nach einer eigenen
  /// Aufzeichnung (`rideId`), nie aus dem GPX-Import — es sei denn, die
  /// Kurzanleitung hat sie ausdrücklich bestellt. Nach dem Bild, weil die
  /// Anker erst dann vermessbar sind; läuft schon etwas, bleibt es dabei.
  void _considerTour() {
    if (_tourConsidered) return;
    _tourConsidered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final requested = ref.read(requestedSplitTourProvider);
      final due = widget.request.rideId != null &&
          !ref.read(seenCoachToursProvider).contains(kSplitTourScript.id);
      if (!requested && !due) return;
      if (ref.read(coachProvider.notifier).busy) return;
      if (requested) ref.read(requestedSplitTourProvider.notifier).state = false;
      startSplitTour(ref);
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_compute());
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.nameField.dispose();
    }
    for (final t in _takeOvers.values) {
      t.nameField.dispose();
    }
    super.dispose();
  }

  Future<void> _compute() async {
    final points = widget.request.track.points;
    final latLng = [for (final p in points) LatLng(p.lat, p.lon)];
    final projection = FlatProjection.around(latLng);
    List<Trail> trails;
    try {
      trails = await ref.read(trailsProvider.future);
    } catch (_) {
      trails = const [];
    }
    List<StoredArea> areas;
    try {
      areas = await ref.read(storedAreasProvider.future);
    } catch (_) {
      areas = const [];
    }
    if (!mounted) return;
    final store = ref.read(areaStoreProvider);
    final open = ref.read(areaArchiveOpenerProvider);
    RoadLoadResult roads;
    try {
      roads = await loadRoads(
        areas: areas,
        box: LatBox.of(latLng),
        open: (a) => open(store, a),
        projection: projection,
        sourceKey: (a) => a.region,
      );
    } catch (e, s) {
      logError('Wege für das Zerlege-Blatt lesen', e, s);
      roads = (index: null, coverage: RoadCoverage.none, tilesNeeded: 0, tilesFound: 0);
    }
    if (!mounted) return;
    final split = splitRide(
      points: points,
      accuracyM: widget.request.accuracyM,
      trails: trails,
      roads: roads,
      marks: widget.request.marks,
    );
    setState(() {
      _split = split;
      _loading = false;
      _knownSelected.addAll([for (var i = 0; i < split.known.length; i++) i]);
      for (var i = 0; i < split.known.length; i++) {
        final trail = split.known[i].trail;
        if (needsTakeOver(trail)) _takeOvers[i] = _TakeOverDraft(takeOverOf(trail));
      }
      final date = _date.format((points.first.time ?? DateTime.now()).toLocal());
      _dateLabel = date;
      for (var i = 0; i < split.candidates.length; i++) {
        _drafts.add(_CandidateDraft(
            split.candidates[i], split.candidates.length == 1 ? 'Trail vom $date' : 'Trail ${i + 1} vom $date'));
      }
    });
    _pushPreview();
  }

  /// „Stück selbst wählen" (#104): ein Kandidat über die ganze Fahrt,
  /// vorgewählt ohne die Heimzone ([manualSection]).
  void _addManual() {
    final split = _split;
    final m = split == null ? null : manualSection(split);
    if (m == null) return;
    final open = _drafts.where((d) => !d.discarded).length;
    setState(() {
      _drafts.add(_CandidateDraft(
          m.section, open == 0 ? 'Trail vom $_dateLabel' : 'Trail ${open + 1} vom $_dateLabel',
          start: m.start, end: m.end));
    });
    _pushPreview();
  }

  /// Die Frage zur bekannten Zeile [i], mit der Zeit der Fahrt am Trail.
  /// Ohne Zeiten (geplante Datei) keine Frage: Wer nicht nachweislich dort
  /// war, bestätigt nichts.
  (ConfirmTarget, DateTime)? _questionAt(RideSplit split, int i) {
    final known = split.known[i];
    final at = split.points[known.start].time;
    final target = splitQuestionFor(known.trail, at);
    return target == null || at == null ? null : (target, at);
  }

  List<LatLng> _latLng(int start, int end) => [
        for (final p in _split!.points.sublist(start, end + 1)) LatLng(p.lat, p.lon),
      ];

  double _lengthOf(int start, int end) => trackLengthM(_split!.points.sublist(start, end + 1));

  double? _lossOf(int start, int end) {
    final a = _split!.points[start].ele, b = _split!.points[end].ele;
    return a == null || b == null ? null : a - b;
  }

  /// Die Karte zeichnet: die ganze Fahrt blass, darüber die bekannten
  /// Stücke grün und die Kandidaten in ihrer Farbe — gewählt kräftig,
  /// abgewählt gestrichelt, verworfen gar nicht.
  void _pushPreview() {
    final split = _split;
    if (split == null) return;
    final lines = <MapViewPolyline>[
      MapViewPolyline(
        points: [for (final p in thinnedTrack(split.points)) LatLng(p.lat, p.lon)],
        color: AppColors.mapLines.ride.withValues(alpha: 0.45),
        width: 4,
        borderColor: AppColors.mapLines.halo,
        borderWidth: AppColors.mapLines.haloBorderWidth,
      ),
      for (var i = 0; i < split.known.length; i++)
        MapViewPolyline(
          points: _latLng(split.known[i].start, split.known[i].end),
          color: AppColors.mapLines.mine.withValues(alpha: _knownSelected.contains(i) ? 1 : 0.5),
          width: 6,
          borderColor: AppColors.mapLines.halo,
          borderWidth: AppColors.mapLines.haloBorderWidth,
          dash: _knownSelected.contains(i) ? null : const [10, 8],
        ),
      for (final d in _drafts)
        if (!d.discarded)
          MapViewPolyline(
            points: _latLng(d.start, d.end),
            color: AppColors.mapLines.candidate.withValues(alpha: d.selected ? 1 : 0.5),
            width: 6,
            borderColor: AppColors.mapLines.halo,
            borderWidth: AppColors.mapLines.haloBorderWidth,
            dash: d.selected ? null : const [10, 8],
          ),
    ];
    ref.read(rideSplitPreviewProvider.notifier).state = lines;
  }

  /// Eine bekannte Zeile zählt, wenn sie angehakt ist UND — beim ersten
  /// Befahren — übernommen (#102, E2).
  bool _knownCounts(int i) => _knownSelected.contains(i) && (_takeOvers[i]?.confirmed ?? true);

  int get _selectedCount =>
      [for (var i = 0; i < (_split?.known.length ?? 0); i++) if (_knownCounts(i)) i].length +
      _drafts.where((d) => d.selected && !d.discarded && _longEnough(d)).length;

  /// Wann die Fahrt am Trail war — die Zeit einer Zustandsangabe beim
  /// Übernehmen. Ohne Zeiten (geplante Datei) keine: Wer nicht
  /// nachweislich dort war, meldet keinen Zustand „vor Ort".
  DateTime? _rodeAt(int i) => _split!.points[_split!.known[i].start].time;

  bool _longEnough(_CandidateDraft d) => _lengthOf(d.start, d.end) >= kTrailMinLengthM;

  GpxTrack _trackOf(int start, int end, String name) => GpxTrack(
        name: name,
        points: [
          for (final p in _split!.points.sublist(start, end + 1))
            widget.request.stripElevation ? TrackPoint(p.lat, p.lon, time: p.time) : p,
        ],
      );

  Future<void> _contribute() async {
    final split = _split;
    if (split == null || _selectedCount == 0) return;
    setState(() {
      _busy = true;
      _done = 0;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(trailsProvider.notifier);
    var ok = 0, queued = 0, failed = 0;
    var limitHit = false;
    final jobs = <({GpxTrack track, int? grade, Set<TrailTrait> traits, int? rating, int? knownIndex})>[
      for (var i = 0; i < split.known.length; i++)
        if (_knownCounts(i))
          if (_takeOvers[i] case final t?)
            // Zum ersten Mal gefahren (#102): der ganze Beitrag, vorbelegt
            // aus dem Netz und bestätigt — auch der fremde Name wird mein.
            (
              track: _trackOf(split.known[i].start, split.known[i].end, t.nameField.text),
              grade: t.grade,
              traits: {...t.traits},
              rating: t.rating,
              knownIndex: i,
            )
          else
            // Schon beschrieben: „wieder gefahren" ist ein Beleg, kein
            // Name — der eigene Beitrag bleibt, wie er ist.
            (
              track: _trackOf(split.known[i].start, split.known[i].end, ''),
              grade: null,
              traits: const <TrailTrait>{},
              rating: null,
              knownIndex: i,
            ),
      for (final d in _drafts)
        if (d.selected && !d.discarded && _longEnough(d))
          (
            track: _trackOf(d.start, d.end, d.nameField.text),
            grade: d.grade,
            traits: {...d.traits},
            rating: null,
            knownIndex: null,
          ),
    ];
    for (final job in jobs) {
      try {
        final r = await notifier.contribute(job.track,
            source: widget.request.source,
            rodeAt: widget.request.rodeAt,
            grade: job.grade,
            traits: job.traits,
            rating: job.rating);
        // Der Zustand beim Übernehmen geht als Meldung an den bekannten
        // Trail, zur Zeit der Fahrt dort — ohne Netz über den Korb.
        final k = job.knownIndex;
        final condition = k == null ? null : _takeOvers[k]?.condition;
        final at = k == null ? null : _rodeAt(k);
        if (k != null && condition != null && at != null) {
          await notifier.report(split.known[k].trail.id, condition: condition, onSite: true, at: at);
        }
        if (r.queued) {
          queued++;
        } else {
          ok++;
        }
      } on DailyLimitException {
        limitHit = true;
        break;
      } catch (e, s) {
        logError('Fahrt-Abschnitt beisteuern', e, s);
        failed++;
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    final fresh = ok == 0 || await notifier.reloadAfterWrite('Trails nach dem Zerlegen laden');
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(
        '$ok ${ok == 1 ? 'Abschnitt' : 'Abschnitte'} beigesteuert'
        '${queued > 0 ? ', $queued ${queued == 1 ? 'wartet' : 'warten'} im Ausgangskorb auf Netz' : ''}'
        '${failed > 0 ? ', $failed fehlgeschlagen' : ''}'
        '${limitHit ? ' — für heute ist das Limit erreicht' : ''}'
        '${fresh ? '' : ' — sichtbar, sobald die Liste wieder lädt.'}',
      ),
    ));
    if (failed == 0 && !limitHit) navigator.pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final split = _split;
    final track = widget.request.track;
    final totalM = split?.totalM ?? trackLengthM(track.points);
    if (split != null) _considerTour();
    // Während der Zerlege-Tour baut die Liste ALLES: Sonst gäbe es die
    // Zeilen unter dem Rand nicht, `requires` hielte sie für fehlend, und
    // der Schritt fiele weg. Die Maschine scrollt das Ziel selbst ins Bild.
    final touring = ref.watch(coachProvider.select((r) => r?.script.id == kSplitTourScript.id));
    final firstTakeOver = [
      for (var i = 0; i < (split?.known.length ?? 0); i++)
        if (_takeOvers[i] != null && _knownSelected.contains(i)) i,
    ].firstOrNull;
    final firstQuestion = split == null
        ? null
        : [for (var i = 0; i < split.known.length; i++) if (_questionAt(split, i) != null) i].firstOrNull;
    final firstCandidate = [for (var i = 0; i < _drafts.length; i++) if (!_drafts[i].discarded) i].firstOrNull;
    // Die Knöpfe stehen FEST unter der Liste: Auf einem halb geöffneten
    // Blatt lägen sie sonst unter dem Rand, und „Behalten" wäre erst
    // nach Scrollen zu erreichen.
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
        controller: widget.scroll,
        scrollCacheExtent: touring ? const ScrollCacheExtent.pixels(100000) : null,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        children: [
          Text(widget.offerDiscard ? 'Fahrt beendet' : 'Fahrt zerlegen',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${formatLength(totalM)} · ${track.points.length} Punkte'
            '${widget.rideDuration != null ? ' · ${rideDurationLabel(widget.rideDuration!)}' : ''}',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          if (_loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Die Fahrt wird zerlegt: bekannte Trails, Kandidaten, Rest …'),
          ] else if (split != null) ...[
            if (split.known.isNotEmpty) ...[
              Text('Wieder gefahren', style: theme.textTheme.titleMedium),
              const Text('Vorangehakt — als Beleg beigesteuert, das hält den Trail aktuell.'),
              if (_takeOvers.values.any((t) => !t.confirmed && t.canConfirm))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('split-takeover-all'),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              for (final t in _takeOvers.values) {
                                if (t.canConfirm) t.confirmed = true;
                              }
                            }),
                    icon: const Icon(Icons.done_all),
                    label: const Text('Alle übernehmen'),
                  ),
                ),
              for (var i = 0; i < split.known.length; i++) ...[
                _anchorIf(i == 0, SplitCoach.known, CheckboxListTile(
                  key: ValueKey('split-known-$i'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _knownSelected.contains(i),
                  enabled: !_busy,
                  onChanged: (v) => setState(() {
                    if (v ?? false) {
                      _knownSelected.add(i);
                    } else {
                      _knownSelected.remove(i);
                    }
                    _pushPreview();
                  }),
                  title: Text(split.known[i].trail.displayName),
                  subtitle: Text(formatLength(split.known[i].lengthM)),
                )),
                if (_takeOvers[i] != null && _knownSelected.contains(i))
                  _anchorIf(i == firstTakeOver, SplitCoach.takeOver, _takeOverCard(i, theme)),
                // Unbestätigtes zu diesem Trail, das unterwegs offen blieb
                // (#116): hier noch einmal gefragt, zur Zeit der Fahrt.
                if (_questionAt(split, i) case (final target, final at))
                  _anchorIf(i == firstQuestion, SplitCoach.question,
                      SplitConfirmRow(target: target, rodeAt: at, index: i)),
              ],
              const SizedBox(height: 12),
            ],
            Text('Kandidaten für neue Trails', style: theme.textTheme.titleMedium),
            if (split.roads != RoadCoverage.complete)
              CoachAnchor(
                id: SplitCoach.noRoads,
                child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  key: const ValueKey('split-no-roads'),
                  split.roads == RoadCoverage.partial
                      ? 'Die Wege kennt die App hier nur zum Teil: Ein gespeicherter '
                          'Bereich deckt die Fahrt nicht ganz. Von selbst findet sie '
                          'Kandidaten erst, wenn ein Bereich bis Zoomstufe 13 '
                          'die ganze Fahrt trägt (Knopf „Offline-Karten" auf der Karte → '
                          'Ausschnitt oder Fläche wählen → Speichern).'
                      : 'Die Wege kennt die App hier nicht: Es gibt keinen '
                          'gespeicherten Bereich über der Fahrt. Von selbst findet sie '
                          'Kandidaten erst damit — Knopf „Offline-Karten" auf der Karte → '
                          'Ausschnitt oder Fläche wählen → Speichern, dann die Fahrt aus '
                          '„Meine Fahrten" noch einmal zerlegen.',
                  style: theme.textTheme.bodyMedium,
                ),
              ))
            else if (!split.hasElevation)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Ohne Höhen lässt sich kein Gefälle finden — die Spur trägt keine.'),
              )
            else if (_drafts.every((d) => d.discarded))
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Kein Stück mit anhaltendem Gefälle abseits von Wegen.'),
              ),
            for (var i = 0; i < _drafts.length; i++)
              if (!_drafts[i].discarded) _candidateCard(i, theme, anchored: i == firstCandidate),
            // Was die Suche nicht findet — eine Jump-Line, ein flacher
            // Flowtrail, ein Uphill —, wählt man selbst (#104). Ohne
            // gespeicherten Bereich und ohne Höhen.
            if (manualSection(split) != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    // `Flexible`: auf 360 dp lief die Zeile sonst über (mit
                    // dem Test der Tour gefunden, #134).
                    Flexible(
                      child: CoachAnchor(
                        id: SplitCoach.pick,
                        child: TextButton.icon(
                          key: const ValueKey('split-pick-section'),
                          onPressed: _busy ? null : _addManual,
                          icon: const Icon(Icons.content_cut),
                          label: const Text('Stück selbst wählen'),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text('Für alles, was die Suche nicht findet.',
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Rest: ${formatLength(split.restM)} Anfahrt, Forstweg, Straße — wird nicht angeboten.'
              '${split.droppedInaccurate > 0 ? ' ${split.droppedInaccurate} unscharfe Punkte ausgelassen.' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            if (widget.request.rideId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Die Fahrt bleibt als Ganzes auf deinem Gerät („Meine Fahrten"); '
                  'beigesteuert werden nur die gewählten Stücke.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(
                  value: _selectedCount == 0 ? null : _done / _selectedCount),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
            children: [
              if (widget.offerDiscard)
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(true),
                  child: const Text('Verwerfen'),
                ),
              const Spacer(),
              CoachAnchor(
                id: SplitCoach.submit,
                child: FilledButton(
                key: const ValueKey('split-submit'),
                onPressed: _busy || _loading
                    ? null
                    : _selectedCount == 0
                        ? () => Navigator.of(context).pop(false)
                        : _contribute,
                child: Text(_selectedCount == 0
                    ? (widget.offerDiscard ? 'Behalten' : 'Schließen')
                    : '$_selectedCount beisteuern'),
              )),
            ],
            ),
          ),
        ],
      ),
    );
  }

  /// Die aufgeklappte Zeile eines Trails, den ich zum ersten Mal fahre
  /// (#102): Name, S-Grad, Charakter, Sterne, Zustand — vorbelegt aus dem
  /// Netz, sichtbar als „Vorschlag aus dem Netz" (E1). Bestätigt klappt
  /// sie zu einer Zeile zusammen.
  Widget _takeOverCard(int i, ThemeData theme) {
    final t = _takeOvers[i]!;
    final palette = AppPalette.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(color: palette.muted);
    const fromNet = 'Vorschlag aus dem Netz';
    if (t.confirmed) {
      final grade = t.grade;
      return Padding(
        padding: const EdgeInsets.only(left: 48, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                key: ValueKey('split-takeover-done-$i'),
                'Übernommen: ${t.nameField.text.trim().isEmpty ? 'ohne Namen' : t.nameField.text.trim()}'
                '${grade != null ? ' · ${singletrailGrade(grade).label}' : ''}'
                ' · ${'★' * (t.rating ?? 0)}'
                '${t.condition != null ? ' · ${trailConditionLabel(t.condition!)}' : ''}',
                style: hint,
              ),
            ),
            TextButton(
              key: ValueKey('split-takeover-edit-$i'),
              onPressed: _busy ? null : () => setState(() => t.confirmed = false),
              child: const Text('Ändern'),
            ),
          ],
        ),
      );
    }
    return Card(
      key: ValueKey('split-takeover-$i'),
      margin: const EdgeInsets.only(left: 32, bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Zum ersten Mal gefahren — mach ihn dir zu eigen. Dann bleibt er '
              'dir, auch wenn der Buddy seinen Beitrag löscht. Ohne Bewertung '
              'wird das Stück nicht beigesteuert.',
              style: theme.textTheme.bodySmall,
            ),
            TextField(
              key: ValueKey('split-takeover-name-$i'),
              controller: t.nameField,
              enabled: !_busy,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Name', counterText: ''),
              textCapitalization: TextCapitalization.sentences,
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    key: ValueKey('split-takeover-grade-$i'),
                    initialValue: t.grade,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Schwierigkeit (Singletrail-Skala)',
                      isDense: true,
                      helperText: t.grade != null && t.grade == t.prefill.grade ? fromNet : null,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Keine Angabe')),
                      for (final g in kSingletrailScale)
                        DropdownMenuItem<int?>(
                          value: g.value,
                          child: Text('${g.label} · ${g.short}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => t.grade = v),
                  ),
                ),
                SingletrailScaleButton(highlight: t.grade),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tr in TrailTrait.values)
                    TrailTraitChip(
                      tr,
                      key: ValueKey('split-takeover-trait-$i-${tr.db}'),
                      selected: t.traits.contains(tr),
                      onSelected: _busy
                          ? null
                          : (v) => setState(() => v ? t.traits.add(tr) : t.traits.remove(tr)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Bewertung', style: theme.textTheme.labelLarge),
            Row(
              children: [
                RatingPicker(
                  keyPrefix: 'split-takeover-rating-$i',
                  value: t.rating,
                  onChanged: _busy ? null : (v) => setState(() => t.rating = v),
                ),
                if (t.rating != null && t.rating == t.prefill.rating)
                  Flexible(child: Text(fromNet, style: hint)),
              ],
            ),
            Text('Zustand heute (freiwillig)', style: theme.textTheme.labelLarge),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in kTrailConditions)
                  ChoiceChip(
                    key: ValueKey('split-takeover-condition-$i-${c.value}'),
                    label: Text(c.label),
                    tooltip: c.description,
                    selected: t.condition == c.value,
                    onSelected: _busy
                        ? null
                        : (sel) => setState(() => t.condition = sel ? c.value : null),
                  ),
              ],
            ),
            if (t.condition != null && t.condition == t.prefill.condition)
              Text('Zuletzt bestätigt gemeldet', style: hint),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonal(
                  key: ValueKey('split-takeover-confirm-$i'),
                  onPressed: _busy || !t.canConfirm ? null : () => setState(() => t.confirmed = true),
                  child: const Text('Übernehmen'),
                ),
                const SizedBox(width: 8),
                if (!t.canConfirm)
                  Expanded(
                    child: Text('Erst Sterne vergeben — wie gefällt er dir?',
                        key: ValueKey('split-takeover-needs-rating-$i'), style: hint),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Legt um [child] den Anker [id] — nur für die ERSTE Zeile ihrer Art,
  /// denn eine Kennung zeigt auf genau ein Widget.
  Widget _anchorIf(bool first, String id, Widget child) =>
      first ? CoachAnchor(id: id, child: child) : child;

  Widget _candidateCard(int i, ThemeData theme, {bool anchored = false}) {
    final d = _drafts[i];
    final s = d.section;
    final lengthM = _lengthOf(d.start, d.end);
    final loss = _lossOf(d.start, d.end);
    final tooShort = lengthM < kTrailMinLengthM;
    final home = homeZoneOf(_split!, d.start, d.end);
    final share = s.offRoadShare;
    // Selbst gewählt und markiert: Die Griffe reichen über die ganze
    // Fahrt, vorgewählt ist das Stück.
    final bounds = s.spansRide ? (0, _split!.points.length - 1) : (s.start, s.end);
    return _anchorIf(anchored, SplitCoach.candidate, Card(
      key: ValueKey('split-candidate-$i'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  key: ValueKey('split-candidate-check-$i'),
                  value: d.selected && !tooShort,
                  onChanged: _busy || tooShort ? null : (v) => setState(() {
                        d.selected = v ?? false;
                        _pushPreview();
                      }),
                ),
                Expanded(
                  child: TextField(
                    key: ValueKey('split-candidate-name-$i'),
                    controller: d.nameField,
                    enabled: !_busy,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Name', counterText: ''),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                IconButton(
                  key: ValueKey('split-candidate-discard-$i'),
                  tooltip: 'Kandidat verwerfen',
                  icon: const Icon(Icons.close),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            d.discarded = true;
                            _pushPreview();
                          }),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                '${formatLength(lengthM)}'
                '${loss != null ? ' · ↓ ${loss.round()} Hm' : ''}'
                '${share != null ? ' · ${(share * 100).round()} % abseits von Wegen' : ''}'
                '${s.manual ? ' · selbst gewählt' : ''}'
                '${s.marked ? ' · unterwegs markiert' : ''}'
                '${tooShort ? ' · zu kurz für einen Trail' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (home.nearStart || home.nearEnd)
              _anchorIf(anchored, SplitCoach.home, Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  key: ValueKey('split-candidate-home-$i'),
                  home.nearStart && home.nearEnd
                      ? 'Beginnt und endet nahe Start und Ziel deiner Fahrt.'
                      : home.nearStart
                          ? 'Beginnt nahe deinem Start.'
                          : 'Endet nahe deinem Ziel.',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppPalette.of(context).warningText),
                ),
              )),
            // Die zwei Griffe: Punkt für Punkt, die Karte zeigt es.
            _anchorIf(anchored, SplitCoach.range, RangeSlider(
              key: ValueKey('split-candidate-range-$i'),
              min: bounds.$1.toDouble(),
              max: bounds.$2.toDouble(),
              divisions: bounds.$2 - bounds.$1,
              values: RangeValues(d.start.toDouble(), d.end.toDouble()),
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                        d.start = v.start.round();
                        d.end = v.end.round();
                        _pushPreview();
                      }),
            )),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    key: ValueKey('split-candidate-grade-$i'),
                    initialValue: d.grade,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Schwierigkeit (Singletrail-Skala)', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Keine Angabe')),
                      for (final g in kSingletrailScale)
                        DropdownMenuItem<int?>(
                          value: g.value,
                          child: Text('${g.label} · ${g.short}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => d.grade = v),
                  ),
                ),
                SingletrailScaleButton(highlight: d.grade),
              ],
            ),
            // Der Charakter (#72): dieselben Chips wie in „Mein Beitrag".
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final t in TrailTrait.values)
                    TrailTraitChip(
                      t,
                      key: ValueKey('split-candidate-trait-$i-${t.db}'),
                      selected: d.traits.contains(t),
                      onSelected: _busy
                          ? null
                          : (v) => setState(() => v ? d.traits.add(t) : d.traits.remove(t)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

extension on _RideSplitSheet {
  /// Dauer nur bei einer eigenen Fahrt mit Zeiten.
  Duration? get rideDuration {
    final pts = request.track.points;
    final a = pts.first.time, b = pts.last.time;
    return request.rideId == null || a == null || b == null ? null : b.difference(a);
  }
}

/// Jeder n-te Punkt für die blasse Fahrt darunter — dieselbe Grenze wie
/// bei der laufenden Spur.
List<TrackPoint> thinnedTrack(List<TrackPoint> points, {int max = kRideTrackMaxDots}) {
  if (points.length <= max) return points;
  final step = (points.length / max).ceil();
  final kept = <TrackPoint>[for (var i = 0; i < points.length; i += step) points[i]];
  if (kept.last != points.last) kept.add(points.last);
  return kept;
}
