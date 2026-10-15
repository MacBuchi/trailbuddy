// „Zeig es mir" (#135, Plan `docs/konzept-onboarding.md` 3.6; Vorlage
// PilzBuddys `highlight_demos.dart`, #596): je Eintrag in „Entdecken" eine
// kurze Vorführung auf der Hinweis-Maschine.
//
// **Sie endet IN der Funktion, nicht davor.** Wer „Melden, was gerade gilt"
// sehen will, bekommt das Trail-Blatt mit dem Knopf, nicht den Reiter, in
// dem es irgendwo liegt. Was eine Vorführung öffnet, schließt sie wieder —
// ohne dass etwas ausgelöst wird.
//
// Drei Dinge, die man wissen muss:
//
// - **Jeder Eintrag bringt seine Vorführung mit.**
//   `highlight_demos_flow_test.dart` verlangt eine je Kennung in
//   `kFeatureHighlights` und fährt jede durch.
// - **Was nicht jeder hat, hat einen Ersatzschritt** (`requires`/`unless`):
//   ohne Trail „Erst einen Trail holen" am Import-Symbol, ohne eigenen Trail
//   der Hinweis, dass es um eigene geht, ohne Buddy das Suchfeld. Genau
//   einer läuft.
// - **Die Schritte der Touren werden übernommen, nicht abgeschrieben**
//   (`_from`, über die `id` des Schritts): Ändert sich ein Tour-Text,
//   ändert sich die Vorführung mit.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../coach/coach.dart';
import '../help/map_tour.dart';
import '../help/tab_tours.dart';
import '../routing/road_graph_loader.dart' show kOnlineFillMaxTiles;

/// Eine Vorführung: wo sie beginnt und was sie zeigt.
class HighlightDemo {
  const HighlightDemo({required this.route, required this.script});

  /// Die Route, auf die zuerst gewechselt wird.
  final String route;
  final CoachScript script;

  /// Die Geste, die die Karte in „Entdecken" als kleines Bild zeigt: die
  /// erste, die die Vorführung benutzt, sonst ein Tipp.
  CoachGesture get gesture => script.steps
      .map((s) => s.gesture)
      .firstWhere((g) => g != CoachGesture.none, orElse: () => CoachGesture.tap);
}

CoachScript _demo(String id, List<CoachStep> steps) => CoachScript(id: 'demo.$id', steps: steps);

/// Ein Schritt einer Tour, über seine `id` — nie über den Titel, der ist
/// je Sprache ein anderer (#209).
CoachStep _from(CoachScript script, String id) => script.steps.firstWhere((s) => s.id == id);

// Bausteine, die mehrere Vorführungen teilen.

CoachStep _openTrailFirst(AppLocalizations l) => CoachStep(
  title: l.demoOpenTrailFirstTitle,
  text: l.demoOpenTrailFirstText,
  lit: [TrailsCoach.row],
  ring: [],
  gesture: CoachGesture.tap,
  requires: [TrailsCoach.row],
);

CoachStep _noTrailYet(AppLocalizations l) => CoachStep(
  title: l.demoNoTrailYetTitle,
  text: l.demoNoTrailYetText,
  lit: [TrailsCoach.import],
  unless: [TrailsCoach.row],
);

CoachStep _noOwnTrail(AppLocalizations l) => CoachStep(
  title: l.demoNoOwnTrailTitle,
  text: l.demoNoOwnTrailText,
  lit: [TrailsCoach.import],
  requires: [TrailsCoach.row],
  unless: [TrailsCoach.rowOwn],
);

CoachStep _androidOnly(AppLocalizations l) => CoachStep(
  title: l.demoAndroidOnlyTitle,
  text: l.demoAndroidOnlyText,
  unless: [MapCoach.record],
);

CoachStep _findBuddyFirst(AppLocalizations l) => CoachStep(
  title: l.demoFindBuddyFirstTitle,
  text: l.demoFindBuddyFirstText,
  lit: [BuddysCoach.search],
  unless: [BuddysCoach.row],
);

CoachStep _profileRow(String id, String title, String text) => CoachStep(
      title: title,
      text: text,
      lit: [ProfileCoach.row(id)],
      scrollIn: ProfileCoach.list,
    );

