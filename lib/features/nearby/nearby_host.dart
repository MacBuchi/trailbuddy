// Hält „Buddy in der Nähe" (#526) am Laufen, solange die App lebt, und
// zeigt die Meldung. Liegt in `app.dart` neben dem PushListener — gemeldet
// wird überall, nicht nur auf der Karte.
//
// **Vorne eine Leiste, hinten eine Benachrichtigung.** Ohne Aufzeichnung
// teilt die App nur im Vordergrund (nearbyPause); mit Aufzeichnung lebt
// der Main-Isolate neben dem Dienst weiter, der Bildschirm ist oft aus —
// dann kommt die Meldung über den Kanal `trailbuddy_meldungen`, wie die
// Fragen der Fahrt.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../models/friendship.dart';
import '../friends/buddy_alias.dart';
import '../friends/friend_providers.dart';
import '../rides/ride_confirm_notify.dart';
import '../rides/ride_providers.dart';
import '../routing/voice_service.dart' show VoiceSpeak, speakVoice;
import 'nearby_core.dart';
import 'nearby_providers.dart';

/// Zeigt die Meldung, während die App im Hintergrund ist. Im Test
/// überschrieben; auf dem Web und ohne Kanal tut sie nichts.
typedef NearbyBackgroundNotice = Future<void> Function({required String title, required String body, required int id});

final nearbyBackgroundNoticeProvider = Provider<NearbyBackgroundNotice>((ref) => _platformNotice);

Future<void> _platformNotice({required String title, required String body, required int id}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await initRideNotices();
    await rideNoticesPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          kConfirmChannelId,
          kConfirmChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  } catch (_) {
    // Kein Kanal, keine Berechtigung: Die Meldung ist ein Zusatz.
  }
}

/// Spricht die Meldung (#525: Ansagen übers Ohr) — im Test überschrieben.
final nearbySpeakProvider = Provider<VoiceSpeak>((ref) => speakVoice);

/// Wie oft ohne andere Änderung abgeglichen wird (Zelle auffrischen,
/// abgelehnten Kanälen neu beitreten). Nur, solange geteilt wird.
const kNearbyTick = Duration(minutes: 1);

/// Die Sitzung ohne Aufzeichnung: ein Prozess der App.
final Object _appSession = Object();

class NearbyHost extends ConsumerStatefulWidget {
  const NearbyHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NearbyHost> createState() => _NearbyHostState();
}

class _NearbyHostState extends ConsumerState<NearbyHost> {
  late final NearbyEngine _engine;
  late final AppLifecycleListener _lifecycle;
  Timer? _tick;
  bool _wasActive = false;
  final _subs = <ProviderSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _engine = NearbyEngine(ref.read(nearbyRepositoryProvider), onNotice: _notice, onSightings: (list) {
      if (mounted) ref.read(buddySightingsProvider.notifier).set(list);
    });
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) => ref
          .read(appForegroundProvider.notifier)
          .set(s == AppLifecycleState.resumed || s == AppLifecycleState.inactive),
    );
    void watch<T>(ProviderListenable<T> p) =>
        _subs.add(ref.listenManual<T>(p, (_, _) => _sync()));
    watch(nearbyPauseProvider);
    watch(nearbyPositionProvider);
    watch(friendshipsProvider);
    watch(nearbyPrefsProvider);
    watch(rideProvider);
    watch(currentUserIdProvider);
    watch(liveShareProvider);
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final pause = ref.read(nearbyPauseProvider);
    final position = ref.read(nearbyPositionProvider);
    final uid = ref.read(currentUserIdProvider);
    final active = pause == null && position != null && uid != null;
    final buddies = <String>{
      if (uid != null)
        for (final f in ref.read(friendshipsProvider).valueOrNull ?? const <FriendshipEntry>[])
          if (f.isAccepted) f.otherId(uid),
    };
    // Ohne geladene Schalter je Buddy (Start, kein Empfang) wird niemand
    // gemeldet — lieber eine Meldung zu spät als eine, die stumm war.
    final prefs = ref.read(nearbyPrefsProvider).valueOrNull;
    final ride = ref.read(rideProvider);
    // Live (#519) nur in einer Fahrt, mit dem Schalter dieser Fahrt.
    final live = active && ride != null && ref.read(liveShareProvider);
    unawaited(_engine.sync(
      mine: active ? NearbyCell.of(position.lat, position.lon) : null,
      buddies: buddies,
      muted: prefs == null ? null : {for (final p in prefs.values) if (p.muted) p.buddyId},
      session: ride?.startedAt ?? _appSession,
      live: live,
      position: live ? position : null,
    ));
    // Wer mich als Homie gewählt hat, kann sich geändert haben — einmal je
    // Beginn des Teilens neu fragen.
    if (active && !_wasActive) ref.invalidate(homieOwnersProvider);
    _wasActive = active;
    if (active && _tick == null) {
      _tick = Timer.periodic(kNearbyTick, (_) => _sync());
    } else if (!active) {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _notice(String buddyId) {
    if (!mounted) return;
    final uid = ref.read(currentUserIdProvider);
    final friendship = (ref.read(friendshipsProvider).valueOrNull ?? const <FriendshipEntry>[])
        .where((f) => uid != null && f.isAccepted && f.otherId(uid) == buddyId)
        .firstOrNull;
    if (friendship == null || uid == null) return;
    final name = ref.read(buddyNamesViewProvider).of(buddyId, friendship.otherUsername(uid));
    final l = context.l10n;
    final body = l.nearbyNotice(name);
    // Mit „Ansagen" (#525) und laufender Fahrt auch übers Ohr — das Handy
    // steckt dann meist in der Tasche.
    if (ref.read(voiceCuesProvider) && ref.read(rideProvider) != null) {
      unawaited(ref.read(nearbySpeakProvider)(body, Localizations.localeOf(context)));
    }
    if (!ref.read(appForegroundProvider)) {
      unawaited(ref.read(nearbyBackgroundNoticeProvider)(
          title: l.nearbyNoticeTitle, body: body, id: _noticeId(buddyId)));
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      key: const ValueKey('nearby-notice'),
      content: Text(body),
      duration: const Duration(seconds: 6),
      persist: false,
    ));
  }

  /// Eine Kennung je Buddy im Bereich der Meldungen, fern von denen der
  /// Fahrt (Trail-Fragen, Wheelies).
  static int _noticeId(String buddyId) => 0x52600000 + (buddyId.hashCode & 0xffff);

  @override
  void dispose() {
    _tick?.cancel();
    for (final s in _subs) {
      s.close();
    }
    _lifecycle.dispose();
    unawaited(_engine.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
