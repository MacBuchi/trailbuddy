# TrailBuddy — Arbeitsregeln für `supabase/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Der Abgleich läuft in der Datenbank** (`contribute_recording`,
  Security Definer): Korridor 15 m, beidseitige Deckung ≥ 0,8, Fréchet auf
  den Punkten IM Korridor ≤ 2·d, Mindestlänge 50 m (Patch 017, Betreiber
  2026-10-04; gemessen waren 150 m), Abtastung 5 m — gemessen an 584
  Tracks. Nur „gleich" verschmilzt; Teil und Gabel werden
  neuer Trail plus unsichtbare Kante (`app_internal.trail_overlaps`). Die
  RPC gibt nur die Trail-Kennung zurück, nie ob sie neu ist. Tageslimit
  500 Aufzeichnungen je Nutzer in 24 h (Patch 006, gemessen mit
  `tool/limit_measure.sql`); `attach_elevation` zählt nicht mit. Das
  Python-Werkzeug `tool/trail_match.py` ist die Referenz und läuft mit
  `--self-test` in CI; Werkzeug und SQL kommen bei Schwellenänderungen im
  SELBEN PR.
- **`trails` hat keinen Client-Grant.** Alles Sichtbare kommt aus
  `recordings_visible` (Sicht mit `security_invoker`) und `trail_details`,
  gruppiert im Client (`buildTrails`). Eine Aggregation über alle Nutzer
  darf es nicht geben (Konzept 12).
- **Beitrag löschen** (seit 0.46.0, Patch 010, `withdrawContribution`
  im Trail-Blatt): `withdraw_contribution(trail_id)` löscht eigene
  Aufzeichnungen, eigene Hinweise und den eigenen Beitrag in EINER
  Transaktion, Security INVOKER (die RLS erlaubt jede der drei Löschungen
  ohnehin). Einzeln aus der App ginge es nicht: Fällt der Beitrag zuerst,
  sagt `contributor_shares` ohne Zeile „teilt", und ein privater Beitrag
  läge kurz offen. Den leeren Trail holt `sweep_orphan_trails`
  (nächtlich). Kein Ausgangskorb — ohne Netz scheitert es sichtbar; und
  kein Knopf, solange ein eigener Beitrag im Korb wartet (der legte die
  Zeile beim Nachholen wieder an). `matcher_check.sql` Block 21.
