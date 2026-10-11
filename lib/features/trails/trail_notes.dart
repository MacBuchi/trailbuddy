import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../core/photo_pipeline.dart';
import '../../core/photo_providers.dart';
import '../../core/read_after_write.dart';
import '../../core/widgets/photo_attachment.dart';
import '../../models/trail.dart';
import 'trail_providers.dart';
import 'trail_sheet.dart';

/// Hinweise zu einem Trail für Buddys (Issue #7): „Baum liegt quer nach
/// der zweiten Kehre". Kein Feedback an den Betreiber — das bleibt die
/// Glühbirne —, sondern eine Nachricht an meine Buddys, die den Trail
/// sehen. Schreiben darf jeder, der den Trail sieht; entfernen jeder, der
/// den Hinweis sieht (wer am Trail steht, sagt „erledigt"); bearbeiten
/// niemand: Das Alter soll stimmen.

/// Höchstlänge eines Hinweises, dieselbe wie im Check der Tabelle.
const kNoteMaxLength = 500;

/// So lange bleibt ein Foto am Hinweis (#37) — die Frist steht als Default
/// und Constraint in Patch 026, hier nur für den Satz im Dialog.
const kNotePhotoDays = 90;

/// Der Abschnitt im Trail-Blatt: die Hinweise, neueste zuerst, und der
/// Knopf zum Schreiben. [seenBefore] sind die Hinweise, die schon VOR dem
/// Öffnen gesehen waren — was jetzt neu ist, bleibt im Blatt getönt, auch
/// wenn es beim Öffnen als gesehen gemerkt wird.
class TrailNotesSection extends ConsumerWidget {
  const TrailNotesSection(
      {super.key, required this.trail, this.seenBefore = const {}, this.showAdd = true});
  final Trail trail;
  final Set<String> seenBefore;

  /// Der Knopf „Hinweis schreiben" in der Überschrift — das Trail-Blatt
  /// stellt ihn seit 0.39.0 (Design 1i) unten als Hauptaktion hin.
  final bool showAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = trail.notesShown();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Hinweise', style: theme.textTheme.titleSmall),
            const Spacer(),
            if (showAdd)
              TextButton.icon(
                key: const ValueKey('add-note'),
                onPressed: () => addTrailNote(context, ref, trail),
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Hinweis schreiben'),
              ),
          ],
        ),
        if (notes.isEmpty)
          Text('Noch keine. Ein Baum quer, ein neuer Drop? Deine Buddys sehen es hier.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        for (final n in notes)
          _NoteTile(
            note: n,
            mine: n.userId == trail.myId,
            fresh: trail.isFreshNote(n, seen: seenBefore),
          ),
      ],
    );
  }

}

