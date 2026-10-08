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
//   (`_from`): Ändert sich ein Tour-Text, ändert sich die Vorführung mit.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

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

/// Ein Schritt einer Tour, über seinen Titel.
CoachStep _from(CoachScript script, String title) => script.steps.firstWhere((s) => s.title == title);

// Bausteine, die mehrere Vorführungen teilen.

const _openTrailFirst = CoachStep(
  title: 'Einen Trail öffnen',
  text: 'Ein Tipp auf die Zeile öffnet das Blatt — dasselbe wie auf der Karte.',
  lit: [TrailsCoach.row],
  ring: [],
  gesture: CoachGesture.tap,
  requires: [TrailsCoach.row],
);

const _noTrailYet = CoachStep(
  title: 'Erst einen Trail holen',
  text: 'Das geht an einem Trail. Hol dir einen über GPX aus einer anderen App, '
      'zeichne eine Fahrt auf oder verbinde dich mit Buddys.',
  lit: [TrailsCoach.import],
  unless: [TrailsCoach.row],
);

const _noOwnTrail = CoachStep(
  title: 'An eigenen Trails',
  text: 'Das geht an Trails, die du selbst beigesteuert hast — über GPX oder '
      'aus einer aufgezeichneten Fahrt. Einen Buddy-Trail machst du beim ersten '
      'Befahren zu deinem.',
  lit: [TrailsCoach.import],
  requires: [TrailsCoach.row],
  unless: [TrailsCoach.rowOwn],
);

const _androidOnly = CoachStep(
  title: 'In der Android-App',
  text: 'Aufgezeichnet wird in der Android-App — ein Browser bekommt im '
      'Hintergrund keine Positionen.',
  unless: [MapCoach.record],
);

const _findBuddyFirst = CoachStep(
  title: 'Erst einen Buddy finden',
  text: 'Das geht mit deinen Buddys. Such hier nach einem Benutzernamen oder '
      'einer genauen E-Mail-Adresse — oder lade jemanden ein.',
  lit: [BuddysCoach.search],
  unless: [BuddysCoach.row],
);

CoachStep _profileRow(String id, String title, String text) => CoachStep(
      title: title,
      text: text,
      lit: [ProfileCoach.row(id)],
      scrollIn: ProfileCoach.list,
    );

