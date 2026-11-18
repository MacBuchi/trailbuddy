// Buddys auf der Karte (#519, E4; docs/konzept-geraete.md 6.3) — rein:
// aus [BuddyMapEntry] werden Polygone und Marker der Fassade.
//
// **Eine Form, keine Farbe** (A13): Farbe heißt auf der Karte
// Schwierigkeit. Ein Buddy ist eine Scheibe mit seinem Anfangsbuchstaben —
// genau und live gefüllt, grob (Homie) als Ring auf dem Mittelpunkt seiner
// Zelle, dazu das blasse Quadrat der Zelle selbst: Ein Punkt allein täte
// so, als wüsste die App, wo er ist. Alt ist blass und sagt „vor 4 min"
// (A8). Die Karte ist immer hell ([AppColors.mapLines]).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../models/friendship.dart';
import '../friends/buddy_alias.dart';
import '../friends/friend_providers.dart';
import '../map/map_view/map_view.dart';
import 'nearby_core.dart';

/// Der Name eines direkten Buddys, wie ihn die Buddy-Liste zeigt (Alias
/// vor Benutzername); unbekannt „?".
final nearbyBuddyNameProvider = Provider<String Function(String buddyId)>((
  ref,
) {
  final uid = ref.watch(currentUserIdProvider);
  final friendships =
      ref.watch(friendshipsProvider).valueOrNull ?? const <FriendshipEntry>[];
  final names = ref.watch(buddyNamesViewProvider);
  return (id) {
    final f = friendships
        .where((f) => uid != null && f.isAccepted && f.otherId(uid) == id)
        .firstOrNull;
    return f == null || uid == null ? '?' : names.of(id, f.otherUsername(uid));
  };
});

/// Was ein Tipp auf einen Buddy meldet.
class BuddyMapHit {
  const BuddyMapHit(this.entry, this.name);

  final BuddyMapEntry entry;
  final String name;
}

/// Der Anfangsbuchstabe eines Namens, groß; ohne Buchstaben „?".
String buddyInitial(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  return String.fromCharCode(t.runes.first).toUpperCase();
}

/// Die Quadrate der Zellen (Homies), unter allem anderen.
List<MapViewPolygon> buddyCellPolygons(List<BuddyMapEntry> entries) {
  const map = AppColors.mapLines;
  return [
    for (final e in entries)
      if (e.kind == BuddyMapKind.cell && e.cell != null)
        MapViewPolygon(
          points: [
            LatLng(e.cell!.south, e.cell!.west),
            LatLng(e.cell!.south, e.cell!.east),
            LatLng(e.cell!.north, e.cell!.east),
            LatLng(e.cell!.north, e.cell!.west),
          ],
          fillColor: map.buddy.withValues(
            alpha: e.seenAgo == null ? 0.08 : 0.04,
          ),
          borderColor: map.buddy.withValues(
            alpha: e.seenAgo == null ? 0.45 : 0.25,
          ),
          borderWidth: 1.5,
        ),
  ];
}

/// Die Scheiben, über allem außer der eigenen Position.
List<MapViewMarker> buddyMarkers(
  List<BuddyMapEntry> entries,
  String Function(String buddyId) nameOf,
) => [
  for (final e in entries)
    MapViewMarker(
      key: ValueKey('buddy-${e.kind.name}-${e.buddyId}'),
      point: LatLng(e.point.lat, e.point.lon),
      width: BuddyDisc.extent,
      height: BuddyDisc.extent,
      hitValue: BuddyMapHit(e, nameOf(e.buddyId)),
      child: BuddyDisc(
        initial: buddyInitial(nameOf(e.buddyId)),
        live: e.kind == BuddyMapKind.live,
        seenAgo: e.seenAgo,
      ),
    ),
];

/// „vor 4 min" — kurz, für unter die Scheibe.
String buddySeenAgoShort(AppLocalizations l, Duration ago) =>
    l.buddyMapAgo(ago.inMinutes < 1 ? 1 : ago.inMinutes);

class BuddyDisc extends StatelessWidget {
  const BuddyDisc({
    super.key,
    required this.initial,
    required this.live,
    this.seenAgo,
  });

  final String initial;
  final bool live;
  final Duration? seenAgo;

  static const size = 30.0;

  /// Die Fläche des Markers: Scheibe plus Zeile „vor 4 min" darunter.
  static const extent = 64.0;

  @override
  Widget build(BuildContext context) {
    const map = AppColors.mapLines;
    final l = context.l10n;
    final stale = seenAgo != null;
    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: live ? map.buddy : Colors.white,
        border: live
            ? Border.all(color: Colors.white, width: 2.5)
            : Border.all(color: map.buddy, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          height: 1,
          color: live ? Colors.white : map.buddy,
        ),
      ),
    );
    return Semantics(
      label: live
          ? l.buddyMapLiveSemantics(initial)
          : l.buddyMapCellSemantics(initial),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Die Scheibe sitzt auf dem Punkt; die Zeile darunter gleicht
          // die Höhe oben aus.
          const SizedBox(height: 14),
          Opacity(opacity: stale ? 0.55 : 1, child: disc),
          SizedBox(
            height: 14,
            child: stale
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    color: Colors.white.withValues(alpha: 0.85),
                    child: Text(
                      buddySeenAgoShort(l, seenAgo!),
                      key: const ValueKey('buddy-seen-ago'),
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        color: Color(0xFF333333),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// Der Satz nach einem Tipp auf einen Buddy.
String buddyMapHitText(AppLocalizations l, BuddyMapHit hit) {
  final e = hit.entry;
  final ago = e.seenAgo;
  return switch ((e.kind, ago)) {
    (BuddyMapKind.live, null) => l.buddyMapLiveNow(hit.name),
    (BuddyMapKind.live, final a?) => l.buddyMapLiveAgo(
      hit.name,
      a.inMinutes < 1 ? 1 : a.inMinutes,
    ),
    (BuddyMapKind.cell, null) => l.buddyMapCellNow(hit.name),
    (BuddyMapKind.cell, final a?) => l.buddyMapCellAgo(
      hit.name,
      a.inMinutes < 1 ? 1 : a.inMinutes,
    ),
  };
}
