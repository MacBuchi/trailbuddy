import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../core/settings.dart';
import '../../data/outbox.dart';
import '../../data/outbox_runner.dart';
import '../../data/providers.dart';
import '../../data/trail_cache.dart';
import '../../data/trail_sharing.dart';
import '../../data/trail_repository.dart';
import '../../models/trail.dart';
import '../map/map_view/map_view.dart' show MapViewBounds;
import 'elevation_backfill.dart';
import 'gpx.dart';
import 'outbox_providers.dart';
import 'still_valid.dart';
import 'trail_geometry.dart';
import 'trail_list.dart';

final trailRepositoryProvider = Provider<TrailRepository>(
    (ref) => SupabaseTrailRepository(ref.watch(supabaseClientProvider)));

/// Was aus einem Schreibvorgang geworden ist (#30).
enum WriteOutcome {
  /// Auf dem Server, Liste frisch.
  done,

  /// Auf dem Server, aber das Neuladen scheiterte — die Liste ist alt
  /// ([staleAfterWriteHint]).
  doneStale,

  /// Kein Netz: liegt im Ausgangskorb und geht, sobald wieder Verbindung
  /// besteht.
  queued,
}

/// Ergebnis von [TrailsNotifier.contribute]: die Trail-Kennung — bei
/// [queued] die des Auftrags, unter der der wartende Trail auf der Karte
/// steht.
typedef ContributeResult = ({String trailId, bool queued});

