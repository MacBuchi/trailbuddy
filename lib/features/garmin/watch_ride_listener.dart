// Beim Start der App auf die Uhr lauschen, wenn schon einmal eine da war,
// und zeigen, wenn eine Fahrt von ihr ankam (#484). Liegt in `app.dart`
// neben dem `PushListener`: Eine Fahrt kann ankommen, während jemand im
// Profil steht, nicht nur auf der Karte.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router.dart';
import '../../l10n/l10n.dart';
import 'watch_ride_inbox.dart';

class WatchRideListener extends ConsumerStatefulWidget {
  const WatchRideListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WatchRideListener> createState() => _WatchRideListenerState();
}

class _WatchRideListenerState extends ConsumerState<WatchRideListener> {
  @override
  void initState() {
    super.initState();
    // Nach dem ersten Frame: Vorher gibt es keinen ScaffoldMessenger.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.listenManual(watchRideInboxProvider, (previous, next) {
        if (next > (previous ?? 0)) _show();
      });
      ref.read(watchRideInboxProvider.notifier).startIfKnown();
    });
  }

  void _show() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(context.l10n.watchRideSaved),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: context.l10n.watchRideShow,
        onPressed: () => ref.read(routerProvider).go('/profile/rides'),
      ),
      persist: false,
    ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
