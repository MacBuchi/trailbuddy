# TrailBuddy auf der Garmin-Uhr — Konzept

*Angelegt am 2026-11-03. Anlass: Der Betreiber will das Handy nicht mehr
ans Rad kleben und unterwegs nicht herauskramen; die Uhr am Lenker oder
am Handgelenk soll die Navigation zeigen. Erstes Gerät ist die fēnix 5
des Betreibers. Dieses Dokument kommt vor dem ersten Code.*

## 0. Entscheidungen des Betreibers (2026-11-03)

1. **Die Uhr ist Anzeige, nicht Sensor.** Die fēnix 5 hat keinen
   Kreisel, nur Beschleunigung, Magnetfeld und Barometer; ohne Kreisel
   gibt es im Flug keine Lage und beim Bremsen keine verlässliche
   (`docs/recherche-sensorfusion.md`, Abschnitt 2). Messen bleibt Sache
   des Handys, später eines eigenen Lenkergeräts.
2. **A5 bekommt eine Ausnahme wie bei #398.** Die Uhr-App läuft über
   Connect IQ: Die Garmin-Connect-App auf dem Handy reicht die
   Nachrichten an die Uhr weiter. Das ist keine Kopplung — TrailBuddy
   hat kein Garmin-Konto und schickt Garmin nichts über Trails, Fahrten
   oder Buddys; die Uhr-App zeichnet keine Garmin-Aktivität auf (die
   ginge sonst an Garmin Connect, Abschnitt 4).
3. **A12 bekommt einen Satz für die Uhr: Vibrieren beim Abkommen.** Die
   Uhr zeigt wie der Navigationsmodus der App (Route, Position, Abstand)
   und vibriert zusätzlich, wenn man die Route verlässt. Das ist eine
   Warnung, kein Abbiegehinweis: keine Meter bis zum Abzweig, kein
   Vibrieren vor einer Kreuzung, kein Ton. Die App selbst bleibt still.
4. **Der Code liegt in `garmin/` in diesem Repo.** Dann ändern sich
   Protokoll, Android-Brücke und Uhr-App im selben PR.

## 1. Was die Uhr zeigt