/// Alle Trails meines Netzes — eigene Belege plus die meiner Buddys, so
/// wie die RLS sie liefert, dazu die Aufträge aus dem Ausgangskorb
/// (#30) als wartende Trails. Zwei Abfragen, gruppiert im Client.
class TrailsNotifier extends AsyncNotifier<List<Trail>>
    with ReadAfterWrite<List<Trail>> {
  /// Der letzte erfolgreiche Stand vom Server — die Grundlage, auf die
  /// der Korb gelegt wird, ohne dafür neu zu laden.
  List<Trail> _server = const [];

  /// Aufträge, die gerade UNTERWEGS sind (#183): Sie stehen schon da wie
  /// wartende, bis Schreiben UND Neuladen durch sind — sonst erschien ein
  /// gesetzter S-Grad erst nach mehreren Abrufen, mit einem Balken nach
  /// Sekunden. Kein optimistisches Update an der Regel vorbei: Was hier
  /// steht, ist als „wird übertragen" gekennzeichnet, und ein Fehler
  /// nimmt es sichtbar zurück.
  final List<OutboxJob> _sending = [];

  /// Für wen schon einmal etwas gezeigt wurde. Nur der ERSTE Abruf je
  /// Konto darf die Kopie vorziehen ([fetchWithCacheQuick]); ein
  /// Neuladen nach dem Schreiben muss sagen, ob es frisch ist.
  String? _shownFor;

  /// Zählt die Abrufe — ein später Netzstand gilt nur für den Abruf, der
  /// ihn angestoßen hat.
  int _builds = 0;

  @override
  Future<List<Trail>> build() async {
    final myId = ref.watch(currentUserIdProvider);
    if (myId == null) return const [];
    final generation = ++_builds;
    // Ändert sich der Korb, wird NICHT neu vom Server geladen — ein
    // Auftrag entsteht ja gerade, weil es kein Netz gibt. Der Korb wird
    // auf den letzten bekannten Stand gelegt.
    ref.listen(outboxJobsProvider, (_, next) {
      final jobs = next.valueOrNull;
      if (jobs != null) _applyPending(jobs, myId);
    });
    final repo = ref.watch(trailRepositoryProvider);
    Future<TrailSnapshot> fetch() async {
      final results = await Future.wait([
        repo.fetchRecordings(),
        repo.fetchDetails(),
        repo.fetchNotes(),
        repo.fetchReports(),
      ]);
      // Was sich nicht geändert hat, bleibt dasselbe Objekt — auch für die
      // Kopie auf dem Gerät, die einen unveränderten Stand dann nicht neu
      // schreibt (`trail_sharing.dart`).
      return shareSnapshot(_snapshotFor(myId), (
        recordings: results[0] as List<TrailRecording>,
        details: results[1] as List<TrailDetails>,
        notes: results[2] as List<TrailNote>,
        reports: results[3] as List<TrailReport>,
      ));
    }

    // Netz zuerst, ohne Empfang die Kopie vom letzten Mal (#32) — ein
    // Serverfehler bleibt sichtbar, `fetchWithCache` liest die Kopie nur
    // bei `looksOffline`. Beim ersten Abruf wartet die Karte darauf nur
    // kurz (#183): Ohne Empfang kam die Kopie sonst erst nach den
    // Wiederholungen von postgrest, rund 7 s.
    final cache = ref.read(trailCacheProvider);
    final now = DateTime.now();
    final TrailSnapshotResult result;
    var waiting = false;
    if (_shownFor == myId) {
      result = await fetchWithCache(fetch: fetch, cache: cache, uid: myId, now: now);
    } else {
      bool current() => generation == _builds;
      result = await fetchWithCacheQuick(
        fetch: fetch,
        cache: cache,
        uid: myId,
        now: now,
        patience: ref.read(noConnectivityProvider) ? Duration.zero : kTrailsNetworkPatience,
        onLate: (fresh) {
          if (!current()) return;
          ref.read(trailsAwaitNetworkProvider.notifier).state = false;
          ref.read(trailsCachedAtProvider.notifier).set(null);
          _server = _fromSnapshot(fresh, myId);
          _fetchedAt = now;
          state = AsyncData(_compose(myId));
        },
        onLateOffline: () {
          if (current()) ref.read(trailsAwaitNetworkProvider.notifier).state = false;
        },
        onStillWaiting: () => waiting = true,
        onLateError: (error, stackTrace) {
          if (!current()) return;
          ref.read(trailsAwaitNetworkProvider.notifier).state = false;
          logError('Trails laden', error, stackTrace);
          state = AsyncError<List<Trail>>(error, stackTrace).copyWithPrevious(state);
        },
      );
    }
    _shownFor = myId;
    ref.read(trailsCachedAtProvider.notifier).set(result.cachedAt);
    // Kam die Kopie, weil das Netz zu langsam war, läuft es noch — die
    // Hinweise sagen dann nicht „Kein Empfang".
    if (generation == _builds) ref.read(trailsAwaitNetworkProvider.notifier).state = waiting;
    _server = _fromSnapshot(result.snapshot, myId);
    // Nur ein frischer Stand taugt als Grundlage für [_rereadAfterWrite];
    // eine Kopie vom letzten Mal lädt nach dem Schreiben ganz neu.
    _fetchedAt = result.cachedAt == null ? now : null;
    final cached = ref.read(outboxJobsProvider).valueOrNull;
    final List<OutboxJob> jobs = cached ?? await ref.read(outboxJobsProvider.future);
    return _composeWith(jobs, myId);
  }

  /// Der Server-Stand hinter [_server], für das Konto [_snapshotUid] —
  /// die Grundlage, gegen die ein neuer Abruf seine unveränderten Teile
  /// tauscht.
  TrailSnapshot? _snapshot;
  String? _snapshotUid;

  TrailSnapshot? _snapshotFor(String myId) => _snapshotUid == myId ? _snapshot : null;

  /// Wann [_snapshot] zuletzt GANZ vom Server kam — null, wenn er aus der
  /// Kopie stammt. Mit diesem Zeitpunkt schreibt [_rereadAfterWrite] die
  /// Kopie neu: Die Aufzeichnungen darin sind so alt, nicht jünger.
  DateTime? _fetchedAt;

  /// Read-after-write für das, was geschrieben wurde, statt für das ganze
  /// Netz (Feldbericht 2026-10-02). Ein Stern lud bis 0.82.x jede Linie
  /// neu — bei einem großen Netz Megabytes über die Leitung und Sekunden
  /// auf dem Haupt-Thread, mehrmals je Speichern. Die Aufzeichnungen
  /// ändert ein Beitrag, eine Meldung oder ein Hinweis nicht; sie bleiben
  /// stehen, bis das Netz ohnehin neu lädt.
  ///
  /// Dieselbe Zusage wie [reloadAfterWrite]: wirft nicht, `false` heißt
  /// „geschrieben, aber die Anzeige ist alt", der Fehler geht mit [what]
  /// nach `error_reports`, und der Zustand steht auf `AsyncError` mit dem
  /// Wert darunter. Ohne frischen Server-Stand (Kopie, anderes Konto)
  /// lädt es ganz neu.
  Future<bool> _rereadAfterWrite(String what,
      {bool details = false, bool notes = false, bool reports = false}) async {
    final myId = ref.read(currentUserIdProvider);
    final fetchedAt = _fetchedAt;
    if (myId == null || fetchedAt == null || _snapshotFor(myId) == null || !state.hasValue) {
      return reloadAfterWrite(what);
    }
    final repo = ref.read(trailRepositoryProvider);
    try {
      final fresh = await Future.wait<List<Object>>([
        if (details) repo.fetchDetails(),
        if (notes) repo.fetchNotes(),
        if (reports) repo.fetchReports(),
      ]);
      // Erst NACH dem Abruf auf den Stand legen: Ein Neuladen dazwischen
      // hat ihn vielleicht schon ersetzt.
      final base = _snapshotFor(myId);
      if (base == null || ref.read(currentUserIdProvider) != myId) return await reloadAfterWrite(what);
      var i = 0;
      final next = (
        recordings: base.recordings,
        details: details ? fresh[i++] as List<TrailDetails> : base.details,
        notes: notes ? fresh[i++] as List<TrailNote> : base.notes,
        reports: reports ? fresh[i++] as List<TrailReport> : base.reports,
      );
      _server = _fromSnapshot(next, myId);
      unawaited(ref.read(trailCacheProvider).write(uid: myId, snapshot: _snapshot!, savedAt: fetchedAt));
      state = AsyncData(_compose(myId));
      return true;
    } catch (error, stackTrace) {
      logError(what, error, stackTrace);
      state = AsyncError<List<Trail>>(error, stackTrace).copyWithPrevious(state);
      return false;
    }
  }

  List<Trail> _fromSnapshot(TrailSnapshot s, String myId) {
    final shared = shareSnapshot(_snapshotFor(myId), s);
    final previous = _snapshotUid == myId ? _server : const <Trail>[];
    _snapshot = shared;
    _snapshotUid = myId;
    return buildTrails(
      recordings: shared.recordings,
      details: shared.details,
      notes: shared.notes,
      reports: shared.reports,
      myId: myId,
      previous: previous,
    );
  }

  /// Server-Stand plus Korb plus, was gerade unterwegs ist. Ein Auftrag,
  /// der schon im Korb liegt, zählt dort — einen Augenblick lang ist er
  /// beides, und eine Meldung stünde sonst doppelt da.
  List<Trail> _composeWith(List<OutboxJob> jobs, String myId) {
    final queued = {for (final j in jobs) j.id};
    final sending = [for (final j in _sending) if (!queued.contains(j.id)) j];
    return withPendingJobs(_server, [...jobs, ...sending],
        myId: myId, sending: {for (final j in sending) j.id});
  }

  List<Trail> _compose(String myId) =>
      _composeWith(ref.read(outboxJobsProvider).valueOrNull ?? const [], myId);

  void _applyPending(List<OutboxJob> jobs, String myId) {
    // Ohne je einen Server-Stand und ohne Trail-Aufträge gibt es nichts zu
    // zeigen — der Fehlerzustand bleibt dann stehen. Feedback (#218) zählt
    // nicht: Es steht auf keiner Karte.
    if (!state.hasValue && !jobs.any((j) => j is! FeedbackJob)) return;
    state = AsyncData(_composeWith(jobs, myId));
  }

  /// Legt [job] als „unterwegs" auf die Anzeige (#183) — sofort, vor dem
  /// ersten Byte im Netz.
  void _beginSending(OutboxJob job, String myId) {
    _sending.add(job);
    if (state.hasValue) state = AsyncData(_compose(myId));
  }

  /// Nimmt [job] wieder herunter. Ein Fehlerzustand des Neuladens bleibt
  /// stehen ([reloadAfterWrite] hat ihn gesetzt), nur der Wert darunter
  /// ändert sich.
  void _endSending(OutboxJob job, String myId) {
    if (!_sending.remove(job) || !state.hasValue) return;
    final next = AsyncData(_compose(myId));
    final current = state;
    state = current is AsyncError<List<Trail>>
        ? AsyncError<List<Trail>>(current.error, current.stackTrace).copyWithPrevious(next)
        : next;
  }

  /// Steuert eine Spur bei: vereinfacht (mit Höhe, siehe [simplify]),
  /// schickt Linie und Höhen an die RPC und legt den eigenen Beitrag mit
  /// dem Namen aus der Datei an. Ohne Netz wandert der Auftrag in den
  /// Ausgangskorb (#30) und der Trail steht sofort als wartender auf der
  /// Karte. Wirft, wenn das SCHREIBEN aus einem anderen Grund scheitert;
  /// ein gescheitertes Neuladen meldet der Rückgabewert von
  /// [reloadAfterWrite] beim Aufrufer.
  ///
  /// [source] steht fest, wenn die Spur aus der eigenen Aufzeichnung
  /// kommt (`app`, Zerlege-Blatt #29); sonst entscheidet die Datei
  /// ([sourceOf]). [grade] und [traits] gehen mit dem Namen in den
  /// eigenen Beitrag.
  ///
  /// [rodeAt] ist das Fahrdatum, das der Fahrer für eine Datei ohne Zeiten
  /// eingetragen hat (#120): Sie bleibt `planned` (die Linie ist
  /// gezeichnet), zählt aber als gefahren — `recorded_at` trägt es.
  Future<ContributeResult> contribute(GpxTrack track,
      {String? clientId, RecordingSource? source, int? grade,
      Set<TrailTrait> traits = const {}, int? rating, DateTime? rodeAt}) async {
    final repo = ref.read(trailRepositoryProvider);
    final myId = ref.read(currentUserIdProvider);
    if (myId == null) throw const NotSignedInException();
    final pts = simplify(track.points);
    source ??= sourceOf(track.points);
    final recordedAt =
        source == RecordingSource.planned ? rodeAt?.toUtc() : track.points.first.time;
    // Der Auftrag entsteht VOR dem Sendeversuch, mit seiner Kennung: So
    // trägt schon der erste Versuch die `client_id`, und ein Abriss nach
    // dem Insert legt beim Nachholen keine zweite Aufzeichnung an.
    final job = ContributeJob(
      id: clientId ?? newClientId(),
      createdAt: DateTime.now().toUtc(),
      coords: flatCoords(pts),
      eles: trackElevations(pts),
      source: source,
      recordedAt: recordedAt,
      name: track.name,
      link: track.link,
      grade: grade,
      traits: traits,
      rating: rating,
    );
    try {
      final trailId = await repo.contribute(
        coords: job.coords,
        eles: job.eles,
        source: job.source,
        recordedAt: job.recordedAt,
        clientId: job.id,
      );
      await adoptDetails(trailId, track.name,
          grade: grade, traits: traits, link: track.link, rating: rating);
      return (trailId: trailId, queued: false);
    } catch (error, stackTrace) {
      await _queueIfOffline(error, stackTrace, job);
      return (trailId: job.id, queued: true);
    }
  }

  /// Nur `looksOffline` führt in den Korb; alles andere wirft weiter,
  /// samt dem Fall, dass der Korb selbst nicht schreiben kann.
  Future<void> _queueIfOffline(Object error, StackTrace stackTrace, OutboxJob job) async {
    if (!looksOffline(error)) Error.throwWithStackTrace(error, stackTrace);
    try {
      await ref.read(outboxJobsProvider.notifier).append(job);
    } catch (_) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Arbeitet den Ausgangskorb ab und lädt danach neu. Angestoßen beim
  /// Start, bei der Rückkehr der Verbindung und auf Tippen im Banner;
  /// Doppelläufe hält der Runner auseinander.
  Future<OutboxRunResult> sendOutbox() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return (sent: 0, remaining: 0, failed: 0);
    // Den Korb ABWARTEN, nicht den Zähler lesen: Beim Kartenstart ist er
    // noch nicht geladen, und ein Zähler von 0 hieße dann „nichts zu tun".
    final jobs = await ref.read(outboxJobsProvider.future);
    if (jobs.isEmpty) return (sent: 0, remaining: 0, failed: 0);
    final result = await ref.read(outboxRunnerProvider).run(uid: uid);
    await ref.read(outboxJobsProvider.notifier).refresh();
    // Neu geladen wird nur, wenn ein TRAIL-Auftrag hinausging: Ein
    // nachgeholter Wunsch (#218) ändert am Netz nichts, und ein ganzes
    // Neuladen kostet die Karte (siehe „Speichern ohne Neuladen des Netzes").
    final trailJobsLeft =
        (ref.read(outboxJobsProvider).valueOrNull ?? const []).where((j) => j is! FeedbackJob).length;
    final trailJobsSent = jobs.where((j) => j is! FeedbackJob).length > trailJobsLeft;
    if (result.sent > 0 && trailJobsSent) {
      await reloadAfterWrite('Trails nach dem Ausgangskorb laden');
    }
    return result;
  }

  /// Übernimmt den Namen aus der Datei als eigenen Namen des Trails —
  /// gekürzt auf [kTrailNameMaxLength]. Ein vorhandener eigener Name
  /// bleibt: Der Import überschreibt nicht, was jemand bewusst eingetragen
  /// hat. Kein Neuladen hier (der Import lädt einmal am Ende). Gibt
  /// zurück, ob geschrieben wurde.
  Future<bool> adoptName(String trailId, String fileName) => adoptDetails(trailId, fileName);

  /// Wie [adoptName], dazu S-Grad und Charakter aus dem Zerlege-Blatt
  /// (#29, #72). Der Grad wird immer gesetzt — wer ihn gewählt hat, hat
  /// ihn gerade gefahren. Die Merkmale kommen DAZU, nichts wird
  /// weggenommen: Das Blatt zeigt den bisherigen eigenen Charakter nicht,
  /// und legt der Server die Spur auf einen Trail, den ich schon
  /// beschrieben habe, soll eine Abfahrt nicht still meine Angabe
  /// ersetzen. EIN Schreibvorgang für alles. Der [link] aus der Datei
  /// (#103) kommt wie der Name nur, wenn noch keiner steht — ebenso die
  /// [rating] beim Übernehmen eines Buddy-Trails (#102). Ein fremder Name
  /// ([fileName] ist dann der angezeigte) wird so zum eigenen, wenn noch
  /// keiner steht: Danach hängt nichts mehr am Beitrag des Buddys.
  Future<bool> adoptDetails(String trailId, String fileName,
      {int? grade, Set<TrailTrait> traits = const {}, String? link, int? rating}) async {
    final myId = ref.read(currentUserIdProvider);
    if (myId == null) throw const NotSignedInException();
    final name = clampTrailName(fileName);
    final existing = state.valueOrNull
        ?.where((t) => t.id == trailId)
        .firstOrNull
        ?.myDetails;
    final keepName = existing != null && (existing.name ?? '').trim().isNotEmpty;
    final writesName = name.isNotEmpty && !keepName;
    final addsTraits = !(existing?.traits ?? const {}).containsAll(traits);
    final writesLink = link != null && (existing?.link ?? '').isEmpty;
    final writesRating = rating != null && existing?.rating == null;
    if (!writesName && grade == null && !addsTraits && !writesLink && !writesRating) return false;
    var details = existing ?? TrailDetails(trailId: trailId, userId: myId);
    if (writesName) details = details.copyWith(name: name);
    if (writesLink) details = details.copyWith(link: link);
    if (writesRating) details = details.copyWith(rating: rating);
    if (grade != null) details = details.copyWith(grade: grade);
    if (addsTraits) details = details.copyWith(traits: {...details.traits, ...traits});
    await ref.read(trailRepositoryProvider).saveDetails(details);
    return true;
  }

  /// Meldet [status] und/oder [condition] (#101, `report_trail`). Ein
  /// [note] geht als Hinweis mit — der Hinweis sagt WARUM. Ohne Netz
  /// wartet beides im Ausgangskorb, mit der Zeit des Meldens; [onSite]
  /// ist dann schon geprüft (die Position von damals zählt, nicht die beim
  /// Senden).
  ///
  /// [at] ist der Zeitpunkt der Angabe, wenn er nicht jetzt ist — eine
  /// Antwort unterwegs (#116) geht erst beim Beenden der Fahrt hinaus.
  Future<WriteOutcome> report(String trailId,
      {TrailStatus? status,
      int? condition,
      required bool onSite,
      String? note,
      DateTime? at}) async {
    final repo = ref.read(trailRepositoryProvider);
    final myId = ref.read(currentUserIdProvider);
    if (myId == null) throw const NotSignedInException();
    final text = note?.trim() ?? '';
    final job = ReportJob(
      id: newClientId(),
      createdAt: (at ?? DateTime.now()).toUtc(),
      trailId: trailId,
      status: status,
      condition: condition,
      onSite: onSite,
      note: text.isEmpty ? null : text,
    );
    _beginSending(job, myId);
    try {
      try {
        await repo.report(
            trailId: trailId,
            status: status,
            condition: condition,
            onSite: onSite,
            reportedAt: job.createdAt,
            clientId: job.id);
        if (text.isNotEmpty) await repo.addNote(trailId: trailId, body: text);
      } catch (error, stackTrace) {
        await _queueIfOffline(error, stackTrace, job);
        return WriteOutcome.queued;
      }
      return await _rereadAfterWrite('Melden', reports: true, notes: text.isNotEmpty)
          ? WriteOutcome.done
          : WriteOutcome.doneStale;
    } finally {
      _endSending(job, myId);
    }
  }

  /// Speichert den eigenen Beitrag. Ohne Netz wartet er im Ausgangskorb
  /// (#30).
  Future<WriteOutcome> saveDetails(TrailDetails details) async {
    final repo = ref.read(trailRepositoryProvider);
    final myId = ref.read(currentUserIdProvider);
    if (myId == null) throw const NotSignedInException();
    final job = DetailsJob(id: newClientId(), createdAt: DateTime.now().toUtc(), details: details);
    // Sofort zeigen, was gesetzt wurde (#183) — verblasst, bis Schreiben
    // und Neuladen durch sind. Ohne Netz übernimmt der Korb nahtlos: Der
    // Auftrag liegt dort, bevor er hier heruntergenommen wird.
    _beginSending(job, myId);
    try {
      try {
        await repo.saveDetails(details);
      } catch (error, stackTrace) {
        await _queueIfOffline(error, stackTrace, job);
        return WriteOutcome.queued;
      }
      return await _rereadAfterWrite('Trail-Beitrag speichern', details: true)
          ? WriteOutcome.done
          : WriteOutcome.doneStale;
    } finally {
      _endSending(job, myId);
    }
  }

  Future<bool> addNote(String trailId, String body) async {
    await ref
        .read(trailRepositoryProvider)
        .addNote(trailId: trailId, body: body.trim());
    return _rereadAfterWrite('Hinweis speichern', notes: true);
  }

  Future<bool> deleteNote(String id) async {
    await ref.read(trailRepositoryProvider).deleteNote(id);
    return _rereadAfterWrite('Hinweis löschen', notes: true);
  }

  /// Den eigenen Beitrag zurückziehen. Kein Ausgangskorb: Ein Löschauftrag,
  /// der Tage später zuschlägt, wäre schlimmer als eine Fehlermeldung
  /// (PilzBuddy #267) — ohne Netz scheitert es sichtbar.
  Future<bool> withdraw(String trailId) async {
    await ref.read(trailRepositoryProvider).withdraw(trailId);
    return reloadAfterWrite('Beitrag zurückziehen');
  }

  /// Höhen einer eigenen Aufzeichnung nachtragen (#16). Kein Neuladen
  /// hier: Der Import lädt einmal am Ende, nicht nach jeder Datei.
  Future<bool> attachElevation(ExistingRecording existing) {
    final eles = existing.eles;
    if (eles == null) throw StateError('Datei ohne vollständige Höhen');
    return ref.read(trailRepositoryProvider).attachElevation(
          recordingId: existing.recording.id,
          coords: flatCoords(existing.points),
          eles: eles,
        );
  }
}

