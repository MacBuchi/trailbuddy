// Zeigt Benachrichtigungen an, die eintreffen, während die App vorne ist,
// und folgt dem Tipp auf eine Meldung (#34; PilzBuddy #277/#564).
//
// **Warum es das überhaupt braucht:** Android zeigt eine
// `notification`-Nutzlast nur an, solange die App NICHT im Vordergrund
// ist. Ist sie es, liefert FCM sie ausschließlich an `onMessage` — und
// ohne Zuhörer verschwindet sie spurlos.
//
// Liegt im Widget-Baum ganz außen (`app.dart`), damit es überall
// funktioniert und nicht nur auf der Karte — eine Meldung kann eintreffen,
// während jemand im Profil steht.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/friends/message_providers.dart';
import '../../features/profile/push_providers.dart';
import '../../l10n/l10n.dart';
import '../../features/rides/ride_confirm_notify.dart';
import '../../features/trails/trail_providers.dart';
import '../errors.dart';
import '../push_messaging.dart';
import '../push_routes.dart';
import '../router.dart';

class PushListener extends ConsumerStatefulWidget {
  const PushListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushListener> createState() => _PushListenerState();
}

class _PushListenerState extends ConsumerState<PushListener> {
  StreamSubscription<RemoteMessage>? _subscription;
  StreamSubscription<RemoteMessage>? _taps;
  StreamSubscription<String>? _confirmTaps;

  @override
  void initState() {
    super.initState();
    // Nach dem ersten Frame: Vorher gibt es keinen ScaffoldMessenger, an
    // den sich eine SnackBar hängen könnte.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _subscription = ref.read(pushMessageListenerProvider)().listen(_show);
      } catch (e, stackTrace) {
        // Push ist ein Nebenfeature: Ohne Firebase gibt es diesen Strom
        // nicht, und die App läuft trotzdem.
        logError('Vordergrund-Nachrichten verdrahten', e, stackTrace);
      }
      // Der Tipp auf eine Meldung: aus dem Hintergrund über den Strom,
      // aus dem beendeten Zustand über die Startmeldung.
      try {
        _taps = ref.read(pushTapListenerProvider)().listen(_open);
        ref.read(pushInitialMessageProvider)().then((message) {
          if (message != null) _open(message);
        }, onError: (Object e, StackTrace s) {
          logError('Startmeldung lesen', e, s);
        });
      } catch (e, stackTrace) {
        logError('Tipp auf Meldungen verdrahten', e, stackTrace);
      }
      // Die lokale Frage während einer Fahrt (#116): Ein Tipp darauf oder
      // auf „Ändern…" zeigt den Trail — gemeldet wird dort.
      _confirmTaps = ref.read(rideConfirmTapsProvider)().listen((trailId) {
        final route = pushRouteOf({'route': '/trail/$trailId'});
        if (route != null && mounted) ref.read(routerProvider).go(route);
      });
    });
  }

  /// Die Sprache der App bestimmt die Sprache der Meldungen (#209). Hier,
  /// weil dieses Widget unter `Localizations` lebt und es bei JEDEM
  /// Wechsel neu erfährt — Schalter im Profil wie Gerätesprache.
  /// `syncLocale` schreibt nur, wenn sie sich vom Gemerkten unterscheidet.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = pushLocaleOf(Localizations.localeOf(context));
    unawaited(ref.read(pushEnabledProvider.notifier).syncLocale(locale));
  }

  /// Folgt dem Ziel einer Meldung — nur, wenn es auf der Erlaubnisliste
  /// steht (`pushRouteOf`). Vorher frisch holen: Die Meldung sagt ja
  /// gerade, dass es Neues gibt. `/trail/<id>` löst der Router auf (er
  /// setzt den Fokus der Karte), `/trails` ist die Liste,
  /// `/friends/chat/<id>` der Verlauf mit einem Buddy.
  void _open(RemoteMessage message) {
    final route = pushRouteOf(message.data);
    if (route == null || !mounted) return;
    _refresh(route);
    ref.read(routerProvider).go(route);
  }

  /// Was die Meldung ankündigt, ist ab jetzt alt: Nachrichten oder Trails.
  void _refresh(String route) => isPushChatRoute(route)
      ? ref.invalidate(messagesProvider)
      : ref.invalidate(trailsProvider);

  void _show(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null || !mounted) return;
    // Was die Meldung ankündigt, soll die Liste auch zeigen: Der Stand
    // ist ab jetzt alt.
    final route = pushRouteOf(message.data);
    if (route != null) _refresh(route);
    // Steht der Verlauf schon offen, ist die Nachricht dort zu lesen,
    // sobald er neu geladen hat — eine SnackBar darüber wäre doppelt.
    if (route != null &&
        isPushChatRoute(route) &&
        ref.read(routerProvider).routerDelegate.currentConfiguration.uri.path == route) {
      return;
    }
    final body = notification.body;
    if (body == null || body.isEmpty) return;
    // Der TITEL trägt die Aussage („Ein Buddy meldet einen Trail als
    // gesperrt"), der Rumpf nur die Ergänzung — Android zeigt beides,
    // hier muss es also auch beides sein.
    final title = notification.title;
    final messenger = ScaffoldMessenger.of(context);
    // Erst räumen, dann zeigen. `showSnackBar` stellt sich sonst hinten
    // an: Beim Testknopf stand „Testnachricht ist unterwegs." vier
    // Sekunden lang davor, und genau in dieser Zeit traf die Meldung
    // ein — es sah aus, als käme im Vordergrund nichts an (PilzBuddy,
    // 2026-08-12). Eintreffende Meldung schlägt stehende Rückmeldung.
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null && title.isNotEmpty)
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(body),
        ],
      ),
      duration: const Duration(seconds: 4),
      action: route == null
          ? null
          : SnackBarAction(
              label: context.l10n.pushOpen,
              onPressed: () => _open(message),
            ),
    ));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _taps?.cancel();
    _confirmTaps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
