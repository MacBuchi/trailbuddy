import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/errors.dart';
import 'package:trailbuddy/data/trail_repository.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/features/trails/trail_link.dart';
import 'package:trailbuddy/features/trails/trail_merge_candidates.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';
import 'package:trailbuddy/models/trail.dart';
import 'package:trailbuddy/models/trail_merge.dart';

/// Eine Zeile aus `app_internal.trail_aliases` (Patch 019).
typedef FakeAlias = ({String userId, String trailId, String sameAs, bool reversed, DateTime createdAt});

/// Spiegelt die RLS der Trail-Tabellen (Konzept 3): sichtbar ist ein
/// Beleg, wenn er mir gehört oder einem Buddy, dessen Beitrag zu diesem
/// Trail nicht `private` ist; ein Hinweis (Patch 005) und eine Meldung
/// (Patch 013) zusätzlich nur, wenn ich den Trail sehe. Den Abgleich ersetzt eine Vorgabe
/// ([matcher]) — die Geometrie prüft `tool/matcher_check.sql` gegen die
/// echte Datenbank, hier geht es um die App drumherum.
class FakeTrailRepository implements TrailRepository {
  FakeTrailRepository({required this.myId, this.areFriends});

  final String Function() myId;
  final bool Function(String a, String b)? areFriends;

  final recordings = <TrailRecording>[];
  final details = <TrailDetails>[];
  final usernames = <String, String>{};

  /// Liefert die Trail-Kennung, an die eine beigesteuerte Linie gehängt
  /// wird; `null` heißt neuer Trail.
  String? Function(List<double> coords)? matcher;

  int contributeCalls = 0;

  /// Die Höhen des letzten Aufrufs — so, wie sie an die RPC gingen.
  List<double>? lastEles;

  /// Spiegelt `match_params().daily_limit`: so viele eigene Aufzeichnungen
  /// nimmt der Server an, danach wirft das echte Repository
  /// [DailyLimitException] (SQLSTATE 54000). `null` = kein Limit.
  int? dailyLimit;
  Object? failNextContribute;
  Object? failFetch;

  /// Hält den nächsten Abruf an, bis das Future erfüllt ist — für den
  /// Fall „Fokus-Wunsch, bevor die Trails da sind" (Push, Kaltstart).
  Future<void>? fetchGate;

  bool _visible(String userId, String trailId) {
    final me = myId();
    if (userId == me) return true;
    if (!(areFriends?.call(me, userId) ?? false)) return false;
    final d = details.where((x) => x.userId == userId && x.trailId == trailId).firstOrNull;
    return d == null || d.visibility == TrailVisibility.buddies;
  }

  /// Wie oft die Linien abgerufen wurden — das Teure eines Neuladens.
  int recordingFetches = 0;

  @override
  Future<List<TrailRecording>> fetchRecordings() async {
    recordingFetches++;
    final gate = fetchGate;
    if (gate != null) {
      fetchGate = null;
      await gate;
    }
    if (failFetch != null) throw failFetch!;
    return [for (final r in recordings) if (_visible(r.userId, r.trailId)) r];
  }

  @override
  Future<List<TrailDetails>> fetchDetails() async {
    if (failFetch != null) throw failFetch!;
    final me = myId();
    return [
      for (final d in details)
        if (d.userId == me ||
            ((areFriends?.call(me, d.userId) ?? false) &&
                d.visibility == TrailVisibility.buddies))
          TrailDetails(
            trailId: d.trailId,
            userId: d.userId,
            username: usernames[d.userId],
            name: d.name,
            description: d.description,
            grade: d.grade,
            traits: d.traits,
            rating: d.rating,
            link: d.link,
            visibility: d.visibility,
            updatedAt: d.updatedAt,
          ),
    ];
  }

