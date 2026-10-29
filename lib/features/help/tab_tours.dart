// Kurze Touren je Reiter (#136, Plan `docs/konzept-onboarding.md` 3.5,
// 4.2 und 4.3; Vorlage PilzBuddys `tab_tours.dart`, #596) — auf derselben
// Hinweis-Maschine wie die Karten-Tour.
//
// **Warum je Reiter und nicht eine lange Tour vorab.** Was eine Tour
// zeigt, bevor man es braucht, ist beim Brauchen vergessen. Deshalb läuft
// jede beim ERSTEN Besuch ihres Reiters — und beim ersten Start fragt die
// Kette nach der Karten-Tour an jeder Grenze („Weiter mit den Trails?").
//
// Vier Dinge, die man wissen muss:
//
// - **Ohne eigene Daten zeigt sie Beispiele** (`tour_examples.dart`):
//   eine gezeichnete Zeile, ein Blatt, ein Buddy — nie gespeichert.
// - **Sie läuft nur, wenn der Reiter SICHTBAR ist** (`TickerMode`, den
//   go_router für verdeckte Reiter abschaltet). Die Reiter bleiben nach
//   dem ersten Besuch im Baum, und die Trail-Liste lädt gern nach,
//   während man auf der Karte ist.
// - **Karten-Tour und Hinweis gehen vor.** Solange sie nicht gesehen
//   sind, startet hier nichts — zwei Touren übereinander wären keine.
// - **„Später"/„Nicht jetzt" ist ein Gesehen** (#417): Wer ablehnt, hat
//   entschieden; die Tour bleibt in der Kurzanleitung startbar.
//
// Keine Profil-Tour (Plan 3.5): Die Karten-Tour nennt das Profil, die
// Kurzanleitung liegt dort, und eine dritte Frage verlängerte den ersten
// Start, ohne etwas zu zeigen, das man nicht erraten kann.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/safety_note.dart';
import '../../l10n/l10n.dart';
import '../coach/coach.dart';
import 'map_tour.dart';
import 'seen_tours.dart';
import 'tour_intro_art.dart';

/// Die Anker des Reiters „Trails".
abstract final class TrailsCoach {
  /// Die erste Zeile — der Trail, dessen Blatt die Tour öffnet (der erste
  /// eigene, sonst der erste), oder die Beispielzeile.
  static const row = 'trails.row';

  /// Derselbe Trail, wenn er MIR gehört: Nur dann stehen „Deine
  /// Einschätzung" und „Mein Beitrag" in seinem Blatt.
  static const rowOwn = 'trails.row.own';

  /// Das Navi-Symbol derselben Zeile (#176).
  static const nav = 'trails.nav';
  static const search = 'trails.search';
  static const sort = 'trails.sort';
  static const chips = 'trails.chips';
  static const import = 'trails.import';

  /// Szene: das Blatt des Trails der ersten Zeile (oder das Beispiel).
  static const sheet = 'trails.sheet';
}

/// Die Anker des Reiters „Buddys".
abstract final class BuddysCoach {
  static const invite = 'buddys.invite';
  static const search = 'buddys.search';
  static const requests = 'buddys.requests';

  /// Die erste Zeile unter „Meine Buddys", ihr Stift und ihre Sprechblase.
  static const row = 'buddys.row';
  static const alias = 'buddys.alias';
  static const message = 'buddys.message';

  /// Szene: der Verlauf mit dem ersten Buddy, mit dem Eingabefeld (#34).
  static const chat = 'buddys.chat';
  static const chatInput = 'buddys.chat.input';
}

/// Die Anker der Kurzanleitung — für die Vorführungen aus „Entdecken"
/// (#135): Die Knöpfe der Reiter-Touren stehen weit unten und werden erst
/// beim Scrollen gebaut.
abstract final class HelpCoach {
  static const list = 'help.list';
  static const tabTours = 'help.tabTours';
}

/// Die Anker des Profils — für die Vorführungen aus „Entdecken" (#135).
abstract final class ProfileCoach {
  /// Die Liste; untere Zeilen werden erst beim Scrollen gebaut.
  static const list = 'profile.list';

  /// Eine Zeile, je `_ProfileRow.id`.
  static String row(String id) => 'profile.$id';
}

