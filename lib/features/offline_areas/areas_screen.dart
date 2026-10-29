// „Meine Bereiche" (Konzept 3.2): was auf dem Gerät liegt — Name, Größe,
// Kartenstand, auf der Karte zeigen, aktualisieren, löschen. Bereiche
// werden nie verdrängt; was bleibt, muss man sehen und loswerden können.
// Seit 0.106.0 (#229) teilen Bereiche ihre Kacheln: Die Zeile nennt, was
// ein Bereich ALLEIN belegt — das, was sein Löschen frei gibt —, und ein
// abgebrochener Download steht als „unvollständig" mit „Fortsetzen" da.
// Seit 0.108.0 (#229 Schritt 5) auf dem Telefon „Ganze Region speichern":
// ein Bereich wie jeder andere, nur mit der Form „alle Kacheln der Region".
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
import '../../l10n/l10n.dart';
import '../map/map_regions.dart';
import '../map/online_map.dart';
import '../routing/routing_bake.dart';
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
    final bake = ref.watch(routingBakeProvider);
    // Je Bereich gegen die Manifeste SEINER Region (#220). Eine Region,
    // die der Index gerade nicht nennt, bietet nichts an.
    final regions = ref.watch(mapRegionsProvider).valueOrNull ?? const [kDachRegion];
    final overviews = ref.watch(storedOverviewsProvider).valueOrNull ?? const <StoredOverview>[];
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.areasTitle)),
      body: areasAsync.when(
        loading: () => const CenteredTrailLoader(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.areasLoadError),
        ),
        data: (areas) {
          // Die ganze Region, wo sie noch nicht liegt (nur auf dem Telefon).
          final wholeOffers = ref.watch(wholeRegionSupportedProvider)
              ? [
                  for (final r in regions)
                    if (!areas.any((a) => a.region == r.id && a.shape is RegionShape)) _WholeRegionTile(r),
                ]
              : const <Widget>[];
          if (areas.isEmpty && overviews.isEmpty) {
            if (wholeOffers.isNotEmpty) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(l.areasEmptyWithWhole),
                ),
                ...wholeOffers,
              ]);
            }
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.areasEmpty),
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
                child: Text(l.areasIntro(formatBytes(total))),
              ),
              if (download.phase == AreaDownloadPhase.running)
                ListTile(
                  leading: const SizedBox(
                      width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  title: Text(download.refreshing
                      ? l.areasRefreshing(download.name ?? '')
                      : l.areasSaving(download.name ?? '')),
                  subtitle: download.waiting
                      ? Text(l.areasWaiting)
                      : LinearProgressIndicator(value: download.progress?.fraction),
                  trailing: IconButton(
                    key: const ValueKey('area-download-cancel'),
                    tooltip: l.commonCancel,
                    icon: const Icon(Icons.close),
                    onPressed: () => ref.read(areaDownloadProvider.notifier).cancel(),
                  ),
                ),
              // Die Stücke des Planers backen nach dem Speichern (#380 Weg C)
              // — eine Zeile, solange es läuft; ohne Knopf zum Starten.
              if (bake.running)
                ListTile(
                  key: const ValueKey('area-bake'),
                  leading: const SizedBox(
                      width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  title: Text(l.areasBaking(bake.name ?? '')),
                  subtitle: LinearProgressIndicator(value: bake.fraction),
                  trailing: IconButton(
                    key: const ValueKey('area-bake-cancel'),
                    tooltip: l.commonCancel,
                    icon: const Icon(Icons.close),
                    onPressed: () => ref.read(routingBakeProvider.notifier).cancel(),
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
              ...wholeOffers,
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
  String? _offer(AppLocalizations l) => heightsMissing && waysMissing
          ? l.areasOfferHeightsAndWays
          : heightsMissing
              ? l.areasOfferHeights
              : waysMissing
                  ? l.areasOfferWays
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
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.areasDeleteTitle(area.name)),
        content: Text(overview == null
            ? l.areasDeleteText(formatBytes(alone))
            : l.areasDeleteTextLast(formatBytes(alone + overview.bytes))),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.commonCancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.commonDelete)),
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
    final l = context.l10n;
    final notifier = ref.read(areaDownloadProvider.notifier);
    try {
      final plan = await notifier.plan(area.shape, refresh: refresh);
      await notifier.start(plan, name: area.name, id: area.id, refresh: refresh);
    } on AreaTooLarge {
      messenger.showSnackBar(SnackBar(content: Text(l.areasTooLargeForUpdate)));
    } on OutsideRegions catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message(l))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.areasHostUnreachable)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(areaDownloadProvider.select((s) => s.busy));
    final pending = !area.complete;
    final l = context.l10n;
    final offer = pending ? l.areasIncomplete : _offer(l);
    final alone = ref.watch(areaExclusiveBytesProvider(area.id)).valueOrNull;
    final facts = [
      if (alone != null) l.areasAlone(formatBytes(alone)),
      if (!pending) ...[
        l.areasTilesAndBuild(area.tiles, buildLabel(area.build)),
        if (area.poiFiles.isNotEmpty) l.areasWithPlaces,
        if (area.hasHeights) l.areasWithHeights,
        if (area.hasWays) l.areasWithWays,
      ],
    ];
    return ListTile(
      key: ValueKey('area-${area.id}'),
      leading: Icon(pending ? Icons.downloading : Icons.map_outlined),
      title: Text(area.name),
      subtitle: Text('${facts.join(' · ')}${offer == null ? '' : '\n$offer'}'),
      isThreeLine: offer != null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (pending)
          IconButton(
            key: ValueKey('area-resume-${area.id}'),
            tooltip: l.areasResume,
            icon: const Icon(Icons.download),
            onPressed: busy ? null : () => _update(context, ref, refresh: false),
          )
        else if (offer != null)
          IconButton(
            key: ValueKey('area-update-${area.id}'),
            tooltip: l.areasUpdate,
            icon: const Icon(Icons.update),
            onPressed: busy ? null : () => _update(context, ref),
          ),
        IconButton(
          key: ValueKey('area-delete-${area.id}'),
          tooltip: l.areasDeleteArea,
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

/// „Ganze Region speichern" (#229 Schritt 5, Konzept 8.2): ein Bereich mit
/// der Form `RegionShape` — alle Kacheln der Region bis zum Zoom des Hosts,
/// mit Orten (als Bündel), Höhen und Wegen. Vorher die gemessene Größe,
/// über Mobilfunk mit Warnung; geladen wird nur, was nicht schon liegt.
/// Nur auf dem Telefon (Betreiber, 2026-10-09).
class _WholeRegionTile extends ConsumerStatefulWidget {
  const _WholeRegionTile(this.region);

  final MapRegion region;

  @override
  ConsumerState<_WholeRegionTile> createState() => _WholeRegionTileState();
}

class _WholeRegionTileState extends ConsumerState<_WholeRegionTile> {
  /// Das Messen liest das ganze Verzeichnis des Hosts — das dauert.
  bool _measuring = false;

  MapRegion get region => widget.region;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final notifier = ref.read(areaDownloadProvider.notifier);
    final box = region.box;
    final shape = RegionShape(region: region.id, bounds: AreaBounds(south: box.s, west: box.w, north: box.n, east: box.e));
    final AreaPlan plan;
    setState(() => _measuring = true);
    try {
      plan = await notifier.plan(shape);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.areasHostUnreachable)));
      return;
    } finally {
      if (mounted) setState(() => _measuring = false);
    }
    if (!mounted) return;
    final mobile = ref.read(onMobileDataProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.areasWholeConfirmTitle(region.name)),
        content: Text('${l.areasLoads(formatBytes(plan.totalBytes), plan.tiles.length)}'
            '${plan.map.stored > 0 ? ' ${l.areasAlreadyStored(plan.map.stored)}' : ''}'
            '${plan.poiBundle != null || plan.poiNames.isNotEmpty ? ' · ${l.areasWithPlaces}' : ''}'
            '${plan.hasHeights ? ' · ${l.areasWithHeights}' : ''}'
            '${plan.hasWays ? ' · ${l.areasWithWays}' : ''}.\n\n'
            '${l.areasWholeConfirmNote}'
            '${mobile ? '\n\n${l.areasMobileData}' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.commonCancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.commonSave)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final area = await notifier.start(plan, name: l.areasWholeName(region.name));
    if (area == null) {
      final error = ref.read(areaDownloadProvider).error;
      if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(areaDownloadProvider.select((s) => s.busy));
    final map = ref.watch(regionMapManifestProvider(region)).valueOrNull;
    final heights = ref.watch(regionHeightsManifestProvider(region)).valueOrNull;
    final ways = ref.watch(areaWaysAvailableProvider(region)).valueOrNull;
    final size = map == null ? null : map.bytes + (heights?.bytes ?? 0) + (ways?.bytes ?? 0);
    final l = context.l10n;
    return ListTile(
      key: ValueKey('whole-${region.id}'),
      leading: const Icon(Icons.download_for_offline_outlined),
      title: Text(l.areasWholeTitle(region.name)),
      subtitle: _measuring
          ? const LinearProgressIndicator()
          : Text(size == null ? l.areasWholeSubtitle : l.areasWholeSubtitleSize(formatBytes(size))),
      trailing: IconButton(
        key: ValueKey('whole-save-${region.id}'),
        tooltip: l.areasWholeTooltip,
        icon: const Icon(Icons.download),
        onPressed: busy || _measuring || map == null ? null : _save,
      ),
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
    final l = context.l10n;
    final notifier = ref.read(areaDownloadProvider.notifier);
    final RegionRefreshPlan plan;
    try {
      plan = await notifier.planRegionRefresh(region);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.areasHostUnreachable)));
      return;
    }
    if (!context.mounted) return;
    if (plan.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.areasAllUpToDate)));
      // Nichts zu holen, aber vielleicht zu backen (#410): fehlende oder
      // alte Stücke des Planers; was frisch liegt, bleibt still.
      final areas = await ref.read(storedAreasProvider.future);
      ref.read(routingBakeProvider.notifier).bakeAreas([for (final a in areas) if (a.region == region.id) a]);
      return;
    }
    final mobile = ref.read(onMobileDataProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.areasRegionRefreshTitle(region.name)),
        content: Text('${plan.poiNames.isEmpty ? l.areasRegionRefreshText(plan.staleTiles, formatBytes(plan.fetchBytes)) : l.areasRegionRefreshTextPlaces(plan.staleTiles, formatBytes(plan.fetchBytes))}'
            '${mobile ? '\n\n${l.areasMobileData}' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.commonCancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.areasRefreshAction)),
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
    final l = context.l10n;
    final String state;
    if (age.stale > 0) {
      state = build == null ? l.areasRegionStaleHost(age.stale) : l.areasRegionStale(age.stale, buildLabel(build));
    } else {
      state = build == null ? l.areasRegionBuildUnknown : l.areasRegionAllCurrent(buildLabel(build));
    }
    return ListTile(
      key: ValueKey('region-${region.id}'),
      leading: const Icon(Icons.layers_outlined),
      title: Text(l.areasRegionTitle(region.name)),
      subtitle: Text('${l.areasRegionTiles(age.tiles)}\n$state'),
      isThreeLine: true,
      trailing: age.stale > 0
          ? IconButton(
              key: ValueKey('region-refresh-${region.id}'),
              tooltip: l.areasRegionRefreshTooltip,
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
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.areasOverviewDeleteTitle(name)),
        content: Text(l.areasOverviewDeleteText(formatBytes(o.bytes))),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.commonCancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.commonDelete)),
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
    final l = context.l10n;
    final String subtitle;
    if (o != null) {
      subtitle = '${l.areasOverviewStored(formatBytes(o.bytes), o.maxZoom, buildLabel(o.build))}'
          '${wanted ? '\n${l.areasOverviewNewer}' : ''}';
    } else if (a != null) {
      subtitle = l.areasOverviewMissing(formatBytes(a.bytes));
    } else {
      subtitle = l.areasOverviewMissingLater;
    }
    return ListTile(
      key: ValueKey('overview-$regionId'),
      leading: const Icon(Icons.public),
      title: Text(l.areasOverviewTitle(name)),
      subtitle: Text(subtitle),
      isThreeLine: o != null && wanted,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (wanted)
          IconButton(
            key: ValueKey('overview-fetch-$regionId'),
            tooltip: o == null ? l.areasOverviewFetch : l.areasUpdate,
            icon: Icon(o == null ? Icons.download : Icons.update),
            onPressed: busy ? null : () => _fetch(context, ref),
          ),
        if (o != null)
          IconButton(
            key: ValueKey('overview-delete-$regionId'),
            tooltip: l.areasOverviewDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: busy ? null : () => _delete(context, ref),
          ),
      ]),
    );
  }
}
