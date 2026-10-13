import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// „Erneut senden" mit Wartezeit — für die Bestätigungsmail bei der
/// Registrierung und den Code beim Passwort-Reset.
///
/// Der Knopf startet **gesperrt**: An beiden Stellen ist gerade eben eine
/// Mail rausgegangen, und GoTrue lehnt eine zweite an dieselbe Adresse rund
/// eine Minute lang ab. Ohne den Countdown bestätigt die App einen Versand,
/// den es nie gab — beim Warten auf eine Mail genau die falsche Auskunft.
/// Die sichtbare Restzeit beantwortet außerdem die Frage, die man in dem
/// Moment wirklich hat: noch warten oder ins Spam-Verzeichnis schauen?
class ResendButton extends StatefulWidget {
  const ResendButton({
    super.key,
    required this.onResend,
    required this.label,
    this.enabled = true,
    this.cooldown = const Duration(seconds: 60),
  });

  /// Verschickt die Mail erneut. Danach läuft die Wartezeit von vorn.
  final Future<void> Function() onResend;

  /// Beschriftung im Ruhezustand, z. B. „Mail nicht angekommen? Erneut
  /// senden".
  final String label;

  /// Zusätzliche Sperre von außen (läuft gerade eine andere Anfrage?).
  final bool enabled;

  final Duration cooldown;

  @override
  State<ResendButton> createState() => _ResendButtonState();
}

class _ResendButtonState extends State<ResendButton> {
  Timer? _timer;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    _remaining = widget.cooldown.inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    // Die Wartezeit sofort neu starten, nicht erst nach der Antwort: Sonst
    // öffnet ein langsamer Server ein Fenster für den zweiten Tap.
    setState(_startCooldown);
    await widget.onResend();
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _remaining > 0;
    return TextButton(
      onPressed: (waiting || !widget.enabled) ? null : _resend,
      child: Text(waiting ? context.l10n.resendIn(_remaining) : widget.label),
    );
  }
}
