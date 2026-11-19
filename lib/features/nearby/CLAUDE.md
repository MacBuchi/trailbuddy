# TrailBuddy — Arbeitsregeln für `lib/features/nearby/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Buddy in der Nähe** (#526, E8, seit 0.186.0, Patch 031; Konzept
  `docs/konzept-geraete.md` 6.1/6.2, Datenbank in `supabase/CLAUDE.md`).
  `nearby_core.dart` pur (Zelle, `nearbyPause`, `NearbyNoticeLog`),
  `nearby_providers.dart` (Merker, `nearbyPauseProvider`,
  `NearbyEngine`), `nearby_host.dart` (in `app.dart` neben dem
  PushListener), `nearby_widgets.dart` (Frage, Abschnitt unter
  „Benachrichtigungen", Blatt je Buddy), `lib/data/nearby_repository.dart`
  (Tabelle + Realtime). Sieben Dinge, die man wissen muss:
  - **Hinaus geht nur `"<zeile>:<spalte>"`** eines Rasters von 0,045°
    Breite, die Spaltenbreite je Zeile so, dass die Zelle rund 5 km im
    Quadrat ist. In der Nähe heißt: Mittelpunkte ≤ 7,6 km (dieselbe oder
    eine der acht Nachbarzellen), deshalb vergleicht `isNearTo`
    Mittelpunkte, nicht Indizes. Eine fremde Nutzlast geht durch
    `tryParse`, das nie wirft.
  - **Realtime je Nutzer, nicht je Zelle** (Betreiber 2026-11-18):
    privater Kanal `nearby:<uid>`, eigene Zelle als Presence; zugehört
    wird in den Kanälen der direkten Buddys. Realtime prüft die Rechte
    beim Beitritt und bei jedem neuen JWT, nicht je Nachricht — ein
    Kanal je Zelle zeigte jedem jeden. Ein abgelehnter Beitritt ist
    „nichts zu hören", kein Fehler.
  - **Wann geteilt wird, rechnet `nearbyPause` allein** (Reihenfolge =
    der Satz im Profil): aus/nie gefragt, keine Position, im Umkreis von
    1 km um „Zuhause", mit Fahrt erst ab 1 km vom ersten Punkt (dann auch
    im Hintergrund), ohne Fahrt nur vorne und nur mit „Zuhause". Wer
    nicht teilt, hört auch nicht zu.
  - **Gemeldet wird erst, wenn die Schalter je Buddy geladen sind**
    (`muted: null` ⇒ niemand). Im Flow-Test gefunden: Der erste Abgleich
    lief vor `nearbyPrefsProvider`, und ein stummer Buddy kam durch.
  - **Einmal je Fahrt** über `NearbyNoticeLog`, Schlüssel ist der Beginn
    der Aufzeichnung, ohne Fahrt ein Objekt je Prozess. Vorne eine
    Leiste, hinten (nur mit Fahrt möglich) eine Benachrichtigung im Kanal
    `trailbuddy_meldungen` über `rideNoticesPlugin`
    (`nearbyBackgroundNoticeProvider`, im Test überschrieben).
  - **Die Frage kommt im Buddys-Reiter**, sobald es einen angenommenen
    Buddy gibt und keine Tour läuft, je Öffnen höchstens einmal;
    Wegtippen ist keine Antwort. `FakeSettings` setzt `buddiesNearby`
    ab Werk auf `false` (schon beantwortet) — sonst käme die Frage in
    jeden Flow-Test mit Buddys.
  - **Der Host gleicht NACH dem Flush ab** (W47, #566, seit 0.190.1):
    Die Listener stoßen `_queueSync` an, eine Microtask je Durchgang.
    Synchron las `_sync` im Listener von `nearbyPositionProvider` die
    Pause, die gerade geflusht wurde (Fahrt und Fix im selben Frame) —
    sie baute sich mitten in Riverpods Lauf über ihre Abhängigkeiten
    neu: `ConcurrentModificationError` im Build des ProviderScope. Regel
    für jeden Listener: Wer auf A hört, liest synchron nichts, was A
    beobachtet. Test „Fahrt und Fix im selben Frame" im Flow-Test
    (Gegenprobe: ohne die Microtask rot).
  Takt: Der Host gleicht bei jeder Änderung ab und, solange geteilt
  wird, jede Minute (`kNearbyTick`); die Engine setzt die Zelle neu bei
  Wechsel oder alle 5 min, tritt abgelehnten Kanälen alle 2 min neu bei.
  Tests: `test/nearby/nearby_test.dart`, `test/flows/nearby_flow_test.dart`
  (Gegenproben 2026-11-18: ohne Zuhause-Regel, ohne „einmal", ohne die
  Wartepflicht der Schalter, Hintergrund als Leiste, ohne Frage, ohne
  ersten Kilometer, ohne Stimme — je rot). Mit „Ansagen" (#525,
  `voiceCuesProvider`) und laufender Fahrt spricht `nearbySpeakProvider`
  (= `speakVoice`, das Plugin ist auch im Main-Isolate registriert) den
  Satz zusätzlich. An der Uhr (1.8.0): `WatchSync.buddyNear` aus
  `_notice` — kurz vibrieren, Scheibe und Name (`garmin/CLAUDE.md`).
