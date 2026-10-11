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
  @override
  Future<List<FriendshipEntry>> build() {
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) return Future.value([]);
    return ref.read(friendRepositoryProvider).fetchFriendships();
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
    final fresh = await ref.read(trailsProvider.notifier).reloadAfterWrite('Trails nach dem Verbinden laden');
    final after = ref.read(trailsProvider).valueOrNull;
    if (!fresh || before == null || after == null || myId == null || buddyId == null) return null;
    return summarizeConnection(before: before, after: after, myId: myId, buddyId: buddyId);
  }

  Future<void> remove(String friendshipId) async {
    await ref.read(friendRepositoryProvider).remove(friendshipId);
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
        FriendshipsNotifier.new);
