// Airtime unter Buddys (#36 Schritt 6): was die Oberfläche zeigt —
// Rangliste im Trail-Blatt, Titel und Zähler an Buddy und eigener Karte
// (Entwurf „Airtime unter Buddys", Variante A „Zeile", 2026-11-07).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../data/airtime_repository.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../friends/buddy_alias.dart';
import '../friends/friend_providers.dart';
import 'airtime_providers.dart';
import 'airtime_share.dart';
import 'trail_values.dart' show airtimeNumber;

/// Zehntelsekunden als „4,3".
String airtimeDsText(AppLocalizations l, int ds) => airtimeNumber(l, ds / 10, 1);

/// Der Name zu einer Nutzer-id in der Rangliste: „Du", sonst Alias vor
/// Name (eine Regel, `BuddyNames.of`).
String airtimeNameOf(WidgetRef ref, AppLocalizations l, String userId) {
  final me = ref.watch(currentUserIdProvider);
  if (userId == me) return l.airtimeYou;
  final names = ref.watch(buddyNamesViewProvider);
  final entry = ref
      .watch(friendshipsProvider)
      .valueOrNull
      ?.where((f) => f.otherId(me ?? '') == userId)
      .firstOrNull;
  return names.of(userId, entry?.otherUsername(me ?? ''));
}

/// Die Zeilen der Rangliste für [trailId], oder null — ohne Teilen, ohne
/// Wert oder solange geladen wird, steht im Blatt nichts (auch kein Panel).
List<AirtimeRank>? shownAirtimeRanking(WidgetRef ref, String trailId) {
  final board = ref.watch(airtimeBoardProvider).valueOrNull;
  final me = ref.watch(currentUserIdProvider);
  if (board == null || me == null) return null;
  final ranking = trailAirtimeRanking(board.bests, trailId);
  if (ranking.isEmpty) return null;
  return airtimeRankingShown(ranking, me);
}

/// Inhalt des Panels „AIRTIME UNTER BUDDYS" im Trail-Blatt: Platz, Avatar,
/// Name, Monat, Wert — die eigene Zeile hinterlegt in der Marke.
class AirtimeRankingList extends ConsumerWidget {
  const AirtimeRankingList({super.key, required this.trailId, required this.rows});

  final String trailId;
  final List<AirtimeRank> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final me = ref.watch(currentUserIdProvider);
    final mine = ref.watch(airtimeBoardProvider).valueOrNull?.bestOf(me ?? '', trailId);
    final month = DateFormat(l.airtimeMonthPattern, l.localeName);
    final small = theme.textTheme.bodySmall?.copyWith(color: palette.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.airtimeGameNote, style: small),
        const SizedBox(height: 4),
        for (final r in rows)
          Builder(builder: (context) {
            final own = r.best.userId == me;
            final name = airtimeNameOf(ref, l, r.best.userId);
            final value = airtimeDsText(l, r.best.airDs);
            final when = month.format(r.best.month);
            return Semantics(
              label: l.airtimeRankingLabel(r.place, name, value, when),
              excludeSemantics: true,
              child: Container(
                key: ValueKey('airtime-rank-${r.best.userId}'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: own
                    ? BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8))
                    : null,
                child: Row(children: [
                  SizedBox(
                    width: 22,
                    child: Text('${r.place}',
                        style: AppFonts.numbers(TextStyle(color: own ? palette.accentText : palette.muted))),
                  ),
                  Expanded(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: own ? FontWeight.w600 : FontWeight.w400)),
                  ),
                  Text(when, style: small),
                  SizedBox(
                    width: 64,
                    child: Text(l.airtimeSecondsValue(value),
                        textAlign: TextAlign.right, style: AppFonts.numbers(const TextStyle())),
                  ),
                ]),
              ),
            );
          }),
        if (mine != null) ...[
          const SizedBox(height: 6),
          Text(l.airtimeMyLongest(airtimeDsText(l, mine.longestDs)),
              key: const ValueKey('airtime-my-longest'), style: small),
        ],
      ],
    );
  }
}

/// Die Titel einer Person, wie der Betrachter sie sieht: die vom Gerät
/// (Segelflieger, Bodenpersonal) und die aus dem Vergleich (Vielflieger,
/// Trailkönig).
List<String> airtimeTitlesOf(AppLocalizations l, AirtimeBoard board, String userId, DateTime now) {
  final c = board.counterOf(userId);
  final kings = trailKingCounts(board.bests)[userId] ?? 0;
  return [
    if (c != null && airtimeCounterFresh(c, now) && c.titles.contains(AirtimeTitle.glider)) l.airtimeTitleGlider,
    if (frequentFlyers(board.counters, now).contains(userId)) l.airtimeTitleFrequentFlyer,
    if (kings > 0) l.airtimeTitleTrailKing(kings),
    if (c != null && airtimeCounterFresh(c, now) && c.titles.contains(AirtimeTitle.groundCrew)) l.airtimeTitleGroundCrew,
  ];
}

