# TrailBuddy — Arbeitsregeln für `lib/features/official/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Offizielle Trails in der App** (#13, `lib/features/official/`):
  Index und Regionen von `raw.githubusercontent.com` (Daten-Branch),
  erst ab Zoom 8 (`kOfficialMinZoom`) und nur für Regionen, deren Rahmen
  den Ausschnitt berührt; der Index je App-Lauf einmal, eine Region nur
  bei neuem `updated`. Gemerkt in `official_trails/` im App-Verzeichnis
  (vom Backup ausgenommen); ohne Netz gilt der gemerkte, auch ältere
  Stand. Im Web nur für die Laufzeit (den Rest macht der HTTP-Cache).
  Dateinamen aus dem Index werden geprüft (werden zu Pfaden), eine
  fremde Formatversion lässt die Ebene leer. Gestrichelt in
  `officialViolet`, gesperrte Teile grau (Orange ist die Meldung eines
  Buddys), zwischen Orten und Netz; ein Tipp auf das Netz gewinnt. Das
  Blatt nennt Status und Schwierigkeit IMMER mit der Quelle, kein
  S-Grad. Schalter im Blatt „Kartenebenen"
  (`Settings.officialTrailsEnabled`, Vorgabe an); aus heißt: keine
  Anfrage. Der Test-Harness hängt `FakeOfficialTrailsSource` und
  einen Speicher-Cache ein. „Auch ausgeschildert als …" im Trail-Blatt
  (`official_match.dart`, `OfficialSignposts`): Deckung wie im Abgleich
  (15 m, 0,8, Abtastung 5 m) — **dritter Spiegel der Schwellen**
  neben SQL und `tool/trail_match.py`, im selben PR mitändern; seit
  0.20.0 stehen sie als `kMatch*` in `lib/core/line_geometry.dart`,
  zusammen mit Projektion, Abtastung und Gitter, geteilt mit dem
  Zerlege-Blatt. Ohne Fréchet (nichts wird verschmolzen); Varianten
  zählen nicht gegen „derselbe". Das Blatt lädt die Region des Trails
  selbst nach.
