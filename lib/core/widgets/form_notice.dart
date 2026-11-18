import 'package:flutter/material.dart';

/// Tonfall einer Formular-Rückmeldung.
enum NoticeTone { info, success, error }

/// Hinweisfläche unter einem Formular.
///
/// Vorher war das ein nacktes `Text` — „Der Code ist unterwegs" und „Der Code
/// ist falsch" sahen identisch aus. Farbe und Symbol kommen aus dem
/// `ColorScheme`, damit hier keine neuen Hex-Literale entstehen.
class FormNotice extends StatelessWidget {
  const FormNotice({super.key, required this.message, required this.tone});

  final String message;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (tone) {
      NoticeTone.success => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.mark_email_read_outlined,
      ),
      NoticeTone.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      NoticeTone.info => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.info_outline,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
