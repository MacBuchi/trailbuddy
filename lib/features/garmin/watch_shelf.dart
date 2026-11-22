// Die Ablage auf der Uhr (#515, Entscheidung E3; docs/konzept-garmin.md 2b):
// Routen, die man am Handy „auf die Uhr legt", ohne die Navigation zu
// starten, und an der Uhr ohne Handy startet. Die Uhr hält höchstens
// [kWatchShelfMax] (bis Messung 8.6), jede ganz (A8) — vereinfacht wie jede
// Route für die Uhr, nie in Stücken um den Fortschritt.
//
// Das Handy hört die Ablage im „hallo" der Uhr (`sh`) und in ihrer Antwort
// auf jede Änderung (`sh` als eigene Nachricht). Was hin oder weg soll, wartet
// hier ([WatchShelf]) — gemerkt in `rides/watch_shelf.json` neben den Fahrten
// (dieselben Backup-Ausschlüsse; eine Route beginnt oft an der Haustür, also
// nicht in die Einstellungen), auch über einen Neustart der App —, bis die
// Uhr-App sich meldet: Auf der fēnix 5 weckt eine Nachricht
// vom Handy sie nicht (Konzept-Geräte 4), Garmin Connect meldet SUCCESS auch
// für eine geschlossene App und verwirft die Nachricht. Erst die Antwort der
// Uhr nimmt einen Auftrag aus der Liste.
//
// Gespeichert wird nur die Route und was die Liste zeigt (Name, Länge,
// bergauf) — keine Position, keine Fahrt (A3).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/errors.dart';
import '../rides/ride_store.dart' show FileRideStore;
import 'garmin_bridge.dart';
import 'watch_route.dart';

/// Ab dieser Fassung kennt die Uhr-App die Ablage. Eine ältere nähme ein
/// Stück mit `sh` als Route der Navigation — sie bekommt keins.
const kWatchShelfFrom = '1.9.0';

bool watchKnowsShelf(String? version) =>
    watchVersionAtLeast(version, kWatchShelfFrom);

/// So viele Routen liegen höchstens auf der Uhr (`PhoneRoute.SHELF_MAX`;
/// E3: drei, bis Messung 8.6 eine andere Zahl sagt).
const kWatchShelfMax = 3;

/// Die Ablage der Uhr: im „hallo" als `sh`, als Antwort mit `t: sh` und `l`.
const kWatchShelf = 'sh';

/// „Aus der Ablage nehmen" ans Handy … an die Uhr.
const kWatchShelfDrop = 'sd';

/// Die Uhr hat keinen Platz, und die Route ersetzt keine (`x`, `c`).
const kWatchErrFull = 'full';

/// So lange wartet das Handy nach dem Senden auf die Antwort der Uhr; ein
/// Stück braucht über Garmin Connect ~15 s (Messung 8.2). Danach bleibt der
/// Auftrag liegen, bis die Uhr sich wieder meldet.
const kWatchShelfAckWait = Duration(seconds: 45);

/// Ab dieser Toleranz sagt das Handy, die Route sei stark vereinfacht:
/// viermal die Vorgabe, also eine Linie mit weit mehr als
/// [kWatchMaxPoints] Knicken.
const kWatchShelfStrongTolM = kWatchSimplifyM * 4;

/// Eine Route in der Ablage, wie die Liste sie zeigt.
class WatchShelfEntry {
  const WatchShelfEntry({
    required this.id,
    required this.name,
    required this.lengthM,
    required this.climbM,
  });

  final String id;
  final String name;
  final int lengthM;
  final int climbM;

  List<Object> toJson() => [id, name, lengthM, climbM];

  /// `[id, Name, Meter, bergauf]`, geprüft; sonst null.
  static WatchShelfEntry? fromJson(Object? raw) {
    if (raw is! List || raw.length < 4) return null;
    final [id, name, len, hm, ...] = raw;
    if (id is! String || name is! String || len is! int || hm is! int) {
      return null;
    }
    return WatchShelfEntry(id: id, name: name, lengthM: len, climbM: hm);
  }
}

