// „Foto anhängen" für den Hinweis-Dialog (#37). Aus PilzBuddy übernommen
// (`lib/core/widgets/photo_attachment.dart`, #525/#532), ohne die
// Mehrfachauswahl — am Hinweis gibt es EIN Foto.
//
// Holen und entkernen passieren HIER, beim Anhängen, nicht erst beim
// Speichern: Ein Bild, das die Pipeline nicht lesen kann, soll sofort
// sagen, warum — und die Vorschau zeigt das Ergebnis, nicht das
// Original. Was der Dialog zurückgibt, ist ein [PreparedPhoto]; einen
// Weg mit rohen Bytes gibt es nicht.
import 'package:flutter/material.dart';

import '../errors.dart';
import '../photo_pipeline.dart';
import '../photo_providers.dart';

const kAttachPhotoKey = Key('attach-photo');
const kAttachPhotoCameraKey = Key('attach-photo-camera');
const kRemovePhotoKey = Key('remove-photo');

class PhotoAttachment extends StatefulWidget {
  const PhotoAttachment({
    super.key,
    required this.pick,
    required this.prepare,
    required this.photo,
    required this.onChanged,
    required this.attachedNote,
    this.label = 'Foto anhängen',
  });

  final PhotoPicker pick;
  final PhotoPreparer prepare;
  final PreparedPhoto? photo;
  final ValueChanged<PreparedPhoto?> onChanged;

  /// Die Beschriftung des Knopfs.
  final String label;

  /// Der Satz neben der Vorschau: wer das Bild sieht und was nicht darin
  /// steht. Er hängt am Zweck, deshalb gibt ihn der Aufrufer.
  final String attachedNote;

  @override
  State<PhotoAttachment> createState() => _PhotoAttachmentState();
}

class _PhotoAttachmentState extends State<PhotoAttachment> {
  bool _busy = false;

  Future<void> _pick(PhotoSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await widget.pick(source);
      if (bytes == null) return; // abgebrochen
      final prepared = await widget.prepare(bytes);
      if (mounted) widget.onChanged(prepared);
    } catch (e, s) {
      // Ein unlesbares Format ist kein Fehler der App — der Satz an den
      // Nutzer reicht. Alles andere (auch ein Bild, das wider Erwarten
      // noch Metadaten trägt) soll im Digest auftauchen.
      if (!(e is PhotoPipelineException && e.message.contains('Bildformat'))) {
        logError('Foto anhängen', e, s);
      }
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = widget.photo;
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Foto wird vorbereitet …'),
        ]),
      );
    }
    if (photo == null) {
      return Row(children: [
        // Nachgeben darf nur die Beschriftung: Im Dialog auf 360 dp bleibt
        // neben der Kamera wenig Platz (PilzBuddy #596).
        Flexible(
          child: OutlinedButton.icon(
            key: kAttachPhotoKey,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text(widget.label, overflow: TextOverflow.ellipsis),
            onPressed: () => _pick(PhotoSource.gallery),
          ),
        ),
        IconButton(
          key: kAttachPhotoCameraKey,
          tooltip: 'Foto aufnehmen',
          icon: const Icon(Icons.photo_camera_outlined),
          onPressed: () => _pick(PhotoSource.camera),
        ),
      ]);
    }
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(photo.thumb,
            width: 56, height: 56, fit: BoxFit.cover, semanticLabel: 'Angehängtes Foto'),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(widget.attachedNote, style: theme.textTheme.bodySmall)),
      IconButton(
        key: kRemovePhotoKey,
        tooltip: 'Foto entfernen',
        icon: const Icon(Icons.close),
        onPressed: () => widget.onChanged(null),
      ),
    ]);
  }
}
