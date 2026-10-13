// Neu laden nach einem erfolgreichen Schreibvorgang — und der Unterschied
// zwischen „das Schreiben ist gescheitert" und „das Neuladen ist
// gescheitert".
//
// Das Haus-Muster für Mutationen ist Read-after-write: Repo-Aufruf, dann
// neu laden. Steht das `await future` nackt da, fällt ein Fehler des
// ABRUFS in denselben `catch` wie ein Fehler des SCHREIBENS. Was der
// Nutzer davon sieht (PilzBuddy #371): Der Eintrag lag auf dem Server,
// aber die App meldete „Internet verfügbar?" — und der nächste Schritt ist
// dann, ihn noch einmal einzutragen. Ein echtes Duplikat aus einer
// Fehlermeldung, die nur die falsche Stelle benannte.
//
// **Kein erneuter Versuch an dieser Stelle.** postgrest wiederholt GETs
// von sich aus dreimal — ein 504 hat vier Versuche hinter sich, und ein
// fünfter wäre nur Wartezeit vor derselben Antwort.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import 'errors.dart';

/// Was der Oberfläche zu sagen bleibt, wenn geschrieben, aber nicht mehr
/// neu geladen werden konnte.
///
/// Ein eigener Baustein, weil die Aussage an jeder Schreibstelle
/// dieselbe sein muss: **Es ist gespeichert** — wer hier „Fehler" liest,
/// trägt es ein zweites Mal ein. Der Nachsatz erklärt, warum trotzdem
/// nichts zu sehen ist; ohne ihn sähe „gespeichert" bei unveränderter
/// Liste nach einer Lüge aus.
///
/// Die Sätze stehen in den ARB-Dateien (#209): `l.staleAfterWrite(done)`
/// hängt den Nachsatz an die Erfolgsmeldung, [doneOrStale] wählt.
/// Dasselbe für den Ausgangskorb (#30) ist `l.queuedHint`: NICHT
/// „gespeichert" — auf dem Server liegt noch nichts —, aber auch kein
/// Fehler.
String doneOrStale(AppLocalizations l, String done, {required bool fresh}) =>
    fresh ? done : l.staleAfterWrite(done);

/// Read-after-write für [AsyncNotifier]-Mutationen.
mixin ReadAfterWrite<T> on AsyncNotifier<T> {
  /// Lädt neu, nachdem geschrieben wurde — und wirft dabei **nicht**.
  ///
  /// Gibt `true` zurück, wenn die Anzeige jetzt frisch ist, und `false`,
  /// wenn der Schreibvorgang durch ist, das Neuladen aber scheiterte.
  ///
  /// Der Fehler verschwindet nicht, er wird nur richtig benannt: Er
  /// läuft mit [what] nach `error_reports`, statt sich als Schreibfehler
  /// auszugeben. Der Digest verliert damit nichts — er hört auf, an der
  /// falschen Stelle zu suchen.
  ///
  /// Der Zustand des Providers bleibt unangetastet: Nach einem
  /// fehlgeschlagenen Abruf steht er auf `AsyncError` (mit dem Vorwert
  /// darunter). Eine Aufrufstelle, die den Nutzer über die veraltete
  /// Anzeige unterrichten will, fragt danach — der Rückgabewert hier
  /// sagt dasselbe, nur ohne zweiten Zugriff.
  Future<bool> reloadAfterWrite(String what) async {
    ref.invalidateSelf();
    try {
      await future;
      return true;
    } catch (error, stackTrace) {
      logError(what, error, stackTrace);
      return false;
    }
  }
}
