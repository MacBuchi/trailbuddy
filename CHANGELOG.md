# TrailBuddy

*Was ist neu — in Alltagssprache, nach Themen. Jeder Block nennt seine Versionen.*

## Die ganze Region offline

*Versionen 0.108.0 und 0.108.1, 2026-10-09*

- **Ganz DACH oder ganz Südkanada aufs Telefon**: In „Meine Bereiche"
  steht je Region „ganz speichern" — die ganze Karte bis Zoom 13 samt
  Orten, Höhen und Wegen. Vorher sagt die App, wie viel es ist, und warnt
  über Mobilfunk. Was deine Bereiche schon haben, kommt nicht noch
  einmal.
- Das dauert eine Weile und läuft weiter, wenn du die App wechselst.
  Bricht es ab, bleibt alles Geladene liegen, und „Fortsetzen" holt den
  Rest.
- Löschst du die Region später, bleiben die Kacheln deiner anderen
  Bereiche dort liegen. Mit dem Radierer lässt sich eine ganze Region
  nicht verkleinern — sie geht nur im Ganzen.
- Nur in der Android-App; im Browser bleiben gezeichnete Bereiche.
- **Korrigiert (0.108.1):** Der Download blieb bei 0 % stehen. Er holte
  am Anfang über 200 MB in einem Stück und hielt sie im Speicher. Jetzt
  kommt die Karte in kleinen Häppchen, und die Prozentzahl wächst mit
  den geladenen Megabytes.

## Gespeicherte Bereiche teilen sich ihre Kacheln

*Versionen 0.106.0 und 0.107.0, 2026-10-09*

- **Jede Kachel liegt nur noch einmal auf dem Gerät**: Überschneiden sich
  zwei Bereiche, lädt der zweite nur noch, was der erste nicht schon hat.
  Der Dialog vor dem Speichern sagt, wie viele Kacheln schon liegen.
- **Löschen nimmt nur, was kein anderer Bereich braucht**: „Meine
  Bereiche" zeigt je Bereich, was er allein belegt — genau so viel gibt
  sein Löschen frei. Dasselbe gilt für den Radierer.
- **Ein abgebrochener Download ist nicht mehr verloren**: Bricht die
  Verbindung ab oder tippst du auf Abbrechen, bleibt der Bereich als
  „unvollständig" mit allem, was schon geladen ist. „Fortsetzen" holt den
  Rest.
- Deine bisherigen Bereiche zieht die App beim ersten Start selbst um,
  ohne Netz — du musst nichts neu laden.
- **Aktualisieren je Region, nur was alt ist**: „Meine Bereiche" sagt
  oben je Region, wie viele deiner Kacheln älter sind als der aktuelle
  Kartenstand. „Aktualisieren" nennt vorher die Größe, warnt über
  Mobilfunk und holt dann nur diese Kacheln — für alle Bereiche dort auf
  einmal. Von selbst passiert das nie. Ein laufender Download lässt sich
  dort jetzt auch abbrechen.

## Karte jetzt auch in Südkanada

*Versionen 0.104.0, 0.105.0 und 0.105.1, 2026-10-09*

- **Die Karte reicht bis nach Kanada**: Im Süden Kanadas, bis zum
  55. Breitengrad, zeigt die App jetzt dieselbe Karte wie in DACH. Sie
  sucht sich von selbst aus, wo du gerade schaust — einen Wähler gibt es
  nicht.
- **Bereiche speichern geht dort auch**: Ein Bereich in Kanada kommt
  aus der kanadischen Karte und bleibt auf dem Gerät wie jeder andere.
  Wo es keine Karte gibt, sagt die App beim Speichern in einem Satz,
  für welche Gegenden es welche gibt.
- Wege, Orte und Höhen holt die App dort genauso nach Lage, sobald der
  Kartenhost sie für Kanada bereithält.
- **Übersichtskarte für Kanada**: Der erste Bereich, den du in Kanada
  speicherst, bringt eine grobe Karte von ganz Kanada mit (rund 35 MB,
  der Dialog nennt die Größe). Ohne Empfang liegt um deine Bereiche dann
  Land, Wasser, Orte und große Straßen statt einer leeren Fläche — wie in
  DACH, wo diese Karte schon in der App steckt. Unter „Meine Bereiche"
  steht sie als eigene Zeile zum Löschen; mit deinem letzten Bereich in
  Kanada geht sie von selbst.

## Sperren offizieller Trails mit Datum

*Version 0.103.0, 2026-10-08*

- **Gesperrt — und seit wann**: Sperrt das Land Tirol einen offiziellen
  Trail, nennt das Blatt jetzt auch den Stand der Quelle, etwa
  „Gesperrt laut Land Tirol, Stand 28.09.2026".
- **Die Warnung im Trail-Blatt trifft genauer**: Deckt einer deiner
  Trails einen offiziellen, warnt die Zeile nur noch, wenn der
  gesperrte Abschnitt wirklich auf deinem Trail liegt. Ist nur eine
  Variante daneben gesperrt, steht dort „anderer Abschnitt gesperrt".
- Die Sperren werden jetzt täglich statt wöchentlich abgerufen.

## Ohne Empfang auch in der Web-App

*Version 0.102.0, 2026-10-08*

- **Die Web-App behält deine Trails**: Sie legt das Netz deiner Trails
  im Speicher des Browsers ab. Startest du sie ohne Empfang neu, zeigt
  sie den letzten Stand — mit Datum, damit du weißt, wie alt er ist.
- **Den Ausgangskorb gibt es jetzt auch im Browser**: Steuerst du ohne
  Netz eine Aufzeichnung bei, speicherst deine Einschätzung, meldest
  etwas oder schickst Feedback, wartet der Auftrag im Browser und geht
  raus, sobald wieder Verbindung besteht. Beim ersten Mal bittet die App
  den Browser, diesen Speicher nicht von selbst zu räumen. Sagt er nein,
  steht das auf der Karte — dann am besten senden, sobald du Empfang
  hast.

## Gesehenes bleibt liegen — auch im Browser

*Version 0.101.0, 2026-10-08*

- **Die Web-App merkt sich jetzt ebenfalls, was du angesehen hast**:
  Kartenstücke und Wege, die du mit Empfang geladen hast, bleiben im
  Speicher des Browsers, bis zu 100 MB, die am längsten nicht
  gebrauchten gehen zuerst. Ohne Netz zeigt die Karte sie über der
  groben Übersicht. Und weil ein Stück, das schon liegt, nicht noch
  einmal geholt wird, baut sich eine bekannte Gegend schneller auf. Der
  Browser darf seinen Speicher selbst räumen — für ganze Gebiete
  bleiben die gespeicherten Bereiche der sichere Weg.

## Höhenlinien

*Version 0.100.0, 2026-10-08*

- **Höhenlinien auf der Karte**: Unter „Kartenebenen" schaltest du sie
  dazu. Sie liegen dezent unter Wegen und Trails, die kräftigeren tragen
  ihre Höhe. Wie dicht sie liegen, richtet sich nach dem Gelände: im
  Hügelland alle 10 oder 20 m, in den Alpen alle 50 oder 100 m — die
  Legende sagt, welcher Abstand gerade gilt. Sie kommen aus demselben
  Geländemodell wie die Höhenprofile, in gespeicherten Bereichen also
  auch ohne Empfang. Weit herausgezoomt erscheinen keine.

## Gesehenes bleibt liegen

*Version 0.99.0, 2026-10-08*

- **Die Karte merkt sich, was du angesehen hast**: Auf dem Telefon
  bleiben die Kartenstücke, die du mit Empfang geladen hast, auf dem
  Gerät, bis zu 100 MB, die ältesten gehen zuerst. Wer am Vorabend die
  Gegend ansieht, hat sie im Wald auch ohne Netz, samt Forstwegen und
  Pfaden. Wo nichts liegt, zeigt die Karte wie bisher die grobe
  Übersicht. Für ganze Gebiete bleiben die gespeicherten Bereiche der
  sichere Weg; im Browser kommt das später.

## Forstweg oder Pfad auf einen Blick

*Versionen 0.98.0 und 0.99.1, 2026-10-08*

- **Forstwege sind jetzt eine Doppellinie**: zwei schmale Fahrspuren
  mit hellem Streifen in der Mitte, wie in einer Wanderkarte. Pfade
  bleiben eine einfache Linie. Wie gut der Forstweg ist, zeigen weiter
  die Spuren: durchgezogen heißt gut, gestrichelt mittel, gepunktet
  schlecht. Die Legende zeichnet es genauso.
- **Namen stehen wieder über den Wegen**: Orts-, Flur- und
  Straßennamen lagen unter der Wege-Ebene und wurden von Forstwegen
  durchgestrichen. Auf dem Telefon stehen sie jetzt obenauf.

## Navigieren

*Versionen 0.94.0 bis 0.97.0, 2026-10-08*

- **Folgeansicht**: Im Ergebnis einer Runde und eines Wegs zum Trail
  steht jetzt „Navigieren", in „Meine Fahrten" im Menü jeder Fahrt
  ebenso. Die Karte dreht sich mit der Fahrtrichtung, deine Position
  sitzt im unteren Drittel, die Route ist hervorgehoben und der
  gefahrene Teil wird blass.
- **Oben drei Zahlen**: wie weit es noch ist, wie viele Höhenmeter
  bergauf noch kommen und wie weit du neben der Route bist. Bist du
  mehr als 30 m daneben, steht der Abstand in Warnfarbe, und ein Pfeil
  zeigt zur Route. Abbiegehinweise und Ton gibt es bewusst nicht —
  fahre nach Sicht.
- **„Norden"** schaltet die Drehung ab. Am Ziel steht „Angekommen",
  die Navigation endet nach einer Minute von selbst.
- **Beim Start** fragt die App, ob die Fahrt mit aufgezeichnet werden
  soll und ob der Bildschirm anbleibt — beides ist vorgewählt. Beenden
  der Navigation beendet die Aufzeichnung nicht.
- **„Zurück zur Route"** (0.95.0): Bist du neben der Route, sucht ein
  Tipp den Weg zurück — nicht zum nächsten Punkt, sondern 200 m voraus,
  damit du nicht umkehrst. Das Stück liegt gestrichelt vor der Route
  und verschwindet, sobald du wieder drauf bist. Gerechnet wird über
  deine Bereiche wie bei der Planung; findet sich kein Weg, sagt es
  die Leiste. Neu gerechnet wird nie von selbst.
- **„Zuletzt navigiert"** (0.95.0): Oben in „Meine Fahrten" geht eine
  beendete Navigation mit einem Tipp weiter, dort, wo du aufgehört hast.
- **In der Benachrichtigung** (0.96.0): Steckt das Telefon in der
  Tasche oder ist eine andere App vorne, zeigt die Benachrichtigung,
  wie weit es noch ist, die Höhenmeter und ob du auf der Route bist —
  alle fünf Sekunden neu, auch wenn du TrailBuddy aus der Übersicht
  gewischt hast. „Navigation beenden" geht direkt dort, ein Tipp auf
  die Benachrichtigung holt die Karte zurück. Läuft die Aufzeichnung
  mit, bleibt es eine Benachrichtigung, nicht zwei. Im Browser gibt es
  das nicht.
- **Kleines Fenster** (0.97.0): Wischst du während der Navigation nach
  Hause, schrumpft die Karte in ein Fenster über den anderen Apps —
  die Route dreht weiter mit, oben stehen Rest, Höhenmeter und ob du
  daneben bist. „Beenden" geht direkt im Fenster, ein Tipp darauf holt
  die App zurück. Ab Android 8; im Browser gibt es das nicht.

## Den Weg von Hand ziehen

*Version 0.93.0, 2026-10-08*

- **Zwischenpunkte**: Ein Tipp auf die Linie einer geplanten Runde
  oder eines Wegs zum Trail setzt dort einen Punkt. Zieh ihn dorthin,
  wo der Weg langgehen soll — beim Loslassen rechnet die App den Weg
  durch ihn neu. Ein Tipp auf den Punkt nimmt ihn wieder weg, mit
  „Rückgängig".
