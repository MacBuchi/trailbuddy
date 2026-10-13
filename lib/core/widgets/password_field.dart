import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Mindestlänge, die die App selbst verlangt — an EINER Stelle, weil sie
/// vorher an dreien stand: Registrierung 6, Reset 8, und der Ändern-Dialog
/// wäre die vierte Meinung geworden. Supabase erlaubt serverseitig weniger;
/// strenger als der Server zu sein ist unkritisch, uneinheitlich zu sein
/// nicht.
const minPasswordLength = 8;

/// Passwortfeld mit Auge zum Sichtbarmachen.
///
/// Bewusst ein eigenes Widget statt vier Kopien: Anmeldung, Registrierung,
/// Passwort-Reset und der Ändern-Dialog im Profil brauchen dasselbe. Innen
/// bleibt es ein gewöhnliches `TextField` mit `labelText` — Tests finden die
/// Felder weiterhin über `find.widgetWithText(TextField, '<Label>')`.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.autofillHints,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      autofocus: widget.autofocus,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(_hidden
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined),
          tooltip: _hidden ? context.l10n.passwordShow : context.l10n.passwordHide,
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

/// Live-Rückmeldung, ob neues Passwort und Wiederholung übereinstimmen
///. Bewusst eine eigene Zeile unter dem Wiederholungsfeld und
/// kein zweites Suffix-Icon: neben dem Auge wird es eng, und Text lässt sich
/// vorlesen und prüfen.
///
/// Solange noch nichts wiederholt wurde, bleibt die Zeile leer — während des
/// Tippens ist Ungleichheit der Normalfall und keine Fehlermeldung wert.
class PasswordMatchHint extends StatelessWidget {
  const PasswordMatchHint({
    super.key,
    required this.password,
    required this.repeated,
  });

  final String password;
  final String repeated;

  @override
  Widget build(BuildContext context) {
    if (repeated.isEmpty) return const SizedBox.shrink();
    final matches = password == repeated;
    final scheme = Theme.of(context).colorScheme;
    final color = matches ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            matches ? Icons.check_circle_outline : Icons.info_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              matches
                  ? context.l10n.passwordsMatch
                  : context.l10n.passwordsDontMatch,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
