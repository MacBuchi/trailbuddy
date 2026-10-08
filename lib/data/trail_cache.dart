// Der Zwischenspeicher des eigenen Netzes (#32, Konzept 4.7) — damit die
// Karte ohne Empfang etwas zeigt, auch wenn die App dort NEU startet.
// PilzBuddys `spot_cache.dart` ist die Vorlage.
//
// **Warum es ihn braucht.** `trailsProvider` holt alles aus Supabase. Ein
// fehlgeschlagener Refresh ist harmlos (Riverpod behält den Vorwert),
// aber beim Kaltstart ohne Empfang gibt es keinen Vorwert — und die Karte
// stand kommentarlos leer. Genau im Wald.
//
// **Eine Kopie, kein Original.** Deshalb wirft hier nichts: Eine
// fehlende Kopie darf einen erfolgreichen Abruf nie kaputtmachen. Und
// **nur `looksOffline` liest die Kopie** (PilzBuddy #80): Ein
// Serverfehler muss sichtbar bleiben, sonst zeigte die App bei kaputtem
// Deployment wochenlang einen alten Stand als aktuellen.
//
// **Abgelegt wird die Zeilenform** — dieselbe, die auch vom Netz kommt,
// gelesen von denselben `fromJson`. Die Encoder hier sind die zweite
// Hälfte dazu; `test/trails/trail_cache_test.dart` prüft den Rundlauf
// Feld für Feld, damit die beiden Abbildungen nicht auseinanderlaufen.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/errors.dart';
import '../models/trail.dart';

/// Was das Netz auf einen Schlag liefert: die vier Tabellen des Netzes
/// (die Meldungen seit Patch 013).
typedef TrailSnapshot = ({
  List<TrailRecording> recordings,
  List<TrailDetails> details,
  List<TrailNote> notes,
  List<TrailReport> reports,
});

/// Ein Abruf mit Herkunft: `cachedAt == null` heißt frisch aus dem Netz.
typedef TrailSnapshotResult = ({TrailSnapshot snapshot, DateTime? cachedAt});

abstract interface class TrailCache {
  Future<({TrailSnapshot snapshot, DateTime savedAt})?> read({required String uid});
  Future<void> write({required String uid, required TrailSnapshot snapshot, required DateTime savedAt});
  Future<void> clear();
}

Map<String, dynamic> recordingToRow(TrailRecording r) => {
      'id': r.id,
      'trail_id': r.trailId,
      'user_id': r.userId,
      'source': r.source.name,
      'recorded_at': r.recordedAt?.toUtc().toIso8601String(),
      'reversed': r.reversed,
      'quality': r.quality,
      'created_at': r.createdAt.toUtc().toIso8601String(),
      'geojson': {
        'type': 'LineString',
        'coordinates': [for (final p in r.points) [p.longitude, p.latitude]],
      },
      'length_m': r.lengthM,
      'ele': r.ele,
    };

Map<String, dynamic> detailsToRow(TrailDetails d) => {
      ...d.toRow(),
      'updated_at': d.updatedAt?.toUtc().toIso8601String(),
      'contributor': d.username == null ? null : {'username': d.username},
    };

Map<String, dynamic> noteToRow(TrailNote n) => {
      'id': n.id,
      'trail_id': n.trailId,
      'user_id': n.userId,
      'body': n.body,
      'created_at': n.createdAt.toUtc().toIso8601String(),
      'author': n.username == null ? null : {'username': n.username},
    };

/// EIN JSON-Text mit dem Konto, dem er gehört.
String encodeTrailCache({required String uid, required TrailSnapshot snapshot, required DateTime savedAt}) =>
    jsonEncode({
      'uid': uid,
      'saved_at': savedAt.toUtc().toIso8601String(),
      'recordings': [for (final r in snapshot.recordings) recordingToRow(r)],
      'details': [for (final d in snapshot.details) detailsToRow(d)],
      'notes': [for (final n in snapshot.notes) noteToRow(n)],
      'reports': [for (final r in snapshot.reports) r.toRow()],
    });

