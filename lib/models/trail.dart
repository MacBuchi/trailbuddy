import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../features/trails/trail_elevation.dart';
import '../l10n/l10n.dart';
import '../features/trails/trail_geometry.dart';
import 'trail_merge.dart';

/// Ein Beleg: „ich bin das gefahren" (Konzept 3). Die Linie kommt aus
/// der Sicht `recordings_visible` als GeoJSON und wird hier zu Punkten.
class TrailRecording {
  const TrailRecording({
    required this.id,
    required this.trailId,
    required this.userId,
    required this.source,
    required this.recordedAt,
    required this.reversed,
    required this.quality,
    required this.createdAt,
    required this.points,
    required this.lengthM,
    this.ele,
  });

  final String id;
  final String trailId;
  final String userId;
  final RecordingSource source;
  final DateTime? recordedAt;
  final bool reversed;
  final double quality;
  final DateTime createdAt;
  final List<LatLng> points;
  final double lengthM;

  /// Eine Höhe je Punkt, oder null (Datei ohne Höhen, Aufzeichnung vor
  /// Patch 002). Passt die Anzahl nicht zu den Punkten, ist sie ebenfalls
  /// null — eine verschobene Reihe wäre schlimmer als keine.
  final List<double>? ele;

  /// Belegt eine Fahrt: nicht nur geplant — oder geplant MIT eingetragenem
  /// Fahrdatum (Patch 015, #120). Dieselbe Regel wie `has_ridden` auf dem
  /// Server; die Linie einer geplanten bleibt trotzdem gezeichnet.
  bool get ridden => source != RecordingSource.planned || recordedAt != null;

  /// Dieselbe Aufzeichnung unter einem anderen Trail (#107): ein Duplikat,
  /// das bei mir unter [trailId] steht. [flip]: B läuft gegen A, die
  /// Richtung zum Trail dreht sich mit. Die Punkte bleiben dieselbe Liste.
  TrailRecording movedTo(String trailId, {required bool flip}) => TrailRecording(
        id: id,
        trailId: trailId,
        userId: userId,
        source: source,
        recordedAt: recordedAt,
        reversed: reversed != flip,
        quality: quality,
        createdAt: createdAt,
        points: points,
        lengthM: lengthM,
        ele: ele,
      );

  factory TrailRecording.fromJson(Map<String, dynamic> json) {
    // `st_asgeojson` liefert Text. Je nachdem, ob die Sicht ihn nach json
    // castet, kommt er als String oder als Map — beides wird angenommen,
    // damit eine Spaltenänderung nicht still leere Linien erzeugt.
    final raw = json['geojson'];
    final geo = raw is String
        ? jsonDecode(raw)
        : raw;
    final coords = geo is Map ? geo['coordinates'] : null;
    final points = <LatLng>[];
    if (coords is List) {
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          points.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
        }
      }
    }
    final rawEle = json['ele'];
    List<double>? ele;
    if (rawEle is List && rawEle.length == points.length && rawEle.every((e) => e is num)) {
      ele = [for (final e in rawEle) (e as num).toDouble()];
    }
    return TrailRecording(
      id: json['id'] as String,
      trailId: json['trail_id'] as String,
      userId: json['user_id'] as String,
      source: RecordingSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => RecordingSource.import),
      recordedAt: json['recorded_at'] == null
          ? null
          : DateTime.parse(json['recorded_at'] as String).toLocal(),
      reversed: json['reversed'] as bool? ?? false,
      quality: (json['quality'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      points: points,
      lengthM: (json['length_m'] as num?)?.toDouble() ?? 0,
      ele: ele,
    );
  }
}

/// Höchstlänge eines Trail-Namens — dieselbe wie der Check an
/// `trail_details.name` im Schema.
const kTrailNameMaxLength = 80;

/// Ein Name aus einer Datei, so gekürzt, dass der Server ihn annimmt:
/// möglichst an einem Wortende, mit „…". Ohne das scheiterte der ganze
/// Import einer Spur an ihrem Namen, obwohl die Aufzeichnung längst lag.
String clampTrailName(String name) {
  final n = name.trim();
  if (n.length <= kTrailNameMaxLength) return n;
  var cut = n.substring(0, kTrailNameMaxLength - 1);
  final space = cut.lastIndexOf(' ');
  if (space >= kTrailNameMaxLength * 3 ~/ 4) cut = cut.substring(0, space);
  return '${cut.trimRight()}…';
}

/// Singletrail-Skala S0–S5, die in DACH übliche Schwierigkeitsangabe.
String gradeLabel(int grade) => 'S$grade';

/// Der Charakter eines Trails (#72, Patch 009, seit 0.34.0) — MEHRFACHWAHL
/// je Beitrag, ersetzt die frühere Einzelwahl „Art" (`kind`). Die sieben
/// Merkmale hat der Betreiber festgelegt (2026-09-29): die fünf aus dem
/// Design (Turn 4) plus Naturtrail und Verbindung aus der alten Art,
/// damit beim Übernehmen nichts verloren geht. Beschreibungen und
/// Symbole: `trail_traits.dart`. Die Reihenfolge hier ist die Reihenfolge
/// überall (Auswahl, Chips, Gleichstand beim Zählen).
enum TrailTrait {
  flowy('flowy'),
  jumps('jumps'),
  rocky('rocky'),
  steep('steep'),
  uphill('uphill'),
  natural('natural'),
  connection('connection');

  const TrailTrait(this.db);
  final String db;

  /// Der Name auf dem Schirm (#209) — ein `switch`, damit ein neues
  /// Merkmal ohne Text nicht baut.
  String label(AppLocalizations l) => switch (this) {
        flowy => l.traitFlowy,
        jumps => l.traitJumps,
        rocky => l.traitRocky,
        steep => l.traitSteep,
        uphill => l.traitUphill,
        natural => l.traitNatural,
        connection => l.traitConnection,
      };

  static TrailTrait? fromDb(String? s) =>
      s == null ? null : values.where((k) => k.db == s).firstOrNull;