List<WatchShelfEntry> _entriesOf(Object? raw) => raw is List
    ? [for (final e in raw) ?WatchShelfEntry.fromJson(e)]
    : const [];

/// Die Ablage aus dem „hallo" (fehlt `sh`, ist sie leer) oder aus der
/// Antwort `sh` (mit der Kennung der Route, die gerade ankam); sonst null.
({List<WatchShelfEntry> entries, String? id})? watchShelfOf(Object? message) {
  if (message is! Map) return null;
  if (message['t'] == kWatchHello) {
    return (entries: _entriesOf(message['sh']), id: null);
  }
  if (message['t'] != kWatchShelf) return null;
  final id = message['id'];
  return (entries: _entriesOf(message['l']), id: id is String ? id : null);
}

/// Die Stücke einer Route für die Ablage: jedes mit `sh`, das erste dazu mit
/// Name, Länge und bergauf für die Liste, und `rp`, wenn sie eine ersetzt.
List<Map<String, Object>> watchShelfParts(
  WatchRoute route,
  WatchShelfEntry entry, {
  String? replace,
}) => [
  for (final (i, p) in route.parts().indexed)
    {
      ...p,
      'sh': 1,
      if (i == 0) ...{
        'nm': entry.name,
        'len': entry.lengthM,
        'hm': entry.climbM,
        'rp': ?replace,
      },
    },
];

Map<String, Object> watchShelfDropOf(String id) => {
  't': kWatchShelfDrop,
  'id': id,
};

/// Ein Auftrag an die Ablage: hinlegen ([parts]) oder wegnehmen.
class WatchShelfJob {
  const WatchShelfJob.put(
    WatchShelfEntry this.entry,
    List<Map<String, Object>> this.parts, {
    this.replace,
  }) : dropId = null;

  const WatchShelfJob.drop(String this.dropId)
    : entry = null,
      parts = null,
      replace = null;

  final WatchShelfEntry? entry;
  final List<Map<String, Object>>? parts;
  final String? replace;
  final String? dropId;

  bool get isPut => entry != null;
  String get id => entry?.id ?? dropId!;

  Map<String, Object> toJson() => isPut
      ? {'put': entry!.toJson(), 'parts': parts!, 'rp': ?replace}
      : {'drop': dropId!};

  static WatchShelfJob? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final drop = raw['drop'];
    if (drop is String) return WatchShelfJob.drop(drop);
    final entry = WatchShelfEntry.fromJson(raw['put']);
    final parts = raw['parts'];
    final rp = raw['rp'];
    if (entry == null || parts is! List) return null;
    return WatchShelfJob.put(entry, [
      for (final p in parts)
        if (p is Map) Map<String, Object>.from(p),
    ], replace: rp is String ? rp : null);
  }
}

/// Warum ein Auftrag nicht ankam: kein Platz, die Uhr konnte ihn nicht
/// nehmen (Speicher, Absturz, Form), die Uhr-App ist zu alt.
enum WatchShelfFailure { full, refused, outdated, unconfirmed }

final watchShelfTraceProvider =
    StateProvider<({DateTime at, String? version, String event})?>(
      (ref) => null,
    );

class WatchShelfState {
  const WatchShelfState({
    this.entries = const [],
    this.jobs = const [],
    this.sendingId,
    this.failed,
    this.failure,
  });

  /// Was die Uhr zuletzt als ihre Ablage meldete.
  final List<WatchShelfEntry> entries;

  /// Was noch hin- oder wegmuss, der Reihe nach.
  final List<WatchShelfJob> jobs;

  /// Der Auftrag, der gerade hinübergeht.
  final String? sendingId;

  /// Der Name der Route, die zuletzt nicht ankam, und warum.
  final String? failed;
  final WatchShelfFailure? failure;

  /// Routen, die auf dem Weg zur Uhr sind.
  List<WatchShelfEntry> get pending => [for (final j in jobs) ?j.entry];

  /// Kennungen, die von der Uhr weg sollen.
  Set<String> get removing => {for (final j in jobs) ?j.dropId};