final trailsProvider =
    AsyncNotifierProvider<TrailsNotifier, List<Trail>>(TrailsNotifier.new);

/// Die Kopie des Netzes (#32): Datei auf Android, im Browser bewusst
/// keine (IndexedDB wie PilzBuddy #385 ist ein eigener Schritt).
final trailCacheProvider =
    Provider<TrailCache>((ref) => kIsWeb ? const NoTrailCache() : FileTrailCache());

/// Wann der angezeigte Stand geholt wurde — `null`, solange er frisch aus
/// dem Netz kommt. Karte und Liste sagen es, sonst hielte man einen alten
/// Stand für den aktuellen.
class TrailsCachedAtNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime? at) => state = at;
}

final trailsCachedAtProvider =
    NotifierProvider<TrailsCachedAtNotifier, DateTime?>(TrailsCachedAtNotifier.new);

/// Die Kopie steht, weil das Netz beim Start zu langsam war — es läuft
/// aber noch (#183). Dann sagen Karte und Liste nicht „Kein Empfang",
/// sondern dass gleich der frische Stand kommt.
final trailsAwaitNetworkProvider = StateProvider<bool>((ref) => false);

/// Die Wiedervorlage (#30). Den Namen übernimmt sie über den Notifier,
/// der den Bestand kennt und keinen bewusst eingetragenen überschreibt.
final outboxRunnerProvider = Provider<OutboxRunner>((ref) => OutboxRunner(
      repository: ref.watch(trailRepositoryProvider),
      feedback: ref.watch(feedbackRepositoryProvider),
      outbox: ref.watch(outboxProvider),
      adoptDetails: (trailId, name, grade, traits, link, rating) => ref
          .read(trailsProvider.notifier)
          .adoptDetails(trailId, name, grade: grade, traits: traits, link: link, rating: rating),
    ));

