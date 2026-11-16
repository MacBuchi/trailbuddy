# Planer-Zeitskala (#549) — Entwurf aus dem Designer

Canvas „Planer-Zeitskala #549" vom 2026-11-16, vom Betreiber
freigegeben („Bin dacore", Konzept-Routing 12.10). Zwei Artboards,
390 × 844, interaktiv:

- `A-zeitleiste.dc.html` — **A · Zeitleiste im Ergebnis**: Die Zeit-Skala
  der Kachel wird zur Leiste über die ganze Breite (Zeit ± 2 × Fenster).
  Jeder Stand des Greedy ein Stiel: Höhe = Trail-Anteil, Kopf = höchster
  S-Grad als Form + Farbe. Tipp/Ziehen rastet auf den nächsten Stand,
  Karte und Kacheln folgen; die Zeile darunter sagt Zeit · Anteil ·
  höchster Grad und „Kürzer: ohne …" / „Länger: zusätzlich …".
- `B-anteil-ueber-zeit.dc.html` — **B · Anteil über der Zeit**: x = Zeit,
  y = Trail-Anteil, die Stände als Kette; Ring um jeden Punkt =
  Höhenmeter am Limit, Gipfel voll, die übrigen blass; Karte zum
  gezeigten Stand, „Diese Runde nehmen" / „Zurück zum Vorschlag",
  Schalter „Auch über dem Limit" (hohl, gestrichelt, Warnfarbe).

`canvas.json` ist der Index des Canvas (Lage, Notizen). Die Dateien sind
Prototypen in HTML (Design-Component-Format, `support.js` gehört zur
Laufzeit des Designers und fehlt hier) — maßgeblich sind Maße, Formen
und Texte, nicht der Aufbau. Farben in der App aus `AppPalette`, nicht
die festen Werte der Skizze (die Skizze ist dunkel). Trail-Namen und
Zahlen sind erfunden.

Umgesetzt: siehe `docs/design/README.md` 7 und Konzept-Routing 12.10.
