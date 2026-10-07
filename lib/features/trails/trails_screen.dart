import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../core/errors.dart';
import '../../core/widgets/motion.dart';
import '../../models/trail.dart';
import '../friends/buddy_alias.dart' show buddyNamesViewProvider;
import '../coach/coach.dart';
import '../routing/navigate_choice.dart';
import '../help/help_link.dart';
import '../help/tab_tours.dart';
import '../help/tour_examples.dart';
import '../map/map_screen.dart' show formatCachedAt;
import 'trail_filter_chips.dart';
import 'rating_stars.dart';
import 'trail_list.dart';
import 'trail_providers.dart';
import 'trail_sheet.dart';
import 'grade_shield.dart';
import 'trail_traits.dart';

/// Die Karte als Liste: erst die eigenen Trails, dann die, die nur Buddys
/// belegt haben. Antippen öffnet das Blatt; von dort geht es auf die Karte.
/// Darüber Suche, Filter und Sortierung (#66, `trail_list.dart`).
class TrailsScreen extends ConsumerStatefulWidget {
  const TrailsScreen({super.key});

  @override
  ConsumerState<TrailsScreen> createState() => _TrailsScreenState();
}

class _TrailsScreenState extends ConsumerState<TrailsScreen> {
  final _search = TextEditingController();

  /// Der Trail, dessen Blatt die Trails-Tour (#136) öffnet: der erste
  /// eigene der Liste, sonst der erste. Gesetzt bei jedem Aufbau.
  Trail? _tourTrail;

  /// Zeigt die Liste gerade das Beispiel? Dann öffnet die Tour das
  /// Beispiel-Blatt.
  bool _showsExample = false;
  VoidCallback? _unregisterScene;

  @override
  void initState() {
    super.initState();
    _unregisterScene = ref.read(coachRegistryProvider).registerScene(TrailsCoach.sheet, () async {
      final trail = _tourTrail;
      if (!mounted) return () {};
      if (trail == null) return _showsExample ? showExampleTrailSheet(context) : () {};
      final navigator = Navigator.of(context);
      var open = true;
      unawaited(showTrailSheet(context, trail, showOnMapButton: true).whenComplete(() => open = false));
      return () {
        if (open) navigator.pop();
      };
    });
  }

