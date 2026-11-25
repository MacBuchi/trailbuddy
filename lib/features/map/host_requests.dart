/// Anfragen an den Kartenhost zählen (#596 H7, `docs/konzept-traffic.md`).
///
/// Jeder Abruf beim eigenen Host (`kMapTilesBase`) geht über [hostClient]
/// oder [hostGet] — nie über `http.Client()` oder `http.get` direkt;
/// `test/map/host_requests_test.dart` sucht danach in `lib/`. So zählt
/// [HostRequestCounter] alles, was Dart holt: Manifeste, Orte, Namen,
/// Höhen, die Range-Anfragen auf Karte und Wege im Browser und beim
/// Speichern eines Bereichs. Was MapLibre auf Android selbst lädt (Karte,
/// Wege), zählt die native Seite (`HostRequestCounter.kt`, nur in der
/// Dev-App); [readHostRequests] legt beides zusammen.
///
/// Gezählt wird immer (eine Zahl je Abruf), gezeigt nur in der Dev-App und
/// der Web-Vorschau (Profil → Entwicklung).
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pmtiles/pmtiles.dart' show PmTilesArchive;

import '../../core/app_distribution.dart';
import '../../core/platform_support.dart';
import 'map_providers.dart' show kMapTilesBase;

/// Wofür eine Anfrage an den Host ging.
enum HostRequestKind {
  /// Kacheln der Grundkarte (`dach-…`, `map-…`) und Übersichten.
  map,

  /// Kacheln der Ebene „Wege".
  ways,

  /// Höhenkacheln.
  heights,

  /// Manifeste und der Regionen-Index (`dach.json`, `pois.json` …).
  manifest,

  /// Orte- und Ortsnamen-Zellen (`<z>_<s>.<gruppe>.json`).
  pois,

  /// Namensdateien der Ortssuche (`names/<schlüssel>.json`).
  names,

  /// Alles andere (das Orte-Bündel einer ganzen Region).
  other,
}

final _host = Uri.parse(kMapTilesBase).host;

final _cellFile = RegExp(r'^-?\d+_-?\d+\.[A-Za-z]+\.json$');

/// Die Art einer Anfrage nach ihrem Pfad. EINE Regel für Dart und die
/// native Seite, die nur Pfade zählt.
HostRequestKind hostRequestKindOfPath(String path) {
  final file = path.substring(path.lastIndexOf('/') + 1);
  if (file.endsWith('.pmtiles')) {
    if (file.startsWith('ways-')) return HostRequestKind.ways;
    if (file.startsWith('heights-')) return HostRequestKind.heights;
    if (file.startsWith('dach-') ||
        file.startsWith('map-') ||
        file.startsWith('overview-')) {
      return HostRequestKind.map;
    }
    return HostRequestKind.other;
  }
  if (!file.endsWith('.json')) return HostRequestKind.other;
  if (path.contains('/names/')) return HostRequestKind.names;
  if (_cellFile.hasMatch(file)) return HostRequestKind.pois;
  return HostRequestKind.manifest;
}

/// Die Art einer Anfrage; null, wenn sie nicht an den Kartenhost geht.
HostRequestKind? hostRequestKindOf(Uri uri) =>
    uri.host == _host ? hostRequestKindOfPath(uri.path) : null;

/// Die Zählung der Dart-Seite, eine je App-Lauf.
class HostRequestCounter {
  HostRequestCounter._();

  static final instance = HostRequestCounter._();

  final _counts = <HostRequestKind, int>{};

  /// Seit wann gezählt wird: Start der App oder das letzte [reset].
  DateTime since = DateTime.now();

  Map<HostRequestKind, int> get counts => Map.unmodifiable(_counts);

  void record(Uri uri) {
    final kind = hostRequestKindOf(uri);
    if (kind == null) return;
    _counts[kind] = (_counts[kind] ?? 0) + 1;
  }

