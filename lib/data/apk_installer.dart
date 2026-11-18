import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Übergibt eine geladene APK an Androids System-Installer
/// (`MainActivity.kt`, Kanal `apk_install`).
///
/// Installiert wird nie still: Das System zeigt seinen eigenen Dialog. Die
/// App darf nur *anbieten* — deshalb genügt `REQUEST_INSTALL_PACKAGES` und
/// es braucht kein `INSTALL_PACKAGES` (Signatur-Berechtigung, PilzBuddy #88).
class ApkInstaller {
  const ApkInstaller({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('de.mcbuchi.trailbuddy/apk_install');

  final MethodChannel _channel;

  /// Nur die per APK verteilte Android-App aktualisiert sich selbst.
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Hat die Nutzerin dieser App erlaubt, Apps zu installieren?
  ///
  /// Ab Android 8 eine Freigabe pro App. Fehlt sie, führt [openSettings]
  /// direkt dorthin — der Systemdialog beim Installieren würde sonst nur
  /// „blockiert" sagen.
  Future<bool> canInstall() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      // Fehlender Kanal (alter Build) heißt: kein In-App-Installieren.
      // Der Aufrufer fällt auf den Browser zurück.
      return false;
    }
  }

  Future<void> openSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {
      // Ohne Einstellungsseite bleibt der Browser-Weg — kein Grund,
      // den Nutzer mit einem Fehler zu behelligen.
    }
  }

  /// Öffnet den System-Installer für [path]. `false`, wenn das nicht ging.
  Future<bool> install(String path) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('install', {'path': path}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

final apkInstallerProvider = Provider<ApkInstaller>(
  (ref) => const ApkInstaller(),
);
