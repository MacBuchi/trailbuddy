# Trail-Abgleich: Messung an echten Aufzeichnungen

*Phase 0 aus `konzept-trails.md`, gemessen am 2026-09-27 mit
`tool/trail_match.py` gegen die Locus-Sammlung des Betreibers (584
GPX-Dateien, gezippt; liegt außerhalb des Repos, Pfad über `TRAIL_GPX`).
Dieser Bericht nennt Kennzahlen, keine Namen, keine Koordinaten, keine
Orte. Die Paar-Tabelle MIT Namen (`--private-out`) hat nur der
Betreiber.*

## Ergebnis in vier Sätzen

1. **Die Startwerte halten**: Korridor 15 m, beidseitige Deckung ≥ 0,8,
   Fréchet ≤ 2 × Korridor. Bei diesen Werten findet der Abgleich 8
   Gleich-Paare, alle dem Namen nach plausibel, darunter 4 mit
   verschiedenen Namen für denselben Trail — genau der Fall, für den das
   Konzept Namen an den Beitrag statt an den Trail hängt.
2. **Fréchet muss auf den Punkten IM KORRIDOR gerechnet werden**, nicht
   auf allen. Der erste Lauf mit dem nackten Maximum hielt drei
   namensgleiche Trails für Nachbarn (Fréchet 40 bis 89 m bei Deckung
   0,85 bis 1,0): Ein einzelner GPS-Sporn oder ein grob gezeichneter
   Bogen treibt das Maximum, sagt aber nichts über die Reihenfolge. Mit
   dem Zuschnitt liegen dieselben Paare bei 12 bis 19 m; der
   Serpentinen-Fall aus dem Selbsttest bleibt erkannt.
3. **Dubletten sind in einer einzelnen Sammlung selten, Überlappungen
   häufig**: 3 % der Tracks stecken in einem Gleich-Paar, aber 30 Paare
   sind „Teil" (fast immer ein Trail in einer Fahrt) und 55 „Gabel"
   (gemeinsames Stück, dann Abzweig). Die konservative v1-Regel — nur
   „gleich" verschmelzen, alles andere neuer Trail mit unsichtbarer
   Kante — trifft damit den Normalfall, nicht die Ausnahme.
4. **Die Importregel „kurz und bergab" braucht 8 km statt 3 km.** Alpine
   Trails sind 3 bis 8 km lang und abfahrtsdominiert; Fahrten beginnen in
   dieser Sammlung bei 8 km. 44 % der Dateien haben keine verwertbaren
   Zeiten — die Kennzeichnung „geplant" (Entscheidung 2) betrifft fast
   die Hälfte des Bestands.

## Was gemessen wurde

Je Paar von Tracks, deren Hüllen sich bis auf 25 m nahekommen:

- beide Linien auf 5 m abgetastet; je Abtastpunkt von A der Abstand zum
  nächsten Segment von B (Gitterindex), und umgekehrt;
- Deckung `cov(A→B, d)` = Anteil der Punkte von A näher als `d` an B;
- Richtung aus der Bogenlänge der nächsten Punkte auf B (steigend,
  fallend, gemischt);
- diskrete Fréchet-Distanz auf den Punkten, die im 15-m-Korridor liegen,
  bei „fallend" auf der umgedrehten Linie; Schrittweite so, dass höchstens
  1 200 Punkte je Linie bleiben.

Einordnung: gleich (Deckung beidseitig ≥ c UND Fréchet ≤ 2d), Nachbar
(Deckung ja, Fréchet nein), Teil (einseitig ≥ c), Gabel (beidseitig
≥ 0,3), sonst verschieden. Der Selbsttest (`--self-test`) prüft an
synthetischen Linien: verrauschte Kopie, Gegenrichtung, Parallele in
40 m, Hälfte, Trail in Fahrt, Gabel, Serpentinen gegen die um eine
Kehre verschobenen Serpentinen (deckt sich zu ≥ 0,7 und MUSS Nachbar
sein), Erkennung geplanter Routen.