  /// Was die Liste zeigt: die Ablage ohne das, was weg soll oder ersetzt
  /// wird, dann was kommt.
  List<WatchShelfEntry> get shown => [
    for (final e in entries)
      if (!removing.contains(e.id) && !jobs.any((j) => j.replace == e.id)) e,
    for (final e in pending)
      if (!entries.any((x) => x.id == e.id)) e,
  ];

  /// Ist die Ablage mit dem, was schon kommt, voll?
  bool get full => shown.length >= kWatchShelfMax;

  WatchShelfState copyWith({
    List<WatchShelfEntry>? entries,
    List<WatchShelfJob>? jobs,
    String? Function()? sendingId,
    String? Function()? failed,
    WatchShelfFailure? Function()? failure,
  }) => WatchShelfState(
    entries: entries ?? this.entries,
    jobs: jobs ?? this.jobs,
    sendingId: sendingId != null ? sendingId() : this.sendingId,
    failed: failed != null ? failed() : this.failed,
    failure: failure != null ? failure() : this.failure,
  );

  String encode() => jsonEncode({
    'e': [for (final e in entries) e.toJson()],
    'j': [for (final j in jobs) j.toJson()],
  });

  static WatchShelfState parse(String? raw) {
    if (raw == null) return const WatchShelfState();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const WatchShelfState();
      final jobs = m['j'];
      return WatchShelfState(
        entries: _entriesOf(m['e']),
        jobs: jobs is List
            ? [for (final j in jobs) ?WatchShelfJob.fromJson(j)]
            : const [],
      );
    } catch (_) {
      // Unlesbar (eine ältere Fassung): leer anfangen, die Uhr meldet sich.
      return const WatchShelfState();
    }
  }
}

/// Wo die Ablage des Handys liegt: ein Text ([WatchShelfState.encode]).
abstract class WatchShelfStore {
  /// Wirft nie; null, wenn nichts da ist.
  Future<String?> read();

  /// null löscht. Wirft nie.
  Future<void> write(String? value);
}

class FileWatchShelfStore implements WatchShelfStore {
  FileWatchShelfStore({Directory? baseDir}) : _baseDirOverride = baseDir;

  final Directory? _baseDirOverride;
  static const fileName = 'watch_shelf.json';
  Future<void> _lock = Future.value();

  Future<File> _file() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/${FileRideStore.dirName}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$fileName');
  }

  @override
  Future<String?> read() async {
    if (kIsWeb) return null;
    try {
      await _lock;
      final f = await _file();
      return await f.exists() ? await f.readAsString() : null;
    } catch (e, s) {
      logError('Ablage der Uhr lesen', e, s);
      return null;
    }
  }

  @override
  Future<void> write(String? value) {
    if (kIsWeb) return Future.value();
    final done = _lock.then((_) async {
      try {
        final f = await _file();
        if (value == null) {
          if (await f.exists()) await f.delete();
          return;
        }
        final tmp = File('${f.path}.part');
        await tmp.writeAsString(value, flush: true);
        await tmp.rename(f.path);
      } catch (e, s) {
        logError('Ablage der Uhr schreiben', e, s);
      }
    });
    _lock = done;
    return done;
  }
}

/// Für Tests und das Web: nur im Speicher.
class MemoryWatchShelfStore implements WatchShelfStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? v) async => value = v;
}

final watchShelfStoreProvider = Provider<WatchShelfStore>(
  (ref) => FileWatchShelfStore(),
);

/// Wie [WatchShelf.put] ausging.
enum WatchShelfPut {
  /// Geht gleich hinüber — die Uhr-App hat sich in diesem Lauf gemeldet.
  sending,

  /// Wartet, bis TrailBuddy auf der Uhr aufgeht (die Uhr fragt).
  waiting,

  /// Liegt schon auf der Uhr.
  already,

  /// Unsere App ist nicht auf der Uhr.
  notInstalled,
}

class WatchShelf extends Notifier<WatchShelfState> {
  StreamSubscription<Object?>? _messages;

  /// Die Fassung der Uhr-App aus ihrem „hallo" — gesetzt heißt: Sie hat
  /// sich in diesem Lauf gemeldet.
  String? _ver;
  bool _heard = false;
  Timer? _ackTimer;
  WatchShelfJob? _sending;

