// Die Erklärtexte der App — Kurzanleitung und Sicherheitshinweis (#131).
//
// Geprüft wird nicht der Wortlaut Zeichen für Zeichen; das wäre ein Test,
// den man bei jeder Verbesserung mitschreibt und der deshalb nichts
// beweist (PilzBuddy `help_texts_test.dart`). Geprüft werden die Zusagen,
// die man wirklich verlieren kann: Umfang, Eindeutigkeit, die Regeln der
// Karte, und dass Anleitung und Oberfläche dasselbe Wort benutzen.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/widgets/safety_note.dart';
import 'package:trailbuddy/features/help/help_screen.dart';
import 'package:trailbuddy/features/trails/trail_report.dart';

import 'fakes/l10n_de.dart';

void main() {
  HelpStep step(String title) => kHelpSteps.firstWhere((s) => s.title == title);

  test('Sechs Abschnitte, jeder Titel einmal', () {
    // Sechs sind die Obergrenze: Eine Anleitung, die man scrollen muss,
    // liest niemand zu Ende.
    expect(kHelpSteps, hasLength(6));
    expect(kHelpSteps.map((s) => s.title).toSet(), hasLength(6));
  });

  test('„Die Karte lesen" nennt die Regeln der Karte', () {
    // Farbe = Schwierigkeit, Linienart = Zustand, S4/S5 auf dem Saum
    // (docs/design/README.md Abschnitt 2). Ändert sich eine Regel, soll
    // dieser Test den Satz daran erinnern.
    final text = step('Die Karte lesen').text;
    for (final word in ['S0', 'S3', 'Saum', 'S4', 'Magenta', 'Zustand', 'gestrichelt', 'orange', 'gelb',
      'Violett', 'Schild']) {
      expect(text, contains(word), reason: 'fehlt: $word');
    }
  });

  test('Die Anleitung sagt „Meldung" wie der Melde-Dialog', () {
    // Bis 0.48.0 hieß die Meldung „Status" (Rework E7). Hier steht die
    // Beschriftung des Dialogs als Konstante im Text — benennt jemand sie
    // um, zieht die Anleitung mit, und der Test hält fest, dass das Wort
    // überhaupt darin vorkommt.
    expect(kReportFieldLabel, 'Meldung');
    // Der Dialog liest das Wort seit #209 aus den ARB-Dateien.
    expect(l10nDe.reportFieldLabel, kReportFieldLabel);
    expect(step('Dein Beitrag zum Trail').text, contains(kReportFieldLabel));
    expect(kHelpSteps.any((s) => s.text.contains('Status')), isFalse,
        reason: 'das alte Wort ist zurück');
  });

  test('Sichtbarkeit: nur direkte Buddys, keine öffentliche Karte', () {
    // Konzept 12: nichts wird über Netze hinweg gerechnet.
    final text = step('Buddys und Sichtbarkeit').text;
    expect(text, contains('direkten Buddys'));
    expect(text, contains('öffentliche Karte'));
  });

  test('Eine Fahrt bleibt auf dem Gerät, nur Trails gehen zu Buddys', () {
    expect(step('Trails importieren').text, contains('Nur Trails gehen zu deinen Buddys'));
    expect(step('Fahrt aufzeichnen und zerlegen').text, contains('auf deinem Gerät'));
    expect(step('Fahrt aufzeichnen und zerlegen').text, contains('Web-App'),
        reason: 'die PWA zeigt den Abschnitt auch — mit dem Zusatz');
  });

  test('Der Sicherheitshinweis nennt Verantwortung und Sperrungen', () {
    expect(kSafetyNote, contains('Verantwortung'));
    expect(kSafetyNote, contains('Sperrungen'));
    // Beide Richtungen einer Meldung: keine Freigabe, und Schweigen heißt
    // nicht frei.
    expect(kSafetyNote, contains('keine Freigabe'));
    expect(kSafetyNote, contains('keine Meldung'));
  });
}
