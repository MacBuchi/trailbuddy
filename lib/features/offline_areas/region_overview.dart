// Die Übersicht einer Region als Download (#220 Schritt 4,
// `docs/konzept-regionen.md` §5): Zoom 0–7 als EINE Datei (Kanada 35 MB),
// die mit dem ersten Bereich der Region kommt. DACH hat seine im Binary.
//
// Anders als die Bereiche wird sie nicht kachelweise per Range geholt,
// sondern als Ganzes — es ist eine fertige Datei vom Host, ein Abruf statt
// tausender Range-Anfragen (jede wäre eine R2-Class-B-Operation, #55).
// Gelesen wird sie erst, wenn Länge, Prüfsumme UND Archiv-Header stimmen;
// eine Übersicht, die nicht passt, kommt nicht auf das Gerät.
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pmtiles/pmtiles.dart';

import '../map/online_map.dart';

/// Holt eine Datei vom Host als Ganzes, mit Fortschritt und Abbruch
/// zwischen den Stücken; null bei 404 (die Übersicht fehlt — der Bereich
/// kommt ohne sie).
typedef OverviewFetcher = Future<Uint8List?> Function(
  Uri uri, {
  void Function(int received, int total)? onProgress,
  void Function()? check,
});

Future<Uint8List?> fetchOverviewFile(
  Uri uri, {
  void Function(int received, int total)? onProgress,
  void Function()? check,
}) async {
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', uri)).timeout(const Duration(seconds: 30));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw http.ClientException('${uri.path}: HTTP ${response.statusCode}', uri);
    }
    final total = response.contentLength ?? 0;
    final out = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      check?.call();
      out.add(chunk);
      onProgress?.call(out.length, total);
    }
    return out.takeBytes();
  } finally {
    client.close();
  }
}

/// Die Naht für Tests; der Harness setzt sie auf eine, die nichts holt.
final overviewFetcherProvider = Provider<OverviewFetcher>((ref) => fetchOverviewFile);

/// Die Datei passt nicht zu ihrem Manifest — kein Netzfehler, also kein
/// zweiter Versuch: Der Bereich kommt ohne Übersicht.
class OverviewMismatch implements Exception {
  const OverviewMismatch(this.message);
  final String message;
  @override
  String toString() => 'Übersicht passt nicht: $message';
}

/// Prüft Länge, Prüfsumme und Archiv-Header; wirft [OverviewMismatch].
Future<void> checkOverview(OverviewManifest manifest, Uint8List bytes) async {
  if (bytes.length != manifest.bytes) {
    throw OverviewMismatch('${bytes.length} statt ${manifest.bytes} Bytes');
  }
  final sha = crypto.sha256.convert(bytes).toString();
  if (sha != manifest.sha256) throw OverviewMismatch('Prüfsumme $sha');
  final PmTilesArchive archive;
  try {
    archive = await PmTilesArchive.fromBytes(bytes);
  } catch (e) {
    throw OverviewMismatch('kein Archiv ($e)');
  }
  try {
    if (archive.header.maxZoom != manifest.maxZoom) {
      throw OverviewMismatch('Zoom ${archive.header.maxZoom} statt ${manifest.maxZoom}');
    }
  } finally {
    await archive.close();
  }
}
