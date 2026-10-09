// „Meine Bereiche" (Konzept 3.2): was auf dem Gerät liegt — Name, Größe,
// Kartenstand, auf der Karte zeigen, aktualisieren, löschen. Bereiche
// werden nie verdrängt; was bleibt, muss man sehen und loswerden können.
// Seit 0.106.0 (#229) teilen Bereiche ihre Kacheln: Die Zeile nennt, was
// ein Bereich ALLEIN belegt — das, was sein Löschen frei gibt —, und ein
// abgebrochener Download steht als „unvollständig" mit „Fortsetzen" da.
// Seit 0.107.0 (#229 Schritt 4) das Alter je Kachel, je Region: eine Zeile
// sagt, wie viele Kacheln älter sind als der Stand des Hosts, und
// „Aktualisieren" holt nur sie — über alle Bereiche der Region zusammen.
// Seit 0.105.0 auch die Übersicht einer Region (#220 Schritt 4): eine
// eigene Zeile mit Größe und Löschen-Knopf, und wo sie fehlt oder älter
// ist, ein Knopf, der nur sie holt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connectivity.dart';
import '../../core/router_branches.dart';
import '../../core/widgets/motion.dart';
import '../map/map_regions.dart';
import '../map/online_map.dart';
import 'area_downloader.dart';
import 'area_plan.dart';
import 'area_providers.dart';
import 'area_store.dart';

/// `JJJJMMTT` als `TT.MM.JJJJ`.
String buildLabel(String build) => build.length == 8
    ? '${build.substring(6, 8)}.${build.substring(4, 6)}.${build.substring(0, 4)}'
    : build;

class AreasScreen extends ConsumerWidget {
  const AreasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(storedAreasProvider);
    final download = ref.watch(areaDownloadProvider);
    // Je Bereich gegen die Manifeste SEINER Region (#220). Eine Region,
    // die der Index gerade nicht nennt, bietet nichts an.
    final regions = ref.watch(mapRegionsProvider).valueOrNull ?? const [kDachRegion];
    final overviews = ref.watch(storedOverviewsProvider).valueOrNull ?? const <StoredOverview>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Bereiche')),
      body: areasAsync.when(
        loading: () => const CenteredTrailLoader(),
        error: (e, _) => const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Die Bereiche ließen sich nicht lesen.'),
        ),
        data: (areas) {
          if (areas.isEmpty && overviews.isEmpty) {
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
          var total = ref.watch(areaStoredBytesProvider).valueOrNull ?? 0;
          for (final o in overviews) {
            total += o.bytes;
          }
          // Je Region außer DACH (Übersicht im Binary) eine Zeile, sobald
          // dort ein Bereich oder eine Übersicht liegt.
          final overviewRegions = [
            for (final r in regions)
              if (!r.isDach &&
                  (areas.any((a) => a.region == r.id) || overviews.any((o) => o.region == r.id)))
                r,
          ];
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Bereiche liegen nur auf diesem Gerät (${formatBytes(total)}) und '
                  'werden nie von selbst gelöscht. Ohne Empfang sind sie die Karte. Wo sich '
                  'Bereiche überschneiden, liegt jede Kachel nur einmal.',
                ),
              ),
              if (download.phase == AreaDownloadPhase.running)
                ListTile(
                  leading: const SizedBox(
                      width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  title: Text(download.refreshing
                      ? '${download.name} wird aktualisiert …'
                      : '„${download.name}" wird gespeichert …'),
                  subtitle: LinearProgressIndicator(value: download.progress?.fraction),
                  trailing: IconButton(
                    key: const ValueKey('area-download-cancel'),
                    tooltip: 'Abbrechen',
                    icon: const Icon(Icons.close),
                    onPressed: () => ref.read(areaDownloadProvider.notifier).cancel(),
                  ),
                ),
              // Je Region mit Bereichen das Alter ihrer Kacheln (#229
              // Schritt 4): Aktualisiert wird die Region, nicht der Bereich.
              for (final r in regions)
                if (areas.any((a) => a.region == r.id)) _RegionTile(r),
              for (final a in areas)
                if (regions.where((r) => r.id == a.region).firstOrNull case final region?)
                  _AreaTile(a,
                      heightsMissing:
                          ref.watch(regionHeightsManifestProvider(region)).valueOrNull != null && !a.hasHeights,
                      waysMissing: ref.watch(areaWaysAvailableProvider(region)).valueOrNull != null && a.waysBuild == null)
                else
                  _AreaTile(a, heightsMissing: false, waysMissing: false),
              for (final r in overviewRegions)
                _OverviewTile(
                  regionId: r.id,
                  name: r.name,
                  region: r,
                  stored: overviews.where((o) => o.region == r.id).firstOrNull,
                  available: ref.watch(regionOverviewAvailableProvider(r)).valueOrNull,
                ),
              // Eine Übersicht, deren Region der Index gerade nicht nennt:
              // sehen und löschen muss man sie trotzdem können.
              for (final o in overviews)
                if (!regions.any((r) => r.id == o.region))
                  _OverviewTile(regionId: o.region, name: o.region.toUpperCase(), stored: o, available: null),
            ],
          );
        },
      ),
    );
  }
}