/// Die Trails-Tour. Funktionen statt Konstanten wie die Karten-Tour
/// (#209): Die Texte kommen aus den ARB-Dateien, Vorführungen finden ihre
/// Schritte über die `id`.
CoachScript trailsTourScript(AppLocalizations l) => CoachScript(
      id: kTrailsTourId,
      examples: true,
      steps: [
        CoachStep(
          id: 'trails.intro',
          title: l.tourTrailsIntroTitle,
          chainTitle: l.tourTrailsIntroChainTitle,
          text: l.tourTrailsIntroText,
          art: trailsArt,
        ),
        CoachStep(
          id: 'trails.row',
          title: l.tourTrailsRowTitle,
          text: l.tourTrailsRowText,
          lit: const [TrailsCoach.row],
          ring: const [],
          gesture: CoachGesture.tap,
          requires: const [TrailsCoach.row],
        ),
        CoachStep(
          id: 'trails.sheet',
          title: l.tourTrailsSheetTitle,
          text: l.tourTrailsSheetText,
          scene: TrailsCoach.sheet,
          lit: const [SheetCoach.metrics],
          requires: const [TrailsCoach.row],
        ),
        CoachStep(
          id: 'trails.grade',
          title: l.tourTrailsGradeTitle,
          text: l.tourTrailsGradeText,
          scene: TrailsCoach.sheet,
          lit: const [SheetCoach.ownGrade],
          requires: const [TrailsCoach.rowOwn],
        ),
        CoachStep(
          id: 'trails.contribution',
          title: l.tourTrailsContributionTitle,
          text: l.tourTrailsContributionText,
          scene: TrailsCoach.sheet,
          lit: const [SheetCoach.contribution],
          requires: const [TrailsCoach.rowOwn],
        ),
        CoachStep(
          id: 'trails.note',
          title: l.tourTrailsNoteTitle,
          text: l.tourTrailsNoteText,
          scene: TrailsCoach.sheet,
          lit: const [SheetCoach.addNote],
          requires: const [TrailsCoach.row],
        ),
        CoachStep(
          id: 'trails.search',
          title: l.tourTrailsSearchTitle,
          text: l.tourTrailsSearchText,
          lit: const [TrailsCoach.search, TrailsCoach.chips],
        ),
        CoachStep(
          id: 'trails.import',
          title: l.tourTrailsImportTitle,
          text: l.tourTrailsImportText,
          lit: const [TrailsCoach.import],
        ),
      ],
    );

CoachScript buddysTourScript(AppLocalizations l) => CoachScript(
      id: kBuddysTourId,
      examples: true,
      steps: [
        CoachStep(
          id: 'buddys.intro',
          title: l.tourBuddysIntroTitle,
          chainTitle: l.tourBuddysIntroChainTitle,
          text: l.tourBuddysIntroText,
          art: buddysArt,
        ),
        CoachStep(
          id: 'buddys.invite',
          title: l.tourBuddysInviteTitle,
          text: l.tourBuddysInviteText,
          lit: const [BuddysCoach.invite],
        ),
        CoachStep(
          // Nicht „Buddy finden": So heißt das Suchfeld selbst.
          id: 'buddys.search',
          title: l.tourBuddysSearchTitle,
          text: l.tourBuddysSearchText,
          lit: const [BuddysCoach.search],
        ),
        CoachStep(
          id: 'buddys.requests',
          title: l.tourBuddysRequestsTitle,
          text: l.tourBuddysRequestsText,
          lit: const [BuddysCoach.requests],
          requires: const [BuddysCoach.requests],
        ),
        CoachStep(
          id: 'buddys.row',
          title: l.tourBuddysRowTitle,
          text: l.tourBuddysRowText,
          lit: const [BuddysCoach.row],
          ring: const [BuddysCoach.alias, BuddysCoach.message],
          requires: const [BuddysCoach.row],
        ),
        CoachStep(
          id: 'buddys.connect',
          title: l.tourBuddysConnectTitle,
          text: l.tourBuddysConnectText,
        ),
      ],
    );

/// Die Kennungen der Reiter-Touren — Merker in `seenCoachTours`, Wunsch
/// aus der Kurzanleitung.
const kTrailsTourId = 'trails';
const kBuddysTourId = 'buddys';

/// Alle Reiter-Touren — für den Test, der sie gegen die Fake-Vorgabe hält.
List<CoachScript> tabTourScripts(AppLocalizations l) => [trailsTourScript(l), buddysTourScript(l)];

/// Die Reiter-Touren in der Reihenfolge der Leiste, mit ihrer Route.
List<(CoachScript, String)> tabTours(AppLocalizations l) => [
      (trailsTourScript(l), '/trails'),
      (buddysTourScript(l), '/friends'),
    ];

/// Eine ausdrücklich gewünschte Tour (aus der Kurzanleitung). Sie läuft
/// auch, wenn sie schon gesehen ist, sobald ihr Reiter sichtbar wird.
class RequestedTabTour extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String id) => state = id;

  void clear() => state = null;
}

final requestedTabTourProvider = NotifierProvider<RequestedTabTour, String?>(RequestedTabTour.new);

