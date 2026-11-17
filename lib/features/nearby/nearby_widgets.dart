// Buddy in der Nähe (#526) — was man davon sieht: die einmalige Frage,
// der Abschnitt auf der Seite „Benachrichtigungen" und das Blatt mit den
// zwei Schaltern je Buddy.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../data/nearby_repository.dart';
import '../../l10n/l10n.dart';
import '../map/position_provider.dart';
import 'nearby_core.dart';
import 'nearby_providers.dart';

/// Fragt EINMAL nach „Buddys unterwegs", „Ja" vorausgewählt (Betreiber
/// 2026-11-17, E8). Nur, solange nie beantwortet; ein Wegtippen des
/// Dialogs zählt nicht als Antwort.
Future<void> askBuddiesNearbyOnce(BuildContext context, WidgetRef ref) async {
  if (ref.read(buddiesNearbyProvider) != null) return;
  final l = context.l10n;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('nearby-ask'),
      icon: const Icon(Icons.social_distance_outlined),
      title: Text(l.nearbyAskTitle),
      content: Text(l.nearbyAskBody),
      actions: [
        TextButton(
          key: const ValueKey('nearby-ask-no'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.nearbyAskNo),
        ),
        FilledButton(
          key: const ValueKey('nearby-ask-yes'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.nearbyAskYes),
        ),
      ],
    ),
  );
  if (yes == null) return;
  ref.read(buddiesNearbyProvider.notifier).set(yes);
}

/// Der Satz zum Zustand.
String nearbyStatusText(AppLocalizations l, NearbyPause? pause) => switch (pause) {
      null => l.nearbyStatusActive,
      NearbyPause.off => '',
      NearbyPause.noPosition => l.nearbyPauseNoPosition,
      NearbyPause.home => l.nearbyPauseHome,
      NearbyPause.nearStart => l.nearbyPauseNearStart,
      NearbyPause.background => l.nearbyPauseBackground,
      NearbyPause.noHome => l.nearbyPauseNoHome,
    };

/// Schalter, Zustand und „Zuhause" — auf der Seite „Benachrichtigungen".
class NearbySection extends ConsumerWidget {
  const NearbySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final palette = AppPalette.of(context);
    final enabled = ref.watch(buddiesNearbyProvider) == true;
    final pause = ref.watch(nearbyPauseProvider);
    final home = ref.watch(nearbyHomeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const ValueKey('nearby-switch'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.social_distance_outlined),
          title: Text(l.nearbySwitchTitle),
          subtitle: Text(l.nearbySwitchSubtitle),
          value: enabled,
          onChanged: (v) => ref.read(buddiesNearbyProvider.notifier).set(v),
        ),
        if (enabled) ...[
          Padding(
            padding: const EdgeInsets.only(left: 56, bottom: 4),
            child: Text(nearbyStatusText(l, pause),
                key: const ValueKey('nearby-status'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted)),
          ),
          ListTile(
            key: const ValueKey('nearby-home'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.home_outlined),
            title: Text(home == null ? l.nearbyHomeSet : l.nearbyHomeClear),
            subtitle: home == null ? null : Text(l.nearbyHomeIsSet),
            onTap: () async {
              if (home != null) {
                ref.read(nearbyHomeProvider.notifier).set(null);
                return;
              }
              final messenger = ScaffoldMessenger.of(context);
              final fix = await ref.read(positionFixProvider)();
              if (fix == null) {
                messenger.showSnackBar(SnackBar(content: Text(l.nearbyHomeNoPosition)));
                return;
              }
              ref.read(nearbyHomeProvider.notifier).set((lat: fix.latitude, lon: fix.longitude));
              // Erst jetzt darf der Strom laufen — die Berechtigung kam
              // eben über den Fix.
              ref.invalidate(positionStreamProvider);
            },
          ),
        ],
      ],
    );
  }
}

/// Der Knopf an der Buddy-Zeile: öffnet die zwei Schalter für [buddyId].
/// Nur, solange „Buddys unterwegs“ an ist.
class NearbyBuddyButton extends ConsumerWidget {
  const NearbyBuddyButton({super.key, required this.buddyId, required this.name});

  final String buddyId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(buddiesNearbyProvider) != true) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final pref = ref.watch(nearbyPrefsProvider).valueOrNull?[buddyId];
    final changed = pref != null && (pref.hidden || pref.muted);
    return IconButton(
      key: ValueKey('nearby-buddy-$buddyId'),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => NearbyBuddySheet(buddyId: buddyId, name: name),
      ),
      icon: Icon(changed ? Icons.location_disabled_outlined : Icons.social_distance_outlined,
          color: palette.muted),
      tooltip: context.l10n.nearbyBuddyTooltip,
    );
  }
}

class NearbyBuddySheet extends ConsumerStatefulWidget {
  const NearbyBuddySheet({super.key, required this.buddyId, required this.name});

  final String buddyId;
  final String name;

  @override
  ConsumerState<NearbyBuddySheet> createState() => _NearbyBuddySheetState();
}

class _NearbyBuddySheetState extends ConsumerState<NearbyBuddySheet> {
  bool _saving = false;

  Future<void> _save(NearbyPref next) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      await ref.read(nearbyPrefsProvider.notifier).set(next);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final palette = AppPalette.of(context);
    final pref = ref.watch(nearbyPrefsProvider).valueOrNull?[widget.buddyId] ??
        NearbyPref(buddyId: widget.buddyId);
    final on = ref.watch(buddiesNearbyProvider) == true;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.nearbySwitchTitle, style: Theme.of(context).textTheme.titleMedium),
            if (!on)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l.nearbyBuddyOff,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted)),
              ),
            SwitchListTile(
              key: const ValueKey('nearby-buddy-sees-me'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.nearbyBuddySeesMe(widget.name)),
              subtitle: Text(l.nearbyBuddySeesMeHint(widget.name)),
              value: !pref.hidden,
              onChanged: _saving
                  ? null
                  : (v) => _save(NearbyPref(buddyId: widget.buddyId, hidden: !v, muted: pref.muted)),
            ),
            SwitchListTile(
              key: const ValueKey('nearby-buddy-notify'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.nearbyBuddyNotify(widget.name)),
              value: !pref.muted,
              onChanged: _saving
                  ? null
                  : (v) => _save(NearbyPref(buddyId: widget.buddyId, hidden: pref.hidden, muted: !v)),
            ),
          ],
        ),
      ),
    );
  }
}