## Zahlen

### Bestand

- Tracks: 584, davon ohne verwertbare Zeiten oder mit Fahrradfremden Geschwindigkeiten (`planned`): 258
- Länge: Median 935 m, kürzeste 13 m, längste 34.1 km
  - bis 150 m: 12
  - bis 500 m: 166
  - bis 1000 m: 304
  - bis 3000 m: 464
  - bis 10000 m: 552
- Punktabstand (Median je Track, Median darüber): 13.1 m
- Höhen: 578 Tracks vollständig
- Abfahrtsdominiert (Verlust > 2 × Gewinn): 468 (80 %)
- „Kurz und bergab“ (< 3 km und Verlust > 2 × Gewinn, Importregel 5.2): 398 (68 %)
- Tracks mit Kehren (Richtungsumkehr ≥ 150° binnen 30 m): 212, Kehren insgesamt: 1050

Abfahrtsdominierte Tracks nach Länge (wo endet „Trail“, wo beginnt „Fahrt“?):

| Länge | abfahrtsdominiert | übrige |
|---|---|---|
| 0–1 km | 276 | 28 |
| 1–3 km | 122 | 38 |
| 3–5 km | 41 | 9 |
| 5–8 km | 25 | 6 |
| 8–15 km | 4 | 12 |
| ab 15 km | 0 | 23 |

### Paare

- Paare mit sich berührenden Hüllen (Rand 25 m) und mindestens einem Punkt im Korridor: 291

### Einordnung nach Korridor und Deckungsschwelle

Zeile = Korridor `d`, Spalte = Deckung; Zelle = gleich / gleich-gegen / Nachbar (deckt, Fréchet scheitert) / Teil / Gabel.

| d | cov ≥ 0.7 | cov ≥ 0.8 | cov ≥ 0.9 |
|---|---|---|---|
| 10 m | 8 / 0 / 1 / 24 / 42 | 7 / 0 / 0 / 18 / 50 | 7 / 0 / 0 / 13 / 55 |
| 15 m | 10 / 0 / 1 / 40 / 43 | 8 / 0 / 1 / 30 / 55 | 7 / 0 / 0 / 16 / 71 |
| 20 m | 12 / 0 / 2 / 46 / 46 | 11 / 0 / 2 / 38 / 55 | 7 / 0 / 1 / 30 / 68 |
| 25 m | 16 / 0 / 2 / 50 / 52 | 11 / 0 / 2 / 46 / 61 | 10 / 0 / 1 / 35 / 74 |

### Bei den Startwerten (d = 15 m, Deckung ≥ 0.8)

- gleich: 8, gleich in Gegenrichtung: 0, Nachbar: 1, Teil: 30, Gabel: 55
- Fréchet der Gleichen: Median 6.2 m, 90. Perzentil 19.3 m, Maximum 19.4 m
- Gleiche Paare, an denen ein Track mit Kehren beteiligt ist: 5
- Längenverhältnis der Gleichen: Median 1.00, Maximum 1.20
- Nachbar-Paare: Fréchet 84 m

### Fréchet-Schwelle bei beidseitiger Deckung (d = 15 m, ≥ 0,8)

| Fréchet ≤ | Paare |
|---|---|
| 15 m | 6 |
| 20 m | 8 |
| 30 m | 8 |
| 45 m | 8 |
| 60 m | 8 |
| 100 m | 9 |
| ∞ | 9 |

### Verteilung der beidseitigen Deckung (min(cov_ab, cov_ba) bei d = 15 m)

| min. Deckung | Paare |
|---|---|
| 0.3 – 0.5 | 16 |
| 0.5 – 0.7 | 10 |
| 0.7 – 0.8 | 2 |
| 0.8 – 0.9 | 2 |
| 0.9 – 1.0 | 7 |

### Namensgleiche Paare als Bodenwahrheit

- Paare mit gleichem gefaltetem Namen: 8; davon geometrisch überhaupt benachbart: 6
  - eingeordnet als same: 4
  - eingeordnet als a-in-b: 1
  - eingeordnet als b-in-a: 1
