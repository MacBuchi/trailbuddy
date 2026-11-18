/// Zugangsdaten des Supabase-Projekts.
///
/// Die Vorgaben zeigen auf das Live-Projekt (Region und Einrichtung:
/// Konzept, Punkt 9). Der Publishable-Key ist bewusst öffentlich — die
/// Sicherheit liegt vollständig in den Row-Level-Security-Policies
/// (`supabase/schema.sql`). Niemals den service_role-Key eintragen.
///
/// Gegen den lokalen Stack aus `supabase/config.toml` (Ports 5452x) baut
/// man mit `--dart-define=SUPABASE_URL=http://127.0.0.1:54521` und
/// `--dart-define=SUPABASE_KEY=<anon-Key aus supabase status -o json>`.
/// `tool/schema_check.sh` und `tool/check_service_worker.mjs` lesen die
/// Vorgaben aus dieser Datei — die Form `String.fromEnvironment(…,
/// defaultValue: '…')` muss deshalb bleiben.
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ibxrjgvwouuoydhdkfmf.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_aMBpsLzdggO9Sx-q6dCuDw_rMRca4kT',
  );
}
