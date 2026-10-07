// Die Kurzanleitung (#131, Plan `docs/konzept-onboarding.md` 3.1; Vorlage
// PilzBuddy #350, Baustein A).
//
// **Warum ein Bildschirm aus Widgets und keine mitgelieferte Textdatei.**
// „Was ist neu" liest `CHANGELOG.md` als Asset, und dieselbe Mechanik
// hätte hier nahegelegen. Sie kann aber genau das nicht, worauf es einer
// Anleitung ankommt: das ECHTE Symbol zeigen. Wer das Schild sucht, sucht
// ein Bild, keine Beschreibung eines Bildes — und dieselben Symbole, die
// hier stehen, stehen auf der Karte. Zweiter Grund: Eine `.md` unter
// `assets/` liegt im Binary, wäre für den Version Guard aber eine
// `*.md`-Datei und damit von der Bump-Pflicht ausgenommen — genau die
// Falle, die CLAUDE.md für `CHANGELOG.md` beschreibt. Und eine
// `web/anleitung.html` gibt es auch nicht (Betreiber, Plan 1.2): zwei
// Stellen zu pflegen, und die PWA IST die App.
//
// **Der Umfang ist die Entscheidung.** Erklärt wird, was man nicht
// erraten kann; alles Übrige findet man beim Benutzen. Sechs Abschnitte
// sind die Obergrenze — eine Anleitung, die man scrollen muss, liest
// niemand zu Ende.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/widgets/safety_note.dart';
import '../coach/coach.dart';
import '../trails/grade_shield.dart';
import '../trails/trail_report.dart' show kReportFieldLabel;
import '../rides/ride_providers.dart' show rideRecordingAvailableProvider, ridesProvider;
import '../rides/ride_split_sheet.dart' show SplitRequest, mapSplitRequestProvider;
import 'map_tour.dart';
import 'split_tour.dart';
import 'tab_tours.dart';

/// Ein Abschnitt der Anleitung: Symbol, Überschrift, ein paar Sätze.
class HelpStep {
  const HelpStep({required this.icon, required this.title, required this.text});

  /// Bewusst ein Widget und kein `IconData`: Das Schild ist gezeichnet,
  /// nicht aus Material entnommen.
  final Widget icon;
  final String title;
  final String text;
}