- Als gleich erkannte Paare mit VERSCHIEDENEN Namen: 4 (der Fall „ein Trail, zwei Namen“ aus dem Konzept)

- Tracks, die in mindestens einem Gleich-Paar stecken: 16 von 584 (3 %)

## Lesart

**Es gibt eine Lücke in der Deckung, und 0,8 liegt darin.** Von 37
Paaren mit beidseitiger Deckung ≥ 0,3 liegen 26 unter 0,7 und 7 über
0,9; dazwischen nur 4. Die zwei Paare in 0,7–0,8 sind je ein Trail und
seine Variante mit demselben Anfang (Namen wie „X" und „X I"): Jeder hat
rund ein Fünftel außerhalb des anderen. Sie NICHT zu verschmelzen ist
richtig — ob es eine Variante oder ein anderer Trail ist, entscheidet
später jemand, der beide sieht.

**Der Korridor ist unkritisch zwischen 10 und 15 m** (7 bis 8 Gleiche),
ab 20 m kommen Paare dazu, die bei 15 m Gabel oder Teil sind. 15 m
bleibt: Das ist die gemessene GPS-Streuung unter Blätterdach, und ein
weiterer Korridor kauft nichts als Fehlverschmelzungen.

**Fréchet trennt sauber, wenn er getrimmt ist.** Alle 8 Gleichen liegen
bei ≤ 19,4 m, also unter 2 × 15 m; das eine Nachbar-Paar bei 84 m sind
zwei 25-km-Fahrten mit Varianten, kein Trail. Zwischen 20 und 60 m liegt
nichts — die Schwelle 2d hat Luft.

**Namensgleichheit als Bodenwahrheit** (Namen so gefaltet wie in
PilzBuddys Artensuche): 8 Paare tragen denselben Namen. 4 sind
geometrisch gleich (URL-kodierte Kopien und ein echtes Zweitfahren), 2
sind Teil-Beziehungen (eine 13-m-Datei, die nur ein Fragment ist; ein
halber Trail unter vollem Namen), 2 liegen an verschiedenen Orten
(Allerweltsnamen). Umgekehrt: 4 der 8 Gleichen haben VERSCHIEDENE
Namen. Beides sagt dasselbe: Der Name ist kein Schlüssel, die Geometrie
ist es.

**Die Sammlung testet die Dublette schwach und die Überlappung stark.**
Eine kuratierte Einzelsammlung enthält jeden Trail einmal; das Szenario
„zwei Buddys, 80 % gemeinsam" lässt sich erst mit einer zweiten
Sammlung messen. Die Überlappungsfälle sind dagegen reichlich: Trails in
Fahrten (Deckung 1,0 / 0,05), Trails, die sich ein Einstiegsstück teilen,
Trail und Trail-Variante. Für diese Fälle ist die v1-Regel gebaut.

**Kehren sind kein Problem, sondern häufig**: 212 Tracks haben
mindestens eine Richtungsumkehr binnen 30 m, 1 050 insgesamt. 5 der 8
Gleich-Paare enthalten Kehren und liegen trotzdem bei Fréchet ≤ 19 m.
Der Serpentinen-Nachbar (parallele Schenkel in 15 m Abstand) kommt in
der Sammlung nicht als Paar vor; der Selbsttest hält den Fall.

**Mindestlänge 150 m**: 12 Dateien darunter, die kürzeste 13 m — ein
Fragment mit dem Namen eines echten Trails. Die Grenze ist eher zu
niedrig als zu hoch, bleibt aber, bis Kandidaten aus Fahrten gemessen
sind (die entstehen erst in Phase 2).
**Seit Patch 017 (2026-10-04) 50 m**, Entscheidung des Betreibers: Kurze
echte Trails (Jump-Line, kurze Steilpassage) fielen unter 150 m weg; das
kürzeste Fragment im Bestand (13 m) bleibt auch unter 50 m.

## Folgen für das Konzept

