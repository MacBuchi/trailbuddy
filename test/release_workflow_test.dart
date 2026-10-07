/// Wächter über die Workflows — Konfigurationsfehler fängt nur ein
/// Konfigurations-Regressionstest (PilzBuddy-Muster). Die Fallen hier
/// sind alle still: Jede kompiliert, jede PR-CI bleibt grün.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflows = Directory('.github/workflows')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.yml'))
      .toList();
  final ci = File('.github/workflows/ci.yml').readAsStringSync();
  final release = File('.github/workflows/release.yml').readAsStringSync();

  test('es gibt die Workflows des Grundgerüsts', () {
    final names = workflows.map((f) => f.uri.pathSegments.last).toSet();
    expect(names, containsAll([
      'ci.yml', 'release.yml', 'security.yml', 'workflow-lint.yml',
      'keepalive.yml', 'promote.yml', 'preview.yml',
    ]));
  });

  test('die Web-Vorschau zeigt auf ihr eigenes Repo und trägt den Streifen', () {
    final preview = File('.github/workflows/preview.yml').readAsStringSync();
    final promote = File('.github/workflows/promote.yml').readAsStringSync();
    // Ohne das Flag sähe die Vorschau aus wie die echte App, und ein
    // Fehlerbericht daraus beträfe Code, den es nie gab.
    expect(preview, contains('--dart-define=PREVIEW_BUILD=true'));
    expect(preview, contains('--no-web-resources-cdn'));
    // Falsche base-href heißt: Die Seite lädt ihre eigenen Assets nicht
    // und bleibt weiß, ohne Fehlermeldung. Der Pfad muss zum Link im
    // Profil passen.
    expect(preview, contains('--base-href /trailbuddy-preview/'));
    expect(File('lib/core/app_info.dart').readAsStringSync(),
        contains("'https://macbuchi.github.io/trailbuddy-preview/'"));
    expect(preview, contains('external_repository: MacBuchi/trailbuddy-preview'));
    expect(preview, contains('node tool/check_service_worker.mjs build/web'));
    // Ein Deploy Key, kein Token — er hängt an genau einem Repo.
    expect(preview, contains('deploy_key:'));
    expect(preview, isNot(contains('personal_token')));
    expect(preview, isNot(contains('github_token')));
    // Die Beförderung bleibt bei der echten Adresse.
    expect(promote, contains('--base-href /trailbuddy/'));
    expect(promote, isNot(contains('trailbuddy-preview')));
  });

  test('alle Workflows pinnen dieselbe Flutter-Version', () {
    final versions = <String>{};
    for (final f in workflows) {
      for (final m in RegExp(r'flutter-version:\s*([0-9.]+)')
          .allMatches(f.readAsStringSync())) {
        versions.add(m.group(1)!);
      }
    }
    expect(versions, hasLength(1),
        reason: 'Flutter-Version driftet zwischen Workflows: $versions');
  });

  test('jeder Web-Build holt CanvasKit aus dem eigenen Build', () {
    final builds = [
      for (final line in ci.split('\n'))
        if (line.contains('flutter build web')) line,
    ];
    expect(builds, isNotEmpty);
    for (final b in builds) {
      expect(b, contains('--no-web-resources-cdn'));
      expect(b, contains('--base-href /trailbuddy/'));
    }
  });

  test('CI fährt den Service Worker gegen einen echten Browser', () {
    expect(ci, contains('node tool/check_service_worker.mjs build/web'));
    expect(File('tool/check_service_worker.mjs').existsSync(), isTrue);
  });

  test('jeder Merge veröffentlicht als Prerelease, nie als latest', () {
    // Beide Zeilen gehören zusammen: `prerelease` allein genügt nicht.
    expect(release, contains('prerelease: true'));
    expect(release, contains('make_latest: false'));
  });

  test('kein Keystore, kein Tag: das Tor steht VOR dem Taggen', () {
    // Ein Tag ohne Release ist nur von Hand zu heilen. Der Feststell-Schritt
    // muss im version-Job vor `git tag` stehen und das `decide` daran hängen.
    final versionJob = release.substring(
        release.indexOf('  version:'), release.indexOf('  build-android:'));
    final gate = versionJob.indexOf('id: keystore');
    final tag = versionJob.indexOf('git tag');
    expect(gate, greaterThan(-1));
    expect(tag, greaterThan(gate));
    expect(versionJob, contains("if: steps.keystore.outputs.have == 'true'"));
  });

  test('kein secrets-Kontext in if-Bedingungen', () {
    // `secrets` ist in `if:` NICHT verfügbar — GitHub verwirft dann die
    // ganze Datei beim Einlesen, ohne roten Check (PilzBuddy, 2026-08-13).
    final offenders = <String>[];
    for (final file in workflows) {
      var line = 0;
      for (final raw in file.readAsLinesSync()) {
        line++;
        final code = raw.split('#').first;
        if (RegExp(r'\bif:').hasMatch(code) && code.contains('secrets.')) {
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('Secrets gehen über env: in die Shell, nie interpoliert', () {
    // `${{ secrets.X }}` direkt in einem run:-Block landet im Klartext im
    // Skript; über env: bleibt es eine Umgebungsvariable.
    for (final file in workflows) {
      var inRun = false;
      var line = 0;
      for (final raw in file.readAsLinesSync()) {
        line++;
        if (RegExp(r'^\s*run:').hasMatch(raw)) inRun = true;
        if (RegExp(r'^\s*-\s*(name|uses|id):|^\s*(env|with|if):').hasMatch(raw)) {
          inRun = false;
        }
        if (inRun && raw.contains(r'${{ secrets.')) {
          fail('${file.path}:$line interpoliert ein Secret im run:-Block');
        }
      }
    }
  });

  test('Release baut beide Flavors, und die Pfade tragen den Namen', () {
    expect(release, contains('--flavor github'));
    expect(release, contains('app-github-release.apk'));
    expect(release, contains('--flavor play'));
    expect(release, contains('playRelease/app-play-release.aab'));
    expect(release, contains('-Pdisable-abi-filtering=true'));
    expect(ci, contains('--flavor play'));
  });

  test('der Dry Run fährt beide Wege und den Abgleich', () {
    expect(ci, contains('tool/patch_guard.sh'));
    expect(ci, contains('tool/db_migrate.sh'));
    expect(ci, contains('tool/schema_check.sh'));
    expect(ci, contains('tool/matcher_check.sql'));
    expect(ci, contains('supabase db reset'));
    // Portblock 5452x (supabase/config.toml) — Drift zwischen Workflow und
    // Konfiguration wäre ein Dry Run gegen eine fremde Datenbank.
    final config = File('supabase/config.toml').readAsStringSync();
    expect(config, contains('port = 54521'));
    expect(config, contains('port = 54522'));
    expect(ci, contains('127.0.0.1:54522'));
    expect(ci, contains('http://127.0.0.1:54521'));
  });

  test('Version Guard nimmt genau die Nicht-Binary-Pfade aus', () {
    for (final ex in [":!*.md'", ":!.github'", ":!tool'", ":!supabase'", ":!docs'"]) {
      expect(ci, contains(ex));
    }
    expect(ci, contains('-- CHANGELOG.md'),
        reason: 'CHANGELOG.md liegt im Binary und braucht den Bump');
  });

  test('die Live-Datenbank wird erst nach dem Dry Run angefasst', () {
    final job = ci.substring(
        ci.indexOf('  schema-check:'), ci.indexOf('  housekeeping:'));
    expect(job, contains('needs: schema-dry-run'));
    expect(job, contains('SUPABASE_DB_URL: \${{ secrets.SUPABASE_DB_URL }}'));
    expect(job, contains('bash tool/db_migrate.sh'));
    expect(job, contains('bash tool/schema_check.sh'));
    // Ohne Historie hält db_migrate.sh jeden secretlosen Lauf für rot.
    expect(job, contains('fetch-depth: 0'));
  });

  test('Release migriert und prüft VOR dem Bauen', () {
    final build = release.substring(release.indexOf('  build-android:'));
    expect(build, contains('needs: [version, migrate]'));
    final migrate = release.substring(
        release.indexOf('  migrate:'), release.indexOf('  build-android:'));
    expect(migrate, contains('bash tool/db_migrate.sh'));
    expect(migrate, contains('bash tool/schema_check.sh'));
  });

  test('der Frisch-Weg im Dry Run ist der Bootstrap des Live-Projekts', () {
    // Ein leeres Projekt bekommt schema.sql über db_migrate.sh — derselbe
    // Zweig muss im Dry Run laufen, sonst fährt die Produktion etwas, das
    // CI nie gesehen hat.
    final fresh = ci.substring(ci.indexOf('supabase db reset'));
    expect(fresh.indexOf('bash tool/db_migrate.sh'), greaterThan(-1));
    expect(fresh, isNot(contains('-f supabase/schema.sql')));
    expect(File('tool/db_migrate.sh').readAsStringSync(),
        contains('-f supabase/schema.sql'));
  });

  test('das Live-Projekt wird wach gehalten', () {
    // Free-Plan pausiert nach ~1 Woche ohne Zugriff.
    final keep = File('.github/workflows/keepalive.yml').readAsStringSync();
    final cron = RegExp(r'cron: "[^"]*\* \* ([0-9,]+)"').firstMatch(keep);
    expect(cron, isNotNull);
    final days = cron!.group(1)!.split(',').map(int.parse).toList()..sort();
    // Größte Lücke zwischen zwei Läufen, über das Wochenende hinweg.
    var gap = days.first + 7 - days.last;
    for (var i = 1; i < days.length; i++) {
      gap = gap > days[i] - days[i - 1] ? gap : days[i] - days[i - 1];
    }
    expect(gap, lessThan(7));
    expect(keep, contains('bash tool/schema_check.sh'));
  });

  test('der Dry Run gibt Tabellen nicht automatisch frei', () {
    // Mit `true` ersetzte die Vorgabe einen vergessenen Grant still.
    final config = File('supabase/config.toml').readAsStringSync();
    expect(config, contains('auto_expose_new_tables = false'));
  });

  test('Workflows mit Pflicht-Checks starten auf JEDEM PR', () {
    // Ein Pflicht-Check hinter einem Pfadfilter meldet sich auf einem PR,
    // der die Pfade nicht berührt, nie — der PR bleibt „blocked", obwohl
    // alles grün ist (so passiert mit Workflow Lint an PR #6).
    for (final name in ['ci.yml', 'security.yml', 'workflow-lint.yml']) {
      final text = File('.github/workflows/$name').readAsStringSync();
      final code = text.split('\n').map((l) => l.split('#').first).join('\n');
      expect(RegExp(r'^\s*(paths|paths-ignore):', multiLine: true).hasMatch(code), isFalse,
          reason: '$name trägt einen Pfadfilter');
    }
  });

  test('der Feedback-Bot läuft nur mit Schlüssel und sagt es sonst', () {
    final bot = File('.github/workflows/feedback.yml').readAsStringSync();
    expect(bot, contains('id: key'));
    expect(bot, contains("if: steps.key.outputs.have == 'true'"));
    expect(bot, contains('python3 tool/feedback_bot.py'));
    // Nur was er braucht: Issues schreiben, den Code lesen.
    expect(bot, contains('issues: write'));
    expect(bot, isNot(contains('contents: write')));
    expect(ci, contains('python3 tool/feedback_bot.py --self-test'));
    expect(ci, contains('tool/grants_check.sql'));
  });

  test('Push (#34): Dry Run ruft push_flush auf, Build Web prüft den Worker, Functions deployt ein eigener Workflow', () {
    // PL/pgSQL prüft den Rumpf erst beim Aufruf — ohne den Schritt legte
    // ein Fehler in push_flush live jede Minute alle Meldungen still.
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    expect(ci, contains('bash tool/push_flush_check.sh'));
    // Der Worker entscheidet, ob eine Meldung im Browser erscheint; FCM
    // quittiert auch dann „ok", wenn danach nichts passiert.
    expect(ci, contains('node tool/check_push_worker.mjs'));
    // Edge Functions spielt der Schema Check NICHT ein; ohne eigenen
    // Workflow läge `send-push` nur im Repo (PilzBuddy #277).
    final deploy = File('.github/workflows/deploy-functions.yml').readAsStringSync();
    expect(deploy, contains('supabase/functions/**'));
    expect(deploy, contains('supabase functions deploy --project-ref'));
    expect(deploy, contains("if: steps.token.outputs.have == 'true'"),
        reason: 'ohne SUPABASE_ACCESS_TOKEN sichtbar überspringen, nie rot');
    // Derselbe Projekt-Ref wie in der App — sonst deployt CI in ein
    // Projekt, das die App nie fragt.
    final config = File('lib/core/supabase_config.dart').readAsStringSync();
    final ref = RegExp(r'https://([a-z]+)\.supabase\.co').firstMatch(config)!.group(1)!;
    expect(deploy, contains('--project-ref $ref'));
    // Die Function braucht `verify_jwt = false` — der Cron-Job hat kein JWT.
    final toml = File('supabase/config.toml').readAsStringSync();
    expect(toml, contains('[functions.send-push]\nverify_jwt = false'));
    expect(File('supabase/functions/send-push/index.ts').existsSync(), isTrue);
  });

  test('CI prüft die erzeugten Assets als eigenen Schritt', () {
    // Kartenstil und Übersichtskarte sind ERZEUGT; eine Handänderung
    // bestünde jeden anderen Check und wäre beim nächsten Erzeugen weg
    // (PilzBuddy #226). Der Schritt steht getrennt von den Selbsttests,
    // damit im Log sofort das Asset und der Weg zum Neu-Erzeugen stehen.
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    expect(ci, contains('python3 tool/generated_assets.py --check'));
    final manifest = File('tool/generated_assets.json').readAsStringSync();
    expect(manifest, contains('assets/map_style/protomaps_light_de.json'));
    expect(manifest, contains('assets/offline_maps/overview_dach.pmtiles'));
  });

  test('der Kartenhost in CI und in der App ist derselbe, und CI prüft den Rundlauf', () {
    // Die App liest `kMapTilesBase`, der Workflow lädt nach `PUBLIC_BASE`.
    // Laufen die beiden auseinander, lädt CI ein Archiv, das die App
    // nie findet — und beide Seiten wären für sich grün.
    final mapData = File('.github/workflows/map-data.yml').readAsStringSync();
    final providers = File('lib/features/map/map_providers.dart').readAsStringSync();
    final host = RegExp(r"kMapTilesBase = '([^']+)'").firstMatch(providers)!.group(1)!;
    expect(mapData, contains('PUBLIC_BASE: $host'));
    expect(mapData, contains("R2_PREFIX: ${host.split('/').last}"));
    // Zoom 13 ist die Entscheidung des Betreibers (2026-09-28).
    expect(mapData, contains("MAXZOOM: \${{ inputs.maxzoom || '13' }}"));
    // Nach dem Upload liest CI die ÖFFENTLICHE Kopie wie die App: 206,
    // accept-ranges, CORS, und Kacheln gegen die Quelle.
    expect(mapData, contains("grep -q '^http/[0-9.]* 206'"));
    expect(mapData, contains('accept-ranges: bytes'));
    expect(mapData, contains('access-control-allow-origin'));
    expect(mapData, contains('map_tiles.py check --source "\$SOURCE" \\\n            --extract "\$url"'));
    // Die Secrets gehen über env: in einen Feststell-Schritt (kein
    // `secrets.` in `if:`, das prüft der Test oben).
    expect(mapData, contains("steps.r2.outputs.present == 'true'"));
    // Das Manifest ist der Zeiger, die Archive tragen das Datum.
    expect(mapData, contains('dach-\${SOURCE_BUILD}.pmtiles'));
    // EU-Jurisdiktion: der Bucket liegt nur hinter dem EU-Endpunkt.
    expect(mapData, contains('.eu.r2.cloudflarestorage.com'));
    expect(mapData, contains('max-age=300'));
  });

  test('Orte, Onlinekarte und Übersicht decken DENSELBEN Bereich (#73)', () {
    // Vorher Orte nur für DACH + Liechtenstein, die Karte reichte bis
    // Südtirol, Elsass und Tschechien — dort gab es Karte ohne Orte.
    String bboxOf(String text, String key) =>
        RegExp('$key: "([^"]+)"').firstMatch(text)!.group(1)!;
    final poi = bboxOf(File('.github/workflows/poi-data.yml').readAsStringSync(), 'POI_BBOX');
    final map = bboxOf(File('.github/workflows/map-data.yml').readAsStringSync(), 'DACH_BBOX');
    final heights = bboxOf(File('.github/workflows/height-data.yml').readAsStringSync(), 'DACH_BBOX');
    expect(heights, map, reason: 'ein Bereich hat Höhen, wo er Karte hat');
    final overview = RegExp(r'overview_dach\.pmtiles --bbox=([0-9.,]+)')
        .firstMatch(File('tool/generated_assets.json').readAsStringSync())!
        .group(1)!;
    expect(poi, map);
    expect(overview, map);
  });

  test('die Höhenkacheln kommen vom selben Host als EIN Archiv, geprüft wie die Karte', () {
    // height-data.yml (Konzept-Routing 2.6, Weg B): `heights.json` zeigt
    // auf `heights-<build>.pmtiles`; die App liest beides unter
    // `kMapTilesBase` (`kHeightsManifestUrl`, `HeightsManifest`). CI
    // prüft das Archiv mit dem offiziellen Werkzeug und liest die
    // öffentliche Kopie per Range zurück, Kacheln gegen das DEM.
    final data = File('.github/workflows/height-data.yml').readAsStringSync();
    final providers = File('lib/features/map/map_providers.dart').readAsStringSync();
    final host = RegExp(r"kMapTilesBase = '([^']+)'").firstMatch(providers)!.group(1)!;
    expect(providers, contains("kHeightsManifestUrl = '\$kMapTilesBase/heights.json'"));
    expect(data, contains('PUBLIC_BASE: $host'));
    expect(data, contains("R2_PREFIX: ${host.split('/').last}"));
    expect(data, contains("steps.r2.outputs.present == 'true'"));
    expect(data, contains('.eu.r2.cloudflarestorage.com'));
    expect(data, contains('heights-\${BUILD}.pmtiles'));
    expect(data, contains('max-age=31536000, immutable'));
    expect(data, contains('max-age=300'));
    expect(data, contains("grep -q '^http/[0-9.]* 206'"));
    expect(data, contains('accept-ranges: bytes'));
    expect(data, contains('access-control-allow-origin'));
    expect(data, contains('pmtiles verify'));
    expect(data, contains('tool/height_tiles.py build --bbox "\$DACH_BBOX"'));
    expect(data, contains('tool/height_tiles.py check --source "\$url"'));
    // Der Self-Test läuft WITH numpy vor dem Bau und ohne in ci.yml.
    expect(data, contains('pip install --quiet "numpy'));
    expect(data, contains('tool/height_tiles.py --self-test'));
    expect(File('.github/workflows/ci.yml').readAsStringSync(), contains('tool/height_tiles.py --self-test'));
    // Format und Raster stehen in Dart und im Werkzeug gleich.
    final tool = File('tool/height_tiles.py').readAsStringSync();
    final dart = File('lib/features/offline_areas/height_tiles.dart').readAsStringSync();
    for (final (py, dt) in [('FORMAT', 'kHeightsFormat'), ('GRID', 'kHeightGrid'), ('ZOOM', 'kHeightTileZoom'), ('NODATA', 'kHeightNoData')]) {
      final a = RegExp('^$py = (-?\\d+)', multiLine: true).firstMatch(tool)!.group(1);
      final b = RegExp('const $dt = (-?\\d+);').firstMatch(dart)!.group(1);
      expect(b, a, reason: '$dt gegen $py');
    }
  });

  test('das Wege-Archiv (#212) kommt vom selben Host, im Format, das die App liest', () {
    // way-data.yml schreibt `ways.json` + `ways-<build>.pmtiles`; die App
    // liest beides unter `kMapTilesBase` (`kWaysManifestUrl`,
    // `WaysManifest`) und zeichnet Kacheln mit genau diesem Format.
    final data = File('.github/workflows/way-data.yml').readAsStringSync();
    final providers = File('lib/features/map/map_providers.dart').readAsStringSync();
    final host = RegExp(r"kMapTilesBase = '([^']+)'").firstMatch(providers)!.group(1)!;
    expect(providers, contains("kWaysManifestUrl = '\$kMapTilesBase/ways.json'"));
    expect(data, contains('PUBLIC_BASE: $host'));
    final tool = File('tool/way_archive.py').readAsStringSync();
    final dart = File('lib/features/map/way_layer.dart').readAsStringSync();
    for (final (py, dt) in [('FORMAT', 'kWaysFormat'), ('ZOOM', 'kWaysZoom')]) {
      final a = RegExp('^$py = (\\d+)', multiLine: true).firstMatch(tool)!.group(1);
      final b = RegExp('const $dt = (\\d+);').firstMatch(dart)!.group(1);
      expect(b, a, reason: '$dt gegen $py');
    }
    for (final (py, dt) in [('LAYER', 'kWaysLayer'), ('KEY', 'kWaysKey')]) {
      final a = RegExp('^$py = "(\\w+)"', multiLine: true).firstMatch(tool)!.group(1);
      final b = RegExp("const $dt = '(\\w+)';").firstMatch(dart)!.group(1);
      expect(b, a, reason: '$dt gegen $py');
    }
  });

  test('die Orte kommen vom selben Host, je Zelle und Gruppe, und CI liest sie zurück', () {
    // poi-data.yml (Konzept 3.4, Weg 3): Manifest `pois.json` und
    // Dateien `pois-<build>/<zeile>_<spalte>.<gruppe>.json` neben dem
    // Archiv. Die App baut dieselben Namen (`poiCellFileName`,
    // `kPoiManifestUrl`); der Workflow prüft die öffentliche Kopie mit
    // Origin-Header und vergleicht je Gruppe eine Datei Byte für Byte.
    final poiData = File('.github/workflows/poi-data.yml').readAsStringSync();
    final providers = File('lib/features/map/map_providers.dart').readAsStringSync();
    final host = RegExp(r"kMapTilesBase = '([^']+)'").firstMatch(providers)!.group(1)!;
    expect(providers, contains("kPoiManifestUrl = '\$kMapTilesBase/pois.json'"));
    expect(poiData, contains('PUBLIC_BASE: $host'));
    expect(poiData, contains("R2_PREFIX: ${host.split('/').last}"));
    expect(poiData, contains("steps.r2.outputs.present == 'true'"));
    expect(poiData, contains('.eu.r2.cloudflarestorage.com'));
    expect(poiData, contains('pois-\${BUILD}/'));
    expect(poiData, contains('max-age=31536000, immutable'));
    expect(poiData, contains('max-age=300'));
    expect(poiData, contains('access-control-allow-origin'));
    expect(poiData, contains("cell.replace(',', '_')"));
    expect(poiData, contains('tool/poi_extract.py build'));
    // Die Arten kommen aus EINER Liste; das Werkzeug liest sie von dort.
    final tool = File('tool/poi_extract.py').readAsStringSync();
    expect(poiData, contains(r'--bbox "$POI_BBOX"'));
    expect(tool, contains('"pois", "kinds.json"'));
    expect(tool, contains('CELL_LAT = 0.1'));
    expect(tool, contains('CELL_LON = 0.15'));
  });

  test('jedes Werkzeug mit Selbsttest läuft in CI (sonst verrottet es still)', () {
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    final tools = Directory('tool')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.py'))
        .where((f) => f.readAsStringSync().contains("'--self-test'") ||
            f.readAsStringSync().contains('"--self-test"'));
    expect(tools, isNotEmpty);
    for (final f in tools) {
      final name = f.uri.pathSegments.last;
      expect(ci, contains('python3 tool/$name --self-test'), reason: name);
    }
  });
}
