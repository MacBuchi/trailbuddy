# Play Console — Ausfüllhilfe

Vorlage für das **Data-Safety-Formular**, die **Berechtigungs-Deklarationen**
und das **Store-Listing** (Issue #39). Aufgebaut nach PilzBuddys
`docs/play-console.md`, die Antworten aber aus TrailBuddys Code
abgeleitet: `supabase/schema.sql`, `android/app/src/main/AndroidManifest.xml`
samt den Manifesten der Plugins, die Netzziele in
`test/privacy_policy_test.dart` und `web/datenschutz.html`.

> **Warum das hier steht und nicht nur in der Konsole:** Google lehnt ab,
> wenn Formular und Binary auseinanderlaufen. Ändert sich, was die App
> erhebt, wohin sie verbindet oder welche Berechtigung sie braucht, gehört
> diese Datei in denselben PR (PR-Vorlage, dritter Haken) — dann sieht man
> beim Review, dass die Konsole nachzuziehen ist.

Stand: 1. Oktober 2026, App-Version 0.68.0+79. **Noch nicht eingereicht** —
vor dem Store-Eintrag steht die rechtliche Prüfung (Konzept 10.7, #39), und
der Entwurf der Nutzungsbedingungen liegt daneben in
`docs/nutzungsbedingungen-entwurf.md`.

---

## 1. Datensicherheit (Data safety)

Anders als in PilzBuddy gibt es noch **keine CSV zum Importieren**
(`tool/play_data_safety.py` dort). Beim ersten Ausfüllen von Hand nach den
Tabellen unten; ein Werkzeug lohnt sich erst, wenn sich Antworten ändern.

### Vorfragen

| Frage | Antwort | Begründung |
|---|---|---|
| Erhebt oder teilt deine App die geforderten Nutzerdatentypen? | **Ja** | Konto, beigesteuerte Trail-Linien, Beiträge, Meldungen, Fehlerberichte |
| Werden alle Daten bei der Übertragung verschlüsselt? | **Ja** | Alle Ziele sind HTTPS: das Supabase-Projekt, `tiles.mcbuchi.de` (Karte und Orte), `raw.githubusercontent.com` (offizielle Trails), `api.github.com` und `github.com` (Update-Prüfung, **nur GitHub-APK**), `macbuchi.github.io` (Web-App und Rechtsseiten); nur im Browser zusätzlich `fonts.gstatic.com` und — erst nach dem Einschalten der Benachrichtigungen — `www.gstatic.com`. Push läuft serverseitig über Firebase Cloud Messaging, die Konto-Mails über Brevo; die App selbst spricht mit keinem der beiden. `test/privacy_policy_test.dart` hält die Liste vollständig |
| Können Nutzer die Löschung ihrer Daten beantragen? | **Ja** | In der App unter *Profil → Konto löschen* (sofort, Cascade über alle Tabellen) **und** ohne App über die URL unten. Zusätzlich je Trail „Löschen" im Trail-Blatt (`withdraw_contribution`: eigene Aufzeichnungen, Beitrag, Meldungen, Hinweise) |
| URL zum Löschen des Kontos | `https://macbuchi.github.io/trailbuddy/konto-loeschen.html` | Erreichbar erst nach der ersten Beförderung (`promote.yml` baut Pages) |
| Unabhängige Sicherheitsüberprüfung? | **Nein** | |
| Enthält die App Werbung? | **Nein** | Keine Werbe- oder Analyse-SDKs in `pubspec.yaml`; von Firebase nur Messaging, kein Analytics, kein Crashlytics |

### Datentypen

Für jeden Typ fragt die Konsole: *erhoben*, *geteilt*, *nur kurzzeitig
verarbeitet*, *erforderlich oder optional* — plus die Zwecke.

| Datentyp | Erhoben | Geteilt | Pflicht? | Zweck | Woher |
|---|---|---|---|---|---|
| **Standort → Genauer Standort** | Ja | Nein¹ | Optional | App-Funktionalität | Die beigesteuerten Trail-Linien (`trail_recordings.geom`, Höhen `ele`, Zeitpunkt `recorded_at`). Nur die Ausschnitte, die der Nutzer im Zerlege-Blatt oder beim Import als Trail auswählt — die ganze Fahrt bleibt auf dem Gerät (siehe „Nicht erhoben"). Sichtbar für den Nutzer und seine direkten Buddys, bei „Nur für mich" nur für ihn |
| **Standort → Ungefährer Standort** | Nein | — | — | — | `ACCESS_COARSE_LOCATION` ist deklariert, aber ein grober Fix wird nur auf dem Gerät benutzt (Punkt auf der Karte, „Ich bin vor Ort"); an den Server geht nie eine Position |
| **Persönliche Infos → E-Mail-Adresse** | Ja | Nein³ | Erforderlich | App-Funktionalität, Kontoverwaltung | Supabase Auth; Buddy-Suche über die exakte Adresse; Konto-Mails über Brevo |
| **Persönliche Infos → Name** | Ja | Nein¹ | Erforderlich | App-Funktionalität, Kontoverwaltung | `profiles.username` (Pflicht, über das Präfix suchbar) und `display_name` |
| **Persönliche Infos → Nutzer-IDs** | Ja | Nein | Erforderlich | App-Funktionalität, Kontoverwaltung | `profiles.id` (UUID aus `auth.users`) |
| **App-Aktivität → Andere nutzergenerierte Inhalte** | Ja | **Ja²** (nur Feedback) | Optional | App-Funktionalität, Entwicklerkommunikation | Beiträge zu Trails (`trail_details`: Name, Beschreibung, S-Grad, Charakter, Sterne, Sichtbarkeit, Link), Meldungen und Zustand (`trail_reports`), Hinweise (`trail_notes`), Aliase für Buddys (`friend_aliases`, nur für den Vergebenden sichtbar) — alles *nicht geteilt*¹. Feedback (`feedback`: Text, Typ, App-Version) wird als öffentliches GitHub-Issue veröffentlicht, ohne Benutzernamen — *geteilt*² |
| **App-Info und -Leistung → Absturzprotokolle** | Ja | Nein | Erforderlich | App-Funktionalität | `error_reports`: Kontext, Fehlertyp, Meldung, Stack, App-Version, Plattform, ggf. Nutzer-id. Dazu beim nächsten Start Androids eigene Beendigungsgründe (ANR, Absturz, nativer Absturz mit Tombstone) — keine Position, keine Trails |
| **App-Info und -Leistung → Diagnose** | Ja | Nein | Erforderlich | App-Funktionalität | Speicherwerte (RSS/PSS in MB) und der Haupt-Thread-Auszug, die mit einem Beendigungsgrund kommen (`AppExit.summary`) |
| **Geräte- oder andere IDs** | Ja⁴ | **Ja⁴** | Optional | App-Funktionalität | `push_devices.token` — die FCM-Gerätekennung, sobald jemand Benachrichtigungen einschaltet |

**Ausdrücklich NICHT erhoben** — im Formular leer lassen: Fotos, Videos,
Audio, Kontakte, Kalender, Nachrichten, Finanzdaten, Gesundheits- und
Fitnessdaten (siehe ⁵), Web-Browsing-Verlauf, installierte Apps, keine
Advertising-ID (`error_reports.platform` ist „android"/„web").

**Die aufgezeichnete Fahrt gilt nicht als erhoben.** Google zählt Daten,
die nur auf dem Gerät verarbeitet werden, nicht als *erhoben*. Die Fahrt
(`rides/<id>.jsonl`: Position alle fünf Sekunden, Genauigkeit, Zeit, rohe
GPS-Höhe, Antworten auf Rückfragen, Marken) liegt im App-Verzeichnis, ist
vom Android-Backup ausgeschlossen und verlässt das Gerät nie von selbst.
Hinaus geht nur, was der Nutzer im Zerlege-Blatt als Trail auswählt — das
steht oben unter „Genauer Standort". Dasselbe gilt für den Ausgangskorb
(`outbox/`), den Zwischenspeicher der Trails (`trail_cache/`), gespeicherte
Kartenbereiche und die „Vor Ort"-Prüfung: alles auf dem Gerät, an den Server
geht beim Melden nur ja oder nein. Wer daran etwas ändert (eine Sicherung
der Fahrten in der Cloud, Konzept 10.4 „verworfen für jetzt"), ändert diese
Tabelle.

**GPX-Export ist keine Weitergabe der App** (#150): Der Nutzer tippt
„Als GPX exportieren", das System-Teilen-Menü zeigt IHM die Empfänger, die
App schickt selbst nichts ins Netz.

**Kurzzeitige Verarbeitung („processed ephemerally"):** bei allen Typen
**nein** — alles Erhobene liegt in PostgreSQL.

### Die Ermessensfragen — hier lohnt der zweite Blick

**¹ Zählt „Buddys sehen meine Trails" als *geteilt*?**
Empfehlung: **nein**, dieselbe Abwägung wie in PilzBuddy. Google meint mit
*geteilt* die Weitergabe an einen Dritten; nutzerinitiierte Übertragungen,
bei denen der Nutzer die Weitergabe selbst auslöst und darüber informiert
ist, sind ausgenommen. Sichtbar wird ein Beitrag nur für direkte Buddys nach
angenommener Anfrage, je Trail auf „Nur für mich" abschaltbar, nie
transitiv, nie öffentlich (Konzept 7 und 10.1, durchgesetzt per RLS).
Datenschutzerklärung und Store-Beschreibung sagen es.

Der **stille Abgleich** (Konzept 4) ändert daran nichts: Der Server
vergleicht eine beigesteuerte Linie auch mit Trails, die der Nutzer nicht
sieht, gibt aber nur die Trail-Kennung zurück — nie, ob sie neu ist, nie
fremde Beiträge. Es fließt nichts an andere Nutzer, das sie nicht ohnehin
über eine Buddy-Verbindung sähen.

Auf derselben Ausnahme steht die **Anfahrt** (#151, seit 0.67.0): Der
Nutzer tippt „Anfahrt", Android zeigt IHM den Wähler mit den installierten
Navi-Apps — die App entscheidet weder, wohin der Trailkopf geht, noch
schickt sie selbst etwas ins Netz. Wo niemand `geo:` annimmt, landet die
Koordinate in der Zwischenablage (Konzept 9: nie ein fester Kartendienst).

**² Feedback landet öffentlich auf GitHub — *geteilt*.**
Empfehlung: **ja, als geteilt deklarieren.** Der Feedback-Bot macht daraus
öffentliche Issues — anders als in PilzBuddy ohne Benutzernamen, aber
dauerhaft und außerhalb der Kontrolle des Nutzers; ein Löschen des Kontos
nimmt das Issue nicht mit. Dialog und Datenschutzerklärung sagen es,
das Formular soll es auch sagen. Untertreiben ist hier das teurere Risiko.

**³ Der Mailversand über Brevo — *geteilt*?**
Empfehlung: **nein.** Brevo ist Auftragsverarbeiter für drei Mails, die der
Nutzer selbst auslöst (Registrierung bestätigen, Passwort zurücksetzen,
Adresse wechseln). Übermittelt wird die E-Mail-Adresse und der Inhalt der
Mail, nie Trails oder Linien. Google nimmt Dienstleister, die nur im
Auftrag und für diesen Zweck verarbeiten, von *geteilt* aus — Bedingung
dafür ist die Nennung in der Datenschutzerklärung, und die steht dort.

**⁴ Das FCM-Token — erhoben UND geteilt.**
Die Antwort lautet **ja** in beiden Spalten, wie in PilzBuddy: Ein
FCM-Token ist eine Gerätekennung, es entsteht bei Google, und ohne Google
wird keine Meldung zugestellt. Die Auftragsverarbeiter-Ausnahme trägt
nicht, weil Google die Kennung selbst erzeugt.

Was die Einordnung trägt: **Optional.** Benachrichtigungen sind ab Werk
aus, ein Schalter im Profil, Ausschalten löscht die Zeile in
`push_devices`. Anders als PilzBuddy trägt die Meldung **Inhalt** (seit
0.54.0, Patch 014, Betreiber-Entscheidung): Trailname, Name bzw. Alias des
Buddys, das Statuswort und beim Hinweis dessen Text (≤ 140 Zeichen) — aber
**nie eine Koordinate, nie einen Ort, nie eine E-Mail-Adresse**.
`tool/push_flush_check.sh` prüft das Wort für Wort, und die
Datenschutzerklärung sagt es ausdrücklich. Der Inhalt ist damit
nutzergenerierter Inhalt, den Google nur zustellt — Dienstleister, *nicht
geteilt*, dieselbe Einordnung wie Brevo.

**⁵ Sind beigesteuerte Linien „Fitnessdaten"?**
Empfehlung: **nein.** Google meint mit *Fitness* Angaben über körperliche
Aktivität (Schritte, Kalorien, Trainingseinheiten). Auf dem Server liegt
eine Wegstrecke mit Höhen und einem Zeitpunkt — als Standortdatum bereits
oben deklariert. Geschwindigkeit, Dauer, Herzfrequenz oder Leistung werden
weder erhoben noch berechnet und hochgeladen. Kommt mit Airtime und
Ranking (#36) eine Tabelle „Ereignis je Fahrt und Trail" dazu, ist diese
Frage neu zu stellen.

### Berechtigungen im Build

**Abgeleitet, noch nicht am Binary gemessen.** Die Liste unten stammt aus
`android/app/src/main/AndroidManifest.xml` und den Manifesten der Plugins
in `.dart_tool/package_config.json`. Vor dem ersten Upload am gebauten AAB
nachprüfen und das Ergebnis hier eintragen:

```bash
bundletool dump manifest --bundle trailbuddy-v<version>.aab | grep uses-permission
```

| Berechtigung | Wofür | Herkunft |
|---|---|---|
| `INTERNET` | Supabase, Karte, Orte, offizielle Trails | Manifest (auch `firebase_messaging`) |
| `ACCESS_FINE_LOCATION` | „Meine Position", Fahrt aufzeichnen, „Ich bin vor Ort" | Manifest |
| `ACCESS_COARSE_LOCATION` | dasselbe, grob (Android verlangt beide zusammen) | Manifest |
| `FOREGROUND_SERVICE` | Fahrt und Bereichs-Download halten den Prozess wach | Manifest, `flutter_foreground_task` |
| `FOREGROUND_SERVICE_LOCATION` | Typ des Dienstes während einer Fahrt (#28) und einer Navigation (#232) | Manifest, `geolocator_android` |
| `FOREGROUND_SERVICE_DATA_SYNC` | Typ des Dienstes beim Speichern eines Kartenbereichs | Manifest |
| `POST_NOTIFICATIONS` | Dauerbenachrichtigung der Fahrt und der Navigation, Fortschritt des Downloads, Rückfrage „Stimmt die Meldung?" (#116), Push | Manifest und vier Plugins |
| `VIBRATE` | Rückfrage während der Fahrt im Kanal `trailbuddy_meldungen` | Manifest, `flutter_local_notifications` |
| `ACCESS_NETWORK_STATE` | Verbindung zurück ⇒ Ausgangskorb senden; ohne Empfang kein Kartenabruf | `connectivity_plus`, `firebase_messaging` |
| `WAKE_LOCK` | Fahrt und Download über den Bildschirm-Timeout hinaus | `flutter_foreground_task`, `firebase_messaging` |
| `com.google.android.c2dm.permission.RECEIVE` | Push entgegennehmen (keine Laufzeitabfrage, im Store nicht gelistet) | Firebase-Bibliothek — am AAB bestätigen |
| `REQUEST_INSTALL_PACKAGES` | Update der GitHub-APK in der App | Manifest — **nur im `github`-Flavor**, im `play`-Flavor per `tools:node="remove"` entfernt |

**Entfernt:** `RECEIVE_BOOT_COMPLETED` (`flutter_foreground_task` bringt es
für einen Autostart mit, den die App nicht nutzt) per `tools:node="remove"`.
**Fehlt bewusst:** `ACCESS_BACKGROUND_LOCATION`, `CAMERA`, alle
Speicher-Berechtigungen. `test/android_manifest_test.dart` hält die
Entfernungen und den Service-Typ `dataSync|location` fest.

**Zwei Flavors, eine `applicationId`** (`de.mcbuchi.trailbuddy`, wie in
PilzBuddy seit 1.87.1): `release.yml` baut die APK aus `github` und das AAB
aus `play` mit `--dart-define=PLAY_BUILD=true`. Das Flag schaltet den
Dart-Pfad der Update-Prüfung ab (`AppDistribution.isPlayBuild`), der Flavor
die Berechtigung — wer nur eines setzt, liefert eine halb abgeschaltete
Funktion aus.

### Deklarationen der Vordergrunddienste

Ab Android 14 verlangt Play je Dienst-Typ ein eigenes Formular mit
Begründung und Demo-Video. **Beide Videos fehlen noch** — aufnehmen mit
einem Testkonto auf dem Emulator, NIE mit echten Trails oder einer echten
Fahrt (eine Fahrt beginnt an der Haustür).

**`FOREGROUND_SERVICE_LOCATION`** — Aufgabe **„Navigation / Standort
verfolgen, vom Nutzer gestartet"**: Der Nutzer tippt den Aufnahme-Knopf,
die App misst alle fünf Sekunden die Position, auch mit dem Telefon in der
Tasche, bis er „Fahrt beenden" tippt (spätestens nach zwölf Stunden). Die
Dauerbenachrichtigung steht die ganze Zeit. Gemessen wird im Isolate des
Dienstes, weil das Main-Isolate beim Wegwischen stirbt (#28). Das Video
zeigt: Knopf in der App, Benachrichtigung in der Statusleiste, Home, Rückkehr,
„Fahrt beenden". **Navigation** (#232, seit 0.96.0) nutzt denselben Dienst und
dieselbe Benachrichtigung: Der Nutzer tippt „Navigieren", die
Benachrichtigung zeigt alle fünf Sekunden Rest und Abstand zur Route,
bis er „Navigation beenden" tippt (dort oder in der App) oder eine Minute
nach der Ankunft. Die Position bleibt auf dem Gerät. Ein zweites Video
braucht es nicht, ein Satz in der Begründung genügt. **Bild-im-Bild**
(#232, seit 0.97.0): Wischt der Nutzer während einer Navigation nach
Hause, zeigt dieselbe Activity die Karte als schwebendes Fenster
(`supportsPictureInPicture`). Keine Berechtigung, ausdrücklich NICHT
`SYSTEM_ALERT_WINDOW`; Dienst, Benachrichtigung und Standort bleiben,
wie sie sind — die Position verlässt das Gerät auch hier nicht.

**`FOREGROUND_SERVICE_DATA_SYNC`** — Aufgabe **„Verarbeitung im Netzwerk →
Sonstiger"**: nutzergestarteter Download eines Kartenbereichs für
unterwegs (Konzept-Schritt 3). Sichtbar über die Fortschrittsmeldung, der
Dienst endet mit dem Download. Fahrt und Download teilen sich EINEN Dienst
über den `KeepAliveCoordinator`; das Manifest deklariert
`dataSync|location` als Obermenge, gestartet wird je Lauf nur der Typ, den
er braucht.

### Prominent Disclosure für den Standort

**Nicht erforderlich**, und das ist kein Versehen:

- **Kein Hintergrund-Standort.** Die Fahrt läuft über einen
  Vordergrunddienst vom Typ `location`, im Vordergrund gestartet, mit
  Dauerbenachrichtigung. Die Benachrichtigung IST die Offenlegung; die
  schwere Berechtigung bräuchte eine eigene Prüfrunde, ohne dass die App
  mehr könnte.
- **Gefragt wird nur nach einer sichtbaren Nutzeraktion**:
  `positionFixProvider` hinter „Meine Position", dem Aufnahme-Knopf und
  „Ich bin vor Ort" im Melde-Dialog. Der Positionsstrom für den Punkt auf
  der Karte (`positionStreamProvider`) fragt NIE — er nutzt eine bereits
  erteilte Erlaubnis und tut ohne sie nichts. Kein Systemdialog beim Start.
- Ohne Erlaubnis läuft alles andere weiter: Import, Karte, Liste, Buddys.

Falls die Konsole beim Review trotzdem danach fragt: dieser Abschnitt ist
die Antwort.

---

## 2. Store-Listing

### Angaben

| Feld | Wert |
|---|---|
| App-Name | TrailBuddy |
| Paketname | `de.mcbuchi.trailbuddy` (unveränderlich ab dem ersten Upload) |
| Kategorie | Sport (Alternative: Karten & Navigation) |
| Tags | Mountainbike, Radfahren, Karte |
| Kontakt-E-Mail | dieselbe wie in Datenschutzerklärung und Impressum: die gemeinsame Adresse mit PilzBuddy (Betreiber, 2026-10-01: „gleich zu PilzBuddy“). Wer sie je trennt, ändert alle drei Stellen und PilzBuddy im selben Zug |
| Website | `https://macbuchi.github.io/trailbuddy/` |
| Datenschutzerklärung | `https://macbuchi.github.io/trailbuddy/datenschutz.html` |
| Impressum | `https://macbuchi.github.io/trailbuddy/impressum.html` — kein eigenes Feld in der Konsole, deshalb in die lange Beschreibung |
| Nutzungsbedingungen | noch keine Seite — erst nach der rechtlichen Prüfung des Entwurfs |
| Enthält Werbung | Nein |
| In-App-Käufe | Nein |

### Kurzbeschreibung (max. 80 Zeichen)

```
Deine MTB-Trails auf der Karte – geteilt nur mit deinen Buddys.
```

(63 Zeichen)

### Vollständige Beschreibung (Entwurf, max. 4000 Zeichen)

```
TrailBuddy ist das Netz für die Trails, die auf keiner öffentlichen Plattform stehen.

Du fährst sie, deine Buddys fahren sie — und bisher stehen sie in einer Chatgruppe
oder nirgends. TrailBuddy hält sie auf einer Karte fest, mit Schwierigkeit, Zustand
und dem, was gerade los ist. Sichtbar nur für dich und die Buddys, mit denen du
verbunden bist. Keine öffentliche Karte, keine Suche nach Trails, kein Ranking über
alle.

TRAILS
• Fahrt aufzeichnen oder GPX-Datei importieren — die App findet die Abfahrten und
  schlägt sie als Trails vor. Du wählst, was beigesteuert wird.
• Die ganze Fahrt bleibt auf deinem Gerät. Hinaus geht nur der Trail.
• Derselbe Trail existiert nur einmal, auch wenn ihn zehn Buddys fahren.
• Schwierigkeit S0–S5, Charakter (flowig, verblockt, Sprünge …), Sterne.

ZUSTAND
• Melden, was gilt: offen, gesperrt, zerstört, verändert — und wie gepflegt.
• Bestätigt ist eine Meldung, wenn sie jemand gefahren ist oder vor Ort war.
• Hinweise für deine Buddys: „Baum liegt quer nach der zweiten Kehre."
• Auf Wunsch eine Benachrichtigung, wenn ein Buddy etwas meldet.

UNTERWEGS
• Bereiche der Karte speichern und ohne Empfang weiterfahren.
• Orte auf der Karte: Wasser, Einkehr, Rad-Service.
• Anfahrt: der Trailkopf geht an die Navi-App deiner Wahl.
• Runden über deine Trails planen und navigieren: Die Karte dreht mit, auf
  Wunsch als kleines Fenster über anderen Apps — ohne Abbiegehinweise.
• Fahrten und Trails als GPX exportieren — deine Daten bleiben deine.

Kein Werbebanner, kein Tracking, keine In-App-Käufe. TrailBuddy ist ein privates
Projekt und finanziert sich nicht über deine Daten.

Hinweis: TrailBuddy sagt nicht, ob ein Weg befahren werden darf oder gerade sicher
ist. Du fährst auf eigene Verantwortung — beachte Sperrungen, Wegeregeln und
Naturschutz vor Ort.

Impressum: https://macbuchi.github.io/trailbuddy/impressum.html
```

**Nicht hineinschreiben:** Verweise auf APK-Downloads oder Selbst-Updates
(Play verbietet sie; der Play-Build hat den Weg abgeschaltet), keine
Trailnamen, Orte oder Regionen — auch nicht als Beispiel. „Legal",
„offiziell", „erlaubt" kommen nicht vor: Die App kann es nicht wissen
(Konzept 7), und die Ebene der offiziellen Trails sagt nur „ausgewiesen
laut Quelle".

### Grafiken

**Noch offen** (#39): Unter `store/` fehlt alles. Gebraucht werden das
App-Symbol 512 × 512 (aus `tool/brand_icons.py`, nie von Hand), eine
Feature-Grafik 1024 × 500 und Screenshots 1080 × 1920. Screenshots nur mit
einem Testkonto und erfundenen Trails aufnehmen — ein echter Trail im Store
wäre genau die öffentliche Karte, die Konzept 7 ausschließt.

### Inhaltsbewertung (IARC-Fragebogen)

Ehrlich antworten, sonst passt die Bewertung nicht zum Binary:

- Gewalt, Sexualität, Drogen, Glücksspiel: **nein**.
- **Können Nutzer miteinander interagieren oder Inhalte austauschen?**
  **Ja** — Buddy-Verbindungen, geteilte Trails, Meldungen und Hinweise,
  Feedback.
- **Können Nutzer ihren Standort mit anderen teilen?** **Ja** —
  beigesteuerte Trail-Linien sind für Buddys sichtbar. Kein Live-Standort.
- Nutzergenerierte Inhalte werden nicht moderiert; Feedback wird
  öffentlich.

### Vor dem Upload

- [ ] Rechtliche Prüfung von Nutzungsbedingungen und Datenschutzerklärung (Konzept 10.7)
- [ ] Erste Beförderung gelaufen — sonst sind Datenschutz-, Impressums- und Löschseite nicht erreichbar
- [ ] AAB aus dem Release-Workflow (Artefakt `android-aab`), nicht die APK; Berechtigungen am AAB gemessen und oben eingetragen
- [ ] Im Play-Build fehlt der Update-Hinweis (`PLAY_BUILD=true`)
- [ ] Beide Demo-Videos der Vordergrunddienste aufgenommen
- [ ] Store-Grafiken unter `store/`
- [ ] Supabase in einem Pro-Plan (Konzept 10.9) — ein pausiertes Projekt heißt eine tote App für Prüfer
- [ ] Testkonto für Googles Prüfer angelegt; wo Adresse und Passwort liegen, steht im DocuHub, nicht hier
- [ ] Version 1.0.0 mit dem Store-Eintrag, nicht mit einer Schemaänderung (CLAUDE.md, SemVer)

**Die Regel „12 Tester, 14 Tage"** für persönliche Konten ab 2023-11-13
bestimmt den Zeitplan. Die Konsole zeigt erst nach dem Anlegen des
App-Eintrags, ob sie gilt; die 14 Tage sind Kalenderzeit.

**Play App Signing:** Mit dem ersten AAB wird der eigene Keystore zum
Upload-Key, signiert wird danach von Google. Die Play-Fassung hat damit
eine andere Signatur als die GitHub-APK — wer wechselt, deinstalliert
einmal. Trails und Konto liegen auf dem Server und bleiben; verloren gehen
gespeicherte Kartenbereiche, der Ausgangskorb und **alle Fahrten** (sie
liegen nur auf dem Gerät — vorher als GPX exportieren). Das gehört in die
Einladung der Tester. Den Fingerprint des Upload-Keys führt der DocuHub.
