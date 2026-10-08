import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/geo.dart';
import '../map/map_view/map_view.dart';
import '../trails/trail_sheet.dart' show formatElevation;
import 'official_trails.dart';
import 'official_trails_source.dart';

/// Die offiziellen Trails als gestrichelte Linien — seit der
/// Kartenfassade (#31) keine Ebene INNERHALB der Engine mehr, sondern
/// zwei pure Schritte für den Karten-Screen: [officialViewFor] sagt, ob
/// und für welchen Ausschnitt nachzuladen ist, [officialPolylines] baut
/// die Linien der Fassade. Sie liegen über den Orten und unter den
/// Trails des Netzes (Reihenfolge im Screen).

/// Der Ausschnitt, für den der Controller nachladen soll — oder null:
/// Ebene aus, unter [kOfficialMinZoom], oder alles Berührte schon da.
/// Nur fragen, wenn der Ausschnitt eine noch fehlende Region berührt
/// (oder der Index fehlt) — sonst wäre jedes Verschieben ein Aufruf.
({double s, double w, double n, double e})? officialViewFor(
  MapViewCamera? camera,
  OfficialTrailsState state, {
  required bool enabled,
}) {
  if (camera == null || !enabled || camera.zoom < kOfficialMinZoom) return null;
  final b = camera.bounds;
  final view = (s: b.south, w: b.west, n: b.north, e: b.east);
  final index = state.index;
  final missing = index == null ||
      index.regions.any((r) =>
          !state.byRegion.containsKey(r.id) && r.touches(view.s, view.w, view.n, view.e));
  return missing ? view : null;
}

/// Die Linien: violett gestrichelt, gesperrte Teile grau, Varianten
/// dünner; ein Tipp meldet den [OfficialTrail].
List<MapViewPolyline> officialPolylines(OfficialTrailsState state) => [
      for (final t in state.trails)
        for (final s in t.sections)
          MapViewPolyline(
            points: s.points,
            color: s.closed ? Colors.grey.shade600 : AppColors.mapLines.official,
            width: s.variant ? 2.5 : 3.5,
            dash: const [10, 6],
            borderColor: AppColors.mapLines.halo,
            borderWidth: AppColors.mapLines.haloBorderWidth,
            hitValue: t,
          ),
    ];

/// Die Aussage über den Status — immer mit der Quelle, denn sie kommt von
/// dort und nicht von einem Buddy; eine Sperre mit dem Stand der Quelle
/// (#41: „gesperrt laut Quelle, Stand Datum", nie ein Urteil der App).
String officialStatusLine(OfficialStatus status, String by, {String? updated}) {
  final at = updated == null ? '' : ', Stand ${formatIsoDateDe(updated)}';
  return switch (status) {
    OfficialStatus.open => 'Freigegeben laut $by.',
    OfficialStatus.partlyClosed =>
      'Teilweise gesperrt laut $by$at — die gesperrten Teile sind grau.',
    OfficialStatus.closed => 'Gesperrt laut $by$at.',
  };
}

/// Das Blatt eines offiziellen Trails: was die Quelle sagt, und von wem.
/// Keine Beiträge, keine Hinweise, kein Status eines Buddys — dafür gibt
/// es die Trails des Netzes (Konzept offizielle Trails 5.3).
Future<void> showOfficialTrailSheet(BuildContext context, OfficialTrail trail) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _OfficialTrailSheet(trail),
    );

class _OfficialTrailSheet extends ConsumerWidget {
  const _OfficialTrailSheet(this.trail);

  final OfficialTrail trail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(officialTrailsControllerProvider).sourceOf(trail);
    final by = source?.attribution ?? 'Quelle';
    final text = Theme.of(context).textTheme;
    final facts = [
      if (trail.lengthM != null) formatMeters(trail.lengthM!),
      if (trail.downM != null && trail.upM != null)
        formatElevation((gain: trail.upM!, loss: trail.downM!)),
    ];
    final url = source?.url;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trail.name, style: text.titleLarge),
              const SizedBox(height: 4),
              Text('Offizieller Singletrail', style: text.bodyMedium),
              if (facts.isNotEmpty) Text(facts.join(' · '), style: text.bodyMedium),
              if (trail.difficulty != null)
                Text('Schwierigkeit laut Quelle: ${trail.difficulty}',
                    style: text.bodyMedium),
              const SizedBox(height: 8),
              Row(children: [
                Icon(
                  trail.status == OfficialStatus.open
                      ? Icons.verified_outlined
                      : Icons.block,
                  size: 18,
                  color: trail.status == OfficialStatus.open
                      ? AppPalette.of(context).map.official
                      : Colors.grey.shade700,
                ),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(officialStatusLine(trail.status, by, updated: trail.updated),
                        style: text.bodyMedium)),
              ]),
              if (trail.description != null) ...[
                const SizedBox(height: 8),
                Text(trail.description!, style: text.bodyMedium),
              ],
              const SizedBox(height: 12),
              // Konzept 6.3: Die Ebene sagt nur etwas über ihre eigenen
              // Linien, nie über die übrigen Trails.
              Text(
                'Ausgewiesen laut Quelle. Über andere Trails sagt diese '
                'Ebene nichts.',
                style: text.bodySmall,
              ),
              if (source != null)
                Text(
                  'Quelle: ${source.name} · ${source.license}'
                  '${trail.updated == null ? '' : ' · Stand ${formatIsoDateDe(trail.updated!)}'}',
                  style: text.bodySmall,
                ),
              if (url != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Bei der Quelle ansehen'),
                    onPressed: () => launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
