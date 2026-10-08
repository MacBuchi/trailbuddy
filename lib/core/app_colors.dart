import 'package:flutter/material.dart';

/// Design-Tokens der TrailBuddy-Palette — DIE eine Quelle für die
/// wiederkehrenden Töne, hell und dunkel. Neue Farben gehören hierher,
/// nicht als Hex-Literal in ein Widget (bekannte Schuld aus PilzBuddy,
/// dort nie ganz aufgeräumt — hier von Anfang an so).
///
/// Widgets lesen die Palette des aktuellen Modus über
/// [AppPalette.of]; nur was nicht vom Modus abhängt, steht hier als
/// Konstante.
abstract final class AppColors {
  /// Die Markenfarbe: Lime. In beiden Modi derselbe Knopf — Lime mit
  /// dunkler Schrift ([onBrand]). Als Textfarbe auf Hell taugt sie
  /// nicht (1,35:1), dort gilt [AppPalette.accentText].
  static const brand = Color(0xFFB6F04A);

  /// Schrift und Symbole auf [brand].
  static const onBrand = Color(0xFF0E1411);

  /// Flächen der Buchstaben-Avatare anderer (Design 1k), in beiden Modi
  /// dieselben, Buchstabe immer [onBrand] (≥ 7:1 auf jeder). Lime fehlt
  /// mit Absicht: Lime heißt „mein".
  static const avatarFills = [
    Color(0xFF5AD0F0),
    Color(0xFFFFD23F),
    Color(0xFFFF6BA8),
    Color(0xFFB58CFF),
  ];

  /// Der Landton der Karte, wo (noch) keine Kachel liegt — derselbe Wert
  /// wie die `earth`-Fläche des erzeugten Kartenstils, damit die Fläche
  /// nach „Karte lädt" aussieht und nicht nach „kaputt". Beide Engines
  /// lesen ihn (flutter_map als `backgroundColor`, MapLibre als
  /// background-Ebene im Style).
  static const mapBackground = Color(0xFFE2DFDA);

  /// Die Höhenlinien (#271) — kühles Graublau gegen die warme Karte, aus
  /// PilzBuddy übernommen: Die Wege sind Braun (Design 5a), die Trails
  /// tragen die Pistenfarben; ein Braun hier hieße „Pfad", ein Blau „S1".
  /// Dezent wird es über Deckkraft und Breite (`contour_layer.dart`),
  /// nicht über eine blassere Farbe — die verschwände auf Waldgrün.
  static const contourLine = Color(0xFF5B6B7A);

  /// Die Zahlen an den Hauptlinien, mit weißem Hof.
  static const contourLabel = Color(0xFF44515C);

  /// Die Linienfarben AUF DER KARTE. Die Karte ist (noch) immer der
  /// helle Protomaps-Stil, auch im dunklen Modus der App — deshalb gilt
  /// dort der helle Satz samt weißem Saum, nicht der des App-Modus: Lime
  /// auf hellem Kartengrund ginge unter. Kommt ein dunkler Kartenstil,
  /// wählt man hier nach dessen Helligkeit.
  static const mapLines = MapPalette.light;

  /// Die Schwierigkeitsfarben AUF DER KARTE — aus demselben Grund wie
  /// [mapLines] immer der helle Satz.
  static const mapGrades = GradePalette.light;

  static const dark = AppPalette(
    brightness: Brightness.dark,
    ground: Color(0xFF0E1411),
    surface: Color(0xFF161E19),
    surface2: Color(0xFF1F2923),
    line: Color(0xFF2A3630),
    text: Color(0xFFF2F4EF),
    muted: Color(0xFF9AA69D),
    accentText: brand,
    brandMark: brand,
    warningText: Color(0xFFFF8A3D),
    buddyText: Color(0xFF5AD0F0),
    noteText: Color(0xFFFFD23F),
    map: MapPalette.dark,
    grade: GradePalette.dark,
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    ground: Color(0xFFF3F2EC),
    surface: Color(0xFFFFFFFF),
    // Im Entwurf nicht genannt: eine Stufe zwischen Fläche und Linie.
    surface2: Color(0xFFECEBE4),
    line: Color(0xFFE4E3DB),
    text: Color(0xFF131A16),
    muted: Color(0xFF5E6B62),
    // Die Linienfarben (#4F8A10 & Co.) reichen als Linie und Symbol
    // (≥ 3:1), als Text nicht (4,2:1) — dafür je eine dunklere Stufe,
    // ≥ 4,8:1 auf Grund und Fläche (`test/core/app_theme_test.dart`).
    accentText: Color(0xFF3D6E0B),
    // „Marke auf Hell" (Design 1a): das Logo und große Flächen der Marke.
    brandMark: Color(0xFF4F8A10),
    warningText: Color(0xFFA94510),
    buddyText: Color(0xFF0A7299),
    // Das Hinweis-Gelb (#F2B600) hat auf Weiß 1,9:1 — als Wort in der
    // Liste („NEUER HINWEIS") ein dunkles Senfgelb, ≥ 5,2:1.
    noteText: Color(0xFF7A5C00),
    map: MapPalette.light,
    grade: GradePalette.light,
  );
}

