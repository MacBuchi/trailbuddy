// Bewegung (Design Turn 1p–1t): Die Keyframes rechnen pur, die Widgets
// laufen nur, wenn das System Bewegung will, und das Endbild ist immer
// vollständig — auch wenn nichts läuft.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/app_theme.dart';
import 'package:trailbuddy/core/widgets/motion.dart';
import 'package:trailbuddy/core/widgets/start_splash.dart';
import 'package:trailbuddy/core/widgets/trailbuddy_logo.dart';
import 'package:trailbuddy/features/friends/friends_screen.dart' show ConnectMergeMark, connectMergeAt;
import 'package:trailbuddy/features/map/map_screen.dart' show kRidePulseScale, ridePulseAt;

Widget _host(Widget child, {bool reduce = false}) => ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(AppColors.dark),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
            child: Scaffold(body: child),
          ),
        ),
      ),
    );

int _tickers() => SchedulerBinding.instance.transientCallbackCount;

void main() {
  group('1q Loader', () {
    final total = LogoGeometry.of(LogoSize.l).total;

    test('jeder Durchlauf zeigt das ganze Zeichen, bevor er ausblendet', () {
      const period = kLoaderDrawMs + kLoaderHoldMs + kLoaderFadeMs;
      expect(TrailLoader.period.inMilliseconds, period);
      expect(TrailLoader.period, lessThan(const Duration(milliseconds: 2000)), reason: 'schneller als bis 0.65.0');
      expect(loaderAt(0, total), (to: 0.0, opacity: 1.0), reason: 'beginnt leer');
      expect(loaderAt(0.2, total).to, greaterThan(loaderAt(0.1, total).to));
      // Stehen: ganz und deckend, vom Ende des Zeichnens bis zum Ausblenden.
      for (var ms = kLoaderDrawMs; ms <= kLoaderDrawMs + kLoaderHoldMs; ms += 10) {
        final s = loaderAt(ms / period, total);
        expect(s.to, closeTo(total, 1e-9));
        expect(s.opacity, 1);
      }
      // Ausblenden nur über dem ganzen Zeichen.
      for (var t = 0.0; t <= 1; t += 0.01) {
        final s = loaderAt(t, total);
        if (s.opacity < 1) expect(s.to, closeTo(total, 1e-9), reason: 'kein halbes Zeichen beim Ausblenden (t = $t)');
      }
      expect(loaderAt(1, total).opacity, closeTo(0, 1e-9), reason: 'am Ende zurück in der Spur');
    });

    testWidgets('läuft und sagt „Lädt …"', (tester) async {
      await tester.pumpWidget(_host(const CenteredTrailLoader()));
      expect(find.bySemanticsLabel('Lädt …'), findsOneWidget);
      expect(_tickers(), greaterThan(0));
    });

    testWidgets('mit reduzierter Bewegung steht er, sagt aber weiter „Lädt …"', (tester) async {
      await tester.pumpWidget(_host(const CenteredTrailLoader(), reduce: true));
      await tester.pump(const Duration(seconds: 1));
      expect(find.bySemanticsLabel('Lädt …'), findsOneWidget);
      expect(_tickers(), 0);
      final painter = tester
          .widgetList<CustomPaint>(find.descendant(of: find.byType(TrailLoader), matching: find.byType(CustomPaint)))
          .map((p) => p.painter)
          .whereType<LogoPainter>()
          .single;
      expect(painter.to, closeTo(painter.geometry!.total, 1e-9), reason: 'das ganze Zeichen, kein halbes');
      expect(painter.color.a, 1);
    });
  });

  group('1r Fahrt läuft', () {
    test('der Ring wächst vom Punkt auf das 3,2-Fache und blendet von 0,7 aus', () {
      expect(ridePulseAt(0), (scale: 1.0, opacity: 0.7));
      final end = ridePulseAt(1);
      expect(end.scale, closeTo(kRidePulseScale, 1e-9));
      expect(end.opacity, closeTo(0, 1e-9));
      expect(ridePulseAt(0.5).scale, greaterThan(1));
    });
  });

  group('1t Neuer Hinweis', () {
    test('der Schein atmet von 2 auf 6 px, außen von 0 auf 14 px', () {
      expect(glowAt(0), (inner: 2.0, outer: 0.0));
      expect(glowAt(1), (inner: 6.0, outer: 14.0));
    });

    testWidgets('mit reduzierter Bewegung ein ruhiger Schein, kein Takt', (tester) async {
      await tester.pumpWidget(_host(
          const BreathingGlow(color: Colors.yellow, radius: 14, child: SizedBox(width: 50, height: 20)),
          reduce: true));
      await tester.pump();
      expect(find.byKey(const ValueKey('breathing-glow')), findsOneWidget);
      expect(_tickers(), 0);
    });
  });

  group('1s Buddy verbunden', () {
    test('erst auseinander, dann eine Spur, dann der Punkt', () {
      expect(connectMergeAt(0), (apart: 1.0, dot: 0.0));
      expect(connectMergeAt(0.15).apart, 1);
      expect(connectMergeAt(0.55).apart, closeTo(0, 1e-9));
      expect(connectMergeAt(0.55).dot, 0, reason: 'der Punkt kommt NACH dem Zusammenlaufen');
      expect(connectMergeAt(0.75).dot, closeTo(1.25, 1e-5));
      expect(connectMergeAt(1).apart, 0);
      expect(connectMergeAt(1).dot, closeTo(1, 1e-5));
    });

    testWidgets('läuft einmal und hört auf', (tester) async {
      await tester.pumpWidget(_host(const ConnectMergeMark()));
      expect(_tickers(), greaterThan(0));
      await tester.pump(ConnectMergeMark.duration + const Duration(milliseconds: 100));
      expect(_tickers(), 0);
    });
  });

  group('1p Splash', () {
    test('das Endbild ist vollständig: Zeichen ganz, Wortmarke ganz', () {
      final end = splashAt(1);
      expect(end.draw, 1);
      expect(end.wipe, closeTo(1 + kSplashWipeEdge, 1e-9), reason: 'auch das letzte Zeichen ohne Kante');
      expect(splashAt(0), (draw: 0.0, wipe: 0.0));
      // 1,3 s von 1,78 s: das Zeichen steht, die Wortmarke hat begonnen.
      expect(splashAt(1300 / 1780).draw, closeTo(1, 1e-9));
      expect(splashAt(1300 / 1780).wipe, inExclusiveRange(0, 0.5));
      expect(splashAt(1200 / 1780).wipe, 0, reason: 'die Wortmarke wartet auf die Spitze');
      expect(splashAt(0.5).draw, closeTo(890 / 1300, 1e-9), reason: 'linear gezeichnet');
    });

    test('ein langes Bild verlangsamt, statt zu springen (#217)', () {
      const t = Duration(milliseconds: 400);
      expect(splashAdvance(t, const Duration(milliseconds: 16)), t + const Duration(milliseconds: 16));
      expect(splashAdvance(t, const Duration(milliseconds: 300)), t + kSplashMaxStep,
          reason: 'ein Bild, das die Startarbeit aufhält, schiebt die Zeichnung nur ein Stück');
      expect(splashAdvance(t, Duration.zero), t);
      expect(kSplashFade, const Duration(seconds: 1), reason: '#235: über 1 s ausblenden');
      expect(kSplashHold, greaterThanOrEqualTo(const Duration(milliseconds: 500)),
          reason: 'das ganze Bild steht, bevor es geht');
    });

    // Das Kind trägt KEINEN GlobalKey (anders als der Navigator unter
    // MaterialApp.home): Nur so zeigt der Test, dass der Splash die App
    // darunter nicht umhängt — ein GlobalKey rettete den Zustand sonst.
    Widget app({bool enabled = true, bool reduce = false}) => ProviderScope(
          overrides: [startSplashEnabledProvider.overrideWithValue(enabled)],
          child: MaterialApp(
            theme: buildAppTheme(AppColors.dark),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
                child: const StartSplash(child: _Counter()),
              ),
            ),
          ),
        );
    final splash = find.byKey(const ValueKey('start-splash'));

    testWidgets('liegt einmal über der App, die darunter schon läuft, und geht wieder',
        (tester) async {
      await tester.pumpWidget(app());
      expect(splash, findsOneWidget);
      expect(find.bySemanticsLabel('TrailBuddy'), findsWidgets);
      // Die App darunter ist schon gebaut und hat ihren Zustand — aber
      // sie zeichnet nicht, solange der Splash deckt (#217).
      final counter = find.byType(_Counter, skipOffstage: false);
      tester.state<_CounterState>(counter).bump();
      expect(find.byType(_Counter), findsNothing, reason: 'offstage unter dem deckenden Splash');
      // Bildweise weiter (je 50 ms — die Uhr des Splashs geht je Bild
      // höchstens so weit): Zeichnen 1,78 s, Stehen 0,6 s, Ausblenden 1 s.
      Future<void> frames(int n) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
      await frames(46);
      expect(splash, findsOneWidget, reason: 'nach 2,3 s steht das Bild noch');
      expect(find.byType(_Counter), findsNothing);
      await frames(4);
      expect(find.byType(_Counter), findsOneWidget, reason: 'beim Ausblenden ist die App darunter zu sehen');
      expect(splash, findsOneWidget, reason: 'und blendet über 1 s aus');
      await frames(22);
      expect(splash, findsNothing);
      expect(tester.state<_CounterState>(find.byType(_Counter)).count, 1, reason: 'derselbe Zustand — nichts neu eingehängt');
      expect(_tickers(), 0);
    });

    testWidgets('die Wortmarke hat einen echten Textstil, auch über dem Navigator',
        (tester) async {
      // Wie in app.dart: im Builder, also ohne Material der Seite darüber.
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(AppColors.dark),
          builder: (context, child) => StartSplash(child: child!),
          home: const _Counter(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      final word = find.byType(TrailBuddyWordmark);
      expect(word, findsOneWidget);
      final style = DefaultTextStyle.of(tester.element(word)).style;
      expect(style.debugLabel ?? '', isNot(contains('fallback')),
          reason: 'sonst gelb doppelt unterstrichen');
    });

    testWidgets('ein Tipp überspringt ihn', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(splash);
      await tester.pump(); // das Ausblenden beginnt im nächsten Bild
      await tester.pump(kSplashSkipFade + const Duration(milliseconds: 50));
      expect(splash, findsNothing);
    });

    testWidgets('bei reduzierter Bewegung und im Test-Harness gibt es ihn nicht', (tester) async {
      await tester.pumpWidget(app(reduce: true));
      expect(splash, findsNothing);
      await tester.pumpWidget(Container());
      await tester.pumpWidget(app(enabled: false));
      expect(splash, findsNothing);
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var count = 0;
  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('$count', textDirection: TextDirection.ltr);
}