- Bei der Runde bleibt die Reihenfolge der Trails, wie sie ist; nur die
  Verbindungen folgen deinen Punkten. Liegt die Runde danach über deinem
  Budget, sagt es das Blatt. „Zurücksetzen" rechnet wieder frei.
- Führt durch einen Punkt kein Weg, springt er an seinen Platz zurück.

## Der Planer kennt schlechte Wege

*Version 0.92.0, 2026-10-08*

- **Bergauf lieber über den guten Forstweg**: Runde und Weg zum Trail
  wissen jetzt, wie gut ein Forstweg ist und wie schwer ein Pfad. Ein
  holpriger, grober oder matschiger Forstweg kostet bergauf deutlich
  mehr, ein schwerer Pfad zählt bergauf als geschoben. Bergab ändert
  sich nichts.
- Gemessen an echten Fahrten: Wer selbst plant, fährt schlechte
  Forstwege kaum hinauf — der Planer nahm sie bisher doppelt so oft,
  jetzt etwa so selten wie die Fahrten.
- Wo OpenStreetMap nichts über einen Weg weiß, plant der Planer wie
  bisher. Die Güte kommt aus deinen gespeicherten Bereichen und, mit
  Empfang, vom selben Kartenserver wie die Karte.

## Wie gut ist der Weg?

*Versionen 0.89.0–0.91.0, 2026-10-08*

- **Forstwege nach Güte, Pfade nach Schwierigkeit**: Ab Zoomstufe 13
  liegt über den Wegen der Karte, was OpenStreetMap über sie weiß.
  Durchgezogen und kräftig heißt ein guter Forstweg oder ein leichter
  Pfad, gestrichelt mittel, gepunktet und blass ein schlechter Forstweg
  oder ein schwerer Pfad. In der Legende stehen die Striche unter
  „Forstweg" und „Pfad".
- Wo in OpenStreetMap nichts eingetragen ist, bleibt der Weg, wie die
  Karte ihn immer gezeichnet hat — bei Pfaden ist das noch der Normalfall.
- Die Ebene ist ab Werk an; unter „Kartenebenen" schaltest du sie ab.
  Die Daten kommen vom selben Kartenserver wie die Karte selbst.
- **Auch ohne Empfang** (0.90.0): Ein gespeicherter Bereich nimmt die
  Wege jetzt mit, wie Orte und Höhen — der Dialog vor dem Speichern
  nennt sie, und die Größe zählt sie mit. Das gilt auch, wenn die Ebene
  gerade aus ist; schaltest du sie im Wald ein, sind sie da.
- Bereiche von früher zeigen unter „Meine Bereiche" „Wege verfügbar";
  ein Tipp auf „Aktualisieren" holt sie nach.
- **Feiner abgestuft** (0.91.0): Ganz schlechte Forstwege (grobes
  Geröll, tiefe Spurrinnen, Matsch) und sehr schwere Pfade haben jetzt
  eine eigene, noch blassere Stufe mit weiter auseinanderliegenden
  Punkten. Das ist die Grundlage dafür, dass der Planer solche Wege
  bergauf bald meidet.

## Höhenprofil der geplanten Runde

*Version 0.88.0, 2026-10-07*

- **Auf einen Blick, wo es hoch und runter geht**: Unter der Summe einer
  geplanten Runde steht jetzt ihr Höhenprofil, kompakt über die ganze
  Strecke vom Start bis zurück. Dasselbe gibt es beim Weg zum Trail und
  bei „Route hierher".
- Die Höhen kommen aus dem Geländemodell deiner gespeicherten Bereiche,
  mit Empfang auch vom Kartenserver. Fehlt für ein Stück die Höhe, zeigt
  die App lieber kein Profil als ein erfundenes.

## Planer: Treppen bergauf meiden

*Version 0.87.0, 2026-10-07*

- **Das Rad wird nicht mehr die Treppe hinaufgeschickt**: Wo es eine
  Treppe hinaufginge, rechnet der Planer jetzt mit, dass du das Rad
  trägst, und nimmt lieber einen Umweg über Forstweg — auch wenn die
  Treppe nur kurz ist. Hinunter gilt das nicht, und ein Weg, den es nur
  über die Treppe gibt, bleibt möglich.

## Feedback auch ohne Empfang

*Version 0.86.0, 2026-10-07*

- **Nichts geht mehr verloren**: Schreibst du über die Glühbirne einen
  Wunsch oder einen Fehler, während du kein Netz hast, bleibt er auf dem
  Gerät und geht von selbst raus, sobald wieder Empfang da ist — wie
  Trails, die du draußen beisteuerst.
- **Du siehst, was noch wartet**: Öffnest du die Glühbirne, steht oben,
  welche Meldung noch nicht übertragen ist. Sollte eine abgelehnt worden
  sein, kannst du sie dort noch einmal senden oder verwerfen.

## Meine Fahrten aufräumen

*Version 0.85.0, 2026-10-07*

- **Das Rad an jeder Fahrt**: In „Meine Fahrten" steht bei jeder Fahrt,
  ob sie mit dem Bio-Bike oder dem E-Bike gefahren wurde. Ein Tipp
  darauf stellt es um — wichtig, weil das Fahrerprofil aus diesen
  Fahrten lernt, wie schnell du bergauf kommst. Danach bietet die App an,
  gleich neu zu lernen.
- **Wischen und mehrere wählen**: Nach links wischen löscht eine Fahrt
  (die App fragt vorher nach). Ein langer Druck wählt mehrere aus; dann
  stellst du für alle das Rad ein oder löschst sie auf einmal.
- **Vorschlag beim GPX-Import**: Holst du alte Fahrten per GPX herein,
  schaut die App auf die Steigrate und schlägt je Fahrt Bio- oder
  E-Bike vor. Ist es nicht eindeutig, gilt das Rad, das du wählst.

## Trail-Liste: Ausschnitt und S-Grad nach Wahl

*Version 0.84.0, 2026-10-07*

- **„Auf der Karte"**: Ein neuer Chip in der Trail-Liste zeigt nur die
  Trails, die gerade im Kartenausschnitt liegen. Schiebst du die Karte
  weiter, zieht die Liste mit. Die Karte selbst blendet dabei nichts aus.
- **Schwierigkeit als Bereich**: Statt fest „bis S2" stellst du den
  S-Grad jetzt mit zwei Schiebern ein, zum Beispiel „ab S3" oder
  „S1–S3". Das gilt wie bisher für Liste und Karte. Trails, die noch
  niemand eingeschätzt hat, fallen dabei heraus, und die Liste sagt,
  wie viele.

## Legende, die sagt, was gemeint ist

*Version 0.83.5, 2026-10-07*

- **Die Legende auf der Karte nennt die Bedeutung**: Statt „bröckelig",
  „gestrichelt" und „verblasst" steht dort jetzt „ausgefahren",
  „abgerockt" und „kaum fahrbar", dieselben Wörter wie beim Melden.
  Kleine Überschriften (Schwierigkeit, Zustand, Am Trail) ordnen die
  Linien. Tour und Kurzanleitung erklären, welches Muster welcher
  Zustand ist.

## Links mit Umlauten

*Version 0.83.4, 2026-10-07*

- **Links mit ä, ö, ü sehen aus wie im Browser**: Am Trail steht
  „mühle-trails.de" statt einer Reihe von Prozentzeichen, und beim
  Bearbeiten steht der ganze Link lesbar im Feld. Umlaute darf man
  direkt eintippen.

## Planer gut sichtbar

*Version 0.83.3, 2026-10-07*

- **Gewählte Trails leuchten im Planer deutlich**: kräftiges Grün mit
  dunklem Rand unter der Linie, Pflicht-Trails mit stärkerem Rand.
  Bisher war die Auswahl so blass, dass man nach dem Umfahren eines
  Gebiets nicht sah, was dazugekommen war.
- **Die Startfahne hat einen dunklen Rand** und ist auf der hellen
  Karte gut zu finden.

## Aktuelle Bausteine

*Version 0.83.2, 2026-10-07*

- Die Bausteine für Anmeldung, Navigation in der App und GPX-Dateien
  sind auf dem neuesten Stand. Sichtbar ändert sich nichts.

## Ruhiger Start

*Version 0.83.1, 2026-10-07*

- **Das Logo beim Start zeichnet sich flüssig ein**, auch wenn die App
  darunter gerade lädt. Bisher sprang die Linie, sobald das Laden die
  Anzeige kurz aufhielt.
- **Danach bleibt es kurz stehen und blendet über eine Sekunde aus** —
  lange genug, um es zu lesen. Ein Tipp überspringt es wie bisher.

## Trail-Blatt: schließen und Anfahrt oben

*Version 0.83.0, 2026-10-07*

- **Das Blatt eines Trails lässt sich wieder schließen** — mit dem X
  oben rechts, mit der Zurück-Taste und indem du es nach unten ziehst,
  egal wo du es anfasst. Bisher ging Ziehen nur am kleinen Griff, und
  bei langem Inhalt lag der unter der Statusleiste.
- **Die Anfahrt sitzt jetzt als Navi-Symbol oben im Blatt**, neben dem
  Namen — am Parkplatz musst du nicht mehr bis ganz nach unten scrollen.
  Unten stehen nur noch „Zum Trailkopf" und „Karte".

## Kurze Trails

*Version 0.82.2, 2026-10-04*

- **Trails gibt es jetzt schon ab 50 m Länge** statt erst ab 150 m. Eine
  kurze Jump-Line oder eine Steilpassage zwischen zwei Forstwegen lässt
  sich damit beisteuern — beim Import, im Zerlege-Blatt und mit „Stück
  selbst wählen".

## Speichern ohne Hänger

*Version 0.82.1, 2026-10-02*

- **Ein Stern, ein Link, ein S-Grad: gespeichert, ohne dass die App
  stockt.** Bisher lud die App nach jedem Speichern das ganze Netz neu,
  mit jeder Linie, und schickte jede Linie noch einmal an die Karte. Bei
  vielen Trails stand die App dabei sekundenlang, bis Android „App
  reagiert nicht" melden konnte. Jetzt wird nur nachgelesen, was du
  geändert hast, und die Karte zeichnet nur die Linien neu, die sich
  wirklich ändern.
- Auch das Antippen eines Trails und „Meine Position" schicken nicht mehr
  alle Linien neu an die Karte.
- Die Kopie des Netzes für Funklöcher wird in kleinen Stücken
  geschrieben, die Bedienung läuft dabei weiter.
- Die Tastatur legt sich über die Karte, statt sie bei jedem Tippen
  kleiner zu rechnen.

## Alte Fahrten zählen mit

*Version 0.82.0, 2026-10-02*

- **Fahrten aus anderen Apps in „Meine Fahrten"**: Der GPX-Import bietet
  für aufgezeichnete Fahrten (mit Fahrzeiten) an, sie auf dem Gerät zu
  speichern — mit dem Rad, mit dem du sie gefahren bist, Bio-Bike oder
  E-Bike. Dieselbe Datei zweimal gewählt legt keine zweite Fahrt an.
- **Das Fahrerprofil lernt aus ihnen**: Gleich nach dem Speichern oder
  später unter „Fahrerprofil" — Steigrate und Flachgeschwindigkeit
  kommen dann auch aus deinen älteren Fahrten, mit den Höhen der Datei.
- Gespeicherte Fahrten lassen sich zerlegen und wieder als GPX
  exportieren wie jede eigene Aufzeichnung. Sie verlassen das Gerät nie
  von selbst.

## Wege nach deinem Geschmack

*Version 0.81.0, 2026-10-02*

- **Drei neue Schalter in den Parametern des Planers**: Straßen meiden,
  Wanderwege bergauf meiden, steile Rampen meiden. Ab Werk ist alles
  „meiden" wie bisher; ausgeschaltet heißt „ist mir egal" — dann bleibt
  nur ein kleiner Teil des Aufschlags, und eine kürzere Straße oder ein
  Pfad bergauf gewinnt eher. Die Wahl merkt sich das Gerät, und sie gilt
  auch für „Zum Trailkopf".
