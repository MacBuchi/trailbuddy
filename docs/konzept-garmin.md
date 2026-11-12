# TrailBuddy auf der Garmin-Uhr — Konzept

*Angelegt am 2026-11-03. Anlass: Der Betreiber will das Handy nicht mehr
ans Rad kleben und unterwegs nicht herauskramen; die Uhr am Lenker oder
am Handgelenk soll die Navigation zeigen. Erstes Gerät ist die fēnix 5
des Betreibers. Dieses Dokument kommt vor dem ersten Code.*

## 0. Entscheidungen des Betreibers (2026-11-03)

1. **Die Uhr ist Anzeige, nicht Sensor** (eingeschränkt durch 5: die
   eigene Spur zeichnet sie auf). Die fēnix 5 hat keinen
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
5. **Die Uhr zeichnet die Fahrt auf** (Betreiber 2026-11-07, #484:
   „auch ohne Handy bzw. ohne Navigation starten und aufnehmen, Sync bei
   Beenden, wenn das Handy verfügbar ist"). Das schränkt Entscheidung 1
   ein: Gemessen wird nur, was eine Fahrt des Handys auch hat — GPS,
   Höhe (vom Barometer) und Zeit —, kein Puls, keine Sensor-Rohdaten,
   keine Erkennung. Weiterhin **keine Garmin-Aktivität**: Die Fahrt geht
   über Garmin Connect nur an das eigene Handy (Abschnitt 2a). Die Uhr
   zeichnet immer auf; hat das Handy dieselbe Zeit selbst aufgezeichnet,
   behält es seine Fahrt und verwirft die der Uhr. Das Handy lauscht ab
   dem Start der App, sobald einmal eine Uhr gefunden wurde — geöffnet
   wird die Uhr dabei nicht.
6. **Die Aufzeichnung steuert man an der Uhr, „wie Garmin"** (Betreiber
   2026-11-07, nach 1.1.0: „Aufzeichnung stop start sowie Trail
   Aufzeichnungen stop start würde ich gern an der Uhr machen, und beim
   Stoppen/Verlassen irgendein sinnvolles Menü, wo ich an der Uhr gleich
   verwerfen angeben kann"). START beginnt die Aufzeichnung — erst dann,
   nicht mehr beim ersten Fix —, START hält an und zeigt das Menü
   *Weiter · Speichern · Verwerfen*; ZURÜCK ist LAP und markiert „Trail
   beginnt" / „Trail endet", nach dem Ende *Behalten · Verwerfen*;
   hoch/runter blättern die Seiten. Dazu stößt die Uhr die Aufzeichnung
   am Handy an, wenn TrailBuddy dort läuft („erst messen", Abschnitt 8.7).
   Das schränkt Entscheidung 5 ein: Die Uhr zeichnet jede Fahrt auf, die
   man mit START beginnt.

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
  Steht man weiter von der Linie entfernt, als die Karte je zeigen kann
  (über 540 m), passt stattdessen die ganze Linie genordet in den Kreis:
  der nächste Punkt der Linie als Warnpunkt, ein gestrichelter Strich in
  die eigene Richtung, dieselbe Warnfläche darunter (#498, fēnix 5
  2026-11-08: sonst bleibt das Blatt leer).
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
  Uhr selbst; die Zahlen stehen nur im Speicher der laufenden App, die
  Seiten speichern und verschicken nichts (die Fahrt selbst zeichnet
  `RideLog` auf, Abschnitt 2a).
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
- **Tasten** (Entscheidung 6, wie Garmins eigene Aktivitäten): **START**
  beginnt die Aufzeichnung, hält sie an (Menü *Weiter · Speichern ·
  Verwerfen*, mit Route steht unter „Speichern" „beendet die Navigation";
  ZURÜCK lässt die Pause stehen, START macht weiter) und macht weiter.
  **ZURÜCK/LAP** setzt während der Aufzeichnung „Trail beginnt" bzw.
  „Trail endet" (kurz vibrieren, Einblendung), nach dem Ende das Menü
  *Behalten · Verwerfen* (ZURÜCK behält); in der Pause öffnet es das Menü;
  vor START fragt es „Navigation beenden?" bzw. „TrailBuddy beenden?".
  **hoch/runter** blättern Karte → Fahrt → Berg (→ Sprünge), **langes
  HOCH** (MENU) holt die Karte nach vorn und schaltet die drei Zoomstufen
  durch (1, 1,5 und 4 m je Pixel, Start auf 1,5 — gut 180 m voraus).
  Beim Abkommen kommt die Karte von selbst nach vorn. „Verwerfen" der
  Fahrt fragt noch einmal. Tippziele gibt es nicht; A13 heißt hier: große
  Schrift, kräftige Linien.
- **Was die Aufzeichnung tut**, steht immer da: auf der Karte oben, auf
  den Zahlenseiten unten ein Schild — vor START „START: AUFNAHME" in Lime
  auf Schwarz, in der Pause „PAUSE" in Warnfarbe, auf einem markierten
  Trail „TRAIL" schwarz auf Lime, sonst ein roter Punkt. Ist man vor
  START schon zehn Fixe über 9 km/h unterwegs, vibriert die Uhr einmal
  kurz und blendet „START: AUFNAHME" ein. Vor START und in der Pause
  zählen Strecke, Fahrzeit und bergauf nicht.

- **Ohne Route die freie Fahrt** (#484, Store-Paket ohne Testroute):
  Statt „Navigation starten in der TrailBuddy-App" schaltet die Uhr GPS
  ein und zeigt die eigene Spur der letzten 25 min (300 Punkte) dünn in
  Moos auf der gedrehten Karte, „N", den Pfeil, unten „Freie Fahrt" mit
  Strecke und Anstieg; „Fahrt" und „Berg" wie sonst, kein Ring. Beendet
  wird über das Menü der Pause, vor START mit „TrailBuddy beenden?".
  Kommt eine Route vom Handy, wechselt die Uhr in die Navigation, die
  Aufzeichnung läuft weiter. Mit Handy sagt die freie Fahrt alle 30 s
  wieder „hallo" (Messung 8.8): Eine Route, deren erstes Senden verloren
  ging, kommt so doch noch.

Das Handy antwortet von selbst (#484, #501): Hat es kein Navigationsziel, sucht
es den Trail, dessen Linie am nächsten liegt (800 m Reichweite, mindestens
250 m Rest), und schickt sie ab dem nächstliegenden Punkt in die längere
Richtung. Driftet die Uhr von dieser Linie ab, geht der nächste Trail in
Reichweite hinterher; die Uhr fragt vorher, ob sie ihn nimmt (#501).
Connect IQ weckt das Handy nicht: Die App muss laufen, gestartet wird die
Uhr-App auf der Uhr.

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
`{t: "g", la, lo}` meldet („ich habe eigenes GPS") und gleich diesen
ersten eigenen Fix, die
Navigation endet oder 3 min um sind (`kWatchPositionFor`) — die Uhr
navigiert allein (A8), das ist nur ein Vorsprung beim Start. Ein neues
„hallo" (die Uhr-App startete neu) beginnt den Takt wieder. Die Uhr hält
die Position nur im Speicher (A3).

**Der Abgleich der beiden GPS (#500, Betreiber 2026-11-09):** Mit dem
ersten eigenen Fix nennt die Uhr ihren Ort. Das Handy vergleicht ihn mit
der eigenen Navigationsposition: mehr als 200 m (`kWatchFixApartM`)
auseinander, sagt die Uhr-Leiste „Die Uhr meldet einen Ort … von hier" —
die Uhr folgt dann einer Linie, die hier nicht läuft, und meldet
„neben der Route", obwohl niemand abweicht. Einmal, nicht dauerhaft:
mehr darf die Uhr nicht senden (A8, A3), und eine ältere Uhr-App nennt
keinen Ort — dann bleibt der Stand wie er ist.

Die Uhr schickt zurück: „angekommen und gespeichert" mit der Kennung,
„hallo" mit der Kennung der Route, die sie hat (und den wartenden
Fahrten), einmal „habe GPS" mit ihrem ersten Fix, START/PAUSE/WEITER
(2a), der Stand, wenn sie aus dem Blickfeld fährt (unten), und die
eigene Fahrt. Kein Takt, keine Position im Lauf sonst.

**Der Umkreis hat Vorrang, die Linie kommt in Teilen (#500, Betreiber
2026-11-09):** Die Uhr hat rund 124 KB, die volle Linie nimmt schon bis
2000 Punkte (Messung 8.1, ~70 KB); im Simulator 2026-11-09 standen 1000
Punkte mit Ring und Seiten bei 94–99 KB. Deshalb gilt: **erst der
Umkreis, dann die Linie.** Die Linie geht nicht mehr als Ganzes hin,
sondern **stückweise um den Fortschritt** — das Handy kennt sie ganz und
schickt die nächsten Stücke, wenn die Uhr ans Ende des Geladenen kommt.
**Nur mit verbundenem Handy** (2026-11-11, Feldszenario F2 in
`konzept-geraete.md` 9): Stückweise nachladen braucht das Handy unterwegs
— eine Route, die vorher auf die Uhr gelegt wurde (Ablage, #515), liegt
dort immer ganz und wird dafür so weit vereinfacht, bis sie passt. Sonst
widerspräche der Umkreis A8 („die Uhr navigiert ohne Handy").

- **Wann die Uhr ihren Stand meldet:** nur, wenn sie ihn braucht. Den
  ersten Fix mit `{t: "g", la, lo}` (schon gebaut, siehe Abgleich), dann
  `{t: "d", la, lo, off}` sobald `offM` größer ist als die Sicht der
  Ansicht (`_reach`, 540 m bei Zoom 4 — genau der Punkt, an dem die
  Ansicht leer wird, #498), und erst wieder, wenn der Stand mindestens
  300 m weiter liegt als die letzte Meldung. Kein Abfragen von
  Handyseite: eine Nachricht über Connect braucht ~15 s (Messung 8.2),
  ihre Antwort wäre beim Eintreffen schon 300 m alt (20 km/h), und jede
  Anfrage kostet Akku auf beiden Seiten. Die Uhr rechnet selbst —
  `NavTracker` weiß jeden Fix gegen die Linie, `offM` und `offRoute`
  stehen schon.
- **Wie groß das Fenster ist:** 800 m Umkreis. Die Ansicht sieht höchstens
  540 m (`_reach = 135 px × mpp`, `ZOOM_MPP` 1,0 / 1,5 / 4,0), 800 m
  tragen zwei Zoomstufen weiter, ohne dass die Uhr nachladen muss.
  Nachgeladen wird die Linie, sobald weniger als 1 km vor dem Fortschritt
  geladen ist.
- **Was die Uhr dann nicht mehr sieht:** die ganze Linie. Die
  eingepasste Übersicht (#498) zeigt, was geladen ist; „bis zum Ziel",
  Länge und Höhenmeter kommen aus dem Kopf des ersten Stücks, nicht aus
  den Punkten. Der Kopf muss sie tragen.
- **Was im Fenster steht (Betreiber, 2026-11-09):** derselbe Ausschnitt,
  den man auf dem Handy um sich herum sieht — nur als Linie, nicht als
  Karte. Alles, was die Karte aus Vector zeichnet:
  - die **Trails der Gruppe** im 800-m-Umkreis, in denselben Farben nach
    Grad wie auf dem Handy; das Netz liegt unter der Route,
  - die **Linie der Navigation** und ihre Stummel,
  - Schilder mit Namen nur für Trails, die die Ansicht wirklich berührt.
  Nicht hin können die Rasterkacheln und die Randlinien des Bestands:
  dafür hat die Uhr keinen Platz (124 KB, MIP ohne Glättung). Sie liegen
  auf dem Handy ohnehin nur als Gebietspakete; die Uhr zeichnet Linien.
  Vereinfacht wird auf **10 m**, höchstens **800 Punkte** (rund 28 KB) —
  sonst wird das Fenster dicker als die Linie. Was schon Teil der Linie
  oder eines Stummels ist, wird nicht noch einmal geschickt. Ein neues
  Fenster verdrängt das alte: die Uhr hält nie zwei.
- **Was der Alarm auslöst (Betreiber, 2026-11-09):** von selbst. Weicht
  die Uhr ab, rechnet das Handy eine neue Linie ab der Position der Uhr
  (wie „Route umplanen", #464) und schickt sie. Die Uhr fragt kurz
  „Route ab deiner Position?", wer nichts tut, nimmt sie nach 8 s an;
  START oder Zurück lehnen. Ohne die Frage würde jemand unwissend auf
  einer anderen Linie weiterfahren. Nachprüfbar ohne Gerät am Arm:
  `tool/garmin_scenario.sh` spielt die Runde im Simulator (Frage, Ablehnung,
  Annahme nach der Frist) und prüft die Konsole; `garmin/source/Tests.mc`
  hält die Einheitentests dazu (gebaut 2026-11-11). Die Fälle, die dabei
  geprüft werden, stehen gesammelt in `docs/watch_cases.json` —
  `test/garmin/watch_cases_test.dart` kontrolliert, dass jeder Fall wirklich
  eine Prüfung hat, damit die Abdeckung nicht leise kleiner wird.
- **Was genau hin geht (Entwurf, Zahlen noch zu messen):**
  1. Kopf: Kennung, Fassung, Abschnitte, **Gesamtlänge und Aufstieg** —
     die Uhr kennt nicht mehr die ganze Linie, „bis zum Ziel" muss aus
     dem Kopf kommen.
  2. Die Linie in Stücken à 800 Zahlen (~4 KB, ~15 s, Messung 8.2),
     gepackt je Punkt eine Zahl; die Stummel `br` fahren im Stück ihres
     Punkts mit.
  3. Das Fenster: neue Art `w` — Mittelpunkt, Radius, gepackte Punkte
     der Gruppen-Trails, Namen nur für die Trails, die die Ansicht
     berührt.
  4. Die Position des Handys bleibt, bis die Uhr eigenes GPS hat
     (`p`, Abschnitt 2).
  5. Zurück von der Uhr: `g` erster Fix, `d` „ich fahre hinaus" mit
     Stand und Abstand, `ok` gespeichert, `rp`/`rr`/`rt`/`re` (2a).
- **Wann die Uhr ihren Stand meldet (Betreiber, 2026-11-09, gebaut
  2026-11-11):** erst wenn die Fahrt wirklich läuft. Scharf ist die
  Prüfung, sobald die Uhr die Linie einmal berührt hat — ein eigener Fix
  näher als 50 m (`ARM_M` in `garmin/source/NavTracker.mc`), und
  `driftM` gibt den Abstand erst, wenn er 300 m weiter liegt als die
  letzte Meldung (`DRIFT_STEP_M`). Zurück kommt `{t: "d", la, lo, off}`;
  die Leiste auf dem Handy sagt „Die Uhr ist … neben ihrer Route". Vorher
  (Anfahrt, Uhr im Pocket, Stand 12 km weit) ist ein Abstand normal: die
  eingepasste Übersicht (#498) zeigt dann die Route, aber weder Alarm
  noch Nachladen. Wer nie auf der Linie war, hat auch nichts verlassen.
- **Offen noch:** die Punktgrenzen. Die Uhr hat 124 KB, davon sind
  ~60 KB Ring, Seiten und Code (Simulator 2026-11-09: 1000 Punkte mit
  Ring und Seiten 94–99 KB). Route und Fenster zusammen müssen in die
  restlichen ~60 KB passen, und beim Empfang hält die Uhr ein Stück
  samt Zwischenspeicher. Messung 8.9 an der fēnix 5: wie viel Netz
  liegen real in 800 m, und wie viele Punkte passen, ohne dass die
  Linie darunter leidet. Ob dafür eine neue App-Version nötig ist,
  entscheidet die Store-Fassung (Abschnitt 5).

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
  Fahrt wie bisher auf dem Handy von Hand. Die Uhr schließt ihre eigene
  Fahrt ab und schickt sie (Abschnitt 2a); das Handy verwirft sie, weil
  es dieselbe Zeit selbst aufzeichnet. Ohne Verbindung beendet jede
  Seite nur sich selbst.
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

## 2a. Die Fahrt auf der Uhr (#484)

Entscheidung 5. Gebaut in `garmin/source/RideLog.mc` (Uhr),
`lib/features/garmin/watch_ride.dart` (Form, pur) und
`watch_ride_inbox.dart` (Empfang).

- **Aufgezeichnet wird ab START** (Entscheidung 6), mit Route oder ohne:
  jeder EIGENE Fix danach (die Position des Handys zählt nicht), alle 5 s
  ein Punkt wie die Fahrt des Handys; in der Pause keiner, und der
  Sprung über die Pause zählt nicht als Strecke. „Verwerfen" löscht die
  offene Fahrt samt Marken, nichts wartet. Je Punkt Lage in 1e-5°, Zeit in Sekunden,
  Höhe vom Barometer (sonst GPS) in Dezimetern und die Klasse der
  Genauigkeit (gut, brauchbar, … — auf dem Handy 5, 15, 40, 100 m).
  Kein Puls.
- **Gepackt wie Protokoll 2**, in Stücken zu 60 Punkten (5 min): der
  erste Punkt ganz, dann je Punkt `(dLat << 16) | dLon` und
  `(dt << 16) | (dE << 2) | acc`; passt ein Schritt nicht (Lücke im
  GPS), beginnt ein neues Stück. Je Stück 123 Zahlen, ~600 Byte im
  Speicher der Uhr.
- **Sofort im Speicher der Uhr** (`Application.Storage`): das offene Stück
  jede Minute neu, dazu der Stand `wo`. Ein Absturz kostet höchstens eine
  Minute; der nächste Start nimmt die Fahrt in die Warteschlange `rq`.
  Unter 2 min oder 200 m ist es keine Fahrt (Start vom Sofa), sie fällt
  weg. Höchstens 6000 Punkte (gut 8 h) und 20 Fahrten warten; ist die
  Schlange voll, steht die Aufzeichnung („Speicher voll") — nichts
  Wartendes wird überschrieben. Die Grenze ist ein Startwert bis zur
  Messung 8.6.
- **Die Trail-Marken** (LAP an der Uhr): wie `RideMark` der App nur die
  Zeit, unter `m<id>` = `[Art, t, …]` (0 Beginn, 1 Ende), sofort im
  Speicher; „Verwerfen" nach dem Ende nimmt das letzte Paar weg. Sie
  reisen mit der ersten Nachricht der Fahrt (`m`) und stehen auf dem
  Handy in der Datei wie die eigenen — das Zerlege-Blatt nimmt sie als
  „markiert". Den Namen gibt man dort, die Uhr hat keine Tastatur.
- **Das Handy nimmt mit auf** (Entscheidung 6): START an der Uhr schickt
  `{t: "rs"}`; läuft TrailBuddy und keine Aufzeichnung, beginnt das
  Handy eine (mit Sensoren, `WatchRideInbox`). Ein behaltener Trail geht
  als `{t: "rt", s, e}` und wird dort eine Marke, das Ende als `{t: "re",
  k}` (gespeichert/verworfen) und beendet nur eine Aufzeichnung, die die
  Uhr begann. Kommt in 45 s kein Punkt (der Dienst mit Standort darf aus
  dem Hintergrund nicht starten), nimmt das Handy sie still zurück —
  Messung 8.7. Pause und Weiter melden die Uhr dazu (`{t: "rp"}`, `{t: "rr"}`,
  #499): Das Handy zeichnet davon unberührt weiter, gezeigt wird sie dem
  Nutzer auf dem Handy (der nächste Punkt). Hat das Handy aufgezeichnet,
  bleibt beim Ablegen dessen
  Fahrt (Überdeckung, unten) und die der Uhr fällt weg; die Marken hat es
  dann schon aus `rt`.
- **Der Stand der Uhr steht auf dem Handy** (#499, Betreiber 2026-11-09:
  "der aktuelle Status der Uhr sollte auch auf dem Handydisplay angezeigt
  werden — verbunden, nimmt auf"): Ist die Uhr gefunden, steht das
  Uhren-Symbol in der Navigationsleiste dauerhaft, nicht nur während des
  Sendens; nimmt die Uhr auf, ist es gefüllt und sagt es in Worten, Pause
  und Weiter ebenso. Das Startblatt nennt denselben Stand, bevor die
  Navigation beginnt.
- **Beim Beenden** ("Speichern" im Menü der Pause, "Navigation beenden?"
  vor START, oder das Handy beendet die Navigation): die Fahrt in die
  Warteschlange (zu kurz: „Fahrt zu kurz, nicht gespeichert"); ist ein
  Handy verbunden, gehen die wartenden Fahrten hinüber — `{t: "w", id,
  p, n, c}`, je Nachricht bis zu 6 Stücke (~740 Zahlen), eine nach der
  anderen; die Uhr zeigt „Fahrt geht ans Handy · 1/2". Erst `{t: "wk",
  id}` vom Handy löscht sie auf der Uhr; dann kurz vibrieren, „Fahrt ist
  auf dem Handy", zu. Ohne Antwort in 20 s, ohne Handy oder mit ZURÜCK
  geht die App zu, und die Fahrt wartet („Fahrt gespeichert, wartet aufs
  Handy").
- **Beim nächsten Start** trägt das „hallo" die wartenden Fahrten (`rq`);
  das Handy antwortet `{t: "wq"}` („schick"), und die Uhr schickt sie im
  Lauf — nicht, solange eine Route ankommt: eine Übertragung zur Zeit.
  Neue Arten, keine neue Fassung: Eine ältere Seite übergeht sie, die
  Fahrt wartet dann einfach.
- **Das Handy lauscht ab dem Start der App**, sobald das Startblatt einmal
  eine Uhr mit unserer App fand (`Settings.watchSeen`, Kanal-Methode
  `listen`: SDK starten, auf die Uhr hören, kein `openApplication`). Es
  fragt die Uhr nicht (`q` bleibt der Navigation): Die Uhr-App meldet
  sich bei jedem Start mit `rq` und schickt beim Beenden selbst.
- **Das Handy legt ab, erst dann quittiert es**: Stücke je Kennung
  zusammensetzen (eine halbe Fahrt verfällt nach 2 min), entpacken,
  prüfen. Liegt dieselbe Startsekunde schon da, oder deckt eine eigene
  gemessene Fahrt mindestens die halbe Zeit (`rideOverlaps`), bleibt es
  bei der vorhandenen — quittiert wird trotzdem. Sonst als übernommene
  Fahrt in „Meine Fahrten" (`source: watch`, „Von der Uhr", Rad des
  Fahrerprofils), mit der Leiste „Fahrt von der Uhr übernommen ·
  Ansehen". Ohne Anmeldung oder wenn das Ablegen scheitert, quittiert es
  nicht: Die Fahrt bleibt auf der Uhr. Eine unlesbare Fahrt wird
  quittiert — sie belegte die Uhr sonst für immer.
- **Danach ist sie eine Fahrt wie jede andere** (A3): zerlegen, exportieren,
  kalibrieren, löschen; sie verlässt das Telefon nicht.

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
  Haustür (A3, A5). Die eigene Aufzeichnung der Uhr (Abschnitt 2a) geht
  nur an die TrailBuddy-App auf dem eigenen Handy.
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
   **Entscheidung (Betreiber, 2026-11-07):** erst als **Beta-App**, die
   nur das Entwicklerkonto sieht, installiert über die Connect-IQ-App wie
   bei echten Nutzern; danach dasselbe Paket öffentlich. Für die Uhren
   der **240er-Familie** (240 × 240 px MIP, fünf Tasten: fēnix 5, 5X,
   5 Plus, 5X Plus, 5S Plus, 6S, Forerunner 935, 945, 945 LTE), je mit
   den Unit-Tests im Simulator; am Gerät abgenommen ist nur die fēnix 5.
   Das Store-Paket (`tool/garmin_build.sh --store`) hat **keine
   Testroute**: Ohne Route vom Handy beginnt die freie Fahrt (#484,
   Abschnitt 1). Ausfüllhilfe
   und Ablauf: `docs/garmin-store.md`.

## 6. Code und Build

- `garmin/`: `manifest.xml`, `monkey.jungle`, `source/`, `resources/`
  mit Texten auf Deutsch und Englisch (A14), Geräte in der
  Produktliste des Manifests — zuerst `fenix5`, weitere Uhren erst nach
  einem Test im Simulator (seit 2026-11-07 die 240er-Familie, Abschnitt
  5). Andere Größen (fēnix 5S mit 218 px, fēnix 6/7 mit 260 px) brauchen
  erst ein Layout, das aus der Bildschirmgröße rechnet.
- **Bauen** lokal mit dem Connect-IQ-SDK (`monkeyc`), dazu ein Skript
  `tool/garmin_build.sh`. Der normale Build — der, der auf die Uhr kommt —
  enthält **keine erfundene Route**: ohne Route vom Handy beginnt die freie
  Fahrt. Die Testroute steckt nur in den Prüf- und Messbauten
  (`--test`, `--demo`, `--run`, `--demo-route`, `--points`, `--gpx`). Ob CI
  die Uhr-App mitbauen kann, hängt daran, ob sich das SDK ohne
  Garmin-Anmeldung laden lässt — offen, bis es probiert ist.
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

**Wer misst was** (Roadmap #501, 2026-11-09): Die Logik der Uhr-App — Kodierung,
Stückteilung, Crash-Wächter, Fahrten-Log, die 540-m-Schwelle der Übersicht — prüft
der Simulator mit `tool/garmin_build.sh --test`. `--demo` spielt reihum Anfahrt,
Trail, abseits, angekommen und **weitab von der Linie** (#498), und die Konsole
sagt je Szene, welche Ansicht genommen wird und wie viel Speicher Route, Ring und
Seiten brauchen. Optik und Grenzen zeigen `--run` und `--points` im Simulator;
Übertragung, Akku, Sonnen-lesbarkeit, Speicher unter Last und das GPS im Wald
kann nur das echte Gerät.
Alles, was über Garmin Connect geht (8.2, 8.7, 8.8), braucht das Telefon neben der
Uhr — die Brücke sitzt dort, nicht auf der Uhr.

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
6. **Die Fahrt auf der Uhr** (#484): Wie viel nimmt `Application.Storage`
   an der fēnix 5 neben einer Route mit 2000 Punkten — passen die 6000
   Punkte der Warteschlange? Wie lange dauert die Übertragung einer
   Stunde (720 Punkte, 2 Nachrichten)? Danach `RideLog.MAX_POINTS`
   festlegen.
7. **Das Handy nimmt mit auf** (Entscheidung 6): Startet `rs` die
   Aufzeichnung am Pixel 7 Pro, wenn TrailBuddy im Vordergrund ist, im
   Hintergrund und bei ausgeschaltetem Bildschirm? Kommt `rs` überhaupt
   an, wenn die App im Hintergrund ist? Logcat `TB-GARMIN rs: …` sagt
   gestartet, „kein Punkt … zurückgenommen" oder nichts. Geht es im
   Hintergrund nicht, ist der nächste Schritt eine Benachrichtigung über
   Garmin Connect (`openWebPage`, ein Tipp öffnet die App) — nur mit
   Befund.
8. **Runde vom Handy, Uhr bleibt in der freien Fahrt** (Feldbefund
   2026-11-07, 1.1.0, Uhr vom Handy geöffnet, kein Vibrieren — die Route
   kam nie ganz an). Wahrscheinlich: Die Antwort auf „hallo" kam nach den
   8 s (das Handy rechnet erst Höhen und Abzweigungen der Runde), oder ein
   Senden scheiterte, und ohne neues „hallo" versuchte das Handy es nicht
   wieder. Seitdem sagt die Uhr in der freien Fahrt mit Handy alle 30 s
   wieder „hallo" (höchstens 20-mal), das Handy schickt dann nach.
   Bestätigen mit Logcat (`TB-GARMIN`, `send`/`receive`) am Gerät.

9. **Der Umkreis (#500)**: wie viel Netz der Gruppe real in 800 m um
   einen Trailkopf liegt (Trails, Kilometer, Punkte bei 10 m
   Vereinfachung), und wie viele Punkte Linie + Fenster + Ring zugleich
   in die 124 KB passen, ohne dass die Linie darunter leidet. Erst mit
   dem Befund stehen die Grenzen in Abschnitt 2.
10. **Die Frage an der Uhr (#501, am Gerät offen):** Steht der Pill
   „Route ab deiner Position?“ auf der fēnix 5 lesbar, lehnen START und
   ZURÜCK die neue Linie wirklich — die alte bleibt, der Speicher ist
   leer — und nimmt der Rahmen sie nach den 8 s? Im Simulator spielt
   `tool/garmin_scenario.sh` das schon durch (Frage, Ablehnung, Annahme
   nach der Frist, dieselbe Linie nochmal ohne Frage), und
   `garmin/source/Tests.mc` hält die Bedingungen. Was fehlt: die Tasten
   am Handgelenk, die MIP-Lesbarkeit der Frage in der Sonne und der Weg
   über Garmin Connect, solange der Store nur 1.2.0 kennt (1.3.0 liegt
   fertig als `build/garmin/trailbuddy.iq` bereit).

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
3. **G3 — Abnahme am Gerät** (📱) und die Entscheidung zum Store
   (gefallen 2026-11-07: Beta, 240er-Familie, Abschnitt 5).
4. **G4 — Freie Fahrt und Fahrt auf der Uhr** (#484, `feat`, Bump):
   Entscheidung 5, Abschnitt 2a; Messung 8.6 und die Abnahme an der
   fēnix 5 offen.
5. **G5 — Aufzeichnung an der Uhr** (`feat`, Bump): Entscheidung 6 —
   START/Pause mit Menü, LAP-Marken, Verwerfen, Handy nimmt mit auf; dazu
   das erneute „hallo" der freien Fahrt (8.8). Messung 8.7 und die
   Abnahme an der fēnix 5 offen.

## 10. Abgleich mit den Kernanforderungen

- A1, A2: nur die Trails der Route, die der Nutzer schon sieht.
- A3: die Fahrt der Uhr geht nur an das eigene Handy und bleibt dort
  (Entscheidung 5, Abschnitt 2a), keine Garmin-Aktivität; die Zahlen der
  Seiten (Strecke, Puls, bergauf) nur im Speicher der laufenden App.
- A5: Ausnahme nach Entscheidung 2.
- A6: Datenschutz und Play-Console mit G2.
- A7: Schlüssel und Testrouten nie im Repo; die Testroute in G1 ist
  erfunden.
- A8: Die Uhr navigiert nach der Übertragung ohne Handy; ohne Route
  fährt und zeichnet sie frei, die Fahrt wartet aufs Handy.
- A9: nur Android, wie das Aufzeichnen.
- A12: zeigt; vibriert beim Abkommen (Entscheidung 3). Die Stummel der
  Abzweigungen sind Anzeige wie die Karte, kein Abbiegehinweis.
- A13: große Schrift, MIP-Farben am Gerät geprüft.
- A14: Texte der Uhr-App in beiden Sprachen.

## 11. Bedienkonzept 2.0 (Vorschlag, 2026-11-10 — nicht entschieden)

*Bis der Betreiber entscheidet (`docs/konzept-geraete.md`, E2), gelten
Entscheidung 6 und Abschnitt 1. Entwurf im Designer („TrailBuddy Uhr
2.0", Link im PR).*

Was heute hakt (Stand 1.3.1, `garmin/source/TrailBuddyApp.mc`):

- **ZURÜCK hat vier Bedeutungen** (`backKey`): Trail-Marke in der
  Aufzeichnung, Menü in der Pause, „beenden?" vor START, und es lehnt
  eine angebotene Route ab.
- **START lehnt ab** (`declineReplan`): Während der Frage „Route ab
  deiner Position?" lehnen START und ZURÜCK beide, nur Abwarten nimmt
  an. An jeder anderen Stelle der Uhr heißt START „ja".
- **Für alles Weitere gibt es keinen Ort**: Langes HOCH schaltet nur den
  Zoom. Trails in der Nähe, eine andere Route, Buddys oder „zurück zum
  Start" hätten keine Taste.

Der Vorschlag:

| Zustand | START | ZURÜCK / LAP | hoch · runter | langes HOCH |
|---|---|---|---|---|
| Bereit | Aufnahme starten | verlassen, fragt nach | Seite | **Aktionsmenü** |
| Aufnahme läuft | Pause (Weiter · Speichern · Verwerfen) | Trail beginnt / endet | Seite | **Aktionsmenü** |
| Pause | Weiter | Pause-Menü | Seite | **Aktionsmenü** |
| Frage offen | **ja** | nein | Frage bleibt | — |
| Menü oder Liste | wählen | eine Ebene zurück | blättern | — |

- **Das Aktionsmenü** (ein `Menu2`): Zoom · Trails in der Nähe · Route
  (neu ab hier, nächsten Trail überspringen, zurück zum Start, beenden)
  · Gespeicherte Routen · Buddys. Was gerade nicht geht, fehlt.
- **Fragen sehen immer gleich aus**: ein Schild mit ablaufender Frist,
  „JA" steht neben START, „NEIN" neben ZURÜCK. Nach der Frist gilt ja —
  wie heute (`ASK_MS`).
- **Zoom von selbst**: nach Tempo und Abstand zum nächsten Trailkopf;
  von Hand im Menü. Dann fehlt die Taste niemandem.
- **Navigation ist eine Ebene, kein Modus**: Freie Fahrt, Linie in der
  Nähe (#506) und Route sind derselbe Bildschirm mit mehr oder weniger
  Inhalt. „Route beenden" steht im Menü und lässt die Aufzeichnung
  laufen; „Speichern" beendet die Fahrt, nicht „die Navigation".
- **Bereit zeigt schon den Umkreis** (#500): Vor START stehen die Trails
  in der Nähe und die Wege dorthin auf der Karte, unten der nächste
  Trail mit Weg und Anstieg.

- **Sprünge und Wheelies ohne neue Seite** (Betreiber, 2026-11-10:
  „eine kleine Info … falls sauber aktiviert. Aber nicht zu viele
  Screens"). Heute gibt es die vierte Seite „Sprünge" und eine Zeile in
  der Zusammenfassung (9.2); beides zeigt Bestwerte, und nur, was das
  Handy bei OFFENER App meldet. Was fehlt, ist der Moment und der Stand:
  - **Ein Zeichen am Rand der Karte**, solange das Handy erkennt UND
    seine Halterung gelernt hat (`FusionLive.mountReady`). Ohne beides
    fehlt es — die Uhr behauptet nie eine Erkennung, die nicht läuft.
  - **Ein Hinweis im Fußfeld für 3 s** („AIR 0,9 s", „WHEELIE 12 m"),
    derselbe Platz wie das Schild einer Frage, danach wieder der Trail.
    Eine Frage geht vor.
  - **Keine fünfte Seite.** Die Seite „Sprünge" bleibt, wie sie ist, und
    nur, wenn die Erkennung läuft.
  Voraussetzung am Handy: Die Erkennung muss auch aus dem Dienst melden,
  nicht nur an die offene App — bei gesperrtem Bildschirm kommt heute
  nichts nach. Im Protokoll ist es ein Feld im Stand (`on`) und eine
  Nachricht je Ereignis; bei ~3,5 s Laufzeit ist der Hinweis ein
  Nachklang, keine Echtzeit. Das gehört in den Gesprächskatalog (T2).

Gebaut wird das erst auf dem Ablaufkern aus Abschnitt 12 (T1) — sonst
ist jede dieser Regeln wieder nur am Gerät zu prüfen.

## 12. Teststrategie: die Prüfleiter (2026-11-11)

*Anlass (Betreiber, 2026-11-10): „Ich muss ziemlich viel selbst auf der
realen Hardware testen … meine Erwartung ist eigentlich, dass alle
Anwendungsfälle sauber abgetestet werden können." Und 2026-11-11: „ein
sauber aufgearbeitetes Setup / Skill / Toolkit, um möglichst die ganze
Kette zu testen." Der Vorschlag vom 2026-11-10 (T1–T7) ist hier zur
Leiter geordnet; die T-Nummern stehen in Klammern. Gebaut sind S0 und
S1, dazu das Szenario im Vorführmodus.*

### 12.1 Was erreichbar ist — und was nicht

Kein Simulator sieht Garmin Connect (Laufzeit, Hintergrund, `SUCCESS`
bei geschlossener App), Akku, Sonne und GPS im Wald. „Keine Fehler im
Feld" ist deshalb kein Ziel, das sich halten lässt. Das Ziel ist:

1. **Im Feld wird gemessen, nicht gesucht.** Was dort schiefgehen kann,
   ist eine Zahl aus Abschnitt 8, kein Ablauf.
2. **Jeder Ablauf ist geprüft, bevor die Uhr am Arm ist** — auf der
   Stufe, die ihn am billigsten findet.
3. **Jeder Feldbefund wird ein Skript** (Fahrtenschreiber, #510) und
   bleibt als Test.

Warum bisher so viel am Gerät landete:

- Die Unit-Tests prüfen Bausteine (`NavTracker`, `RideLog`,
  `PhoneRoute`, `RideStats`). Der **Ablauf** — welche Taste in welchem
  Zustand was tut, welche Frist läuft, was ans Handy geht — steht in
  `TrailBuddyApp.mc` und ist nur über den Vorführmodus erreichbar.
- Tasten und Menüs ließen sich im Simulator nicht von außen drücken
  (`garmin/CLAUDE.md`, „Aufzeichnung an der Uhr").
- Die Fake-Uhr der Dart-Tests antwortet sofort und verliert nichts; die
  Feldbefunde 8.2, 8.7 und 8.8 waren aber Laufzeit und Verlust.
- **Die Kette selbst** — Dart, Kotlin-Brücke, Companion-SDK, Uhr-App und
  zurück — prüfte nichts. Der R8-Absturz von 0.150.0 und die veraltete
  `.prg` vom 2026-11-04 lagen genau dort.
- Das Aussehen prüft niemand automatisch.
- Die Fälle in `docs/watch_cases.json` waren nach Issue geordnet, nicht
  nach dem, was jemand im Feld tut.

### 12.2 Die Leiter

| Stufe | Was | Findet | Wo | Stand |
|---|---|---|---|---|
| S0 | Dart-Tests gegen die Fake-Uhr (`test/garmin/`) | Logik am Handy, Kodierung | CI | da |
| S1 | Monkey-C-Unit-Tests (`garmin/source/Tests.mc`) | Bausteine der Uhr | 💻, CI als Versuch (T6, #512) | da |
| S2 | **Ablaufkern**: Ereignis-Skripte gegen den Zustandsautomaten (T1, #508; `WatchCore.mc`, Tests in `CoreTests.mc`) | Tasten, Menüs, Fristen, Reihenfolgen | 💻 | da |
| S3 | **Gesprächskatalog** für beide Seiten und die Fake-Uhr mit Kanalmodell (T2, T3, #509) | Protokoll-Drift, Laufzeit, Verlust, geschlossene App | CI (Handy, Frische der Uhr-Seite), 💻 (Uhr) | da |
| S4 | **Dart-Abbild der Ansicht** mit Golden-Tests (T5, #511) | Aussehen, Textlängen, andere Größen | CI | offen |
| S5 | **Kettenstand**: Android-Emulator und Simulator, verbunden über adb (T7, #527) | Brücke, Kotlin, SDK, beide Apps zusammen | 💻 | da (`tool/garmin_bench.sh chain`) |
| S6 | **Tischabnahme**: Release-Bau am Pixel 7 Pro und fēnix 5, als Skript (#527) | Garmin Connect, R8, Hintergrund, alter Stand auf der Uhr | 📱, ~10 min | offen |
| S7 | Feld | Messungen 8.3–8.6, 8.9 | 📱 | — |

Dazwischen bleibt der Vorführmodus mit `tool/garmin_scenario.sh`. Seit
S2 (#508) spielt er nur noch, was die Ansicht braucht: die Szenen, eine
Route in Stücken, die Frage auf der Karte und den Wechsel danach — die
Abläufe (Rückfrage, freie Fahrt, Tasten, Fristen) prüft der Ablaufkern.

**Der Ablaufkern** (`garmin/source/WatchCore.mc`): nimmt Ereignisse an
(Taste, Menüpunkt, eigener Fix, Nachricht vom Handy, Ergebnis einer
Übertragung, Takt) und wirkt nur über den Wirt — `TrailBuddyApp` auf
der Uhr, `FakeHost` im Test — und die Ansicht. Kein Timer darin: Jede
Frist ist ein Zeitpunkt, den der Takt gegen „jetzt" vergleicht, und der
Test stellt die Uhr vor. Gemessen 2026-11-11 (fēnix 5, Simulator): Code
im Release-Bau 62 236 → 62 556 Byte (+320); belegt im Vorführmodus mit
1000 Punkten 101,8 KB → 98,0 KB (der Vorführmodus ist dabei kleiner
geworden). Der Umbau fand selbst einen Fehler, den nur der Vorführmodus
zeigte: Dekodiert der Kern die neue Route im selben Takt wie den
Wechsel, hält die alte Ansicht noch die alte Route — „Out of Memory" bei
1000 Punkten. Der Takt des Wechsels endet deshalb dort; ein Unit-Test
wacht darüber (Fall 508.9).

**Der Gesprächskatalog** (S3, #509): `docs/watch_cases.json` →
`gespraeche`, je Gespräch die Schritte beider Seiten (wer sendet was,
welche Handlung löst es aus, wie viel Zeit vergeht, welcher Stand dann
gilt; die Form in `gespraeche_form`). Die Seite des Handys spielt
`test/garmin/watch_talks_test.dart` gegen den echten `WatchSync` und
`WatchRideInbox`; die Seite der Uhr steht erzeugt in
`garmin/source/GeneratedTalks.mc` (`tool/watch_talks.py`, Frische über
`tool/generated_assets.py` in CI) und läuft mit dem Spieler `TestTalk`
in `CoreTests.mc` gegen den Ablaufkern — im Takt, den der Kern beim
Wirt verlangt. Jede Art Nachricht beider Richtungen muss in einem
Gespräch vorkommen (Fall 509.1); ein umbenannter Schlüssel ist auf der
sendenden Seite rot. Das Kanalmodell (`WatchChannel` in
`test/fakes/fake_garmin.dart`, ab Werk aus) gibt der Fake-Uhr die
gemessenen Laufzeiten (3,5 s je kleiner Nachricht, 14,5 s je Stück),
die geschlossene App, die trotz `SUCCESS` nichts bekommt, Verlust und
Abbruch mittendrin; `test/garmin/watch_channel_test.dart` stellt damit
die Befunde 8.2, 8.7 und 8.8 nach. Der erste Lauf fand einen Fehler
der Uhr: Ein „schick" (`wq`) während des Wartens auf das Handy verfiel,
die Fahrt ging erst beim nächsten Start (Fall 509.7).

**Die Regel der Leiter:** Ein Fehler, der auf Stufe n gefunden wird,
bekommt seinen Test auf der niedrigsten Stufe, die ihn hätte finden
können. Findet ihn erst S6 oder S7, ist das ein Loch in der Leiter und
steht im PR.

### 12.3 Der Kettenstand (S5)

Was er ist: beide Apps echt, nur Garmin Connect und der Funk fehlen.

- **Handy:** der Android-Emulator mit der Dev-App,
  `--dart-define=GARMIN_TETHERED=true` — das Companion-SDK spricht dann
  über adb statt über Garmin Connect (Abschnitt 3). `adb forward
  tcp:7381 tcp:7381`. Bisher lief das nur am echten Pixel von Hand; der
  Weg ist derselbe.
- **Uhr:** der Connect-IQ-Simulator mit einem Bau, der wirklich sendet
  (`nosim`), und einer neuen Annotation **`(:bench)`**, die der normale
  Bau ausschließt wie `demo`. Im Bench-Bau nimmt die Uhr über den
  normalen Kanal zusätzlich **Ereignisse** — Taste (`_k`), Fix (`_f`),
  Zeitsprung (`_t`) — und meldet ihren Ansichtszustand (`_s`). Das
  umgeht das Tastenproblem und sitzt auf dem Ablaufkern (#508): Es ruft
  dessen `startKey`/`backKey`/`tick`.
- **Treiber:** ein `integration_test` auf dem Emulator mit der echten
  `GarminBridge`; alles andere kommt aus den Fakes. Das GPS des Handys
  per `adb emu geo fix` aus einer **erfundenen** Spur
  (`tool/garmin_route.py`, A7 — nie eine echte Fahrt).
- **Erste Runden:** hallo → Route in Stücken → `ok`; START an der Uhr →
  das Handy nimmt mit auf; Abkommen → Umplanen → Frage → Annahme nach
  der Frist; Fahrt hinüber → `wk`.

**Der Versuch (2026-11-11, Branch `spike/watch-chain-bench`): 20 von 20.**
Die Runde „Route → `ok`" lief zwischen dem Android-Emulator und dem
Simulator zwanzigmal hintereinander durch, je rund 0,2 s; „hallo" auf `q`
ebenso. Das Kriterium (ab 19 von 20) ist erfüllt — S5 wird eine Stufe der
Leiter. Gemessen ist eine Sitzung mit einer Route aus einem Stück; mehrere
Stücke, lange Läufe und der Neuaufbau der Verbindung stehen noch aus.
Dass die Verbindung bisher als wackelig galt („gut für `status` und
`send`, nicht für Quittungen"), hatte zwei Gründe, beide gefunden:

- **Der Simulator meldet seine App ohne Kennung.** Der Empfang
  (`registerForAppEvents`) muss im Tethered-Modus für `IQApp("")`
  angemeldet sein; mit unserer Kennung kam nie eine Nachricht der Uhr an,
  obwohl die Uhr `ok` sendete und der Simulator das Senden bestätigte.
  Aus demselben Grund sagt `openApplication` dort `APP_IS_NOT_INSTALLED`
  — das bleibt so und ist im Kettenstand kein Fehler.
- **Die Reihenfolge beim Start.** Ein Bau, der wirklich sendet (`nosim`),
  sagt beim Start „hallo". Steht die adb-Verbindung dann noch nicht,
  öffnet der Simulator einen Dialog und nimmt keine App mehr an. Also:
  erst die Handy-App (das SDK lauscht nach dem ersten `status`), dann
  „adb Connection → Start", dann die Uhr-App laden.

Der Klick im Menü des Simulators geht über System Events, auch ohne das
Fenster nach vorn zu holen. Der Treiber braucht `integration_test` als
Abhängigkeit und die Änderung in `GarminBridge.kt` — beides geht ins
Binary bzw. in `pubspec.yaml`, also mit Bump in den PR zu #527.

**Gebaut (#527, 0.168.2):** `tool/garmin_bench.sh chain` startet den
Emulator (ohne Fenster), baut die Uhr mit `--bench`, startet den
Simulator frisch, hält die Reihenfolge ein und druckt je Schritt OK oder
FEHLT. Der Treiber ist `integration_test/watch_bench_test.dart`, die Uhr
nimmt im Bench-Bau `_k` (Taste, Menüpunkt), `_f` (Fixe, einer je
50 ms), `_t` (Zeitsprung), `_x` (eine Art nie senden) und antwortet mit
`_s` (Stand); Menüs zeigt sie dort nicht an, `_s` sagt, welches stünde.
Ein Lauf, gut 3 min mit gebautem Treiber (2026-11-11, grün):

1. hallo auf `q` (7–9 s inkl. Verbindungsaufbau);
2. fünfmal eine Route in zwei Stücken → `ok`, je 9,1 s (Streuung unter
   10 ms — der feste Schlaf des SDK je Nachricht, keine Feldzeit);
3. die Frage nach der neuen Linie läuft ab, sie lädt;
4. START → `rs`, Fixe, Pause → `rp` mit dem Menü, Weiter → `rr`;
5. weit neben der Linie → `d`;
6. eine neue Linie während der Fahrt → `ok`, die Frage, nach der Frist
   genommen, die Aufzeichnung läuft weiter;
7. Speichern → `re`, die Fahrt in Nachrichten (41 Punkte, dekodiert),
   `wk` → die Uhr schickt sie nicht noch einmal.

`chain --break` lässt die Uhr nie `ok` senden und ist grün, wenn die
Kette bei Runde 1 rot wird. Die Schritte hängen als Prüfweg `kette` an
den Fällen 527.1–527.7 und darüber an F1–F4 (`docs/watch_cases.json`).
Zwei Fallen des Prüfstands selbst, beide behoben: Alle Fixe in einem
Ereignis brachen den Watchdog (am Gerät kommt einer je Ereignis), und
der Simulator behält den Speicher der Uhr — eine Fahrt aus einem
abgebrochenen Lauf kam als laufende Aufzeichnung zurück. Der Bench-Bau
löscht deshalb beim Start alles.

Was S5 nie zeigt: die 3,5 s je Nachricht, `SUCCESS` bei geschlossener
App, Android, das die App schlafen legt (#524), R8. Dafür S3 und S6.

### 12.4 Die Tischabnahme (S6)

Zehn Minuten am Schreibtisch statt einer Fahrt, mit dem, was wirklich
auf die Geräte geht: Release-Bau (R8) am Pixel 7 Pro, der Uhr-Bau auf
der fēnix 5. `tool/garmin_bench.sh device` sagt jeden Schritt an, liest
`adb logcat` nach `TB-GARMIN` und druckt je Schritt OK oder FEHLT:

1. Build-Stempel der Uhr stimmt mit dem Stand überein (sonst ist die
   neue `.prg` nicht drauf).
2. `status` findet die Uhr, `open`, „hallo" mit der richtigen Fassung.
3. Route in Stücken, `ok`; dieselbe noch einmal bleibt still.
4. START an der Uhr → `rs`, das Handy nimmt auf; Pause, Weiter.
5. Bildschirm zehn Minuten aus, dann START an der Uhr (#524).
6. Speichern → Fahrt hinüber → `wk`, die Fahrt steht in „Meine Fahrten".

**Pflicht vor jeder Beförderung**, die `lib/features/garmin/`,
`GarminBridge.kt` oder die Uhr-App berührt. Bis das Skript die Schritte
selbst liest, ist es die Liste im Skill `watch-bench`.

### 12.5 Feldszenarien als Maß der Abdeckung

`docs/watch_cases.json` hat neben den Fällen die **Szenarien F1–F8**
(`konzept-geraete.md` 9): je Szenario die Schritte, die ein Fahrer tut.
Jeder Schritt nennt entweder Fälle mit Prüfung, eine Messung am Gerät
oder das Issue, das ihn noch schuldet. `tool/watch_scenarios_check.py`
(CI, „Analyze & Test") macht rot, wenn ein Schritt nichts davon hat
oder ein genannter Fall fehlt; mit `--online` (so ruft es
`tool/garmin_bench.sh cases`) auch, wenn ein als offen genanntes Issue
schon zu ist. Es druckt je Szenario, wie viele Schritte geprüft, zu
messen und offen sind. So sieht man vor einer Fahrt, was sie beweisen
soll — und was nicht.

### 12.6 Werkzeug

- **Ein Einstieg:** `tool/garmin_bench.sh` — `cases` (die Abdeckung der
  Szenarien), `unit` (S1), `scenario` (Vorführmodus), `chain` (S5),
  `device` (S6), `all`. Es räumt hängende `monkeydo`- und
  Simulator-Prozesse vorher weg und sagt, was auf diesem Rechner fehlt.
- **Der Skill `watch-bench`** (`.claude/skills/`): welche Stufe eine
  Änderung braucht, die Befehle, die Gegenprobe und die bekannten Fallen.
- **Wer an der Uhr etwas ändert**, trägt den Fall in
  `docs/watch_cases.json` ein, bevor er baut, und hängt ihn an den
  Schritt eines Szenarios.

### 12.7 Reihenfolge und Risiko

#508 zuerst, der Versuch zu #527 parallel, dann #509; #511, #510 und
#512 danach, wie es passt.

Risiko von S2: Der Code der Uhr-App teilt sich 124 KB mit der Route.
Der Ablaufkern verschiebt Code, er verdoppelt ihn nicht; gemessen wird
vorher und nachher (`--demo`, Speicher in der Konsole), höchstens 2 KB
mehr.

**Wann S2 als gelungen gilt**: Ein Ablauf, der heute nur am Gerät zu
prüfen ist — Pause, Menü, „Verwerfen", Rückfrage —, läuft als Unit-Test,
und eine Gegenprobe macht ihn rot.

**Am Gerät bleibt danach**, was nur dort geht: Akku (8.3), Lesbarkeit in
der Sonne (8.4), GPS im Wald (8.5), Speicher unter Last (8.6), das Netz
im Umkreis (8.9) — Messungen, keine Fehlersuche.
