// Neuheiten und Tipps (#135, Plan `docs/konzept-onboarding.md` 3.6) — die
// Daten und die eine Entscheidung, wer wann was sieht. Strukturkopie von
// PilzBuddys `feature_highlights.dart` (#596): `planHighlights` ist
// wörtlich übernommen, die Einträge sind TrailBuddys.
//
// **Eine Liste, zwei Anzeigen.** Das Blatt nach einem Update zeigt die
// jüngsten Highlights (höchstens drei), die Seite „Entdecken" zeigt alles.
// Tipps stehen nur dort — ein Blatt beim Start, das Kleinigkeiten
// ankündigt, wird nach dem zweiten Mal ungelesen weggewischt.
//
// **Rückwirkend geht es über die Karten-Tour.** Bis 0.64.0 hat kein Gerät
// gespeichert, welche Version es kannte. Der Merker der Karten-Tour (seit
// 0.60.0) trennt die Fälle: gesehen ⇒ Bestandsnutzer ⇒ einmal der
// Rückblick; nicht gesehen ⇒ frisch ⇒ die Tour erklärt, Version merken.
//
// **Wer eine Funktion baut, bringt ihren Eintrag im selben PR mit** —
// samt Vorführung (`highlight_demos.dart`) oder einem Satz im PR, warum
// nicht (PR-Vorlage).
import 'package:flutter/material.dart';

import '../../core/update_check.dart' show isNewerVersion;
import '../../l10n/l10n.dart';

/// Highlight (ins Blatt) oder Tipp (nur „Entdecken").
enum HighlightKind { highlight, tip }

/// Wo die Funktion wohnt — die Gruppen der Seite „Entdecken", in der
/// Reihenfolge der Reiterleiste.
enum HighlightTab {
  map,
  trails,
  buddys,
  profile;

  /// Wie der Reiter in der Reiterleiste heißt (#209).
  String label(AppLocalizations l) => switch (this) {
        HighlightTab.map => l.tabMap,
        HighlightTab.trails => l.tabTrails,
        HighlightTab.buddys => l.tabBuddys,
        HighlightTab.profile => l.tabProfile,
      };
}

/// Ein Eintrag.
class FeatureHighlight {
  const FeatureHighlight({
    required this.id,
    required this.since,
    required this.kind,
    required this.tab,
    required this.icon,
    required this.title,
    required this.text,
    required this.target,
  });

  /// Stabil für immer: Unter ihr merkt sich das Gerät „gesehen".
  final String id;

  /// Die Version, mit der die Funktion kam (aus `CHANGELOG.md`). Nie über
  /// der eigenen — ein Test prüft das gegen `pubspec.yaml`.
  final String since;

  final HighlightKind kind;
  final HighlightTab tab;

  /// Das ECHTE Symbol der Funktion — wer „Ebenen" sucht, sucht das Bild
  /// auf dem Knopf.
  final IconData icon;

  /// Titel und Text aus den ARB-Dateien (#209) — Funktionen, weil die
  /// Liste ohne `BuildContext` steht und gen-l10n keinen Zugriff über den
  /// Namen kennt. Schlüssel `highlight<Kennung>Title`/`…Text`.
  final String Function(AppLocalizations l) title;

  /// Zwei, höchstens drei Sätze.
  final String Function(AppLocalizations l) text;

  /// Wohin „Ausprobieren" führt: eine Route der App.
  final String target;
}

