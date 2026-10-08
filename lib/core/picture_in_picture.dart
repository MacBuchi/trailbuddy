// Bild-im-Bild in der Navigation (#232, Konzept-Routing 9.6): Wischt man
// nach Hause, während eine Navigation läuft, schrumpft die App in ein
// schwebendes Fenster — Android Picture-in-Picture, kein
// `SYSTEM_ALERT_WINDOW` (Sonderfreigabe, die Play nur eng gewährt). Ein
// Methodenkanal in `MainActivity`, kein Paket. Im Web und unter
// Android 8 gibt es das nicht; dann ist die Benachrichtigung alles.
//
// Dieselbe Bauweise wie `screen_awake.dart`: Der Web-Weg ist die Vorgabe,
// `dart.library.io` wählt den Kanal.
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'picture_in_picture_web.dart' if (dart.library.io) 'picture_in_picture_io.dart';

abstract interface class PictureInPicture {
  /// Darf die App beim Verlassen ins Fenster? Nur, solange eine
  /// Navigation läuft. Aus heißt auch: Ist sie gerade klein, geht das
  /// Fenster zu (die Navigation ist vorbei, die kleine Karte zeigte
  /// nichts mehr).
  Future<void> allow(bool on);

  /// Die Rückrichtung: [onMode] beim Wechsel zwischen groß und klein,
  /// [onStop] beim Tipp auf „Beenden" im Fenster.
  void listen({required void Function(bool inPip) onMode, required VoidCallback onStop});
}

/// Tests ersetzen ihn — im Harness gibt es keinen Kanal.
final pictureInPictureProvider = Provider<PictureInPicture>((ref) => createPictureInPicture());

/// Ist die App gerade das kleine Fenster? Dann baut die Karte die
/// schmale Fassung der Folgeansicht und die Hülle keine Reiterleiste.
final pipModeProvider = StateProvider<bool>((ref) => false);