/// Die Abschnitte der Kurzanleitung.
///
/// **Offen und nicht als lokale `const` in `build`**, damit
/// `help_texts_test.dart` einen EINZELNEN Abschnitt prüfen kann statt die
/// Datei als Text (PilzBuddy: die Prüfung über die ganze Datei war aus
/// dem falschen Grund grün, weil das Wort auch in einem anderen Abschnitt
/// stand).
///
/// Die Texte folgen `konzept-trails.md`: Trail ≠ Fahrt ≠ Aufzeichnung;
/// sichtbar sind eigene Beiträge und die direkter Buddys; Fahrt und
/// Position verlassen das Gerät nie.
const kHelpSteps = <HelpStep>[
  HelpStep(
    icon: _HelpIcon(Icons.file_upload_outlined),
    title: 'Trails importieren',
    text: 'GPX- oder Zip-Dateien aus anderen Apps holst du über das Symbol '
        'oben rechts im Reiter „Trails" oder im Profil unter „Trails '
        'importieren". Eine kurze Spur, die überwiegend bergab führt, wird '
        'ein Trail; eine ganze Runde ist eine Fahrt — die zerlegst du über die '
        'Schere im Import in Trails. Nur Trails gehen zu deinen Buddys, nie '
        'die ganze Fahrt.',
  ),
  HelpStep(
    icon: GradeShield(2),
    title: 'Die Karte lesen',
    // Farbe = Schwierigkeit (0.42.0), Linienart = Zustand und S4/S5 auf
    // dem Saum (0.51.0) — `docs/design/README.md` Abschnitt 2. Ändert
    // sich dort eine Regel, gehört dieser Satz in denselben PR.
    text: 'Die Farbe einer Linie ist ihre Schwierigkeit, wie auf der Piste: '
        'grün S0, blau S1, rot S2, schwarz ab S3; ein weiß gestrichelter Saum '
        'heißt S4 oder S5, grau noch ohne Einschätzung, Magenta Uphill. Die '
        'Art der Linie ist der Zustand: durchgezogen heißt alles gut, '
        'bröckelig ausgefahren, gestrichelt abgerockt, verblasst kaum fahrbar. '
        'Ein orangener Rand heißt Meldung (gesperrt, zerstört oder verändert), '
        'ein gelber ein neuer Hinweis; Violett gestrichelt '
        'sind offizielle Trails — die Legende links am Rand der Karte '
        'klappt all das auf. Am Anfang jedes Trails steht sein Schild, '
        'darunter ein Punkt, dessen Pfeil die Fahrtrichtung zeigt. '
        'Ein Tipp aufs Schild oder auf die Linie wählt den Trail aus '
        '— unten steht eine kleine Karte, ein Tipp darauf öffnet das Blatt. Ein '
        'langer Druck auf die Karte bietet „Route ab hier" und „Route bis hier".',
  ),
  HelpStep(
    icon: _HelpIcon(Icons.circle),
    title: 'Fahrt aufzeichnen und zerlegen',
    // Auch in der PWA gezeigt, mit dem Zusatz: Wer die Web-App benutzt,
    // soll wissen, dass es den Weg gibt — nur eben auf dem Telefon.
    text: 'In der Android-App zeichnet der große Knopf unten rechts auf der '
        'Karte eine Fahrt auf — auch ohne Empfang, und sie bleibt auf deinem '
        'Gerät. Unterwegs markierst du mit der Fahne, wo ein Trail beginnt '
        'und endet. Danach zerlegst du die Fahrt: Bekannte Trails erkennt die '
        'App wieder, neue Stücke wählst du selbst. Als GPX exportiert, kannst '
        'du die Fahrt in jede andere App laden. Vorher planst du mit dem '
        'Runden-Knopf eine Runde: Trails antippen (noch einmal heißt ab), links '
        'Parameter, Liste und Gebiet, dann rechnen — offline, aus deinen '
        'gespeicherten Bereichen; sie liegt dann unter „Meine Fahrten". In der '
        'Web-App gibt es keine Aufzeichnung.',
  ),
  HelpStep(
    icon: _HelpIcon(Icons.group_outlined),
    title: 'Buddys und Sichtbarkeit',
    text: 'Du siehst deine Trails und die deiner direkten Buddys — sonst '
        'niemandes, eine öffentliche Karte gibt es nicht. Buddys findest du '
        'im Reiter „Buddys" über den Benutzernamen oder die genaue E-Mail. '
        'Sind zwei Aufzeichnungen derselbe Weg, werden sie EIN Trail, auch '
        'mit zwei Namen. Was du „Nur für mich" stellst, sieht niemand.',
  ),
  HelpStep(
    icon: _HelpIcon(Icons.edit),
    title: 'Dein Beitrag zum Trail',
    // „Meldung" ist die Beschriftung im Melde-Dialog (`kReportFieldLabel`,
    // bis 0.48.0 „Status") — `help_texts_test.dart` hält beide zusammen.
    text: 'Im Blatt eines Trails, den du selbst beigesteuert hast, trägst du unter „Mein '
        'Beitrag" Name, S-Grad, Charakter, Sterne, Sichtbarkeit, Beschreibung '
        'und einen Link ein. „Melden" sagt, was gerade gilt — die '
        '$kReportFieldLabel (gesperrt, zerstört, verändert) und der Zustand; '
        'bestätigt ist sie, wenn du ihn gefahren hast oder vor Ort bist. Ein '
        'Hinweis erzählt Buddys, was los ist, und leuchtet bei ihnen gelb. '
        'Das Navi-Symbol oben im Blatt übergibt den Anfang des Trails an '
        'deine Navi-App; „Zum '
        'Trailkopf" rechnet den Weg dorthin selbst — offline, aus deinen '
        'gespeicherten Bereichen, mit Höhenmetern und Zeit.',
  ),
  HelpStep(
    icon: _HelpIcon(Icons.wifi_off),
    title: 'Ohne Empfang',
    text: 'Deine Trails zeigt die App auch offline, mit dem Stand deines '
        'letzten Abrufs. Was du ohne Netz beisteuerst oder meldest, wartet im '
        'Ausgangskorb und geht los, sobald du wieder Empfang hast. Damit die '
        'Karte etwas zeigt, speicherst du vorher einen Bereich: Knopf '
        '„Offline-Karten" auf der Karte, dann zeichnen; verwalten unter „Meine Bereiche" im '
        'Profil — am besten zu Hause im WLAN.',
  ),
];

