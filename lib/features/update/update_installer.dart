import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/update_check.dart';
import '../../data/apk_installer.dart';

/// Warum ein Update nicht in der App installiert werden konnte.
///
/// Kein `Exception`-Typ, sondern ein Ergebnis: Jeder dieser Fälle ist
/// vorgesehen und endet im Browser-Download, nicht in einer Fehlermeldung.
enum UpdateFailure {
  /// Freigabe „Unbekannte Apps installieren" fehlt (ab Android 8).
  notAllowed,

  /// Download abgebrochen — kein Netz, Abbruch, HTTP-Fehler.
  downloadFailed,

  /// Der System-Installer ließ sich nicht öffnen.
  installFailed,
}

/// Lädt die Update-APK und übergibt sie dem System-Installer.
///
/// Warum wieder in der App (PilzBuddy #88 hatte es entfernt, #161 baute es neu): Der Browser-Weg
/// verlangt die Freigabe „Unbekannte Apps installieren" für den *Browser*
/// und lässt die Nutzerin die Datei danach selbst finden. Hier hängt die
/// Freigabe an TrailBuddy — einmal erteilt, ist jedes weitere Update ein Tipp.
///
/// Was NICHT zurückkommt, ist `ota_update`: Dessen Manifest zog
/// `INSTALL_PACKAGES`, `READ/WRITE_EXTERNAL_STORAGE` und
/// `RECEIVE_BOOT_COMPLETED` in jeden Build. Der eigene Weg braucht eine
/// einzige Berechtigung.
class UpdateInstaller {
  UpdateInstaller({
    required ApkInstaller installer,
    http.Client? client,
    Future<Directory> Function()? directory,
  }) : _installer = installer,
       _client = client ?? http.Client(),
       _directory = directory ?? getApplicationSupportDirectory;

  final ApkInstaller _installer;
  final http.Client _client;
  final Future<Directory> Function() _directory;

  /// Steht dieser Weg auf diesem Gerät überhaupt zur Verfügung?
  bool get supported => _installer.supported;

  static const _inactivityTimeout = Duration(seconds: 60);

  Future<Directory> _updatesDir() async {
    final dir = Directory('${(await _directory()).path}/updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Lädt die APK und öffnet den System-Installer.
  ///
  /// Liefert `null` bei Erfolg, sonst den Grund — der Aufrufer schickt dann
  /// in den Browser. [onProgress] bekommt 0…1, solange die Größe bekannt
  /// ist; sonst gar nichts (die Anzeige läuft dann unbestimmt).
  Future<UpdateFailure?> downloadAndInstall(
    UpdateInfo info, {
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!await _installer.canInstall()) return UpdateFailure.notAllowed;

    final File apk;
    try {
      apk = await _download(info, onProgress, isCancelled ?? () => false);
    } catch (_) {
      return UpdateFailure.downloadFailed;
    }

    return await _installer.install(apk.path)
        ? null
        : UpdateFailure.installFailed;
  }

  Future<File> _download(
    UpdateInfo info,
    void Function(double)? onProgress,
    bool Function() isCancelled,
  ) async {
    final dir = await _updatesDir();
    // Alte Downloads wegräumen, bevor der nächste beginnt: Eine APK wiegt
    // ~60 MB, und nach der Installation braucht sie niemand mehr. Ein
    // abgebrochener Rest bliebe sonst für immer liegen.
    await _clear(dir);

    final target = File('${dir.path}/trailbuddy-${info.latestVersion}.apk');
    final request = http.Request('GET', Uri.parse(info.downloadUrl));
    final response = await _client.send(request).timeout(_inactivityTimeout);
    if (response.statusCode != 200) {
      throw HttpException('Update-Download: HTTP ${response.statusCode}');
    }

    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = target.openWrite();
    try {
      await for (final chunk in response.stream.timeout(_inactivityTimeout)) {
        if (isCancelled()) throw const _Cancelled();
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // Eine abgeschnittene Datei würde der Installer mit „App nicht
    // installiert" quittieren — ohne zu sagen, warum.
    if (total > 0 && received < total) {
      await target.delete();
      throw const HttpException('Update-Download unvollständig');
    }
    return target;
  }

  Future<void> _clear(Directory dir) async {
    try {
      await for (final entry in dir.list()) {
        if (entry is File) await entry.delete();
      }
    } catch (_) {
      // Aufräumen ist Kür: Scheitert es, überschreibt der Download die
      // gleichnamige Datei ohnehin.
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

final updateInstallerProvider = Provider<UpdateInstaller>(
  (ref) => UpdateInstaller(installer: ref.watch(apkInstallerProvider)),
);
