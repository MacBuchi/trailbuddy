import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../profile/profile_providers.dart';

/// Der Name, den der Trigger `handle_new_user` vergibt, wenn die
/// Anmeldung keinen mitbringt — bei Google & Co. immer (#398).
final _assignedUsername = RegExp(r'^trailbuddy_[0-9a-f]{8}$');

/// Sagt einmal, wie man nach einer Anmeldung über einen Anbieter heißt,
/// und führt ins Konto zum Ändern. Wer über E-Mail kam, hat seinen Namen
/// selbst gewählt; wer ihn schon geändert hat, braucht nichts.
///
/// In der Hülle, nicht im Login-Screen: Der ist weg, sobald die Sitzung
/// steht. Eine Namenswahl vor der Karte wäre sauberer — vorgemerkt als
/// #422 (#156, Stufe 8).
class UsernameHint extends ConsumerStatefulWidget {
  const UsernameHint({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UsernameHint> createState() => _UsernameHintState();
}

class _UsernameHintState extends ConsumerState<UsernameHint> {
  @override
  void initState() {
    super.initState();
    // Sofort feuern: Das Profil kann schon geladen sein, wenn die Hülle
    // entsteht.
    ref.listenManual(myProfileProvider, (_, next) => _maybeShow(next.valueOrNull?.username),
        fireImmediately: true);
  }

  void _maybeShow(String? username) {
    if (username == null || !_assignedUsername.hasMatch(username)) return;
    if (ref.read(authRepositoryProvider).externalProvider == null) return;
    final settings = ref.read(settingsProvider);
    if (settings.usernameHintSeen) return;
    settings.setUsernameHintSeen(true);
    // Nach dem Frame: `fireImmediately` ruft noch während `initState`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.usernameHint(username)),
        duration: const Duration(seconds: 10),
        // #371: mit Aktion bliebe die Leiste sonst stehen.
        persist: false,
        action: SnackBarAction(
          label: l.usernameHintAction,
          onPressed: () => context.go('/profile/account'),
        ),
      ));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