/// Derselbe Text wie [encodeTrailCache], aber in Häppchen: Nach jeweils
/// [slice] Rechenzeit gibt es den Haupt-Thread frei, damit Eingaben und
/// Bilder dazwischen drankommen (Feldbericht 2026-10-02). Die Linien sind
/// der teure Teil — gemessen an 600 Trails 0,8 s am Stück, und das bei
/// jedem Laden des Netzes. Kein Isolate: Das Kopieren des Stands hinüber
/// kostete wieder den Haupt-Thread, und in der Test-Zone antwortet keins.
Future<String> encodeTrailCacheInSlices({
  required String uid,
  required TrailSnapshot snapshot,
  required DateTime savedAt,
  Duration slice = const Duration(milliseconds: 4),
}) async {
  final out = StringBuffer()
    ..write('{"uid":${jsonEncode(uid)},"saved_at":${jsonEncode(savedAt.toUtc().toIso8601String())},"recordings":[');
  final clock = Stopwatch()..start();
  for (var i = 0; i < snapshot.recordings.length; i++) {
    if (i > 0) out.write(',');
    out.write(jsonEncode(recordingToRow(snapshot.recordings[i])));
    if (clock.elapsed >= slice) {
      await Future<void>.delayed(Duration.zero);
      clock.reset();
    }
  }
  out
    ..write('],"details":')
    ..write(jsonEncode([for (final d in snapshot.details) detailsToRow(d)]))
    ..write(',"notes":')
    ..write(jsonEncode([for (final n in snapshot.notes) noteToRow(n)]))
    ..write(',"reports":')
    ..write(jsonEncode([for (final r in snapshot.reports) r.toRow()]))
    ..write('}');
  return out.toString();
}

/// Liest [text] zurück — `null`, wenn nichts Brauchbares darin steht oder
/// der Inhalt einem anderen Konto gehört. Die Trails eines anderen
/// Nutzers dürfen nie in einer fremden Sitzung auftauchen.
({TrailSnapshot snapshot, DateTime savedAt})? decodeTrailCache(String text, {required String uid}) {
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) return null;
    if (json['uid'] != uid) return null;
    final savedAt = DateTime.tryParse(json['saved_at'] as String? ?? '');
    if (savedAt == null) return null;
    List<Map<String, dynamic>> rows(String key) =>
        (json[key] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    return (
      snapshot: (
        recordings: [for (final r in rows('recordings')) TrailRecording.fromJson(r)],
        details: [for (final d in rows('details')) TrailDetails.fromJson(d)],
        notes: [for (final n in rows('notes')) TrailNote.fromJson(n)],
        // Fehlt bei einer Kopie von vor 0.49.0: dann eben keine Meldungen.
        reports: [for (final r in rows('reports')) ?TrailReport.fromJson(r)],
      ),
      savedAt: savedAt.toLocal(),
    );
  } catch (_) {
    return null;
  }
}

/// Was jede Ablage der Kopie gemeinsam hat: Schreiben und Löschen laufen
/// nacheinander, ein überholtes Schreiben fällt weg, und nichts wirft.
/// Die Ablage selbst — Datei oder IndexedDB (`trail_cache_idb.dart`) —
/// kennt nur Text.
abstract class QueuedTrailCache implements TrailCache {
  /// Legt [text] ab. Darf werfen; geschluckt wird hier.
  Future<void> storeText(String text);

  /// Der abgelegte Text oder `null`. Darf werfen; geschluckt wird hier.
  Future<String?> loadText();

  /// Entfernt die Kopie. Darf werfen; geschluckt wird hier.
  Future<void> removeText();

  /// Schreiben und Löschen laufen nacheinander: Das Schreiben gibt
  /// zwischendurch den Haupt-Thread frei ([encodeTrailCacheInSlices]),
  /// und zwei Läufe zugleich teilten sich sonst die Ablage — oder ein
  /// Schreiben legte die Kopie nach dem Abmelden wieder an.
  Future<void> _queue = Future.value();

  /// Zählt die Aufträge: Ein Schreiben, hinter dem schon ein neueres oder
  /// ein Löschen wartet, legt nichts mehr ab.
  int _generation = 0;

