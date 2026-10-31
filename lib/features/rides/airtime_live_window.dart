// Das kleine Fenster über der Karte (#36, Betreiber 2026-10-31): ein
// Fully von der Seite, das sich mit dem Pitch gegen den Weg neigt — um die
// Hinterachse, wenn die Front hochgeht, um die Vorderachse beim Stoppie —,
// dazu der Winkel, die laufende Zeit der Phase mit ihrer Spitze und was
// das Modell gerade glaubt. Darunter die offenen Fragen mit „Stimmt" /
// „War keiner" und ein Menü für „… verpasst" — die Banner gehen unter,
// sobald mehrere da sind.
//
// Abgespielt wird nur, solange noch Takte vor dem Abspielpunkt liegen
// (Ticker an, sonst aus): Ein Fenster, das immer zeichnet, kostete Akku
// und ließe keinen Widget-Test zur Ruhe kommen.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../l10n/l10n.dart';
import 'airtime_live.dart';
import 'sensor_fusion.dart';
import 'wheelie_notify.dart';

const kAirtimeWindowWidth = 260.0;

class AirtimeLiveWindow extends ConsumerStatefulWidget {
  const AirtimeLiveWindow({super.key});

  @override
  ConsumerState<AirtimeLiveWindow> createState() => _AirtimeLiveWindowState();
}

class _AirtimeLiveWindowState extends ConsumerState<AirtimeLiveWindow> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _advance());
  FusionLive? _shown;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AirtimeLiveState>(airtimeLiveProvider, (_, next) => _play(next), fireImmediately: true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _play(AirtimeLiveState state) {
    if (state.ticks.isEmpty || state.collapsed) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    if (!_ticker.isActive) _ticker.start();
    _advance();
  }

  void _advance() {
    final state = ref.read(airtimeLiveProvider);
    final tick = state.tickAt(ref.read(airtimeClockProvider)());
    if (!identical(tick, _shown)) setState(() => _shown = tick);
    // Beim letzten Takt angekommen: warten auf den nächsten Schub.
    if (state.ticks.isEmpty || identical(tick, state.ticks.last)) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(airtimeLiveProvider);
    if (!state.active) return const SizedBox.shrink();
    final l = context.l10n;
    final notifier = ref.read(airtimeLiveProvider.notifier);
    if (state.collapsed) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Badge(
          isLabelVisible: state.pending.isNotEmpty,
          label: Text('${state.pending.length}'),
          // 48 dp wie jedes Tippziel auf der Karte (A13).
          child: IconButton.filled(
            key: const ValueKey('airtime-live-expand'),
            tooltip: l.airtimeLiveExpand,
            onPressed: () => notifier.setCollapsed(false),
            icon: const Icon(Icons.sensors),
          ),
        ),
      );
    }
    final palette = AppPalette.of(context);
    final tick = _shown;
    final event = state.pending.isEmpty ? null : state.pending.first;
    return SizedBox(
      width: kAirtimeWindowWidth,
      child: Card(
        key: const ValueKey('airtime-live-window'),
        margin: const EdgeInsets.only(top: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sensors, size: 16, color: palette.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l.airtimeLiveTitle,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: palette.muted)),
                  ),
                  PopupMenuButton<String>(
                    key: const ValueKey('airtime-live-missed'),
                    tooltip: l.airtimeLiveMissed,
                    icon: const Icon(Icons.flag_outlined, size: 20),
                    onSelected: (actionId) => _missed(actionId),
                    itemBuilder: (context) => [
                      PopupMenuItem(value: kWheelieMissed, child: Text(l.wheelieMissedButton)),
                      PopupMenuItem(value: kJumpMissed, child: Text(l.jumpMissedButton)),
                      PopupMenuItem(value: kStoppieMissed, child: Text(l.stoppieMissedButton)),
                    ],
                  ),
                  IconButton(
                    key: const ValueKey('airtime-live-collapse'),
                    tooltip: l.airtimeLiveCollapse,
                    icon: const Icon(Icons.close_fullscreen, size: 20),
                    onPressed: () => notifier.setCollapsed(true),
                  ),
                ],
              ),
              _LiveBody(tick: tick, lagUs: state.lagUs),
              if (event != null) ...[
                const Divider(height: 16),
                _PendingQuestion(
                  event: event,
                  more: state.pending.length - 1,
                  onAnswer: (yes) => notifier.answer(event, yes: yes),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _missed(String actionId) async {
    await ref.read(airtimeLiveProvider.notifier).missed(actionId);
    if (!mounted) return;
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.wheelieMissedNoted('${two(now.hour)}:${two(now.minute)}:${two(now.second)}'))));
  }
}

