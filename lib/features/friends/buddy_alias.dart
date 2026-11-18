// Aliase für Buddys — eine private Notiz je Buddy, damit man nach einer
// Umbenennung noch weiß, wer es war.
//
// **Eine Stelle für alle Namen.** Buddy-Namen stehen an vielen Orten
// (Liste, Trails, Karte …), und jeder läse sonst seinen eigenen
// `username`. Wer dort einen Alias vergäße, zeigte an genau einer Stelle
// den alten Namen — und genau die fiele dann auf. Deshalb gehen alle über
// [BuddyNames.of].
//
// **Zwei Formen, bewusst:** Wo Platz ist (Buddy-Liste), stehen Alias UND
// Name — das ist der Zweck: „Andi" oben, darunter der Name, den er sich
// gerade gegeben hat. Überall sonst steht der Alias allein; „Andi (klabuster
// 2)" in einem Tooltip wäre Lärm.
//
// **Ohne Empfang fällt der Alias still weg** und der Name steht da. Er ist
// eine Bequemlichkeit, kein Inhalt — ein eigener Zwischenspeicher dafür
// wäre mehr Maschinerie, als er wert ist.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/read_after_write.dart';
import '../../data/providers.dart';

/// Buddy-id → Alias, und die eine Regel, welcher Name angezeigt wird.
class BuddyNames {
  const BuddyNames(this.aliases);

  static const empty = BuddyNames({});

  final Map<String, String> aliases;

  /// Der eigene Alias für [userId], sonst `null`.
  String? aliasOf(String? userId) => userId == null ? null : aliases[userId];

  /// Was angezeigt wird: der Alias, sonst der Name, sonst [fallback].
  String of(String? userId, String? username, {String fallback = 'Buddy'}) =>
      aliasOf(userId) ?? username ?? fallback;
}

class BuddyAliasesNotifier extends AsyncNotifier<Map<String, String>>
    with ReadAfterWrite<Map<String, String>> {
  @override
  Future<Map<String, String>> build() {
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) return Future.value({});
    return ref.read(friendRepositoryProvider).fetchAliases();
  }

  /// Setzt den Alias; ein leerer Text entfernt ihn. Wirft bei Fehlern —
  /// der Dialog zeigt sie an.
  Future<void> set(String friendId, String alias) async {
    await ref.read(friendRepositoryProvider).setAlias(friendId, alias);
    await reloadAfterWrite('Aliase neu laden');
  }
}

final buddyAliasesProvider =
    AsyncNotifierProvider<BuddyAliasesNotifier, Map<String, String>>(
      BuddyAliasesNotifier.new,
    );

/// Die Namensregel mit den geladenen Aliasen. Solange sie laden oder
/// nicht laden können: ohne — dann steht der Name da.
final buddyNamesViewProvider = Provider<BuddyNames>((ref) {
  final aliases = ref.watch(buddyAliasesProvider).valueOrNull;
  return aliases == null || aliases.isEmpty
      ? BuddyNames.empty
      : BuddyNames(aliases);
});