- 4.2: Fréchet auf den Punkten im Korridor; Schwellen bestätigt.
- 5.2: „kurz und bergab" heißt < 8 km und Verlust > 2 × Gewinn. Fahrten
  ab 8 km, darunter 4 lange abfahrtsdominierte Tracks, die als Fahrt
  durchs Zerlege-Blatt gehen — das ist der harmlose Fehler.
- 2 / 4.6: `planned` ist kein Randfall, sondern 44 % eines echten
  Bestands.

## Wiederholen

    TRAIL_GPX=/pfad/zu/Trails.zip python3 tool/trail_match.py \
        --report docs/trail-abgleich-messung-roh.md --private-out ~/pairs.tsv

Der Bericht ist mit `--report` reproduzierbar; die Zahlen oben sind
seine Ausgabe vom 2026-09-27. Eine zweite Sammlung (ein Buddy) wird
gegen dieselbe Datei gemessen, indem beide Zips in einen Ordner
entpackt werden — das Werkzeug nimmt auch ein Verzeichnis.

## Höhen (Issue #14)

Anstieg und Abstieg zählt die App mit Hysterese: Eine Höhenänderung
zählt erst ab einer Schwelle (`kElevationThresholdM`), und vor dem
Hochladen bleibt ein Punkt auch, wenn seine Höhe mehr als
`kSimplifyVerticalM` neben der Geraden liegt. Gemessen am 2026-09-27
mit `tool/elevation_measure.py` an derselben Sammlung wie oben:

- Dateien: 584, davon mit Höhe an JEDEM Punkt: 578 (99 %)
- darunter Trails (< 8 km, bergab): 454, Fahrten: 112
- Höhenschritt Punkt zu Punkt: Median 0,83 m, p90 4,00 m; ganzzahlige
  Werte 32 %

**Ergebnis: Schwelle 3 m, senkrechte Toleranz 2 m.**

### Schwelle — Trails

Auf einem Trail, der bergab läuft, ist fast jeder Meter „bergauf"
Rauschen. Abstieg − Anstieg ist bei jeder Schwelle gleich.

| Schwelle | Anstieg Median | Anstieg p90 | Abstieg Median | Abstieg / Nettogefälle |
|---:|---:|---:|---:|---:|
| 0 m | 4 m | 37 m | 86 m | 1.03 |
| 1 m | 3 m | 31 m | 85 m | 1.02 |
| 2 m | 1 m | 25 m | 83 m | 1.01 |
| 3 m | 0 m | 22 m | 82 m | 1.00 |
| 5 m | 0 m | 18 m | 82 m | 1.00 |
| 8 m | 0 m | 11 m | 81 m | 1.00 |
| 10 m | 0 m | 11 m | 80 m | 1.00 |

### Schwelle — Fahrten (Gegenprobe)

| Schwelle | Anstieg Median | Anstieg / roh |
|---:|---:|---:|
| 0 m | 105 m | 1.00 |
| 1 m | 97 m | 0.97 |
| 2 m | 93 m | 0.92 |
| 3 m | 91 m | 0.88 |
| 5 m | 88 m | 0.82 |
| 8 m | 80 m | 0.73 |
| 10 m | 72 m | 0.69 |

3 m ist die kleinste Schwelle, ab der der Anstieg auf Trails im Median
0 ist und der Abstieg dem Nettogefälle entspricht. Fahrten behalten
dabei 88 % ihres rohen Anstiegs; 5 m (der vorläufige Wert) kostete sie
82 %, 8 m schon 73 %. Offen bleibt der p90 auf Trails (22 m): Ein
Zehntel der Trails trägt noch Scheinanstieg, den nur eine Schwelle
wegbekäme, die auf Fahrten deutlich mehr kostet.

### Importregel mit Schwelle? (nur berichtet)

Die Importregel „Abstieg > 2 × Anstieg" rechnet ROH und bleibt so.
Rechnete sie mit Schwelle, kippten von den Dateien unter 8 km:

