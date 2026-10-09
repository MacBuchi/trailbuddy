// Die Werkzeugleiste „Offline-Karten" (seit 0.27.0; Betreiber, 2026-09-29):
// eine schmale Leiste am linken Rand statt des Blatts, das den halben
// Schirm deckte. Der Knopf „Offline-Karten" öffnet sie (bis 0.74.x der
// Ebenen-Knopf, der seit #190 nur noch die Kartenebenen trägt), derselbe Knopf,
// das X und die Zurück-Taste schließen sie — mit Rückfrage, wenn im
// Entwurf noch etwas steht (map_screen.dart). Solange sie offen ist, ist
// abgedunkelt, was nicht auf dem Gerät liegt, und der Entwurf liegt
// schraffiert darüber (area_overlay.dart, area_draw.dart).
//
// Oben die Werkzeuge, die den ENTWURF ändern (Ausschnitt, Fläche dazu,
// Fläche weg, entlang der Trails, Rückgängig), darunter Verwalten,
// Speichern und Schließen. Die Leiste steht mittig links: unten liegen
// Maßstab und Quellenhinweis, oben die Banner — beide bleiben frei.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/errors.dart';
import '../coach/coach.dart';
import '../help/map_tour.dart' show MapCoach;
import '../map/map_buttons.dart';
import '../map/online_map.dart';
import 'area_downloader.dart';
import 'area_draw.dart';
import 'area_plan.dart';
import 'area_providers.dart';
import 'area_trim.dart';

/// Kachelzahl kurz, für den Platz unter dem Speichern-Symbol.
String compactCount(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1).replaceAll('.', ',')} k';
  return '${(n / 1000).round()} k';
}

class OfflineToolRail extends ConsumerWidget {
  const OfflineToolRail({
    super.key,
    required this.onSnapshot,
    required this.onTrails,
    required this.onManage,
    required this.onSave,
    required this.onClose,
  });

  final VoidCallback onSnapshot;
  final VoidCallback? onTrails;
  final VoidCallback onManage;
  final void Function(AreaDraft draft) onSave;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(areaDraftProvider);
    final notifier = ref.read(areaDraftProvider.notifier);
    final maxZoom = ref.watch(mapManifestProvider).valueOrNull?.maxZoom ?? kAreaShapeZoom;
    final empty = draft == null || draft.isEmpty;
    // Kacheln über alle Zoomstufen, wie sie geladen bzw. frei werden.
    final adds = draft == null || draft.adds.isEmpty ? 0 : draft.addShape.countTiles(maxZoom: maxZoom);
    final removes = draft == null || draft.removes.isEmpty ? 0 : draft.removeShape.countTiles(maxZoom: maxZoom);
    final tooLarge = adds > kAreaMaxTiles;
    final p = AppPalette.of(context);
    final countStyle = AppFonts.numbers(Theme.of(context).textTheme.labelMedium);

    // Aktives Werkzeug = helle Fläche (auf Hell: die dunkle — immer die
    // Gegenhelligkeit der Leiste), Hauptaktion Speichern = Lime (3e).
    //
    // Jeder Knopf ist ein Anker der Karten-Tour (#132), generisch aus
    // seinem Schlüssel: `map.rail.<key>` — ein neuer Knopf bekommt ihn
    // von selbst.
    Widget button(String key, String tip, Widget icon, VoidCallback? onPressed,
            {bool selected = false, bool primary = false}) =>
        CoachAnchor(
          id: MapCoach.railButton(key),
          child: IconButton(
          key: ValueKey(key),
          tooltip: tip,
          isSelected: selected,
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: kMapButtonSize, height: kMapButtonSize),
          style: IconButton.styleFrom(
            backgroundColor: selected
                ? p.text
                : primary && onPressed != null
                    ? AppColors.brand
                    : null,
            foregroundColor: selected
                ? p.ground
                : primary && onPressed != null
                    ? AppColors.onBrand
                    : p.text,
            // 44 ist schon die Trefferfläche (Handschuh); Material
            // polsterte sonst auf 48 auf, und die Leiste würde länger.
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onPressed,
          icon: icon,
        ));

