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

/// Highlight (ins Blatt) oder Tipp (nur „Entdecken").
enum HighlightKind { highlight, tip }

/// Wo die Funktion wohnt — die Gruppen der Seite „Entdecken", in der
/// Reihenfolge der Reiterleiste.
enum HighlightTab {
  map('Karte'),
  trails('Trails'),
  buddys('Buddys'),
  profile('Profil');

  const HighlightTab(this.label);
  final String label;
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

  final String title;

  /// Zwei, höchstens drei Sätze.
  final String text;

  /// Wohin „Ausprobieren" führt: eine Route der App.
  final String target;
}

const kFeatureHighlights = <FeatureHighlight>[
  // ─── Highlights ──────────────────────────────────────────────────
  FeatureHighlight(
    id: 'route-elevation',
    since: '0.88.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.alt_route,
    title: 'Höhenprofil der Runde',
    text: 'Unter der Summe einer geplanten Runde steht jetzt ihr Höhenprofil, '
        'kompakt über die ganze Strecke — ebenso beim Weg zum Trail. Die Höhen '
        'kommen aus dem Geländemodell deiner Bereiche.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'rides-tidy',
    since: '0.85.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.profile,
    icon: Icons.electric_bike_outlined,
    title: 'Meine Fahrten aufräumen',
    text: 'An jeder Fahrt steht ihr Rad, ein Tipp stellt es um. Nach links wischen '
        'löscht, ein langer Druck wählt mehrere. Beim GPX-Import schlägt die App '
        'das Rad nach der Steigrate vor.',
    target: '/profile/rides',
  ),
  FeatureHighlight(
    id: 'trail-list-filters',
    since: '0.84.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.tune,
    title: 'Filter nach Ausschnitt und S-Grad',
    text: '„Auf der Karte" zeigt in der Liste nur die Trails im Kartenausschnitt. '
        'Den S-Grad stellst du als Bereich ein, etwa „ab S3" oder „S1–S3".',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'ride-import',
    since: '0.82.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.file_upload_outlined,
    title: 'Alte Fahrten zählen mit',
    text: 'Fahrten aus anderen Apps holst du per GPX-Import in „Meine Fahrten" — '
        'mit dem Rad, mit dem du sie gefahren bist. Das Fahrerprofil lernt dann '
        'auch aus ihnen, wie schnell du bergauf kommst.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'route-prefs',
    since: '0.81.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.tune,
    title: 'Wege nach deinem Geschmack',
    text: 'Straßen, Wanderwege bergauf, steile Rampen: In den Parametern des '
        'Planers sagst du je, ob du sie meidest oder ob sie dir egal sind. Das '
        'gilt für Runden und den Weg zum Trail.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'steep-climbs',
    since: '0.80.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.trending_up,
    title: 'Steile Rampen meiden',
    text: 'Runden und Wege zum Trail weichen sehr steilen Anstiegen aus, wo es '
        'flacher geht — je steiler, desto stärker, auf Schotter und Pfad mehr '
        'als auf Asphalt. Uphill-Trails bleiben gewollt.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'terrain-heights',
    since: '0.79.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.terrain,
    title: 'Höhen aus dem Geländemodell',
    text: 'Fehlen einem Trail die Höhen, zeigt das Blatt sein Profil aus dem '
        'Geländemodell — beschriftet und nie gespeichert. Der Import prüft die '
        'Höhen einer Datei und bietet an, schlechte zu verwerfen.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'online-fill',
    since: '0.78.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.cloud_download_outlined,
    title: 'Runden auch ohne Bereich',
    text: 'Mit Empfang holt der Planer die Wege, die deinen Bereichen fehlen, '
        'vom Kartenhost — eine Runde geht dann auch ohne gespeicherten Bereich. '
        'Abschalten kannst du es unter Parameter.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'map-legend',
    since: '0.77.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.legend_toggle,
    title: 'Die Legende auf der Karte',
    text: 'Links am Rand steht eine schmale Lasche mit den Pistenfarben. Ein '
        'Tipp klappt die Legende auf — Farben, Linienarten, Ränder —, ein '
        'zweiter wieder zu. Die App merkt sich, wie du sie magst.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'map-layers',
    since: '0.75.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.layers_outlined,
    title: 'Ebenen mit einem Tipp',
    text: 'Der oberste Knopf rechts öffnet die Kartenebenen direkt: Trail-Filter, '
        'offizielle Trails und Orte in einem Blatt. Die Offline-Karten haben '
        'ihren eigenen Knopf darunter, die Glühbirne steht jetzt oben rechts.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'map-select',
    since: '0.74.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.touch_app_outlined,
    title: 'Trail antippen, Route ab hier',
    text: 'Ein Tipp hebt einen Trail hervor und zeigt unten eine kleine Karte; '
        'ein zweiter öffnet sein Blatt. Ein langer Druck auf die Karte bietet '
        '„Route ab hier" und „Route bis hier".',
    target: '/',
  ),
  FeatureHighlight(
    id: 'trail-nav',
    since: '0.74.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.navigation_outlined,
    title: 'Zum Trail navigieren',
    text: 'Das Navi-Symbol an jedem Trail: mit deiner Navi-App, oder in '
        'TrailBuddy direkt oder spaßig — dann nimmt der Weg Trails mit. Was du '
        'meistens willst, merkt es sich.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'loop-planner',
    since: '0.72.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.alt_route,
    title: 'Runde planen',
    text: 'Der Runden-Knopf öffnet den Planer: Trails antippen, links Start, '
        'Parameter, Liste und Gebiet — die App verbindet sie bergab über die '
        'Wege deiner Bereiche, offline. Als geplante Fahrt oder GPX.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'gpx-export',
    since: '0.68.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.share_outlined,
    title: 'Trails und Fahrten als GPX',
    text: 'Jeder Trail und jede Fahrt lässt sich als GPX-Datei weitergeben — '
        'an Komoot, Garmin, eine Navi-App oder als Sicherung. Trails im Blatt, '
        'Fahrten unter „Meine Fahrten".',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'trail-head',
    since: '0.71.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.route_outlined,
    title: 'Zum Trailkopf, offline',
    text: '„Zum Trailkopf" im Blatt rechnet den Weg von deinem Standort zum '
        'Anfang des Trails — aus deinen gespeicherten Bereichen, ohne Netz: '
        'Linie auf der Karte, Höhenmeter, Zeit, und ob ein Wanderweg dabei ist.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'navigate',
    since: '0.67.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.directions_outlined,
    title: 'Anfahrt zum Trail',
    text: 'Das Navi-Symbol oben im Blatt übergibt den Anfang des Trails an '
        'deine Navi-App — welche, entscheidest du im Wähler. Ohne Navi-App '
        'landen die Koordinaten in der Zwischenablage.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'trail-ends',
    since: '0.66.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.trending_flat,
    title: 'Anfang und Richtung',
    text: 'Jeder Trail hat einen Punkt mit Pfeil am Anfang, in seiner '
        'Farbe. So siehst du auf der Karte, wo es losgeht und in welche '
        'Richtung.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'kurzanleitung',
    since: '0.59.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.profile,
    icon: Icons.help_outline,
    title: 'Die Kurzanleitung',
    text: 'Das Wichtigste in sechs Schritten, mit den echten Symbolen — und '
        'von dort startest du jede Tour noch einmal.',
    target: '/profile/help',
  ),
  FeatureHighlight(
    id: 'still-valid',
    since: '0.58.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.fact_check_outlined,
    title: 'Noch gültig?',
    text: 'Sind deine Meldungen und Zustände älter als 30 Tage, fragt das '
        'Profil nach: Ja, Nein oder Weiß nicht — dann in 14 Tagen wieder.',
    target: '/profile',
  ),
  FeatureHighlight(
    id: 'marks',
    since: '0.57.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.flag_outlined,
    title: 'Trail beginnt, Trail endet',
    text: 'Während einer Aufzeichnung steht über dem Aufnahmeknopf eine Fahne. '
        'Am Anfang und am Ende eines Trails antippen — im Zerlege-Blatt ist '
        'das Stück dann schon angehakt.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'takeover',
    since: '0.55.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.bookmark_add_outlined,
    title: 'Einen Buddy-Trail zu deinem machen',
    text: 'Fährst du einen Trail deiner Buddys zum ersten Mal, übernimmst du '
        'ihn im Zerlege-Blatt mit deinen Sternen. Dann bleibt er dir, auch '
        'wenn der Buddy seinen Beitrag löscht.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'reports',
    since: '0.49.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.flag_outlined,
    title: 'Melden, was gerade gilt',
    text: '„Melden" im Blatt sagt, ob ein Trail gesperrt, zerstört oder '
        'verändert ist, und wie er gerade aussieht — von kaum fahrbar bis top '
        'gepflegt. Bestätigt ist es, wenn du ihn gefahren hast oder vor Ort bist.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'rating',
    since: '0.49.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.star_outline_rounded,
    title: 'Sterne für Trails',
    text: 'Trails, die du gefahren bist, bewertest du mit ein bis fünf Sternen. '
        'Die Liste sortiert auf Wunsch danach.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'grade-colors',
    since: '0.42.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.palette_outlined,
    title: 'Farbe heißt Schwierigkeit',
    text: 'Wie auf der Piste: grün S0, blau S1, rot S2, schwarz ab S3. Die Art '
        'der Linie sagt den Zustand, ein gestrichelter Saum S4 oder S5.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'connect-merge',
    since: '0.22.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.buddys,
    icon: Icons.merge_type,
    title: 'Verbinden heißt zusammenlegen',
    text: 'Nimmst du eine Anfrage an, werden gleiche Trails EIN Trail mit zwei '
        'Namen. Die Karte danach sagt, was ihr gemeinsam habt und was neu ist.',
    target: '/friends',
  ),
  FeatureHighlight(
    id: 'import-split',
    since: '0.20.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.content_cut,
    title: 'Aus einer Fahrt werden Trails',
    text: 'Eine ganze Runde zerlegst du mit der Schere: Bekannte Trails erkennt '
        'die App wieder, neue schlägt sie vor. Zu Buddys gehen nur die '
        'gewählten Stücke.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'offline-areas',
    since: '0.19.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.download_for_offline_outlined,
    title: 'Karten für unterwegs',
    text: 'Unter „Offline-Karten" zeichnest du einen Bereich, den die App '
        'speichert — dann steht die Karte auch ohne Empfang. „Meine Bereiche" '
        'im Profil verwaltet sie.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'ride-record',
    since: '0.13.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.circle,
    title: 'Eine Fahrt aufzeichnen',
    text: 'In der Android-App zeichnet der große Knopf deine Fahrt auf, auch '
        'ohne Empfang. Sie bleibt auf deinem Gerät, bis du sie zerlegst.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'official-trails',
    since: '0.10.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.verified_outlined,
    title: 'Offizielle Trails',
    text: 'Vom Land ausgewiesene Singletrails, gestrichelt in Violett — mit '
        'Status und Quelle. Ein- und ausschalten unter „Kartenebenen".',
    target: '/',
  ),
  FeatureHighlight(
    id: 'trail-notes',
    since: '0.8.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.trails,
    icon: Icons.add_comment_outlined,
    title: 'Hinweise für Buddys',
    text: '„Baum liegt quer": Ein Hinweis im Blatt erzählt deinen Buddys, was '
        'gerade los ist. Bei ihnen leuchtet der Trail gelb, bis sie ihn gelesen '
        'haben.',
    target: '/trails',
  ),
  // ─── Tipps ───────────────────────────────────────────────────────
  FeatureHighlight(
    id: 'tours',
    since: '0.63.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.profile,
    icon: Icons.play_circle_outline,
    title: 'Touren noch einmal ansehen',
    text: 'Karte, Trails, Buddys und das Zerlegen einer Fahrt erklären sich in '
        'kurzen Touren. Neu starten: Profil → Kurzanleitung.',
    target: '/profile/help',
  ),
  FeatureHighlight(
    id: 'pick-section',
    since: '0.47.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.content_cut,
    title: 'Ein Stück selbst wählen',
    text: 'Findet die Suche im Zerlege-Blatt eine Jump-Line nicht, legt „Stück '
        'selbst wählen" einen Kandidaten über die ganze Fahrt — die Griffe '
        'machen den Rest.',
    target: '/profile/rides',
  ),
  FeatureHighlight(
    id: 'trail-link',
    since: '0.48.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.open_in_new,
    title: 'Ein Link zur Quelle',
    text: 'In „Mein Beitrag" kann ein Trail auf eine Seite zeigen, etwa die des '
        'Vereins. Das Blatt nennt die Adresse, geöffnet wird im Browser.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'planned',
    since: '0.46.1',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.edit_calendar_outlined,
    title: 'Geplant oder gefahren',
    text: 'Eine GPX-Datei ohne Fahrzeiten gilt als nur geplant. Bist du ihn '
        'gefahren, trägst du beim Import „Gefahren am …" ein.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'traits',
    since: '0.34.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.terrain_outlined,
    title: 'Der Charakter eines Trails',
    text: 'Flowig, Jump-Line, verblockt, steil, Uphill: Die zwei häufigsten '
        'Angaben stehen am Schild — und die Filter „Flowig" und „Jumps" suchen '
        'danach.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'grade-votes',
    since: '0.4.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.bar_chart,
    title: 'Wer wie eingeschätzt hat',
    text: 'Ein Tipp auf den S-Grad im Blatt zeigt alle Einschätzungen deines '
        'Netzes — und was S0 bis S5 bedeuten.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'visibility',
    since: '0.1.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.trails,
    icon: Icons.visibility_off_outlined,
    title: 'Nur für mich',
    text: 'In „Mein Beitrag" hältst du einen Trail vor deinen Buddys verborgen. '
        'Er bleibt auf deiner Karte.',
    target: '/trails',
  ),
  FeatureHighlight(
    id: 'pois',
    since: '0.5.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.map,
    icon: Icons.layers_outlined,
    title: 'Orte auf der Karte',
    text: 'Einkehr, Wasser, Rad-Service: Welche Orte die Karte zeigt, wählst du '
        'unter „Kartenebenen", dem obersten Knopf rechts.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'my-position',
    since: '0.12.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.map,
    icon: Icons.my_location,
    title: 'Wo bin ich?',
    text: 'Der Positionsknopf holt die Karte zu dir. Dein Standort verlässt das '
        'Gerät nie.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'buddy-alias',
    since: '0.1.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.buddys,
    icon: Icons.edit_outlined,
    title: 'Ein eigener Name für Buddys',
    text: 'Der Stift neben einem Buddy gibt ihm einen Namen, den nur du siehst '
        '— überall in der App.',
    target: '/friends',
  ),
  FeatureHighlight(
    id: 'invite',
    since: '0.1.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.buddys,
    icon: Icons.share,
    title: 'Buddys einladen',
    text: 'Oben rechts im Reiter „Buddys": ein Link zu TrailBuddy mit deinem '
        'Benutzernamen, damit man dich gleich findet.',
    target: '/friends',
  ),
  FeatureHighlight(
    id: 'notifications',
    since: '0.37.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.profile,
    icon: Icons.notifications_outlined,
    title: 'Benachrichtigungen',
    text: 'Meldet ein Buddy einen Trail oder schreibt einen Hinweis, sagt es dir '
        'dein Telefon — einschalten im Profil.',
    target: '/profile/notifications',
  ),
  FeatureHighlight(
    id: 'rider-learn',
    since: '0.73.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.profile,
    icon: Icons.school_outlined,
    title: 'Gelernt aus deinen Fahrten',
    text: 'Unter „Fahrerprofil": „Aus meinen Fahrten lernen" liest Zeit und '
        'GPS-Höhe deiner Aufzeichnungen und stellt Steigrate und '
        'Flachgeschwindigkeit je Profil auf dich ein. Zurücksetzen geht jederzeit.',
    target: '/profile/rider',
  ),
  FeatureHighlight(
    id: 'rider-profile',
    since: '0.70.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.profile,
    icon: Icons.pedal_bike_outlined,
    title: 'Bio-Bike oder E-Bike',
    text: 'Unter „Fahrerprofil" im Profil: wie schnell es bergauf geht, wie '
        'teuer ein Wanderweg ist, wie viele Höhenmeter eine Runde haben darf. '
        'Die Routenplanung rechnet damit; jede Fahrt merkt es sich.',
    target: '/profile/rider',
  ),
  FeatureHighlight(
    id: 'appearance',
    since: '0.28.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.profile,
    icon: Icons.contrast,
    title: 'Hell oder dunkel',
    text: 'Unter „Erscheinungsbild" im Profil — oder wie das System. Die Karte '
        'bleibt hell, in der Sonne liest sie sich besser.',
    target: '/profile/appearance',
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
  List<FeatureHighlight> all = kFeatureHighlights,
  List<String> recapLead = kRecapLead,
}) {
  if (current == null || !_isVersion(current)) return const HighlightNothing();
  final shipped = [
    for (final h in all)
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
      if (a.since == b.since) return all.indexOf(a) - all.indexOf(b);
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
