// Das Logo „Serpentine C3" (docs/design/trailbuddy-logo) hat EINE
// Geometrie: tool/brand/logo_c3.json. tool/brand_icons.py erzeugt daraus
// die Dart-Konstanten und alle App-Symbole (`--check` in CI hält beides
// als Fixpunkt). Hier wird festgehalten, dass Dart dieselben Zahlen
// liest, die Form stimmt und die Symbole dort liegen, wo Android und das
// Web sie suchen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/app_theme.dart';
import 'package:trailbuddy/core/widgets/trailbuddy_logo.dart';

const _res = 'android/app/src/main/res';

void main() {
  final json =
      jsonDecode(File('tool/brand/logo_c3.json').readAsStringSync())
          as Map<String, dynamic>;

  test('Dart liest dieselbe Geometrie wie der Generator', () {
    for (final (key, size) in [
      ('L', LogoSize.l),
      ('M', LogoSize.m),
      ('S', LogoSize.s),
    ]) {
      final g = json[key] as Map<String, dynamic>;
      final geo = LogoGeometry.of(size);
      expect(geo.length, g['length'], reason: key);
      expect(geo.total, g['total'], reason: key);
      final samples = [
        for (final s in g['samples'] as List)
          ...(s as List).cast<num>().map((v) => v.toDouble()),
      ];
      expect(geo.samples, samples, reason: key);
      expect(geo.dashes.length, (g['dashes'] as List).length, reason: key);
    }
  });

  test('drei optische Größen: L zwei Endstriche, M einer, S keiner', () {
    expect(logoSizeFor(64), LogoSize.l);
    expect(logoSizeFor(32), LogoSize.l);
    expect(logoSizeFor(24), LogoSize.m);
    expect(logoSizeFor(20), LogoSize.m);
    expect(logoSizeFor(18), LogoSize.s);
    expect(LogoGeometry.of(LogoSize.l).dashes.length, 2);
    expect(LogoGeometry.of(LogoSize.m).dashes.length, 1);
    expect(LogoGeometry.of(LogoSize.s).dashes, isEmpty);
    expect(
      LogoGeometry.of(LogoSize.s).total,
      LogoGeometry.of(LogoSize.s).length,
    );
  });

  test('die Form liegt mittig im 100er-Raster und wird schmaler', () {
    for (final size in LogoSize.values) {
      final geo = LogoGeometry.of(size);
      final b = geo.range(0, geo.total).getBounds();
      expect(b.left, greaterThan(10), reason: '$size');
      expect(b.right, lessThan(90), reason: '$size');
      expect(b.top, greaterThan(10), reason: '$size');
      expect(b.bottom, lessThan(90), reason: '$size');
      expect(b.center.dx, closeTo(50, 2), reason: '$size');
      expect(b.center.dy, closeTo(50, 2), reason: '$size');
    }
    final l = LogoGeometry.of(LogoSize.l).samples;
    expect(l[4] + l[5], closeTo(11, 1e-9), reason: 'Anfang 11 breit');
    expect(
      l[l.length - 2] + l[l.length - 1],
      closeTo(8, 1e-9),
      reason: 'Ende 8 breit',
    );
  });

  test(
    'ein Abschnitt ohne Endstriche ist nur Strecke, einer dahinter nur Strich',
    () {
      final geo = LogoGeometry.of(LogoSize.l);
      final ende = geo.pointAt(geo.length);
      final striche = geo.range(geo.length, geo.total).getBounds();
      expect(
        striche.left,
        greaterThan(ende.dx + 4),
        reason: 'die Endstriche liegen rechts vom Ende, mit Luft',
      );
      final letzter = geo.dashes.last;
      final strich = geo.range(letzter.c0, geo.total).getBounds();
      expect(strich.height, closeTo(letzter.w, 1e-9));
      expect(
        geo.range(geo.total + 1, geo.total + 40).getBounds().isEmpty,
        isTrue,
      );
      expect(geo.pointAt(0), Offset(geo.samples[0], geo.samples[1]));
    },
  );

  test('Statusleisten-Symbol: weiß, nur Alpha, eine gefüllte Fläche', () {
    final xml = File('$_res/drawable/ic_notification.xml').readAsStringSync();
    expect('<path'.allMatches(xml).length, 1);
    expect(xml, isNot(contains('strokeColor')));
    final colors = RegExp(
      r'android:(?:fill|stroke)Color="(#[0-9A-Fa-f]+)"',
    ).allMatches(xml).map((m) => m.group(1)).toSet();
    expect(colors, {'#FFFFFFFF'});
  });

  test(
    'adaptives App-Symbol: Lime-Grund, dunkles Zeichen, Themen-Variante',
    () {
      final adaptive = File(
        '$_res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      expect(adaptive, contains('@color/ic_launcher_background'));
      expect(adaptive, contains('@drawable/ic_launcher_foreground'));
      expect(adaptive, contains('@drawable/ic_launcher_monochrome'));
      final colors = File('$_res/values/colors.xml').readAsStringSync();
      expect(
        colors,
        contains('<color name="ic_launcher_background">#B6F04A</color>'),
      );
      expect(AppColors.brand, const Color(0xFFB6F04A));
      final fg = File(
        '$_res/drawable/ic_launcher_foreground.xml',
      ).readAsStringSync();
      expect(fg, contains('android:fillColor="#FF0E1411"'));
      for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(
          File('$_res/mipmap-$d/ic_launcher.png').existsSync(),
          isTrue,
          reason: d,
        );
      }
    },
  );

  test('Startschirm ab Android 12: das Zeichen in der Marke des Modus', () {
    for (final v in ['values-v31', 'values-night-v31']) {
      expect(
        File('$_res/$v/styles.xml').readAsStringSync(),
        contains(
          '<item name="android:windowSplashScreenAnimatedIcon">@drawable/ic_splash</item>',
        ),
        reason: v,
      );
    }
    expect(
      File('$_res/drawable/ic_splash.xml').readAsStringSync(),
      contains('@color/brand_mark'),
    );
    expect(
      File('$_res/values/colors.xml').readAsStringSync(),
      contains('<color name="brand_mark">#4F8A10</color>'),
    );
    expect(
      File('$_res/values-night/colors.xml').readAsStringSync(),
      contains('<color name="brand_mark">#B6F04A</color>'),
    );
    expect(AppColors.light.brandMark, const Color(0xFF4F8A10));
    expect(AppColors.dark.brandMark, AppColors.brand);
  });

  test('Web: SVG-Favicon vor der PNG, beide im Service Worker', () {
    final html = File('web/index.html').readAsStringSync();
    final svg = html.indexOf('href="favicon.svg"');
    expect(svg, greaterThan(0));
    expect(svg, lessThan(html.indexOf('href="favicon.png"')));
    final sw = File('web/sw.js').readAsStringSync();
    expect(sw, contains("'favicon.svg',"));
    expect(sw, contains("'favicon.png',"));
  });

  testWidgets('Zeichen und Wortmarke lesen die Palette des Modus', (
    tester,
  ) async {
    for (final p in [AppColors.light, AppColors.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(p),
          home: const Column(
            children: [TrailBuddyMark(), TrailBuddyWordmark()],
          ),
        ),
      );
      await tester.pumpAndSettle(); // das Theme blendet über
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(TrailBuddyMark),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as LogoPainter;
      expect(painter.color, p.brandMark);
      expect(painter.geometry, LogoGeometry.of(LogoSize.l));
      expect(find.bySemanticsLabel('TrailBuddy'), findsNWidgets(2));
    }
  });

  testWidgets('klein gezeichnet nimmt das Zeichen die kleinere Form', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppColors.dark),
        home: const Row(
          children: [TrailBuddyMark(size: 24), TrailBuddyMark(size: 16)],
        ),
      ),
    );
    final painters = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(TrailBuddyMark),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((c) => (c.painter! as LogoPainter).geometry)
        .toList();
    expect(painters, [
      LogoGeometry.of(LogoSize.m),
      LogoGeometry.of(LogoSize.s),
    ]);
  });
}
