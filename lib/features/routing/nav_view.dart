// Die Folgeansicht der Navigation (#232, Konzept-Routing 9.2): eine Lage
// ÜBER der Karte, keine eigene Karte — dieselbe Fassade, derselbe Stil,
// dieselben Bereiche offline. Die Karte (`map_screen.dart`) dreht und
// folgt, hier stehen Leiste, Knöpfe und der Start-Dialog.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/geo.dart';
import '../../core/screen_awake.dart';
import '../map/map_buttons.dart';
import '../map/map_view/map_view.dart';
import 'nav_providers.dart';

/// Die Route auf der Karte: der gefahrene Teil blass, der Rest in der
/// Farbe des Ergebnisses mit weißem Saum. Liegt unter dem Netz — Trails
/// auf der Route behalten ihre Farbe (Design 7).
List<MapViewPolyline> navRouteLines(NavSession session) {
  final c = AppColors.mapLines.ride;
  final along = session.state?.alongM ?? 0;
  final (done, rest) = session.route.splitAt(along);
  return [
    if (done.length >= 2) MapViewPolyline(points: done, color: c.withValues(alpha: 0.35), width: 5),
    MapViewPolyline(
      points: rest,
      color: c,
      width: 6,
      borderColor: AppColors.mapLines.halo,
      borderWidth: AppColors.mapLines.haloBorderWidth,
    ),
  ];
}

/// Was der Start-Dialog zurückgibt.
class NavStartChoice {
  const NavStartChoice({required this.record});

  /// Die Fahrt mit aufzeichnen (9.4).
  final bool record;
}

/// Vor dem Start: Aufzeichnen (nur wenn es geht und noch keine läuft)
/// und Bildschirm (nur wo es den Weg gibt). Vorgabe beider: an
/// (Betreiber, 2026-10-08). Null heißt abgebrochen.
Future<NavStartChoice?> showNavStartSheet(BuildContext context, {required String title, required bool canRecord}) =>
    showModalBottomSheet<NavStartChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NavStartSheet(title: title, canRecord: canRecord),
    );

class _NavStartSheet extends ConsumerStatefulWidget {
  const _NavStartSheet({required this.title, required this.canRecord});

  final String title;
  final bool canRecord;

  @override
  ConsumerState<_NavStartSheet> createState() => _NavStartSheetState();
}

