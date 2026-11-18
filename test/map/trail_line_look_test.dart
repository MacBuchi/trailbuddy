// Glattere Linien und Namen entlang der Linie (Betreiber, 2026-09-29):
// Glättung nur fürs Bild, runde Ecken in MapLibre, Namen als Symbol-Ebene
// entlang der Linie, in flutter_map einmal in der Mitte, nie kopfüber.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:trailbuddy/features/map/line_smoothing.dart';
import 'package:trailbuddy/features/map/map_view/line_labels.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_map_view.dart';

void main() {
  group('Glättung', () {
    const kink = [LatLng(48, 9), LatLng(48.001, 9), LatLng(48.001, 9.001)];

    test('Anfang und Ende bleiben, die Ecke wird abgeschnitten', () {
      final s = chaikinSmooth(kink);
      expect(s.first, kink.first);
      expect(s.last, kink.last);
      expect(s.length, greaterThan(kink.length));
      expect(s, isNot(contains(kink[1])), reason: 'die spitze Ecke ist weg');
    });

    test(
      'bleibt nah an der Linie: höchstens ein Viertel des Abschnitts neben der Ecke',
      () {
        final s = chaikinSmooth(kink);
        const d = Distance();
        final corner = kink[1];
        final nearest = s
            .map((p) => d.as(LengthUnit.Meter, p, corner))
            .reduce(math.min);
        final seg = d.as(LengthUnit.Meter, kink[0], kink[1]);
        expect(nearest, lessThan(seg / 4));
      },
    );

    test(
      'nur echte Ecken: ein leichter Knick bleibt ein Punkt (kostet sonst Übertragung)',
      () {
        // ~5° Knick über 100-m-Abschnitte.
        const slight = [
          LatLng(48, 9),
          LatLng(48 + 0.0009, 9),
          LatLng(48 + 0.0018, 9 + 0.00011),
        ];
        expect(chaikinSmooth(slight), slight);
      },
    );

    test('eine Gerade bleibt gerade, zwei Punkte bleiben zwei', () {
      final line = [
        const LatLng(48, 9),
        const LatLng(48.001, 9),
        const LatLng(48.002, 9),
      ];
      expect(chaikinSmooth(line).every((p) => p.longitude == 9), isTrue);
      expect(chaikinSmooth(line.sublist(0, 2)), hasLength(2));
    });
  });

  group('Name in flutter_map', () {
    test('in der Mitte nach Länge, waagerecht gelesen', () {
      final a = lineLabelAnchor(const [LatLng(48, 9), LatLng(48, 9.01)])!;
      expect(a.point.longitude, closeTo(9.005, 1e-9));
      expect(a.angle, closeTo(0, 1e-9));
    });

    test(
      'nie auf dem Kopf: eine Linie nach Westen liest sich wie eine nach Osten',
      () {
        final west = lineLabelAnchor(const [LatLng(48, 9.01), LatLng(48, 9)])!;
        expect(west.angle.abs(), lessThan(1e-9));
        final north = lineLabelAnchor(const [LatLng(48, 9), LatLng(48.01, 9)])!;
        expect(north.angle, closeTo(-math.pi / 2, 1e-6));
        for (final a in [west.angle, north.angle]) {
          expect(a, inInclusiveRange(-math.pi / 2, math.pi / 2));
        }
      },
    );
  });

  test('MapLibre: ein Neuaufbau mit denselben Linien überträgt nichts neu', () {
    final pts = [const LatLng(48, 9), const LatLng(48.01, 9)];
    final other = [const LatLng(48, 9.1), const LatLng(48.01, 9.1)];
    List<MapViewPolyline> build(List<LatLng> b) => [
      MapViewPolyline(points: pts, color: const Color(0xFF1F6FD1), label: 'A'),
      MapViewPolyline(points: b, color: const Color(0xFFC62828), label: 'B'),
    ];
    final cache = MapLibreLineCache();
    final first = mapLibrePolylineLayers(build(other), cache);
    // Neue Polyline-Objekte wie bei jedem Aufbau des Screens, dieselben Punktlisten.
    final again = mapLibrePolylineLayers(build(other), cache);
    for (var i = 0; i < first.length; i++) {
      expect(identical(again[i], first[i]), isTrue, reason: 'Ebene $i');
      expect(
        again[i] == first[i],
        isTrue,
        reason: 'MapLibre vergleicht mit ==',
      );
    }
    // Ändert sich eine Linie, wird genau ihre Gruppe (und das Fach ihrer
    // Namen) neu gebaut.
    final changed = mapLibrePolylineLayers(build([...other]), cache);
    expect(
      identical(changed.first, first.first),
      isTrue,
      reason: 'blaue Gruppe unverändert',
    );
    expect(
      identical(changed[1], first[1]),
      isFalse,
      reason: 'rote Gruppe hat eine neue Liste',
    );
    LineLabelLayer labelsOf(List<ml.Layer> layers, String name) => layers
        .whereType<LineLabelLayer>()
        .firstWhere((l) => l.list.any((f) => f.properties['label'] == name));
    expect(
      identical(labelsOf(changed, 'B'), labelsOf(first, 'B')),
      isFalse,
      reason: 'die Namen tragen die neue Linie',
    );
    if (lineBucketOf(pts) != lineBucketOf(other)) {
      expect(
        identical(labelsOf(changed, 'A'), labelsOf(first, 'A')),
        isTrue,
        reason: 'das Fach der anderen Namen bleibt',
      );
    }
  });

  test(
    'MapLibre: runde Ecken, Namen als Symbol-Ebene entlang der Linie, darüber, ab Zoom 14',
    () {
      final layers = mapLibrePolylineLayers([
        const MapViewPolyline(
          points: [LatLng(48, 9), LatLng(48.01, 9)],
          color: Color(0xFF1F6FD1),
          label: 'Hexentanz',
        ),
        const MapViewPolyline(
          points: [LatLng(48, 9.1), LatLng(48.01, 9.1)],
          color: Color(0xFF1F6FD1),
        ),
      ]);
      final lines = layers.whereType<ml.PolylineLayer>().toList();
      expect(lines, isNotEmpty);
      for (final l in lines) {
        expect(l.getLayout(), containsPair('line-join', 'round'));
        expect(l.getLayout(), containsPair('line-cap', 'round'));
      }
      final label = layers.last as LineLabelLayer;
      expect(label.list, hasLength(1), reason: 'nur Linien mit Namen');
      expect(label.list.single.properties['label'], 'Hexentanz');
      expect(label.getLayout(), containsPair('symbol-placement', 'line'));
      expect(label.getLayout()['text-field'], '{label}');
      // Auf der Mittellinie, nicht daneben (#181): kein Versatz.
      expect(label.getLayout().containsKey('text-offset'), isFalse);
      // Auf der Linie trägt der Saum die Lesbarkeit: breiter als die
      // 1,5 px von vorher, nie über dem, was MapLibre zeichnet (¼ der Schrift).
      expect(label.getPaint()['text-halo-width'], kLineLabelHaloWidth);
      expect(kLineLabelHaloWidth, greaterThan(1.5));
      expect(
        kLineLabelHaloWidth,
        lessThanOrEqualTo((label.getLayout()['text-size']! as num) / 4),
      );
      // Der Stack muss als Glyphen-Ordner im Paket liegen — sonst lässt
      // MapLibre den Namen still weg.
      for (final stack in label.getLayout()['text-font']! as List) {
        expect(
          Directory('assets/map_glyphs/$stack').existsSync(),
          isTrue,
          reason: '$stack',
        );
      }
      // 512er-Zählung der Engine: eins weniger als die Fassade.
      expect(label.minZoom, kLineLabelMinZoom - 1);
    },
  );
}