final trailByIdProvider = Provider.family<Trail?, String>((ref, id) =>
    ref.watch(trailsProvider).valueOrNull?.where((t) => t.id == id).firstOrNull);

/// Die Hinweise, die auf DIESEM Gerät schon im Trail-Blatt zu sehen
/// waren (#7): Sie heben den Trail in Karte und Liste nicht mehr hervor.
/// Gerätelokal wie der Orte-Filter — gelesen ist eine Frage des Geräts,
/// nicht des Kontos, und der Server erfährt nicht, wer was gelesen hat.
class SeenNotesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {...?ref.read(settingsProvider).seenNoteIds};

  /// Merkt [ids] als gesehen. Gespeichert wird nur, was es noch gibt
  /// ([known]: alle geladenen Hinweise) — so wächst die Liste nicht mit
  /// jedem gelöschten Hinweis weiter.
  void markSeen(Iterable<String> ids, {required Set<String> known}) {
    final next = {...state, ...ids}.where(known.contains).toSet();
    if (next.length == state.length && next.containsAll(state)) return;
    state = next;
    unawaited(ref
        .read(settingsProvider)
        .setSeenNoteIds(next.toList())
        .catchError((Object e, StackTrace s) => logError('Gelesene Hinweise merken', e, s)));
  }
}