/// Zeigt in sechs Schritten, wie TrailBuddy benutzt wird.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kurzanleitung')),
      body: CoachAnchor(
        id: HelpCoach.list,
        child: ListView(
        key: const ValueKey('help-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Das Wichtigste in sechs Schritten. Alles andere findest du beim '
            'Ausprobieren.',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppPalette.of(context).muted),
          ),
          const SizedBox(height: 12),
          // Ganz oben und nicht am Ende: Wer die Kurzanleitung öffnet, soll
          // den Hinweis nicht erst finden müssen.
          const SafetyNoteTile(),
          for (final step in kHelpSteps) _StepTile(step: step),
          const SizedBox(height: 24),
          // Der Wiederaufruf der Tour (#132). Hier und nicht als eigene
          // Zeile im Profil: Wer die Tour sucht, sucht eine Erklärung — und
          // landet ohnehin hier.
          OutlinedButton.icon(
            key: const ValueKey('help-map-tour'),
            onPressed: () {
              // Erst die Karte, dann die Tour: Ihre Anker hängen am
              // Karten-Screen, und dessen Reiter muss sichtbar sein.
              context.go('/');
              startMapTour(ref);
            },
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Tour auf der Karte zeigen'),
          ),
          const SizedBox(height: 8),
          // Die Reiter-Touren (#136) laufen von selbst beim ersten Besuch;
          // hier noch einmal auf Wunsch. Erst der Wunsch, dann der Reiter —
          // sie startet, sobald er sichtbar ist.
          CoachAnchor(
            id: HelpCoach.tabTours,
            child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (label, route, script) in const [
                ('Trails', '/trails', kTrailsTourScript),
                ('Buddys', '/friends', kBuddysTourScript),
              ])
                OutlinedButton.icon(
                  key: ValueKey('tab-tour-${script.id}'),
                  onPressed: () {
                    ref.read(requestedTabTourProvider.notifier).request(script.id);
                    context.go(route);
                  },
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: Text('Tour: $label'),
                ),
            ],
          )),
          // Die Zerlege-Tour (#134), nur wo man aufzeichnen kann: Sie
          // öffnet die jüngste Fahrt, und dort läuft die Tour.
          if (ref.watch(rideRecordingAvailableProvider)) ...[
            const SizedBox(height: 8),
            const _SplitTourButton(),
          ],
          const SizedBox(height: 8),
          // Alles, was über die sechs Abschnitte hinausgeht (#135) — die
          // Kurzanleitung bleibt kurz, weil es diesen Weg gibt.
          OutlinedButton.icon(
            key: const ValueKey('help-discover'),
            onPressed: () => context.push('/profile/discover'),
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('Funktionen und Tipps entdecken'),
          ),
        ],
      )),
    );
  }
}

/// Ein Material-Symbol in der Farbe, die es auf seinem Knopf trägt.
class _HelpIcon extends StatelessWidget {
  const _HelpIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 24, color: AppPalette.of(context).accentText);
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final HelpStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Feste Breite statt eines ListTile-`leading`: Das Schild bringt
          // seine eigene Breite mit, und ohne Rahmen stünden die
          // Überschriften unterschiedlich weit eingerückt. `scaleDown`,
          // falls es mit großer Systemschrift breiter wird als der Rahmen.
          SizedBox(
            width: 40,
            child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: step.icon)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(step.text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// „Tour: Fahrt zerlegen" (#134): öffnet die jüngste Fahrt im
/// Zerlege-Blatt und bestellt dort die Tour. Ohne Fahrt deaktiviert, mit
/// einem Satz, wie eine entsteht.
class _SplitTourButton extends ConsumerWidget {
  const _SplitTourButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rides = ref.watch(ridesProvider).valueOrNull ?? const [];
    final latest = rides.isEmpty
        ? null
        : rides.reduce((a, b) => a.startedAt.isAfter(b.startedAt) ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('help-split-tour'),
          onPressed: latest == null
              ? null
              : () {
                  // Erst der Reiter, dann der Wunsch — wie „Meine Fahrten".
                  ref.read(requestedSplitTourProvider.notifier).state = true;
                  context.go('/');
                  ref.read(mapSplitRequestProvider.notifier).state = SplitRequest.fromRide(latest);
                },
          icon: const Icon(Icons.content_cut),
          label: const Text('Tour: Fahrt zerlegen'),
        ),
        if (latest == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Zeichne erst eine Fahrt auf — der große Knopf auf der Karte. '
              'Danach zeigt die Tour an ihr, wie aus einer Fahrt Trails werden.',
              key: const ValueKey('help-split-tour-hint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.of(context).muted),
            ),
          ),
      ],
    );
  }
}
