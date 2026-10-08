// Der Ausgangskorb (#30, Konzept 4.7 und 8): Aufträge, die ohne Empfang
// entstanden sind, warten hier auf die nächste Verbindung. Baustein aus
// PilzBuddy (#267 dort), auf vier Aufträge zugeschnitten.
//
// **Warum es ihn braucht.** Beisteuern ging bis 0.13.0 direkt an die RPC
// und scheiterte im Funkloch mit „Keine Verbindung" — die Aufzeichnung
// war weg, wenn niemand sie zu Hause noch einmal wählte. Genau falsch
// herum: Der Trail ist der Ort ohne Netz.
//
// **Der Korb trägt das Original, keine Kopie.** Deshalb WIRFT
// [Outbox.append], wenn der Auftrag nicht sicher liegt — der Aufrufer
// meldet dann den ursprünglichen Netzfehler. Still „gespeichert" zu
// melden wäre die schlimmste Variante.
//
// **Nur `looksOffline` führt hierher.** Ein Serverfehler muss sichtbar
// scheitern, sonst sammelte der Korb still Aufträge, die nie durchgehen,
// und ein kaputtes Deployment bliebe unbemerkt.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../features/trails/trail_geometry.dart' show RecordingSource;
import '../models/trail.dart';
import 'feedback_repository.dart' show FeedbackType;

/// Ein Auftrag im Korb. Genau VIER Arten — die Schreibwege, die draußen
/// vorkommen: eine Aufzeichnung beisteuern, den eigenen Beitrag speichern,
/// melden (seit 0.49.0, #101 — die Meldung stand bis dahin im Beitrag,
/// und „gesperrt" meldet man am Trail, also ohne Netz) und Feedback (seit
/// 0.86.0, #218 — der Wunsch kommt draußen, und verworfen ist er weg).
/// Höhen nachtragen, Hinweise allein, Löschen scheitern weiter sichtbar:
/// Schreibtischarbeit im WLAN.
sealed class OutboxJob {
  const OutboxJob({
    required this.id,
    required this.createdAt,
    this.attempts = 0,
    this.failure,
  });

  /// Bei einer Aufzeichnung zugleich ihre `client_id` — die Kennung, mit
  /// der der Server einen zweiten Versuch als denselben erkennt.
  final String id;
  final DateTime createdAt;

  /// Wie oft die Wiedervorlage es schon versucht hat.
  final int attempts;

  /// Gesetzt heißt: endgültig abgelehnt, wird nicht mehr versucht. Der
  /// Text ist für den Nutzer, nicht fürs Log.
  final String? failure;

  Map<String, dynamic> toJson();

  OutboxJob copyWith({int? attempts, String? failure, bool clearFailure = false});

  static OutboxJob? tryParse(Map<String, dynamic> json) {
    try {
      final id = json['id'] as String?;
      final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
      if (id == null || createdAt == null) return null;
      final attempts = json['attempts'] as int? ?? 0;
      final failure = json['failure'] as String?;
      switch (json['kind']) {
        case 'contribute':
          final coords = [for (final c in json['coords'] as List) (c as num).toDouble()];
          final rawEles = json['eles'] as List?;
          final eles = rawEles == null
              ? null
              : [for (final e in rawEles) (e as num).toDouble()];
          if (coords.length < 4 || coords.length.isOdd) return null;
          if (eles != null && eles.length * 2 != coords.length) return null;
          return ContributeJob(
            id: id,
            createdAt: createdAt,
            coords: coords,
            eles: eles,
            source: RecordingSource.values
                .firstWhere((s) => s.name == json['source'], orElse: () => RecordingSource.import),
            recordedAt: DateTime.tryParse(json['recorded_at'] as String? ?? '')?.toUtc(),
            name: json['name'] as String?,
            link: json['link'] as String?,
            grade: json['grade'] as int?,
            traits: {
              for (final t in json['traits'] as List? ?? const []) ?TrailTrait.fromDb(t as String?),
            },
            rating: switch (json['rating']) {
              final int r when r >= 1 && r <= kRatingMax => r,
              _ => null,
            },
            attempts: attempts,
            failure: failure,
          );
        case 'details':
          final details = json['details'] as Map<String, dynamic>;
          // Ein Auftrag von vor 0.49.0 trägt den Status noch im Beitrag —
          // er geht beim Nachholen als Meldung raus, zu seiner Zeit.
          final legacyAt = DateTime.tryParse(details['status_at'] as String? ?? '');
          return DetailsJob(
            id: id,
            createdAt: createdAt,
            details: TrailDetails.fromJson(details),
            note: json['note'] as String?,
            legacyStatus: legacyAt == null ? null : TrailStatus.fromDb(details['status'] as String?),
            legacyStatusAt: legacyAt?.toUtc(),
            attempts: attempts,
            failure: failure,
          );
        case 'report':
          final status = json['status'] == null ? null : TrailStatus.fromDb(json['status'] as String?);
          final condition = json['condition'] as int?;
          if (status == null && condition == null) return null;
          return ReportJob(
            id: id,
            createdAt: createdAt,
            trailId: json['trail_id'] as String,
            status: status,
            condition: condition,
            onSite: json['on_site'] as bool? ?? false,
            note: json['note'] as String?,
            attempts: attempts,
            failure: failure,
          );
        case 'feedback':
          final message = json['message'] as String?;
          if (message == null || message.trim().isEmpty) return null;
          return FeedbackJob(
            id: id,
            createdAt: createdAt,
            type: json['type'] == 'bug' ? FeedbackType.bug : FeedbackType.feature,
            message: message,
            appVersion: json['app_version'] as String?,
            attempts: attempts,
            failure: failure,
          );
        default:
          return null; // Ein Auftragstyp, den dieser Stand nicht kennt.
      }
    } catch (_) {
      return null;
    }
  }
}