/// Die Farben eines Modus. Hängt als [ThemeExtension] am Theme.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.ground,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.muted,
    required this.accentText,
    required this.brandMark,
    required this.warningText,
    required this.buddyText,
    required this.noteText,
    required this.map,
    required this.grade,
  });

  final Brightness brightness;

  /// Der Grund hinter allem (Scaffold, Reiterleiste).
  final Color ground;

  /// Karten, Blätter, Dialoge.
  final Color surface;

  /// Eine Stufe darüber: Kacheln im Blatt, gewählte Chips.
  final Color surface2;

  /// Rahmen und Trenner.
  final Color line;

  final Color text;

  /// Nebentext.
  final Color muted;

  /// Die Marke als Schrift: Lime im Dunkeln, ein dunkles Grün im Hellen.
  final Color accentText;

  /// Die Marke als ZEICHEN (Logo, große Formen): Lime im Dunkeln,
  /// Moosgrün #4F8A10 im Hellen — als Fläche reicht 3:1, als Text nicht.
  final Color brandMark;

  /// Warnung als Schrift.
  final Color warningText;

  /// „Von einem Buddy" als Schrift.
  final Color buddyText;

  /// „Neuer Hinweis" als Schrift (die Linie trägt nur den Leuchtrand).
  final Color noteText;

  /// Die Beziehungsfarben dieses Modus — für Symbole, Streifen und Chips
  /// auf den Flächen der App. Auf der Karte gilt [AppColors.mapLines].
  final MapPalette map;

  /// Die Schwierigkeitsfarben dieses Modus — Streifen und Schild. Auf der
  /// Karte gilt [AppColors.mapGrades].
  final GradePalette grade;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? AppColors.light;

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(AppPalette? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// Die übrigen Farben der Karte. Seit 0.42.0 trägt die LINIE eines
/// Trails seine Schwierigkeit ([GradePalette], Betreiber 2026-09-29);
/// [mine] und [buddy] sind keine Linienfarben mehr, sondern bleiben für
/// Symbole und Vorschauen (Zerlege-Blatt: „bekannt"). [warning] und
/// [note] liegen als Leuchtrand UM die Linie. Was kein Trail des Netzes
/// ist (offiziell, Kandidat, Fahrt), trägt keine Schwierigkeitsfarbe.
@immutable
class MapPalette {
  const MapPalette({
    required this.mine,
    required this.buddy,
    required this.warning,
    required this.note,
    required this.official,
    required this.candidate,
    required this.ride,
    required this.halo,
  });

  /// Mein Trail (ich habe ihn beigesteuert).
  final Color mine;

  /// Nur von Buddys.
  final Color buddy;

  /// Ein Buddy hat ihn gemeldet (Status warnt).
  final Color warning;

  /// „Hier gibt es etwas Neues von einem Buddy" (#7) — NUR als
  /// Leuchtrand um die Linie und als Tönung der Zeile, nie die Linie
  /// selbst.
  final Color note;

  /// Offizielle Trails (#13), gestrichelt. Gesperrte Teile grau, nicht
  /// orange: Orange ist die Meldung eines Buddys.
  final Color official;

  /// Ein Kandidat im Zerlege-Blatt (#29): ein Stück der Fahrt, das noch
  /// kein Trail ist — eine Frage.
  final Color candidate;

  /// Die eigene Fahrt und der Positionspunkt (#28): „das bin ich,
  /// gerade jetzt". Nicht Blau — Blau heißt „von einem Buddy".
  final Color ride;

  /// Der Saum um jede Linie (je Seite 2, zusammen Breite + 4), damit sie
  /// sich vom hellen Kartengrund löst; null = kein Saum.
  final Color? halo;

  /// Breite des Saums je Seite.
  static const haloWidth = 2.0;

  /// [haloWidth], wenn es einen Saum gibt, sonst 0 — für
  /// `MapViewPolyline.borderWidth`.
  double get haloBorderWidth => halo == null ? 0 : haloWidth;

  static const dark = MapPalette(
    mine: Color(0xFFB6F04A),
    buddy: Color(0xFF5AD0F0),
    warning: Color(0xFFFF8A3D),
    note: Color(0xFFFFD23F),
    official: Color(0xFFB58CFF),
    candidate: Color(0xFFFF6BA8),
    ride: Color(0xFFE8ECE6),
    halo: null,
  );

  static const light = MapPalette(
    mine: Color(0xFF4F8A10),
    buddy: Color(0xFF0B84B0),
    warning: Color(0xFFD9591A),
    note: Color(0xFFF2B600),
    official: Color(0xFF7B4FD6),
    candidate: Color(0xFFD1336F),
    ride: Color(0xFF2A332E),
    halo: Color(0xFFFFFFFF),
  );
}


/// Die Farbe eines Trails ist seine Schwierigkeit (Betreiber,
/// 2026-09-29: „nicht nach Buddy / mein Trail, sondern nach den
/// Schwierigkeitsstufen"). Pistenfarben wie im Skigebiet: S0 grün,
/// S1 blau, S2 rot, ab S3 schwarz; ohne Einschätzung grau. Ob ein Trail
/// meiner ist, sagt seither nur noch das Wort („MEIN", Namen).
///
/// Zwei Sätze, weil „schwarz" auf dunklem Grund verschwände: Im Dunklen
/// sind die Farben heller und S3+ ist die Textfarbe. [ink] ist die
/// Schrift auf der Farbe (das Schild), ≥ 4,5:1 auf jeder Stufe; jede
/// Stufe hat ≥ 3:1 auf der Fläche (`test/core/app_theme_test.dart`).
/// Die Töne des Entwurfs (#2E9E4F, #D6322F) sind dafür nachgedunkelt.
@immutable
class GradePalette {
  const GradePalette({
    required this.s0,
    required this.s1,
    required this.s2,
    required this.s3,
    required this.ungraded,
    required this.uphill,
    required this.ink,
  });

  final Color s0;
  final Color s1;
  final Color s2;

  /// S3 bis S5 — ab S4 zusätzlich gestrichelt auf der Karte.
  final Color s3;

  /// Noch niemand hat den Trail eingeschätzt.
  final Color ungraded;

  /// Uphill (Betreiber, 2026-09-29: „hier macht Symbol und Farbe Sinn"):
  /// Die Pistenfarben beschreiben eine Abfahrt — bergauf gefahren sagt
  /// „rot" wenig. Ein Trail, dessen angezeigter Charakter Uphill ist,
  /// trägt deshalb Magenta statt seiner Stufe, das Schild einen Pfeil
  /// statt der Form. Magenta seit 0.77.2 (#195, Betreiber): Das Petrol
  /// davor war auf der Karte kaum von S0-Grün zu unterscheiden. Violett
  /// heißt „offiziell"; das Rosa der Kandidaten liegt nah, steht aber
  /// nur in der Vorschau des Zerlege-Blatts.
  final Color uphill;

  /// Schrift und Form auf einer Stufenfarbe.
  final Color ink;

  Color of(int? grade) => switch (grade) {
        null => ungraded,
        0 => s0,
        1 => s1,
        2 => s2,
        _ => s3,
      };

  static const light = GradePalette(
    s0: Color(0xFF1F7A3A),
    s1: Color(0xFF1F6FD1),
    s2: Color(0xFFC62828),
    s3: Color(0xFF131A16),
    ungraded: Color(0xFF6B756F),
    uphill: Color(0xFFB0279C),
    ink: Color(0xFFFFFFFF),
  );

  static const dark = GradePalette(
    s0: Color(0xFF4CC46E),
    s1: Color(0xFF5A9BF0),
    s2: Color(0xFFF0605C),
    s3: Color(0xFFF2F4EF),
    ungraded: Color(0xFF9AA69D),
    uphill: Color(0xFFE060D0),
    ink: Color(0xFF0E1411),
  );
}
