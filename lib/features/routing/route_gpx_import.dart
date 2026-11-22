import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/l10n.dart';
import '../garmin/watch_providers.dart';
import '../garmin/watch_shelf_actions.dart';
import '../rides/ride_providers.dart';
import '../trails/gpx.dart';
import '../trails/gpx_files.dart';
import '../trails/trail_import_screen.dart' show gpxPickerProvider;
import '../trails/trail_providers.dart' show trailsProvider;
import 'loop_planner_providers.dart' show mapFitRequestProvider;
import 'map_panel.dart';
import 'nav_providers.dart';
import 'nav_view.dart';
import 'route_progress.dart';

Future<NavRequest?> pickGpxRoute(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final routes = <NavRequest>[];
  final errors = <String>[];
  try {
    final picked = await ref.read(gpxPickerProvider)();
    if (!context.mounted || picked.isEmpty) return null;
    for (final file in picked) {
      final decoded = gpxFilesFrom(l, file);
      errors.addAll(decoded.errors);
      for (final gpx in decoded.files) {
        try {
          for (final track in parseGpx(gpx.text, fallbackName: gpx.name)) {
            final line = NavRoute.of([
              for (final p in track.points) LatLng(p.lat, p.lon),
            ]);
            if (line != null) {
              routes.add(NavRequest(points: line.points, title: track.name));
            }
          }
        } on GpxFormatException {
          errors.add(l.routeImportNoTrack);
        }
      }
    }
  } catch (_) {
    // File selection and decoding can fail before a GPX document is available.
    errors.add(l.routeImportNoTrack);
  }
  if (!context.mounted) return null;
  if (routes.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(errors.firstOrNull ?? l.routeImportNoTrack)),
    );
    return null;
  }
  if (routes.length == 1) return routes.single;
  return showDialog<NavRequest>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l.routeImportGpx),
      children: [
        for (final route in routes)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, route),
            child: Text('${route.title} · ${navStartSummary(l, route)}'),
          ),
      ],
    ),
  );
}

Future<void> showGpxRoutePanel(ScaffoldState scaffold, NavRequest route) =>
    showMapPanel(
      scaffold,
      initialSize: kMapPanelPool,
      builder: (context, scroll, panel) =>
          _GpxRoutePanel(route: route, scroll: scroll, panel: panel),
    );

class _GpxRoutePanel extends ConsumerStatefulWidget {
  const _GpxRoutePanel({
    required this.route,
    required this.scroll,
    required this.panel,
  });

  final NavRequest route;
  final ScrollController scroll;
  final MapPanelController panel;

  @override
  ConsumerState<_GpxRoutePanel> createState() => _GpxRoutePanelState();
}

class _GpxRoutePanelState extends ConsumerState<_GpxRoutePanel> {
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(mapFitRequestProvider.notifier).state = widget.route.points;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final l = context.l10n;
    final canRecord =
        ref.watch(rideRecordingAvailableProvider) &&
        !ref.watch(rideProvider.notifier).isRunning;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        MapPanelHeader(title: route.title, onClose: widget.panel.close),
        Text(navStartSummary(l, route)),
        const SizedBox(height: 8),
        NavStartOptions(
          canRecord: canRecord,
          onWatchFound: () =>
              ref.read(watchSyncProvider.notifier).prepare(route.points),
        ),
        const SizedBox(height: 8),
        NavStartButton(
          buttonKey: 'gpx-route-navigate',
          onPressed: () =>
              ref.read(navRequestProvider.notifier).state = NavRequest(
                points: route.points,
                title: route.title,
                start: navStartChoiceOf(ref, canRecord: canRecord),
              ),
        ),
        if (ref.watch(watchShelfAvailableProvider))
          TextButton.icon(
            onPressed: _sending ? null : _putOnWatch,
            icon: const Icon(Icons.watch_outlined),
            label: Text(l.watchShelfPut),
          ),
      ],
    );
  }

  Future<void> _putOnWatch() async {
    setState(() => _sending = true);
    final route = widget.route;
    try {
      await putOnWatch(
        context,
        ref,
        points: route.points,
        name: route.title,
        sections: navSectionsOfLine(
          context.l10n,
          route.points,
          ref.read(trailsProvider).valueOrNull ?? const [],
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