  /// Die alte „Art" (`kind`) als Merkmal — dieselbe Zuordnung wie im
  /// Patch 009, für Zeilen, die noch keine `traits` tragen (ein alter
  /// Zwischenspeicher, ein wartender Auftrag im Ausgangskorb).
  static TrailTrait? fromLegacyKind(String? kind) => switch (kind) {
        'flow' => flowy,
        'jump' => jumps,
        'tech' => rocky,
        'natural' => natural,
        'connection' => connection,
        _ => null,
      };
}

/// Höchstens so viele Merkmale zeigt ein Trail (Design Turn 4): die
/// häufigsten über alle sichtbaren Beiträge.
const kShownTraits = 2;

enum TrailVisibility {
  buddies('buddies'),
  private('private');

  const TrailVisibility(this.db);
  final String db;

  String label(AppLocalizations l) => switch (this) {
        buddies => l.visibilityBuddies,
        private => l.visibilityPrivate,
      };

  static TrailVisibility fromDb(String? s) =>
      values.where((v) => v.db == s).firstOrNull ?? TrailVisibility.buddies;
}

/// Die Meldung zu einem Trail (bis 0.48.0 in der App „Status", Rework
/// E7): offen, gesperrt, zerstört, verändert. Seit Patch 013 steht sie
/// nicht mehr am Beitrag, sondern als [TrailReport] im Verlauf.
enum TrailStatus {
  open('open'),
  closed('closed'),
  destroyed('destroyed'),
  changed('changed');

  const TrailStatus(this.db);
  final String db;

  String label(AppLocalizations l) => switch (this) {
        open => l.statusOpen,
        closed => l.statusClosed,
        destroyed => l.statusDestroyed,
        changed => l.statusChanged,
      };

  static TrailStatus fromDb(String? s) =>
      values.where((v) => v.db == s).firstOrNull ?? TrailStatus.open;

  bool get warns => this != TrailStatus.open;

  /// Sperrt den Trail für die Planung (#434, Betreiber 2026-10-31):
  /// gesperrt und zerstört, nicht „Verändert" (`changed`).
  bool get blocksRouting => this == TrailStatus.closed || this == TrailStatus.destroyed;
}

/// Was ein Nutzer über einen Trail sagt — genau eine Zeile je Nutzer und
/// Trail (Konzept 3). Name, Schwierigkeit, Charakter und Bewertung sind
/// Eigenschaften des BEITRAGS, nicht des Trails. Die Meldung steht seit
/// Patch 013 nicht mehr hier, sondern in [TrailReport]: Melden darf auch,
/// wer keinen Beitrag hat.
class TrailDetails {
  const TrailDetails({
    required this.trailId,
    required this.userId,
    this.username,
    this.name,
    this.description,
    this.grade,
    this.traits = const {},
    this.rating,
    this.twoWay = false,
    this.link,
    this.visibility = TrailVisibility.buddies,
    this.updatedAt,
  });

  final String trailId;
  final String userId;

  /// Aus dem Embed `contributor:profiles(...)`; leer bei der eigenen Zeile,
  /// wenn das Profil nicht mitgeladen wurde.
  final String? username;
  final String? name;
  final String? description;
  final int? grade;

  /// Der Charakter laut DIESEM Beitrag, leer = keine Angabe.
  final Set<TrailTrait> traits;

  /// Die Bewertung (#101, Patch 013): 1–5 Sterne, null = noch nicht
  /// bewertet. Unbekannte Werte fallen beim Lesen weg.
  final int? rating;

  /// In beide Richtungen fahrbar (#174, Patch 016) — sonst fährt der
  /// Planer den Trail nie gegen seine Richtung. Vorgabe aus.
  final bool twoWay;

  /// Link zur Quelle (#103, Patch 012): https, ohne Query — geprüft von
  /// `sanitizeLink` und vom Check in der Datenbank.
  final String? link;
  final TrailVisibility visibility;
  final DateTime? updatedAt;

