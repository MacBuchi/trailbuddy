// Die Tour im Zerlege-Blatt (#134, Plan `docs/konzept-onboarding.md` 3.4
// und 4.4) — auf derselben Hinweis-Maschine wie die Karten-Tour.
//
// **Warum hier und nicht im Profil.** Das Zerlege-Blatt nach der ersten
// Aufzeichnung ist der Moment, in dem man Hilfe braucht: bekannte Trails,
// Kandidaten mit Griffen, eine Übernahme, eine Nachfrage — alles auf einem
// Blatt, und nichts davon kann man erraten. Deshalb startet sie EINMAL,
// und nur nach einer eigenen Aufzeichnung (`SplitRequest.rideId`), nie aus
// dem GPX-Import.
//
// **Jede Fahrt sieht anders aus**, also hängt fast jeder Schritt an
// `requires`: ohne bekannten Trail kein „Schon bekannt", ohne Wege statt
// der Kandidaten der Ersatzschritt „Erst einen Bereich speichern". Damit
// `requires` die Zeilen weiter unten überhaupt SIEHT, baut das Blatt
// seine faule Liste während dieser Tour ganz (`cacheExtent`); die
// Maschine scrollt das Ziel dann selbst ins Bild.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../coach/coach.dart';
import 'seen_tours.dart';
import 'tour_intro_art.dart';

/// Die Anker im Zerlege-Blatt.
abstract final class SplitCoach {
  /// Die erste bekannte Zeile („wieder gefahren").
  static const known = 'split.known';

  /// Die aufgeklappte Übernahme der ersten Zeile, die ich zum ersten Mal
  /// fahre (#127).
  static const takeOver = 'split.takeover';

  /// Die erste Nachfrage zu einer unbestätigten Meldung (#124).
  static const question = 'split.question';

  /// Der erste Kandidat, seine Griffe und sein Heimzonen-Hinweis.
  static const candidate = 'split.candidate';
  static const range = 'split.range';
  static const home = 'split.home';

  /// „Die Wege kennt die App hier nicht" — ohne gespeicherten Bereich.
  static const noRoads = 'split.noRoads';

  /// „Stück selbst wählen".
  static const pick = 'split.pick';

  /// Der Knopf unten: „n beisteuern" / „Behalten".
  static const submit = 'split.submit';
}

CoachStep splitIntro(AppLocalizations l) => CoachStep(
      id: 'split.intro',
      title: l.tourSplitIntroTitle,
      text: l.tourSplitIntroText,
      art: splitArt,
    );

/// Titel nie wie ein Text im Blatt („Wieder gefahren", „Stück selbst
/// wählen", „Übernehmen" stehen dort) — der Test fände sonst das Element
/// statt der Blase.
CoachScript splitTourScript(AppLocalizations l) => CoachScript(
      id: kSplitTourId,
      steps: [
        splitIntro(l),
        CoachStep(
          id: 'split.known',
          title: l.tourSplitKnownTitle,
          text: l.tourSplitKnownText,
          lit: const [SplitCoach.known],
          requires: const [SplitCoach.known],
        ),
        CoachStep(
          id: 'split.takeOver',
          title: l.tourSplitTakeOverTitle,
          text: l.tourSplitTakeOverText,
          lit: const [SplitCoach.takeOver],
          requires: const [SplitCoach.takeOver],
        ),
        CoachStep(
          id: 'split.question',
          title: l.tourSplitQuestionTitle,
          text: l.tourSplitQuestionText,
          lit: const [SplitCoach.question],
          requires: const [SplitCoach.question],
        ),
        CoachStep(
          id: 'split.candidate',
          title: l.tourSplitCandidateTitle,
          text: l.tourSplitCandidateText,
          // Nur die Griffe, nicht die ganze Karte des Kandidaten: Die ist mit
          // Grad und Charakter so hoch, dass auf einem kleinen Schirm keine
          // Blase mehr daneben passt (360×740 im Test).
          lit: const [SplitCoach.range],
          requires: const [SplitCoach.candidate],
        ),
        CoachStep(
          id: 'split.home',
          title: l.tourSplitHomeTitle,
          text: l.tourSplitHomeText,
          lit: const [SplitCoach.home],
          requires: const [SplitCoach.home],
        ),
        CoachStep(
          id: 'split.noRoads',
          title: l.tourSplitNoRoadsTitle,
          text: l.tourSplitNoRoadsText,
          lit: const [SplitCoach.noRoads],
          requires: const [SplitCoach.noRoads],
        ),
        CoachStep(
          id: 'split.pick',
          title: l.tourSplitPickTitle,
          text: l.tourSplitPickText,
          lit: const [SplitCoach.pick],
          requires: const [SplitCoach.pick],
        ),
        CoachStep(
          id: 'split.submit',
          title: l.tourSplitSubmitTitle,
          text: l.tourSplitSubmitText,
          lit: const [SplitCoach.submit],
        ),
      ],
    );

/// Die Kennung der Zerlege-Tour — der Merker in `seenCoachTours`.
const kSplitTourId = 'split';

/// Eine ausdrücklich gewünschte Zerlege-Tour (aus der Kurzanleitung): Sie
/// läuft beim nächsten Öffnen des Blatts, auch wenn sie gesehen ist.
final requestedSplitTourProvider = StateProvider<bool>((ref) => false);

/// Startet die Tour. Durchgesehen oder übersprungen ⇒ gesehen; „Nicht
/// jetzt" ist kein Gesehen — beim nächsten Blatt nach einer Fahrt fragt
/// sie wieder.
void startSplitTour(AppLocalizations l, WidgetRef ref) {
  final seen = ref.read(seenCoachToursProvider.notifier);
  ref.read(coachProvider.notifier).start(splitTourScript(l), onDone: () => seen.markSeen(kSplitTourId));
}
