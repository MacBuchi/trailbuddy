# TrailBuddy — Rework: Besitz, Bewertung, Aufzeichnen, Duplikate

*Entwurf vom 2026-09-30, aus einem Gespräch mit dem Betreiber über
Schwachstellen des Konzepts aus Sicht eines Nutzers, der viele
GPX-Dateien importiert hat und einen Trail neu aufzeichnen will. Das
Dokument ergänzt `docs/konzept-trails.md`, es ersetzt es nicht: Jeder
Punkt, der gebaut wird, zieht im selben PR die betroffene Stelle dort
nach (Regel aus `CLAUDE.md`). Die Entscheidungen des Betreibers stehen in
Abschnitt 9, der Plan in Abschnitt 10, der Abgleich mit dem Code in
Abschnitt 11; verfolgt in #109.*

## 0. Kurzfassung

Das Modell „Trail ohne Besitzer, Beiträge je Nutzer, stiller Abgleich“
trägt. Im Gebrauch zeigen sich sieben Lücken:

1. **Der Name hängt am Beitrag dessen, der ihn vergeben hat.** Wer einen
   Trail über einen Buddy kennt und ihn wieder fährt, bekommt einen
   Beitrag OHNE Namen. Löscht der Buddy, entfreundet er sich oder löscht
   er sein Konto, steht dort „Trail ohne Namen“. Seit 0.46.0 ist
   das Löschen ein Knopf im Blatt (`withdraw_contribution`, #99) — der
   Fall wird damit häufiger, nicht seltener.
2. **Ein geplanter Import sagt „offen“.** Jede Aufzeichnung setzt den
   eigenen Status auf „offen“, auch eine GPX-Datei von einer
   Vereinsseite ohne Zeiten. Und das Blatt zeigt Buddys nicht, dass eine
   Linie nur geplant ist — anders als Konzept 4.6 sagt.
3. **Es fehlt „wie gut“ und „in welchem Zustand“.** S-Grad und
   Charakter sagen, wie schwer und wie ein Trail ist, nicht ob er Spaß
   macht und ob er gerade ausgefahren ist.
4. **Die Herkunft einer Linie geht verloren.** Eine Vereinsseite mit
   Beschreibung und Regeln wäre ein nützlicher Verweis; GPX trägt ihn
   oft schon in `<link>`.
5. **Aufzeichnen findet nur, was die Heuristik erkennt.** Jump-Lines,
   flache Flowtrails, Uphills und Trails mit Forstweg-Stück werden kein
   Kandidat, und es gibt keinen Weg, ein Stück selbst zu wählen.
6. **Knapp-daneben wird ein Duplikat, das nie heilt.** Lange Version mit
   Anfahrt, gezeichnete Vereinslinie, Gabel, GPS unter dichtem Wald:
   neuer Trail plus unsichtbare Kante. Der Abgleich vergleicht nur mit
   der BESTEN Aufzeichnung eines Trails, und ein zweiter Zwilling bleibt
   für immer daneben. Beim Verbinden sehen Buddys dann doppelte Linien.
7. **Zusammenführen fehlt** (#33 Teil 2), weil die Regel dafür fehlt.

## 1. Der eigene Beitrag beim ersten Wiederfahren (Lücke 1)

**Regel:** Wer einen Trail fährt, den er bisher nur über Buddys sieht,
**macht ihn sich mit einer Bewertung zu eigen** — ein vollständiger
eigener Beitrag, vorbelegt aus dem, was er sieht. Danach hängt nichts
mehr an einem fremden Beitrag.

- **Wann:** genau dann, wenn es zu diesem Trail noch keinen eigenen
  Beitrag gibt (erste Aufzeichnung). Wer ihn schon beschrieben hat,
  wird nicht noch einmal gefragt — sonst wären es bei einer Hausrunde
  sechs Bewertungen nach jeder Fahrt.
- **Wo:** im Zerlege-Blatt, an der Zeile des bekannten Trails (heute
  nur ein Haken). Die Zeile klappt auf: Name, S-Grad, Charakter, Spaß
  (Abschnitt 3). Ein Knopf „Alle übernehmen“ nimmt die Vorbelegung für
  alle Zeilen. Kein neuer Dialog. Beim Import, wo der Client erst nach
  der RPC weiß, dass die Kennung zu einem sichtbaren Trail gehört, zeigt
  das Ergebnis dieselben Zeilen.
- **Vorbelegt:**
  - Name = der angezeigte Name (`displayName`), Charakter = die
    angezeigten Merkmale (`topTraits`). Tatsachennah, eine Kopie schadet
    nicht.
  - S-Grad = der angezeigte Median, sichtbar als **„Vorschlag aus dem
    Netz“** markiert (Entscheidung E1). Ein Tipp bestätigt ihn — das
    ist eine echte Aussage: gefahren und nicht widersprochen. Die
    Verankerung am ersten Urteil ist der bekannte Preis.
  - Spaß: **nie** vorbelegt (Abschnitt 3).
- **Pflicht:** Die Zeile muss bestätigt werden, damit „wieder
  gefahren“ gespeichert wird (Entscheidung E2); mit Vorbelegung ist das
  ein Tipp.
- **Offline:** über den Ausgangskorb wie heute (`ContributeJob` trägt
  schon Grad und Merkmale; er bekommt Name, Spaß und Zustand dazu).
- **Bestand:** Trails mit eigener Aufzeichnung, aber ohne eigenen Namen,
  gibt es schon. Ein Rückfüllen auf dem Server ginge nicht: Er würde
  Namen aus Beiträgen AUSSERHALB des Netzes kopieren (Konzept 12). Die
  Liste bekommt stattdessen den Filter „Bewertung offen“, das Blatt an
  solchen Trails eine Zeile „Übernehmen“ mit derselben Vorbelegung.

`adoptDetails` bleibt die EINE Schreibstelle; sie lernt, einen fremden
Namen zu übernehmen, wenn der eigene leer ist.

## 2. Geplante Importe (Lücke 2)

- **Kein Status-Rücksetzen durch `planned`.** `contribute_recording`
  setzt den Status nur bei `app` und `import` auf „offen“. Eine Datei
  ohne Zeiten belegt nicht, dass der Trail befahrbar war. Patch,
  `matcher_check.sql` bekommt einen Block dafür.
- **Das Blatt sagt „geplant“.** Hat ein Beitrag nur geplante
  Aufzeichnungen, steht beim Namen des Beitragenden „geplant, nicht
  gefahren“; ein Trail, dessen sichtbare Belege alle geplant sind,
  sagt es oben im Blatt. Das löst ein, was Konzept 4.6 schon verspricht.
- **Bleibt:** Geplante Importe gehen an Buddys (Entscheidung 2 vom
  2026-09-27). Ob sie privat bleiben sollten, bis man sie gefahren hat,
  ist Entscheidung E3.

## 3. Spaß und Zustand (Lücke 3)

Zwei neue Werte je Beitrag, beide 1–5, **beide mit 5 als bestem Wert**
(dieselbe Richtung, sonst verwechselt man sie).

### 3.1 Spaß

Frage: **„Wie viel Spaß?“** — nicht „Qualität“, das vermischte sich mit
Zustand und Schwierigkeit. Symbol aus dem Design (Vorschlag: fünf
kleine Serpentinen aus dem Logo statt Sternen; Entscheidung E4 bei der
Design-Datei).

- Einmal gesagt, jederzeit in „Mein Beitrag“ änderbar, nie vorbelegt.
- Anzeige: Mittelwert der sichtbaren Beiträge **mit Anzahl**
  („4,2 · 3“). In einem Netz aus drei Leuten ist eine Zahl ohne Anzahl
  Rauschen.
- Sortieren nach Spaß in der eigenen Liste: ja. Eine Rangliste über das
  Netz hinaus: nie (Konzept 7, 12).

### 3.2 Zustand

| Wert | Wortlaut |
|---|---|
| 5 | Top gepflegt |
| 4 | Gut |
| 3 | Ausgefahren |
| 2 | Abgerockt — Wurzeln frei, Löcher, Wildwuchs |
| 1 | Kaum fahrbar |

- **Er veraltet, deshalb gilt er wie der Status:** der jüngste
  sichtbare gewinnt, angezeigt mit Alter („ausgefahren · vor 3
  Wochen“), nach 90 Tagen ausgegraut. Kein Median, keine Vorbelegung —
  sonst bestätigt man einen alten Stand.
- **Gefragt nach jeder Fahrt**, freiwillig, ein Tipp, in derselben Zeile
  des Zerlege-Blatts. Das ist der dauerhafte „nach dem Fahren“-Moment.
- **Nur mit eigenem Beleg** (wie Status und S-Grad, Konzept 3); wer
  etwas sieht, ohne gefahren zu sein, schreibt einen Hinweis.
- **Keine Push-Meldung** — die bleibt Status und Hinweisen. Bei 1 oder 2
  bietet die App einen Hinweis an, wie beim Status.
- **Zustand, nie Maßnahme.** Kein „Arbeiten fällig“, kein „braucht
  Pflege“: Konzept 7 schließt Bau-Features und Aufrufe zu
  Arbeitseinsätzen aus, und eine Skala, deren unteres Ende „hier müsste
  jemand ran“ heißt, wäre genau das. Wer Konkretes sagen will, schreibt
  einen Hinweis.
- Unterhalb von 1 beginnt der Status („gesperrt“, „zerstört“,
  „verändert“) — der Zustand beschreibt einen OFFENEN Trail.

### 3.3 Schema

Ein Patch an `trail_details`: `fun smallint` (1–5, null),
`condition smallint` (1–5, null), `condition_at timestamptz`. Ein Check
hält `condition_at` und `condition` zusammen. Ältere Clients schreiben
per `upsert` nur ihre eigenen Spalten und lassen die neuen stehen — im
PR per Test gegen den lokalen Stack belegt, nicht angenommen.

## 4. Link zur Quelle (Lücke 4)

- **Im eigenen Beitrag, nicht am Trail:** `trail_details.link`. Anzeige
  wie beim Namen: eigener, sonst der des ältesten sichtbaren Beitrags,
  weitere als „auch: …“. Es gibt damit keine Frage, wem der Link gehört.
- **Nur `https`**, höchstens 500 Zeichen, Check in der Datenbank. Gezeigt
  wird nur der Host mit Pfeil („trailsurfers-bw.de ↗“), geöffnet im
  externen Browser. Die App ruft den Link nie selbst ab — kein neues
  Netzziel, nichts für die Datenschutzerklärung außer dem Satz, dass
  Beiträge einen Link tragen können.
- **Vorgeschlagen beim Import** aus `<link href>` in `<trk>` oder
  `<metadata>` (GPX 1.1), **ohne Query und Fragment**: Freigabelinks von
  Tourenportalen tragen dort Tokens und Nutzerkennungen. Der Nutzer
  kann den Link vor dem Speichern ändern oder leeren.
- **Gebaut in #113 (0.48.0), mit drei Abweichungen:** (1) Der Import
  übernimmt den Link wie den Namen ohne eigenes Feld — auch den Namen
  kann man dort nicht ändern; geändert wird danach in „Mein Beitrag".
  (2) Links von Geräteherstellern und Tourenportalen fallen beim
  Vorschlag weg (`kLinkIgnoredHosts`): `<metadata><link>` ist meist die
  Seite des Exporteurs, und der Link zur eigenen Strava- oder
  Komoot-Aktivität verriete Buddys das eigene Konto dort. (3) Kein
  „auch: …" für weitere Links — das Blatt zeigt einen (E11).
- **Abgrenzung:** Die offizielle Ebene (#13) bleibt der Weg für
  Vereins-Trails mit Erlaubnis. Ein Link in einem Beitrag ist die
  Aussage eines Nutzers, keine Quelle der App.

## 5. Aufzeichnen: ein Stück selbst wählen (Lücke 5)

Zwei Wege, damit man sagen kann „genau DAS war der Trail“. Beide
bleiben im Konzept: Das Stück kommt aus eigenen Daten und ist gefahren.

1. **„Stück selbst wählen“ im Zerlege-Blatt.** Unter den Kandidaten ein
   Knopf, der einen Kandidaten über die GANZE Fahrt anlegt, mit
   denselben Griffen (`RangeSlider`), Name, S-Grad, Charakter. Die Karte
   zeigt die Vorschau wie bei einem gefundenen Kandidaten. Braucht
   keinen gespeicherten Bereich — die Wege braucht nur die Heuristik.
   Mindestlänge 50 m (Abgleich, seit Patch 017; davor 150 m) gilt.
2. **Markieren während der Aufnahme.** Ein Knopf „Trail beginnt“ /
   „Trail endet“ neben dem Aufnahmeknopf schreibt eine Marke in die
   JSON-Lines-Datei (im Service-Isolate, wie die Punkte). Das
   Zerlege-Blatt macht aus jedem Paar Marken einen Kandidaten,
   zusätzlich zur Heuristik, vorangehakt. Eine offene Marke am Ende der
   Fahrt gilt bis zum letzten Punkt.

**Weg 1 gebaut in #112 (0.47.0)**, wie oben, dazu: Vorgewählt ist die
Fahrt ohne ihre ersten und letzten 300 m (Heimzone) — eine Fahrt beginnt
an der Haustür; der Heimzonen-Hinweis folgt seither den Griffen, bei
jedem Kandidaten.

**Weg 2 gebaut in #129 (0.57.0)**, mit drei Abweichungen vom Text oben:
(1) Die Marke trägt nur die ZEIT, das Blatt nimmt den zeitlich nächsten
Punkt — der Ort steht in der Spur. (2) Geschrieben wird sie aus dem
Main-Isolate, wo getippt wird, nicht im Service-Isolate; die Datei nimmt
von dort schon die Antworten aus #116. (3) Die Griffe eines markierten
Kandidaten reichen über die ganze Fahrt wie bei Weg 1 — eine Marke kann
einen Takt daneben sitzen. Dazu: Die Marke schlägt die Heuristik, wo
beide sich überschneiden, und weicht nur einem bekannten Trail, der das
Stück zu ≥ 0,8 deckt; ein zweiter Beginn schließt den offenen dort, ein
Ende ohne Beginn zählt nicht.

**Nie ein Merkmal „neu“ oder „selbst gebaut“** — die App fragt nicht,
seit wann es einen Trail gibt (Konzept 7).

Folge: Die Heuristik darf weiter nur Abfahrten vorschlagen; Uphills
und Jump-Lines kommen über die zwei Wege oben.

## 6. Abgleich: weniger Zwillinge (Lücke 6)

Zwei Änderungen am Abgleich, beide mit Messung, `tool/trail_match.py`
und SQL im selben PR (Regel aus `CLAUDE.md`):

1. **Gegen mehrere Aufzeichnungen je Trail vergleichen**, nicht nur
   gegen die beste. Heute fällt eine saubere kurze Linie durch, wenn die
   beste Aufzeichnung zufällig die lange Version mit Anfahrt ist —
   obwohl eine passende kurze schon am Trail hängt. Vorschlag: die
   besten drei je Trail; der Trail mit der höchsten Deckung gewinnt wie
   heute. Die Messung sagt, ob drei genügen und was es kostet
   (`tool/limit_measure.sql`).
2. **Zwillinge sichtbar machen.** Passt ein Kandidat „gleich“ auf ZWEI
   Trails, hängt er am besseren, und zwischen den beiden entsteht eine
   Overlap-Kante mit der Markierung „beide gleich einer dritten Linie“.
   Das ist der beste Beleg für ein Duplikat, den es gibt, und der
   Vorrat für den Vorschlag in Abschnitt 7.

**Nicht:** den Korridor weiten oder die Deckung senken. Die Schwellen
sind gemessen, und ab 20 m werden Gabeln „gleich“ (`docs/trail-abgleich-messung.md`).
Eine falsche Verschmelzung bleibt teurer als eine Dublette (Konzept 4.4).

**Später, eigener Schritt:** Kurze Importe (< 8 km, direkt als Trail)
auf Forstwege stutzen wie das Zerlege-Blatt, wenn ein gespeicherter
Bereich die Datei trägt — dann entstehen weniger Versionen „mit
Anfahrt“.

## 7. Zusammenführen im Netz (Lücke 7, #33 Teil 2)

**Regel: Zusammenführen ist eine Aussage in MEINEM Beitrag, kein
Eingriff am Trail.** Niemand verändert die Daten eines anderen.

- **„Für mich ist B derselbe wie A“** heißt:
  1. Meine Aufzeichnungen zu B ziehen nach A um (neue RPC
     `merge_own_into(from, to)`, Security Definer, prüft, dass der
     Aufrufer BEIDE Trails sieht). Mein Beitrag zu B verschmilzt mit
     meinem zu A (A gewinnt, leere Felder füllt B). Meine Hinweise
     ziehen mit.
  2. Für die Beiträge meiner Buddys zu B legt der Client eine
     **persönliche Zuordnung** an (`trail_aliases(user_id, from, to)`,
     nur für mich lesbar). `buildTrails` zeigt B's Beiträge unter A. Nur
     die eigene Ansicht ändert sich.
- **Vorgeschlagen** wird nur für Paare, die der Aufrufer ohnehin beide
  sieht und zwischen denen eine Kante liegt (RPC über
  `trail_overlaps`, Konzept 6), zuerst die aus Abschnitt 6.2. Frei
  wählen („mit einem anderen Trail zusammenführen“) nur unter sichtbaren
  Trails mit einer Mindestdeckung von 0,3, auf dem Gerät gerechnet.
- **Beide Seiten bekommen den Vorschlag.** Führt jeder für sich zusammen,
  verschwindet B aus beiden Ansichten; der Aufräumjob holt die Kennung,
  wenn niemand mehr etwas daran hat.
- **Der Abgleich lernt nicht global** aus einer Zusammenführung (keine
  Umleitung B → A für alle): Ein Nutzer soll nicht über fremde Netze
  entscheiden (Entscheidung E5).
- **Sonderfall „B liegt in A“ (lange Version mit Anfahrt):** Statt
  zusammenführen „auf den gemeinsamen Teil kürzen“ — die eigene
  Aufzeichnung wird im Zerlege-Blatt geöffnet, das Stück neu
  beigesteuert, die alte gelöscht.
- **Rückgängig:** Die persönliche Zuordnung lässt sich lösen; umgezogene
  eigene Aufzeichnungen bleiben, wo sie sind.

## 8. Was sich am Konzept ändert

| Stelle in `konzept-trails.md` | Änderung |
|---|---|
| 3, Name | Wiederfahren übernimmt den angezeigten Namen (1) |
| 3, Status | `planned` setzt ihn nicht zurück (2) |
| 3, neu | Spaß und Zustand (3), Link (4) |
| 4.4 | Vergleich gegen mehrere Aufzeichnungen, Zwillingskanten (6) |
| 4.6 | „geplant“ tatsächlich im Blatt (2) |
| 5.1 | Stück selbst wählen, Marken (5) |
| 6 | Regel fürs Zusammenführen (7) |

Jeder PR aus Abschnitt 10 zieht seine Zeile nach.

## 9. Entscheidungen des Betreibers (2026-09-30)

Alle Fragen aus dem Entwurf und aus dem Abgleich (Abschnitt 11) sind
entschieden. **Wo die Abschnitte 1 bis 7 davon abweichen, gilt dieser
Abschnitt**; jeder Schritt aus Abschnitt 10 zieht seinen Abschnitt beim
Bauen nach.

**Bewertung statt Spaß (E4, E8).** Die Skala aus 3.1 heißt
**„Bewertung"** und zeigt **Sterne** (1–5): Es geht ums Gefallen, nicht
nur um Spaß. In Übersichten (Liste, Karte, Kachel) reichen die Sterne;
dazu **Median** und Anzahl, wo Platz ist (wie beim S-Grad, bei
Gleichstand der höhere). Ein Trail,
den ich belegt, aber noch nicht bewertet habe, zeigt **verblasste
Sterne** — das IST „Bewertung offen", kein eigenes Wort (Nachtrag des
Betreibers). Der Filter-Chip „Bewertung offen" in der Liste kommt dazu
(E13).

**Meldung und Zustand (E7).** Der bisherige „Status" (offen, gesperrt,
zerstört, verändert) heißt in der App und in der Datenschutzerklärung
**„Meldung"** (passt zu „gemeldet vor …" und zum Filter „Gemeldet").
Die neue Skala 1–5 aus 3.2 heißt **„Zustand"**.

**Gebaut in #101 (0.49.0, Patch 013)** — Bewertung, Meldung, Zustand,
„zu bestätigen", die Umbenennung; Linienart auf der Karte und die
Wörter in der Liste folgen als eigene Schritte. Vier Nachträge des
Betreibers vom 2026-09-30 zur Schemaskizze, hier eingearbeitet:
(1) Eine geplante Aufzeichnung ist kein Beleg für „bestätigt".
(2) Der Zustand gilt **dauerhaft** — die jüngste bestätigte Angabe
steht mit ihrem Alter, ohne 90-Tage-Grenze. (3) Eine Fahrt setzt die
Meldung zum **Fahrdatum** auf „offen", nicht zur Importzeit. (4) Alle
Meldungen stehen **90 Tage** im Verlauf, mit Name oder Alias des
Meldenden; die jüngste bestätigte und unbestätigte je Person bleiben
länger. Offen und nicht in #101: Meldungen nicht still wegräumen,
sondern den Meldenden in einer Übersicht fragen, ob sie noch gelten
(„Ja / Nein / Weiß nicht"; „Weiß nicht" lässt alles, wie es ist) — das
Schema trägt es schon, eine Antwort ist eine neue Meldung (#119); das Fahrdatum für eine Datei ohne Zeiten eintragen: #120.
**Beides gebaut in #130 (0.58.0).** #119: Seite „Noch gültig?" im Profil mit
Zähler und derselbe Satz als Filter in Liste und Karte; gefragt wird
nach der EIGENEN jüngsten Angabe je Art, wenn sie noch angezeigt wird,
bei einer Meldung nur, wenn sie warnt, ab 30 Tagen; „Weiß nicht" ruht
14 Tage (Betreiber, 2026-09-30), gemerkt auf dem Gerät. #120 (Patch
015): Eine geplante Datei mit eingetragenem Datum bleibt `planned`
(Qualität 0,1), `recorded_at` trägt das Datum, und genau das zählt als
gefahren (`has_ridden`, Schritt 8) — Betreiber-OK zur Skizze am
2026-09-30. Keine neue Quelle: Ältere Clients kennen keinen neuen Wert.
Bestätigen durch Fahren samt lokaler Benachrichtigung: #116.

**Bestätigt oder zu bestätigen (E6).** Für Meldung UND Zustand:
- **Bestätigt** ist eine Angabe, wenn der Meldende den Trail belegt hat
  (eigene Aufzeichnung) ODER beim Melden **vor Ort** war: innerhalb
  **200 m** der Trail-Linie, geprüft auf dem Gerät mit der aktuellen
  Position. Zum Server geht nur das Merkmal „vor Ort" (ja/nein), nie
  die Position (wie beim Positionspunkt der Karte).
- **Ohne Beleg und nicht vor Ort** geht es trotzdem — wer die Hausrunde
  nicht aufgezeichnet hat und zu Hause an die Meldung denkt —, dann aber
  **verblasst, „zu bestätigen"**. Schreiben darf, wer den Trail sieht
  (die Regel der Hinweise, `can_see_trail`), nicht nur, wer ihn belegt
  hat — das weicht von Konzept 3 („ohne Beleg kein Beitrag") ab.
- **Ein Buddy bestätigt** eine solche Angabe, indem er den Trail fährt
  (eine Aufzeichnung darauf beisteuert, auch „wieder gefahren" im
  Zerlege-Blatt) oder vor Ort dieselbe Angabe macht. **Gespeichert als
  eigene, bestätigte Meldung des Fahrers** (Betreiber, 2026-09-30, #116):
  kein Schema, `report_trail` mit `on_site`; sichtbar nur im Netz
  (Konzept 12). Eine Fahrt OHNE Antwort bestätigt nichts — gefragt wird
  unterwegs und im Zerlege-Blatt. Knöpfe: „Stimmt" / „Trail ist frei"
  bei einer Meldung, „Stimmt" / „Ändern…" beim Zustand; der Trailname
  steht in der Benachrichtigung.

**Welche Meldung steht da (Betreiber, 2026-09-30).** Die **jüngste
bestätigte** Meldung, und dazu — verblasst, „zu bestätigen" — die
**jüngste unbestätigte, wenn sie jünger ist**; eine ältere unbestätigte
ist überholt und fällt weg. Ersetzt „der jüngste gewinnt" aus Konzept 3
für die Meldung.

**Zum Bestätigen auffordern.** Wer gerade aufzeichnet und auf einen Trail
mit unbestätigter Meldung oder unbestätigtem Zustand kommt, wird
**sofort gefragt**: Der Aufnahme-Dienst prüft je Takt im
Service-Isolate die Position gegen die Trails aus dem Zwischenspeicher
(Korridor wie „vor Ort", 200 m, genauer: auf der Linie im
Abgleich-Korridor) und zeigt eine **lokale Benachrichtigung** — geht
ohne Netz, und die Position verlässt das Gerät nicht. Eine Push-Meldung
vom Server geht dafür NICHT: Der Server müsste wissen, wo jemand fährt.
Wer die Frage übergeht, bekommt sie beim Beenden im Zerlege-Blatt an der
Zeile des Trails noch einmal. Die Bestätigung geht über den
Ausgangskorb raus, sobald Netz da ist. Je Trail und Fahrt höchstens eine
Benachrichtigung.

**Zustand auf der Karte (E9).** Keine Farbe (Farbe heißt Schwierigkeit).
Den Zustand trägt die **innere Hauptlinie**: durchgezogen (gut) →
bröckelig → gestrichelt → gestrichelt und verblasst (kaum fahrbar).
**S4/S5 wandern auf die Umrahmung**: Sie erkennt man künftig an der Art
des Saums, nicht mehr an der gestrichelten Linie (heute
`docs/design/README.md` Abschnitt 2; die Datei ändert sich im selben
PR). Technisch trägt beides: Der Saum ist auf beiden Engines eine eigene,
breitere Ebene unter der Linie und kann ein eigenes Muster haben. In der
Liste erscheint der Zustand bei 1–2 als Wort („ABGEROCKT", „KAUM
FAHRBAR") hinter Meldung und Hinweis; im Blatt als Kachel (E8).

**Anzeige und Voreinstellung = das Netz (Betreiber, 2026-09-30).** Was
die App zeigt, ist der **Median der sichtbaren Beiträge** — eigene plus
direkte Buddys, auf dem Gerät gerechnet, deshalb für jeden anders (nicht
jeder hat dieselben Buddys) und nie über alle Nutzer (Konzept 12). Der
Zwischenspeicher (`trail_cache/network.json`) trägt die Beiträge roh,
also rechnet die App den Median auch im Wald ohne Netz; neue Felder
kommen über `toRow` von selbst hinein. **Genau diese Werte sind die
Voreinstellung beim Bewerten** — für S-Grad, Charakter UND Sterne
(ersetzt „Sterne nie vorbelegt" aus 3.1), jeweils sichtbar als
„Vorschlag aus dem Netz". So entsteht gemeinsamer Inhalt aus der
Buddy-Gemeinschaft. **Ausnahme Zustand:** Er veraltet; angezeigt und
vorbelegt wird der **jüngste bestätigte der letzten 90 Tage** mit
seinem Alter, sonst nichts — ein Median mischte alte und neue Angaben.

**Blatt (E8).** Eine zweite Kachelreihe unter LÄNGE / HÖHE / S-GRAD:
BEWERTUNG (Sterne, Median, Anzahl) und ZUSTAND (Wort, Alter,
„zu bestätigen", wenn unbestätigt); ein Tipp zeigt die Einzelstimmen wie
beim S-Grad.

**Übernehmen beim ersten Befahren (E1, E2).** Wer den Trail eines Buddys
zum ersten Mal fährt, **muss ihn bewerten, um ihn selbst zu haben und
weitergeben zu können**; danach wird nicht mehr gefragt. Ohne Bewertung
wird das Stück nicht beigesteuert. Der S-Grad ist vorbelegt (Median),
als „Vorschlag aus dem Netz" markiert; Name, Charakter und Sterne
ebenso (Median des Netzes, siehe oben); der Zustand mit dem jüngsten
bestätigten. „Alle übernehmen" nimmt die Vorbelegung.

**Geplante Importe (E3, E10).** Werden weiter an Buddys gegeben
(Entscheidung 2 vom 2026-09-27 bleibt); in der Liste steht gedämpft das
Wort „GEPLANT", hinter allen anderen.

**Link (E11).** Bleibt wie in #113 gebaut: ein Link, der Host als
Textknopf, Hersteller und Tourenportale beim Import ignoriert.

**Marken beim Aufnehmen (E12).** Ein Knopf (44 dp, Fahne) über der
Aufnahme, nur während einer Fahrt: erster Tipp „Trail beginnt", zweiter
„Trail endet"; läuft ein Trail, trägt der Knopf einen Rand. Nicht
verwechselbar mit den Start-/Ende-Marken der Trails (#96).

**Zusammenführen (E5, E14).** Nur für mich (Abschnitt 7), kein
Umleiten für alle. **Vorgeschlagen wird es allen, die einen der beiden
Trails gefahren sind — sofern sie BEIDE sehen.** Die Einschränkung ist
nicht verhandelbar: Wer nur Trail A sieht, erführe über den Vorschlag,
dass es B gibt und wo er liegt (Konzept 12). Der Vorschlag steht im
Trail-Blatt; die Karte „Mit … verbunden" nennt nur die Anzahl.

## 10. Plan

Reihenfolge nach Nutzen je Aufwand und nach Abhängigkeit. Jeder Schritt
ist ein PR mit eigenem Issue; `feat` hebt MINOR, `fix` PATCH (Regeln in
`CLAUDE.md`). Schema-Schritte bringen ihren Patch, `schema.sql`, die
Saat-Liste und einen Block in `matcher_check.sql` mit. Die Patch-Nummern
in der Tabelle gelten für diese Reihenfolge; wer vorzieht, nimmt die
nächste freie.

**Die PRs sind gestapelt** (#111 ← #112 ← #113), weil jeder die Version
hebt; nach dem Squash-Merge des unteren wird der nächste auf `main`
umgesetzt. **Ein Patch geht live, sobald sein PR den Schema Check
durchläuft** (`db_migrate.sh` spielt je PR neue Patches ein, nicht erst
nach dem Merge) — Patch 011 ist deshalb schon live, Patch 012 mit #113.
Schritte, deren Schema noch an einer Entscheidung hängt (2, 7, 8),
bekommen ihren PR erst danach.

| # | Schritt | Issue | PR | Typ | Schema | Hängt ab von |
|---|---|---|---|---|---|---|
| 1 | Geplant: kein Status-Rücksetzen, „geplant“ im Blatt (2) | #100 | #111 ✓ | fix 0.46.1 | Patch 011 | — |
| 2 | Bewertung (Sterne) und Zustand samt „zu bestätigen“, Meldung umbenannt (3, 9) | #101 | #118 Schema + Blatt, #121 Liste, (c) Karte | feat 0.49.0–0.51.0 | Patch 013 | — |
| 3 | Übernehmen beim ersten Befahren (Pflicht), Zustand je Fahrt, Filter (1, 9) | #102 | #127 Zerlege-Blatt, (b) Import, Filter, Blatt | feat 0.55.0–0.56.0 | — | #101 |
| 4 | Link im Beitrag, Vorschlag aus GPX (4) | #103 | #113 ✓ | feat 0.48.0 | Patch 012 | — |
| 5 | Stück selbst wählen im Zerlege-Blatt (5.1) | #104 | #112 ✓ | feat 0.47.0 | — | — |
| 6 | Marken während der Aufnahme (5.2, 9) | #105 | #129 | feat 0.57.0 | — | — |
| 7 | Abgleich gegen mehrere Aufzeichnungen, Zwillingskanten (6) | #106 | #114 (Messung) | — | vorerst keins | Daten mehrerer Nutzer |
| 8 | Zusammenführen im Netz (7, 9) | #107 | — | feat | Patch 015 | #106 |
| 9 | Kurze Importe auf Forstwege stutzen (6, später) | #108 | — | feat | — | — |
| 10 | Bestätigen durch Fahren, lokale Benachrichtigung während der Aufnahme (9) | #116 | #123 Benachrichtigung, (b) Zerlege-Blatt | feat 0.52.0–0.53.0 | keins | #101 |
| 11 | Übersicht „Noch gültig? Ja / Nein / Weiß nicht“ für eigene Meldungen (9) | #119 | #130 | feat 0.58.0 | — | #101 |
| 12 | Fahrdatum für eine Datei ohne Zeiten eintragen | #120 | #130 | feat 0.58.0 | Patch 015 | #101 |

### Schritt 1 — Geplant

- `contribute_recording`: `on conflict … do update set status = 'open'`
  nur, wenn `source <> 'planned'`. Neuer Block in `matcher_check.sql`:
  „gesperrt“ + geplanter Import ⇒ bleibt gesperrt; + App-Aufzeichnung ⇒
  offen.
- `Trail`: je Beitrag „nur geplant“ ableiten (aus den sichtbaren
  Aufzeichnungen des Nutzers, `RecordingSource.planned`); Blatt und
  Beitragsliste zeigen es. Widget-Test im Harness.
- `konzept-trails.md` 3 und 4.6 nachziehen.

### Schritt 2 — Spaß und Zustand

- Patch 013: drei Spalten, Checks (1–5; `condition_at` genau dann,
  wenn `condition`). Grants unverändert (Spalten erben).
- `TrailDetails`: Felder, `fromJson`/`toRow`/Cache-Encoder (Rundlauf-
  Test), `copyWith`. `Trail`: `funAverage`, `funCount`,
  `latestCondition` (jüngster mit Alter, ausgegraut nach 90 Tagen).
- `singletrail_scale.dart`-Muster: Wortlaut an EINER Stelle
  (`trail_condition.dart`), Symbol für Spaß nach Design-Datei.
- Blatt: Anzeige; „Mein Beitrag“: Auswahl. Liste: Sortierung nach
  Spaß. Beim Zustand 1–2 einen Hinweis anbieten.
- Test gegen den lokalen Stack: ein Upsert ohne die neuen Spalten
  lässt sie stehen.
- `docs/design/README.md` (Symbol), `konzept-trails.md` 3.

### Schritt 3 — Übernehmen beim ersten Wiederfahren

- Zerlege-Blatt: bekannte Zeile klappt auf, wenn kein eigener Beitrag
  existiert; Vorbelegung nach Abschnitt 1; „Alle übernehmen“; Zustand
  je Zeile (immer, freiwillig). Speichern verlangt die Bestätigung
  (E2).
- `adoptDetails`: übernimmt einen fremden Namen, wenn der eigene leer
  ist; schreibt Spaß und Zustand mit. `ContributeJob`: Name, Spaß,
  Zustand (alter Auftrag ohne Felder liest sich leer).
- Import: Ergebnis zeigt dieselben Zeilen für Kennungen, die im Netz
  schon sichtbar waren.
- Liste: Filter „Bewertung offen“; Blatt: „Übernehmen“.
- Flow-Test: Buddy-Trail wieder fahren ⇒ eigener Name; Buddy entfreundet
  ⇒ Name bleibt.

### Schritt 4 — Link

- Patch 012: `trail_details.link text` mit Check (`^https://`, ≤ 500).
- `gpx.dart`: `<link href>` aus `<trk>`, sonst `<metadata>`; Query und
  Fragment weg. Import schlägt ihn vor.
- Blatt: Host mit ↗, öffnet extern; „Mein Beitrag“: Feld.
- Datenschutzerklärung: ein Satz; `privacy_policy_test` bleibt grün.

### Schritt 5 — Stück selbst wählen

- `ride_split_sheet.dart`: Knopf „Stück selbst wählen“ legt einen
  Kandidaten über die ganze Fahrt an (Griffe, Vorschau, Name, Grad,
  Charakter); ohne gespeicherten Bereich verfügbar.
- `ride_split.dart` (pur): Kandidat aus Index-Bereich, Mindestlänge.
- Test: Fahrt ohne Bereich ⇒ Stück wählen ⇒ beigesteuert.

### Schritt 6 — Marken

- `ride_task_handler.dart`: Marke als eigene Zeile in der JSON-Lines-
  Datei; Brücke zum Main-Isolate wie beim Punkt
  (`ride_live_bridge_test.dart` erweitern).
- Kartenknopf neben der Aufnahme (Design-Datei, 44 dp), nur während
  einer Fahrt.
- `ride_split.dart`: Marken-Paare ⇒ Kandidaten, offene Marke bis zum
  Ende.

### Schritt 7 — Abgleich

- Messung zuerst: `tool/trail_match.py` mit „beste N je Trail“ an den
  584 Tracks; Ergebnis in `docs/trail-abgleich-messung.md`.
- `contribute_recording`: `limit 1` → `limit N`; bei zwei „gleich“-
  Trails die Zwillingskante (`trail_overlaps` bekommt `twin boolean`).
- `matcher_check.sql`: Block für kurze Linie gegen Trail mit langer
  bester Aufzeichnung; Block für Zwillinge.

### Schritt 8 — Zusammenführen

- Patch 015: `merge_own_into`, `trail_aliases` (RLS: nur eigene Zeilen),
  RPC für Vorschläge (nur Paare, die der Aufrufer beide sieht).
- `buildTrails` wendet die Zuordnungen an; Blatt „Sind das dieselben?“
  mit beiden Linien auf der Karte; „auf gemeinsamen Teil kürzen“ öffnet
  das Zerlege-Blatt.
- `fake_trails.dart` spiegelt die neuen Regeln; `matcher_check.sql`
  prüft, dass die RPC für nicht sichtbare Paare nichts sagt.
- #33 schließen.

## 11. Abgleich mit dem Stand 0.46.0 (2026-09-30)

Nach dem Rebase auf `main` (0.38.0 bis 0.46.0: neue Liste, neues Blatt,
Farbe = Schwierigkeit, Bewegung, „Löschen") gegen den Code geprüft:

- **Hält:** Der Name hängt am Beitrag (`Trail.displayName`), das
  Zerlege-Blatt steuert „wieder gefahren" ohne Namen bei
  (`_contribute`, Name `''`), `contribute_recording` setzte den Status
  auch bei `planned` zurück, das Blatt zeigte „geplant" nirgends, der
  Abgleich vergleicht nur mit der besten Aufzeichnung (`limit 1`). Alle
  Lücken aus Abschnitt 0 bestanden.
- **Neu seit dem Entwurf:** „Löschen" im Blatt (#99, Patch 010) macht
  Lücke 1 häufiger. Die Patch-Nummern haben sich um eins verschoben.
- **Stellt Fragen, die der Entwurf nicht kannte** (E7–E14): Die
  Farbregel (Farbe = Schwierigkeit, Ränder = Warnung/Hinweis) lässt dem
  Zustand keine Farbe; „Zustand" ist im Dialog und in der
  Datenschutzerklärung schon das Wort für den Status; das Blatt hat drei
  feste Kacheln; die Liste zeigt Zustände als Wort (`trailRowTags`).
- **Hilft:** `adoptDetails` schreibt Name, Grad und Merkmale schon in
  EINEM Vorgang und überschreibt keinen eigenen Namen — Schritt 3 baut
  darauf; `OwnGradePicker` im Blatt ist das Vorbild fürs Übernehmen im
  Bestand. Der Dialog „Mein Beitrag" baut `TrailDetails` neu: Jedes neue
  Feld muss er mitgeben, sonst löscht Speichern es (in #113 für den Link
  so gebaut, gilt für Spaß und Zustand genauso).
- **Prozess:** Der Schema Check spielt Patches je PR live ein
  (Abschnitt 10).
