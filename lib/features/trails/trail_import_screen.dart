import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../core/router_branches.dart';
import '../../models/trail.dart';
import '../profile/profile_providers.dart';
import '../rides/ride_import.dart';
import '../rides/ride_providers.dart';
import '../rides/ride_split_sheet.dart';
import '../rides/ride_profile_guess.dart';
import '../routing/ride_calibrator.dart';
import '../routing/route_profile.dart';
import 'elevation_backfill.dart';
import 'gpx.dart';
import 'gpx_files.dart';
import 'terrain_heights.dart';
import 'trail_geometry.dart';
import 'trail_details_dialog.dart';
import 'trail_providers.dart';
import 'trail_sheet.dart';
import 'trail_takeover.dart';

/// Dateiauswahl als Provider, damit Tests Dateien einhängen, ohne den
/// System-Dialog zu öffnen.
///
/// **Auf Android ohne Typfilter.** Der System-Dialog (SAF) filtert nach
/// MIME-Typen, und für `.gpx` gibt es keinen registrierten — Dateimanager
/// melden `application/octet-stream` oder gar nichts. Mit einem Filter auf
/// `application/gpx+xml` waren GPX- UND Zip-Dateien ausgegraut, die
/// Auswahl scheiterte, bevor die App eine Datei sah (Feldbefund v0.1.0,
/// dieselbe Lehre wie im PilzBuddy-Import). Geprüft wird deshalb danach,
/// in [gpxFilesFrom]. Im Browser filtert die Endung bequem vor.
final gpxPickerProvider = Provider<Future<List<PickedFile>> Function()>((ref) {
  return () async {
    // Ohne `BuildContext`: die Sprache wie beim Dienst (`serviceL10n`).
    final l = serviceL10n();
    final typeGroups = kIsWeb
        ? [XTypeGroup(label: l.importPickerGpxOrZip, extensions: ['gpx', 'zip'])]
        : [XTypeGroup(label: l.importPickerAllFiles, mimeTypes: ['*/*'])];
    final files = await openFiles(acceptedTypeGroups: typeGroups);
    return [
      for (final f in files) PickedFile(name: f.name, bytes: await f.readAsBytes()),
    ];
  };
});

/// „12.9.2026" — das eingetragene Fahrdatum (#120).
String formatRideDate(DateTime d) => '${d.day}.${d.month}.${d.year}';

/// Ein Kandidat aus einer Datei, mit der Einordnung nach Konzept 5.2.
class ImportCandidate {
  ImportCandidate(this.file, this.track,
      {this.existing, this.existingNameMissing = false})
      : lengthM = trackLengthM(track.points),
        // Aus der VEREINFACHTEN Spur, also aus genau dem, was hochgeht:
        // Das Blatt rechnet danach mit denselben Punkten, und die Zahl
        // hier soll dieselbe sein wie dort.
        _elevation = elevationGainLoss(simplify(track.points)),
        _kind = classifyTrack(track.points),
        heightless = GpxTrack(
            name: track.name,
            link: track.link,
            points: [for (final p in track.points) TrackPoint(p.lat, p.lon, time: p.time)]),
        source = sourceOf(track.points);

  final String file;
  final GpxTrack track;
  final double lengthM;
  final ({double gain, double loss})? _elevation;
  final TrackKind _kind;
  final RecordingSource source;

  /// Dieselbe Spur ohne Höhen — was hochgeht, wenn sie verworfen sind.
  final GpxTrack heightless;

  /// Der Vergleich der Datei-Höhen mit dem Geländemodell (#186); null,
  /// solange er läuft, die Datei keine Höhen hat oder das Modell dort
  /// keine kennt.
  TerrainComparison? terrain;

  /// Die Höhen der Datei verwerfen (#186): angeboten, wenn [terrain]
  /// auffällt, und dann vorgewählt — schlechte Höhen sollen das Netz nie
  /// erreichen. Die Anzeige liest danach das Geländemodell.
  bool discardHeights = false;

