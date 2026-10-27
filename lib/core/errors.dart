import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:executor_lib/executor_lib.dart' show CancellationException;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/l10n.dart';
import 'photo_pipeline.dart';

/// Empfänger für Fehlerberichte. `main()` hängt hier das Schreiben nach
/// Supabase ein (siehe `ErrorReportRepository`); in Tests bleibt der Haken
/// leer, damit `flutter test` ohne Netz auskommt.
typedef ErrorSink = void Function(
    String context, Object error, StackTrace? stackTrace);

ErrorSink? _sink;

/// Einmalig in `main()` setzen. `null` schaltet das Melden wieder ab.
void setErrorSink(ErrorSink? sink) => _sink = sink;

/// Ob eine Web-App, die von [host] geladen wurde, Fehlerberichte in die
/// ECHTE Tabelle schreiben darf.
///
/// **Nicht von der eigenen Maschine.** Browser-Checks der CI, lokale
/// Läufe und `flutter run -d chrome` laden die App von `127.0.0.1` oder
/// `localhost` — gegen das Live-Supabase. Bei PilzBuddy waren an einem
/// Tag 117 von 222 Berichten genau solche Testläufe, und der
/// Wochendigest zählte sie wie echte Nutzer. Echte Nutzer rufen die App
/// nie über diese Adressen auf.
bool reportsFromHost(String host) => !const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
      '0.0.0.0',
    }.contains(host.toLowerCase());

/// Zentrales, bewusst minimales Logging: gefangene Fehler landen mit
/// Stacktrace im Log (dart:developer → adb logcat / DevTools), statt
/// still in generischen SnackBars zu verschwinden. Optionale Features
/// (Update-Check, GPS) degradieren weiterhin still — aber auch dort darf
/// geloggt werden.
///
/// Zusätzlich geht der Fehler an den [ErrorSink], falls einer gesetzt ist.
/// Der Aufruf darf unter keinen Umständen werfen: ein Fehler beim Melden
/// eines Fehlers würde sonst erneut hier landen und sich aufschaukeln.
void logError(String context, Object error, [StackTrace? stackTrace]) {
  developer.log(context,
      name: 'trailbuddy', error: error, stackTrace: stackTrace);
  if (kDebugMode) debugPrint('[$context] $error');
  try {
    _sink?.call(context, error, stackTrace);
  } catch (_) {
    // Bewusst still: hier zu loggen wäre genau die Endlosschleife.
  }
}

/// Der Stack eines Framework-Fehlers, mit der PHASE davor.
///
/// `FlutterError.onError` bekommt mehr als Fehler und Stack: Bibliothek und
/// Zusammenhang („scheduler library", „during a scheduler callback").
/// Ohne sie stand im Digest von 2026-W40 fünfmal `Null check operator`
/// in `AnimationController.stop` — ohne einen Frame aus unserem Code,
/// weil ein Ticker-Rückruf nur Framework-Frames trägt, und ohne Hinweis,
/// ob es beim Zeichnen, beim Abbauen oder in einer Animation geschah. Die
/// Phase steht als erste Zeile VOR dem Stack: Der Digest sucht seinen
/// Frame unter den Zeilen, die mit `#` beginnen, und überliest sie.
StackTrace? flutterErrorStack(FlutterErrorDetails details) {
  final phase = flutterErrorPhase(details);
  if (phase == null) return details.stack;
  return StackTrace.fromString('Phase: $phase\n${details.stack ?? ''}');
}

/// „Bibliothek · Zusammenhang", oder null, wenn beides fehlt.
String? flutterErrorPhase(FlutterErrorDetails details) {
  final parts = [
    if (details.library?.trim().isNotEmpty ?? false) details.library!.trim(),
    if (details.context != null) details.context!.toDescription().trim(),
  ].where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  // Gekürzt: Der Zusammenhang nennt beim Bauen das Element samt seiner
  // Beschreibung, und die gehört nicht ganz in eine Zeile des Berichts.
  final phase = parts.join(' · ');
  return phase.length <= 200 ? phase : phase.substring(0, 200);
}