class _LiveBody extends StatelessWidget {
  const _LiveBody({required this.tick, required this.lagUs});

  final FusionLive? tick;
  final int lagUs;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final palette = AppPalette.of(context);
    final tick = this.tick;
    final pitch = tick == null || !tick.mountReady ? null : tick.pitchDeg;
    final phase = tick?.phase ?? FusionPhase.none;
    final active = phase != FusionPhase.none;
    final mono = TextStyle(fontFamily: AppFonts.mono, color: palette.text);
    final status = tick == null
        ? l.airtimeLiveWaiting
        : !tick.upKnown
            ? l.airtimeLiveLearningUp
            : pitch == null
                ? l.airtimeLiveLearningForward
                : switch (phase) {
                    FusionPhase.none => l.airtimeLivePhaseNone,
                    FusionPhase.wheelie => l.airtimeLivePhaseWheelie,
                    FusionPhase.stoppie => l.airtimeLivePhaseStoppie,
                    FusionPhase.airborne => l.airtimeLivePhaseAirborne,
                  };
    final start = tick?.phaseStartUs;
    final running = tick == null || start == null ? null : _num(l, (tick.tUs - start) / 1e6, 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 84,
              child: CustomPaint(
                key: const ValueKey('airtime-live-bike'),
                painter: BikeSidePainter(
                  pitchDeg: pitch ?? 0,
                  frame: palette.text,
                  tyre: palette.text,
                  accent: active ? AppColors.brand : palette.muted,
                  ground: palette.line,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pitch == null ? '–°' : '${_num(l, pitch, 0)}°',
                      key: const ValueKey('airtime-live-angle'),
                      style: mono.copyWith(
                          fontSize: 28, height: 1.1, color: active ? palette.accentText : palette.text)),
                  Text(status,
                      key: const ValueKey('airtime-live-status'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  if (running != null)
                    Text(
                        phase == FusionPhase.airborne
                            ? l.airtimeLiveSeconds(running)
                            : l.airtimeLiveRunning(running, _num(l, tick!.peakDeg, 0)),
                        key: const ValueKey('airtime-live-running'),
                        style: mono.copyWith(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        if (tick != null)
          Text(l.airtimeLiveFooter(_num(l, tick.speedKmh, 0), _num(l, lagUs / 1e6, 1)),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: palette.muted)),
      ],
    );
  }
}

class _PendingQuestion extends StatelessWidget {
  const _PendingQuestion({required this.event, required this.more, required this.onAnswer});

  final FusionEvent event;
  final int more;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final seconds = _num(l, event.duration.inMilliseconds / 1000, 1);
    final (title, body) = switch (event) {
      WheelieEvent e => (
          l.wheelieNoticeTitle,
          l.wheelieNoticeBody(seconds, _num(l, e.lengthM, 0), _num(l, e.maxTiltDeg, 0))
        ),
      JumpEvent e => (
          l.jumpNoticeTitle,
          e.plausible
              ? l.jumpNoticeBody(_num(l, e.duration.inMilliseconds / 1000, 2), _num(l, e.landingG, 1))
              : l.jumpNoticeBodyImplausible(_num(l, e.duration.inMilliseconds / 1000, 2), _num(l, e.landingG, 1))
        ),
      StoppieEvent e => (
          l.stoppieNoticeTitle,
          l.stoppieNoticeBody(seconds, _num(l, e.maxTiltDeg, 0), _num(l, e.decel, 1))
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        key: const ValueKey('airtime-live-question'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
          if (more > 0)
            Text(l.airtimeLivePendingMore(more),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppPalette.of(context).muted)),
          const SizedBox(height: 6),
          // Je die Hälfte: Groß genug für den Daumen mit Handschuh.
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('airtime-live-no'),
                  onPressed: () => onAnswer(false),
                  child: Text(l.wheelieNoticeNo, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('airtime-live-yes'),
                  onPressed: () => onAnswer(true),
                  child: Text(l.wheelieNoticeYes, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _num(AppLocalizations l, double v, int digits) {
  final text = v.toStringAsFixed(digits);
  return l.localeName.startsWith('de') ? text.replaceAll('.', ',') : text;
}

/// Ein Fully von der Seite, nach rechts fahrend, im Raster 104 × 56 —
/// angelehnt an ein Trail-Fully wie Orbea Rise oder Rocky Mountain
/// Altitude: 29er, flacher Lenkwinkel, Dämpfer liegend unter dem
/// Oberrohr, Wippe am Sitzrohr. [pitchDeg] > 0 hebt die Front (Drehung
/// um die Hinterachse), < 0 das Heck (um die Vorderachse); höchstens 80°.
class BikeSidePainter extends CustomPainter {
  const BikeSidePainter(
      {required this.pitchDeg, required this.frame, required this.tyre, required this.accent, required this.ground});

  final double pitchDeg;
  final Color frame, tyre, accent, ground;

  static const _rear = Offset(20, 36);
  static const _front = Offset(82, 36);
  static const _wheelR = 18.0;
  /// Unter dem Reifen: Achshöhe 36 + Radius 18 + 1.
  static const _groundY = 55.0;

  /// Über dem Rad bleibt Platz, damit es sich bis 60° ganz zeigt; was
  /// darüber hinausragt, schneidet der Rand ab.
  static const _headroom = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 104, size.height / (56 + _headroom));
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate((size.width - 104 * scale) / 2 + 2 * scale, size.height - 56 * scale);
    canvas.scale(scale);

    canvas.drawLine(const Offset(-2, _groundY), const Offset(104, _groundY),
        Paint()
          ..color = ground
          ..strokeWidth = 1.2);

    final pitch = pitchDeg.clamp(-80.0, 80.0);
    final pivot = pitch >= 0 ? _rear : _front;
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(-pitch * math.pi / 180);
    canvas.translate(-pivot.dx, -pivot.dy);
    _bike(canvas);
    canvas.restore();
  }

  void _bike(Canvas canvas) {
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Räder: Reifen, Felge, Bremsscheibe.
    for (final axle in [_rear, _front]) {
      canvas.drawCircle(axle, _wheelR - 1.6, stroke(tyre, 3.2));
      canvas.drawCircle(axle, _wheelR - 4.2, stroke(tyre.withValues(alpha: 0.35), 0.9));
      canvas.drawCircle(axle, 4.5, stroke(tyre.withValues(alpha: 0.5), 1.0));
      canvas.drawCircle(axle, 1.3, Paint()..color = tyre);
    }

    const bb = Offset(47, 39);
    const seatTop = Offset(40, 9);
    const headTop = Offset(70, 10);
    const headBottom = Offset(73.5, 19);
    const mainPivot = Offset(45, 33);
    const rocker = Offset(38, 21);
    const rockerPivot = Offset(42.5, 20);
    const shockEnd = Offset(57, 28.5);

    final tube = stroke(frame, 3.0);
    final thin = stroke(frame, 2.0);
    // Hauptrahmen: Unterrohr, Sitzrohr, Oberrohr, Steuerrohr.
    canvas.drawLine(bb, headBottom, stroke(frame, 3.6));
    canvas.drawLine(bb, seatTop, tube);
    canvas.drawLine(const Offset(41.5, 15), headTop, tube);
    canvas.drawLine(headTop, headBottom, stroke(frame, 3.8));
    // Hinterbau: Kettenstrebe zum Hauptlager, Sitzstrebe zur Wippe.
    canvas.drawLine(mainPivot, _rear, tube);
    canvas.drawLine(_rear, rocker, thin);
    canvas.drawLine(rocker, rockerPivot, stroke(frame, 2.6));
    // Dämpfer liegend, in der Farbe der Phase.
    canvas.drawLine(rockerPivot.translate(0.5, 0.8), shockEnd, stroke(accent, 2.8));
    // Federgabel: Tauchrohr dick, Standrohr bis zur Achse.
    canvas.drawLine(headBottom, const Offset(77, 27), stroke(frame, 3.4));
    canvas.drawLine(const Offset(77, 27), _front, stroke(accent, 2.2));
    // Cockpit: Vorbau, Lenker; Sattelstütze (Dropper), Sattel.
    canvas.drawLine(headTop, const Offset(74, 7.5), thin);
    canvas.drawLine(const Offset(72.5, 5), const Offset(75.5, 9), stroke(frame, 2.2));
    canvas.drawLine(seatTop, const Offset(39.3, 5.5), thin);
    canvas.drawLine(const Offset(33.5, 4.5), const Offset(44.5, 4.8), stroke(frame, 2.6));
    // Tretlager und Kurbel.
    canvas.drawCircle(bb, 3.0, stroke(frame, 1.6));
    canvas.drawLine(bb, const Offset(50.5, 44.5), stroke(frame, 2.0));
  }

  @override
  bool shouldRepaint(BikeSidePainter old) =>
      old.pitchDeg != pitchDeg || old.frame != frame || old.accent != accent || old.ground != ground;
}
