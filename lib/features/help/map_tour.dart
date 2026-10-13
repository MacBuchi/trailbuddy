// Die geführte Tour über die Karte (#132, Plan `docs/konzept-onboarding.md`
// 3.2 und 4.1; Vorlage PilzBuddys `map_tour.dart`, #350/#596).
//
// **Sie erklärt Wege und Zeichen, nicht Knöpfe allein.** PilzBuddys Karte
// ist selbst Inhalt; TrailBuddys ist am Anfang leer. Deshalb zeigt die
// Tour, was auf der Karte steht (Schild, Blatt, die Regeln der Linien),
// dann, was hinter den Knöpfen liegt — und sie FÜHRT VOR: Das Blatt
// „Kartenebenen" und die Leiste „Offline-Karten" gehen auf und wieder zu.
//
// **Sie blockiert nie.** „Überspringen" steht in jedem Schritt, und ein
// Tipp irgendwohin geht weiter. Was sie öffnet, schließt sie wieder, ohne
// dass etwas ausgelöst wird.
//
// Schritttitel dürfen nicht lauten wie etwas auf dem Schirm — ein Test
// fände sonst das Element statt der Blase (PilzBuddy, zweimal passiert).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../l10n/l10n.dart';
import '../coach/coach.dart';
import 'tour_intro_art.dart';

/// Die Leiste unten — die Karten-Tour nennt ihre Bereiche zum Schluss.
abstract final class NavCoach {
  static const bar = 'nav.bar';
  static const map = 'nav.map';
  static const trails = 'nav.trails';
  static const buddys = 'nav.buddys';
  static const profile = 'nav.profile';

  /// Je Reiter der `AppShell`, in dieser Reihenfolge.
  static const tabs = [map, trails, buddys, profile];
}

/// Die Anker der Karte — eine Stelle für die Kennungen, damit Skript und
/// Widgets dieselben Wörter benutzen.
abstract final class MapCoach {
  /// Die Knopfspalte rechts.
  static const buttons = 'map.buttons';
  /// Die Glühbirne, seit 0.75.0 oben rechts (#180) — nicht mehr in [buttons].
  static const feedback = 'map.feedback';

  /// Kartenebenen (#190): öffnet das Blatt [layersSheet].
  static const layers = 'map.layers';

  /// Offline-Karten: öffnet die Leiste [rail].
  static const offline = 'map.offline';
  static const locate = 'map.locate';

  /// Die Aufnahme — nur, wo man aufzeichnen kann (Android).
  static const record = 'map.record';

  /// Der Rundenplaner (#158 Schritt 5): der Knopf rechts.
  static const loop = 'map.loop';

  /// Die Leiste des Planers (seit 0.74.0) — Anker UND Szene (sie öffnet
  /// den Modus), und je Knopf `map.loopRail.<key>`.
  static const loopRail = 'map.loopRail';
  static String loopRailButton(String key) => 'map.loopRail.$key';

  /// Das Schild am Anfang des Trails, dessen Blatt die Tour öffnet.
  static const trailBadge = 'map.trailBadge';

  /// Die Startmarke desselben Trails (#96) — für den Schritt zur Richtung.
  static const trailStart = 'map.trailStart';

  /// Der leere Kartenzustand — da heißt: kein Trail, kein Blatt.
  static const empty = 'map.empty';

  /// Die Werkzeugleiste „Offline-Karten" — Anker UND Szene.
  static const rail = 'map.rail';

  /// Ein Knopf der Leiste, je `ValueKey` in `OfflineToolRail`.
  static String railButton(String key) => 'map.rail.$key';

  /// Der Stift der Leiste („Fläche dazunehmen") — `railButton('area-draw-add')`
  /// als Konstante, damit die Listen im Skript `const` bleiben.
  static const railDraw = 'map.rail.area-draw-add';