  @override
  void dispose() {
    _unregisterScene?.call();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trailsAsync = ref.watch(trailsProvider);
    // Das Beispiel (#136) nur während der Tour und nur ohne JEDEN Trail —
    // eine leere Suche ist kein leeres Konto.
    _showsExample = ref.watch(coachExamplesProvider) && (trailsAsync.valueOrNull?.isEmpty ?? false);
    if (_showsExample) _tourTrail = null;
    return TabTourStarter(
      script: kTrailsTourScript,
      child: Scaffold(
      appBar: AppBar(
        // Der Reiter-Kopf aus dem Entwurf (1j): groß, in Versalien, rechts
        // der Bestand in Mono.
        toolbarHeight: 64,
        title: Text('TRAILS',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        actions: [
          if (trailsAsync.valueOrNull case final all? when all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '${all.length} · ${formatLength(all.fold(0.0, (sum, t) => sum + t.lengthM))}',
                key: const ValueKey('trails-total'),
                style: AppFonts.numbers(Theme.of(context).textTheme.bodySmall)
                    .copyWith(color: AppPalette.of(context).muted),
              ),
            ),
          CoachAnchor(
            id: TrailsCoach.import,
            child: IconButton(
              key: const ValueKey('trail-import-button'),
              tooltip: 'GPX importieren',
              icon: const Icon(Icons.file_upload_outlined),
              onPressed: () => context.push('/profile/import'),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(trailsProvider.future),
        child: trailsAsync.when(
          loading: () => const CenteredTrailLoader(),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(friendlyError(e)),
            ),
          ]),
          data: (trails) {
            if (_showsExample) {
              return ListView(
                children: [
                  _Controls(
                    search: _search,
                    onSearch: () => setState(() {}),
                    filter: ref.watch(trailListFilterProvider),
                    showOwner: false,
                    sort: ref.watch(trailSortProvider),
                  ),
                  const SizedBox(height: 8),
                  const ExampleTrailTile(),
                ],
              );
            }
            if (trails.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  Text(
                    'Noch keine Trails. Importiere deine GPX-Dateien (Symbol '
                    'oben rechts) oder verbinde dich mit Buddys.',
                  ),
                  SizedBox(height: 8),
                  HelpLinkButton(),
                ],
              );
            }
            final seen = ref.watch(seenNotesProvider);
            final cachedAt = ref.watch(trailsCachedAtProvider);
            final sort = ref.watch(trailSortProvider);
            final filter = ref.watch(trailListFilterProvider);
            final onMap =
                ref.watch(trailListOnMapProvider) ? ref.watch(mapVisibleBoundsProvider) : null;
            final query = _search.text;
            final result = trailListOf(trails,
                query: query,
                onMap: onMap,
                filter: filter,
                sort: sort,
                seenNotes: seen,
                snoozed: ref.watch(stillValidSnoozesProvider));
            final shown = result.trails;
            final pending = shown.where((t) => t.pending).toList();
            final own = shown.where((t) => t.isOwn && !t.pending).toList();
            final buddies = shown.where((t) => !t.isOwn).toList();
            _tourTrail = own.firstOrNull ?? buddies.firstOrNull;
            // Der Dreier-Schalter nur, wenn es beides gibt — sonst hätte
            // eine Hälfte immer „keine Trails".
            final mixed = trails.any((t) => t.isOwn) && trails.any((t) => !t.isOwn);
            final searching = query.trim().isNotEmpty || filter.isActive || onMap != null;
            return ListView(
              children: [
                _Controls(
                  search: _search,
                  onSearch: () => setState(() {}),
                  filter: filter,
                  showOwner: mixed,
                  sort: sort,
                ),
                if (searching)
                  _Summary(
                    count: shown.length,
                    isGuess: result.isGuess,
                    hiddenUngraded: result.hiddenUngraded,
                  ),
                if (cachedAt != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      ref.watch(trailsAwaitNetworkProvider)
                          ? 'Stand vom ${formatCachedAt(cachedAt)} — das Netz antwortet noch, '
                              'der frische Stand kommt gleich.'
                          : 'Kein Empfang — Stand vom ${formatCachedAt(cachedAt)}. '
                              'Neue Beiträge deiner Buddys kommen mit dem nächsten Netz.',
                      key: const ValueKey('cached-notice-list'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                // Der Ausgangskorb (#30) zuerst: Was wartet, soll man
                // sehen — sonst steuert man dieselbe Datei zweimal bei.
                if (pending.isNotEmpty) _Header('Wartet auf Übertragung (${pending.length})'),
                for (final t in pending) _TrailTile(t, fresh: false),
                if (own.isNotEmpty) _Header('Meine Trails (${own.length})'),
                for (final t in own)
                  _TrailTile(t, fresh: t.hasFreshNote(seen: seen), coach: t == _tourTrail),
                if (buddies.isNotEmpty) _Header('Von Buddys (${buddies.length})'),
                for (final t in buddies)
                  _TrailTile(t, fresh: t.hasFreshNote(seen: seen), coach: t == _tourTrail),
              ],
            );
          },
        ),
      ),
    ));
  }
}

/// Suchfeld, Filter und Sortierung über der Liste.
class _Controls extends ConsumerWidget {
  const _Controls({
    required this.search,
    required this.onSearch,
    required this.filter,
    required this.showOwner,
    required this.sort,
  });