| Schwelle | Fahrt → Trail | Trail → Fahrt |
|---:|---:|---:|
| 1 m | 4 | 0 |
| 2 m | 5 | 0 |
| 3 m | 9 | 0 |
| 5 m | 11 | 0 |
| 8 m | 16 | 0 |
| 10 m | 18 | 0 |

### Ausdünnen vor dem Hochladen

Punkte, die übrig bleiben (Median), und Abweichung von Anstieg/Abstieg
gegenüber allen Punkten, je Schwelle. „nur 3 m" ist die Vereinfachung
ohne Höhe.

| senkrecht | Punkte übrig | Δ Anstieg p90 (3 m) | Δ Abstieg p90 (3 m) | Δ Anstieg p90 (5 m) | Δ Abstieg p90 (5 m) |
|---|---:|---:|---:|---:|---:|
| nur 3 m | 38 % | 3 m | 3 m | 4 m | 4 m |
| 1 m | 46 % | 2 m | 2 m | 3 m | 3 m |
| 2 m | 41 % | 2 m | 2 m | 3 m | 3 m |
| 3 m | 40 % | 3 m | 3 m | 3 m | 3 m |
| 5 m | 39 % | 2 m | 2 m | 4 m | 4 m |

Der Bericht rundet auf ganze Meter; ungerundet (Schwelle 3 m) liegt
Δ p90 bei 2,02 m (1 m), 2,21 m (2 m), 2,25 m (2,5 m), 2,76 m (3 m) und
2,50 m (5 m) — oberhalb von 2 m fallen kaum noch Punkte weg, die
Abweichung wächst. 2 m bleibt, auch weil der Wert unter der Schwelle
liegt: Eine Welle, die zählt, übersteht das Ausdünnen.

### Steilstes Stück — Trails

| Fenster | Median | p90 | über 100 % |
|---:|---:|---:|---:|
| 50 m | 26 % | 41 % | 1 |
| 100 m | 22 % | 35 % | 0 |

### Offen

Eine feste Schwelle für alle Geräte ist ein Kompromiss. Später könnte
sie sich am Eingangssignal ausrichten — etwa am Rauschen einer
Aufzeichnung (Signal-Rausch-Verhältnis der Höhenreihe), sodass ein
Barometer eine kleinere Schwelle bekommt als eine GPS-Höhe.

## Tageslimit (Issue #23)

*Gemessen am 2026-09-28, `tool/limit_measure.sql`, lokal auf dem
Datenbank-Container des Supabase-Stacks (Postgres 17.6, arm64).*

Frage: Was kostet ein ganzer Bestand am Stück? Der gemessene Bestand hat
454 Trails; beim alten Limit von 50 in 24 h hätte sein Import zehn Tage
gedauert.

Last, synthetisch nach dem Bestand geformt: 150 verschiedene, kurvige
Trails von 1 bis 6 km, dicht auf 8 × 8 km, im Mittel 330 Punkte je Linie
(alle 10 m — mehr, als die Vereinfachung übrig lässt). Ein Buddy hat sie
schon beigesteuert; dann kommen sie dreimal verrauscht (σ 4 m) als
Import, jede Kopie ist „gleich" und läuft damit durch den teuersten Weg
(Deckung und Fréchet).