Eine Ansicht, angelehnt an die Folgeansicht der App
(`docs/konzept-routing.md` 9.2 und 9.9, Design 13), geschnitten für
240 × 240 Pixel MIP (64 Farben, in der Sonne gut lesbar, kein Touch).
Entwurf im Designer am 2026-11-04 (Betreiber: „nutze den Designer, um
das Garmin-App-Design zu optimieren"): helle Karte wie in der App, darunter eine
dunkle Infofläche, „Was kommt als Nächstes?" statt „Wie weit noch?".

- **Die Route als Band**, gedreht in Fahrtrichtung: in Bewegung nach
  dem GPS-Kurs, im Stand nach dem Kompass der Uhr — die fēnix 5 hat
  einen Magnetfeldsensor, und gerade an einer Kreuzung im Stand kennt
  das GPS die Richtung nicht. Die eigene Position steht im unteren Teil
  der Karte (y 128 von 240), damit mehr voraus zu sehen ist; der
  gefahrene Teil ist eine dünne Linie in Moos (Design 2, „B+"). Am
  Rand ein „N" für Norden.
- **Die Trails der Route in ihrer Farbe** (S-Grad, Design 2), am
  Trailkopf voraus ihr Schild als Form (○ ● ■ ◆, Design 6): auf MIP
  die nächste der 64 Farben zu `AppColors.mapGrades`; geprüft am Gerät,
  nicht nur im Simulator.
- **Abzweigungen an Kreuzungen** (Betreiber, 2026-11-04: „muss nicht
  der ganze Weg sein"): je Kreuzung der Route ein Stummel des
  abgehenden Wegs, 40 m, dünn in Grau unter dem Band. Man sieht, DASS
  man abbiegen kann und wohin die Route geht — ohne Kartenbild und ohne
  Abbiegehinweis (Entscheidung 3).
- **Unten die Infofläche** (schwarz, ab y 168 — darunter wird der Kreis
  zu schmal für zwei Zeilen): vor einem Trail dessen Schild und Name,
  darunter Weg und Anstieg bis zum Trailkopf; auf dem Trail Schild,
  Name und der Rest (den Anteil zeigt der Ring); ohne
  Trail voraus „BIS ZUM ZIEL" mit Rest-km und Rest-hm. Abseits wird die
  Fläche zur Warnfarbe mit dem Abstand, dazu ein gestrichelter Strich
  und ein Pfeil zum Punkt der Linie 50 m voraus (wie 9.3).
- **Der Ring außen herum** (Entwurf „Ring und Seiten" im Designer,
  2026-11-04; Betreiber: „den Balken (wie weit, wann kommt der nächste
  Trail) ringförmig außen herum", Variante A): Ein Umlauf ist die
  ganze Route, im Uhrzeigersinn, Start und Ziel oben an einer Lücke.
  Gefahren Lime (abseits in Warnfarbe), voraus Grau, die Trails als
  Blöcke in ihrer S-Farbe (dunkler Satz, der Ring liegt in einem
  schwarzen Rand), eine weiße Marke für die eigene Position. „Wie
  weit" ist die Füllung, „wann kommt der nächste Trail" der Abstand
  der Marke zum nächsten Block. Der Ring steht auf jeder Seite.
- **Drei Seiten, fest, ohne Einstellungen** (Betreiber: „im
  Zweifelsfall mehr als eine Seite, aber nicht zu kompliziert"):
  Karte; „Fahrt" (Tempo groß, Fahrzeit, Strecke, bergauf, Puls);
  „Berg" (Steigung über die letzten 30 m aus dem Barometer, Höhe,
  bergauf bis zum nächsten Trailkopf und bis zum Ziel, Uhrzeit; Akku
  und Speicher für die Messungen nur noch im Vorführmodus — auf der Uhr
  stand die Zeile mitten in der Seite, 2026-11-05). Der Puls vom Handgelenk
  dezent in Grau (Betreiber: „Ja, aber dezent"). Alle Werte misst die
  Uhr selbst; sie stehen nur im Speicher der laufenden App, nichts
  wird gespeichert oder verschickt (A3, Entscheidung 1: Anzeige).
  Fahrzeit und Strecke zählen ab 1 m/s, bergauf mit 3 m Hysterese.
- **„Angekommen"** wie in der App (unter 30 m vom Ende bzw. letzter
  Abschnitt einer Runde), mit einer Zusammenfassung (Betreiber: „Ja"):
  Strecke, Fahrzeit, bergauf und die befahrenen Trails als Schilder.
- **Vor dem ersten GPS-Fix die Übersicht** (Feldbefund 2026-11-05,
  bis dahin nur „Warte auf GPS"): die ganze Route genordet und
  eingepasst, Start als Punkt, Trailköpfe als Schilder, unten „Warte auf
  GPS" mit Länge und Höhenmetern der Route. Mit dem ersten Fix kommt die
  gedrehte Karte.
- **Die Position des Handys als erster Fix** (Betreiber, 2026-11-05):
  Bis die Uhr selbst GPS hat, nimmt sie die Position, die das Handy nach
  dem „gespeichert" schickt — Karte, „Zum Trail", „Zum Ziel" und Anstieg
  stehen damit sofort statt Strichen. Der Pfeil ist dann hohl, darüber
  „HANDY-GPS". Kein Vibrieren beim Abkommen (die Position kann ein paar
  Sekunden alt sein), keine Zahlen der Fahrt; mit dem ersten eigenen Fix
  beginnt die Verfolgung neu, und nur noch das eigene GPS zählt.
- **Kurz vibrieren bei einer neuen Route** (Betreiber, 2026-11-05):
  ein kurzer, schwacher Stoß, sobald eine neue Route vom Handy ganz
  gespeichert ist — dieselbe noch einmal bleibt still. Er ist deutlich
  kürzer als das Abkommen, damit man beides nicht verwechselt.
- **Vibrieren beim Abkommen** (Entscheidung 3): einmal, wenn „abseits"
  beginnt — dieselbe Regel wie 9.3 (mehr als 30 m neben der Linie, zwei
  Fixe in Folge). Kein zweites Vibrieren, bis man wieder auf der Linie
  war; nichts beim Zurückkommen, nichts vor Abzweigen.
- **Tasten**: START blättert Karte → Fahrt → Berg; hoch/runter zoomt
  auf der Karte (drei Stufen: 1, 1,5 und 4 m je Pixel,
  Start auf 1,5 — gut 180 m voraus) und blättert auf
  den Zahlenseiten; beim Abkommen kommt die Karte von selbst nach vorn.
  ZURÜCK beendet nach Rückfrage. Tippziele gibt es nicht; A13 heißt hier:
  große Schrift, kräftige Linien.

Kein Kartenbild: Die fēnix 5 hat keine Karten, und Kacheln passen nicht
in den Speicher einer App (Abschnitt 7). Gezeigt werden nur Route,
Trails der Route und die Stummel der Abzweigungen.

## 2. Was auf die Uhr geht

Dasselbe, was der Navigationsmodus navigiert (9.1): ein Planer-Ergebnis,
eine geplante oder eine eigene Fahrt. Beim Start der Navigation in der
App steht, wenn eine Uhr verbunden ist, ein Schalter „Auf der Uhr
zeigen" (Vorgabe an). Dann schickt die App die Route einmal; die Uhr
legt sie in ihren eigenen Speicher und navigiert **ab da selbst** — mit
eigenem GPS, ohne Handy, ohne Netz (A8). Das Handy darf in der Tasche
bleiben, schlafen oder die Verbindung verlieren.

Was die Nachricht trägt:

- die Linie, vereinfacht (Douglas-Peucker, Startwert 5 m) und als
  Ganzzahlen in Schritten von 1e-5° gegen den Vorgänger; Höhen in
  Metern, falls vorhanden;
- die Abschnitte: von Punkt, bis Punkt, S-Grad, Name — nur die Trails
  DIESER Route, die der Nutzer in der App ohnehin sieht (A1, A2);
- die Abzweigungen: je Kreuzung der Route der Punkt und das Ende eines
  40-m-Stummels des abgehenden Wegs, aus dem Wegegraphen des Planers
  (OSM-Wege und eigene Trails, keine fremden — A1, A2);
- Kopf: Protokollversion, Länge, Höhenmeter, eine Kennung der Route.

Die Form steht in `garmin/source/PhoneRoute.mc` und `NavRoute.mc`
(Protokoll 2, Schlüssel `v`, `id`, `np`, `o`, `e0`, `sec`, `pts`, `ele`,
`br`); die Testroute liest sie aus der Ressource, `tool/garmin_route.py`
schreibt sie.

**Protokoll 2 — gepackt** (#449, 2026-11-05, Betreiber: „sparsam mit
Speicher und Datenstrom, robust mit Fehlerbehandlung"). Jede Zahl kostet
auf dem Draht und im Speicher der Uhr ~5 Byte, gleich wie groß. Deshalb
trägt eine Zahl zwei 16-Bit-Werte: je Punkt `(dLat << 16) | dLon` gegen
den Vorgänger (der erste gegen `o`), die Höhendifferenzen zu zweit, je
Stummel `[Punkt, gepackt(dLat, dLon)]` — halb so viele Zahlen wie mit
Protokoll 1. Ein Schritt über 32 767 × 1e-5° (gut 240 m in der Länge bei
47°) bekommt beim Handy Zwischenpunkte. Der Kopf (`v`, `np` = Anzahl der
Punkte, `o`, `e0`, `sec`) steht im ersten Stück und zählt in dessen
Grenze mit. Erster Test am Gerät (fēnix 5 über Garmin Connect,
2026-11-05): eine Route „Zum Trailkopf" in 2 Stücken, beide bestätigt,
die Uhr zeigte sie. Eine Uhr-App mit Protokoll 1 nimmt Protokoll 2 nicht
und umgekehrt — beide Seiten kommen aus demselben Stand. **Das Handy
prüft die Fassung** (seit 0.154.0): Weicht `v` im „hallo" ab (oder
fehlt), geht nichts hin, und die Leiste nennt die veraltete Seite —
„Die Uhr-App ist veraltet …" bei einer kleineren, „TrailBuddy auf dem
Handy ist älter …" bei einer größeren Fassung. Erst ein „hallo" mit der
passenden Fassung gibt das Senden wieder frei. Ging das „hallo" verloren,
antwortet die Uhr auf das erste Stück einer anderen Fassung mit
`{t: "x", id, c: "ver", v}` statt `bad`; das Handy behandelt es gleich.

**Die Uhr hält nie die ganze Route roh** (2026-11-05): Sie legt jedes
Stück geprüft (Typen, Größen, Trails innerhalb der Linie) als `[pts, ele,
br]` in `Application.Storage` und dekodiert danach Stück für Stück in
Felder, die von Anfang an ihre volle Länge haben. Vorher lagen rohe Daten
und Felder kurz zusammen (Messung 8.1: ab 3000 Punkten „Out of Memory"
beim Laden). Passt ein Stück nicht, ist die Route „unbrauchbar" und die
Uhr nimmt die Testroute — statt abzustürzen; eine Route aus Protokoll 1
im Speicher räumt sie weg.

**Fehler sagt die Uhr dem Handy** (`{t: "x", id, c}`): `mem` (zu wenig
Arbeitsspeicher zum Ablegen), `store` (der Speicher nahm es nicht),
`bad` (falsche Form), `crash` (siehe unten). Bei `mem`, `store` und
`crash` rechnet das Handy die Route EINMAL mit halb so vielen Punkten und
schickt sie; scheitert auch das, sagt die Leiste „Die Uhr konnte die
Route nicht laden, auch nicht vereinfacht". **Kein Absturz zweimal**:
Solange eine Route neu ist (sie kommt an, oder sie lädt und lief noch
keine Minute), merkt sich die Uhr ihre Kennung; endet die App so zweimal
hintereinander nicht sauber, verwirft sie die Route, nimmt sie nicht
mehr an und nennt sie im „hallo" (`bad`) — das Handy schickt dann die
kleinere. **Bricht die Übertragung mittendrin ab**
(`FAILURE_DURING_TRANSFER`, `FAILURE_TIMEOUT`), gehen nach 2 s die
übrigen Stücke noch einmal, höchstens zweimal — die Uhr hat die
angekommenen schon abgelegt. Die Uhr sendet nur, wenn ein Handy
verbunden ist. **Höchstens 2000 Punkte**
(Messung 8.1): darüber vereinfacht die App stärker, bis es passt.

**Die Position des Handys** (Betreiber, 2026-11-05): Nach dem
„gespeichert" schickt das Handy seine Position (`{t: "p", la, lo}` in
1e-5°), gleich und dann alle 10 s (`kWatchPositionEvery`), bis die Uhr
`{t: "g"}` meldet („ich habe eigenes GPS", ohne Koordinate), die
Navigation endet oder 3 min um sind (`kWatchPositionFor`) — die Uhr
navigiert allein (A8), das ist nur ein Vorsprung beim Start. Ein neues
„hallo" (die Uhr-App startete neu) beginnt den Takt wieder. Die Uhr hält
die Position nur im Speicher (A3).

Die Uhr schickt zurück: „angekommen und gespeichert" mit der Kennung,
„hallo" mit der Kennung der Route, die sie hat, und einmal „habe GPS" —
sonst nichts. Keine Position, keine Fahrt (A3).

**Gebaut in G2 (2026-11-04)**: `lib/features/garmin/watch_route.dart`
kodiert und schneidet in **Stücke** (`t: "r"`, `id`, Laufnummer `p`, Anzahl
`n`, im ersten `v` und `sec`; je Stück höchstens 800 Zahlen, rund 4 KB —
Startwert bis Messung 8.2). Die Kennung ist ein FNV-Hash der Punkte:
dieselbe Route noch einmal ist dieselbe. Die Höhen kommen aus dem
Geländemodell entlang der Linie (höchstens 5 s Warten, sonst ohne).
**Die Wendepunkte der Höhe bleiben beim Vereinfachen stehen**
(`climbTurnIndices`, 2026-11-05): Douglas-Peucker sieht nur die Lage,
und auf einem geraden Weg über eine Kuppe fiel der Gipfel weg — die
fēnix 5 zeigte „Zum Ziel ▲198 m" bei 461 hm auf dem Handy. Behalten
wird je bestätigter Gipfel und Senke der 10-m-Hysterese der nächste
Punkt der Linie; so zählt die Uhr aus ihren Punkten dieselben
Höhenmeter wie das Handy aus dem Profil. Die
Uhr legt jedes Stück sofort in `Application.Storage` (zwei Fächer, die
neue Route gilt erst mit dem letzten Stück, `garmin/source/PhoneRoute.mc`),
lädt beim Start die gespeicherte statt der Testroute und antwortet
`{t: "ok", id}`. Uphill-Trails gehen ohne Grad (-1), ab S3 als 3.

**Die Abzweigungen (`br`)**, eigener PR nach G2 (Betreiber,
2026-11-04): Beim Start der Navigation liegt kein Wegegraph im
Speicher, und eine Fahrt aus „Meine Fahrten" hatte nie einen. Deshalb
liest die App beim Senden die Kacheln im Korridor von 100 m um die Linie
(`tilesAlong`, wie die Kalibrierung; Bereiche, vorgebackene Stücke, mit
Empfang und Schalter vom Host), baut den Graphen in einem eigenen
Rechen-Isolate samt der sichtbaren Trails und rechnet dort die Stummel
(`lib/features/garmin/watch_branches.dart`). Eine Kreuzung der Route ist
ein Knoten mit drei und mehr Kanten, höchstens 8 m neben der Linie, an
dem mindestens eine Kante der Route folgt (15 m weiter höchstens 6 m
daneben); jede andere Kante ab 10 m Länge gibt einen Stummel von 40 m
(oder bis zu ihrem Ende). Höchstens 300 Stummel, darüber gleichmäßig
ausgedünnt. Höhen und Stummel laufen zugleich; auf die Stummel wartet das
Senden höchstens 15 s, danach geht die Route ohne. **Angestoßen werden
beide, sobald das Startblatt die Uhr gefunden hat** (`WatchSync.prepare`,
seit 0.152.2), nicht erst mit „Los": Wer liest, wartet nicht. „Los"
nimmt das Vorbereitete, wenn die Linie Punkt für Punkt dieselbe ist, und
wartet dann nur noch den Rest (die 5 bzw. 15 s zählen ab „Los"). Zu ohne
„Los" oder mit dem Schalter aus verwirft es; jede spätere Route der
Navigation rechnet selbst. Die Kreuzung bleibt
beim Vereinfachen als Punkt der Linie stehen, das Ende geht als Versatz
gegen den Knoten (bei einer GPS-Fahrt liegt der Linienpunkt ein paar
Meter daneben). Jeder Stummel fährt im Stück seines Punkts mit und zählt
in dessen 800 Zahlen; die Uhr hängt `br` wie `pts` aneinander.
**Das Handy stößt an, die Uhr meldet sich** (Betreiber, 2026-11-04,
nach dem ersten Test mit der fēnix 5 über Garmin Connect auf einem
Pixel 7 Pro). Befund: Garmin Connect meldet `SUCCESS` auch, wenn die
Uhr-App zu ist — die Uhr verwirft die Nachricht. Eine Watch-App empfängt
nur, solange sie läuft; nur das `{t: "ok", id}` der Uhr zählt als
angekommen (beantwortet 8.2). Deshalb:

- **Beim Start der Navigation** mit „Auf der Uhr zeigen" ruft das Handy
  `openApplication` (`GarminBridge.kt`, Methode `open`), zugleich mit
  dem Rechnen von Höhen und Stummeln. Läuft die Uhr-App, gehen die
  Stücke; sonst fragt die Uhr „TrailBuddy öffnen?", und die Leiste sagt
  „Auf der Uhr TrailBuddy öffnen". Fehlt die App, sagt sie das, und
  nichts geht hin.
- **Die Uhr-App meldet sich beim Start** mit `{t: "hi", v, id}` — `id`
  ist die gespeicherte Route, fehlt ohne eine vom Handy. Weicht sie von
  der laufenden Navigation ab, schickt das Handy die aktuelle; stimmt
  sie, gilt sie als gespeichert. Ein „hallo", das kommt, während das
  Handy noch rechnet, wartet auf die fertige Route.
- **Das Handy antwortet sofort auf das „hallo"** (Betreiber,
  2026-11-06: „Wen juckt die alte Route?"): `{t: "n", id, np}` — eine
  neue Route kommt, in `np` Stücken (0: wird noch gerechnet), auch vor
  jeder Übertragung —, oder `{t: "k", id}` — die gespeicherte ist
  aktuell. Ist beim Start ein Handy verbunden, zeigt die Uhr bis dahin
  das Logo als Lader statt der alten Route, nach `n` mit „Route kommt ·
  1/2". Ohne Antwort in 8 s oder ohne neues Stück in 45 s zeigt sie die
  gespeicherte, wie ohne Handy. Erst waren es 3 s; gemessen brauchen
  „hallo" und Antwort über Garmin Connect zusammen 5–7 s (eine kleine
  Nachricht 3,5 s je Richtung, 2026-11-06), also 8 s (Betreiber). Eine
  laufende Navigation auf der Uhr übergeht `n`: Sie bleibt, bis die neue
  Route ganz da ist. Ein „hallo", während dieselbe Route gerade
  hinübergeht (etwa auf das Nachfassen `q`), schickt sie nicht noch
  einmal. Beides kam ohne neue Fassung dazu — eine ältere Uhr übergeht
  unbekannte Arten, eine neue Uhr mit älterer App wartet nur die 8 s.
- **Die Navigation endet auf beiden Geräten** (`{t: "e", id}`,
  Betreiber 2026-11-06). Endet sie auf dem Handy, zeigt die Uhr kurz
  „Navigation beendet" und schließt sich — wenn sie eine Route dieser
  Navigation zeigt. Beendet man sie auf der Uhr („Navigation
  beenden?"), geht erst `e` ans Handy, die App schließt sich, sobald
  Garmin Connect die Nachricht abnahm (höchstens 5 s); das Handy beendet
  seine Navigation, wenn die Kennung zu einer Route dieses Folgens
  gehört. **Die Aufzeichnung läuft weiter** — gespeichert wird die
  Fahrt wie bisher auf dem Handy von Hand; die Uhr speichert nichts
  außer der Route (A3), es geht also nichts verloren. Ohne Verbindung
  beendet jede Seite nur sich selbst.
- **Neu verbunden** meldet Garmin Connect (`device`, `CONNECTED`), dann
  fragt das Handy `{t: "q"}`, und eine laufende Uhr-App antwortet mit
  „hallo". Kein Abfragen im Takt — nur ein kurzes Nachfassen: Wartet das
  Handy auf die Uhr (sie fragt „öffnen?", oder ein „gespeichert" blieb
  aus), schickt es nach 5, 15 und 45 s noch einmal `q`
  (`kWatchNudges`), dann wartet es still. Ein verlorenes „hallo" holte
  sonst erst das nächste Wiederverbinden nach.
- **Eine Übertragung nach der anderen.** Kommt eine neue Route, während
  die alte noch hinübergeht, geht sie danach (`WatchSync._push`); vorher
  fiel sie still weg. Auch `GarminBridge.kt` stellt jedes `send` hinten
  an: Zwei Folgen zugleich mischten ihre Stücke, und die Uhr finge bei
  jeder neuen Kennung ihr Fach von vorn an.
- **Garmin Connect neu gestartet** (`onSdkShutDown`: Update, vom System
  beendet): `open` und `send` starten das SDK wieder und lauschen erneut
  auf die Uhr — vorher kam bis zum nächsten Startblatt nichts mehr an.
  Scheitert der Start, bekommen alle Wartenden den Fehler, nicht nur der
  erste.
- **Das Startblatt sagt „Uhr wird gesucht …"**, solange die erste Frage
  nach der Uhr läuft (das SDK startet, Garmin Connect antwortet bei
  Entwickler-Apps erst nach 3 s) — sonst tauchte der Schalter erst auf,
  wenn man schon „Los" getippt hatte.
- **Die Uhr folgt der Navigation, bis sie endet**: Jede neue Linie der
  Navigation (eine neue Route, auch ohne neues Startblatt) geht von
  selbst hinterher, mit erneutem Anstoßen; die Uhr wechselt die Route
  im Lauf. Mit dem Schalter aus oder nach dem Ende antwortet das Handy
  auf kein „hallo" mehr. „Zurück zur Route" ist keine neue Linie: Die
  Uhr zeigt dafür ihren eigenen Pfeil zurück.
- **„Route auf der Uhr" erst nach dem `ok`**. Kommt es 15 s nach dem
  Senden nicht (`kWatchAckWait`), sagt die Leiste „Die Uhr hat nicht
  geantwortet"; öffnet man die Uhr-App danach, holt ihr „hallo" die
  Route. Die Bestwerte gehen erst nach dem `ok` (vorher verwürfe sie
  eine geschlossene App) und nach jedem passenden „hallo" noch einmal.
- **Kein Anstoßen beim Start der App** (Betreiber, 2026-11-04): Die
  Frage auf der Uhr gehört zum Start einer Fahrt. Eine nach einem
  Neustart wiederaufgenommene Navigation folgt der Uhr nicht.

**Bestwerte (Idee des Betreibers, in G2 gebaut)**: `{t: "b", jn, ja, wn,
wl, wa, sn}` — Sprünge und längste Flugzeit in ms, Wheelies, längster in
m, größter Winkel in Grad, Stoppies; aus `AirtimeLog.kept`, nur plausible
Sprünge. Die App schickt nach dem Senden der Route jeden neuen Stand,
solange die Fahrt läuft; die Uhr zeigt sie auf einer vierten Seite
„Sprünge" und in der Zusammenfassung. Die Erkennung meldet nur an die
offene App (`airtimeLiveProvider`); im Hintergrund kommt nichts nach.

## 3. Der Weg vom Handy zur Uhr

- **Android**: das Connect-IQ-Companion-SDK von Garmin
  (`com.garmin.connectiq:ciq-companion-app-sdk:2.4.0`, Maven Central),
  eingebunden als kleine native Brücke (`GarminBridge.kt`, Kanal
  `de.mcbuchi.trailbuddy/garmin`: `status`, `send`, zurück `message`).
  Voraussetzung ist die Garmin-Connect-App, mit der die Uhr gekoppelt
  ist. Fehlt sie, ist keine Uhr verbunden oder meldet Garmin Connect
  unsere App als nicht installiert, erscheint der Schalter nicht; „weiß
  nicht" (eine per USB geladene App meldet Garmin Connect nicht immer)
  zeigt ihn. Das SDK startet erst, wenn das Startblatt der Navigation
  fragt. Gegen den Simulator: Dev-App mit
  `--dart-define=GARMIN_TETHERED=true` und `adb forward tcp:7381 tcp:7381`.
  Erst das Startblatt öffnen (das SDK lauscht), dann im Simulator „adb
  Connection → Start", dann das Blatt neu öffnen — sonst fehlt der
  Schalter. Gesendet wird auf einem eigenen Thread: Im Simulator-Modus
  schläft `sendMessage` 2–3 s und schreibt auf einen Socket, auf dem
  UI-Thread warf Android `NetworkOnMainThreadException`. Jedes Stück
  wartet höchstens 20 s auf die Bestätigung, dann `FAILURE_TIMEOUT`.
  Logcat-Marke `TB-GARMIN` (Ergebnis jedes Sendens).
  **R8**: `android/app/proguard-rules.pro` hält das ganze SDK
  (`com.garmin.**`). Garmin Connect schickt `IQDevice`/`IQApp` als
  Parcelable zurück, Android packt sie über den Klassennamen aus; ohne
  die Regel stürzte jeder Release-Build beim ersten `status` ab (0.150.0,
  gesehen am Pixel 7 Pro mit fēnix 5). Der Simulator-Modus zeigt das
  nicht — eine Abnahme braucht Garmin Connect und eine echte Uhr.
- **Web**: keine Uhr. Wie das Aufzeichnen bleibt das Android (A9).
- **Nachrichten klein halten.** Wie groß eine Nachricht werden darf und
  wie lange die Übertragung dauert, ist zu messen (Abschnitt 8);
  notfalls geht die Route in Stücken mit Laufnummer.
- **Ohne eigene App, per Datei**: Die App kann die Route heute schon als
  GPX exportieren. Über USB in `GARMIN/NEWFILES/` macht die Uhr daraus
  einen eigenen Kurs und navigiert mit Garmins Navigation. Das bleibt
  der Weg für Uhren ohne unsere App und für alle, die Garmin Connect
  nicht wollen; die Kurzanleitung nennt ihn, wenn die Uhr-App kommt.
  Eine Connect-IQ-App selbst kann keine Dateien vom Laufwerk lesen —
  für sie geht es nur über Connect IQ.

## 4. Was die Uhr bewusst nicht tut

- **Keine Garmin-Aktivität** (`ActivityRecording`): Sie ginge beim
  nächsten Abgleich an Garmin Connect, und eine Fahrt beginnt an der
  Haustür (A3, A5). Aufgezeichnet wird wie bisher auf dem Handy.
- **Kein Netz von der Uhr aus** (`makeWebRequest`): kein neuer Host
  (A6), keine Daten an uns oder Dritte.
- **Keine Sensor-Rohdaten**, keine Airtime, keine Sprünge
  (Entscheidung 1).
- **Keine Buddy-Daten über die Route hinaus**, keine Meldungen, keine
  Hinweise — das bleibt in der App.
- **Keine Abbiegehinweise** (Entscheidung 3, A12).

## 5. Verteilung

1. **Erst nur der Betreiber**: Die Uhr-App wird lokal gebaut und per
   USB in `GARMIN/APPS/` kopiert. Der Entwicklerschlüssel liegt beim
   Betreiber, nie im Repo (A7).
2. **Dann der Connect-IQ-Store** — eigene Entscheidung des Betreibers,
   wenn die Uhr-App am Gerät abgenommen ist: Entwicklerkonto, App-ID,
   Prüfung durch Garmin. Mit der Android-Brücke kommen in denselben PR
   der Satz zur Garmin-Connect-App in `web/datenschutz.html` und
   `web/privacy.html` und die Paket-Sichtbarkeit in `docs/play-console.md`
   (A6).

## 6. Code und Build

- `garmin/`: `manifest.xml`, `monkey.jungle`, `source/`, `resources/`
  mit Texten auf Deutsch und Englisch (A14), Geräte in der
  Produktliste des Manifests — zuerst `fenix5`, weitere Uhren erst nach
  einem Test im Simulator.
- **Bauen** lokal mit dem Connect-IQ-SDK (`monkeyc`), dazu ein Skript
  `tool/garmin_build.sh`. Ob CI die Uhr-App mitbauen kann, hängt daran,
  ob sich das SDK ohne Garmin-Anmeldung laden lässt — offen, bis es
  probiert ist.
- **Version Guard**: Die Uhr-App ist nicht im APK; `garmin/` wird wie
  `tool/` ausgenommen. Die Android-Brücke ist es nicht, sie bumpt.
- **Tests**: Die Protokoll-Kodierung ist eine pure Dart-Funktion mit
  Tests; die Uhr-Seite hat Monkey-C-Unit-Tests (`(:test)`,
  `tool/garmin_build.sh --test` im Simulator) für Dekodierung,
  Abseits-Regel, Vibrieren, Ankunft und Suche.
- **Vorführmodus** `tool/garmin_build.sh --demo`: im Simulator ohne
  GPS reihum Anfahrt, Trail, abseits, angekommen, mit dem Speicher in
  der Konsole. Im normalen Build schließt `monkey.jungle` ihn aus.

## 7. Grenzen der fēnix 5

Aus der Gerätedatei des SDK 9.3.0 und der Uhr selbst:

- Connect IQ 3.1 (Uhr: VM 3.1.9).
- Speicher je App-Art: Uhr-App 128 KB, Widget 64 KB, Datenfeld 32 KB.
  Deshalb eine **Uhr-App**: Nur sie hat genug Platz, eigenes GPS und
  Nachrichten vom Handy.
- Display 240 × 240, MIP, rund, 64 Farben, keine Glättung. Schriften
  Roboto Condensed (26–37 px) und Chronos für Zahlen (bis 58 px).
- **Watchdog: 120 000 Bytecode-Schritte je Ereignis.** Schon 1000
  Punkte in einem Zug zu dekodieren löste ihn aus, ebenso das Zeichnen
  aller Stücke und die Suche über die ganze Linie. Deshalb dekodiert
  die Uhr in Häppchen zu 300 Punkten (Timer, Lader „Lade Route …"), und
  Zeichnen wie Suche gehen über Blöcke zu 32 Punkten mit Hülle.
- Die Uhr erscheint am Rechner als Laufwerk (Massenspeicher); gekoppelt
  wird mit der Garmin-Connect-App.

## 8. Messplan (📱, an der fēnix 5)

1. **Speicher**: Wie viele Punkte passen in die 128 KB, mit Ansicht?
   Gemessen mit Routen von 500, 1000, 2000 und 4000 Punkten.
   **Im Simulator gemessen (2026-11-04, G1)**, 124 KB frei für die App:
   500 Punkte 39 KB, 1000 Punkte 49 KB, 2000 Punkte 70 KB — gut 20 Byte
   je Punkt auf ~29 KB Grundlast. 3000 und 4000 Punkte: „Out of Memory"
   schon beim Laden, weil rohe Daten und dekodierte Felder kurz
   zusammen im Speicher liegen. Grenze für G2: 2000 Punkte (Abschnitt
   2). Mit Ring und Seiten (2026-11-04): 2000 Punkte 76 KB. Am Gerät
   nachmessen.
2. **Übertragung**: größte Nachricht, die ankommt; Dauer für eine
   typische Runde. Seit Protokoll 2 (2026-11-05) halb so viele Zahlen
   je Punkt; eine Route „Zum Trailkopf" ging in 2 Stücken. Am Gerät (2026-11-04): Für eine geschlossene Uhr-App
   meldet Garmin Connect `SUCCESS` und die Nachricht verfällt — daher
   das Anstoßen und „hallo" (Abschnitt 2). Größe und Dauer offen.
3. **Akku**: Prozent je Stunde mit GPS jede Sekunde und Anzeige an.
4. **Lesbarkeit**: die S-Farben auf MIP in der Sonne.
5. **Abseits**: Die 30-m-Regel mit dem GPS der Uhr — löst sie im Wald
   falsch aus? Das ist der Startwert, wie in der App.

## 9. Umsetzung in Schritten (je ein PR)

1. **G1 — Uhr-App mit fester Testroute** (`garmin/`, kein Bump): Ansicht,
   Drehung, Abseits-Regel, Vibrieren, Speicher; Messung 1 und 3 bis 5.
   Gebaut am 2026-11-04: erfundene Runde mit Trails und Abzweigungen,
   am ersten GPS-Fix verankert; eine eigene Route geht mit
   `tool/garmin_build.sh --gpx` (ohne Abschnitte, nur unter `build/`).
   Messung 1 im Simulator erledigt, 3 bis 5 am Gerät offen.
   Ring, drei Seiten und Zusammenfassung bei der Ankunft am selben Tag
   (Entwurf „Ring und Seiten").
2. **G2 — Protokoll und Android-Brücke** (`feat`, Bump): Kodierung in
   Dart, Brücke, Schalter „Auf der Uhr zeigen", Datenschutz und
   Play-Console; Messung 2. Gebaut am 2026-11-04 (0.150.0) samt
   Bestwerten; Messung 2 und die Abnahme am Gerät offen, die
   Abzweigungen als eigener Schritt danach. Idee des Betreibers (2026-11-04) für die
   Brücke: Das Handy schickt während der Fahrt die Bestwerte seiner
   Erkennung (#36) — weitester und höchster Sprung, längster Wheelie,
   größter Wheelie-Winkel —, die Uhr zeigt sie auf „Fahrt" und in der
   Zusammenfassung. Nur Zahlen, keine Spur; bleibt auf Handy und Uhr
   (A3). Die Uhr misst dabei weiter nichts (Entscheidung 1).
3. **G3 — Abnahme am Gerät** (📱) und die Entscheidung zum Store.

## 10. Abgleich mit den Kernanforderungen

- A1, A2: nur die Trails der Route, die der Nutzer schon sieht.
- A3: keine Fahrt von der Uhr, keine Garmin-Aktivität; die Zahlen der
  Seiten (Strecke, Puls, bergauf) nur im Speicher der laufenden App.
- A5: Ausnahme nach Entscheidung 2.
- A6: Datenschutz und Play-Console mit G2.
- A7: Schlüssel und Testrouten nie im Repo; die Testroute in G1 ist
  erfunden.
- A8: Die Uhr navigiert nach der Übertragung ohne Handy.
- A9: nur Android, wie das Aufzeichnen.
- A12: zeigt; vibriert beim Abkommen (Entscheidung 3). Die Stummel der
  Abzweigungen sind Anzeige wie die Karte, kein Abbiegehinweis.
- A13: große Schrift, MIP-Farben am Gerät geprüft.
- A14: Texte der Uhr-App in beiden Sprachen.
