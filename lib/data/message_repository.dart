// Nachrichten zwischen Buddys (#34) — Patch 021, Vorlage PilzBuddy #564.
//
// **Eine Abfrage für alle Verläufe.** 30 Tage und eine Handvoll Buddys
// sind wenige Zeilen; ein Abruf je Verlauf wäre ein Abruf je Buddy beim
// Öffnen des Reiters, nur um die Zahl am Knopf zu zeichnen.
//
// **Die Grenzen zieht die Datenbank**, nicht dieses Repository: wer wem
// schreiben darf, das Limit von drei Nachrichten bei offener Anfrage,
// die 30 Tage. Hier steht nur, was die App dafür schickt — Empfänger
// und Text, sonst nichts (die Spalten-Grants ließen mehr gar nicht zu).
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/buddy_message.dart';
import 'session.dart';

/// So lang darf eine Nachricht sein — derselbe Wert wie der Check in
/// Patch 021.
const kMessageMaxLength = 500;

/// Ohne angenommene Freundschaft: so viele eigene Nachrichten je
/// Person. Derselbe Wert wie in `app_internal.may_message`.
const kPendingMessageLimit = 3;

/// Wie lange eine Nachricht bleibt — Default und Check in Patch 021.
const kMessageDays = 30;

/// Die Datenbank hat die Nachricht abgelehnt: keine offene Anfrage mehr,
/// oder das Limit ist erreicht. Die Policy sagt nicht, welches von
/// beiden — die Oberfläche weiß es meist schon vorher.
class MessageRejectedException implements Exception {
  const MessageRejectedException();

  @override
  String toString() => 'Nachricht nicht zugestellt — vielleicht wurde die '
      'Anfrage zurückgezogen, oder deine drei Nachrichten sind schon '
      'geschrieben.';
}

class MessageRepository {
  MessageRepository(this._client);

  final SupabaseClient _client;

  /// Exakt diese Spalten prüft `tool/schema_check.sh`.
  static const columns =
      'id, sender_id, recipient_id, body, created_at, expires_at, read_at';

  /// Alle eigenen Nachrichten, beide Richtungen, älteste zuerst. Die
  /// Policy liefert nur, was mich betrifft und nicht abgelaufen ist.
  Future<List<BuddyMessage>> fetchAll() async {
    final rows = await _client
        .from('buddy_messages')
        .select(columns)
        // `ascending` ausdrücklich: postgrest-dart sortiert ohne Angabe
        // ABSTEIGEND (PilzBuddy #594 — der Verlauf stand auf dem Kopf).
        .order('created_at', ascending: true);
    return [for (final row in rows) BuddyMessage.fromJson(row)];
  }

  Future<void> send({required String recipientId, required String body}) async {
    try {
      await _client
          .from('buddy_messages')
          .insert({'recipient_id': recipientId, 'body': body.trim()});
    } on PostgrestException catch (e) {
      // 42501: die Policy hat nein gesagt (`may_message`).
      if (e.code == '42501') throw const MessageRejectedException();
      rethrow;
    }
  }

  /// Markiert alles, was [otherId] mir geschickt hat, als gelesen.
  Future<void> markRead(String otherId) => _client
      .from('buddy_messages')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('sender_id', otherId)
      .eq('recipient_id', _client.requireUid)
      .isFilter('read_at', null);

  /// Nimmt eine eigene Nachricht zurück.
  Future<void> delete(String messageId) =>
      _client.from('buddy_messages').delete().eq('id', messageId);
}
