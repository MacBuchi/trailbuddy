import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import 'official_trails.dart';

/// Woher die Dateien kommen. Eine Schnittstelle, damit Tests ein Fake
/// einhängen — kein Netz in Tests.
abstract interface class OfficialTrailsSource {
  /// Eine Datei des Daten-Branches: `index.json` oder eine Region.
  Future<String> fetch(String file);
}

/// Der Daten-Branch über `raw.githubusercontent.com` — steht in der
/// Datenschutzerklärung. Übertragen wird nur, WELCHE Datei; welche
/// Region, verrät der Ausschnitt, mehr nicht.
class GithubOfficialTrailsSource implements OfficialTrailsSource {
  GithubOfficialTrailsSource([http.Client? client])
    : _client = client ?? http.Client();

  final http.Client _client;

  static const base =
      'https://raw.githubusercontent.com/MacBuchi/TrailBuddy/official-trails-data/';

  @override
  Future<String> fetch(String file) async {
    final res = await _client
        .get(Uri.parse('$base$file'))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw OfficialTrailsUnavailable(res.statusCode);
    // Die Dateien sind UTF-8 (Umlaute in Namen); nicht auf den
    // Zeichensatz im Content-Type verlassen.
    return utf8.decode(res.bodyBytes);
  }
}

class OfficialTrailsUnavailable implements Exception {
  const OfficialTrailsUnavailable(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'Offizielle Trails: HTTP $statusCode';
}

/// Die gemerkten Dateien — damit die Ebene im Funkloch am Trail da ist,
/// wo sie gebraucht wird.
abstract interface class OfficialTrailsCache {
  Future<String?> read(String name);
  Future<void> write(String name, String body);
}

/// Auf Android ein Ordner im App-Verzeichnis (vom Backup ausgenommen,
/// `res/xml/`). Im Web merkt sich der Browser die Antworten selbst; dort
/// hält die App sie nur für die Laufzeit.
class FileOfficialTrailsCache implements OfficialTrailsCache {
  FileOfficialTrailsCache({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  final _memory = <String, String>{};

  Future<File> _file(String name) async =>
      File('${(await _directory()).path}/official_trails/$name');

  @override
  Future<String?> read(String name) async {
    if (kIsWeb) return _memory[name];
    final f = await _file(name);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String name, String body) async {
    if (kIsWeb) {
      _memory[name] = body;
      return;
    }
    final f = await _file(name);
    await f.parent.create(recursive: true);
    // Erst daneben schreiben, dann umbenennen: Ein Abbruch mittendrin
    // hinterlässt keine halbe Datei, die beim nächsten Start kaputt wäre.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(f.path);
  }
}

final officialTrailsSourceProvider = Provider<OfficialTrailsSource>(
  (ref) => GithubOfficialTrailsSource(),
);

final officialTrailsCacheProvider = Provider<OfficialTrailsCache>(
  (ref) => FileOfficialTrailsCache(),
);

/// Der Schalter der Ebene, gerätelokal. Aus heißt: keine Anfrage.
final officialTrailsEnabledProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.officialTrailsEnabled,
    write: (s, v) => s.setOfficialTrailsEnabled(v),
    label: 'Ebene offizielle Trails merken',
  ),
);

@immutable
class OfficialTrailsState {
  const OfficialTrailsState({
    this.index,
    this.byRegion = const {},
    this.unavailable = false,
  });

  final OfficialIndex? index;

  /// Die geladenen Regionen, je Kennung.
  final Map<String, List<OfficialTrail>> byRegion;

  /// Eine gebrauchte Region (oder der Index) kam nicht und lag auch
  /// nicht auf dem Gerät.
  final bool unavailable;

  List<OfficialTrail> get trails => [for (final l in byRegion.values) ...l];

  /// Die Quellen der geladenen Regionen — für die Attribution der Karte.
  List<OfficialSource> get loadedSources {
    final i = index;
    if (i == null) return const [];
    final ids = <String>{
      for (final r in i.regions)
        if (byRegion.containsKey(r.id)) ...r.sourceIds,
    };
    return [for (final id in ids) ?i.sources[id]];
  }

  OfficialSource? sourceOf(OfficialTrail t) => index?.sources[t.sourceId];

  OfficialTrailsState copyWith({
    OfficialIndex? index,
    Map<String, List<OfficialTrail>>? byRegion,
    bool? unavailable,
  }) => OfficialTrailsState(
    index: index ?? this.index,
    byRegion: byRegion ?? this.byRegion,
    unavailable: unavailable ?? this.unavailable,
  );
}

/// Lädt, was der Ausschnitt braucht. Der Index wird je App-Lauf einmal
/// gefragt; eine Region nur, wenn ihr Rahmen den Ausschnitt berührt und
/// sie nicht schon mit demselben Stand auf dem Gerät liegt. Ohne Netz
/// gilt, was gemerkt ist — auch ein älterer Stand.
class OfficialTrailsController extends Notifier<OfficialTrailsState> {
  bool _busy = false;
  ({double s, double w, double n, double e})? _queued;
  bool _indexAsked = false;

