// Melden (#101, Rework Abschnitt 9; seit #433 ein Eintrag aus Status,
// Text und Foto, `docs/konzept-melden.md`) und der Zustand 1–5 zu einem
// Trail. Anders als der Beitrag darf das JEDER, der
// den Trail sieht — wer die Hausrunde nie aufgezeichnet hat, soll trotzdem
// „Baum liegt quer" melden können. Dann aber verblasst, „zu bestätigen".
//
// **Bestätigt** ist eine Angabe, wenn der Meldende den Trail gefahren hat
// oder vor Ort ist. „Vor Ort" prüft NUR das Gerät: ≤ [kOnSiteMaxM] zur
// Linie, mit der Position, die ein Tipp auf „Ich bin vor Ort" holt. Zum
// Server geht das Ja/Nein, nie die Position — und gespeichert wird dort
// nicht einmal das, nur das Ergebnis `confirmed`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../../core/geo.dart' show formatMeters;
import '../../core/line_geometry.dart';
import '../../core/photo_pipeline.dart';
import '../../core/photo_providers.dart';
import '../../core/widgets/photo_attachment.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import '../friends/buddy_alias.dart';
import '../map/position_provider.dart';
import 'pending_value.dart';
import 'rating_stars.dart';
import 'trail_condition.dart';
import 'trail_list.dart' show kConditionWordMax;
import 'trail_notes.dart';
import 'trail_providers.dart';

/// So nah muss man an der Linie sein, damit eine Meldung „vor Ort" gilt
/// (Betreiber, 2026-09-30).
const kOnSiteMaxM = 200.0;

/// Die Beschriftung der Chips im Dialog „Melden" (bis 0.48.0 „Status",
/// bis 0.146 „Meldung" — seit #433 ist „Meldung" der ganze Eintrag), auf
/// Deutsch für die Kurzanleitung. Der Dialog liest `reportFieldLabel` aus
/// den ARB-Dateien; `help_texts_test.dart` hält Konstante, ARB-Text und
/// Anleitung zusammen — ändert sich die Beschriftung, bricht der Test,
/// nicht still der Text.
const kReportFieldLabel = 'Der Trail ist …';

/// „heute", „gestern", „vor 3 Tagen", „vor 4 Monaten" — das Alter einer
/// Meldung, ohne das Verb (das sagt die Zeile).
String reportAgeLabel(AppLocalizations l, DateTime at, {DateTime? now}) {
  final days = (now ?? DateTime.now()).difference(at).inDays;
  if (days <= 0) return l.reportAgeToday;
  if (days == 1) return l.reportAgeYesterday;
  if (days < 60) return l.reportAgeDays(days);
  final months = (days / 30.4).round();
  if (months < 24) return l.reportAgeMonths(months);
  return l.reportAgeYears((days / 365).floor());
}

/// Was eine Meldung sagt, in Worten: „Gesperrt" bzw. „Ausgefahren".
String reportValueLabel(AppLocalizations l, TrailReport r) => r.kind == ReportKind.status
    ? r.status!.label(l)
    : trailCondition(r.condition!).label(l);

/// Das Ergebnis des Melde-Dialogs (#433): wahlweise ein Status, Text und
/// Foto — mindestens Status oder Text.
typedef ReportInput = ({TrailStatus? status, bool onSite, String? note, PreparedPhoto? photo});

