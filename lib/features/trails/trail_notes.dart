import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import '../friends/buddy_alias.dart';
import 'trail_providers.dart';
import 'trail_report.dart' show reportAgeLabel;

/// Die Liste „MELDUNGEN" im Trail-Blatt (#433, `docs/konzept-melden.md`
/// 6): ein Eintrag je Zeile — Status, Text und Foto, was davon da ist.
/// Früher zwei Listen („Hinweise" für Buddys, #7, und der Verlauf der
/// Meldungen, #101), die dieselbe Sache von zwei Seiten zeigten.
/// Schreiben darf jeder, der den Trail sieht; den Text entfernen jeder,
/// der ihn sieht (wer am Trail steht, sagt „erledigt"); bearbeiten
/// niemand: Das Alter soll stimmen.

/// Höchstlänge eines Textes, dieselbe wie im Check von `trail_notes`.
const kNoteMaxLength = 500;

/// So lange bleibt ein Foto am Text (#37) — die Frist steht als Default
/// und Constraint in Patch 026, hier nur für die Sätze im Dialog.
const kNotePhotoDays = 90;

/// [seenBefore] sind die Texte, die schon VOR dem Öffnen gesehen waren —
/// was jetzt neu ist, bleibt im Blatt getönt, auch wenn es beim Öffnen als
/// gesehen gemerkt wird.
class TrailEntriesSection extends ConsumerWidget {
  const TrailEntriesSection({super.key, required this.trail, this.seenBefore = const {}});
  final Trail trail;
  final Set<String> seenBefore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = trail.entriesShown();
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final l = context.l10n;
    return Column(
      key: const ValueKey('trail-reports'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.reportHistoryTitle,
            style: theme.textTheme.labelSmall?.copyWith(
                color: palette.muted, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        if (entries.isEmpty)
          Text(l.noteEmpty, style: theme.textTheme.bodySmall?.copyWith(color: palette.muted)),
        for (final e in entries)
          _EntryTile(
            entry: e,
            trail: trail,
            fresh: e.note != null && trail.isFreshNote(e.note!, seen: seenBefore),
          ),
      ],
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.trail, required this.fresh});
  final TrailEntry entry;
  final Trail trail;
  final bool fresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final l = context.l10n;
    final names = ref.watch(buddyNamesViewProvider);
    final report = entry.report;
    final note = entry.note;
    final userId = report?.userId ?? note!.userId;
    final who = userId == trail.myId ? l.reportYou : names.of(userId, report?.username ?? note?.username);
    final pending = report?.pending ?? note!.pending;
    final sending = report?.sending ?? note!.sending;
    final caption = [
      who,
      reportAgeLabel(l, entry.at),
      if (sending)
        l.reportSending
      else if (pending)
        l.reportWaiting
      else if (report != null && !report.confirmed)
        l.reportUnconfirmed,
    ].join(' · ');
    return Container(
      key: ValueKey(note != null ? 'note-${note.id}' : 'report-${report!.id}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      // Ein neuer Text gelb umrandet (Design 1i) — der Rand, der auf der
      // Karte um die Linie leuchtet.
      decoration: BoxDecoration(
        color: fresh ? palette.map.note.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainerHighest,
        border: fresh ? Border.all(color: palette.map.note, width: 1.5) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Unbestätigt verblasst nur der Status — ein Text
                // verblasst nie (Konzept 6).
                if (report != null)
                  Opacity(
                    opacity: report.confirmed ? 1 : 0.6,
                    child: Row(
                      children: [
                        Icon(report.status!.warns ? Icons.warning_amber : Icons.check_circle_outline, size: 18),
                        const SizedBox(width: 6),
                        Flexible(child: Text(report.status!.label(l), style: theme.textTheme.titleSmall)),
                      ],
                    ),
                  ),
                if (note != null) Text(note.body),
                const SizedBox(height: 2),
                Text(caption,
                    style: fresh
                        ? theme.textTheme.bodySmall?.copyWith(color: palette.noteText, fontWeight: FontWeight.w600)
                        : theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (note?.shownPhoto() case final photo?)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: NotePhotoThumb(photo: photo, note: note!),
            ),
          if (note != null && !note.pending)
            IconButton(
              tooltip: userId == trail.myId ? l.noteDelete : l.noteResolve,
              visualDensity: VisualDensity.compact,
              icon: Icon(userId == trail.myId ? Icons.delete_outline : Icons.check_circle_outline),
              onPressed: () => _remove(context, ref, note),
            ),
        ],
      ),
    );
  }

  /// „Erledigt" (oder bei eigenem Text „Löschen") nimmt Text und Foto.
  /// Steht daneben eine warnende Meldung, die das Blatt gerade anzeigt,
  /// fragt die Rückfrage, ob der Trail wieder offen ist (Konzept 6, A10:
  /// sagen, nicht raten) — sonst bliebe eine Sperre nach dem Wegräumen des
  /// Baums stehen.
  Future<void> _remove(BuildContext context, WidgetRef ref, TrailNote note) async {
    final l = context.l10n;
    final mine = note.userId == trail.myId;
    final name = ref.read(buddyNamesViewProvider).of(note.userId, note.username);
    final report = entry.report;
    final shown = trail.shownStatus;
    final asksReopen = report != null &&
        report.status!.warns &&
        (identical(report, shown.confirmed) || identical(report, shown.unconfirmed));
    final body = switch ((mine, note.photo != null)) {
      (true, false) => l.noteDeleteBody(note.body),
      (true, true) => l.noteDeleteBodyPhoto(note.body),
      (false, false) => l.noteResolveBody(note.body, name),
      (false, true) => l.noteResolveBodyPhoto(note.body, name),
    };
    // null = abgebrochen, false = nur den Text, true = auch „wieder offen".
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(mine ? l.noteDeleteTitle : l.noteResolveTitle),
        content: Text(asksReopen ? '$body\n\n${l.reportResolveReopenQuestion}' : body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.commonCancel),
          ),
          if (asksReopen) ...[
            TextButton(
              key: const ValueKey('resolve-text-only'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.reportResolveTextOnly),
            ),
            FilledButton(
              key: const ValueKey('resolve-reopen'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l.reportResolveReopen),
            ),
          ] else
            FilledButton(
              key: const ValueKey('resolve-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(mine ? l.commonDelete : l.noteRemove),
            ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(trailsProvider.notifier);
    try {
      final fresh = await notifier.deleteNote(note.id);
      if (!choice) {
        messenger.showSnackBar(SnackBar(content: Text(doneOrStale(l, l.noteRemoved, fresh: fresh))));
        return;
      }
      // Bestätigt nach der üblichen Regel: gefahren — „vor Ort" fragt hier
      // niemand, die Frage galt dem Text.
      final outcome = await notifier.report(trail.id, status: TrailStatus.open, onSite: false);
      messenger.showSnackBar(SnackBar(
          content: Text(switch (outcome) {
        WriteOutcome.done => l.reportReopened,
        WriteOutcome.doneStale => l.staleAfterWrite(l.reportReopened),
        WriteOutcome.queued => l.queuedHint,
      })));
    } catch (e, st) {
      logError('Text entfernen', e, st);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    }
  }
}

