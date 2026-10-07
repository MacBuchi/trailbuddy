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
// - **„Später"/„Nicht jetzt" ist kein Gesehen**: In derselben Sitzung
//   fragt der Reiter nicht wieder (`declinedTabToursProvider`, nur im
//   Speicher), beim nächsten Start schon.
//
// Keine Profil-Tour (Plan 3.5): Die Karten-Tour nennt das Profil, die
// Kurzanleitung liegt dort, und eine dritte Frage verlängerte den ersten
// Start, ohne etwas zu zeigen, das man nicht erraten kann.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/safety_note.dart';
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

  /// Die erste Zeile unter „Meine Buddys" und ihr Stift.
  static const row = 'buddys.row';
  static const alias = 'buddys.alias';
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

const kTrailsTourScript = CoachScript(
  id: 'trails',
  examples: true,
  steps: [
    CoachStep(
      title: 'Deine Trails',
      chainTitle: 'Weiter mit den Trails?',
      text: 'Alle Trails deines Netzes als Liste: was du gefahren bist und was '
          'deine Buddys beisteuern. Hier findest du einen Trail schneller als '
          'auf der Karte.',
      art: trailsArt,
    ),
    CoachStep(
      title: 'Eine Zeile lesen',
      text: 'Streifen und Schild tragen die Schwierigkeit; das Wort sagt, wessen '
          'Trail es ist — MEIN oder die Namen deiner Buddys. Ein Tipp öffnet das '
          'Blatt.',
      lit: [TrailsCoach.row],
      ring: [],
      gesture: CoachGesture.tap,
      requires: [TrailsCoach.row],
    ),
    CoachStep(
      title: 'Zahlen und Profil',
      text: 'Länge, Höhenmeter, Grad und darunter das Höhenprofil. Ein Tipp auf '
          'den Grad zeigt alle Einschätzungen — und was S0 bis S5 bedeuten.',
      scene: TrailsCoach.sheet,
      lit: [SheetCoach.metrics],
      requires: [TrailsCoach.row],
    ),
    CoachStep(
      title: 'Deine Einschätzung',
      text: 'Deinen eigenen S-Grad und deine Sterne tippst du hier an. Angezeigt '
          'wird, was dein Netz sagt — nicht nur du.',
      scene: TrailsCoach.sheet,
      lit: [SheetCoach.ownGrade],
      requires: [TrailsCoach.rowOwn],
    ),
    CoachStep(
      title: 'Was du beisteuerst',
      text: 'Name, Charakter, Bewertung, Sichtbarkeit, Beschreibung und Link — '
          'dein Beitrag zum Trail. „Nur für mich" hält ihn vor Buddys verborgen.',
      scene: TrailsCoach.sheet,
      lit: [SheetCoach.contribution],
      requires: [TrailsCoach.rowOwn],
    ),
    CoachStep(
      title: 'Etwas Aktuelles erzählen',
      text: 'Ein Hinweis sagt, was gerade ist: umgestürzter Baum, neue Sprünge. '
          'Buddys sehen ihn mit gelbem Rand, bis sie ihn gelesen haben. Eine '
          'Sperre oder den Zustand meldest du daneben.',
      scene: TrailsCoach.sheet,
      lit: [SheetCoach.addNote],
      requires: [TrailsCoach.row],
    ),
    CoachStep(
      title: 'Suchen und eingrenzen',
      text: 'Gesucht wird über Name und Buddy, Tippfehler inklusive; die Chips '
          'grenzen nach Kartenausschnitt, S-Grad-Bereich, Charakter oder Meldung '
          'ein. Daneben die Sortierung. Bis auf den Ausschnitt gilt der Filter '
          'auch auf der Karte.',
      lit: [TrailsCoach.search, TrailsCoach.chips],
    ),
    CoachStep(
      title: 'GPX hereinholen',
      text: 'Das Symbol oben rechts liest GPX- oder Zip-Dateien aus anderen Apps. '
          'Kurz und bergab wird ein Trail, eine ganze Runde eine Fahrt — die '
          'zerlegst du dann in Trails.',
      lit: [TrailsCoach.import],
    ),
  ],
);

