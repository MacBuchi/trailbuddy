// Der Ausgangskorb im Browser (#153; PilzBuddy #386 als Vorlage).
//
// Dieselbe Aufgabe wie `FileOutbox`, nur ohne Dateisystem, und derselbe
// Unterschied zur Kopie des Netzes: **Der Korb trägt das Original.**
// Kommt der Auftrag nicht unter, ist die Aufzeichnung weg — also wirft
// [IdbOutbox.append], und der Aufrufer meldet den ursprünglichen
// Netzfehler. „Gespeichert" zu behaupten wäre die schlimmste Variante.
//
// Was im Browser dazukommt: **Der Speicher darf ohne Vorwarnung geräumt
// werden.** Dagegen hilft nur `navigator.storage.persist()`, erbeten
// beim ersten Ablegen. Lehnt der Browser ab, wird TROTZDEM abgelegt —
// Chrome lehnt in einem gewöhnlichen Tab regelmäßig ab, und dann wäre
// die Aufzeichnung sofort verloren statt vielleicht später —, und die
// Karte sagt es (`outboxDurableProvider`).
//
// **Abgelegt wird derselbe JSON-Text wie in der Datei** ([encodeOutbox]),
// kein Objekt: IndexedDB gäbe verschachtelte Maps als
// `Map<String, Object?>` zurück, und darauf ist das
// `Map<String, dynamic>` der `fromJson` nicht zuweisbar.
import 'dart:async';

import 'package:idb_shim/idb_shim.dart';

import 'browser_db.dart';
import 'browser_storage.dart' as storage;
import 'outbox.dart';

/// Welcher Korb zu dieser Plattform gehört — als Funktion und nicht als
/// `kIsWeb` im Provider, damit die Entscheidung prüfbar ist (`kIsWeb` ist
/// im Test immer falsch).
Outbox chooseOutbox({required bool web, required IdbFactory? factory}) {
  if (!web) return FileOutbox();
  // Kein IndexedDB: kein Ort für das Original, also sichtbar scheitern.
  if (factory == null) return const NoOutbox();
  return IdbOutbox(BrowserDb(factory));
}

class IdbOutbox implements Outbox {
  IdbOutbox(
    this._db, {
    Future<bool> Function() requestDurable = storage.requestDurableStorage,
    Future<bool> Function() checkDurable = storage.isStorageDurable,
  })  : _requestDurable = requestDurable,
        _checkDurable = checkDurable;

  final BrowserDb _db;
  final Future<bool> Function() _requestDurable;
  final Future<bool> Function() _checkDurable;

  /// Fester Schlüssel, das Konto steht IM Eintrag — wie in der Datei.
  static const _key = 'jobs';

  /// Lese-Ändern-Schreiben: Die Wiedervorlage arbeitet den Korb ab,
  /// während ein Import einen Auftrag ablegt. Auf Dart-Ebene und nicht als
  /// EINE Transaktion — eine IndexedDB-Transaktion, über die hinweg
  /// `await`et wird, schließt sich im Browser je nach Zeitpunkt selbst.
  Future<void> _lock = Future.value();

  /// Die Bitte um Dauer, einmal je Sitzung — der Browser merkt sich die
  /// Antwort, und Firefox fragte sonst bei jedem Auftrag.
  Future<bool>? _durableRequest;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    // Die Kette darf an einem Fehler nicht abreißen.
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<List<OutboxJob>> read({required String uid}) => _serialized(() => _readUnlocked(uid: uid));

  Future<List<OutboxJob>> _readUnlocked({required String uid}) async {
    try {
      final text = await _db.readStore(kOutboxStore, (s) => s.getObject(_key));
      if (text is! String) return const [];
      return decodeOutbox(text, uid: uid);
    } catch (_) {
      // Unlesbar heißt „kein Korb", wie in der Datei. Kein `logError`:
      // ein Bericht je Start.
      return const [];
    }
  }

  @override
  Future<void> append(OutboxJob job, {required String uid}) => _serialized(() async {
        // Der eine Moment, in dem die Frage einen Anlass hat: Gerade
        // entsteht etwas, das noch nirgends sonst liegt. Die Antwort ändert
        // am Ablegen NICHTS — nicht abgewartet, sonst hinge das Ablegen an
        // einer Nachfrage, die vielleicht nie beantwortet wird.
        _durableRequest ??= _askDurable();
        final jobs = await _readUnlocked(uid: uid);
        await _writeUnlocked([...jobs, job], uid: uid);
      });

  /// Wirft nie: Eine fehlende `navigator.storage` heißt „nicht
  /// zugesichert", nicht „Auftrag verloren".
  Future<bool> _askDurable() async {
    try {
      return await _requestDurable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid}) =>
      _serialized(() => _writeUnlocked(jobs, uid: uid));

  /// Anders als bei der Kopie wird hier NICHTS geschluckt.
  Future<void> _writeUnlocked(List<OutboxJob> jobs, {required String uid}) =>
      _db.writeStore(kOutboxStore, (s) => s.put(encodeOutbox(jobs, uid: uid), _key));

  /// Wartet eine laufende Bitte ab (Firefox fragt nach), dann der Stand
  /// des Browsers. Ohne Bitte in dieser Sitzung (der Korb lag schon da)
  /// nur der Stand — nachgefragt wird erst beim nächsten Ablegen.
  @override
  Future<bool> isDurable() async {
    final asked = _durableRequest;
    if (asked != null) await asked;
    try {
      return await _checkDurable();
    } catch (_) {
      return false;
    }
  }
}
