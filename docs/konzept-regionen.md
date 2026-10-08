# Regionen per Konfiguration

**Stand:** 2026-10-08 · **Issue:** #220 · **Fahrplan:** 18c in #156 ·
**Grundlage:** die Messung `docs/karte-welt-messung.md` (18b). Ergänzt
`docs/konzept-offline-karten.md`: Dort steht, wie die Karte ohne Empfang
funktioniert, hier, wie sie über DACH hinaus kommt. Kanada ist die erste
Region außerhalb Europas.

## 1. Was der Betreiber entschieden hat (2026-10-08)

1. **Die App wählt die Region selbst.** Jede Region ist eine eigene
   Kartenquelle mit ihren Grenzen; die Karte zeigt, was im Bild liegt,
   und ein gespeicherter Bereich lädt aus der Region, in der er liegt.
   Es gibt keinen Regionswähler und keinen neuen Gebietsbegriff in der
   Oberfläche. Das ist dieselbe Linie wie `konzept-offline-karten.md`
   §5 („ein Mechanismus für beide Plattformen ist mehr wert als zwei
   Gebietsbegriffe").
2. **Die Höhen baut CI, notfalls in Teilen.** Wiederholbar aus der
   Cloud, nicht einmalig auf dem Rechner des Betreibers.
3. **Die Übersicht kommt je Region als Download.** Die DACH-Übersicht
   bleibt im Binary. Jede andere Region bringt ihre Übersicht z0–7 mit
   dem ersten gespeicherten Bereich dort mit, und „Meine Bereiche" zeigt
   sie mit Größe und Löschen-Knopf.
4. **Alles bleibt im Free-Kontingent von R2** (10 GB-Monat Speicher).
   Das entscheidet den Zuschnitt von Kanada (Abschnitt 3).

## 2. Was eine Region ist

Eine Region ist eine Zeile in **`tool/regions.json`**, der einen Quelle
für alle Workflows:

| Feld | Bedeutung | DACH | Kanada |
|---|---|---|---|
| `id` | Kennung, Pfad auf dem Host | `dach` | `ca` |
| `name` | Anzeige in „Meine Bereiche" | DACH | Kanada |
| `bbox` | Rahmen W,S,E,N — für die App und als Zuschnitt der Begleitebenen | 5,5 / 45,5 / 17,5 / 55,5 | −133,2 / 41,6 / −52,6 / 55,0 |
| `map` | Zuschnitt der Karte: Rechteck oder Ländergrenze (Natural Earth, festgenagelt wie in `map-data.yml`) mit Breitengrad-Kappe | Rechteck | `ISO_A2_EH=CA`, südlich 55° N |
| `extracts` | Geofabrik-Auszüge für Wege und Orte | die heutige Liste (#73) | `north-america/canada` |
| `overview` | Übersicht z0–7: mitgeliefert oder vom Host | mitgeliefert | Host, ganz Kanada |
| `day` | Tag im Monat, an dem neu gebaut wird | 1. | 15. |

Drei Regeln, die daraus folgen:

- **Regionen überschneiden sich nicht.** Ein Punkt gehört höchstens zu
  einer Region; für einen Bereich zählt seine Mitte. Kommen später zwei
  Nachbarn dazu (z. B. DACH und Frankreich), wird die Grenze zwischen
  ihnen gezogen, nicht doppelt gebaut.
- **Die Werkzeuge bleiben, wie sie sind.** `map_tiles.py`,
  `height_tiles.py`, `way_archive.py`, `poi_extract.py` nehmen schon
  heute ein Rechteck oder eine Region (18b). Die Workflows lesen nur
  ihre Eingaben aus `tool/regions.json` statt aus festen `DACH_BBOX`-Zeilen;
  `test/release_workflow_test.dart` hält Datei und Workflows zusammen.
- **Ein Lauf baut eine Region.** Jeder Workflow bekommt die Eingabe
  `region` (von Hand) und einen Zeitplan je Region. So liegt nie mehr
  als eine Vorgängerdatei gleichzeitig im Bucket (Abschnitt 3), und ein
  kaputter Kanada-Lauf fasst DACH nicht an.

## 3. Was in 10 GB passt

Gemessen am 2026-10-08 aus der Cloud gegen den Protomaps-Bau `20261007`
(`tool/map_tiles.py plan --region`, Natural Earth 1:50 m, mit
`shapely` am Breitengrad gekappt):

| Kanada bis z13 | z13-Kacheln | Karte |
|---|---:|---:|
| ganz (18b) | 2,16 Mio. | 4,30 GB |
| südlich 62° N | 867 000 | 3,03 GB |
| südlich 60° N | 744 000 | 2,75 GB |
| südlich 55° N | 470 000 | **1,99 GB** |

Der Norden ist viel Fläche für wenig Karte: Nördlich von 55° N liegen
78 % der Kacheln, aber nur 58 % der Bytes. **Gewählt ist 55° N**
(Betreiber, 2026-10-08: „Nur Südkanada ist für Trails relevant"). Drin
liegen alle bekannten Trailgebiete — North Shore, Squamish, Whistler,
Kamloops, die Kootenays, Canmore und Bragg Creek, Prince George
(53,9° N), Smithers (54,8° N), dazu der besiedelte Süden von Ontario
und Québec, die Seeprovinzen und die Insel Neufundland. Draußen bleiben
die Territorien, Labrador und der Norden der Provinzen. Die Übersicht z0–7 deckt trotzdem ganz Kanada
(34 MB): Auch nördlich davon zeigt die Karte Land, Wasser, Orte und
große Straßen in groben Zügen, nur keine Bereiche und keinen Planer.
Die Kappe ist eine Zahl in `tool/regions.json`; wer später Whitehorse
will, setzt sie auf 61° N und misst den Bucket nach.

Der Bucket im Dauerzustand, je Ebene eine Datei:

| | DACH | Kanada (bis 55° N) |
|---|---:|---:|
| Karte | 2,8 GB | 2,0 GB |
| Höhen | 0,15 GB | ~0,6–0,7 GB (geschätzt aus 470 000 Kacheln × 1,2–1,5 KB; der `plan`-Lauf misst es) |
| Wege | 0,13 GB | 0,005 GB |
| Orte | 0,17 GB | 0,02 GB |
| Übersicht | im Binary | 0,034 GB |
| **zusammen** | **3,3 GB** | **~2,7–2,8 GB** |

**Rund 6,1 GB im Dauerzustand.** Das reicht nur, wenn sich eine Regel
ändert: Heute bleibt die Vorgängerdatei einen ganzen Lauf lang liegen,
also einen Monat (`map-data.yml`, „sessions in flight keep the previous
file"). Mit Kanada wären das zwei Karten je Region und zusammen gut
11 GB.

**Neu: Die Vorgängerdatei geht nach zwei Tagen.** Eine Sitzung, die ihre
Verzeichnisse gemerkt hat, lebt Stunden, nicht Wochen; nach dem Wechsel
des Zeigers holt jede neue Sitzung das neue Manifest. Ein kleiner
Workflow `r2-prune.yml` (täglich, nur löschend) entfernt jede Datei, die
kein aktuelles Manifest nennt und deren Nachfolger seit mehr als 48 h
gilt. Er nutzt dieselbe Liste wie das Inventar (#230), und „nennt kein
Manifest" ist dieselbe Prüfung, die das Inventar heute schon rot macht,
nur umgekehrt.

R2 rechnet Speicher als Monatsmittel ab (GB-Monat). Zwei Tage mit der
Vorgängerkarte einer Region kosten im Mittel rund 0,15–0,2 GB. Weil die
Regionen an verschiedenen Tagen bauen (Abschnitt 2), liegt nie mehr als
eine Vorgängerdatei gleichzeitig da: **Spitze ~8,9 GB für zwei Tage,
Mittel ~6,3 GB.** Das Monats-Inventar (#230) zeigt den Stand; wird es
knapp, ist die nächste Stellschraube der Breitengrad, nicht der Zoom —
z13 braucht der Planer für sein Wegenetz (#158).

**Die Höhen passen damit in einen Job.** 470 000 Kacheln gegen 98 640 im
DACH-Lauf (17 min) sind linear hochgerechnet rund 1,4 h. Die Teilung,
die der Betreiber für 4,5–6 h freigegeben hat, ist also erst nötig,
wenn der `plan`-Lauf mehr als 4 h ansagt. Dann baut ein Matrix-Job je
Breitenstreifen ein Archiv, und das Manifest nennt die Teile.

## 4. Auf dem Host

Die alten Pfade bleiben, wie sie sind: Apps bis 0.103 lesen `dach.json`,
`pois.json`, `heights.json` und `ways.json` an der Wurzel, und das tun
sie weiter. Neu dazu kommt:

```
trailbuddy/regions.json             der Index: id, name, bbox, Manifeste
trailbuddy/ca/map.json              → ca/map-<build>.pmtiles
trailbuddy/ca/heights.json          → ca/heights-<build>.pmtiles
trailbuddy/ca/ways.json             → ca/ways-<build>.pmtiles
trailbuddy/ca/pois.json             → ca/pois-<build>/…
trailbuddy/ca/overview.json         → ca/overview-<build>.pmtiles
```

DACH steht im Index mit seinen alten Pfaden. `regions.json` schreibt der
letzte Schritt jedes Laufs neu, und zwar nur mit den Regionen, deren
Kartenmanifest wirklich da ist: Eine Region, die nie veröffentlicht
wurde, gibt es für die App nicht. Kein neues Netzziel (derselbe Host),
also keine Änderung an der Datenschutzerklärung; sie nennt den Host und
nicht die Region.

Die Manifeste behalten ihre Form. Nur die Namensprüfung der App lässt
ein Unterverzeichnis zu (`^(?:[a-z]{2,8}/)?<art>-\d{8}\.pmtiles$`),
weiter ohne `..` und ohne Schrägstrich am Anfang.

## 5. In der App

Alles hängt an EINEM neuen Provider, `regionsProvider` (der Index, mit
Frist wie das Kartenmanifest, gemerkt wie die Manifeste in #155). Ohne
Index, also ohne Empfang, vor dem ersten Abruf oder bei kaputtem Host,
gilt die eingebaute Liste mit genau DACH und den alten Pfaden: Die App
benimmt sich dann wie 0.103.

- **Online-Karte:** eine Quelle je Region, jede mit ihrem `bbox` als
  `bounds`. MapLibre fragt außerhalb davon nichts, und die Range-Anfragen
  einer Region beginnen erst, wenn sie im Bild ist. Der Composer kann
  das schon: Bereiche sind heute bereits eigene Quellen mit eigenen
  Ebenen. flutter_map bekommt je Region einen Lieferanten. Die Übersicht
  einer Region liegt online wie offline unter ihrer Karte.
- **Wege, Höhen, Orte, Nachladen des Planers (#187):** je Position die
  Region, in der sie liegt. Das Raster der Orte (0,1° × 0,15°) und die
  z13-Kacheln von Wegen und Höhen sind weltweit dieselben, es ändert
  sich also nur, welches Manifest gefragt wird.
- **Gespeicherte Bereiche:** `StoredArea` bekommt `region` (fehlt das
  Feld, gilt `dach`, alle heutigen Bereiche). Geplant, geladen und
  aktualisiert wird gegen die Manifeste DIESER Region. Ein Bereich, der
  über den Rand seiner Region reicht, wird nicht geteilt; was jenseits
  liegt, fehlt im Archiv, und die Größe vorher sagt es schon richtig,
  weil sie aus dem Verzeichnis kommt.
- **Übersicht je Region:** Der erste Bereich in einer Region ohne
  mitgelieferte Übersicht lädt sie dazu (Größe im Dialog). „Meine
  Bereiche" zeigt sie als eigene Zeile; gelöscht wird sie mit dem
  letzten Bereich der Region oder von Hand. Sie gehört in dieselben
  Backup-Ausschlüsse wie die Bereiche.
- **Gesehenes bleibt liegen (#155):** Die Schlüssel tragen schon heute den
  Archivnamen, und der trägt jetzt das Verzeichnis der Region — der
  Browser-Speicher und MapLibres Ambient Cache unterscheiden die
  Regionen also von selbst. Gemerkt wird das Manifest je Region.

Was sich NICHT ändert: Trails, Fahrten, Abgleich und Buddys kennen keine
Regionen. Ein Trail in Kanada ist ein Trail wie jeder andere; ohne
Kartenregion dort hätte er bisher nur keine Karte unter sich gehabt.

## 6. Reihenfolge

1. **Dieses Konzept** (docs, kein Bump).
2. **`tool/regions.json` und die Workflows** (`.github/`, `tool/`, kein
   Bump): Eingabe `region`, Zeitplan je Region, Kanada mit Polygon und
   Kappe, `regions.json` auf dem Host, `r2-prune.yml`. DACH baut danach
   byte-gleich weiter (gleiche Pfade, gleiche Box), ein `plan`-Lauf je
   Ebene für Kanada misst Höhen und Bauzeit. Danach veröffentlicht der
   Betreiber Kanada (`publish`, die R2-Secrets hat nur CI).
3. **Die App liest Regionen** (feat ⇒ MINOR): Index, Quellen je Region,
   Begleitebenen je Position, `StoredArea.region`. Tests mit zwei
   Regionen im Harness; mit nur DACH im Index dasselbe Bild wie 0.103.
4. **Die Übersicht je Region** (feat ⇒ MINOR): Download mit dem ersten
   Bereich, Zeile in „Meine Bereiche", Backup-Ausschluss.
5. **18d (#229) danach:** eine ganze Region auf einmal speichern —
   dafür ändert sich §5 von `konzept-offline-karten.md`, nicht hier.

Nach 3 und 4 ist 🚀 C fällig, zusammen mit 18d.

## 7. Offen

- **Höhen in Kanada**: Die Schätzung (0,6–0,7 GB, ~1,4 h) misst erst der
  `plan`-Lauf in Schritt 2. Liegt er über 4 h, kommt die Teilung.
- **Wege in Kanada** sagen wenig (3 % benotet, 18b). Sie werden trotzdem
  gebaut, weil sie fast nichts kosten und die Ebene sonst ein Sonderfall
  wäre; die Legende sagt ohnehin „unbekannt".
- **Class-B-Operationen** wachsen mit den Nutzern, nicht mit den
  Regionen (#55). Daran ändert dieses Konzept nichts.