- **Steile Anstiege werden mit der Steigung immer teurer**: Statt ab
  15 % auf einen Schlag zählt jeder Höhenmeter ab 10 % ein wenig extra,
  sehr steile Rampen sehr viel — auf Schotter und Pfad mehr als auf
  Asphalt.
- **Bergab auf Verbindungswegen zählt etwas mehr**: Die Höhe ist
  verschenkt, die ein Trail hätte nutzen können. Bergab auf einem Trail
  kostet nichts extra.

## Runden rechnen, ohne dass die Karte steht

*Version 0.80.1–0.80.2, 2026-10-02*

- **Der Rundenplaner rechnet im Hintergrund**: Mit vielen gewählten
  Trails stand die Karte bisher während der Rechnung still, bei 60 Trails
  mehrere Sekunden. Jetzt bleibt sie bedienbar, und der Kreisel dreht
  weiter — nur beim ersten Rechnen nach dem Laden hakt es kurz.
- **Planer oder Ergebnis schließen bricht die Rechnung ab** — eine Runde,
  die danach fertig wird, taucht nicht mehr auf.
- **Nachrechnen geht fast sofort**: Wer nach der ersten Runde einen Trail
  abwählt, einen aus der Gegend dazuwählt, einen zur Pflicht macht oder
  Höhen- und Wanderweg-Budget ändert, bekommt die neue Runde in einem
  Augenblick statt nach Sekunden. Von vorn gerechnet wird bei anderem
  Startpunkt, anderem Fahrerprofil, anderer Zeit oder einem Trail
  weiter weg.

## Steile Rampen meiden

*Version 0.80.0, 2026-10-02*

- **Runden und Wege zum Trail weichen sehr steilen Anstiegen aus**:
  Jeder Höhenmeter über 15 % Steigung zählt extra — auf Schotter,
  Forstweg und Pfad dreifach, auf Asphalt einfach. Wo ein flacherer Weg
  hinaufführt, nimmt der Planer ihn, auch wenn er etwas länger ist.
- **Uphill-Trails bleiben gewollt**: Wer einen steilen Anstieg als
  Uphill-Trail eingetragen hat, fährt ihn — ohne Aufschlag.
- **Das Ergebnis sagt es**, wenn die Route trotzdem steile Stücke hat.
  Die geschätzte Zeit bleibt dabei, wie sie war.

## Höhen aus dem Geländemodell

*Version 0.79.0, 2026-10-02*

- **Jeder Trail hat ein Höhenprofil**: Fehlen einem Trail aufgezeichnete
  Höhen, zeigt das Blatt sein Profil aus dem Geländemodell (90 m) — aus
  deinen gespeicherten Bereichen oder mit Empfang vom Kartenhost. Die
  Kachel trägt dann ein „≈", das Profil sagt, woher es kommt, und
  gespeichert wird davon nichts.
- **Der GPX-Export trägt diese Höhen mit**, als Höhen aus dem
  Geländemodell markiert. Importierst du die Datei wieder, nimmt die App
  sie nicht als gemessen.
- **Der Import prüft die Höhen einer Datei**: Liegen sie weit neben dem
  Gelände (ein verstellter Höhenmesser, GPS-Sprünge), bietet er an, sie
  zu verwerfen — dann geht die Spur ohne Höhen hinauf, und das Blatt
  zeigt das Geländemodell.

## Runden auch ohne gespeicherten Bereich

*Version 0.78.0, 2026-10-02*

- **Mit Empfang ergänzt der Planer fehlende Wege**: Was deine
  gespeicherten Bereiche nicht tragen, holt er vom Kartenhost —
  höchstens 75 Kacheln je Planung, nur für diese Sitzung. Eine Runde
  oder der Weg zum Trail geht dann auch ganz ohne Bereich, und das
  Ergebnis sagt, wie viele Kacheln online dazukamen.
- **Offline-Lage zu Hause prüfen**: Unter Parameter lässt sich
  „Fehlende Wege online ergänzen" abschalten — dann rechnet der Planer
  wie im Funkloch, nur mit deinen Bereichen.

## Sofort sichtbar, auch im Funkloch

*Version 0.77.1–0.77.2, 2026-10-02*

- **Ein ausgewählter Trail leuchtet deutlich**: kräftiges Grün mit
  dunklem Rand statt eines blassen Schimmers, der im weißen Saum jeder
  Linie unterging.
- **Uphill-Trails sind jetzt magenta** statt petrol — das Petrol sah
  auf der Karte fast aus wie das Grün von S0.

- **Was du setzt, steht sofort da**: Schwierigkeit, Sterne und
  Meldungen erscheinen mit dem Tipp — blass und mit „wird übertragen",
  bis sie angekommen sind. Ohne Netz bleiben sie blass stehen und
  warten im Ausgangskorb. Lehnt der Server ab, verschwinden sie wieder,
  und die App sagt es.
- **Der Start ohne Empfang ist schneller**: Die Trails vom letzten Mal
  stehen nach gut einer Sekunde da statt nach sieben. Antwortet das
  Netz doch noch, kommt der frische Stand von selbst nach — und kommt
  die Verbindung später zurück, auch.
- **Die Karte bleibt im Funkloch nicht mehr leer**: Kommt die
  Online-Karte nicht, zeigt sie gleich die mitgelieferte Übersicht und
  wechselt, sobald die Online-Karte da ist.

## Die Legende auf der Karte

*Version 0.77.0, 2026-10-02*

- **Links am Rand steht eine schmale Lasche** mit den Pistenfarben. Ein
  Tipp klappt die Legende auf: welche Farbe welche Schwierigkeit ist,
  was die Art der Linie über den Zustand sagt und was die Ränder heißen.
  Ein Tipp auf „Legende" klappt sie wieder zu.
- **Die App merkt sich, wie du sie magst** — offen oder zu.
- Die Tour zeigt die Farben jetzt an der echten Legende statt in ihrer
  Sprechblase.

## Zurück, wie man es erwartet

*Version 0.76.0, 2026-10-02*

- **Die Zurück-Taste schließt Schritt für Schritt**: erst, was gerade
  offen ist — Blatt, Dialog, Unterseite —, in einem anderen Reiter
  danach die Karte statt die App.
- **Auf der Karte legt sie die App in den Hintergrund**, statt sie zu
  beenden. Beim nächsten Öffnen steht die Karte, wo du sie verlassen
  hast.

## Ebenen mit einem Tipp

*Version 0.75.0, 2026-10-02*

- **Der oberste Knopf rechts öffnet die Kartenebenen direkt**: welche
  Trails die Karte zeigt, die offiziellen Trails und die Orte — ein
  Blatt statt drei Schritte über die Leiste mit den Offline-Werkzeugen.
- **Die Offline-Karten haben einen eigenen Knopf** darunter. Er öffnet
  links die Werkzeuge zum Zeichnen, Radieren und Speichern wie bisher.
- **Die Glühbirne steht oben rechts**, neben den Hinweisen oben —
  abgesetzt von den Knöpfen, mit denen man die Karte bedient.

## Ruhigere Karte

*Version 0.74.2, 2026-10-02*

- **Kein Quadrat mehr am Ende eines Trails.** Wo er endet, zeigt die
  Linie, und der Pfeil am Anfang trägt die Richtung.
- **Die Schilder mit Grad und Charakter erscheinen eine Zoomstufe
  näher**, zusammen mit den Namen — weiter draußen bleibt die Karte
  frei.
- **Die Namen stehen auf dem Trail**, nicht mehr daneben, wo sie sich
  wie der Name des Nachbarwegs lasen — mit einem breiteren weißen Rand,
  damit sie auch auf einer schwarzen Linie lesbar bleiben.

## Fehlerberichte, die sagen, wo es passiert ist

*Version 0.74.1, 2026-10-02*

- **Wenn die App unterwegs einen Fehler abfängt, sagt der Bericht jetzt
  auch, in welchem Schritt es passiert ist** — beim Zeichnen, beim
  Abbauen eines Fensters oder in einer Animation. Ein Fehler aus 0.73.0
  kam fünfmal an, ohne dass sich die Stelle finden ließ; mit dieser
  Version lässt sie sich beim nächsten Mal benennen. Für dich ändert sich
  nichts, es wird nichts Neues über dich gemeldet.

## Navigation rund: sichtbar, ehrlich, nie gegen den Trail

*Version 0.74.0, 2026-10-01*

- **Die geplante Route liegt jetzt über dem Blatt, nicht darunter.**
  Planer und „Zum Trailkopf" sind kein Fenster mehr, das die Karte
  sperrt: Die Karte bleibt bedienbar, beim Ergebnis klappt das Blatt
  ein und die Karte zeigt die ganze Route darüber. **Runterziehen
  verkleinert nur** — geschlossen wird mit dem X oder Zurück.
- **Kein Scheitern mehr ohne Grund.** Gerechnet wird über die Kacheln
  deiner Bereiche, die da sind — auch wenn sie das Rechteck um die Runde
  nicht ganz füllen (das war bei „Entlang meiner Trails" fast immer so).
  Was eine Planung aufhält, steht oben im Blatt; geht beim Rechnen etwas
  schief, sagt das Blatt es, statt weiter zu kreiseln. Und Wege, an die
  ein Trailkopf angeheftet wird, verlieren ihre Höhen nicht mehr.
- **Nie rückwärts über einen Trail.** Liegt ein Trail auf einem Pfad der
  Karte, fährt die Planung ihn nur noch in seiner Richtung — nicht mehr
  hinauf. Ein flacher Trail darf auch andersherum: dafür gibt es im
  eigenen Beitrag **„In beide Richtungen fahrbar"**.
- **Uphill-Trails und Verbinder sind der Weg bergauf.** Sie stehen nicht
  mehr als Abfahrt im Pool, sondern werden beim Aufstieg bevorzugt —
  auch mehrmals, auch wenn die Karte sie nicht kennt. Das Ergebnis nennt
  sie mit Namen. Forstwege dürfen wie bisher beliebig oft vorkommen.
- **Der Planer hat eine eigene Leiste links**, wie „Ebenen": Start
  (Standort oder auf der Karte getippt), **Parameter** (Profil, Zeit,
  Höhenmeter, Wanderweg, „Start ist auch Ziel" und der Radius der
  Liste), die **Liste** der Trails im Radius, **Gebiet dazu / weg** (mit
  dem Finger umfahren — wie beim Zeichnen der Bereiche), Auswahl leeren
  und **Rechnen**. Vor allem aber: **Trails auf der Karte antippen** —
  einmal heißt dabei (sie leuchten), noch einmal heißt raus. Das Ergebnis
  kommt von unten, die Leiste und deine Auswahl bleiben stehen, bis du
  den Planer schließt.
- **Außerhalb des Planers heißt Trail antippen erst auswählen:** Er
  leuchtet, unten steht eine kleine Karte mit Name, Länge und Sternen;
  ein Tipp darauf (oder ein zweiter auf den Trail) öffnet das Blatt.
- **Das Navi-Symbol an jedem Trail** (Liste und kleine Karte): mit deiner
  Navi-App, oder in TrailBuddy **direkt** oder **spaßig** — spaßig nimmt
  Abfahrten auf dem Weg zum Trail mit. Einmal als Standard gemerkt, fragt
  nur noch ein langer Druck aufs Symbol.
- **Langer Druck auf die Karte:** „Route ab hier" (der Planer mit diesem
  Start), „Route bis hier" (der Weg von deinem Standort) oder die
  Navi-App.

## Auf dich eingestellt: gelernt aus deinen Fahrten

*Version 0.73.0, 2026-10-01*

- Unter „Fahrerprofil" im Profil gibt es jetzt **„Aus meinen Fahrten
  lernen"**: Die App liest Zeit und GPS-Höhe deiner Aufzeichnungen, findet
  die Aufstiege ab 100 Höhenmetern am Stück, ordnet sie über die Wege
  deiner gespeicherten Bereiche ein und merkt sich je Profil deine
  Steigrate (Forstweg, Pfad, Schieben) und deine Flachgeschwindigkeit.
