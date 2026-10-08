// „Meine Fahrten" (#28): was auf dem Gerät liegt — ansehen, auf der
// Karte zeigen, löschen. Die Liste ist das Gegenstück zur Zusage „die
// Fahrt bleibt auf dem Gerät": Was bleibt, muss man sehen und loswerden
// können.
//
// Seit 0.85.0 (#228, #227) auch aufräumen: das Rad je Fahrt sehen und
// umstellen (falsch eingeordnet lernt eine Fahrt dem falschen Profil eine
// falsche Steigrate bei), nach links wischen zum Löschen, langer Druck für
// die Mehrfachauswahl. Gelöscht wird immer erst nach Nachfrage — die
// Fahrt liegt nur hier.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/gpx_share.dart';
import '../../core/router_branches.dart';
import '../../core/widgets/motion.dart';
import '../help/help_link.dart';
import '../routing/nav_providers.dart';
import '../routing/ride_calibrator.dart';
import '../routing/route_profile.dart';
import '../trails/gpx_writer.dart';
import 'ride_export.dart';
import 'ride_profile_guess.dart';
import 'ride_providers.dart';
import 'ride_split_sheet.dart';
import 'ride_track.dart';

class RidesScreen extends ConsumerStatefulWidget {
  const RidesScreen({super.key});