class _NavStartSheetState extends ConsumerState<_NavStartSheet> {
  bool _record = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = ref.watch(screenAwakeProvider).supported;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Navigieren', style: theme.textTheme.titleLarge),
            Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            if (widget.canRecord)
              SwitchListTile(
                key: const ValueKey('nav-record'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Fahrt mit aufzeichnen'),
                subtitle: const Text('Wie der Knopf auf der Karte — danach zerlegst du sie wie immer.'),
                value: _record,
                onChanged: (v) => setState(() => _record = v),
              ),
            if (screen)
              SwitchListTile(
                key: const ValueKey('nav-screen'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Bildschirm anlassen'),
                subtitle: const Text('Solange die Navigation vorne ist.'),
                value: ref.watch(navKeepScreenOnProvider),
                onChanged: (v) => ref.read(navKeepScreenOnProvider.notifier).set(v),
              ),
            const SizedBox(height: 8),
            Text(
              'Die Karte zeigt die Route und dreht mit — ohne Abbiegehinweise, fahre nach Sicht.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('nav-go'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.of(context).pop(NavStartChoice(record: widget.canRecord && _record)),
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Navigation starten'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Leiste oben, Knöpfe unten; hält den Bildschirm an, solange sie steht
/// und der Schalter an ist.
class NavOverlay extends ConsumerStatefulWidget {
  const NavOverlay({super.key, required this.session, required this.onStop});

  final NavSession session;
  final VoidCallback onStop;

  @override
  ConsumerState<NavOverlay> createState() => _NavOverlayState();
}

class _NavOverlayState extends ConsumerState<NavOverlay> {
  // Beim Aufbau gegriffen: Im `dispose` ist `ref` nicht mehr zu lesen.
  late final ScreenAwake _screen = ref.read(screenAwakeProvider);

  @override
  void initState() {
    super.initState();
    if (ref.read(navKeepScreenOnProvider)) unawaited(_screen.keepOn(true));
  }

  @override
  void dispose() {
    unawaited(_screen.keepOn(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(navKeepScreenOnProvider, (_, on) => unawaited(_screen.keepOn(on)));
    final session = widget.session;
    final keepOn = ref.watch(navKeepScreenOnProvider);
    return Stack(children: [
      SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: session.state?.arrived ?? false
                ? _ArrivedBar(onStop: widget.onStop)
                : _NavBar(session: session),
          ),
        ),
      ),
      SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                MapRoundButton(
                  key: const ValueKey('nav-north'),
                  tooltip: session.north ? 'Mit der Fahrtrichtung drehen' : 'Norden oben',
                  icon: Icons.explore_outlined,
                  active: session.north,
                  onPressed: () => ref.read(navigationProvider.notifier).toggleNorth(),
                ),
                if (_screen.supported) ...[
                  const SizedBox(width: 10),
                  MapRoundButton(
                    key: const ValueKey('nav-screen-toggle'),
                    tooltip: keepOn ? 'Bildschirm darf ausgehen' : 'Bildschirm anlassen',
                    icon: keepOn ? Icons.light_mode : Icons.light_mode_outlined,
                    active: keepOn,
                    onPressed: () => ref.read(navKeepScreenOnProvider.notifier).set(!keepOn),
                  ),
                ],
                const Spacer(),
                FilledButton.icon(
                  key: const ValueKey('nav-stop'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: widget.onStop,
                  icon: const Icon(Icons.close),
                  label: const Text('Beenden'),
                ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Drei Zahlen: Rest in km, Rest bergauf, Abstand zur Linie. Keine
/// Restzeit — das Zeitmodell ist ±30 %, eine Uhr, die am Berg nachgeht,
/// liest man als Fehler (9.2).
class _NavBar extends StatelessWidget {
  const _NavBar({required this.session});

  final NavSession session;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = session.state;
    final climb = session.remainingClimbM;
    final off = state?.offRoute ?? false;
    return Card(
      key: const ValueKey('nav-bar'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Expanded(child: _NavNumber(key: const ValueKey('nav-remaining'), value: formatMeters(session.remainingM), label: 'noch')),
            if (climb != null)
              Expanded(
                  child: _NavNumber(key: const ValueKey('nav-climb'), value: '${climb.round()} hm', label: 'bergauf')),
            Expanded(
              child: _NavNumber(
                key: const ValueKey('nav-off'),
                value: state == null ? '–' : formatMeters(state.offM),
                label: off ? 'neben der Route' : 'zur Route',
                color: off ? palette.warningText : null,
                // Abseits zeigt ein Pfeil zur Linie voraus — gedreht gegen
                // die Karte, damit er auf dem Schirm stimmt.
                arrowDeg: off && state != null
                    ? bearingDegrees(state.position.latitude, state.position.longitude, state.rejoin.latitude,
                            state.rejoin.longitude) -
                        session.bearingDeg
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavNumber extends StatelessWidget {
  const _NavNumber({super.key, required this.value, required this.label, this.color, this.arrowDeg});

  final String value;
  final String label;
  final Color? color;
  final double? arrowDeg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Verkleinert statt überzulaufen: drei Zahlen auf 360 dp, und beim
    // Wechsel des Reiters ist die Fläche ein paar Bilder lang winzig.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (arrowDeg != null)
              Transform.rotate(
                key: const ValueKey('nav-off-arrow'),
                angle: arrowDeg! * 3.141592653589793 / 180,
                child: Icon(Icons.navigation, size: 18, color: color),
              ),
            Text(
              value,
              maxLines: 1,
              style: theme.textTheme.titleLarge?.copyWith(fontFamily: AppFonts.mono, color: color),
            ),
          ],
        ),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color ?? theme.hintColor)),
      ],
      ),
    );
  }
}

class _ArrivedBar extends StatelessWidget {
  const _ArrivedBar({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('nav-arrived'),
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.sports_score),
          title: const Text('Angekommen'),
          subtitle: const Text('Die Navigation endet gleich von selbst.'),
          onTap: onStop,
        ),
      );
}
