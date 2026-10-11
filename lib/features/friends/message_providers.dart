// Nachrichten zwischen Buddys (#34, Vorlage PilzBuddy #564) — Zustand und die kleinen
// Rechnungen darüber, ohne Widgets.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/read_after_write.dart';
import '../../data/message_repository.dart';
import '../../data/providers.dart';
import '../../models/buddy_message.dart';
import '../../models/friendship.dart';

class MessagesNotifier extends AsyncNotifier<List<BuddyMessage>>
    with ReadAfterWrite<List<BuddyMessage>> {
  @override
  Future<List<BuddyMessage>> build() {
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) return Future.value([]);
    return ref.read(messageRepositoryProvider).fetchAll();
  }

  /// Wirft bei Fehlern — die Oberfläche lässt den Text dann im Feld
  /// stehen, statt ihn zu verschlucken.
  Future<void> send(String recipientId, String body) async {
    await ref
        .read(messageRepositoryProvider)
        .send(recipientId: recipientId, body: body);
    await reloadAfterWrite('Nachrichten neu laden');
  }

  /// Gelesen markieren — still: Scheitert es, bleibt der Punkt eben
  /// stehen, und das nächste Öffnen versucht es wieder.
  Future<void> markRead(String otherId) async {
    final uid = ref.read(currentUserIdProvider);
    final unread = (state.valueOrNull ?? const <BuddyMessage>[])
        .any((m) => m.senderId == otherId && m.isUnreadFor(uid ?? ''));
    if (uid == null || !unread) return;
    await ref.read(messageRepositoryProvider).markRead(otherId);
    await reloadAfterWrite('Nachrichten neu laden');
  }

  Future<void> delete(String messageId) async {
    await ref.read(messageRepositoryProvider).delete(messageId);
    await reloadAfterWrite('Nachrichten neu laden');
  }
}

final messagesProvider =
    AsyncNotifierProvider<MessagesNotifier, List<BuddyMessage>>(
        MessagesNotifier.new);

/// Der Verlauf mit [otherId], älteste zuerst.
///
/// **Älteste zuerst, und zwar HIER sortiert**, nicht im Vertrauen auf die
/// Abfrage: Deren Reihenfolge hing in PilzBuddy an einem Vorgabewert
/// von postgrest-dart (absteigend), während der Fake aufsteigend lieferte
/// — der Verlauf stand im Feld auf dem Kopf, die Tests blieben grün
/// (PilzBuddy #594). Der Fake hier liefert deshalb absichtlich verkehrt.
List<BuddyMessage> conversationWith(
        List<BuddyMessage> all, String uid, String otherId) =>
    [for (final m in all) if (m.otherId(uid) == otherId) m]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

/// Ungelesene je Absender.
Map<String, int> unreadBySender(List<BuddyMessage> all, String uid) {
  final counts = <String, int>{};
  for (final m in all) {
    if (m.isUnreadFor(uid)) {
      counts[m.senderId] = (counts[m.senderId] ?? 0) + 1;
    }
  }
  return counts;
}

final unreadMessagesProvider = Provider<Map<String, int>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const {};
  return unreadBySender(
      ref.watch(messagesProvider).valueOrNull ?? const [], uid);
});

/// Wie viele Nachrichten ich [friendship] noch schreiben darf — `null`
/// heißt unbegrenzt (angenommen). Dieselbe Regel wie
/// `app_internal.may_message`; die Datenbank hat das letzte Wort, die
/// Zahl hier ist die Ansage vorher.
int? messagesLeft(
    FriendshipEntry friendship, List<BuddyMessage> all, String uid) {
  if (friendship.isAccepted) return null;
  final other = friendship.otherId(uid);
  final sent =
      all.where((m) => m.senderId == uid && m.recipientId == other).length;
  return (kPendingMessageLimit - sent).clamp(0, kPendingMessageLimit);
}

/// Die Freundschaft zu [otherId] — oder `null`, wenn es keine (mehr) gibt.
FriendshipEntry? friendshipWith(
        List<FriendshipEntry> all, String uid, String otherId) =>
    all.where((f) => f.otherId(uid) == otherId).firstOrNull;
