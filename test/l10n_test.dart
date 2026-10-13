// Sprachen der Oberfläche (#209). Drei Zusagen: Jeder Text steht in
// beiden Sprachen, die App wählt Englisch für alles außer Deutsch, und
// bis die Übersetzung trägt, bleibt sie deutsch — auch auf einem
// englischen Gerät.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_distribution.dart';
import 'package:trailbuddy/core/app_info.dart';
import 'package:trailbuddy/features/friends/connect_summary.dart';
import 'package:trailbuddy/features/map/map_legend.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/rides/ride_confirm.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/routing/navigate_choice.dart';
import 'package:trailbuddy/features/routing/route_profile.dart' as routing show WayClass;
import 'package:trailbuddy/features/routing/trail_head_route.dart' show routeTimeLabel;
import 'package:trailbuddy/models/trail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/singletrail_scale.dart';
import 'package:trailbuddy/features/trails/trail_condition.dart';
import 'package:trailbuddy/features/trails/trail_list.dart';
import 'package:trailbuddy/l10n/l10n.dart';

import 'fakes/fake_backend.dart';
import 'fakes/l10n_de.dart';
import 'fakes/fake_rides.dart';
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

  // Stufe (d1): Fahrten, Zerlege-Blatt und die Texte des Dienstes.
  group('Fahrten auf Englisch', () {
    test('Benachrichtigung und App sprechen dieselbe Sprache', () {
      // Der Dienst hat keinen BuildContext; spräche er eine andere Sprache
      // als die Oberfläche, stünde die Frage unterwegs auf Englisch über
      // einer deutschen App.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(appLocaleProvider), pinnedAppLocale);
      expect(serviceL10n().localeName, pinnedAppLocale!.languageCode);
    });

    test('die Frage unterwegs', () {
      final notice = confirmNoticeOf(
          lookupAppLocalizations(const Locale('en')),
          ConfirmTarget(
              trailId: 't1',
              name: 'Hausrunde',
              line: const [LatLng(47, 11), LatLng(47.001, 11)],
              status: TrailStatus.closed,
              condition: 2));
      expect(notice.body, endsWith('is that right?'));
      expect([for (final a in notice.actions) a.$2], ['That’s right', 'Trail is open', 'Change…']);
    });

    testWidgets('„Meine Fahrten"', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      final anna = backend.addUser(username: 'anna');
      backend.signInAs(anna.id);
      final t0 = DateTime.utc(2026, 9, 21, 9);
      final pts = [
        for (var i = 0; i <= 60; i++)
          RidePoint(lat: 47 + i / 10000, lng: 11, at: t0.add(Duration(seconds: 10 * i)), accuracyM: 5, altM: 500),
      ];
      final store = FakeRideStore()
        ..uid = anna.id
        ..rides.add(Ride(id: '20260921T090000Z', startedAt: t0, endedAt: pts.last.at, points: pts, profile: 'bio'));
      await pumpApp(tester, backend,
          rideStore: store,
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      await openProfilePage(tester, 'rides');
      await settle(tester);
      expect(find.text('My rides'), findsOneWidget);
      expect(find.text('Meine Fahrten'), findsNothing);
      expect(find.textContaining('61 points'), findsOneWidget);
      expect(find.text('Bike'), findsOneWidget, reason: 'das Rad am Chip');
      // Das Datum folgt der Sprache (Muster aus der ARB-Datei).
      expect(find.textContaining('September 21, 2026'), findsOneWidget);
    });
  });

  // Stufe (d2): Rundenplaner, Weg zum Trailkopf und die Navigation.
  group('Planer und Navigation auf Englisch', () {
    testWidgets('Leiste und Parameter des Planers', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend,
          settings: FakeSettings(),
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      await settle(tester, frames: 20);
      await tester.tap(find.byKey(const ValueKey('loop-button')));
      await settle(tester, frames: 10);
      for (final tip in ['Settings', 'Choose trails from the list', 'Clear selection', 'Close planner',
        'Compute loop — choose trails first']) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      expect(find.byTooltip('Planer schließen'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('loop-rail-params')));
      await settle(tester, frames: 20);
      for (final text in ['Loop settings', 'Start: my location', 'Tap on the map', 'Bike']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('Parameter der Runde'), findsNothing);
    });

    test('Wegklassen, Navi-Auswahl und Zeit sind in beiden Sprachen benannt und verschieden', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l = lookupAppLocalizations(locale);
        final groups = <String, List<String>>{
          'Wegklassen': [for (final c in routing.WayClass.values) c.label(l)],
          'Navi-Auswahl': [for (final c in NavChoice.values) c.label(l)],
          'Navi-Auswahl lang': [for (final c in NavChoice.values) c.description(l)],
        };
        for (final MapEntry(key: what, value: names) in groups.entries) {
          expect(names.where((n) => n.trim().isEmpty), isEmpty, reason: '$locale: $what');
          expect(names.toSet(), hasLength(names.length), reason: '$locale: $what');
        }
      }
      final en = lookupAppLocalizations(const Locale('en'));
      expect(routeTimeLabel(en, 100), 'under 5 min');
      expect(routeTimeLabel(en, 4800), '1 h 20 min');
      expect(routing.WayClass.bundesstrasse.label(en), 'Highway');
    });
  });

  // Stufe (e1): Buddys — Liste, Anfragen, Alias, Verlauf, Einladung.
  group('Buddys auf Englisch', () {
    testWidgets('Liste mit Anfrage und Buddy, Verlauf mit Grenze', (tester) async {
      final backend = FakeBackend();
      final me = backend.addUser(username: 'anna');
      final jan = backend.addUser(username: 'jan');
      final lea = backend.addUser(username: 'lea');
      backend.signInAs(me.id);
      backend.addFriendship(jan.id, me.id);
      backend.addFriendship(lea.id, me.id, status: 'pending');
      await pumpApp(tester, backend,
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      await openTab(tester, 'Buddys');
      for (final text in ['BUDDIES', 'REQUESTS FOR YOU · 1', 'MY BUDDIES · 1', 'Accept', '0 shared']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      for (final tip in ['Invite buddies to TrailBuddy', 'Set alias', 'Remove buddy', 'Decline']) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      expect(find.text('MEINE BUDDYS · 1'), findsNothing);

      // Die Anfrage von Lea: drei Nachrichten, bevor ich annehme.
      await tester.tap(find.byTooltip('Messages').first);
      await settle(tester);
      expect(find.textContaining('Messages disappear after 30 days'), findsOneWidget);
    });

    test('Sätze mit Zahlen und die Einladung', () {
      final en = lookupAppLocalizations(const Locale('en'));
      const one = ConnectSummary(shared: 1, newFromBuddy: 2, newForBuddy: 0);
      expect(one.sentence(en, 'Jan'), 'Connected with Jan: 1 trail shared, 2 new from Jan, 0 new for Jan.');
      const none = ConnectSummary(shared: 0, newFromBuddy: 0, newForBuddy: 0);
      expect(none.sentence(en, 'Jan'), contains('no trails on either side'));
      expect(en.messagesLeftOutgoing(1, 'Jan'), '1 message left until Jan accepts the request.');
      expect(en.messagesLeftIncoming(3), '3 messages left before you accept the request.');
      expect(AppInfo.inviteText(en, null), isNot(contains('Sign up')));
      expect(AppInfo.inviteText(en, 'anna'), allOf(contains(AppInfo.webAppUrl), contains('“anna”')));
      expect(AppInfo.inviteText(l10nDe, 'anna'), contains('such mich dort als „anna“'));
    });
  });
}