/// Die Vorführungen je Kennung in `kFeatureHighlights`. Eine Funktion, weil
/// sie Schritte der Touren übernehmen, und die bauen ihre Texte aus
/// [AppLocalizations] (#209).
Map<String, HighlightDemo> highlightDemos(AppLocalizations l) => {
  // ─── Highlights ────────────────────────────────────────────────
  'whole-region': HighlightDemo(
    route: '/profile',
    script: _demo('whole-region', [
      _profileRow('areas', l.demoWholeRegionTitle, l.demoWholeRegionText),
    ]),
  ),
  'online-fill': HighlightDemo(
    route: '/',
    script: _demo('online-fill', [
      CoachStep(
        title: l.demoOnlineFill1Title,
        text: l.demoOnlineFill1Text(kOnlineFillMaxTiles),
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
      CoachStep(
        title: l.demoOnlineFill2Title,
        text: l.demoOnlineFill2Text,
        scene: MapCoach.loopRail,
        lit: const [MapCoach.loopRail],
        ring: [MapCoach.loopRailButton('loop-rail-params')],
        requires: const [MapCoach.loop],
      ),
    ]),
  ),
  'contours': HighlightDemo(
    route: '/',
    script: _demo('contours', [
      _from(mapTourScript(l), 'map.layers'),
      CoachStep(
        title: l.demoContoursTitle,
        text: l.demoContoursText,
        scene: MapCoach.layersSheet,
        lit: [MapCoach.filterContours],
      ),
    ]),
  ),
  'way-quality': HighlightDemo(
    route: '/',
    script: _demo('way-quality', [
      _from(mapTourScript(l), 'map.layers'),
      CoachStep(
        title: l.demoWayQuality1Title,
        text: l.demoWayQuality1Text,
        scene: MapCoach.layersSheet,
        lit: [MapCoach.filterWays],
      ),
      CoachStep(
        title: l.demoWayQuality2Title,
        text: l.demoWayQuality2Text,
        scene: MapCoach.legend,
        lit: [MapCoach.legend],
      ),
    ]),
  ),
  'map-legend': HighlightDemo(
    route: '/',
    script: _demo('map-legend', [
      _from(mapTourScript(l), 'map.colors'),
    ]),
  ),
  'map-layers': HighlightDemo(
    route: '/',
    script: _demo('map-layers', [
      _from(mapTourScript(l), 'map.layers'),
      _from(mapTourScript(l), 'map.layersSheet'),
      _from(mapTourScript(l), 'map.offline'),
      _from(mapTourScript(l), 'map.rail'),
    ]),
  ),
  'map-select': HighlightDemo(
    route: '/',
    script: _demo('map-select', [
      CoachStep(
        title: l.demoMapSelect1Title,
        text: l.demoMapSelect1Text,
        lit: [MapCoach.trailBadge],
        gesture: CoachGesture.tap,
        requires: [MapCoach.trailBadge],
      ),
      CoachStep(
        title: l.demoMapSelect2Title,
        text: l.demoMapSelect2Text,
        lit: [MapCoach.loop],
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'trail-nav': HighlightDemo(
    route: '/trails',
    script: _demo('trail-nav', [
      CoachStep(
        title: l.demoTrailNavTitle,
        text: l.demoTrailNavText,
        lit: [TrailsCoach.nav],
        gesture: CoachGesture.tap,
        requires: [TrailsCoach.nav],
      ),
      _noTrailYet(l),
    ]),
  ),
  'nav-minimize': HighlightDemo(
    route: '/',
    script: _demo('nav-minimize', [
      CoachStep(
        title: l.demoNavMinimizeTitle,
        text: l.demoNavMinimizeText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'nav-trail-end': HighlightDemo(
    route: '/',
    script: _demo('nav-trail-end', [
      CoachStep(
        title: l.demoNavTrailEndTitle,
        text: l.demoNavTrailEndText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'nav-sections': HighlightDemo(
    route: '/',
    script: _demo('nav-sections', [
      CoachStep(
        title: l.demoNavSectionsTitle,
        text: l.demoNavSectionsText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'nav-pip': HighlightDemo(
    route: '/',
    script: _demo('nav-pip', [
      CoachStep(
        title: l.demoNavPipTitle,
        text: l.demoNavPipText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'nav-notice': HighlightDemo(
    route: '/',
    script: _demo('nav-notice', [
      CoachStep(
        title: l.demoNavNoticeTitle,
        text: l.demoNavNoticeText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'nav-rejoin': HighlightDemo(
    route: '/',
    script: _demo('nav-rejoin', [
      CoachStep(
        title: l.demoNavRejoinTitle,
        text: l.demoNavRejoinText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'navigation': HighlightDemo(
    route: '/',
    script: _demo('navigation', [
      CoachStep(
        title: l.demoNavigationTitle,
        text: l.demoNavigationText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'route-vias': HighlightDemo(
    route: '/',
    script: _demo('route-vias', [
      CoachStep(
        title: l.demoRouteViasTitle,
        text: l.demoRouteViasText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'route-profile-scrub': HighlightDemo(
    route: '/',
    script: _demo('route-profile-scrub', [
      CoachStep(
        title: l.demoRouteProfileScrubTitle,
        text: l.demoRouteProfileScrubText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'route-elevation': HighlightDemo(
    route: '/',
    script: _demo('route-elevation', [
      CoachStep(
        title: l.demoRouteElevationTitle,
        text: l.demoRouteElevationText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'loop-planner': HighlightDemo(
    route: '/',
    script: _demo('loop-planner', [
      CoachStep(
        title: l.demoLoopPlanner1Title,
        text: l.demoLoopPlanner1Text,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
      CoachStep(
        title: l.demoLoopPlanner2Title,
        text: l.demoLoopPlanner2Text,
        scene: MapCoach.loopRail,
        lit: const [MapCoach.loopRail],
        ring: [MapCoach.loopRailButton('loop-rail-compute')],
        requires: const [MapCoach.loop],
      ),
    ]),
  ),
  'trail-list-filters': HighlightDemo(
    route: '/trails',
    script: _demo('trail-list-filters', [
      CoachStep(
        title: l.demoTrailListFiltersTitle,
        text: l.demoTrailListFiltersText,
        lit: [TrailsCoach.chips],
      ),
    ]),
  ),
  'ride-import': HighlightDemo(
    route: '/trails',
    script: _demo('ride-import', [
      CoachStep(
        title: l.demoRideImportTitle,
        text: l.demoRideImportText,
        lit: [TrailsCoach.import],
      ),
    ]),
  ),
  'route-prefs': HighlightDemo(
    route: '/',
    script: _demo('route-prefs', [
      CoachStep(
        title: l.demoRoutePrefsTitle,
        text: l.demoRoutePrefsText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'steep-climbs': HighlightDemo(
    route: '/',
    script: _demo('steep-climbs', [
      CoachStep(
        title: l.demoSteepClimbsTitle,
        text: l.demoSteepClimbsText,
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'terrain-heights': HighlightDemo(
    route: '/trails',
    script: _demo('terrain-heights', [
      _openTrailFirst(l),
      CoachStep(
        title: l.demoTerrainHeightsTitle,
        text: l.demoTerrainHeightsText,
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.metrics],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet(l),
    ]),
  ),
  'gpx-export': HighlightDemo(
    route: '/trails',
    script: _demo('gpx-export', [
      _openTrailFirst(l),
      CoachStep(
        title: l.demoGpxExportTitle,
        text: l.demoGpxExportText,
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.export],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet(l),
    ]),
  ),
  'trail-head': HighlightDemo(
    route: '/trails',
    script: _demo('trail-head', [
      _openTrailFirst(l),
      CoachStep(
        title: l.demoTrailHeadTitle,
        text: l.demoTrailHeadText,
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.trailHead],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet(l),
    ]),
  ),
  'navigate': HighlightDemo(
    route: '/trails',
    script: _demo('navigate', [
      _openTrailFirst(l),
      CoachStep(
        title: l.demoNavigateTitle,
        text: l.demoNavigateText,
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.navigate],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet(l),
    ]),
  ),
  'trail-ends': HighlightDemo(
    route: '/',
    script: _demo('trail-ends', [
      CoachStep(
        title: l.demoTrailEnds1Title,
        text: l.demoTrailEnds1Text,
        lit: [MapCoach.trailStart],
        requires: [MapCoach.trailStart],
      ),
      CoachStep(
        title: l.demoTrailEnds2Title,
        text: l.demoTrailEnds2Text,
        lit: [MapCoach.empty],
        unless: [MapCoach.trailStart],
      ),
    ]),
  ),
  'kurzanleitung': HighlightDemo(
    route: '/profile',
    script: _demo('kurzanleitung', [
      _profileRow('help', l.demoKurzanleitungTitle, l.demoKurzanleitungText),
    ]),
  ),
  'still-valid': HighlightDemo(
    route: '/profile',
    script: _demo('still-valid', [
      CoachStep(
        title: l.demoStillValid1Title,
        text: l.demoStillValid1Text,
        lit: [ProfileCoach.row('still-valid')],
        requires: [ProfileCoach.row('still-valid')],
      ),
      CoachStep(
        title: l.demoStillValid2Title,
        text: l.demoStillValid2Text,
        unless: [ProfileCoach.row('still-valid')],
      ),
    ]),
  ),
  'marks': HighlightDemo(
    route: '/',
    script: _demo('marks', [
      CoachStep(
        title: l.demoMarksTitle,
        text: l.demoMarksText,
        lit: [MapCoach.buttons],
        ring: [MapCoach.record],
        requires: [MapCoach.record],
      ),
      _androidOnly(l),
    ]),
  ),
  'takeover': HighlightDemo(
    route: '/trails',
    script: _demo('takeover', [
      CoachStep(
        title: l.demoTakeoverTitle,
        text: l.demoTakeoverText,
      ),
    ]),
  ),
  'reports': HighlightDemo(
    route: '/trails',
    script: _demo('reports', [
      _openTrailFirst(l),
      CoachStep(
        title: l.demoReportsTitle,
        text: l.demoReportsText,
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.report],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet(l),
    ]),
  ),
  'rating': HighlightDemo(
    route: '/trails',
    script: _demo('rating', [
      _openTrailFirst(l),
      _from(trailsTourScript(l), 'trails.grade'),
      _noOwnTrail(l),
      _noTrailYet(l),
    ]),
  ),
  'grade-colors': HighlightDemo(
    route: '/',
    script: _demo('grade-colors', [_from(mapTourScript(l), 'map.colors')]),
  ),
  'connect-merge': HighlightDemo(
    route: '/friends',
    script: _demo('connect-merge', [
      CoachStep(
        title: l.demoConnectMerge1Title,
        text: l.demoConnectMerge1Text,
        lit: [BuddysCoach.requests],
        requires: [BuddysCoach.requests],
      ),
      CoachStep(
        title: l.demoConnectMerge2Title,
        text: l.demoConnectMerge2Text,
        lit: [BuddysCoach.search],
        unless: [BuddysCoach.requests],
      ),
    ]),
  ),
  'import-split': HighlightDemo(
    route: '/trails',
    script: _demo('import-split', [_from(trailsTourScript(l), 'trails.import')]),
  ),
  'offline-areas': HighlightDemo(
    route: '/',
    script: _demo('offline-areas', [
      _from(mapTourScript(l), 'map.offline'),
      _from(mapTourScript(l), 'map.rail'),
    ]),
  ),
  'ride-record': HighlightDemo(
    route: '/',
    script: _demo('ride-record', [_from(mapTourScript(l), 'map.record'), _androidOnly(l)]),
  ),
  'official-trails': HighlightDemo(
    route: '/',
    script: _demo('official-trails', [
      _from(mapTourScript(l), 'map.layers'),
      _from(mapTourScript(l), 'map.layersSheet'),
    ]),
  ),
  // Das Foto hängt man im Dialog an, den „Hinweis schreiben" öffnet — die
  // Vorführung zeigt auf denselben Knopf wie die der Hinweise.
  'note-photos': HighlightDemo(
    route: '/trails',
    script: _demo('note-photos', [
      _openTrailFirst(l),
      _from(trailsTourScript(l), 'trails.note'),
      _noTrailYet(l),
    ]),
  ),
  'trail-notes': HighlightDemo(
    route: '/trails',
    script: _demo('trail-notes', [
      _openTrailFirst(l),
      _from(trailsTourScript(l), 'trails.note'),
      _noTrailYet(l),
    ]),
  ),
  // ─── Tipps ─────────────────────────────────────────────────────
  // Der Knopf selbst steht nur, wenn ein Trail nah genug daneben liegt —
  // und ein Anker im Blatt darf nicht in `requires` stehen (er entsteht
  // erst mit der Szene). Deshalb zeigt die Vorführung auf den Export, unter
  // dem er steht.
  'merge-proposals': HighlightDemo(
    route: '/profile',
    script: _demo('merge-proposals', [
      CoachStep(
        title: l.demoMergeProposals1Title,
        text: l.demoMergeProposals1Text,
        lit: [ProfileCoach.row('merge-proposals')],
        requires: [ProfileCoach.row('merge-proposals')],
      ),
      CoachStep(
        title: l.demoMergeProposals2Title,
        text: l.demoMergeProposals2Text,
        unless: [ProfileCoach.row('merge-proposals')],
      ),
    ]),
  ),
  'trail-merge': HighlightDemo(
    route: '/trails',
    script: _demo('trail-merge', [
      _openTrailFirst(l),
      CoachStep(
        title: l.demoTrailMergeTitle,
        text: l.demoTrailMergeText,
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.export],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet(l),
    ]),
  ),
  'tours': HighlightDemo(
    route: '/profile/help',
    script: _demo('tours', [
      CoachStep(
        title: l.demoToursTitle,
        text: l.demoToursText,
        lit: [HelpCoach.tabTours],
        scrollIn: HelpCoach.list,
      ),
    ]),
  ),
  'rides-tidy': HighlightDemo(
    route: '/profile',
    script: _demo('rides-tidy', [
      _profileRow('rides', l.demoRidesTidyTitle, l.demoRidesTidyText),
    ]),
  ),
  'pick-section': HighlightDemo(
    route: '/profile',
    script: _demo('pick-section', [
      _profileRow('rides', l.demoPickSectionTitle, l.demoPickSectionText),
    ]),
  ),
  'trail-link': HighlightDemo(
    route: '/trails',
    script: _demo('trail-link', [
      _openTrailFirst(l),
      _from(trailsTourScript(l), 'trails.contribution'),
      _noOwnTrail(l),
      _noTrailYet(l),
    ]),
  ),
  'planned': HighlightDemo(
    route: '/trails',
    script: _demo('planned', [_from(trailsTourScript(l), 'trails.import')]),
  ),
  'traits': HighlightDemo(
    route: '/trails',
    script: _demo('traits', [_from(trailsTourScript(l), 'trails.search')]),
  ),
  'grade-votes': HighlightDemo(
    route: '/trails',
    script: _demo('grade-votes', [
      _openTrailFirst(l),
      CoachStep(
        title: l.demoGradeVotesTitle,
        text: l.demoGradeVotesText,
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.metrics],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet(l),
    ]),
  ),
  'visibility': HighlightDemo(
    route: '/trails',
    script: _demo('visibility', [
      _openTrailFirst(l),
      _from(trailsTourScript(l), 'trails.contribution'),
      _noOwnTrail(l),
      _noTrailYet(l),
    ]),
  ),
  'pois': HighlightDemo(
    route: '/',
    script: _demo('pois', [
      _from(mapTourScript(l), 'map.layers'),
      _from(mapTourScript(l), 'map.layersSheet'),
    ]),
  ),
  'my-position': HighlightDemo(
    route: '/',
    script: _demo('my-position', [_from(mapTourScript(l), 'map.position')]),
  ),
  'messages': HighlightDemo(
    route: '/friends',
    script: _demo('messages', [
      CoachStep(
        title: l.demoMessages1Title,
        text: l.demoMessages1Text,
        lit: [BuddysCoach.message],
        ring: [],
        gesture: CoachGesture.tap,
        requires: [BuddysCoach.message],
      ),
      CoachStep(
        title: l.demoMessages2Title,
        text: l.demoMessages2Text,
        scene: BuddysCoach.chat,
        lit: [BuddysCoach.chatInput],
        requires: [BuddysCoach.message],
      ),
      _findBuddyFirst(l),
    ]),
  ),
  'buddy-alias': HighlightDemo(
    route: '/friends',
    script: _demo('buddy-alias', [
      _from(buddysTourScript(l), 'buddys.row'),
      _findBuddyFirst(l),
    ]),
  ),
  'invite': HighlightDemo(
    route: '/friends',
    script: _demo('invite', [_from(buddysTourScript(l), 'buddys.invite')]),
  ),
  'notifications': HighlightDemo(
    route: '/profile',
    script: _demo('notifications', [
      _profileRow('notifications', l.demoNotificationsTitle, l.demoNotificationsText),
    ]),
  ),
  'rider-learn': HighlightDemo(
    route: '/profile',
    script: _demo('rider-learn', [
      _profileRow('rider', l.demoRiderLearnTitle, l.demoRiderLearnText),
    ]),
  ),
  'rider-profile': HighlightDemo(
    route: '/profile',
    script: _demo('rider-profile', [
      _profileRow('rider', l.demoRiderProfileTitle, l.demoRiderProfileText),
    ]),
  ),
  'appearance': HighlightDemo(
    route: '/profile',
    script: _demo('appearance', [
      _profileRow('appearance', l.demoAppearanceTitle, l.demoAppearanceText),
    ]),
  ),
  'language': HighlightDemo(
    route: '/profile',
    script: _demo('language', [
      _profileRow('language', l.demoLanguageTitle, l.demoLanguageText),
    ]),
  ),
};

/// Wechselt zur Route der Vorführung und startet sie, sobald der Reiter
/// steht. **Erst nach ein paar Bildern**: `requires` fragt beim Start, ob
/// die Anker DA sind, und die des Zielreiters meldet erst sein Aufbau an.
/// Bis dahin ist der Start vorgemerkt (`reserve`), damit die Tour des
/// Reiters nicht dazwischenkommt.
Future<void> startHighlightDemo(GoRouter router, CoachNotifier coach, HighlightDemo demo) async {
  coach.reserve();
  router.go(demo.route);
  for (var i = 0; i < 3; i++) {
    await WidgetsBinding.instance.endOfFrame;
  }
  coach.start(demo.script);
}
