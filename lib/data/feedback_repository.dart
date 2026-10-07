import 'package:supabase_flutter/supabase_flutter.dart';

import 'session.dart';

enum FeedbackType { feature, bug }

/// So viele Zeichen braucht der Text, bevor „Senden" antippbar wird.
///
/// **„Senden" ist nur aktiv, wenn danach wirklich gesendet wird.** Ein
/// grauer Knopf mit dem Grund darunter sagt es vorher; eine SnackBar nach
/// dem Tipp sagt es zu spät.
const kFeedbackMinChars = 3;

/// In-App-Feedback, Text pur (`public.feedback`: user_id, type, message,
/// app_version). Der Feedback-Bot macht daraus GitHub-Issues.
class FeedbackRepository {
  FeedbackRepository(this._client);

  final SupabaseClient _client;

  /// Feature-Wunsch oder Bug-Meldung einreichen.
  ///
  /// [appVersion] steht im Issue. Ohne sie ist bei einer Feldmeldung nicht
  /// entscheidbar, ob sie ein Duplikat einer schon behobenen ist oder ein
  /// neuer Fehler im frischen Stand. `null` ist erlaubt und heißt schlicht
  /// „unbekannt": Eine erfundene Version wäre schlimmer.
  ///
  /// Sie kommt als PARAMETER und nicht aus `PackageInfo` im Repository:
  /// `appVersionProvider` hält sie ohnehin schon, und über den Parameter
  /// ist sie im Test überprüfbar statt immer null.
  ///
  /// [clientId] ist die Kennung des Auftrags im Ausgangskorb (#218, Patch
  /// 018). Sie entsteht VOR dem ersten Versuch; kam die Zeile beim ersten
  /// Mal an und nur die Antwort nicht, meldet der Server beim Nachholen
  /// `23505` — das heißt „stand schon" und ist kein Fehler. Die einzigen
  /// eindeutigen Spalten sind `id` (vom Server) und `client_id`.
  Future<void> submit(FeedbackType type, String message,
      {String? appVersion, String? clientId}) async {
    try {
      await _client.from('feedback').insert({
        'user_id': _client.requireUid,
        'type': type == FeedbackType.bug ? 'bug' : 'feature',
        'message': message.trim(),
        'app_version': appVersion,
        'client_id': ?clientId,
      });
    } on PostgrestException catch (e) {
      if (clientId != null && e.code == '23505') return;
      rethrow;
    }
  }
}