  final TextEditingController search;
  final VoidCallback onSearch;
  final TrailListFilter filter;
  final bool showOwner;
  final TrailSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Die Sortierung neben der Suche, nicht bei den Chips: Dort
          // schnitt sie auf 360 dp den dritten Chip ab.
          Row(
            children: [
              Expanded(
                child: CoachAnchor(
                  id: TrailsCoach.search,
                  child: TextField(
                  key: const ValueKey('trail-search'),
                  controller: search,
                  onChanged: (_) => onSearch(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Trail oder Buddy',
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Suche leeren',
                            onPressed: () {
                              search.clear();
                              onSearch();
                            },
                          ),
                  ),
                )),
              ),
              CoachAnchor(
                id: TrailsCoach.sort,
                child: PopupMenuButton<TrailSort>(
                key: const ValueKey('trail-sort'),
                tooltip: 'Sortieren: ${sort.label}',
                icon: const Icon(Icons.sort),
                initialValue: sort,
                onSelected: (v) => ref.read(trailSortProvider.notifier).state = v,
                itemBuilder: (_) => [
                  for (final v in TrailSort.values)
                    CheckedPopupMenuItem(
                      key: ValueKey('trail-sort-${v.name}'),
                      value: v,
                      checked: v == sort,
                      child: Text(v.label),
                    ),
                ],
              )),
            ],
          ),
          CoachAnchor(
              id: TrailsCoach.chips, child: TrailFilterChips(showOwner: showOwner, onMapChip: true)),
        ],
      ),
    );
  }
}

/// Was die Suche gefunden hat — und ob geraten wurde.
class _Summary extends StatelessWidget {
  const _Summary({required this.count, required this.isGuess, required this.hiddenUngraded});

  final int count;
  final bool isGuess;
  final int hiddenUngraded;

  @override
  Widget build(BuildContext context) {
    final text = count == 0
        ? 'Keine Trails für diese Suche.'
        : isGuess
            ? 'Kein Trail heißt so. Meintest du …?'
            : count == 1
                ? 'Ein Trail gefunden.'
                : '$count Trails gefunden.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: text),
          if (hiddenUngraded > 0)
            TextSpan(
              text: hiddenUngraded == 1
                  ? ' Ein Trail ohne Einschätzung ist nicht dabei.'
                  : ' $hiddenUngraded Trails ohne Einschätzung sind nicht dabei.',
              style: TextStyle(color: AppPalette.of(context).muted),
            ),
        ]),
        key: const ValueKey('trail-search-summary'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 6),
        // Wie die Abschnitte im Entwurf (1k): klein, gesperrt, gedämpft.
        child: Text(text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppPalette.of(context).muted)),
      );
}

/// Eine Zeile als Karte (Design 1j/4e): links der Farbstreifen der
/// Beziehung, dann Name, Zahlen in Mono und das Wort in seiner Farbe;
/// rechts der Charakter. Ein neuer Hinweis rahmt die Karte gelb — die
/// Farbe des Leuchtrands auf der Karte.
class _TrailTile extends ConsumerWidget {
  const _TrailTile(this.trail, {required this.fresh, this.coach = false});
  final Trail trail;

  /// Die Zeile, auf die die Trails-Tour (#136) zeigt.
  final bool coach;

