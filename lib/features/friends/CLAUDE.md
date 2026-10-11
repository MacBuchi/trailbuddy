# TrailBuddy — Arbeitsregeln für `lib/features/friends/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Nach dem Annehmen einer Buddy-Anfrage** (#33 Teil 1, seit 0.22.0,
  `connect_summary.dart` pur): `FriendshipsNotifier.accept` merkt sich
  den Trail-Stand VOR dem Annehmen, lädt Freundschaften und Trails neu
  und rechnet „gemeinsam / neu von / neu für" aus den zwei sichtbaren
  Ständen — auf dem Gerät, nie auf dem Server (Konzept 12). Privat
  zählt nicht als „neu für", wartend (Ausgangskorb) gar nicht.
  Scheitert das Neuladen, gibt es keine Zahlen, aber die Annahme steht.
  Teil 2 (Overlap-Vorschläge, RPC über `trail_overlaps`) wartet auf die
  Regel fürs Zusammenführen im Konzept.
- **Nachrichten zwischen Buddys** (#34, seit 0.111.0, Patch 021; Vorlage
  PilzBuddy #564, Regeln unverändert — Betreiber 2026-10-11: „Ja,
  höchstens 3"). `buddy_messages`, `message_repository.dart`,
  `message_providers.dart`, `conversation_screen.dart` unter
  `/friends/chat/:id`; die Sprechblase (`MessageButton`) steht an jeder
  Buddy-Zeile und an beiden Arten offener Anfragen. Sechs Dinge, die man
  wissen muss:
  - **Die Grenzen stehen nur in der Datenbank** (`app_internal.may_message`,
    Spalten-Grants, Check auf 30 Tage). Die App zeigt die Zahl vorher
    (`messagesLeft`), entscheidet aber nichts; ein abgelehntes Senden ist
    `42501` ⇒ `MessageRejectedException`. Die Spalten-Grants brauchen das
    `revoke all` davor — ein Tabellen-INSERT schlüge sie, und `created_at`
    ließe sich in die Zukunft legen. `matcher_check.sql` Block 27 und
    `grants_check.sql` wachen darüber (Gegenprobe: Tabellen-Grant, Grenze
    4, ohne Trigger, ohne Ablauf in der Policy — alle vier rot).
  - **Entfernen löscht beide Seiten** (Trigger `friendships_delete_messages`,
    wie die Aliase). `FriendshipsNotifier.remove` invalidiert deshalb auch
    `messagesProvider` — sonst bliebe die Zahl am Reiter stehen.
  - **Sortiert wird in `conversationWith`, nie in der Abfrage.**
    postgrest-dart sortiert ohne `ascending` absteigend; in PilzBuddy stand
    der Verlauf so auf dem Kopf, während der Fake aufsteigend lieferte. Der
    Fake liefert hier absichtlich NEUESTE zuerst.
  - **Gelesen markiert jede Nachricht genau einmal je Öffnen**
    (`_readAttempted`): Bewirkt das Markieren still nichts, lüde die Liste
    neu und der Bildschirm versuchte es endlos (`markReadIgnored` im Fake).
  - **Geladen wird beim Start über `BuddysNavIcon`** (Zahl am Reiter), beim
    Öffnen eines Verlaufs und beim Herunterziehen — keine Live-Verbindung.
    Kein Ausgangskorb: Ohne Netz scheitert das Senden sichtbar und der
    Text bleibt im Feld; eine Nachricht, die Tage später ankommt, wäre
    schlimmer.
  - **Konzept 12 bleibt offen:** Eine Nachricht gehört zu genau einer
    Buddy-Beziehung, der Server rechnet nichts über Nutzer hinweg. Nicht
    Ende-zu-Ende-verschlüsselt — so in `web/datenschutz.html` und
    `docs/play-console.md` („Andere In-App-Nachrichten").