final kFeatureHighlights = <FeatureHighlight>[
  // ─── Highlights ──────────────────────────────────────────────────
  FeatureHighlight(
    id: 'loop-waypoints',
    since: '0.126.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.add_location_alt_outlined,
    title: (l) => l.highlightLoopWaypointsTitle,
    text: (l) => l.highlightLoopWaypointsText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'place-plan',
    since: '0.125.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.place_outlined,
    title: (l) => l.highlightPlacePlanTitle,
    text: (l) => l.highlightPlacePlanText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'trail-head-plan',
    since: '0.124.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.trip_origin,
    title: (l) => l.highlightTrailHeadPlanTitle,
    text: (l) => l.highlightTrailHeadPlanText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'loop-end',
    since: '0.123.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.sports_score,
    title: (l) => l.highlightLoopEndTitle,
    text: (l) => l.highlightLoopEndText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'route-profile-scrub',
    since: '0.122.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.directions_bike,
    title: (l) => l.highlightRouteProfileScrubTitle,
    text: (l) => l.highlightRouteProfileScrubText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'nav-minimize',
    since: '0.116.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.picture_in_picture_alt,
    title: (l) => l.highlightNavMinimizeTitle,
    text: (l) => l.highlightNavMinimizeText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'nav-trail-end',
    since: '0.115.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.emoji_events_outlined,
    title: (l) => l.highlightNavTrailEndTitle,
    text: (l) => l.highlightNavTrailEndText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'nav-sections',
    since: '0.114.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.alt_route,
    title: (l) => l.highlightNavSectionsTitle,
    text: (l) => l.highlightNavSectionsText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'note-photos',
    since: '0.113.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.add_a_photo_outlined,
    title: (l) => l.highlightNotePhotosTitle,
    text: (l) => l.highlightNotePhotosText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'messages',
    since: '0.111.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.buddys,
    icon: Icons.chat_bubble_outline,
    title: (l) => l.highlightMessagesTitle,
    text: (l) => l.highlightMessagesText,
    target: '/friends',
  ),
  FeatureHighlight(
    id: 'whole-region',
    since: '0.108.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.profile,
    icon: Icons.download_for_offline_outlined,
    title: (l) => l.highlightWholeRegionTitle,
    text: (l) => l.highlightWholeRegionText,
    target: '/profile/areas',
  ),
  FeatureHighlight(
    id: 'contours',
    since: '0.100.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.layers_outlined,
    title: (l) => l.highlightContoursTitle,
    text: (l) => l.highlightContoursText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'nav-pip',
    since: '0.97.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.picture_in_picture_alt_outlined,
    title: (l) => l.highlightNavPipTitle,
    text: (l) => l.highlightNavPipText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'nav-notice',
    since: '0.96.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.notifications_active_outlined,
    title: (l) => l.highlightNavNoticeTitle,
    text: (l) => l.highlightNavNoticeText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'nav-rejoin',
    since: '0.95.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.u_turn_left,
    title: (l) => l.highlightNavRejoinTitle,
    text: (l) => l.highlightNavRejoinText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'navigation',
    since: '0.94.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.navigation_outlined,
    title: (l) => l.highlightNavigationTitle,
    text: (l) => l.highlightNavigationText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'route-vias',
    since: '0.93.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.alt_route,
    title: (l) => l.highlightRouteViasTitle,
    text: (l) => l.highlightRouteViasText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'way-quality',
    since: '0.89.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.layers_outlined,
    title: (l) => l.highlightWayQualityTitle,
    text: (l) => l.highlightWayQualityText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'route-elevation',
    since: '0.88.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.alt_route,
    title: (l) => l.highlightRouteElevationTitle,
    text: (l) => l.highlightRouteElevationText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'rides-tidy',
    since: '0.85.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.profile,
    icon: Icons.electric_bike_outlined,
    title: (l) => l.highlightRidesTidyTitle,
    text: (l) => l.highlightRidesTidyText,
    target: '/profile/rides',
  ),
  FeatureHighlight(
    id: 'trail-list-filters',
    since: '0.84.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.tune,
    title: (l) => l.highlightTrailListFiltersTitle,
    text: (l) => l.highlightTrailListFiltersText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'ride-import',
    since: '0.82.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.file_upload_outlined,
    title: (l) => l.highlightRideImportTitle,
    text: (l) => l.highlightRideImportText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'route-prefs',
    since: '0.81.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.tune,
    title: (l) => l.highlightRoutePrefsTitle,
    text: (l) => l.highlightRoutePrefsText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'steep-climbs',
    since: '0.80.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.trending_up,
    title: (l) => l.highlightSteepClimbsTitle,
    text: (l) => l.highlightSteepClimbsText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'terrain-heights',
    since: '0.79.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.terrain,
    title: (l) => l.highlightTerrainHeightsTitle,
    text: (l) => l.highlightTerrainHeightsText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'online-fill',
    since: '0.78.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.cloud_download_outlined,
    title: (l) => l.highlightOnlineFillTitle,
    text: (l) => l.highlightOnlineFillText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'map-legend',
    since: '0.77.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.legend_toggle,
    title: (l) => l.highlightMapLegendTitle,
    text: (l) => l.highlightMapLegendText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'map-layers',
    since: '0.75.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.layers_outlined,
    title: (l) => l.highlightMapLayersTitle,
    text: (l) => l.highlightMapLayersText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'map-select',
    since: '0.74.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.touch_app_outlined,
    title: (l) => l.highlightMapSelectTitle,
    text: (l) => l.highlightMapSelectText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'trail-nav',
    since: '0.74.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.navigation_outlined,
    title: (l) => l.highlightTrailNavTitle,
    text: (l) => l.highlightTrailNavText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'loop-planner',
    since: '0.72.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.alt_route,
    title: (l) => l.highlightLoopPlannerTitle,
    text: (l) => l.highlightLoopPlannerText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'gpx-export',
    since: '0.68.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.share_outlined,
    title: (l) => l.highlightGpxExportTitle,
    text: (l) => l.highlightGpxExportText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'trail-head',
    since: '0.71.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.route_outlined,
    title: (l) => l.highlightTrailHeadTitle,
    text: (l) => l.highlightTrailHeadText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'navigate',
    since: '0.67.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.directions_outlined,
    title: (l) => l.highlightNavigateTitle,
    text: (l) => l.highlightNavigateText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'trail-ends',
    since: '0.66.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.trending_flat,
    title: (l) => l.highlightTrailEndsTitle,
    text: (l) => l.highlightTrailEndsText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'kurzanleitung',
    since: '0.59.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.profile,
    icon: Icons.help_outline,
    title: (l) => l.highlightKurzanleitungTitle,
    text: (l) => l.highlightKurzanleitungText,
    target: '/profile/help',
  ),
  FeatureHighlight(
    id: 'still-valid',
    since: '0.58.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.fact_check_outlined,
    title: (l) => l.highlightStillValidTitle,
    text: (l) => l.highlightStillValidText,
    target: '/profile',
  ),
  FeatureHighlight(
    id: 'marks',
    since: '0.57.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.flag_outlined,
    title: (l) => l.highlightMarksTitle,
    text: (l) => l.highlightMarksText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'takeover',
    since: '0.55.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.bookmark_add_outlined,
    title: (l) => l.highlightTakeoverTitle,
    text: (l) => l.highlightTakeoverText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'reports',
    since: '0.49.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.flag_outlined,
    title: (l) => l.highlightReportsTitle,
    text: (l) => l.highlightReportsText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'rating',
    since: '0.49.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.star_outline_rounded,
    title: (l) => l.highlightRatingTitle,
    text: (l) => l.highlightRatingText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'grade-colors',
    since: '0.42.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.palette_outlined,
    title: (l) => l.highlightGradeColorsTitle,
    text: (l) => l.highlightGradeColorsText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'connect-merge',
    since: '0.22.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.buddys,
    icon: Icons.merge_type,
    title: (l) => l.highlightConnectMergeTitle,
    text: (l) => l.highlightConnectMergeText,
    target: '/friends',
  ),
  FeatureHighlight(
    id: 'import-split',
    since: '0.20.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.content_cut,
    title: (l) => l.highlightImportSplitTitle,
    text: (l) => l.highlightImportSplitText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'offline-areas',
    since: '0.19.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.download_for_offline_outlined,
    title: (l) => l.highlightOfflineAreasTitle,
    text: (l) => l.highlightOfflineAreasText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'ride-record',
    since: '0.13.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.circle,
    title: (l) => l.highlightRideRecordTitle,
    text: (l) => l.highlightRideRecordText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'official-trails',
    since: '0.10.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.verified_outlined,
    title: (l) => l.highlightOfficialTrailsTitle,
    text: (l) => l.highlightOfficialTrailsText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'trail-notes',
    since: '0.8.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.add_comment_outlined,
    title: (l) => l.highlightTrailNotesTitle,
    text: (l) => l.highlightTrailNotesText,
    target: '/trails',
  ),
  // ─── Tipps ───────────────────────────────────────────────────────
  FeatureHighlight(
    id: 'merge-proposals',
    since: '0.110.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.merge_type,
    title: (l) => l.highlightMergeProposalsTitle,
    text: (l) => l.highlightMergeProposalsText,
    target: '/profile',
  ),
  FeatureHighlight(
    id: 'trail-merge',
    since: '0.109.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.merge_type,
    title: (l) => l.highlightTrailMergeTitle,
    text: (l) => l.highlightTrailMergeText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'tours',
    since: '0.63.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.profile,
    icon: Icons.play_circle_outline,
    title: (l) => l.highlightToursTitle,
    text: (l) => l.highlightToursText,
    target: '/profile/help',
  ),
  FeatureHighlight(
    id: 'pick-section',
    since: '0.47.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.content_cut,
    title: (l) => l.highlightPickSectionTitle,
    text: (l) => l.highlightPickSectionText,
    target: '/profile/rides',
  ),
  FeatureHighlight(
    id: 'trail-link',
    since: '0.48.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.open_in_new,
    title: (l) => l.highlightTrailLinkTitle,
    text: (l) => l.highlightTrailLinkText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'planned',
    since: '0.46.1',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.edit_calendar_outlined,
    title: (l) => l.highlightPlannedTitle,
    text: (l) => l.highlightPlannedText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'traits',
    since: '0.34.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.terrain_outlined,
    title: (l) => l.highlightTraitsTitle,
    text: (l) => l.highlightTraitsText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'grade-votes',
    since: '0.4.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.bar_chart,
    title: (l) => l.highlightGradeVotesTitle,
    text: (l) => l.highlightGradeVotesText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'visibility',
    since: '0.1.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.visibility_off_outlined,
    title: (l) => l.highlightVisibilityTitle,
    text: (l) => l.highlightVisibilityText,
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'pois',
    since: '0.5.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.map,
    icon: Icons.layers_outlined,
    title: (l) => l.highlightPoisTitle,
    text: (l) => l.highlightPoisText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'my-position',
    since: '0.12.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.map,
    icon: Icons.my_location,
    title: (l) => l.highlightMyPositionTitle,
    text: (l) => l.highlightMyPositionText,
    target: '/',
  ),
  FeatureHighlight(
    id: 'buddy-alias',
    since: '0.1.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.buddys,
    icon: Icons.edit_outlined,
    title: (l) => l.highlightBuddyAliasTitle,
    text: (l) => l.highlightBuddyAliasText,
    target: '/friends',
  ),
  FeatureHighlight(
    id: 'invite',
    since: '0.1.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.buddys,
    icon: Icons.share,
    title: (l) => l.highlightInviteTitle,
    text: (l) => l.highlightInviteText,
    target: '/friends',
  ),
  FeatureHighlight(
    id: 'notifications',
    since: '0.37.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.profile,
    icon: Icons.notifications_outlined,
    title: (l) => l.highlightNotificationsTitle,
    text: (l) => l.highlightNotificationsText,
    target: '/profile/notifications',
  ),
  FeatureHighlight(
    id: 'rider-learn',
    since: '0.73.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.profile,
    icon: Icons.school_outlined,
    title: (l) => l.highlightRiderLearnTitle,
    text: (l) => l.highlightRiderLearnText,
    target: '/profile/rider',
  ),
  FeatureHighlight(
    id: 'rider-profile',
    since: '0.70.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.profile,
    icon: Icons.pedal_bike_outlined,
    title: (l) => l.highlightRiderProfileTitle,
    text: (l) => l.highlightRiderProfileText,
    target: '/profile/rider',
  ),
  FeatureHighlight(
    id: 'appearance',
    since: '0.28.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.profile,
    icon: Icons.contrast,
    title: (l) => l.highlightAppearanceTitle,
    text: (l) => l.highlightAppearanceText,
    target: '/profile/appearance',
  ),
  FeatureHighlight(
    id: 'language',
    since: '0.118.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.profile,
    icon: Icons.translate,
    title: (l) => l.highlightLanguageTitle,
    text: (l) => l.highlightLanguageText,
    target: '/profile/language',
  ),
];

