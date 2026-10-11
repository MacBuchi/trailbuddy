// „Noch gültig?" (#119), pur: wer wann nach welcher Angabe gefragt wird.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/still_valid.dart';
import 'package:trailbuddy/features/trails/trail_list.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/l10n_de.dart';
import 'trail_model_test.dart' show rec, rep;

void main() {
  final now = DateTime.utc(2026, 9, 30, 12);
  DateTime ago(int days) => now.subtract(Duration(days: days));
  Trail trail(List<TrailReport> reports, {String id = 't'}) =>
      Trail(id: id, myId: 'me', recordings: [rec(id, 'me')], details: const [], reports: reports);

  test('eigene warnende Meldung und eigener Zustand, älter als 30 Tage', () {
    final t = trail([
      rep('t', 'me', ago(45), status: TrailStatus.closed),
      rep('t', 'me', ago(40), condition: 2),
    ]);
    final qs = stillValidQuestionsOf(t, now: now);
    expect([for (final q in qs) q.kind], [ReportKind.status, ReportKind.condition]);
    expect(stillValidQuestionsOf(trail([rep('t', 'me', ago(29), status: TrailStatus.closed)]), now: now),
        isEmpty, reason: 'jünger als 30 Tage');
  });

  test('ein altes „offen" wird nicht gefragt, eine fremde Angabe nie', () {
    expect(stillValidQuestionsOf(trail([rep('t', 'me', ago(90), status: TrailStatus.open)]), now: now),
        isEmpty);
    expect(stillValidQuestionsOf(trail([rep('t', 'anna', ago(90), status: TrailStatus.closed)]), now: now),
        isEmpty);
  });

  test('überholt: eine jüngere bestätigte Angabe, oder meine eigene jüngere', () {
    // Anna hat seither bestätigt gemeldet — meine steht nicht mehr da.
    expect(
        stillValidQuestionsOf(
            trail([
              rep('t', 'me', ago(60), status: TrailStatus.closed),
              rep('t', 'anna', ago(10), status: TrailStatus.open),
            ]),
            now: now),
        isEmpty);
    // Meine jüngere (unbestätigte, von zu Hause) überholt meine ältere
    // bestätigte, auch wenn beide angezeigt werden.
    expect(
        stillValidQuestionsOf(
            trail([
              rep('t', 'me', ago(60), status: TrailStatus.closed),
              rep('t', 'me', ago(5), status: TrailStatus.closed, confirmed: false),
            ]),
            now: now),
        isEmpty);
    // Eine jüngere UNBESTÄTIGTE von Anna lässt meine bestätigte stehen.
    expect(
        stillValidQuestionsOf(
            trail([
              rep('t', 'me', ago(60), status: TrailStatus.closed),
              rep('t', 'anna', ago(5), status: TrailStatus.open, confirmed: false),
            ]),
            now: now),
        hasLength(1));
  });

  test('„Weiß nicht" ruht 14 Tage, dann wird wieder gefragt', () {
    final t = trail([rep('t', 'me', ago(45), status: TrailStatus.destroyed)]);
    final id = t.reports.single.id;
    final until = now.add(kStillValidSnooze);
    expect(stillValidQuestionsOf(t, now: now, snoozed: {id: until}), isEmpty);
    expect(stillValidQuestionsOf(t, now: until, snoozed: {id: until}), hasLength(1));
  });

  test('ruhende Angaben überstehen Speichern und Lesen, Abgelaufenes fällt weg', () {
    final snoozes = {'a': now.add(const Duration(days: 3)), 'b': now.subtract(const Duration(days: 1))};
    final raw = encodeStillValidSnoozes(snoozes, now: now);
    expect(raw, hasLength(1));
    expect(decodeStillValidSnoozes(raw), {'a': snoozes['a']});
    expect(decodeStillValidSnoozes(['kaputt', 'x|nie']), isEmpty);
  });

  test('der Filter „Noch gültig?" lässt genau diese Trails durch, älteste Angabe zuerst', () {
    final a = trail([rep('a', 'me', ago(40), condition: 1)], id: 'a');
    final b = trail([rep('b', 'me', ago(80), status: TrailStatus.closed)], id: 'b');
    final c = trail([rep('c', 'me', ago(5), status: TrailStatus.closed)], id: 'c');
    const f = TrailListFilter(stillValidOnly: true);
    expect([for (final t in [a, b, c]) if (passesTrailFilter(t, f, now: now)) t.id], ['a', 'b']);
    expect(f.describe(l10nDe), 'noch gültig?');
    expect([for (final q in stillValidQuestions([a, b, c], now: now)) q.trail.id], ['b', 'a']);
  });
}