  Future<void> _enqueue(Future<void> Function(int generation) job) {
    final generation = ++_generation;
    final next = _queue.then((_) => job(generation));
    _queue = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<void> write({required String uid, required TrailSnapshot snapshot, required DateTime savedAt}) =>
      _enqueue((generation) async {
        try {
          if (generation != _generation) return;
          final text = await encodeTrailCacheInSlices(uid: uid, snapshot: snapshot, savedAt: savedAt);
          if (generation != _generation) return;
          await storeText(text);
        } catch (_) {
          // Volle Platte, fehlende Rechte, voller Browser-Speicher: Dann
          // gibt es eben keine Kopie. Der Abruf war erfolgreich und darf
          // daran nicht scheitern.
        }
      });

  @override
  Future<({TrailSnapshot snapshot, DateTime savedAt})?> read({required String uid}) async {
    try {
      final text = await loadText();
      return text == null ? null : decodeTrailCache(text, uid: uid);
    } catch (_) {
      // Unlesbar heißt „keine Kopie". Kein `logError`: ein Bericht je Start.
      return null;
    }
  }

  /// Beim Abmelden: Das Netz des abgemeldeten Kontos hat auf dem Gerät
  /// nichts mehr verloren — es ist eine Kopie, es geht nichts verloren.
  @override
  Future<void> clear() => _enqueue((_) async {
        try {
          await removeText();
        } catch (_) {
          // Ein Löschfehler darf das Abmelden nicht aufhalten.
        }
      });
}

/// Die Datei im App-Verzeichnis (Android). `trail_cache/` steht in beiden
/// Backup-Ausschlüssen: Googles Cloud ist in der Datenschutzerklärung
/// kein Empfänger.
class FileTrailCache extends QueuedTrailCache {
  FileTrailCache({Directory? baseDir}) : _baseDirOverride = baseDir;

  final Directory? _baseDirOverride;

  static const dirName = 'trail_cache';

  Future<File> _file() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/network.json');
  }

