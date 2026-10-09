// „Meine Bereiche" (Konzept 3.2): was auf dem Gerät liegt — Name, Größe,
// Kartenstand, auf der Karte zeigen, aktualisieren, löschen. Bereiche
// werden nie verdrängt; was bleibt, muss man sehen und loswerden können.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router_branches.dart';
import '../../core/widgets/motion.dart';
import '../map/map_regions.dart';
import 'area_downloader.dart';
import 'area_plan.dart';
import 'area_providers.dart';
import 'area_store.dart';

class AreasScreen extends ConsumerWidget {
  const AreasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(storedAreasProvider);
    final download = ref.watch(areaDownloadProvider);
    // Je Bereich gegen die Manifeste SEINER Region (#220). Eine Region,
    // die der Index gerade nicht nennt, bietet nichts an.
    final regions = ref.watch(mapRegionsProvider).valueOrNull ?? const [kDachRegion];
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Bereiche')),
      body: areasAsync.when(
        loading: () => const CenteredTrailLoader(),
        error: (e, _) => const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Die Bereiche ließen sich nicht lesen.'),
        ),
        data: (areas) {
          if (areas.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Noch kein Bereich. Speichere einen auf der Karte: Knopf „Offline-Karten", '
                'dann Ausschnitt oder Fläche wählen und speichern — die Karte bis '
                'Zoomstufe 13 samt Orten, Höhen und Wegen bleibt dann auf dem Gerät, für '
                'den Wald ohne Empfang.',
              ),
            );
          }
          var total = 0;
          for (final a in areas) {
            total += a.totalBytes;
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Bereiche liegen nur auf diesem Gerät (${formatBytes(total)}) und '
                  'werden nie von selbst gelöscht. Ohne Empfang sind sie die Karte.',
                ),
              ),
              if (download.phase == AreaDownloadPhase.running)
                ListTile(
                  leading: const SizedBox(
                      width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  title: Text('„${download.name}" wird gespeichert …'),
                  subtitle: LinearProgressIndicator(value: download.progress?.fraction),
                ),
              for (final a in areas)
                if (regions.where((r) => r.id == a.region).firstOrNull case final region?)
                  _AreaTile(a,
                      newerBuild: (ref.watch(regionMapManifestProvider(region)).valueOrNull?.sourceBuild ?? '')
                              .compareTo(a.build) >
                          0,
                      heightsMissing:
                          ref.watch(regionHeightsManifestProvider(region)).valueOrNull != null && !a.hasHeights,
                      waysMissing: ref.watch(areaWaysAvailableProvider(region)).valueOrNull != null && a.waysBuild == null)
                else
                  _AreaTile(a, newerBuild: false, heightsMissing: false, waysMissing: false),
            ],
          );
        },
      ),
    );
  }
}

class _AreaTile extends ConsumerWidget {
  const _AreaTile(this.area, {required this.newerBuild, required this.heightsMissing, required this.waysMissing});

  final StoredArea area;

  /// Der Host hat einen neueren Kartenstand als dieser Bereich.
  final bool newerBuild;

  /// Der Host hat Höhenkacheln, dieser Bereich (von vor 0.69.0 oder
  /// ohne Manifest gespeichert) noch keine — „Aktualisieren" holt sie.
  final bool heightsMissing;

  /// Der Host hat Wege, dieser Bereich (vor 0.90.0 gespeichert) hat sie
  /// noch nicht geholt — „Aktualisieren" holt sie.
  final bool waysMissing;

  /// Was „Aktualisieren" brächte, als zweite Zeile; null: nichts.
  String? get _offer => newerBuild
      ? 'Neuerer Kartenstand verfügbar'
      : heightsMissing && waysMissing
          ? 'Höhen und Wege verfügbar'
          : heightsMissing
              ? 'Höhendaten verfügbar'
              : waysMissing
                  ? 'Wege verfügbar'
                  : null;

  static String _buildLabel(String build) => build.length == 8
      ? '${build.substring(6, 8)}.${build.substring(4, 6)}.${build.substring(0, 4)}'
      : build;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('„${area.name}" löschen?'),
        content: Text('${formatBytes(area.totalBytes)} werden vom Gerät gelöscht. '
            'Ohne Empfang bleibt dort dann nur die Übersichtskarte.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(storedAreasProvider.notifier).delete(area.id);
  }

  /// Dieselbe Form mit dem neuen Kartenstand noch einmal holen — unter
  /// derselben Id, der alte Bereich wird ersetzt. Angeboten, nicht
  /// aufgezwungen; ob das Netz frei ist, entscheidet, wer tippt.
  Future<void> _update(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(areaDownloadProvider.notifier);
    try {
      final plan = await notifier.plan(area.shape);
      await notifier.start(plan, name: area.name, id: area.id);
    } on AreaTooLarge {
      messenger.showSnackBar(const SnackBar(content: Text('Der Bereich ist für den neuen Stand zu groß.')));
    } on OutsideRegions catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Der Kartenhost ist gerade nicht erreichbar.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(areaDownloadProvider.select((s) => s.busy));
    final offer = _offer;
    return ListTile(
      key: ValueKey('area-${area.id}'),
      leading: const Icon(Icons.map_outlined),
      title: Text(area.name),
      subtitle: Text('${formatBytes(area.totalBytes)} · ${area.tiles} Kacheln · '
          'Stand ${_buildLabel(area.build)}'
          '${area.poiFiles.isEmpty ? '' : ' · mit Orten'}'
          '${area.hasHeights ? ' · mit Höhen' : ''}'
          '${area.hasWays ? ' · mit Wegen' : ''}'
          '${offer == null ? '' : '\n$offer'}'),
      isThreeLine: offer != null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (offer != null)
          IconButton(
            key: ValueKey('area-update-${area.id}'),
            tooltip: 'Auf den neuen Stand bringen',
            icon: const Icon(Icons.update),
            onPressed: busy ? null : () => _update(context, ref),
          ),
        IconButton(
          key: ValueKey('area-delete-${area.id}'),
          tooltip: 'Bereich löschen',
          icon: const Icon(Icons.delete_outline),
          onPressed: busy ? null : () => _delete(context, ref),
        ),
      ]),
      onTap: () {
        // Erst der Reiter, dann der Wunsch (PilzBuddy #345).
        StatefulNavigationShell.of(context).goBranch(kMapBranchIndex);
        ref.read(mapFocusAreaProvider.notifier).state = area;
      },
    );
  }
}