final seenNotesProvider =
    NotifierProvider<SeenNotesNotifier, Set<String>>(SeenNotesNotifier.new);

/// „Weiß nicht" bei „Noch gültig?" (#119): Kennung der Angabe → bis wann
/// sie ruht. Gerätelokal wie [seenNotesProvider].
class StillValidSnoozesNotifier extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() =>
      decodeStillValidSnoozes(ref.read(settingsProvider).stillValidSnoozes);

  void snooze(String reportId, {DateTime? now}) {
    final at = (now ?? DateTime.now()).toUtc();
    state = {...state, reportId: at.add(kStillValidSnooze)};
    unawaited(ref
        .read(settingsProvider)
        .setStillValidSnoozes(encodeStillValidSnoozes(state, now: at))
        .catchError((Object e, StackTrace s) => logError('„Weiß nicht" merken', e, s)));
  }
}

final stillValidSnoozesProvider =
    NotifierProvider<StillValidSnoozesNotifier, Map<String, DateTime>>(StillValidSnoozesNotifier.new);

/// Die offenen Fragen „Noch gültig?" über alle geladenen Trails — für den
/// Zähler im Profil und die Seite. Ohne geladene Trails keine.
final stillValidQuestionsProvider = Provider<List<StillValidQuestion>>((ref) {
  final trails = ref.watch(trailsProvider).valueOrNull ?? const <Trail>[];
  return stillValidQuestions(trails,
      now: DateTime.now(), snoozed: ref.watch(stillValidSnoozesProvider));
});

