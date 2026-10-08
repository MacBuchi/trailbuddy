import 'dart:js_interop';

import 'package:idb_shim/idb_browser.dart';
import 'package:web/web.dart' as web;

/// Das echte IndexedDB des Browsers — oder `null`, wenn es keins gibt
/// (manche Browser im privaten Modus, `file://`). Dann bleibt es beim
/// Verhalten ohne Ablage.
///
/// Bewusst NICHT `idbFactoryBrowser`: Das fällt still auf die
/// Speicher-Fassung zurück, und ein Korb, der jeden Neustart vergisst,
/// sähe von außen aus wie einer, der bleibt.
IdbFactory? browserIdbFactory() => idbFactoryNativeSupported ? idbFactoryNative : null;

/// Bittet den Browser, diesen Speicher nicht von sich aus zu räumen.
/// Chrome entscheidet still nach eigenen Kriterien (installierte PWA,
/// Nutzung), Firefox FRAGT — deshalb erst, wenn wirklich etwas
/// Ungesendetes entsteht (`outbox_idb.dart`), nie beim Start.
Future<bool> requestDurableStorage() => _ask((s) => s.persist());

/// Liest nur den Stand, ohne Nachfrage — die Grundlage des Hinweises auf
/// der Karte.
Future<bool> isStorageDurable() => _ask((s) => s.persisted());

Future<bool> _ask(JSPromise<JSBoolean> Function(web.StorageManager) call) async {
  try {
    return (await call(web.window.navigator.storage).toDart).toDart;
  } catch (_) {
    // `navigator.storage` gibt es nur in sicheren Kontexten. Im Zweifel
    // „nicht zugesichert": Ein Hinweis zu viel ist die harmlose Richtung,
    // eine verlorene Aufzeichnung nicht.
    return false;
  }
}
