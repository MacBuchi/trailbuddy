// Die Legende auf der Karte (#182, seit 0.77.0): eine schmale Lasche am
// linken Rand, die zu den Linienproben aufklappt — Feldwunsch „ausklappbar,
// sodass man nicht in ein Untermenü abtauchen muss, aber kaum sichtbar
// zusammenklappbar". Bis dahin stand die Legende nur in der Tour und in
// der Kurzanleitung.
//
// **Eine Liste.** Die Proben (`legendSamples`) und ihr Maler stehen hier
// und nirgends sonst; bis 0.76.x hatte die Tour eine eigene Mini-Legende,
// jetzt klappt sie diese auf. Farben und Muster kommen aus
// `AppColors.mapGrades`/`mapLines` und `grade_shield.dart`, wie auf der
// Karte — ändert sich dort ein Muster, zieht die Legende mit.
//
// **Auf dem Landton der Karte**, auch in der dunklen App: Der weiße Saum
// der Linien stünde sonst auf Schwarz und sähe anders aus als dort.
//
// **Auf oder zu merkt sich das Gerät** (`Settings.mapLegendOpen`, Vorgabe
// zu): Wer sie offen haben will, soll sie nicht bei jedem Start neu
// aufklappen. Die Lasche ist 16 dp breit, die Trefferfläche trotzdem
// 44 dp (Handschuh, wie jeder Kartenknopf).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/settings.dart';
import '../../core/widgets/motion.dart';
import '../trails/grade_shield.dart';
import 'map_buttons.dart';

/// Eine Probe: Farbe, Strich der Linie, Saum, Deckkraft — und die Gruppe
/// (Schwierigkeit, Zustand, Rand, offiziell), nach der die Karte Luft lässt.
typedef LegendSample = ({
  String label,
  int group,
  Color color,
  List<double>? dash,
  Color? border,
  List<double>? borderDash,
  double opacity,
});

LegendSample _line(String label, int group, Color color,
        {List<double>? dash, Color? border, List<double>? borderDash, double opacity = 1}) =>
    (
      label: label,
      group: group,
      color: color,
      dash: dash,
      border: border,
      borderDash: borderDash,
      opacity: opacity,
    );

/// Die Proben, in der Reihenfolge der Kurzanleitung: Schwierigkeit, dann
/// Zustand, dann was UM die Linie liegt. Jede nennt, was sie BEDEUTET,
/// mit den Wörtern des Melde-Dialogs — bis 0.83.x stand beim Zustand das
/// Aussehen („bröckelig", „gestrichelt", „verblasst"), das die Probe
/// ohnehin zeigt (#231, Betreiber 2026-10-07: Variante A).
List<LegendSample> legendSamples() {
  const g = AppColors.mapGrades;
  const m = AppColors.mapLines;
  return [
    _line('S0', 0, g.s0),
    _line('S1', 0, g.s1),
    _line('S2', 0, g.s2),
    _line('S3', 0, g.s3),
    _line('S4/S5', 0, g.s3, borderDash: kHaloDashExpert),
    _line('ohne Grad', 0, g.ungraded),
    _line('Uphill', 0, g.uphill),
    _line('ausgefahren', 1, g.s1, dash: kLineDashWorn),
    _line('abgerockt', 1, g.s1, dash: kLineDashRough),
    _line('kaum fahrbar', 1, g.s1, dash: kLineDashRough, opacity: 0.45),
    _line('Meldung', 2, g.s1, border: m.warning),
    _line('neuer Hinweis', 2, g.s1, border: m.note),
    _line('offizieller Trail', 3, m.official, dash: const [6, 4]),
  ];
}

/// Die Überschrift über einer Gruppe; null heißt: nur Luft, keine neue
/// Überschrift (offizielle Trails stehen unter „Am Trail"). Ohne sie
/// musste man erraten, dass „abgerockt" ein Zustand ist (#231).
String? legendGroupTitle(int group) => switch (group) {
      0 => 'Schwierigkeit',
      1 => 'Zustand',
      2 => 'Am Trail',
      _ => null,
    };

/// Zeichnet eine Probe als kurzes Linienstück.
class LegendLinePainter extends CustomPainter {
  const LegendLinePainter(this.sample);

  final LegendSample sample;

  static const _width = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final a = Offset(2, y);
    final b = Offset(size.width - 2, y);
    // Erst der Saum (weiß, auf Wunsch gestrichelt), dann ein farbiger
    // Rand, dann die Linie — dieselbe Reihenfolge wie auf der Karte.
    _stroke(canvas, a, b, AppColors.mapLines.halo!, _width + 4, sample.borderDash);
    if (sample.border case final c?) _stroke(canvas, a, b, c, _width + 5, null);
    _stroke(canvas, a, b, sample.color.withValues(alpha: sample.opacity), _width, sample.dash);
  }

  void _stroke(Canvas canvas, Offset a, Offset b, Color color, double width, List<double>? dash) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;
    if (dash == null) {
      canvas.drawLine(a, b, paint);
      return;
    }
    // Muster in Vielfachen der Strichbreite, wie die Engines es zeichnen.
    var x = a.dx;
    var i = 0;
    while (x < b.dx) {
      final len = dash[i % dash.length] * _width / 3;
      if (i.isEven) canvas.drawLine(Offset(x, a.dy), Offset((x + len).clamp(a.dx, b.dx), a.dy), paint);
      x += len;
      i++;
    }
  }

  @override
  bool shouldRepaint(LegendLinePainter old) => old.sample != sample;
}

