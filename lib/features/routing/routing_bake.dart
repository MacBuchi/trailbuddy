// Backen im Hintergrund (#380, Konzept-Routing 11.4 Weg C): Nach dem
// Speichern oder Aktualisieren eines Bereichs backt die App die Stücke
// seiner z13-Kacheln, bevor jemand dort plant — dann setzt schon die
// ERSTE Planung nur noch zusammen. Weg B (`routing_pieces.dart`) bleibt
// das Netz darunter: Was hier nicht fertig wird, backt die Planung.
//
// Vier Regeln, die man wissen muss:
// - **Block für Block, wiederaufnehmbar.** Je Block (4 × 4 Kacheln, im
//   Browser 2 × 2) fragt der Dienst wie der Lader, welche Stücke frisch
//   liegen ([findPieces]), liest nur den Rest ([readRoadTiles] mit
//   `only`/`covered`, das Wege-Archiv eine Kachel darüber hinaus wie beim
//   Bau eines Rahmens), backt im EIGENEN Runner ([LoopPlanRunner.bake],
//   auf Android ein eigener Rechen-Isolate) und legt die Stücke in einem
//   Schreibvorgang ab. Was liegt, ist fertig: Nach einem Abbruch oder
//   Neustart macht der nächste Start ([RoutingBakeNotifier.bakeStored],
//   #410), das nächste Speichern oder Aktualisieren dort weiter, wo es
//   stand, und eine Planung dazwischen backt den Rest ihres Rahmens.
// - **Nie, während der Planer rechnet.** Vor jedem Block wartet er, bis
//   `loopPlannerProvider` nicht mehr `busy` ist — beide wollen dieselben
//   Kerne, und gewartet wird auf den Planer.
// - **Die ganze Region backt nicht im Hintergrund** (Betreiber
//   2026-10-18): DACH sind ~95 000 Kacheln, 4–10 h am Pixel. Dort backt
//   jede Planung ihren Rahmen (Weg B).
// - **Unter dem KeepAlive-Koordinator** (Schlüssel `bake`, `dataSync`)
//   wie der Download — mit eigenem Schlüssel, damit das Ende des Downloads
//   den Dienst nicht beendet, während hier gebacken wird.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../l10n/l10n.dart';
import '../keep_alive/keep_alive.dart';
import '../offline_areas/area_plan.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../offline_areas/height_tiles.dart';
import '../offline_areas/tile_store.dart';
import 'graph_input.dart';
import 'loop_plan_runner.dart';
import 'loop_planner_controller.dart' show loopPlannerProvider;
import 'road_graph_loader.dart';
import 'routing_pieces.dart';
import 'routing_tile.dart';

/// Die Kantenlänge eines Blocks in Kacheln. Im Browser kleiner: Dort
/// backt der UI-Thread selbst, und ein Block ist ein Ruckler.
const kBakeBlockSide = kIsWeb ? 2 : 4;

/// Was gerade gebacken wird — für die Zeile in „Meine Bereiche".
@immutable
class RoutingBakeState {
  const RoutingBakeState({this.name, this.done = 0, this.total = 0});

  /// Der Bereich, der gerade backt; null, wenn nichts läuft.
  final String? name;
  final int done;
  final int total;

  bool get running => name != null;

  double? get fraction => total == 0 ? null : done / total;
}

/// Die Pause zwischen zwei Blicken auf einen rechnenden Planer, und
/// zwischen zwei Blöcken (dem Browser seine Frames) — die Naht für Tests.
final routingBakePauseProvider = Provider<Future<void> Function({required bool planner})>((ref) =>
    ({required bool planner}) => Future.delayed(planner ? const Duration(seconds: 1) : Duration.zero));

/// Rechnet der Planer gerade? Dann wartet das Backen — die Naht für Tests.
final routingBakePlannerBusyProvider = Provider<bool Function()>(
    (ref) => () => ref.exists(loopPlannerProvider) && ref.read(loopPlannerProvider).busy);

/// Backt der Kartenstart nach ([RoutingBakeNotifier.bakeStored])? Die
/// Naht für Tests — der Harness schaltet es ab.
final routingBakeOnStartProvider = Provider<bool>((ref) => true);

