// Was der Browser an Ablage hergibt — IndexedDB und die Zusage, sie nicht
// von sich aus zu räumen (#153; PilzBuddy `idb_factory.dart` und
// `browser_storage.dart`). Der Web-Weg ist die Vorgabe, `dart.library.io`
// wählt den Stub: So sieht der Android-Build `idb_browser.dart` und
// `package:web` nie.
export 'browser_storage_web.dart' if (dart.library.io) 'browser_storage_io.dart';