  @override
  OfficialTrailsState build() => const OfficialTrailsState();

  OfficialTrailsSource get _source => ref.read(officialTrailsSourceProvider);
  OfficialTrailsCache get _cache => ref.read(officialTrailsCacheProvider);

  Future<void> ensure(({double s, double w, double n, double e}) view) async {
    if (_busy) {
      _queued = view;
      return;
    }
    _busy = true;
    try {
      await _load(view);
      while (_queued != null) {
        final q = _queued!;
        _queued = null;
        await _load(q);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _load(({double s, double w, double n, double e}) view) async {
    final index = state.index ?? await _loadIndex();
    if (index == null) {
      state = state.copyWith(unavailable: true);
      return;
    }
    var unavailable = false;
    for (final r in index.regions) {
      if (state.byRegion.containsKey(r.id) ||
          !r.touches(view.s, view.w, view.n, view.e)) {
        continue;
      }
      final trails = await _loadRegion(r);
      if (trails == null) {
        unavailable = true;
        continue;
      }
      state = state.copyWith(byRegion: {...state.byRegion, r.id: trails});
    }
    state = state.copyWith(unavailable: unavailable);
  }

  Future<OfficialIndex?> _loadIndex() async {
    if (!_indexAsked) {
      _indexAsked = true;
      try {
        final body = await _source.fetch('index.json');
        final index = OfficialIndex.parse(body);
        state = state.copyWith(index: index);
        await _remember('index.json', body);
        return index;
      } catch (e, s) {
        _report('Index offizieller Trails laden', e, s);
      }
    }
    final cached = await _recall('index.json');
    if (cached == null) {
      // Beim nächsten Verschieben noch einmal fragen — sonst bliebe die
      // Ebene nach einem Start im Funkloch den ganzen Lauf leer.
      _indexAsked = false;
      return null;
    }
    try {
      final index = OfficialIndex.parse(cached);
      state = state.copyWith(index: index);
      return index;
    } catch (e, s) {
      logError('Gemerkten Index offizieller Trails lesen', e, s);
      _indexAsked = false;
      return null;
    }
  }

  Future<List<OfficialTrail>?> _loadRegion(OfficialRegion r) async {
    // Der Dateiname ist geprüft (`OfficialRegion._safeFile`), die
    // Kennung nicht — daher hängt der Stand am Dateinamen.
    final stampKey = '${r.file}.updated';
    final cached = await _recall(r.file);
    final cachedStamp = await _recall(stampKey);
    if (cached != null && cachedStamp == r.updated) {
      final trails = _parse(cached, r);
      if (trails != null) return trails;
    }
    try {
      final body = await _source.fetch(r.file);
      final trails = parseOfficialRegion(body);
      await _remember(r.file, body);
      await _remember(stampKey, r.updated);
      return trails;
    } catch (e, s) {
      _report('Offizielle Trails ${r.id} laden', e, s);
    }
    // Ein älterer Stand ist besser als eine leere Ebene am Trail.
    return cached == null ? null : _parse(cached, r);
  }

  List<OfficialTrail>? _parse(String body, OfficialRegion r) {
    try {
      return parseOfficialRegion(body);
    } catch (e, s) {
      logError('Gemerkte offizielle Trails ${r.id} lesen', e, s);
      return null;
    }
  }

  Future<String?> _recall(String name) async {
    try {
      return await _cache.read(name);
    } catch (e, s) {
      logError('Offizielle Trails vom Gerät lesen', e, s);
      return null;
    }
  }

  Future<void> _remember(String name, String body) async {
    try {
      await _cache.write(name, body);
    } catch (e, s) {
      // Nicht merken zu können kostet nur den nächsten Download.
      logError('Offizielle Trails merken', e, s);
    }
  }

  /// Ein Funkloch ist am Trail der Normalfall und kein Bericht wert,
  /// ebenso ein Server, der gerade nicht will; eine kaputte Datei schon.
  void _report(String context, Object e, StackTrace s) {
    if (looksOffline(e) ||
        e is OfficialTrailsUnavailable ||
        e is TimeoutException) {
      return;
    }
    logError(context, e, s);
  }
}

final officialTrailsControllerProvider =
    NotifierProvider<OfficialTrailsController, OfficialTrailsState>(
      OfficialTrailsController.new,
    );
