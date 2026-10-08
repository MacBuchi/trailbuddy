// Die Kopie des Netzes im Browser (#153; PilzBuddy #385 als Vorlage):
// Damit die Web-App ohne Empfang nicht leer startet — und ein Tab, dem
// das Netz wegbricht, beim Neuladen etwas zeigt.
//
// Warum IndexedDB und nicht `localStorage`: Dort liegen Sitzung und
// Einstellungen, der Platz ist knapp (üblich 5 MB je Origin, das Netz
// mit seinen Linien sprengt das schnell), und jeder Zugriff hält den
// Haupt-Thread an.
//
// **Eine Kopie, kein Original** — ein Browser darf sie räumen, der
// nächste Abruf füllt sie wieder. Deshalb wirft hier nichts (die
// gemeinsame Hülle [QueuedTrailCache] fängt), und deshalb bittet die
// Kopie NICHT um `persist()`: Das tut nur der Ausgangskorb, der das
// Original trägt.
//
// **Abgelegt wird derselbe JSON-Text wie in der Datei** — mit Konto und
// Zeitpunkt darin, unter EINEM festen Schlüssel. Nach Konto zu schlüsseln
// ließe das Netz jedes früher angemeldeten Kontos im Browser liegen.
import 'package:idb_shim/idb_shim.dart';

import 'browser_db.dart';
import 'trail_cache.dart';

/// Welche Kopie zu dieser Plattform gehört — prüfbar, anders als `kIsWeb`.
TrailCache chooseTrailCache({required bool web, required IdbFactory? factory}) {
  if (!web) return FileTrailCache();
  // Kein IndexedDB: keine Kopie, NIE die Speicher-Fassung — eine Kopie,
  // die jeden Neustart vergisst, sähe aus wie eine, die bleibt.
  if (factory == null) return const NoTrailCache();
  return IdbTrailCache(BrowserDb(factory));
}

class IdbTrailCache extends QueuedTrailCache {
  IdbTrailCache(this._db);

  final BrowserDb _db;

  static const _key = 'network';

  @override
  Future<void> storeText(String text) => _db.writeStore(kTrailCacheStore, (s) => s.put(text, _key));

  @override
  Future<String?> loadText() async {
    final value = await _db.readStore(kTrailCacheStore, (s) => s.getObject(_key));
    return value is String ? value : null;
  }

  @override
  Future<void> removeText() => _db.writeStore(kTrailCacheStore, (s) => s.delete(_key));
}