  void reset() {
    _counts.clear();
    since = DateTime.now();
  }
}

/// Ein Client, der jede Anfrage zählt und an [inner] weitergibt.
class HostCountingClient extends http.BaseClient {
  HostCountingClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    HostRequestCounter.instance.record(request.url);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Der Client für Abrufe beim Kartenhost — wie `http.Client()`, nur
/// gezählt. Wer ihn anlegt, schließt ihn auch (wie vorher).
http.Client hostClient() => HostCountingClient(http.Client());

/// EIN Client für alle Archive des Hosts, nie geschlossen: Ein Archiv
/// schließt einen übergebenen Client nicht (`PmTilesArchive.fromUri`), und
/// einer je Archiv bliebe offen liegen. Range-Anfragen teilen sich so auch
/// die Verbindungen.
final _archiveClient = hostClient();

/// Ein Archiv des Hosts über Range-Anfragen öffnen, gezählt.
Future<PmTilesArchive> openHostPmTiles(Uri uri) =>
    PmTilesArchive.fromUri(uri, client: _archiveClient);

/// `http.get` beim Kartenhost, gezählt.
Future<http.Response> hostGet(Uri uri) async {
  final client = hostClient();
  try {
    return await client.get(uri);
  } finally {
    client.close();
  }
}

/// Der Kanal zur nativen Zählung; der Name steht in Kotlin gleich
/// (`android_manifest_test`).
const kHostRequestsChannel = MethodChannel(
  'de.mcbuchi.trailbuddy/host_requests',
);

/// Was MapLibre auf Android beim Host geholt hat, je Pfad. Leer im Web,
/// außerhalb der Dev-App und wenn der Kanal nicht antwortet.
Future<Map<String, int>> _nativeCounts() async {
  if (!(isAndroidApp || isIosApp)) return {};
  try {
    final raw = await kHostRequestsChannel.invokeMapMethod<String, int>(
      'counts',
    );
    return raw ?? {};
  } on PlatformException {
    return {};
  } on MissingPluginException {
    return {};
  }
}

/// Dart- und native Zählung zusammen, je Art.
Map<HostRequestKind, int> mergeHostCounts(
  Map<HostRequestKind, int> dart,
  Map<String, int> nativePaths,
) {
  final out = {...dart};
  for (final MapEntry(key: path, value: n) in nativePaths.entries) {
    final kind = hostRequestKindOfPath(path);
    out[kind] = (out[kind] ?? 0) + n;
  }
  return out;
}

/// Der Stand für „Entwicklung": Zählung und seit wann.
typedef HostRequestSnapshot = ({
  Map<HostRequestKind, int> counts,
  DateTime since,
});

Future<HostRequestSnapshot> readHostRequests() async {
  final counter = HostRequestCounter.instance;
  return (
    counts: mergeHostCounts(counter.counts, await _nativeCounts()),
    since: counter.since,
  );
}

Future<void> resetHostRequests() async {
  HostRequestCounter.instance.reset();
  if (!(isAndroidApp || isIosApp)) return;
  try {
    await kHostRequestsChannel.invokeMethod<void>('reset');
  } on PlatformException {
    // Ohne native Zählung gibt es dort nichts zurückzusetzen.
  } on MissingPluginException {
    // Ebenso.
  }
}

/// Lesen und Zurücksetzen — die Naht für Tests.
final hostRequestsProvider =
    Provider<
      ({
        Future<HostRequestSnapshot> Function() read,
        Future<void> Function() reset,
      })
    >((ref) => (read: readHostRequests, reset: resetHostRequests));

/// Ob das Profil die Zeile „Entwicklung" zeigt: nur Dev-App und
/// Web-Vorschau. Als Provider, weil beide Schalter `const` sind.
final devToolsVisibleProvider = Provider<bool>(
  (ref) => AppDistribution.isDevBuild || AppDistribution.isPreviewBuild,
);
