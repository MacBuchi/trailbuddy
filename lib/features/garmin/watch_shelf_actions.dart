// „Auf die Uhr legen" (#515) an Planer, geplanter und eigener Fahrt, und die
// Seite „Uhr" im Profil mit dem, was auf der Uhr liegt. Die Regeln stehen in
// `watch_shelf.dart`; hier wird nur gebaut, gefragt und gesagt.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors.dart';
import '../../core/geo.dart' show formatMeters;
import '../../core/settings.dart';
import '../../l10n/l10n.dart';
import '../offline_areas/height_tiles.dart'
    show hysteresisClimb, kClimbHysteresisM;
import '../routing/nav_sections.dart';
import '../trails/terrain_heights.dart';
import 'watch_branches.dart';
import 'watch_providers.dart'
    show kWatchBranchesWait, kWatchHeightsWait, watchBranchesLoaderProvider;
import 'watch_ride_inbox.dart' show watchRideInboxProvider;
import 'watch_route.dart';
import 'watch_shelf.dart';

/// Steht „Auf die Uhr legen"? Nur, wo es eine Uhr geben kann (nicht im
/// Web, A9), und erst, wenn einmal eine mit unserer App da war — wie das
/// Lauschen auf ihre Fahrten (#484).
final watchShelfAvailableProvider = Provider<bool>(
  (ref) => !kIsWeb && ref.watch(settingsProvider).watchSeen,
);

/// Die Linie [points] mit Namen [name] auf die Uhr legen: vereinfacht, mit
/// Höhen und Abzweigungen, wenn sie rechtzeitig kommen (wie die Navigation,
/// `WatchSync._show`). Ist die Ablage voll, fragt ein Dialog, welche Route
/// weichen soll. Eine Leiste sagt, wie es ausging.
Future<void> putOnWatch(
  BuildContext context,
  WidgetRef ref, {
  required List<LatLng> points,
  required String name,
  NavSections sections = NavSections.none,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  void say(String text) => messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 5),
        persist: false,
      ),
    );

  final shelf = ref.read(watchShelfProvider);
  String? replace;
  if (shelf.full) {
    replace = await _askReplace(context, shelf.shown);
    if (replace == null || !context.mounted) return;
  }
  say(l.watchShelfPreparing);
  // Auf die Uhr hören, falls die App heute noch nicht lauschte.
  unawaited(ref.read(watchRideInboxProvider.notifier).start());
  final heightsSoon = ref
      .read(terrainHeightsProvider)
      .profile(points)
      .timeout(kWatchHeightsWait, onTimeout: () => null)
      .catchError((Object e, StackTrace s) {
        logError('Höhen für die Ablage', e, s);
        return null;
      });
  final branches = await ref
      .read(watchBranchesLoaderProvider)(points)
      .timeout(kWatchBranchesWait, onTimeout: () => const <WatchBranch>[])
      .catchError((Object e, StackTrace s) {
        logError('Abzweigungen für die Ablage', e, s);
        return const <WatchBranch>[];
      });
  final heights = await heightsSoon;
  final route = watchRouteOf(
    points,
    sections,
    heights: heights,
    branches: branches,
  );
  if (route == null) return say(l.watchShelfUnfit);
  final entry = WatchShelfEntry(
    id: route.id,
    name: name.length <= kWatchNameChars
        ? name
        : '${name.substring(0, kWatchNameChars - 1)}…',
    lengthM: cumulativeM(points).last.round(),
    climbM: route.ele == null
        ? 0
        : hysteresisClimb([
            for (final e in route.ele!) e.toDouble(),
          ], kClimbHysteresisM).$1.round(),
  );
  final put = await ref
      .read(watchShelfProvider.notifier)
      .put(entry, route, replace: replace);
  final strong = route.tolM >= kWatchShelfStrongTolM;
  final text = switch (put) {
    WatchShelfPut.sending => l.watchShelfSending(entry.name),
    WatchShelfPut.waiting => l.watchShelfWaiting(entry.name),
    WatchShelfPut.already => l.watchShelfAlready,
    WatchShelfPut.notInstalled => l.watchShelfNotInstalled,
  };
  say(
    strong && (put == WatchShelfPut.sending || put == WatchShelfPut.waiting)
        ? '$text ${l.watchShelfSimplified}'
        : text,
  );
}

/// Die Ablage ist voll: welche Route soll weichen? Null heißt abbrechen.
Future<String?> _askReplace(BuildContext context, List<WatchShelfEntry> shown) {
  final l = context.l10n;
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      key: const ValueKey('watch-shelf-replace'),
      title: Text(l.watchShelfFullTitle),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(l.watchShelfFullBody(kWatchShelfMax)),
        ),
        for (final e in shown)
          SimpleDialogOption(
            key: ValueKey('watch-shelf-replace-${e.id}'),
            onPressed: () => Navigator.pop(context, e.id),
            child: Text('${e.name} · ${formatMeters(e.lengthM.toDouble())}'),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
      ],
    ),
  );
}

/// Die Seite „Uhr" im Profil: was auf der Uhr liegt, was noch kommt, und
/// Entfernen.
class WatchShelfScreen extends ConsumerWidget {
  const WatchShelfScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(watchShelfProvider);
    final pending = {for (final e in s.pending) e.id};
    final shown = s.shown;
    return Scaffold(
      appBar: AppBar(title: Text(l.watchShelfTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(l.watchShelfIntro(kWatchShelfMax)),
          ),
          if (s.failed != null && s.failure != null)
            ListTile(
              key: const ValueKey('watch-shelf-failed'),
              leading: const Icon(Icons.error_outline),
              title: Text(switch (s.failure!) {
                WatchShelfFailure.full => l.watchShelfFailedFull(s.failed!),
                WatchShelfFailure.refused => l.watchShelfFailedRefused(
                  s.failed!,
                ),
                WatchShelfFailure.outdated => l.watchShelfFailedOutdated,
              }),
            ),
          if (shown.isEmpty)
            ListTile(
              key: const ValueKey('watch-shelf-empty'),
              title: Text(l.watchShelfEmpty),
            ),
          for (final e in shown)
            ListTile(
              key: ValueKey('watch-shelf-${e.id}'),
              leading: Icon(
                pending.contains(e.id) ? Icons.schedule : Icons.watch,
              ),
              title: Text(e.name),
              subtitle: Text(
                [
                  formatMeters(e.lengthM.toDouble()),
                  if (e.climbM > 0) '${e.climbM} hm',
                  if (pending.contains(e.id)) l.watchShelfComing,
                ].join(' · '),
              ),
              trailing: IconButton(
                key: ValueKey('watch-shelf-remove-${e.id}'),
                tooltip: l.watchShelfRemove,
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    ref.read(watchShelfProvider.notifier).remove(e.id),
              ),
            ),
          for (final id in s.removing)
            if (s.entries.any((e) => e.id == id))
              ListTile(
                key: ValueKey('watch-shelf-leaving-$id'),
                leading: const Icon(Icons.schedule),
                title: Text(s.entries.firstWhere((e) => e.id == id).name),
                subtitle: Text(l.watchShelfLeaving),
              ),
        ],
      ),
    );
  }
}
