// Startet die komplette App gegen das In-Memory-Backend: alle
// Repository-Provider werden mit Fakes überschrieben, die Karte ist eine
// Fake ohne Kacheln (kein Netz, kein Kartenhost) und der Update-Check ist
// stillgelegt. Damit laufen echte End-to-End-Abläufe
// (Login → Karte → Buddys → Profil) als schnelle Widget-Tests.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trailbuddy/app.dart';
import 'package:trailbuddy/core/app_info.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/push_messaging.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/core/update_check.dart';
import 'package:trailbuddy/core/widgets/start_splash.dart';
import 'package:trailbuddy/data/providers.dart';
import 'package:trailbuddy/features/map/base_map_providers.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/map/map_view/flutter_map_view.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/keep_alive/keep_alive.dart';
import 'package:trailbuddy/features/map/poi_source.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/map/position_provider.dart';
import 'package:trailbuddy/features/official/official_trails_source.dart';
import 'package:trailbuddy/features/rides/ride_confirm_notify.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_service.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner.dart';
import 'package:trailbuddy/features/trails/outbox_providers.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';

import 'fake_backend.dart';
import 'fake_map_view.dart';
import 'fake_official_trails.dart';
import 'fake_outbox.dart';
import 'fake_pois.dart';
import 'fake_rides.dart';
import 'fake_settings.dart';
import 'fake_trail_cache.dart';
import 'fake_trails.dart';
import 'fake_keep_alive.dart';

/// Test-Position ohne Geolocator-Plugin (alle Pflichtfelder gefüllt).
Position fakePosition(double lat, double lon, {double accuracy = 8}) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime(2026, 9, 28, 12),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Der EINZELNE Fix hinter „Meine Position" — zählt, wie oft gefragt
/// wurde (nur dort darf nach der Berechtigung gefragt werden).
class FakePositionFix {
  FakePositionFix([this.next]);

  Position? next;
  int calls = 0;

  Future<Position?> call() async {
    calls++;
    return next;
  }
}

