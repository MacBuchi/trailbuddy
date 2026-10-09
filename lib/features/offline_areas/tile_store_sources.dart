// Der Kachelspeicher als Quelle (#229): für flutter_map und die Leser im
// Dart-Code (Wege-Index des Zerlege-Blatts, Graph und Wegegüte des
// Planers) eine Kachelquelle je Region und Ebene, für die Höhen eine
// Höhenquelle je Region. Eine fehlende Kachel ist eine `ProviderException`
// mit 404 — genau das, was ein Archiv für eine Kachel außerhalb sagt, und
// die Deckungsregel des Wege-Index zählt sie als „nicht gedeckt".
import 'dart:typed_data';

import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../map/pmtiles_tile_provider.dart';
import 'height_tiles.dart';
import 'tile_store.dart';

class StoreTileProvider extends ClosableVectorTileProvider {
  StoreTileProvider(this._store, this.region, this.layer, {required int minZoom, required int maxZoom})
      : _minZoom = minZoom,
        _maxZoom = maxZoom;

  final TileStore _store;
  final String region;
  final TileLayer layer;
  final int _minZoom;
  final int _maxZoom;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final bytes = await _store.read(region, layer, tile.z, tile.x, tile.y);
    if (bytes == null) {
      throw ProviderException(
        message: 'Kachel ${tile.key()} nicht im Speicher ($region/${layer.name})',
        retryable: Retryable.none,
        statusCode: 404,
      );
    }
    return unpackStoredTile(bytes);
  }

  /// Der Speicher gehört der App, nicht der Quelle — nichts zu schließen.
  @override
  Future<void> close() async {}

  @override
  int get minimumZoom => _minZoom;

  @override
  int get maximumZoom => _maxZoom;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;
}

/// Die Höhenkacheln einer Region aus dem Speicher, einmal entpackt und
/// gemerkt — wie `ArchiveHeightSource` für ein Archiv.
class StoreHeightSource implements HeightTileSource {
  StoreHeightSource(this._store, this.region);

  final TileStore _store;
  final String region;
  final _cache = <int, HeightTile?>{};

  @override
  Future<HeightTile?> tile(int x, int y) async {
    final key = (x << kHeightTileZoom) | y;
    if (_cache.containsKey(key)) return _cache[key];
    HeightTile? out;
    final bytes = await _store.read(region, TileLayer.heights, kHeightTileZoom, x, y);
    if (bytes != null) {
      try {
        out = HeightTile.decode(unpackStoredTile(bytes));
      } on FormatException {
        // Eine Kachel, die sich nicht lesen lässt, ist keine Kachel — der
        // Abnehmer sagt dann „keine Höhen", statt eine Zahl zu erfinden.
        out = null;
      }
    }
    return _cache[key] = out;
  }

  @override
  Future<void> close() async {}
}