/// Die drei Highlights, mit denen der RÜCKBLICK beginnt — beim Rückblick
/// wäre „die jüngsten" die falsche Regel (PilzBuddy, 2026-09-24).
const kRecapLead = ['import-split', 'trail-notes', 'reports'];

/// Höchstens so viele Einträge im Blatt. Der Rest steht in „Entdecken".
const kHighlightSheetMax = 3;

/// Was beim Start zu tun ist.
sealed class HighlightPlan {
  const HighlightPlan();
}

/// Nichts zeigen, nichts merken (Version unbekannt).
class HighlightNothing extends HighlightPlan {
  const HighlightNothing();
}

/// Nichts zeigen, aber [version] als gesehen merken — frische
/// Installation oder ein Update ohne neues Highlight.
class HighlightRecord extends HighlightPlan {
  const HighlightRecord(this.version);
  final String version;
}

/// Das Blatt zeigen.
class HighlightShow extends HighlightPlan {
  const HighlightShow({
    required this.version,
    required this.pages,
    required this.recap,
    required this.more,
  });

  /// Die Version, die danach als gesehen gilt.
  final String version;
  final List<FeatureHighlight> pages;

  /// Rückblick (Bestandsnutzer, erstes Mal) statt „neu seit".
  final bool recap;

  /// Wie viele weitere in „Entdecken" warten.
  final int more;
}