List<Override> overridesFor(FakeBackend backend,
        {FakeAppConfigRepository? appConfig,
        String appVersion = '1.0.0',
        Settings? settings,
        FakeTrailRepository? trails,
        FakePoiSource? pois,
        FakeOfficialTrailsSource? official,
        MemoryOfficialTrailsCache? officialCache,
        Position? position,
        FakePositionFix? positionFix,
        FakeRideStore? rideStore,
        FakeRideFix? rideFix,
        FakeRideServiceBridge? rideBridge,
        FakeRideService? rideService,
        FakeOutbox? outbox,
        FakeTrailCache? trailCache,
        MemoryAreaStore? areaStore,
        FakeKeepAlive? keepAlive,
        Stream<List<ConnectivityResult>>? connectivity,
        FakePushRepository? push,
        Stream<RemoteMessage>? pushMessages,
        bool useRealMap = false,
        List<Override> extra = const []}) =>
    [
      // Die Karten-Engine ist standardmäßig die Fake (Marker in einem
      // Wrap, Kamera synchron simuliert, Tipps über die Trefferprüfung
      // der Fassade) — die Flow-Suiten beweisen Verhalten, nicht
      // Rendering. Tests, die flutter_map-Interna prüfen, pumpen mit
      // `useRealMap: true`; die MapLibre-Platform-View ist im Widget-Test
      // nicht renderbar, ihr Gate ist das Gerät.
      mapViewBuilderProvider.overrideWithValue(useRealMap
          ? (config, controller, layers) =>
              FlutterMapView(config: config, controller: controller, layers: layers)
          : (config, controller, layers) =>
              FakeMapView(config: config, controller: controller, layers: layers)),
      // Die Übersichtskarte kommt aus einem Asset, das der Test-Runner
      // nicht liefert — und ohne Empfang würde die echte Karte sie öffnen.
      overviewOpenerProvider.overrideWithValue(() async => null),
      // Der Start-Splash (1p) läge sonst über jedem Flow-Test und
      // schluckte die ersten Tipps; er hat seinen eigenen Test.
      startSplashEnabledProvider.overrideWithValue(false),
      settingsProvider.overrideWithValue(settings ?? FakeSettings()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(backend)),
      profileRepositoryProvider
          .overrideWithValue(FakeProfileRepository(backend)),
      friendRepositoryProvider.overrideWithValue(FakeFriendRepository(backend)),
      feedbackRepositoryProvider
          .overrideWithValue(FakeFeedbackRepository(backend)),
      // Die Karte beobachtet die Trails, und die kämen sonst aus
      // `Supabase.instance` — das gibt es im Widget-Test nicht. Vorgabe
      // ist ein leeres Trail-Netz mit den Buddy-Regeln dieses Backends;
      // Tests mit Trails reichen ihr eigenes Fake herein.
      trailRepositoryProvider.overrideWithValue(trails ??
          FakeTrailRepository(
              myId: () => backend.currentUserId ?? '',
              areFriends: backend.areFriends)),
      // Kein Netz in Tests: kein Manifest vom Kartenhost, also keine
      // Online-Karte — und die Übersicht kommt aus keinem Asset (oben).
      mapManifestLoaderProvider.overrideWithValue(() async => null),
      areaHeightsManifestLoaderProvider.overrideWithValue(() async => null),
      heightsManifestLoaderProvider.overrideWithValue(() async => null),
      // Und keine Orte-Dateien vom Host: Eine Karte, die auf einen Trail
      // zoomt, liegt über Zoom 12 und fragte sonst wirklich an.
      poiSourceProvider.overrideWithValue(pois ?? FakePoiSource()),
      // Ebenso die offiziellen Trails: Vorgabe ist ein Index ohne
      // Regionen, gemerkt wird im Speicher statt im App-Verzeichnis.
      officialTrailsSourceProvider
          .overrideWithValue(official ?? FakeOfficialTrailsSource()),
      officialTrailsCacheProvider
          .overrideWithValue(officialCache ?? MemoryOfficialTrailsCache()),
      // Kein Plattform-Kanal für den Standort: Die Position kommt aus dem
      // Test (Vorgabe: keine, wie ohne Berechtigung).
      positionStreamProvider.overrideWith((ref) => Stream.value(position)),
      positionFixProvider
          .overrideWithValue((positionFix ?? FakePositionFix(position)).call),
      // Die Fahrt (#28): im Speicher statt auf der Platte, ohne
      // Foreground-Service und ohne Berechtigungsdialog. Ohne diese
      // Zeilen ginge jeder Kartentest beim ersten Frame (`restore`) an
      // `path_provider`.
      rideStoreProvider.overrideWithValue(rideStore ?? FakeRideStore()),
      rideFixProvider.overrideWithValue((rideFix ?? FakeRideFix()).call),
      rideServiceBridgeProvider.overrideWithValue(rideBridge ?? FakeRideServiceBridge()),
      rideServiceProvider.overrideWithValue(rideService ?? FakeRideService()),
      ridePermissionProvider.overrideWithValue(() async => null),
      // Der Ausgangskorb (#30) im Speicher; der Netzwechsel kommt aus dem
      // Test (Vorgabe: WLAN, ohne Wechsel).
      outboxProvider.overrideWithValue(outbox ?? FakeOutbox()),
      // Die Kopie des Netzes (#32) im Speicher — ohne Override ginge
      // jeder Abruf an `path_provider`.
      trailCacheProvider.overrideWithValue(trailCache ?? FakeTrailCache()),
      // Gespeicherte Bereiche (Konzept-Schritt 3) im Speicher, der
      // Foreground-Service als Fake — ohne beides ginge der Kartenstart
      // an `path_provider` und den Plattform-Kanal.
      areaStoreProvider.overrideWithValue(areaStore ?? MemoryAreaStore()),
      keepAliveProvider.overrideWithValue(keepAlive ?? FakeKeepAlive()),
      // Ein echter Rechen-Isolate antwortet in der Test-Zone nie (#188).
      loopPlanRunnerFactoryProvider.overrideWithValue(InlineLoopPlanRunner.new),
      connectivityProvider.overrideWith(
          (ref) => connectivity ?? Stream.value(const [ConnectivityResult.wifi])),
      updateInfoProvider.overrideWith((ref) => Future.value(null)),
      // Push (#34): Im Widget-Test gibt es weder FCM noch
      // Berechtigungsdialoge. Ohne diese Naht liefe ein Test, der den
      // Schalter im Profil antippt, in echtes Plattform-IO — und das löst
      // in der Fake-Zone NIE auf. Vorgabe ist ein Token: Der interessante
      // Weg ist „eingeschaltet"; wer die Ablehnung prüfen will,
      // überschreibt gezielt. Und die Ströme: `PushListener` hängt sich
      // beim ersten Frame an `onMessage`, also in JEDEM Test.
      pushRepositoryProvider
          .overrideWithValue(push ?? FakePushRepository(backend)),
      pushTokenProvider.overrideWithValue(
          () async => (token: 'test-token', denied: false, unavailable: false)),
      pushMessageListenerProvider
          .overrideWithValue(() => pushMessages ?? const Stream.empty()),
      pushTapListenerProvider.overrideWithValue(() => const Stream.empty()),
      rideConfirmTapsProvider.overrideWithValue(() => const Stream.empty()),
      pushInitialMessageProvider.overrideWithValue(() async => null),
      // Mindestversion: ohne Angabe sperrt nichts. PackageInfo gibt es im
      // Test nicht, deshalb kommt die eigene Version aus dem Harness.
      appConfigRepositoryProvider
          .overrideWithValue(appConfig ?? FakeAppConfigRepository()),
      appVersionProvider.overrideWith((ref) => Future.value(appVersion)),
      // Zuletzt, damit ein Test gezielt etwas aus der Liste oben ersetzen
      // kann — bei Riverpod gewinnt der spätere Eintrag.
      ...extra,
    ];

