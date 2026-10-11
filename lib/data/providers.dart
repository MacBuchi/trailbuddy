import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config_repository.dart';
import 'auth_repository.dart';
import 'feedback_repository.dart';
import 'friend_repository.dart';
import 'message_repository.dart';
import 'profile_repository.dart';
import 'push_repository.dart';

final supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authRepositoryProvider =
    Provider((ref) => AuthRepository(ref.watch(supabaseClientProvider)));

final profileRepositoryProvider =
    Provider((ref) => ProfileRepository(ref.watch(supabaseClientProvider)));

final friendRepositoryProvider =
    Provider((ref) => FriendRepository(ref.watch(supabaseClientProvider)));

final messageRepositoryProvider =
    Provider((ref) => MessageRepository(ref.watch(supabaseClientProvider)));

final feedbackRepositoryProvider =
    Provider((ref) => FeedbackRepository(ref.watch(supabaseClientProvider)));

final appConfigRepositoryProvider =
    Provider((ref) => AppConfigRepository(ref.watch(supabaseClientProvider)));

final pushRepositoryProvider =
    Provider((ref) => PushRepository(ref.watch(supabaseClientProvider)));

/// Auth-Zustand als Stream — steuert den Router-Redirect und sorgt dafür,
/// dass alle Daten-Provider bei Login/Logout neu laden.
final authStateProvider = StreamProvider<AuthState>(
    (ref) => ref.watch(authRepositoryProvider).onAuthStateChange);

final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).currentUserId;
});