class _AreaTile extends ConsumerWidget {
  const _AreaTile(this.area, {required this.heightsMissing, required this.waysMissing});

  final StoredArea area;

  /// Der Host hat Höhenkacheln, dieser Bereich (von vor 0.69.0 oder
  /// ohne Manifest gespeichert) noch keine — „Aktualisieren" holt sie.
  final bool heightsMissing;

  /// Der Host hat Wege, dieser Bereich (vor 0.90.0 gespeichert) hat sie
  /// noch nicht geholt — „Aktualisieren" holt sie.
  final bool waysMissing;

  /// Was „Aktualisieren" brächte, als zweite Zeile; null: nichts. Ein
  /// neuerer Kartenstand steht seit 0.107.0 an der Region (#229 Schritt 4)
  /// — die Kacheln gehören ihr, nicht dem Bereich.
  String? get _offer => heightsMissing && waysMissing
          ? 'Höhen und Wege verfügbar'
          : heightsMissing
              ? 'Höhendaten verfügbar'
              : waysMissing
                  ? 'Wege verfügbar'
                  : null;


  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // Der letzte Bereich einer Region nimmt ihre Übersicht mit (#220
    // Schritt 4) — der Dialog sagt es, mit Größe.
    final areas = ref.read(storedAreasProvider).valueOrNull ?? const <StoredArea>[];
    final last = !areas.any((a) => a.id != area.id && a.region == area.region);
    final overview = last
        ? (ref.read(storedOverviewsProvider).valueOrNull ?? const <StoredOverview>[])
            .where((o) => o.region == area.region)
            .firstOrNull
        : null;
    // Nur was KEIN anderer Bereich deckt, geht (#229).
    final alone = await ref.read(areaExclusiveBytesProvider(area.id).future);
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('„${area.name}" löschen?'),
        content: Text(overview == null
            ? '${formatBytes(alone)} werden vom Gerät gelöscht — was ein anderer Bereich '
                'auch braucht, bleibt. Ohne Empfang bleibt sonst nur die Übersichtskarte.'
            : '${formatBytes(alone + overview.bytes)} werden vom Gerät gelöscht — '
                'es ist der letzte Bereich dort, die Übersichtskarte der Region geht mit.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(storedAreasProvider.notifier).delete(area.id);
  }