/// Gehört dieser Fehler in `error_reports`?
///
/// Für die globalen Handler in `main()`, die alles melden, was ihnen vor die
/// Füße fällt. Zwei Dinge fallen dort regelmäßig hin, ohne dass etwas kaputt
/// ist — und Hunderte Meldungen pro Woche für einen Normalfall begraben im
/// Wochendigest die echten Funde (Lehre aus PilzBuddy #124 und #136):
///
/// * [NotSignedInException]: Hintergrundabfragen, die nach dem Abmelden
///   noch einen Moment weiterlaufen.
/// * Alles, was [looksOffline] als fehlenden Empfang erkennt: Die App wird
///   auf dem Trail benutzt, ohne Netz zu sein ist dort der Normalzustand.
///
/// Bewusst NICHT in `logError` selbst: Wer einen Fehler mit eigenem Kontext
/// meldet, hat sich für das Melden entschieden — diese Entscheidung darf ein
/// Filter nicht überstimmen. Wo eine Hintergrundschleife das ausdrücklich
/// nicht will, fragt sie [looksOffline] selbst.
bool worthReporting(Object error) =>
    error is! NotSignedInException &&
    // Der Kartenrenderer (`vector_map_tiles`) bricht Kachel-Aufträge ab,
    // sobald die Kachel aus dem Bild gewandert ist, und eine davon
    // entkommt als unbehandelter async-Fehler. Abgebrochen heißt
    // abgebrochen — 193 Zeilen je Woche für einen Normalfall begruben in
    // PilzBuddy (#136) die echten Funde.
    error is! CancellationException &&
    !looksOffline(error);

/// `PlatformDispatcher.onError` der App: meldet, was [worthReporting]
/// durchlässt, und sagt, ob der Fehler damit behandelt ist.
///
/// `true` nur für [CancellationException] (#351): Ein abgebrochener
/// Kachel-Auftrag ist gewollt, und mit `false` warf die Standardbehandlung
/// ihn im Browser trotzdem als „Uncaught Error" in die Konsole. Alles
/// andere bleibt `false` — ein echter Fehler soll in der Konsole und im
/// Logcat stehen, auch wenn er nicht gemeldet wird.
bool handleUncaughtError(Object error, StackTrace stack) {
  if (worthReporting(error)) logError('Unbehandelter Fehler', error, stack);
  return error is CancellationException;
}

/// Es gibt gerade keine angemeldete Sitzung.
///
/// Kein Fehler im eigentlichen Sinn: Beim Abmelden und beim Ablaufen eines
/// Tokens laufen Hintergrundabfragen noch einen Moment weiter und greifen
/// dann ins Leere. Vorher war das ein `Null check operator used on a null
/// value` aus `currentUser!` — 37 Fehlerberichte in einer Woche für einen
/// völlig normalen Vorgang (PilzBuddy #124). Als eigener Typ, damit genau
/// die Stellen ihn erkennen und still aufhören können, statt zu melden.
class NotSignedInException implements Exception {
  const NotSignedInException();

  @override
  String toString() => 'NotSignedInException: keine angemeldete Sitzung';
}

/// Die Datenbank hat eine Änderung stillschweigend verworfen.
///
/// PostgREST meldet eine von RLS abgelehnte Zeile NICHT als Fehler: Die
/// Anfrage gelingt, sie trifft nur keine Zeile. Ohne diesen Typ würde die
/// App „gespeichert" melden, während in der Datenbank nichts passiert ist
/// — der schlechteste aller Ausgänge, weil niemand ihn bemerkt. Die
/// Schreibwege prüfen deshalb die zurückgegebenen Zeilen und werfen das
/// hier, wenn keine dabei ist.
class WriteRejectedException implements Exception {
  const WriteRejectedException(this.what);

  /// Was nicht geschrieben wurde, für Protokoll und Fehlerbericht.
  final String what;

  @override
  String toString() => 'WriteRejectedException: $what';
}

/// Der Server nimmt heute keine weitere Aufzeichnung an
/// (`contribute_recording`, SQLSTATE 54000, `match_params().daily_limit`).
///
/// Eigener Typ, weil der Import davon anders abhängt als von einem
/// Fehlschlag: Ab hier scheitert JEDER weitere Versuch gleich, also hört
/// er auf, statt dreihundert Zeilen „fehlgeschlagen" zu sammeln — und die
/// übrigen bleiben angehakt für morgen.
class DailyLimitException implements Exception {
  const DailyLimitException();