  /// Die Ablage aus der Datei; alles andere wartet darauf.
  late Future<void> _loaded;

  @override
  WatchShelfState build() {
    ref.onDispose(() {
      _messages?.cancel();
      _ackTimer?.cancel();
    });
    _loaded = _load();
    final bridge = ref.read(garminBridgeProvider);
    if (bridge.supported) {
      _messages = bridge.messages.listen((m) => unawaited(_onMessage(m)));
    }
    return const WatchShelfState();
  }

  Future<void> _load() async {
    final saved = WatchShelfState.parse(
      await ref.read(watchShelfStoreProvider).read(),
    );
    state = saved;
  }

  void _set(WatchShelfState next) {
    state = next;
    unawaited(
      ref
          .read(watchShelfStoreProvider)
          .write(
            next.entries.isEmpty && next.jobs.isEmpty ? null : next.encode(),
          ),
    );
  }

  /// Eine Route auf die Uhr legen; [replace] ersetzt eine der Ablage (die
  /// Liste fragt, wenn sie voll ist). Liegt TrailBuddy auf der Uhr nicht
  /// offen, fragt die Uhr danach, und der Auftrag wartet auf ihr „hallo".
  Future<WatchShelfPut> put(
    WatchShelfEntry entry,
    WatchRoute route, {
    String? replace,
  }) async {
    await _loaded;
    if (state.entries.any((e) => e.id == entry.id) &&
        !state.removing.contains(entry.id)) {
      return WatchShelfPut.already;
    }
    var jobs = [
      for (final j in state.jobs)
        if (j.id != entry.id) j,
    ];
    // Ersetzt sie eine, die selbst erst kommt, fällt die einfach weg.
    String? rp = replace;
    if (rp != null && jobs.any((j) => j.isPut && j.id == rp)) {
      jobs = [
        for (final j in jobs)
          if (j.id != rp) j,
      ];
      rp = null;
    }
    // Die Stücke erst jetzt: `rp` steht im ersten.
    jobs.add(
      WatchShelfJob.put(
        entry,
        watchShelfParts(route, entry, replace: rp),
        replace: rp,
      ),
    );
    _set(state.copyWith(jobs: jobs, failed: () => null, failure: () => null));
    if (_heard) {
      _flush();
      return WatchShelfPut.sending;
    }
    final bridge = ref.read(garminBridgeProvider);
    final open = await bridge.open();
    if (!_heard) _trace('open: ${open.name}');
    if (open == WatchOpen.notInstalled && !kGarminTethered && !_heard) {
      _set(
        state.copyWith(
          jobs: [
            for (final j in state.jobs)
              if (j.id != entry.id) j,
          ],
        ),
      );
      return WatchShelfPut.notInstalled;
    }
    // Bei unklarem Status kann die Uhr-App bereits laufen und ihr „hallo"
    // vor diesem Lauf geschickt haben (auch bei per USB geladener App).
    if (open != WatchOpen.prompted && !_heard) {
      unawaited(checkConnection());
    }
    return _heard ? WatchShelfPut.sending : WatchShelfPut.waiting;
  }

  /// Eine Route von der Uhr nehmen — oder, wenn sie erst kommt, nicht mehr
  /// schicken.
  Future<void> remove(String id) async {
    await _loaded;
    final waiting = state.jobs.any(
      (j) => j.isPut && j.id == id && j.id != state.sendingId,
    );
    final jobs = [
      for (final j in state.jobs)
        if (j.id != id) j,
    ];
    if (!waiting) jobs.add(WatchShelfJob.drop(id));
    _set(state.copyWith(jobs: jobs));
    _flush();
  }