/// Der Satz neben dem angehängten Foto: wer es sieht, wie lange, und was
/// nicht darin steht — und was trotzdem bleibt.
String notePhotoNote(AppLocalizations l, {required bool private}) =>
    private ? l.notePhotoPrivate(kNotePhotoDays) : l.notePhotoShared(kNotePhotoDays);

/// Die Vorschau am Hinweis (#37): lädt nur die 200er Fassung, das Bild
/// erst auf Tipp. Kann sie nicht laden (kein Netz, schon abgeräumt), steht
/// ein stilles Symbol da — der Hinweis selbst ist das Wichtige.
class NotePhotoThumb extends ConsumerWidget {
  const NotePhotoThumb({super.key, required this.photo, required this.note});
  final NotePhoto photo;
  final TrailNote note;

  static const size = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bytes = ref.watch(notePhotoThumbProvider(photo.thumbPath));
    final placeholder = Container(
      width: size,
      height: size,
      color: theme.colorScheme.surfaceContainer,
      alignment: Alignment.center,
      child: bytes.isLoading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.image_not_supported_outlined, color: theme.colorScheme.onSurfaceVariant),
    );
    return Semantics(
      button: true,
      label: context.l10n.notePhotoOpen,
      child: InkWell(
        key: ValueKey('note-photo-${note.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => showNotePhoto(context, photo: photo, note: note),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: switch (bytes) {
            AsyncData(:final value) =>
              Image.memory(value, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
            _ => placeholder,
          },
        ),
      ),
    );
  }
}

/// Das volle Bild über dem Blatt; schließt mit X, Zurück oder Tipp daneben.
Future<void> showNotePhoto(BuildContext context, {required NotePhoto photo, required TrailNote note}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _NotePhotoView(photo: photo, note: note),
  );
}

class _NotePhotoView extends ConsumerWidget {
  const _NotePhotoView({required this.photo, required this.note});
  final NotePhoto photo;
  final TrailNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final full = ref.watch(notePhotoFullProvider(photo.fullPath));
    // Solange das große Bild lädt, steht die Vorschau da (sie liegt schon
    // im Speicher) — kein leerer Rahmen.
    final thumb = ref.watch(notePhotoThumbProvider(photo.thumbPath)).valueOrNull;
    final shown = full.valueOrNull ?? thumb;
    return Dialog(
      key: const ValueKey('note-photo-view'),
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Das X in einer eigenen Zeile, nicht über dem Bild: Solange das
          // Bild noch dekodiert, ist es 0 hoch, und ein überlagertes X läge
          // unter dem Text (im Test gefunden: der Tipp ging daneben).
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: context.l10n.commonClose,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          // Flexible: Das Bild nimmt, was neben Kopf und Text bleibt — ein
          // Querformat-Bild auf einem kleinen Schirm schöbe sonst den Text
          // aus dem Dialog.
          Flexible(
            child: shown != null
                ? InteractiveViewer(
                    child: Image.memory(shown,
                        fit: BoxFit.contain, gaplessPlayback: true, semanticLabel: context.l10n.notePhotoLabel),
                  )
                : const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
          ),
          if (full.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(context.l10n.notePhotoFullFailed(friendlyError(context.l10n, full.error!)),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(note.body),
          ),
        ],
      ),
    );
  }
}
