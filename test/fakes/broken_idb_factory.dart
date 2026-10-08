import 'package:idb_shim/idb_shim.dart';

/// Ein IndexedDB-Zugang, bei dem nichts geht — er steht für den privaten
/// Modus mancher Browser und einen vollen Speicher (PilzBuddy). Frei von
/// `dart:io`, damit ihn auch Tests unter dart2js benutzen können.
class BrokenIdbFactory implements IdbFactory {
  @override
  Future<Database> open(String dbName,
          {int? version, OnUpgradeNeededFunction? onUpgradeNeeded, OnBlockedFunction? onBlocked}) async =>
      throw StateError('kein IndexedDB');

  @override
  Future<IdbFactory> deleteDatabase(String name, {OnBlockedFunction? onBlocked}) async =>
      throw StateError('kein IndexedDB');

  /// Alles andere fragt dieser Stand nie — und idb_shim wächst je Fassung
  /// um weitere Mitglieder.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('kein IndexedDB');
}