  @override
  ConsumerState<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends ConsumerState<RidesScreen> {
  /// Die Mehrfachauswahl: leer heißt „keine Auswahl".
  final _selected = <String>{};

  /// Weggewischte Fahrten, bis die Liste neu gelesen ist — ein
  /// `Dismissible` darf nach dem Wischen nicht mehr im Baum stehen.
  final _gone = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _clearSelection() => setState(_selected.clear);

  void _forgetFocus(Iterable<String> ids) {
    if (ids.contains(ref.read(mapFocusRideProvider)?.id)) {
      ref.read(mapFocusRideProvider.notifier).state = null;
    }
  }

  Future<void> _deleteSelected(List<Ride> rides) async {
    final chosen = [for (final r in rides) if (_selected.contains(r.id)) r];
    if (chosen.isEmpty) return;
    final n = chosen.length;
    final ok = await confirmRideDelete(context,
        title: n == 1 ? 'Fahrt löschen?' : '$n Fahrten löschen?',
        planned: chosen.every((r) => r.planned));
    if (ok != true || !mounted) return;
    final ids = [for (final r in chosen) r.id];
    await ref.read(ridesProvider.notifier).deleteMany(ids);
    if (!mounted) return;
    _forgetFocus(ids);
    _clearSelection();
  }

  Future<void> _setProfileSelected(List<Ride> rides, RiderProfile profile) async {
    final ids = [for (final r in rides) if (_selected.contains(r.id) && !r.planned) r.id];
    await setRidesProfile(context, ref, ids, profile);
    if (mounted) _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final ridesAsync = ref.watch(ridesProvider);
    final rides = [
      for (final r in ridesAsync.valueOrNull ?? const <Ride>[])
        if (!_gone.contains(r.id)) r,
    ];
    // Was nicht mehr da ist, ist auch nicht mehr ausgewählt.
    _selected.removeWhere((id) => !rides.any((r) => r.id == id));
    final measuredSelected = rides.any((r) => _selected.contains(r.id) && !r.planned);
    return PopScope(
      // Zurück beendet zuerst die Auswahl (#175: erst schließt, was oben liegt).
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  key: const ValueKey('rides-selection-close'),
                  tooltip: 'Auswahl beenden',
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                ),
                title: Text('${_selected.length} ausgewählt'),
                actions: [
                  PopupMenuButton<RiderProfile>(
                    key: const ValueKey('rides-selection-profile'),
                    tooltip: 'Rad festlegen',
                    enabled: measuredSelected,
                    icon: const Icon(Icons.directions_bike),
                    onSelected: (p) => _setProfileSelected(rides, p),
                    itemBuilder: (context) => [
                      for (final p in RiderProfile.values)
                        PopupMenuItem(
                          value: p,
                          child: ListTile(leading: Icon(riderProfileIcon(p)), title: Text('Als ${p.label}')),
                        ),
                    ],
                  ),
                  IconButton(
                    key: const ValueKey('rides-selection-delete'),
                    tooltip: 'Ausgewählte löschen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteSelected(rides),
                  ),
                ],
              )
            : AppBar(title: const Text('Meine Fahrten')),
        body: ridesAsync.when(
          loading: () => const CenteredTrailLoader(),
          error: (e, _) => const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Die Fahrten ließen sich nicht lesen.'),
          ),
          data: (_) {
            if (rides.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  _LastNavCard(padding: EdgeInsets.only(bottom: 16)),
                  Text(
                    'Noch keine Fahrt. Starte eine auf der Karte mit dem '
                    'Aufnahme-Knopf — sie bleibt auf deinem Gerät.',
                  ),
                  SizedBox(height: 8),
                  HelpLinkButton(),
                ],
              );
            }
            return ListView(
              children: [
                const _LastNavCard(padding: EdgeInsets.fromLTRB(16, 12, 16, 0)),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Fahrten liegen nur auf diesem Gerät. Beigesteuert wird '
                    'nie eine ganze Fahrt, nur ein Stück, das einen Trail belegt '
                    '— „Zerlegen" zeigt, welche. Nach links wischen löscht, '
                    'langer Druck wählt mehrere.',
                  ),
                ),
                for (final r in rides)
                  _RideTile(
                    r,
                    selecting: _selecting,
                    selected: _selected.contains(r.id),
                    onToggle: () => _toggle(r.id),
                    onDismissed: () async {
                      setState(() => _gone.add(r.id));
                      await ref.read(ridesProvider.notifier).delete(r.id);
                      if (!mounted) return;
                      _forgetFocus([r.id]);
                      setState(() => _gone.remove(r.id));
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// „Zuletzt navigiert" (Konzept-Routing 9.2): Beenden fragt nicht, also
/// geht es hier mit einem Tipp weiter — dort, wo die Navigation endete.
/// Nur solange keine läuft.
class _LastNavCard extends ConsumerWidget {
  const _LastNavCard({required this.padding});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastNavProvider);
    if (last == null || ref.watch(navigationProvider) != null) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Card(
        key: const ValueKey('nav-last'),
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.navigation_outlined),
          title: const Text('Zuletzt navigiert'),
          subtitle: Text(last.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: FilledButton.tonal(
            key: const ValueKey('nav-last-resume'),
            onPressed: () {
              StatefulNavigationShell.of(context).goBranch(kMapBranchIndex);
              ref.read(navRequestProvider.notifier).state = last;
            },
            child: const Text('Weiter'),
          ),
        ),
      ),
    );
  }
}

/// Das Symbol eines Rads — dasselbe wie im GPX-Import.
IconData riderProfileIcon(RiderProfile p) => switch (p) {
      RiderProfile.bio => Icons.pedal_bike_outlined,
      RiderProfile.ebike => Icons.electric_bike_outlined,
    };

/// Die EINE Nachfrage vor dem Löschen — Menü, Wischen und Auswahl.
Future<bool?> confirmRideDelete(BuildContext context, {required String title, required bool planned}) =>
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(planned
            ? 'Die geplante Runde wird vom Gerät gelöscht.'
            : 'Die Aufzeichnung wird vom Gerät gelöscht. '
                'Beigesteuerte Trails bleiben davon unberührt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              key: const ValueKey('ride-delete-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Löschen')),
        ],
      ),
    );

/// Das Rad setzen und anbieten, das Fahrerprofil neu lernen zu lassen —
/// gelernt wird weiter auf Knopfdruck (`ride_calibrator.dart`), nicht von
/// selbst nach jedem Umstellen.
Future<void> setRidesProfile(BuildContext context, WidgetRef ref, List<String> ids, RiderProfile profile) async {
  if (ids.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final learner = ref.read(riderCalibrationsProvider.notifier);
  final n = await ref.read(ridesProvider.notifier).setProfile(ids, profile);
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(n == 0
          ? 'Das Rad ließ sich nicht ändern.'
          : '${n == 1 ? 'Fahrt' : '$n Fahrten'} als ${profile.label} eingeordnet.'),
      action: n == 0
          ? null
          : SnackBarAction(
              label: 'Neu lernen',
              onPressed: () async {
                final text = learnResultText(await learner.learn());
                messenger.showSnackBar(SnackBar(content: Text(text)));
              },
            ),
    ));
}