/// App starten und den ersten Aufbau abwarten.
Future<void> pumpApp(WidgetTester tester, FakeBackend backend,
    {FakeAppConfigRepository? appConfig,
    String appVersion = '1.0.0',
    Settings? settings,
    FakeTrailRepository? trails,
    FakePoiSource? pois,
    FakeOfficialTrailsSource? official,
    MemoryOfficialTrailsCache? officialCache,
    Position? position,
    FakePositionFix? positionFix,
    FakeRideStore? rideStore,
    FakeRideFix? rideFix,
    FakeRideServiceBridge? rideBridge,
    FakeRideService? rideService,
    FakeOutbox? outbox,
    FakeTrailCache? trailCache,
    MemoryAreaStore? areaStore,
    FakeKeepAlive? keepAlive,
    Stream<List<ConnectivityResult>>? connectivity,
    FakePushRepository? push,
    Stream<RemoteMessage>? pushMessages,
    bool useRealMap = false,
    List<Override> extraOverrides = const []}) async {
  addTearDown(backend.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: overridesFor(backend,
        appConfig: appConfig,
        appVersion: appVersion,
        settings: settings,
        trails: trails,
        pois: pois,
        official: official,
        officialCache: officialCache,
        position: position,
        positionFix: positionFix,
        rideStore: rideStore,
        rideFix: rideFix,
        rideBridge: rideBridge,
        rideService: rideService,
        outbox: outbox,
        trailCache: trailCache,
        areaStore: areaStore,
        keepAlive: keepAlive,
        connectivity: connectivity,
        push: push,
        pushMessages: pushMessages,
        useRealMap: useRealMap,
        extra: extraOverrides),
    child: const TrailBuddyApp(),
  ));
  await tester.pump();
  await settle(tester);
}

