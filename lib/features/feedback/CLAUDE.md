# TrailBuddy — Arbeitsregeln für `lib/features/feedback/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Feedback (die Glühbirne)**: `lib/features/feedback/feedback_dialog.dart`
  (Karte oben rechts seit 0.75.0, #180, und Profil) schreibt in `public.feedback`;
  `tool/feedback_bot.py` (`feedback.yml`, alle 2 h) macht daraus
  ÖFFENTLICHE Issues mit Label `enhancement`/`bug` und löscht
  `error_reports` nach 90 Tagen (Datenschutzerklärung). Auf demselben
  Tick der **Fehlerbericht-Digest** (#40, seit 0.21.0): ein Issue je
  ISO-Woche (Label `ops`, Titel `Error reports JJJJ-Wnn`), bei jedem
  Lauf neu geschrieben statt kommentiert; keine Fehler ⇒ kein Issue.
  Jede Gruppe zeigt den obersten Frame im EIGENEN Code (`top_frame`,
  `package:trailbuddy/`), sonst den obersten überhaupt (ANR-Dump), und
  bei Framework-Fehlern die PHASE (seit 0.74.1: `flutterErrorStack`
  schreibt `Phase: <Bibliothek> · <Zusammenhang>` über den Stack,
  `stack_phase` liest sie) — ein Ticker-Rückruf trägt keinen eigenen
  Frame, und in 2026-W40 stand fünfmal ein Null-Check in
  `AnimationController.stop` ohne jeden Hinweis da. Gekürzt wird der
  Stack nicht mehr von hinten (`clipStack`: Anfang, Zahl der fehlenden
  Zeilen, dann die eigenen Frames aus dem Rest). Eine
  vergangene Woche rendert `--digest-week 2026-W40` (liest nur), im
  Workflow über die Eingabe `digest_week` in die Run-Summary.
  `--test-digest` läuft in CI mit. Vier Dinge, die man wissen muss:
  - **Kein Benutzername im Issue**, anders als PilzBuddy: Das Issue ist
    öffentlich, wer schrieb, steht nur in der Datenbank. `@`-Erwähnungen
    werden entschärft. Der Dialog bittet ausdrücklich um keine
    Trailnamen oder Orte — ein Trail gehört nie in ein Issue (Konzept 4).
    Was an einem einzelnen Trail los ist, gehört in einen Hinweis an
    Buddys (#7), nie in ein Issue.
  - **Rechte des Service-Schlüssels stehen ausdrücklich im Schema**
    (patch_001): `service_role` umgeht RLS, aber keine fehlenden Grants,
    und das Live-Projekt gibt ohne automatische Freigabe keine von
    selbst. `tool/grants_check.sql` prüft sie im Dry Run — der
    API-Wächter sieht sie nicht, er fragt mit dem Publishable Key.
  - **Kein Schlüssel, kein Lauf — sichtbar**: Fehlt
    `SUPABASE_SERVICE_ROLE_KEY`, sagt es die Run-Summary, der Job bleibt
    grün. Die Projekt-URL liest der Bot aus `supabase_config.dart`.
  - **Auch der Digest nennt niemanden**: Kontext, Typ, Meldung, Frame —
    keine `user_id`, kein Name; Meldungen werden wie Feedback entschärft
    (`defuse`). Der Selbsttest hält es fest.