  /// Szene: das Blatt „Kartenebenen" (seit 0.75.0 direkt vom Knopf, #190;
  /// bis 0.74.x `map.rail/filter`, auf der Leiste).
  static const layersSheet = 'map.layersSheet';
  static const filterTrails = 'map.filter.trails';
  static const filterOfficial = 'map.filter.official';

  /// Der Schalter „Wege" (#212): Forstweg-Güte und Pfad-Schwierigkeit.
  static const filterWays = 'map.filter.ways';

  /// Der Schalter „Höhenlinien" (#271).
  static const filterContours = 'map.filter.contours';
  static const filterPois = 'map.filter.pois';

  /// Die Legende am linken Rand (#182) — Anker UND Szene (sie klappt sie
  /// auf und danach wieder zu, wenn sie zu war).
  static const legend = 'map.legend';

  /// Szene: das Blatt des Trails, dessen Schild [trailBadge] trägt.
  static const trailSheet = 'map.trailSheet';
}

/// Die Anker im Trail-Blatt. Das Blatt teilt sich die Karte mit der
/// Trails-Tour (#136), deshalb ein eigener Bereich.
abstract final class SheetCoach {
  static const metrics = 'sheet.metrics';
  static const grade = 'sheet.grade';
  static const ownGrade = 'sheet.ownGrade';
  static const contribution = 'sheet.contribution';
  static const addNote = 'sheet.addNote';
  static const report = 'sheet.report';
  static const showOnMap = 'sheet.showOnMap';

  /// „Anfahrt" — der Trailkopf an eine Navi-App (#151).
  static const navigate = 'sheet.navigate';

  /// „Zum Trailkopf" (#158 Schritt 4) — der Weg aus den eigenen Bereichen.
  static const trailHead = 'sheet.trailHead';

  /// „Als GPX exportieren" (#150).
  static const export = 'sheet.export';
}

/// Die Startseite beim ERSTEN Start (#133). Sie nennt die drei Wege, auf
/// denen Trails hierher kommen — die Karte ist am Anfang leer, anders als
/// bei PilzBuddy. „Nicht jetzt" fragt beim nächsten Start wieder.
CoachStep welcomeIntro(AppLocalizations l) => CoachStep(
      id: 'welcome',
      title: l.tourWelcomeTitle,
      text: l.tourWelcomeText,
      art: welcomeArt,
      startLabel: l.tourWelcomeStart,
    );

/// Die Startseite, wenn die Karten-Tour aus der Kurzanleitung kommt.
CoachStep mapIntro(AppLocalizations l) => CoachStep(
      id: 'map.intro',
      title: l.tourMapIntroTitle,
      text: l.tourMapIntroText,
      art: mapArt,
    );

/// Zum Schluss der Karten-Tour die Bereiche unten, je ein Halbsatz.
CoachStep navStep(AppLocalizations l) => CoachStep(
      id: 'map.nav',
      title: l.tourMapNavTitle,
      text: l.tourMapNavText,
      lit: const [NavCoach.bar],
      ring: const [NavCoach.trails, NavCoach.buddys, NavCoach.profile],
    );