/// Auf einen Reiter wechseln — über die Leiste und nicht über den
/// nackten Text: „Trails" und „Profil" stehen auch im Inhalt (AppBar-
/// Titel, Überschriften), `find.text` träfe dann zwei Widgets.
Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text(label)));
  await settle(tester);
}

/// Feste Frames statt pumpAndSettle — die Karte animiert (Attribution,
/// Kamera), pumpAndSettle käme dort nicht zuverlässig zurück.
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Den S-Grad-Bereich der Trail-Filter (#222) über die Oberfläche setzen:
/// Chip antippen, im Blatt die Schieber ziehen, „Fertig". Gezogen wird
/// von der Stelle des Daumens um so viele Stufen, wie fehlen — der
/// Schieber rastet auf ganze Grade ein, ein paar Pixel Rand verzeihen.
Future<void> setGradeRange(WidgetTester tester,
    {int min = 0, int max = 5, String keyPrefix = 'trail'}) async {
  await tester.tap(find.byKey(ValueKey('$keyPrefix-filter-grade')));
  await settle(tester);
  final slider = find.byKey(const ValueKey('grade-range-slider'));
  Future<void> drag(double from, double to) async {
    final rect = tester.getRect(slider);
    const pad = 24.0;
    final track = rect.width - 2 * pad;
    final start = Offset(rect.left + pad + track * from / 5, rect.center.dy);
    await tester.dragFrom(start, Offset(track * (to - from) / 5, 0));
    await settle(tester);
  }

  final values = tester.widget<RangeSlider>(slider).values;
  if (values.end != max) await drag(values.end, max.toDouble());
  if (values.start != min) await drag(values.start, min.toDouble());
  final now = tester.widget<RangeSlider>(slider).values;
  expect((now.start, now.end), (min.toDouble(), max.toDouble()), reason: 'Schieber gezogen');
  await tester.tap(find.byKey(const ValueKey('grade-range-done')));
  await settle(tester);
}

/// Lässt die Wartezeit des „Erneut senden"-Knopfes ablaufen (ResendButton
/// startet gesperrt, weil gerade eine Mail rausging). Sekundenweise pumpen,
/// damit der Timer wirklich jede Sekunde feuert — ein Sprung um 60 s würde
/// nur einen Tick auslösen und den Countdown bei 59 stehen lassen.
Future<void> passResendCooldown(WidgetTester tester, {int seconds = 61}) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

/// SnackBar-Timer auslaufen lassen, damit am Testende nichts mehr tickt.
Future<void> drainSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Scrollt die erste Liste des Bildschirms, bis [finder] etwas trifft —
/// eine `ListView` baut nur, was im Bild ist, ein Eintrag weiter unten
/// existiert also erst nach dem Heranscrollen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 8 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle(tester, frames: 4);
  }
  await tester.ensureVisible(finder);
  await settle(tester);
}

/// Ein Widget mit dieser Beschriftung für Bildschirmleser. Die Kennzahl-
/// Kacheln des Trail-Blatts (seit 0.39.0) zeigen „S2" und „S1–S3 · 4×",
/// ihre Aussage „S2 · S1–S3 · 4 Einschätzungen" steht als Beschriftung
/// an der Kachel — geprüft wird derselbe Satz wie vorher im Chip.
Finder findLabel(String label) =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

/// Eine Unterseite des Profils öffnen (seit 0.41.0, Design 1l): Reiter
/// „Profil", dann die Zeile [id] (`profile-<id>`: account,
/// notifications, appearance, about, import, rides, areas).
Future<void> openProfilePage(WidgetTester tester, String id) async {
  await openTab(tester, 'Profil');
  final row = find.byKey(ValueKey('profile-$id'));
  await scrollTo(tester, row);
  await tester.tap(row);
  await settle(tester);
}