final kHighlightDemos = <String, HighlightDemo>{
  // ─── Highlights ────────────────────────────────────────────────
  'online-fill': HighlightDemo(
    route: '/',
    script: _demo('online-fill', [
      const CoachStep(
        title: 'Wege vom Kartenhost',
        text: 'Der Planer rechnet über die Wege deiner Bereiche. Mit Empfang '
            'holt er, was fehlt, vom Kartenhost — höchstens $kOnlineFillMaxTiles '
            'Kacheln je Planung, nur für diese Sitzung.',
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
      CoachStep(
        title: 'Offline prüfen',
        text: 'Unter Parameter schaltest du „Fehlende Wege online ergänzen" ab — '
            'dann rechnet er wie im Funkloch, und du siehst zu Hause, ob deine '
            'Bereiche für die Runde reichen.',
        scene: MapCoach.loopRail,
        lit: const [MapCoach.loopRail],
        ring: [MapCoach.loopRailButton('loop-rail-params')],
        requires: const [MapCoach.loop],
      ),
    ]),
  ),
  'way-quality': HighlightDemo(
    route: '/',
    script: _demo('way-quality', [
      _from(kMapTourScript, 'Was die Karte zeigt'),
      const CoachStep(
        title: 'Die Güte der Wege',
        text: 'Hier schaltest du sie ab und wieder an. Sie kommt aus OpenStreetMap — '
            'wo dort nichts eingetragen ist, bleibt der Weg, wie die Karte ihn zeichnet.',
        scene: MapCoach.layersSheet,
        lit: [MapCoach.filterWays],
      ),
      const CoachStep(
        title: 'Was die Striche heißen',
        text: 'Unter „Forstweg" und „Pfad" steht in der Legende, welcher Strich '
            'was bedeutet. Je durchbrochener, desto rauer.',
        scene: MapCoach.legend,
        lit: [MapCoach.legend],
      ),
    ]),
  ),
  'map-legend': HighlightDemo(
    route: '/',
    script: _demo('map-legend', [
      _from(kMapTourScript, 'Farbe heißt Schwierigkeit'),
    ]),
  ),
  'map-layers': HighlightDemo(
    route: '/',
    script: _demo('map-layers', [
      _from(kMapTourScript, 'Was die Karte zeigt'),
      _from(kMapTourScript, 'Orte und offizielle Trails wählen'),
      _from(kMapTourScript, 'Karten ohne Empfang'),
      _from(kMapTourScript, 'Die Werkzeugleiste'),
    ]),
  ),
  'map-select': HighlightDemo(
    route: '/',
    script: _demo('map-select', const [
      CoachStep(
        title: 'Erst auswählen',
        text: 'Ein Tipp auf einen Trail hebt ihn hervor, unten steht eine '
            'kleine Karte mit Navi-Symbol. Ein Tipp auf sie — oder ein zweiter '
            'auf den Trail — öffnet das Blatt; ein Tipp daneben hebt sie auf.',
        lit: [MapCoach.trailBadge],
        gesture: CoachGesture.tap,
        requires: [MapCoach.trailBadge],
      ),
      CoachStep(
        title: 'Langer Druck auf die Karte',
        text: 'Hält man den Finger auf eine Stelle, bietet die Karte „Route ab '
            'hier" (eine Runde mit diesem Start), „Route bis hier" (der Weg von '
            'deinem Standort) und die Navi-App an.',
        lit: [MapCoach.loop],
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'trail-nav': HighlightDemo(
    route: '/trails',
    script: _demo('trail-nav', const [
      CoachStep(
        title: 'Das Navi-Symbol',
        text: 'Mit deiner Navi-App, oder in TrailBuddy: direkt, oder spaßig — '
            'dann nimmt der Weg Abfahrten mit. Einmal als Standard gemerkt, '
            'fragt nur noch ein langer Druck.',
        lit: [TrailsCoach.nav],
        gesture: CoachGesture.tap,
        requires: [TrailsCoach.nav],
      ),
      _noTrailYet,
    ]),
  ),
  'route-vias': HighlightDemo(
    route: '/',
    script: _demo('route-vias', const [
      CoachStep(
        title: 'Zwischenpunkte im Ergebnis',
        text: 'Plane eine Runde oder einen Weg zum Trail. Ein Tipp auf die Linie '
            'setzt einen Punkt; zieh ihn dorthin, wo der Weg langgehen soll. Bei '
            'der Runde bleibt die Reihenfolge der Trails dabei, wie sie ist.',
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'route-elevation': HighlightDemo(
    route: '/',
    script: _demo('route-elevation', const [
      CoachStep(
        title: 'Das Profil im Ergebnis',
        text: 'Plane eine Runde oder einen Weg zum Trail: Unter der Summe steht '
            'das Höhenprofil, von Start bis Ziel. Fehlt einem Stück die Höhe, '
            'bleibt es weg — erfunden wird nichts.',
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'loop-planner': HighlightDemo(
    route: '/',
    script: _demo('loop-planner', [
      const CoachStep(
        title: 'Eine Runde aus deinen Trails',
        text: 'Der Knopf öffnet den Planer: links eine eigene Leiste, und '
            'jeder Trail, den du auf der Karte antippst, kommt in die Runde — '
            'ein zweiter Tipp nimmt ihn wieder heraus.',
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
      CoachStep(
        title: 'Die Leiste des Planers',
        text: 'Oben der Start (Standort oder getippt) und die Parameter — Zeit, '
            'Höhenmeter, Wanderweg, Radius. Darunter die Liste und das Gebiet: '
            'umfahren, und die Trails darin sind dabei. Ganz unten: rechnen.',
        scene: MapCoach.loopRail,
        lit: const [MapCoach.loopRail],
        ring: [MapCoach.loopRailButton('loop-rail-compute')],
        requires: const [MapCoach.loop],
      ),
    ]),
  ),
  'trail-list-filters': HighlightDemo(
    route: '/trails',
    script: _demo('trail-list-filters', const [
      CoachStep(
        title: 'Ausschnitt und S-Grad',
        text: '„Auf der Karte" lässt nur die Trails im Kartenausschnitt stehen — '
            'die Liste zieht mit, wenn du die Karte bewegst. Der S-Grad-Chip '
            'öffnet zwei Schieber für den Bereich. Er gilt auch auf der Karte.',
        lit: [TrailsCoach.chips],
      ),
    ]),
  ),
  'ride-import': HighlightDemo(
    route: '/trails',
    script: _demo('ride-import', const [
      CoachStep(
        title: 'Fahrten aus anderen Apps',
        text: 'Hier liest TrailBuddy GPX- oder Zip-Dateien. In der Android-App '
            'steht unter den Spuren dann „Fahrten für dein Fahrerprofil": Rad '
            'wählen, speichern, lernen lassen. Die Fahrten bleiben auf dem Gerät.',
        lit: [TrailsCoach.import],
      ),
    ]),
  ),
  'route-prefs': HighlightDemo(
    route: '/',
    script: _demo('route-prefs', const [
      CoachStep(
        title: 'Meiden oder egal',
        text: 'Im Planer unter „Parameter": Straßen, Wanderwege bergauf und '
            'steile Rampen je meiden oder egal. Egal heißt nicht umsonst — '
            'nur ein Bruchteil des Aufschlags bleibt. Die Wahl merkt sich das '
            'Gerät, und sie gilt auch für den Weg zum Trail.',
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'steep-climbs': HighlightDemo(
    route: '/',
    script: _demo('steep-climbs', const [
      CoachStep(
        title: 'Flacher, wo es geht',
        text: 'Planer und „Zum Trailkopf" zählen jeden Höhenmeter ab 10 % '
            'Steigung extra, und je steiler, desto mehr — auf Schotter und '
            'Pfad dreifach so viel wie auf Asphalt. Ein Umweg, der flacher '
            'hinaufführt, gewinnt dann. Uphill-Trails zählen nie als zu steil.',
        lit: [MapCoach.loop],
        gesture: CoachGesture.tap,
        requires: [MapCoach.loop],
      ),
    ]),
  ),
  'terrain-heights': HighlightDemo(
    route: '/trails',
    script: _demo('terrain-heights', const [
      _openTrailFirst,
      CoachStep(
        title: 'Höhen ohne Aufzeichnung',
        text: 'Hat kein Beitrag Höhen, kommen sie aus dem Geländemodell (90 m): '
            'mit Empfang vom Kartenhost, sonst aus deinen Bereichen. Die Kachel '
            'trägt dann ein „≈", das Profil sagt es — gespeichert wird nichts.',
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.metrics],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet,
    ]),
  ),
  'gpx-export': HighlightDemo(
    route: '/trails',
    script: _demo('gpx-export', const [
      _openTrailFirst,
      CoachStep(
        title: 'Die Linie als Datei',
        text: 'Gibt den Trail als GPX-Datei weiter — über das Teilen-Menü an '
            'jede App, die GPX liest. Nur die Linie mit Namen; keine Buddys, '
            'keine Hinweise. Fahrten exportierst du unter „Meine Fahrten".',
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.export],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet,
    ]),
  ),
  'trail-head': HighlightDemo(
    route: '/trails',
    script: _demo('trail-head', const [
      _openTrailFirst,
      CoachStep(
        title: 'Der Weg aus deinen Bereichen',
        text: 'Rechnet den Weg von deinem Standort zum Anfang des Trails — '
            'offline, aus den Wegen in deinen gespeicherten Bereichen, nach '
            'deinem Fahrerprofil. Die Karte zeigt die Linie, das Blatt '
            'Höhenmeter und Zeit; als GPX geht sie an jede Navi-App.',
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.trailHead],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet,
    ]),
  ),
  'navigate': HighlightDemo(
    route: '/trails',
    script: _demo('navigate', const [
      _openTrailFirst,
      CoachStep(
        title: 'In die Navi-App',
        text: 'Übergibt den Anfang des Trails an deine Navi-App — du wählst, '
            'welche. Die App selbst baut dabei keine Verbindung auf; ohne '
            'Navi-App landen die Koordinaten in der Zwischenablage.',
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.navigate],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet,
    ]),
  ),
  'trail-ends': HighlightDemo(
    route: '/',
    script: _demo('trail-ends', const [
      CoachStep(
        title: 'Wo es losgeht',
        text: 'Der Punkt am Anfang zeigt mit seinem Pfeil die Fahrtrichtung, '
            'in der Farbe des Trails, ab der Zoomstufe der Schilder.',
        lit: [MapCoach.trailStart],
        requires: [MapCoach.trailStart],
      ),
      CoachStep(
        title: 'Erst einen Trail holen',
        text: 'Das zeigt die Karte an einem Trail. Hol dir einen über GPX aus '
            'einer anderen App, zeichne eine Fahrt auf oder verbinde dich mit '
            'Buddys.',
        lit: [MapCoach.empty],
        unless: [MapCoach.trailStart],
      ),
    ]),
  ),
  'kurzanleitung': HighlightDemo(
    route: '/profile',
    script: _demo('kurzanleitung', [
      _profileRow('help', 'Hier steht sie',
          'Sechs Abschnitte mit den echten Symbolen, dazu die Knöpfe für jede Tour.'),
    ]),
  ),
  'still-valid': HighlightDemo(
    route: '/profile',
    script: _demo('still-valid', [
      CoachStep(
        title: 'Angaben prüfen',
        text: 'Die Zahl sagt, wie viele deiner Meldungen und Zustände älter als '
            '30 Tage sind. Ein Tipp, dann je Trail Ja, Nein oder Weiß nicht.',
        lit: [ProfileCoach.row('still-valid')],
        requires: [ProfileCoach.row('still-valid')],
      ),
      CoachStep(
        title: 'Gerade nichts zu prüfen',
        text: 'Ist eine deiner Angaben älter als 30 Tage, steht hier im Profil '
            '„Noch gültig?" mit der Zahl.',
        unless: [ProfileCoach.row('still-valid')],
      ),
    ]),
  ),
  'marks': HighlightDemo(
    route: '/',
    script: _demo('marks', const [
      CoachStep(
        title: 'Die Fahne kommt mit der Fahrt',
        text: 'Läuft eine Aufzeichnung, steht über diesem Knopf eine Fahne: am '
            'Anfang eines Trails antippen, am Ende noch einmal.',
        lit: [MapCoach.buttons],
        ring: [MapCoach.record],
        requires: [MapCoach.record],
      ),
      _androidOnly,
    ]),
  ),
  'takeover': HighlightDemo(
    route: '/trails',
    script: _demo('takeover', const [
      CoachStep(
        title: 'Beim ersten Befahren',
        text: 'Fährst du einen Trail deiner Buddys, klappt seine Zeile im '
            'Zerlege-Blatt auf: vorbelegt aus dem Netz. Mit deinen Sternen wird er '
            'deiner. Für Trails, die du schon hast, gibt es im Blatt „Übernehmen".',
      ),
    ]),
  ),
  'reports': HighlightDemo(
    route: '/trails',
    script: _demo('reports', const [
      _openTrailFirst,
      CoachStep(
        title: 'Hier melden',
        text: 'Gesperrt, zerstört, verändert — und der Zustand. Bestätigt ist es, '
            'wenn du ihn gefahren hast oder vor Ort bist; sonst steht es als „zu '
            'bestätigen" da.',
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.report],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet,
    ]),
  ),
  'rating': HighlightDemo(
    route: '/trails',
    script: _demo('rating', [
      _openTrailFirst,
      _from(kTrailsTourScript, 'Deine Einschätzung'),
      _noOwnTrail,
      _noTrailYet,
    ]),
  ),
  'grade-colors': HighlightDemo(
    route: '/',
    script: _demo('grade-colors', [_from(kMapTourScript, 'Farbe heißt Schwierigkeit')]),
  ),
  'connect-merge': HighlightDemo(
    route: '/friends',
    script: _demo('connect-merge', const [
      CoachStep(
        title: 'Eine Anfrage annehmen',
        text: 'Nimmst du an, werden gleiche Trails EIN Trail mit zwei Namen. Danach '
            'steht hier, was ihr gemeinsam habt und was neu dazukommt.',
        lit: [BuddysCoach.requests],
        requires: [BuddysCoach.requests],
      ),
      CoachStep(
        title: 'Erst eine Anfrage',
        text: 'Such einen Buddy über den Benutzernamen oder die genaue E-Mail und '
            'frag an. Sobald er annimmt, legt die App eure Trails zusammen.',
        lit: [BuddysCoach.search],
        unless: [BuddysCoach.requests],
      ),
    ]),
  ),
  'import-split': HighlightDemo(
    route: '/trails',
    script: _demo('import-split', [_from(kTrailsTourScript, 'GPX hereinholen')]),
  ),
  'offline-areas': HighlightDemo(
    route: '/',
    script: _demo('offline-areas', [
      _from(kMapTourScript, 'Karten ohne Empfang'),
      _from(kMapTourScript, 'Die Werkzeugleiste'),
    ]),
  ),
  'ride-record': HighlightDemo(
    route: '/',
    script: _demo('ride-record', [_from(kMapTourScript, 'Eine Fahrt aufzeichnen'), _androidOnly]),
  ),
  'official-trails': HighlightDemo(
    route: '/',
    script: _demo('official-trails', [
      _from(kMapTourScript, 'Was die Karte zeigt'),
      _from(kMapTourScript, 'Orte und offizielle Trails wählen'),
    ]),
  ),
  'trail-notes': HighlightDemo(
    route: '/trails',
    script: _demo('trail-notes', [
      _openTrailFirst,
      _from(kTrailsTourScript, 'Etwas Aktuelles erzählen'),
      _noTrailYet,
    ]),
  ),
  // ─── Tipps ─────────────────────────────────────────────────────
  'tours': HighlightDemo(
    route: '/profile/help',
    script: _demo('tours', const [
      CoachStep(
        title: 'Noch einmal ansehen',
        text: 'Hier startest du die Touren für Trails und Buddys neu; darunter die '
            'Tour zum Zerlegen einer Fahrt.',
        lit: [HelpCoach.tabTours],
        scrollIn: HelpCoach.list,
      ),
    ]),
  ),
  'rides-tidy': HighlightDemo(
    route: '/profile',
    script: _demo('rides-tidy', [
      _profileRow('rides', 'In „Meine Fahrten"',
          'An jeder Fahrt steht, ob mit Bio- oder E-Bike gefahren — ein Tipp stellt '
              'es um, und das Fahrerprofil lernt danach richtig. Nach links wischen '
              'löscht, ein langer Druck wählt mehrere.'),
    ]),
  ),
  'pick-section': HighlightDemo(
    route: '/profile',
    script: _demo('pick-section', [
      _profileRow('rides', 'Über „Meine Fahrten"',
          'Die Schere neben einer Fahrt öffnet das Zerlege-Blatt; dort steht unter '
              'den Kandidaten „Stück selbst wählen".'),
    ]),
  ),
  'trail-link': HighlightDemo(
    route: '/trails',
    script: _demo('trail-link', [
      _openTrailFirst,
      _from(kTrailsTourScript, 'Was du beisteuerst'),
      _noOwnTrail,
      _noTrailYet,
    ]),
  ),
  'planned': HighlightDemo(
    route: '/trails',
    script: _demo('planned', [_from(kTrailsTourScript, 'GPX hereinholen')]),
  ),
  'traits': HighlightDemo(
    route: '/trails',
    script: _demo('traits', [_from(kTrailsTourScript, 'Suchen und eingrenzen')]),
  ),
  'grade-votes': HighlightDemo(
    route: '/trails',
    script: _demo('grade-votes', const [
      _openTrailFirst,
      CoachStep(
        title: 'Ein Tipp auf den Grad',
        text: 'Die Kachel zeigt den Median deines Netzes; ein Tipp darauf listet '
            'alle Einschätzungen und erklärt die Skala.',
        scene: TrailsCoach.sheet,
        lit: [SheetCoach.metrics],
        requires: [TrailsCoach.row],
      ),
      _noTrailYet,
    ]),
  ),
  'visibility': HighlightDemo(
    route: '/trails',
    script: _demo('visibility', [
      _openTrailFirst,
      _from(kTrailsTourScript, 'Was du beisteuerst'),
      _noOwnTrail,
      _noTrailYet,
    ]),
  ),
  'pois': HighlightDemo(
    route: '/',
    script: _demo('pois', [
      _from(kMapTourScript, 'Was die Karte zeigt'),
      _from(kMapTourScript, 'Orte und offizielle Trails wählen'),
    ]),
  ),
  'my-position': HighlightDemo(
    route: '/',
    script: _demo('my-position', [_from(kMapTourScript, 'Zu dir und zu uns')]),
  ),
  'buddy-alias': HighlightDemo(
    route: '/friends',
    script: _demo('buddy-alias', [
      _from(kBuddysTourScript, 'Ein Buddy in der Liste'),
      _findBuddyFirst,
    ]),
  ),
  'invite': HighlightDemo(
    route: '/friends',
    script: _demo('invite', [_from(kBuddysTourScript, 'Jemanden einladen')]),
  ),
  'notifications': HighlightDemo(
    route: '/profile',
    script: _demo('notifications', [
      _profileRow('notifications', 'Hier einschalten',
          'Der Schalter sagt, was wirklich ankommt — auch, wenn der Browser oder '
              'Android Benachrichtigungen nicht erlaubt.'),
    ]),
  ),
  'rider-learn': HighlightDemo(
    route: '/profile',
    script: _demo('rider-learn', [
      _profileRow('rider', 'Auf dich eingestellt',
          'Unter „Fahrerprofil" lernt die App aus deinen Aufzeichnungen, wie '
              'schnell du wirklich bergauf kommst — je Profil, nur aus deinen '
              'Fahrten, nur auf diesem Gerät. Die Planer rechnen dann damit.'),
    ]),
  ),
  'rider-profile': HighlightDemo(
    route: '/profile',
    script: _demo('rider-profile', [
      _profileRow('rider', 'Bio-Bike oder E-Bike',
          'Das Profil ändert, wie schnell es bergauf geht, wie teuer ein '
              'Wanderweg bergauf ist und wie viele Höhenmeter eine Runde haben '
              'darf. Jede Fahrt merkt es sich beim Start.'),
    ]),
  ),
  'appearance': HighlightDemo(
    route: '/profile',
    script: _demo('appearance', [
      _profileRow('appearance', 'Hell, dunkel oder wie das System',
          'Gilt für die App; die Karte bleibt hell, in der Sonne liest sie sich '
              'besser.'),
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