  /// Neuer, noch nicht gesehener Hinweis eines Buddys (#7).
  final bool fresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final names = ref.watch(buddyNamesViewProvider);
    final numbers = <String>[
      formatLength(trail.lengthM),
      if (trail.elevation != null) '↓ ${trail.elevation!.lossM.round()} Hm',
    ];
    final tags = trailRowTags(trail,
        freshNote: fresh, nameOf: (id, username) => names.of(id, username));
    Color tagColor(TrailRowTagKind k) => switch (k) {
          TrailRowTagKind.pending => palette.muted,
          TrailRowTagKind.failure => theme.colorScheme.error,
          TrailRowTagKind.warning => palette.warningText,
          TrailRowTagKind.unconfirmed => palette.muted,
          TrailRowTagKind.note => palette.noteText,
          TrailRowTagKind.condition => theme.colorScheme.onSurface,
          TrailRowTagKind.mine => palette.accentText,
          TrailRowTagKind.buddy => palette.buddyText,
        };
    // Der Streifen sagt die Schwierigkeit wie die Linie auf der Karte
    // (seit 0.42.0); wem der Trail gehört und ob er gemeldet ist, sagt
    // das Wort darunter. Ein wartender Trail ist blass — er ist noch
    // nicht auf dem Server.
    final stripe = trail.pending ? palette.muted : trailColorOf(trail, palette.grade);
    final tagStyle = theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: 0.8, fontSize: 11);
    final card = Card(
      margin: EdgeInsets.zero,
      // Flach mit Rand wie im Entwurf; der Schatten der Vorgabe (1) zog im
      // Hellen eine dunkle Kante um jede Karte.
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: fresh
            ? BorderSide(color: palette.map.note, width: 1.5)
            : BorderSide(color: palette.line),
      ),
      child: ListTile(
        // Die Rundung auch am Tipp-Schein, sonst stünde er eckig in der Karte.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        horizontalTitleGap: 12,
        minLeadingWidth: 4,
        leading: _anchorIf(
          coach && trail.isOwn,
          TrailsCoach.rowOwn,
          Container(
            key: const ValueKey('trail-stripe'),
            width: 4,
            height: 40,
            decoration: BoxDecoration(color: stripe, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        title: Text(trail.displayName,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Die Zahlen in Mono — auch der Pfeil, den Barlow nicht hat.
            Text(numbers.join(' · '),
                style: AppFonts.numbers(theme.textTheme.bodySmall)
                    .copyWith(color: palette.muted)),
            // Die Sterne (#101, Rework E4): der Median des Netzes; blass,
            // solange ich meinen eigenen Trail nicht bewertet habe.
            if (trail.rating != null || trail.ratingOpen)
              Semantics(
                label: trail.rating == null
                    ? 'Noch nicht bewertet'
                    : 'Bewertung ${trail.rating} von $kRatingMax Sternen',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: RatingStars(trail.rating,
                      key: const ValueKey('row-rating'),
                      size: 13,
                      faded: trail.rating == null || trail.ratingOpen),
                ),
              ),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(children: [
                    for (final (i, t) in tags.indexed) ...[
                      if (i > 0) TextSpan(text: ' · ', style: TextStyle(color: palette.muted)),
                      TextSpan(text: t.text, style: TextStyle(color: tagColor(t.kind))),
                    ],
                  ]),
                  style: tagStyle,
                ),
              ),
          ],
        ),
        // Rechts oben das Schild, darunter der Charakter (Design 4e);
        // links davon das Navi-Symbol (#176) — nicht für wartende Trails.
        // Das Schild bleibt am Rand, wo das Auge es sucht.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!trail.pending) _anchorIf(coach, TrailsCoach.nav, TrailNavButton(trail)),
            if (trail.grade != null || trail.topTraits.isNotEmpty)
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (trail.grade != null) GradeShield(trail.grade!, key: const ValueKey('grade-shield'), uphill: isUphill(trail)),
                  if (trail.grade != null && trail.topTraits.isNotEmpty) const SizedBox(height: 4),
                  if (trail.topTraits.isNotEmpty) TrailTraitIcons(trail.topTraits, color: palette.muted),
                ],
              ),
          ],
        ),
        onTap: () => showTrailSheet(context, trail, showOnMapButton: true),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      // Der gelbe Rand atmet, solange der Hinweis ungesehen ist (1t).
      child: _anchorIf(coach, TrailsCoach.row,
          fresh ? BreathingGlow(color: palette.map.note, radius: 14, child: card) : card),
    );
  }
}

Widget _anchorIf(bool yes, String id, Widget child) => yes ? CoachAnchor(id: id, child: child) : child;
