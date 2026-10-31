// Die Erklärtexte der App — Kurzanleitung und Sicherheitshinweis (#131).
//
// Geprüft wird nicht der Wortlaut Zeichen für Zeichen; das wäre ein Test,
// den man bei jeder Verbesserung mitschreibt und der deshalb nichts
// beweist (PilzBuddy `help_texts_test.dart`). Geprüft werden die Zusagen,
// die man wirklich verlieren kann: Umfang, Eindeutigkeit, die Regeln der
// Karte, und dass Anleitung und Oberfläche dasselbe Wort benutzen.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:trailbuddy/features/coach/coach.dart';
import 'package:trailbuddy/features/help/help_screen.dart';
import 'package:trailbuddy/features/help/map_tour.dart';
import 'package:trailbuddy/features/help/split_tour.dart';
import 'package:trailbuddy/features/help/tab_tours.dart';
import 'package:trailbuddy/l10n/l10n.dart';
import 'package:trailbuddy/features/trails/trail_report.dart';

import 'fakes/l10n_de.dart';

void main() {
  HelpStep step(String title) => helpSteps(l10nDe).firstWhere((s) => s.title == title);

  test('Sechs Abschnitte, jeder Titel einmal', () {
    // Sechs sind die Obergrenze: Eine Anleitung, die man scrollen muss,
    // liest niemand zu Ende.
    expect(helpSteps(l10nDe), hasLength(6));
    expect(helpSteps(l10nDe).map((s) => s.title).toSet(), hasLength(6));
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

  test('Die Anleitung sagt, was der Melde-Dialog sagt', () {
    // Bis 0.48.0 hieß das Feld „Status" (Rework E7), bis 0.146 „Meldung";
    // seit #433 ist „Meldung" der ganze Eintrag und das Feld heißt „Der
    // Trail ist …". Hier steht die Beschriftung des Dialogs als Konstante
    // im Text — benennt jemand sie um, zieht die Anleitung mit.
    expect(kReportFieldLabel, 'Der Trail ist …');
    // Der Dialog liest das Wort seit #209 aus den ARB-Dateien.
    expect(l10nDe.reportFieldLabel, kReportFieldLabel);
    expect(step('Dein Beitrag zum Trail').text, contains(kReportFieldLabel));
    expect(helpSteps(l10nDe).any((s) => s.text.contains('Status:')), isFalse,
        reason: 'das alte Feldwort ist zurück');
    expect(helpSteps(l10nDe).any((s) => s.text.contains('Hinweis')), isFalse,
        reason: '„Hinweis" ist seit #433 eine Meldung');
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
    expect(l10nDe.safetyNote, contains('Verantwortung'));
    expect(l10nDe.safetyNote, contains('Sperrungen'));
    // Beide Richtungen einer Meldung: keine Freigabe, und Schweigen heißt
    // nicht frei.
    expect(l10nDe.safetyNote, contains('keine Freigabe'));
    expect(l10nDe.safetyNote, contains('keine Meldung'));
  });

  test('Jeder Tour-Schritt hat eine Kennung, in jeder Sprache dieselbe', () {
    // Vorführungen übernehmen Schritte über die `id` (#209) — der Titel ist
    // je Sprache ein anderer. Fehlte sie oder hinge sie an der Sprache,
    // fände `_from` unter Englisch nichts.
    List<CoachScript> scripts(AppLocalizations l) =>
        [mapTourScript(l), welcomeTourScript(l), splitTourScript(l), ...tabTourScripts(l)];
    final en = lookupAppLocalizations(const Locale('en'));
    final de = scripts(l10nDe);
    for (final (i, script) in de.indexed) {
      final ids = [for (final s in script.steps) s.id];
      expect(ids, everyElement(isNotNull), reason: script.id);
      expect(ids.toSet(), hasLength(ids.length), reason: '${script.id}: doppelt');
      expect([for (final s in scripts(en)[i].steps) s.id], ids, reason: script.id);
      expect([for (final s in scripts(en)[i].steps) s.title], isNot([for (final s in script.steps) s.title]),
          reason: '${script.id}: Englisch zeigt deutsche Titel');
    }
  });
}
