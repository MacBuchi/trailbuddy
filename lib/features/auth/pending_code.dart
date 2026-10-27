import 'dart:async';
import 'dart:convert';

import '../../core/errors.dart';
import '../../core/settings.dart';

/// Wofür ein Code unterwegs ist.
enum PendingCodeKind { reset, signup }

/// Ein Code, der per Mail unterwegs ist (#399): Art, Adresse, wann
/// angefordert.
///
/// Chrome räumt Tabs im Hintergrund („Memory Saver") und lädt sie beim
/// Zurückkommen neu — genau dann, wenn man im Postfach war. Ohne Merker
/// stand danach das leere Anmeldeformular da, und der Code aus der Mail
/// ließ sich nirgends mehr eingeben. Gemerkt wird nur, was die Ansicht
/// braucht; Passwörter bleiben, wo sie sind (im Feld, also weg).
class PendingCode {
  const PendingCode(this.kind, this.email, this.requestedAt);

  final PendingCodeKind kind;
  final String email;
  final DateTime requestedAt;

  /// So lange gilt ein Code bei GoTrue (Vorgabe `otp_expiry` 3600 s).
  /// Danach führt ein Neuladen wieder aufs leere Formular — ein Feld für
  /// einen abgelaufenen Code wäre eine Sackgasse.
  static const lifetime = Duration(hours: 1);

  String encode() => jsonEncode({
        'kind': kind.name,
        'email': email,
        'at': requestedAt.toUtc().toIso8601String(),
      });

  /// Liest den Merker, oder null, wenn keiner da, er unlesbar oder
  /// abgelaufen ist.
  static PendingCode? decode(String? raw, {required DateTime now}) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final kind = PendingCodeKind.values.byName(json['kind'] as String);
      final email = json['email'] as String;
      final at = DateTime.parse(json['at'] as String);
      if (email.isEmpty || now.difference(at) > lifetime) return null;
      return PendingCode(kind, email, at);
    } catch (_) {
      // Ein kaputter Merker ist kein Fehler: dann eben das leere Formular.
      return null;
    }
  }

  /// Der Merker für [kind], sonst null — ein Reset-Code öffnet nicht die
  /// Registrierung und umgekehrt.
  static PendingCode? read(Settings settings, PendingCodeKind kind, {DateTime? now}) {
    final code = decode(settings.pendingAuthCode, now: now ?? DateTime.now());
    return code?.kind == kind ? code : null;
  }

  /// Merken und Vergessen laufen nach und werfen nie: Ein Merker, der
  /// sich nicht schreiben lässt, darf die Anmeldung nicht aufhalten.
  static void remember(Settings settings, PendingCodeKind kind, String email) =>
      _write(settings, PendingCode(kind, email, DateTime.now()).encode());

  /// Vergisst nur einen Merker der Art [kind]: Der Login-Screen, der
  /// beim Wechsel zur Registrierung verschwindet, darf deren Code nicht
  /// mitnehmen.
  static void forget(Settings settings, PendingCodeKind kind) {
    final raw = settings.pendingAuthCode;
    if (raw == null) return;
    final code = decode(raw, now: DateTime.now());
    if (code != null && code.kind != kind) return;
    _write(settings, null);
  }

  static void _write(Settings settings, String? value) => unawaited(settings
      .setPendingAuthCode(value)
      .catchError((Object e, StackTrace s) => logError('Code-Merker schreiben', e, s)));
}
