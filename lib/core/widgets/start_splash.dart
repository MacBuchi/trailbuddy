// Der Splash („Splash B" aus docs/design/trailbuddy-logo): Das Zeichen
// zeichnet sich in 1,3 s ein, und sobald die Spitze den letzten Endstrich
// erreicht, baut sich die Wortmarke daneben von links nach rechts auf —
// als Fortsetzung des Trails. Einmal je App-Start, 1,78 s, dann steht das
// ganze Bild 0,6 s und blendet über 1 s aus (#235: vorher war es weg,
// bevor man es lesen konnte).
//
// Flüssig, auch wenn die App darunter beim Start arbeitet (#217): Die Uhr
// des Splashs geht je Bild höchstens [kSplashMaxStep] weiter. Ein Bild,
// das die Startarbeit 300 ms aufhält, lässt die Zeichnung kurz warten,
// statt ein Stück zu überspringen — der Sprung war das Ruckeln. Und
// solange er deckt, zeichnet die App darunter nicht (`Offstage`): gebaut
// und ausgelegt wird sie weiter, gerastert wird nur der Splash.
//
// Er liegt ÜBER der App, statt vor ihr zu stehen: Anmeldung, Karte und
// Trails laden darunter schon, der Splash kostet also keine Wartezeit,
// die es ohne ihn nicht gäbe. Ein Tipp überspringt ihn, und bei
// reduzierter Bewegung gibt es ihn gar nicht — ein stehendes Logo vor der
// App wäre nur eine Pause.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_colors.dart';
import 'motion.dart';
import 'trailbuddy_logo.dart';

/// Ob der Splash beim Start läuft. Der Test-Harness schaltet ihn ab — er
/// läge sonst über jedem Flow-Test und schluckte die ersten Tipps.
final startSplashEnabledProvider = Provider<bool>((ref) => true);

/// Dauer der Animation selbst, des stehenden Bilds danach und des
/// Ausblendens; ein Tipp blendet schneller aus.
const kSplashDuration = Duration(milliseconds: 1780);
const kSplashHold = Duration(milliseconds: 600);
const kSplashFade = Duration(milliseconds: 1000);
const kSplashSkipFade = Duration(milliseconds: 250);

/// So weit geht die Uhr des Splashs je Bild höchstens — drei Bilder bei
/// 60 Hz. Ein längeres Bild verlangsamt, statt zu springen.
const kSplashMaxStep = Duration(milliseconds: 50);

/// Die Uhr des Splashs nach einem Bild von [frame]: [elapsed] plus das
/// Bild, gedeckelt auf [kSplashMaxStep]. Pur, damit der Test ohne Pixel
/// prüfen kann, dass ein langes Bild nichts überspringt.
Duration splashAdvance(Duration elapsed, Duration frame) =>
    elapsed + Duration(microseconds: math.max(0, math.min(frame.inMicroseconds, kSplashMaxStep.inMicroseconds)));

/// Zeitpunkte aus dem Entwurf: Zeichnen 0…1,3 s linear, die Wortmarke ab
/// 1,26 s in 0,52 s (`easeOutQuad`) mit weicher Kante.
const _drawMs = 1300.0;
const _wipeStartMs = 1260.0;
const _wipeMs = 520.0;

/// Breite der weichen Kante der Wortmarke, Anteil ihrer Breite.
const kSplashWipeEdge = 0.14;

/// Stand des Splashs bei [t] (0…1 über [kSplashDuration]): wie viel des
/// Zeichens steht (`draw`, 0…1) und wo die Kante der Wortmarke ist
/// (`wipe`, 0…1 + [kSplashWipeEdge] — erst dann ist auch das letzte
/// Zeichen ganz da). Pur, damit der Test ohne Pixel prüfen kann, dass das
/// Endbild vollständig ist.
({double draw, double wipe}) splashAt(double t) {
  final ms = t.clamp(0.0, 1.0) * kSplashDuration.inMilliseconds;
  final draw = (ms / _drawMs).clamp(0.0, 1.0);
  // Kurveneingänge klemmen: Gleitkomma liegt sonst knapp über 1, und die
  // Kurve lehnt das ab.
  final w = ((ms - _wipeStartMs) / _wipeMs).clamp(0.0, 1.0);
  return (draw: draw, wipe: Curves.easeOutQuad.transform(w) * (1 + kSplashWipeEdge));
}

