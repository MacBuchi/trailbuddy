// Punkte, Länge, Verdünnung und die Brücke zwischen den Isolaten (#28).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_task_handler.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';

void main() {
  final at = DateTime.utc(2026, 9, 28, 10, 0, 5);

  test('ein Punkt überlebt JSON, ohne Höhe bleibt die Höhe null', () {
    final p = RidePoint(lat: 47.25, lng: 11.4, at: at, accuracyM: 4.5, altM: 812.3);
    final back = RidePoint.fromJson(p.toJson())!;
    expect((back.lat, back.lng, back.at, back.accuracyM, back.altM),
        (47.25, 11.4, at, 4.5, 812.3));
    final flat = RidePoint.fromJson({'lat': 47.0, 'lng': 11.0, 'at': at.toIso8601String()})!;
    expect(flat.altM, isNull);
    expect(flat.accuracyM, double.infinity, reason: 'fehlend heißt unbrauchbar, nicht perfekt');
    expect(RidePoint.fromJson({'lat': 91.0, 'lng': 11.0, 'at': at.toIso8601String()}), isNull);
    expect(RidePoint.fromJson({'lat': 47.0, 'lng': 11.0}), isNull);
  });

  test('der Takt-Text trägt alles, mit und ohne Höhe', () {
    final p = RidePoint(lat: 47.25, lng: 11.4, at: at, accuracyM: 4.5, altM: 812.3);
    final back = decodeRideTick(encodeRideTick(p))!;
    expect((back.lat, back.lng, back.at, back.accuracyM, back.altM),
        (47.25, 11.4, at, 4.5, 812.3));
    final noAlt = RidePoint(lat: 47.25, lng: 11.4, at: at, accuracyM: 4.5);
    expect(decodeRideTick(encodeRideTick(noAlt))!.altM, isNull);
    expect(decodeRideTick('47;11;kaputt;5;'), isNull);
    expect(decodeRideTick(42), isNull);
  });

  test('Länge und Dauer einer Fahrt', () {
    // 10 Punkte nach Norden, je 100 m.
    final pts = [
      for (var i = 0; i < 10; i++)
        RidePoint(lat: 47 + i * 100 / 111195.0, lng: 11, at: at.add(Duration(seconds: i * 20)),
            accuracyM: 5),
    ];
    expect(rideLengthM(pts), closeTo(900, 1));
    final ride = Ride(id: 'x', startedAt: at, endedAt: at.add(const Duration(minutes: 72)),
        points: pts);
    expect(ride.lengthM, closeTo(900, 1));
    expect(rideDurationLabel(ride.duration), '1 h 12 min');
    expect(rideDurationLabel(const Duration(minutes: 9)), '9 min');
    expect(rideLengthM(const []), 0);
  });

  test('verdünnt auf höchstens 500 Punkte, der letzte bleibt immer', () {
    final pts = [
      for (var i = 0; i < 2101; i++)
        RidePoint(lat: 47 + i / 1e4, lng: 11, at: at.add(Duration(seconds: i * 5)), accuracyM: 5),
    ];
    final thin = thinnedRide(pts);
    expect(thin.length, lessThanOrEqualTo(kRideTrackMaxDots + 1));
    expect(thin.first, pts.first);
    expect(thin.last, pts.last);
    expect(thinnedRide(pts.take(10).toList()), hasLength(10));
  });

  test('eine Marke (#105) überlebt JSON und ist kein Punkt', () {
    final mark = RideMark(kind: RideMarkKind.end, at: DateTime.utc(2026, 9, 30, 12, 1, 2));
    final json = jsonDecode(jsonEncode(mark.toJson())) as Map<String, dynamic>;
    expect(RideMark.isMark(json), isTrue);
    expect(RidePoint.fromJson(json), isNull);
    final back = RideMark.fromJson(json)!;
    expect(back.kind, RideMarkKind.end);
    expect(back.at, mark.at);
    expect(RideMark.fromJson({'mark': 'middle', 'at': '2026-09-30T12:00:00Z'}), isNull);
    expect(markedTrailOpen(const []), isFalse);
    expect(markedTrailOpen([RideMark(kind: RideMarkKind.start, at: mark.at)]), isTrue);
    expect(markedTrailOpen([RideMark(kind: RideMarkKind.start, at: mark.at), mark]), isFalse);
  });

  group('Nachträge zum Ende (#486)', () {
    final t0 = DateTime.utc(2026, 11, 7, 10);
    RideMark m(RideMarkKind kind, int s, [String? name]) =>
        RideMark(kind: kind, at: t0.add(Duration(seconds: s)), name: name);

    test('der Name überlebt JSON, ein leerer Name ist keiner', () {
      final label = m(RideMarkKind.label, 60, 'Hexenstieg');
      final back = RideMark.fromJson(jsonDecode(jsonEncode(label.toJson())) as Map<String, dynamic>)!;
      expect(back.kind, RideMarkKind.label);
      expect(back.name, 'Hexenstieg');
      expect(RideMark.fromJson({'mark': 'label', 'at': '2026-11-07T10:00:00Z', 'name': '  '}), isNull);
      expect(m(RideMarkKind.start, 0).toJson().containsKey('name'), isFalse);
    });

    test('ein Name gilt dem Ende mit derselben Zeit, der letzte gewinnt', () {
      final folded = foldRideMarks([
        m(RideMarkKind.start, 0),
        m(RideMarkKind.end, 60),
        m(RideMarkKind.label, 60, 'Erst'),
        m(RideMarkKind.label, 60, 'Hexenstieg'),
        m(RideMarkKind.label, 30, 'Ohne Ende'),
      ]);
      expect([for (final x in folded) x.kind], [RideMarkKind.start, RideMarkKind.end]);
      expect(folded.last.name, 'Hexenstieg');
      expect(foldRideMarks(folded).last.name, 'Hexenstieg', reason: 'ein zweiter Lauf ändert nichts');
    });

    test('Verwerfen nimmt Ende UND Beginn zurück, sonst nichts', () {
      final marks = [
        m(RideMarkKind.start, 0),
        m(RideMarkKind.end, 60, 'Erster'),
        m(RideMarkKind.start, 100),
        m(RideMarkKind.end, 120),
        m(RideMarkKind.discard, 120),
      ];
      final folded = foldRideMarks(marks);
      expect([for (final x in folded) x.at], [t0, t0.add(const Duration(seconds: 60))]);
      expect(markedTrailOpen(marks), isFalse, reason: 'der Knopf zeigt wieder „Trail beginnt"');
      expect(foldRideMarks([...marks, m(RideMarkKind.discard, 500)]), hasLength(2),
          reason: 'ein Verwerfen ohne sein Ende zählt nicht');
    });
  });
}
