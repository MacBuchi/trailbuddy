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
import '../../l10n/l10n.dart';
import '../coach/coach.dart';
import '../trails/grade_shield.dart';
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
/// **Offen und nicht als lokale Liste in `build`**, damit
/// `help_texts_test.dart` einen EINZELNEN Abschnitt prüfen kann statt die
/// Datei als Text (PilzBuddy: die Prüfung über die ganze Datei war aus
/// dem falschen Grund grün, weil das Wort auch in einem anderen Abschnitt
/// stand).
///
/// Die Texte folgen `konzept-trails.md`: Trail ≠ Fahrt ≠ Aufzeichnung;
/// sichtbar sind eigene Beiträge und die direkter Buddys; Fahrt und
/// Position verlassen das Gerät nie.
///
/// Eine Funktion seit #209: Die Texte kommen aus den ARB-Dateien.
List<HelpStep> helpSteps(AppLocalizations l) => [
      HelpStep(
        icon: const _HelpIcon(Icons.file_upload_outlined),
        title: l.helpImportTitle,
        text: l.helpImportText,
      ),
      HelpStep(
        icon: const GradeShield(2),
        title: l.helpMapTitle,
        // Farbe = Schwierigkeit (0.42.0), Linienart = Zustand und S4/S5 auf
        // dem Saum (0.51.0) — `docs/design/README.md` Abschnitt 2. Ändert
        // sich dort eine Regel, gehört dieser Satz in denselben PR.
        text: l.helpMapText,
      ),
      HelpStep(
        icon: const _HelpIcon(Icons.circle),
        title: l.helpRideTitle,
        // Auch in der PWA gezeigt, mit dem Zusatz: Wer die Web-App benutzt,
        // soll wissen, dass es den Weg gibt — nur eben auf dem Telefon.
        text: l.helpRideText,
      ),
      HelpStep(
        icon: const _HelpIcon(Icons.group_outlined),
        title: l.helpBuddysTitle,
        text: l.helpBuddysText,
      ),
      HelpStep(
        icon: const _HelpIcon(Icons.edit),
        title: l.helpContributionTitle,
        // „Meldung" ist die Beschriftung im Melde-Dialog (`reportFieldLabel`,
        // bis 0.48.0 „Status") — `help_texts_test.dart` hält beide zusammen.
        text: l.helpContributionText(l.reportFieldLabel),
      ),
      HelpStep(
        icon: const _HelpIcon(Icons.wifi_off),
        title: l.helpOfflineTitle,
        text: l.helpOfflineText,
      ),
    ];

/// Zeigt in sechs Schritten, wie TrailBuddy benutzt wird.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.helpTitle)),
      body: CoachAnchor(
        id: HelpCoach.list,
        child: ListView(
        key: const ValueKey('help-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            l.helpIntro,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppPalette.of(context).muted),
          ),
          const SizedBox(height: 12),
          // Ganz oben und nicht am Ende: Wer die Kurzanleitung öffnet, soll
          // den Hinweis nicht erst finden müssen.
          const SafetyNoteTile(),
          for (final step in helpSteps(l)) _StepTile(step: step),
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
              startMapTour(l, ref);
            },
            icon: const Icon(Icons.play_circle_outline),
            label: Text(l.helpMapTour),
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
              for (final (label, route, id) in [
                (l.tabTrails, '/trails', kTrailsTourId),
                (l.tabBuddys, '/friends', kBuddysTourId),
              ])
                OutlinedButton.icon(
                  key: ValueKey('tab-tour-$id'),
                  onPressed: () {
                    ref.read(requestedTabTourProvider.notifier).request(id);
                    context.go(route);
                  },
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: Text(l.helpTabTour(label)),
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
            label: Text(l.helpDiscover),
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
          label: Text(context.l10n.helpSplitTour),
        ),
        if (latest == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              context.l10n.helpSplitTourHint,
              key: const ValueKey('help-split-tour-hint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.of(context).muted),
            ),
          ),
      ],
    );
  }
}