  Future<void> _onMessage(Object? message) async {
    await _loaded;
    final hello = watchHelloOf(message);
    if (hello.hello) {
      _heard = true;
      _ver = hello.ver;
      _trace('hi');
      if (watchKnowsShelf(_ver)) _confirm(watchShelfOf(message)!.entries);
      _flush();
      return;
    }
    final shelf = watchShelfOf(message);
    if (shelf != null) {
      _heard = true;
      _trace('sh');
      _confirm(shelf.entries);
      _flush();
      return;
    }
    final error = watchErrorOf(message);
    final sending = _sending;
    if (error != null && sending != null && error.id == sending.id) {
      _ackTimer?.cancel();
      _sending = null;
      _trace('x: ${error.code}');
      _set(
        state.copyWith(
          jobs: [
            for (final j in state.jobs)
              if (!identical(j, sending)) j,
          ],
          sendingId: () => null,
          failed: () => sending.entry?.name,
          failure: () => switch (error.code) {
            kWatchErrFull => WatchShelfFailure.full,
            kWatchErrVersion => WatchShelfFailure.outdated,
            _ => WatchShelfFailure.refused,
          },
        ),
      );
      _flush();
    }
  }

  void _confirm(List<WatchShelfEntry> entries) {
    final stored = entries.map((entry) => entry.id).toSet();
    bool confirmed(WatchShelfJob job) => job.isPut == stored.contains(job.id);
    final sending = _sending;
    final done = sending != null && confirmed(sending);
    if (done) {
      _ackTimer?.cancel();
      _sending = null;
    }
    final jobs = [
      for (final job in state.jobs)
        // A removal queued during a transfer must wait for that transfer.
        if (!confirmed(job) ||
            (!done && job.id == sending?.id && !identical(job, sending)))
          job,
    ];
    final updated = done || jobs.length < state.jobs.length;
    _set(
      state.copyWith(
        entries: entries,
        jobs: jobs,
        sendingId: done ? () => null : null,
        failed: updated ? () => null : null,
        failure: updated ? () => null : null,
      ),
    );
  }

  /// Den nächsten Auftrag hinüber, einen zur Zeit — nur, solange die Uhr-App
  /// sich gemeldet hat und die Ablage kennt.
  void _flush() {
    if (!_heard || state.sendingId != null || state.jobs.isEmpty) return;
    if (!watchKnowsShelf(_ver)) {
      if (state.failure != WatchShelfFailure.outdated) {
        _set(
          state.copyWith(
            failed: () => state.pending.firstOrNull?.name,
            failure: () => WatchShelfFailure.outdated,
          ),
        );
      }
      return;
    }
    final job = state.jobs.first;
    _sending = job;
    _set(
      state.copyWith(
        sendingId: () => job.id,
        failed: () => null,
        failure: () => null,
      ),
    );
    unawaited(_send(job));
  }

  void _trace(String event) {
    ref.read(watchShelfTraceProvider.notifier).state = (
      at: DateTime.now(),
      version: _ver,
      event: event,
    );
  }

  Future<void> checkConnection() async {
    final bridge = ref.read(garminBridgeProvider);
    await bridge.listen();
    _trace('q');
    final result = await bridge.send([watchQuery]);
    if (!result.ok && !_heard) _trace('q: ${result.status}');
  }

  Future<void> _send(WatchShelfJob job) async {
    _trace('send');
    try {
      final result = await ref
          .read(garminBridgeProvider)
          .send(job.parts ?? [watchShelfDropOf(job.id)]);
      if (!identical(_sending, job)) return;
      _trace('${result.status} · ${result.sent}/${job.parts?.length ?? 1}');
      if (!result.ok) return _giveUp(job);
    } catch (e, s) {
      logError('Ablage an die Uhr', e, s);
      _giveUp(job);
      return;
    }
    // Ist die Antwort schon da, ist der Auftrag schon weg.
    if (!identical(_sending, job)) return;
    _ackTimer?.cancel();
    _ackTimer = Timer(kWatchShelfAckWait, () {
      _trace('sh timeout');
      _giveUp(job);
    });
  }

  /// Keine Antwort (die Uhr-App ging zu) oder Senden ging nicht: Der
  /// Auftrag bleibt, bis die Uhr sich wieder meldet.
  void _giveUp(WatchShelfJob job) {
    if (!identical(_sending, job)) return;
    _sending = null;
    _heard = false;
    _set(
      state.copyWith(
        sendingId: () => null,
        failed: () => job.entry?.name,
        failure: () => WatchShelfFailure.unconfirmed,
      ),
    );
  }
}

final watchShelfProvider = NotifierProvider<WatchShelf, WatchShelfState>(
  WatchShelf.new,
);
