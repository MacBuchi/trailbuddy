import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../official/official_signposts.dart';
import '../../core/errors.dart';
import '../../core/geo.dart' show formatMeters;
import '../../core/gpx_share.dart';
import '../../core/read_after_write.dart';
import '../../core/router_branches.dart';
import '../../models/trail.dart';
import '../coach/coach.dart';
import '../help/map_tour.dart' show SheetCoach;
import '../routing/trail_head_providers.dart';
import 'gpx_writer.dart';
import 'grade_shield.dart';
import 'elevation_profile_chart.dart';
import 'outbox_providers.dart';
import 'pending_value.dart';
import 'singletrail_scale.dart';
import 'trail_elevation.dart';
import 'terrain_heights.dart';
import 'trail_export.dart';
import 'trail_geometry.dart';
import 'trail_details_dialog.dart';
import 'trail_link.dart';
import 'trail_navigation.dart';
import 'trail_notes.dart';
import 'rating_stars.dart';
import 'trail_condition.dart';
import 'trail_providers.dart';
import 'trail_report.dart';
import 'trail_takeover.dart';
import 'trail_traits.dart';

/// Das Blatt zu einem Trail: Name (und die anderen Namen), Länge, S-Grad,
/// Bewertung und Zustand, die Meldung mit Alter, wer ihn belegt hat,
/// Hinweise und Meldungen der Buddys und der eigene Beitrag.
Future<void> showTrailSheet(BuildContext context, Trail trail,
    {bool showOnMapButton = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Ohne läuft ein langes Blatt bis unter die Statusleiste, und der
    // Griff liegt dort, wo kein Daumen hinkommt (#215).
    useSafeArea: true,
    showDragHandle: true,
    // Ziehbar auf dem GANZEN Inhalt (#215): Eine Scrollfläche im Blatt
    // nimmt sonst jede senkrechte Geste, und nur der Griff schließt. Ganz
    // oben gescrollt schiebt Ziehen nach unten das Blatt hinaus; an der
    // Untergrenze schließt es (`shouldCloseOnMinExtent`).
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: kTrailSheetInitialSize,
      minChildSize: kTrailSheetMinSize,
      maxChildSize: 1,
      builder: (_, controller) =>
          _TrailSheet(trailId: trail.id, showOnMapButton: showOnMapButton, controller: controller),
    ),
  );
}

/// Anteil der Höhe, mit dem das Blatt aufgeht — der Kopf, die Kennzahlen
/// und das Höhenprofil; der Rest liegt einen Wisch darunter.
const kTrailSheetInitialSize = 0.75;

/// Darunter schließt das Blatt, wenn man es nach unten zieht.
const kTrailSheetMinSize = 0.3;

/// „gemeldet vor 3 Tagen" — das Alter einer Meldung im Blatt.
String statusAge(DateTime at, {DateTime? now}) {
  final age = reportAgeLabel(at, now: now);
  return age == 'heute' || age == 'gestern' ? '$age gemeldet' : 'gemeldet $age';
}

/// „3,4 km" bzw. „850 m" — [formatMeters], die EINE Schreibweise der App
/// (bis 0.37.0 stand hier eine zweite mit Punkt: „3.4 km").
String formatLength(double m) => formatMeters(m);

/// „↓ 420 Hm · ↑ 35 Hm" — bergab zuerst, weil ein Trail bergab gefahren
/// wird. Dieselbe Zeile im Import-Blatt und im Trail-Blatt.
String formatElevation(({double gain, double loss}) el) =>
    '↓ ${el.loss.round()} Hm · ↑ ${el.gain.round()} Hm';

/// „Ø 14 % Gefälle" bzw. „Ø 3 % Steigung"; unter einem halben Prozent
/// „Ø eben" statt einer Null mit Vorzeichen.
String formatMeanGrade(double descentPct) {
  final v = descentPct.abs().round();
  if (v == 0) return 'Ø eben';
  return descentPct > 0 ? 'Ø $v % Gefälle' : 'Ø $v % Steigung';
}

class _TrailSheet extends ConsumerStatefulWidget {
  const _TrailSheet({required this.trailId, required this.showOnMapButton, required this.controller});
  final String trailId;
  final bool showOnMapButton;
  final ScrollController controller;

