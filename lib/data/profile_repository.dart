import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/avatar_config.dart';
import '../models/profile.dart';
import 'session.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.requireUid;

  /// Exakt diese Spalten prüft der Schema Check.
  static const columns = 'id, username, display_name, profile_avatars(config)';

  Future<Profile> fetchMyProfile() async {
    final row = await _client
        .from('profiles')
        .select(columns)
        .eq('id', _uid)
        .single();
    return Profile.fromJson(row);
  }

  Future<void> updateAvatar(AvatarConfig? avatar) async {
    final uid = _uid;
    final avatars = _client.from('profile_avatars');
    if (avatar == null) {
      await avatars.delete().eq('profile_id', uid);
      return;
    }
    await avatars.upsert({'profile_id': uid, 'config': avatar.toJson()});
  }

  /// Wirft bei vergebenem Namen eine PostgrestException mit Code 23505
  /// (unique-Verletzung) — der Dialog übersetzt sie in denselben Text wie
  /// die Registrierung.
  Future<void> updateUsername(String username) async {
    await _client
        .from('profiles')
        .update({'username': username})
        .eq('id', _uid);
  }
}