- **Gruppenfahrt** (#519, E4, seit 0.187.0, Patch 032; Konzept
  `docs/konzept-geraete.md` 6.3). Auf derselben Engine wie „Buddy in der
  Nähe"; neu: `buddy_map_layer.dart` (Scheiben und Quadrate der Karte,
  `nearbyBuddyNameProvider`), `LiveShareButton` in `nearby_widgets.dart`.
  Fünf Dinge, die man wissen muss:
  - **Wer meine genaue Position bekommt, entscheidet nur
    `livePairsFor`** (pur): ich habe Live an und teile, der Buddy hat
    Live an (`l` an seiner Zelle), seine Zelle liegt noch im Kanal und ist
    nah. Die Engine hält mit genau diesen einen Paarkanal
    (`NearbyRepository.livePairs`) und legt die Position gedrosselt hinein
    (`liveEvery` 15 s oder `liveMoveMeters` 40 m). Fällt ein Buddy heraus,
    vergisst die Engine auch SEINE genaue Position.
  - **Was die Karte zeigt, rechnet `buddyMapEntries`** (pur): genau, wenn
    eine Position da ist (frisch < 2 min, weg nach 15 min); sonst die
    Zelle, aber nur für die, die mich als Homie gewählt haben
    (`homieOwnersProvider`, RPC `nearby_homie_owners`). Alle anderen:
    nichts. Die Zelle empfangen trotzdem alle direkten Buddys — so
    entschieden (Betreiber 2026-11-18), so steht es im Datenschutz.
  - **Live hängt an der Fahrt**: `LiveShareNotifier` beobachtet den
    Beginn der Aufzeichnung, eine neue Fahrt (oder keine) baut ihn neu,
    also aus. Ohne Fahrt nimmt `set` nichts an.
  - **Zeit der Position ist die des Senders**, gekappt auf „jetzt" — eine
    vorgehende Uhr machte sonst ewig frisch. Bei der Zelle zählt die
    Ankunft beim Empfänger (sie wird nur alle 5 min neu gesetzt).
  - **Das Blatt je Buddy scrollt** (`isScrollControlled`): Mit dem dritten
    Schalter lief es im halben Fenster über (im Flow-Test gefunden).
    „Sieht mich" aus sperrt „Homie".
  Tests: `test/nearby/group_ride_test.dart`,
  `test/flows/group_ride_flow_test.dart` (Gegenproben 2026-11-18: Paar
  ohne Live des Buddys, ohne Nähe, ohne eigenes Live, Zelle ohne
  Homie-Prüfung, alte Position nie weg, Live überlebt die Fahrt, Position
  bleibt nach Verlassen der Nähe, Sichtungen ohne Teilen, keine
  Drosselung, Homie trotz Ausschluss — je rot). Im `FakeMapView` trifft
  ein Tipp über `tapMapAt`, nicht über das Widget der Scheibe. An der
  Uhr (1.8.0): `WatchSync` hört auf `buddySightingsProvider` und schickt
  nur die genauen Positionen (`watchBuddiesOf`, ohne Homie-Zellen),
  höchstens alle 15 s und erst nach dem „hallo" der Uhr
  (`test/garmin/watch_buddies_test.dart`).
