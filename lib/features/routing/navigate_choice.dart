// Das Navi-Symbol an einem Trail (#176, Feldbericht 0.73.0: „Jeder Trail
// sollte ein kleines Icon haben, um dahin zu navigieren. Zwei auswählbare
// Optionen: externe Navi-App (Koordinate teilen) oder app-interne
// MTB-Navigation — spaßig oder direkt").
//
// Ein Tipp tut, was als Standard gemerkt ist (`Settings.navDefault`);
// ohne Standard fragt ein kleines Blatt mit drei Zeilen und dem Haken
// „Als Standard merken". Ein langer Druck fragt immer — so kommt man vom
// Standard wieder weg, ohne ins Profil zu müssen.
//
// Der Weg in TrailBuddy ist ein WUNSCH an die Karte
// (`trailHeadRequestProvider`), wie „Zum Trailkopf" im Blatt: Das Symbol
// steht auch in der Liste, die Vorschau gehört aber auf die Karte.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/router_branches.dart';
import '../../core/settings.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import '../trails/trail_navigation.dart';
import 'trail_head_providers.dart';

enum NavChoice {
  external('external', Icons.directions_outlined),
  direct('direct', Icons.straight),
  fun('fun', Icons.downhill_skiing),
  easy('easy', Icons.directions_bike);

  const NavChoice(this.db, this.icon);
  final String db;
  final IconData icon;

  String label(AppLocalizations l) => switch (this) {
        external => l.navChoiceExternal,
        direct => l.navChoiceDirect,
        fun => l.navChoiceFun,
        easy => l.navChoiceEasy,
      };

  String description(AppLocalizations l) => switch (this) {
        external => l.navChoiceExternalHint,
        direct => l.navChoiceDirectHint,
        fun => l.navChoiceFunHint,
        easy => l.navChoiceEasyHint,
      };

  static NavChoice? parse(String? s) => values.where((c) => c.db == s).firstOrNull;
}

/// Das Symbol. [choose]: immer fragen (der lange Druck).
Future<void> navigateToTrail(BuildContext context, WidgetRef ref, Trail trail, {bool choose = false}) async {
  final remembered = NavChoice.parse(ref.read(settingsProvider).navDefault);
  final choice = !choose && remembered != null ? remembered : await _ask(context, ref, remembered);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case NavChoice.external:
      await navigateToTrailHead(context, trail);
    case NavChoice.direct || NavChoice.fun || NavChoice.easy:
      // Ein offenes Trail-Blatt zu, dann der Reiter, dann der Wunsch —
      // wie „Zum Trailkopf" im Blatt.
      final request = ref.read(trailHeadRequestProvider.notifier);
      final navigator = Navigator.of(context);
      if (navigator.canPop() && ModalRoute.of(context) is PopupRoute) navigator.pop();
      StatefulNavigationShell.maybeOf(context)?.goBranch(kMapBranchIndex);
      request.state = (
        trailId: trail.id,
        mode: switch (choice) {
          NavChoice.fun => RouteMode.fun,
          NavChoice.easy => RouteMode.easy,
          _ => RouteMode.direct,
        },
      );
  }
}

Future<NavChoice?> _ask(BuildContext context, WidgetRef ref, NavChoice? current) async {
  var remember = false;
  final picked = await showModalBottomSheet<NavChoice>(
    context: context,
    showDragHandle: true,
    // Fünf Zeilen mit Erklärung sind auf einem kleinen Telefon höher als
    // die Vorgabe (9/16 der Höhe) — der Haken läge sonst unter dem Rand.
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(context.l10n.navChoiceTitle, style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final c in NavChoice.values)
              ListTile(
                key: ValueKey('nav-choice-${c.db}'),
                leading: Icon(c.icon),
                title: Text(c.label(context.l10n)),
                subtitle: Text(c.description(context.l10n)),
                trailing: c == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(c),
              ),
            CheckboxListTile(
              key: const ValueKey('nav-remember'),
              value: remember,
              onChanged: (v) => setState(() => remember = v ?? false),
              title: Text(context.l10n.navChoiceRemember),
              subtitle: Text(context.l10n.navChoiceRememberHint),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
          ],
          ),
        ),
      ),
    ),
  );
  if (picked != null && remember) {
    try {
      await ref.read(settingsProvider).setNavDefault(picked.db);
    } catch (e, s) {
      logError('Navi-Standard merken', e, s);
    }
  }
  return picked;
}

/// Das kleine Symbol, das an jedem Trail steht (Liste, Schnellkarte).
class TrailNavButton extends ConsumerWidget {
  const TrailNavButton(this.trail, {super.key});

  final Trail trail;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
        onLongPress: () => navigateToTrail(context, ref, trail, choose: true),
        child: IconButton(
          key: ValueKey('trail-nav-${trail.id}'),
          tooltip: context.l10n.navChoiceTitle,
          icon: const Icon(Icons.navigation_outlined),
          onPressed: () => navigateToTrail(context, ref, trail),
        ),
      );
}
