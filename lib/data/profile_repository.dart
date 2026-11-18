import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import 'session.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.requireUid;

  /// Exakt diese Spalten prüft der Schema Check.
  static const columns = 'id, username, display_name, avatar';

  Future<Profile> fetchMyProfile() async {
    final row = await _client
        .from('profiles')
        .select(columns)
        .eq('id', _uid)
        .single();
    return Profile.fromJson(row);
  }

  Future<void> updateAvatar(int avatar) async {
    await _client.from('profiles').update({'avatar': avatar}).eq('id', _uid);
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
