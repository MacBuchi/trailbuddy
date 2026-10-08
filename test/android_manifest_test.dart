/// Die Android-Seite hat kein Test-Netz — außer diesem. Hält
/// applicationId, Kotlin-Pfad, Flavors, Berechtigungen und
/// Backup-Ausschlüsse zusammen (PilzBuddy-Muster, gekürzt).
library;

import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';

void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final play = File('android/app/src/play/AndroidManifest.xml').readAsStringSync();
  final appId = RegExp(r'applicationId = "([a-z.]+)"').firstMatch(gradle)!.group(1)!;

  test('applicationId ist die eine Quelle', () {
    expect(appId, 'de.mcbuchi.trailbuddy');
    expect(gradle, contains('namespace = "$appId"'));
    expect(File('android/app/src/main/kotlin/${appId.replaceAll('.', '/')}/MainActivity.kt').existsSync(),
        isTrue, reason: 'Kotlin-Verzeichnis passt nicht zur applicationId');
  });

  test('der Install-Kanal heißt in Kotlin und Dart gleich', () {
    // Ein Tippfehler auf einer Seite antwortet stumm mit „kein Kanal",
    // und Dart fällt dann für immer auf den Browser zurück.
    final kotlin = File('android/app/src/main/kotlin/${appId.replaceAll('.', '/')}/MainActivity.kt').readAsStringSync();
    final dart = File('lib/data/apk_installer.dart').readAsStringSync();
    const channel = 'de.mcbuchi.trailbuddy/apk_install';
    expect(kotlin, contains('"$channel"'));
    expect(dart, contains("'$channel'"));
    expect(manifest, contains('androidx.core.content.FileProvider'));
    expect(kotlin, contains('FileProvider.getUriForFile'));
  });

  test('der Bildschirm-Kanal heißt in Kotlin und Dart gleich (#232)', () {
    final kotlin = File('android/app/src/main/kotlin/${appId.replaceAll('.', '/')}/MainActivity.kt').readAsStringSync();
    final dart = File('lib/core/screen_awake_io.dart').readAsStringSync();
    const channel = 'de.mcbuchi.trailbuddy/screen';
    expect(kotlin, contains('"$channel"'));
    expect(dart, contains("'$channel'"));
    // Das Fenster-Flag: gilt nur, solange die App sichtbar ist.
    expect(kotlin, contains('FLAG_KEEP_SCREEN_ON'));
  });

  test('Bild-im-Bild: Kanal in Kotlin und Dart gleich, Activity darf ins Fenster (#232)', () {
    final kotlin = File('android/app/src/main/kotlin/${appId.replaceAll('.', '/')}/MainActivity.kt').readAsStringSync();
    final dart = File('lib/core/picture_in_picture_io.dart').readAsStringSync();
    const channel = 'de.mcbuchi.trailbuddy/pip';
    expect(kotlin, contains('"$channel"'));
    expect(dart, contains("'$channel'"));
    // Ohne das Attribut wirft `enterPictureInPictureMode`; ohne die
    // configChanges startete die Activity beim Schrumpfen neu.
    final activity = RegExp(r'<activity[^>]*android:name="\.MainActivity"[^>]*>').firstMatch(manifest)!.group(0)!;
    expect(activity, contains('android:supportsPictureInPicture="true"'));
    final changes = RegExp(r'android:configChanges="([^"]+)"').firstMatch(activity)!.group(1)!.split('|');
    expect(changes, containsAll(['screenSize', 'smallestScreenSize', 'screenLayout', 'orientation']));
    // Hinein von selbst ab Android 12, darunter beim Verlassen; der Knopf
    // im Fenster geht nur an uns selbst. Kein Overlay-Recht (9.6).
    expect(kotlin, contains('setAutoEnterEnabled'));
    expect(kotlin, contains('override fun onUserLeaveHint'));
    expect(kotlin, contains('RECEIVER_NOT_EXPORTED'));
    expect(manifest, isNot(contains('android.permission.SYSTEM_ALERT_WINDOW')));
  });

  test('Zurück auf der Karte legt die App in den Hintergrund, statt sie zu beenden', () {
    // #175: Flutter ruft ohne Überschreibung `finish()` — die Karte
    // startete danach von vorn. Der Weg dorthin ist Dart (AppShell); hier
    // steht nur, dass am Ende `moveTaskToBack` steht und nicht `finish`.
    final kotlin = File('android/app/src/main/kotlin/${appId.replaceAll('.', '/')}/MainActivity.kt').readAsStringSync();
    final body = RegExp(r'override fun popSystemNavigator\(\): Boolean \{([^}]*)\}').firstMatch(kotlin);
    expect(body, isNotNull, reason: 'popSystemNavigator ist nicht überschrieben');
    expect(body!.group(1), contains('moveTaskToBack(true)'));
    expect(body.group(1), contains('return true'));
    expect(body.group(1), isNot(contains('finish')));
  });

  test('der Beendigungs-Kanal heißt in Kotlin und Dart gleich, das Tombstone liest Dart', () {
    // #40: Ein Tippfehler auf einer Seite hieße „keine Historie" — ohne
    // Fehlermeldung, für immer. Und das Tombstone (Protobuf) gehört auf
    // die Dart-Seite, die einen Test hat; Kotlin reicht es nur durch.
    final kotlin = File('android/app/src/main/kotlin/${appId.replaceAll('.', '/')}/MainActivity.kt').readAsStringSync();
    final dart = File('lib/data/exit_info_repository.dart').readAsStringSync();
    final channel = RegExp(r"kExitInfoChannel = '([\w./]+)'").firstMatch(dart)!.group(1)!;
    expect(channel, startsWith('$appId/'));
    expect(kotlin, contains('"$channel"'));
    expect(kotlin, contains('getHistoricalProcessExitReasons'));
    expect(kotlin, isNot(contains('Tombstone.parseFrom')));
    expect(kotlin, isNot(contains('import com.google.protobuf')));
  });

  test('zwei Flavors, eine App: play nimmt den Update-Weg heraus', () {
    expect(gradle, contains('create("github")'));
    expect(gradle, contains('create("play")'));
    final code = gradle.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    expect(code, isNot(contains('applicationIdSuffix')));
    expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(play, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(play, contains('tools:node="remove"'));
    // Zwei Bindestriche in einem XML-Kommentar brechen den ManifestMerger.
    expect(play, isNot(contains('--dart-define')));
  });

  test('genau die Berechtigungen, die es bis Phase 2 braucht', () {
    // Standort im Vordergrund für den Punkt, im Foreground-Service für
    // die Fahrt (#28) — nie als Hintergrund-Berechtigung.
    final perms = RegExp(r'android:name="android\.permission\.([A-Z_]+)"')
        .allMatches(manifest)
        .map((m) => m.group(1))
        .toSet();
    expect(perms, {
      'INTERNET',
      'REQUEST_INSTALL_PACKAGES',
      'ACCESS_FINE_LOCATION',
      'ACCESS_COARSE_LOCATION',
      'FOREGROUND_SERVICE',
      'FOREGROUND_SERVICE_LOCATION',
      'FOREGROUND_SERVICE_DATA_SYNC',
      'POST_NOTIFICATIONS',
      'VIBRATE',
      'RECEIVE_BOOT_COMPLETED',
    });
    expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION"')));
    expect(
        RegExp(r'RECEIVE_BOOT_COMPLETED"\s+tools:node="remove"').hasMatch(manifest), isTrue,
        reason: 'das Plugin bringt sie mit, wir starten nie beim Booten');
  });

  test('Fahrt und Bereichs-Download teilen EINEN Foreground-Service, Typen dataSync|location', () {
    expect(manifest, contains('com.pravera.flutter_foreground_task.service.ForegroundService'));
    // Die Obermenge dessen, was vorkommen KANN; welche Typen ein Lauf
    // nennt, entscheidet der Koordinator je Start (PilzBuddy #338).
    final type = RegExp(r'android:foregroundServiceType="([a-zA-Z|]+)"').firstMatch(manifest)!.group(1)!;
    expect(type.split('|').toSet(), {'dataSync', 'location'});
    // Der Meta-Data-Name des Symbols steht in Dart und im Manifest; das
    // Plugin liefert bei einem Tippfehler stumm die Ressourcen-id 0.
    final dart = File('lib/features/keep_alive/keep_alive_service.dart').readAsStringSync();
    final name = RegExp(r"keepAliveNotificationIconMetaData = '([\w.]+)'").firstMatch(dart)!.group(1)!;
    expect(name, startsWith('$appId.'));
    expect(manifest, contains('android:name="$name"'));
    expect(manifest, contains('android:resource="@drawable/ic_notification"'));
    final icon = File('android/app/src/main/res/drawable/ic_notification.xml').readAsStringSync();
    // Nur der Alphakanal zählt: jede Fläche weiß, keine zweite Farbe.
    final colors = RegExp(r'android:(?:fill|stroke)Color="(#[0-9A-Fa-f]+)"').allMatches(icon).map((m) => m.group(1)).toSet();
    expect(colors, {'#FFFFFFFF'});
  });

  test('der Push-Kanal ist deklariert, angelegt und laut (#34)', () {
    // Drei Stellen müssen zusammenpassen, und keine fällt beim Editieren
    // auf: Ohne Manifest-Zeile legt FCM still einen eigenen, leisen
    // Kanal an (nur ein Symbol in der Statusleiste, kein Banner —
    // PilzBuddy #277); ohne `createNotificationChannel` zeigt das
    // Manifest auf nichts; unterhalb von IMPORTANCE_HIGH gibt es kein
    // Banner — und die Stufe lässt sich später NICHT mehr ändern.
    const idName = 'notification_channel_id';
    final declared = RegExp(
            r'android:name="com\.google\.firebase\.messaging\.default_notification_channel_id"\s+android:value="([^"]+)"')
        .allMatches(manifest)
        .map((m) => m.group(1))
        .toList();
    expect(declared, ['@string/$idName'],
        reason: 'Manifest nennt den Kanal nicht (oder mehrfach)');
    final strings = File('android/app/src/main/res/values/strings.xml').readAsStringSync();
    expect(strings, contains('name="$idName"'));
    final kotlin = File('android/app/src/main/kotlin/${appId.replaceAll('.', '/')}/MainActivity.kt').readAsStringSync();
    expect(kotlin, contains('createNotificationChannel'));
    expect(kotlin, contains('R.string.$idName'));
    expect(kotlin, contains('NotificationManager.IMPORTANCE_HIGH'));
    // Symbol und Tönung: Ohne die Symbol-Zeile nähme FCM das
    // Launcher-Icon — als Silhouette ein weißer Klotz (PilzBuddy #331).
    expect(
        RegExp(r'android:name="com\.google\.firebase\.messaging\.default_notification_icon"\s+android:resource="@drawable/ic_notification"')
            .hasMatch(manifest),
        isTrue);
    expect(
        RegExp(r'android:name="com\.google\.firebase\.messaging\.default_notification_color"\s+android:resource="@color/notification_color"')
            .hasMatch(manifest),
        isTrue);
    expect(File('android/app/src/main/res/values/colors.xml').readAsStringSync(),
        contains('name="notification_color"'));
  });

  test('die Frage während der Fahrt nimmt den lauten Kanal und hat ihren Empfänger (#116)', () {
    // Der Kanal der Frage ist der der Meldungen — derselbe Name in Dart
    // und strings.xml, sonst legte das Paket still einen zweiten an.
    final dart = File('lib/features/rides/ride_confirm_notify.dart').readAsStringSync();
    final id = RegExp(r"kConfirmChannelId = '([\w]+)'").firstMatch(dart)!.group(1)!;
    final name = RegExp(r"kConfirmChannelName = '([^']+)'").firstMatch(dart)!.group(1)!;
    final strings = File('android/app/src/main/res/values/strings.xml').readAsStringSync();
    expect(strings, contains('name="notification_channel_id" translatable="false">$id<'));
    expect(strings, contains('name="notification_channel_name">$name<'));
    // Ohne Empfänger tut ein Knopf nichts, ohne Fehlermeldung.
    expect(
        RegExp(r'android:exported="false"\s+android:name="com\.dexterous\.flutterlocalnotifications\.ActionBroadcastReceiver"')
            .hasMatch(manifest),
        isTrue);
    // Das Symbol ist dasselbe Alpha-Drawable wie bei Push und Fahrt.
    expect(dart, contains("kConfirmNotificationIcon = 'ic_notification'"));
    // Das Paket verlangt Desugaring; ohne bricht der Build ab.
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
    expect(gradle, contains('coreLibraryDesugaring("com.android.tools:desugar_jdk_libs'));
  });

  test('das Startfenster trägt den Grund der App, hell und dunkel', () {
    String ground(String dir) => RegExp(r'name="ground">#([0-9A-F]{6})<')
        .firstMatch(File('android/app/src/main/res/$dir/colors.xml').readAsStringSync())!
        .group(1)!;
    String hex(Color c) => c.toARGB32().toRadixString(16).toUpperCase().substring(2);
    expect(ground('values'), hex(AppColors.light.ground));
    expect(ground('values-night'), hex(AppColors.dark.ground));
    for (final d in ['drawable', 'drawable-v21']) {
      expect(File('android/app/src/main/res/$d/launch_background.xml').readAsStringSync(),
          contains('@color/ground'), reason: d);
    }
    for (final d in ['values', 'values-night', 'values-v31', 'values-night-v31']) {
      final styles = File('android/app/src/main/res/$d/styles.xml').readAsStringSync();
      expect(styles, isNot(contains('colorBackground')), reason: d);
      expect(styles, contains('@color/ground'), reason: d);
    }
    for (final d in ['values-v31', 'values-night-v31']) {
      expect(File('android/app/src/main/res/$d/styles.xml').readAsStringSync(),
          contains('windowSplashScreenBackground">@color/ground'), reason: d);
    }
  });

  test('der App-Wähler für die Anfahrt sieht geo:-Empfänger (#151)', () {
    // Ohne den <queries>-Eintrag sieht die App ab Android 11 keinen
    // Empfänger für geo:, der Wähler bleibt aus, und der Knopf fällt
    // still auf die Zwischenablage zurück — ein Fehler, der wie eine
    // Entscheidung aussieht. Das Schema steht in Dart und im Manifest.
    final dart = File('lib/features/trails/trail_navigation.dart').readAsStringSync();
    final scheme = RegExp(r"kGeoScheme = '(\w+)'").firstMatch(dart)!.group(1)!;
    final queries = RegExp(r'<queries>([\s\S]*?)</queries>').firstMatch(manifest)!.group(1)!;
    expect(queries, contains('android:scheme="$scheme"'));
    expect(queries, contains('android.intent.action.VIEW'));
  });

  test('google-services nur mit Datei — und die Datei kennt den Paketnamen', () {
    // Das Plugin bricht den Build ab, wenn google-services.json fehlt; bis
    // der Betreiber das Firebase-Projekt anlegt, baut die App ohne. Liegt
    // die Datei da, muss sie DIESES Paket kennen, sonst scheitert Gradle.
    expect(File('android/settings.gradle.kts').readAsStringSync(),
        contains('id("com.google.gms.google-services")'));
    final code = gradle.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    expect(code, contains('if (file("google-services.json").exists())'));
    expect(code, contains('apply(plugin = "com.google.gms.google-services")'));
    final json = File('android/app/google-services.json');
    if (json.existsSync()) {
      expect(json.readAsStringSync(), contains('"package_name": "$appId"'),
          reason: 'google-services.json kennt $appId nicht — neu aus der Firebase-Konsole holen');
    }
  });

  test('beide Backup-Regeln schließen dasselbe aus', () {
    Set<String> excludes(String path) => RegExp(r'<exclude domain="(\w+)" path="([^"]+)"')
        .allMatches(File(path).readAsStringSync())
        .map((m) => '${m.group(1)}:${m.group(2)}')
        .toSet();
    final rules = excludes('android/app/src/main/res/xml/backup_rules.xml');
    final legacy = excludes('android/app/src/main/res/xml/full_backup_content.xml');
    expect(rules, legacy);
    expect(rules, containsAll(['sharedpref:FlutterSharedPreferences.xml',
        'file:rides', 'file:trail_cache', 'file:outbox', 'file:updates',
        'file:official_trails']));
    expect(manifest, contains('@xml/backup_rules'));
    expect(manifest, contains('@xml/full_backup_content'));
  });
}
