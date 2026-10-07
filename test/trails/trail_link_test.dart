// Der Link zur Quelle (#103): was die Datenbank annimmt, was aus einer
// GPX-Datei vorgeschlagen wird, und was die App davon zeigt.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/idn.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/trail_link.dart';
import 'package:trailbuddy/models/trail.dart';

void main() {
  test('sanitizeLink: https, ohne Query und Fragment, sonst null', () {
    expect(sanitizeLink('https://www.Verein.example/strecken?share=abc123#karte'),
        'https://www.verein.example/strecken');
    expect(sanitizeLink('  verein.example/trails  '), 'https://verein.example/trails',
        reason: 'ohne Schema wird https angenommen');
    expect(sanitizeLink('http://verein.example'), isNull, reason: 'nur https');
    expect(sanitizeLink('https://user:pw@verein.example'), isNull);
    expect(sanitizeLink('https://verein.example/mit leerzeichen'), isNull);
    expect(sanitizeLink('mailto:a@b.example'), isNull);
    expect(sanitizeLink('https://verein.example/${'a' * 500}'), isNull, reason: 'höchstens 500 Zeichen');
    expect(sanitizeLink(''), isNull);
    expect(sanitizeLink(null), isNull);
  });

  test('linkFromFile: Gerätehersteller und Tourenportale fallen weg', () {
    expect(linkFromFile('https://www.garmin.com'), isNull);
    expect(linkFromFile('https://connect.garmin.com/modern/activity/1'), isNull);
    expect(linkFromFile('https://www.strava.com/activities/123'), isNull);
    expect(linkFromFile('https://verein.example/strecken'), 'https://verein.example/strecken');
  });

  test('linkHost zeigt den Host ohne www', () {
    expect(linkHost('https://www.verein.example/strecken/1'), 'verein.example');
    expect(linkHost('https://trails.verein.example'), 'trails.verein.example');
  });

  group('Umlaute (#223)', () {
    test('Punycode wie RFC 3492 und der Browser', () {
      expect(hostToAscii('bücher.example'), 'xn--bcher-kva.example');
      expect(hostToAscii('MÜNCHEN.example'), 'xn--mnchen-3ya.example', reason: 'klein geschrieben');
      expect(hostToAscii('verein.example'), 'verein.example');
      expect(hostToUnicode('xn--bcher-kva.example'), 'bücher.example');
      expect(hostToUnicode('xn--mnchen-3ya.example'), 'münchen.example');
      expect(hostToUnicode('xn--!!.example'), 'xn--!!.example', reason: 'kaputt bleibt, wie es ist');
      for (final h in ['straße-trails.example', 'öko.ärger.example', 'ñandú.example']) {
        expect(hostToUnicode(hostToAscii(h)), h);
      }
    });

    test('gespeichert wird die Form des Browsers: Host in Punycode, Pfad kodiert', () {
      expect(sanitizeLink('https://www.Mühle-Trails.example/Strecken/Bärental?x=1'),
          'https://www.xn--mhle-trails-thb.example/Strecken/B%C3%A4rental');
      expect(sanitizeLink('mühle.example'), 'https://xn--mhle-0ra.example');
      expect(sanitizeLink('https://xn--mhle-0ra.example/a'), 'https://xn--mhle-0ra.example/a');
    });

    test('gezeigt wird, was die Adresszeile zeigt', () {
      const stored = 'https://www.xn--mhle-trails-thb.example/Strecken/B%C3%A4rental';
      expect(linkHost(stored), 'mühle-trails.example');
      expect(linkForDisplay(stored), 'https://www.mühle-trails.example/Strecken/Bärental');
      expect(sanitizeLink(linkForDisplay(stored)), stored, reason: 'das Feld speichert unverändert zurück');
      expect(linkHost('https://m%C3%BChle.example/'), 'mühle.example',
          reason: 'alte Zeilen mit prozentkodiertem Host');
      expect(linkForDisplay('https://verein.example/a%20b%2Fc'), 'https://verein.example/a%20b%2Fc',
          reason: 'ASCII-Escapes bleiben');
      expect(linkForDisplay('https://verein.example/%FF'), 'https://verein.example/%FF');
    });
  });

  group('GPX', () {
    String file({String meta = '', String trk = ''}) =>
        '<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">'
        '<metadata>$meta</metadata><trk><name>T</name>$trk<trkseg>'
        '<trkpt lat="48.0" lon="9.0"/><trkpt lat="48.01" lon="9.0"/></trkseg></trk></gpx>';

    test('der Link der Spur gewinnt, ohne Query', () {
      final t = parseGpx(file(
              meta: '<link href="https://verein.example/"/>',
              trk: '<link href="https://verein.example/trail?token=geheim"><text>Seite</text></link>'))
          .single;
      expect(t.link, 'https://verein.example/trail');
    });

    test('sonst der aus metadata — aber nicht der Hersteller', () {
      expect(parseGpx(file(meta: '<link href="https://verein.example/"/>')).single.link,
          'https://verein.example/');
      expect(parseGpx(file(meta: '<link href="http://www.garmin.com"><text>Garmin</text></link>'))
          .single.link, isNull);
      expect(parseGpx(file()).single.link, isNull);
    });
  });

  test('der Beitrag trägt den Link; angezeigt wird der eigene, sonst der älteste', () {
    final row = {
      'trail_id': 't',
      'user_id': 'bob',
      'link': 'https://verein.example/roots',
    };
    final d = TrailDetails.fromJson(row);
    expect(d.link, 'https://verein.example/roots');
    expect(d.toRow()['link'], 'https://verein.example/roots');
    expect(d.copyWith(clearLink: true).link, isNull);
    expect(d.copyWith(name: 'x').link, d.link, reason: 'copyWith behält ihn');
  });
}
