import '../l10n/l10n.dart';

/// Mindestlänge des Benutzernamens — EINE Quelle für Registrierung und
/// „Benutzername ändern" (Muster `minPasswordLength`).
const minUsernameLength = 3;

/// Was am Benutzernamen nicht stimmt — `null`, wenn er in Ordnung ist.
///
/// EINE Prüfung für beide Eingabestellen (Registrierung und
/// „Benutzername ändern"), aus demselben Grund wie [minUsernameLength]:
/// Zwei Kopien wären zwei Antworten auf dieselbe Frage, und die zweite
/// bräche still.
///
/// **Warum die Mailadresse auffallen muss** (Lehre aus PilzBuddy #352):
/// Der Benutzername ist öffentlich. Er steht in Buddy-Listen, an
/// geteilten Trails und in den Treffern von `search_profiles`. Wer bei
/// der Registrierung aus Versehen seine Adresse einträgt — und das
/// passiert, weil das Mail-Feld direkt daneben liegt —, veröffentlicht
/// sie damit. Die Buddy-Suche baut gerade darauf, dass das NICHT
/// passiert: Sie findet über die exakte Adresse, und das ist nur so lange
/// kein Verzeichnis, wie die Adressen nicht ohnehin dastehen.
///
/// **Bewusst grob geprüft.** Erkannt wird „etwas @ etwas . etwas" ohne
/// Leerzeichen, mehr nicht. Ein strenger Mail-Prüfausdruck wäre hier der
/// falsche Ehrgeiz: Die Prüfung soll keine Adressen validieren, sondern
/// einen Vertipper abfangen — und alles, was wie eine Adresse AUSSIEHT,
/// ist als öffentlicher Anzeigename ohnehin eine schlechte Wahl. Der
/// Fehler in die andere Richtung (ein @ im Namen, das keine Adresse ist)
/// kostet einen anderen Namen, nicht ein preisgegebenes Postfach.
String? usernameProblem(AppLocalizations l, String username) {
  final name = username.trim();
  if (name.length < minUsernameLength) return l.usernameTooShort(minUsernameLength);
  if (_emailShaped.hasMatch(name)) return l.usernameLooksLikeEmail;
  return null;
}

final _emailShaped = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Ist das der Name, den der Trigger `handle_new_user` vergibt, wenn die
/// Anmeldung keinen mitbringt — bei Google & Co. immer (#398, #422)?
bool isAssignedUsername(String username) => _assignedUsername.hasMatch(username);

final _assignedUsername = RegExp(r'^trailbuddy_[0-9a-f]{8}$');

/// Das eigene Profil (`public.profiles`).
class Profile {
  final String id;
  final String username;

  /// Optionaler Anzeigename — steht in der Buddy-Suche unter dem
  /// Benutzernamen; im eigenen Profil bisher nicht bearbeitbar.
  final String? displayName;

  /// Index in einen künftigen Avatar-Katalog. Heute zeigt die App den
  /// ersten Buchstaben des Namens (`LetterAvatar`); die Spalte bleibt,
  /// damit ein Katalog später keinen Schema-Patch braucht.
  final int avatar;

  const Profile({
    required this.id,
    required this.username,
    this.displayName,
    this.avatar = 0,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        avatar: json['avatar'] as int? ?? 0,
      );
}
