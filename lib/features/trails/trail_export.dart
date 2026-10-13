// Ein Trail als GPX (#150, Konzept 13: die Brücke zu anderen Apps ist
// die Datei). Pur: Trail rein, Spur raus.
//
// Exportiert wird die ANGEZEIGTE Linie in Trail-Richtung — die beste
// Aufzeichnung (`Trail.best`) samt IHREN Höhen (`best.ele`, nicht
// `Trail.elevation`: das kann eine andere Aufzeichnung sein, deren Höhen
// an diese Punkte nicht passen). Punkte und Höhen drehen sich gemeinsam,
// wenn die beste Aufzeichnung gegen die Richtung lief.
//
// Hinein geht der Name und der EIGENE Link (`myDetails.link`, nie der
// eines Buddys); nicht hinein gehen Buddy-Namen, Hinweise, Meldungen
// und Zeiten — die Datei ist eine Linie, kein Auszug aus dem Netz.
//
// Hat die beste Aufzeichnung keine Höhen, trägt die Datei die des
// Geländemodells (#186), je Punkt und als solche markiert
// (`GpxTrack.terrainHeights` → `<extensions>`); fehlt dem Modell ein
// Punkt, bleibt sie ohne Höhen.
import '../../models/trail.dart';
import 'gpx.dart';
import 'terrain_heights.dart';

/// [terrain]: Höhen des Geländemodells für [Trail.directedPoints] — nur
/// genommen, wenn die beste Aufzeichnung selbst keine hat.
GpxTrack trailToGpx(Trail trail, {List<double>? terrain}) {
  final best = trail.best;
  final points = best.reversed ? best.points.reversed.toList() : best.points;
  final recorded = best.ele == null ? null : (best.reversed ? best.ele!.reversed.toList() : best.ele!);
  final fromTerrain = recorded == null && terrain != null && terrain.length == points.length;
  final ele = recorded ?? (fromTerrain ? terrain : null);
  return GpxTrack(
    name: trail.name ?? 'Trail',
    points: [
      for (var i = 0; i < points.length; i++)
        TrackPoint(points[i].latitude, points[i].longitude, ele: ele?[i]),
    ],
    link: trail.myDetails?.link,
    terrainHeights: fromTerrain,
  );
}

/// Die Spur für den Export, mit Geländehöhen, wo aufgezeichnete fehlen.
Future<GpxTrack> trailExportTrack(TerrainHeights terrain, Trail trail) async {
  if (trail.best.ele != null) return trailToGpx(trail);
  return trailToGpx(trail, terrain: await terrain.at(trail.directedPoints));
}