/// Wunsch der Liste an die Karte: diesen Trail zeigen (Muster PilzBuddy
/// #345, erst Reiter wechseln, dann Wunsch stellen).
/// Sortierung der Liste (#66) — nur für die Liste, für die Sitzung.
final trailSortProvider = StateProvider<TrailSort>((ref) => TrailSort.recent);

/// Der Trail-Filter (#66) — für Liste UND Karte (seit 0.33.0), für die
/// Sitzung: Wer die App neu öffnet, sieht wieder alles.
final trailListFilterProvider = StateProvider<TrailListFilter>((ref) => const TrailListFilter());

/// „Auf der Karte" (#222): Die Liste zeigt nur, was im Ausschnitt der
/// Karte liegt — nur für die Liste, für die Sitzung.
final trailListOnMapProvider = StateProvider<bool>((ref) => false);

/// Der Ausschnitt der Karte beim letzten Stillstand — geschrieben von der
/// Karte, gelesen von „Auf der Karte". `null`, solange sie nie stand.
final mapVisibleBoundsProvider = StateProvider<MapViewBounds?>((ref) => null);

final mapFocusTrailProvider = StateProvider<String?>((ref) => null);

/// UUID v4 aus `Random.secure()` — die Kennung des Auftrags, damit ein
/// Wiederholversuch nach abgerissener Antwort keinen zweiten Beleg anlegt
/// (Idempotenz in `contribute_recording`, PilzBuddy Patch 016).
String newClientId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final h = List.generate(16, hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
