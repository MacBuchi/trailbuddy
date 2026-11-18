// GPX schreiben (#150): Was `writeGpx` schreibt, liest `parseGpx` Feld
// für Feld zurück — mit und ohne Höhen, mit und ohne Zeiten, mit Link.
// Testdaten stehen inline; GPX-Dateien gehören nicht ins Repo. Breiten
// einstellig, damit der Private-Info-Wächter sie nicht für Orte hält.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/gpx_writer.dart';

void main() {
  test('Rundlauf mit Höhen, Zeiten und Link', () {
    final points = [
      TrackPoint(
        7.0,
        9.0,
        ele: 500.0,
        time: DateTime.utc(2026, 1, 1, 10, 0, 0),
      ),
      TrackPoint(
        7.001,
        9.0005,
        ele: 490.5,
        time: DateTime.utc(2026, 1, 1, 10, 0, 30),
      ),
      TrackPoint(
        7.002,
        9.001,
        ele: 480.0,
        time: DateTime.utc(2026, 1, 1, 10, 1, 0),
      ),
    ];
    final xml = writeGpx(
      name: 'Wurzeltrail & Co',
      points: points,
      link: 'https://www.verein.example/roots',
    );
    expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(xml, contains('creator="TrailBuddy"'));
    expect(xml, contains('xmlns="$kGpxNamespace"'));
    expect(xml, contains('<name>Wurzeltrail &amp; Co</name>'));

    final back = parseGpx(xml).single;
    expect(back.name, 'Wurzeltrail & Co');
    expect(back.link, 'https://www.verein.example/roots');
    expect(back.points.length, 3);
    for (var i = 0; i < 3; i++) {
      expect(back.points[i].lat, closeTo(points[i].lat, 1e-6));
      expect(back.points[i].lon, closeTo(points[i].lon, 1e-6));
      expect(back.points[i].ele, closeTo(points[i].ele!, 0.05));
      expect(back.points[i].time, points[i].time);
    }
  });

  test('ohne Höhen und Zeiten stehen auch keine in der Datei', () {
    final xml = writeGpx(
      name: 'Geplant',
      points: const [TrackPoint(7.0, 9.0), TrackPoint(7.01, 9.0)],
    );
    expect(xml, isNot(contains('<ele>')));
    expect(xml, isNot(contains('<time>')));
    expect(xml, isNot(contains('<link')));
    final back = parseGpx(xml).single;
    expect(back.points.map((p) => p.ele), [null, null]);
    expect(back.points.map((p) => p.time), [null, null]);
    expect(back.link, isNull);
  });

  test('Dateiname: Kleinbuchstaben, Umlaute aufgelöst, nie leer', () {
    expect(
      gpxFileName('Rosskopf Süd (Variante)'),
      'trailbuddy-rosskopf-sued-variante.gpx',
    );
    expect(gpxFileName('Äußere Höhe!'), 'trailbuddy-aeussere-hoehe.gpx');
    expect(gpxFileName('   '), 'trailbuddy-trail.gpx');
    expect(gpxFileName('x' * 90).length, lessThan(80));
  });
}
