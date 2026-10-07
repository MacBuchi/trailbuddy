// Geländehöhen für Trails (#186, Betreiber 2026-10-02: „DEM-Höhen werden
// gezeigt, nie gespeichert"). Dieselben Höhenkacheln wie die Planung
// (Copernicus GLO-90, `height_tiles.dart`): erst die gespeicherten
// Bereiche, mit Empfang dahinter der Host über den Sitzungsspeicher
// (`OnlineHeights`, #187). Vier Abnehmer, eine Stelle:
//
// - **Anzeige**: Ein Trail ohne aufgezeichnete Höhen bekommt sein Profil
//   aus dem Geländemodell ([terrainProfileProvider]), beschriftet mit
//   [kTerrainLabel]. M3 hat entlang einer Linie ~5 % Medianfehler im
//   Abstieg gemessen — genug für die Anzeige.
// - **Export**: Die GPX-Datei trägt dann die Geländehöhen, markiert in
//   `<extensions>` der Spur (`gpx_writer.dart`). Der Import liest
//   markierte Höhen nie (`gpx.dart`) — sonst schriebe ein Re-Import der
//   eigenen Datei Modellhöhen als aufgezeichnete auf den Server.
// - **Planer** (#234): Das Ergebnis einer Runde und der Weg zum Trail
//   zeigen ihr Profil entlang der geplanten Linie ([lineProfileProvider]).
//   Die Engine kennt Höhen nur je Kante, ein Profil braucht sie je Punkt.
// - **Import**: [compareToTerrain] prüft die Höhen einer Datei gegen das
//   Modell. Liegen sie weit daneben (barometrischer Versatz, GPS-Sprünge),
//   bietet der Import an, sie zu verwerfen; die Aufzeichnung geht dann
//   ohne Höhen hinauf, und die Anzeige füllt sie hier auf. Schlechte
//   Höhen erreichen das Netz nie.
//
// Keine Höhe wird geraten: Fehlt für einen Punkt die Kachel, gibt es gar
// keine ([terrainHeightsAt] ist null) — ein halbes Profil wäre erfunden.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../offline_areas/area_providers.dart' show areaHeightReaderProvider;
import '../offline_areas/height_tiles.dart';
import '../routing/online_fill.dart' show onlineHeightsFactoryProvider;
import 'trail_elevation.dart';
import 'trail_providers.dart' show trailByIdProvider;

/// Die Beschriftung, wo Geländehöhen statt aufgezeichneter stehen.
const kTerrainLabel = 'Höhen aus dem Geländemodell (90 m)';

/// Die Höhe jedes Punkts aus [reader] — null, sobald einer keine hat.
Future<List<double>?> terrainHeightsAt(HeightReader reader, List<LatLng> points) async {
  final out = <double>[];
  for (final p in points) {
    final h = await reader.heightAt(p);
    if (h == null) return null;
    out.add(h);
  }
  return out;
}

/// Das Profil aus dem Geländemodell: Proben alle [kClimbSampleM] Meter
/// entlang [line] (in Trail-Richtung). Null ohne vollständige Höhen.
Future<ElevationProfile?> terrainProfileOf(HeightReader reader, List<LatLng> line) async {
  if (line.length < 2) return null;
  final samples = samplesAlong(line, kClimbSampleM);
  final heights = await terrainHeightsAt(reader, samples);
  return heights == null ? null : ElevationProfile.terrain(samples, heights);
}

/// Geländehöhen lesen: Bereiche zuerst, mit Empfang der Host. Eine Naht
/// für Blatt, Export und Import; die Quelle des Hosts lebt je Aufruf
/// (geöffnet erst, wenn eine Kachel nicht im Sitzungsspeicher liegt).
class TerrainHeights {
  TerrainHeights(this._ref);
  final Ref _ref;

  Future<T> _with<T>(Future<T> Function(HeightReader reader) use) async {
    HeightReader? areas;
    try {
      areas = await _ref.read(areaHeightReaderProvider.future);
    } catch (e, s) {
      logError('Höhen der Bereiche öffnen', e, s);
    }
    final online = _ref.read(noConnectivityProvider) ? null : _ref.read(onlineHeightsFactoryProvider)();
    // Die Quellen der Bereiche gehören ihrem Provider und bleiben offen;
    // geschlossen wird nur, was hier geöffnet wurde.
    final reader = HeightReader([...?areas?.sources, ?online]);
    try {
      return await use(reader);
    } finally {
      await online?.close();
    }
  }