  @override
  ConsumerState<_TrailSheet> createState() => _TrailSheetState();
}

class _TrailSheetState extends ConsumerState<_TrailSheet> {
  /// Was vor dem Öffnen schon gesehen war — damit das Neue im Blatt
  /// getönt bleibt, obwohl es beim Öffnen als gesehen gemerkt wird.
  late final Set<String> _seenBefore = ref.read(seenNotesProvider);

  /// Wer das Blatt sieht, hat die Hinweise gesehen (#7): Karte und Liste
  /// heben den Trail danach nicht mehr hervor.
  void _markSeen(Trail trail) {
    final seen = ref.read(seenNotesProvider);
    if (trail.notes.every((n) => seen.contains(n.id))) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final known = {
        for (final t in ref.read(trailsProvider).valueOrNull ?? const <Trail>[])
          for (final n in t.notes) n.id,
      };
      ref
          .read(seenNotesProvider.notifier)
          .markSeen(trail.notes.map((n) => n.id), known: known);
    });
  }

  @override
  Widget build(BuildContext context) {
    final trail = ref.watch(trailByIdProvider(widget.trailId));
    if (trail == null) {
      return ListView(
        controller: widget.controller,
        padding: const EdgeInsets.all(24),
        children: const [Text('Dieser Trail ist nicht mehr sichtbar.')],
      );
    }
    _markSeen(trail);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final shownStatus = trail.shownStatus;
    final mine = trail.myDetails;
    final buddies = trail.buddyIds.length;
    // Ohne aufgezeichnete Höhen das Profil aus dem Geländemodell (#186) —
    // beobachtet nur dann, denn beobachten heißt laden.
    final terrain = trail.elevation == null ? ref.watch(terrainProfileProvider(trail.id)) : null;
    final elevation = trail.elevation ?? terrain?.valueOrNull;
    final contributors = trail.contributionsOrdered
        .where((d) => d.userId != trail.myId)
        .map((d) => d.username ?? 'Buddy')
        .toList();

    // Scrollbar, seit das Höhenprofil drinsteht: Auf einem kleinen oder
    // quer gehaltenen Telefon liefe das Blatt sonst unten über.
    return SafeArea(
      child: SingleChildScrollView(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Der Kopf (Design 1i/4f): Name in Versalien, darunter, wer ihn
            // kennt — die Beziehung, die in der Liste der Streifen sagt.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(trail.displayName.toUpperCase(),
                      key: const ValueKey('trail-sheet-title'),
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                // Das Schild neben dem Namen (Design 4f) — der Median, wie
                // in der Kachel darunter.
                if (trail.grade != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: GradeShield(trail.grade!,
                        key: const ValueKey('grade-shield'), fontSize: 14, uphill: isUphill(trail)),
                  ),
                // Anfahrt (#224) und Schließen (#215) im Kopf: Die Navi-App
                // braucht man am Parkplatz, ohne erst ans Ende zu scrollen,
                // und ein X schließt, wo Wischen und Zurück nicht gefunden
                // werden.
                CoachAnchor(
                  id: SheetCoach.navigate,
                  child: IconButton(
                    key: const ValueKey('trail-navigate'),
                    tooltip: 'Anfahrt',
                    onPressed: () => navigateToTrailHead(context, trail),
                    icon: const Icon(Icons.directions_outlined),
                  ),
                ),
                IconButton(
                  key: const ValueKey('trail-sheet-close'),
                  tooltip: 'Schließen',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (trail.otherNames.isNotEmpty)
              Text('auch: ${trail.otherNames.join(', ')}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted)),
            Text(
              trail.isOwn
                  ? (buddies == 0
                      ? 'Nur du hast diesen Trail belegt.'
                      : 'Du und $buddies ${buddies == 1 ? 'Buddy' : 'Buddys'} '
                          '(${contributors.join(', ')}).')
                  : 'Belegt von ${contributors.isEmpty ? '$buddies Buddys' : contributors.join(', ')} '
                      '— du bist ihn noch nicht gefahren.',
              style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted),
            ),
            // Nur geplant (#100, Konzept 4.6): Eine Datei ohne Fahrzeiten
            // ist eine Behauptung, keine Fahrt — Buddys sollen das sehen.
            if (plannedNotice(trail) case final planned?)
              Text(planned,
                  key: const ValueKey('trail-planned'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted)),
            // Wartet im Ausgangskorb (#30): Der Trail ist noch nicht auf
            // dem Server — kein Beitrag, kein Hinweis, keine Einschätzung,
            // dafür fehlt die Kennung. Das Blatt sagt es, statt Knöpfe zu
            // zeigen, die scheitern.
            if (trail.pending) _PendingNotice(trail),
            if (trail.pendingDetails)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    trail.sendingDetails
                        ? 'Dein Beitrag wird übertragen …'
                        : 'Dein Beitrag wartet auf Übertragung.',
                    key: const ValueKey('pending-details'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            // Offizielle Trails, die dieser deckt (#13) — auf dem Gerät
            // gerechnet, aus der Linie, die die Karte zeichnet.
            OfficialSignposts(line: trail.points),
            // Charakter (#72) und Meldung als Chips — die Kennzahlen stehen
            // darunter in Kacheln. Die Meldung (#101): die bestätigte, wenn
            // sie warnt, und verblasst eine jüngere unbestätigte — „zu
            // bestätigen", bis jemand vor Ort ist.
            if (trail.topTraits.isNotEmpty ||
                trail.status.warns ||
                shownStatus.unconfirmed != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (shownStatus.confirmed case final c? when c.status!.warns)
                    Chip(
                      key: const ValueKey('status-chip'),
                      avatar: const Icon(Icons.warning_amber, size: 18),
                      backgroundColor: palette.map.warning.withValues(alpha: 0.25),
                      label: Text('${c.status!.label} · ${statusAge(c.reportedAt)}'),
                    ),
                  if (shownStatus.unconfirmed case final u?)
                    Opacity(
                      opacity: 0.6,
                      child: Chip(
                        key: const ValueKey('status-chip-unconfirmed'),
                        avatar: Icon(u.status!.warns ? Icons.warning_amber : Icons.help_outline, size: 18),
                        label: Text('${u.status!.label}? · zu bestätigen'),
                      ),
                    ),
                  // Die höchstens zwei häufigsten, mit der Zahl der Beiträge,
                  // die sie nennen.
                  for (final t in trail.topTraits)
                    Tooltip(
                      message: t.description,
                      child: Chip(
                        key: ValueKey('trait-chip-${t.db}'),
                        avatar: Icon(t.icon, size: 18),
                        label: Text('${t.label} · ${trail.traitCounts[t]}'),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // Die Anker der Touren (#132): Kacheln, Einschätzung, Beitrag,
            // Hinweis und Karte — die Karten-Tour und die Trails-Tour
            // zeigen auf dieselben.
            CoachAnchor(id: SheetCoach.metrics, child: _MetricTiles(trail: trail, elevation: elevation)),
            const SizedBox(height: 8),
            _OpinionTiles(trail: trail),
            const SizedBox(height: 8),
            if (elevation != null)
              _Panel(
                label: 'HÖHENPROFIL',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ElevationProfileChart(elevation),
                    const SizedBox(height: 4),
                    Text(_profileCaption(elevation),
                        key: const ValueKey('profile-caption'),
                        style: theme.textTheme.bodySmall?.copyWith(color: palette.muted)),
                    // Geländehöhen sind eine Anzeige, kein Beitrag: Wer die
                    // Datei mit Höhen hat, trägt die echten nach.
                    if (elevation.fromTerrain && trail.isOwn)
                      Text('Hat deine GPX-Datei Höhen, importiere sie noch einmal — sie werden nachgetragen.',
                          style: theme.textTheme.bodySmall?.copyWith(color: palette.muted)),
                  ],
                ),
              )
            else if (terrain?.isLoading ?? false)
              Text('Höhen werden aus dem Geländemodell gelesen …',
                  key: const ValueKey('terrain-loading'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              Text(
                  trail.isOwn
                      ? 'Keine Höhenangaben. Hat deine GPX-Datei welche, '
                          'importiere sie noch einmal — sie werden nachgetragen.'
                      : 'Keine Höhenangaben.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (mine?.description != null && mine!.description!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(mine.description!),
              ),
            // Link zur Quelle (#103): nur der Host, geöffnet im Browser —
            // die App selbst ruft ihn nie ab.
            if (trail.displayLink case final link?)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('trail-link'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(linkHost(link)),
                ),
              ),
            // Als GPX hinaus (#150): die angezeigte Linie in Trail-Richtung,
            // Name und eigener Link — für jeden sichtbaren Trail, auch
            // die der Buddys; nicht für wartende (ohne Server-Kennung ist
            // noch nichts fertig).
            if (!trail.pending)
              Align(
                alignment: Alignment.centerLeft,
                child: CoachAnchor(
                  id: SheetCoach.export,
                  child: TextButton.icon(
                    key: const ValueKey('trail-export'),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () async {
                      final track = await trailExportTrack(ref.read(terrainHeightsProvider), trail);
                      if (!context.mounted) return;
                      await shareGpx(context, ref,
                          fileName: gpxFileName(track.name),
                          xml: writeGpx(
                              name: track.name,
                              points: track.points,
                              link: track.link,
                              terrainHeights: track.terrainHeights));
                    },
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Als GPX exportieren'),
                  ),
                ),
              ),
            if (!trail.pending) ...[
              const SizedBox(height: 12),
              TrailNotesSection(trail: trail, seenBefore: _seenBefore, showAdd: false),
              const SizedBox(height: 8),
              TrailReportsSection(trail: trail),
            ],
            if (trail.isOwn && !trail.pending) ...[
              const SizedBox(height: 12),
              // EIN Anker um Grad UND Sterne: Die Trails-Tour sagt „deinen
              // S-Grad und deine Sterne tippst du hier an" — bis 0.64.0 lagen
              // die Sterne außerhalb der Aussparung.
              CoachAnchor(
                id: SheetCoach.ownGrade,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OwnGradePicker(trail: trail),
                    OwnRatingPicker(trail: trail),
                  ],
                ),
              ),
              // Der ganze Beitrag (Name, Charakter, Bewertung, Sichtbarkeit)
              // — gleich unter der Einschätzung, die ein Teil davon ist.
              Wrap(
                spacing: 8,
                children: [
                  // Mein Beitrag hängt noch am Namen eines Buddys (#102):
                  // übernehmen, vorbelegt aus dem Netz.
                  if (offersTakeOver(trail))
                    FilledButton.tonalIcon(
                      key: const ValueKey('trail-takeover'),
                      onPressed: () => showTrailDetailsDialog(context, ref, trail, takeOver: true),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Übernehmen'),
                    ),
                  CoachAnchor(
                    id: SheetCoach.contribution,
                    child: TextButton.icon(
                      key: const ValueKey('trail-contribution'),
                      onPressed: () => showTrailDetailsDialog(context, ref, trail),
                      icon: const Icon(Icons.edit),
                      label: const Text('Mein Beitrag'),
                    ),
                  ),
                  // Nicht, solange ein Beitrag im Ausgangskorb wartet: Der
                  // legte die gelöschte Zeile beim Nachholen wieder an.
                  if (!trail.pendingDetails)
                    TextButton.icon(
                      key: const ValueKey('trail-withdraw'),
                      onPressed: () => withdrawContribution(context, ref, trail),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Löschen'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // Unten die Wege aus dem Blatt (Design 1i): schreiben (Lime,
            // die Hauptaktion), melden (#101 — jeder, der den Trail sieht)
            // und zur Karte.
            if (!trail.pending)
              Row(
                children: [
                  Expanded(
                    child: CoachAnchor(
                      id: SheetCoach.addNote,
                      child: FilledButton.icon(
                      key: const ValueKey('add-note'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () => addTrailNote(context, ref, trail),
                      icon: const Icon(Icons.add_comment_outlined),
                      label: const Text('Hinweis schreiben'),
                    )),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CoachAnchor(
                      id: SheetCoach.report,
                      child: OutlinedButton.icon(
                      key: const ValueKey('trail-report'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () => reportTrail(context, ref, trail),
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Melden'),
                    )),
                  ),
                ],
              ),
            // „Zum Trailkopf" (#158 Schritt 4) und „Karte" in einer Zeile;
            // die Anfahrt (#151) steht seit #224 als Symbol im Kopf. Den
            // Trailkopf gibt es auch für wartende Trails — Punkte haben
            // sie, der Trailkopf steht fest.
            if (!trail.pending) const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: CoachAnchor(
                    id: SheetCoach.trailHead,
                    child: OutlinedButton.icon(
                    key: const ValueKey('trail-head'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () {
                      // Der Weg wird auf der Karte gezeigt: erst das Blatt zu,
                      // dann der Reiter, dann der Wunsch — die Karte löst ihn
                      // nach dem nächsten Bild ein (wie der Fokus-Wunsch).
                      final request = ref.read(trailHeadRequestProvider.notifier);
                      Navigator.of(context).pop();
                      StatefulNavigationShell.maybeOf(context)?.goBranch(kMapBranchIndex);
                      request.state = (trailId: trail.id, mode: RouteMode.direct);
                    },
                    icon: const Icon(Icons.route_outlined),
                    label: const Text('Zum Trailkopf'),
                  )),
                ),
                if (widget.showOnMapButton) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: CoachAnchor(
                      id: SheetCoach.showOnMap,
                      child: OutlinedButton.icon(
                      key: const ValueKey('trail-show-on-map'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () {
                        // Erst der Reiter, dann der Wunsch (PilzBuddy #345).
                        Navigator.of(context).pop();
                        StatefulNavigationShell.maybeOf(context)
                            ?.goBranch(kMapBranchIndex);
                        ref.read(mapFocusTrailProvider.notifier).state = trail.id;
                      },
                      icon: const Icon(Icons.map),
                      label: const Text('Karte'),
                    )),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Wer den Trail nur GEPLANT hat (Datei ohne Fahrzeiten), in einem Satz;
/// null, wenn jeder Beitragende ihn gefahren ist. Sind alle sichtbaren
/// Belege geplant, sagt es der Satz für den ganzen Trail.
String? plannedNotice(Trail trail) {
  if (trail.pending) return null;
  if (trail.allPlanned) {
    return 'Nur geplant: Jeder Beleg hier kommt aus einer Datei ohne '
        'Fahrzeiten — gefahren hat ihn niemand nachweislich.';
  }
  final who = [
    for (final d in trail.contributionsOrdered)
      if (trail.onlyPlanned(d.userId))
        d.userId == trail.myId ? 'du' : (d.username ?? 'Buddy'),
  ];
  if (who.isEmpty) return null;
  return 'Nur geplant, nicht gefahren: ${who.join(', ')}.';
}

/// Was nach dem Löschen bleibt, in einem Satz. „Bleibt" nur, wenn ich
/// eine fremde Aufzeichnung SEHE; was ein Fremder privat belegt, kenne ich
/// nicht — für mich verschwindet der Trail dann trotzdem.
String withdrawConsequence(Trail trail) =>
    trail.recordings.any((r) => r.userId != trail.myId)
        ? 'Der Trail bleibt für deine Buddys, die ihn auch belegt haben.'
        : 'Der Trail verschwindet von deiner Karte.';

/// „Löschen" im Blatt: eigene Aufzeichnungen, Einschätzung, Charakter,
/// Bewertung, Meldungen und Hinweise zu diesem Trail (Konzept 4, „Löschen
/// und DSGVO").
Future<void> withdrawContribution(BuildContext context, WidgetRef ref, Trail trail) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Meinen Beitrag löschen?'),
      content: Text('Deine Aufzeichnungen, deine Einschätzung, deine '
          'Meldungen und deine Hinweise zu diesem Trail werden gelöscht. '
          '${withdrawConsequence(trail)}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const ValueKey('trail-withdraw-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Löschen'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final fresh = await ref.read(trailsProvider.notifier).withdraw(trail.id);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
        content: Text('Beitrag gelöscht${fresh ? '' : staleAfterWriteHint}')));
  } catch (e, st) {
    logError('Beitrag zurückziehen', e, st);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// „Wartet auf Übertragung" — oder die Ablehnung des Servers mit den
/// beiden Auswegen.
class _PendingNotice extends ConsumerWidget {
  const _PendingNotice(this.trail);
  final Trail trail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final failure = trail.pendingFailure;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failure == null
                ? 'Wartet auf Übertragung — geht raus, sobald wieder Netz da ist.'
                : 'Konnte nicht beigesteuert werden: $failure',
            key: const ValueKey('pending-notice'),
            style: theme.textTheme.bodyMedium?.copyWith(
                color: failure == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error),
          ),
          // Wrap, nicht Row: Auf einem schmalen Telefon passen die beiden
          // Knöpfe nicht nebeneinander.
          Wrap(
            children: [
              if (failure != null)
                TextButton(
                  onPressed: () {
                    ref.read(outboxJobsProvider.notifier).retry(trail.id);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Erneut versuchen'),
                ),
              TextButton(
                onPressed: () {
                  ref.read(outboxJobsProvider.notifier).discard(trail.id);
                  Navigator.of(context).pop();
                },
                child: const Text('Aus dem Ausgangskorb entfernen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _profileCaption(ElevationProfile p) {
  final steepest = p.steepestDescentPct;
  final parts = <String>[
    if (p.fromTerrain) kTerrainLabel,
    'In Trail-Richtung',
    formatMeanGrade(p.meanDescentPct),
  ];
  if (steepest != null && steepest > 0) {
    parts.add('steilstes Stück ${steepest.round()} % auf ${kSteepestWindowM.round()} m');
  }
  return parts.join(' · ');
}

/// „S2 · S1–S3 · 4 Einschätzungen" — Median, Spanne (nur wenn es eine
/// gibt) und wie viele es sind. Eine Einschätzung ist eine Meinung, vier
/// sind ein Bild; die Zahl sagt, welches von beiden man sieht.
String? gradeSummary(Trail trail) {
  final median = trail.grade;
  final range = trail.gradeRange;
  if (median == null || range == null) return null;
  final n = trail.gradeVotes.length;
  return [
    gradeLabel(median),
    if (range.min != range.max) '${gradeLabel(range.min)}–${gradeLabel(range.max)}',
    '$n ${n == 1 ? 'Einschätzung' : 'Einschätzungen'}',
  ].join(' · ');
}

/// Wer hat was gesagt — nur sichtbare Beiträge, also die eigenen und die
/// der Buddys (dieselbe Liste, aus der der Median kommt).
Future<void> showGradeVotesSheet(BuildContext context, Trail trail) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Schwierigkeit', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(gradeSummary(trail) ?? 'Noch keine Einschätzung',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              for (final d in trail.gradeVotes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 18,
                    child: Text(gradeLabel(d.grade!)),
                  ),
                  title: Text(d.userId == trail.myId ? 'Du' : (d.username ?? 'Buddy')),
                  subtitle: Text(singletrailGrade(d.grade!).short),
                ),
              TextButton.icon(
                onPressed: () =>
                    showSingletrailScaleSheet(sheetContext, highlight: trail.grade),
                icon: const Icon(Icons.help_outline),
                label: const Text('Was bedeuten S0 bis S5?'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Die eigene Einschätzung direkt im Blatt: ein Tipp auf S0–S5 speichert,
/// ein zweiter Tipp auf dieselbe Stufe nimmt sie zurück. Nur für Trails,
/// die man selbst belegt hat — ohne Beleg kein Beitrag (Konzept 3).
class OwnGradePicker extends ConsumerStatefulWidget {
  const OwnGradePicker({super.key, required this.trail});
  final Trail trail;

  @override
  ConsumerState<OwnGradePicker> createState() => _OwnGradePickerState();
}

class _OwnGradePickerState extends ConsumerState<OwnGradePicker> {
  bool _saving = false;

  Future<void> _set(int? grade) async {
    final trail = widget.trail;
    final current = trail.myDetails ??
        TrailDetails(trailId: trail.id, userId: trail.myId);
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final outcome = await ref.read(trailsProvider.notifier).saveDetails(
          grade == null ? current.copyWith(clearGrade: true) : current.copyWith(grade: grade));
      switch (outcome) {
        case WriteOutcome.done:
          break;
        case WriteOutcome.doneStale:
          messenger.showSnackBar(const SnackBar(
              content: Text('Einschätzung gespeichert$staleAfterWriteHint')));
        case WriteOutcome.queued:
          messenger.showSnackBar(const SnackBar(content: Text(kQueuedHint)));
      }
    } catch (e, st) {
      logError('Trail-Einschätzung speichern', e, st);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.trail.myDetails?.grade;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Deine Einschätzung', style: theme.textTheme.titleSmall),
            SingletrailScaleButton(highlight: mine),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final g in kSingletrailScale)
              // Der eigene Grad steht sofort da (#183), verblasst, bis er
              // auf dem Server liegt.
              Opacity(
                opacity: mine == g.value && widget.trail.pendingDetails ? kPendingValueOpacity : 1,
                child: ChoiceChip(
                  key: ValueKey('own-grade-${g.value}'),
                  label: Text(g.label),
                  tooltip: g.short,
                  selected: mine == g.value,
                  onSelected: _saving
                      ? null
                      : (on) => _set(on ? g.value : null),
                ),
              ),
          ],
        ),
        PendingValueCaption(
            key: const ValueKey('own-grade-pending'), trail: widget.trail, hasValue: mine != null),
      ],
    );
  }
}


/// Eine Kachel mit kleiner Überschrift in Versalien (Design 1i): die
/// Fläche eine Stufe über dem Blatt, Rundung 12.
class _Panel extends StatelessWidget {
  const _Panel({required this.label, required this.child, this.onTap, this.panelKey});
  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final Key? panelKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: palette.muted, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
    return Material(
      key: panelKey,
      color: palette.surface2,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.hardEdge,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Die drei Kennzahlen (Design 1i/4f): Länge, Abfahrt, S-Grad — die Zahl
/// groß in Mono, die Einheit und das Kleingedruckte daneben. Der ganze
/// Satz steht für Bildschirmleser an der Kachel („↓ 420 Hm · ↑ 35 Hm",
/// „S2 · S1–S3 · 4 Einschätzungen"); die S-Grad-Kachel öffnet, wer was
/// gesagt hat.
class _MetricTiles extends StatelessWidget {
  const _MetricTiles({required this.trail, required this.elevation});
  final Trail trail;

  /// Aufgezeichnet oder aus dem Geländemodell (#186, dann mit „≈").
  final ElevationProfile? elevation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final big = AppFonts.numbers(theme.textTheme.titleLarge).copyWith(fontSize: 20);
    final small = AppFonts.numbers(theme.textTheme.bodySmall).copyWith(color: palette.muted);
    final elevation = this.elevation;
    final grade = trail.grade;
    final range = trail.gradeRange;

    Widget tile(String label, String semantics, List<InlineSpan> value, {Key? key, VoidCallback? onTap}) =>
        Expanded(
          child: Semantics(
            label: semantics,
            button: onTap != null,
            excludeSemantics: true,
            child: _Panel(
              panelKey: key,
              label: label,
              onTap: onTap,
              child: Text.rich(TextSpan(children: value), style: big, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
        );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile('LÄNGE', formatLength(trail.lengthM), [TextSpan(text: formatLength(trail.lengthM))],
              key: const ValueKey('metric-length')),
          const SizedBox(width: 8),
          tile(
            'HÖHE',
            elevation == null
                ? 'Keine Höhenangaben'
                : '${formatElevation((gain: elevation.gainM, loss: elevation.lossM))}'
                    '${elevation.fromTerrain ? ' aus dem Geländemodell' : ''}',
            elevation == null
                ? [TextSpan(text: '—', style: TextStyle(color: palette.muted))]
                : [
                    TextSpan(text: '${elevation.fromTerrain ? '≈' : ''}↓${elevation.lossM.round()}'),
                    TextSpan(text: ' Hm', style: small),
                  ],
            key: const ValueKey('metric-elevation'),
          ),
          const SizedBox(width: 8),
          CoachAnchor(
            id: SheetCoach.grade,
            child: tile(
            'S-GRAD',
            gradeSummary(trail) ?? 'Noch keine Einschätzung',
            grade == null || range == null
                ? [TextSpan(text: '—', style: TextStyle(color: palette.muted))]
                : [
                    TextSpan(text: gradeLabel(grade), style: TextStyle(color: palette.accentText)),
                    // Spanne und Anzahl eine Zeile tiefer — neben dem Grad
                    // bräche „S2–S3 · 4" in einer Drittel-Kachel um.
                    TextSpan(
                        text: '\n${[
                          if (range.min != range.max) '${gradeLabel(range.min)}–${gradeLabel(range.max)}',
                          '${trail.gradeVotes.length}×',
                        ].join(' · ')}',
                        style: small),
                  ],
            // Der Schlüssel des früheren Chips bleibt: Die Kachel tut dasselbe.
            key: const ValueKey('grade-chip'),
            onTap: grade == null ? null : () => showGradeVotesSheet(context, trail),
          )),
        ],
      ),
    );
  }
}

/// Die zweite Kachelreihe (Rework E8): BEWERTUNG und ZUSTAND. Ein Tipp
/// zeigt die Einzelstimmen wie beim S-Grad.
class _OpinionTiles extends ConsumerWidget {
  const _OpinionTiles({required this.trail});
  final Trail trail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final big = AppFonts.numbers(theme.textTheme.titleLarge).copyWith(fontSize: 20);
    final small = AppFonts.numbers(theme.textTheme.bodySmall).copyWith(color: palette.muted);
    final rating = trail.rating;
    final votes = trail.ratingVotes.length;
    final condition = trail.shownCondition;
    final shown = condition.unconfirmed ?? condition.confirmed;

    final ratingSemantics = rating == null
        ? (trail.ratingOpen ? 'Noch nicht bewertet, auch nicht von dir' : 'Noch keine Bewertung')
        : 'Bewertung $rating von $kRatingMax Sternen, $votes ${votes == 1 ? 'Stimme' : 'Stimmen'}';
    final conditionSemantics = [
      if (condition.confirmed case final c?)
        '${trailCondition(c.condition!).label}, ${reportAgeLabel(c.reportedAt)}',
      if (condition.unconfirmed case final u?)
        '${trailCondition(u.condition!).label}, ${reportAgeLabel(u.reportedAt)}, zu bestätigen',
    ].join('; ');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Semantics(
              label: ratingSemantics,
              button: votes > 0,
              excludeSemantics: true,
              child: _Panel(
                panelKey: const ValueKey('metric-rating'),
                label: 'BEWERTUNG',
                onTap: votes == 0 ? null : () => showRatingVotesSheet(context, ref, trail),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Eigener Trail ohne eigene Bewertung: verblasste Sterne
                    // — das IST „Bewertung offen" (Rework E4).
                    RatingStars(rating, size: 20, faded: rating == null || trail.ratingOpen),
                    Text(rating == null ? '—' : '$rating von $kRatingMax · $votes×', style: small),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              label: conditionSemantics.isEmpty ? 'Kein Zustand gemeldet' : 'Zustand: $conditionSemantics',
              button: shown != null,
              excludeSemantics: true,
              child: _Panel(
                panelKey: const ValueKey('metric-condition'),
                label: 'ZUSTAND',
                onTap: shown == null ? null : () => showConditionVotesSheet(context, ref, trail),
                child: shown == null
                    ? Text('—', style: big.copyWith(color: palette.muted))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (condition.confirmed case final c?)
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: trailCondition(c.condition!).label),
                                TextSpan(text: ' · ${reportAgeLabel(c.reportedAt)}', style: small),
                              ]),
                              style: theme.textTheme.titleMedium,
                            ),
                          if (condition.unconfirmed case final u?)
                            Opacity(
                              opacity: 0.6,
                              child: Text(
                                  '${trailCondition(u.condition!).label}? · ${reportAgeLabel(u.reportedAt)} · zu bestätigen',
                                  key: const ValueKey('condition-unconfirmed'),
                                  style: theme.textTheme.bodySmall),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