/// Die eine Entscheidung. Rein, damit jeder Fall ohne App prüfbar ist.
HighlightPlan planHighlights({
  required String? current,
  required String? seenVersion,
  required bool mapTourSeen,
  List<FeatureHighlight>? all,
  List<String> recapLead = kRecapLead,
}) {
  final entries = all ?? kFeatureHighlights;
  if (current == null || !_isVersion(current)) return const HighlightNothing();
  final shipped = [
    for (final h in entries)
      if (h.kind == HighlightKind.highlight && !isNewerVersion(h.since, current))
        h,
  ];
  if (seenVersion == null) {
    // Frisch installiert: Die Tour erklärt, ein Rückblick auf Dinge, die
    // es vorher nie gab, wäre keiner.
    if (!mapTourSeen) return HighlightRecord(current);
    final lead = [
      for (final id in recapLead)
        ...shipped.where((h) => h.id == id),
    ];
    final pages = [
      ...lead,
      ...shipped.where((h) => !lead.contains(h)),
    ].take(kHighlightSheetMax).toList();
    if (pages.isEmpty) return HighlightRecord(current);
    return HighlightShow(
      version: current,
      pages: pages,
      recap: true,
      more: shipped.length - pages.length,
    );
  }
  // Gemerkt ist schon dieser Stand oder ein jüngerer (etwa nach einem
  // Rückschritt vom Vorabkanal): nichts zeigen und vor allem nichts
  // ZURÜCKschreiben — sonst käme alles dazwischen noch einmal.
  if (!isNewerVersion(current, seenVersion)) return const HighlightNothing();
  final pending = shipped
      .where((h) => isNewerVersion(h.since, seenVersion))
      .toList()
    // Jüngste zuerst; bei gleicher Version bleibt die Reihenfolge der
    // Liste (`sort` ist in Dart nicht stabil, daher der Index).
    ..sort((a, b) {
      if (a.since == b.since) return entries.indexOf(a) - entries.indexOf(b);
      return isNewerVersion(a.since, b.since) ? -1 : 1;
    });
  if (pending.isEmpty) return HighlightRecord(current);
  final pages = pending.take(kHighlightSheetMax).toList();
  return HighlightShow(
    version: current,
    pages: pages,
    recap: false,
    more: pending.length - pages.length,
  );
}

bool _isVersion(String v) => RegExp(r'^\d+\.\d+\.\d+').hasMatch(v.trim());