/// Die Karten-Tour. Eine Funktion und keine Konstante, weil die Texte aus
/// den ARB-Dateien kommen (#209); Vorführungen finden ihre Schritte über
/// die `id`, nie über den Titel — der ist je Sprache ein anderer.
CoachScript mapTourScript(AppLocalizations l) => CoachScript(
      id: 'map',
      endLink: (l.helpTitle, '/profile/help'),
      steps: [
        mapIntro(l),
        CoachStep(
          id: 'map.badge',
          title: l.tourMapBadgeTitle,
          text: l.tourMapBadgeText,
          lit: const [MapCoach.trailBadge],
          gesture: CoachGesture.tap,
          requires: const [MapCoach.trailBadge],
        ),
        CoachStep(
          id: 'map.sheet',
          title: l.tourMapSheetTitle,
          text: l.tourMapSheetText,
          scene: MapCoach.trailSheet,
          lit: const [SheetCoach.metrics],
          // Ohne Trail kein Blatt. Der Anker im Blatt steht NICHT in
          // `requires` — er entsteht erst mit der Szene dieses Schritts.
          unless: const [MapCoach.empty],
        ),
        CoachStep(
          id: 'map.colors',
          title: l.tourMapColorsTitle,
          text: l.tourMapColorsText,
          // Die Linien zeichnet die Engine, sie sind keine Widgets — aber die
          // Legende auf der Karte ist eins (#182, seit 0.77.0). Bis dahin stand
          // eine gezeichnete Mini-Legende in der Blase.
          scene: MapCoach.legend,
          lit: const [MapCoach.legend],
        ),
        CoachStep(
          id: 'map.layers',
          title: l.tourMapLayersTitle,
          text: l.tourMapLayersText,
          lit: const [MapCoach.buttons],
          ring: const [MapCoach.layers],
        ),
        CoachStep(
          id: 'map.layersSheet',
          title: l.tourMapLayersSheetTitle,
          text: l.tourMapLayersSheetText,
          scene: MapCoach.layersSheet,
          lit: const [MapCoach.filterOfficial, MapCoach.filterWays, MapCoach.filterPois],
        ),
        CoachStep(
          id: 'map.offline',
          title: l.tourMapOfflineTitle,
          text: l.tourMapOfflineText,
          lit: const [MapCoach.buttons],
          ring: const [MapCoach.offline],
        ),
        CoachStep(
          id: 'map.rail',
          title: l.tourMapRailTitle,
          text: l.tourMapRailText,
          scene: MapCoach.rail,
          lit: const [MapCoach.rail],
          ring: const [MapCoach.railDraw],
        ),
        CoachStep(
          id: 'map.position',
          title: l.tourMapPositionTitle,
          text: l.tourMapPositionText,
          lit: const [MapCoach.buttons, MapCoach.feedback],
          ring: const [MapCoach.feedback, MapCoach.locate],
        ),
        CoachStep(
          id: 'map.record',
          title: l.tourMapRecordTitle,
          text: l.tourMapRecordText,
          lit: const [MapCoach.buttons],
          ring: const [MapCoach.record],
          // Nur in der Android-App; im Browser fällt der Schritt weg.
          requires: const [MapCoach.record],
        ),
        navStep(l),
      ],
    );

/// Die Karten-Tour beim ersten Start: mit der Willkommensseite statt der
/// Karten-Startseite und OHNE den Weg in die Kurzanleitung am Ende —
/// `startWelcomeTour` (`tab_tours.dart`) hängt die Reiter-Touren an, und
/// die Kette liefe sonst gleichzeitig in die Kurzanleitung.
CoachScript welcomeTourScript(AppLocalizations l) => CoachScript(
      id: 'map',
      steps: [welcomeIntro(l), ...mapTourScript(l).tourSteps],
    );

/// Startet die Tour und merkt sich danach, dass sie gesehen wurde —
/// durchgesehen ODER übersprungen: Wer abbricht, hat entschieden.
///
/// Gemerkt wird über den NOTIFIER, nicht über [ref]: Aus der
/// Kurzanleitung gestartet, kann das aufrufende Widget weg sein, bevor
/// die Tour endet — und ein `ref` eines abgebauten Widgets wirft.
void startMapTour(AppLocalizations l, WidgetRef ref) {
  final seen = ref.read(mapTourSeenProvider.notifier);
  ref.read(coachProvider.notifier).start(mapTourScript(l), onDone: () => seen.set(true));
}

/// Hat der Nutzer die Karten-Tour schon gesehen? Gerätelokal, Schlüssel
/// `map_tour_seen` ohne Suffix (Reset-Konvention in CLAUDE.md).
final mapTourSeenProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.mapTourSeen,
    write: (s, v) => s.setMapTourSeen(v),
    label: 'Karten-Tour merken',
  ),
);
