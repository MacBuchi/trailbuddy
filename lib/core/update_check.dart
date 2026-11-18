import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../data/providers.dart';
import 'app_distribution.dart';
import 'app_info.dart';
import 'errors.dart';
import 'settings.dart';

/// Informationen über ein verfügbares Update von GitHub Releases.
class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String? releaseNotes;

  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    this.releaseNotes,
  });
}

/// `true`, wenn [latest] eine neuere Version als [current] ist
/// (numerischer Vergleich je Segment, z. B. 1.10.0 > 1.9.2).
///
/// Vorab wird alles ab `-` oder `+` abgeschnitten: `1.5.1-rc1` und
/// `1.5.1+42` sind für den Vergleich 1.5.1. Ohne das würde
/// `int.tryParse('1-rc1')` null liefern und die Version stillschweigend auf
/// 1.5.0 zurückfallen — ein Vorabversion-Suffix hätte den Vergleich also
/// verfälscht statt ihn nur zu ignorieren.
bool isNewerVersion(String latest, String current) {
  List<int> parse(String v) => v
      .trim()
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((part) => int.tryParse(part.trim()) ?? 0)
      .toList();
  final l = parse(latest);
  final c = parse(current);
  for (var i = 0; i < 3; i++) {
    final li = i < l.length ? l[i] : 0;
    final ci = i < c.length ? c[i] : 0;
    if (li != ci) return li > ci;
  }
  return false;
}

/// Läuft der Update-Weg auf diesem Gerät überhaupt?
///
/// Web ist immer aktuell, und im Play-Build übernimmt der Store das
/// Aktualisieren (Verweise auf APK-Downloads sind dort unzulässig).
bool get updateChecksApply =>
    AppDistribution.showsUpdateHints &&
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android;

/// Bekommt dieses Gerät Vorabversionen?
///
/// Der Riegel steht HIER und nicht nur in der Oberfläche: Wo der
/// Update-Weg gar nicht läuft, muss der Schalter aus sein, sonst ließe
/// er sich umlegen, ohne dass je etwas passieren kann.
class PrereleaseUpdatesNotifier extends Notifier<bool> {
  @override
  bool build() =>
      updateChecksApply && ref.read(settingsProvider).prereleaseUpdatesEnabled;

  /// Zustand springt sofort, Speichern läuft nach, ein Fehler beim Merken
  /// wird nur protokolliert.
  void set(bool value) {
    state = value;
    unawaited(
      ref.read(settingsProvider).setPrereleaseUpdatesEnabled(value).catchError((
        Object e,
        StackTrace stackTrace,
      ) {
        logError('Vorab-Kanal merken', e, stackTrace);
      }),
    );
  }
}

final prereleaseUpdatesProvider =
    NotifierProvider<PrereleaseUpdatesNotifier, bool>(
      PrereleaseUpdatesNotifier.new,
    );

/// Der erste VERÖFFENTLICHTE Eintrag einer Release-Liste — Prereleases
/// eingeschlossen, Entwürfe nicht.
///
/// GitHub liefert die Liste absteigend nach Erstellungszeit, genommen wird
/// also der jüngste Stand. Ein Entwurf ist keiner: Seine Dateien sind
/// nicht öffentlich abrufbar, der Download liefe ins Leere und der
/// Hinweis nennte eine Version, die es für niemanden gibt.
Map<String, dynamic>? firstPublishedRelease(List<dynamic> releases) {
  for (final entry in releases) {
    if (entry is! Map<String, dynamic>) continue;
    if (entry['draft'] == true) continue;
    return entry;
  }
  return null;
}

/// Ist das der APK-Anhang eines Releases?
///
/// Der Release-Workflow legt die APK als `trailbuddy-v<version>.apk` ab.
/// Geprüft wird das Muster und nicht nur die Endung: Liegt einmal eine
/// zweite APK am Release (ein anderer Flavor, ein Testbuild), darf der
/// Hinweis nicht die erstbeste nehmen.
bool isApkAsset(String name) =>
    name.startsWith('trailbuddy-v') && name.endsWith('.apk');