/// Startet [script] und merkt sich danach, dass sie gesehen wurde — auch
/// nach „Nicht jetzt" (#417).
void startTabTour(WidgetRef ref, CoachScript script) {
  final seen = ref.read(seenCoachToursProvider.notifier);
  ref.read(coachProvider.notifier).start(script,
      onDone: () => seen.markSeen(script.id), onDecline: () => seen.markSeen(script.id));
}

/// Der erste Start: Willkommensseite, Karten-Tour, danach die Reiter —
/// jeder mit seiner Startseite als FRAGE („Weiter mit den Trails?"). Wer
/// „Später" wählt, beendet die Kette und hat diese Tour gesehen; die
/// übrigen kommen beim ersten Besuch ihres Reiters. „Nicht jetzt" auf der
/// Willkommensseite merkt die Karten-Tour als gesehen (#417) — die
/// Reiter fragen dann je einmal bei ihrem ersten Besuch.
///
/// Notifier und Router werden VORHER gegriffen: Die Kette läuft über
/// mehrere Reiter, und der `ref` des Karten-Screens ist dabei vielleicht
/// schon nicht mehr zu gebrauchen.
void startWelcomeTour(AppLocalizations l, WidgetRef ref, GoRouter router) {
  final coach = ref.read(coachProvider.notifier);
  final mapSeen = ref.read(mapTourSeenProvider.notifier);
  final seen = ref.read(seenCoachToursProvider.notifier);
  coach.start(welcomeTourScript(l), onDone: () {
    mapSeen.set(true);
    unawaited(_continueChain(coach, router, seen, tabTours(l)));
  }, onDecline: () => mapSeen.set(true));
}

Future<void> _continueChain(
  CoachNotifier coach,
  GoRouter router,
  SeenCoachTours seen,
  List<(CoachScript, String)> rest,
) async {
  final open = [
    for (final tour in rest)
      if (!seen.hasSeen(tour.$1.id)) tour,
  ];
  if (open.isEmpty) return;
  final (script, route) = open.first;
  coach.reserve();
  router.go(route);
  // Bis der Reiter steht und seine Anker gemeldet hat.
  for (var i = 0; i < 3; i++) {
    await WidgetsBinding.instance.endOfFrame;
  }
  coach.start(script,
      chained: true,
      onDone: () {
        seen.markSeen(script.id);
        unawaited(_continueChain(coach, router, seen, open.sublist(1)));
      },
      onDecline: () => seen.markSeen(script.id));
}

/// Startet die Tour seines Reiters, sobald es passt. Gehört einmal in den
/// Reiter, um dessen Inhalt.
class TabTourStarter extends ConsumerStatefulWidget {
  const TabTourStarter({super.key, required this.script, required this.child});

  /// Das Skript des Reiters, gebaut in der Sprache der App.
  final CoachScript Function(AppLocalizations l) script;
  final Widget child;

  @override
  ConsumerState<TabTourStarter> createState() => _TabTourStarterState();
}

class _TabTourStarterState extends ConsumerState<TabTourStarter> {
  bool _scheduled = false;

  /// Lief beim Eintreffen schon etwas, wartet die Tour bis zum nächsten
  /// Besuch des Reiters — sonst fiele sie über das Ende dessen her, was
  /// gerade lief.
  bool _yielded = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.script(context.l10n).id;
    final requested = ref.watch(requestedTabTourProvider) == id;
    final seen = ref.watch(seenCoachToursProvider).contains(id);
    // Abhängigkeit, nicht nur Abfrage: Wird der Reiter sichtbar, baut
    // dieses Widget neu, und der Start wird erneut versucht.
    final visible = TickerMode.valuesOf(context).enabled;
    if (!visible) _yielded = false;
    if (visible && (requested || (!seen && !_yielded))) _schedule();
    return widget.child;
  }

  /// Nach dem Bild, weil die Anker erst dann vermessbar sind.
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (!TickerMode.valuesOf(context).enabled) return;
      // Liegt eine Unterseite darüber, ist der Reiter aktiv, aber nicht zu
      // sehen.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final script = widget.script(context.l10n);
      final requested = ref.read(requestedTabTourProvider) == script.id;
      if (ref.read(coachProvider.notifier).busy) {
        if (!requested) _yielded = true;
        return;
      }
      if (requested) {
        ref.read(requestedTabTourProvider.notifier).clear();
      } else if (ref.read(seenCoachToursProvider).contains(script.id) ||
          !ref.read(mapTourSeenProvider) ||
          !ref.read(safetyNoteSeenProvider)) {
        return;
      }
      startTabTour(ref, script);
    });
  }
}
