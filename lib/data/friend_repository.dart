import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friendship.dart';
import 'session.dart';

class FriendRepository {
  FriendRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.requireUid;

  /// Sucht über die RPC `search_profiles` — Benutzername als Präfix oder
  /// die EXAKTE E-Mail-Adresse. Die RPC ist nur für `authenticated`
  /// ausführbar; für anon wäre sie ein E-Mail-Orakel.
  Future<List<ProfileSearchResult>> search(String query) async {
    final rows =
        await _client.rpc('search_profiles', params: {'query': query})
            as List<dynamic>;
    return rows
        .map((r) => ProfileSearchResult.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<FriendshipEntry>> fetchFriendships() async {
    final rows = await _client
        .from('friendships')
        .select(
          'id, status, requester_id, addressee_id, '
          'requester:profiles!friendships_requester_id_fkey(username, avatar), '
          'addressee:profiles!friendships_addressee_id_fkey(username, avatar)',
        );
    return rows.map((r) => FriendshipEntry.fromJson(r)).toList();
  }

  Future<void> sendRequest(String addresseeId) async {
    await _client.from('friendships').insert({
      'requester_id': _uid,
      'addressee_id': addresseeId,
    });
  }

  Future<void> accept(String friendshipId) async {
    await _client
        .from('friendships')
        .update({'status': 'accepted'})
        .eq('id', friendshipId);
  }

  /// Ablehnen, Anfrage zurückziehen oder Freundschaft beenden.
  Future<void> remove(String friendshipId) async {
    await _client.from('friendships').delete().eq('id', friendshipId);
  }

  /// Blockiert [otherId] (#584, Patch 033): Die RPC beendet die
  /// Beziehung (auch eine offene Anfrage) in derselben Transaktion; danach
  /// verwirft die Datenbank jede neue Anfrage zwischen beiden still.
  Future<void> block(String otherId) async {
    await _client.rpc('block_user', params: {'other': otherId});
  }

  /// Gibt [otherId] wieder frei. Die Beziehung kommt nicht zurück.
  Future<void> unblock(String otherId) async {
    await _client.from('user_blocks').delete().eq('blocked_id', otherId);
  }

  /// Wen ICH blockiert habe, mit Namen — die Profile selbst sind danach
  /// nicht mehr lesbar.
  Future<List<BlockedUser>> fetchBlocks() async {
    final rows = await _client.rpc('my_blocks') as List<dynamic>;
    return rows
        .map((r) => BlockedUser.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Meldet [reportedId] oder — mit [messageId] — eine Nachricht, die er
  /// mir geschickt hat. Den Text kopiert der Server selbst; lesen kann die
  /// Meldung nur der Betreiber (Dashboard).
  Future<void> report(
    String reportedId, {
    String? messageId,
    required ReportReason reason,
    String? note,
  }) async {
    await _client.rpc(
      'report_content',
      params: {
        'reported': reportedId,
        'kind': messageId == null ? 'user' : 'message',
        'message': messageId,
        'reason': reason.wire,
        'note': note,
      },
    );
  }

  /// Exakt diese Spalten prüft der Schema Check.
  static const aliasColumns = 'friend_id, alias';

  /// Die eigenen Aliase: Buddy-id → Alias. Die Policy liefert nur, was
  /// ICH vergeben habe.
  Future<Map<String, String>> fetchAliases() async {
    final rows = await _client.from('friend_aliases').select(aliasColumns);
    return {
      for (final r in rows) r['friend_id'] as String: r['alias'] as String,
    };
  }

  /// Setzt den Alias für [friendId]; ein leerer Text entfernt ihn.
  Future<void> setAlias(String friendId, String alias) async {
    final text = alias.trim();
    if (text.isEmpty) {
      await _client.from('friend_aliases').delete().eq('friend_id', friendId);
      return;
    }
    await _client.from('friend_aliases').upsert({
      'owner_id': _uid,
      'friend_id': friendId,
      'alias': text,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'owner_id,friend_id');
  }
}

/// So lang darf ein Alias sein — derselbe Wert wie der Check im Schema.
const kAliasMaxLength = 40;
