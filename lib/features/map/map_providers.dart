/// Der Kartenhost (#31, Schritt 2 in `docs/konzept-offline-karten.md`):
/// EIN PMTiles-Archiv von DACH (Protomaps-Basiskarte, Zoom 0–13, ODbL)
/// auf Cloudflare R2 hinter `tiles.mcbuchi.de`, geschnitten und geprüft
/// von `.github/workflows/map-data.yml`. Beide Engines lesen kachelweise
/// per Range-Anfrage daraus; OSM-Rasterkacheln gibt es nicht mehr.
///
/// Bewusst Konstanten und keine Konfiguration: Die Adresse ist öffentlich,
/// steht in der Datenschutzerklärung, und `test/privacy_policy_test.dart`
/// liest sie von hier.
const kMapTilesBase = 'https://tiles.mcbuchi.de/trailbuddy';

/// Das Manifest nennt die AKTUELLE Archivdatei (`dach-<build>.pmtiles`).
/// Der Umweg ist Absicht: Eine Sitzung merkt sich die Verzeichnisse des
/// Archivs, und ein Archiv, das unter ihr überschrieben würde, ließe diese
/// Versätze in eine andere Datei zeigen. Dateien mit Datum im Namen sind
/// unveränderlich; nur der Zeiger wechselt.
const kMapManifestUrl = '$kMapTilesBase/dach.json';

/// Das Manifest der Orte (`pois.json`, geschrieben von `poi-data.yml`):
/// welcher Bau gerade gilt (`pois-<build>/`) und welche Rasterzellen je
/// Gruppe eine Datei haben. Dieselbe Zeiger-Idee wie beim Archiv — die
/// Dateien eines Baus sind unveränderlich, nur der Zeiger wechselt.
const kPoiManifestUrl = '$kMapTilesBase/pois.json';

/// Das Manifest der Höhenkacheln (`heights.json`, geschrieben von
/// `height-data.yml`): welches Archiv `heights-<build>.pmtiles` gerade
/// gilt. Dieselbe Zeiger-Idee; die Kacheln kommen mit einem Bereich
/// (`lib/features/offline_areas/height_tiles.dart`).
const kHeightsManifestUrl = '$kMapTilesBase/heights.json';

/// Das Manifest des Wege-Archivs (`ways.json`, geschrieben von
/// `way-data.yml`, #212): welches `ways-<build>.pmtiles` gilt. Dieselbe
/// Zeiger-Idee; gelesen in `way_layer.dart`.
const kWaysManifestUrl = '$kMapTilesBase/ways.json';