  /// Höhe je Punkt, null wenn einer fehlt.
  Future<List<double>?> at(List<LatLng> points) => _with((r) => terrainHeightsAt(r, points));

  /// Das Profil entlang [line] — siehe [terrainProfileOf].
  Future<ElevationProfile?> profile(List<LatLng> line) => _with((r) => terrainProfileOf(r, line));
}

final terrainHeightsProvider = Provider<TerrainHeights>((ref) => TerrainHeights(ref));

/// Das Profil eines Trails OHNE aufgezeichnete Höhen aus dem
/// Geländemodell; null, wenn er welche hat oder das Modell dort keine
/// kennt. Gerechnet nur, solange jemand zusieht (das Blatt) — beobachten
/// heißt laden.
final terrainProfileProvider = FutureProvider.autoDispose.family<ElevationProfile?, String>((ref, trailId) async {
  final line = ref.watch(trailByIdProvider(trailId).select((t) => t == null || t.elevation != null ? null : t.directedPoints));
  if (line == null) return null;
  return ref.read(terrainHeightsProvider).profile(line);
});

/// Das Profil entlang einer geplanten Linie (#234) aus dem Geländemodell,
/// in Fahrtrichtung; null, wo eine Kachel fehlt. Der Schlüssel ist die
/// Liste selbst (Gleichheit = dieselbe Liste): Jedes neue Ergebnis bringt
/// eine neue, und nur so lange es gezeigt wird, lebt die Rechnung. Mit
/// Empfang kommen fehlende Kacheln aus dem Sitzungsspeicher, in den die
/// Planung sie schon gelegt hat — kein zweiter Abruf.
final lineProfileProvider = FutureProvider.autoDispose.family<ElevationProfile?, List<LatLng>>(
    (ref, line) => ref.read(terrainHeightsProvider).profile(line));

/// Wie die Höhen einer Datei zum Geländemodell passen (#186).
class TerrainComparison {
  const TerrainComparison({required this.offsetM, required this.spreadM});

  /// Median von Datei minus Modell: ein Versatz der ganzen Spur
  /// (barometrische Höhe ohne Abgleich).
  final double offsetM;

  /// 95. Perzentil der Abweichung um diesen Versatz: Sprünge und Zacken,
  /// die kein Gelände erklärt.
  final double spreadM;

  bool get offsetSuspicious => offsetM.abs() > kTerrainOffsetMaxM;
  bool get spreadSuspicious => spreadM > kTerrainSpreadMaxM;

  /// Weit genug daneben, dass der Import das Verwerfen anbietet.
  bool get suspicious => offsetSuspicious || spreadSuspicious;

  /// Der Satz im Import: was auffiel, in ganzen Metern.
  String get reason {
    final parts = <String>[
      if (offsetSuspicious)
        'liegen im Mittel ${offsetM.abs().round()} m ${offsetM > 0 ? 'über' : 'unter'} dem Gelände',
      if (spreadSuspicious) 'springen bis ${spreadM.round()} m daneben',
    ];
    return 'Die Höhen der Datei ${parts.join(' und ')}.';
  }
}

/// Ab diesem Versatz (Median) gelten die Höhen einer Datei als verschoben.
/// Nicht gemessen, sondern vorsichtig gesetzt: Das DEM liegt im Wald und
/// am Hang zehn, zwanzig Meter daneben, ein unkalibrierter Höhenmesser
/// gern hundert. Der Feldtest (#188) prüft die Zahl mit.
const kTerrainOffsetMaxM = 50.0;

/// Ab dieser Streuung (95. Perzentil um den Versatz) gelten sie als
/// verrauscht — weit über dem, was ein 90-m-Raster quer zum Hang erklärt.
const kTerrainSpreadMaxM = 80.0;

/// Vergleicht die Höhen einer Datei mit denen des Modells an denselben
/// Punkten; null ohne Paare.
TerrainComparison? compareToTerrain(List<double> file, List<double> terrain) {
  if (file.length != terrain.length || file.isEmpty) return null;
  final d = [for (var i = 0; i < file.length; i++) file[i] - terrain[i]]..sort();
  final offset = _quantile(d, 0.5);
  final spread = [for (final v in d) (v - offset).abs()]..sort();
  return TerrainComparison(offsetM: offset, spreadM: _quantile(spread, 0.95));
}

double _quantile(List<double> sorted, double q) {
  final pos = (sorted.length - 1) * q;
  final lo = pos.floor(), hi = pos.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}
