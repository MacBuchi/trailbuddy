// Die eigene Position auf der Karte, und eine Karte, die sich nicht
// dreht. Gefragt wird nach dem Standort nur über „Meine Position".
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trailbuddy/features/map/position_provider.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
  });

  final dot = find.byKey(const ValueKey('my-position'));

  testWidgets('die Karte dreht sich nicht (flutter_map-Engine)', (tester) async {
    // flutter_map-Interna: hier läuft die echte Engine des Web-Pfads.
    await pumpApp(tester, backend, useRealMap: true);
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final flags = map.options.interactionOptions.flags;
    expect(flags & InteractiveFlag.rotate, 0);
    expect(flags & InteractiveFlag.pinchZoom, isNot(0));
    expect(flags & InteractiveFlag.drag, isNot(0));
  });

  testWidgets('ohne Berechtigung: kein Punkt, und beim Start wird nicht gefragt',
      (tester) async {
    final fix = FakePositionFix();
    await pumpApp(tester, backend, positionFix: fix);
    expect(dot, findsNothing);
    expect(fix.calls, 0);

    await tester.tap(find.byTooltip('Meine Position'));
    await settle(tester);
    expect(fix.calls, 1);
    expect(find.textContaining('Position nicht verfügbar'), findsOneWidget);
    await drainSnackbars(tester);
  });

  // #400: Hat der Browser den Standort gesperrt, fragt er nie wieder von
  // selbst. Die Meldung muss sagen, wo man ihn freigibt — „für TrailBuddy
  // nicht erlaubt" schickte in die App-Einstellungen, die es im Browser
  // nicht gibt.
  testWidgets('im Browser gesperrt: die Meldung nennt die Adressleiste',
      (tester) async {
    final fix = FakePositionFix();
    await pumpApp(tester, backend,
        positionFix: fix,
        extraOverrides: [locationBlockedProvider.overrideWithValue(() async => true)]);

    await tester.tap(find.byTooltip('Meine Position'));
    await settle(tester);
    expect(fix.calls, 1);
    expect(find.textContaining('Adressleiste'), findsOneWidget);
    expect(find.textContaining('Position nicht verfügbar'), findsNothing);
    await drainSnackbars(tester);
  });

  testWidgets('mit Position: Punkt auf der Karte, „Meine Position" zentriert',
      (tester) async {
    final here = fakePosition(47.2, 11.4);
    final fix = FakePositionFix(here);
    await pumpApp(tester, backend, position: here, positionFix: fix);
    await settle(tester);
    expect(dot, findsOneWidget);
    expect(fix.calls, 0, reason: 'der Punkt allein fragt nie');
    // Der Genauigkeitskreis in Metern — er wächst mit der Karte.
    final circle = fakeMapLayers(tester).circles.single;
    expect(circle.radiusM, 8);
    // Der Punkt meldet nichts: ein Tipp darauf gilt der Karte.
    final marker = fakeMapLayers(tester).markers.single;
    expect(marker.hitValue, isNull);

    await tester.tap(find.byTooltip('Meine Position'));
    await settle(tester, frames: 12);
    final c = fakeMap(tester);
    expect(c.center.latitude, closeTo(47.2, 1e-6));
    expect(c.center.longitude, closeTo(11.4, 1e-6));
    expect(c.zoom, 15);
  });
}
