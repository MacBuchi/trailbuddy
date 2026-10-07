# TrailBuddy — Design

*Stand 2026-09-29. Quelle: das Design-Projekt des Betreibers in Claude
Design („TrailBuddy Design", Turns 1–4), abgelegt in diesem Ordner. Hier
steht, was davon gilt und wo es im Code umgesetzt ist.*

Die Reihenfolge der Umsetzung (je ein PR) steht am Ende. Was hier steht,
ist verbindlich wie das Konzept: Wer im Code davon abweicht, ändert diese
Datei im selben PR. **Die Entwurfsdatei ist die Vorlage, diese Datei die
Entscheidung** — wo beide sich widersprechen (etwa Text in `#4F8A10` auf
Hell), gilt diese hier.

## 0. Die Vorlage in diesem Ordner

Das Design-Projekt, so unverändert wie möglich (Stand des letzten Syncs
2026-09-29 06:54 UTC):

| Datei | Was | Herkunft |
|---|---|---|
| `TrailBuddy Design.dc.html` | der Entwurf, alle vier Turns auf einer Leinwand | unverändert aus dem Projekt |
| `support.js` | die Laufzeit von Claude Design, die die Datei rendert | unverändert |
| `github.md` | die Sync-Notiz von Claude Design (welche Repo-Dateien es gelesen hat) | unverändert |
| `web/favicon.png`, `web/icons/Icon-512.png`, `web/icons/Icon-maskable-512.png` | die damaligen App-Symbole, die Claude Design aus dem Repo kopiert hatte (noch das Flutter-Standardsymbol) | byte-gleich aus Commit `8e10007` |
| `notification_icon_512.png`, `notification_icon_96.png` | das Statusleisten-Symbol (1f): weiß, Alpha, 12 % Rand | **neu gerendert** mit `tool/brand_icons.py` (`symbol_svg(px, NOTIFICATION_SCALE, None, 0, color="#FFFFFF", size="M")`) — das Original kam nur als Text über die Schnittstelle, byte-genau war es nicht zu übernehmen; seit Turn 1h bzw. C3 die neue Form, ohne die Herkunftsdaten (C2PA) des Originals |

**`trailbuddy-logo/`** ist der Handoff des Logos „Serpentine C3"
(2026-10-01), so abgelegt, wie er aus Claude Design kam: `README.md`
(Anweisungen), `reference/TrailBuddy Logo C3.dc.html` (die Leinwand mit
der parametrischen Form, `build()`), `flutter/trailbuddy_logo.dart`
(Widgets mit den abgetasteten Stichproben), fertige PNGs und SVGs. Die
App nimmt davon NUR die Stichproben — sie stehen in
`tool/brand/logo_c3.json`, und `tool/brand_icons.py` erzeugt daraus alle
Symbole und `lib/core/widgets/trailbuddy_logo_geometry.dart`. Die
fertigen Bilder des Handoffs sind Vergleich, nicht Quelle (Abschnitt 4).

Nicht übernommen: `.thumbnail`, das Vorschaubild, das Claude Design selbst
für die Projektübersicht erzeugt.

**Ansehen:** `TrailBuddy Design.dc.html` im Browser öffnen (sie lädt
`support.js` daneben). Die Datei holt Schriften und Symbole von Google
Fonts und React von unpkg.com — das betrifft nur die Vorlage beim Ansehen,
nie die App. Namen, Trails und die Mailadresse darin sind Beispiele.

## 1. Grundidee

Sportlich und kartografisch: ein Signal-Lime als Marke, Mono-Ziffern für
Länge, Höhenmeter und S-Grad, schmale Großbuchstaben für Titel. Hell und
dunkel. **Die Farbe eines Trails sagt seine Schwierigkeit** — in
Pistenfarben, auf der Karte, im Streifen der Liste und im Schild
(Betreiber, 2026-09-29: „nicht nach Buddy / mein Trail, sondern nach den
Schwierigkeitsstufen"). Der Entwurf hatte es umgekehrt (Farbe =
Beziehung, Schwierigkeit nur als Form und als Schalter „Pisten-Brille");
das gilt seit 0.42.0 nicht mehr. Wem ein Trail gehört, sagt nur noch das
Wort („MEIN", „JAN, MIRA", „Du und 2 Buddys") — farblich gar nicht. Der
Charakter bleibt Symbol, nie Farbe: Eine Linie trägt nur eine Farbe, ein
Trail bis zu zwei Merkmale.

## 2. Farben (Turn 1a, 4a) — `lib/core/app_colors.dart`

| Token | Dunkel | Hell |
|---|---|---|
| Grund | `#0E1411` | `#F3F2EC` |
| Fläche | `#161E19` | `#FFFFFF` |
| Fläche 2 | `#1F2923` | `#ECEBE4` (nicht im Entwurf) |
| Linie | `#2A3630` | `#E4E3DB` |
| Text | `#F2F4EF` | `#131A16` |
| gedämpft | `#9AA69D` | `#5E6B62` |
| Knopf | `#B6F04A`, Schrift `#0E1411` | derselbe |
| Marke als Zeichen (Logo) | `#B6F04A` | `#4F8A10` („Marke auf Hell") |
| Marke als Text | `#B6F04A` | `#3D6E0B` ¹ |
| Hinweis als Text | `#FFD23F` | `#7A5C00` ¹ |

¹ Abweichung vom Entwurf, der `#4F8A10` auch für Text zeigt: Als Text
erreicht es auf Weiß nur 4,2:1, verlangt sind 4,5:1. Dasselbe für Warnung
(`#A94510`) und Buddy (`#0A7299`) als Text, und für das Hinweis-Gelb
(`#F2B600`, 1,9:1) als Wort in der Liste („NEUER HINWEIS", seit 0.38.0).
`test/core/app_theme_test.dart` prüft jedes Paar.

**Trail-Farben = Schwierigkeit** (Linie, Streifen, Schild;
`GradePalette`, seit 0.42.0):

| Stufe | Dunkel | Hell (auch Karte) | Form auf der Karte |
|---|---|---|---|
| S0 | `#4CC46E` | `#1F7A3A` | durchgezogen |
| S1 | `#5A9BF0` | `#1F6FD1` | durchgezogen |
| S2 | `#F0605C` | `#C62828` | durchgezogen |
| S3 | `#F2F4EF` | `#131A16` | durchgezogen |
| S4, S5 | `#F2F4EF` | `#131A16` | Saum gestrichelt (seit 0.51.0; davor die Linie) |
| ohne Einschätzung | `#9AA69D` | `#6B756F` | durchgezogen |
| **Uphill** (schlägt die Stufe) | `#E060D0` | `#B0279C` | durchgezogen; im Schild ein Pfeil ↗ statt der Form |

**Uphill** (Betreiber, 2026-09-29: „hier macht Symbol und Farbe Sinn"):
Die Pistenfarben beschreiben eine Abfahrt; ein Trail, unter dessen
angezeigten zwei Merkmalen Uphill ist (dieselbe Lesart wie die Filter),
trägt Magenta statt seiner Stufe — auf der Karte, im Streifen und im
Schild. Das Schild behält den Grad („↗ S2"): Er sagt, wie technisch die
Auffahrt ist. EINE Regel für alle drei Stellen: `trailColorOf` in
`grade_shield.dart`. Magenta seit 0.77.2 (#195, Betreiber): Das Petrol
davor (`#00796B`) lag im Farbton 35° neben S0-Grün und sah auf der Karte
gleich aus; Violett heißt „offiziell". Ein Test verlangt ≥ 40° Abstand im
Farbton zu S0–S2, offiziell, Marke und Buddy (`app_theme_test.dart`). Das
Rosa der Kandidaten liegt nah, steht aber nur in der Vorschau des
Zerlege-Blatts.

Die Töne des Entwurfs (S0 `#2E9E4F`, S2 `#D6322F`) sind nachgedunkelt:
Auf ihnen steht im Schild weiße Schrift, verlangt sind 4,5:1. Im Dunklen
hellere Töne mit dunkler Schrift, und „schwarz" ist dort die Textfarbe —
ein schwarzer Streifen auf dunkler Karte verschwände. Jede Stufe hat
≥ 3:1 auf Fläche, Grund und dem Landton der Karte (Test).

**Der Zustand eines Trails (#101, Rework E9) ist die Art der Linie**,
nie eine Farbe — Farbe heißt Schwierigkeit (`trailLineStyleOf` in
`grade_shield.dart`, eine Regel für beide Engines):

| Zustand | Linie |
|---|---|
| 5 top gepflegt, 4 gut, keiner | durchgezogen |
| 3 ausgefahren | bröckelig (lange Striche, kurze Lücken, 10/3) |
| 2 abgerockt | gestrichelt (5/5) |
| 1 kaum fahrbar | gestrichelt und verblasst (45 %) |

Nur ein BESTÄTIGTER Zustand zählt; ein unbestätigter steht verblasst im
Blatt. Weil die Linie den Zustand trägt, wandern **S4/S5 auf den Saum**:
der weiße Rand gestrichelt (6/4). Der Saum ist auf beiden Engines eine
eigene, breitere Linie darunter (in flutter_map eigens gezeichnet, weil
dessen Rand sonst das Muster der Linie teilt). Mit Warn- oder
Hinweis-Rand ist der farbige Rand gestrichelt. Wartend (#30) bleibt
gestrichelt (12/8) und blass.

**Zustände liegen als Rand UM die Linie, nie auf ihr:**

| Bedeutung | Dunkel | Hell | Form |
|---|---|---|---|
| Gesperrt / Warnung | `#FF8A3D` | `#D9591A` | Leuchtrand (schlägt den Hinweis); als Wort in der Liste |
| Neuer Hinweis | `#FFD23F` | `#F2B600` | Leuchtrand; Kartenrand in der Liste |

**Andere Linien** (keine Trails des Netzes, keine Stufenfarbe):

| Bedeutung | Dunkel | Hell | Form |
|---|---|---|---|
| Mein Trail / Von Buddy | `#B6F04A` / `#5AD0F0` | `#4F8A10` / `#0B84B0` | nur noch Symbole und Vorschau „bekannt" im Zerlege-Blatt, keine Trail-Linie |
| Offiziell | `#B58CFF` | `#7B4FD6` | gestrichelt |
| Kandidat | `#FF6BA8` | `#D1336F` | „eine Frage" |
| Meine Fahrt / Position | `#E8ECE6` | `#2A332E` | |

**Die Karte ist hell** (Turn 4: „Die Karte (Protomaps light) ist hell, und
in praller Sonne liest sich dunkel schlechter"). Turn 1 zeigte noch eine
dunkle „Nacht-Karte"; Turn 4 hat das ersetzt. Deshalb zeichnet die Karte
in BEIDEN App-Modi den hellen Satz mit weißem Saum (Breite + 4):
`AppColors.mapLines`. Der dunkle Satz färbt Symbole und Streifen auf den
dunklen Flächen der App.

## 3. Schriften — `lib/core/app_theme.dart`, `assets/fonts/`

- **Barlow Condensed** 700/800 — Titel, gern in Großbuchstaben
  („TRAILS", „ROSSKOPF SÜD").
- **Barlow** 400–600 — Text.
- **JetBrains Mono** 500 — ALLE Zahlen: km, Hm, S-Grad, Zähler
  (`AppFonts.numbers`).

Als Assets gebündelt (SIL OFL), nie `google_fonts` — die App muss offline
gleich aussehen.

## 4. Logo (Turn 1b, Form seit C3) — `lib/core/widgets/trailbuddy_logo.dart`, `tool/brand_icons.py`

Die **Serpentine C3 — zwei Kehren mit Anliegern, am Ende auslaufende
Striche**, als gefüllte FLÄCHE im 100er-Raster (keine Linie mit
Strichstärke):

```
Kehren      r 13 (oben) und r 16 (unten), über eine gemeinsame Tangente
Breite      11 → 8 entlang der Strecke; die Anlieger nur nach außen breiter
L ≥ 32 px   zwei Endstriche (Breite 6 / 4)       — App-Symbole, Login, Splash, Loader
M 20–28 px  ein Endstrich (Breite 8)             — Statusleiste, Knopf, Kopfzeile
S ≤ 18 px   keiner, längerer Auslauf             — Favicon, kleine Bilder
Hülle (L)   x 14…86, y 17…83 — Mitte des Rasters, fernster Punkt 48,5
```

Die Form steht als Stichproben der Mittellinie in
`tool/brand/logo_c3.json` (je Größe 241 Stück `[x, y, nx, ny,
halbeBreiteLinks, halbeBreiteRechts]` plus Endstriche). **Ein Abschnitt
a…b der Strecke ist eine Fläche** (`LogoGeometry.range` in Dart,
`outline()` im Skript, dieselbe Rechnung): linker Rand, runde Kappe in
der Streckenbreite, rechter Rand zurück, Kappe — dazu die Endstriche im
Abschnitt als Pillen. Daraus kommen Logo (`range(0, total)`), das Einzeichnen
des Loaders und das Zeichnen im Splash. Die optische Größe wählt
`logoSizeFor` nach der Kantenlänge (≥ 30 px L, ≥ 19 px M, sonst S).

- App-Symbol: dunkles Zeichen (`#0E1411`) auf Lime. Adaptiv mit 0,66
  der Kante (fernster Punkt 34,6 dp, im Kreis einer runden Maske mit
  36 dp), Altformat 0,80, Web 0,90, maskable 0,80 (Kreis mit 40 %).
- Zeichen in der App: EINE Farbe, die Marke des Modus (`brandMark`:
  Lime auf Dunkel, Moos auf Hell). Die zweite Farbe der Endstriche aus
  1g/1h ist weg — C3 ist eine Fläche.
- Statusleiste: Größe M, weiß, nur Alphakanal, 0,88 der Kante
  (`ic_notification`, für Push UND die Dauerbenachrichtigung der Fahrt).
- Startschirm ab Android 12: das Zeichen in `@color/brand_mark` (Moos
  hell, Lime dunkel) ohne Lime-Scheibe, 0,60 von 288 dp
  (`ic_splash`) — danach zeichnet der Splash der App dasselbe Zeichen.
- Favicon: Größe S; `favicon.svg` Moos im Hellen, Lime im Dunklen
  (`prefers-color-scheme`), `favicon.png` Moos als Rückfall.
- Wortmarke: „TRAIL" in Textfarbe + „BUDDY" in der Marke, Barlow
  Condensed 800.

**Abweichungen vom Handoff** (`trailbuddy-logo/README.md`):

- **Kein `flutter_launcher_icons`, kein `flutter_native_splash`**, keine
  kopierten PNGs: Alle Symbole erzeugt weiter `tool/brand_icons.py` aus
  der einen Geometrie (Regel dieses Repos). Die Maßstäbe sind aus den
  Bildern des Handoffs abgelesen; maskable ist pixelgleich, die übrigen
  unterscheiden sich nur in den abgerundeten Ecken.
- **Statusleiste als Vektor** (`ic_notification.xml`) statt
  `ic_stat_trailbuddy.png` je Dichte — dieselbe Form auf jedem Gerät.
- **`theme_color` bleibt `#0E1411`**, nicht Lime: Die PWA färbt ihre
  Systemleisten danach, und auf Lime wären helle Statussymbole
  unlesbar (siehe `web/index.html`).
- **Vor Android 12** bleibt das Startfenster der Grund des Modus ohne
  Zeichen; der Splash der App folgt sofort.
- Die Widgets des Handoffs sind nicht wörtlich übernommen:
  `TrailBuddyMark`, `LogoPainter` und die Geometrie ja (API wie dort,
  Farben aus der Palette), Loader und Splash bleiben `TrailLoader` und
  `StartSplash` mit reduzierter Bewegung und Tippen zum Überspringen
  (Abschnitt 9).

**C3 (Betreiber, 2026-10-01)** folgt auf Turn 1h, bevor 1h ausgeliefert
war: 1h (Strich 14, zwei ungleiche Kehren, zwei dünner werdende
Endstriche) behielt die gleichmäßige Strichstärke, und die Striche in
Strichdicke blieben in kleinen Größen Krümel. C3 zeichnet den Weg als
Fläche — Anlieger in den Kehren, schmaler werdende Strecke — und gibt
jeder Größe ihre eigene Form, statt eine Form zu skalieren. Davor
(Turn 1h, 2026-09-30): Die Form aus 1b — zwei gleiche, waagerechte
Kehren mit Punkt in Strichdicke am Linienende — las sich als „2.",
nicht als Trail; nicht genommen wurden dort A (nur das Ende geändert),
C (drei Kehren — in 24 dp zu dicht) und D (um 12° geneigt).

Die Richtungen 1c (zwei Spuren), 1d (Monogramm TB) und 1e (Stollen) sind
verworfen (1d noch einmal bestätigt am 2026-09-30: gutes App-Symbol,
schlechtes Zeichen — in der Statusleiste zu eng, und zwei Zeichen wären
eine halbe Marke); 1e bleibt eine Idee für Hintergründe.

**Alle Symbole kommen aus EINEM Skript**: `python3 tool/brand_icons.py`
(braucht `rsvg-convert`) schreibt Android adaptiv + Altformat, Web,
maskable, beide Favicons, das Statusleisten-Symbol, das Zeichen des
Startschirms und die Dart-Geometrie; `python3 tool/generated_assets.py
--update` danach. In CI: `brand_icons.py --check` (Textdateien sind
Fixpunkt), `--self-test` und die Prüfsummen der PNGs;
`test/brand_icons_test.dart` hält Dart und JSON zusammen.

## 5. Offline-Kacheln (Turn 2) — eine Regel statt neuer Farbe

**Helligkeit = was auf dem Gerät liegt. Schraffur + gestrichelter Rand =
offene Änderung.** Die Schraffur hat immer die Gegenhelligkeit ihres
Grunds, deshalb reicht eine Regel für beide Richtungen. Kein Grün mehr —
Lime bleibt „mein Trail".

| Zustand | Grund | Schraffur | Rand |
|---|---|---|---|
| Nicht offline | abgedunkelt | — | — |
| Offline | hell | — | durchgehend um den ganzen Bestand |
| Kommt dazu | dunkel | hell | gestrichelt |
| Fällt weg | hell | dunkel | gestrichelt |

Variante A (die Leiste bearbeitet den ganzen Bestand) ist gebaut; der
Speichern-Dialog nennt beide Seiten und die betroffenen Bereiche beim
Namen (2c). Schraffur als **gerechnete Linien** je zusammengefasstem
Kachelrechteck über die `MapViewPolyline`-Fassade, Abstand in
Bildschirm-Pixeln (7 px), kein Füllmuster im Stil. Rückfall 2e: halbe
Tönung, nur die Randfarbe unterscheidet (hell = dazu, dunkel = weg) — er
greift, wenn die Schraffur über `kAreaHatchMaxLines` Linien bräuchte; auf
MapLibre selbst tragen die Linien.

Umgesetzt in `area_overlay.dart` (Maske, `offlineCoverage` mit dem Rand
um den Bestand in der Textfarbe des Modus, `tileOutline`) und
`area_draw.dart` (`draftLayers`, `kAreaInkLight`/`kAreaInkDark`). Auch
der Strich beim Zeichnen folgt der Regel.

## 6. Karte mit zwei Leisten (Turn 3, Spezifikation 3e)

- **Rechts unten — immer:** Aufnahme 60 px (Lime; läuft die Fahrt: Orange
  mit Stop-Quadrat), darüber 44 px: Position, Runde planen (seit 0.72.0,
  #158 Schritt 5 — ein eigener Knopf, nicht die Glühbirne),
  Offline-Karten, Kartenebenen (seit 0.75.0 zwei Knöpfe, #190: die
  Ebenen öffnen ihr Blatt direkt, Offline-Karten die linke Leiste).
- **Rechts oben — immer:** die Glühbirne, 44 px (seit 0.75.0, #180;
  Betreiber: abgesetzt vom Menü). Die Banner oben halten rechts immer
  52 px frei (`kBannerRightInset`), auch ohne Banner — so liegt nichts
  unter ihr und nichts springt.
  Ein offenes Menü markiert seinen Knopf mit Rand in der Marke. Nur wo
  die Spalte nicht mehr hinpasst (kleines Telefon quer, 360 px hoch),
  skaliert sie als Ganzes herunter; hochkant gelten die 44 px.
  Während einer Fahrt steht direkt über der Aufnahme ein weiterer
  44-px-Knopf für die Marken (#105, E12): Fahne „Trail beginnt", dann
  Zielflagge „Trail endet" mit Rand in der Marke, solange ein markierter
  Trail läuft. Bewusst kein Pin und keine Trail-Farbe — nicht zu
  verwechseln mit den Start-/Ende-Marken der Trails (#96).
- **Links mittig — nur mit Menü:** 52 px breit, Knöpfe 44 px
  (Handschuh, Mindest-Trefferfläche), Gruppen durch 8 px Luft statt
  Trennlinien. Aktives Werkzeug = helle Fläche. Hauptaktion (Speichern) =
  Lime, der +/−-Zähler in Mono direkt darunter.
- **Links mittig — ohne Menü: die Legende** (seit 0.77.0, #182;
  Feldwunsch „ausklappbar, aber kaum sichtbar"). Zu eine Lasche am Rand,
  16 × 56 px sichtbar (Fläche, feiner Rand, die vier Pistenfarben als
  kleine Balken), Trefferfläche 44 × 64. Auf: 124 px breit, auf dem
  Landton der Karte (`mapBackground`, auch dunkel — der weiße Saum der
  Proben stünde sonst auf Schwarz), Kopfzeile „Legende" mit Pfeil nach
  links zum Zuklappen, darunter die Proben in vier Gruppen mit 8 px
  Luft: Schwierigkeit, Zustand, Rand, offiziell — dieselben Farben und
  Muster wie die Karte (`map_legend.dart`). 124 px, weil die Blase der
  Tour daneben passen muss (200 px auf einem 360-px-Telefon). Mit
  offener Leiste ist sie weg; auf oder zu merkt sich das Gerät.
- **Oben:** ein Satz, was der nächste Strich tut; verschwindet, sobald kein
  Werkzeug scharf ist.
- **Unten links:** Maßstab + Quelle, rückt neben die linke Leiste.
- **Schließen:** X, Knopf „Offline-Karten", Zurück — mit Rückfrage bei
  offenem Entwurf.
- Der Filter (Orte, offizielle Trails, welche Trails) steht seit 0.75.0
  NICHT mehr in der Leiste (#190, Betreiber: „genested ist UX-Gift"),
  sondern hinter dem eigenen Knopf „Kartenebenen" als Blatt; bis 0.74.x
  war er der erste Knopf der Leiste (3c). Dasselbe Muster später für die Fahrt (3d: Folgen, Hinweis
  hier; Foto ist #37).
- **Reiterleiste:** Grund-Farbe, aktiver Reiter als Lime-Pill.

## 7. Schwierigkeit und Charakter (Turn 4)

**S-Grad als Form** — im Entwurf farblos, schwarzes Schild mit weißer
Form und „S3"; seit 0.42.0 in der Stufenfarbe (siehe Abschnitt 2):

| S0 | S1 | S2 | S3 | S4 | S5 |
|---|---|---|---|---|---|
| ○ fester, ebener Weg | ● kleine Wurzeln, Steine | ■ Stufen, lose, enge Kurven | ◆ Blockfelder, Spitzkehren | ◆◆ steil, verblockt, Umsetzen | ◆◆▮ extrem, Sprünge Pflicht |

(Die Beschreibungen in der App bleiben die eigenen aus
`singletrail_scale.dart`.) Auf der Karte am Trailanfang (Entwurf: erst ab
Zoom 13), in Liste und Blatt neben dem Namen.

**Gebaut in 0.42.0 für Liste, Blatt und Erklärblatt** (`grade_shield.dart`:
`GradeShield`, Formen gezeichnet, nicht als Zeichen aus der Schrift —
◆ und ▮ fehlen in Barlow wie der Pfeil). Das Schild trägt die
Stufenfarbe des Modus (`palette.grade`), Form und Zahl in
`GradePalette.ink`. Gezeigt wird der Median (`Trail.grade`), wie in
der Kachel; ohne Einschätzung kein Schild. In der Liste steht es rechts
oben über den Charakter-Symbolen, und „S2" fällt aus der Zahlenzeile —
zweimal dieselbe Angabe. Der Bildschirmleser hört „Schwierigkeit S3:
verblockt, hohe Stufen, enge Kehren".

**Auf der Karte seit 0.43.0** (`trail_badges.dart`, Schritt 6b): ab der
gerechneten Zoomstufe 14 (`kTrailBadgeMinZoom`; bis 0.74.1 13, eine
Stufe zu früh — #184, Feldbericht; jetzt zusammen mit den Namen an der
Linie) ein Schild je Trail am
Anfang in Trail-Richtung (`trailStart`: bei einer gegen die Richtung
aufgenommenen besten Linie deren Ende), mit Grad und den angezeigten
Merkmalen wie im Entwurf 4c, in der Farbe der Linie (`AppColors.mapGrades`,
die Karte ist immer hell). Abweichung vom Entwurf: Das Schild steht auf
der Seite, von der die Linie WEGführt (`trailHeadsNorth`, gemessen an
einem Punkt ~30 m weiter) — über dem Anfang lag es sonst auf der Linie.
Kein Schild ohne Grad und ohne Merkmale, keins für wartende Trails. Ein
Tipp wählt den Trail aus (`hitValue`); die Trefferprüfung fragt Linien vor
Markern, am Anfang treffen beide denselben Trail.

**Auswählen statt öffnen seit 0.74.0** (#178, `trail_quick_card.dart`):
Ein Tipp legt einen Leuchtrand in der Marke unter die Linie — seit
0.77.2 (#195) deckendes Lime, 16 px, mit 2 px dunkler Kontur
(`onBrand`, 70 %) je Seite: Jeder Trail trägt schon einen weißen Saum,
und das halbdurchsichtige Lime davor (55 %, 12 px) war darin kaum zu
sehen — und zeigt unten links, neben der Knopfspalte, die
Schnellkarte — Schild, Name, Länge, Sterne, das Navi-Symbol (#176), ein
Pfeil und ein X. Ein Tipp auf sie oder ein zweiter auf den Trail öffnet
das Blatt; ein Tipp ins Leere, das X oder Zurück heben auf. Ein langer
Druck auf die Karte setzt eine Nadel in der Marke und öffnet das Menü
„Route ab hier / Route bis hier / Mit der Navi-App hierher" (#177).

**Die Leiste des Planers seit 0.74.0** (`loop_tool_rail.dart`): derselbe
Look wie die Leiste „Ebenen" (52 dp, Knöpfe 44 dp, aktives Werkzeug in
Gegenhelligkeit, „Rechnen" Lime, die Zahl der gewählten Trails in Mono
darunter), am selben Platz und nie mit ihr zugleich. Der Runden-Knopf
rechts trägt dann den Rand in der Marke. Gewählte Trails leuchten in der
Marke — seit 0.83.3 (#233) deckend, 12 px, mit dunkler Kontur (2 px,
Pflicht 3,5 px deckend) unter der Linie wie der Leuchtrand (#195); 55 %
ohne Kontur ging im weißen Saum unter. Der getippte Start ist eine Fahne
in der Marke mit dunkler Kontur und Schein (`LoopStartFlag`).

**Anfang und Richtung seit 0.66.0** (#96, `trail_end_marks.dart`,
Schritt 6c): je Trail eine Scheibe (14 px) in der Trail-Farbe mit weißem
Pfeil, gedreht auf die Peilung der ersten ~30 m (`trailStartBearing`),
mit weißem Saum wie die Linie. Das Quadrat am Ende (die Zielmarke) ist
seit 0.74.2 weg (#179, Feldbericht: „überflüssig und eher störend") —
wo der Trail endet, zeigt die Linie selbst. Dieselbe Zoomstufe wie die
Schilder (unter 14
lägen sie übereinander, und MapLibre setzt jeden Widget-Marker in jedem
Bild neu), keine für wartende Trails, auch für Trails ohne Schild. Nicht
antippbar: Ein Tipp dort trifft die Linie. Kein Pin und keine Fahne — die
Fahne gehört dem Marken-Knopf (Abschnitt 6), die Nadel den Orten. Der
Anfang kommt aus `Trail.start` in Trail-Richtung; das
Schild liegt über der Startmarke und bleibt das Antippbare.

**Charakter** — Mehrfachwahl je Beitrag, wie der Grad von Buddys
vergeben; angezeigt die höchstens 2 häufigsten, als Symbol:
Flowig (Wellen, Anlieger, Rhythmus), Jump-Line (Kicker, Drops, Tables),
Verblockt (Steine, Wurzeln, Stufen), Steil (anhaltendes Gefälle), Uphill
(Auffahrt, auch bergauf fahrbar). **Gebaut seit 0.34.0 (#72)** und um
Naturtrail und Verbindung aus der früheren „Art" erweitert (Betreiber,
2026-09-29: der Charakter ERSETZT die Art, sieben Merkmale): Auswahl als
Chips im Beitrag, im Blatt „Flowig · 3", in der Liste als Symbole
(`trail_traits.dart`, Symbole farblos), seit 0.35.0 auch je Kandidat im
Zerlege-Blatt.

**Pisten-Brille** — im Entwurf ein Schalter unter Ebenen, „Farbe nach
Schwierigkeit", mit der Breite als Beziehung (meiner 5, nur Buddy 3,5).
**Entfällt seit 0.42.0:** Die Pistenfarben sind der Normalzustand, und
die Beziehung zeigt die Karte gar nicht mehr (Betreiber, 2026-09-29) —
alle Trails gleich breit.

Liste (4e): Filter-Chips „Alle", „bis S2", „Flowig", „Jumps" (Suche, „Alle/Meine/Von Buddys", „bis S2" und die Sortierung gibt es seit 0.32.0, #66 — `trail_list.dart`; der Filter gilt seit 0.33.0 auch auf der Karte, `TrailFilterChips` im Blatt „Ebenen"; „Flowig"/„Jumps" seit 0.34.0, #72 — sie filtern über die angezeigten zwei Merkmale, nicht über jede einzelne Nennung); Zeile als
Karte mit Farbstreifen links, Zahlen in Mono, Schild und Symbole rechts.
Blatt (4f): Name, „Du und 2 Buddys", Charakter-Chips mit Anzahl, drei
Kacheln Länge / Höhe / S-Grad oder Spanne, „Deine Einschätzung".
**Seit 0.49.0 (#101, Rework E8)** darunter eine zweite Reihe BEWERTUNG
(Sterne in der Marke, Median und Anzahl; verblasst, solange der eigene
Trail nicht bewertet ist) und ZUSTAND (Wort und Alter; eine jüngere
unbestätigte Angabe verblasst mit „zu bestätigen"), je mit Tipp auf die
Einzelstimmen. Eine unbestätigte Meldung steht als verblasster Chip
neben der bestätigten; unten „Hinweis schreiben" (Lime) und „Melden"
nebeneinander, „Karte" darunter. **Liste seit 0.50.0:** die Sterne unter
den Zahlen (13 px, blass bei „Bewertung offen"), Sortierung „Bewertung";
hinter Meldung und Hinweis der Zustand 1–2 als Wort („ABGEROCKT",
„KAUM FAHRBAR") in der Textfarbe — ohne eigene Farbe, die gehört der
Schwierigkeit (E9) —, eine unbestätigte Meldung gedämpft mit „?"
(„GESPERRT?"). Die Linienart auf der Karte: Abschnitt 2 (seit 0.51.0).

## 8. Screens (Turn 1g–1l)

- **Login (1g):** Logo, Wortmarke, „Trails teilen — nur mit deinen
  Buddys.", linksbündig.
- **Trail-Blatt (1i):** Titel in Großbuchstaben, drei Kennzahl-Kacheln,
  Höhenprofil in Trail-Richtung, Hinweis eines Buddys als gelb umrandete
  Karte, unten „Hinweis schreiben" (Lime) + „Karte". **Gebaut seit
  0.39.0** (`trail_sheet.dart`: `_MetricTiles`, `_Panel`;
  `trail_notes.dart`). Unter dem Titel die Beziehung („Du und 2 Buddys
  (Jan, Mira).", 4f). Kacheln LÄNGE / HÖHE (↓ Hm) / S-GRAD (Median in der
  Marke, darunter Spanne und Anzahl „S1–S3 · 4×"); der ganze Satz
  („↓ 420 Hm · ↑ 35 Hm", „S2 · S1–S3 · 4 Einschätzungen") steht als
  Beschriftung für Bildschirmleser an der Kachel, die S-Grad-Kachel
  öffnet wie der frühere Chip die Einschätzungen. Das Ø-Gefälle steht
  im Profil-Untertitel. Charakter und Meldung bleiben Chips über den
  Kacheln. „Mein Beitrag" steht als Textknopf unter „Deine
  Einschätzung" (4f bearbeitet den Beitrag direkt im Blatt; der Dialog
  kann mehr — Name, Status, Sichtbarkeit). Das S-Grad-Schild neben dem
  Titel (4f) steht seit 0.42.0 (Schritt 6a). Rechts im Kopf seit 0.83.0
  das Navi-Symbol („Anfahrt", #224) und ein X (#215); unten stehen nur
  noch „Zum Trailkopf" und „Karte" nebeneinander. Das Blatt ist auf dem
  ganzen Inhalt ziehbar (geht mit drei Vierteln der Höhe auf, nach unten
  gezogen schließt es).
- **Trail-Liste (1j):** Karten mit 14 px Radius, Farbstreifen links =
  Beziehung (seit 0.42.0: Schwierigkeit), rechts ein Wort in der Farbe (NEUER HINWEIS, MEIN, GESPERRT,
  AUSGANGSKORB …), Zahlen in Mono. **Gebaut seit 0.38.0**
  (`trails_screen.dart`, Regel `trailRowTags` in `trail_list.dart`), mit
  drei Abweichungen: Das Wort steht unter den Zahlen, nicht rechts —
  rechts stehen seit 4e Schild und Charakter-Symbole, beides zusammen
  liefe auf 360 dp über. Seit 0.74.0 steht LINKS davon das Navi-Symbol
  (#176); das Schild bleibt am rechten Rand. Ein Zustand (wartet, gemeldet, neuer Hinweis)
  schlägt die Beziehung; nur ohne Zustand steht „MEIN · 2 BUDDYS" bzw.
  die Namen (höchstens zwei, Alias vor Name). Die Karten sind flach
  (`elevation: 0`) mit Rand in der Linienfarbe; der gelbe Rahmen trägt
  den neuen Hinweis, eine Tönung der Zeile gibt es nicht mehr. Die
  Abschnitte „Meine Trails" / „Von Buddys" bleiben (der Entwurf hat
  keine) — im Stil der Abschnitte aus 1k. Kopf: „TRAILS" groß, rechts
  „Anzahl · Gesamtlänge" in Mono.
- **Buddys (1k):** Nach dem Annehmen eine Karte „Mit Jan verbunden" mit
  drei Zahlen (gemeinsam / neu von / neu für) statt einer Leiste;
  Avatare als abgerundetes Quadrat (12 px).
  Gebaut in 0.40.0 (`friends_screen.dart`) mit vier Abweichungen: Die
  Karte bleibt, bis man sie schließt (eine Leiste war nach acht Sekunden
  weg). „vor 2 Stunden" an der Anfrage fehlt — die App kennt den
  Zeitpunkt einer Anfrage nicht. Statt des Chevrons stehen rechts Alias
  und Entfernen: Eine Seite je Buddy gibt es nicht, ein Pfeil ins Leere
  wäre eine falsche Zusage. Das Einladen, im Entwurf nicht zu sehen,
  steht oben rechts (ohne Buddys zusätzlich als Knopf in der Liste).
  „n gemeinsam" zählt dieselben Trails wie „gemeinsam" in der Karte
  (`sharedTrailCounts`). Die Avatarflächen (`AppColors.avatarFills`:
  Blau, Gelb, Pink, Lila, fest je Nutzer-id) tragen dunkle Schrift in
  beiden Modi; Lime bleibt dem eigenen Avatar, denn Lime heißt „mein".
- **Profil (1l):** Kopf mit Avatar und drei Zahlen, darunter Zeilen mit
  Wert rechts (Benachrichtigungen, Erscheinungsbild …).
  Gebaut in 0.41.0 (`profile_screen.dart`): Die Zeilen sind Karten mit
  Symbol auf eigener Fläche, der Wert steht UNTER dem Titel wie im
  Entwurf. Benachrichtigungen, Erscheinungsbild und Konto sind eigene
  Unterseiten (`/profile/notifications`, `appearance`, `account`); dazu
  kommt eine siebte Zeile „Über TrailBuddy" (`/profile/about`), die der
  Entwurf nicht hat — Datenschutzerklärung, Impressum und Lizenzen
  müssen aus der App erreichbar bleiben. Abmelden steht oben rechts,
  „Konto löschen" am Ende der Seite „Konto". Die drei Zahlen zählen
  eigene Trails (belegt oder wartend), angenommene Buddys und Fahrten
  auf dem Gerät; was nicht geladen ist, fällt weg statt als 0
  dazustehen, im Web gibt es keine Fahrten.

- **Kurzanleitung** (#131, seit 0.59.0, `help_screen.dart`): kein
  Entwurf im Turn; gebaut im Stil der Profil-Unterseiten. Oben die
  Kachel des Sicherheitshinweises (Warnton 10 % auf der Fläche, Rand
  `line`, Symbol `warning_amber_outlined` in `warningText` — kein Emoji),
  darunter sechs Abschnitte mit dem ECHTEN Symbol links in einem
  40-dp-Rahmen (Material-Symbole in `accentText`, für die Karte das
  `GradeShield`), Titel `titleMedium`, Text `bodyMedium`. Der
  Sicherheitshinweis beim ersten Start ist ein `AlertDialog` „Kurz vorweg"
  mit einem gefüllten „Verstanden". Der leere Kartenzustand trägt rechts
  ein `help_outline` und ist als Ganzes tippbar; die übrigen Leerzustände
  bekommen einen Textknopf „Kurzanleitung".

## 9. Bewegung (Turn 1p–1t)

Jede Animation ist aus, wenn das System es will
(`MediaQuery.disableAnimations`).

| | Was | Dauer (Entwurf) |
|---|---|---|
| 1p Splash („Splash B", C3) | das Zeichen zeichnet sich in 1,3 s linear ein, Spitze in Streckenbreite; ab 1,26 s baut sich die Wortmarke daneben von links nach rechts auf, weiche Kante 14 % der Breite, 0,52 s `easeOutQuad` | einmal, 1,78 s |
| 1q Loader (C3) | das Logo als Spur (`line`), darauf zeichnet sich das ganze Zeichen in der Marke ein (`easeInOut`, über die Lücken in die Endstriche), steht und blendet zurück in die Spur — nie ein halbes Zeichen beim Ausblenden (seit 0.65.1; vorher ein Läufer von 40 Einheiten, der nie das ganze Zeichen zeigte, Betreiber 2026-10-01: „recht langsam und nicht vollständig") | 0,85 s Zeichnen + 0,2 s Stehen + 0,35 s Ausblenden, Schleife |
| 1r Fahrt läuft | Ring um den Positionspunkt skaliert 1 → 3,2 und blendet von 0,7 aus; die Spur wächst | 1,6 s, Schleife |
| 1s Buddy verbunden | zwei Spuren laufen zu einer zusammen, dann der Punkt | 3 s |
| 1t Neuer Hinweis | der gelbe Leuchtrand atmet (2 → 6/14 px Schein) | 1,8 s, nur solange ungesehen |
| 1u Tour-Ring | Lime-Ring um das Gemeinte pulsiert 3 → 7 px (Abschnitt 12) | 1,8 s, Schleife, solange die Tour läuft |
| 1v Tour-Hand | herankommen, drücken, abheben (Wischen: rechts nach links) | 1,8 s, Schleife |
| 1w Startseiten-Bild | ein Punkt fährt die Serpentine ab: Moment am Start, weich die Linie entlang, Moment am Ziel (`introDriftAt`) | 4 s, Schleife; ohne Takt der Punkt am Ziel |

Gebaut in 0.45.0 (`lib/core/widgets/motion.dart`, `start_splash.dart`;
die Keyframes stehen je als pure Funktion daneben — `splashAt`,
`loaderAt` (seit 0.65.1, vorher `loaderRunAt` und `loaderSegments`), `ridePulseAt`, `connectMergeAt`, `glowAt` — und sind
ohne Pixel geprüft, `test/core/motion_test.dart`). Bei reduzierter
Bewegung steht überall das Endbild, kein Takt läuft. Fünf Abweichungen:

- **1p liegt ÜBER der App, nicht vor ihr**: Anmeldung, Karte und Trails
  laden darunter schon, der Splash kostet also keine eigene Wartezeit
  (1,78 s, dann steht das ganze Bild 0,6 s und blendet über 1 s aus —
  seit 0.83.1, #235; einmal je Start). Seine Uhr geht je Bild höchstens
  50 ms weiter: Hält die Startarbeit ein Bild auf, wartet die Zeichnung,
  statt zu springen (#217); die App darunter zeichnet erst, wenn er
  ausblendet. Ein Tipp überspringt ihn (0,25 s); bei reduzierter Bewegung gibt es ihn gar nicht — ein stehendes
  Logo vor der App wäre nur eine Pause. Grund ist der des Modus, nicht
  immer das Dunkel des Entwurfs. Der Test-Harness schaltet ihn ab
  (`startSplashEnabledProvider`).
- **1q ersetzt nur die ganzseitigen Kreisel.** In Knöpfen und Zeilen
  bleibt der kleine Kreisel: Eine Serpentine in 16 px liest niemand.
- **1r**: Der Ring hat die Farbe des Positionspunkts; die Markerfläche
  wächst während der Fahrt auf das 3,2-Fache, sonst würde er
  beschnitten. „Die Spur wächst" tat sie schon — mit jedem Punkt.
- **1s läuft einmal**, 3 s, wenn die Karte „Mit … verbunden" erscheint:
  erst auseinander, dann eine Spur, dann der Punkt. Die Vorschau im
  Entwurf läuft hin und her, das wäre auf einer Karte, die man liest,
  Unruhe. Zusammen trägt die Spur die Marke (Lime heißt „mein").
- **1t atmet nur in der Liste**, auf der Karte steht der Rand still:
  Eine atmende Linie hieße in MapLibre, die Linien in jedem Bild neu zu
  übertragen — genau die Last, die 0.44.0 abgeschafft hat.

## 10. Nicht bauen

Nachrichten (1m, #34 Rest), Fahrt-Zusammenfassung mit Airtime (1n, #36)
und Routing zum Trailkopf (1o, #35) sind Entwürfe für später; vor dem
Routing kommt die Übergabe an eine Navi-App (#151, Konzept 9).

## 11. Umsetzung

| PR | Inhalt | Version |
|---|---|---|
| #74 | Tokens, Theme hell/dunkel, Schriften, „Erscheinungsbild" | 0.28.0 |
| 2 | Logo, App-Symbole, Statusleisten-Symbol, Login | 0.29.0 |
| 3 | Hülle und Karte (Turn 3) | 0.30.0 |
| 4 | Offline-Kacheln: eine Regel (Turn 2) | 0.31.0 |
| 5a | Trail-Liste (1j, 4e ohne Schild) | 0.38.0 |
| 5b | Trail-Blatt (1i, 4f ohne Schild) | 0.39.0 |
| 5c | Buddys (1k) | 0.40.0 |
| 5d | Profil (1l) | 0.41.0 |
| 6 | S-Grad als Form, Charakter, Pisten-Brille (Turn 4, Schema) | Charakter 0.34.0 (#72) |
| 6a | S-Grad-Schild, Farbe = Schwierigkeit (Karte, Liste, Schild) | 0.42.0 |
| 6b | Schild mit Charakter am Trailanfang auf der Karte | 0.43.0 |
| 6c | Start- und Endmarke mit Richtung auf der Karte (#96; Endmarke seit 0.74.2 weg, #179) | 0.66.0 |
| 6c | Glatte Linien, Name entlang der Linie (Betreiber-Wunsch) | 0.44.0 |
| 7 | Animationen (Turn 1p–1t) | 0.45.0 |
| E1 | Einführung: Kurzanleitung, Sicherheitshinweis (#131) | 0.59.0 |
| E2 | Hinweis-Maschine, Karten-Tour aus der Kurzanleitung (#132) | 0.60.0 |
| E3 | Karten-Tour beim ersten Start mit Startseite (#133) | 0.61.0 |
| E4 | Tour im Zerlege-Blatt (#134) | 0.62.0 |
| E5 | Touren für Trails und Buddys, Beispiele (#136) | 0.63.0 |
| E6 | Neuheiten-Blatt, „Entdecken", „Zeig es mir" (#135) | 0.64.0 |

## 12. Einführung: Hinweis-Maschine und Touren (#126)

Plan `docs/konzept-onboarding.md` Abschnitt 6; gebaut ab 0.60.0
(`lib/features/coach/coach.dart`, Kopie von PilzBuddy #596).

- **Abdunkelung** Schwarz mit 65 %, Aussparung in der Form des
  Elements, 2 px Luft, Radius 12. Kein Vergrößern — der Fehler der
  ersten PilzBuddy-Tour, die runde Löcher je Knopf schnitt.
- **Ring = Marke**: außen Weiß 90 % 5 px, innen Lime 3 px, pulsiert
  3 → 7 px in 1,8 s. Der Ring heißt „hier, für dich" und ist nie eine
  Bedeutungsfarbe der Karte. Lime kollidiert nicht: S0 ist ein anderes
  Grün, und „mein" ist seit 0.42.0 ein Wort. Orange, Gelb, Magenta,
  Violett und Blau bleiben den Linien.
- **Hand** gezeichnet (`FingerPainter`), Ärmel und Druckpunkt in der
  Marke, Kontur fast schwarz (`onBrand` — PilzBuddy: Pilzbraun); heran,
  drücken, abheben, Keyframes pur (`FingerMotion`).
- **Blase** auf `surface` mit Rand `line`, Radius 12, Pfeil zum Ziel;
  Titel `titleLarge` (Barlow Condensed), Text `bodyMedium`, Zähler
  „2 von 7" in JetBrains Mono, gedämpft; „Überspringen" als Text,
  „Weiter"/„Los geht's" gefüllt in Lime. Erst messen, dann setzen: neben
  ein hohes schmales Ziel, ins Bild geschoben ohne Pfeil.
- **Illustration** (TrailBuddys Erweiterung): ein Bild unter dem Text,
  wo nichts auszusparen ist. Bis 0.76.x stand dort die Mini-Legende;
  seit 0.77.0 (#182) zeigt die Tour die Legende auf der Karte selbst
  (Abschnitt 6, „Links mittig — ohne Menü").
- **Reduzierte Bewegung**: Ring steht, Hand steht in der Druckstellung.
  Während einer Tour blendet die Maschine alles darunter für TalkBack
  aus; die Blase ist eine Live-Region.
- **Startseite** (seit 0.61.0, `tour_intro_art.dart`): Karte mit Radius
  24 auf `surface` mit Rand `line`, darin das Bild 240 × 150 (Radius 20,
  schrumpft mit dem Schirm auf bis zu 80 px Höhe), Titel
  `headlineSmall`, zwei Sätze `bodyLarge`, die Wahl „Nicht jetzt" /
  „Tour starten" (aus der Kurzanleitung „Zeig's mir"; in der Kette ab
  #136 „Später" / „Weiter"). Nur der Inhalt scrollt, die Wahl bleibt im
  Bild. Bilder: `welcomeArt` — das Logo (L) in `brandMark` auf dem
  Grund des Modus, die Endstriche halb durchsichtig, ein Punkt in
  Textfarbe mit Kern in der Marke fährt sie ab; `mapArt` — drei
  Linienstücke S0/S1/S2 mit weißem Saum auf dem Landton der Karte und
  ein S1-Schild. Kein Foto, kein Lottie, keine Emojis.
  `splitArt` (seit 0.62.0, Zerlege-Tour): eine Fahrt als blasse Linie in
  `ride` mit weißem Saum auf dem Landton, darin ein bekanntes Stück in
  `mine` und ein Kandidat in `candidate` mit zwei weißen Griffen —
  dieselben Farben wie die Vorschau auf der Karte. Steht still.
  `trailsArt` (seit 0.63.0): drei Zeilen wie in der Liste — Streifen
  S1/S2/S0, ein gedämpfter Balken als Name, rechts das `GradeShield` —
  auf dem Grund des Modus. `buddysArt`: zwei Spuren (`mine`, `buddy`)
  laufen zu einer in der Marke zusammen, dann der Punkt — das Motiv von
  1s, stehend.
- **Neuheiten und „Entdecken"** (seit 0.64.0, `lib/features/highlights/`):
  Bild je Eintrag (`HighlightArt`) — das echte Symbol der Funktion in
  `accentText` auf einer Scheibe `surface2` mit Rand `line`, unten rechts
  das Logo auf `surface`; steht still, kein Screenshot, kein Lottie. Das
  Blatt nach einem Update ist EINE Seite: Titel `headlineSmall` („Neu in
  TrailBuddy" / „Das kann TrailBuddy inzwischen"), die Einträge als Zeilen
  untereinander, unten „N weitere entdecken", „Alle Änderungen" und „Fertig"
  (gefüllt in Lime). „Entdecken" gruppiert nach Reiter in der Reihenfolge
  der Leiste (Karte, Trails, Buddys, Profil), je Eintrag Bild, Titel,
  zwei, drei Sätze in `bodySmall`, Schilder „Neu" (Lime auf `onBrand`) und
  „Tipp" (gedämpft auf `surface2`), Radius 8; darunter „Zeig es mir" und
  „Ausprobieren". Der Neu-Punkt an der Profilzeile ist die Zahl in Lime.
- **Beispiel-Schild** (seit 0.63.0, `TourExampleBadge`): „Beispiel" in
  `labelSmall` auf `tertiaryContainer`, Radius 8, an Beispiel-Zeile,
  -Blatt und -Buddy; dazu steht „Beispiel:" im Namen, damit es auch der
  Bildschirmleser hört. Die Beispiele sind wie die echten Zeilen gebaut
  (Karte mit Streifen, Schild, Mono-Zahlen), die Knöpfe sehen aktiv aus,
  tun aber nichts.