/// „Melden" im Blatt: Dialog, dann schreiben (oder in den Ausgangskorb).
Future<void> reportTrail(BuildContext context, WidgetRef ref, Trail trail) async {
  final input = await showDialog<ReportInput>(
    context: context,
    builder: (_) => _ReportDialog(trail: trail),
  );
  if (input == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  try {
    final result = await ref.read(trailsProvider.notifier).reportEntry(trail.id,
        status: input.status, onSite: input.onSite, note: input.note, photo: input.photo);
    final photoError = result.photoError;
    final done = input.photo != null ? l.reportDoneWithPhoto : l.reportDone;
    messenger.showSnackBar(SnackBar(
        content: Text(switch (result.outcome) {
      // Beides sagen: Der Eintrag steht — sonst schriebe man ihn ein
      // zweites Mal —, das Foto nicht.
      _ when photoError != null => l.notePhotoFailed(friendlyError(l, photoError)),
      WriteOutcome.done => done,
      WriteOutcome.doneStale => l.staleAfterWrite(done),
      WriteOutcome.queued => result.photoDropped ? l.reportQueuedNoPhoto : l.queuedHint,
    })));
  } catch (e, st) {
    logError('Trail melden', e, st);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
  }
}

class _ReportDialog extends ConsumerStatefulWidget {
  const _ReportDialog({required this.trail});
  final Trail trail;

  @override
  ConsumerState<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<_ReportDialog> {
  TrailStatus? _status;
  final _note = TextEditingController();
  PreparedPhoto? _photo;
  var _onSite = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final l = context.l10n;
    final text = _note.text.trim();
    // Privat zählt nur, wenn ich selbst einen Beitrag habe — sonst gibt
    // es nichts, was ich verbergen könnte.
    final private = widget.trail.myDetails?.visibility == TrailVisibility.private;
    final offline = ref.watch(noConnectivityProvider);
    // Ein Foto ohne Text gibt es nicht (`trail_notes.body` ist Pflicht).
    final ready = (_status != null || text.isNotEmpty) && (_photo == null || text.isNotEmpty);
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.muted);
    return AlertDialog(
      title: Text(l.reportDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.reportFieldLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in kReportStatusOrder)
                  ChoiceChip(
                    key: ValueKey('report-status-${s.db}'),
                    label: Text(s.reportLabel(l)),
                    selected: _status == s,
                    onSelected: (on) => setState(() => _status = on ? s : null),
                  ),
              ],
            ),
            TextField(
              key: const ValueKey('report-note'),
              controller: _note,
              maxLength: kNoteMaxLength,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.reportNoteLabel,
                hintText: switch (_status) {
                  null => l.reportNoteHintNone,
                  TrailStatus.open => l.reportNoteHintOpen,
                  _ => l.reportNoteHintWarn,
                },
              ),
            ),
            PhotoAttachment(
              pick: ref.read(photoPickerProvider),
              prepare: ref.read(photoPreparerProvider),
              photo: _photo,
              attachedNote: notePhotoNote(l, private: private),
              onChanged: (photo) => setState(() => _photo = photo),
            ),
            if (_photo != null && text.isEmpty)
              Text(l.reportPhotoNeedsText, key: const ValueKey('report-photo-needs-text'), style: muted),
            if (_photo != null && offline)
              Text(l.reportPhotoOffline, key: const ValueKey('report-photo-offline'), style: muted),
            const SizedBox(height: 8),
            Text(reportAudience(l, private: private, status: _status != null),
                key: const ValueKey('report-audience'), style: muted),
            // Bestätigen gibt es nur für einen Status — Text allein ist
            // nichts, was man bestätigen müsste.
            if (_status != null) ...[
              const SizedBox(height: 8),
              ReportConfirmation(trail: widget.trail, onChanged: (onSite) => _onSite = onSite),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('report-submit'),
          onPressed: !ready
              ? null
              : () {
                  // Der Text beim Tippen, nicht der vom letzten Bau.
                  final note = _note.text.trim();
                  Navigator.of(context).pop((
                    status: _status,
                    onSite: _status != null && _onSite,
                    note: note.isEmpty ? null : note,
                    photo: note.isEmpty ? null : _photo,
                  ));
                },
          child: Text(l.reportSubmit),
        ),
      ],
    );
  }
}

/// Die Reihenfolge der Chips „Der Trail ist …" (`docs/konzept-melden.md`
/// 4): erst die Warnungen, dann die gute Nachricht.
const kReportStatusOrder = [
  TrailStatus.closed,
  TrailStatus.destroyed,
  TrailStatus.changed,
  TrailStatus.open,
];

extension on TrailStatus {
  /// Im Dialog heißt „offen" „wieder offen" — gemeldet wird es, wenn es
  /// vorher nicht so war.
  String reportLabel(AppLocalizations l) => this == TrailStatus.open ? l.reportStatusOpenAgain : label(l);
}

/// Wer was sieht, in einem Satz (Betreiber 2026-10-31: Status und Text
/// sehen dieselben, die direkten Buddys). Bei „privat" ehrlich: niemand.
String reportAudience(AppLocalizations l, {required bool private, required bool status}) {
  if (private) return l.noteAudiencePrivate;
  return status ? l.reportAudienceWithStatus(kNotePhotoDays) : l.reportAudienceText(kNotePhotoDays);
}

enum _Site { unknown, checking, onSite, away, noFix }

/// Ob eine Angabe als bestätigt gilt, und „Ich bin vor Ort" dazu —
/// dieselbe Zeile im Dialog „Melden" und beim Zustand (#433). Meldet
/// [onChanged], sobald die Prüfung ein Ergebnis hat.
class ReportConfirmation extends ConsumerStatefulWidget {
  const ReportConfirmation({super.key, required this.trail, required this.onChanged});
  final Trail trail;
  final ValueChanged<bool> onChanged;

  @override
  ConsumerState<ReportConfirmation> createState() => _ReportConfirmationState();
}