  factory TrailDetails.fromJson(Map<String, dynamic> json) {
    final contributor = json['contributor'];
    return TrailDetails(
      trailId: json['trail_id'] as String,
      userId: json['user_id'] as String,
      username: contributor is Map ? contributor['username'] as String? : null,
      name: json['name'] as String?,
      description: json['description'] as String?,
      grade: json['grade'] as int?,
      traits: _traitsFromJson(json),
      rating: _ratingFromJson(json['rating']),
      twoWay: json['two_way'] == true,
      link: json['link'] as String?,
      visibility: TrailVisibility.fromDb(json['visibility'] as String?),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toRow() => {
        'trail_id': trailId,
        'user_id': userId,
        'name': name,
        'description': description,
        'grade': grade,
        // `kind` schreibt die App nicht mehr; der Server behält den
        // alten Wert, bis Patch-Folge die Spalte entfernt.
        'traits': [for (final t in TrailTrait.values) if (traits.contains(t)) t.db],
        'rating': rating,
        'two_way': twoWay,
        'link': link,
        'visibility': visibility.db,
        // `status`/`status_at` schreibt die App seit 0.49.0 nicht mehr: Die
        // Meldung geht über `report_trail` (Patch 013), und der Server
        // gleicht sie für ältere Clients an den Beitrag ab.
      };

  /// Derselbe Beitrag unter einem anderen Trail (#107) — nur für die
  /// Anzeige; geschrieben wird er nie so.
  TrailDetails withTrailId(String trailId) => TrailDetails(
        trailId: trailId,
        userId: userId,
        username: username,
        name: name,
        description: description,
        grade: grade,
        traits: traits,
        rating: rating,
        twoWay: twoWay,
        link: link,
        visibility: visibility,
        updatedAt: updatedAt,
      );

  TrailDetails copyWith({
    String? name,
    String? description,
    int? grade,
    bool clearGrade = false,
    Set<TrailTrait>? traits,
    int? rating,
    bool clearRating = false,
    bool? twoWay,
    String? link,
    bool clearLink = false,
    TrailVisibility? visibility,
  }) =>
      TrailDetails(
        trailId: trailId,
        userId: userId,
        username: username,
        name: name ?? this.name,
        description: description ?? this.description,
        grade: clearGrade ? null : (grade ?? this.grade),
        traits: traits ?? this.traits,
        rating: clearRating ? null : (rating ?? this.rating),
        twoWay: twoWay ?? this.twoWay,
        link: clearLink ? null : (link ?? this.link),
        visibility: visibility ?? this.visibility,
        updatedAt: updatedAt,
      );
}

int? _ratingFromJson(Object? raw) =>
    raw is int && raw >= kRatingMin && raw <= kRatingMax ? raw : null;

/// Die Sterne der Bewertung (#101) — dieselben Grenzen wie der Check
/// `trail_details_rating_check`.
const kRatingMin = 1;
const kRatingMax = 5;

/// Was eine Meldung ist: die Meldung selbst („gesperrt" …) oder der
/// Zustand 1–5. Die Werte sind die von `trail_reports.kind`.
enum ReportKind {
  status('status'),
  condition('condition');

  const ReportKind(this.db);
  final String db;

  static ReportKind? fromDb(String? s) =>
      values.where((k) => k.db == s).firstOrNull;
}

/// Eine Meldung oder ein Zustand (#101, Patch 013), eine Zeile im
/// Verlauf. Schreiben darf jeder, der den Trail sieht; ob sie
/// [confirmed] ist, legt der Server fest: gefahren oder vor Ort.
class TrailReport {
  const TrailReport({
    required this.id,
    required this.trailId,
    required this.userId,
    required this.kind,
    required this.confirmed,
    required this.reportedAt,
    this.status,
    this.condition,
    this.username,
    this.pending = false,
    this.sending = false,
  });

  final String id;
  final String trailId;
  final String userId;
  final ReportKind kind;

  /// Nur bei [ReportKind.status].
  final TrailStatus? status;

  /// Nur bei [ReportKind.condition]: 1 (kaum fahrbar) bis 5 (top gepflegt).
  final int? condition;

  /// Bestätigt: Der Meldende war dort — gefahren oder vor Ort gemeldet.
  /// Sonst „zu bestätigen" (verblasst).
  final bool confirmed;
  final DateTime reportedAt;

  /// Aus dem Embed `reporter:profiles(...)`.
  final String? username;

  /// Wartet im Ausgangskorb; [confirmed] ist dann die Vorhersage des
  /// Geräts (vor Ort oder selbst gefahren), der Server rechnet nach.
  final bool pending;

  /// Noch nicht im Korb, sondern gerade unterwegs (#183): Die Meldung
  /// steht schon da, während der Sendeversuch läuft. Immer mit [pending].
  final bool sending;

  /// null, wenn die Zeile nicht zu diesem Stand passt (unbekannte Art,
  /// fehlender Wert) — eine neuere App darf eine ältere nicht umwerfen.
  static TrailReport? fromJson(Map<String, dynamic> json) {
    final kind = ReportKind.fromDb(json['kind'] as String?);
    final at = DateTime.tryParse(json['reported_at'] as String? ?? '');
    if (kind == null || at == null) return null;
    final status = json['status'] == null ? null : TrailStatus.fromDb(json['status'] as String?);
    final condition = json['condition'];
    if (kind == ReportKind.status && status == null) return null;
    if (kind == ReportKind.condition &&
        !(condition is int && condition >= kConditionMin && condition <= kConditionMax)) {
      return null;
    }
    final reporter = json['reporter'];
    return TrailReport(
      id: json['id'] as String,
      trailId: json['trail_id'] as String,
      userId: json['user_id'] as String,
      kind: kind,
      status: kind == ReportKind.status ? status : null,
      condition: kind == ReportKind.condition ? condition as int : null,
      confirmed: json['confirmed'] as bool? ?? false,
      reportedAt: at.toLocal(),
      username: reporter is Map ? reporter['username'] as String? : null,
    );
  }

  /// Dieselbe Meldung unter einem anderen Trail (#107), nur für die Anzeige.
  TrailReport withTrailId(String trailId) => TrailReport(
        id: id,
        trailId: trailId,
        userId: userId,
        kind: kind,
        confirmed: confirmed,
        reportedAt: reportedAt,
        status: status,
        condition: condition,
        username: username,
        pending: pending,
        sending: sending,
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'trail_id': trailId,
        'user_id': userId,
        'kind': kind.db,
        'status': status?.db,
        'condition': condition,
        'confirmed': confirmed,
        'reported_at': reportedAt.toUtc().toIso8601String(),
        'reporter': username == null ? null : {'username': username},
      };
}

/// Die Skala des Zustands — dieselben Grenzen wie der Check an
/// `trail_reports.condition`. Wortlaut: `trail_condition.dart`.
const kConditionMin = 1;
const kConditionMax = 5;

/// So lange steht eine Meldung im Verlauf des Blatts (Betreiber,
/// 2026-09-30: „zur Nachvollziehbarkeit 90 Tage"); der Server räumt
/// danach auf (`sweep_old_reports`), die angezeigte bleibt.
const kReportRetentionDays = 90;

/// Was angezeigt wird (Rework, Abschnitt 9): die jüngste BESTÄTIGTE
/// Angabe, dazu die jüngste UNBESTÄTIGTE, wenn sie jünger ist — eine
/// ältere unbestätigte ist überholt.
typedef ShownReports = ({TrailReport? confirmed, TrailReport? unconfirmed});

ShownReports shownReportsOf(Iterable<TrailReport> reports) {
  TrailReport? confirmed;
  TrailReport? unconfirmed;
  bool newer(TrailReport a, TrailReport? b) => b == null || a.reportedAt.isAfter(b.reportedAt);
  for (final r in reports) {
    if (r.confirmed) {
      if (newer(r, confirmed)) confirmed = r;
    } else if (newer(r, unconfirmed)) {
      unconfirmed = r;
    }
  }
  if (confirmed != null && unconfirmed != null && !unconfirmed.reportedAt.isAfter(confirmed.reportedAt)) {
    unconfirmed = null;
  }
  return (confirmed: confirmed, unconfirmed: unconfirmed);
}

/// `traits` aus einer Zeile; fehlt die Spalte (Zwischenspeicher oder
/// Ausgangskorb von vor 0.34.0), zählt die alte Art.
Set<TrailTrait> _traitsFromJson(Map<String, dynamic> json) {
  final raw = json['traits'];
  if (raw is List) {
    return {for (final v in raw) ?TrailTrait.fromDb(v as String?)};
  }
  final legacy = TrailTrait.fromLegacyKind(json['kind'] as String?);
  return {?legacy};
}

/// Ein Hinweis zu einem Trail für Buddys (Issue #7, Patch 004/005):
/// „Baum liegt quer". Schreiben darf jeder, der den Trail sieht; sehen
/// seine direkten Buddys, die den Trail auch sehen. Kein Bearbeiten — das
/// Alter steht dabei.
class TrailNote {
  const TrailNote({
    required this.id,
    required this.trailId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.username,
    this.photo,
    this.reportId,
    this.pending = false,
    this.sending = false,
  });

  final String id;
  final String trailId;
  final String userId;
  final String body;
  final DateTime createdAt;

  /// Die Meldung, zu der der Text gehört (#433, Patch 028): Status und
  /// Text sind EIN Eintrag. null bei Text allein — und wenn die Meldung
  /// im Aufräumen wegfiel.
  final String? reportId;

  /// Wartet im Ausgangskorb (#433: Text geht seitdem auch ohne Netz).
  final bool pending;

  /// Gerade unterwegs (#183), immer mit [pending].
  final bool sending;

  /// Aus dem Embed `author:profiles(...)`.
  final String? username;

  /// Das Foto dazu (#37, Patch 026) — auch ein abgelaufenes, das der Autor
  /// bis zum Abräumen noch sieht. Angezeigt wird [shownPhoto].
  final NotePhoto? photo;

  /// Das Foto, solange es gilt. Fremde bekommen ein abgelaufenes gar nicht
  /// erst (`tnp_friend_select`), der Autor schon — bis der Bot räumt.
  NotePhoto? shownPhoto({DateTime? now}) {
    final p = photo;
    return p != null && p.expiresAt.isAfter(now ?? DateTime.now()) ? p : null;
  }

  /// Derselbe Hinweis unter einem anderen Trail (#107), nur für die Anzeige.
  TrailNote withTrailId(String trailId) => TrailNote(
      id: id,
      trailId: trailId,
      userId: userId,
      body: body,
      createdAt: createdAt,
      username: username,
      photo: photo,
      reportId: reportId,
      pending: pending,
      sending: sending);

  factory TrailNote.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    return TrailNote(
      id: json['id'] as String,
      trailId: json['trail_id'] as String,
      userId: json['user_id'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      username: author is Map ? author['username'] as String? : null,
      photo: NotePhoto.fromEmbed(json['photo']),
      reportId: json['report_id'] as String?,
    );
  }
}

/// Eine Zeile in „MELDUNGEN" (#433): eine Statusmeldung, ein Text oder
/// beides — in der Datenbank zwei Zeilen (`trail_notes.report_id`), für
/// Nutzer ein Eintrag. Wer den Text nicht sehen darf, bekommt die Notiz
/// gar nicht erst und sieht nur die Meldung.
class TrailEntry {
  const TrailEntry({this.report, this.note}) : assert(report != null || note != null);

  /// Nur [ReportKind.status].
  final TrailReport? report;
  final TrailNote? note;

  DateTime get at => report?.reportedAt ?? note!.createdAt;
}

/// Ein Foto am Hinweis (#37, Patch 026): EINES je Hinweis, die Bytes im
/// Bucket `trail-note-photos` unter [key] (`<user_id>/<id>`), Bild und
/// Vorschau als zwei JPEGs. Sichtbar für genau die, die den Hinweis sehen;
/// 90 Tage, dann räumt der Feedback-Bot ab.
class NotePhoto {
  const NotePhoto({required this.key, required this.expiresAt});

  final String key;
  final DateTime expiresAt;

  /// Das Bild mit 1024er Kante — geladen erst auf Tipp.
  String get fullPath => '$key.jpg';

  /// Die Vorschau mit 200er Kante — das, was das Blatt lädt.
  String get thumbPath => '${key}_s.jpg';

  /// Aus dem Embed `photo:trail_note_photos(...)`. PostgREST liefert die
  /// eins-zu-eins-Beziehung (`note_id unique`) als Objekt; eine Liste
  /// nimmt der Leser trotzdem, falls ein Dienst sie anders erkennt.
  static NotePhoto? fromEmbed(Object? raw) {
    final row = raw is List ? (raw.isEmpty ? null : raw.first) : raw;
    if (row is! Map) return null;
    final key = row['key'];
    final expires = row['expires_at'];
    if (key is! String || expires is! String) return null;
    return NotePhoto(key: key, expiresAt: DateTime.parse(expires).toLocal());
  }

  Map<String, dynamic> toRow() => {'key': key, 'expires_at': expiresAt.toUtc().toIso8601String()};
}

/// So lange gilt ein Hinweis eines Buddys als neu: Liste und Karte heben
/// den Trail hervor, bis man ihn im Blatt gesehen hat. Danach steht er
/// nur noch dort, mit seinem Alter.
const kFreshNoteDays = 7;

/// Nach so vielen Tagen verschwindet ein Hinweis — außer dem jüngsten
/// (Entscheidung des Betreibers). Der Server räumt je Autor auf
/// (`sweep_old_notes`), das Blatt zeigt von den alten nur den jüngsten.
const kNoteRetentionDays = 90;

/// Ein Trail, wie ICH ihn sehe: die Kennung plus alle sichtbaren Belege
/// und Beiträge. Alles Angezeigte ist daraus GERECHNET (Konzept 3):
/// beste sichtbare Linie, eigener Name vor dem des ältesten Beitrags,
/// jüngster Status.
class Trail {
  Trail({
    required this.id,
    required this.recordings,
    required this.details,
    required this.myId,
    this.notes = const [],
    this.reports = const [],
    this.pending = false,
    this.pendingFailure,
    this.pendingDetails = false,
    this.sendingDetails = false,
    this.mergedFrom = const [],
  }) : assert(recordings.isNotEmpty, 'ein Trail ohne sichtbaren Beleg');

  final String id;
  final List<TrailRecording> recordings;
  final List<TrailDetails> details;
  final String myId;

  /// Wartet im Ausgangskorb (#30): Die Aufzeichnung ist noch nicht auf
  /// dem Server, [id] ist die Kennung des Auftrags. Kein Beitrag, kein
  /// Hinweis, keine Einschätzung — dafür fehlt die Server-Kennung.
  final bool pending;

  /// Der Server hat den Auftrag dauerhaft abgelehnt; der Text ist für den
  /// Nutzer. Nur bei [pending].
  final String? pendingFailure;

  /// Der eigene Beitrag zu diesem (übertragenen) Trail wartet noch im
  /// Korb — die eigene Zeile in [details] ist die wartende Fassung.
  final bool pendingDetails;

  /// Der eigene Beitrag ist gerade UNTERWEGS (#183), noch nicht im Korb:
  /// Die eigene Zeile zeigt schon, was gesetzt wurde, während der
  /// Sendeversuch läuft — ein S-Grad, der erst nach dem Neuladen
  /// erscheint, sah aus wie ein Tipp, der nicht ankam. Immer mit
  /// [pendingDetails].
  final bool sendingDetails;

  /// Die sichtbaren Hinweise, in beliebiger Reihenfolge — angezeigt über
  /// [notesShown].
  final List<TrailNote> notes;

  /// Trails, die bei mir unter diesem stehen (#107, Konzept 6.1): von mir
  /// selbst oder von direkten Buddys zum Duplikat erklärt. Ihre sichtbaren
  /// Belege, Beiträge, Hinweise und Meldungen stecken schon in den Listen
  /// hier; das Blatt nennt sie und lässt die eigenen lösen.
  final List<MergedTrail> mergedFrom;

  /// Stand [id] einmal für diesen Trail — er selbst oder ein Duplikat,
  /// das bei mir unter ihm steht? Für Kennungen von früher (Push, Fokus,
  /// ein offenes Blatt), die nach dem Zusammenführen ins Leere zeigten.
  bool answersTo(String trailId) => id == trailId || mergedFrom.any((m) => m.id == trailId);

  /// Die sichtbaren Meldungen und Zustände (#101), in beliebiger
  /// Reihenfolge — angezeigt über [shownStatus], [shownCondition] und
  /// [reportsShown].
  final List<TrailReport> reports;

  bool get isOwn => recordings.any((r) => r.userId == myId);

  /// [userId] hat den Trail nur GEPLANT: Jeder sichtbare Beleg von ihm
  /// ist eine Datei ohne Fahrzeiten (`planned`, Konzept 4.6) und ohne
  /// eingetragenes Fahrdatum ([TrailRecording.ridden]). Ohne Beleg
  /// von ihm false — dann hat er gar nichts belegt.
  bool onlyPlanned(String userId) {
    final own = recordings.where((r) => r.userId == userId);
    return own.isNotEmpty && own.every((r) => !r.ridden);
  }

  /// Alle sichtbaren Belege sind geplant — gefahren hat ihn hier
  /// nachweislich niemand.
  bool get allPlanned =>
      recordings.every((r) => !r.ridden);

  /// Die beste sichtbare Aufzeichnung: höchste Qualität, bei Gleichstand
  /// die ältere (sie hat den Trail „angelegt").
  ///
  /// Einmal je Trail gerechnet: Karte, Liste und Blatt fragen sie (über
  /// [points], [start], [lengthM] …) bei jedem Aufbau für jeden Trail.
  late final TrailRecording best = () {
    final sorted = List.of(recordings)
      ..sort((a, b) {
        final q = b.quality.compareTo(a.quality);
        return q != 0 ? q : a.createdAt.compareTo(b.createdAt);
      });
    return sorted.first;
  }();

  List<LatLng> get points => best.points;
  double get lengthM => best.lengthM;

  /// Die Punkte in TRAIL-Richtung: Die beste Aufzeichnung kann gegen die
  /// Richtung aufgenommen sein (`reversed`), dann laufen ihre Punkte
  /// rückwärts. Anfang und Ende auf der Karte (#96), die Anfahrt (#151)
  /// und der Export (#150) lesen alle hier — EINE Stelle für die Richtung.
  List<LatLng> get directedPoints {
    final b = best;
    return b.reversed ? b.points.reversed.toList() : b.points;
  }

  /// Der Anfang in Trail-Richtung.
  LatLng get start {
    final b = best;
    return b.reversed ? b.points.last : b.points.first;
  }

  /// Das Ende in Trail-Richtung.
  LatLng get end {
    final b = best;
    return b.reversed ? b.points.first : b.points.last;
  }

  /// Die beste sichtbare Aufzeichnung MIT Höhen — nicht unbedingt [best]:
  /// Sonst blieben Trails, deren älteste Aufzeichnung vor Patch 002
  /// entstand, für immer ohne Höhenmeter, auch wenn längst jemand sie mit
  /// Höhen nachgeliefert hat.
  TrailRecording? get elevationRecording {
    final withEle = recordings.where((r) => r.ele != null).toList()
      ..sort((a, b) {
        final q = b.quality.compareTo(a.quality);
        return q != 0 ? q : a.createdAt.compareTo(b.createdAt);
      });
    return withEle.firstOrNull;
  }

  /// Höhenprofil in Trail-Richtung, null ohne Höhen.
  late final ElevationProfile? elevation = () {
    final r = elevationRecording;
    return r == null
        ? null
        : ElevationProfile.of(r.points, r.ele, reversed: r.reversed);
  }();

  TrailDetails? get myDetails =>
      details.where((d) => d.userId == myId).firstOrNull;

  /// Beiträge in der Reihenfolge ihres ersten Belegs — der älteste
  /// Beitragende zuerst. Ohne Beleg (nur Beitrag) hinten.
  List<TrailDetails> get contributionsOrdered {
    DateTime firstRecording(String userId) => recordings
        .where((r) => r.userId == userId)
        .map((r) => r.createdAt)
        .fold<DateTime?>(null, (m, t) => m == null || t.isBefore(m) ? t : m) ??
        DateTime.fromMillisecondsSinceEpoch(1 << 52);
    return List.of(details)
      ..sort((a, b) => firstRecording(a.userId).compareTo(firstRecording(b.userId)));
  }

  /// Eigener Name, sonst der Name des ältesten sichtbaren Beitrags; die
  /// anderen als „auch: …" (Konzept 3, Muster Buddy-Alias).
  String displayName(AppLocalizations l) => _namedBy ?? l.trailUnnamed;

  /// Der Name ohne Platzhalter, `null` ohne Namen — für Sortieren und
  /// Vergleichen, die keine Sprache kennen sollen (#209).
  String? get name => _namedBy;

  /// Hat irgendein sichtbarer Beitrag einen Namen? Sonst zeigt
  /// [displayName] den Platzhalter — und der gehört nicht in eine
  /// fremde App (#151) oder eine Datei (#150).
  bool get hasName => _namedBy != null;

  String? get _namedBy {
    final own = myDetails?.name;
    if (own != null && own.trim().isNotEmpty) return own;
    for (final d in contributionsOrdered) {
      final n = d.name;
      if (n != null && n.trim().isNotEmpty) return n;
    }
    return null;
  }

  /// Link zur Quelle wie der Name (#103): eigener, sonst der des
  /// ältesten sichtbaren Beitrags, der einen hat.
  String? get displayLink {
    final own = myDetails?.link;
    if (own != null && own.isNotEmpty) return own;
    for (final d in contributionsOrdered) {
      final l = d.link;
      if (l != null && l.isNotEmpty) return l;
    }
    return null;
  }

  List<String> get otherNames {
    final shown = _namedBy;
    final names = <String>{};
    for (final d in details) {
      final n = d.name?.trim();
      if (n != null && n.isNotEmpty && n != shown) names.add(n);
    }
    return names.toList();
  }

  /// Die sichtbaren Einschätzungen, älteste Beiträge zuerst — „wer hat
  /// was gesagt" im Blatt.
  List<TrailDetails> get gradeVotes =>
      contributionsOrdered.where((d) => d.grade != null).toList();

  /// Leichteste und schwerste sichtbare Einschätzung (Konzept 3: „Median
  /// … mit Spanne"), null ohne Angabe.
  ({int min, int max})? get gradeRange {
    final grades = details.map((d) => d.grade).whereType<int>();
    if (grades.isEmpty) return null;
    return (
      min: grades.reduce((a, b) => a < b ? a : b),
      max: grades.reduce((a, b) => a > b ? a : b),
    );
  }

  /// Median der sichtbaren S-Grade, null ohne Angabe. Bei gerader Anzahl
  /// der SCHWERERE der beiden mittleren: Im Zweifel gewinnt die Warnung —
  /// wer einen S3 für S2 hält, liegt teurer daneben als umgekehrt.
  int? get grade {
    final grades = details.map((d) => d.grade).whereType<int>().toList()..sort();
    if (grades.isEmpty) return null;
    return grades[grades.length ~/ 2];
  }

  /// Wie viele sichtbare Beiträge welches Merkmal nennen (#72) — wie der
  /// Grad von Buddys vergeben, je Beitrag höchstens einmal.
  Map<TrailTrait, int> get traitCounts {
    final counts = <TrailTrait, int>{};
    for (final d in details) {
      for (final t in d.traits) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Die höchstens [kShownTraits] häufigsten Merkmale — das, was Liste,
  /// Blatt und Filter „der Charakter" nennen. Gleichstand: die
  /// Reihenfolge von [TrailTrait].
  List<TrailTrait> get topTraits {
    final counts = traitCounts;
    final sorted = counts.keys.toList()
      ..sort((a, b) {
        final c = counts[b]!.compareTo(counts[a]!);
        return c != 0 ? c : a.index.compareTo(b.index);
      });
    return sorted.take(kShownTraits).toList();
  }

  /// Die angezeigte Meldung (Rework, Abschnitt 9): die jüngste
  /// bestätigte, dazu verblasst die jüngste unbestätigte, wenn sie jünger
  /// ist. Ersetzt „der jüngste Status gewinnt".
  ShownReports get shownStatus =>
      shownReportsOf(reports.where((r) => r.kind == ReportKind.status));

  /// Der angezeigte Zustand — dieselbe Regel wie bei der Meldung, ohne
  /// Frist: Die jüngste bestätigte Angabe steht dauerhaft, mit ihrem
  /// Alter (Betreiber, 2026-09-30).
  ShownReports get shownCondition =>
      shownReportsOf(reports.where((r) => r.kind == ReportKind.condition));

  /// Die BESTÄTIGTE Meldung — sie färbt Karte und Liste und zählt im
  /// Filter „Gemeldet". Eine unbestätigte steht nur verblasst im Blatt.
  TrailStatus get status => shownStatus.confirmed?.status ?? TrailStatus.open;

  /// Der Verlauf im Blatt, neueste zuerst: alles aus den letzten
  /// [kReportRetentionDays] Tagen, dazu immer, was angezeigt wird.
  List<TrailReport> reportsShown({DateTime? now}) {
    final since = (now ?? DateTime.now())
        .subtract(const Duration(days: kReportRetentionDays));
    final keep = {
      for (final pair in [shownStatus, shownCondition]) ...[?pair.confirmed, ?pair.unconfirmed],
    };
    return [
      for (final r in reports)
        if (r.reportedAt.isAfter(since) || keep.contains(r)) r,
    ]..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
  }

  /// [userId] ist den Trail gefahren — eine sichtbare Aufzeichnung, die
  /// nicht nur geplant ist. Dieselbe Regel wie `has_ridden` auf dem
  /// Server; auf dem Gerät nur die Vorhersage für wartende Meldungen.
  bool hasRidden(String userId) => recordings
      .any((r) => r.userId == userId && r.ridden);

  /// Die sichtbaren Bewertungen, älteste Beiträge zuerst — „wer hat was
  /// gesagt" im Blatt.
  List<TrailDetails> get ratingVotes =>
      contributionsOrdered.where((d) => d.rating != null).toList();

  /// Median der sichtbaren Bewertungen (Rework E4/E8), null ohne Angabe.
  /// Bei gerader Anzahl der HÖHERE der beiden mittleren — wie beim S-Grad
  /// (dort im Zweifel die Warnung, hier der Betreiber, 2026-09-30).
  int? get rating {
    final ratings = details.map((d) => d.rating).whereType<int>().toList()..sort();
    if (ratings.isEmpty) return null;
    return ratings[ratings.length ~/ 2];
  }

  /// In beide Richtungen fahrbar (#174)? Die EIGENE Angabe gilt für die
  /// eigene Planung; ohne eigenen Beitrag die Mehrheit der sichtbaren
  /// Beiträge, bei Gleichstand NEIN — im Zweifel die Richtung des Trails,
  /// ein Planer, der jemanden einen Trail hinaufschickt, ist der teure
  /// Fehler. Ohne Beitrag: nein.
  bool get twoWay {
    final own = myDetails;
    if (own != null) return own.twoWay;
    if (details.isEmpty) return false;
    final yes = details.where((d) => d.twoWay).length;
    return yes * 2 > details.length;
  }

  /// Ich habe den Trail belegt, aber noch nicht bewertet: verblasste
  /// Sterne (Rework E4, Nachtrag des Betreibers) — das IST „Bewertung
  /// offen". Nicht für wartende Trails, dort gibt es keinen Beitrag.
  bool get ratingOpen => isOwn && !pending && myDetails?.rating == null;

  /// Was das Blatt zeigt, neueste zuerst: alles aus den letzten
  /// [kNoteRetentionDays] Tagen, und immer den jüngsten — der bleibt
  /// stehen, bis ihn jemand entfernt.
  List<TrailNote> notesShown({DateTime? now}) {
    final sorted = List.of(notes)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final since = (now ?? DateTime.now())
        .subtract(const Duration(days: kNoteRetentionDays));
    return [
      for (var i = 0; i < sorted.length; i++)
        if (i == 0 || sorted[i].createdAt.isAfter(since)) sorted[i],
    ];
  }

  /// Die Liste „MELDUNGEN" im Blatt (#433, `docs/konzept-melden.md` 6),
  /// neueste zuerst: Statusmeldungen nach [reportsShown], Texte nach
  /// [notesShown]; ein Text, der zu einer angezeigten Meldung gehört, steht
  /// MIT ihr in einer Zeile. Ein Text, dessen Meldung nicht im Verlauf
  /// steht, bringt sie mit, solange es sie gibt; sonst steht er allein. Den
  /// Zustand zeigt die Kachel, nicht diese Liste.
  List<TrailEntry> entriesShown({DateTime? now}) {
    final notes = notesShown(now: now);
    final byReport = {for (final n in notes) ?n.reportId: n};
    final used = <String>{};
    final out = <TrailEntry>[];
    for (final r in reportsShown(now: now)) {
      if (r.kind != ReportKind.status) continue;
      final n = byReport[r.id];
      if (n != null) used.add(n.id);
      out.add(TrailEntry(report: r, note: n));
    }
    final statusById = {
      for (final r in reports)
        if (r.kind == ReportKind.status) r.id: r,
    };
    for (final n in notes) {
      if (used.contains(n.id)) continue;
      out.add(TrailEntry(report: statusById[n.reportId], note: n));
    }
    return out..sort((a, b) => b.at.compareTo(a.at));
  }

  /// Ein Buddy hat in den letzten [kFreshNoteDays] Tagen etwas dazu
  /// geschrieben, das auf diesem Gerät noch nicht im Blatt zu sehen war
  /// ([seen]). Eigene Hinweise zählen nicht — die sind nichts Neues.
  bool hasFreshNote({DateTime? now, Set<String> seen = const {}}) =>
      notes.any((n) => isFreshNote(n, now: now, seen: seen));

  bool isFreshNote(TrailNote n, {DateTime? now, Set<String> seen = const {}}) {
    final since =
        (now ?? DateTime.now()).subtract(const Duration(days: kFreshNoteDays));
    return n.userId != myId && n.createdAt.isAfter(since) && !seen.contains(n.id);
  }

  /// Wer den Trail belegt hat, ohne mich — für „3 Buddys kennen ihn".
  Set<String> get buddyIds =>
      {for (final r in recordings) if (r.userId != myId) r.userId};
}

/// Ein Duplikat, das bei mir unter einem anderen Trail steht (#107).
/// Nach Namen, ohne Rücksicht auf Groß- und Kleinschreibung; Trails ohne
/// Namen hinten — ihr Platzhalter hängt an der Sprache (#209), die
/// Reihenfolge soll es nicht.
int compareTrailNames(Trail a, Trail b) {
  final x = a.name?.toLowerCase(), y = b.name?.toLowerCase();
  if (x == null || y == null) return x == y ? 0 : (x == null ? 1 : -1);
  return x.compareTo(y);
}

class MergedTrail {
  const MergedTrail({required this.id, required this.byMe, this.name, this.byUsers = const []});

  /// Die Kennung des Duplikats.
  final String id;

  /// Der Name, unter dem es sichtbar war — der erste sichtbare Beitrag mit
  /// Namen; null ohne.
  final String? name;

  /// Meine eigene Zuordnung — lösbar (`unmerge_trail`). Sonst hat ein
  /// direkter Buddy es erklärt ([byUsers]).
  final bool byMe;
  final List<String> byUsers;

  @override
  bool operator ==(Object other) =>
      other is MergedTrail &&
      other.id == id &&
      other.name == name &&
      other.byMe == byMe &&
      _sameValues(other.byUsers, byUsers);

  @override
  int get hashCode => Object.hash(id, name, byMe, Object.hashAll(byUsers));
}

/// Gruppiert die beiden Abfragen zu Trails. Beiträge ohne sichtbaren
/// Beleg fallen weg: Sichtbar ist, was jemand GEFAHREN ist (Konzept 6),
/// nicht, worüber jemand etwas gesagt hat.
///
/// [merges] sind die Zeilen aus `trail_merges()` (#107): Was zu einem
/// Duplikat gehört, steht unter dem behaltenen Trail ([resolveMerges]) —
/// Aufzeichnungen mit ihrer Richtung relativ zu ihm, und hat jemand an
/// beiden einen Beitrag, gilt der am behaltenen.
///
/// [previous] ist der Stand davor: Ein Trail, dessen Belege, Beiträge,
/// Hinweise und Meldungen dieselben OBJEKTE sind (`shareSnapshot`), kommt
/// als derselbe Trail zurück — mit allem, was an ihm schon gerechnet ist.
List<Trail> buildTrails({
  required List<TrailRecording> recordings,
  required List<TrailDetails> details,
  required String myId,
  List<TrailNote> notes = const [],
  List<TrailReport> reports = const [],
  List<TrailMerge> merges = const [],
  Iterable<Trail> previous = const [],
}) {
  final before = {for (final t in previous) if (!t.pending && t.myId == myId) t.id: t};
  final targets = _mergeTargets(merges, recordings);
  final mergedFrom = <String, List<MergedTrail>>{};
  if (targets.isNotEmpty) {
    for (final e in targets.entries) {
      if (!recordings.any((r) => r.trailId == e.key)) continue;
      final name = details
          .where((d) => d.trailId == e.key && (d.name ?? '').trim().isNotEmpty)
          .map((d) => d.name!.trim())
          .firstOrNull;
      (mergedFrom[e.value.to] ??= []).add(MergedTrail(
          id: e.key, name: name, byMe: e.value.byMe, byUsers: e.value.byUsers));
    }
    recordings = [
      for (final r in recordings)
        if (targets[r.trailId] case final t?) _movedRecording(r, t) else r,
    ];
    // Hat jemand an beiden einen Beitrag, gilt der am behaltenen Trail.
    final kept = {for (final d in details) if (!targets.containsKey(d.trailId)) '${d.trailId}|${d.userId}'};
    details = [
      for (final d in details)
        if (targets[d.trailId] case final t?)
          ...[if (kept.add('${t.to}|${d.userId}')) _moved(d, t.to, () => d.withTrailId(t.to))]
        else
          d,
    ];
    notes = [
      for (final n in notes)
        if (targets[n.trailId] case final t?) _moved(n, t.to, () => n.withTrailId(t.to)) else n,
    ];
    reports = [
      for (final r in reports)
        if (targets[r.trailId] case final t?) _moved(r, t.to, () => r.withTrailId(t.to)) else r,
    ];
  }
  final byTrail = <String, List<TrailRecording>>{};
  for (final r in recordings) {
    byTrail.putIfAbsent(r.trailId, () => []).add(r);
  }
  final detailsByTrail = <String, List<TrailDetails>>{};
  for (final d in details) {
    detailsByTrail.putIfAbsent(d.trailId, () => []).add(d);
  }
  final notesByTrail = <String, List<TrailNote>>{};
  for (final n in notes) {
    notesByTrail.putIfAbsent(n.trailId, () => []).add(n);
  }
  final reportsByTrail = <String, List<TrailReport>>{};
  for (final r in reports) {
    reportsByTrail.putIfAbsent(r.trailId, () => []).add(r);
  }
  Trail make(String id, List<TrailRecording> recs) {
    final d = detailsByTrail[id] ?? const <TrailDetails>[];
    final n = notesByTrail[id] ?? const <TrailNote>[];
    final r = reportsByTrail[id] ?? const <TrailReport>[];
    final m = mergedFrom[id] ?? const <MergedTrail>[];
    final old = before[id];
    if (old != null &&
        !old.pendingDetails &&
        _sameObjects(old.recordings, recs) &&
        _sameObjects(old.details, d) &&
        _sameObjects(old.notes, n) &&
        _sameObjects(old.reports, r) &&
        _sameValues(old.mergedFrom, m)) {
      return old;
    }
    return Trail(
        id: id, recordings: recs, details: d, myId: myId, notes: n, reports: r, mergedFrom: m);
  }

  return [
    for (final e in byTrail.entries) make(e.key, e.value),
  ]..sort(compareTrailNames);
}

/// [resolveMerges] mit dem Alter jedes Trails aus seiner ältesten
/// sichtbaren Aufzeichnung.
Map<String, MergeTarget> _mergeTargets(List<TrailMerge> merges, List<TrailRecording> recordings) {
  if (!merges.any((m) => m.kind == TrailMergeKind.own || m.kind == TrailMergeKind.folded)) {
    return const {};
  }
  final firstSeen = <String, DateTime>{};
  for (final r in recordings) {
    final t = firstSeen[r.trailId];
    if (t == null || r.createdAt.isBefore(t)) firstSeen[r.trailId] = r.createdAt;
  }
  return resolveMerges(merges, ageOf: (id) => firstSeen[id]);
}

/// Die umgehängte Fassung einer Zeile bleibt je Ziel DASSELBE Objekt —
/// sonst baute jedes Neuladen jeden zusammengeführten Trail neu, samt
/// geglätteter Linie und Höhenprofil (siehe `trail_sharing.dart`). Die
/// Zeilen selbst teilt `shareSnapshot` über die Abrufe hinweg.
final _movedRows = Expando<(String, bool, Object)>('trail-merge');

T _moved<T extends Object>(T row, String to, T Function() copy, {bool flip = false}) {
  final hit = _movedRows[row];
  if (hit != null && hit.$1 == to && hit.$2 == flip) return hit.$3 as T;
  final made = copy();
  _movedRows[row] = (to, flip, made);
  return made;
}

TrailRecording _movedRecording(TrailRecording r, MergeTarget t) =>
    _moved(r, t.to, flip: t.reversed, () => r.movedTo(t.to, flip: t.reversed));

bool _sameValues<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameObjects<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}