    Widget tool(AreaDrawTool t, String key, String tip, IconData icon) =>
        button(key, tip, Icon(icon), () => notifier.arm(t), selected: draft?.tool == t);

    // Gruppen durch Luft statt Trennlinien.
    const gap = SizedBox(height: 8);

    return Container(
      key: const ValueKey('offline-tool-rail'),
      width: kRailWidth,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(kRailWidth / 2),
        border: Border.all(color: p.line),
        boxShadow: const [BoxShadow(blurRadius: 8, offset: Offset(0, 2), color: Color(0x33000000))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button('rail-snapshot', 'Ausschnitt dazunehmen', const Icon(Icons.crop_free), onSnapshot),
          tool(AreaDrawTool.add, 'area-draw-add', 'Fläche dazunehmen', Icons.add_circle_outline),
          tool(AreaDrawTool.remove, 'area-draw-remove', 'Fläche wegnehmen', Icons.remove_circle_outline),
          button('area-draw-trails', 'Entlang meiner Trails dazunehmen', const Icon(Icons.route_outlined),
              onTrails),
          button('area-draw-undo', 'Rückgängig', const Icon(Icons.undo),
              draft == null || draft.history.isEmpty ? null : notifier.undo),
          gap,
          button('manage-areas', 'Meine Bereiche verwalten', const _ManageIcon(), onManage),
          button(
            'area-draw-save',
            tooLarge
                ? '+$adds Kacheln — zu viel auf einmal, erlaubt sind $kAreaMaxTiles'
                : empty
                    ? 'Speichern — noch keine Änderung'
                    : 'Speichern (+$adds / −$removes Kacheln)',
            const Icon(Icons.save_outlined),
            empty || tooLarge
                ? null
                : () {
                    notifier.disarm();
                    onSave(draft);
                  },
            primary: true,
          ),
          // Der Zähler direkt unter Speichern, in Mono: was dazukommt und
          // was wegfällt, getrennt — wie Schraffur und Gegenschraffur.
          const SizedBox(height: 2),
          Text(
            adds == 0 ? (removes == 0 ? '–' : '') : '+${compactCount(adds)}',
            key: const ValueKey('area-draw-count'),
            style: countStyle.copyWith(color: tooLarge ? Theme.of(context).colorScheme.error : p.text),
          ),
          if (removes > 0)
            Text(
              '−${compactCount(removes)}',
              key: const ValueKey('area-draw-remove-count'),
              style: countStyle.copyWith(color: p.muted),
            ),
          gap,
          button('offline-maps-close', 'Schließen', const Icon(Icons.close), onClose),
        ],
      ),
    );
  }
}

/// Breite der linken Leiste (3e).
const kRailWidth = 52.0;

/// Karte mit Zahnrad: die gespeicherten Bereiche verwalten.
class _ManageIcon extends StatelessWidget {
  const _ManageIcon();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        height: 22,
        child: Stack(children: [
          const Icon(Icons.map_outlined, size: 20),
          Positioned(
            right: -1,
            bottom: -1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppPalette.of(context).surface, shape: BoxShape.circle),
              child: const Icon(Icons.settings, size: 13),
            ),
          ),
        ]),
      );
}

