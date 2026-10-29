import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/elevation_profile_chart.dart';
import 'package:trailbuddy/features/trails/trail_elevation.dart';
import 'package:trailbuddy/l10n/app_localizations.dart';

void main() {
  // Erfundene Linie, 0,01° nach Osten (~740 m), 384 m oben, 180 m unten.
  final profile = ElevationProfile.of(
    [for (var i = 0; i <= 10; i++) LatLng(48, 9 + i * 0.001)],
    [for (var i = 0; i <= 10; i++) i == 3 ? 384.0 : 180.0 + i],
  )!;

  Future<void> pump(WidgetTester tester, double cursorM) async {
    tester.view.physicalSize = const Size(411, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevationProfileChart(profile, compact: true, cursorM: cursorM, onScrub: (_) {}),
        ),
      ),
    ));
  }

  // #412: In der Ecke oben links lag das Etikett direkt an „384 m".
  for (final share in [0.0, 0.2, 0.5, 0.6, 0.9, 1.0]) {
    testWidgets('Etikett der Stelle bei ${(share * 100).round()} % liegt neben dem Strich, nie an der Achse',
        (tester) async {
      await pump(tester, share * profile.lengthM);
      final label = tester.getRect(find.byKey(const ValueKey('elevation-cursor-label')));
      final chart = tester.getRect(find.byKey(const ValueKey('elevation-profile')));
      for (final axis in ['384 m', '180 m']) {
        final r = tester.getRect(find.text(axis));
        expect(label.overlaps(r.inflate(2)), isFalse, reason: '$axis frei');
      }
      expect(label.left, greaterThanOrEqualTo(chart.left), reason: 'in der Zeichnung, nicht in der Achsenspalte');
      expect(label.right, lessThanOrEqualTo(chart.right + 0.01));
      final x = chart.left + share * chart.width;
      if (label.width + 6 <= chart.right - x || label.width + 6 <= x - chart.left) {
        expect(x > label.left && x < label.right, isFalse, reason: 'der Strich bleibt frei');
        final beside = (label.left - x).abs() < (label.right - x).abs() ? label.left - x : x - label.right;
        expect(beside, closeTo(6, 0.5), reason: 'direkt neben dem Strich, nicht in einer Ecke');
      }
    });
  }
}
