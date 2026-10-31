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
  `matcher_check.sql` Block 25. **Der Name des behaltenen Trails gilt**
  (Patch 020, `app_internal.named_for`): Ein Name zieht von B nur mit,
  wenn A für den Aufrufer namenlos ist — kein eigener, kein sichtbarer
  Buddy-Name (Regel wie `td_friend_select`); Grad, Charakter, Sterne,
  Link bleiben wie in Patch 019. Ohne das hieß A nach dem Zusammenführen
  bei mir wieder wie B, weil der eigene Name in der Anzeige vorgeht.
  Block 26, Gegenprobe mit der Funktion aus 019: rot.
- **Fotos am Hinweis** (Patch 026, #37; Vorlage PilzBuddy Patch 026,
  Fundfotos #532): EIN Foto je Hinweis (`trail_note_photos.note_id`
  unique), Bytes im privaten Bucket `trail-note-photos` (`<user_id>/<id>.jpg`
  + Vorschau `_s.jpg`), je Foto eine Zeile mit Schlüssel und Ablauf. Fünf
  Dinge, die man wissen muss:
  - **Die Sichtbarkeit ist geerbt.** `tnp_friend_select` fragt nur, ob der
    Hinweis lesbar ist (`notes_select` greift im Subselect); die
    Storage-Policy `note_photos_read` fragt nur, ob die Zeile lesbar ist.
    Keine zweite Freigabe. Ein Objekt ohne Zeile liest niemand — die App
    lädt deshalb erst die Objekte, dann die Zeile.
  - **90 Tage als Default UND Constraint**, auch für den jüngsten Hinweis,
    den `sweep_old_notes` stehen lässt — sonst wüchse der Bucket mit der
    Zahl der Trails. Abgelaufene sieht nur noch der Autor, bis der Bot
    räumt.
  - **Abgeräumt wird per ABGLEICH** im Feedback-Bot (`sweep_note_photos`,
    alle zwei Stunden): abgelaufene Zeilen löschen, dann jedes Objekt ohne
    lebende Zeile, Schonfrist 1 h für Uploads im Aufbau. Das fängt auch
    Zeilen, die per Cascade mit ihrem Hinweis gingen („erledigt",
    Rückzug, Aufräumen), ohne Trigger auf `storage.objects`.
  - **Der Patch nimmt die Vorgabe-Rechte zurück** (`revoke all … from
    anon, authenticated`), bevor er gewährt: Im Bestandsweg hatte anon
    ohne die Zeile GRANT ALL auf der Tabelle, die Frischinstallation
    nicht. Gefunden von `matcher_check.sql` Block 30 über
    `schema_local_test.sh` mit `TB_BASE_SCHEMA` — beide Wege laufen
    lassen, nicht nur die Frischinstallation.
  - **Storage gibt es lokal nur als Shim** (`tool/auth_shim.sql`:
    `storage.buckets`, `storage.objects`, `storage.foldername`). Block 30
    prüft die Tabelle und dass Bucket und Policies stehen; ihr VERHALTEN
    prüft `tool/photo_access_check.sh` im Dry Run gegen den echten
    Dienst (Upload in den eigenen/fremden Ordner, Lesen als Buddy und
    Fremder, „erledigt", Abräumen durch den Bot). Der Dry Run startet
    dafür `storage-api` mit (`config.toml`, `ci_supabase_start.sh`).
- **Hinweis und Meldung als ein Eintrag** (Patch 028, #433;
  `docs/konzept-melden.md`): Beide Tabellen bleiben, verbunden über
  `trail_notes.report_id` (`on delete set null`: fällt die Meldung im
  Aufräumen weg, bleibt der Text). Vier Dinge, die man wissen muss:
  - **`report_trail(…, note)` schreibt beides in EINER Transaktion** und
    gibt die Kennung des Textes zurück. Die alte Signatur ist im selben
    Patch gefallen (drop + create, weil sich der Rückgabetyp ändert);
    Clients bis 0.146 rufen ohne `note`, der Default nimmt es an.
    `client_id` macht auch den Text idempotent
    (`trail_notes_client_id_key`). **`#variable_conflict use_column`**:
    Die Parameter heißen wie Spalten (PostgREST ruft mit Namen), und
    `on conflict (user_id, client_id)` wäre sonst mehrdeutig.
  - **Eine Push statt zwei**: `push_on_note` hängt den Text einer
    BESTÄTIGTEN Meldung an die wartende Statuszeile desselben Absenders
    (`push_outbox.status_note_id`) und legt für diesen Empfänger keine
    Hinweiszeile an. Eigene Spalte, weil `note_id` per Cascade die ganze
    Zeile nimmt — „erledigt" vor dem Versand nähme sonst die Warnung mit.
    `push_trail_text` zählt Status und Text zusammen als „Meldungen".
  - **`notes_insert`**: eine `report_id` nur an die eigene Meldung zum
    selben Trail (Clients bis 0.146 fügen weiter direkt ein).
  - **Sichtbarkeit unverändert**: `reports_select` und `notes_select`
    sind dieselbe Regel (Meldender + direkte Buddys, nicht bei „privat").
    Das Konzept hatte für den Status anderes angenommen; der Betreiber hat
    am 2026-10-31 „wie heute" entschieden.
  `matcher_check.sql` Block 31 (Gegenproben: ohne den Ausschluss in
  `push_on_note` rot, mit `reports_select` für alle Sichtbaren rot),
  `push_flush_check.sh` Fall 3f. Lokal geprüft mit
  `tool/schema_local_test.sh` in einem `postgis/postgis:16-3.4`-Container
  (`docker run -v "$PWD":/src:ro -w /src … tool/schema_local_test.sh`,
  `TB_TEST_DIR=/tmp/…`), beide Wege, Dumps gleich.
