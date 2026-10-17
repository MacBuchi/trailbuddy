# TrailBuddy — Arbeitsregeln für `android/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Android**: Flavors `github` (mit `REQUEST_INSTALL_PACKAGES` für den
  In-App-Update-Weg) und `play` (ohne), gleiche `applicationId`
  `de.mcbuchi.trailbuddy`. Jeder Build braucht `--flavor`. Backup-Ausschlüsse
  in `res/xml/`: Session-Token, `offline_maps/`, `outbox/`, `trail_cache/`,
  `rides/`, `updates/`, `official_trails/`, `mbgl-offline.db` (MapLibres
  Kachel-Zwischenspeicher, #155).
- **Die Dev-App** (#356, D1, seit 0.127.3): Flavor `dev` mit
  `applicationIdSuffix ".dev"`, Name „TrailBuddy Dev" (Platzhalter
  `appLabel` im Manifest), `versionName` mit `-dev`. Eine ZWEITE App
  neben der echten — eigene Daten, eigene Anmeldung — für Mess- und
  Testbuilds am Pixel des Betreibers: `flutter build apk --release
  --flavor dev --target-platform android-arm64` (mit
  `--dart-define=STALL_WATCH=true` ab #356 PR 4), dann `flutter install
  --flavor dev` bzw. `adb install`. Signiert wie die echte, wenn
  `key.properties` da ist, sonst Debug. Drei Dinge, die man wissen muss:
  - **Keine Firebase-App für `.dev`**: `google-services.json` kennt nur
    die echte Kennung, das Plugin bräche ab; `process…Dev…GoogleServices`
    ist abgeschaltet, Push sagt „noch nicht eingerichtet".
  - **Kein Update-Weg**: `src/dev/AndroidManifest.xml` nimmt
    `REQUEST_INSTALL_PACKAGES` heraus, `AppDistribution.isDevBuild`
    (aus Flutters `appFlavor`) schaltet Prüfung und Hinweise ab — ein
    Hinweis führte zur GitHub-APK, also zur anderen App.
  - **Jede Authority hängt an `${applicationId}`**, sonst scheitert die
    zweite Installation an einem doppelten Provider
    (`android_manifest_test`). Nicht in CI gebaut, nie veröffentlicht.
- **Play Store vorbereitet, nicht eingereicht** (#39 Teil, seit
  2026-10-01): `docs/play-console.md` beantwortet Data Safety,
  Berechtigungen, die beiden Vordergrunddienst-Deklarationen und das
  Store-Listing aus dem Code — ändert sich, was die App erhebt, wohin sie
  verbindet oder welche Berechtigung sie braucht, gehört die Datei in
  denselben PR (PR-Vorlage). Die Berechtigungsliste ist aus den Manifesten
  ABGELEITET, noch nicht am AAB gemessen. `docs/nutzungsbedingungen-entwurf.md`
  ist ein ENTWURF für die rechtliche Prüfung (Konzept 10.7) mit den
  offenen Fragen; er gilt nicht und ist nirgends verlinkt, bis er geprüft
  als `web/nutzungsbedingungen.html` erscheint.