class RoutingBakeNotifier extends Notifier<RoutingBakeState> {
  static const _keepAliveKey = 'bake';
  final _queue = <StoredArea>[];
  Future<void>? _running;
  /// Zählt jedes Abbrechen; ein Bereich backt nur, solange sie steht,
  /// die er beim Start gesehen hat.
  var _cancels = 0;

  /// Wie viele Kacheln drüben gebacken wurden — für den Test.
  @visibleForTesting
  int baked = 0;

  @override
  RoutingBakeState build() => const RoutingBakeState();

  /// Die Bereiche, die im Hintergrund backen — ohne die ganze Region,
  /// unvollständige, übernommene und solche ohne z13.
  static bool bakes(StoredArea a) =>
      a.shape is! RegionShape && a.complete && !a.legacy && a.maxZoom >= kRoutingTileZoom;

  /// Stellt [areas] in die Reihe und startet, falls nichts läuft. Kehrt
  /// sofort zurück; [idle] wartet auf das Ende.
  void bakeAreas(Iterable<StoredArea> areas) {
    var added = false;
    for (final a in areas) {
      if (!bakes(a) || _queue.any((q) => q.id == a.id)) continue;
      _queue.add(a);
      added = true;
    }
    if (!added) return;
    _running ??= _drain();
  }

  /// Läuft, bis die Reihe leer ist — auch, wenn während des Aufräumens
  /// eines Laufs (Dienst beenden) etwas eingereiht wurde.
  Future<void> _drain() async {
    try {
      do {
        await _run();
      } while (_queue.isNotEmpty);
    } finally {
      _running = null;
    }
  }

  /// Holt nach, was beim Start fehlt (#410): jeder Bereich, der backt,
  /// in die Reihe. Bereiche von vor 0.137.0 bekommen so ihre Stücke, ohne
  /// dass jemand „Aktualisieren" kennt, ebenso ein abgebrochenes Backen
  /// und Stücke, die eine neue [kRoutingTileVersion] alt gemacht hat. Was
  /// frisch liegt, kostet je Block nur [findPieces].
  Future<void> bakeStored() async => bakeAreas(await ref.read(storedAreasProvider.future));

  /// Fertig, wenn nichts mehr backt.
  Future<void> get idle => _running ?? Future.value();

  /// Bricht ab; was liegt, bleibt. Der nächste Start, das nächste
  /// Speichern oder Aktualisieren in der Region macht weiter.
  void cancel() {
    _cancels++;
    _queue.clear();
  }

  Future<void> _run() async {
    final coordinator = ref.read(keepAliveCoordinatorProvider);
    final l = serviceL10n();
    LoopPlanRunner? runner;
    var started = false;
    try {
      while (_queue.isNotEmpty) {
        final area = _queue.removeAt(0);
        final cancels = _cancels;
        final blocks = _blocksOf(area.shape.tiles(minZoom: kRoutingTileZoom, maxZoom: kRoutingTileZoom));
        final total = blocks.fold<int>(0, (s, b) => s + b.length);
        var done = 0;
        // Gezeigt wird erst, wenn ein Block wirklich backt: Liegt alles
        // frisch (der Start prüft jeden Bereich), bleiben Dienst und
        // Zeile in „Meine Bereiche" still.
        var shown = false;
        try {
          for (final block in blocks) {
            await _waitWhilePlanning(cancels);
            if (_cancels != cancels) break;
            final lookup =
                await findPieces(ref.read(tileStoreProvider), [area.region], block, ref.read(routingPieceSessionProvider));
            if (lookup.pending) {
              final percent = l.areaNoticePercent(area.name, (100 * done / total).round());
              if (!started) {
                started = true;
                await coordinator.start(_keepAliveKey, percent, title: l.areaNoticeBakeTitle);
              } else if (!shown) {
                unawaited(coordinator.update(_keepAliveKey, percent));
              }
              shown = true;
              state = RoutingBakeState(name: area.name, done: done, total: total);
              await _bakeBlock(area, block, lookup, runner ??= ref.read(loopPlanRunnerFactoryProvider)());
            }
            done += block.length;
            if (!shown) continue;
            state = RoutingBakeState(name: area.name, done: done, total: total);
            unawaited(coordinator.update(_keepAliveKey, l.areaNoticePercent(area.name, (100 * done / total).round())));
            await ref.read(routingBakePauseProvider)(planner: false);
          }
        } catch (e, s) {
          // Ein Bereich, der nicht backt, kostet nur die Abkürzung: Die
          // Planung dort backt selbst (Weg B).
          logError('Routing-Kacheln im Hintergrund backen', e, s);
          runner?.dispose();
          runner = null;
        }
      }
    } finally {
      runner?.dispose();
      state = const RoutingBakeState();
      if (started) await coordinator.stop(_keepAliveKey);
    }
  }