/// Fragt das neueste GitHub-Release ab und vergleicht mit der installierten
/// Version. Nur relevant für die per APK verteilte Android-App — Web ist
/// immer aktuell, und im Play-Build übernimmt der Store das Aktualisieren.
/// Liefert `null`, wenn kein Update verfügbar ist oder der Check fehlschlägt.
///
/// Der Kanal entscheidet ausschließlich über die ADRESSE:
/// `…/releases/latest` liefert grundsätzlich kein Prerelease, `…/releases`
/// die ganze Liste. Alles danach — Versionsvergleich, APK-Suche, „Was ist
/// neu" — ist für beide Kanäle dasselbe. Zwei Fassungen wären zwei
/// Antworten auf „ist das ein Update", und der Unterschied fiele erst dem
/// Tester auf.
final updateInfoProvider = FutureProvider<UpdateInfo?>((ref) async {
  if (!updateChecksApply) return null;
  final prerelease = ref.watch(prereleaseUpdatesProvider);
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final response = await http
        .get(
          Uri.parse(
            prerelease
                ? 'https://api.github.com/repos/MacBuchi/TrailBuddy/releases'
                      '?per_page=10'
                : 'https://api.github.com/repos/MacBuchi/TrailBuddy/releases/latest',
          ),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    final release = prerelease
        ? firstPublishedRelease(decoded as List<dynamic>)
        : decoded as Map<String, dynamic>;
    if (release == null) return null;
    final tag = (release['tag_name'] as String? ?? '');
    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    if (latest.isEmpty || !isNewerVersion(latest, packageInfo.version)) {
      return null;
    }

    final assets = release['assets'] as List<dynamic>? ?? const [];
    final apk = assets.cast<Map<String, dynamic>>().where(
      (a) => isApkAsset(a['name'] as String? ?? ''),
    );
    if (apk.isEmpty) return null;

    return UpdateInfo(
      latestVersion: latest,
      downloadUrl: apk.first['browser_download_url'] as String,
      releaseNotes: release['body'] as String?,
    );
  } catch (_) {
    return null; // Update-Check darf die App nie stören
  }
});

/// Kleinste Version, die noch zum Live-Schema passt (`public.app_config`)
/// — oder `null`, wenn sie sich nicht ermitteln lässt.
///
/// `null` heißt „unbekannt", nicht „0.0.0": ein fehlgeschlagener Abruf darf
/// nie zu einer Sperre führen.
final minimumSupportedVersionProvider = FutureProvider<String?>((ref) async {
  try {
    return await ref
        .watch(appConfigRepositoryProvider)
        .fetchMinimumSupportedVersion();
  } catch (_) {
    return null;
  }
});

/// Ist die installierte App zu alt für das Live-Schema?
///
/// Der Schema Check garantiert nur, dass die *aktuelle* App zu den Tabellen
/// passt. Ein älterer Client fragt nach einer Breaking-Migration Spalten ab,
/// die es nicht mehr gibt, und scheitert still — deshalb sperrt die App sich
/// hier selbst (Lehre aus PilzBuddy #80).
///
/// Sperrt ausschließlich bei einer eindeutigen Antwort: fehlt die
/// Mindestversion oder die eigene Version, läuft die App normal weiter. Die
/// App wird auf dem Trail ohne Empfang benutzt; jemanden dort auszusperren,
/// weil eine Abfrage nicht durchkam, wäre schlimmer als ein veralteter
/// Client. Das Ergebnis wird bewusst nicht persistiert — beim nächsten
/// Start wird wieder frisch gefragt.
final updateRequiredProvider = FutureProvider<bool>((ref) async {
  final minimum = await ref.watch(minimumSupportedVersionProvider.future);
  if (minimum == null || minimum.isEmpty) return false;
  final current = await ref.watch(appVersionProvider.future);
  if (current == AppInfo.unknownVersion) return false;
  return isNewerVersion(minimum, current);
});