  /// Was hochgeht: die Spur, ohne Höhen, wenn sie verworfen sind.
  GpxTrack get uploadTrack => discardHeights ? heightless : track;

  ({double gain, double loss})? get elevation => discardHeights ? null : _elevation;

  /// Ohne Höhen entscheidet die Länge allein (`classifyTrack`) — mit
  /// falschen Höhen würde ein Downhill sonst leicht zur Fahrt.
  TrackKind get kind => discardHeights ? classifyTrack(heightless.points) : _kind;

  /// Lohnt der Vergleich: Die Datei hat Höhen, und sie gingen hinauf.
  bool get checksTerrain =>
      _elevation != null && (existing == null || (existing?.canBackfill ?? false));

  /// EINE Kennung je Kandidat, beim Einlesen vergeben: Ein zweiter
  /// Versuch nach einem Abriss trägt dieselbe, und der Server antwortet
  /// mit der Aufzeichnung von damals statt eine zweite anzulegen.
  final String clientId = newClientId();

  /// Diese Spur liegt schon als eigene Aufzeichnung auf dem Server (#16).
  /// Dann wird sie nie ein zweites Mal beigesteuert — höchstens bekommt
  /// die alte ihre Höhen.
  final ExistingRecording? existing;

  bool get backfill => !discardHeights && (existing?.canBackfill ?? false);

  /// Die schon beigesteuerte Aufzeichnung hat keinen eigenen Namen — etwa
  /// weil der Name aus der Datei vor 0.9.1 zu lang war und das Speichern
  /// scheiterte. Dann übernimmt ein zweiter Import ihn.
  final bool existingNameMissing;

  bool get adoptsName =>
      existing != null && existingNameMissing && track.name.trim().isNotEmpty;

  /// Etwas an einer schon beigesteuerten Aufzeichnung nachtragen (Höhen
  /// oder Name) — nie eine zweite anlegen.
  bool get completesExisting => backfill || adoptsName;

  bool get contributable =>
      existing == null ? kind == TrackKind.trail : completesExisting;

  /// Das Fahrdatum, das der Fahrer für eine Datei ohne Zeiten einträgt
  /// (#120). Mit ihm bleibt die Spur `planned` — die Linie ist gezeichnet
  /// —, zählt aber als gefahren: Meldungen dazu sind bestätigt, und die
  /// eigene Meldung steht zu diesem Tag wieder auf „offen".
  DateTime? rodeAt;

  /// Nur für neue, geplante Spuren, die beigesteuert oder zerlegt werden.
  bool get asksRideDate =>
      existing == null && source == RecordingSource.planned && kind != TrackKind.fragment;
}

class TrailImportScreen extends ConsumerStatefulWidget {
  const TrailImportScreen({super.key});

  @override
  ConsumerState<TrailImportScreen> createState() => _TrailImportScreenState();
}

class _TrailImportScreenState extends ConsumerState<TrailImportScreen> {
  final _candidates = <ImportCandidate>[];
  final _selected = <ImportCandidate>{};
  final _errors = <String>[];
  bool _busy = false;
  int _done = 0;
  ({int ok, int queued, int backfilled, int named, int failed})? _result;

  /// Vergleiche mit dem Geländemodell, die laufen oder liefen (#186) —
  /// das Beisteuern wartet auf sie, sonst gingen auffällige Höhen
  /// hinauf, bevor der Vergleich sie fand.
  final _terrainChecks = <Future<void>>[];
  final _checked = <ImportCandidate>{};

  /// Trails, die ich vor dem Import schon über Buddys sah und jetzt selbst
  /// belegt habe (#102): Das Ergebnis bietet an, sie zu übernehmen. Erst
  /// NACH der RPC weiß der Client, dass eine Kennung dazugehört.
  final _takeOverIds = <String>[];