class _RideTile extends ConsumerWidget {
  const _RideTile(
    this.ride, {
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onDismissed,
  });

  final Ride ride;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final Future<void> Function() onDismissed;

  static final _date = DateFormat('EEEE, d. MMMM yyyy, HH:mm', 'de');
  static final _day = DateFormat('d. MMMM yyyy', 'de');

  String get _deleteTitle => ride.planned ? 'Geplante Fahrt löschen?' : 'Fahrt löschen?';

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmRideDelete(context, title: _deleteTitle, planned: ride.planned);
    if (ok != true || !context.mounted) return;
    await ref.read(ridesProvider.notifier).delete(ride.id);
    if (ref.read(mapFocusRideProvider)?.id == ride.id) {
      ref.read(mapFocusRideProvider.notifier).state = null;
    }
  }

  /// Die ganze Fahrt als GPX, mit roher GPS-Höhe (#150) — die Sicherung
  /// aus Konzept 10.4, über das Teilen-Blatt des Systems.
  Future<void> _export(BuildContext context, WidgetRef ref) {
    final track = rideToGpx(ride);
    return shareGpx(context, ref,
        fileName: rideExportFileName(ride),
        xml: writeGpx(name: track.name, points: track.points));
  }

  /// Erst der Reiter, dann der Wunsch — die Karte fragt und startet.
  void _navigate(BuildContext context, WidgetRef ref) {
    StatefulNavigationShell.of(context).goBranch(kMapBranchIndex);
    ref.read(navRequestProvider.notifier).state = NavRequest(
      points: [for (final p in ride.points) LatLng(p.lat, p.lng)],
      title: ride.planned ? (ride.name ?? 'Geplante Fahrt') : 'Fahrt vom ${_day.format(ride.startedAt.toLocal())}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eine geplante Fahrt (#158 Schritt 5) ist eine Linie, keine Messung:
    // ihr Name statt des Datums, „etwa" vor der Zeit, keine Schere — zerlegt
    // wird, was gefahren wurde, und das ist dann eine eigene Aufzeichnung.
    final planned = ride.planned;
    final profile = RiderProfile.values.where((p) => p.name == ride.profile).firstOrNull;
    final tile = ListTile(
      key: ValueKey('ride-${ride.id}'),
      selected: selected,
      leading: selecting
          ? Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
              key: ValueKey('ride-check-${ride.id}'))
          : Icon(planned ? Icons.route_outlined : Icons.directions_bike),
      title: Text(planned ? (ride.name ?? 'Geplante Fahrt') : _date.format(ride.startedAt.toLocal())),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(planned
              ? 'Geplant am ${_day.format(ride.startedAt.toLocal())} · ${formatMeters(ride.lengthM)} · '
                  'etwa ${rideDurationLabel(ride.duration)}${profile != null ? ' · ${profile.label}' : ''}'
              : '${ride.imported ? 'Aus GPX: ${ride.name ?? 'Datei'} · ' : ''}'
                  '${formatMeters(ride.lengthM)} · '
                  '${rideDurationLabel(ride.duration)} · ${ride.points.length} Punkte'),
          if (!planned) _ProfileChip(ride, profile, enabled: !selecting),
        ],
      ),
      trailing: selecting
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (!planned)
                IconButton(
                  key: ValueKey('ride-split-${ride.id}'),
                  tooltip: 'Fahrt zerlegen',
                  icon: const Icon(Icons.content_cut),
                  onPressed: () {
                    // Erst der Reiter, dann der Wunsch — wie „auf der Karte zeigen".
                    StatefulNavigationShell.of(context).goBranch(kMapBranchIndex);
                    ref.read(mapSplitRequestProvider.notifier).state = SplitRequest.fromRide(ride);
                  },
                ),
              // Exportieren und Löschen in einem Menü (#150): Drei Symbole
              // nebeneinander ließen auf einem kleinen Telefon vom Datum
              // nichts mehr übrig.
              PopupMenuButton<String>(
                key: ValueKey('ride-menu-${ride.id}'),
                tooltip: 'Mehr',
                onSelected: (value) => switch (value) {
                  'navigate' => _navigate(context, ref),
                  'export' => _export(context, ref),
                  _ => _delete(context, ref),
                },
                itemBuilder: (context) => [
                  // Dieselbe Runde noch einmal, oder die geplante (#232).
                  if (ride.points.length >= 2)
                    PopupMenuItem(
                      key: ValueKey('ride-navigate-${ride.id}'),
                      value: 'navigate',
                      child: const ListTile(leading: Icon(Icons.navigation_outlined), title: Text('Navigieren')),
                    ),
                  PopupMenuItem(
                    key: ValueKey('ride-export-${ride.id}'),
                    value: 'export',
                    child: const ListTile(
                        leading: Icon(Icons.share_outlined), title: Text('Als GPX exportieren')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(planned ? 'Geplante Fahrt löschen' : 'Fahrt löschen')),
                  ),
                ],
              ),
            ]),
      onLongPress: onToggle,
      onTap: selecting
          ? onToggle
          : () {
              // Erst der Reiter, dann der Wunsch (PilzBuddy #345).
              StatefulNavigationShell.of(context).goBranch(kMapBranchIndex);
              ref.read(mapFocusRideProvider.notifier).state = ride;
            },
    );
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('ride-dismiss-${ride.id}'),
      // In der Auswahl wischt nichts — dort löscht die Leiste oben.
      direction: selecting ? DismissDirection.none : DismissDirection.endToStart,
      background: ColoredBox(
        color: scheme.errorContainer,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
          ),
        ),
      ),
      confirmDismiss: (_) async =>
          await confirmRideDelete(context, title: _deleteTitle, planned: planned) == true,
      onDismissed: (_) => onDismissed(),
      child: tile,
    );
  }
}