class StartSplash extends ConsumerStatefulWidget {
  const StartSplash({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StartSplash> createState() => _StartSplashState();
}

class _StartSplashState extends ConsumerState<StartSplash> with TickerProviderStateMixin {
  late final _draw = AnimationController(vsync: this, duration: kSplashDuration);
  late final _fade = AnimationController(vsync: this, duration: kSplashFade, value: 1);
  late final Ticker _clock = createTicker(_tick);

  /// Die eigene Uhr: Summe der gedeckelten Bilder seit dem Start.
  Duration _elapsed = Duration.zero;
  Duration _lastFrame = Duration.zero;

  /// null: noch nicht entschieden (vor dem ersten Build); danach, ob er
  /// noch liegt.
  bool? _showing;

  /// Ob er die App ganz deckt — bis das Ausblenden beginnt.
  bool _covering = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_showing != null) return;
    _showing = ref.read(startSplashEnabledProvider) && !reduceMotion(context);
    if (_showing!) {
      _covering = true;
      _clock.start();
    }
  }

  void _tick(Duration now) {
    _elapsed = splashAdvance(_elapsed, now - _lastFrame);
    _lastFrame = now;
    _draw.value = _elapsed.inMicroseconds / kSplashDuration.inMicroseconds;
    if (_elapsed >= kSplashDuration + kSplashHold) _dismiss();
  }

  void _dismiss({Duration fade = kSplashFade}) {
    if (!mounted || !_covering || _showing != true) return;
    _clock.stop();
    _draw.value = 1;
    setState(() => _covering = false);
    _fade.animateBack(0, duration: fade, curve: Curves.easeInOut).whenComplete(() {
      if (mounted) setState(() => _showing = false);
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    _draw.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    // Immer derselbe Stack: Fiele er nach dem Splash weg, hinge die App
    // um, und der Router verlöre seinen Zustand.
    return Stack(
      fit: StackFit.expand,
      children: [
        // Immer dasselbe Offstage, nur der Schalter wechselt — sonst hinge
        // die App beim Ende des Splashs um.
        Offstage(offstage: _covering, child: widget.child),
        if (_showing == true)
          FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            key: const ValueKey('start-splash'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _dismiss(fade: kSplashSkipFade),
            child: Semantics(
              label: 'TrailBuddy',
              // Material statt ColoredBox: Der Splash liegt im Builder der
              // App, ÜBER dem Navigator — ohne Material darüber zeichnet
              // Flutter Text mit dem Warnstil (gelb, doppelt unterstrichen).
              child: Material(
                color: p.ground,
                // Das Bild sagt nichts, was „TrailBuddy" nicht schon sagt —
                // die Wortmarke brächte den Namen ein zweites Mal.
                child: ExcludeSemantics(
                  child: RepaintBoundary(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _draw,
                      builder: (context, _) {
                        final s = splashAt(_draw.value);
                        final geo = LogoGeometry.of(LogoSize.l);
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: 72,
                              child: CustomPaint(
                                painter: LogoPainter(
                                  geometry: geo,
                                  color: p.brandMark,
                                  to: s.draw * geo.total,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (r) => LinearGradient(
                                colors: const [Color(0xFF000000), Color(0x00000000)],
                                stops: [
                                  (s.wipe - kSplashWipeEdge).clamp(0.0, 1.0),
                                  s.wipe.clamp(0.0, 1.0),
                                ],
                              ).createShader(r),
                              child: const TrailBuddyWordmark(fontSize: 30),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
