// Das Blatt der Routen-Werkzeuge über der Karte (Rundenplaner, Weg zu
// einem Trailkopf oder Punkt) — Feldbericht 0.73.0: „Der erstellte Track
// war nicht wirklich sichtbar. Man musste das Planungsfenster nach unten
// ziehen, aber das beendet dann gleichzeitig die Routenplanung."
//
// Drei Dinge, die man wissen muss:
// - **Kein Modal.** Das Blatt ist ein Persistent Bottom Sheet am Scaffold
//   der Karte: Die Karte darüber bleibt bedienbar (verschieben, zoomen,
//   Trails antippen — der Planer wählt so Trails aus, #178). Zurück
//   schließt es (lokaler Verlauf der Route), ebenso das X im Kopf.
// - **Runterziehen schließt NIE**, es verkleinert bis auf den Kopf
//   ([kMapPanelPeek]). Geschlossen wird nur über X oder Zurück.
// - **Die verdeckte Höhe steht in [mapPanelInsetProvider]**: Die Karte
//   passt eine neue Route in die Fläche ÜBER dem Blatt ein
//   (`cameraToFit(bottomInset:)`), statt sie darunter zu legen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';

/// Was ein offenes Routen-Blatt unten von der Karte verdeckt, in
/// logischen Pixeln; 0 ohne Blatt.
final mapPanelInsetProvider = StateProvider<double>((ref) => 0);

/// Kleinste Höhe: der Kopf mit Titel und X — „eingeklappt".
const kMapPanelPeek = 0.16;

/// Höhe im Pool des Planers: Liste und Karte teilen sich den Schirm
/// (#178 — gewählt wird in beiden).
const kMapPanelPool = 0.45;

/// Höhe, auf die das Blatt beim Ergebnis einklappt: Summen und die
/// Knöpfe darunter sind zu sehen, die Route darüber.
const kMapPanelResult = 0.4;

/// Griff an das offene Blatt: verkleinern/vergrößern und schließen.
class MapPanelController {
  MapPanelController._(this._sheet, this._close);

  final DraggableScrollableController _sheet;
  final VoidCallback _close;

  /// Auf [size] (Anteil der Höhe) fahren; wartet, bis es dort ist.
  Future<void> resizeTo(double size) async {
    if (!_sheet.isAttached) return;
    if ((_sheet.size - size).abs() < 0.01) return;
    await _sheet.animateTo(size, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void close() => _close();
}

/// Öffnet das Blatt am Scaffold [scaffold] (das der Karte) und wartet,
/// bis es zu ist. Ein schon offenes Routen-Blatt wird dabei ersetzt.
Future<void> showMapPanel(
  ScaffoldState scaffold, {
  required double initialSize,
  double maxSize = 0.92,
  required Widget Function(BuildContext context, ScrollController scroll, MapPanelController panel) builder,
}) {
  final container = ProviderScope.containerOf(scaffold.context, listen: false);
  final sheet = DraggableScrollableController();
  late final PersistentBottomSheetController controller;
  final panel = MapPanelController._(sheet, () => controller.close());
  controller = _current = scaffold.showBottomSheet(
    (context) => _MapPanel(
      sheet: sheet,
      initialSize: initialSize,
      maxSize: maxSize,
      builder: (context, scroll) => builder(context, scroll, panel),
    ),
    // Runterziehen verkleinert (das Blatt selbst), es schließt nie.
    enableDrag: false,
    elevation: 8,
  );
  return controller.closed.whenComplete(() {
    if (identical(_current, controller)) _current = null;
    container.read(mapPanelInsetProvider.notifier).state = 0;
    sheet.dispose();
  });
}

PersistentBottomSheetController? _current;

/// Schließt das offene Routen-Blatt, wenn eins offen ist — der Planer
/// schließt so beim Verlassen des Modus sein Ergebnis mit.
void closeMapPanel() => _current?.close();

class _MapPanel extends ConsumerWidget {
  const _MapPanel({required this.sheet, required this.initialSize, required this.maxSize, required this.builder});

  final DraggableScrollableController sheet;
  final double initialSize;
  final double maxSize;
  final Widget Function(BuildContext context, ScrollController scroll) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight.isFinite ? constraints.maxHeight : MediaQuery.sizeOf(context).height;
      void report(double extent) {
        final inset = extent * height;
        final notifier = ref.read(mapPanelInsetProvider.notifier);
        if ((notifier.state - inset).abs() > 1) notifier.state = inset;
      }

      // Die Anfangshöhe gleich melden — die erste Notification kommt erst
      // mit der ersten Bewegung.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (sheet.isAttached) report(sheet.size);
      });
      return NotificationListener<DraggableScrollableNotification>(
        onNotification: (n) {
          report(n.extent);
          return false;
        },
        child: DraggableScrollableSheet(
          controller: sheet,
          expand: false,
          initialChildSize: initialSize,
          minChildSize: kMapPanelPeek,
          maxChildSize: maxSize,
          // Sonst schließt das Scaffold ein Persistent Sheet, sobald es
          // ganz unten ankommt — genau der Fehler aus dem Feldbericht.
          shouldCloseOnMinExtent: false,
          snap: true,
          snapSizes: [kMapPanelResult, kMapPanelPool, if (initialSize > kMapPanelPool && initialSize < maxSize) initialSize],
          builder: (context, scroll) => builder(context, scroll),
        ),
      );
    });
  }
}

/// Der Kopf des Blatts: Griff, Titel, Untertitel und X. Gehört als
/// ERSTES Kind in die Liste des Blatts — so zieht auch der Kopf.
class MapPanelHeader extends StatelessWidget {
  const MapPanelHeader({super.key, required this.title, this.subtitle, required this.onClose, this.closeKey});

  final String title;
  final String? subtitle;
  final VoidCallback onClose;
  final Key? closeKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: theme.textTheme.titleLarge),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
              ]),
            ),
            IconButton(
              key: closeKey,
              tooltip: context.l10n.commonClose,
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