/// Das Rad einer gemessenen Fahrt (#228), antippbar: Bio-Bike oder
/// E-Bike. Ohne Profil (vor 0.70.0) „Rad wählen", dazu der Vorschlag aus
/// der Steigrate, wenn es einen gibt — gesetzt wird er nicht von selbst.
class _ProfileChip extends ConsumerWidget {
  const _ProfileChip(this.ride, this.profile, {required this.enabled});

  final Ride ride;
  final RiderProfile? profile;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final guess = p != null
        ? null
        : guessRideProfile(ride.points,
            bio: ref.watch(calibratedRiderProvider(RiderProfile.bio)),
            ebike: ref.watch(calibratedRiderProvider(RiderProfile.ebike)));
    final label = p?.label ?? (guess == null ? 'Rad wählen' : 'Rad wählen · passt zu ${guess.label}');
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<RiderProfile>(
        key: ValueKey('ride-profile-${ride.id}'),
        tooltip: 'Rad dieser Fahrt',
        enabled: enabled,
        initialValue: p,
        onSelected: (next) {
          if (next != p) setRidesProfile(context, ref, [ride.id], next);
        },
        itemBuilder: (context) => [
          for (final v in RiderProfile.values)
            PopupMenuItem(
              key: ValueKey('ride-profile-${ride.id}-${v.name}'),
              value: v,
              child: ListTile(
                leading: Icon(riderProfileIcon(v)),
                title: Text(v.label),
                trailing: v == p ? const Icon(Icons.check) : null,
              ),
            ),
        ],
        // 44 dp Trefferfläche, auch wenn der Chip selbst kleiner ist.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Chip(
              avatar: Icon(p != null ? riderProfileIcon(p) : Icons.help_outline, size: 18),
              label: Text(label),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ),
    );
  }
}