- „Zum Trailkopf" und der Rundenplaner rechnen dann mit deinen Werten
  statt mit den Vorgaben — gelernte Zahlen stehen als „(gelernt)" dabei.
- Gelernt wird nur aus deinen eigenen Fahrten, nur auf diesem Gerät, und
  erst ab drei Aufstiegen je Wert; Fahrten ohne Profil oder ohne Höhen
  zählen nicht. **Zurücksetzen** bringt die Vorgaben zurück.

## Runde planen — deine Trails, bergab verbunden

*Version 0.72.0, 2026-10-01*

- Neuer Knopf auf der Karte: **„Runde planen"**. Du sagst, wo es losgeht
  (dein Standort oder ein getippter Punkt), wie lange es höchstens dauern
  darf, wie viele Höhenmeter bergauf und wie viel Wanderweg du in Kauf
  nimmst — und welche deiner Trails in Frage kommen. Ein Stern heißt „muss
  dabei sein".
- Die App baut daraus eine Runde, die möglichst viele Trails BERGAB in
  ihrer Richtung mitnimmt, verbunden über die Wege deiner gespeicherten
  Bereiche — offline, nach deinem Fahrerprofil. Ein Trail zweimal zählt
  nur, wenn ihn die Buddys mit 4 oder 5 Sternen bewertet haben.
- Das Ergebnis liegt auf der Karte; das Blatt sagt Länge, Höhenmeter,
  Trail-Meter und etwa die Zeit, nennt die Trails in Reihenfolge und sagt
  zu jedem, der nicht hineingepasst hat, warum. Gemeldete Trails bleiben
  draußen, bis du sie einzeln dazunimmst.
- **„Als Fahrt speichern"** legt die Runde — und seit jetzt auch den Weg
  „Zum Trailkopf" — als geplante Fahrt unter „Meine Fahrten" ab; von dort
  geht sie als GPX an deine Navi-App. Geplante Fahrten haben keine Schere:
  Zerlegt wird, was du wirklich gefahren bist.
- Die Regler merkt sich die App für die nächste Planung.

## Zum Trailkopf — der Weg aus deinen Bereichen

*Version 0.71.0, 2026-10-01*

- Im Trail-Blatt gibt es jetzt **„Zum Trailkopf"**: Die App rechnet den Weg
  von deinem Standort zum Anfang des Trails selbst — offline, aus den Wegen
  und Höhen deiner gespeicherten Bereiche, nach deinem Fahrerprofil. Die
  Karte zeigt die Linie, das Blatt sagt Länge, Höhenmeter und etwa die Zeit.
- Führt der Weg über Wanderweg, Fußweg oder Stufen, steht es dabei (die
  Linie ist dort gestrichelt). Ob du dort fahren darfst, sagt die App nicht.
- **„Als GPX"** gibt den Weg an deine Navi-App weiter; „Anfahrt" bleibt
  daneben — die Navi-App kennt die Straße zum Parkplatz, die App den
  Forstweg vom Parkplatz zum Trail.
- Ohne gespeicherten Bereich gibt es keinen Weg, und das Blatt sagt es.
  Gerechnet wird nie über Gegenden, die du nicht gespeichert hast.

## Fahrerprofil: Bio-Bike oder E-Bike

*Version 0.70.0, 2026-10-01*

- Im Profil gibt es jetzt **„Fahrerprofil"**: Bio-Bike oder E-Bike. Es
  ändert drei Dinge für die kommende Routenplanung — wie schnell es bergauf
  geht, wie teuer ein Wanderweg bergauf ist und wie viele Höhenmeter eine
  Runde haben darf. Bergab bleibt ein S2 ein S2.
- Jede Fahrt merkt sich beim Start, mit welchem Profil sie gefahren wurde.
  Daraus lernt die App später deine eigenen Steigraten — je Profil, nie aus
  Fahrten anderer.
- Unter der Haube steht damit der Wegegraph aus deinen gespeicherten
  Bereichen samt Höhen: die Grundlage für „Zum Trailkopf" und den Planer,
  die als Nächstes kommen.

## Höhendaten für gespeicherte Bereiche

*Version 0.69.0, 2026-10-01*

- Ein gespeicherter Bereich bringt jetzt **Höhendaten** mit: Für jedes
  Kartenstück lädt die App ein kleines Höhenraster (aus dem Copernicus-
  Höhenmodell, etwa 2 KB je Stück) und behält es neben der Karte auf dem
  Gerät. Beim Speichern steht dabei, ob Höhen mitkommen; „Meine Bereiche"
  zeigt „mit Höhen".
- Bereiche von früher haben noch keine. Sobald der Kartenhost Höhen
  anbietet, steht in der Liste „Höhendaten verfügbar", und **Aktualisieren**
  holt sie nach.
- Zu sehen ist davon noch nichts — die Höhen braucht die Routenplanung,
  die als Nächstes kommt. Ohne Höhen bleibt ein Bereich, was er war: die
  Karte für unterwegs.

## Fahrten und Trails als GPX-Datei

*Version 0.68.0, 2026-10-01*

- Jeden Trail gibst du jetzt im Blatt **„Als GPX exportieren"** weiter —
  über das Teilen-Menü an Komoot, Garmin, eine Navi-App oder einfach als
  Datei. In der Datei stehen nur die Linie, der Name und dein eigener
  Link; keine Buddys, keine Hinweise.
- Unter „Meine Fahrten" hat jede Fahrt ein Menü mit **„Als GPX
  exportieren"** und „Fahrt löschen". Die Fahrt geht ganz hinaus, mit
  Zeiten und der vom GPS gemessenen Höhe — das ist deine Sicherung.
- Im Browser wird die Datei heruntergeladen, wenn der Browser kein
  Teilen kennt.

## Anfahrt zum Trail

*Version 0.67.0, 2026-10-01*

- Im Blatt eines Trails gibt es jetzt **„Anfahrt"**: Der Anfang des
  Trails geht an deine Navi-App — welche, entscheidest du im Wähler von
  Android. TrailBuddy selbst baut dabei keine Verbindung auf.
- Ist keine Navi-App da (oder du bist im Browser), landen die
  Koordinaten in der Zwischenablage, und die App sagt es.

## Anfang, Richtung und Ende auf der Karte

*Version 0.66.0, 2026-10-01*

- Jeder Trail trägt jetzt am Anfang einen **Punkt mit Pfeil** in
  Fahrtrichtung und am Ende ein **Quadrat**, beide in seiner Farbe. So
  siehst du auf einen Blick, wo ein Trail losgeht und wohin er führt —
  auch bei Trails ohne Schild.
- Die Marken erscheinen wie die Schilder erst, wenn du nah genug
  herangezoomt hast; weiter draußen bleibt die Karte ruhig.

## Schnellerer Ladekreis

*Version 0.65.1, 2026-10-01*

- Das Ladesymbol zeichnet jetzt jedes Mal das **ganze Zeichen** ein,
  hält kurz und blendet aus — statt eines kurzen Stücks, das langsam
  hindurchlief. Ein Durchlauf dauert 1,4 statt 2 Sekunden.

## Das neue Logo

*Version 0.65.0, 2026-10-01*

- **Die Serpentine hat eine neue Form**: zwei Kehren mit Anliegern wie
  auf einem echten Trail, die Strecke wird zum Ende hin schmaler und
  läuft in kurzen Strichen aus. Der Punkt am Ende ist weg — die alte
  Form las sich als „2.", nicht als Trail.
- Das Zeichen gibt es in drei Größen: groß mit zwei Endstrichen, in der
  Statusleiste mit einem, als Browser-Symbol ohne — so bleibt es auch
  klein klar.
- Neu auf dem Homescreen (auch rund und als Themen-Symbol), in der
  Statusleiste, im Startbildschirm, im Loader, im Login und auf der
  Startseite der Tour. Auf runden Homescreen-Masken wird nichts mehr
  abgeschnitten.
- Beim Start zeichnet sich das Zeichen ein, und der Name baut sich
  daneben auf, als liefe der Trail weiter.
- Im Browser passt sich das Symbol im Tab an helles und dunkles
  Erscheinungsbild an.

## Kleine Korrekturen an der Einführung

*Version 0.64.1, 2026-09-30*

- In der Trails-Tour hebt der Schritt „Deine Einschätzung" jetzt auch
  die Sterne hervor, nicht nur den S-Grad — der Text sprach von beidem.
- Die Kurzanleitung sagt richtig, wo die Schere sitzt: im Import, nicht
  auf der Karte.

## Entdecken und Neuheiten

*Version 0.64.0, 2026-09-30*

- **Was ist neu, gleich nach dem Update**: Bringt eine neue Version etwas
  Sichtbares mit, zeigt die App beim nächsten Start ein kurzes Blatt
  „Neu in TrailBuddy" mit höchstens drei Neuheiten. Weggewischt ist
  weggewischt — verpasst hast du nichts, alles steht auch in „Entdecken".
- **Wer TrailBuddy schon länger hat**, bekommt einmal einen Rückblick:
  „Das kann TrailBuddy inzwischen" mit den wichtigsten Funktionen der
  letzten Wochen. Nach einer frischen Installation erklärt stattdessen die
  Tour.
- **„Entdecken" im Profil** listet alles, was TrailBuddy kann — nach
  Karte, Trails, Buddys und Profil, mit den Symbolen, die du auf den
  Knöpfen wiederfindest. Neues trägt einen Punkt, bis du die Seite
  geöffnet hast.
- **„Zeig es mir"** führt jede Funktion kurz vor und endet genau dort,
  wo sie wohnt — im Blatt eines Trails, in der Werkzeugleiste, im Profil.
  Dabei wird nichts ausgelöst; wo dir noch etwas fehlt (ein Trail, ein
  Buddy), sagt die Vorführung, wie du dahin kommst.

## Touren für Trails und Buddys

*Version 0.63.0, 2026-09-30*

- **Beim ersten Besuch der Reiter** „Trails" und „Buddys" zeigt eine
  kurze Tour, was dort steht: eine Zeile lesen, das Blatt eines Trails
  mit deiner Einschätzung, deinem Beitrag und den Hinweisen, Suche und
  Filter, der GPX-Import — und bei den Buddys Einladen, Suchen, offene
  Anfragen und was beim Verbinden passiert.
- **Auch ohne eigene Trails oder Buddys**: Während der Tour zeigt die App
  einen Beispiel-Trail und einen Beispiel-Buddy, deutlich als „Beispiel"
  markiert. Gespeichert wird davon nichts, und nach der Tour sind sie weg.
- **Beim ersten Start** geht es nach der Tour über die Karte auf Wunsch
  gleich weiter: „Weiter mit den Trails?", dann „Weiter mit den Buddys?".
  „Später" ist in Ordnung — dann kommt die Tour beim ersten Besuch des
  Reiters. In der Kurzanleitung startest du beide jederzeit neu.

## Hilfe beim Zerlegen

*Version 0.62.0, 2026-09-30*

- **Die erste Fahrt zerlegen**: Öffnest du nach einer Aufzeichnung zum
  ersten Mal das Zerlege-Blatt, erklärt eine kurze Tour, was du dort
  siehst — schon bekannte Trails, Vorschläge für neue mit ihren Griffen,
  was ohne gespeicherten Kartenbereich fehlt und dass nur die gewählten
  Stücke zu deinen Buddys gehen, nie die ganze Fahrt. Sie zeigt nur, was
  deine Fahrt wirklich hat. In der Android-App startet „Tour: Fahrt
  zerlegen" in der Kurzanleitung sie jederzeit an deiner jüngsten Fahrt.
- In der Zeile „Stück selbst wählen" läuft auf schmalen Telefonen nichts
  mehr über den Rand.

## Willkommen

*Version 0.61.0, 2026-09-30*

- **Beim ersten Start**: Nach dem Sicherheitshinweis begrüßt dich die
  App mit einer Startseite — was TrailBuddy ist und auf welchen drei
  Wegen Trails auf deine Karte kommen: GPX importieren, eine Fahrt
  aufzeichnen, Buddys verbinden. „Tour starten" zeigt danach die Karte
  Schritt für Schritt. „Nicht jetzt" ist in Ordnung — dann fragt die App
  beim nächsten Start noch einmal. Wer die Tour gesehen oder
  übersprungen hat, bekommt sie nicht wieder; in der Kurzanleitung
  startet sie jederzeit neu.
