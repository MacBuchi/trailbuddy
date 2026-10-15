# TrailBuddy — Arbeitsregeln für `web/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Kein Netzziel ohne Datenschutzerklärung**: `test/privacy_policy_test.dart`
  prüft jeden Host in `lib/` und `web/` gegen seine Einordnung.
- **Rechtsseiten in zwei Sprachen** (#209, Betreiber 2026-10-13):
  `datenschutz.html`, `impressum.html`, `konto-loeschen.html` sind
  verbindlich; `privacy.html`, `imprint.html`, `delete-account.html` sind
  englische Höflichkeitsübersetzungen. Beide verweisen oben aufeinander
  (`hreflang`), die App öffnet über `AppInfo.privacyUrlFor`/
  `impressumUrlFor` die Fassung ihrer Sprache (Deutsch ⇒ deutsch, sonst
  englisch). Wer eine deutsche Seite ändert, zieht die englische im
  selben PR nach: `privacy_policy_test.dart` verlangt dasselbe
  „Stand"-Datum, jeden abgerufenen Host, Anschrift und Mailadresse auf
  beiden Seiten. Knöpfe heißen in der englischen Fassung wie in
  `app_en.arb`.
- **Web**: `web/flutter_bootstrap.js` + `web/sw.js` sind PilzBuddys
  Service Worker (netzwerkzuerst, Cache als Rückfall); die Platzhalter
  dürfen in keinem Kommentar stehen. **`sw.js` ist seit Phase 1 KEINE
  Kopie mehr**, zwei Korrekturen, die PilzBuddy noch nicht hat: (1) der
  frühere Cache wird über den Vollständig-Merker erkannt, nicht über die
  Reihenfolge von `caches.keys()` — Chromium listet den neuen Cache oft
  vor dem alten, dann hielt sich der neue für vollständig und der alte
  blieb für immer; (2) `caches.match(…, {cacheName})` statt `open` zum
  Nachschlagen, Schreibzugriffe nur, solange der eigene Cache existiert,
  und ein Zombie-Sweep (leerer Cache ohne Merker und Hülle) — ein
  abgelöster Worker legte seinen gelöschten Cache sonst leer neu an.
  Gemessen: Prüfer vorher in einem von drei Läufen rot, danach 4/4 grün. `--no-web-resources-cdn` in jedem
  Web-Build, `--base-href /trailbuddy/`. Geprüft im echten Chrome
  (`tool/check_service_worker.mjs`, Job „Build Web").
  **Chrome startet über `tool/chrome_start.mjs`** (beide Browser-Prüfungen,
  auch `check_push_worker.mjs`): Antwortet der Debug-Port 30 s nicht,
  wird Chrome abgeschossen und mit frischem Profil neu gestartet,
  höchstens dreimal — auf dem CI-Rechner hing er einmal ohne jede Ausgabe
  (PR #344). Nur der Start wird wiederholt, nie eine Prüfung. Gegenprobe
  mit `CHROME_EXECUTABLE` auf ein Skript, das nur `sleep` macht: drei
  Starts, dann rot; hängt es nur beim ersten Mal: grün.