  @override
  String toString() => 'DailyLimitException: Tageslimit für Aufzeichnungen erreicht';
}

/// Der Server nimmt eine Zuordnung „B ist ein Duplikat von A" nicht an
/// (`merge_own_into`, Patch 019, #107). Eigener Typ, damit der Text sagt,
/// WARUM — „Serverfehler (22023)" schickte jemanden auf die falsche Fährte.
class MergeRejectedException implements Exception {
  const MergeRejectedException(this.reason);

  final MergeRejection reason;

  @override
  String toString() => 'MergeRejectedException: ${reason.name}';
}

enum MergeRejection {
  /// SQLSTATE 22023: Die beiden liegen nicht grob beieinander (≥ 50 % der
  /// kürzeren Linie innerhalb von 50 m) — die Auswahl auf dem Gerät
  /// rechnet dasselbe, hier ging also eine Linie anders aus als gezeigt.
  notNear,

  /// SQLSTATE P0002: Einer der beiden ist nicht mehr da oder nicht mehr
  /// sichtbar — dieselbe Antwort für beides (4.6).
  gone,
}

/// Sieht dieser Fehler nach fehlendem Empfang aus?
///
/// Bewusst eng: Ein Schema- oder Rechtefehler darf sich nie hinter einer
/// „kein Netz"-Meldung verstecken — sonst bliebe ein kaputtes Deployment
/// unsichtbar (Lehre aus PilzBuddy #80).
///
/// **Und der Sonderfall, der beides sein kann:** GoTrue verpackt jeden
/// fehlgeschlagenen Auth-Aufruf in `AuthRetryableFetchException` — den
/// Netzfehler EBENSO wie eine 5xx-Antwort des Servers. Nur der erste Fall
/// ist fehlender Empfang, und unterscheiden lassen sie sich am
/// [AuthException.statusCode]: Ohne Antwort gibt es keinen. Ein Ausfall
/// der Datenbank behält damit seinen Weg nach draußen.
///
/// Für 5xx gilt das mit EINER Ausnahme: 504, siehe
/// [looksLikeGatewayTimeout].
bool looksOffline(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is http.ClientException ||
    (error is AuthRetryableFetchException && error.statusCode == null) ||
    looksLikeGatewayTimeout(error);

/// Hat die Gegenstelle innerhalb der Frist gar nicht geantwortet?
///
/// **Warum 504 die eine 5xx-Ausnahme ist.** Ein Ausfall der Datenbank muss
/// sichtbar bleiben, und das gilt weiter für 500, 502 und 503: Dort hat
/// der Server GEANTWORTET, und die Antwort ist kaputt. Ein 504 ist das
/// Gegenteil: keine Antwort innerhalb der Frist. Das ist dieselbe Lage wie
/// eine [TimeoutException], die längst als fehlender Empfang zählt; der
/// einzige Unterschied ist, wem die Geduld ausging — unserem Client oder
/// dem Gateway davor.
///
/// Geprüft wird der CODE als Zeichenkette — beide Pakete führen ihn so
/// (`AuthException.statusCode`, `PostgrestException.code` sind
/// `String?`). Wie bei [looksLikeMailRateLimit] bewusst ENG: dieser eine
/// Code, kein „5xx allgemein".
bool looksLikeGatewayTimeout(Object error) =>
    (error is AuthException && error.statusCode == '504') ||
    (error is PostgrestException && error.code == '504');

/// Hat GoTrue den Mailversand abgelehnt, weil zu schnell wieder gefragt
/// wurde?
///
/// Das ist kein Fehler, sondern die Sperre bei der Arbeit: Das Mail-Limit
/// steht im Dashboard bewusst niedrig, damit der geteilte Mailvorrat nicht
/// leerläuft. Wer erneut drückt, bekommt 429 — die vorgesehene Antwort.
///
/// Wie [looksOffline] bewusst ENG: nur dieser eine Code, kein 429
/// allgemein. Und wie dort entscheidet die Aufrufstelle selbst, ob sie
/// ihn hören will — [worthReporting] fasst ihn nicht an, denn wo ein
/// Nutzer wirklich stehen bleibt (Registrierung, Adresswechsel), gehört
/// die abgelehnte Mail sehr wohl gemeldet.
///
/// Geprüft wird der CODE, nicht die Klasse: Live kommt der Fall als
/// `AuthApiException`, es gibt aber keinen Grund, warum dieselbe Aussage
/// in einer anderen `AuthException` nicht zählen sollte. `gotrue` kennt
/// den Wert als `ErrorCode.overEmailSendRateLimit`, exportiert die Enum
/// aber nicht; deshalb der Draht-Wert.
bool looksLikeMailRateLimit(Object error) =>
    error is AuthException && error.code == 'over_email_send_rate_limit';

/// Nutzerfreundliche Meldung nach Fehlerklasse statt pauschalem
/// „… Internet verfügbar?": Netzwerk, Server und Unerwartetes werden
/// unterschieden, damit Problemberichte diagnostizierbar sind.
String friendlyError(AppLocalizations l, Object error) {
  // **Vor [looksOffline], obwohl es ein Sonderfall davon ist.** Sonst
  // stünde bei einem 504 „bitte Internet prüfen" — und das schickt
  // jemanden an die Stelle, an der nichts kaputt ist. Sein Netz trägt
  // ja, sonst hätte er die 504 nie bekommen.
  if (looksLikeGatewayTimeout(error)) return l.errorGatewayTimeout;
  if (looksOffline(error)) return l.errorOffline;
  // Ein Bild, das die Pipeline nicht lesen kann (#37): Ihr Satz ist schon
  // für den Nutzer geschrieben.
  if (error is PhotoPipelineException) return error.userMessage(l);
  if (error is StorageException) {
    return l.errorPhotoUpload(error.statusCode ?? l.errorUnknownCode);
  }
  if (error is NotSignedInException) return l.errorNotSignedIn;
  // Der Fall: ein Eintrag, dessen Freigabe inzwischen endete. Die Policy
  // lässt ihn dann vielleicht noch löschen, aber nicht mehr ändern —
  // deshalb nennt der Text beide Möglichkeiten, statt eine zu raten.
  if (error is DailyLimitException) return l.errorDailyLimit;
  if (error is MergeRejectedException) {
    return switch (error.reason) {
      MergeRejection.notNear => l.errorMergeNotNear,
      MergeRejection.gone => l.errorMergeGone,
    };
  }
  if (error is WriteRejectedException) return l.errorWriteRejected;
  if (error is PostgrestException) {
    // 42501 = RLS-Verbot. Der typische Fall: Ein Blatt ist offen, während
    // die Freigabe endet — „Serverfehler" wäre die falsche Fährte.
    if (error.code == '42501') return l.errorNoLongerShared;
    return l.errorServer(error.code ?? l.errorUnknownCode);
  }
  if (error is AuthException) return l.errorSessionExpired;
  return l.errorUnexpected('${error.runtimeType}');
}

/// Login-Fehler → Meldung. Bevorzugt den typisierten Supabase-Fehlercode;
/// der HTTP-Status bleibt als Fallback für ältere Server.
String loginErrorMessage(AppLocalizations l, AuthException error) {
  // Vor der Standardmeldung prüfen: Die unbestätigte Adresse kommt zwar
  // auch als 400, ist aber etwas völlig anderes als ein falsches Passwort
  // — wer hier „E-Mail oder Passwort falsch" liest, sucht den Fehler an
  // der falschen Stelle.
  if (error.code == 'email_not_confirmed') {
    return l.authErrorEmailNotConfirmed;
  }
  if (error.code == 'invalid_credentials' || error.statusCode == '400') {
    return l.authErrorWrongCredentials;
  }
  return l.authErrorLoginFailed(error.message);
}

/// Fehler beim Einlösen eines Reset-Codes → Meldung.
///
/// Der falsche oder abgelaufene Code ist der Normalfall (abgetippt), er
/// braucht eine Meldung, die zum nächsten Schritt führt. `weak_password`
/// kommt aus der Passwort-Prüfung von Supabase — dort ist „zu kurz"
/// falsch, das Passwort kann auch bekannt geleakt sein.
String resetErrorMessage(AppLocalizations l, AuthException error) {
  if (error.code == 'otp_expired' || error.statusCode == '403') {
    return l.authErrorCodeInvalid;
  }
  if (error.code == 'weak_password') {
    return l.authErrorWeakPassword;
  }
  if (error.code == 'same_password') {
    return l.authErrorSamePassword;
  }
  return l.authErrorResetFailed(error.message);
}

/// Registrierungs-Fehler → Meldung. `user_already_exists` ist typisiert;
/// der "Database error saving new user"-Fall ist ein 500 aus dem
/// Profil-Trigger OHNE Fehlercode (unique-Verletzung am Benutzernamen) —
/// dieses String-Matching ist unvermeidbar und per Test festgenagelt.
String signupErrorMessage(AppLocalizations l, AuthException error) {
  if (error.code == 'user_already_exists') {
    return l.authErrorAccountExists;
  }
  if (error.message.contains('Database error saving new user')) {
    return l.authErrorUsernameTaken;
  }
  return l.authErrorSignupFailed(error.message);
}

/// Fehler beim Ändern des Benutzernamens → Meldung.
///
/// Anders als bei der Registrierung kommt der Konflikt hier nicht als
/// Auth-Fehler aus dem Profil-Trigger, sondern direkt aus PostgREST:
/// unique-Verletzung = SQLSTATE 23505. Derselbe Text wie bei der
/// Registrierung — es ist derselbe Fall, und zwei Formulierungen für
/// eine Ursache wären Rätselraten.
String usernameChangeErrorMessage(AppLocalizations l, Object error) {
  if (error is PostgrestException && error.code == '23505') {
    return l.authErrorUsernameTaken;
  }
  return friendlyError(l, error);
}

/// Fehler beim Ändern der E-Mail-Adresse → Meldung.
///
/// `email_exists` ist typisiert (422). Der offene Text ist Absicht und
/// KEIN neues Orakel: Die Registrierung nennt eine vergebene Adresse
/// längst beim Namen — Konsistenz statt Scheinschutz. `invalid_credentials`
/// kommt aus der vorgeschalteten frischen Anmeldung (Muster
/// Passwortwechsel), `otp_expired` aus einem falsch abgetippten Code.
String emailChangeErrorMessage(AppLocalizations l, AuthException error) {
  if (error.code == 'email_exists') {
    return l.authErrorEmailExists;
  }
  if (error.code == 'invalid_credentials' || error.statusCode == '400') {
    return l.authErrorWrongCurrentPassword;
  }
  if (error.code == 'otp_expired' || error.statusCode == '403') {
    return l.authErrorCodeInvalid;
  }
  return l.authErrorEmailChangeFailed(error.message);
}

/// Fehler beim Bestätigen der Adresse (Code aus der Mail) und beim erneuten
/// Anfordern dieser Mail → Meldung.
///
/// Eigene Funktion statt `resetErrorMessage`: Deren Fallback sagt
/// „Zurücksetzen fehlgeschlagen" — mitten in der Registrierung schickt das
/// den Leser in die falsche Richtung. Dazu kommt das Rate Limit, das es beim
/// Reset praktisch nicht gibt, beim „Erneut senden" aber der häufigste Fall
/// ist.
String confirmErrorMessage(AppLocalizations l, AuthException error) {
  if (error.code == 'otp_expired' || error.statusCode == '403') {
    return l.authErrorCodeInvalid;
  }
  if (error.code == 'over_email_send_rate_limit' ||
      error.statusCode == '429') {
    return l.authErrorMailRateLimit;
  }
  return l.authErrorConfirmFailed(error.message);
}

/// Fehler beim Ändern des Passworts durch Angemeldete → Meldung.
///
/// Der erste Schritt des Ändern-Flows ist eine erneute Anmeldung mit dem
/// aktuellen Passwort. Deren `invalid_credentials` heißt hier deshalb NICHT
/// „E-Mail oder Passwort falsch", sondern genau eines von beidem.
/// Die typisierten Codes stehen bewusst VOR dem Status-Fallback: Ein
/// abgelehntes neues Passwort kommt je nach Server-Version auch als 400 an
/// und läse sich sonst als „aktuelles Passwort falsch".
String changePasswordErrorMessage(AppLocalizations l, AuthException error) {
  if (error.code == 'weak_password') {
    return l.authErrorWeakPassword;
  }
  if (error.code == 'same_password') {
    return l.authErrorSamePassword;
  }
  if (error.code == 'invalid_credentials' || error.statusCode == '400') {
    return l.authErrorWrongCurrentPassword;
  }
  return l.authErrorChangeFailed(error.message);
}
