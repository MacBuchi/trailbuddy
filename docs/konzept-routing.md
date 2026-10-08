# Konzept: Routing-Engine — Anforderungsprofil und Plan

*Entwurf vom 2026-10-01 für #35 (Messung) und #158 (Trail-zuerst-Planer).
Antwort auf die Betreiberfrage vom selben Tag: „Macht ein Zusatztool wie
BRouter Sinn? Besser wäre eine eigene Engine." — und auf die Auflage,
VOR dem Bauen einen sauberen Plan mit Anforderungsprofil zu machen.
Zahlen in diesem Dokument sind Vorschläge, solange Abschnitt 8 sie
nicht als entschieden führt; was die Messung (#35) klären muss, steht
in Abschnitt 6. Dieses Dokument ergänzt `konzept-trails.md` Abschnitt 9
und 13; bei Widerspruch gilt das Hauptkonzept.*

## 0. Die Entscheidung: eigene Engine, kein BRouter

Entschieden vom Betreiber am 2026-10-01. Die Gründe, damit die nächste
Diskussion nicht bei null beginnt:

- **BRouter ist eine zweite App.** Locus ruft sie über eine
  Schnittstelle; sie muss getrennt installiert und mit eigenen
  Segmentdateien (5°×5°, von brouter.de) versorgt werden. Für TrailBuddy
  hieße das: nur Android, ein neues Netzziel, ein zweiter Datenstand
  neben unseren Kacheln — ein Weg wäre auf der Karte da und im Router
  nicht, oder umgekehrt. Im Web gibt es BRouter nicht, und die Web-App
  soll gleich viel können.
- **BRouter beantwortet die falsche Frage.** Es rechnet von A nach B.
  Der Planer braucht die Aufstiege zwischen ALLEN Trail-Enden und
  verkettet sie unter einem Budget; „möglichst viele meiner Trails
  mitnehmen" kann kein BRouter-Profil ausdrücken. Als Zulieferer für die
  Einzelaufstiege wäre es hunderte Anfragen an eine fremde App.
- **Der Wegegraph liegt schon auf dem Gerät.** Die gespeicherten
  Bereiche tragen die Wege bis Zoom 13, und das Zerlege-Blatt liest sie
  (`road_index.dart`). Eine eigene Engine ist damit offline von Geburt
  an, läuft auf beiden Plattformen und braucht keinen neuen Host.
- **Was fehlt, ist überschaubar:** ein A* mit Kostenfunktion (einige
  hundert Zeilen Dart), ein Höhenmodell (Copernicus-DEM, ohne
  Bibliothek lesbar — am 2026-10-01 geprüft), und die Messung, ob die
  Kacheln als Wegenetz REICHEN (Abschnitt 6). Fällt die Messung durch,
  liegt die Antwort in der eigenen Pipeline (`map-data.yml`), nicht in
  einem Fremdprogramm.

Valhalla und jeder Server-Router scheiden aus demselben Grund aus wie
bisher: kostet Geld und ist im Funkloch tot, wo geroutet wird.

## 1. Was die Engine tun soll — und was nicht

Zwei Funktionen, eine Engine:

1. **Zum Trailkopf, offline** (#158 Schritt 4). Vom eigenen Standort
   oder einem getippten Punkt zum Anfang EINES Trails, als Aufstieg nach
   Wegklasse bewertet. Ergebnis: Linie auf der Karte, Länge, Höhenmeter,
   geschätzte Zeit, Anteil Wanderweg. Ersetzt die Übergabe an die
   Navi-App (#151) nicht, sondern ergänzt sie: Die Navi-App kennt die
   Straße zum Parkplatz, die Engine kennt den Forstweg vom Parkplatz zum
   Trailkopf.
2. **Die Trail-zuerst-Runde** (#158 Schritt 5). Start (und wahlweise
   Ziel = Start), Budget, Pool. Ergebnis: eine Runde, die möglichst viele
   sichtbare Trails BERGAB in ihrer Richtung mitnimmt, verbunden durch
   Aufstiege mit möglichst wenig verschenkter Höhe. Gespeichert als
   geplante Fahrt (`planned`, Konzept 5.2), exportiert als GPX (#150).

Nicht-Ziele, damit sie nicht hineinwachsen:

- **Keine Abbiegehinweise, keine Sprachausgabe** (Konzept 13). Die
  Runde geht als GPX an die Navi-App des Nutzers. **Erlaubt seit
  2026-10-05 (#232) ist ein Navigationsmodus, der nur ZEIGT:** Karte in
  Fahrtrichtung gedreht, eigene Position, Route und Abstand zur Linie,
  eine Dauerbenachrichtigung über den `location`-Dienst der Aufzeichnung
  und ein Bild-im-Bild-Fenster (Android PiP — nicht
  `SYSTEM_ALERT_WINDOW`, das Play nur eng zulässt). Sein Abschnitt in
  diesem Dokument kommt vor dem ersten Code.
- **Kein Routing über fremde Gegenden.** Gerechnet wird nur, wo ein
  gespeicherter Bereich liegt; ohne Bereich sagt das Blatt das und
  bietet die Übergabe an. Seit 0.74.0 über die Kacheln, die DA sind,
  auch wenn sie den Rahmen nicht ganz füllen (2.7) — die Wege außerhalb
  kennt die Engine offline weiter nicht. **Die eine Ausnahme seit
  0.78.0 (#187):** Mit Empfang ergänzt der Kartenhost die fehlenden
  Kacheln des Rahmens (2.7, letzter Punkt); dann geht eine Runde auch
  ganz ohne Bereich, und das Blatt sagt, wie viele Kacheln online kamen.
  „Fremd" heißt damit: ohne Bereich UND ohne Empfang — oder abgeschaltet.
- **Kein Urteil über Erlaubnis** (Konzept 7). Die Engine plant über
  Wanderwege, wenn der Aufschlag trotzdem gewinnt, und SAGT es. Sie
  sagt nie, dass ein Weg befahren werden darf.
- **Ein Wanderweg als Verbindung ist kein Trail.** Die Engine darf
  über Wanderwege verbinden, bergauf und — teurer — bergab (Betreiber:
  „auch bergab, wenn's Sinn macht"). Das Stück heißt im Ergebnis
  „Wanderweg", wird nie als Trail beigesteuert und bekommt keinen
  S-Grad; die Linie, die Konzept 7 nicht erzeugen will, entsteht nur,
  wenn jemand sie fährt und beisteuert — und das ist dann seine
  Entscheidung.
- **Keine Daten anderer Nutzer** (Konzept 12): Gerechnet wird über die
  sichtbaren Trails des Aufrufers, auf dem Gerät, nie auf dem Server.

## 2. Anforderungsprofil

### 2.1 Fahrerprofil: Bio-Bike oder E-Bike

**Zwei Profile nebeneinander, jedes mit eigenen Parametern** —
viele fahren beides (Betreiber, 2026-10-01). Gerätelokal: das aktive
Profil (`Settings.riderProfile`, Vorgabe **Bio-Bike**, umschaltbar im
Profil und im Planer-Blatt) und je Profil ein Parametersatz. Die Werte
beginnen mit den Vorgaben unten und **lernen aus den eigenen Fahrten**
(Abschnitt 5, Schritt 6): Jede Aufzeichnung merkt sich beim Start das
aktive Profil (`Ride.profile`), die Kalibrierung rechnet je Profil;
Fahrten ohne Profil (vor diesem Schritt) lernen nichts. Fahrten aus
anderen Apps übernimmt der GPX-Import mit einem gewählten Profil in
„Meine Fahrten" (seit 0.82.0, #188) — dann lernen sie mit, mit den
Höhen der Datei. Wer die
gelernten Werte nicht will, setzt sie im Profil auf die Vorgaben
zurück. Das Profil ändert drei Dinge und sonst nichts:

| | Bio-Bike | E-Bike |
|---|---|---|
| Steigrate Forstweg | 450 hm/h | 850 hm/h |
| Steigrate Pfad (fahrend) | 350 hm/h | 650 hm/h |
| Schieben/Tragen (Steig, Stufen) | 300 hm/h, 3 km/h | 220 hm/h, 2,5 km/h |
| Aufschlag Wanderweg bergauf | ×1,4 | ×2,0 |
| Vorgabe Höhenmeter-Budget | 800 hm | 1 400 hm |

Warum der E-Bike-Aufschlag höher ist: Das Rad wiegt 25 kg; was beim
Bio-Bike ein kurzes Schiebestück ist, ist beim E-Bike der Grund, die
Runde nicht noch einmal zu fahren. Das Profil ändert NICHT die
Wegerechte und NICHT die Trail-Seite: Bergab ist ein S2 ein S2.

Die Raten sind Startwerte (Konzept 9: „Aufstieg 400–600 hm/h, Abfahrt
nach Trail-Länge"). **Kalibriert werden sie aus den eigenen Fahrten auf
dem Gerät** (Abschnitt 5, Schritt 6): Die Fahrten tragen Zeit und
GPS-Höhe je Punkt; aus Aufstiegsabschnitten auf Forstwegen folgt die
eigene Steigrate. Nie aus Fahrten anderer.
**Gebaut (0.73.0) so:** auf Knopfdruck („Aus meinen Fahrten lernen"
unter „Fahrerprofil"), nicht nach jeder Fahrt — das Einordnen liest die
Kacheln der Bereiche. Je Fahrt mit Profil und Höhen die Aufstiege ab
100 hm am Stück (median-geglättet über 7 Punkte, Ende nach 15 m
Abfall — die Regel des Werkzeugs), je Aufstieg die dominante Wegklasse
unter der Spur (alle 5 m der nächste Weg in 15 m), die Rate nur über
fünf Minuten; dazu flache Stücke zwischen den Aufstiegen (≥ 500 m, An-
und Abstieg je unter 2 % der Länge, auf Forstweg oder Straße) als
Flachgeschwindigkeit. Gelernt wird der Median je Gruppe (Forstweg und
Straßen → Steigrate Forstweg; Wanderweg und Fußweg → Pfad; Stufen →
Schieben), erst ab drei Messungen und nur in einer plausiblen Spanne
(150–1 500 hm/h, 8–30 km/h); was fehlt, bleibt Vorgabe. Aufschläge und
Budget-Vorgabe lernen nicht. Eine Fahrt, deren Bereich fehlt, kann
nicht eingeordnet werden und lernt nichts — dafür baut der Loader
auch einen HALBEN Graphen (`requireComplete: false`, nur hier).

### 2.2 Zeitmodell

Die Zeit je Kante ist eine Summe aus Strecke und Höhe (nach dem Muster
der Wanderzeit-Formeln, nicht aus einer Geschwindigkeit allein — eine
Geschwindigkeit „12 km/h bergauf" ist am Hang falsch und im Flachen
auch):

    t = L / v(Klasse, Richtung) + max(0, Δh) / Steigrate(Profil, Klasse)

| Klasse / Lage | v (km/h) Bio | v (km/h) E-Bike |
|---|---|---|
| Forstweg, Nebenstraße, flach | 15 | 20 |
| Pfad bergauf (fahrend) | 8 | 10 |
| Steig, Stufen (schiebend) | 3 | 2,5 |
| Straße/Forstweg bergab | 25 | 25 |
| Trail bergab S0 / S1 / S2 / S3 / S4+ | 16 / 12 / 9 / 6 / 4 | gleich |
| Trail ohne Einschätzung bergab | 10 | 10 |

Bergab zählt nur die Strecke (kein Höhenterm), auf Trails über den
S-Grad des Medians (`Trail`-Anzeige, derselbe Wert wie das Schild). Der
Zeitwert ist eine Schätzung und wird so genannt („etwa 2 h 40").

### 2.3 Budget je Planung

Drei Regler im Planer-Blatt, jeder mit Vorgabe; der engste gewinnt:

| Regler | Vorgabe | Spanne | Schritt |
|---|---|---|---|
| Höchstens Zeit | 3 h | 1–6 h | 30 min |
| Höchstens Höhenmeter bergauf | 800 hm (Bio) / 1 400 hm (E) | 200–2 500 | 100 |
| Höchstens Wanderweg (bergauf und bergab) | 2 km | 0–10 km („kein Wanderweg" = 0) | 0,5 km |

Dazu „Start ist auch Ziel" (Vorgabe AN — eine Runde) und wahlweise ein
Zielpunkt. Die Vorgaben merkt sich das Gerät mit der letzten Planung.
Eine Reserve von 10 % auf die Zeit bleibt eingebaut (die Schätzung
kennt keine Pausen).

### 2.4 Wegklassen und Kosten

Die Engine kennt Kanten aus zwei Quellen: **Wege** aus der
`roads`-Ebene der Kacheln (`kind` + `kind_detail` + `access` +
`oneway`) und **Trails** aus dem sichtbaren Netz. Jede Wegekante bekommt
eine Klasse; die Klasse bestimmt Geschwindigkeit, Steigrate, Aufschlag
und ob die Kante überhaupt gilt.

| `kind` / `kind_detail` | Klasse | Aufschlag bergauf | Aufschlag bergab | Bemerkung |
|---|---|---|---|---|
| `path` / `track` | Forstweg | 1,0 | 1,0 | Grundlinie — „Schotter/Waldweg bevorzugt" |
| `path` / `cycleway` | Radweg | 1,0 | 1,0 | |
| `minor_road` / `unclassified`, `residential`, `living_street` | Nebenstraße | 1,2 | 1,2 | Asphalt, Verkehr |
| `minor_road` / `service` (ohne `driveway`, `parking_aisle`) | Zufahrt | 1,2 | 1,2 | Almzufahrten sind oft `service` |
| `path` / `path`, `bridleway` | Wanderweg | 1,4 (Bio) / 2,0 (E) | 2,0 (Bio) / 2,5 (E) | zählt in beide Richtungen gegen „höchstens Wanderweg" |
| `path` / `footway`, `pedestrian` | Fußweg | 2,0 | 2,5 | im Ort als Lücke brauchbar |
| `path` / `steps` | Stufen | 3,0, schiebend, + 60 s je Treppe | 3,0, schiebend | nur als letzte Brücke; bergauf wird getragen (#210) |
| `medium_road` (tertiary) | Landstraße | 1,6 | 1,6 | |
| `major_road` / `secondary` | Hauptstraße | 2,5 | 2,5 | |
| `major_road` / `primary` | Bundesstraße | 4,0 | 4,0 | nie ausgeschlossen (#158) |
| `highway` (motorway, trunk) | — | gesperrt | gesperrt | |
| `access` = `private`, `no` | — | gesperrt | gesperrt | |
| `other` (Rennstrecken, Pisten) | — | gesperrt | gesperrt | |
| `oneway` | — | nur auf Straßenklassen beachtet | | Forstwege und Pfade in beide Richtungen |

Wanderwege bergab sind erlaubt, „wenn's Sinn macht" (Betreiber): Der
Aufschlag ist so gesetzt, dass ein Forstweg mit der eineinhalbfachen
Länge gewinnt und erst ein deutlich längerer Umweg den Wanderweg
rechtfertigt. Bergab auf einem Wanderweg fährt man im Zeitmodell wie
auf einem Trail ohne Einschätzung (10 km/h), und der Abschnitt steht
im Ergebnis mit Richtung („1,2 km Wanderweg bergab").

Kosten einer Wegekante = geschätzte Zeit × Aufschlag. Der Aufschlag
drückt aus, was die Zeit nicht sagt: Eine Bundesstraße ist nicht
langsam, sie ist falsch. **Bergab auf Wegen kostet zusätzlich die
verschenkte Höhe**: Jeder Meter, den eine Wegekante bergab geht, muss
wieder erstiegen werden, bevor der nächste Trail kommt — er geht als
„verschenkte Höhenmeter" in den Vergleich zweier Pläne und ins Blatt
(„120 hm auf Forstweg verschenkt").

**Stufen bergauf kosten einen festen Aufschlag** (#210, seit 0.87.0,
Betreiber: „Treppen bergauf stark meiden — da wird getragen"): 60 s
Kosten je Stufen-Kante, die steigt, unabhängig von ihrer Länge — Tragen
ist ein Halt, kein langsameres Tempo, und eine kurze Treppe gewann bis
dahin gegen jeden Umweg unter 0,8 km Forstweg (Bio, 20 m mit 4 hm);
jetzt erst ab rund 1 km. Bergab und ohne Höhen nichts; „Wanderwege:
egal" macht ihn nicht billiger. Wird eine Kante geteilt (ein angehefteter
Trailkopf), teilt sich der Aufschlag nach Länge, sonst zählte eine
Treppe doppelt. Kosten, nicht Zeit; ob die Zahl trägt, zeigt die
Feldprüfung in #188.

**Steile Anstiege kosten extra** (#194 seit 0.80.0, seit 0.81.0 als
Kurve, #188; gemessen in `docs/routing-messung.md`): Jeder Höhenmeter
einer Kante kostet seine Steigzeit noch einmal, mal ein **Gewicht, das
mit der Steigung exponentiell wächst** (Betreiber: „sehr steil bergauf
wird exponentiell teurer") — unter **10 %** nichts, dann je fünf
Prozentpunkte etwa ×3 bis ×4: 0,14 bei 15 %, 0,57 bei 20 %, 1,9 bei
25 %, 5,7 bei 30 %, höchstens 30 (`steepWeightAt`). Die Steigung je
50-m-Schritt, Höhen und Positionen über drei Proben geglättet (sonst
ist es Rauschen des 90-m-Modells), in jeder Richtung für sich. Dazu mal
**3** unbefestigt (Forstweg, Wanderweg, Fußweg), mal **1** auf Asphalt
(Radweg, Straßen), auf Stufen nichts. Die Kacheln kennen keinen Belag;
die Klasse ist die Näherung. Uphill-Trails und Verbinder (#185) tragen
keinen Aufschlag. Er ist Kosten, nicht Zeit — die geschätzte Zeit und
die Kalibrierung bleiben unberührt. Bis 0.80.x zählten nur die Meter
über 15 % (ab da ein Sprung); die 15 % bleiben, was das Ergebnis
„steil" nennt: Es sagt es, wenn die Route trotzdem steile Stücke hat (ab
5 hm über der Grenze), ohne Zahl — gezählt ist nur, was über der Grenze
steigt, und „12 hm steil" läse sich wie die Länge der Rampe.

**Schlechte Wege kosten bergauf** (#213, seit 0.92.0, Vorschlag des
Betreibers 2026-10-02; gemessen in `docs/routing-messung.md`): Forstwege
und Wanderwege bekommen ihre Güte aus dem Wege-Archiv (#212, Format 2;
per Geometrie, 3 m, Mehrheit der Proben je 10 m), aus den Bereichen und
— für online nachgeladene Kacheln — vom Host. Abgestuft, nie ein
Schalter, Kosten, nicht Zeit:

| Weg | bergauf und eben | bergab |
|---|---|---|
| Forstweg gut / mittel / ohne Güte | wie bisher | wie bisher |
| Forstweg schlecht (grade4) | Steigteil ×1,3, Strecke ×1,15 | nichts |
| Forstweg sehr schlecht (grade5, holprig, Matsch) | Steigteil ×2, Strecke ×1,3 | nichts |
| Pfad schwer (S3/T3) | geschoben (`push_rate`, `v_push`) | nichts |
| Pfad sehr schwer (ab S4/T4) | doppelt geschoben | nichts |
| Pfad mit `mtb:scale:uphill` | 0–1 wie jeder Pfad, 2 Steigteil ×1,5, 3 geschoben, ab 4 doppelt | nichts |

`mtb:scale:uphill` geht vor der Klasse, wo es steht (nur 2 % der Pfade).
Unbekannt ist bei Pfaden der Normalfall und kostet, was es kostete. Die
eigenen Fahrten des Betreibers klettern zu 3 % auf schlechten Forstwegen,
die im Netz drumherum 19 % ausmachen; der Plan ohne Güte nahm 8–10 %,
mit ihr 4 %. Die Kosten der Fahrt gegen den Plan bleiben gleich (Median
1,37 → 1,36 Bio, 1,30 → 1,28 E). Ein vierter Schalter („schlechte Wege
egal") erst, wenn das Feld danach fragt.

**Verschenkte Höhe kostet** (seit 0.81.0, #188, Betreiber: „Bergab ist
teurer"): Ein Höhenmeter bergab auf einer Wegekante kostet **0,3**
seiner Steigzeit — er muss wieder hinauf, bevor der nächste Trail
kommt. Auf Trails und Verbindern nichts: Dafür sind sie da.

**Die Vorlieben** (seit 0.81.0, #188): drei Schalter in den Parametern
des Planers, gemerkt in `LoopPrefs`, gültig für die Runde UND den Weg
zum Trail — **Straßen meiden**, **Wanderwege bergauf meiden**, **steile
Rampen meiden**. Ab Werk alle an, also die Zahlen oben. Aus heißt „egal",
und das ist nie null: Von Straßen- und Wanderweg-Aufschlag bleibt der
Anteil über 1 zu **35 %** (Hauptstraße 1,525 statt 2,5, Wanderweg
bergauf Bio 1,14, E 1,35), vom Steil-Gewicht **30 %**. Mit null nähme
die Route bei gleicher Zeit die Hauptstraße statt des Forstwegs — die
Reihenfolge Forstweg/Radweg < Nebenstraße < Landstraße < Hauptstraße <
Bundesstraße bleibt immer. Die Grenze „höchstens Wanderweg" gilt
unabhängig davon. Gesetzt, nicht gemessen: Die eigenen Fahrten des
Betreibers passen mit „Straßen egal" am besten (Kosten der Fahrt / des
Plans im Median 1,38 statt 1,52), für eine Vorgabe für alle sind 15
Fälle eines Fahrers zu wenig („weiter optimieren kann man erst mit mehr
Fahrdaten").

Trailkanten: nur in Trail-Richtung (`reversed` beachtet), nur bergab
gedacht, Kosten = Zeit nach S-Grad, Gewinn = Trail-Meter. Ein Trail mit
bestätigter warnender Meldung (`Trail.status.warns`) ist aus dem Pool,
solange der Nutzer ihn nicht ausdrücklich hineinnimmt; wartende und
„nur für mich"-Trails sind drin (es ist meine Planung).

### 2.5 Was die Kacheln NICHT tragen — und was daraus folgt

Gemessen am 2026-10-01 an den Feldern der `roads`-Ebene (Protomaps
Basemap 4.14): es gibt `kind`, `kind_detail`, `access`, `oneway`,
`is_bridge`, `is_tunnel`, `service`, `ref`, Namen. Es gibt **keinen
Belag** (`surface`, `tracktype`), keine `mtb:scale`, keine `sac_scale`,
keine `incline`, keine `width`. Drei Folgen:

- **„Forstweg" ist eine Annahme**: `track` heißt in OSM „Wirtschaftsweg",
  das kann Schotter sein oder eine Wiesenspur. Für die Aufstiegsplanung
  trägt das: Die Sorte, die wir suchen (geschoben oder gefahren, aber
  breit), ist fast immer `track`.
- **„Wanderweg" ist eine Spanne** von der Forststraße mit
  `highway=path` bis zum Klettersteig. Ohne `sac_scale` lässt sich das
  nicht trennen. Deshalb der Regler „höchstens Wanderweg" und die
  Nennung im Ergebnis — und deshalb misst #35, wie oft die eigenen
  Fahrten überhaupt über `path` bergauf gehen.
- **Seit #212/#213 trägt das eigene Wege-Archiv** `tracktype`,
  `smoothness`, `surface=mud`, `sac_scale`, `mtb:scale` und
  `mtb:scale:uphill` als Klassen (`tool/way_archive.py`) — der Weg, den
  der nächste Punkt als „nächsten Schritt" beschrieb, als PMTiles statt
  JSON. Die Kosten in 2.4.
- **Wenn die Messung zeigt, dass es nicht reicht**, ist die Antwort
  unsere Pipeline: `map-data.yml` schneidet aus dem Protomaps-Planetbau
  und kann die Felder nicht ergänzen; eine eigene Datei je Region
  (`roads-<build>/<zelle>.json` wie die Orte, aus dem Geofabrik-Extrakt
  mit `surface`, `tracktype`, `sac_scale`, `mtb:scale`) wäre der
  nächste Schritt — auf dem eigenen Host, kein neues Netzziel. Nicht
  vorher bauen.

### 2.6 Höhen

Das Modell hat kein Höhengitter (CLAUDE.md). Die Trails tragen Höhen aus
Aufzeichnungen, die Wege tragen nichts. Zwei Kandidaten, beide aus dem
Copernicus-DEM GLO-90 (offen, ohne Konto, in CI lesbar — geprüft):

- **A — ein Gitter-Asset wie in PilzBuddy** (`elevation_grid.py`: 250-m-
  Waben, 20-m-Stufen, ~3,4 MB für DACH im APK). Offline, ohne neues
  Netzziel, sofort da. Risiko: Auf einer Forststraße in Kehren liegt die
  halbe Steigung in EINER Wabe; die Summe der Höhenmeter über viele
  Waben stimmt grob, die Kante einzeln nicht. Für ein Budget („etwa 800
  hm") reicht ±10 %; ob es das hält, ist Messfrage M3.
- **B — Höhenkacheln je Bereich** vom eigenen Host (1 Byte je 90-m-
  Zelle, ~3 KB je z13-Kachel gezippt), geladen mit dem Bereich wie die
  Orte-Zellen. Genauer, ein zweiter Dateityp, kein neues Netzziel.

Entschieden (Betreiber, 2026-10-01): **A zuerst, „vielleicht reicht es
fürs Routing"; genauer wie bei Locus, wenn nicht.** Locus rechnet mit
SRTM-Höhen in 3 Bogensekunden (~90 m) — das ist genau die Auflösung
von B, also der Weg, der dann offensteht.

**Gemessen am selben Tag (M3, Tirol-Hälfte, `docs/routing-messung.md`):
A reicht nicht.** Entlang der 168 offiziellen Trails mit Abstiegsangabe
trifft das DEM direkt (90 m) die Zahl der Quelle mit 5 % Medianfehler
und 67 % innerhalb ±10 %; das simulierte Gitter A (250-m-Waben, 20-m-
Stufen) liegt bei 42 % Medianfehler und überschätzt den Abstieg um ein
Viertel (Median 1,25) — die Stufen erzeugen entlang einer Linie Treppen,
die die Hysterese nicht wegbekommt. **Gebaut wird B**: Höhenkacheln je
Bereich vom eigenen Host. Die Höhe einer
Kante wird nicht an den Enden, sondern alle 50 m entlang der Linie
abgetastet und mit einer Hysterese von 10 m zu Anstieg/Abstieg summiert
(die 3 m der Trail-Höhen gelten für aufgezeichnete Höhen, nicht für ein
Gitter). Die Trailkanten behalten ihre aufgezeichneten Höhen.

**Gebaut (Schritt 2, seit 0.69.0)** — und nicht als „1 Byte je Zelle",
das war die Schätzung: Ein Byte hielte in einer Alpenkachel mit 2 000 m
Relief nur 8-m-Stufen, also genau die Treppen, an denen A gescheitert
ist. Das Format (`tool/height_tiles.py`, Leser
`lib/features/offline_areas/height_tiles.dart`, Byte für Byte gegen
dieselben Konstanten geprüft):

- **Je z13-Kachel ein 49 × 49-Raster** in ganzen Metern (int16), bei den
  Kachelbrüchen i/48 — die Ränder eingeschlossen, Nachbarkacheln teilen
  ihre Randzeile, die bilineare Ablesung ist über die Grenze stetig.
  Das sind ~70 m zwischen den Proben bei 47° N; das DEM hat 90 m.
- **Delta-kodiert, dann gzip**; NODATA (−32768), wo kein DEM ist. **EIN
  PMTiles-Archiv** `heights-<build>.pmtiles` auf dem Kartenhost mit
  Manifest `heights.json`, gelesen über denselben Range-Weg wie die
  Karte — kein neues Netzziel, und 98 640 Kacheln als ein Objekt statt
  als 98 640 (die Orte sind je Zelle eine Datei, weil sie je Zelle
  geladen werden; Höhen kommen nur mit einem Bereich).
- **Gemessen** (2026-10-01, je eine 1°-Zelle): Alpen (Innsbruck) 2 420
  B je Kachel im Mittel, Flachland (Berlin) 1 361 B; ganz DACH also
  rund 180–240 MB auf dem Host. Ein Bereich „entlang meiner Trails"
  mit 300 z13-Kacheln trägt ~0,7 MB Höhen neben einigen Dutzend MB
  Karte. Der Bau ist CI-Sache (`height-data.yml`, numpy, rund 140
  DEM-Zellen à 5 MB; die Abtastung einer Zelle dauert 2–8 s).
- **Ein Bereich holt seine Höhenkacheln beim Speichern** (zweites
  Archiv neben dem Kartenarchiv, `StoredArea.heightTiles`); Bereiche von
  vor 0.69.0 bekommen sie über „Aktualisieren", und die Liste sagt es
  („Höhendaten verfügbar"). Ohne Höhen-Manifest kommt der Bereich ohne
  Höhen — das ist kein Fehler.
- **Sichtbar wird davon noch nichts**: Die Höhen braucht erst der Graph
  (Schritt 3). Deshalb gibt es dafür keinen Eintrag in „Entdecken";
  der kommt mit dem Planer.
- **Zweite Verwendung seit 0.79.0 (#186)**: das Höhenprofil eines Trails
  ohne aufgezeichnete Höhen, der GPX-Export dazu und die Prüfung der
  Datei-Höhen beim Import (`terrain_heights.dart`, `konzept-trails.md`
  Abschnitt 3). Vom Host über denselben Sitzungsspeicher wie die
  Planung (`OnlineHeights` in `online_fill.dart`), aber für jede
  Kachel — nicht nur für die, deren Wege nachgeladen wurden.

### 2.7 Daten und Offline

- **Der Graph entsteht aus gespeicherten Bereichen**, z13, Ebene
  `roads`, lesbar über denselben Weg wie `loadRoads`. Keine Kachel, kein
  Weg. **Geändert in 0.74.0** (Feldbericht: „teils hat es nicht
  funktioniert ohne sichtbaren Grund"): Bis dahin hieß `partial` „nicht
  planbar" — aber der Rahmen ist ein RECHTECK um Start und Trails, und
  ein Bereich „Entlang meiner Trails" (Kacheln in 1 km um die Trails)
  füllt ihn nie. Der Planer verweigerte damit fast immer, obwohl jeder
  Weg zwischen Start und Trails bekannt war. Jetzt plant die Suche über
  die gefundenen Kacheln (`planning_graph.dart`), und das Blatt sagt
  „Gerechnet über x von y Kacheln — ein Weg außerhalb deiner Bereiche
  kann kürzer sein". Ein halber Plan ist das nicht: Jede Linie liegt
  auf bekannten Wegen; nur ihre Optimalität ist auf den Bestand
  beschränkt. Ohne eine einzige Kachel bleibt es bei „kein Plan".
- **Mit Empfang kommen die fehlenden Kacheln vom Host** (seit 0.78.0,
  #187, `online_fill.dart`; Betreiber, 2026-10-01: „wenn ich online bin,
  kann er doch mit mehr Kacheln rechnen?"). Aus DEMSELBEN Archiv, aus
  dem die Bereiche geschnitten sind (`dach-<build>.pmtiles`, Ebene
  `roads`), dazu je Kachel die Höhenkachel aus `heights-<build>.pmtiles`
  — per Range-Anfrage wie beim Speichern eines Bereichs, also kein neues
  Netzziel. Fünf Regeln:
  - **Die letzte Quelle**: gefragt wird nur, was kein Bereich hat, die
    Kacheln nächst der Mitte des Rahmens zuerst, höchstens
    `kOnlineFillMaxTiles` (75) je Planung — jede Kachel ist eine
    R2-Class-B-Operation (#55), mit Höhen höchstens 150 Anfragen. Höhen
    nur für die nachgeladenen Kacheln; einem Bereich ohne Höhen (vor
    0.69.0) reicht das hier nichts nach.
  - **Nur für die Sitzung**: im Speicher (`OnlineTileCache`, 300 je
    Sorte, die ältesten fallen zuerst), damit ein zweiter Plan dieselbe
    Gegend nicht noch einmal holt. Behalten ist #155.
  - **Ein Netzfehler beendet das Nachladen, nicht die Planung**: Jeder
    Schritt hat 10 s Frist; was bis dahin da ist, wird gerechnet, und
    das Blatt nennt den Grund für den Rest (Grenze, Abbruch, außerhalb
    der Karte — `planningCoverageNote`, EINE Fassung für Runde und Weg).
  - **Ohne Empfang ändert sich nichts** (`noConnectivityProvider`), und
    ohne Manifest auch nicht.
  - **Abschaltbar**: „Fehlende Wege online ergänzen" in den Parametern
    des Planers (`LoopPrefs.fillOnline`, Vorgabe an, gerätelokal), gilt
    auch für den Weg zum Trail — so lässt sich die Offline-Lage zu Hause
    prüfen.
- **Die Trails des Netzes liegen auf dem Graphen** (seit 0.74.0,
  `trail_overlay.dart`, #174/#185). Eine Kante, deren Proben zu ≥ 0,8 im
  15-m-Korridor eines sichtbaren Trails liegen (die Schwellen des
  Abgleichs), trägt dessen Richtung: Eine **Abfahrt** ist gegen ihre
  Richtung gesperrt (Feldbericht: „man sollte nie rückwärts über einen
  Trail fahren"), außer der Trail ist **„in beide Richtungen fahrbar"**
  (Patch 016, `trail_details.two_way`; gilt die eigene Angabe, sonst die
  Mehrheit der sichtbaren Beiträge, bei Gleichstand nein). Ein
  **Uphill-Trail** (Uphill unter den angezeigten Merkmalen) ist ein
  Verbinder in seiner Richtung, eine **Verbindung** einer in beide; ein
  Verbinder kostet Zeit × 0,8 statt Zeit × Aufschlag der Klasse
  (`kTrailConnectorFactor`, Startwert, nicht gemessen) und zählt nicht
  als Wanderweg. Kennt die Karte einen Verbinder nicht, wird er eine
  eigene Kante zwischen seinen angehefteten Enden, mit seinen Höhen.
  Uphill-Trails und Verbinder stehen deshalb nicht mehr im Pool der
  Abfahrten. Mehrfach befahren darf man Verbinder wie jeden Weg —
  Verbindungen wurden nie bestraft, nur eine zweite ABFAHRT bringt
  weniger (3). Gesperrte Verbinder fallen weg, gesperrte Abfahrten
  behalten ihre Richtung.
- **Gebaut wird je Planung** für den Rahmen Start ± Reichweite
  (Reichweite = Zeitbudget × 15 km/h / 2, höchstens 25 km) und für die
  Sitzung gemerkt (Schlüssel: Bereichs-Builds + Rahmen). Ein
  20-km-Rahmen sind rund 70 Kacheln und schätzungsweise 20 000
  Wegekanten — das baut ein Telefon in unter einer Sekunde (Messfrage
  M5). Gebaut wird im UI-Isolate; GERECHNET wird die Runde seit 0.80.1
  in einem dauerhaften Rechen-Isolate, der den Graphen einmal bekommt
  (#188, gemessen in `docs/routing-messung.md`: an Ort und Stelle stand
  die Oberfläche bei 60 Trails 2,4 s, im Isolate einmal ~0,3 s für das
  Senden, danach 11–31 ms Pause je Rechnung). Seit 0.80.2 behält der
  Isolate die Suchen je Trail-Ende für die nächste Rechnung auf
  demselben Graphen (`LoopSearchCache`): Abwählen, Pflicht, Höhen- und
  Wanderweg-Budget rechnen in Millisekunden; ein anderes Profil, ein
  anderes Zeitbudget oder ein neuer Start suchen neu. Die Trail-Enden
  im Rahmen werden beim Laden angeheftet, ein dazugewählter Trail aus
  dem Rahmen braucht deshalb weder neues Laden noch neue Suchen.
- **Knoten — drei Regeln, gemessen (M1, `docs/routing-messung.md`)**:
  Jede Kachel wird auf ihren Rahmen zugeschnitten (der Puffer legte
  Wege doppelt). Zwei Linien teilen einen Knoten, wenn ihre Punkte auf
  dieselbe Kachelkoordinate fallen. Dann wird jedes tote Ende innerhalb
  von **2 m** an den nächsten anderen Weg gebunden — auch mitten in
  ein Segment, das ist der T-Knoten, den die Vereinfachung aus dem
  durchgehenden Weg entfernt hat — und jede **Kreuzung ohne
  gemeinsamen Knoten geteilt**, sofern beide Wege auf derselben Ebene
  liegen (`is_bridge`/`is_tunnel` aus den Kacheln). Ohne die beiden
  Reparaturen hält die größte Komponente 50–80 % der Kantenlänge, mit
  ihnen 95–98 %, und 93–100 % der Trail-Enden hängen an ihr. 10 m
  statt 2 m bringen nichts mehr.
- **Trail-Enden** werden an den nächsten Wegeknoten innerhalb von 30 m
  geheftet (die GPS-Unschärfe des Trailanfangs); liegt keiner da, wird
  der nächste Wegepunkt im Umkreis als Knoten eingefügt. Die geteilte
  Kante gibt dabei Höhen (anteilig nach Länge), Trail und Sperre an
  BEIDE Hälften weiter — bis 0.73.0 verlor die zweite Hälfte ihre
  Höhen, und das Blatt sagte „nicht alle Wege haben Höhen", auch wenn
  alle da waren. Ein Trail ohne
  Anschluss an beiden Enden ist für den Planer „nicht erreichbar" und
  steht so im Blatt.
- **Kein Netzziel, keine Berechtigung.** Alles kommt von Hosts, die
  die Datenschutzerklärung schon nennt, oder liegt im APK.

## 3. Algorithmus

1. **Aufstiege zwischen allen Trail-Enden** („Zum Trailkopf" ist der
   Sonderfall mit einem Ziel): Dijkstra von jedem Trail-Ende und vom
   Start, begrenzt durch das Budget (abgebrochen, sobald die Kosten das
   Budget übersteigen). Bei N Trails im Rahmen sind das 2N + 1 Läufe auf
   20 000 Kanten — Sekundenbruchteile. Ein A* mit Luftlinien-Heuristik
   für die Einzelanfrage „zum Trailkopf".
2. **Verkettung** (Orienteering-Problem, NP-schwer, hier klein):
   greedy einfügen nach „Trail-Meter je Kostenzuwachs", dann lokale
   Suche (Tausch, Entfernen und Einfügen) mit festem Zeitdeckel
   (300 ms). „Diese will ich heute" (Pflicht-Trails) werden zuerst
   eingefügt und nie entfernt.
   **Gebaut (0.72.0) mit zwei Festlegungen, die hier fehlten:** Das Maß
   im greedy Schritt ist Trail-Meter je ZEITzuwachs, nicht je
   Kostenzuwachs — die Zeit ist das Budget, die Kosten sind nur die
   Wahl des Wegs. Und das Budget „höchstens Wanderweg" ist keine
   Nachprüfung: Die günstigste Verbindung läuft oft über den
   Wanderweg (Faktor 1,4 auf 8 km/h schlägt 15 km/h auf dem dreimal
   längeren Forstweg); überschreitet die Runde das Budget, bekommt die
   Verbindung mit dem meisten Wanderweg ihre Fassung OHNE Wanderweg,
   Fußweg und Stufen (zweiter Dijkstra je Startknoten, `allow`), bis es
   passt — erst wenn keine Fassung mehr da ist, scheitert der Trail am
   Budget. Ohne die Regel ließ „kein Wanderweg" einen Trail aus, zu dem
   drei Seiten Forstweg führten (im Test gefunden).
3. **Zielfunktion**: zuerst mehr **Trail-Meter** (Länge der gefahrenen
   Trails — nicht Anzahl, sonst gewinnen drei kurze gegen einen langen),
   bei Gleichstand weniger Aufstiegs-Höhenmeter, dann weniger
   verschenkte Höhe. Alles unter den drei Budgets aus 2.3.
   **Ein Trail zweimal ist sehr teuer** (Betreiber, 2026-10-01): Die
   zweite Abfahrt bringt keine Trail-Meter — außer der Trail trägt eine
   Bewertung von 4 oder 5 Sternen (Median, wie angezeigt), dann noch
   30 %. Zeit und Aufstieg kostet sie voll. Ein Trail steht höchstens
   zweimal in einer Runde. So fällt ein zweiter Durchgang nur dort an,
   wo sonst nur Forstweg bergab bliebe, und bevorzugt auf dem Trail,
   den die Buddys mögen.
4. **Ergebnis**: Linie mit Abschnitten (Aufstieg nach Klasse, Trail),
   Summen (Länge, hm bergauf, hm Trail bergab, Zeit, Wanderweg-km,
   verschenkte hm), Liste der Trails in Reihenfolge, die Trails, die
   NICHT hineingepasst haben und warum (zu weit, Budget, nicht
   erreichbar).

Alles pur in Dart (`lib/features/routing/`: `road_graph.dart`,
`route_profile.dart`, `route_search.dart`, `loop_planner.dart`), ohne
Widgets, geprüft mit erzeugten Kacheln wie `road_index_test`. Das
Python-Werkzeug `tool/route_measure.py` ist die Referenz für die
Messung und spiegelt Kostentabelle und Zeitmodell; wie bei
`trail_match.py` kommen Werkzeug und Dart bei Änderungen im SELBEN PR.

## 4. Oberfläche

- **Die Blätter sind kein Modal** (seit 0.74.0, `map_panel.dart`;
  Feldbericht: „der erstellte Track war nicht wirklich sichtbar. Man
  musste das Planungsfenster nach unten ziehen, aber das beendet dann
  gleichzeitig die Routenplanung"). Ein Persistent Bottom Sheet am
  Scaffold der Karte: Die Karte darüber bleibt bedienbar, Runterziehen
  verkleinert bis auf den Kopf (`shouldCloseOnMinExtent: false` — sonst
  schließt das Scaffold es unten), geschlossen wird mit X oder Zurück.
  Beim Ergebnis klappt das Blatt auf ein Drittel ein, und die Karte
  passt die Route in die Fläche DARÜBER ein (`cameraToFit(bottomInset:)`,
  höchstens 55 % der Höhe gelten als verdeckt). Was die Planung aufhält,
  steht oben im Blatt; ein Fehler beim Rechnen ist ein Satz und ein
  Fehlerbericht, nie ein Kreisel, der stehen bleibt.
- **Trail-Blatt**: „Zum Trailkopf" neben „Anfahrt" (#151). Ergebnis
  als Vorschau auf der Karte (dieselbe Strecke wie das Zerlege-Blatt:
  Fahrt blass, Aufstieg nach Klasse), darunter die Summen und der
  Satz zum Wanderweg. „Als Fahrt speichern" (geplant) und „Als GPX".
  **Seit 0.74.0 „Direkt" oder „Spaßig"** (#176): Spaßig ist der Planer
  mit Ziel (`planLoop(end:)`, der Ziel-Trail selbst nicht im Pool) im
  Budget 1,6 × die direkte Zeit (mindestens + 20 min) und 1,5 × deren
  Höhenmeter (mindestens + 200) — Startwerte. Passt kein Trail, steht
  der direkte Weg da, mit Satz. Dasselbe Blatt nimmt auch einen Punkt
  als Ziel („Route bis hier", #177).
- **Das Navi-Symbol an jedem Trail** (#176, Liste und Schnellkarte,
  `navigate_choice.dart`): Navi-App, direkt oder spaßig; „Als Standard
  merken" (`Settings.navDefault`), ein langer Druck fragt wieder.
- **Langer Druck auf die Karte** (#177): eine Nadel und das Menü „Route
  ab hier" (der Planer mit diesem Start), „Route bis hier" (das Blatt
  mit dem Punkt als Ziel), „Mit der Navi-App hierher".
- **Auswählen statt öffnen** (#178): Ein Tipp auf einen Trail hebt ihn
  hervor und zeigt die Schnellkarte; ein Tipp auf sie oder ein zweiter
  auf den Trail öffnet das Blatt. Im Planer wählt ein Tipp auf einen
  Trail ihn an oder ab, die gewählten leuchten.
- **Planer-Blatt** über einen EIGENEN Knopf (Betreiber: nicht der
  Idee-Knopf, der bleibt Feedback) — **gebaut in 0.72.0** auf der Karte,
  zwischen „Ebenen" und „Meine Position" (die Knopfspalte trägt ihn
  auch auf 360 × 740, `map_shell_test`). Drei Stufen, eine nach der
  anderen: Regler (Start: Standort oder auf der Karte getippt — das
  Blatt schließt sich, der nächste Tipp auf die Karte ist der Start, das
  Blatt kommt wieder; Profil; die drei Regler aus 2.3; „Start ist auch
  Ziel", sonst endet die Runde am letzten Trail), dann der Pool (alle
  sichtbaren Trails, deren beide Enden höchstens 12 km vom Start liegen
  — `kLoopReachM`; weiter entfernte werden nur gezählt; gemeldete stehen
  abseits und abgewählt, Entscheidung 8.8; Stern = Pflicht), dann das
  Ergebnis wie oben, dazu die ausgelassenen Trails mit Grund (zu weit,
  kein Weg am Ende, nicht erreichbar, Budget). Der Fix kommt erst beim
  Schritt zum Pool, nicht beim Öffnen. Ohne Bereich: ein Satz, der den
  Ebenen-Knopf nennt. Ein Zielpunkt ungleich Start ist nicht gebaut
  (nur „Start ist auch Ziel" an/aus).
  **Seit 0.74.0 kein Blatt mit Stufen mehr, sondern ein Modus mit Leiste
  links** (Betreiber: „zum Planen links ein Menü in der Art wie rechts,
  mit Planer-Optionen"; `loop_tool_rail.dart`, Zustand in
  `loop_planner_controller.dart`). Der Runden-Knopf öffnet und schließt
  ihn, wie der Ebenen-Knopf seine Leiste (beide nie zugleich). Von oben:
  Start (Standort, oder der nächste Tipp auf die Karte), Parameter (das
  Blatt mit Profil, den drei Reglern, „Start ist auch Ziel" und dem
  **Radius der Liste**, 2–30 km, Vorgabe 12), Liste (die wählbaren Trails
  im Radius, „Alle wählen", Stern = Pflicht), Gebiet dazu / weg (mit dem
  Finger umfahren, dieselbe Zeichenfläche wie bei den Bereichen; ein
  Trail zählt, wenn die Mehrheit seiner Punkte drin liegt), Auswahl
  leeren, Rechnen (mit der Zahl der gewählten Trails), Schließen. **Der
  wichtigste Weg ist die Karte selbst: ein Tipp auf einen Trail wählt ihn
  an (er leuchtet), ein zweiter ab.** Ab Werk ist nichts gewählt — die
  Runde besteht aus dem, was der Fahrer will, nicht aus allem im Umkreis.
  Der Radius begrenzt nur die Liste; was angetippt ist, gehört dazu.
  Uphill-Trails und Verbinder sind nicht wählbar (die Karte sagt es),
  wartende auch nicht. Das Ergebnis kommt als Blatt von unten (kein
  Modal); zu heißt Ergebnis weg, Leiste und Auswahl bleiben. Zurück geht
  stufenweise: Start-Tipp, Zeichnen, Planer.
- **Zwischenpunkte zum Ziehen** (#234, seit 0.93.0; Feldbericht 0.82.2:
  „Gummipunkte, die man ziehen kann, um die Wegführung manuell zu
  tunen"): In jedem Ergebnis — Runde, „Zum Trailkopf"/„Route hierher",
  direkt oder spaßig — setzt ein Tipp auf eine VERBINDUNG (nicht auf
  einen Trail) dort einen Punkt; Ziehen verschiebt ihn, ein Tipp auf ihn
  nimmt ihn weg (mit Rückgängig). Ein Punkt gehört zu einem Teilstück
  zwischen zwei festen Halten (Start, Trail-Ende, Trail-Anfang, Ziel)
  und liegt darin in Fahrtrichtung. Gerechnet wird je Abschnitt A*,
  Punkt für Punkt (`pathThrough`). **Bei der Runde steht die Folge der
  Trails dann fest** (`LoopTune`): Die Optimierung aus Abschnitt 3 läuft
  nicht mehr, nur die Teilstücke folgen den Punkten; Budgets prüft
  niemand, das Blatt sagt, wenn die Runde darüber liegt. „Zurücksetzen"
  rechnet frei, ebenso jede Änderung an Reglern, Auswahl, Profil oder
  Weg. Führt durch einen Punkt kein Weg (30 m ohne Weg, Einbahn, Insel),
  springt er zurück, und die Karte sagt es. Gespeichert und exportiert
  wird die fertige Linie, nicht die Punkte. Liegen zwei Teilstücke auf
  demselben Weg (hin und zurück), trifft der Tipp das zuletzt
  gezeichnete — der Punkt liegt auf beiden. Bewusst nicht: die Linie
  selbst ziehen, ohne vorher zu tippen — das nähme jedem Verschieben der
  Karte, das auf der Route beginnt, die Geste.
- **Gespeicherte Runde** = geplante Fahrt in „Meine Fahrten" (Konzept
  5.2; `Ride.planned`, mit Namen, Punkte ohne Zeit und Höhe, Dauer =
  Schätzung) — **ohne Schere**: Abweichung vom Satz oben. Zerlegt wird,
  was gefahren wurde, und das ist nach dem Fahren eine eigene
  Aufzeichnung; die geplante Linie zu zerlegen hieße, Trails zu
  belegen, die niemand gefahren ist. Auch der Weg „Zum Trailkopf" lässt
  sich so ablegen.
- Highlight-Eintrag und Vorführung je Schritt (PR-Vorlage). Die
  Kurzanleitung hat SECHS Abschnitte als Obergrenze (Onboarding 3.1),
  deshalb kein eigener Abschnitt „Runde planen": ein Satz im Abschnitt
  „Fahrt aufzeichnen und zerlegen".

## 5. Umsetzung in Schritten (je ein PR)

| Schritt | Inhalt | Issue | Bump |
|---|---|---|---|
| 0 | dieses Dokument; Konzept 9 und 11 nachziehen | #35 | — |
| 1 | `tool/route_measure.py` + `route-measure.yml`: Graph aus Kacheln, DEM, A*, Messung an Tirol (CI) und an den eigenen Fahrten (lokal), Bericht `docs/routing-messung.md` | #35 | — |
| 2 | Höhen: Höhenkacheln je Bereich vom eigenen Host (B — A ist in M3 durchgefallen), gebaut von `height-data.yml` als EIN Archiv, geladen mit dem Bereich — **gebaut, 0.69.0** (2.6) | #158/2 | feat |
| 3 | `road_graph.dart`, `route_profile.dart`, `route_search.dart`, Tests mit erzeugten Kacheln; Profil-Einstellung Bio/E — **gebaut, 0.70.0** (`lib/features/routing/`; `Ride.profile` seither im Dateikopf) | #158/3 | feat |
| 4 | „Zum Trailkopf" im Trail-Blatt, Vorschau, GPX — **gebaut, 0.71.0** (`trail_head_route.dart` pur, `trail_head_sheet.dart`; Start ist der eigene Standort — der getippte Punkt und „Als Fahrt speichern" kommen mit Schritt 5, weil beides die geplante Fahrt in „Meine Fahrten" braucht) | #158/4 | feat |
| 5 | `loop_planner.dart`, Planer-Blatt, Pool, Pflicht-Trails — **gebaut, 0.72.0** (`loop_planner.dart` pur, `loop_planner_sheet.dart`, `loop_planner_providers.dart`; geplante Fahrt in „Meine Fahrten", „Als Fahrt speichern" auch bei „Zum Trailkopf") | #158/5 | feat |
| 6 | Kalibrierung aus eigenen Fahrten, je Profil (Steigrate je Klasse, Flachgeschwindigkeit), im Profil sichtbar („Bio-Bike: 520 hm/h aus 14 Fahrten") und zurücksetzbar; `Ride.profile` kommt mit Schritt 3 — **gebaut, 0.73.0** (`ride_calibration.dart` pur als Spiegel von `ride_sections`/`class_mix_along` im Werkzeug, `ride_calibrator.dart`; auf Knopfdruck unter „Fahrerprofil", Median je Klassengruppe ab drei Aufstiegen, plausible Spanne; die Planer lesen `calibratedRiderProvider`); seit 0.82.0 auch aus Fahrten, die der GPX-Import mit Profil in „Meine Fahrten" übernimmt (#188) | #158 | feat |
| 7 | Rund machen nach dem ersten Feldeinsatz: Blätter ohne Modal und über der Karte eingepasst, Planung über den vorhandenen Teil der Kacheln, Trail-Richtung und Verbinder auf dem Graphen (Patch 016 „in beide Richtungen"), Direkt/Spaßig, Navi-Symbol, langer Druck, Auswählen statt öffnen — **gebaut, 0.74.0** | #174 #176 #177 #178 #185 | feat |
| 8 | Fehlende Wege- und Höhenkacheln mit Empfang vom eigenen Host, gedeckelt, nur für die Sitzung, abschaltbar (2.7) — **gebaut, 0.78.0** | #187 | feat |

Schritt 1 entscheidet, ob 2–5 so gebaut werden oder ob vorher die
Pipeline (2.5, letzter Punkt) dran ist. Schritte 3–5 brauchen keine
anderen Nutzer und laufen parallel zur Abgleich-Arbeit (Fahrplan #156,
Stufe 3).

## 6. Messplan (#35, neu geschnitten)

Die alte Frage „welche Engine?" ist entschieden. Die Messung fragt
jetzt, ob **unsere Daten** die eigene Engine tragen. Fünf Fragen, jede
mit Schwelle — **Stand 2026-10-01: M1 bestanden (mit den drei
Graph-Regeln aus 2.7), M3 entschieden (Weg B), M5 ohne Befund in
Python; M2, M4 und die Kalibrierung an 47 eigenen Fahrten gemessen
(2026-10-02): Forstweg trägt die Aufstiege, Vorgaben und Tabelle
bleiben, M4 verfehlt die Schwelle und misst die falsche Frage**
(`docs/routing-messung.md`):

| | Frage | Daten | Schwelle |
|---|---|---|---|
| M1 | **Zusammenhang**: Teilen Wege an Kreuzungen bei z13 einen Knoten? Wie groß ist die größte Komponente, wie viele Trail-Enden hängen innerhalb von 30 m an ihr? | Tirol: 181 offizielle Trails (öffentlich, CI) + eigene Trails (lokal) | ≥ 90 % der Trail-Enden angeschlossen, größte Komponente ≥ 95 % der Kanten im Rahmen — **bestanden: 95 / 97 / 98 % und 98 / 93 / 100 % in drei Rahmen, nur mit Verbindung ≤ 2 m und Kreuzungsteilung** |
| M2 | **Wegklassen**: Wie oft führen die eigenen Aufstiege über `track`, `path`, Straße? Trägt die Tabelle 2.4 die Praxis? | eigene Fahrten (lokal; Zerlege-Logik kennt die Aufstiegsstücke) | Bericht, keine Schwelle — **Forstweg 36–55 %, Straßen und Wanderwege je um 15 %** |
| M3 | **Höhenfehler**: hm bergauf aus Gitter A gegen GPX-Höhen derselben Linie; je Kante und je Aufstieg | eigene Tracks (lokal), Tirol `up_m`/`down_m` (CI) | Aufstiegssumme ±10 %, sonst Höhenkacheln B — **Gitter A 42 % Medianfehler, DEM direkt 5 %: Weg B** |
| M4 | **Aufstiegstreue**: Vom Fahrtstart zum ersten Trailkopf — findet A* den Weg, den der Betreiber gefahren ist? Länge, hm, Klassenmix gegen die Fahrt | eigene Fahrten (lokal) | ≥ 70 % der Aufstiege „gleich" nach den Abgleich-Schwellen (15 m, 0,8), Rest erklärbar — **1 von 15 gleich; der Plan ist nach dem Modell nie langsamer als die Fahrt (Median 1,27-mal schneller), und kein Kostenaufschlag rückt ihn näher: Die Fahrt ist nicht das Optimum. Bewertet wird im Feld (#188)** |
| M5 | **Laufzeit**: Graph bauen + 2N+1 Dijkstra + Verkettung für einen 20-km-Rahmen | Tirol (CI), auf dem Telefon nach Schritt 3 | < 2 s auf dem Rechner, < 5 s auf dem Telefon — **Python 0,7–6 s je Rahmen (25 000 Wegstücke: Graph ~2 s, 22 Dijkstra 3,7 s); das Telefon misst Schritt 3** |

Dazu die **Kalibrierung** (kein Durchfallen möglich): Steigrate und
Flachgeschwindigkeit je Klasse aus den eigenen Fahrten, als Startwerte
für 2.1.

Zwei Läufe, ein Werkzeug: `python3 tool/route_measure.py tirol` liest
die z13-Kacheln aus dem Host-Archiv (Range, wie `map_tiles.py check`),
die offiziellen Trails aus dem Daten-Branch und das DEM aus dem offenen
Bucket — alles öffentlich, läuft in CI (`route-measure.yml`,
`workflow_dispatch`, Bericht in der Run-Summary). `python3
tool/route_measure.py rides --gpx <Sammlung> --rides <Export>` läuft
beim Betreiber: Fahrten verlassen das Gerät nie, also kommen sie als
GPX-Export (#150) auf seinen Rechner, und der Bericht nennt Kennzahlen,
keine Orte. Der CI-Lauf allein beantwortet M1, M3 (Tirol-Hälfte) und
M5; M2 und M4 nur der lokale.

## 7. Risiken, benannt

- **Die Kacheln sind für Karten gemacht, nicht für Graphen.** M1 war
  die Frage, an der es scheitern konnte — und sie ist bestanden, aber
  nur mit den drei Reparaturen aus 2.7. Ein Graph-Bauer, der sie
  vergisst, bekommt still einen Graphen in tausend Stücken; die
  Dart-Engine braucht dafür denselben Test wie das Werkzeug. Der
  Ausweg für den Belag (2.5) bleibt die eigene Pipeline.
- **Pfad ist nicht gleich Pfad.** Ohne `sac_scale` plant die Engine im
  Zweifel über einen Steig. Der Regler, die Nennung im Ergebnis und die
  Vorgabe 2 km begrenzen den Schaden; der Nutzer sieht die Linie, bevor
  er fährt.
- **Das Zeitmodell ist ohne Kalibrierung grob** (±30 %). Deshalb
  „etwa", deshalb Schritt 6, deshalb die Reserve.
- **Große Pools.** Hundert Trails im Rahmen sind 201 Dijkstra-Läufe;
  die Budget-Grenze hält jeden klein. Über 150 Trails nimmt der Planer
  die nächsten 150 zum Start und sagt es.
- **Der Planer lädt zum Risiko ein** wie jedes Werkzeug, das eine Runde
  vorschlägt. Das Blatt trägt den Sicherheitshinweis (`kSafetyNote`),
  und die Nutzungsbedingungen (Entwurf, Abschnitt 4) gelten.

## 8. Entscheidungen des Betreibers (2026-10-01)

Alle entschieden; die Zahlen dahinter sind Startwerte und bleiben
Vorschläge, bis die Messung oder die eigenen Fahrten andere liefern.

1. **Zwei Profile, Bio-Bike und E-Bike, nebeneinander mit eigenen
   Parametern** („viele haben beides"), Vorgabe Bio-Bike, je Planung
   umschaltbar; die Parameter entweder feste Vorgaben oder aus den
   Fahrten gelernt — gebaut wird: Vorgaben zuerst, Lernen je Profil in
   Schritt 6 (2.1).
2. **Startwerte** aus 2.1–2.3 (Steigraten, Geschwindigkeiten, 3 h,
   800/1 400 hm, 2 km Wanderweg): so.
3. **Wanderwege auch bergab, wenn es Sinn macht** — als teure
   Verbindung, nie als Trail (1, 2.4).
4. **Hauptstraßen nie ausgeschlossen, nur teuer**; `motorway`/`trunk`
   und `access=private` bleiben gesperrt.
5. **Höhen: zuerst das Gitter wie in PilzBuddy**, „vielleicht reicht es
   fürs Routing"; genauer wie bei Locus (90 m, Weg B), wenn die Messung
   M3 es verlangt — sie verlangt es, am selben Tag gemessen (2.6):
   Weg B.
6. **Zielfunktion Trail-Meter** vor Anzahl; **ein Trail zweimal ist
   sehr teuer**, erst recht ohne 4–5 Sterne der Buddys (3).
7. **Eigener Knopf für den Planer**, nicht der Idee-Knopf (4).
8. **Trails mit warnender Meldung** aus dem Pool, einzeln hineinholbar.
9. **BRouter**: nein, keine Hintertür (0).
10. **Reihenfolge**: Schritt 1 (Messung) vor allem anderen; Schritte
    3–5 erst nach dem Bericht — die Regel aus #35.
