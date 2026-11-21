import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../models/avatar_config.dart';
import '../../models/profile.dart';
import '../routing/route_profile.dart';

/// Das Fahrerprofil der Routing-Engine (Konzept-Routing 2.1), gerätelokal;
/// Vorgabe Bio-Bike. Gelesen vom Planer und beim Start jeder Fahrt
/// (`Ride.profile`).
class RiderProfileNotifier extends Notifier<RiderProfile> {
  @override
  RiderProfile build() =>
      RiderProfile.parse(ref.read(settingsProvider).riderProfile);

  void set(RiderProfile profile) {
    state = profile;
    ref
        .read(settingsProvider)
        .setRiderProfile(profile.name)
        .catchError(
          (Object e, StackTrace s) => logError('Fahrerprofil merken', e, s),
        );
  }
}

final riderProfileProvider =
    NotifierProvider<RiderProfileNotifier, RiderProfile>(
      RiderProfileNotifier.new,
    );

class MyProfileNotifier extends AsyncNotifier<Profile?>
    with ReadAfterWrite<Profile?> {
  @override
  Future<Profile?> build() {
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) return Future.value(null);
    return ref.read(profileRepositoryProvider).fetchMyProfile();
  }

  Future<bool> updateAvatar(AvatarConfig? avatar) async {
    await ref.read(profileRepositoryProvider).updateAvatar(avatar);
    return reloadAfterWrite('Profil neu laden');
  }

  Future<void> updateUsername(String username) async {
    await ref.read(profileRepositoryProvider).updateUsername(username);
    await reloadAfterWrite('Profil neu laden');
  }
}

final myProfileProvider = AsyncNotifierProvider<MyProfileNotifier, Profile?>(
  MyProfileNotifier.new,
);