- **Alle, die TrailBuddy schon benutzen**, sehen die Startseite nach
  diesem Update einmal.

## Tour über die Karte

*Version 0.60.0, 2026-09-30*

- **Tour auf der Karte**: In der Kurzanleitung startet „Tour auf der
  Karte zeigen" eine geführte Tour. Sie dunkelt die Karte ab, hebt
  hervor, worum es gerade geht, und öffnet selbst, was sie erklärt —
  das Blatt eines Trails, die Werkzeugleiste unter „Ebenen" und den
  Filter für Orte und offizielle Trails. Eine kleine Legende zeigt, was
  Farbe und Art einer Linie bedeuten. Antippen löst während der Tour
  nichts aus; „Überspringen" oder die Zurück-Taste beenden sie jederzeit.

## Kurzanleitung und Sicherheitshinweis

*Version 0.59.0, 2026-09-30*

- **Kurzanleitung**: Im Profil steht jetzt „Kurzanleitung" — das
  Wichtigste in sechs Schritten, mit denselben Symbolen wie auf der
  Karte: Trails importieren, die Karte lesen (was Farbe und Art einer
  Linie bedeuten), Fahrten aufzeichnen und zerlegen, Buddys und wer was
  sieht, dein Beitrag zu einem Trail, und was ohne Empfang geht.
- **Sicherheitshinweis**: Beim ersten Start sagt die App einmal, was sie
  dir nicht abnehmen kann — ob ein Weg befahren werden darf oder gerade
  sicher ist. Nachlesen kannst du ihn jederzeit in der Kurzanleitung und
  unter „Über TrailBuddy".
- **Hilfe, wo noch nichts ist**: Eine leere Karte, eine leere
  Trail-Liste, noch keine Buddys oder noch keine Fahrt — überall führt
  jetzt ein Tipp in die Kurzanleitung.

## Meldungen aktuell halten

*Version 0.58.0, 2026-09-30*

- **Noch gültig?**: Im Profil steht, wie viele deiner Meldungen und
  Zustände älter als 30 Tage sind. Auf der Seite dazu beantwortest du je
  Trail „Ja" (gilt weiter), „Nein" (bei einer Meldung ist der Trail
  wieder offen, beim Zustand wählst du den neuen) oder „Weiß nicht" —
  dann bleibt alles, wie es ist, und die App fragt in 14 Tagen wieder.
  Dieselben Trails findest du in der Liste und auf der Karte über den
  Filter „Noch gültig?".
- **Fahrdatum nachtragen**: Eine GPX-Datei ohne Fahrzeiten gilt als nur
  geplant. Bist du den Trail gefahren, trägst du beim Import „Gefahren
  am …" ein. Dann zählt er als gefahren — deine Meldungen dazu sind
  bestätigt, und eine eigene Sperrmeldung von davor steht wieder auf
  offen. Die Linie bleibt gezeichnet und wird nie die Linie des Trails.

## Unterwegs markieren

*Version 0.57.0, 2026-09-30*

- **Trail beginnt, Trail endet**: Während einer Aufzeichnung steht über
  dem Aufnahmeknopf eine Fahne. Tippst du sie am Anfang eines Trails an,
  ist der Beginn markiert, und der Knopf wird zur Zielflagge mit Rand;
  am Ende tippst du noch einmal. Nach der Fahrt steht jedes markierte
  Stück im Zerlege-Blatt als Kandidat, schon angehakt — auch ohne
  gespeicherten Kartenbereich und auch dort, wo die Suche nach Abfahrten
  nichts findet. Sitzt eine Marke nicht ganz genau, verschiebst du sie
  mit den Griffen. Vergisst du das Ende, gilt das Stück bis zum Schluss
  der Fahrt.

## Bewerten und melden

*Versionen 0.49.0 bis 0.56.0, 2026-09-30*