/// Ist die Legende auf der Karte aufgeklappt? Gerätelokal, Vorgabe zu.
final mapLegendOpenProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.mapLegendOpen,
    write: (s, v) => s.setMapLegendOpen(v),
    label: 'Kartenlegende merken',
  ),
);

/// Breite der aufgeklappten Legende. Schmal genug, dass die Blase der
/// Tour auf einem 360-dp-Telefon daneben passt (sie braucht 200 dp).
const kMapLegendWidth = 124.0;

/// Die Legende am linken Rand: zu eine Lasche, auf die Proben.
class MapLegend extends ConsumerWidget {
  const MapLegend({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(mapLegendOpenProvider);
    void toggle() => ref.read(mapLegendOpenProvider.notifier).set(!open);
    return AnimatedSize(
      duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: open ? _Panel(onClose: toggle) : _Tab(onOpen: toggle),
    );
  }
}

const _radius = BorderRadius.horizontal(right: Radius.circular(10));
const _shadow = [BoxShadow(blurRadius: 4, offset: Offset(0, 1), color: Color(0x26000000))];

/// Zu: eine schmale Lasche mit den vier Pistenfarben — kaum sichtbar,
/// aber erkennbar als „hier steht, was die Farben heißen".
class _Tab extends StatelessWidget {
  const _Tab({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    const g = AppColors.mapGrades;
    return Semantics(
      button: true,
      label: 'Legende zeigen',
      child: Tooltip(
        message: 'Legende zeigen',
        child: GestureDetector(
          key: const ValueKey('map-legend-tab'),
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          // Die Trefferfläche ist 44 × 64, sichtbar sind 16 × 56.
          child: SizedBox(
            width: kMapButtonSize,
            height: 64,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 56,
                decoration: BoxDecoration(
                  color: p.surface.withValues(alpha: 0.85),
                  borderRadius: _radius,
                  border: Border(
                    top: BorderSide(color: p.line),
                    right: BorderSide(color: p.line),
                    bottom: BorderSide(color: p.line),
                  ),
                  boxShadow: _shadow,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in [g.s0, g.s1, g.s2, g.s3])
                      Container(
                        width: 4,
                        height: 7,
                        margin: const EdgeInsets.symmetric(vertical: 1.5),
                        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Überschrift vor Probe [i], wenn dort eine Gruppe mit eigener
/// Überschrift beginnt.
String? _titleAt(List<LegendSample> samples, int i) =>
    i == 0 || samples[i].group != samples[i - 1].group ? legendGroupTitle(samples[i].group) : null;

/// Auf: die Proben untereinander, oben „Legende" mit dem Weg zurück.
class _Panel extends StatelessWidget {
  const _Panel({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final text = AppColors.light.text;
    final theme = Theme.of(context).textTheme;
    final label = theme.bodySmall?.copyWith(color: text);
    final heading = theme.labelSmall?.copyWith(
        color: AppColors.light.muted, letterSpacing: 0.8, fontWeight: FontWeight.w600);
    final samples = legendSamples();
    return Container(
      key: const ValueKey('map-legend-panel'),
      width: kMapLegendWidth,
      decoration: const BoxDecoration(
        color: AppColors.mapBackground,
        borderRadius: _radius,
        boxShadow: _shadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: 'Legende einklappen',
            child: InkWell(
              key: const ValueKey('map-legend-close'),
              onTap: onClose,
              borderRadius: const BorderRadius.only(topRight: Radius.circular(10)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMapButtonSize),
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text('Legende',
                              style: theme.labelLarge?.copyWith(color: text)),
                        ),
                      ),
                      Icon(Icons.chevron_left, size: 22, color: text),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 0, 6, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < samples.length; i++) ...[
                    if (_titleAt(samples, i) case final title?)
                      Padding(
                        padding: EdgeInsets.only(top: i > 0 ? 8 : 0, bottom: 1),
                        child: Text(title.toUpperCase(), style: heading),
                      ),
                    Padding(
                      // Luft zwischen Gruppen — unter einer Überschrift
                      // hat die schon die Überschrift.
                      padding: EdgeInsets.only(
                          top: i > 0 &&
                                  samples[i].group != samples[i - 1].group &&
                                  _titleAt(samples, i) == null
                              ? 8
                              : 2),
                      child: Row(
                        children: [
                          CustomPaint(
                              size: const Size(26, 12),
                              painter: LegendLinePainter(samples[i])),
                          const SizedBox(width: 6),
                          Expanded(child: Text(samples[i].label, style: label)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