/// Eine Aufzeichnung beisteuern — die Linie so, wie sie an die RPC ging
/// (vereinfacht, flach), mit dem Namen aus der Datei, der danach als
/// eigener Name übernommen wird.
class ContributeJob extends OutboxJob {
  const ContributeJob({
    required super.id,
    required super.createdAt,
    required this.coords,
    this.eles,
    required this.source,
    this.recordedAt,
    this.name,
    this.link,
    this.grade,
    this.traits = const {},
    this.rating,
    super.attempts,
    super.failure,
  });

  /// `[lon, lat, lon, lat, …]`, wie `contribute_recording` es nimmt.
  final List<double> coords;
  final List<double>? eles;
  final RecordingSource source;
  final DateTime? recordedAt;
  final String? name;

  /// Der Link zur Quelle aus der Datei (#103) — geht wie der Name nur in
  /// einen Beitrag, der noch keinen hat. Fehlt bei Aufträgen vor 0.48.0.
  final String? link;

  /// Der S-Grad aus dem Zerlege-Blatt (#29), der mit dem Namen in den
  /// eigenen Beitrag geht — null, wenn keiner gewählt war.
  final int? grade;

  /// Der Charakter aus dem Zerlege-Blatt (#72) — leer, wenn keiner gewählt
  /// war. Fehlt der Schlüssel (Auftrag von vor 0.35.0), ist er leer.
  final Set<TrailTrait> traits;

