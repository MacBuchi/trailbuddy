// Der Rechen-Isolate des Planers (#188) — Begründung und Regeln in
// `loop_plan_runner.dart`. Ein Isolate je Runner, angelegt beim ersten
// Bau; die Eingabe geht hinüber, der Graph entsteht drüben und bleibt
// dort, danach nur noch Anfragen.
import 'dart:async';
import 'dart:isolate';

import 'graph_input.dart';
import 'loop_plan_runner.dart';
import 'loop_planner.dart';
import 'plan_progress.dart';
import 'routing_tile.dart' show RoutingPiece;

LoopPlanRunner createLoopPlanRunner() => IsolateLoopPlanRunner();

class IsolateLoopPlanRunner implements LoopPlanRunner {
  Future<SendPort>? _worker;
  Completer<SendPort>? _ready;
  Isolate? _isolate;
  final _ports = <ReceivePort>[];
  var _hasGraph = false;
  var _nextId = 0;
  final _pending = <int, Completer<Object?>>{};
  final _progress = <int, void Function(double value)>{};

  /// Wie oft eine Eingabe hinüberging — für den Test.
  int builds = 0;

  @override
  bool get hasGraph => _hasGraph;

  @override
  Future<GraphReport> build(GraphInput input, {void Function(double value)? onProgress}) async {
    final worker = await _ensure();
    builds++;
    // Kopiert die Bytes — Kacheln und Höhenraster, nicht den Graphen.
    final report = await _ask(worker, input, onProgress);
    _hasGraph = true;
    return report as GraphReport;
  }

  @override
  Future<LoopPlan> plan(LoopRequest request, {void Function(double value)? onProgress}) async {
    if (!_hasGraph) throw StateError('kein Graph gebaut');
    final worker = await _ensure();
    return await _ask(worker, request, onProgress) as LoopPlan;
  }

  @override
  Future<R> run<R>(GraphJob<R> job) async {
    if (!_hasGraph) throw StateError('kein Graph gebaut');
    final worker = await _ensure();
    return await _ask(worker, job) as R;
  }

  @override
  Future<List<RoutingPiece>> bake(BakeInput input) async {
    final worker = await _ensure();
    return (await _ask(worker, input) as List).cast<RoutingPiece>();
  }

  Future<SendPort> _ensure() async {
    final spawn = _worker ??= _spawn();
    final worker = await spawn;
    // Zwischen Start und hier freigegeben: Der Isolate ist weg, eine
    // Anfrage an ihn bekäme nie eine Antwort.
    if (!identical(spawn, _worker)) throw StateError('Planer geschlossen');
    return worker;
  }

  Future<Object?> _ask(SendPort worker, Object payload, [void Function(double value)? onProgress]) {
    final id = _nextId++;
    final done = Completer<Object?>();
    _pending[id] = done;
    if (onProgress != null) _progress[id] = onProgress;
    worker.send((id, payload, onProgress != null));
    return done.future;
  }

  Future<SendPort> _spawn() {
    final ready = _ready = Completer<SendPort>();
    final inbox = ReceivePort(), errors = ReceivePort(), exits = ReceivePort();
    _ports.addAll([inbox, errors, exits]);
    inbox.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
        return;
      }
      // Ein Zwischenstand (#356): Anteil 0…1 einer laufenden Rechnung.
      if (msg case (final int id, final double value)) {
        _progress[id]?.call(value);
        return;
      }
      final (id, result, error, stack) = msg as (int, Object?, String?, String?);
      _progress.remove(id);
      final done = _pending.remove(id);
      if (done == null) return;
      if (error == null) {
        done.complete(result);
      } else {
        done.completeError(RemoteError(error, stack ?? ''));
      }
    });
    // Ein Fehler außerhalb einer Rechnung oder das Ende des Isolates:
    // Was wartet, scheitert, und der nächste Bau legt neu an.
    errors.listen((e) {
      final parts = e as List<Object?>;
      _reset(RemoteError('${parts.first}', '${parts.last}'));
    });
    exits.listen((_) => _reset(StateError('Rechen-Isolate beendet')));
    Isolate.spawn(_workerMain, inbox.sendPort, onError: errors.sendPort, onExit: exits.sendPort, debugName: 'loop-planner')
        .then(
      (isolate) {
        // Schon freigegeben, während er startete: gleich wieder weg.
        if (!identical(_ready, ready)) {
          isolate.kill(priority: Isolate.immediate);
          return;
        }
        _isolate = isolate;
      },
      onError: (Object e, StackTrace s) {
        if (identical(_ready, ready)) _reset(e);
      },
    );
    return ready.future;
  }

  void _reset(Object error) {
    // Auch ein Start, der noch läuft, scheitert — sonst wartete die
    // Rechnung, die ihn ausgelöst hat, für immer.
    final ready = _ready;
    _ready = null;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    for (final p in _ports) {
      p.close();
    }
    _ports.clear();
    _worker = null;
    _hasGraph = false;
    final waiting = [..._pending.values];
    _pending.clear();
    _progress.clear();
    for (final c in waiting) {
      c.completeError(error);
    }
  }

  @override
  void dispose() => _reset(StateError('Planer geschlossen'));
}

void _workerMain(SendPort reply) {
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  BuiltGraph? built;
  // Die Suchen der letzten Rechnung (#188): Auf demselben Graphen fragt
  // die nächste meist dieselben.
  var cache = LoopSearchCache();
  inbox.listen((msg) {
    final (id, payload, wantsProgress) = msg as (int, Object, bool);
    try {
      Object work() {
        if (payload is GraphInput) {
          built = null; // der alte Graph darf gehen, bevor der neue entsteht
          cache = LoopSearchCache();
          final b = built = buildGraphFrom(payload, builtIn: Isolate.current.debugName ?? 'isolate');
          return b.report;
        }
        if (payload is BakeInput) return bakeFrom(payload);
        final g = built?.graph;
        if (g == null) throw StateError('kein Graph gebaut');
        return (payload as GraphJob<Object?>).runOn(g, cache) as Object;
      }

      final result = wantsProgress ? PlanProgress.run((v) => reply.send((id, v)), work) : work();
      reply.send((id, result, null, null));
    } catch (e, s) {
      reply.send((id, null, '$e', '$s'));
    }
  });
}
