/// Manifeste des Kartenhosts höchstens einmal am Tag fragen (#596 H4,
/// `docs/konzept-traffic.md`).
///
/// Karte (`dach.json`), Wege, Höhen, der Regionen-Index und die Manifeste
/// der übrigen Regionen gehen über [HostManifests.load]: Ein gemerktes
/// Manifest, das jünger ist als [kHostManifestMaxAge] und sich lesen lässt,
/// gilt ohne Anfrage. Sonst fragt die App den Host, merkt sich die Antwort
/// (erst nachdem sie sich lesen ließ) und teilt laufende Abrufe. Ein
/// Netzfehler bleibt ein Fehler: Was ohne Netz gilt, entscheidet jede
/// Ebene weiter selbst (`Settings.seenMapManifest` & Co.). Das
/// Orte-Manifest hat seine eigene Klasse mit derselben Regel
/// (`PoiManifests`).
///
/// „Aktualisieren" in „Meine Bereiche" fragt frisch ([HostManifests.expire]).
/// Ein Zeiger, der bis zu 24 h alt ist, zeigt nie ins Leere: Der vorige Bau
/// eines Archivs bleibt einen Lauf (etwa einen Monat) liegen.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/browser_storage.dart';
import '../../data/seen_host_files.dart';
import 'host_requests.dart';
import 'map_providers.dart' show kMapTilesBase;

/// Die Ablage gesehener kleiner Dateien des Hosts (#596 H4) — die Naht
/// für Tests (der Harness hängt eine im Speicher ein).
final seenHostFilesProvider = Provider<SeenHostFiles?>(
  (ref) => chooseSeenHostFiles(web: kIsWeb, factory: browserIdbFactory()),
);

/// Höchstens so lange wartet ein Manifest auf den Host — wie
/// `kMapManifestTimeout` (#183).
const kHostManifestTimeout = Duration(seconds: 10);

class HostManifests {
  HostManifests({
    SeenHostFiles? seen,
    Future<http.Response> Function(Uri uri)? get,
    DateTime Function()? now,
  }) : _seen = seen,
       _get = get ?? hostGet,
       _now = now ?? DateTime.now;

  final SeenHostFiles? _seen;
  final Future<http.Response> Function(Uri uri) _get;
  final DateTime Function() _now;

  final _inflight = <String, Future<String?>>{};

  /// Nach [expire]: welche Manifeste seither frisch kamen — alle anderen
  /// gelten nicht mehr als jung. Null: kein [expire] in diesem Lauf.
  Set<String>? _sinceExpire;

  /// Der Schlüssel in der Ablage: der Pfad unter dem Host.
  static String keyOf(Uri uri) {
    final s = uri.toString();
    return s.startsWith('$kMapTilesBase/')
        ? s.substring(kMapTilesBase.length + 1)
        : s;
  }

  /// Das Manifest unter [uri], gelesen mit [parse]; null bei 404 (noch
  /// kein Bau, keine Ebene). Wirft bei jeder anderen Antwort, bei einem
  /// Netzfehler und wenn [parse] die frische Antwort ablehnt.
  Future<T?> load<T>(Uri uri, T Function(String text) parse) async {
    final key = keyOf(uri);
    final young = await _young(key);
    if (young != null) {
      try {
        return parse(young);
      } on Object {
        // Gemerkt, aber diese Fassung liest es nicht (neues Format nach
        // einem Update): wie keins, der Host entscheidet.
      }
    }
    final text = await (_inflight[key] ??= _fetch(uri).whenComplete(() {
      // Ein Block, kein Pfeil: `remove` gäbe die Future selbst zurück,
      // und `whenComplete` wartete auf sich selbst.
      _inflight.remove(key);
    }));
    if (text == null) return null;
    final value = parse(text);
    // Abgewartet: einmal am Tag, und die nächste Frage soll es finden.
    await _seen?.write(key, text);
    _sinceExpire?.add(key);
    return value;
  }

  /// Das gemerkte Manifest unter [uri], jedes Alters — nie eine Anfrage;
  /// null, wenn keins liegt oder es sich nicht lesen lässt.
  Future<T?> remembered<T>(Uri uri, T Function(String text) parse) async {
    final text = await readSeen(_seen, keyOf(uri));
    if (text == null) return null;
    try {
      return parse(text);
    } on Object {
      return null;
    }
  }

  /// Ab jetzt fragt jedes Manifest einmal frisch („Aktualisieren").
  void expire() => _sinceExpire = {};

  Future<String?> _young(String key) async {
    final file = await _seen?.read(key);
    if (file == null) return null;
    if (_now().difference(file.at) > kHostManifestMaxAge) return null;
    if (_sinceExpire case final fresh? when !fresh.contains(key)) return null;
    return file.text;
  }

  Future<String?> _fetch(Uri uri) async {
    final response = await _get(uri).timeout(kHostManifestTimeout);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw http.ClientException(
        '${uri.path}: HTTP ${response.statusCode}',
        uri,
      );
    }
    return utf8.decode(response.bodyBytes);
  }
}

/// Die Manifeste, EINMAL für alle Ebenen.
final hostManifestsProvider = Provider<HostManifests>(
  (ref) => HostManifests(seen: ref.watch(seenHostFilesProvider)),
);