  /// Die Sterne beim Übernehmen eines Buddy-Trails (#102) — gehen nur in
  /// einen Beitrag ohne eigene Bewertung. Fehlt bei Aufträgen vor 0.55.0.
  final int? rating;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'contribute',
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'failure': failure,
        'coords': coords,
        'eles': eles,
        'source': source.name,
        'recorded_at': recordedAt?.toUtc().toIso8601String(),
        'name': name,
        'link': link,
        'grade': grade,
        'traits': [for (final t in TrailTrait.values) if (traits.contains(t)) t.db],
        'rating': rating,
      };

  @override
  ContributeJob copyWith({int? attempts, String? failure, bool clearFailure = false}) =>
      ContributeJob(
        id: id,
        createdAt: createdAt,
        coords: coords,
        eles: eles,
        source: source,
        recordedAt: recordedAt,
        name: name,
        link: link,
        grade: grade,
        traits: traits,
        rating: rating,
        attempts: attempts ?? this.attempts,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// Den eigenen Beitrag zu einem Trail speichern, der auf dem Server
/// schon existiert — samt Hinweis zum geänderten Status, wenn einer
/// mitgegeben wurde (beides gehört zusammen).
class DetailsJob extends OutboxJob {
  const DetailsJob({
    required super.id,
    required super.createdAt,
    required this.details,
    this.note,
    this.legacyStatus,
    this.legacyStatusAt,
    super.attempts,
    super.failure,
  });

  final TrailDetails details;

  /// Nur Aufträge von vor 0.49.0: der Hinweis zum geänderten Status.
  final String? note;

  /// Nur Aufträge von vor 0.49.0: der Status, der damals im Beitrag stand,
  /// und seine Zeit. Er geht als Meldung raus (`report_trail`); der
  /// Server entscheidet, ob er bestätigt ist, und eine ältere Meldung
  /// verdrängt keine jüngere.
  final TrailStatus? legacyStatus;
  final DateTime? legacyStatusAt;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'details',
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'failure': failure,
        'details': {
          ...details.toRow(),
          if (legacyStatus != null) 'status': legacyStatus!.db,
          if (legacyStatusAt != null) 'status_at': legacyStatusAt!.toUtc().toIso8601String(),
        },
        'note': note,
      };

  @override
  DetailsJob copyWith({int? attempts, String? failure, bool clearFailure = false}) =>
      DetailsJob(
        id: id,
        createdAt: createdAt,
        details: details,
        note: note,
        legacyStatus: legacyStatus,
        legacyStatusAt: legacyStatusAt,
        attempts: attempts ?? this.attempts,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// Eine Meldung und/oder einen Zustand zu einem Trail (#101). [id] ist
/// zugleich die `client_id` für `report_trail`, [createdAt] die Zeit des
/// Meldens — sie geht mit, damit „gesperrt" von gestern nicht als
/// Meldung von heute ankommt. [onSite] ist beim Melden geprüft worden.
class ReportJob extends OutboxJob {
  const ReportJob({
    required super.id,
    required super.createdAt,
    required this.trailId,
    this.status,
    this.condition,
    required this.onSite,
    this.note,
    super.attempts,
    super.failure,
  }) : assert(status != null || condition != null);

  final String trailId;
  final TrailStatus? status;
  final int? condition;
  final bool onSite;

  /// Der Hinweis dazu — der sagt WARUM.
  final String? note;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'report',
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'failure': failure,
        'trail_id': trailId,
        'status': status?.db,
        'condition': condition,
        'on_site': onSite,
        'note': note,
      };

  @override
  ReportJob copyWith({int? attempts, String? failure, bool clearFailure = false}) => ReportJob(
        id: id,
        createdAt: createdAt,
        trailId: trailId,
        status: status,
        condition: condition,
        onSite: onSite,
        note: note,
        attempts: attempts ?? this.attempts,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// Ein Wunsch oder eine Fehlermeldung an den Betreiber (#218), geschrieben
/// ohne Empfang. [id] ist zugleich die `client_id` in `public.feedback`
/// (Patch 018) — ein Nachholen nach abgerissener Antwort legt kein zweites
/// öffentliches Issue an. Hängt an keinem Trail und steht deshalb weder
/// auf der Karte noch in der Liste; Wartendes und Abgelehntes zeigt die
/// Glühbirne.
class FeedbackJob extends OutboxJob {
  const FeedbackJob({
    required super.id,
    required super.createdAt,
    required this.type,
    required this.message,
    this.appVersion,
    super.attempts,
    super.failure,
  });

  final FeedbackType type;
  final String message;

  /// Die Version beim SCHREIBEN, nicht beim Nachholen — die Meldung gilt
  /// dem Stand, in dem es passiert ist.
  final String? appVersion;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'feedback',
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'failure': failure,
        'type': type == FeedbackType.bug ? 'bug' : 'feature',
        'message': message,
        'app_version': appVersion,
      };

  @override
  FeedbackJob copyWith({int? attempts, String? failure, bool clearFailure = false}) =>
      FeedbackJob(
        id: id,
        createdAt: createdAt,
        type: type,
        message: message,
        appVersion: appVersion,
        attempts: attempts ?? this.attempts,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// Die Ablage-Form: EIN JSON-Text mit dem Konto, dem er gehört.
String encodeOutbox(List<OutboxJob> jobs, {required String uid}) => jsonEncode({
      'uid': uid,
      'jobs': [for (final job in jobs) job.toJson()],
    });

/// Liest [text] zurück — oder `const []`, wenn nichts Brauchbares darin
/// steht oder der Inhalt einem anderen Konto gehört. Wirft nie; ein
/// einzelner unlesbarer Auftrag fällt weg, der Rest bleibt.
List<OutboxJob> decodeOutbox(String text, {required String uid}) {
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) return const [];
    // Fremdes Konto: Die Aufträge eines anderen Nutzers dürfen nie in
    // einer fremden Sitzung hochgehen — sie trügen dessen Linien in mein
    // Konto.
    if (json['uid'] != uid) return const [];
    final jobs = <OutboxJob>[];
    for (final raw in json['jobs'] as List<dynamic>? ?? const []) {
      final job = OutboxJob.tryParse(raw as Map<String, dynamic>);
      if (job != null) jobs.add(job);
    }
    return jobs;
  } catch (_) {
    return const [];
  }
}

/// Der Korb wirft beim Lesen nie, beim **Schreiben** aber sehr wohl.
abstract interface class Outbox {
  Future<List<OutboxJob>> read({required String uid});

  /// Hängt einen Auftrag an. Wirft, wenn er nicht sicher liegt.
  Future<void> append(OutboxJob job, {required String uid});

  /// Schreibt den ganzen Korb neu — der Weg der Wiedervorlage: „erledigt"
  /// und „Zähler hochgesetzt" werden GEMEINSAM gültig.
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid});

  /// Sichert die Ablage zu, dass niemand sie von sich aus räumt? Eine
  /// Datei ja; ein Browser darf unter Speicherdruck aufräumen, und dann
  /// wäre das Original weg (#153, `outbox_idb.dart`).
  Future<bool> isDurable();
}

