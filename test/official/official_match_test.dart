// „Auch ausgeschildert als …" (#13, Schritt 4): Deckung wie im Abgleich,
// Korridor 15 m, Anteil 0,8 — an ausgedachten Linien in Metern.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/official/official_match.dart';
import 'package:trailbuddy/features/official/official_signposts.dart';
import 'package:trailbuddy/features/official/official_trails.dart';

/// Meter östlich/nördlich eines ausgedachten Nullpunkts.
LatLng _at(double x, double y) => LatLng(48 + y / 111195.0,
    9 + x / (111195.0 * math.cos(48 * math.pi / 180)));

/// Eine Gerade von (x0, y) nach (x1, y), alle 20 m ein Punkt.
List<LatLng> _line(double x0, double x1, {double y = 0}) => [
      for (var x = x0; x <= x1 + 1e-9; x += 20) _at(x, y),
    ];

OfficialTrail _official(List<List<LatLng>> parts,
        {List<bool>? variants, List<bool>? closed, String? updated}) =>
    OfficialTrail(
      id: 'test:1',
      name: 'Amtlich',
      sourceId: 'test',
      status: closed == null || !closed.contains(true)
          ? OfficialStatus.open
          : closed.every((c) => c)
              ? OfficialStatus.closed
              : OfficialStatus.partlyClosed,
      updated: updated,
      sections: [
        for (var i = 0; i < parts.length; i++)
          OfficialSection(
              points: parts[i],
              variant: variants?[i] ?? false,
              closed: closed?[i] ?? false),
      ],
    );

OfficialMatch _match(List<LatLng> net, OfficialTrail t) => matchOfficial(net, [t]).single;

OfficialOverlap? _overlap(List<LatLng> net, OfficialTrail t) =>
    matchOfficial(net, [t]).map((m) => m.overlap).firstOrNull;

void main() {
  test('dieselbe Linie, 8 m daneben: derselbe Trail', () {
    expect(_overlap(_line(0, 600, y: 8), _official([_line(0, 600)])),
        OfficialOverlap.same);
  });

  test('nur ein Stück davon gefahren: Teil des offiziellen', () {
    expect(_overlap(_line(100, 400), _official([_line(0, 600)])),
        OfficialOverlap.partOf);
  });

  test('der Trail des Netzes ist länger: enthält den offiziellen', () {
    expect(_overlap(_line(0, 1200), _official([_line(300, 700)])),
        OfficialOverlap.contains);
  });

  test('parallel in 40 m: nichts', () {
    expect(_overlap(_line(0, 600, y: 40), _official([_line(0, 600)])), isNull);
  });

  test('knapp außerhalb des Korridors (20 m): nichts', () {
    expect(_overlap(_line(0, 600, y: 20), _official([_line(0, 600)])), isNull);
  });

  test('Varianten zählen nicht gegen „derselbe"', () {
    // Hauptroute 0–600, dazu eine Variante 200 m weiter nördlich.
    final t = _official([_line(0, 600), _line(0, 400, y: 200)], variants: [false, true]);
    expect(_overlap(_line(0, 600), t), OfficialOverlap.same);
    // Wer die Variante fährt, ist trotzdem auf dem offiziellen Trail.
    expect(_overlap(_line(0, 400, y: 200), t), OfficialOverlap.partOf);
  });

  test('weit weg: gar nicht erst gerechnet, und „derselbe" steht vorn', () {
    final far = OfficialTrail(
        id: 'test:far',
        name: 'Fern',
        sourceId: 'test',
        sections: [OfficialSection(points: _line(50000, 50600))]);
    final part = OfficialTrail(
        id: 'test:part',
        name: 'Teil',
        sourceId: 'test',
        sections: [OfficialSection(points: _line(-300, 900))]);
    final same = _official([_line(0, 600)]);
    final got = matchOfficial(_line(0, 600), [far, part, same]);
    expect(got.map((m) => m.trail.id), ['test:1', 'test:part']);
  });

  test('Stützpunkte weit auseinander: die Linie dazwischen zählt', () {
    // Offiziell nur Anfang und Ende — ohne Abtastung läge fast jeder
    // Punkt des Netzes „außerhalb".
    expect(_overlap(_line(0, 600), _official([[_at(0, 0), _at(600, 0)]])),
        OfficialOverlap.same);
  });

  group('Sperre der Quelle auf dem Trail (#41)', () {
    test('gesperrte Hauptroute, derselbe Trail: darauf, mit Stand', () {
      final m = _match(_line(0, 600, y: 8),
          _official([_line(0, 600)], closed: [true], updated: '2026-09-28'));
      expect(m.onClosed, isTrue);
      expect(officialClosureLine(m, 'Land Tirol'), 'gesperrt laut Land Tirol, Stand 28.09.2026');
    });

    test('gesperrte Variante liegt woanders: nicht darauf, und der Satz sagt es', () {
      final m = _match(
          _line(0, 600),
          _official([_line(0, 600), _line(0, 400, y: 200)],
              variants: [false, true], closed: [false, true]));
      expect(m.onClosed, isFalse);
      expect(officialClosureLine(m, 'Land Tirol'), 'anderer Abschnitt gesperrt laut Land Tirol');
    });

    test('gesperrte Variante liegt auf dem Trail: Abschnitt gesperrt', () {
      // Der Trail des Netzes fährt die Variante; die Hauptroute ist offen.
      final m = _match(
          _line(0, 400, y: 200),
          _official([_line(0, 600), _line(0, 400, y: 200)],
              variants: [false, true], closed: [false, true]));
      expect(m.onClosed, isTrue);
      expect(officialClosureLine(m, 'Land Tirol'), 'Abschnitt gesperrt laut Land Tirol');
    });

    test('ein gesperrtes Stück, das der Trail nur quert: nicht darauf', () {
      // Hauptroute offen entlang y = 0; gesperrte Variante quer dazu.
      final cross = [for (var y = -300.0; y <= 300; y += 20) _at(300, y)];
      final m = _match(_line(0, 600),
          _official([_line(0, 600), cross], variants: [false, true], closed: [false, true]));
      expect(m.onClosed, isFalse);
    });

    test('kurzes gesperrtes Stück (30 m) ganz auf dem Trail: darauf', () {
      final m = _match(
          _line(0, 600),
          _official([_line(0, 600), [_at(100, 0), _at(130, 0)]],
              variants: [false, true], closed: [false, true]));
      expect(m.onClosed, isTrue);
    });

    test('offen: kein Satz', () {
      expect(officialClosureLine(_match(_line(0, 600), _official([_line(0, 600)])), 'X'),
          isNull);
    });
  });
}