  /// Fahrten aufs Gerät (#188): mit welchem Profil gefahren (null = das
  /// eingestellte), was daraus wurde und der Satz nach dem Lernen.
  RiderProfile? _rideProfile;
  ImportRidesResult? _ridesResult;
  String? _learnText;
  bool _learning = false;

  /// Der Vorschlag aus der Steigrate je Fahrt (#227), einmal gerechnet:
  /// `null` heißt „kein klarer Vorschlag", dann gilt der Knopf.
  final _profileGuesses = Map<ImportCandidate, RiderProfile?>.identity();

  RiderProfile? _guessFor(ImportCandidate c) => _profileGuesses.putIfAbsent(
      c,
      () => guessRideProfile(ridePointsOf(c.uploadTrack),
          bio: ref.read(calibratedRiderProvider(RiderProfile.bio)),
          ebike: ref.read(calibratedRiderProvider(RiderProfile.ebike))));

  /// Aufgezeichnete Fahrten der Auswahl — nur die taugen fürs Lernen.
  List<ImportCandidate> get _rideCandidates => [
        for (final c in _candidates)
          if (c.kind == TrackKind.ride && c.source == RecordingSource.import) c,
      ];

  Future<void> _saveRides() async {
    final RiderProfile profile = _rideProfile ?? ref.read(riderProfileProvider);
    final tracks = [
      for (final c in _rideCandidates)
        (name: c.track.name, points: ridePointsOf(c.uploadTrack), profile: _guessFor(c)?.name),
    ];
    setState(() {
      _busy = true;
      _ridesResult = null;
      _learnText = null;
    });
    ImportRidesResult r;
    try {
      r = await ref.read(ridesProvider.notifier).saveImported(tracks, profile: profile.name);
    } catch (e, st) {
      logError('Fahrten aus GPX speichern', e, st);
      r = (saved: 0, existed: 0, failed: tracks.length);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ridesResult = r;
    });
  }

  Future<void> _learnNow() async {
    final l = context.l10n;
    setState(() => _learning = true);
    String? text;
    try {
      text = learnResultText(l, await ref.read(riderCalibrationsProvider.notifier).learn());
    } catch (e, st) {
      logError('Aus Fahrten lernen', e, st);
    }
    if (!mounted) return;
    setState(() {
      _learning = false;
      _learnText = text ?? context.l10n.importLearnFailed;
    });
  }

  Future<void> _pick() async {
    final List<PickedFile> picked;
    try {
      picked = await ref.read(gpxPickerProvider)();
    } catch (e, st) {
      logError('GPX auswählen', e, st);
      if (mounted) setState(() => _errors.add(context.l10n.importPickFailed));
      return;
    }
    if (!mounted) return;
    final l = context.l10n;
    final files = <PickedGpx>[];
    final unreadable = <String>[];
    for (final p in picked) {
      final r = gpxFilesFrom(l, p);
      files.addAll(r.files);
      unreadable.addAll(r.errors);
    }
    // Die eigenen Aufzeichnungen, gegen die jede Spur geprüft wird: Wer
    // denselben Zip noch einmal wählt, soll keine Doppel anlegen.
    // Noch nicht geladen (Import direkt nach dem Start): abwarten. Geht
    // das Laden schief, wird ohne Abgleich importiert wie vor #16 — der
    // Server legt dann schlimmstenfalls eine zweite Aufzeichnung an.
    List<Trail> trails;
    try {
      trails = await ref.read(trailsProvider.future);
    } catch (_) {
      trails = const [];
    }
    if (!mounted) return;
    final myId = ref.read(currentUserIdProvider);
    final own = <TrailRecording>[
      for (final t in trails)
        for (final r in t.recordings)
          if (r.userId == myId) r,
    ];
    setState(() {
      _result = null;
      _ridesResult = null;
      _learnText = null;
      _errors.addAll(unreadable);
      for (final f in files) {
        try {
          for (final t in parseGpx(f.text, fallbackName: f.name)) {
            final existing = own.isEmpty ? null : findOwnRecording(t, own);
            final c = ImportCandidate(f.name, t,
                existing: existing,
                existingNameMissing: existing != null &&
                    (trails
                                .where((x) => x.id == existing.recording.trailId)
                                .firstOrNull
                                ?.myDetails
                                ?.name ??
                            '')
                        .trim()
                        .isEmpty);
            _candidates.add(c);
            if (c.contributable) _selected.add(c);
          }
        } on GpxFormatException catch (e) {
          _errors.add('${f.name}: ${e.message(l)}');
        }
      }
    });
    for (final c in _candidates) {
      if (c.checksTerrain && !_checked.contains(c)) {
        _checked.add(c);
        _terrainChecks.add(_checkTerrain(c));
      }
    }
  }

  /// Die Höhen der Datei gegen das Geländemodell (#186). Fällt der
  /// Vergleich auf, wird das Verwerfen vorgewählt. Ein Fehler ist nur
  /// „kein Vergleich" — der Import läuft wie vorher.
  Future<void> _checkTerrain(ImportCandidate c) async {
    TerrainComparison? cmp;
    try {
      final file = trackElevations(c.track.points)!;
      final model = await ref
          .read(terrainHeightsProvider)
          .at([for (final p in c.track.points) LatLng(p.lat, p.lon)]);
      cmp = model == null ? null : compareToTerrain(file, model);
    } catch (e, st) {
      logError('Höhen mit dem Geländemodell vergleichen', e, st);
    }
    if (!mounted || cmp == null) return;
    setState(() {
      c.terrain = cmp;
      if (cmp!.suspicious) _setDiscard(c, true);
    });
  }

  void _setDiscard(ImportCandidate c, bool discard) {
    c.discardHeights = discard;
    // Mit oder ohne Höhen kann die Spur anders zählen (Fahrt ⇒ Trail,
    // Nachtragen ⇒ nichts zu tun).
    if (c.contributable) {
      _selected.add(c);
    } else {
      _selected.remove(c);
    }
  }

  Future<void> _contribute() async {
    if (_selected.isEmpty) return;
    setState(() {
      _busy = true;
      _done = 0;
    });
    await Future.wait(_terrainChecks);
    if (!mounted) return;
    final l = context.l10n;
    final chosen = _candidates.where(_selected.contains).toList();
    if (chosen.isEmpty) {
      setState(() => _busy = false);
      return;
    }
    var ok = 0;
    var queued = 0;
    var backfilled = 0;
    var named = 0;
    var failed = 0;
    var limitHit = false;
    final succeeded = <ImportCandidate>{};
    final notifier = ref.read(trailsProvider.notifier);
    // Was ich bisher nur über Buddys sehe — ohne eigenen Beitrag.
    final onlyThroughBuddies = {
      for (final t in ref.read(trailsProvider).valueOrNull ?? const <Trail>[])
        if (needsTakeOver(t)) t.id,
    };
    _takeOverIds.clear();
    for (final c in chosen) {
      try {
        if (c.completesExisting) {
          // Zählt nicht ins Tageslimit, legt nichts Neues an. false heißt:
          // hatte inzwischen schon Höhen — auch das ist erledigt.
          if (c.backfill) {
            await notifier.attachElevation(c.existing!);
            backfilled++;
          }
          if (c.adoptsName &&
              await notifier.adoptName(
                  c.existing!.recording.trailId, c.track.name)) {
            named++;
          }
        } else {
          // Ohne Netz landet der Auftrag im Ausgangskorb (#30) und der
          // Trail steht als wartender auf der Karte — kein Fehler.
          final r = await notifier.contribute(c.uploadTrack, clientId: c.clientId, rodeAt: c.rodeAt);
          if (r.queued) {
            queued++;
          } else {
            ok++;
            if (onlyThroughBuddies.contains(r.trailId) && !_takeOverIds.contains(r.trailId)) {
              _takeOverIds.add(r.trailId);
            }
          }
        }
        succeeded.add(c);
      } on DailyLimitException {
        // Kein Fehlerbericht: das ist die Regel, kein Defekt. Alle weiteren
        // scheiterten genauso, also hier aufhören.
        limitHit = true;
        break;
      } catch (e, st) {
        logError('Trail beisteuern', e, st);
        failed++;
        _errors.add('${c.track.name}: ${friendlyError(l, e)}');
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    // Nur neu laden, wenn etwas auf dem Server gelandet ist — ohne Netz
    // wäre das ein Fehler über einer Liste, die den Korb längst zeigt.
    final fresh = ok + backfilled + named == 0 ||
        await notifier.reloadAfterWrite('Trails nach Import laden');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = (ok: ok, queued: queued, backfilled: backfilled, named: named, failed: failed);
      if (limitHit) {
        _errors.add(context.l10n.importDailyLimit);
      }
      // Gescheiterte bleiben angehakt stehen — ein zweiter Versuch ist
      // ein Tipp, und die Kennung des Auftrags macht ihn idempotent.
      _candidates.removeWhere(succeeded.contains);
      _selected.removeWhere(succeeded.contains);
    });
    final summary = [
      l.importSnackContributed(ok),
      if (queued > 0) l.importSnackQueued(queued),
      if (backfilled > 0) l.importSnackBackfilled(backfilled),
      if (named > 0) l.importSnackNamed(named),
      if (failed > 0) l.importFailedCount(failed),
    ].join(', ');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fresh ? summary : l.importSnackStale(summary)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final selectable =
        _candidates.where((c) => c.contributable && c.existing == null).length;
    final backfills = _candidates.where((c) => c.completesExisting).length;
    return Scaffold(
      appBar: AppBar(title: Text(l.importTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l.importIntro,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.folder_open),
            label: Text(l.importPickButton),
          ),
          for (final e in _errors)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(e, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${[
                  l.importResultContributed(_result!.ok),
                  if (_result!.queued > 0) l.importResultQueued(_result!.queued),
                  if (_result!.backfilled > 0) l.importResultBackfilled(_result!.backfilled),
                  if (_result!.named > 0) l.importResultNamed(_result!.named),
                  l.importFailedCount(_result!.failed),
                ].join(', ')}.',
                style: theme.textTheme.titleSmall,
              ),
            ),
          // Schon im Netz (#102): dieselbe Übernahme wie im Zerlege-Blatt,
          // vorbelegt aus dem, was die Buddys sagen.
          for (final id in _takeOverIds)
            if (ref.watch(trailByIdProvider(id)) case final t?)
              ListTile(
                key: ValueKey('import-takeover-$id'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.group_outlined),
                title: Text(t.displayName(l)),
                subtitle: Text(offersTakeOver(t) || t.ratingOpen
                    ? l.importTakeOverHint
                    : l.importTakenOver),
                trailing: offersTakeOver(t) || t.ratingOpen
                    ? FilledButton.tonal(
                        key: ValueKey('import-takeover-open-$id'),
                        onPressed: () => showTrailDetailsDialog(context, ref, t, takeOver: true),
                        child: Text(l.importTakeOverButton),
                      )
                    : null,
              ),
          if (_candidates.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
                backfills > 0
                    ? l.importFoundWithBackfill(_candidates.length, selectable, backfills)
                    : l.importFound(_candidates.length, selectable),
                style: theme.textTheme.titleSmall),
            for (final c in _candidates) ...[
              CheckboxListTile(
                value: _selected.contains(c),
                enabled: c.contributable && !_busy,
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _selected.add(c);
                  } else {
                    _selected.remove(c);
                  }
                }),
                title: Text(c.track.name),
                subtitle: Text(_describe(l, c)),
                controlAffinity: ListTileControlAffinity.leading,
                // Eine Fahrt geht durch das Zerlege-Blatt (Konzept 5.2),
                // auf der Karte — dort sieht man, was die Griffe tun.
                secondary: c.existing == null && c.kind == TrackKind.ride
                    ? IconButton(
                        key: ValueKey('import-split-${c.clientId}'),
                        tooltip: l.importSplitRide,
                        icon: const Icon(Icons.content_cut),
                        onPressed: _busy
                            ? null
                            : () {
                                StatefulNavigationShell.of(context).goBranch(kMapBranchIndex);
                                ref.read(mapSplitRequestProvider.notifier).state =
                                    SplitRequest.fromGpx(c.uploadTrack, rodeAt: c.rodeAt);
                              },
                      )
                    : null,
              ),
              // Höhen weit neben dem Geländemodell (#186): verwerfen
              // anbieten — vorgewählt, abwählbar.
              if (c.terrain case final t? when t.suspicious)
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: CheckboxListTile(
                    key: ValueKey('import-discard-heights-${c.clientId}'),
                    dense: true,
                    value: c.discardHeights,
                    onChanged: _busy ? null : (v) => setState(() => _setDiscard(c, v ?? false)),
                    title: Text(l.importDiscardHeights),
                    subtitle: Text(t.reason(l)),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              // Eine Datei ohne Fahrzeiten (#120): Wer sie gefahren hat,
              // trägt den Tag ein — sonst gilt sie als nur geplant.
              if (c.asksRideDate)
                Padding(
                  padding: const EdgeInsets.only(left: 56),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: ValueKey('import-ride-date-${c.clientId}'),
                      onPressed: _busy ? null : () => _pickRideDate(c),
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(c.rodeAt == null
                          ? l.importRideDate
                          : l.importRideDateChange(formatRideDate(c.rodeAt!))),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(
                    value: _selected.isEmpty ? null : _done / _selected.length),
              ),
            FilledButton.icon(
              onPressed: _busy || _selected.isEmpty ? null : _contribute,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(_selected.any((c) => c.completesExisting)
                  ? l.importAdoptButton(_selected.length)
                  : l.importContributeButton(_selected.length)),
            ),
            if (_rideCandidates.isNotEmpty && ref.watch(rideRecordingAvailableProvider))
              ..._ridesSection(theme),
          ],
        ],
      ),
    );
  }

  /// Fahrten aufs Gerät, damit das Fahrerprofil aus ihnen lernt (#188).
  /// Nur auf Android — im Browser gibt es „Meine Fahrten" nicht.
  List<Widget> _ridesSection(ThemeData theme) {
    final l = context.l10n;
    final rides = _rideCandidates;
    final n = rides.length;
    final heightless = rides.where((c) => c.uploadTrack.points.any((p) => p.ele == null)).length;
    final RiderProfile profile = _rideProfile ?? ref.watch(riderProfileProvider);
    final r = _ridesResult;
    final guesses = [for (final c in rides) _guessFor(c)];
    final unguessed = guesses.where((g) => g == null).length;
    final guessText = [
      for (final p in RiderProfile.values)
        if (guesses.where((g) => g == p).length case final k when k > 0) '$k × ${p.label(context.l10n)}',
      if (unguessed > 0 && unguessed < n) l.importRideGuessUnguessed(unguessed),
    ];
    return [
      const SizedBox(height: 24),
      Text(l.importRidesTitle, style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
        heightless > 0
            ? '${l.importRidesIntro(n)} ${l.importRidesHeightless(heightless)}'
            : l.importRidesIntro(n),
        style: theme.textTheme.bodyMedium,
      ),
      if (unguessed < n) ...[
        const SizedBox(height: 8),
        Text(
          unguessed > 0
              ? l.importRideGuessRest(guessText.join(', '))
              : l.importRideGuess(guessText.join(', ')),
          key: const ValueKey('import-ride-guess'),
          style: theme.textTheme.bodyMedium,
        ),
      ],
      // Haben alle einen Vorschlag, entscheidet der Knopf nichts mehr.
      if (unguessed > 0) ...[
        const SizedBox(height: 8),
        Text(unguessed == n ? l.importRideProfileAll : l.importRideProfileRest,
            style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<RiderProfile>(
            key: const ValueKey('import-ride-profile'),
            showSelectedIcon: false,
            // Die Namen der Räder trägt das Profil selbst (`RiderProfile.label`, aus den ARB-Dateien).
            segments: [
              ButtonSegment(
                  value: RiderProfile.bio,
                  icon: const Icon(Icons.pedal_bike_outlined),
                  label: Text(RiderProfile.bio.label(context.l10n))),
              ButtonSegment(
                  value: RiderProfile.ebike,
                  icon: const Icon(Icons.electric_bike_outlined),
                  label: Text(RiderProfile.ebike.label(context.l10n))),
            ],
            selected: {profile},
            onSelectionChanged: _busy ? null : (v) => setState(() => _rideProfile = v.single),
          ),
        ),
      ],
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        key: const ValueKey('import-save-rides'),
        onPressed: _busy ? null : _saveRides,
        icon: const Icon(Icons.directions_bike),
        label: Text(l.importSaveRides(n)),
      ),
      if (r != null) ...[
        const SizedBox(height: 8),
        Text(
          [
            l.importRidesSaved(r.saved),
            if (r.existed > 0) l.importRidesExisted(r.existed),
            if (r.failed > 0) l.importFailedCount(r.failed),
          ].join(' · '),
          key: const ValueKey('import-rides-result'),
          style: theme.textTheme.titleSmall,
        ),
        if (r.saved + r.existed > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('import-learn'),
              onPressed: _learning ? null : _learnNow,
              icon: _learning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.school_outlined),
              label: Text(l.importLearnNow),
            ),
          ),
        if (_learnText case final t?)
          Text(t, key: const ValueKey('import-learn-result'), style: theme.textTheme.bodyMedium),
      ],
    ];
  }

  /// Der Tag der Fahrt, höchstens heute; gespeichert wird 12 Uhr
  /// Ortszeit — ein Tag ohne Uhrzeit liegt so mitten in sich selbst.
  Future<void> _pickRideDate(ImportCandidate c) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: c.rodeAt ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: context.l10n.importRideDateQuestion,
    );
    if (picked == null || !mounted) return;
    setState(() => c.rodeAt = DateTime(picked.year, picked.month, picked.day, 12));
  }

  String _describe(AppLocalizations l, ImportCandidate c) {
    final parts = <String>[formatLength(c.lengthM)];
    final existing = c.existing;
    if (existing != null) {
      parts.add(c.discardHeights
          ? (c.adoptsName
              ? l.importExistingDiscardAdopt
              : l.importExistingDiscard)
          : c.backfill && c.adoptsName
          ? l.importExistingBackfillAdopt
          : c.backfill
              ? l.importExistingBackfill
              : c.adoptsName
                  ? l.importExistingAdopt
                  : existing.recording.ele != null
                      ? l.importExisting
                      : l.importExistingNoHeights);
      return parts.join(' · ');
    }
    final el = c.elevation;
    if (el != null) parts.add(formatElevation(l, el));
    if (c.discardHeights) parts.add(l.importWithoutFileHeights);
    parts.add(switch (c.source) {
      RecordingSource.planned => c.rodeAt == null
          ? l.importSourcePlanned
          : l.importSourceDrawnRidden(formatRideDate(c.rodeAt!)),
      RecordingSource.import => l.importSourceRecorded,
      RecordingSource.app => l.importSourceRecorded,
    });
    parts.add(switch (c.kind) {
      TrackKind.trail => l.importKindTrail,
      TrackKind.ride => l.importKindRide,
      TrackKind.fragment => l.importKindFragment,
    });
    return parts.join(' · ');
  }
}