  /// Dieselbe Form noch einmal planen, unter derselben Id: mit [refresh]
  /// auch die Kacheln älterer Bauten (Höhen oder Wege nachholen), sonst nur,
  /// was fehlt (Fortsetzen nach einem Abbruch). Angeboten, nicht aufgezwungen; ob das
  /// Netz frei ist, entscheidet, wer tippt.
  Future<void> _update(BuildContext context, WidgetRef ref, {bool refresh = true}) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(areaDownloadProvider.notifier);
    try {
      final plan = await notifier.plan(area.shape, refresh: refresh);
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
    final pending = !area.complete;
    final offer = pending ? 'Unvollständig — „Fortsetzen" holt den Rest' : _offer;
    final alone = ref.watch(areaExclusiveBytesProvider(area.id)).valueOrNull;
    return ListTile(
      key: ValueKey('area-${area.id}'),
      leading: Icon(pending ? Icons.downloading : Icons.map_outlined),
      title: Text(area.name),
      subtitle: Text('${alone == null ? '' : '${formatBytes(alone)} allein · '}'
          '${pending ? '' : '${area.tiles} Kacheln · Stand ${buildLabel(area.build)}'}'
          '${area.poiFiles.isEmpty || pending ? '' : ' · mit Orten'}'
          '${area.hasHeights && !pending ? ' · mit Höhen' : ''}'
          '${area.hasWays && !pending ? ' · mit Wegen' : ''}'
          '${offer == null ? '' : '\n$offer'}'),
      isThreeLine: offer != null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (pending)
          IconButton(
            key: ValueKey('area-resume-${area.id}'),
            tooltip: 'Fortsetzen',
            icon: const Icon(Icons.download),
            onPressed: busy ? null : () => _update(context, ref, refresh: false),
          )
        else if (offer != null)
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

/// Das Alter der Kacheln einer Region (#229 Schritt 4, Konzept 8.2): wie
/// viele die Formen decken und wie viele davon älter sind als der Stand
/// des Hosts — gezählt aus dem Index, ohne Netz. „Aktualisieren" misst
/// erst (Größe aus dem Verzeichnis des neuen Baus), fragt dann und holt
/// nur die veralteten. Nie von selbst: Wer tippt, entscheidet (§7), und
/// über Mobilfunk sagt der Dialog es dazu.
class _RegionTile extends ConsumerWidget {
  const _RegionTile(this.region);

  final MapRegion region;

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(areaDownloadProvider.notifier);
    final RegionRefreshPlan plan;
    try {
      plan = await notifier.planRegionRefresh(region);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Der Kartenhost ist gerade nicht erreichbar.')));
      return;
    }
    if (!context.mounted) return;
    if (plan.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Alles liegt schon auf dem neuen Stand.')));
      return;
    }
    final mobile = ref.read(onMobileDataProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Karte ${region.name} aktualisieren?'),
        content: Text('${plan.staleTiles} Kacheln werden ersetzt — ${formatBytes(plan.fetchBytes)} aus dem Netz'
            '${plan.poiNames.isEmpty ? '' : ', dazu die Orte'}. Die Bereiche bleiben, wie sie sind; nur '
            'ältere Kacheln kommen neu.'
            '${mobile ? '\n\nDu bist über Mobilfunk verbunden — das geht vom Datenvolumen ab.' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Aktualisieren')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final done = await notifier.startRegionRefresh(region, plan);
    if (!done) {
      final error = ref.read(areaDownloadProvider).error;
      if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final age = ref.watch(regionTileAgeProvider(region)).valueOrNull;
    if (age == null || age.tiles == 0) return const SizedBox.shrink();
    final busy = ref.watch(areaDownloadProvider.select((s) => s.busy));
    final build = age.build;
    final String state;
    if (age.stale > 0) {
      state = '${age.stale} davon älter als der Stand ${build == null ? 'des Kartenhosts' : 'vom ${buildLabel(build)}'}'
          ' — „Aktualisieren" holt nur sie';
    } else {
      state = build == null ? 'Stand des Kartenhosts gerade unbekannt' : 'Alle auf dem Stand vom ${buildLabel(build)}';
    }
    return ListTile(
      key: ValueKey('region-${region.id}'),
      leading: const Icon(Icons.layers_outlined),
      title: Text('Karte ${region.name}'),
      subtitle: Text('${age.tiles} Kacheln auf dem Gerät\n$state'),
      isThreeLine: true,
      trailing: age.stale > 0
          ? IconButton(
              key: ValueKey('region-refresh-${region.id}'),
              tooltip: 'Veraltete Kacheln aktualisieren',
              icon: const Icon(Icons.update),
              onPressed: busy ? null : () => _refresh(context, ref),
            )
          : null,
    );
  }
}

/// Die Übersicht einer Region (#220 Schritt 4): Größe und Stand, Löschen —
/// oder, wenn sie fehlt oder ein neuerer Bau da ist, Holen.
class _OverviewTile extends ConsumerWidget {
  const _OverviewTile(
      {required this.regionId, required this.name, this.region, required this.stored, required this.available});

  final String regionId;
  final String name;

  /// Die Region aus dem Index — null, wenn er sie gerade nicht nennt
  /// (dann gibt es nur Löschen).
  final MapRegion? region;
  final StoredOverview? stored;

  /// Die Übersicht auf dem Host — null ohne Empfang oder wenn es keine gibt.
  final OverviewManifest? available;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final o = stored!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Übersicht $name löschen?'),
        content: Text('${formatBytes(o.bytes)} werden vom Gerät gelöscht. Die Bereiche bleiben; '
            'ohne Empfang liegt um sie herum dann keine Karte mehr.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(storedAreasProvider.notifier).deleteOverview(o.region);
  }

  Future<void> _fetch(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(areaDownloadProvider.notifier).fetchOverview(region!);
    if (!ok) {
      final error = ref.read(areaDownloadProvider).error;
      if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(areaDownloadProvider.select((s) => s.busy));
    final o = stored;
    final a = available;
    final wanted = region != null && overviewWanted([?o], regionId, a);
    final String subtitle;
    if (o != null) {
      subtitle = '${formatBytes(o.bytes)} · Zoom 0–${o.maxZoom} · Stand ${buildLabel(o.build)}'
          '${wanted ? '\nNeuerer Stand verfügbar' : ''}';
    } else if (a != null) {
      subtitle = 'Nicht auf dem Gerät (${formatBytes(a.bytes)}) — ohne Empfang liegt '
          'um die Bereiche sonst keine Karte.';
    } else {
      subtitle = 'Nicht auf dem Gerät — kommt mit dem nächsten Bereich dort, sobald Empfang da ist.';
    }
    return ListTile(
      key: ValueKey('overview-$regionId'),
      leading: const Icon(Icons.public),
      title: Text('Übersicht $name'),
      subtitle: Text(subtitle),
      isThreeLine: o != null && wanted,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (wanted)
          IconButton(
            key: ValueKey('overview-fetch-$regionId'),
            tooltip: o == null ? 'Übersicht laden' : 'Auf den neuen Stand bringen',
            icon: Icon(o == null ? Icons.download : Icons.update),
            onPressed: busy ? null : () => _fetch(context, ref),
          ),
        if (o != null)
          IconButton(
            key: ValueKey('overview-delete-$regionId'),
            tooltip: 'Übersicht löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: busy ? null : () => _delete(context, ref),
          ),
      ]),
    );
  }
}