/// Einen Hinweis schreiben: Dialog, speichern, Rückmeldung.
Future<void> addTrailNote(BuildContext context, WidgetRef ref, Trail trail) async {
  // Privat zählt nur, wenn ich selbst einen Beitrag habe — sonst gibt
  // es nichts, was ich verbergen könnte.
  final private = trail.myDetails?.visibility == TrailVisibility.private;
  final draft = await showNoteDialog(context, private: private);
  if (draft == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result =
        await ref.read(trailsProvider.notifier).addNote(trail.id, draft.body, photo: draft.photo);
    final stale = result.fresh ? '' : staleAfterWriteHint;
    final photoError = result.photoError;
    messenger.showSnackBar(SnackBar(
        content: Text(photoError != null
            // Beides sagen: Der Hinweis steht — sonst schriebe man ihn
            // ein zweites Mal —, das Foto nicht.
            ? 'Hinweis gespeichert, das Foto aber nicht: ${friendlyError(photoError)}'
            : draft.photo != null
                ? 'Hinweis mit Foto gespeichert$stale'
                : 'Hinweis gespeichert$stale')));
  } catch (e, st) {
    logError('Hinweis speichern', e, st);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({required this.note, required this.mine, required this.fresh});
  final TrailNote note;
  final bool mine;
  final bool fresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final who = mine ? 'Du' : (note.username ?? 'Buddy');
    return Container(
      key: ValueKey('note-${note.id}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      // Ein neuer Hinweis gelb umrandet (Design 1i) — der Rand, der auf
      // der Karte um die Linie leuchtet.
      decoration: BoxDecoration(
        color: fresh
            ? AppPalette.of(context).map.note.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        border: fresh ? Border.all(color: AppPalette.of(context).map.note, width: 1.5) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.body),
                const SizedBox(height: 2),
                Text('$who · ${statusAge(note.createdAt)}',
                    style: fresh
                        ? theme.textTheme.bodySmall?.copyWith(
                            color: AppPalette.of(context).noteText, fontWeight: FontWeight.w600)
                        : theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (note.shownPhoto() case final photo?)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: NotePhotoThumb(photo: photo, note: note),
            ),
          if (mine)
            IconButton(
              tooltip: 'Hinweis löschen',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref),
            )
          else
            IconButton(
              tooltip: 'Erledigt — Hinweis entfernen',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () => _delete(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(mine ? 'Hinweis löschen?' : 'Als erledigt entfernen?'),
        content: Text(mine
            ? '„${note.body}"${note.photo != null ? '\n\nDas Foto geht mit.' : ''}'
            : '„${note.body}"\n\nDer Hinweis verschwindet für alle, die ihn '
                'sehen — auch für ${note.username ?? 'deinen Buddy'}'
                '${note.photo != null ? ', samt Foto' : ''}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(mine ? 'Löschen' : 'Entfernen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fresh = await ref.read(trailsProvider.notifier).deleteNote(note.id);
      messenger.showSnackBar(SnackBar(
          content: Text('Hinweis entfernt${fresh ? '' : staleAfterWriteHint}')));
    } catch (e, st) {
      logError('Hinweis löschen', e, st);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

/// Wer den Hinweis sieht, in einem Satz — dieselbe Regel wie für den
/// Beitrag. Bei privatem Beitrag sagt er ehrlich, dass es niemand ist.
String noteAudience({required bool private}) => private
    ? 'Dein Beitrag steht auf „Nur für mich" — dann siehst nur du den Hinweis.'
    : 'Sehen deine Buddys, die diesen Trail auch sehen.';

/// Was der Dialog zurückgibt: der Text und, wenn angehängt, das schon
/// entkernte Foto (#37).
typedef NoteDraft = ({String body, PreparedPhoto? photo});

/// Der Satz neben dem angehängten Foto: wer es sieht, wie lange, und was
/// nicht darin steht — und was trotzdem bleibt.
String notePhotoNote({required bool private}) =>
    '${private ? 'Nur du siehst es' : 'Sehen dieselben wie den Hinweis'}, $kNotePhotoDays Tage lang. '
    'Ortsangaben im Bild werden entfernt — ein erkennbarer Ort bleibt erkennbar.';

/// Ein neuer Hinweis, oder null bei Abbruch.
Future<NoteDraft?> showNoteDialog(BuildContext context, {required bool private}) {
  return showDialog<NoteDraft>(
    context: context,
    builder: (_) => _NoteDialog(private: private),
  );
}

class _NoteDialog extends ConsumerStatefulWidget {
  const _NoteDialog({required this.private});
  final bool private;

  @override
  ConsumerState<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends ConsumerState<_NoteDialog> {
  final _text = TextEditingController();
  PreparedPhoto? _photo;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hinweis für Buddys'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('note-text'),
            controller: _text,
            autofocus: true,
            maxLines: 4,
            maxLength: kNoteMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'z. B. Baum liegt quer nach der zweiten Kehre',
            ),
            onChanged: (_) => setState(() {}),
          ),
          Text(noteAudience(private: widget.private),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          PhotoAttachment(
            pick: ref.read(photoPickerProvider),
            prepare: ref.read(photoPreparerProvider),
            photo: _photo,
            attachedNote: notePhotoNote(private: widget.private),
            onChanged: (photo) => setState(() => _photo = photo),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _text.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop((body: _text.text.trim(), photo: _photo)),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

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
      label: 'Foto zum Hinweis öffnen',
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
              tooltip: 'Schließen',
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
                        fit: BoxFit.contain, gaplessPlayback: true, semanticLabel: 'Foto zum Hinweis'),
                  )
                : const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
          ),
          if (full.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Das Bild in voller Größe lädt gerade nicht — ${friendlyError(full.error!)}',
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