  Future<void> _waitWhilePlanning(int cancels) async {
    final busy = ref.read(routingBakePlannerBusyProvider);
    while (_cancels == cancels && busy()) {
      await ref.read(routingBakePauseProvider)(planner: true);
    }
  }

  /// Ein Block mit fehlenden oder alten Stücken: den Rest lesen, drüben
  /// backen, ablegen.
  Future<void> _bakeBlock(StoredArea area, List<TileXYZ> block, PieceLookup lookup, LoopPlanRunner runner) async {
    final own = {for (final t in block) (t.x, t.y)};
    // Die Nachbarn eine Kachel weit: nur für das Wege-Archiv (das Backen
    // liest 3 × 3), ihre Wege werden nicht gelesen.
    final ring = {
      for (final t in block)
        for (var dx = -1; dx <= 1; dx++)
          for (var dy = -1; dy <= 1; dy++)
            if (!own.contains((t.x + dx, t.y + dy))) (t.x + dx, t.y + dy),
    };
    final centres = [
      for (final (x, y) in {...own, ...ring})
        if (tileBounds(kRoutingTileZoom, x, y) case final b) b.center,
    ];
    final store = ref.read(areaStoreProvider);
    final open = ref.read(areaArchiveOpenerProvider);
    final openWays = ref.read(areaWaysOpenerProvider);
    // Gelesen wird je REGION wie im Planer, nicht je Bereich: Der Bau des
    // Stücks ([findPieces]) nennt das Wege-Archiv und die Höhen, die im
    // Speicher der Region liegen — auch die eines anderen Bereichs. Läse
    // der Dienst nur [area], trüge ein Bereich ohne Wege oder Höhen neben
    // einem mit ein frisches Stück ohne Güte und flach.
    final regionAreas = [
      for (final a in await ref.read(storedAreasProvider.future))
        if (a.region == area.region) a,
    ];
    final read = await readRoadTiles(
      areas: regionAreas.isEmpty ? [area] : regionAreas,
      box: LatBox.of(centres),
      open: (a) => open(store, a),
      openWays: (a) => openWays(store, a),
      sourceKey: (a) => a.region,
      only: {...own, ...ring},
      covered: {...lookup.fresh.keys, ...ring},
    );
    final bake = lookup.split(read.roads).roads;
    if (bake.isEmpty) return;
    // Die Höhen aus dem Leser der Region, wie im Planer. Geht er nicht
    // auf, wirft das bis zum Bereich: flach gebacken trüge das Stück den
    // Höhen-Bau und gälte als frisch. Dann backt die Planung (Weg B).
    final reader = await ref.read(areaHeightReaderProvider.future);
    final heights = await HeightTiles.read(reader, [for (final r in bake) (x: r.tile.x, y: r.tile.y)]);
    final pieces = await runner.bake(BakeInput(roads: bake, ways: read.ways, heights: heights));
    baked += pieces.length;
    await lookup.keepPieces(pieces);
  }
}

/// Die Kacheln in Blöcken von [kBakeBlockSide] × [kBakeBlockSide], von
/// Nord-West nach Süd-Ost — Nachbarn backen nacheinander, und das
/// Wege-Archiv eines Blocks liegt beisammen.
List<List<TileXYZ>> _blocksOf(List<TileXYZ> tiles) {
  final byBlock = <(int, int), List<TileXYZ>>{};
  for (final t in tiles) {
    (byBlock[(t.x ~/ kBakeBlockSide, t.y ~/ kBakeBlockSide)] ??= []).add(t);
  }
  final keys = byBlock.keys.toList()..sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);
  return [for (final k in keys) byBlock[k]!];
}

final routingBakeProvider = NotifierProvider<RoutingBakeNotifier, RoutingBakeState>(RoutingBakeNotifier.new);
