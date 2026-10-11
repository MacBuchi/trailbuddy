// Sprachen der Oberfläche (#209). Drei Zusagen: Jeder Text steht in
// beiden Sprachen, die App wählt Englisch für alles außer Deutsch, und
// bis die Übersetzung trägt, bleibt sie deutsch — auch auf einem
// englischen Gerät.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_distribution.dart';
import 'package:trailbuddy/features/map/map_legend.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/trails/singletrail_scale.dart';
import 'package:trailbuddy/features/trails/trail_condition.dart';
import 'package:trailbuddy/features/trails/trail_list.dart';
import 'package:trailbuddy/l10n/l10n.dart';

import 'fakes/fake_backend.dart';
import 'fakes/fake_settings.dart';
import 'fakes/fake_trails.dart';
import 'fakes/test_app.dart';

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
        as Map<String, dynamic>;

/// Die Texte einer ARB-Datei, ohne `@@locale` und `@key`-Beschreibungen.
Map<String, String> _messages(Map<String, dynamic> arb) => {
      for (final e in arb.entries)
        if (!e.key.startsWith('@')) e.key: e.value as String,
    };

/// Die Platzhalter eines Textes: `{name}` und der Kopf von
/// `{count, plural, …}`. Was in einer Plural-Klammer steht, ist Text.
Set<String> _placeholders(String message) => {
      for (final m in RegExp(r'\{(\w+)\s*[,}]').allMatches(message)) m[1]!,
    };

const _english = 'Development build — not released';
const _german = 'Entwicklungsstand — nicht freigegeben';

Future<void> _pumpPreview(WidgetTester tester,
    {Locale? appLocale = const Locale('de'),
    List<Locale> deviceLocales = const [Locale('de', 'DE')]}) async {
  final backend = FakeBackend();
  backend.signInAs(backend.addUser(username: 'anna').id);
  await pumpApp(tester, backend,
      deviceLocales: deviceLocales,
      extraOverrides: [
        webChannelProvider.overrideWithValue(WebChannel.preview),
        appLocaleProvider.overrideWithValue(appLocale),
      ]);
}

