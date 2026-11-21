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

Stand: 20. November 2026, App-Version 0.192.3. **Im geschlossenen Test
zur Überprüfung eingereicht (2026-11-20, AAB 0.192.3)** — App-Eintrag
angelegt (2026-11-19), Datensicherheit, Inhaltsbewertung, beide
Vordergrunddienst-Deklarationen (LOCATION mit „Standortfreigabe") und der
Zugang für Googles Prüfer eingetragen. Der IARC-Fragebogen enthält Blockieren
und Melden (#584; Abschnitt „Inhaltsbewertung"). Vor der Produktion steht die
rechtliche Prüfung (Konzept 10.7, #39); der
Entwurf der Nutzungsbedingungen liegt daneben in
`docs/nutzungsbedingungen-entwurf.md`.

---

## 1. Datensicherheit (Data safety)

**`docs/play-data-safety.csv`** ist der Export des Formulars, wie es in der
Console steht (2026-11-19; dabei einen verrutschten Haken korrigiert:
Fotos → Zweck nur App-Funktionalität). Ändert sich eine Antwort unten,
gehört die CSV in denselben PR — die Console importiert sie unter
*Datensicherheit → Importieren*, statt dass man alles neu klickt. Ein
Generator wie PilzBuddys `tool/play_data_safety.py` lohnt sich erst, wenn
das oft passiert.

### Vorfragen

| Frage | Antwort | Begründung |
|---|---|---|
| Erhebt oder teilt deine App die geforderten Nutzerdatentypen? | **Ja** | Konto, beigesteuerte Trail-Linien, Beiträge, Meldungen, Fehlerberichte |
| Werden alle Daten bei der Übertragung verschlüsselt? | **Ja** | Alle Ziele sind HTTPS: das Supabase-Projekt, `tiles.mcbuchi.de` (Karte und Orte), `raw.githubusercontent.com` (offizielle Trails), `api.github.com` und `github.com` (Update-Prüfung, **nur GitHub-APK**), `macbuchi.github.io` (Web-App und Rechtsseiten); nur im Browser zusätzlich `fonts.gstatic.com` und — erst nach dem Einschalten der Benachrichtigungen — `www.gstatic.com`. Push läuft serverseitig über Firebase Cloud Messaging, die Konto-Mails über Brevo; die App selbst spricht mit keinem der beiden. `test/privacy_policy_test.dart` hält die Liste vollständig |
| Können Nutzer die Löschung ihrer Daten beantragen? | **Ja** | In der App unter *Profil → Konto löschen* (sofort, Cascade über alle Tabellen) **und** ohne App über die URL unten. Zusätzlich je Trail „Löschen" im Trail-Blatt (`withdraw_contribution`: eigene Aufzeichnungen, Beitrag, Meldungen, Hinweise) und je gemerktem Startpunkt „Löschen" (#543) |
| Wie können Nutzer ein Konto erstellen? | **Nutzername und Passwort**, **OAuth** | E-Mail und Passwort; Google, GitHub, Discord über Supabase Auth (#398) |
| URL zum Löschen des Kontos | `https://macbuchi.github.io/trailbuddy/konto-loeschen.html` | Erreichbar erst nach der ersten Beförderung (`promote.yml` baut Pages) |
| Löschen einzelner Daten, ohne das Konto zu löschen (optional) | **Ja**, URL `https://macbuchi.github.io/trailbuddy/konto-loeschen.html#einzelne-daten` | Der Abschnitt steht seit 0.189.2 auf der Seite (englisch `delete-account.html#single-data`). **Bis er nach einer Beförderung live ist: „Nein"** — Google verlangt, dass die Seite die Schritte zeigt (so am 2026-11-19 eingetragen) |
| Unabhängige Sicherheitsüberprüfung? | **Nein** | |
| Enthält die App Werbung? | **Nein** | Keine Werbe- oder Analyse-SDKs in `pubspec.yaml`; von Firebase nur Messaging, kein Analytics, kein Crashlytics |
| Verwendet die App Werbe-IDs? | **Nein** | Gemessen am AAB (0.189.1): kein `com.google.android.gms.permission.AD_ID` im zusammengeführten Manifest. Bringt ein neues SDK sie mit, ändert sich die Antwort — dann `tools:node="remove"` oder ehrlich „Ja" |

### Datentypen

Für jeden Typ fragt die Konsole: *erhoben*, *geteilt*, *nur kurzzeitig
verarbeitet*, *erforderlich oder optional* — plus die Zwecke.

| Datentyp | Erhoben | Geteilt | Pflicht? | Zweck | Woher |
|---|---|---|---|---|---|
| **Standort → Genauer Standort** | Ja | Nein¹ | Optional | App-Funktionalität | Die beigesteuerten Trail-Linien (`trail_recordings.geom`, Höhen `ele`, Zeitpunkt `recorded_at`). Nur die Ausschnitte, die der Nutzer im Zerlege-Blatt oder beim Import als Trail auswählt — die ganze Fahrt bleibt auf dem Gerät (siehe „Nicht erhoben"). Sichtbar für den Nutzer und seine direkten Buddys, bei „Nur für mich" nur für ihn |
| **Standort → Genauer Standort** (Forts.) | Ja | Nein¹ | Optional | App-Funktionalität | Gruppenfahrt (#519, Patch 032): die genaue Position mit Zeitpunkt (~1 m, etwa alle 15 s), nur während einer Fahrt, in der der Nutzer „Live mit Buddys" eingeschaltet hat (je Fahrt, ab Werk aus), als Presence in Paarkanälen `live:<a>:<b>` — **nicht gespeichert**, verschwindet mit dem Kanal. Nur an direkte Buddys in derselben oder einer Nachbarzelle, die Live auch anhaben (das Gerät des Senders wählt), keiner über „sieht mich" ausgeschlossen (Policies auf `realtime.messages`). Im Formular als „flüchtig verarbeitet" angeben. Dazu der Schalter „Homie" in `buddy_nearby_prefs` |
| **Standort → Genauer Standort** (Forts.) | Ja | Nein¹ | Optional | App-Funktionalität | Gemerkte Startpunkte (#543, Patch 030, `start_points`): Name, Lage (lat/lon), Sichtbarkeit — vom Nutzer eingegeben (Ort der Karte, langer Druck, Planer-Start oder „Mein Standort merken", das privat vorbelegt ist), nie aus Fahrten abgeleitet. Sichtbar für den Nutzer und seine direkten Buddys, bei „privat" nur für ihn; nach dem Entfreunden sofort nicht mehr. Löschbar je Punkt, per Cascade mit dem Konto. Im Formular dieselbe Zeile „Genauer Standort" wie die Trail-Linien |
| **Standort → Ungefährer Standort** | Ja | Nein¹ | Optional | App-Funktionalität | „Buddys unterwegs" (#526, Patch 031): eine Zelle eines Rasters von rund 5 km (`"<zeile>:<spalte>"`, nie eine Position), solange man unterwegs ist, als Presence im privaten Realtime-Kanal `nearby:<uid>` — **nicht gespeichert**, verschwindet mit der Verbindung. Sichtbar für direkte Buddys, die nicht über „sieht mich" ausgeschlossen sind (Policies auf `realtime.messages`). Einmal gefragt, „Ja" vorausgewählt; nie im Umkreis von 1 km um ein gerätelokales „Zuhause", nie im ersten Kilometer einer Aufzeichnung, ohne Aufzeichnung nur im Vordergrund. Dazu die Schalter je Buddy (`buddy_nearby_prefs`). `ACCESS_COARSE_LOCATION` selbst bleibt rein auf dem Gerät (Punkt auf der Karte, „Ich bin vor Ort") |
| **Persönliche Infos → E-Mail-Adresse** | Ja | Nein³ | Erforderlich | App-Funktionalität, Kontoverwaltung | Supabase Auth; Buddy-Suche über die exakte Adresse; Konto-Mails über Brevo; bei Anmeldung über einen Anbieter von dort⁵ |
| **Persönliche Infos → Name** | Ja | Nein¹ | Erforderlich | App-Funktionalität, Kontoverwaltung | `profiles.username` (Pflicht, über das Präfix suchbar) und `display_name` |
| **Persönliche Infos → Nutzer-IDs** | Ja | Nein | Erforderlich | App-Funktionalität, Kontoverwaltung | `profiles.id` (UUID aus `auth.users`) |
| **App-Aktivität → Andere nutzergenerierte Inhalte** | Ja | **Ja²** (nur Feedback) | Optional | App-Funktionalität, Entwicklerkommunikation | Beiträge zu Trails (`trail_details`: Name, Beschreibung, S-Grad, Charakter, Sterne, Sichtbarkeit, Link), Meldungen und Zustand (`trail_reports`), Texte zu Meldungen (`trail_notes`, bis 0.146 „Hinweise"; #433), Zuordnungen von Duplikaten (`trail_aliases`, `trail_distinct`; #107 — sichtbar für direkte Buddys, die beide Trails sehen), Aliase für Buddys (`friend_aliases`, nur für den Vergebenden sichtbar), Sperren (`user_blocks`, #584 — nur für den Blockierenden sichtbar), Meldungen über eine Person oder Nachricht (`content_reports`, #584: Grund, Notiz, Name und bei einer Nachricht deren Text; nur der Betreiber liest sie, 180 Tage) — alles *nicht geteilt*¹. Feedback (`feedback`: Text, Typ, App-Version; bei einer Fehlermeldung auf Wunsch das Uhr-Protokoll im Text, #510 — Tasten, Menüpunkte, Arten von Nachrichten, Sekunden seit dem Start der Uhr-App, keine Position) wird als öffentliches GitHub-Issue veröffentlicht, ohne Benutzernamen — *geteilt*² |
| **Fotos und Videos → Fotos** | Ja | Nein¹ | Optional | App-Funktionalität | Ein Foto je Text einer Meldung (#37, Patch 026): Bild ≤ 1024 px und Vorschau, ohne EXIF/XMP (entfernt und geprüft in `lib/core/photo_pipeline.dart`), im privaten Bucket `trail-note-photos`. Sichtbar für genau die, die den Text sehen; 90 Tage, mit dem Text gelöscht |
| **Nachrichten → Andere In-App-Nachrichten** | Ja | Nein¹ | Optional | App-Funktionalität | `buddy_messages` (#34, Patch 021): Text, Absender, Empfänger, Zeitpunkt, gelesen. Nur Absender und Empfänger sehen sie, 30 Tage, nicht Ende-zu-Ende-verschlüsselt (Datenschutzerklärung). Schreiben nur unter Buddys oder bei offener Anfrage (höchstens drei je Seite). Mit eingeschalteten Benachrichtigungen geht der Text gekürzt über FCM (Patch 022, siehe ⁴) |
| **App-Aktivität → Sonstige Aktionen** | Ja | Nein¹ | Optional | App-Funktionalität | Airtime unter Buddys (#36 Schritt 6, Patch 029; ab Werk aus, eigener Schalter): `trail_airtime` — je Trail der Bestwert (beste Airtime einer Durchfahrt, längster Sprung, Zehntelsekunden, Monat), sichtbar für direkte Buddys, die den Trail sehen; `airtime_counters` — eine Zeile je Nutzer mit Airtime und Sprüngen der letzten 30 Tage, Tag der Rechnung und Titeln, sichtbar für direkte Buddys. Auf dem Gerät aus den Sensordaten gerechnet; keine Fahrt, keine Position, keine Landewucht. Ausschalten löscht beides |
| **App-Info und -Leistung → Absturzprotokolle** | Ja | Nein | Erforderlich | App-Funktionalität, Analysen (Fehlersuche) | `error_reports`: Kontext, Fehlertyp, Meldung, Stack, App-Version, Plattform, ggf. Nutzer-id. Dazu beim nächsten Start Androids eigene Beendigungsgründe (ANR, Absturz, nativer Absturz mit Tombstone) — keine Position, keine Trails |
| **App-Info und -Leistung → Diagnose** | Ja | Nein | Erforderlich | App-Funktionalität | Speicherwerte (RSS/PSS in MB) und der Haupt-Thread-Auszug, die mit einem Beendigungsgrund kommen (`AppExit.summary`) |
| **Geräte- oder andere IDs** | Ja⁴ | **Ja⁴** | Optional | App-Funktionalität | `push_devices.token` — die FCM-Gerätekennung, sobald jemand Benachrichtigungen einschaltet |

**Ausdrücklich NICHT erhoben** — im Formular leer lassen: Videos,
Audio, Kontakte, Kalender, E-Mails und SMS (die Nachrichten zwischen
Buddys stehen oben unter „Andere In-App-Nachrichten"), Finanzdaten, Gesundheits- und
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
geht beim Melden nur ja oder nein. Ebenso die Sensordaten der Erkennung
(#36, seit 0.148.0 auch in der offiziellen App, ab Werk aus:
`rides/sensors/<id>.csv`, Beschleunigung und Kreisel mit 100 Hz, GPS je
Sekunde, Ereignisse und Antworten) — ausgewertet auf dem Gerät, hinaus nur
über „Sensordaten teilen" an einen Empfänger, den der Nutzer wählt; keine
Berechtigung dazu. Seit Schritt 6 (0.158.0) gehen Bestwert und Zähler
auf den Server, wenn der Nutzer teilt — oben unter „Sonstige Aktionen"
(siehe ⁵). Wer daran etwas ändert (eine Sicherung
der Fahrten in der Cloud, Konzept 10.4 „verworfen für jetzt"), ändert diese
Tabelle.

**Datenbank-Sicherungen (#603).** Der Betreiber sichert die serverseitigen
PostgreSQL-Daten für die Wiederherstellung. Die Dateien werden vor der Ablage
in einem privaten GitHub-Repository verschlüsselt. Der private Schlüssel
bleibt beim Betreiber. Beim Wochenlauf bleiben die letzten zwölf Sicherungen
erhalten. Die App lädt für diesen Zweck keine Daten hoch.

**GPX-Export ist keine Weitergabe der App** (#150): Der Nutzer tippt
„Als GPX exportieren", das System-Teilen-Menü zeigt IHM die Empfänger, die
App schickt selbst nichts ins Netz.

**Kurzzeitige Verarbeitung („processed ephemerally"):** nur beim
**ungefähren Standort ja** — die Zelle von „Buddys unterwegs" wird nie
gespeichert. Bei allen anderen Typen **nein**: Sie liegen in PostgreSQL.
Beim genauen Standort ist die Gruppenfahrt zwar flüchtig, die Trail-Linien
und Startpunkte aber nicht, und die Frage gilt je Typ.

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

**⁵ Anmeldung über Google, Microsoft, Facebook, GitHub, Discord oder LinkedIn (#398) — geändert?**
Empfehlung: **nichts Neues anzukreuzen.** Der Anbieter liefert E-Mail-Adresse,
Name und eine Kennung seines Kontos an Supabase Auth (`auth.identities`);
die Adresse steht schon oben, der Name vom Anbieter wird nicht als
Benutzername übernommen (der Trigger vergibt `trailbuddy_…`), die Kennung
ist eine Nutzer-ID wie `profiles.id`. *Geteilt* wird nichts: Der Nutzer
geht selbst zum Anbieter, die App schickt ihm keine Daten. Die
Anmeldeseite öffnet der Browser — kein neues Netzziel der App, keine
Berechtigung (der Intent-Filter für den Rücksprung ist keine).

**⁴ Das FCM-Token — erhoben UND geteilt.**
Die Antwort lautet **ja** in beiden Spalten, wie in PilzBuddy: Ein
FCM-Token ist eine Gerätekennung, es entsteht bei Google, und ohne Google
wird keine Meldung zugestellt. Die Auftragsverarbeiter-Ausnahme trägt
nicht, weil Google die Kennung selbst erzeugt.

Was die Einordnung trägt: **Optional.** Benachrichtigungen sind ab Werk
aus, ein Schalter im Profil, Ausschalten löscht die Zeile in
`push_devices`. Anders als PilzBuddy trägt die Meldung **Inhalt** (seit
0.54.0, Patch 014, Betreiber-Entscheidung): Trailname, Name bzw. Alias des
Buddys, das Statuswort und den Text dazu (≤ 140 Zeichen); seit
0.112.0 (Patch 022) auch Nachrichten zwischen Buddys — Name bzw. Alias und
der Text der jüngsten Nachricht (≤ 180 Zeichen) — aber
**nie eine Koordinate, nie einen Ort, nie eine E-Mail-Adresse**.
`tool/push_flush_check.sh` prüft das Wort für Wort, und die
Datenschutzerklärung sagt es ausdrücklich. Der Inhalt ist damit
nutzergenerierter Inhalt, den Google nur zustellt — Dienstleister, *nicht
geteilt*, dieselbe Einordnung wie Brevo.

**⁶ Die Route auf die Garmin-Uhr (#449 G2) — geteilt?**
Empfehlung: **nein, nutzerinitiiert.** Nur mit dem Schalter „Auf der Uhr
zeigen" beim Start einer Navigation gibt die App die Route (vereinfachte
Linie mit Höhen, Namen und S-Grade der Trails darauf) und während der
Fahrt die Bestwerte der Erkennung (Zahlen, keine Spur), seit 0.154.0
zu Beginn der Navigation auch die aktuelle Position (alle 10 s,
höchstens 3 min, bis die Uhr eigenes GPS meldet — „genauer Standort",
aber nur an das eigene Gerät des Nutzers) an die
Garmin-Connect-App auf DEMSELBEN Telefon, die sie an die eigene Uhr des
Nutzers bringt — dieselbe Ausnahme wie die Anfahrt. Kein Netzziel der
App, kein Garmin-Konto, keine Garmin-Aktivität (Konzept-Garmin 0 und 4).
Seit #484 auch die Gegenrichtung: Die Uhr zeichnet selbst auf und gibt
die Fahrt (Position, Höhe, Zeit) über Garmin Connect an DIESES Telefon,
wo sie unter „Meine Fahrten" liegt — auf dem Gerät, nicht erhoben und
nicht geteilt, wie jede Aufzeichnung der App. Seit #510 kommt mit jeder
Fahrt und nach einem Absturz der Uhr-App das Uhr-Protokoll (die letzten
120 Schritte des Ablaufs: Taste, Menüpunkt, Art der Nachricht, Klasse des
Fixes, Sekunden — keine Position, keine Kennung) und bleibt auf dem
Telefon (die letzten fünf); erhoben wird es erst, wenn der Nutzer es an
eine Fehlermeldung hängt (dann Feedback, ²).
Seit Uhr-App 1.8.0 (#525, #526, #519) gehen auf demselben Weg an die
eigene Uhr: mit „Ansagen" Name und S-Grad des angesagten Trails, mit
„Buddys unterwegs" der Name eines Buddys, der auch fährt, mit „Live mit
Buddys" Anfangsbuchstabe, genaue Position und Alter naher Buddys (die
ohnehin schon auf der Karte dieses Telefons stehen, Fußnote zur
Gruppenfahrt) — wieder nur an das Gerät des Nutzers, nicht erhoben.
Was Garmin Connect selbst überträgt, ist Garmins Sache; die
Datenschutzerklärung sagt beides. **Paket-Sichtbarkeit:** Garmins
Companion-SDK (`com.garmin.connectiq:ciq-companion-app-sdk`) bringt
`<queries><package android:name="com.garmin.android.apps.connectmobile"/>`
mit — genau ein Paket, keine `QUERY_ALL_PACKAGES`. Dazu einen exportierten
Dienst `IQGarminBindingService` (Intent-Filter des SDK, über den Garmin
Connect antwortet) und eine nicht exportierte Dialog-Activity; keine neue
Berechtigung. Am AAB nachprüfen.

**⁵ Sind beigesteuerte Linien „Fitnessdaten"?**
Empfehlung: **nein.** Google meint mit *Fitness* Angaben über körperliche
Aktivität (Schritte, Kalorien, Trainingseinheiten). Auf dem Server liegt
eine Wegstrecke mit Höhen und einem Zeitpunkt — als Standortdatum bereits
oben deklariert. Geschwindigkeit, Dauer, Herzfrequenz oder Leistung werden
weder erhoben noch berechnet und hochgeladen. Airtime und Ranking (#36
Schritt 6, 0.158.0) haben die Frage neu gestellt: Es gibt KEINE Tabelle
„Ereignis je Fahrt und Trail", nur einen Bestwert je Trail (mit Monat) und
eine Zahl der letzten 30 Tage — Sprungzeiten eines Spiels, keine
Trainingseinheit, keine Kalorien, keine Herzfrequenz. Empfehlung bleibt
**nein**, deklariert als „App-Aktivität → Sonstige Aktionen"; wer eine
Dauer, Strecke oder Geschwindigkeit je Fahrt dazunimmt, stellt sie neu.

### Berechtigungen im Build

**Am AAB gemessen** (0.189.1+285, Artefakt `android-aab` des Release-Laufs,
2026-11-18, `bundletool` 1.18.3 — das AAB des ersten Hand-Uploads; vorher
0.158.0+242 am 2026-11-07, unverändert). Die Liste stimmt mit dem Binary überein;
vor jedem Upload mit dem AAB dieses Uploads wiederholen und Abweichungen
hier eintragen:

```bash
bundletool dump manifest --bundle trailbuddy-v<version>.aab \
  | grep -E 'uses-permission|uses-feature|foregroundServiceType|<queries|<package '
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
| `ACCESS_WIFI_STATE` | Netzstatus der Karte (keine Laufzeitabfrage); zieht `uses-feature android.hardware.wifi` mit `required="false"` nach sich, schließt also kein Gerät aus | MapLibre (`android-sdk-opengl`) |
| `com.google.android.c2dm.permission.RECEIVE` | Push entgegennehmen (keine Laufzeitabfrage, im Store nicht gelistet) | Firebase-Bibliothek — am AAB bestätigt |
| `de.mcbuchi.trailbuddy.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | Eigene Signatur-Berechtigung, mit der `ContextCompat.registerReceiver` nicht exportierte Empfänger schützt; kein Nutzer sieht sie | `androidx.core` (erzeugt) |
| `REQUEST_INSTALL_PACKAGES` | Update der GitHub-APK in der App | Manifest — **nur im `github`-Flavor**, im `play`-Flavor per `tools:node="remove"` entfernt |

**Entfernt:** `RECEIVE_BOOT_COMPLETED` (`flutter_foreground_task` bringt es
für einen Autostart mit, den die App nicht nutzt) per `tools:node="remove"`
— am AAB bestätigt. Der Empfänger des Plugins für `BOOT_COMPLETED` steht
noch im Manifest, bekommt ohne die Berechtigung aber nichts zugestellt.
`REQUEST_INSTALL_PACKAGES` fehlt im AAB wie vorgesehen (`play`-Flavor).
**Paketsichtbarkeit:** genau ein `<queries>`-Eintrag,
`com.garmin.android.apps.connectmobile`, aus Garmins Companion-SDK
(`android/CLAUDE.md`, „Die Garmin-Uhr") — kein `QUERY_ALL_PACKAGES`, also
keine Deklaration in der Console. **Sensoren:** Beschleunigung und Gyro
(#36) laufen mit 10 ms (`kSensorSamplingPeriod`), unter der Grenze von
200 Hz, ab der Android 12 `HIGH_SAMPLING_RATE_SENSORS` verlangt; wer den
Takt unter 5 ms setzt, braucht die Berechtigung und trägt sie hier ein.
**Dienst-Typen im AAB:** `ForegroundService` (`flutter_foreground_task`)
mit `dataSync|location`, dazu `GeolocatorLocationService` mit `location`
(aus `geolocator_android`, von der App nicht gestartet, derselbe Typ wie
in der Deklaration unten).
**Fehlt bewusst:** `ACCESS_BACKGROUND_LOCATION`, `CAMERA`, alle
Speicher-Berechtigungen — auch seit dem Foto am Hinweis (#37):
`image_picker` nimmt die Kamera über den System-Intent und die Galerie
über den Photo Picker, beides ohne Berechtigung, und sein
Plugin-Manifest deklariert keine (in PilzBuddy geprüft, 2026-09-22). `test/android_manifest_test.dart` hält die
Entfernungen und den Service-Typ `dataSync|location` fest.

**Zwei Flavors, eine `applicationId`** (`de.mcbuchi.trailbuddy`, wie in
PilzBuddy seit 1.87.1): `release.yml` baut die APK aus `github` und das AAB
aus `play` mit `--dart-define=PLAY_BUILD=true`. Das Flag schaltet den
Dart-Pfad der Update-Prüfung ab (`AppDistribution.isPlayBuild`), der Flavor
die Berechtigung — wer nur eines setzt, liefert eine halb abgeschaltete
Funktion aus.

### Deklarationen der Vordergrunddienste

Ab Android 14 verlangt Play je Dienst-Typ ein eigenes Formular mit
Begründung und Demo-Video (Konsole: *Richtlinien → App-Inhalte →
Berechtigungen für Dienste im Vordergrund*; ohne sie meldet sie „nicht
erklärte Berechtigungen"). **Beide Videos aufgenommen** (2026-11-20, 0.192.3,
Play-Flavor gegen live, Testkonto); sie liegen beim Betreiber, nicht im
Repo, und gehen als nicht gelistetes YouTube-Video in die Konsole.

**Neu aufnehmen** (Emulator `TB_Store_1080x1920`, siehe „Grafiken"):
Testkonto, nie ein echtes — es ist Buddy des Betreiber-Kontos, also den
Standort per `adb emu geo fix` in eine Gegend legen, in der die Karte
**keinen** Trail zeigt (sonst stünde ein privater Trail öffentlich auf
YouTube). Bereich: Ausschnitt dazunehmen, „Speichern" erst tippen, wenn der
Dialog „Lädt …" zeigt, dann `adb emu network speed edge` — bei vollem Netz
ist ein kleiner Bereich in 2 s fertig und die Benachrichtigung nie zu sehen;
bei EDGE schon vor dem Messen kommt der Knopf nicht. Fahrt: Aufnahme-Knopf,
eine Folge von `geo fix` alle 2 s, Benachrichtigungsleiste (`cmd statusbar
expand-notifications`), Home, zurück, „Fahrt beenden", verwerfen. Aufnahme
mit `adb shell screenrecord`. Mit 0.192.3 lief die Fahrt im Emulator ohne
ANR (Gegenprobe zu #586).

**`FOREGROUND_SERVICE_LOCATION`** — Aufgaben **„Navigation / Standort
verfolgen, vom Nutzer gestartet"** und, seit „Buddys unterwegs" (#526,
0.186.0) und der Gruppenfahrt (#519, 0.187.0), **„Standortfreigabe"**:
Beides ist opt-in und läuft nur während einer Fahrt in diesem Dienst — die
Zelle von rund 5 km an die Buddys, bei „Live mit Buddys" die genaue
Position etwa alle 15 s an die Mitfahrer (Datensicherheit oben). Der
Nutzer tippt den Aufnahme-Knopf,
die App misst alle fünf Sekunden die Position, auch mit dem Telefon in der
Tasche, bis er „Fahrt beenden" tippt (spätestens nach zwölf Stunden). Die
Dauerbenachrichtigung steht die ganze Zeit. Gemessen wird im Isolate des
Dienstes, weil das Main-Isolate beim Wegwischen stirbt (#28). Das Video
zeigt: Knopf in der App, Benachrichtigung in der Statusleiste, Home, Rückkehr,
„Fahrt beenden". **Navigation** (#232, seit 0.96.0) nutzt denselben Dienst und
dieselbe Benachrichtigung: Der Nutzer tippt „Navigieren", die
Benachrichtigung zeigt alle fünf Sekunden Rest und Abstand zur Route,
bis er „Navigation beenden" tippt (dort oder in der App) oder eine Minute
nach der Ankunft. Ein zweites Video braucht es nicht, ein Satz in der
Begründung genügt. **Bild-im-Bild**
(#232, seit 0.97.0): Wischt der Nutzer während einer Navigation nach
Hause, zeigt dieselbe Activity die Karte als schwebendes Fenster
(`supportsPictureInPicture`). Keine Berechtigung, ausdrücklich NICHT
`SYSTEM_ALERT_WINDOW`; Dienst, Benachrichtigung und Standort bleiben,
wie sie sind.

Beschreibung für die Konsole (Englisch, für Googles Prüfer):

> The user taps the record button to record a mountain-bike ride. While
> the ride runs, the app reads the GPS position every few seconds, also
> with the phone in a pocket and the screen off, and shows an ongoing
> notification the whole time. The service stops when the user taps "End
> ride", at the latest after 12 hours.
> The same service and notification are used when the user starts
> navigation along a planned route: the notification shows the remaining
> distance and the distance to the route, and navigation ends on "End
> navigation" or one minute after arrival. Location sharing is opt-in and
> only happens during such a ride: a coarse ~5 km cell to the user's
> confirmed friends ("buddies nearby"), and, if the user switches on "Live
> with buddies", the precise position about every 15 seconds to the friends
> riding along. The app never requests background location and never
> starts this service without a visible user action.

**`FOREGROUND_SERVICE_DATA_SYNC`** — Aufgaben **„Verarbeitung im Netzwerk
→ Sonstiger"** und **„Lokale Verarbeitung → Sonstiger"**:
nutzergestarteter Download eines Kartenbereichs für unterwegs
(Konzept-Schritt 3), danach im selben Dienst das Vorberechnen der
Routing-Stücke dieses Bereichs auf dem Gerät (`routing_bake.dart`, #380,
Schlüssel `bake`). Sichtbar über die Fortschrittsmeldung, der Dienst endet,
wenn beides fertig ist. Fahrt, Download und Vorberechnen teilen sich EINEN
Dienst über den `KeepAliveCoordinator`; das Manifest deklariert
`dataSync|location` als Obermenge, gestartet wird je Lauf nur der Typ, den
er braucht.

> The user taps "Save area" to download a map region for offline use
> while mountain biking (map tiles, elevation and path data). The download
> can take several minutes, so it runs in a foreground service with a
> visible progress notification. Right after the download, still in the
> same service, the app pre-computes route-planning data for that area on
> the device, so planning works without a network. The service stops as
> soon as both steps are done or when the user cancels. It is never
> started without this user action and does not run periodically.

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
| Datenschutzerklärung | `https://macbuchi.github.io/trailbuddy/datenschutz.html` — die verbindliche Fassung; die englische Höflichkeitsübersetzung `privacy.html` verweist darauf und umgekehrt (#209). Für einen englischen Store-Eintrag dieselbe deutsche URL angeben, die Seite führt mit einem Tipp zur englischen |
| Impressum | `https://macbuchi.github.io/trailbuddy/impressum.html` — kein eigenes Feld in der Konsole, deshalb in die lange Beschreibung |
| Nutzungsbedingungen | noch keine Seite — erst nach der rechtlichen Prüfung des Entwurfs |
| Enthält Werbung | Nein |
| In-App-Käufe | Nein |

### Kurzbeschreibung (max. 80 Zeichen)

```
Deine MTB-Trails auf der Karte – geteilt nur mit deinen Buddys.
```

(63 Zeichen)

### Vollständige Beschreibung (max. 4000 Zeichen; Stand 2026-11-19, 2301 Zeichen)

```
TrailBuddy ist das Netz für die Trails, die auf keiner öffentlichen Plattform stehen.

Du fährst sie, deine Buddys fahren sie — und bisher stehen sie in einer Chatgruppe oder nirgends. TrailBuddy hält sie auf einer Karte fest, mit Schwierigkeit, Zustand und dem, was gerade los ist. Sichtbar nur für dich und die Buddys, mit denen du verbunden bist. Keine öffentliche Karte, keine Suche nach Trails, kein Ranking über alle.

TRAILS
• Fahrt aufzeichnen oder GPX-Datei importieren — die App findet die Abfahrten und schlägt sie als Trails vor. Du wählst, was beigesteuert wird.
• Die ganze Fahrt bleibt auf deinem Gerät. Hinaus geht nur der Trail.
• Derselbe Trail existiert nur einmal, auch wenn ihn zehn Buddys fahren.
• Schwierigkeit S0–S5, Charakter (flowig, verblockt, Sprünge …), Sterne.

ZUSTAND
• Melden, was gilt: offen, gesperrt, zerstört, verändert — und wie gepflegt.
• Bestätigt ist eine Meldung, wenn sie jemand gefahren ist oder vor Ort war.
• Ein Text und ein Foto für deine Buddys: „Gesperrt — Baum liegt quer nach der zweiten Kehre."
• Auf Wunsch eine Benachrichtigung, wenn ein Buddy etwas meldet.

BUDDYS
• Nachrichten direkt an einen Buddy.
• Buddys unterwegs: Sieh, wer gerade in deiner Gegend fährt — nur als grobes Gebiet, nie als Position, und nur, solange du willst.
• Gruppenfahrt: Bei einer gemeinsamen Runde seht ihr euch genau auf der Karte, für diese eine Fahrt.

UNTERWEGS
• Runden über deine Trails planen: Die App sucht einen Weg, der möglichst viele davon mitnimmt, mit sinnvollen Anstiegen.
• Navigieren ohne Abbiegehinweise: Die Karte dreht mit, auf Wunsch als kleines Fenster über anderen Apps, und kurze Ansagen sagen den nächsten Trail an.
• Bereiche der Karte speichern und ohne Empfang weiterfahren.
• Orte auf der Karte: Wasser, Einkehr, Rad-Service.
• Anfahrt: der Trailkopf geht an die Navi-App deiner Wahl.
• Fahrten und Trails als GPX exportieren — deine Daten bleiben deine.

Kein Werbebanner, kein Tracking, keine In-App-Käufe. TrailBuddy ist ein privates Projekt und finanziert sich nicht über deine Daten.

Hinweis: TrailBuddy sagt nicht, ob ein Weg befahren werden darf oder gerade sicher ist. Du fährst auf eigene Verantwortung — beachte Sperrungen, Wegeregeln und Naturschutz vor Ort.

Impressum: https://macbuchi.github.io/trailbuddy/impressum.html
```

**Die Garmin-Uhr fehlt mit Absicht**, bis die Uhr-App im Connect-IQ-Store steht (`docs/garmin-store.md`) — sonst verspräche der Eintrag, was niemand installieren kann.

**Nicht hineinschreiben:** Verweise auf APK-Downloads oder Selbst-Updates
(Play verbietet sie; der Play-Build hat den Weg abgeschaltet), keine
Trailnamen, Orte oder Regionen — auch nicht als Beispiel. „Legal",
„offiziell", „erlaubt" kommen nicht vor: Die App kann es nicht wissen
(Konzept 7), und die Ebene der offiziellen Trails sagt nur „ausgewiesen
laut Quelle".

### Grafiken

Symbol und Vorstellungsgrafik erzeugt `tool/brand_icons.py`, nie von Hand:
`store/play_icon_512.png` (randlos, Play rundet selbst ab) und
`store/feature_graphic.png` (1024 × 500, ohne Alpha). Die Zeile darin
gehört zur Kurzbeschreibung — wer die eine ändert, prüft die andere.

**Screenshots** (fünf, 1080 × 1920 = 9:16, die Größe für Empfehlungen in
Play, die mindestens vier verlangen): Karte, Trail-Blatt, Buddy-Chat,
Trail-Liste, Rundenplaner.
Nie mit einem echten Konto — ein echter Trail im Store wäre genau die
öffentliche Karte, die Konzept 7 ausschließt. Die Bilder liegen beim
Betreiber, nicht im Repo; neu aufnehmen so:

1. Lokaler Stack und Schema (`supabase start`, `tool/db_migrate.sh` gegen
   `127.0.0.1:54522`), dann `python3 tool/store_demo.py`: vier erfundene
   Nutzer, 14 öffentliche OSM-Trails am Rosskopf, zwei Meldungen, ein
   Chat. Die Basiskarte deckt nur DACH ab — ein Gebiet außerhalb zeigt
   leere Kacheln (so ging der erste Versuch in Ligurien aus).
2. Emulator mit 1080 × 1920 bei 420 dpi (eigenes AVD, `hw.lcd.*` in der
   `config.ini`), Sprache Deutsch (`adb root`, `setprop persist.sys.locale
   de-DE`, Zygote neu), Statusleiste im Demo-Modus
   (`com.android.systemui.demo`: Uhr, volles Akku, kein Mobilfunk).
3. Play-APK gegen den Stack bauen: `--flavor play
   --dart-define=PLAY_BUILD=true --dart-define=SUPABASE_URL=http://10.0.2.2:54521`
   plus der lokale Anon-Key. Android sperrt Klartext-HTTP; für diesen Bau
   `android:usesCleartextTraffic="true"` VORÜBERGEHEND ins Manifest und
   danach per Dateikopie zurück (nie committen).
4. Standort per `adb emu geo fix`. **Keine Fahrt im Emulator**: Mit einer
   Folge von `geo fix` hing der GNSS-Dienst des Emulators (Android 16) in
   einer Verklemmung — `stopNmea` wartet auf die HAL, deren
   `reportNmea` auf dieselbe Sperre —, und die App stand im ANR, weil
   der Geolocator beim Abmelden darauf wartete (2026-11-19; behoben mit
   `geolocator_android` 5.2.1 in 0.189.3, #586 — Fahrt im Emulator vor
   dem nächsten Bilderlauf neu prüfen). Ein Bild der
   Fahrt kommt vom Gerät. Zoomen geht mit dem
   Ein-Finger-Doppeltipp-Ziehen (`input tap` + `input motionevent`), nicht
   mit `sendevent`. Bilder mit `adb exec-out screencap -p`, für Play ohne
   Alpha speichern (JPEG oder PNG ohne Transparenz).

### App-Inhalte (Dashboard „Wichtige Angaben zu den Inhalten deiner App")

| Punkt | Antwort | Begründung |
|---|---|---|
| Datenschutzerklärung | `https://macbuchi.github.io/trailbuddy/datenschutz.html` | |
| App-Zugriff (Anmeldedaten) | Funktionen eingeschränkt → Testkonto für die Prüfer | Ohne Konto nur die Anmeldung. Wo Adresse und Passwort liegen, steht im DocuHub, nicht hier |
| Anzeigen | Nein | |
| Zielgruppe | Empfehlung **nur 18+** — Entscheidung des Betreibers offen | Standort teilen und Nachrichten unter Nutzern; unter 18 prüft Google strenger, unter 13 gilt die Familien-Richtlinie. Kein Dokument nennt bisher ein Mindestalter — gehört dann auch in die Nutzungsbedingungen |
| Gesundheit | Empfehlung **„Aktivität und Fitness"** — Entscheidung des Betreibers offen | Die App zeichnet Radfahrten auf. Kein Widerspruch zur Datensicherheit: Die Fahrten bleiben auf dem Gerät, „Gesundheit und Fitness" ist dort nicht erhoben. Kein Health Connect |
| Behörden-Apps | Nein | |
| Finanzfunktionen | Keine | |
| Kategorie | Sport | Abschnitt 2 |

### Inhaltsbewertung (IARC-Fragebogen)

Ehrlich antworten, sonst passt die Bewertung nicht zum Binary:

- Gewalt, Sexualität, Drogen, Glücksspiel: **nein**.
- **Können Nutzer miteinander interagieren oder Inhalte austauschen?**
  **Ja** — Buddy-Verbindungen, geteilte Trails, Meldungen und Hinweise,
  Nachrichten zwischen zwei Buddys (#34), Feedback.
- **Können Nutzer ihren Standort mit anderen teilen?** **Ja** —
  beigesteuerte Trail-Linien und gemerkte Startpunkte (#543) sind für
  Buddys sichtbar; mit „Buddys unterwegs" (#526) dazu eine grobe Zelle
  von rund 5 km, solange man unterwegs ist (ungespeichert, nur direkte
  Buddys). Genauer Live-Standort nur mit der Gruppenfahrt (#519): je
  Fahrt eingeschaltet, nur an Buddys in der Nähe, die sie auch anhaben,
  ungespeichert.
- Nutzergenerierte Inhalte werden nicht vorab moderiert; gemeldete
  Personen und Nachrichten prüft der Betreiber (#584). Feedback wird
  öffentlich.

**Der Fragebogen, wie er in der Console steht** (Stand 2026-11-20, mit der
Einreichung des geschlossenen Tests; eine Änderung heißt dort „neuen
Fragebogen starten", der den alten beim Absenden ersetzt):

| Abschnitt | Frage | Antwort |
|---|---|---|
| Kategorie | | Alle anderen App-Typen |
| Heruntergeladene App | Freigaberelevante Inhalte im App-Paket? | Nein |
| Teilen von Benutzerinhalten | Natives Feature für Text/Sprache/Bilder zwischen Nutzern? | **Ja** |
| | Nutzerinhalte die primäre Inhaltsquelle? | **Ja** (die Trails sind Beiträge) |
| | Öffentliches Teilen von Nacktheit / drastischer Gewalt? | Nein (nichts ist öffentlich) |
| | Blockieren von Nutzern oder Inhalten? | **Ja** (#584) |
| | Melden von Nutzern oder Inhalten? | **Ja** (#584) |
| | Chatmoderation? | Nein |
| | Interaktion auf eingeladene Freunde beschränkbar? | **Ja** |
| Online-Inhalte | Inhalte außerhalb des Downloads (Filme, Produkte, KI, Artikel)? | Nein — Karte und Trails sind keine Inhalte dieser Art; Nutzerinhalte stehen oben |
| Altersbeschränkte Produkte | Schwerpunkt Bewerben/Verkaufen? | Nein |
| Sonstiges | Aktueller, exakter Standort an andere Nutzer? | **Ja** (Gruppenfahrt, #519) |
| | Digitale Käufe? | Nein |
| | Auszahlungen, Gutscheine, Krypto, NFTs? | Nein |
| | Webbrowser oder Suchmaschine? | Nein |
| | Hauptsächlich Nachrichten oder Bildung? | Nein |

Blockieren (an der Buddy-Zeile, an einer Anfrage und im Verlauf; Freigeben
im Profil unter „Blockierte Nutzer") und Melden (eine Person und eine
einzelne Nachricht, mit Grund; die Meldung landet in `content_reports`,
lesbar nur mit dem Service-Schlüssel, also im Supabase-Dashboard — der
Betreiber setzt dort `handled_at`, wenn er sie bearbeitet hat) gibt es seit
0.190.0. Fotos und Trail-Texte meldet man über die Person, die sie
eingetragen hat (Betreiber 2026-11-19: schlank). Googles Richtlinie für
nutzergenerierte Inhalte verlangt beides.

### Vor dem Upload

- [ ] Rechtliche Prüfung von Nutzungsbedingungen und Datenschutzerklärung (Konzept 10.7)
- [x] Erste Beförderung gelaufen — sonst sind Datenschutz-, Impressums- und Löschseite nicht erreichbar
- [ ] AAB aus dem Release-Workflow (Artefakt `android-aab`), nicht die APK; Berechtigungen am AAB gemessen (0.158.0, 2026-11-07) — mit dem AAB des Uploads wiederholen
- [ ] Im Play-Build fehlt der Update-Hinweis (`PLAY_BUILD=true`)
- [x] Beide Demo-Videos der Vordergrunddienste aufgenommen (2026-11-20, 0.192.3)
- [x] Beide Deklarationen samt Video-Link in der Konsole eingetragen (2026-11-20; LOCATION mit „Standortfreigabe")
- [x] IARC: Blockieren und Melden (#584) in der Console nachgezogen (Stand 2026-11-20)
- [x] Store-Grafiken: Symbol und Vorstellungsgrafik unter `store/`, Screenshots beim Betreiber
- [ ] Supabase in einem Pro-Plan (Konzept 10.9) — ein pausiertes Projekt heißt eine tote App für Prüfer
- [x] Testkonto für Googles Prüfer angelegt und unter „App-Zugriff" hinterlegt (2026-11-20); wo Adresse und Passwort liegen, steht im DocuHub, nicht hier
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

---

## 3. AAB-Upload aus CI

Seit #579 lädt `release.yml` das AAB bei jedem Versionssprung als
**Entwurf** in den internen Test-Track (Muster PilzBuddy 1.91.0).
Sichtbar wird ein Stand erst, wenn ihn jemand in der Console freigibt —
dieselbe Trennung wie Prerelease und `promote.yml`. Bis das Secret
existiert, wird der Schritt übersprungen, und die Run-Summary verweist
hierher.

**Warum der erste Upload trotzdem Handarbeit ist:** Die
Play-Developer-API legt keine App-Einträge an, und Play nimmt
API-Uploads für eine App erst an, nachdem einmal von Hand ein Bundle
hochgeladen wurde.

Einmalige Einrichtung, in dieser Reihenfolge:

1. **App-Eintrag anlegen** (Paketname `de.mcbuchi.trailbuddy`, ab dem
   ersten Upload unveränderlich) und das **erste AAB von Hand** in den
   internen Test laden — das Artefakt `android-aab` eines Release-Laufs,
   nie die APK. Dabei Play App Signing annehmen (Abschnitt 2, „Vor dem
   Upload"). Gleich danach nachsehen, ob die Regel „12 Tester, 14 Tage"
   gilt.
2. **Dienstkonto:** Am einfachsten das von PilzBuddy wiederverwenden —
   es liegt im selben Entwicklerkonto. Seine Mail in der Play Console
   unter **Nutzer und Berechtigungen** für TrailBuddy einladen, und
   denselben JSON-Schlüssel hier als Secret hinterlegen (Schritt 4).
   Ein eigenes Konto ginge auch: Google Cloud Console → Dienstkonto →
   JSON-Schlüssel, keine Cloud-Rollen nötig, die Rechte kommen von Play.
3. **Berechtigung** für diese App: **„Apps in Test-Tracks
   veröffentlichen"** (so heißt sie in der Console; eine engere Stufe
   „nur Entwürfe" gibt es nicht — dass CI nur Entwürfe anlegt, ist das
   `status: draft` in `release.yml`). Kein Produktions-Recht, kein
   Konto-Admin.
4. Den JSON-Inhalt als Repo-Secret **`PLAY_SERVICE_ACCOUNT_JSON`**
   hinterlegen.

Ab dann gilt: Versionssprung ⇒ Entwurf im internen Track. Freigeben
bleibt Handarbeit in der Console.

Wer hier landet, weil der Schritt **rot** ist statt übersprungen: Das
Secret existiert, aber der Schlüssel ist widerrufen, das Dienstkonto aus
der Console entfernt, oder es fehlt das Recht für diese App. Ein falscher
Paketname fällt vorher auf: `test/release_workflow_test.dart` hält ihn
mit der `applicationId` aus Gradle zusammen. Ein Versionscode, den Play
schon kennt, wird abgelehnt — `BUILD` steigt deshalb nie zurück
(CLAUDE.md).