- **Einen Buddy-Trail zu deinem machen**: Fährst du einen Trail zum
  ersten Mal, den du bisher nur über einen Buddy kennst, klappt seine
  Zeile im Zerlege-Blatt auf — Name, Schwierigkeit, Charakter und Sterne
  sind vorbelegt mit dem, was dein Netz sagt („Vorschlag aus dem Netz"),
  dazu der zuletzt bestätigte Zustand. Ein Tipp auf „Übernehmen" (oder
  „Alle übernehmen") genügt; Sterne musst du vergeben, sonst wird das
  Stück nicht beigesteuert. Danach ist es dein eigener Beitrag: Löscht
  der Buddy seinen oder entfreundet ihr euch, bleibt der Trail mit Namen
  bei dir.
- Für Trails, die du schon früher gefahren bist: Im Trail-Blatt steht
  „Übernehmen", solange dein Beitrag keinen eigenen Namen hat — mit
  derselben Vorbelegung. Nach einem GPX-Import bietet das Ergebnis es
  für Trails an, die du schon über Buddys kanntest. Und in der Liste
  gibt es den Filter **„Bewertung offen"** für eigene Trails ohne
  deine Sterne.

- **Unterwegs bestätigen**: Fährst du mit laufender Aufzeichnung auf
  einem Trail, zu dem eine Meldung oder ein Zustand noch bestätigt
  werden muss, fragt dich die App sofort per Benachrichtigung — mit dem
  Namen des Trails und dem, was gemeldet ist. „Stimmt" bestätigt es,
  „Trail ist frei" meldet ihn offen, „Ändern…" öffnet den Trail. Je
  Trail und Fahrt kommt die Frage höchstens einmal. Deine Antwort geht
  beim Beenden der Fahrt als bestätigte Meldung an deine Buddys, ohne
  Empfang später. Die Prüfung läuft auf dem Telefon, deine Position
  verlässt es nicht.
- Hast du unterwegs nicht geantwortet oder „Ändern…" gewählt, steht
  dieselbe Frage **nach der Fahrt im Zerlege-Blatt** an der Zeile des
  Trails — dort auch mit der Wahl, was stattdessen gilt. Die Antwort
  zählt mit der Zeit, zu der du dort warst.
- **Benachrichtigungen sagen jetzt, worum es geht**: „Anna meldet
  „Hexenkessel" als gesperrt" statt „Ein Buddy meldet einen Trail …",
  bei einem Hinweis steht der Text dabei. Der Name ist dein Alias für
  den Buddy, der Trailname der, den du in der App siehst. Ein Ort steht
  nie darin.

- **Auf der Karte sieht man den Zustand an der Linie**: durchgezogen,
  wenn alles gut ist, bröckelig bei „ausgefahren", gestrichelt bei
  „abgerockt", gestrichelt und blass bei „kaum fahrbar". Die Farbe
  bleibt die Schwierigkeit. Gezählt wird nur ein bestätigter Zustand.
- **S4 und S5** erkennt man jetzt am gestrichelten weißen Rand um die
  Linie, nicht mehr an der gestrichelten Linie selbst.

- **In der Trail-Liste** stehen die Sterne jetzt unter den Zahlen — blass,
  solange du einen eigenen Trail noch nicht bewertet hast. Sortieren
  lässt sich nach „Bewertung", die besten zuerst.
- Ist ein Trail „abgerockt" oder „kaum fahrbar", sagt es die Zeile als
  Wort. Eine Meldung, die noch jemand vor Ort bestätigen muss, steht
  gedämpft mit Fragezeichen da („GESPERRT?").

- **Sterne**: Trails, die du selbst gefahren bist, bewertest du mit 1
  bis 5 Sternen — im Blatt unter „Deine Bewertung" oder in „Mein
  Beitrag". Das Blatt zeigt in einer zweiten Kachelreihe, was dein Netz
  sagt (der mittlere Wert und wie viele es sind); ein Tipp zeigt, wer
  was vergeben hat. Hast du einen Trail noch nicht bewertet, stehen die
  Sterne dort blass.
- **Aus „Status" wird „Meldung"**, und melden kann jetzt jeder, der den
  Trail sieht: im Blatt unter „Melden" — offen, gesperrt, zerstört oder
  verändert.
- **Neu: der Zustand**, von „kaum fahrbar" bis „top gepflegt". Du
  meldest ihn zusammen mit der Meldung oder allein; die Kachel ZUSTAND
  zeigt den jüngsten mit seinem Alter.
- **Bestätigt oder zu bestätigen**: Bist du den Trail gefahren oder
  gerade vor Ort („Ich bin vor Ort", höchstens 200 m von der Linie),
  gilt deine Meldung als bestätigt. Sonst steht sie blass mit „zu
  bestätigen" da, und deine Buddys bekommen dafür keine
  Benachrichtigung. Deine Position verlässt dabei das Telefon nicht —
  an den Server geht nur, OB du vor Ort warst.
- **Wer hat was gemeldet**: Das Blatt zeigt die Meldungen der letzten
  90 Tage mit Namen und Alter.
- **Alte Dateien melden nichts mehr**: Eine importierte Fahrt setzt
  deine Meldung nur noch auf „offen", wenn sie jünger ist als die
  Meldung — eine GPX-Datei von 2024 hebt ein „gesperrt" von gestern
  nicht mehr auf.
- Ohne Netz wartet eine Meldung im Ausgangskorb und geht mit der Zeit
  raus, zu der du sie gemacht hast.

## Trails beschreiben

*Version 0.48.0, 2026-09-30*

- **Link zur Quelle**: Ein Trail kann auf eine Seite zeigen, etwa die
  des Vereins mit Beschreibung und Regeln. Trägt deine GPX-Datei einen
  Link, übernimmt der Import ihn; sonst trägst du ihn in „Mein Beitrag"
  ein. Das Blatt zeigt die Adresse kurz, ein Tipp öffnet sie im Browser.
  Nur https, und alles nach „?" fällt weg — Freigabelinks tragen dort
  oft einen Schlüssel.

## Fahrten zerlegen

*Version 0.47.0, 2026-09-30*

- **Stück selbst wählen**: Im Zerlege-Blatt gibt es unter den
  Kandidaten „Stück selbst wählen". Die Griffe reichen über die ganze
  Fahrt — für Jump-Lines, flache Flowtrails, Uphills und alles andere,
  was die Suche nach Abfahrten nicht findet. Das geht auch ohne
  gespeicherten Kartenbereich. Vorgewählt ist die Fahrt ohne ihre ersten
  und letzten 300 m, damit die Haustür nicht aus Versehen mitgeht; der
  Hinweis „Beginnt nahe deinem Start" folgt jetzt den Griffen.

## Trails verwalten

*Versionen 0.46.0 bis 0.46.1, 2026-09-29 bis 2026-09-30*

- **Geplant heißt nicht gefahren** (0.46.1): Eine GPX-Datei ohne
  Fahrzeiten, etwa von einer Vereinsseite, setzt deine Meldung
  „gesperrt" nicht mehr auf „offen" zurück — nur eine echte Fahrt tut
  das. Und das Trail-Blatt sagt jetzt, wer einen Trail nur geplant hat.

- **Beitrag löschen** (0.46.0): Im Trail-Blatt steht neben „Mein Beitrag" jetzt
  „Löschen". Es nimmt deine Aufzeichnungen, deine Einschätzung und deine
  Hinweise zu diesem Trail weg. Haben Buddys ihn auch gefahren, bleibt
  er für sie stehen; sonst verschwindet er.

## Aussehen

*Versionen 0.38.0 bis 0.45.2, 2026-09-29*

- **Sauberes Logo** (0.45.2): Die Schrift im Startbild ist nicht mehr
  gelb doppelt unterstrichen.

- **Nahtloser Start** (0.45.1): Das Startfenster auf Android hat jetzt
  den Grundton der App statt Weiß oder Schwarz, und die Leiste mit
  Meldungen unten trägt ihre Aktion in Lime. Die Kartenquellen unten
  links stehen nur noch einmal da, auch mit mehreren gespeicherten
  Bereichen.

- **Ein bisschen Bewegung** (0.45.0): Beim Start zeichnet sich das Logo,
  während die App darunter schon lädt — ein Tipp überspringt es. Wo
  etwas lädt, läuft die Serpentine des Logos statt des Kreisels. Während
  einer Fahrt pulst ein Ring um deinen Punkt auf der Karte. Nach dem
  Verbinden mit einem Buddy laufen zwei Spuren zu einer zusammen, und
  ein Trail mit neuem Hinweis atmet in der Liste mit seinem gelben Rand.
  Hast du auf dem Telefon „Animationen entfernen" eingeschaltet, bleibt
  alles still — der Start zeigt dann gleich die App.

- **Rundere Trails mit Namen** (0.44.0): Die Linien auf der Karte
  laufen jetzt in weichen Kurven statt in Ecken, und ab einem
  bestimmten Zoom steht der Name des Trails direkt an der Linie — auf
  dem Telefon folgt er ihrem Verlauf wie ein Straßenname.

- **Das Schild auch auf der Karte** (0.43.0): Wenn du nah genug
  heranzoomst, steht am Anfang jedes Trails sein Schild — Schwierigkeit,
  Charakter-Symbole und bei Auffahrten der Pfeil, in der Farbe der
  Linie. Es steht neben der Linie, nicht auf ihr, und ein Tipp darauf
  öffnet den Trail.

- **Die Farbe zeigt jetzt die Schwierigkeit** (0.42.0): Trails sind
  eingefärbt wie Skipisten — grün S0, blau S1, rot S2, schwarz ab S3,
  noch nicht eingeschätzt grau. Uphill-Trails haben ihre eigene Farbe,
  Petrol, und im Schild einen Pfeil nach oben — eine Pistenfarbe
  beschreibt eine Abfahrt. Das gilt für die Linie auf der Karte
  (ab S4 gestrichelt), den Streifen in der Liste und das neue Schild.
  Ob ein Trail deiner ist oder von Buddys kommt, steht nicht mehr in der
  Farbe, sondern im Wort darunter („MEIN", die Namen). Gesperrte Trails
  und neue Hinweise erkennst du auf der Karte am orangen bzw. gelben
  Rand um die Linie.

- **Die Schwierigkeit als Zeichen** (0.42.0): Neben jedem
  eingeschätzten Trail steht ein kleines Schild wie auf der Skipiste:
  Ring für S0, Punkt für S1, Quadrat für S2, Raute für S3, zwei Rauten
  für S4 und zwei Rauten mit Balken für S5. In der Liste rechts oben, im
  Blatt neben dem Namen, und in „Was bedeuten S0 bis S5?" lernst du die
  Zeichen.

- **Das Profil im neuen Look** (0.41.0): Oben stehen dein Name und
  wie viele Trails, Buddys und Fahrten du hast. Darunter führt je eine
  Zeile zu Import, Fahrten, Bereichen, Benachrichtigungen,
  Erscheinungsbild, Konto und „Über TrailBuddy" — und sagt gleich, was
  gerade eingestellt ist. Name, E-Mail, Passwort und „Konto löschen"
  findest du jetzt unter „Konto", Datenschutz, Impressum und „Was ist
  neu" unter „Über TrailBuddy".

- **Die Buddys im neuen Look** (0.40.0): Nach dem Annehmen einer
  Anfrage steht oben eine Karte „Mit Jan verbunden" mit drei Zahlen —
  wie viele Trails ihr gemeinsam habt, wie viele neu von Jan kommen und
  wie viele neu für Jan sind. Sie bleibt, bis du sie schließt. Anfragen
  stehen als Karten mit „Annehmen", jeder Buddy hat ein farbiges
  Buchstabenfeld und darunter, wie viele Trails ihr beide kennt. Das
  Einladen findest du oben rechts.

- **Das Trail-Blatt im neuen Look** (0.39.0): Der Name steht groß
  oben, darunter, wer den Trail kennt. Länge, Abfahrt und
  Schwierigkeit stehen in drei Kacheln nebeneinander, ein Tipp auf die
  Schwierigkeit zeigt wie bisher, wer was gesagt hat. Das Höhenprofil
  hat eine eigene Fläche, ein neuer Hinweis eines Buddys ist gelb
  umrandet. Unten stehen „Hinweis schreiben" und „Karte".

- **Die Trail-Liste im neuen Look** (0.38.0): Jeder Trail steht jetzt
  auf einer eigenen Karte. Ein Farbstreifen links sagt, wem er gehört:
  grün deiner, blau von Buddys, orange gemeldet. Darunter steht in
  einem Wort, was los ist: „NEUER HINWEIS" (dann ist die Karte gelb
  umrandet), „GESPERRT", „MEIN · 2 BUDDYS" oder die Namen deiner Buddys.
  Länge, Abfahrt und Schwierigkeit stehen in einer Zahlenschrift, oben
  steht, wie viele Trails es sind und wie lang zusammen.

- **Kleinigkeiten** (0.38.0): Kilometer mit Komma („3,4 km") überall,
  der Pfeil vor den Höhenmetern ist kein leeres Kästchen mehr, und die
  Titel oben auf Unterseiten haben wieder ihre richtige Größe.

## Benachrichtigungen

*Version 0.37.0, 2026-09-29*

- **Benachrichtigungen eingerichtet** (0.37.0): Im Profil lassen sich
  die Benachrichtigungen jetzt einschalten, auf dem Telefon und im
  Browser. Du erfährst dann, wenn ein Buddy einen Trail meldet, den du
  siehst, oder einen Hinweis dazu schreibt. Die Meldung nennt weder den
  Trail noch den Buddy. Was los ist, siehst du erst nach dem Antippen in
  der App.

## Offline-Karten

*Version 0.36.1, 2026-09-29*

- **Gespeicherte Bereiche zeigen sich auch bei schwachem Empfang**
  (0.36.1): Bisher sprang die App erst auf deine gespeicherten Bereiche
  um, wenn das Telefon gar kein Netz mehr meldete. Im Wald ist das
  selten so. Meist gibt es noch einen Balken, über den nichts mehr
  durchkommt. Dann wartete die Karte auf die Online-Kacheln, und Wege
  und Pfade fehlten, obwohl sie gespeichert waren. Jetzt liegen
  gespeicherte Bereiche immer obenauf, mit und ohne Empfang. Wo du
  nichts gespeichert hast, kommt die Karte wie bisher aus dem Netz.

## Trails finden

*Versionen 0.32.0 bis 0.36.0, 2026-09-29*

- **Orte überall, wo die Karte ist** (0.36.0): Hütten, Brunnen, Einkehr
  und die übrigen Orte gab es bisher nur in Deutschland, Österreich, der
  Schweiz und Liechtenstein. Jetzt kommen sie für den ganzen
  Kartenbereich — Südtirol und Norditalien, Slowenien, Elsass und
  Savoyen, Tschechien und die übrigen Nachbarn am Kartenrand. Sie
  erscheinen mit dem nächsten Monatsstand der Orte.

- **Charakter auch beim Zerlegen einer Fahrt** (0.35.0): Für jeden neuen
  Trail, den das Zerlege-Blatt vorschlägt, wählst du neben Name und
  Schwierigkeit jetzt auch den Charakter — mit denselben Chips wie in
  „Mein Beitrag". Das klappt auch ohne Empfang; der Charakter geht dann
  mit, sobald wieder Netz da ist. Was du schon eingetragen hattest,
  bleibt stehen, neue Merkmale kommen nur dazu.

- **Der Charakter eines Trails** (0.34.0): Statt einer einzigen „Art"
  wählst du in „Mein Beitrag" jetzt alles, was passt — Flowig, Jump-Line,
  Verblockt, Steil, Uphill, Naturtrail, Verbindung. Das Blatt zeigt die
  zwei Merkmale, die du und deine Buddys am häufigsten nennen, mit
  Anzahl („Verblockt · 3"), die Liste zeigt sie als Symbole. Neu in den
  Filtern: „Flowig" und „Jumps", für Liste und Karte. Deine bisherige
  Art ist übernommen.

- **Der Filter gilt jetzt auch auf der Karte** (0.33.0): Was du in der
  Liste filterst — Meine oder Von Buddys, „bis S2", neuer Hinweis,
  gemeldet —, zeigt auch die Karte, und umgekehrt: Dieselben Chips
  stehen auf der Karte im Blatt „Ebenen". Solange ein Filter gilt, sagt
  die Karte es oben („Gefiltert: bis S2 · 3 von 5 Trails"), und das X
  daneben hebt ihn auf. Suche und Sortierung bleiben in der Liste.

- **Suche in der Trail-Liste**: Tippe einen Trailnamen oder den Namen
  eines Buddys. Umlaute, Bindestriche und Leerzeichen sind egal —
  „rosskopf sued" findet „Roßkopf Süd". Bei einem Tippfehler zeigt die
  Liste den nächsten Namen und sagt dazu „Meintest du …?".
- **Filter und Sortierung**: Meine oder die meiner Buddys, „bis S2", nur
  mit neuem Hinweis, nur gemeldete. Sortieren nach zuletzt aktiv, Name,
  Länge, Abfahrt oder Schwierigkeit. Bei „bis S2" fehlen Trails, die noch
  niemand eingeschätzt hat — die Liste sagt, wie viele.

## Aussehen

*Versionen 0.28.0 bis 0.31.0, 2026-09-29*

- **Offline-Karten: eine Regel statt Grün und Rot** (0.31.0): Hell ist,
  was auf dem Gerät liegt, abgedunkelt der Rest — und um alles
  Gespeicherte läuft jetzt ein durchgehender Rand. Was du gerade dazu-
  oder wegnimmst, ist schraffiert und gestrichelt umrandet: helle
  Streifen auf Dunklem kommen dazu, dunkle Streifen auf Hellem fallen
  weg. Grün bleibt damit deinen Trails vorbehalten.
- **Neue Knöpfe auf der Karte** (0.30.0): Rechts unten stehen runde
  Knöpfe — Idee, Ebenen, Position — und darunter, gut mit dem Daumen
  erreichbar, der große Aufnahmeknopf: Lime zum Starten, orange mit
  Stop-Quadrat, solange die Fahrt läuft. Ist die Werkzeugleiste offen,
  hat der Ebenen-Knopf einen farbigen Rand.
- **Die Werkzeugleiste links ist größer und ruhiger**: Die Knöpfe sind
  größer (auch mit Handschuhen gut zu treffen), die Gruppen stehen mit
  etwas Abstand statt mit Trennlinien. Das gewählte Werkzeug ist
  hervorgehoben, Speichern leuchtet, sobald es etwas zu speichern gibt,
  und die Zahl darunter sagt, wie viel dazukommt und wegfällt. Maßstab
  und Quellenhinweis rücken zur Seite, solange die Leiste offen ist.

- **Ein eigenes Logo** (0.29.0): eine Serpentine — zwei Kehren und ein
  Ziel. Sie ersetzt das Flutter-Standardsymbol auf dem Startbildschirm
  des Telefons, im Browser-Tab und bei der installierten Web-App, und sie
  steht jetzt auch in der Anmeldung.
- **Auch die Benachrichtigungen tragen das Logo**: Meldungen von Buddys
  und die laufende Fahrt zeigen oben in der Statusleiste die Serpentine
  statt der Berge.
- **Neue Farben und Schriften**: TrailBuddy trägt jetzt Lime als
  Markenfarbe, eine schmale Titelschrift und für Kilometer, Höhenmeter
  und Schwierigkeit eine Schrift, in der Zahlen sauber untereinander
  stehen. Die Schriften sind in der App eingebaut und sehen auch ohne
  Empfang gleich aus.
- **Hell oder dunkel**: Im Profil unter „Erscheinungsbild" wählst du
  System, Hell oder Dunkel. Die Karte selbst bleibt hell.
- **Trails heben sich besser von der Karte ab**: Jede Linie hat einen
  schmalen weißen Rand. Die Farben sagen weiter dasselbe — Grün ist
  deins, Blau kommt von einem Buddy, Orange ist gemeldet.

## Karte

*Versionen 0.24.0 bis 0.27.0, 2026-09-28 bis 2026-09-29*

- **Offline-Karten über eine schmale Leiste statt eines halben Blatts**
  (0.27.0): Der Ebenen-Knopf öffnet links eine Werkzeugleiste, die Karte
  bleibt frei. Darin: Orte und offizielle Trails, der aktuelle
  Ausschnitt (Kamera), Fläche dazunehmen und wegnehmen, die Kacheln
  entlang der eigenen Trails, Rückgängig, „Meine Bereiche" (Karte mit
  Zahnrad), Speichern und Schließen. Speichern fragt noch einmal nach
  und nennt vorher Größe, Zahl der Kartenstücke und Zahl der Orte.
  Schließen — über das X, den Ebenen-Knopf oder die Zurück-Taste —
  fragt nach, wenn etwas noch nicht gespeichert ist.
- **Die hervorgehobenen Kacheln bleiben beim Zoomen stehen**: Gespeichertes
  und Geändertes erscheint jetzt immer in den feinen Kartenstücken,
  nicht mehr je nach Zoom in größeren.
- **Gespeichertes lässt sich wieder wegnehmen, und man sieht, was sich
  ändert**: Hell ist, was auf dem Gerät liegt. Grün schraffiert ist,
  was beim Speichern dazukommt; rot und andersherum schraffiert, was
  wegfällt. Der Radierer über hellen Kacheln markiert sie zum Entfernen,
  der Stift über schon Gespeichertem ändert nichts — es wird nicht
  doppelt geladen. Die Leiste zählt beides getrennt (+ und −), der
  Speicher-Dialog nennt, was geladen wird und wie viel Platz frei wird.
  Entfernen geht auch ohne Empfang; ein Bereich, von dem nichts übrig
  bleibt, verschwindet ganz.
- **Die Knöpfe der Karte stehen jetzt rechts**, Maßstab und
  Quellenhinweis links unten — dort liegt nichts mehr darüber.
- **Einpassen stürzt auf Android nicht mehr ab** (0.26.1): Wenn die Karte
  auf das Netz, einen Trail, eine Fahrt oder einen Bereich zoomte, gab
  es im Hintergrund jedes Mal einen Fehler — sichtbar war er nicht, die
  Karte stand meist trotzdem richtig. Jetzt rechnet die App den
  Ausschnitt selbst und setzt ihn in einem Schritt. Nebenbei landet
  „Meine Position" auf Android nicht mehr eine Zoomstufe zu nah.
- **Bereiche zeichnen** (0.26.0): Im Blatt „Offline-Karten" gibt es
  „Bereich zeichnen". Stift antippen, dann auf der Karte mit dem Finger
  eine Fläche umfahren — jedes Kartenstück, das sie berührt oder
  umschließt, kommt dazu und steht grün auf der Karte. Weitere Striche
  kommen dazu, der Radierer nimmt wieder weg, was man umfährt oder
  überwischt. „Entlang meiner Trails" lässt sich als Ausgangspunkt
  übernehmen und dann zurechtschneiden; „Rückgängig" nimmt den letzten
  Schritt zurück. Zwischen zwei Strichen lässt sich die Karte ganz normal
  verschieben. Die Zahl der Kartenstücke steht live da, „Speichern …"
  misst die Größe und lädt wie gewohnt — samt Orten. Wer das Blatt
  zwischendurch schließt, verliert seine Striche nicht.
- **„Offline-Karten" zeigt, was auf dem Gerät liegt** (0.25.0): Unter
  „Ebenen und Orte" gibt es jetzt den Punkt „Offline-Karten". Solange
  das Blatt offen ist, bleibt auf der Karte hell, was gespeichert ist,
  der Rest ist abgedunkelt — die Karte lässt sich dabei schieben und
  zoomen. Im Blatt stehen die gespeicherten Bereiche (Antippen zeigt
  einen auf der Karte), „Bereich speichern" und der Weg zur Verwaltung.
- **„Entlang meiner Trails" speichert nur noch, was die Trails
  berühren**: Bisher legte „Um meine Trails" ein Rechteck um alle
  Trails — bei verstreuten Trails vor allem Land dazwischen, und bei
  vielen Trails zu groß. Jetzt kommen nur die Kartenstücke mit, denen
  ein Trail näher als 1 km kommt, samt den Orten dort. Aus einem
  Bereich, der an der Grenze scheiterte, wird so ein Bruchteil. „Meine
  Bereiche" und „Aktualisieren" kennen die Form; alte Bereiche bleiben,
  wie sie sind.

## Benachrichtigungen

*Version 0.23.0, 2026-09-28*

- **Wenn ein Buddy einen Trail meldet, sagt es dir dein Telefon**: Ein
  Schalter im Profil („Benachrichtigungen", ab Werk aus) trägt dieses
  Gerät ein. Meldet danach ein Buddy einen Trail, den du siehst, als
  gesperrt, zerstört, verändert oder wieder offen — oder schreibt einen
  Hinweis dazu —, bekommst du eine Meldung; mehrere Meldungen in kurzer
  Zeit werden zu einer. Antippen zeigt den Trail auf der Karte, bei
  mehreren die Liste.
- **In der Meldung steht kein Inhalt.** Kein Trailname, kein Name, keine
  Koordinate, nicht der Text des Hinweises — eine Meldung läuft über
  Googles Server, und ein Trail verlässt sein Netz nicht. Was passiert
  ist und wo, zeigt die App erst beim Öffnen. Die Datenschutzerklärung
  nennt den neuen Weg.
- „Testnachricht senden" prüft die ganze Kette bis zu diesem Gerät.
  Solange der Betreiber das Firebase-Projekt noch nicht angelegt hat,
  sagt der Schalter, dass Benachrichtigungen in diesem Build noch nicht
  eingerichtet sind.

## Buddys

*Version 0.22.0, 2026-09-28*

- **Nach dem Annehmen einer Anfrage sagt die App, was sich auf der Karte
  tut**: „Mit Jan verbunden: 14 Trails gemeinsam, 8 neu von Jan, 5 neu
  für Jan." Gemeinsam sind Trails, die ihr beide belegt habt — sie sind
  ab jetzt EIN Trail auf beiden Karten. Gezählt wird erst nach dem
  Annehmen, nie davor: Vorher wäre die Zahl ein Blick in die Sammlung
  eines Fremden. Deine privaten Trails zählen nicht als „neu für Jan",
  er sieht sie ja nicht.

## Wenn die App abstürzt

*Version 0.21.0, 2026-09-28*

- **Ein Absturz meldet sich beim nächsten Start selbst**: Wird die App
  von Android beendet — weil sie nicht mehr reagiert hat, abgestürzt ist
  oder der Speicher knapp war —, liest sie das beim nächsten Öffnen aus
  Androids eigener Liste und schickt den Grund als Fehlerbericht: mit
  Speicherwerten und einem Auszug des Thread-Dumps, aber ohne deine
  Trails, deine Position oder deine Fahrt. Normales Beenden (wegwischen,
  Neustart) wird nicht gemeldet. Nur Android ab Version 11.
- Fehlerberichte werden wie bisher nach 90 Tagen gelöscht; der Betreiber
  sieht sie als wöchentliche Zusammenfassung ohne Nutzerkennung.

## Fahrt zerlegen

*Version 0.20.0, 2026-09-28*

- **Nach der Fahrt zeigt ein Blatt, was daraus wird**: Die Fahrt liegt
  auf der Karte, zerlegt in Stücke. **Wieder gefahren** sind Trails
  deines Netzes, die unter deiner Spur liegen — vorangehakt, als Beleg
  beigesteuert, das hält den Trail aktuell. **Kandidaten für neue
  Trails** sind Stücke mit anhaltendem Gefälle abseits von Fahr- und
  Forststraßen: Mit zwei Griffen schneidest du zu (die Linie auf der
  Karte folgt), gibst einen Namen und einen S-Grad, oder verwirfst.
  Anfahrt, Forstweg und Straße werden nicht angeboten. Ein Kandidat, der
  nahe bei Start oder Ziel deiner Fahrt liegt, bekommt einen Hinweis —
  keinen Riegel.
- **Die Wege kennt die App nur aus einem gespeicherten Bereich.** Ohne
  Bereich bis Zoomstufe 13 über der Fahrt findet sie keine Kandidaten
  und sagt das; wieder gefahrene Trails gehen trotzdem. Also erst den
  Bereich speichern, dann die Fahrt aus „Meine Fahrten" zerlegen (die
  Schere).
- **Auch für GPX-Fahrten**: Im Import führt die Schere neben einer
  Fahrt auf die Karte in dasselbe Blatt. Höhen aus der Datei werden
  mit beigesteuert; die GPS-Höhe einer eigenen Aufzeichnung dient nur
  der Suche nach dem Gefälle und geht nicht mit.
- Die Fahrt bleibt als Ganzes auf dem Gerät; beigesteuert werden nur
  die gewählten Stücke.

## Karte

*Versionen 0.16.0, 0.17.0, 0.18.0 und 0.19.0, 2026-09-28*

- **Bereiche für unterwegs speichern** (0.19.0): Unter „Ebenen und Orte"
  gibt es jetzt „Bereich für unterwegs speichern" — der aktuelle
  Ausschnitt oder ein Rahmen um deine Trails mit 2 km Rand. Die Größe
  steht vorher da, genau gemessen, nicht geschätzt. Die Karte bis
  Zoomstufe 13 samt Orten bleibt dann auf dem Gerät und ist ohne
  Empfang die Karte. „Meine Bereiche" im Profil zeigt, was liegt, mit
  Größe und Kartenstand; ein neuerer Stand wird angeboten, nie
  aufgezwungen. Bereiche werden nie von selbst gelöscht.
- **Die Orte auf der Karte kommen jetzt auch vom eigenen Kartenspeicher**
  (0.18.0): Einkehr, Wasser, Rad-Service und Sonstiges liegen als fertige
  Dateien je Rasterzelle neben der Karte, einmal im Monat frisch aus
  OpenStreetMap. Die App lädt nur die Zellen, die dein Ausschnitt
  berührt, und fragt keinen fremden Dienst mehr live — schneller, und
  ohne dass dein genauer Ausschnitt irgendwohin geht. Filter, Nadeln und
  das Blatt beim Antippen bleiben, wie sie waren.
- **Die Karte kommt jetzt von unserem eigenen Kartenspeicher** (0.17.0):
  eine Vektorkarte von Deutschland, Österreich und der Schweiz bis
  Zoomstufe 13, mit Forstwegen, Pfaden und Steigen als eigene Linien
  statt in der Sammelgrube — Trails SIND die Wege. Die App lädt davon
  nur die Stücke, die der Ausschnitt braucht. Die Kachelserver von
  OpenStreetMap werden nicht mehr angefragt.

- **Neue Karten-Engine auf Android**: Die Karte rendert jetzt nativ auf
  der Grafikeinheit (MapLibre) — flüssiger beim Wischen und Zoomen,
  besonders mit vielen Trails. Im Browser bleibt alles wie bisher.
- **Eine Übersichtskarte ohne Empfang**: Fällt das Netz weg, liegt
  unter deinen Trails eine mitgelieferte Übersicht von Deutschland,
  Österreich und der Schweiz (Länder, Städte, große Straßen und Wege) —
  statt einer leeren Fläche. Sie steckt in der App und braucht kein
  Netz. Fein aufgelöste Karten für ganze Gebiete kommen als Nächstes.
- **Tippen auf Linien und Orte** funktioniert auf beiden Plattformen
  gleich: Liegt ein Trail über einer Stecknadel, gewinnt der Trail.

## Ohne Empfang

*Version 0.15.0, 2026-09-28*

- **Deine Trails auch im Funkloch**: Die App merkt sich beim letzten
  Laden mit Netz das ganze Netz — Trails, Beiträge, Hinweise — auf dem
  Gerät. Startest du sie ohne Empfang, siehst du diesen Stand auf Karte
  und Liste, mit dem Hinweis, von wann er ist. Sobald wieder Netz da ist,
  kommt der aktuelle.
- Ein Fehler des Servers wird weiterhin als Fehler gezeigt, nicht mit dem
  alten Stand überdeckt. Beim Abmelden wird die Kopie gelöscht. Im
  Browser gibt es sie noch nicht.

## Ausgangskorb

*Version 0.14.0, 2026-09-28*

- **Beisteuern ohne Netz**: Importierst du eine GPX-Datei oder änderst
  deinen Beitrag zu einem Trail, während kein Netz da ist, geht nichts
  verloren. Der Auftrag wartet in einem Ausgangskorb auf deinem Gerät und
  wird gesendet, sobald wieder Verbindung besteht — beim nächsten
  Netzwechsel, beim nächsten Start oder wenn du den Hinweis oben auf der
  Karte antippst.
- **Wartende Trails siehst du sofort**: gestrichelt auf der Karte, in
  der Liste unter „Wartet auf Übertragung". So steuerst du dieselbe Datei
  nicht zweimal bei. Lehnt der Server einen Auftrag ab, steht der Grund
  dabei, mit „Erneut versuchen" und „Aus dem Ausgangskorb entfernen".
- Ein Serverfehler ist kein Funkloch: Er wird weiter sofort gemeldet
  statt still gesammelt. Im Browser gibt es den Korb noch nicht.

## Fahrt aufzeichnen

*Version 0.13.0, 2026-09-28*

- **Der Aufnahme-Knopf auf der Karte**: Ein Tipp startet die Fahrt, die
  App zeichnet deinen Weg auf — auch mit dem Telefon in der Tasche oder
  wenn du die App weggewischt hast. Solange sie läuft, steht eine
  Benachrichtigung in der Statusleiste; oben auf der Karte siehst du
  Strecke und Dauer, und die Spur wächst als dunkle Linie mit.
- **Die Fahrt bleibt auf deinem Gerät.** Unter „Meine Fahrten" im Profil
  liegen alle Aufzeichnungen: ansehen, auf der Karte zeigen, löschen.
  Nichts davon geht an den Server und nichts ins Android-Backup. Welche
  Trails du wieder gefahren bist und wo ein neuer liegt, zeigt bald das
  Zerlege-Blatt — bis dahin bleibt die Fahrt, wie sie ist.
- **Nach einem Neustart geht es weiter**: Räumt Android die App zwischendurch
  weg, hat der Dienst weiter aufgezeichnet, und die Karte holt die Fahrt
  beim nächsten Öffnen zurück. Nach zwölf Stunden hört eine vergessene
  Aufnahme von selbst auf.
- Im Browser gibt es die Aufzeichnung nicht: Ein Tab im Hintergrund
  bekommt keine Positionen.

## Wo bin ich?

*Version 0.12.0, 2026-09-28*

- **Deine Position auf der Karte**: Der neue Knopf „Meine Position"
  unten links springt zu dir und zeigt dich als dunklen Punkt mit einem
  Kreis für die Genauigkeit. Beim ersten Tipp fragt die App nach dem
  Standort; vorher nie. Der Standort bleibt auf deinem Telefon.
- **Die Karte dreht sich nicht mehr**: Norden bleibt oben, auch wenn
  beim Zoomen mit zwei Fingern die Hand etwas dreht.

## Auch ausgeschildert

*Version 0.11.0, 2026-09-28*

- **„Auch ausgeschildert als …" im Trail-Blatt**: Liegt ein Trail aus
  deinem Netz auf einem offiziellen Trail, steht das jetzt in seinem
  Blatt — ebenso, wenn er nur ein Stück davon ist oder einen offiziellen
  Trail enthält. Ist der offizielle Trail gesperrt, steht auch das da,
  mit der Angabe, von wem die Sperre kommt. Ein Tipp öffnet das Blatt
  des offiziellen Trails.

## Offizielle Trails

*Version 0.10.0, 2026-09-28*

- **Offiziell ausgewiesene Singletrails auf der Karte**: Violett
  gestrichelt, unter den Trails deines Netzes. Den Anfang macht Tirol mit
  gut 180 freigegebenen Singletrails vom Land. Sie erscheinen ab mittlerer
  Zoomstufe, sobald die Karte eine Region zeigt, für die es Daten gibt.
- **Ein Tipp zeigt, was die Quelle sagt**: Name, Länge, Höhenmeter,
  Schwierigkeit laut Quelle, Beschreibung und ob der Trail freigegeben
  oder gesperrt ist — mit der Angabe, von wem das kommt. Gesperrte Teile
  sind grau.
- **Auch ohne Empfang**: Einmal geladen, merkt sich die App die Region
  und zeigt sie auch im Funkloch.
- **Abschaltbar**: Der Knopf „Ebenen und Orte" unten links (vorher nur
  „Orte") hat dafür einen Schalter.

## Lange Namen beim Import

*Version 0.9.1, 2026-09-28*

- **Kein Fehler mehr bei langen Trail-Namen**: Manche Apps (etwa Locus bei
  Spuren aus Trailforks) schreiben Namen wie „DREI%20EICHEN%20-%20…" in
  die Datei. Die App macht daraus wieder „DREI EICHEN - …" und kürzt, was
  länger als 80 Zeichen ist, statt den Import abzubrechen.
- **Namenlose Trails reparieren**: Ist ein Trail dadurch früher ohne Namen
  angelegt worden, importiere die Datei einfach noch einmal — der Name
  wird übernommen, ohne einen zweiten Trail anzulegen.

## Ganzer Bestand auf einmal

*Version 0.9.0, 2026-09-28*

- **Bis zu 500 Trails am Tag beisteuern** statt 50: Dein ganzes
  GPX-Archiv geht jetzt an einem Abend durch, statt sich über zehn Tage
  zu ziehen.

## Hinweise für Buddys

*Version 0.8.0, 2026-09-28*

- **„Baum liegt quer nach der zweiten Kehre"**: Zu jedem Trail, den du
  siehst, kannst du im Trail-Blatt einen Hinweis schreiben. Deine Buddys,
  die den Trail auch sehen, finden ihn dort mit Datum.
- **Neues fällt auf**: Hat ein Buddy in den letzten sieben Tagen einen
  Hinweis geschrieben, leuchtet der Trail auf der Karte gelb umrandet, und
  in der Liste steht „neuer Hinweis" — bis du das Trail-Blatt geöffnet
  hast.
- **Erledigt?** Ist der Baum weggeräumt, kann jeder, der den Hinweis
  sieht, ihn entfernen. Nach drei Monaten verschwinden alte Hinweise von
  selbst; der jüngste bleibt stehen, bis ihn jemand entfernt.
- **Status mit Grund**: Wer den Zustand eines Trails ändert (etwa auf
  gesperrt), kann gleich dazuschreiben, warum.

## Orte: eigene Symbole und Detailfilter

*Version 0.7.0, 2026-09-28*

- **Jede Art an ihrem Symbol erkennbar**: Biergärten zeigen immer den
  Bierkrug — auch Gasthäuser mit Biergarten, die bisher das Besteck
  hatten. Cafés zeigen ein Stück Kuchen, Quellen ein Wasserglas.
- **Detailfilter**: Unter jeder eingeschalteten Gruppe stehen ihre Arten
  zum einzelnen Abwählen — zum Beispiel Einkehr ohne Kneipen, oder
  Wasser nur mit Trinkwasser.

## Höhen für ältere Trails nachtragen

*Version 0.6.0, 2026-09-28*

- **Einfach dieselbe Datei noch einmal importieren**: Trails, die du vor
  Version 0.3.0 beigesteuert hast, haben noch keine Höhenmeter. Wählst du
  die Original-GPX (oder den ganzen Zip) noch einmal, erkennt die App sie
  und trägt die Höhen nach — ohne doppelten Trail und ohne dein
  Tageslimit zu belasten.
- **Nichts doppelt**: Was du schon beigesteuert hast, steht im Import als
  „schon beigesteuert" und wird nicht noch einmal hochgeladen.

## Orte auf der Karte

*Version 0.5.0, 2026-09-28*

- **Trinkwasser, Einkehr, Rad-Service**: Die Karte zeigt ab Zoomstufe 12
  Orte aus OpenStreetMap als Stecknadeln — Café, Biergarten, Hütte,
  Brunnen und Quelle, Reparaturstation, Radladen, E-Bike-Ladestation,
  Unterstand, Toilette, Aussichtspunkt und Parkplatz.
- **Du wählst, was du siehst**: Der Knopf unten links schaltet die vier
  Gruppen einzeln an und aus. Am Anfang ist nur Wasser an.
- **Ein Tipp auf eine Nadel** zeigt Name, Öffnungszeiten und bei Quellen,
  ob das Wasser als trinkbar eingetragen ist.

## Höhenmeter an echten Fahrten abgestimmt

*Version 0.4.1, 2026-09-27*

- **Genauere Höhenmeter**: Ab wann ein Auf und Ab zählt, ist jetzt an
  Hunderten echten Fahrten gemessen statt geschätzt. Auf reinen Abfahrten
  erscheint kein erfundener Anstieg mehr, auf Touren geht weniger echter
  Anstieg verloren.

## Schwierigkeit nach der Singletrail-Skala

*Version 0.4.0, 2026-09-27*

- **S0 bis S5, von euch eingeschätzt**: Das Trail-Blatt zeigt den Wert
  deiner Buddys, die Spanne und wie viele eingeschätzt haben — zum
  Beispiel „S2 · S1–S3 · 4 Einschätzungen". Ein Tipp darauf zeigt, wer
  was gesagt hat.
- **Deine Einschätzung mit einem Tipp** direkt im Blatt, bei Trails, die
  du selbst gefahren bist. Noch ein Tipp nimmt sie zurück.
- **Was heißt S3?** Das „?" neben der Auswahl erklärt jede Stufe in einem
  Satz, auch im Dialog „Mein Beitrag".

## Höhenmeter und Höhenprofil

*Version 0.3.0, 2026-09-27*

- **Jeder Trail zeigt seine Höhenmeter**: „↓ 420 Hm · ↑ 35 Hm" und das
  mittlere Gefälle, im Trail-Blatt und kurz in der Liste.
- **Ein Höhenprofil** im Trail-Blatt, immer in Fahrtrichtung des Trails,
  mit dem steilsten Stück darunter.
- Kleine Wellen aus dem GPS-Rauschen zählen nicht mit — auf einer Abfahrt
  steht deshalb nicht plötzlich „40 m bergauf".
- **Trails, die du vor dieser Version importiert hast, haben noch keine
  Höhen** — die App hat sie damals nicht mitgeschickt. Das Blatt sagt es.
  Ein Weg, sie nachzutragen, kommt.

## Idee oder Fehler melden

*Version 0.2.0 und 0.2.1, 2026-09-27*

- **Die Glühbirne auf der Karte** (und im Profil unter „Idee oder Fehler
  melden"): Wünsche und Fehler gehen direkt an den Entwickler.
- Die Meldung wird ein **öffentlicher** Eintrag im GitHub-Projekt — mit
  deinem Text, aber ohne deinen Namen. Bitte keine Trailnamen oder Orte
  hineinschreiben; der Dialog erinnert daran.

## GPX-Import, der wirklich Dateien findet

*Version 0.1.1, 2026-09-27*

- **Auf Android ließ sich keine Datei auswählen** — GPX- und Zip-Dateien
  waren im Auswahldialog ausgegraut. Jetzt kann man jede Datei wählen;
  was kein GPX ist, sagt die App mit Namen.
- **Zip-Archive werden ausgepackt**, zum Beispiel ein Track-Export aus
  Locus: Jede GPX-Datei darin wird zu einer Spur mit eigenem Namen.
- **Mehr als 50 Trails auf einmal?** Der Server nimmt am Tag höchstens 50
  an. Der Import hält dann an, statt jeden weiteren als Fehler zu melden,
  und die übrigen bleiben für den nächsten Tag angehakt.

## Der Anfang

*Version 0.1.0, 2026-09-27*

Das Grundgerüst: Anmelden, Buddys finden, Trails aus GPX-Dateien
importieren und auf der Karte sehen. Noch nichts für den Alltag, aber der
Boden, auf dem alles Weitere steht.