void main() {
  group('ARB-Dateien', () {
    final de = _arb('de');
    final en = _arb('en');

    test('nennen ihre Sprache', () {
      expect(de['@@locale'], 'de');
      expect(en['@@locale'], 'en');
    });

    test('haben dieselben Schlüssel', () {
      final deKeys = _messages(de).keys.toSet();
      final enKeys = _messages(en).keys.toSet();
      expect(deKeys.difference(enKeys), isEmpty,
          reason: 'fehlt in app_en.arb');
      expect(enKeys.difference(deKeys), isEmpty,
          reason: 'steht nur in app_en.arb — die Vorlage ist app_de.arb');
    });

    test('jeder Text hat eine Beschreibung in der Vorlage', () {
      // Die Beschreibung ist alles, was die übersetzende Person vom Ort
      // des Textes weiß — „Speichern" ist im Trail-Blatt etwas anderes
      // als im Kartenbereich.
      for (final key in _messages(de).keys) {
        final meta = de['@$key'];
        expect(meta is Map && (meta['description'] as String? ?? '').isNotEmpty,
            isTrue,
            reason: '@$key.description fehlt in app_de.arb');
      }
    });

    test('Englisch ist nie leer und hat dieselben Platzhalter', () {
      final deMessages = _messages(de);
      for (final MapEntry(:key, value: english) in _messages(en).entries) {
        expect(english.trim(), isNotEmpty, reason: key);
        expect(_placeholders(english), _placeholders(deMessages[key] ?? ''),
            reason: key);
      }
    });
  });

  group('resolveAppLocale', () {
    test('Deutsch bleibt Deutsch, gleich aus welchem Land', () {
      expect(resolveAppLocale(const [Locale('de', 'AT')]), const Locale('de'));
      expect(resolveAppLocale(const [Locale('de', 'CH')]), const Locale('de'));
    });

    test('Englisch und alles Unbekannte wird Englisch', () {
      expect(resolveAppLocale(const [Locale('en', 'US')]), const Locale('en'));
      expect(resolveAppLocale(const [Locale('fr', 'FR')]), const Locale('en'));
      expect(resolveAppLocale(const []), const Locale('en'));
      expect(resolveAppLocale(null), const Locale('en'));
    });

    test('eine weiter hinten genannte bekannte Sprache gewinnt', () {
      expect(resolveAppLocale(const [Locale('fr'), Locale('de')]),
          const Locale('de'));
      expect(resolveAppLocale(const [Locale('it'), Locale('en'), Locale('de')]),
          const Locale('en'));
    });
  });

  group('die App', () {
    testWidgets('bleibt vorerst deutsch, auch auf einem englischen Gerät',
        (tester) async {
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend,
          deviceLocales: const [Locale('en', 'US')],
          extraOverrides: [
            webChannelProvider.overrideWithValue(WebChannel.preview),
          ]);
      expect(find.text(_german), findsOneWidget);
    });

    testWidgets('zeigt einen umgezogenen Text auf Englisch', (tester) async {
      await _pumpPreview(tester, appLocale: const Locale('en'));
      expect(find.text(_english), findsOneWidget);
      expect(find.text(_german), findsNothing);
    });

    testWidgets('folgt offen der Gerätesprache: Französisch wird Englisch',
        (tester) async {
      await _pumpPreview(tester,
          appLocale: null, deviceLocales: const [Locale('fr', 'FR')]);
      expect(find.text(_english), findsOneWidget);
    });

    testWidgets('folgt offen der Gerätesprache: das Testgerät ist deutsch',
        (tester) async {
      // Die Vorgabe von pumpApp — trägt sie, bleiben alle deutschen
      // Flow-Tests grün, sobald die App der Gerätesprache folgt.
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend, extraOverrides: [
        webChannelProvider.overrideWithValue(WebChannel.preview),
        appLocaleProvider.overrideWithValue(null),
      ]);
      expect(find.text(_german), findsOneWidget);
    });
  });

  // Stufe (b): Karte, Kartenknöpfe und Blätter. Ein Text, der beim Umzug
  // im Code stehen blieb, wäre hier deutsch.
  group('die Karte auf Englisch', () {
    Future<void> pumpMap(WidgetTester tester) async {
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend,
          settings: FakeSettings(),
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      await settle(tester, frames: 20);
    }

    testWidgets('Knöpfe und Legende', (tester) async {
      await pumpMap(tester);
      for (final tip in ['Map layers', 'Offline maps', 'Plan a loop', 'My location', 'Record a ride']) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      expect(find.byTooltip('Kartenebenen'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('map-legend-tab')));
      await settle(tester);
      for (final text in ['Legend', 'DIFFICULTY', 'CONDITION', 'worn', 'no grade']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('SCHWIERIGKEIT'), findsNothing);
    });

    testWidgets('das Blatt „Kartenebenen"', (tester) async {
      await pumpMap(tester);
      await tester.tap(find.byKey(const ValueKey('layers-button')));
      await settle(tester);
      // Ab Werk ist nur „Wasser" an — darunter stehen seine Arten.
      for (final text in ['Layers', 'Official trails', 'Ways', 'Contour lines', 'Places on the map', 'Water',
        'Drinking water', 'Spring']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('Orte auf der Karte'), findsNothing);
    });

    test('Arten und Klassen sind in beiden Sprachen benannt und verschieden', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l = lookupAppLocalizations(locale);
        final names = [
          for (final g in PoiGroup.values) g.label(l),
          for (final k in PoiKind.values) k.label(l),
        ];
        expect(names.where((n) => n.trim().isEmpty), isEmpty, reason: '$locale');
        expect(names.toSet(), hasLength(names.length), reason: '$locale: Orte');
        final legend = [for (final s in legendSamples(l)) s.label];
        expect(legend.toSet(), hasLength(legend.length), reason: '$locale: Legende');
        expect({for (final c in WayClass.values) c.label(l)}, hasLength(WayClass.values.length));
      }
    });
  });

  // Stufe (c): Trails, Trail-Blatt und Import. Wie oben: Ein Text, der
  // beim Umzug im Code stehen blieb, wäre hier deutsch.
  group('die Trails auf Englisch', () {
    Future<void> pumpTrails(WidgetTester tester) async {
      final backend = FakeBackend();
      final anna = backend.addUser(username: 'anna');
      backend.signInAs(anna.id);
      final trails = FakeTrailRepository(
          myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
      trails.seedTrail(anna.id, name: 'Roßkopf Süd', grade: 1);
      trails.seedTrail(anna.id, name: 'Hexentanz', lat: 48.1, grade: 4);
      await pumpApp(tester, backend,
          trails: trails,
          settings: FakeSettings(),
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      await settle(tester, frames: 20);
      await openTab(tester, 'Trails');
      await settle(tester, frames: 20);
    }

    testWidgets('Liste, Suche und Filter', (tester) async {
      await pumpTrails(tester);
      for (final text in ['S grade', 'New note', 'Reported', 'Rating open', 'My trails (2)']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('MINE'), findsNWidgets(2));
      expect(find.text('S-Grad'), findsNothing);
      expect(find.text('MEIN'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('trail-search')), 'rosskopf sued');
      await settle(tester);
      expect(find.text('One trail found.'), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsOneWidget);
      expect(find.text('Ein Trail gefunden.'), findsNothing);
    });

    testWidgets('das Trail-Blatt', (tester) async {
      await pumpTrails(tester);
      await tester.tap(find.text('Hexentanz'));
      await settle(tester);
      for (final text in ['Only you have recorded this trail.', 'LENGTH', 'ELEVATION', 'S GRADE']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('LÄNGE'), findsNothing);
    });

    test('Skala, Zustand, Sortierung und Besitz sind in beiden Sprachen benannt und verschieden', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l = lookupAppLocalizations(locale);
        final groups = <String, List<String>>{
          'Skala kurz': [for (final g in kSingletrailScale) g.short(l)],
          'Skala lang': [for (final g in kSingletrailScale) g.description(l)],
          'Zustand': [for (final c in kTrailConditions) c.label(l)],
          'Zustand lang': [for (final c in kTrailConditions) c.description(l)],
          'Sortierung': [for (final s in TrailSort.values) s.label(l)],
          'Besitz': [for (final o in TrailOwnerFilter.values) o.label(l)],
        };
        for (final MapEntry(key: what, value: names) in groups.entries) {
          expect(names.where((n) => n.trim().isEmpty), isEmpty, reason: '$locale: $what');
          expect(names.toSet(), hasLength(names.length), reason: '$locale: $what');
        }
      }
    });
  });
}
