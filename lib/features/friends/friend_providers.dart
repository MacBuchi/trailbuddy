import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/read_after_write.dart';
import '../../data/providers.dart';
import '../../models/friendship.dart';
import '../trails/trail_providers.dart';
import 'buddy_alias.dart';
import 'connect_summary.dart';
import 'message_providers.dart';

class FriendshipsNotifier extends AsyncNotifier<List<FriendshipEntry>>
    with ReadAfterWrite<List<FriendshipEntry>> {
  final _revalidations = <String, Object>{};

  @override
  Future<List<FriendshipEntry>> build() {
    ref.onDispose(_revalidations.clear);
    if (ref.watch(currentUserIdProvider) == null) return Future.value([]);
    return ref.read(friendRepositoryProvider).fetchFriendships();
  }

  /// A cold chat already gets its relationship from the initial list load.
  Future<void> revalidateWith(String otherId) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || state.isLoading || !state.hasValue) return;
    final request = Object();
    _revalidations[otherId] = request;
    try {
      final fresh = await ref
          .read(friendRepositoryProvider)
          .fetchFriendshipWith(otherId);
      if (_revalidations[otherId] != request ||
          ref.read(currentUserIdProvider) != uid ||
          state.isLoading) {
        return;
      }
      final entries = state.valueOrNull ?? const <FriendshipEntry>[];
      final index = entries.indexWhere(
        (entry) => entry.otherId(uid) == otherId,
      );
      if (index == -1 && fresh == null) return;
      final updated = [...entries];
      if (index == -1) {
        updated.add(fresh!);
      } else if (fresh == null) {
        updated.removeAt(index);
      } else {
        updated[index] = fresh;
      }
      state = AsyncData(updated);
    } catch (_) {
      // A failed check leaves the last known relationship available offline.
    } finally {
      if (_revalidations[otherId] == request) _revalidations.remove(otherId);
    }
  }

  void _forget(String uid, String otherId) {
    _revalidations.remove(otherId);
    final entries = state.valueOrNull;
    if (entries == null) return;
    state = AsyncData([
      for (final entry in entries)
        if (entry.otherId(uid) != otherId) entry,
    ]);
  }

  Future<void> sendRequest(String addresseeId) async {
    await ref.read(friendRepositoryProvider).sendRequest(addresseeId);
    await reloadAfterWrite('Freundschaften neu laden');
  }

  /// Nimmt an und sagt, was sich dadurch auf der Karte tut (Konzept 6):
  /// der Stand der Trails VOR dem Annehmen gegen den danach. `null`, wenn
  /// die Zahlen nicht zu haben sind (kein Stand vorher, Neuladen
  /// gescheitert) — angenommen ist dann trotzdem.
  Future<ConnectSummary?> accept(String friendshipId) async {
    final myId = ref.read(currentUserIdProvider);
    final before = ref.read(trailsProvider).valueOrNull;
    final buddyId = state.valueOrNull
        ?.where((f) => f.id == friendshipId)
        .firstOrNull
        ?.otherId(myId ?? '');
    await ref.read(friendRepositoryProvider).accept(friendshipId);
    await reloadAfterWrite('Freundschaften neu laden');
    // Erst mit der Freundschaft werden seine Trails sichtbar — die Liste
    // muss neu vom Server kommen, nicht aus dem Zwischenspeicher.
    final fresh = await ref
        .read(trailsProvider.notifier)
        .reloadAfterWrite('Trails nach dem Verbinden laden');
    final after = ref.read(trailsProvider).valueOrNull;
    if (!fresh ||
        before == null ||
        after == null ||
        myId == null ||
        buddyId == null) {
      return null;
    }
    return summarizeConnection(
      before: before,
      after: after,
      myId: myId,
      buddyId: buddyId,
    );
  }

  Future<void> remove(String friendshipId) async {
    final uid = ref.read(currentUserIdProvider);
    final otherId = state.valueOrNull
        ?.where((entry) => entry.id == friendshipId)
        .firstOrNull
        ?.otherId(uid ?? '');
    await ref.read(friendRepositoryProvider).remove(friendshipId);
    if (uid != ref.read(currentUserIdProvider)) return;
    if (uid != null && otherId != null) _forget(uid, otherId);
    await reloadAfterWrite('Freundschaften neu laden');
    // Ablehnen, zurückziehen, entfernen: Die Datenbank löscht Alias und
    // Nachrichten beider Seiten (Trigger) — die Listen müssen es
    // mitbekommen, sonst bliebe die Zahl am Reiter stehen.
    ref.invalidate(buddyAliasesProvider);
    ref.invalidate(messagesProvider);
  }
}

final friendshipsProvider =
    AsyncNotifierProvider<FriendshipsNotifier, List<FriendshipEntry>>(
      FriendshipsNotifier.new,
    );

/// Wen ICH blockiert habe (#584, Patch 033) — für die Seite „Blockierte
/// Nutzer" im Profil und damit die Suche einen Blockierten erkennt.
class BlocksNotifier extends AsyncNotifier<List<BlockedUser>>
    with ReadAfterWrite<List<BlockedUser>> {
  @override
  Future<List<BlockedUser>> build() {
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) return Future.value([]);
    return ref.read(friendRepositoryProvider).fetchBlocks();
  }

  /// Blockiert [otherId]. Die Datenbank beendet die Beziehung und löscht,
  /// was an ihr hing (Alias, Nachrichten, Schalter) — alle Listen, die
  /// davon leben, kommen neu, auch die Trails: Was nur über ihn sichtbar
  /// war, ist weg.
  Future<void> block(String otherId) async {
    final uid = ref.read(currentUserIdProvider);
    await ref.read(friendRepositoryProvider).block(otherId);
    if (uid != ref.read(currentUserIdProvider)) return;
    final friendships = ref.read(friendshipsProvider.notifier);
    if (uid != null) friendships._forget(uid, otherId);
    await reloadAfterWrite('Blockierte neu laden');
    await friendships.reloadAfterWrite('Freundschaften neu laden');
    ref.invalidate(buddyAliasesProvider);
    ref.invalidate(messagesProvider);
    await ref
        .read(trailsProvider.notifier)
        .reloadAfterWrite('Trails nach dem Blockieren laden');
  }

  Future<void> unblock(String otherId) async {
    await ref.read(friendRepositoryProvider).unblock(otherId);
    await reloadAfterWrite('Blockierte neu laden');
  }
}

final blocksProvider = AsyncNotifierProvider<BlocksNotifier, List<BlockedUser>>(
  BlocksNotifier.new,
);
