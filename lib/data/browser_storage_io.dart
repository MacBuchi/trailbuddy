import 'package:idb_shim/idb_shim.dart';

/// Außerhalb des Browsers gibt es kein IndexedDB — und es fehlt nichts:
/// Korb und Kopie liegen dort als Datei.
IdbFactory? browserIdbFactory() => null;

/// Eine Datei verfällt nicht. Bewusst `true`: Ein Warnhinweis über ein
/// Dateisystem wäre schlicht falsch.
Future<bool> requestDurableStorage() async => true;

/// Siehe [requestDurableStorage].
Future<bool> isStorageDurable() async => true;
