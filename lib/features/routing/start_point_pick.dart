// Gemerkte Startpunkte im Planer (#543 Schritt 3,
// `docs/konzept-startpunkte.md` 4 und 5.1).
//
// - [startPointChoices] ist die Liste „Gemerkt" (pur): dieselbe
//   30-m-Regel wie die Karte (`shownStartPoints`), nach Abstand vom
//   Standort — ohne Standort von der Kartenmitte —, der zuletzt gewählte
//   Punkt oben (9.4).
// - [nearbyStartPoint] ist die Vorbelegung vor Ort (9.4): nur wer
//   höchstens [kStartPointNearM] von einem Punkt entfernt steht, startet
//   dort. Am Dienstag zu Hause bleibt es bei „Mein Standort".
// - [pickStartPoint] zeigt die Liste und gibt die Wahl an den Planer;
//   darunter steht „Mein Standort merken" (privat vorbelegt, mit der
//   Warnung vor der Haustür, Konzept 4).
// - [rememberPlannerStart] ist „Start merken" in der Wahl des Starts.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../core/geo.dart' show formatMeters;
import '../../core/settings.dart' show settingsProvider;
import '../../data/providers.dart' show currentUserIdProvider;
import '../../l10n/l10n.dart';
import '../../models/start_point.dart';
import '../friends/buddy_alias.dart' show buddyNamesViewProvider;
import '../map/position_provider.dart';
import '../map/start_point_layer.dart' show StartPointPin, shownStartPoints;
import '../map/start_point_sheet.dart' show rememberStartPoint;
import '../trails/trail_geometry.dart' show haversineM;
import '../trails/trail_providers.dart' show mapVisibleBoundsProvider, startPointsProvider;
import 'loop_planner_controller.dart';

/// Bis zu diesem Abstand vom Standort ist ein gemerkter Punkt beim
/// Öffnen des Planers schon der Start (Konzept Startpunkte 9.4).
const kStartPointNearM = 300.0;

typedef StartPointChoice = ({StartPoint point, double? distanceM});

/// Die Liste „Gemerkt": alle sichtbaren Punkte nach der 30-m-Regel, nach
/// Abstand von [from] (ohne [from] nach Namen), [lastKey] zuoberst.
List<StartPointChoice> startPointChoices(List<StartPoint> points, String? myId,
    {LatLng? from, String? lastKey}) {
  final choices = [
    for (final p in shownStartPoints(points, myId))
      (point: p, distanceM: from == null ? null : haversineM(from.latitude, from.longitude, p.lat, p.lon)),
  ];
  choices.sort((a, b) {
    if (a.point.key == lastKey) return -1;
    if (b.point.key == lastKey) return 1;
    final da = a.distanceM, db = b.distanceM;
    if (da != null && db != null && da != db) return da.compareTo(db);
    return a.point.name.toLowerCase().compareTo(b.point.name.toLowerCase());
  });
  return choices;
}

/// Der nächste sichtbare Punkt höchstens [kStartPointNearM] von [at] —
/// oder keiner.
StartPoint? nearbyStartPoint(List<StartPoint> points, String? myId, LatLng at) {
  StartPoint? best;
  var bestM = kStartPointNearM;
  for (final p in shownStartPoints(points, myId)) {
    final d = haversineM(at.latitude, at.longitude, p.lat, p.lon);
    if (d <= bestM) {
      best = p;
      bestM = d;
    }
  }
  return best;
}

/// Wovon die Liste misst: der laufende Standort, sonst die Mitte des
/// Ausschnitts. Fragt nie nach der Berechtigung.
LatLng? startPointOrigin(WidgetRef ref) {
  final fix = ref.read(positionStreamProvider).valueOrNull;
  if (fix != null) return LatLng(fix.latitude, fix.longitude);
  final b = ref.read(mapVisibleBoundsProvider);
  return b == null ? null : LatLng((b.south + b.north) / 2, (b.west + b.east) / 2);
}

/// Zeigt die Liste und gibt den gewählten Punkt als Start (oder Ziel) an
/// den Planer. Wahr, wenn einer gewählt wurde. „Mein Standort merken"
/// unten in der Liste legt einen Punkt an, wählt ihn aber nicht — wer
/// dort steht, startet ohnehin dort.
Future<bool> pickStartPoint(BuildContext context, WidgetRef ref, {required bool asTarget}) async {
  final myId = ref.read(currentUserIdProvider);
  final choices = startPointChoices(ref.read(startPointsProvider), myId,
      from: startPointOrigin(ref), lastKey: ref.read(settingsProvider).lastStartPoint);
  final picked = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _StartPointList(choices: choices, myId: myId, asTarget: asTarget),
  );
  if (!context.mounted) return false;
  if (picked is StartPoint) {
    ref.read(loopPlannerProvider.notifier).takeStartPoint(picked, asTarget: asTarget);
    return true;
  }
  if (picked == _rememberHere) await rememberMyPosition(context, ref);
  return false;
}

const _rememberHere = #rememberHere;

/// „Mein Standort merken" (Konzept 4): privat vorbelegt, mit der Warnung
/// vor der Haustür. Ohne Standort ein Satz.
Future<void> rememberMyPosition(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final fix = await ref.read(currentPositionProvider)();
  if (!context.mounted) return;
  if (fix == null) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(key: const ValueKey('start-point-no-position'), content: Text(l.startPointNoPosition)));
    return;
  }
  await rememberStartPoint(context, ref, LatLng(fix.latitude, fix.longitude), shared: false, home: true);
}

/// „Start merken" aus der Wahl des Starts (Konzept 4, „Planer-Ergebnis";
/// nur, solange der Start kein gemerkter ist — `LoopSession.startSaved`):
/// ein getippter Start oder ein Ort mit seinem Namen, „Buddys" vorbelegt;
/// der eigene Standort wie „Mein Standort merken".
Future<void> rememberPlannerStart(BuildContext context, WidgetRef ref) async {
  final s = ref.read(loopPlannerProvider);
  final at = s.start;
  if (at == null) return rememberMyPosition(context, ref);
  await rememberStartPoint(context, ref, at, name: s.startName);
}

class _StartPointList extends ConsumerWidget {
  const _StartPointList({required this.choices, required this.myId, required this.asTarget});

  final List<StartPointChoice> choices;
  final String? myId;
  final bool asTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final names = ref.watch(buddyNamesViewProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(asTarget ? l.startPointPickTarget : l.startPointPickStart, style: theme.textTheme.titleMedium),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final c in choices)
                Builder(builder: (context) {
                  final p = c.point;
                  final own = myId != null && p.isMine(myId!);
                  final String? who = !own
                      ? l.startPointFrom(names.of(p.userId, p.username))
                      : p.shared
                          ? null
                          : l.startPointPrivate;
                  return ListTile(
                    key: ValueKey('start-point-choice-${p.key}'),
                    minTileHeight: 52,
                    leading: StartPointPin(own: own, pending: p.pending),
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: who == null
                        ? null
                        : Text(who, style: own ? null : TextStyle(color: palette.buddyText)),
                    trailing: c.distanceM == null
                        ? null
                        : Text(formatMeters(c.distanceM!), style: AppFonts.numbers(theme.textTheme.bodyMedium)),
                    onTap: () => Navigator.of(context).pop(p),
                  );
                }),
              if (!asTarget) ...[
                const Divider(height: 1),
                ListTile(
                  key: const ValueKey('start-point-remember-here'),
                  minTileHeight: 52,
                  leading: const Icon(Icons.my_location),
                  title: Text(l.startPointRememberHere),
                  onTap: () => Navigator.of(context).pop(_rememberHere),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
