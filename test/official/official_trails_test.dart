// Offizielle Trails (#13): das Format des Daten-Branches lesen.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:trailbuddy/features/official/official_trails.dart';
import 'package:trailbuddy/features/official/official_trails_layer.dart';

import '../fakes/fake_official_trails.dart';
import '../fakes/l10n_de.dart';

void main() {
  // Die App lädt die Datumsdaten über die Material-Delegates; ein Test
  // ohne Widget-Baum muss es selbst tun (`formatIsoDate`).
  setUpAll(() => initializeDateFormatting('de'));

  test('Index: Region mit Rahmen, Stand und Quelle', () {
    final i = OfficialIndex.parse(fakeIndex());
    final r = i.regions.single;
    expect(r.file, 'testland.geojson');
    expect(r.updated, '2026-09-01');
    expect((r.south, r.west, r.north, r.east), (47.9, 8.9, 48.1, 9.1));
    expect(i.sources['testland']!.attribution, 'Land Testland');
    expect(i.sources['testland']!.license, 'CC0 1.0');
  });

  test('Rahmen: berührt oder nicht', () {
    final r = OfficialIndex.parse(fakeIndex()).regions.single;
    expect(r.touches(48.0, 9.0, 48.01, 9.01), isTrue, reason: 'innen');
    expect(r.touches(47.0, 8.0, 48.0, 9.0), isTrue, reason: 'überlappt die Ecke');
    expect(r.touches(46.0, 8.0, 47.0, 9.0), isFalse, reason: 'südlich davon');
    expect(r.touches(48.0, 10.0, 48.1, 11.0), isFalse, reason: 'östlich davon');
  });

  test('Index: fremde Formatversion und Pfade im Dateinamen werden abgelehnt', () {
    final j = jsonDecode(fakeIndex()) as Map<String, dynamic>;
    expect(() => OfficialIndex.parse(jsonEncode({...j, 'version': 2})),
        throwsFormatException);
    final regions = j['regions'] as List;
    (regions.single as Map)['file'] = '../shared_prefs.geojson';
    expect(() => OfficialIndex.parse(jsonEncode(j)), throwsFormatException);
  });

  test('Region: Teile mit Status, Werte der Quelle, Kaputtes fällt weg', () {
    final trails = parseOfficialRegion(fakeRegion());
    final t = trails.single;
    expect(t.id, 'testland:1');
    expect(t.name, 'Flowline');
    expect(t.difficulty, 'mittelschwierig');
    expect(t.status, OfficialStatus.partlyClosed);
    expect(t.lengthM, 1234);
    expect((t.upM, t.downM), (10, 180));
    expect(t.sections, hasLength(2));
    expect(t.sections[0].closed, isFalse);
    expect(t.sections[1].variant, isTrue);
    expect(t.sections[1].closed, isTrue);
    // GeoJSON ist [Länge, Breite].
    expect(t.sections[0].points.first.latitude, 48.003);
    expect(t.sections[0].points.first.longitude, 9.002);
  });

  test('Region ohne ein lesbares Feature ist kaputt', () {
    final j = jsonDecode(fakeRegion()) as Map<String, dynamic>;
    j['features'] = [(j['features'] as List).last];
    expect(() => parseOfficialRegion(jsonEncode(j)), throwsFormatException);
  });

  test('Status und Datum sagen, von wem sie kommen', () {
    expect(officialStatusLine(l10nDe, OfficialStatus.closed, 'Land Tirol'),
        'Gesperrt laut Land Tirol.');
    expect(officialStatusLine(l10nDe, OfficialStatus.open, 'Land Tirol'),
        'Freigegeben laut Land Tirol.');
    expect(formatIsoDate(l10nDe, '2026-05-19'), '19.05.2026');
    expect(formatIsoDate(l10nDe, 'Mai'), 'Mai');
  });
}