  /// `.part` + `rename`: Ein Abbruch mitten im Schreiben darf keine halbe
  /// Datei hinterlassen — das wäre genau der Zustand, den die Kopie
  /// beseitigen soll.
  @override
  Future<void> storeText(String text) async {
    final file = await _file();
    final temp = File('${file.path}.part');
    await temp.writeAsString(text, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<String?> loadText() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> removeText() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

/// Kein Ort zum Ablegen: der Browser ohne IndexedDB (privater Modus,
/// `file://`; mit IndexedDB gilt seit #153 `IdbTrailCache`) — und der
/// Fall in Tests, die keine Kopie wollen.
class NoTrailCache implements TrailCache {
  const NoTrailCache();

  @override
  Future<({TrailSnapshot snapshot, DateTime savedAt})?> read({required String uid}) async => null;

  @override
  Future<void> write({required String uid, required TrailSnapshot snapshot, required DateTime savedAt}) async {}

  @override
  Future<void> clear() async {}
}

/// Netz zuerst, Kopie als Rückfalllinie — und zwar NUR bei fehlendem
/// Empfang. Als freie Funktion, damit die Regel ohne Supabase prüfbar
/// ist: [fetch] ist im Test eine Funktion, die wirft.
Future<TrailSnapshotResult> fetchWithCache({
  required Future<TrailSnapshot> Function() fetch,
  required TrailCache cache,
  required String uid,
  required DateTime now,
}) async {
  final TrailSnapshot snapshot;
  try {
    snapshot = await fetch();
  } catch (error) {
    // Ein Serverfehler bleibt sichtbar; ein 504 zählt wie kein Netz.
    if (!looksOffline(error)) rethrow;
    final cached = await cache.read(uid: uid);
    if (cached == null) rethrow;
    return (snapshot: cached.snapshot, cachedAt: cached.savedAt);
  }
  // Nicht abgewartet: Die Kopie ist für das NÄCHSTE Mal; die Karte soll
  // nicht warten, bis Megabytes auf der Platte liegen.
  unawaited(cache.write(uid: uid, snapshot: snapshot, savedAt: now));
  return (snapshot: snapshot, cachedAt: null);
}

/// Wie lange der Kaltstart auf das Netz wartet, bevor er die Kopie zeigt
/// (#183). Kurz, weil das Netz im Wald nicht schnell ABLEHNT, sondern
/// langsam: postgrest wiederholt ein GET bei jedem Netzfehler dreimal,
/// mit 1, 2 und 4 s Pause — ohne Empfang kam die Kopie so erst nach
/// rund 7 s, bei einem Balken ohne Daten noch später. Lang genug, dass
/// ein gewöhnliches Netz gewinnt und die Kopie gar nicht erst aufblitzt.
const kTrailsNetworkPatience = Duration(milliseconds: 1500);

/// Der Kaltstart (#183): Netz und Uhr laufen gleichzeitig los. Antwortet
/// das Netz innerhalb von [patience], gilt dieselbe Regel wie bei
/// [fetchWithCache]. Sonst kommt SOFORT die Kopie, und das Netz läuft
/// weiter — nur dann ruft die Funktion [onStillWaiting], bevor sie die
/// Kopie zurückgibt: [onLate] bekommt den frischen Stand (die Kopie ist dann schon
/// neu geschrieben), [onLateOffline] sagt, dass es ohne Antwort aufgab,
/// [onLateError] meldet einen Serverfehler — der bleibt sichtbar, auch
/// wenn die Kopie schon steht (PilzBuddy #80).
///
/// Ohne Kopie wird gewartet wie bisher: Eine leere Karte vorab wäre keine
/// Antwort, sondern eine falsche. Die Uhr ist ein [Timer], der beim Sieg
/// des Netzes abgebrochen wird — ein `Future.delayed` liefe im
/// Widget-Test über das Testende hinaus.
Future<TrailSnapshotResult> fetchWithCacheQuick({
  required Future<TrailSnapshot> Function() fetch,
  required TrailCache cache,
  required String uid,
  required DateTime now,
  required Duration patience,
  required void Function(TrailSnapshot fresh) onLate,
  required void Function() onLateOffline,
  required void Function(Object error, StackTrace stackTrace) onLateError,
  void Function()? onStillWaiting,
}) async {
  final settled = fetch().then<_Fetched>((s) => _Fetched(s),
      onError: (Object e, StackTrace st) => _Fetched.failed(e, st));
  final first = Completer<_Fetched?>();
  final clock = Timer(patience, () {
    if (!first.isCompleted) first.complete(null);
  });
  unawaited(settled.then((r) {
    clock.cancel();
    if (!first.isCompleted) first.complete(r);
  }));

  Future<TrailSnapshotResult> settle(_Fetched r) =>
      fetchWithCache(fetch: r.get, cache: cache, uid: uid, now: now);

  final quick = await first.future;
  if (quick != null) return settle(quick);
  final cached = await cache.read(uid: uid);
  if (cached == null) return settle(await settled);
  unawaited(settled.then((r) async {
    final error = r.error;
    if (error == null) {
      await cache.write(uid: uid, snapshot: r.snapshot!, savedAt: DateTime.now());
      onLate(r.snapshot!);
    } else if (looksOffline(error)) {
      onLateOffline();
    } else {
      onLateError(error, r.stackTrace!);
    }
  }));
  onStillWaiting?.call();
  return (snapshot: cached.snapshot, cachedAt: cached.savedAt);
}

/// Ausgang eines Abrufs, ohne zu werfen — damit er auf zwei Wegen
/// abgewartet werden kann, ohne einen unbehandelten Fehler zu erzeugen.
class _Fetched {
  _Fetched(TrailSnapshot this.snapshot)
      : error = null,
        stackTrace = null;
  _Fetched.failed(Object this.error, StackTrace this.stackTrace) : snapshot = null;

  final TrailSnapshot? snapshot;
  final Object? error;
  final StackTrace? stackTrace;

  Future<TrailSnapshot> get() async {
    final e = error;
    if (e != null) Error.throwWithStackTrace(e, stackTrace!);
    return snapshot!;
  }
}
