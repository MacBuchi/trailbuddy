import 'dart:io';
import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'seen_tiles.dart' show SeenTile;

/// Eine Kachelquelle, die man schließt, wenn ihre Schicht geht — ein
/// Archiv (Dateihandle) oder der Kachelspeicher der Bereiche (#229).
abstract class ClosableVectorTileProvider extends VectorTileProvider {
  Future<void> close();
}

/// Liefert Vector-Tiles aus einem PMTiles-Archiv an vector_map_tiles
/// (PilzBuddy-Adapter; das fertige Paket vector_map_tiles_pmtiles kann
/// flutter_map 8 noch nicht).
class PmTilesVectorTileProvider extends ClosableVectorTileProvider {
  PmTilesVectorTileProvider._(this._archive, this._minZoom, this._maxZoom);

  final PmTilesArchive _archive;
  final int _minZoom;
  final int _maxZoom;

  /// Aus einer Datei — der Weg auf dem Telefon. `FileAt` liest faul über
  /// einen Pool von Handles; das Archiv liegt nie ganz im Speicher.
  static Future<PmTilesVectorTileProvider> open(String path) async {
    final archive = await PmTilesArchive.fromFile(File(path));
    return PmTilesVectorTileProvider._(
        archive, archive.header.minZoom, archive.header.maxZoom);
  }

  /// Aus Bytes — der Weg im Browser. Dort gibt es die Wahl nicht:
  /// `pmtiles` exportiert für JS eine `FileAt`, die beim Anlegen
  /// `UnsupportedError` wirft; `MemoryAt` ist reines Dart. Der Preis ist,
  /// dass das Archiv im Speicher bleibt — vertretbar für die Übersicht
  /// (8,6 MB), nicht für einen gespeicherten Bereich.
  static Future<PmTilesVectorTileProvider> openBytes(Uint8List bytes) async {
    final archive = await PmTilesArchive.fromBytes(bytes);
    return PmTilesVectorTileProvider._(
        archive, archive.header.minZoom, archive.header.maxZoom);
  }

  /// Über das Netz, kachelweise per Range-Anfrage — der Online-Weg beider
  /// Plattformen (#31). Das Archiv wird nie ganz geladen: Header und
  /// Verzeichnisse einmal, danach je Kachel ein Bereich. Der Host muss
  /// dafür 206 und CORS liefern; `map-data.yml` prüft genau das nach
  /// jedem Upload.
  static Future<PmTilesVectorTileProvider> openUri(Uri uri) async {
    final archive = await PmTilesArchive.fromUri(uri);
    return PmTilesVectorTileProvider._(
        archive, archive.header.minZoom, archive.header.maxZoom);
  }

  /// Gibt das Dateihandle frei — beim Neuaufbau aufrufen, sonst leaken
  /// Handles.
  @override
  Future<void> close() => _archive.close();

  @override
  Future<Uint8List> provide(TileIdentity tile) => _guarded(tile, () async {
        final t = await _archive.tile(ZXY(tile.z, tile.x, tile.y).toTileId());
        return Uint8List.fromList(t.bytes());
      });

  /// Die Kachel, wie sie im Archiv liegt — für den Speicher gesehener
  /// Kacheln im Browser (#155), der komprimiert ablegt. Eine Kompression
  /// außer gzip wird gleich ausgepackt (Protomaps schreibt gzip).
  Future<SeenTile> rawTile(TileIdentity tile) => _guarded(tile, () async {
        final t = await _archive.tile(ZXY(tile.z, tile.x, tile.y).toTileId());
        return switch (t.compression) {
          Compression.gzip => SeenTile(Uint8List.fromList(t.compressedBytes()), gzip: true),
          Compression.none => SeenTile(Uint8List.fromList(t.compressedBytes()), gzip: false),
          _ => SeenTile(Uint8List.fromList(t.bytes()), gzip: false),
        };
      });

  Future<T> _guarded<T>(TileIdentity tile, Future<T> Function() read) async {
    try {
      return await read();
    } on TileNotFoundException {
      throw ProviderException(
        message: 'Tile ${tile.key()} nicht im Archiv',
        retryable: Retryable.none,
        statusCode: 404,
      );
    } on StateError catch (e) {
      // Das Archiv ist geschlossen — gefragt wird eine ältere Generation
      // der Quelle, die ein Layer noch in seinen Caches hält (PilzBuddy
      // #144). Als ProviderException degradiert es zu „Kachel fehlt"
      // statt zu einer Zeile je Kachel in `error_reports`.
      throw ProviderException(
        message: 'Archiv bereits geschlossen (${tile.key()}): $e',
        retryable: Retryable.none,
        statusCode: 410,
      );
    }
  }

  @override
  int get minimumZoom => _minZoom;

  @override
  int get maximumZoom => _maxZoom;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;
}
