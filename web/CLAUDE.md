# TrailBuddy — Arbeitsregeln für `web/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Kein Netzziel ohne Datenschutzerklärung**: `test/privacy_policy_test.dart`
  prüft jeden Host in `lib/` und `web/` gegen seine Einordnung.
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
