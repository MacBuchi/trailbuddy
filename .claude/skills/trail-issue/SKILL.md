---
name: trail-issue
description: Ein TrailBuddy-Issue oder eine Änderungsanfrage vom Anfang bis zum PR durchziehen, ohne Schleifen — vor dem Coden Lagebild, frischer Branch, Issue samt Kommentaren und die Ordner-CLAUDE.md lesen; am Ende Version, Changelog, Neuheiten-Eintrag mit Vorführung, gezielte Tests mit Gegenprobe und PR-Text. Nutzen, sobald an einem Issue (#NNN) oder einer Funktions-/Fehleränderung in lib/, assets/, supabase/ oder web/ gearbeitet wird — auch wenn nur „schau dir #NNN an" oder „bau X" gesagt wird.
---

# Vom Issue zum PR

Übernommen aus PilzBuddys `pilz-issue` (#671) für TrailBuddy #237. Jeder
Schritt steht hier, weil er schon einmal gefehlt hat. Der Skill bündelt;
die Einzelheiten stehen dort, wo sie hingehören — Regeln in der
Root-`CLAUDE.md`, Fachwissen in der `CLAUDE.md` des Ordners, Testfallen in
`test/CLAUDE.md`, die Reihenfolge der Arbeit in #156.

## Wie viel Ritual

Die Größe der Anfrage bestimmt den Aufwand, nicht dieser Skill.

- **Klein und eindeutig** (Text ändern, Farbe, ein Fehler mit klarer
  Ursache): Start-Schritte 1–4 still erledigen, dann direkt bauen. Kein
  Plan zur Freigabe, keine Rückfrage.
- **Größer oder mehrdeutig** (neue Funktion, Schema, Datenschutz, mehrere
  Ordner, Konzept berührt, oder „fertig" ist nicht beschrieben): kurzer
  Plan zur Freigabe.

Rückfragen nur, wenn die Antwort den Bau ändert — gebündelt, mit einer
empfohlenen Option. Ein fehlendes Abnahmekriterium selbst als Vorschlag in
den Plan schreiben („fertig, wenn …"), nicht abfragen.

## Start

1. **Lagebild lesen.** Der SessionStart-Hook (`tool/session_status.py`)
   hat es schon in den Kontext geschrieben: Branch, Abstand zu
   `origin/main`, Unkommittiertes, offene Bump-PRs. Fehlt es:
   `python3 tool/session_status.py`.
   - Unkommittiertes ansehen, nie per `git checkout` verwerfen.
   - Offene PRs mit Versions-Bump notieren — sie bestimmen die Version am
     Ende.
2. **Issue lesen, mit allen Kommentaren** (`gh api
   repos/{owner}/{repo}/issues/N` und `…/comments`). Entscheidungen des
   Betreibers stehen oft im TEXT des Issues; in #156 steht, wo es im
   Fahrplan liegt.
3. **Branch frisch von `origin/main`.** Nie vom lokalen `main` und nie von
   einem Branch, dessen PR schon squash-gemergt ist — der trägt den Commit
   sonst doppelt. Gibt die Sitzung einen Branch vor, wird der neu von
   `origin/main` aufgesetzt.
4. **Fachwissen laden:** Index „Technik-Notizen" in der Root-`CLAUDE.md`
   ansehen und die Teildatei(en) der betroffenen Ordner lesen, BEVOR
   geplant wird. Berührt die Änderung das Modell, gilt
   `docs/konzept-trails.md`, beim Aussehen `docs/design/README.md` — wer
   davon abweicht, ändert sie im selben PR. Breite Suchen an einen
   Explore-Subagenten geben.
5. **Plan** (nur bei größeren Anfragen): was sich ändert, welche Dateien,
   welche Tests, „fertig, wenn …", und was bewusst NICHT gemacht wird.
   Dann warten.

## Bauen

- **Dart-MCP zuerst** (`.mcp.json`, Abschnitt in `test/CLAUDE.md`):
  `analyze_files` mit `file://`-URIs, `run_tests` mit Pfaden relativ zur
  Wurzel, `lsp` → `resolveWorkspaceSymbol`, um nur die Zeilen eines
  Symbols zu lesen. Ohne Server: `flutter test --reporter failures-only
  test/…`, nur die betroffenen Dateien.
- Vor dem ersten neuen Widget-Test `test/CLAUDE.md` lesen.
- Neues Fachwissen (eine Falle, eine Messung, eine Entscheidung) gehört in
  die `CLAUDE.md` des Ordners, in dem der Code liegt — nicht in die Root;
  `tool/agent_docs.py` hält den Index zusammen.

## Abschluss

1. **Version:** Ändert sich etwas unter `lib/`, `assets/`, `web/` oder
   `CHANGELOG.md`, `pubspec.yaml` nach Semver aus dem PR-Typ erhöhen
   (`feat` MINOR, `fix`/`perf` PATCH, `BUILD` immer +1). Ausgangspunkt ist
   `origin/main`; liegt ein offener Bump-PR davor, über ihn hinaus zählen
   oder die Reihenfolge mit dem Betreiber klären.
2. **Changelog:** Block oder Versionszeile in `CHANGELOG.md`, in
   Alltagssprache, nach Thema. Nackte URLs, keine Markdown-Links.
3. **Sichtbare Funktion?** Eintrag in `kFeatureHighlights` UND Vorführung
   in `highlight_demos.dart` — oder im PR einen Satz, warum nicht.
   Oberfläche geändert, auf die eine Tour zeigt (Kartenknöpfe, Leisten,
   Trail-Blatt, Reiterleiste)? Anker prüfen, `map_tour_flow_test`.
4. **Neues Netzziel, neue Berechtigung, neue Datenkategorie?**
   `web/datenschutz.html` und `docs/play-console.md` im selben PR
   (`test/privacy_policy_test.dart` wacht über die Hosts).
   **Schema?** `patch_NNN`, Struktur in `schema.sql` UND Saat-Liste,
   `tool/schema_check.sh` und — beim Abgleich — `tool/matcher_check.sql`
   erweitern; Werkzeug und SQL im selben PR.
5. **Prüfen:** betroffene Tests, dann `flutter analyze`, dann einmal die
   ganze Suite. Für jede neue Zusicherung die **Gegenprobe**:
   Produktionsstelle entschärfen, Test rot sehen, per Dateikopie
   zurückbauen, grün sehen.
6. **Aufräumen vor dem Commit:** `pubspec.lock` nur behalten, wenn eine
   Abhängigkeit wirklich dazukam; kein `dart format`;
   `python3 tool/private_info_check.py`.
7. **Commit und PR** auf Englisch, Conventional Commits — der PR-Titel IST
   der Commit auf `main`. PR-Text nach `.github/pull_request_template.md`,
   Checkliste ehrlich abhaken, die gefahrene Gegenprobe nennen, `Closes #N`
   in den Body. Gemergt wird vom Menschen. In #156 den Punkt abhaken.
8. **Schnitt anbieten:** Ist die Aufgabe mit dem PR erledigt, die Antwort
   mit einem Satz schließen: „Guter Moment für `/clear`." Abschnitt „Compact instructions" in der Root-`CLAUDE.md`.