const kBuddysTourScript = CoachScript(
  id: 'buddys',
  examples: true,
  steps: [
    CoachStep(
      title: 'Deine Buddys',
      chainTitle: 'Weiter mit den Buddys?',
      text: 'Wer deine Trails sieht — und du seine. Nur direkte Buddys, nichts '
          'darüber hinaus; eine öffentliche Karte gibt es nicht.',
      art: buddysArt,
    ),
    CoachStep(
      title: 'Jemanden einladen',
      text: 'Schickt einen Link zu TrailBuddy über deine Messenger-App — mit '
          'deinem Benutzernamen, damit man dich gleich findet.',
      lit: [BuddysCoach.invite],
    ),
    CoachStep(
      // Nicht „Buddy finden": So heißt das Suchfeld selbst.
      title: 'Nach Buddys suchen',
      text: 'Gefunden wird über den Benutzernamen oder die genaue '
          'E-Mail-Adresse. Trails seht ihr voneinander erst, wenn die Anfrage '
          'angenommen ist.',
      lit: [BuddysCoach.search],
    ),
    CoachStep(
      title: 'Offene Anfragen',
      text: 'Anfragen an dich stehen hier mit Annehmen und Ablehnen; gesendete '
          'lassen sich zurückziehen.',
      lit: [BuddysCoach.requests],
      requires: [BuddysCoach.requests],
    ),
    CoachStep(
      title: 'Ein Buddy in der Liste',
      text: '„n gemeinsam" zählt Trails, die ihr beide kennt. Der Stift gibt dem '
          'Buddy einen Namen, den nur du siehst.',
      lit: [BuddysCoach.row],
      ring: [BuddysCoach.alias],
      requires: [BuddysCoach.row],
    ),
    CoachStep(
      title: 'Beim Verbinden',
      text: 'Verbindet ihr euch, werden gleiche Trails EIN Trail mit zwei Namen, '
          'der Rest kommt dazu. Trennt ihr euch, verschwinden seine Trails wieder '
          'von deiner Karte.',
    ),
  ],
);

/// Alle Reiter-Touren — für den Test, der sie gegen die Fake-Vorgabe hält.
const kTabTourScripts = [kTrailsTourScript, kBuddysTourScript];

/// Die Reiter-Touren in der Reihenfolge der Leiste, mit ihrer Route.
const kTabTours = [
  (kTrailsTourScript, '/trails'),
  (kBuddysTourScript, '/friends'),
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

/// Touren, bei denen in DIESER Sitzung „Nicht jetzt" oder „Später"
/// gewählt wurde. Nur im Speicher.
class DeclinedTabTours extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String id) => state = {...state, id};
}

final declinedTabToursProvider = NotifierProvider<DeclinedTabTours, Set<String>>(DeclinedTabTours.new);

/// Startet [script] und merkt sich danach, dass sie gesehen wurde.
void startTabTour(WidgetRef ref, CoachScript script) {
  final seen = ref.read(seenCoachToursProvider.notifier);
  final declined = ref.read(declinedTabToursProvider.notifier);
  ref.read(coachProvider.notifier).start(script,
      onDone: () => seen.markSeen(script.id), onDecline: () => declined.add(script.id));
}

/// Der erste Start: Willkommensseite, Karten-Tour, danach die Reiter —
/// jeder mit seiner Startseite als FRAGE („Weiter mit den Trails?"). Wer
/// „Später" wählt, beendet die Kette; die übrigen Touren kommen beim
/// ersten Besuch ihres Reiters. „Nicht jetzt" auf der Willkommensseite
/// fragt beim nächsten Start wieder.
///
/// Notifier und Router werden VORHER gegriffen: Die Kette läuft über
/// mehrere Reiter, und der `ref` des Karten-Screens ist dabei vielleicht
/// schon nicht mehr zu gebrauchen.
void startWelcomeTour(WidgetRef ref, GoRouter router) {
  final coach = ref.read(coachProvider.notifier);
  final mapSeen = ref.read(mapTourSeenProvider.notifier);
  final seen = ref.read(seenCoachToursProvider.notifier);
  final declined = ref.read(declinedTabToursProvider.notifier);
  coach.start(kWelcomeTourScript, onDone: () {
    mapSeen.set(true);
    unawaited(_continueChain(coach, router, seen, declined, kTabTours));
  });
}

Future<void> _continueChain(
  CoachNotifier coach,
  GoRouter router,
  SeenCoachTours seen,
  DeclinedTabTours declined,
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
        unawaited(_continueChain(coach, router, seen, declined, open.sublist(1)));
      },
      onDecline: () => declined.add(script.id));
}

/// Startet die Tour seines Reiters, sobald es passt. Gehört einmal in den
/// Reiter, um dessen Inhalt.
class TabTourStarter extends ConsumerStatefulWidget {
  const TabTourStarter({super.key, required this.script, required this.child});

  final CoachScript script;
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
    final id = widget.script.id;
    final requested = ref.watch(requestedTabTourProvider) == id;
    final seen = ref.watch(seenCoachToursProvider).contains(id) ||
        ref.watch(declinedTabToursProvider).contains(id);
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
      final requested = ref.read(requestedTabTourProvider) == widget.script.id;
      if (ref.read(coachProvider.notifier).busy) {
        if (!requested) _yielded = true;
        return;
      }
      if (requested) {
        ref.read(requestedTabTourProvider.notifier).clear();
      } else if (ref.read(seenCoachToursProvider).contains(widget.script.id) ||
          ref.read(declinedTabToursProvider).contains(widget.script.id) ||
          !ref.read(mapTourSeenProvider) ||
          !ref.read(safetyNoteSeenProvider)) {
        return;
      }
      startTabTour(ref, widget.script);
    });
  }
}
