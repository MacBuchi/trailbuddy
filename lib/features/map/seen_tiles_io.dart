import 'seen_tiles.dart';

/// Auf Android behält MapLibres Ambient Cache, was gesehen wurde
/// (`online_map.dart`, [kSeenTilesCacheBytes]) — hier kein zweiter
/// Speicher, und der flutter_map-Rückfall bleibt, wie er war. Im Test
/// (VM) ebenso; wer den Browser-Weg prüft, überschreibt den Provider.
SeenTileStore? createSeenTileStore() => null;