/// „Entwurf verwerfen?" — true heißt verwerfen.
Future<bool> confirmDiscardDraft(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Entwurf verwerfen?'),
        content: const Text('Die gewählten Kacheln sind noch nicht gespeichert.'),
        actions: [
          TextButton(
            key: const ValueKey('draft-keep'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Weiter bearbeiten'),
          ),
          FilledButton(
            key: const ValueKey('draft-discard'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    ) ??
    false;

/// Der Dialog vor dem Speichern: misst, was dazukommt (Kacheln, Bytes,
/// Orte — braucht den Kartenhost) und was wegfällt (lokal, ohne Netz),
/// fragt nach dem Namen des neuen Bereichs, schreibt dann erst die
/// Bereiche ohne die wegfallenden Kacheln neu und lädt danach. `true`,
/// wenn alles gespeichert ist.
Future<bool> showSaveDraftDialog(BuildContext context, AreaDraft draft) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaveDraftDialog(draft: draft),
    ) ??
    false;

class _SaveDraftDialog extends ConsumerStatefulWidget {
  const _SaveDraftDialog({required this.draft});

  final AreaDraft draft;

  @override
  ConsumerState<_SaveDraftDialog> createState() => _SaveDraftDialogState();
}

class _SaveDraftDialogState extends ConsumerState<_SaveDraftDialog> {
  static final _date = DateFormat('d. MMMM', 'de');

  late final TextEditingController _name =
      TextEditingController(text: 'Bereich vom ${_date.format(DateTime.now())}');
  AreaPlan? _plan;
  TrimPlan? _trim;
  String? _error;
  bool _measuring = true;
  bool _trimming = false;

  bool get _hasAdds => widget.draft.adds.isNotEmpty;
  bool get _hasRemoves => widget.draft.removes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Ein früherer Download (fertig, gescheitert) gehört nicht hierher.
      ref.read(areaDownloadProvider.notifier).reset();
      _measure();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    try {
      if (_hasRemoves) {
        final trim = await ref.read(storedAreasProvider.notifier).planTrim(widget.draft.removes);
        if (mounted) setState(() => _trim = trim);
      }
      if (_hasAdds) {
        final plan = await ref.read(areaDownloadProvider.notifier).plan(widget.draft.addShape);
        if (mounted) setState(() => _plan = plan);
      }
    } on AreaTooLarge catch (e) {
      if (mounted) setState(() => _error = 'Zu viel auf einmal: ${e.tiles} Kacheln, erlaubt sind $kAreaMaxTiles.');
    } on OutsideRegions catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = looksOffline(e) || e is StateError
          ? 'Ohne Empfang lässt sich nichts dazuladen — der Kartenhost ist nicht erreichbar. '
              'Entfernen geht auch offline: dazu nur wegnehmen, nichts dazunehmen.'
          : 'Die Größe ließ sich nicht messen.');
    } finally {
      if (mounted) setState(() => _measuring = false);
    }
  }

  bool get _ready =>
      !_measuring &&
      _error == null &&
      (!_hasAdds || (_plan != null && _plan!.hasMap) || (_hasRemoves && _plan != null)) &&
      (!_hasRemoves || _trim != null);

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final trim = _trim;
    if (trim != null && !trim.isEmpty) {
      setState(() => _trimming = true);
      try {
        await ref.read(storedAreasProvider.notifier).applyTrim(trim);
      } catch (e, s) {
        logError('Kacheln entfernen', e, s);
        if (mounted) {
          setState(() {
            _trimming = false;
            _error = 'Das Entfernen ließ sich nicht speichern.';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() => _trimming = false);
    }
    final plan = _plan;
    if (plan != null && plan.hasMap) {
      final name = _name.text.trim().isEmpty ? 'Bereich' : _name.text.trim();
      final area = await ref.read(areaDownloadProvider.notifier).start(plan, name: name);
      if (area == null) {
        // Gescheitert oder abgebrochen: Der Fehler steht im Dialog. Das
        // Entfernen ist schon gespeichert — der Entwurf behält es nicht.
        if (trim != null && !trim.isEmpty) {
          ref.read(areaDraftProvider.notifier).dropRemoves();
          messenger.showSnackBar(const SnackBar(content: Text('Entfernt ist gespeichert, das Laden nicht.')));
        }
        return;
      }
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  static String _progressLine(AreaProgress? p) {
    if (p == null) return 'Verbindung zum Kartenhost …';
    return switch (p.phase) {
      AreaPhase.tiles => 'Kacheln ${p.done} von ${p.total}',
      AreaPhase.pois => 'Orte ${p.done} von ${p.total}',
      AreaPhase.heights => 'Höhen ${p.done} von ${p.total}',
      AreaPhase.ways => 'Wege ${p.done} von ${p.total}',
      AreaPhase.overview => 'Übersicht ${formatBytes(p.done)} von ${formatBytes(p.total)}',
      AreaPhase.writing => 'Wird abgelegt …',
    };
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final download = ref.watch(areaDownloadProvider);
    final plan = _plan;
    final trim = _trim;
    final running = download.phase == AreaDownloadPhase.running;
    final errorStyle = text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error);

    final Widget body;
    if (running || _trimming) {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_trimming ? 'Kacheln werden entfernt …' : '„${download.name}" wird gespeichert …'),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: _trimming ? null : download.progress?.fraction),
        if (!_trimming) ...[
          const SizedBox(height: 4),
          Text(_progressLine(download.progress), style: text.bodySmall),
        ],
      ]);
    } else if (_measuring) {
      body = const Row(children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Expanded(child: Text('Größe, Orte, Höhen und Wege werden gemessen …')),
      ]);
    } else {
      final pois = plan?.poiCount;
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (plan != null)
          Text(
            !plan.hasMap
                ? 'Dazu: hier liegt keine Karte — außerhalb der Regionen des Kartenhosts.'
                : plan.nothingToFetch
                    // Lädt nur, was fehlt (#229): Alles liegt schon, der
                    // neue Bereich ist ein Verweis darauf.
                    ? 'Liegt schon auf dem Gerät · ${plan.map.covered} Kacheln — nichts zu laden'
                    : 'Lädt ${formatBytes(plan.totalBytes)} · ${plan.tiles.length} Kacheln'
                    '${plan.map.stored == 0 ? '' : ' (${plan.map.stored} liegen schon)'}'
                    '${pois == null ? ' · ohne Orte' : ' · $pois ${pois == 1 ? 'Ort' : 'Orte'}'}'
                    '${plan.hasHeights ? ' · Höhen' : ' · ohne Höhen'}'
                    // Ohne Wege-Kachel nichts: Einem kleinen Bereich, in
                    // dem OSM nichts weiß, fehlt nichts.
                    '${plan.hasWays ? ' · Wege' : ''}'
                    // Die Übersicht der Region kommt mit dem ersten Bereich
                    // dort (#220 Schritt 4) — mit Größe, sie ist der größte
                    // Posten eines kleinen Bereichs.
                    '${plan.overview == null ? '' : ' · Übersicht ${formatBytes(plan.overviewBytes)}'}',
            key: const ValueKey('area-size'),
            style: text.titleMedium,
          ),
        if (trim != null)
          Text(
            'Gibt ${formatBytes(trim.freedBytes)} frei · ${trim.freedTiles} Kacheln'
            '${trim.trims.where((t) => t.shape == null).isEmpty ? '' : ' · ${trim.trims.where((t) => t.shape == null).length} Bereich(e) ganz'}',
            key: const ValueKey('area-free'),
            style: text.titleMedium?.copyWith(color: AppPalette.of(context).muted),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: errorStyle),
        ],
        if (plan != null && plan.hasMap) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('area-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name des neuen Bereichs'),
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
        if (download.phase == AreaDownloadPhase.failed && download.error != null) ...[
          const SizedBox(height: 8),
          Text(download.error!, style: errorStyle),
        ],
      ]);
    }

    return AlertDialog(
      title: const Text('Änderungen speichern?'),
      content: SingleChildScrollView(child: body),
      actions: [
        if (running)
          TextButton(
            key: const ValueKey('area-cancel'),
            onPressed: () => ref.read(areaDownloadProvider.notifier).cancel(),
            child: const Text('Abbrechen'),
          )
        else ...[
          TextButton(
            key: const ValueKey('area-save-cancel'),
            onPressed: _trimming ? null : () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const ValueKey('area-save'),
            onPressed: _ready && !_trimming ? _save : null,
            child: const Text('Speichern'),
          ),
        ],
      ],
    );
  }
}
