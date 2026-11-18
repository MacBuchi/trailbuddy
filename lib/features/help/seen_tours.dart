// Welche Touren außerhalb der Karte dieses Gerät gesehen hat (#134, ab
// #136 auch die der Reiter) — Muster PilzBuddys `SeenCoachTours`.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';

class SeenCoachTours extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.read(settingsProvider).seenCoachTours;

  bool hasSeen(String id) => state.contains(id);

  /// Merkt [id]. Der Zustand springt sofort, das Merken läuft nach — ein
  /// Fehler dabei wird nur protokolliert (wie bei `RememberedFlag`).
  void markSeen(String id) {
    if (state.contains(id)) return;
    final next = {...state, id};
    state = next;
    unawaited(
      ref
          .read(settingsProvider)
          .setSeenCoachTours(next)
          .catchError(
            (Object e, StackTrace s) => logError('Tour merken', e, s),
          ),
    );
  }
}

final seenCoachToursProvider = NotifierProvider<SeenCoachTours, Set<String>>(
  SeenCoachTours.new,
);
