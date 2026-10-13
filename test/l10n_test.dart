// Sprachen der Oberfläche (#209). Drei Zusagen: Jeder Text steht in
// beiden Sprachen, die App wählt Englisch für alles außer Deutsch, und
// bis die Übersetzung trägt, bleibt sie deutsch — auch auf einem
// englischen Gerät.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:trailbuddy/core/app_distribution.dart';
import 'package:trailbuddy/core/app_info.dart';
import 'package:trailbuddy/core/errors.dart' show friendlyError;
import 'package:trailbuddy/core/photo_pipeline.dart';
import 'package:trailbuddy/core/read_after_write.dart' show doneOrStale;
import 'package:trailbuddy/core/update_check.dart';
import 'package:trailbuddy/features/changelog/changelog_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart' show RecordingSource;
import 'package:trailbuddy/features/friends/connect_summary.dart';
import 'package:trailbuddy/features/map/map_legend.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/official/official_trails.dart' show OfficialStatus;
import 'package:trailbuddy/features/official/official_trails_layer.dart' show officialStatusLine;
import 'package:trailbuddy/models/profile.dart' show usernameProblem;
import 'package:trailbuddy/features/offline_areas/area_providers.dart' show OutsideRegions;
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
      await openProfilePage(tester, 'rides', tab: 'Profile');
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
      await openTab(tester, 'Buddies');
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

  // Stufe (e2): Profil samt Unterseiten, Kontodialoge und die Reiterleiste.
  group('Profil auf Englisch', () {
    testWidgets('Reiter, Profilliste, Konto und Fahrerprofil', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      final me = backend.addUser(username: 'anna');
      final jan = backend.addUser(username: 'jan');
      backend.signInAs(me.id);
      backend.addFriendship(jan.id, me.id);
      await pumpApp(tester, backend,
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      for (final tab in ['Map', 'Trails', 'Buddies', 'Profile']) {
        expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)), findsOneWidget,
            reason: tab);
      }
      await openTab(tester, 'Profile');
      expect(find.textContaining('1 buddy'), findsOneWidget, reason: 'Zahl im Kopf');
      for (final text in ['Import trails', 'My rides', 'My areas', 'Notifications', 'Rider profile',
          'Appearance', 'Account', 'Discover', 'Quick guide', 'About TrailBuddy']) {
        await scrollTo(tester, find.text(text));
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('Meine Bereiche'), findsNothing);

      await openProfilePage(tester, 'account', tab: 'Profile');
      for (final text in ['Change username', 'Change email address', 'Change password',
          'Sign out other devices', 'Delete account']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      await tester.tap(find.text('Delete account'));
      await settle(tester);
      expect(find.text('Type “anna” to confirm:'), findsOneWidget);
      expect(find.text('Delete for good'), findsOneWidget);
    });

    testWidgets('Fahrerprofil', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      final me = backend.addUser(username: 'anna');
      backend.signInAs(me.id);
      await pumpApp(tester, backend,
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      await openProfilePage(tester, 'rider', tab: 'Profile');
      expect(find.text('Learn from my rides'), findsOneWidget);
      expect(find.text('Bike: defaults — nothing learned yet.'), findsOneWidget);
      expect(find.textContaining('Climb rate forest road:'), findsOneWidget);
      expect(find.textContaining('Steigrate'), findsNothing);
    });

    test('Sätze mit Zahlen', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.profileStillValidValue(1), '1 entry to check');
      expect(en.profileMergeValue(3), '3 pairs to check');
      expect(l10nDe.profileStatBuddys(2), '2 Buddys');
      expect(
          l10nDe.riderProfileCalibLineAsOf('Bio-Bike', 'Forstweg 520 hm/h', l10nDe.riderProfileCalibRides(14),
              l10nDe.riderProfileCalibClimbs(31), '1.10.2026'),
          'Bio-Bike: Forstweg 520 hm/h — aus 14 Fahrten (31 Aufstiege), Stand 1.10.2026');
    });
  });

  // Stufe (f1): Hinweis, Kurzanleitung, Maschine und Touren.
  group('Touren und Hilfe auf Englisch', () {
    testWidgets('erster Start: Hinweis, Willkommensseite, Blase', (tester) async {
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      final settings = FakeSettings(safetyNoteSeen: false, mapTourSeen: false);
      await pumpApp(tester, backend,
          settings: settings, extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      expect(find.text('Before you start'), findsOneWidget);
      expect(find.textContaining('You ride at your own risk.'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await settle(tester, frames: 20);

      expect(find.text('Welcome to TrailBuddy'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      await tester.tap(find.text('Start the tour'));
      await settle(tester);
      final bubble = find.byKey(const ValueKey('coach-bubble'));
      expect(find.descendant(of: bubble, matching: find.text('Skip')), findsOneWidget);
      expect(find.descendant(of: bubble, matching: find.textContaining(RegExp(r'^1 of \d+$'))), findsOneWidget);
      expect(find.descendant(of: bubble, matching: find.textContaining(RegExp('[äöüß]'))), findsNothing,
          reason: 'kein deutscher Satz in der Blase');
      await tester.tap(find.descendant(of: bubble, matching: find.text('Skip')));
      await settle(tester);
      expect(settings.mapTourSeen, isTrue);
    });

    testWidgets('die Kurzanleitung', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend,
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      await openProfilePage(tester, 'help', tab: 'Profile');
      expect(find.text('Quick guide'), findsWidgets);
      for (final text in ['Importing trails', 'Reading the map', 'Buddies and visibility',
          'Show the tour on the map', 'Tour: Trails', 'Tour: Buddies', 'Discover features and tips']) {
        await scrollTo(tester, find.text(text));
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.textContaining('the Report status'), findsOneWidget, reason: 'Platzhalter {report}');
      expect(find.text('Die Karte lesen'), findsNothing);
    });
  });

  // Stufe (f2): „Entdecken", das Neuheiten-Blatt und die eigenen Schritte
  // der Vorführungen.
  group('Entdecken auf Englisch', () {
    testWidgets('Seite, Marken, Knöpfe und eine Vorführung', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend,
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      await openProfilePage(tester, 'discover', tab: 'Profile');
      expect(find.text('Discover'), findsWidgets);
      expect(find.textContaining('“Show me” gives a short demo'), findsOneWidget);
      expect(find.text('MAP'), findsOneWidget, reason: 'Gruppe nach Reiter, aus tabMap');
      expect(find.text('Minimise'), findsOneWidget);
      expect(find.text('Try it'), findsWidgets);
      expect(find.text('Show me'), findsWidgets);
      expect(find.text('Entdecken'), findsNothing);

      final show = find.byKey(const ValueKey('show-nav-sections'));
      await scrollTo(tester, show);
      await tester.tap(show);
      await settle(tester, frames: 20);
      final bubble = find.byKey(const ValueKey('coach-bubble'));
      expect(find.descendant(of: bubble, matching: find.text('From trail to trail')), findsOneWidget);
      expect(find.descendant(of: bubble, matching: find.textContaining(RegExp('[äöüß]'))), findsNothing,
          reason: 'kein deutscher Satz in der Blase');
    });

    testWidgets('das Blatt nach einem Update', (tester) async {
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend,
          settings: FakeSettings(highlightsSeenVersion: '0.56.0'),
          appVersion: '0.58.0',
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      expect(find.text('New in TrailBuddy'), findsOneWidget);
      expect(find.text('Still valid?'), findsOneWidget);
      expect(find.text('All changes'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    test('Sätze mit Zahlen', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.highlightSheetMore(1), 'Discover 1 more');
      expect(l10nDe.highlightSheetMore(4), '4 weitere entdecken');
      expect(en.demoOnlineFill1Text(16), contains('at most 16 tiles'));
    });
  });

  // Stufe (g1): Offline-Karten — Meine Bereiche, Leiste, Speichern-Dialog
  // und die Texte des Downloads.
  group('Offline-Karten auf Englisch', () {
    testWidgets('„Meine Bereiche" ohne Bereich', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend,
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      await openProfilePage(tester, 'areas', tab: 'Profile');
      expect(find.text('My areas'), findsOneWidget);
      expect(find.textContaining('No area yet.'), findsOneWidget);
      expect(find.textContaining('Noch kein Bereich'), findsNothing);
      expect(find.textContaining('Save all of'), findsWidgets, reason: 'ganze Region, nur auf dem Telefon');
    });

    test('Sätze mit Zahlen', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.areaSaveWholeAreas(1), '1 whole area');
      expect(l10nDe.areaSaveWholeAreas(2), '2 Bereiche ganz');
      expect(en.areasTilesAndBuild(1, '01.10.2026'), '1 tile · version 01.10.2026');
      expect(l10nDe.areasLoads('12 MB', 3), 'Lädt 12 MB · 3 Kacheln');
      expect(const OutsideRegions(['DACH', 'Canada']).message(en),
          'There is no map to save here — maps exist for DACH, Canada.');
    });
  });

  // Stufe (g2): Anmelden, Registrieren und das Blatt eines offiziellen
  // Trails.
  group('Anmelden und offizielle Trails auf Englisch', () {
    setUpAll(() => initializeDateFormatting('en'));

    testWidgets('Anmelden und Registrieren', (tester) async {
      await pumpApp(tester, FakeBackend(),
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      expect(find.text('Share trails — only with your buddies.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(find.text('Anmelden'), findsNothing);
      await tester.tap(find.text('No account yet? Sign up'));
      await tester.pumpAndSettle();
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Password (at least 8 characters)'), findsOneWidget);
    });

    test('Sätze der Quelle und Prüfungen', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(officialStatusLine(en, OfficialStatus.closed, 'Land Tirol', updated: '2026-09-28'),
          'Closed according to Land Tirol, as of 28 Sep 2026.');
      expect(usernameProblem(en, 'ab'), 'The username needs at least 3 characters.');
      expect(en.resendIn(42), 'Send again in 42 s');
    });
  });

  // Stufe (h): die letzten Texte in `lib/core/` und `models/trail.dart`.
  group('Kern und Trail-Modell auf Englisch', () {
    final en = lookupAppLocalizations(const Locale('en'));

    test('friendlyError nach Fehlerklasse', () {
      expect(friendlyError(en, const SocketException('x')), 'No connection — please check your internet.');
      expect(friendlyError(en, const PostgrestException(message: 'x', code: '42501')),
          'This is no longer shared with you.');
      expect(friendlyError(en, const PostgrestException(message: 'x')), 'Server error (unknown) — please try again later.');
      expect(friendlyError(en, StateError('x')), 'Unexpected error (StateError) — please try again later.');
      expect(friendlyError(l10nDe, const SocketException('x')), 'Keine Verbindung — bitte Internet prüfen.');
      expect(friendlyError(en, const PhotoPipelineException.unreadable()), 'The app cannot read this image format.');
    });

    test('Merkmal, Zustand, Sichtbarkeit und der Platzhalter ohne Namen', () {
      expect(TrailTrait.flowy.label(en), 'Flowy');
      expect(TrailTrait.flowy.label(l10nDe), 'Flowig');
      expect(TrailStatus.closed.label(en), 'Closed');
      expect(TrailVisibility.private.label(en), 'Only for me');
      final unnamed = Trail(id: 't', myId: 'me', recordings: [_rec('t')], details: const []);
      expect(unnamed.displayName(en), 'Unnamed trail');
      expect(unnamed.displayName(l10nDe), 'Trail ohne Namen');
      expect(unnamed.name, isNull);
    });

    test('Hinweise nach dem Speichern', () {
      expect(doneOrStale(en, 'Saved', fresh: true), 'Saved');
      expect(doneOrStale(en, 'Saved', fresh: false), 'Saved — visible once the list reloads.');
      expect(l10nDe.queuedHint, startsWith('Kein Netz — liegt im Ausgangskorb'));
    });

    test('eine Datei, die kein GPX ist', () {
      expect(() => parseGpx('<kml/>'),
          throwsA(isA<GpxFormatException>().having((e) => e.message(en), 'message', 'Not a GPX file (root is <kml>).')));
      expect(() => parseGpx('<<<'),
          throwsA(isA<GpxFormatException>().having((e) => e.message(l10nDe), 'message', startsWith('Kein gültiges XML: '))));
    });

    testWidgets('Update-Sperre', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(builder: (context) => Text(context.l10n.updateRequiredVersions('0.1.0', '0.2.0'))),
      ));
      expect(find.text('Installed: 0.1.0\nRequired: 0.2.0'), findsOneWidget);
    });
  });

  // Stufe (i): Glühbirne, Update-Banner und „Was ist neu“.
  group('Feedback, Update und Änderungsliste auf Englisch', () {
    testWidgets('der Feedback-Dialog', (tester) async {
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend,
          extraOverrides: [appLocaleProvider.overrideWithValue(const Locale('en'))]);
      await tester.tap(find.byTooltip('Report an idea or a bug'));
      await settle(tester);
      expect(find.text('Make a wish!'), findsOneWidget);
      expect(find.text('Your wish'), findsOneWidget);
      expect(find.textContaining('public entry on GitHub'), findsOneWidget);
      await tester.tap(find.text('Bug'));
      await settle(tester);
      expect(find.text('What happened?'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Send'), findsOneWidget);
      expect(find.textContaining(RegExp('[äöüß]')), findsNothing, reason: 'kein deutscher Satz im Dialog');
    });

    testWidgets('Banner und Dialog eines Updates', (tester) async {
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend, extraOverrides: [
        appLocaleProvider.overrideWithValue(const Locale('en')),
        updateInfoProvider.overrideWith((ref) => Future.value(const UpdateInfo(
              latestVersion: '9.9.9',
              downloadUrl: 'https://example.invalid/trailbuddy-v9.9.9.apk',
              releaseNotes: 'Faster map',
            ))),
      ]);
      await settle(tester);
      expect(find.text('Update to v9.9.9 available'), findsOneWidget);
      expect(find.byTooltip('Hide for this session'), findsOneWidget);
      await tester.tap(find.text('Update to v9.9.9 available'));
      await settle(tester);
      expect(find.text('Update to v9.9.9'), findsOneWidget);
      expect(find.text("What's new:"), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('In the browser'), findsOneWidget);
    });

    testWidgets('die Seite „Was ist neu“', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: ChangelogScreen(),
      ));
      expect(find.text("What's new"), findsOneWidget);
    });

    test('Sätze mit Zahlen', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.updateLoadingPercent(42), 'Downloading … 42 %');
      expect(l10nDe.updateLoadingPercent(42), 'Wird geladen … 42 %');
      expect(en.feedbackRejected('too short'), 'Not accepted: too short');
    });
  });
}

TrailRecording _rec(String trail) => TrailRecording(
      id: '$trail-r',
      trailId: trail,
      userId: 'me',
      source: RecordingSource.import,
      recordedAt: null,
      reversed: false,
      quality: 0.5,
      createdAt: DateTime(2026, 1, 1),
      points: const [LatLng(48, 9), LatLng(48.01, 9)],
      lengthM: 1000,
    );