  @override
  Future<String> contribute({
    required List<double> coords,
    List<double>? eles,
    required RecordingSource source,
    DateTime? recordedAt,
    required String clientId,
  }) async {
    contributeCalls++;
    if (failNextContribute != null) {
      final e = failNextContribute!;
      failNextContribute = null;
      throw e;
    }
    final me = myId();
    final existing = recordings
        .where((r) => r.userId == me && r.id == 'rec-$clientId')
        .firstOrNull;
    if (existing != null) return existing.trailId;
    // Wie in der RPC: erst die Wiederholung beantworten, dann das Limit.
    if (dailyLimit != null &&
        recordings.where((r) => r.userId == me).length >= dailyLimit!) {
      throw const DailyLimitException();
    }
    final trailId = matcher?.call(coords) ?? 'trail-${newClientId()}';
    final points = <LatLng>[
      for (var i = 0; i + 1 < coords.length; i += 2) LatLng(coords[i + 1], coords[i]),
    ];
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += haversineM(points[i - 1].latitude, points[i - 1].longitude,
          points[i].latitude, points[i].longitude);
    }
    if (length < kTrailMinLengthM) {
      throw StateError('Linie kürzer als ${kTrailMinLengthM.round()} m');
    }
    // Wie die RPC: eine Höhe je Punkt oder keine (SQLSTATE 22023).
    if (eles != null && eles.length != points.length) {
      throw StateError('Höhen: ${eles.length} Werte für ${points.length} Punkte');
    }
    lastEles = eles;
    recordings.add(TrailRecording(
      id: 'rec-$clientId',
      trailId: trailId,
      userId: me,
      source: source,
      recordedAt: recordedAt,
      reversed: false,
      quality: switch (source) {
        RecordingSource.app => 0.6,
        RecordingSource.import => 0.4,
        RecordingSource.planned => 0.1,
      },
      createdAt: DateTime.now(),
      points: points,
      lengthM: length,
      ele: eles,
    ));
    // Wie Schritt 7 der RPC: Beitrag anlegen, falls er fehlt.
    if (!details.any((d) => d.trailId == trailId && d.userId == me)) {
      details.add(TrailDetails(trailId: trailId, userId: me));
    }
    // Wie Schritt 8 (Patch 013): Die eigene Meldung zum FAHRDATUM auf
    // „offen" — nur wenn es eine gibt, sie älter ist und nicht schon ein
    // bestätigtes „offen"; nie bei `planned` (Patch 011) — außer mit
    // eingetragenem Fahrdatum (Patch 015).
    if (source != RecordingSource.planned || recordedAt != null) {
      final now = DateTime.now();
      final rideAt = recordedAt == null || recordedAt.isAfter(now) ? now : recordedAt;
      final own = reports
          .where((r) => r.trailId == trailId && r.userId == me && r.kind == ReportKind.status)
          .toList()
        ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
      final last = own.firstOrNull;
      if (last != null &&
          rideAt.isAfter(last.reportedAt) &&
          !(last.status == TrailStatus.open && last.confirmed)) {
        reports.add(TrailReport(
          id: 'report-${newClientId()}',
          trailId: trailId,
          userId: me,
          kind: ReportKind.status,
          status: TrailStatus.open,
          confirmed: true,
          reportedAt: rideAt,
        ));
      }
    }
    return trailId;
  }

  int attachCalls = 0;

  /// Spiegelt `attach_elevation` (Patch 003): nur die eigene Aufzeichnung,
  /// nur ohne Höhen, und nur, wenn [coords] Punkt für Punkt die
  /// gespeicherte Linie ist (≤ 5 cm).
  @override
  Future<bool> attachElevation({
    required String recordingId,
    required List<double> coords,
    required List<double> eles,
  }) async {
    attachCalls++;
    final i = recordings
        .indexWhere((r) => r.id == recordingId && r.userId == myId());
    if (i < 0) throw StateError('P0002: Keine eigene Aufzeichnung');
    final r = recordings[i];
    if (r.ele != null) return false;
    final n = r.points.length;
    if (coords.length != 2 * n || eles.length != n) {
      throw StateError('22023: Linie passt nicht');
    }
    for (var k = 0; k < n; k++) {
      final d = haversineM(r.points[k].latitude, r.points[k].longitude,
          coords[2 * k + 1], coords[2 * k]);
      if (d > 0.05) throw StateError('22023: nicht die gespeicherte Linie');
    }
    recordings[i] = TrailRecording(
      id: r.id,
      trailId: r.trailId,
      userId: r.userId,
      source: r.source,
      recordedAt: r.recordedAt,
      reversed: r.reversed,
      quality: r.quality,
      createdAt: r.createdAt,
      points: r.points,
      lengthM: r.lengthM,
      ele: List.of(eles),
    );
    return true;
  }

  Object? failNextSaveDetails;

  /// Hält das nächste Speichern an, bis das Future erfüllt ist — für „der
  /// Wert steht schon da, während das Netz noch arbeitet" (#183). Ein
  /// Fehler des Futures ist der Fehler des Speicherns.
  Future<void>? saveDetailsGate;

  @override
  Future<void> saveDetails(TrailDetails d) async {
    final gate = saveDetailsGate;
    if (gate != null) {
      saveDetailsGate = null;
      await gate;
    }
    if (failNextSaveDetails != null) {
      final e = failNextSaveDetails!;
      failNextSaveDetails = null;
      throw e;
    }
    final me = myId();
    // Spiegelt den Check an trail_details.name (1–80 Zeichen).
    final name = d.name;
    if (name != null && (name.isEmpty || name.length > 80)) {
      throw StateError('23514: Name mit ${name.length} Zeichen');
    }
    // Spiegelt trail_details_link_check (Patch 012): nur, was sanitizeLink
    // durchlässt.
    final link = d.link;
    if (link != null && sanitizeLink(link) != link) {
      throw StateError('23514: Link $link');
    }
    // Spiegelt trail_details_rating_check (Patch 013).
    final rating = d.rating;
    if (rating != null && (rating < kRatingMin || rating > kRatingMax)) {
      throw StateError('23514: Bewertung $rating');
    }
    details.removeWhere((x) => x.trailId == d.trailId && x.userId == me);
    details.add(TrailDetails(
      trailId: d.trailId,
      userId: me,
      name: d.name,
      description: d.description,
      grade: d.grade,
      traits: d.traits,
      rating: d.rating,
      twoWay: d.twoWay,
      link: d.link,
      visibility: d.visibility,
      updatedAt: DateTime.now(),
    ));
  }

  final reports = <TrailReport>[];
  int reportCalls = 0;
  Object? failNextReport;

  /// Spiegelt `reports_select`: wie die Hinweise.
  bool _reportVisible(TrailReport r) =>
      r.userId == myId() || (_visible(r.userId, r.trailId) && _canSeeTrail(r.trailId));

  @override
  Future<List<TrailReport>> fetchReports() async {
    if (failFetch != null) throw failFetch!;
    return [
      for (final r in reports)
        if (_reportVisible(r))
          TrailReport(
            id: r.id,
            trailId: r.trailId,
            userId: r.userId,
            kind: r.kind,
            status: r.status,
            condition: r.condition,
            confirmed: r.confirmed,
            reportedAt: r.reportedAt,
            username: usernames[r.userId],
          ),
    ];
  }

  /// Die `client_id` je Art, wie der eindeutige Index in `trail_reports`.
  final _reportClientIds = <String>{};

  /// Wie [saveDetailsGate], für das Melden.
  Future<void>? reportGate;

  /// Spiegelt `report_trail` (Patch 013): nur, wer den Trail sieht; der
  /// Server legt `confirmed` fest (gefahren oder vor Ort) und kappt die
  /// Zeit auf jetzt; dieselbe `client_id` legt nichts an.
  @override
  Future<void> report({
    required String trailId,
    TrailStatus? status,
    int? condition,
    required bool onSite,
    required DateTime reportedAt,
    required String clientId,
  }) async {
    reportCalls++;
    final gate = reportGate;
    if (gate != null) {
      reportGate = null;
      await gate;
    }
    if (failNextReport != null) {
      final e = failNextReport!;
      failNextReport = null;
      throw e;
    }
    final me = myId();
    if (status == null && condition == null) throw StateError('22023: nichts gemeldet');
    if (!_canSeeTrail(trailId)) throw StateError('42501: Trail nicht sichtbar');
    if (condition != null && (condition < kConditionMin || condition > kConditionMax)) {
      throw StateError('23514: Zustand $condition');
    }
    final confirmed = onSite ||
        recordings.any((r) =>
            r.trailId == trailId && r.userId == me && r.ridden);
    final now = DateTime.now();
    final at = reportedAt.isAfter(now) ? now : reportedAt;
    for (final kind in [if (status != null) ReportKind.status, if (condition != null) ReportKind.condition]) {
      if (!_reportClientIds.add('$me/$clientId/${kind.db}')) continue;
      reports.add(TrailReport(
        id: 'report-${newClientId()}',
        trailId: trailId,
        userId: me,
        kind: kind,
        status: kind == ReportKind.status ? status : null,
        condition: kind == ReportKind.condition ? condition : null,
        confirmed: confirmed,
        reportedAt: at.toLocal(),
      ));
    }
  }

  /// Eine Meldung von [userId], ohne Prüfung — für Ausgangslagen in Tests.
  void seedReport(String userId, String trailId,
      {TrailStatus? status, int? condition, bool confirmed = true, DateTime? at}) {
    reports.add(TrailReport(
      id: 'report-${newClientId()}',
      trailId: trailId,
      userId: userId,
      kind: status != null ? ReportKind.status : ReportKind.condition,
      status: status,
      condition: status != null ? null : condition,
      confirmed: confirmed,
      reportedAt: at ?? DateTime.now(),
    ));
  }

  final notes = <TrailNote>[];

  /// Spiegelt `app_internal.can_see_trail`.
  bool _canSeeTrail(String trailId) =>
      recordings.any((r) => r.trailId == trailId && _visible(r.userId, trailId));

  /// Spiegelt `notes_select` (und `notes_delete`).
  bool _noteVisible(TrailNote n) =>
      n.userId == myId() || (_visible(n.userId, n.trailId) && _canSeeTrail(n.trailId));

  @override
  Future<List<TrailNote>> fetchNotes() async {
    if (failFetch != null) throw failFetch!;
    return [
      for (final n in notes)
        if (_noteVisible(n))
          TrailNote(
            id: n.id,
            trailId: n.trailId,
            userId: n.userId,
            body: n.body,
            createdAt: n.createdAt,
            username: usernames[n.userId],
          ),
    ];
  }

  /// Spiegelt `notes_insert` und den Check der Tabelle: nur, wer den
  /// Trail sieht, 1–500 Zeichen.
  @override
  Future<void> addNote({required String trailId, required String body}) async {
    final me = myId();
    if (!_canSeeTrail(trailId)) {
      throw StateError('42501: Trail nicht sichtbar');
    }
    final len = body.trim().length;
    if (len < 1 || len > 500) throw StateError('23514: Länge $len');
    notes.add(TrailNote(
      id: 'note-${newClientId()}',
      trailId: trailId,
      userId: me,
      body: body,
      createdAt: DateTime.now(),
    ));
  }

  /// Spiegelt `notes_delete`: entfernen darf, wer den Hinweis sieht;
  /// alles andere filtert still.
  @override
  Future<void> deleteNote(String id) async {
    notes.removeWhere((n) => n.id == id && _noteVisible(n));
  }

  Object? failNextWithdraw;

  /// Spiegelt `withdraw_contribution` (Patch 010): nur die eigenen Zeilen,
  /// alle drei in einem Schritt; den leeren Trail holt der Aufräumjob —
  /// hier genügt, dass ihn keine Aufzeichnung mehr trägt.
  @override
  Future<int> withdraw(String trailId) async {
    if (failNextWithdraw != null) {
      final e = failNextWithdraw!;
      failNextWithdraw = null;
      throw e;
    }
    final me = myId();
    final n = recordings.where((r) => r.trailId == trailId && r.userId == me).length;
    recordings.removeWhere((r) => r.trailId == trailId && r.userId == me);
    notes.removeWhere((x) => x.trailId == trailId && x.userId == me);
    reports.removeWhere((x) => x.trailId == trailId && x.userId == me);
    details.removeWhere((d) => d.trailId == trailId && d.userId == me);
    return n;
  }

  /// `app_internal.trail_aliases` und `trail_distinct` (Patch 019, #107).
  final aliases = <FakeAlias>[];
  final distinct = <({String userId, String a, String b})>[];
  int mergeCalls = 0;
  Object? failNextMerge;

  /// Die beste Linie von [trailId], die ICH sehe — wie
  /// `app_internal.visible_line` (höchste Qualität, dann die ältere).
  TrailRecording? _visibleLine(String trailId) {
    final seen = [
      for (final r in recordings)
        if (r.trailId == trailId && _visible(r.userId, trailId)) r,
    ]..sort((a, b) {
        final q = b.quality.compareTo(a.quality);
        return q != 0 ? q : a.createdAt.compareTo(b.createdAt);
      });
    return seen.firstOrNull;
  }

  /// Spiegelt `app_internal.shares_on`: [person] hat an [trailId] eine
  /// Aufzeichnung, deren Beitrag nicht privat ist.
  bool _sharesOn(String person, String trailId) =>
      recordings.any((r) => r.userId == person && r.trailId == trailId) &&
      !details.any((d) =>
          d.userId == person && d.trailId == trailId && d.visibility == TrailVisibility.private);

  /// Spiegelt `app_internal.owns_contribution`.
  bool _owns(String uid, String trailId) =>
      recordings.any((r) => r.userId == uid && r.trailId == trailId) ||
      details.any((d) => d.userId == uid && d.trailId == trailId);

  /// Spiegelt `merge_own_into` (Patch 019). Die Richtung von B zu A
  /// schätzt der Fake aus den Enden der Linien (die Datenbank aus den
  /// Fußpunkten, `merge_near`); die Nähe rechnet er wie die App.
  @override
  Future<String> mergeInto({required String duplicateId, required String targetId}) async {
    mergeCalls++;
    if (failNextMerge != null) {
      final e = failNextMerge!;
      failNextMerge = null;
      throw e;
    }
    final me = myId();
    var target = targetId;
    final dup = duplicateId;
    if (dup == target) throw const MergeRejectedException(MergeRejection.notNear);
    final known = aliases.where((a) => a.userId == me && a.trailId == dup).firstOrNull;
    if (known != null) return known.sameAs;
    final hop = aliases.where((a) => a.userId == me && a.trailId == target).firstOrNull;
    if (hop != null) {
      target = hop.sameAs;
      if (target == dup) throw const MergeRejectedException(MergeRejection.notNear);
    }
    if (!_canSeeTrail(dup) || !_canSeeTrail(target)) {
      throw const MergeRejectedException(MergeRejection.gone);
    }
    final la = _visibleLine(target)!, lb = _visibleLine(dup)!;
    if (mergeNearShare(lb.points, la.points) < kMergeNearShare) {
      throw const MergeRejectedException(MergeRejection.notNear);
    }
    LatLng startOf(TrailRecording r) => r.reversed ? r.points.last : r.points.first;
    LatLng endOf(TrailRecording r) => r.reversed ? r.points.first : r.points.last;
    double dist(LatLng p, LatLng q) => haversineM(p.latitude, p.longitude, q.latitude, q.longitude);
    final flip = dist(startOf(lb), startOf(la)) > dist(startOf(lb), endOf(la));

    // 1. Aufzeichnungen.
    for (var i = 0; i < recordings.length; i++) {
      final r = recordings[i];
      if (r.userId == me && r.trailId == dup) recordings[i] = r.movedTo(target, flip: flip);
    }
    // 2. Beitrag: A gewinnt, leere Felder füllt B, privat gewinnt.
    final db = details.where((d) => d.trailId == dup && d.userId == me).firstOrNull;
    if (db != null) {
      final da = details.where((d) => d.trailId == target && d.userId == me).firstOrNull;
      details.remove(db);
      if (da == null) {
        details.add(db.withTrailId(target));
      } else {
        details[details.indexOf(da)] = TrailDetails(
          trailId: target,
          userId: me,
          name: da.name ?? db.name,
          description: da.description ?? db.description,
          grade: da.grade ?? db.grade,
          traits: da.traits.isEmpty ? db.traits : da.traits,
          rating: da.rating ?? db.rating,
          link: da.link ?? db.link,
          twoWay: da.twoWay || db.twoWay,
          visibility: TrailVisibility.private == da.visibility || TrailVisibility.private == db.visibility
              ? TrailVisibility.private
              : TrailVisibility.buddies,
          updatedAt: DateTime.now(),
        );
      }
    }
    // 3. Hinweise und Meldungen.
    for (var i = 0; i < notes.length; i++) {
      if (notes[i].userId == me && notes[i].trailId == dup) notes[i] = notes[i].withTrailId(target);
    }
    for (var i = 0; i < reports.length; i++) {
      if (reports[i].userId == me && reports[i].trailId == dup) {
        reports[i] = reports[i].withTrailId(target);
      }
    }
    // 4. Eigene Ketten X → B zeigen auf A; die neue Zuordnung.
    for (var i = 0; i < aliases.length; i++) {
      final a = aliases[i];
      if (a.userId == me && a.sameAs == dup) {
        aliases[i] = (userId: me, trailId: a.trailId, sameAs: target,
            reversed: a.reversed != flip, createdAt: a.createdAt);
      }
    }
    aliases.add((userId: me, trailId: dup, sameAs: target, reversed: flip, createdAt: DateTime.now()));
    // 5. Ein eigenes „verschieden" fällt weg.
    distinct.removeWhere((d) => d.userId == me && {d.a, d.b}.containsAll({dup, target}));
    return target;
  }

  /// Spiegelt `unmerge_trail`.
  @override
  Future<void> unmerge(String duplicateId) async {
    final me = myId();
    aliases.removeWhere((a) => a.userId == me && a.trailId == duplicateId);
  }

  /// Spiegelt `trail_merges()` (Patch 019) ohne die Overlap-Kanten (die
  /// legt nur der Abgleich in der Datenbank an).
  @override
  Future<List<TrailMerge>> fetchMerges() async {
    if (failFetch != null) throw failFetch!;
    final me = myId();
    bool seen(String id) => _canSeeTrail(id);
    bool buddy(String u) => u != me && (areFriends?.call(me, u) ?? false);
    final own = [
      for (final a in aliases)
        if (a.userId == me && seen(a.trailId) && seen(a.sameAs)) a,
    ];
    final ownDistinct = [
      for (final d in distinct)
        if (d.userId == me && seen(d.a) && seen(d.b)) d,
    ];
    bool isDistinct(Iterable<({String userId, String a, String b})> rows, String x, String y) =>
        rows.any((d) => {d.a, d.b}.containsAll({x, y}));
    final claims = [
      for (final a in aliases)
        if (buddy(a.userId) &&
            seen(a.trailId) &&
            seen(a.sameAs) &&
            (_sharesOn(a.userId, a.trailId) || _sharesOn(a.userId, a.sameAs)) &&
            !own.any((o) => o.trailId == a.trailId || (o.trailId == a.sameAs && o.sameAs == a.trailId)) &&
            !isDistinct(ownDistinct, a.trailId, a.sameAs))
          a,
    ]..sort((x, y) => x.createdAt.compareTo(y.createdAt));
    final vetoes = [
      for (final d in distinct)
        if (buddy(d.userId) && (_sharesOn(d.userId, d.a) || _sharesOn(d.userId, d.b))) d,
    ];
    final judged = <String, TrailMerge>{};
    for (final c in claims) {
      final key = '${c.trailId}|${c.sameAs}';
      final kind = _owns(me, c.trailId) ? TrailMergeKind.proposed : TrailMergeKind.folded;
      final prev = judged[key];
      judged[key] = TrailMerge(
        trailId: c.trailId,
        sameAs: c.sameAs,
        kind: kind,
        reversed: prev?.reversed ?? c.reversed,
        byUsers: [...?prev?.byUsers, c.userId],
      );
    }
    final rows = <TrailMerge>[
      for (final o in own)
        TrailMerge(trailId: o.trailId, sameAs: o.sameAs, kind: TrailMergeKind.own, reversed: o.reversed),
      for (final d in ownDistinct)
        TrailMerge(trailId: d.a, sameAs: d.b, kind: TrailMergeKind.distinct),
      for (final j in judged.values)
        if (j.kind == TrailMergeKind.proposed || !isDistinct(vetoes, j.trailId, j.sameAs)) j,
    ];
    return rows;
  }

  /// Eine Erklärung „[trailId] ist ein Duplikat von [sameAs]" von
  /// [userId], ohne Prüfung — für Ausgangslagen mit Buddys.
  void seedAlias(String userId, String trailId, String sameAs, {bool reversed = false, DateTime? at}) {
    aliases.add((
      userId: userId,
      trailId: trailId,
      sameAs: sameAs,
      reversed: reversed,
      createdAt: at ?? DateTime.now(),
    ));
  }

  /// Ein Hinweis von [userId], ohne Prüfung — für Ausgangslagen in Tests.
  void seedNote(String userId, String trailId, String body, {DateTime? at}) {
    notes.add(TrailNote(
      id: 'note-${newClientId()}',
      trailId: trailId,
      userId: userId,
      body: body,
      createdAt: at ?? DateTime.now(),
    ));
  }

  /// Ein fertiger Beleg von [userId] für Tests — eine 1-km-Linie nach
  /// Norden ab [lat]/[lon], drei Punkte; [ele] trägt dann drei Höhen.
  String seedTrail(String userId,
      {String? name, double lat = 48.0, double lon = 9.0, double quality = 0.4,
      TrailStatus status = TrailStatus.open, DateTime? statusAt,
      TrailVisibility visibility = TrailVisibility.buddies, String? trailId,
      List<double>? ele, bool reversed = false, int? grade,
      Set<TrailTrait> traits = const {}, int? rating,
      RecordingSource source = RecordingSource.import, String? link}) {
    final id = trailId ?? 'trail-${newClientId()}';
    recordings.add(TrailRecording(
      id: 'rec-${newClientId()}',
      trailId: id,
      userId: userId,
      source: source,
      recordedAt: null,
      reversed: reversed,
      quality: quality,
      createdAt: DateTime(2026, 1, 1).add(Duration(seconds: recordings.length)),
      points: [LatLng(lat, lon), LatLng(lat + 0.005, lon), LatLng(lat + 0.009, lon)],
      lengthM: 1000,
      ele: ele,
    ));
    details.add(TrailDetails(
      trailId: id,
      userId: userId,
      name: name,
      grade: grade,
      traits: traits,
      rating: rating,
      link: link,
      visibility: visibility,
    ));
    // Eine Meldung ungleich „offen" steht seit Patch 013 im Verlauf —
    // bestätigt, wenn der Beleg keine geplante Datei ist.
    if (status != TrailStatus.open || statusAt != null) {
      seedReport(userId, id,
          status: status,
          confirmed: source != RecordingSource.planned,
          at: statusAt ?? DateTime(2026, 1, 1));
    }
    return id;
  }
}
