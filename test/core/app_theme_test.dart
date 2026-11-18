// Die Palette hell und dunkel: Kontraste nach WCAG, das Theme je Modus,
// und die Einstellung „Erscheinungsbild" samt Merken.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/app_theme.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final p in [AppColors.light, AppColors.dark]) {
    group('Palette ${p.brightness.name}', () {
      final grounds = {
        'Grund': p.ground,
        'Fläche': p.surface,
        'Fläche 2': p.surface2,
      };
      final texts = {
        'Text': p.text,
        'gedämpft': p.muted,
        'Marke als Text': p.accentText,
        'Warnung als Text': p.warningText,
        'Buddy als Text': p.buddyText,
        'Hinweis als Text': p.noteText,
      };
      for (final g in grounds.entries) {
        for (final t in texts.entries) {
          test('${t.key} auf ${g.key} ≥ 4,5:1', () {
            expect(contrast(t.value, g.value), greaterThanOrEqualTo(4.5));
          });
        }
      }

      test(
        'Schwierigkeitsfarben: Streifen auf Fläche und Grund ≥ 3:1, Schild-Schrift ≥ 4,5:1',
        () {
          for (var g = 0; g <= 5; g++) {
            final c = p.grade.of(g);
            expect(
              contrast(c, p.surface),
              greaterThanOrEqualTo(3),
              reason: 'S$g',
            );
            expect(
              contrast(c, p.ground),
              greaterThanOrEqualTo(3),
              reason: 'S$g',
            );
            expect(
              contrast(p.grade.ink, c),
              greaterThanOrEqualTo(4.5),
              reason: 'S$g',
            );
          }
          expect(
            contrast(p.grade.ungraded, p.surface),
            greaterThanOrEqualTo(3),
          );
          expect(contrast(p.grade.uphill, p.surface), greaterThanOrEqualTo(3));
          expect(contrast(p.grade.uphill, p.ground), greaterThanOrEqualTo(3));
          expect(
            contrast(p.grade.ink, p.grade.uphill),
            greaterThanOrEqualTo(4.5),
          );
          // Uphill hat eine eigene Farbe, keine der Stufen.
          expect([
            for (var g = 0; g <= 5; g++) p.grade.of(g),
          ], isNot(contains(p.grade.uphill)));
          // Vier verschiedene Stufenfarben, sonst sagt die Farbe nichts.
          expect({for (var g = 0; g <= 3; g++) p.grade.of(g)}, hasLength(4));
        },
      );

      test('Symbole in Beziehungsfarbe auf Fläche ≥ 3:1', () {
        for (final c in [p.map.mine, p.map.buddy, p.map.warning]) {
          expect(contrast(c, p.surface), greaterThanOrEqualTo(3), reason: '$c');
        }
      });

      test(
        'das Theme trägt die Palette, der Knopf ist Lime mit dunkler Schrift',
        () {
          final theme = buildAppTheme(p);
          expect(theme.brightness, p.brightness);
          expect(theme.extension<AppPalette>(), same(p));
          expect(theme.scaffoldBackgroundColor, p.ground);
          final style = theme.filledButtonTheme.style!;
          expect(style.backgroundColor!.resolve({}), AppColors.brand);
          expect(style.foregroundColor!.resolve({}), AppColors.onBrand);
          expect(theme.textTheme.titleLarge!.fontFamily, AppFonts.display);
          expect(theme.textTheme.bodyMedium!.fontFamily, AppFonts.body);
          // Der Titel der Leiste trägt seine Größe selbst — `textTheme`
          // bekommt sie erst in `Theme.of`, dieser Stil nie (bis 0.37.0:
          // 14 px).
          expect(theme.appBarTheme.titleTextStyle!.fontSize, 22);
          expect(
            theme.appBarTheme.titleTextStyle!.fontFamily,
            AppFonts.display,
          );
        },
      );

      test(
        'die Leiste unten: Text und Aktion ≥ 4,5:1, die Aktion in der Marke',
        () {
          final bar = buildAppTheme(p).snackBarTheme;
          expect(bar.actionTextColor, AppColors.brand);
          expect(
            contrast(bar.contentTextStyle!.color!, bar.backgroundColor!),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(bar.actionTextColor!, bar.backgroundColor!),
            greaterThanOrEqualTo(4.5),
          );
        },
      );
    });
  }

  test('Schrift auf dem Knopf ≥ 4,5:1', () {
    expect(
      contrast(AppColors.onBrand, AppColors.brand),
      greaterThanOrEqualTo(4.5),
    );
    // Die Buchstaben-Avatare anderer (Design 1k): dunkle Schrift auf jeder
    // Fläche, und nie Lime — Lime heißt „mein".
    for (final fill in AppColors.avatarFills) {
      expect(
        contrast(AppColors.onBrand, fill),
        greaterThanOrEqualTo(4.5),
        reason: '$fill',
      );
      expect(fill, isNot(AppColors.brand));
    }
  });

  test('die Karte ist hell: ihre Linien haben einen weißen Saum', () {
    expect(AppColors.mapLines, same(MapPalette.light));
    expect(AppColors.mapLines.halo, Colors.white);
    // Die Karte ist hell: dort gilt der helle Stufensatz, ≥ 3:1 auf dem Landton.
    expect(AppColors.mapGrades, same(GradePalette.light));
    for (var g = 0; g <= 5; g++) {
      expect(
        contrast(AppColors.mapGrades.of(g), AppColors.mapBackground),
        greaterThanOrEqualTo(3),
        reason: 'S$g',
      );
    }
    expect(
      contrast(AppColors.mapGrades.uphill, AppColors.mapBackground),
      greaterThanOrEqualTo(3),
    );
    expect(AppColors.mapLines.haloBorderWidth * 2, 4, reason: 'Breite + 4');
    expect(MapPalette.dark.haloBorderWidth, 0);
  });

  test(
    'Uphill liegt im Farbton weit weg von den Stufen und von offiziell (#195)',
    () {
      // Das Petrol bis 0.77.1 lag 35° neben S0-Grün und sah auf der Karte
      // gleich aus.
      double hueGap(Color a, Color b) {
        final d =
            (HSVColor.fromColor(a).hue - HSVColor.fromColor(b).hue).abs() % 360;
        return math.min(d, 360 - d);
      }

      for (final (grades, lines) in [
        (GradePalette.light, MapPalette.light),
        (GradePalette.dark, MapPalette.dark),
      ]) {
        for (final other in [
          grades.s0,
          grades.s1,
          grades.s2,
          lines.official,
          lines.mine,
          lines.buddy,
        ]) {
          expect(
            hueGap(grades.uphill, other),
            greaterThanOrEqualTo(40),
            reason: '$other',
          );
        }
      }
    },
  );

  test('ein unbekannter Wert gilt als System', () {
    expect(parseThemeMode(null), ThemeMode.system);
    expect(parseThemeMode('quatsch'), ThemeMode.system);
    expect(parseThemeMode('dark'), ThemeMode.dark);
  });

  testWidgets(
    'Erscheinungsbild: aus der Einstellung gelesen, umgeschaltet, gemerkt',
    (tester) async {
      final backend = FakeBackend();
      final me = backend.addUser(username: 'testrail');
      backend.signInAs(me.id);
      final settings = FakeSettings(appearance: 'dark');
      await pumpApp(tester, backend, settings: settings);

      Brightness brightness() =>
          Theme.of(tester.element(find.byType(NavigationBar))).brightness;
      expect(brightness(), Brightness.dark);

      await openProfilePage(tester, 'appearance');
      await tester.tap(find.text('Hell'));
      await settle(tester);
      expect(brightness(), Brightness.light);
      expect(settings.appearance, 'light');

      await tester.tap(find.text('System'));
      await settle(tester);
      expect(settings.appearance, 'system');
    },
  );
}
