// Fahrt aufzeichnen (#28): vom Knopf auf der Karte über den Service bis
// zur Liste im Profil — und zurück nach einem Prozess-Kill.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/map/map_buttons.dart';
import 'package:trailbuddy/features/map/map_screen.dart' show kRidePulseExtent;
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_task_handler.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_rides.dart';
import '../fakes/test_app.dart';

const _portName = 'flutter_foreground_task/isolateComPort';

void main() {
  late FakeBackend backend;
  late String annaId;
  late FakeRideStore store;
  late FakeRideFix fix;
  late FakeRideServiceBridge bridge;
  late FakeRideService service;

  final t0 = DateTime.utc(2026, 9, 28, 10);
  RidePoint pt(int i) => RidePoint(
      lat: 47.2 + i * 50 / 111195.0, lng: 11.4, at: t0.add(Duration(seconds: 5 * i)),
      accuracyM: 5, altM: 800.0 - i);

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    annaId = anna.id;
    store = FakeRideStore();
    fix = FakeRideFix();
    bridge = FakeRideServiceBridge();
    service = FakeRideService();
  });

  tearDown(() {
    IsolateNameServer.removePortNameMapping(_portName);
  });

  Future<void> pump(WidgetTester tester, {List<Override> extra = const []}) => pumpApp(
      tester, backend,
      rideStore: store, rideFix: fix, rideBridge: bridge, rideService: service,
      extraOverrides: extra);

  /// Ein Messpunkt aus dem Service-Isolate — über denselben Port wie in
  /// echt, damit die Rückrichtung mitgeprüft ist.
  Future<void> tick(WidgetTester tester, RidePoint p) async {
    // Ein Port stellt über die ECHTE Ereignisschleife zu; unter der
    // Fake-Zeit des Widget-Tests käme die Meldung nie an.
    // Der Service hat den Punkt schon geschrieben, bevor er ihn meldet.
    await store.appendPoint(p);
    await tester.runAsync(() async {
      FlutterForegroundTask.sendDataToMain(encodeRideTick(p));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await settle(tester, frames: 3);
  }

  final button = find.byKey(const ValueKey('ride-button'));
  /// Die Spur auf der Karte: die Linien in der Fahrt-Farbe (ohne
  /// Kennung — ein Tipp gilt weiter dem Trail).
  List<MapViewPolyline> rideLines(WidgetTester tester) => [
        for (final l in fakeMapLayers(tester).polylines)
          if (l.hitValue == null && l.color.toARGB32() == AppColors.mapLines.ride.withValues(alpha: 0.75).toARGB32()) l,
      ];

  testWidgets('aufzeichnen, beenden, behalten — und die Fahrt steht im Profil',
      (tester) async {
    FlutterForegroundTask.initCommunicationPort();
    fix.next = pt(0);
    await pump(tester);
    expect(find.byTooltip('Fahrt aufzeichnen'), findsOneWidget);
    expect(find.byKey(const ValueKey('ride-status')), findsNothing);
    expect(service.running, isFalse);

    await tester.tap(button);
    await settle(tester);
    expect(find.textContaining('Fahrt läuft — der Weg'), findsOneWidget);
    expect(find.byTooltip('Fahrt beenden'), findsOneWidget);
    expect(find.byKey(const ValueKey('ride-status')), findsOneWidget);
    expect(bridge.armed, isTrue);
    expect(bridge.uid, annaId);
    expect(service.running, isTrue);
    expect(service.every, kRideTickInterval);
    expect(service.titles.last, 'Fahrt wird aufgezeichnet');
    expect(store.points, hasLength(1), reason: 'der erste Fix kommt aus dem Main-Isolate');
    expect(rideLines(tester), isEmpty, reason: 'eine Linie braucht zwei Punkte');

    await tick(tester, pt(1));
    await tick(tester, pt(2));
    expect(rideLines(tester), hasLength(1));
    expect(rideLines(tester).single.points, hasLength(3));
    expect(find.textContaining('Fahrt läuft · 100 m'), findsOneWidget);

    await drainSnackbars(tester);
    await tester.tap(button);
    await settle(tester);
    expect(find.text('Fahrt beendet'), findsOneWidget);
    expect(find.textContaining('100 m · '), findsOneWidget);
    expect(service.running, isFalse);
    expect(bridge.armed, isFalse);
    expect(store.rides, hasLength(1), reason: 'gespeichert VOR dem Blatt');

    await tester.tap(find.text('Behalten'));
    await settle(tester);
    expect(find.byKey(const ValueKey('ride-status')), findsNothing);
    expect(rideLines(tester), isEmpty);
    expect(store.rides, hasLength(1));

    await openTab(tester, 'Profil');
    await tester.tap(find.text('Meine Fahrten'));
    await settle(tester);
    expect(find.textContaining('100 m · '), findsOneWidget);
    expect(find.textContaining('3 Punkte'), findsOneWidget);

    // Auf der Karte zeigen: Reiter wechselt, die Fahrt liegt als Linie da.
    await tester.tap(find.byKey(ValueKey('ride-${store.rides.single.id}')));
    await settle(tester, frames: 12);
    expect(find.byKey(const ValueKey('focus-ride')), findsOneWidget);
    expect(rideLines(tester), hasLength(1));
    await tester.tap(find.byTooltip('Fahrt ausblenden'));
    await settle(tester);
    expect(rideLines(tester), isEmpty);
  });

  testWidgets('während der Fahrt pulst ein Ring um den Positionspunkt (Design 1r)',
      (tester) async {
    FlutterForegroundTask.initCommunicationPort();
    fix.next = pt(0);
    await pumpApp(tester, backend,
        position: fakePosition(47.2, 11.4),
        rideStore: store, rideFix: fix, rideBridge: bridge, rideService: service);
    await settle(tester);
    final pulse = find.byKey(const ValueKey('ride-pulse'));
    Size marker() {
      final m = fakeMapLayers(tester).markers.singleWhere((m) => m.key == const ValueKey('my-position'));
      return Size(m.width, m.height);
    }
    expect(pulse, findsNothing);
    expect(marker(), const Size(22, 22));

    await tester.tap(button);
    await settle(tester);
    expect(pulse, findsOneWidget);
    expect(find.bySemanticsLabel('Deine Position, Fahrt läuft'), findsOneWidget);
    // Die Markerfläche wächst mit dem Ring, sonst würde er beschnitten.
    expect(marker(), const Size(kRidePulseExtent, kRidePulseExtent));

    // Beendet (ein einzelner Punkt wird nicht gespeichert): kein Ring mehr.
    await drainSnackbars(tester);
    await tester.tap(button);
    await settle(tester);
    expect(pulse, findsNothing);
    expect(marker(), const Size(22, 22));
  });

  testWidgets('verwerfen löscht die Fahrt vom Gerät', (tester) async {
    FlutterForegroundTask.initCommunicationPort();
    fix.next = pt(0);
    await pump(tester);
    await tester.tap(button);
    await settle(tester);
    await tick(tester, pt(1));
    await drainSnackbars(tester);
    await tester.tap(button);
    await settle(tester);
    await tester.tap(find.text('Verwerfen'));
    await settle(tester);
    expect(store.rides, isEmpty);
  });

  testWidgets('löschen aus der Liste fragt nach', (tester) async {
    store.uid = annaId;
    store.rides.add(Ride(
        id: 'r1', startedAt: t0, endedAt: t0.add(const Duration(minutes: 40)),
        points: [pt(0), pt(1), pt(2)]));
    await pump(tester);
    await openTab(tester, 'Profil');
    await tester.tap(find.text('Meine Fahrten'));
    await settle(tester);
    expect(find.textContaining('40 min'), findsOneWidget);
    // Löschen liegt seit 0.68.0 im Zeilenmenü, neben dem Export (#150).
    await tester.tap(find.byTooltip('Mehr'));
    await settle(tester);
    await tester.tap(find.text('Fahrt löschen'));
    await settle(tester);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(store.rides, hasLength(1));
    await tester.tap(find.byTooltip('Mehr'));
    await settle(tester);
    await tester.tap(find.text('Fahrt löschen'));
    await settle(tester);
    await tester.tap(find.text('Löschen'));
    await settle(tester);
    expect(store.rides, isEmpty);
    expect(find.textContaining('Noch keine Fahrt'), findsOneWidget);
  });

  testWidgets('eine unterbrochene Fahrt läuft nach dem Neustart weiter', (tester) async {
    // Der Prozess-Kill: Auf der Platte liegt eine laufende Fahrt, die
    // App startet frisch.
    await store.begin(uid: annaId, startedAt: DateTime.now().toUtc());
    await store.appendPoint(pt(0));
    await store.appendPoint(pt(1));
    await pump(tester);
    await settle(tester);
    expect(find.byTooltip('Fahrt beenden'), findsOneWidget);
    expect(find.byKey(const ValueKey('ride-status')), findsOneWidget);
    expect(rideLines(tester), hasLength(1));
    expect(bridge.armed, isTrue, reason: 'der Service wird wieder aufgesetzt');
    expect(service.running, isTrue);
    expect(fix.calls, 0, reason: 'kein neuer Start, kein erster Fix');
  });

  group('Marken während der Aufnahme (#105)', () {
    final markButton = find.byKey(const ValueKey('ride-mark-button'));
    bool markActive(WidgetTester tester) => tester.widget<MapRoundButton>(markButton).active;

    testWidgets('erster Tipp „Trail beginnt", zweiter „Trail endet" — nur während der Fahrt',
        (tester) async {
      fix.next = pt(0);
      await pump(tester);
      expect(markButton, findsNothing, reason: 'ohne Fahrt keine Marke');

      await tester.tap(button);
      await settle(tester);
      await drainSnackbars(tester);
      expect(markButton, findsOneWidget);
      expect(find.byTooltip('Trail beginnt'), findsOneWidget);
      expect(markActive(tester), isFalse);

      await tester.tap(markButton);
      await settle(tester);
      expect(find.textContaining('Trail beginnt — markiert'), findsOneWidget);
      expect([for (final m in store.marks) m.kind], [RideMarkKind.start]);
      expect(find.byTooltip('Trail endet'), findsOneWidget);
      expect(markActive(tester), isTrue, reason: 'läuft ein Trail, trägt der Knopf den Rand');

      await tester.tap(markButton);
      await settle(tester);
      expect(find.textContaining('Trail endet — markiert'), findsOneWidget);
      expect([for (final m in store.marks) m.kind], [RideMarkKind.start, RideMarkKind.end]);
      expect(find.byTooltip('Trail beginnt'), findsOneWidget);
      expect(markActive(tester), isFalse);

      // Ein zweiter Punkt, sonst gilt die Fahrt als leer und wird verworfen.
      await store.appendPoint(pt(1));
      await drainSnackbars(tester);
      await tester.tap(button);
      await settle(tester);
      expect(store.rides.single.marks, hasLength(2), reason: 'die Marken gehören zur Fahrt');
      await tester.tap(find.text('Behalten'));
      await settle(tester);
      expect(markButton, findsNothing);
    });

    testWidgets('nach dem Neustart weiß der Knopf, dass ein Trail läuft', (tester) async {
      await store.begin(uid: annaId, startedAt: DateTime.now().toUtc());
      await store.appendPoint(pt(0));
      await store.appendMark(RideMark(kind: RideMarkKind.start, at: DateTime.now().toUtc()));
      await pump(tester);
      await settle(tester);
      expect(find.byTooltip('Trail endet'), findsOneWidget);
      expect(markActive(tester), isTrue);
    });

    testWidgets('nimmt die Datei die Marke nicht, steht sie auch nicht am Knopf', (tester) async {
      fix.next = pt(0);
      await pump(tester);
      await tester.tap(button);
      await settle(tester);
      await drainSnackbars(tester);
      store.failOnMark = true;
      await tester.tap(markButton);
      await settle(tester);
      expect(find.text('Die Marke ließ sich nicht speichern.'), findsOneWidget);
      expect(find.byTooltip('Trail beginnt'), findsOneWidget);
      expect(markActive(tester), isFalse);
    });
  });

  testWidgets('eine zu alte unterbrochene Fahrt zeichnet nicht weiter auf', (tester) async {
    await store.begin(
        uid: annaId, startedAt: DateTime.now().toUtc().subtract(const Duration(hours: 13)));
    await store.appendPoint(pt(0));
    await pump(tester);
    await settle(tester);
    expect(find.byTooltip('Fahrt beenden'), findsOneWidget, reason: 'offen, abschließbar');
    expect(bridge.armed, isFalse);
    expect(service.running, isFalse);
  });

  testWidgets('ohne Berechtigung startet nichts, und die Karte sagt es', (tester) async {
    await pump(tester, extra: [
      ridePermissionProvider.overrideWithValue(() async => RideStartResult.noPermission),
    ]);
    await tester.tap(button);
    await settle(tester);
    expect(find.textContaining('Ohne Standortberechtigung'), findsOneWidget);
    expect(service.running, isFalse);
    expect(store.startedAt, isNull, reason: 'keine Datei ohne Berechtigung');
    await drainSnackbars(tester);
  });

  testWidgets('ohne einen einzigen Standort wird nichts gespeichert', (tester) async {
    await pump(tester);
    await tester.tap(button);
    await settle(tester);
    await drainSnackbars(tester);
    await tester.tap(button);
    await settle(tester);
    expect(find.textContaining('nichts gespeichert'), findsOneWidget);
    expect(find.text('Fahrt beendet'), findsNothing);
    expect(store.rides, isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('wo es keinen Service gibt (Web), gibt es keinen Knopf', (tester) async {
    await pump(tester, extra: [rideRecordingAvailableProvider.overrideWithValue(false)]);
    expect(button, findsNothing);
    expect(find.byTooltip('Meine Position'), findsOneWidget);
  });

  testWidgets('im Web fragt der Kartenstart den Fahrt-Speicher gar nicht (#337)', (tester) async {
    // Im Browser wirft der echte Speicher (path_provider); hier steht
    // eine Fahrt drin, damit ein Zugriff sichtbar würde.
    await store.begin(uid: annaId, startedAt: DateTime.now().toUtc());
    await store.appendPoint(pt(0));
    await pump(tester, extra: [rideRecordingAvailableProvider.overrideWithValue(false)]);
    await settle(tester);
    expect(find.byKey(const ValueKey('ride-status')), findsNothing);
    expect(rideLines(tester), isEmpty);
    expect(bridge.armed, isFalse);
  });
}
