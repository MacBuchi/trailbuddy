import 'package:idb_shim/idb_browser.dart';

import 'tile_store.dart';
import 'tile_store_idb.dart';

/// Der Browser-Speicher — dieselbe Wahl wie bei der Ablage der Bereiche
/// (`area_store_web.dart`). Eigene Datei, weil `idb_browser.dart` nur im
/// Web kompiliert; `IdbTileStore` selbst läuft im Test auf der VM.
TileStore createTileStore() => IdbTileStore(idbFactoryBrowser);
