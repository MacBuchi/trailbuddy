// Die Liste der Neuheiten und Tipps (#135) und die eine Entscheidung
// `planHighlights` — ohne App.
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/update_check.dart' show isNewerVersion;
import 'package:trailbuddy/features/highlights/feature_highlights.dart';
import 'package:trailbuddy/l10n/l10n.dart';

import 'fakes/l10n_de.dart';

void main() {
  final pubspec = RegExp(r'^version:\s*([\d.]+)', multiLine: true)
      .firstMatch(File('pubspec.yaml').readAsStringSync())!
      .group(1)!;

  test('Kennungen einmalig, Ziele sind Routen, Texte kurz', () {
    final ids = kFeatureHighlights.map((h) => h.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final h in kFeatureHighlights) {
      expect(h.target, startsWith('/'), reason: h.id);
      // In beiden Sprachen (#209): Auch die Übersetzung bleibt kurz.
      for (final l in [l10nDe, lookupAppLocalizations(const Locale('en'))]) {
        final sentences = RegExp(r'[.!?](\s|$)').allMatches(h.text(l)).length;
        expect(sentences, inInclusiveRange(1, 3), reason: '${h.id} (${l.localeName}): höchstens drei Sätze');
        expect(h.title(l), isNotEmpty, reason: h.id);
      }
    }
  });

  test('keine Funktion kommt aus der Zukunft', () {
    for (final h in kFeatureHighlights) {
      expect(isNewerVersion(h.since, pubspec), isFalse, reason: '${h.id}: ${h.since} > $pubspec');
    }
  });

  test('der Rückblick beginnt mit Highlights, die es gibt', () {
    for (final id in kRecapLead) {
      expect(kFeatureHighlights.where((h) => h.id == id && h.kind == HighlightKind.highlight), hasLength(1),
          reason: id);
    }
  });

  group('planHighlights', () {
    test('Version unbekannt: nichts', () {
      expect(planHighlights(current: null, seenVersion: null, mapTourSeen: true), isA<HighlightNothing>());
    });

    test('frisch installiert: nur merken', () {
      final plan = planHighlights(current: '0.64.0', seenVersion: null, mapTourSeen: false);
      expect(plan, isA<HighlightRecord>());
      expect((plan as HighlightRecord).version, '0.64.0');
    });

    test('Bestand ohne Merker: einmal der Rückblick, mit kRecapLead vorn', () {
      final plan = planHighlights(current: '0.64.0', seenVersion: null, mapTourSeen: true);
      expect(plan, isA<HighlightShow>());
      plan as HighlightShow;
      expect(plan.recap, isTrue);
      expect(plan.pages.map((h) => h.id), kRecapLead);
      expect(plan.more, greaterThan(0));
    });

    test('nach einem Update: die jüngsten Highlights, höchstens drei', () {
      final plan = planHighlights(current: '0.64.0', seenVersion: '0.50.0', mapTourSeen: true);
      plan as HighlightShow;
      expect(plan.recap, isFalse);
      expect(plan.pages, hasLength(kHighlightSheetMax));
      expect(plan.pages.first.id, 'kurzanleitung', reason: 'die jüngste zuerst');
      expect(plan.pages.every((h) => h.kind == HighlightKind.highlight), isTrue, reason: 'Tipps nie im Blatt');
    });

    test('Update ohne neues Highlight: nur merken', () {
      expect(planHighlights(current: '0.64.0', seenVersion: '0.63.0', mapTourSeen: true), isA<HighlightRecord>());
    });

    test('Rückschritt vom Vorabkanal: nichts, und nichts zurückschreiben', () {
      expect(planHighlights(current: '0.60.0', seenVersion: '0.64.0', mapTourSeen: true), isA<HighlightNothing>());
    });
  });
}