| Phase | Aufzeichnungen | Summe | Median | p95 | Max |
|---|---:|---:|---:|---:|---:|
| Bestand (neue Trails) | 150 | 11,4 s | 61 ms | 186 ms | 237 ms |
| Import (alle „gleich") | 450 | 143,8 s | 311 ms | 516 ms | 685 ms |

Danach gibt es genau 150 Trails — keine Kopie wurde zum neuen Trail.

Lesart: Ein ganzer Bestand kostet die Datenbank rund zweieinhalb Minuten
Rechenzeit, verteilt auf einzelne Aufrufe unter einer Sekunde. Das
Live-Projekt (Free-Plan, geteilte CPU) ist langsamer als dieser Rechner;
selbst mit Faktor 4 bleibt jeder Aufruf weit unter dem Statement-Timeout
der API, und ein Konto, das das Limit täglich ausschöpft, kostet einige
Minuten Rechenzeit am Tag. Gegen das Sondieren schützt das Limit nichts,
was der Abgleich nicht ohnehin verbirgt (Konzept 4.6); es begrenzt, was
ein einzelnes Konto an Last erzeugen kann. **Entscheidung (Betreiber,
2026-09-28): 500 in 24 h** (Patch 006).

Wiederholen, gern mit echten Linien statt der synthetischen: auf einer
Wegwerf-Datenbank `supabase/schema.sql` einspielen, dann
`tool/limit_measure.sql` — es hebt das Limit dort auf.


## Vertreter je Trail (Issue #106, 2026-09-30)

Frage aus `docs/konzept-rework.md` (Abschnitt 6): Hilft es, einen
Kandidaten gegen die besten DREI Aufzeichnungen eines Trails zu
vergleichen statt nur gegen die beste (`limit 1` in
`contribute_recording`)? „Gleich" ist nicht transitiv: X ~ Y und Y ~ C
heißt nicht X ~ C. Ist X die beste Aufzeichnung (etwa die lange Version
mit Anfahrt), legt C einen zweiten Trail an, obwohl Y schon am ersten
hängt. Der Selbsttest des Werkzeugs zeigt genau das an drei Linien
(900 m bzw. 850 m Überlappung, X zu C nur 750 m).

Gemessen mit `tool/trail_match.py --simulate 1,3,all`: Die
trail-artigen Dateien (Importregel der App, < 8 km und Abstieg > 2 ×
Anstieg) werden der Reihe nach beigesteuert, wie es die RPC tut —
Vergleich gegen die besten N Aufzeichnungen je Trail, nur „gleich"
hängt an, bei mehreren Treffern die höchste beidseitige Deckung.
Duplikate zählt die Tabelle über Namen: Dateien gleichen Namens meint
der Betreiber als denselben Trail; landet eine davon auf einem anderen
Trail als die erste, hat der Abgleich sie nicht erkannt (Obergrenze —
gleiche Namen können Varianten sein).

| Vertreter je Trail | beigesteuert | Trails | angehängt | Zwillings-Ereignisse | Zwillings-Paare | Namen mehrfach | davon auf anderem Trail |
|---|---|---|---|---|---|---|---|
| 1 | 458 | 453 | 5 | 0 | 0 | 5 | 2 |
| 3 | 458 | 453 | 5 | 0 | 0 | 5 | 2 |
| alle | 458 | 453 | 5 | 0 | 0 | 5 | 2 |

Die zwei „auf anderem Trail" liegen weit auseinander (kein Vergleich
innerhalb von 25 m): verschiedene Trails mit demselben Namen, keine
übersehenen Duplikate.

**Lesart: Mit einem einzelnen Bestand lässt sich die Frage nicht
beantworten.** Fast jeder Trail hat hier genau eine Aufzeichnung (453
Trails aus 458 Dateien), also gibt es keine zweite, gegen die ein
Vergleich etwas ändern könnte — und kein Duplikat, das er verhindern
müsste. Das Problem aus dem Rework entsteht erst mit MEHREREN Nutzern
(jeder bringt seine Version desselben Trails) und mit wieder gefahrenen
Stücken aus Fahrten (Zerlege-Blatt). Beides gibt es im Bestand nicht.

**Folge: `contribute_recording` bleibt bei `limit 1`**, bis Daten mit
mehreren Aufzeichnungen je Trail da sind — Schwellen und Verfahren sind
gemessen, nicht geraten (`CLAUDE.md`). Wiederholen, sobald Buddys
beigesteuert haben: Die Simulation braucht dann deren Linien, und die
liegen nicht beim Betreiber — der Weg ist eine Auswertung auf einer
Kopie der Datenbank (Aufzeichnungen je Trail, Anteil mit mehr als einer,
Zwillingstreffer bei `limit 3`), nie eine Funktion der App.
