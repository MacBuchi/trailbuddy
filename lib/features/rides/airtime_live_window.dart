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
              child: BikeSideView(
                key: const ValueKey('airtime-live-bike'),
                pitchDeg: pitch ?? 0,
                color: active ? palette.accentText : palette.text,
                ground: palette.line,
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

/// Die Silhouette eines E-Fullys (`assets/airtime/bike_side.png`, vom
/// Betreiber mit Gemini erzeugt, 2026-10-31; freigestellt und auf 512 px
/// verkleinert), eingefärbt in [color]. [pitchDeg] > 0 hebt die Front
/// (Drehung um die Hinterachse), < 0 das Heck (um die Vorderachse);
/// höchstens 80°, über dem Rad bleibt Platz bis etwa 60°, darüber schneidet
/// der Rand ab.
class BikeSideView extends StatelessWidget {
  const BikeSideView({super.key, required this.pitchDeg, required this.color, required this.ground});

  final double pitchDeg;
  final Color color, ground;

  static const asset = 'assets/airtime/bike_side.png';

  /// Maße und Achsen im Bild, in Pixeln (gemessen an den Reifen).
  static const imageSize = Size(512, 276);
  static const rearAxle = Offset(97, 178.75);
  static const frontAxle = Offset(416.75, 178.75);

  /// Wo die Reifen aufsetzen.
  static const tyreBottom = 273.5;

  /// Kopfraum über dem Bild, als Anteil seiner Höhe.
  static const headroom = 0.75;

  @override
  Widget build(BuildContext context) {
    final pitch = pitchDeg.clamp(-80.0, 80.0);
    final pivot = pitch >= 0 ? rearAxle : frontAxle;
    return LayoutBuilder(builder: (context, box) {
      final scale = math.min(box.maxWidth / imageSize.width, box.maxHeight / (imageSize.height * (1 + headroom)));
      final w = imageSize.width * scale, h = imageSize.height * scale;
      final groundY = box.maxHeight - (imageSize.height - tyreBottom) * scale;
      return ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: groundY,
              child: Container(height: 1.2, color: ground),
            ),
            Positioned(
              left: (box.maxWidth - w) / 2,
              top: box.maxHeight - h,
              width: w,
              height: h,
              child: Transform.rotate(
                angle: -pitch * math.pi / 180,
                alignment: Alignment(
                    pivot.dx / imageSize.width * 2 - 1, pivot.dy / imageSize.height * 2 - 1),
                child: Image.asset(asset, color: color, colorBlendMode: BlendMode.srcIn, filterQuality: FilterQuality.medium),
              ),
            ),
          ],
        ),
      );
    });
  }
}
