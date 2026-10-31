# TrailBuddy — Konzept: Hinweis und Meldung werden eins (#433)

Stand 2026-10-31. Feldbericht aus 0.142.0 (#433): „Hinweis und Meldung
müssen wir irgendwie zusammenfassen, das macht keinen Sinn, das
aufzutrennen. Das Foto-Feature dafür ist schon gut. […] Was ich aber
trennen würde, ist der Trail-Zustand, denn der ist eher langfristig und
nicht einfach eine Meldung.“ Dieses Konzept beschreibt, wie das gebaut
wird. Bis der Bau gemergt ist, gilt `konzept-trails.md` Abschnitt 3 in
der heutigen Form; der Bau-PR zieht ihn nach.

## 1. Heute

Im Trail-Blatt gibt es drei Dinge, und zwei davon tun fast dasselbe:

| | Hinweis (#7) | Meldung (#101) | Zustand (#101) |
|---|---|---|---|
| Inhalt | Text bis 500 Zeichen, ein Foto (#37) | offen / gesperrt / zerstört / verändert | 1–5 |
| Tabelle | `trail_notes` (+ `trail_note_photos`) | `trail_reports`, `kind = 'status'` | `trail_reports`, `kind = 'condition'` |
| Sehen | Autor und seine direkten Buddys, die den Trail sehen; nicht bei „privat“ | jeder, der den Trail sieht (`can_see_trail`) | wie Meldung |
| Dauer | 90 Tage, der jüngste je Autor bleibt; „erledigt“ entfernt; Foto 90 Tage hart | bleibt, bis jemand anderes meldet; Verlauf 90 Tage | dauerhaft mit Alter |
| Bestätigt | — | gefahren oder vor Ort (`report_trail`) | wie Meldung |
| Wirkt auf | gelber Rand „neuer Hinweis“, Push | Warnfarbe, Filter „Gemeldet“, Planer (#434), Push | Linienstil, Wort in der Liste |
| Eingang | Knopf „Hinweis schreiben“ (mit Foto) | Knopf „Melden“: Status, Zustand und Text, aber ohne Foto | im Dialog „Melden“ und im Zerlege-Blatt |

Damit gibt es zwei Wege zu einem Text am Trail: Der eine kann ein Foto
anhängen, der andere einen Status setzen. Unten im Blatt stehen dann zwei
Listen („Hinweise“ und „MELDUNGEN“), die ein und dieselbe Sache von zwei
Seiten zeigen.

## 2. Entscheidungen des Betreibers (2026-10-31)

Wortlaut der Antworten in #433:

1. **Ein Dialog „Melden“**: Text und Foto, dazu wahlweise ein Status
   (gesperrt / zerstört / verändert / wieder offen). Mit Status wirkt er
   wie heute die Meldung (Warnfarbe, Filter, Planer).
2. **Der Status bleibt, der Text läuft ab**: Text und Foto
   verschwinden nach 90 Tagen oder mit „erledigt“. Ein gesetzter Status
   (gesperrt/zerstört) bleibt, bis jemand „wieder offen“ meldet, wie
   heute.
3. **„Zustand“ bleibt die Bewertung 1–5** wie heute. „Zerstört“ und
   „Verlauf geändert“ bleiben Status im Eintrag und halten dauerhaft
   (siehe 2).
4. **Sichtbarkeit getrennt**: Den Status sehen alle, die den Trail
   sehen (Regel der Meldung, er steuert Warnung und Planer). Text und
   Foto sehen nur die direkten Buddys des Verfassers (Regel des
   Hinweises).

## 3. Das Modell: ein Eintrag, zwei Zeilen

Für Nutzer gibt es nur noch **eine Meldung**: optional ein Status,
optional Text und Foto, mindestens eines von beiden. Der Zustand steht
nicht mehr im Dialog, er ist eine eigene Angabe (Abschnitt 5).

**In der Datenbank bleiben beide Tabellen.** Die Entscheidungen 2 und 4
trennen den Eintrag genau an der Grenze, an der die Tabellen heute
schon getrennt sind: Der Status braucht die Sichtbarkeit und die Dauer
von `trail_reports`, Text und Foto brauchen beides von `trail_notes`.
Eine gemeinsame Tabelle müsste für jede Spalte eine eigene RLS-Regel und
eine eigene Frist haben, also wieder zwei Tabellen in einer. Neu ist
nur die **Verbindung**:

- `trail_notes.report_id uuid null references trail_reports(id) on
  delete set null`: Der Text gehört zu diesem Status. Fällt die
  Statuszeile im Aufräumen (`sweep_old_reports`) weg, bleibt der Text
  als Eintrag ohne Status stehen. Andersherum nimmt „erledigt“ den Text
  mit, und der Status bleibt (Entscheidung 2).
- Wer nur den Status sieht (kein Buddy des Verfassers), sieht die
  Notiz nicht. Die RLS von `trail_notes` bleibt, wie sie ist. Ein
  Fremder kann auch über `report_id` nichts erfahren: Die Kennung steht
  in der Notiz, die er nicht lesen darf, und nicht in der Meldung.
- **Geschrieben wird in einem Aufruf.** `report_trail` bekommt einen
  optionalen Text (`p_note text default null`), legt die Meldung an und
  hängt die Notiz mit `report_id` daran, beides in einer Transaktion.
  Die Funktion gibt die Kennung der Notiz zurück, damit die App das
  Foto anhängen kann (wie heute nach `addNote`, „der Hinweis ist das
  Original“). Heute schreibt `report` erst die Meldung und dann einzeln
  den Hinweis: Fällt das Netz dazwischen, landet die Meldung im
  Ausgangskorb ein zweites Mal, dann mit Text. Mit einem Aufruf ist das
  vorbei. Die Idempotenz über `client_id` gilt für beide Zeilen: Kommt
  ein `ReportJob` zweimal, entsteht keine zweite Notiz.
- **Nur Text, kein Status**: eine Notiz ohne `report_id`, also genau
  der heutige Hinweis. Sie geht künftig AUCH über den Ausgangskorb
  (heute scheitert ein Hinweis ohne Netz sichtbar). Das Foto braucht
  weiter Netz, weil Bytes nicht im Korb liegen sollen. Ohne Netz sagt
  der Dialog das und bietet an, den Text allein zu senden.
- **Ältere Clients**: Ein Aufruf von `report_trail` ohne `p_note` läuft
  weiter, weil der Parameter einen Default hat. Ob PostgREST die alte
  benannte Signatur trotz neuer Überladung eindeutig auflöst, belegt
  der Dry Run (alte Funktion im selben Patch ersetzen statt eine zweite
  daneben stellen). Hinweise aus der Zeit vor dem Patch haben keine
  `report_id` und erscheinen als Einträge ohne Status.

Was bleibt, wie es ist: Bestätigt durch Fahren oder „vor Ort“, die
Anzeige der jüngsten bestätigten Meldung und der jüngeren unbestätigten,
„Eine Fahrt setzt die eigene Meldung auf offen“, „Noch gültig?“,
„Bestätigen durch Fahren“, die 90-Tage-Regeln beider Tabellen samt
„der jüngste je Autor bleibt“, die Foto-Frist, der Planer (#434), der
Warnrand auf der Karte, Zusammenführen (`merge_own_into` zieht beide
Zeilen um, die Verbindung zieht mit).

## 4. Der Dialog „Melden“

Ein Knopf **„Melden“** unten im Blatt ersetzt die zwei Knöpfe „Hinweis
schreiben“ und „Melden“. Er bekommt die ganze Breite und die
Hauptfarbe (A13). Der Dialog, von oben nach unten:

1. **„Der Trail ist …“** mit den Chips *gesperrt · zerstört ·
   verändert · wieder offen*, keiner vorgewählt, ein zweiter Tipp
   nimmt die Wahl zurück. „Wieder offen“ heißt in der Datenbank weiter
   `open`.
2. **Text** (immer sichtbar, bis 500 Zeichen), Beispiel je nach Wahl:
   ohne Status „z. B. neuer Drop nach der Brücke“, bei einer Warnung
   „z. B. Baum liegt quer nach der zweiten Kehre“, bei „wieder offen“
   „z. B. Baum ist weggeräumt“.
3. **Foto** (`PhotoAttachment` wie heute, eines).
4. **Wer sieht was**, eine Zeile in Gedämpft:
   „Den Status sehen alle, die den Trail sehen. Text und Foto sehen
   deine Buddys, 90 Tage lang.“ Ohne Status nur der zweite Satz, bei
   „privat“ wie heute „nur du“. Die Zeile zum Entfernen der Ortsangaben
   aus dem Foto bleibt.
5. **Bestätigung** (gefahren / „Ich bin vor Ort“) nur, wenn ein Status
   gewählt ist. Für Text allein gibt es nichts zu bestätigen.

„Melden“ ist aktiv, sobald ein Status gewählt oder Text da ist. Ein Foto
ohne Text gibt es nicht, weil `trail_notes.body` Pflicht bleibt. Das
Foto braucht ein Wort dazu.

## 5. Der Zustand für sich

Der Zustand verlässt den Dialog „Melden“. Er ist langfristig und
beschreibt einen offenen Trail (Rework 3.2: „Unterhalb von 1 beginnt der
Status“). Gefragt wird er dort, wo man ihn kennt:

- **Nach der Fahrt im Zerlege-Blatt**, wie heute (`split_confirm_row`).
- **Im Trail-Blatt über die Kachel „Zustand“**: Heute öffnet ein Tipp
  den Verlauf (`showConditionVotesSheet`), wenn es einen gibt. Künftig
  öffnet er ihn immer, mit der Skala 1–5 obendrauf („Dein Eindruck“) und
  derselben Bestätigung wie beim Melden. Ohne Angabe zeigt die Kachel
  wie heute „—“, der Tipp führt direkt zur Skala.
- Bei 1 oder 2 bietet die App wie heute an, etwas dazu zu schreiben:
  Das öffnet „Melden“ ohne Status.

Der Verlauf des Zustands erscheint nicht mehr in der Liste der
Meldungen (Abschnitt 6), sondern nur noch hinter der Kachel. Dort steht
er schon heute mit Namen und Alter.

## 6. Das Blatt: eine Liste

**„MELDUNGEN“** ersetzt die Abschnitte „Hinweise“ und „MELDUNGEN“.
Neueste zuerst, jede Zeile ein Eintrag:

- **Status + Text**: Statuswort als Titel („Gesperrt“), darunter Text
  und Foto-Vorschau, dann Name · Alter · „zu bestätigen“. Sieht der Leser
  die Notiz nicht (kein Buddy des Verfassers), bleibt es eine
  Statuszeile wie heute.
- **Nur Status**: wie die heutige Statuszeile.
- **Nur Text**: wie der heutige Hinweis.

Was angezeigt wird, folgt den heutigen Regeln je Teil: Statuszeilen nach
`reportsShown` (90 Tage Verlauf plus die angezeigten), Texte nach
`notesShown` (von den alten der jüngste je Autor). Läuft der Text eines
Eintrags ab, bleibt die Statuszeile allein stehen. Unbestätigtes steht
verblasst da wie heute, eine Notiz verblasst nie.

**„Erledigt“** an einem Eintrag mit Text entfernt Text und Foto. Steht
daneben eine warnende Meldung, die das Blatt gerade anzeigt, fragt die
Rückfrage zusätzlich: „Ist der Trail wieder offen?“ Ein Ja meldet
„wieder offen“ (bestätigt nach der üblichen Regel). Ohne das bliebe eine
Sperre nach dem Wegräumen des Baums stehen, und genau das will
Entscheidung 2 nicht. Ein Nein entfernt nur den Text (A10: sagen, nicht
raten).

**Hervorhebung**: Der gelbe Rand und „neu“ in der Liste bleiben die
Regel für frischen Buddy-Text (`kFreshNoteDays`). Das Wort in der Liste
heißt künftig „neue Meldung“ statt „neuer Hinweis“, der Warnrand einer
bestätigten Meldung schlägt ihn wie heute.

## 7. Push: ein Eintrag, eine Nachricht

Heute schickt eine bestätigte Meldung mit Text zwei Einträge in den Korb
(`trail_status` und `trail_note`), und ein Buddy bekommt beide. Künftig:

- `push_on_note` lässt eine Notiz aus, deren `report_id` auf eine
  bestätigte Meldung zeigt, die selbst eine Push ausgelöst hat (die
  Regel in `push_on_report`: anderer Wert als die vorige bestätigte).
  Stattdessen setzt sie `note_id` an der Zeile `trail_status`.
- `push_trail_text` nimmt bei einer einzelnen Meldung mit `note_id` den
  Text als zweite Zeile: „Anna meldet Hausrunde als gesperrt“ /
  „Baum liegt quer nach der zweiten Kehre“. Ohne Text bleibt es „Tippen
  zeigt den Trail“.
- Eine unbestätigte Meldung mit Text schickt weiter nur die
  Hinweis-Push (der Status scheucht niemanden auf, der Text schon, wie
  heute). Den Zustand gibt es weiter nie als Push.
- Die Empfänger sind bei beiden Arten dieselben (`push_recipients`),
  die Regel ändert also niemandes Sichtbarkeit.

## 8. Wörter

„Hinweis“ verschwindet aus der Oberfläche, es heißt überall
„Meldung“. Die Chips heißen „Der Trail ist …“ (bis 0.48.0 hieß das
Feld „Status“, seitdem „Meldung“; jetzt ist „Meldung“ der ganze
Eintrag). Kurzanleitung, Tour (der Anker `SheetCoach.addNote` fällt
weg, `SheetCoach.report` bleibt), Beispiele (`tour_examples.dart`),
„Zeig es mir“ (`highlight_demos.dart`), Push-Texte und
Datenschutzerklärung ziehen mit, deutsch und englisch (A14). In der
Datenbank und im Code bleiben `trail_notes`/`note` als Namen. Eine
Umbenennung brächte nur Risiko und keinen Nutzen.

## 9. Kernanforderungen

- **A2**: Text und Foto bleiben bei den direkten Buddys. Der Status
  bleibt bei allen, die den Trail sehen, wie heute. Die neue Spalte
  zeigt in die erlaubte Richtung (Notiz → Meldung), nie umgekehrt.
- **A6**: keine neue Datenkategorie. Text, Foto und Meldung stehen
  schon in der Datenschutzerklärung; dort ändert sich nur das Wort.
- **A8**: Status und Text gehen ohne Netz in den Ausgangskorb, auch Text
  allein (neu). Das Foto braucht Netz, und der Dialog sagt das.
- **A10**: „Erledigt“ fragt nach „wieder offen“, statt eine Sperre still
  stehen zu lassen oder still aufzuheben.
- **A11**: kein neues Wort, das zu Arbeitseinsätzen einlädt. Der
  Zustand bleibt „Zustand, nie Maßnahme“.
- **A13**: ein Knopf in voller Breite statt zwei halber.
- **A14**: jeder neue Text in beiden ARB-Dateien.

## 10. Bau

Ein PR (`feat(trails)`, MINOR), weil Patch, App und Texte nur zusammen
Sinn ergeben:

- **Patch 028**: `trail_notes.report_id`, `report_trail(…, p_note)`
  ersetzt die alte Signatur, `push_on_note`/`push_trail_text` wie in
  Abschnitt 7. Dazu Struktur in `schema.sql` und die Saat-Liste.
  `matcher_check.sql` bekommt einen neuen Block: Fremder sieht Status,
  nicht Text. „Erledigt“ lässt den Status stehen. Fällt die Meldung im
  Aufräumen weg, bleibt die Notiz. Ein doppelter Job erzeugt keine
  zweite Notiz. `push_flush_check.sh` prüft: eine Push mit Text statt
  zwei.
- **App**: Dialog (Abschnitt 4), Kachel „Zustand“ (5), Liste und
  „Erledigt“ (6), ein Knopf, `ReportJob` auch ohne Status, Fake
  (`fake_trails.dart`) mit derselben Verbindung und Sichtbarkeit,
  Touren und Beispiele, Changelog in beiden Sprachen, Eintrag in
  `kFeatureHighlights` mit Vorführung.
- **Fertig, wenn**: Ein Buddy sieht „Gesperrt · Baum liegt quer“ mit
  Foto als eine Zeile. Ein Fremder mit Sicht auf den Trail sieht nur
  „Gesperrt“. „Erledigt“ mit „wieder offen“ hebt die Warnung auf, ohne
  bleibt sie. Nach 90 Tagen steht nur noch der Status. Ein Buddy bekommt
  eine Push statt zwei. Gegenproben für die Sichtbarkeit (Fake und
  `matcher_check.sql`) und für die eine Push.
- **Bewusst nicht**: keine Zusammenlegung der Tabellen, keine
  Umbenennung im Code, kein Text am Zustand, keine Frist für den
  Status, keine Meldung zu einem Trail für alle („Noch nicht da,
  bewusst“ in der Root-`CLAUDE.md` bleibt).