class _ReportConfirmationState extends ConsumerState<ReportConfirmation> {
  var _site = _Site.unknown;
  double? _distance;

  late final bool _ridden = widget.trail.hasRidden(widget.trail.myId);

  /// Ein Tipp holt EINEN Fix — die Nachfrage nach der Berechtigung kommt
  /// damit nur, wenn jemand darum bittet (Play: Prominent Disclosure).
  Future<void> _checkSite() async {
    setState(() => _site = _Site.checking);
    try {
      final fix = await ref.read(currentPositionProvider)();
      if (!mounted) return;
      if (fix == null) {
        setState(() => _site = _Site.noFix);
        return;
      }
      final d = distanceToLineM(LatLng(fix.latitude, fix.longitude), widget.trail.points);
      setState(() {
        _distance = d;
        _site = d != null && d <= kOnSiteMaxM ? _Site.onSite : _Site.away;
      });
      widget.onChanged(_site == _Site.onSite);
    } catch (e, st) {
      logError('Position zum Melden', e, st);
      if (mounted) setState(() => _site = _Site.noFix);
    }
  }

  String _confirmationText(AppLocalizations l) {
    if (_ridden) return l.reportConfirmedRidden;
    return switch (_site) {
      _Site.onSite => l.reportConfirmedOnSite(formatMeters(_distance!)),
      _Site.away => l.reportUnconfirmedAway(formatMeters(_distance!)),
      _Site.noFix => l.reportUnconfirmedNoFix,
      _ => l.reportUnconfirmedUnchecked,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final l = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_confirmationText(l),
            key: const ValueKey('report-confirmation'),
            style: theme.textTheme.bodySmall?.copyWith(color: palette.muted)),
        if (!_ridden && _site != _Site.onSite)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('report-on-site'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: _site == _Site.checking ? null : _checkSite,
              icon: const Icon(Icons.my_location, size: 18),
              label: Text(_site == _Site.checking ? l.reportCheckingPosition : l.reportOnSite),
            ),
          ),
      ],
    );
  }
}

/// Wer den Trail gemeldet hat, in einem Namen: „Du", der Alias, der
/// Benutzername.
String reporterName(AppLocalizations l, TrailReport r, Trail trail, BuddyNames names) =>
    r.userId == trail.myId ? l.reportYou : names.of(r.userId, r.username);

/// Die eigene Bewertung direkt im Blatt, wie [OwnGradePicker]: ein Tipp
/// auf einen Stern speichert, ein zweiter Tipp auf denselben nimmt sie
/// zurück. Nur für Trails, die man selbst belegt hat.
class OwnRatingPicker extends ConsumerStatefulWidget {
  const OwnRatingPicker({super.key, required this.trail});
  final Trail trail;

  @override
  ConsumerState<OwnRatingPicker> createState() => _OwnRatingPickerState();
}

class _OwnRatingPickerState extends ConsumerState<OwnRatingPicker> {
  bool _saving = false;

  Future<void> _set(int? rating) async {
    final trail = widget.trail;
    final current = trail.myDetails ?? TrailDetails(trailId: trail.id, userId: trail.myId);
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      final outcome = await ref.read(trailsProvider.notifier).saveDetails(
          rating == null ? current.copyWith(clearRating: true) : current.copyWith(rating: rating));
      switch (outcome) {
        case WriteOutcome.done:
          break;
        case WriteOutcome.doneStale:
          messenger.showSnackBar(SnackBar(
              content: Text(l.staleAfterWrite(l.reportRatingSaved))));
        case WriteOutcome.queued:
          messenger.showSnackBar(SnackBar(content: Text(l.queuedHint)));
      }
    } catch (e, st) {
      logError('Trail-Bewertung speichern', e, st);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.trail.myDetails?.rating;
    final palette = AppPalette.of(context);
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.reportOwnRating, style: Theme.of(context).textTheme.titleSmall),
        Row(
          children: [
            for (var i = kRatingMin; i <= kRatingMax; i++)
              IconButton(
                key: ValueKey('own-rating-$i'),
                tooltip: l.reportStarTooltip(i, kRatingMax),
                visualDensity: VisualDensity.compact,
                onPressed: _saving ? null : () => _set(mine == i ? null : i),
                icon: Icon(
                  mine != null && i <= mine ? Icons.star_rounded : Icons.star_outline_rounded,
                  // Sofort gesetzt, verblasst bis auf dem Server (#183).
                  color: mine == null
                      ? palette.muted.withValues(alpha: 0.5)
                      : widget.trail.pendingDetails
                          ? palette.accentText.withValues(alpha: kPendingValueOpacity)
                          : palette.accentText,
                ),
              ),
          ],
        ),
        PendingValueCaption(
            key: const ValueKey('own-rating-pending'), trail: widget.trail, hasValue: mine != null),
      ],
    );
  }
}

