// Der Charakter eines Trails (#72): Mehrfachwahl je Beitrag statt der
// früheren „Art", angezeigt die zwei häufigsten über alle sichtbaren
// Beiträge, gefiltert über genau diese.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/features/trails/trail_list.dart';
import 'package:trailbuddy/features/trails/trail_traits.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/l10n_de.dart';

Trail trailWith(List<Set<TrailTrait>> contributions) => Trail(
      id: 't',
      myId: 'me',
      recordings: [
        TrailRecording(
          id: 'r',
          trailId: 't',
          userId: 'me',
          source: RecordingSource.import,
          recordedAt: null,
          reversed: false,
          quality: 0.5,
          createdAt: DateTime(2026, 9, 1),
          points: const [LatLng(48, 9), LatLng(48.01, 9)],
          lengthM: 1000,
        ),
      ],
      details: [
        for (var i = 0; i < contributions.length; i++)
          TrailDetails(trailId: 't', userId: 'u$i', traits: contributions[i]),
      ],
    );

void main() {
  group('Zeile ↔ Merkmale', () {
    test('die alte Art wird dasselbe Merkmal wie im Patch 009', () {
      expect(TrailTrait.fromLegacyKind('flow'), TrailTrait.flowy);
      expect(TrailTrait.fromLegacyKind('jump'), TrailTrait.jumps);
      expect(TrailTrait.fromLegacyKind('tech'), TrailTrait.rocky);
      expect(TrailTrait.fromLegacyKind('natural'), TrailTrait.natural);
      expect(TrailTrait.fromLegacyKind('connection'), TrailTrait.connection);
      expect(TrailTrait.fromLegacyKind(null), isNull);
      expect(TrailTrait.fromLegacyKind('unbekannt'), isNull);
    });

    test('traits gewinnt; fehlt die Spalte, zählt die alte Art', () {
      Map<String, dynamic> row(Map<String, dynamic> extra) =>
          {'trail_id': 't', 'user_id': 'u', ...extra};
      expect(TrailDetails.fromJson(row({'traits': ['rocky', 'steep'], 'kind': 'flow'})).traits,
          {TrailTrait.rocky, TrailTrait.steep},
          reason: 'die neue Spalte ist die Wahrheit, auch wenn kind noch dasteht');
      expect(TrailDetails.fromJson(row({'traits': <String>[], 'kind': 'flow'})).traits, isEmpty,
          reason: 'leer heißt: bewusst nichts gewählt');
      expect(TrailDetails.fromJson(row({'kind': 'tech'})).traits, {TrailTrait.rocky},
          reason: 'Zwischenspeicher/Ausgangskorb von vor 0.34.0');
      expect(TrailDetails.fromJson(row({'traits': ['flowy', 'bogus']})).traits, {TrailTrait.flowy},
          reason: 'ein Merkmal, das diese Fassung nicht kennt, fällt weg statt zu werfen');
    });

    test('toRow schreibt traits in fester Reihenfolge und kein kind mehr', () {
      final row = const TrailDetails(
              trailId: 't', userId: 'u', traits: {TrailTrait.steep, TrailTrait.flowy})
          .toRow();
      expect(row['traits'], ['flowy', 'steep']);
      expect(row.containsKey('kind'), isFalse,
          reason: 'sonst überschriebe ein neuer Client die Art, die ein alter noch liest');
    });
  });

  group('Charakter eines Trails', () {
    test('die zwei häufigsten, gezählt je Beitrag', () {
      final t = trailWith([
        {TrailTrait.rocky, TrailTrait.steep},
        {TrailTrait.rocky},
        {TrailTrait.flowy, TrailTrait.steep, TrailTrait.rocky},
      ]);
      expect(t.traitCounts, {TrailTrait.rocky: 3, TrailTrait.steep: 2, TrailTrait.flowy: 1});
      expect(t.topTraits, [TrailTrait.rocky, TrailTrait.steep]);
    });

    test('Gleichstand: Reihenfolge der Merkmale, nicht die der Beiträge', () {
      final t = trailWith([
        {TrailTrait.connection},
        {TrailTrait.uphill},
        {TrailTrait.flowy},
      ]);
      expect(t.topTraits, [TrailTrait.flowy, TrailTrait.uphill]);
      expect(t.topTraits, hasLength(kShownTraits));
    });

    test('ohne Angabe kein Charakter', () {
      expect(trailWith([{}]).topTraits, isEmpty);
    });

    test('jedes Merkmal hat Beschreibung und Symbol, keine zwei dasselbe', () {
      expect({for (final t in TrailTrait.values) t.icon}, hasLength(TrailTrait.values.length));
      expect({for (final t in TrailTrait.values) t.label}, hasLength(TrailTrait.values.length));
      for (final t in TrailTrait.values) {
        expect(t.description(l10nDe), isNotEmpty, reason: t.db);
      }
    });
  });

  group('Filter', () {
    final flowJump = trailWith([
      {TrailTrait.flowy, TrailTrait.jumps},
    ]);
    // Einer sagt flowig, drei sagen verblockt und steil: flowig ist NICHT
    // der Charakter, also findet der Filter ihn auch nicht.
    final mostlyRocky = trailWith([
      {TrailTrait.flowy},
      {TrailTrait.rocky, TrailTrait.steep},
      {TrailTrait.rocky, TrailTrait.steep},
      {TrailTrait.rocky, TrailTrait.steep},
    ]);

    test('gefiltert wird über das, was angezeigt wird', () {
      const flowy = TrailListFilter(traits: {TrailTrait.flowy});
      expect(passesTrailFilter(flowJump, flowy), isTrue);
      expect(passesTrailFilter(mostlyRocky, flowy), isFalse);
    });

    test('mehrere Merkmale: alle müssen passen', () {
      const both = TrailListFilter(traits: {TrailTrait.flowy, TrailTrait.jumps});
      expect(passesTrailFilter(flowJump, both), isTrue);
      expect(passesTrailFilter(trailWith([{TrailTrait.flowy}]), both), isFalse);
    });

    test('describe, isActive und Gleichheit', () {
      const f = TrailListFilter(traits: {TrailTrait.jumps, TrailTrait.flowy});
      expect(f.describe(l10nDe), 'Flowig · Jump-Line');
      expect(f.isActive, isTrue);
      expect(f, const TrailListFilter(traits: {TrailTrait.flowy, TrailTrait.jumps}));
      expect(f.hashCode, const TrailListFilter(traits: {TrailTrait.flowy, TrailTrait.jumps}).hashCode);
      expect(f == const TrailListFilter(traits: {TrailTrait.flowy}), isFalse);
    });
  });
}
