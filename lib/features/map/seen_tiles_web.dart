import 'package:idb_shim/idb_browser.dart';

import 'seen_tiles.dart';

/// Im Browser die echte IndexedDB — bewusst nicht die Fassung, die still
/// auf den Speicher zurückfällt (Begründung in `area_store_web.dart`).
/// Eigene Datei, weil `idb_browser.dart` nur im Web kompiliert.
SeenTileStore? createSeenTileStore() => IdbSeenTileStore(idbFactoryBrowser);