/// Die Einzelstimmen der Bewertung (Rework E8: „ein Tipp zeigt die
/// Einzelstimmen wie beim S-Grad").
Future<void> showRatingVotesSheet(BuildContext context, WidgetRef ref, Trail trail) {
  final names = ref.read(buddyNamesViewProvider);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final l = sheetContext.l10n;
      final n = trail.ratingVotes.length;
      final median = trail.rating;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.reportRatingTitle, style: theme.textTheme.titleLarge),
              Text(
                  n == 0 || median == null
                      ? l.reportRatingNone
                      : l.reportRatingMedian(median, kRatingMax, n),
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              for (final d in trail.ratingVotes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.userId == trail.myId ? l.reportYou : names.of(d.userId, d.username)),
                  trailing: RatingStars(d.rating),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Der Zustand für sich (#433, `docs/konzept-melden.md` 5): Ein Tipp auf
/// die Kachel öffnet immer dieses Blatt — oben die eigene Angabe 1–5 mit
/// derselben Bestätigung wie beim Melden, darunter die Einzelstimmen (je
/// Person die jüngste, mit Alter und „zu bestätigen"). Bei 1 oder 2 bietet
/// die Rückmeldung an, etwas dazu zu schreiben: Das öffnet „Melden" ohne
/// Status.
Future<void> showConditionVotesSheet(BuildContext context, WidgetRef ref, Trail trail) async {
  final names = ref.read(buddyNamesViewProvider);
  final latest = <String, TrailReport>{};
  for (final r in trail.reports.where((r) => r.kind == ReportKind.condition)) {
    final prev = latest[r.userId];
    if (prev == null || r.reportedAt.isAfter(prev.reportedAt)) latest[r.userId] = r;
  }
  final votes = latest.values.toList()..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
  final input = await showModalBottomSheet<({int value, bool onSite})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ConditionSheet(trail: trail, votes: votes, names: names),
  );
  if (input == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  try {
    final outcome = await ref
        .read(trailsProvider.notifier)
        .report(trail.id, condition: input.value, onSite: input.onSite);
    final poor = input.value <= kConditionWordMax;
    messenger.showSnackBar(SnackBar(
      content: Text(switch (outcome) {
        WriteOutcome.done => l.conditionSaved,
        WriteOutcome.doneStale => l.staleAfterWrite(l.conditionSaved),
        WriteOutcome.queued => l.queuedHint,
      }),
      persist: false,
      action: poor
          ? SnackBarAction(
              label: l.conditionWriteMore,
              onPressed: () {
                if (context.mounted) reportTrail(context, ref, trail);
              })
          : null,
    ));
  } catch (e, st) {
    logError('Zustand melden', e, st);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
  }
}

class _ConditionSheet extends ConsumerStatefulWidget {
  const _ConditionSheet({required this.trail, required this.votes, required this.names});
  final Trail trail;
  final List<TrailReport> votes;
  final BuddyNames names;

  @override
  ConsumerState<_ConditionSheet> createState() => _ConditionSheetState();
}

class _ConditionSheetState extends ConsumerState<_ConditionSheet> {
  int? _value;
  var _onSite = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final trail = widget.trail;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          key: const ValueKey('condition-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.reportCondition, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l.conditionYours, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in kTrailConditions)
                  ChoiceChip(
                    key: ValueKey('report-condition-${c.value}'),
                    label: Text(c.label(l)),
                    tooltip: c.description(l),
                    selected: _value == c.value,
                    onSelected: (on) => setState(() => _value = on ? c.value : null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ReportConfirmation(trail: trail, onChanged: (onSite) => _onSite = onSite),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('condition-submit'),
                onPressed: _value == null
                    ? null
                    : () => Navigator.of(context).pop((value: _value!, onSite: _onSite)),
                child: Text(l.conditionSubmit),
              ),
            ),
            if (widget.votes.isNotEmpty) const Divider(height: 24),
            for (final r in widget.votes)
              Opacity(
                opacity: r.confirmed ? 1 : 0.6,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(reporterName(l, r, trail, widget.names)),
                  subtitle: Text([
                    trailCondition(r.condition!).label(l),
                    reportAgeLabel(l, r.reportedAt),
                    if (r.sending)
                      l.reportSending
                    else if (r.pending)
                      l.reportWaiting
                    else if (!r.confirmed)
                      l.reportUnconfirmed,
                  ].join(' · ')),
                ),
              ),
            const SizedBox(height: 8),
            for (final c in kTrailConditions)
              Text('${c.label(l)}: ${c.description(l)}', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