/// Titel als kleine Chips (Text, kein Symbol — liest sich ohne Legende).
class AirtimeTitleChips extends StatelessWidget {
  const AirtimeTitleChips({super.key, required this.titles, this.own = false});

  final List<String> titles;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: context.l10n.airtimeTitleHint,
      child: Wrap(spacing: 6, runSpacing: 4, children: [
        for (final t in titles)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: palette.surface2, borderRadius: BorderRadius.circular(6)),
            child: Text(t,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: own ? palette.accentText : palette.buddyText)),
          ),
      ]),
    );
  }
}

/// Zähler und Titel unter einem Buddy in der Liste; nichts, wenn er nicht
/// teilt oder sein Stand älter als 30 Tage ist.
class BuddyAirtimeLine extends ConsumerWidget {
  const BuddyAirtimeLine({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(airtimeBoardProvider).valueOrNull;
    if (board == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final c = board.counterOf(userId);
    final titles = airtimeTitlesOf(context.l10n, board, userId, now);
    final fresh = c != null && airtimeCounterFresh(c, now);
    if (!fresh && titles.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final palette = AppPalette.of(context);
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted);
    final today = DateTime(now.year, now.month, now.day);
    return Padding(
      key: ValueKey('buddy-airtime-$userId'),
      padding: const EdgeInsets.only(top: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (fresh)
          Text(
            [
              l.airtimeCounterLine(airtimeDsText(l, c.airDs)),
              if (c.asOf.isBefore(today)) l.airtimeCounterAsOf(DateFormat(l.airtimeAsOfPattern, l.localeName).format(c.asOf)),
            ].join(' · '),
            style: small,
          ),
        if (titles.isNotEmpty) ...[
          const SizedBox(height: 3),
          AirtimeTitleChips(titles: titles),
        ],
      ]),
    );
  }
}

/// Die eigene Karte oben im Buddys-Reiter: Airtime und Sprünge der letzten
/// 30 Tage und die eigenen Titel — wie Buddys sie sehen.
class MyAirtimeCard extends ConsumerWidget {
  const MyAirtimeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(airtimeBoardProvider).valueOrNull;
    final me = ref.watch(currentUserIdProvider);
    final c = me == null ? null : board?.counterOf(me);
    if (board == null || me == null || c == null) return const SizedBox.shrink();
    final l = context.l10n;
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final titles = airtimeTitlesOf(l, board, me, DateTime.now());
    return Card(
      key: const ValueKey('my-airtime-card'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.airtimeMyCardTitle,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: palette.muted, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(l.airtimeSecondsValue(airtimeDsText(l, c.airDs)),
                style: AppFonts.numbers(const TextStyle(fontSize: 28))),
            const SizedBox(width: 10),
            Text(l.airtimeMyJumps(c.jumps), style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted)),
          ]),
          if (titles.isNotEmpty) ...[
            const SizedBox(height: 6),
            AirtimeTitleChips(titles: titles, own: true),
          ],
        ]),
      ),
    );
  }
}

/// Die Rangzeile in „Trail geschafft" (Entwurf 1a): diese Durchfahrt
/// gegen die geteilten Bestwerte der Buddys — „#2 hinter Jan (5,1 s)".
/// null ohne Teilen oder ohne Sprung.
({String rank, bool newBest})? airtimeRunRank(
    WidgetRef ref, AppLocalizations l, String trailId, double airS) {
  final board = ref.watch(airtimeBoardProvider).valueOrNull;
  final me = ref.watch(currentUserIdProvider);
  if (board == null || me == null || airS <= 0) return null;
  final run = (airS * 10).round();
  final others = [for (final b in board.bests) if (b.trailId == trailId && b.userId != me) b]
    ..sort((a, b) => b.airDs.compareTo(a.airDs));
  final mine = board.bestOf(me, trailId);
  final newBest = mine == null || run > mine.airDs;
  if (others.isEmpty) return newBest ? (rank: '', newBest: true) : null;
  final ahead = others.where((b) => b.airDs > run).toList();
  if (ahead.isEmpty) return (rank: l.airtimeRankFirst, newBest: newBest);
  final first = ahead.first;
  return (
    rank: l.airtimeRankBehind(ahead.length + 1, airtimeNameOf(ref, l, first.userId), airtimeDsText(l, first.airDs)),
    newBest: newBest,
  );
}
