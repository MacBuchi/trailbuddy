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
- **Duplikate zusammenführen** (Patch 019, #107; Regel in
  `docs/konzept-trails.md` 6.1): `merge_own_into(duplicate_id,
  target_id)` zieht die EIGENEN Aufzeichnungen, den Beitrag (A gewinnt,
  leere Felder füllt B, privat gewinnt), Hinweise und Meldungen von B
  nach A und legt die Zuordnung in `app_internal.trail_aliases` an;
  „verschieden" steht in `app_internal.trail_distinct`. Beide Tabellen
  ohne Client-Grant — gelesen wird nur über `trail_merges()`, das je
  Leser filtert (nur Paare, die er beide sieht; Erklärungen nur von
  direkten Buddys, die an einem der beiden sichtbar beitragen). Vier
  Dinge, die man wissen muss:
  - **„Grob beieinander" ist eine eigene Schwelle**, nicht die des
    Abgleichs: ≥ 50 % der kürzeren Linie innerhalb von 50 m
    (`merge_near`, geschätzt, nicht gemessen). Der Client rechnet für
    seine Auswahl dieselben Zahlen; wer sie ändert, ändert beide.
  - **`reversed` an der Zuordnung** sagt, ob B gegen A läuft — aus den
    Linien bestimmt und um die Richtung jeder Vertreterin korrigiert.
    Umgezogene und spätere Aufzeichnungen tragen damit ihre Richtung
    relativ zu A, sonst führe der Planer sie verkehrt herum.
  - **Der Abgleich vergleicht seit Patch 019 auch mit den EIGENEN
    Aufzeichnungen** des Aufrufers, nicht nur mit der Vertreterin je
    Trail: Nach dem Zusammenführen hängt die B-Linie an A, ist dort aber
    nicht die Vertreterin — ohne das legte die nächste Fahrt auf ihr
    wieder einen eigenen Trail an. Hängt der Abgleich an ein eigenes
    Duplikat, leitet die eigene Zuordnung um (nie eine fremde, E5).
  - **Ein zweiter Aufruf ist ein Erfolg** (Ausgangskorb): Steht die
    Zuordnung schon, antwortet `merge_own_into` mit dem Ziel, ohne zu
    prüfen — B kann nach dem ersten Aufruf unsichtbar sein. Ist B
    inzwischen gefegt (`sweep_orphan_trails`), fällt die Zuordnung per
    Cascade mit, und der Aufruf antwortet `P0002` wie für jede unbekannte
    Kennung; ein Korb-Auftrag muss das als „erledigt" lesen.
  `matcher_check.sql` Block 25.