/// Der Korb als Datei im App-Verzeichnis (Android). `outbox/` steht in
/// beiden Backup-Ausschlüssen: Hier liegen Linien, BEVOR sie irgendwo
/// anders liegen.
class FileOutbox implements Outbox {
  FileOutbox({Directory? baseDir}) : _baseDirOverride = baseDir;

  final Directory? _baseDirOverride;

  static const dirName = 'outbox';

  /// Lese-Ändern-Schreiben ist hier die Regel: Die Wiedervorlage arbeitet
  /// den Korb ab, während der Import einen weiteren Auftrag ablegt.
  Future<void> _lock = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _file() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/jobs.json');
  }

  @override
  Future<List<OutboxJob>> read({required String uid}) =>
      _serialized(() => _readUnlocked(uid: uid));

  Future<List<OutboxJob>> _readUnlocked({required String uid}) async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      return decodeOutbox(await file.readAsString(), uid: uid);
    } catch (_) {
      // Unlesbar heißt „kein Korb". Kein `logError`: ein Bericht je Start.
      return const [];
    }
  }

  @override
  Future<void> append(OutboxJob job, {required String uid}) => _serialized(() async {
        final jobs = await _readUnlocked(uid: uid);
        await _writeUnlocked([...jobs, job], uid: uid);
      });

  @override
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid}) =>
      _serialized(() => _writeUnlocked(jobs, uid: uid));

  /// `.part` + `rename`: Ein Abbruch mitten im Schreiben darf keine halbe
  /// Datei hinterlassen. Anders als bei einer Kopie wird hier NICHTS
  /// geschluckt.
  Future<void> _writeUnlocked(List<OutboxJob> jobs, {required String uid}) async {
    final file = await _file();
    final temp = File('${file.path}.part');
    await temp.writeAsString(encodeOutbox(jobs, uid: uid), flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<bool> isDurable() async => true;
}

/// Kein Ort zum Ablegen, also kein Korb: [append] wirft, und der Aufrufer
/// meldet den ursprünglichen Netzfehler — wie vor diesem Feature. Seit
/// #153 nur noch der Browser OHNE IndexedDB (privater Modus, `file://`);
/// mit IndexedDB gilt `IdbOutbox`.
class NoOutbox implements Outbox {
  const NoOutbox();

  @override
  Future<List<OutboxJob>> read({required String uid}) async => const [];

  @override
  Future<void> append(OutboxJob job, {required String uid}) async =>
      throw const OutboxUnavailable();

  @override
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid}) async {}

  /// Hier liegt nie etwas, also kann auch nichts verfallen.
  @override
  Future<bool> isDurable() async => true;
}

class OutboxUnavailable implements Exception {
  const OutboxUnavailable();

  @override
  String toString() => 'Auf dieser Plattform gibt es keinen Ausgangskorb';
}
