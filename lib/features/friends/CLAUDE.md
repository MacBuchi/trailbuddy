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
