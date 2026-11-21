# Datenbank sichern und wiederherstellen

Der Workflow **Database Backup** sichert montags um 03:17 UTC die Schemata
`public`, `app_internal` und `auth` in einem konsistenten PostgreSQL-Dump.
Darin liegen unter anderem Trail-Beiträge, Buddys, Profile, Kontodaten,
Richtlinien, Datenbankfunktionen und der Stand der eingespielten Patches.
`tool/db_backup.sh` prüft die PostgreSQL-Hauptversion, die Mindestgröße und
die erwarteten Definitionen und Datenabschnitte, bevor es die SQL-Datei
mit `age` verschlüsselt.

Die Sicherung liegt im privaten Repo `MacBuchi/trailbuddy-backups` als
`trailbuddy-YYYY-MM-DD.sql.age` im Release `backup-YYYY-MM-DD` (UTC).
Je Kalendertag bleibt der erste vollständige Stand erhalten. Nach einem
verifizierten Upload behält der Workflow die zwölf jüngsten von ihm
erstellten Sicherungen.

Hinweisfotos liegen als separate Objekte in Supabase Storage. Für einen
vollständigen Projektumzug müssen diese Objekte separat vorhanden sein.
Das betrifft auch die Supabase-Projekteinstellungen, OAuth- und SMTP-Zugänge,
Vault-Secrets, Cron-Jobs und Edge Functions. Fahrten liegen auf dem Gerät.

## Einrichtung und erster Lauf

1. Privates Repo `MacBuchi/trailbuddy-backups` mit einer README
   initialisieren. Ein Standardbranch ist für Releases erforderlich.
2. Mit `age-keygen -o "$KEYS/trailbuddy-backup.agekey"` einen eigenen
   Schlüssel erzeugen. `$KEYS` verweist auf den geschützten Schlüsselordner
   des Betreibers. Die private Schlüsseldatei dort und auf einem gesicherten
   Medium aufbewahren. Mit `age-keygen -y "$KEYS/trailbuddy-backup.agekey"`
   den öffentlichen Empfänger als Actions-Variable `BACKUP_AGE_RECIPIENT`
   in TrailBuddy hinterlegen.
3. Ein Fine-grained PAT mit Zugriff ausschließlich auf
   `trailbuddy-backups` und **Contents: Read and write** anlegen. Als
   Actions-Secret `BACKUP_REPO_TOKEN` im TrailBuddy-Repo hinterlegen.
   `SUPABASE_DB_URL` ist die vorhandene Session-Pooler-URI.
4. **Database Backup** auf `main` mit `dry_run=true` manuell starten.
   Die Zusammenfassung nennt die PostgreSQL-Hauptversion und bestätigt die
   Verschlüsselung. Der Workflow installiert den passenden Client anhand
   der gemeldeten Server-Version.
5. Mit `dry_run=false` erneut starten. Das private Release und das
   verschlüsselte Asset prüfen. Danach einmal die folgende Restore-Probe
   durchführen und Datum und Ergebnis in #603 festhalten.

Lokal kann `bash tool/db_backup.sh --no-upload` ebenfalls prüfen und
verschlüsseln. Für die Restore-Probe lässt sich als zweites Argument
eine neue Ausgabedatei für das Chiffrat angeben.

## Restore-Probe in einer isolierten Datenbank

Ein lokaler Supabase-PostgreSQL-Server gleicher Hauptversion stellt die
Standardrollen bereit. Der folgende Ablauf verwendet eine neue Datenbank
in diesem lokalen Cluster und benötigt einen lokalen Datenbank-Superuser.
Den Cluster ohne ausgehenden Zugriff für App- und Mail-Dienste betreiben.
Die Ausgabedateien enthalten personenbezogene Daten und gehören in ein
temporäres Verzeichnis mit eingeschränktem Zugriff.

```bash
umask 077
restore_dir=$(mktemp -d)
trap 'rm -rf "$restore_dir"' EXIT
# Setze backup_date auf das Datum des gewünschten Releases (YYYY-MM-DD).
gh release download "backup-$backup_date" --repo MacBuchi/trailbuddy-backups \
  --pattern "trailbuddy-$backup_date.sql.age" --dir "$restore_dir"
age --decrypt --identity "$KEYS/trailbuddy-backup.agekey" \
  --output "$restore_dir/trailbuddy.sql" \
  "$restore_dir/trailbuddy-$backup_date.sql.age"

# Setze local_db_container auf den DB-Container des lokalen Teststacks.
local_sql() {
  docker exec -i --user postgres "$local_db_container" \
    psql -X -w -U supabase_admin -v ON_ERROR_STOP=1 "$@"
}
local_sql -d postgres -c 'create database trailbuddy_restore template template0'
local_sql -d trailbuddy_restore --single-transaction \
  -c 'drop schema public' \
  -c 'create schema extensions' \
  -c 'create extension postgis with schema extensions' \
  -c 'create extension pgcrypto with schema extensions' \
  -c 'create extension "uuid-ossp" with schema extensions' \
  -f - < "$restore_dir/trailbuddy.sql" \
  -c 'select count(*) from auth.users' \
  -c 'select count(*) from public.profiles' \
  -c 'select count(*) from public.trail_details' \
  -c 'select count(*) from public.applied_patches'
```

Konten, Profile und Beiträge gegen den erwarteten Sicherungsstand prüfen.
Zusätzlich die Datenbankrechte prüfen. `authenticated` darf z. B. die
Tabelle `public.trails` nicht direkt lesen. Nach der Probe die isolierte
Datenbank und die temporären Dateien löschen.

## Wiederanlauf eines verwalteten Supabase-Projekts

Zuerst den aktuellen Datenbankstand sichern. Für eine zusätzliche Sicherung
am selben UTC-Tag den lokalen Trockenlauf mit eigenem verschlüsseltem
Ausgabepfad verwenden. Den gewünschten Stand in der isolierten Datenbank
prüfen, bevor die App auf ein wiederhergestelltes Projekt zeigt.

Ein frisches gehostetes Supabase-Projekt hat bereits ein verwaltetes
`auth`-Schema. Für dieses Ziel den offiziellen
[Supabase-Migrationsablauf](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
verwenden. App-Schema und Patch-Stand passend zur Sicherung wiederherstellen,
die Daten aus der isoliert wiederhergestellten Datenbank übernehmen und die
Projektbestandteile aus dem ersten Abschnitt separat einrichten. Die
Zugriffsregeln für Storage und Realtime stehen in `supabase/schema.sql`.
Danach Anmeldung, Lese- und Schreibzugriffe mit einem Testkonto, Buddys und
Hinweisfotos prüfen. Erst nach dieser Prüfung auf das neue Projekt
umschalten.
