import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/gpx.dart';

const _locus = '''<?xml version="1.0" encoding="utf-8"?>
<gpx version="1.1" creator="Locus Map, Android"
 xmlns="http://www.topografix.com/GPX/1/1"
 xmlns:locus="http://www.locusmap.eu">
<trk><name>Wurzeltrail</name>
<trkseg>
<trkpt lat="48.0000" lon="9.0000"><ele>500</ele><time>2026-01-01T10:00:00Z</time></trkpt>
<trkpt lat="48.0000" lon="9.0000"><ele>500</ele><time>2026-01-01T10:00:05Z</time></trkpt>
<trkpt lat="48.0010" lon="9.0000"><ele>490</ele><time>2026-01-01T10:00:30Z</time></trkpt>
</trkseg>
<trkseg>
<trkpt lat="48.0020" lon="9.0000"><ele>480</ele><time>2026-01-01T10:01:00Z</time></trkpt>
</trkseg>
</trk>
<rte><name>Geplant</name>
<rtept lat="48.1" lon="9.1"/><rtept lat="48.2" lon="9.2"/>
</rte>
</gpx>''';

void main() {
  test(
    'liest Tracks und Routen, ignoriert Namensräume, dünnt Doppelpunkte',
    () {
      final tracks = parseGpx(_locus);
      expect(tracks.map((t) => t.name), ['Wurzeltrail', 'Geplant']);
      final trail = tracks.first;
      // Der doppelte Pausenpunkt fällt weg, beide Segmente hängen aneinander.
      expect(trail.points.length, 3);
      expect(trail.points.first.ele, 500);
      expect(trail.points.first.time, DateTime.utc(2026, 1, 1, 10));
      final route = tracks.last;
      expect(route.points.length, 2);
      expect(route.points.first.ele, isNull);
      expect(route.points.first.time, isNull);
    },
  );

  test(
    'Spuren mit einem Punkt fallen weg, fehlender Name bekommt den Ersatz',
    () {
      const xml =
          '<gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>'
          '<trkpt lat="48" lon="9"/></trkseg></trk>'
          '<trk><trkseg><trkpt lat="48" lon="9"/><trkpt lat="48.001" lon="9"/>'
          '</trkseg></trk></gpx>';
      final tracks = parseGpx(xml, fallbackName: 'datei.gpx');
      expect(tracks.length, 1);
      expect(tracks.single.name, 'datei.gpx');
    },
  );

  test('kein XML und falsche Wurzel werden benannt, nicht geschluckt', () {
    expect(() => parseGpx('<<<'), throwsA(isA<GpxFormatException>()));
    expect(() => parseGpx('<kml/>'), throwsA(isA<GpxFormatException>()));
  });

  test('URL-kodierte Namen werden dekodiert, echte Prozentzeichen bleiben', () {
    expect(
      decodeTrackName('DREI%20EICHEN%20-%20Sponsored'),
      'DREI EICHEN - Sponsored',
    );
    expect(decodeTrackName('Tr%C3%A4umerle'), 'Träumerle');
    expect(decodeTrackName('100 % Flow'), '100 % Flow');
    expect(
      decodeTrackName('kaputt %E2%28 Ende'),
      'kaputt %E2%28 Ende',
      reason: 'kein gültiges UTF-8: lieber roh als falsch',
    );
  });
}
