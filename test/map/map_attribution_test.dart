// Der Quellenhinweis der MapLibre-Karte: jede Angabe einmal, egal wie viele
// Quellen (gespeicherte Bereiche) die Karte hat.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/app_theme.dart';
import 'package:trailbuddy/features/map/map_view/map_attribution.dart';
import 'package:trailbuddy/l10n/l10n.dart';

void main() {
  test('jede Angabe genau einmal, OSM mit Lizenz', () {
    final lines = mapAttributionLines(['Land X (CC BY)', 'Land X (CC BY)', 'Protomaps']);
    expect(lines, ['MapLibre', '© OpenStreetMap-Mitwirkende (ODbL)', 'Protomaps', 'Land X (CC BY)']);
  });

  testWidgets('zu, bis man auf das i tippt; Tippfläche 44 px', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(AppColors.light),
      home: Scaffold(body: MapAttribution(lines: mapAttributionLines(const []))),
    ));
    final button = find.byKey(const ValueKey('map-attribution'));
    expect(tester.getSize(button), const Size.square(44));
    expect(find.textContaining('OpenStreetMap'), findsNothing);
    await tester.tap(button);
    await tester.pump();
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
  });
}
