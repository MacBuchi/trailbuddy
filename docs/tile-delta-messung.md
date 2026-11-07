# Messung: Wie viele Kacheln ändert ein neuer Kartenbau? (#479)

Stand 2026-11-07. Frage aus #479: Lohnt eine kleine Delta-Datei je Bau
(die Kachel-Ids, deren Bytes sich geändert haben), damit „Aktualisieren"
nur die geänderten Kacheln holt statt aller? Gemessen mit
`tool/tile_delta.py` (Selbsttest in CI), bevor etwas gebaut wird.

## Wie gemessen

- **Quelle:** die Protomaps-Tagesbauten direkt
  (`build.protomaps.com/<tag>.pmtiles`). Unser R2-Bau `dach-20261101`
  trägt die Bytes des Protomaps-Baus 20261101 (`map_tiles.py check`
  beweist das bei jeder Veröffentlichung) — gemessen wurde also genau
  unser Bestand, ohne einen einzigen R2-Lesezugriff.
- **Fläche:** die DACH-Box `5.5,45.5,17.5,55.5`, z6–z13 (132 107 Kacheln,
  2,61 GB). z0–z5 sind 21 Kacheln und zählen nicht.
- **Zwei Durchgänge:** Die Verzeichnisse beider Bauten ganz (2,6 MB):
  neu, weg oder andere Länge ist sicher geändert. Bei gleicher Länge die
  Bytes einer Stichprobe (300 je Zoom): gleich, anders, oder „Bytes
  anders, Inhalt gleich" (entpackt verglichen).
- **Größe als Ersatz für Ort/Wald:** Drittel der gespeicherten Länge je
  Zoom. Eine Ortskachel ist groß, Wald und Feld sind klein — kein
  Landnutzungsplan, aber ein ehrlicher Stellvertreter.
- **Grenze:** Protomaps hält seine Tagesbauten nur etwa sechs Tage
  (1.–6. Nov. erreichbar, ältere 404), unser Vorbau geht nach 48 h
  (`r2-prune.yml`). Ein Monatsabstand, unser Takt, ist heute nicht
  messbar — siehe „Was noch fehlt".

## Ergebnis

**Die Bauten sind byte-stabil.** In rund 10 000 verglichenen Paaren kein
einziges „Bytes anders, Inhalt gleich": Was gleich bleibt, bleibt Byte
für Byte gleich. Eine Id-Liste reicht, ein Inhaltsvergleich in der App
ist nicht nötig.

Abstand vom Bau 20261101 (Kacheln geändert / Bytes, die ein Aktualisieren
mit Delta holte):

| Abstand | Kacheln geändert | Bytes mit Delta | Delta-Datei (gzip) |
|---|---|---|---|
| 1 Tag | 4,4 % | 267 MB (10,0 %) | 4,1 KB |
| 2 Tage | 6,7 % | 431 MB (16,1 %) | 5,5 KB |
| 3 Tage | 9,4 % | 557 MB (20,8 %) | 7,1 KB |
| 4 Tage | 11,7 % | 651 MB (24,3 %) | 8,3 KB |
| 5 Tage | 13,4 % | 736 MB (27,5 %) | 9,0 KB |
| 1 Tag (5.→6.) | 3,6 % | 242 MB (9,0 %) | 3,4 KB |

Je Zoom, 5 Tage (1.→6. Nov.), Anteil geändert, dazu kleines / mittleres /
großes Drittel:

| Zoom | Kacheln | geändert | klein / mittel / groß |
|---|---|---|---|
| z6 | 12 | 100 % | 100 / 100 / 100 % |
| z7 | 36 | 97 % | 92 / 100 / 100 % |
| z8 | 120 | 92 % | 78 / 100 / 97 % |
| z9 | 432 | 80 % | 59 / 90 / 92 % |
| z10 | 1 610 | 59 % | 33 / 66 / 78 % |
| z11 | 6 279 | 32 % | 16 / 32 / 48 % |
| z12 | 24 978 | 21 % | 8 / 19 / 35 % |
| z13 | 98 640 | 9,3 % | 2,8 / 8,1 / 16,8 % |

Was daraus folgt:

1. **Die oberen Zooms ändern sich fast immer** — eine Kachel z6–z9 deckt
   so viel Fläche, dass irgendwo darin immer jemand kartiert. Sie sind
   aber klein; die Bytes sitzen in z12/z13.
2. **Geändert wird vor allem in Orten.** Das große Drittel von z13 ändert
   sich sechsmal so oft wie das kleine. Ein Bereich, wie ein Biker ihn
   speichert (Wald, Hang, Dorf), liegt eher unter dem DACH-Schnitt von
   27 % der Bytes in fünf Tagen.
3. **Die Delta-Datei ist winzig:** einstellige KB je Bau als sortierte
   Varint-Abstände, gzip. Eine Hash-Liste je Kachel wäre ≥ 1 MB (132 107
   × 8 Bytes, Hashes packen nicht). Beides liegt weit unter der 512-MB-
   Grenze des Edge-Caches, die Id-Liste kostet aber nichts.
4. **Die Änderungen wachsen langsamer als die Zeit:** Tag für Tag kommen
   rund 10 % der Bytes neu dazu (5.→6. allein 9 %), die Vereinigung über
   fünf Tage ist aber 27,5 %, nicht 50 % — dieselben Ortskacheln ändern
   sich immer wieder.

## Hochrechnung auf einen Monat — nur eine Spanne

Aus fünf Punkten auf 30 Tage: logarithmisch ≈ 46 % der Bytes (23 % der
Kacheln), als Potenzgesetz ≈ 87 % (48 %). Die Spanne ist zu breit, um
darauf zu bauen. Sicher ist nur: Ein monatliches Aktualisieren mit
Delta spart **mindestens** etwas, im Wald mehr als im Schnitt — und #478
(unterwegs geladene Kacheln, aktualisiert bei Nutzung) spart dasselbe.

## Was noch fehlt

- **Der Monatsabstand.** `map-data.yml` misst ab jetzt bei jedem
  Veröffentlichen den öffentlichen aktuellen Bau gegen das frische
  Extrakt (Schritt „Measure the delta against the current build",
  Stichprobe 300 je Zoom, Ergebnis in der Run-Summary). Der nächste Lauf
  am 2026-12-01 liefert die Zahl für 30 Tage; danach wird hier
  entschieden. Der Schritt hält nie eine Veröffentlichung auf.
- **Die Wege.** `way-data.yml` misst ebenso, dort jedes Paar (das Archiv
  ist ~130 MB und kommt in einem GET), auch im Modus `plan` — also
  jederzeit ohne Veröffentlichung. Der Bau ist deterministisch
  (`gzip … mtime=0`, sortierte Kacheln); gegen sich selbst gemessen:
  0 von 84 021 geändert.
- **Die Höhen** brauchen kein Delta: Das DEM ist statisch, ein neuer Bau
  kommt nur mit neuem Format oder neuer Box — dann ist ohnehin alles neu.

## Form, falls es sich lohnt

Je Bau eine Datei `<stamm>-<bau>.delta` neben dem Archiv: der Vorbau,
gegen den gerechnet wurde, und die geänderten, neuen und entfernten Ids
als Varint-Abstände, gzip. Delta-Dateien werden **nicht** weggeräumt
(einige KB je Monat), damit eine App mehrere Bauten zurück die Kette
gehen kann; fehlt ein Glied, holt sie alles wie heute. Gerechnet wird im
Workflow über jedes Paar (das alte Archiv in einem GET), nicht über eine
Stichprobe.
